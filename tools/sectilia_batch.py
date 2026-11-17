#!/usr/bin/env python3
"""Run a manifest of Sectilia jobs, up to three at once, from one process.

usage: sectilia_batch.py manifest.json [--limit N] [--workers 3] [--retry-failed] [--dry-run]

Skips entries whose `out` exists, resolves style/source keys through
assets/map/jobs.json, records each finished job id under its key, and handles
exit codes per the Sectilia skill ("When a command fails").

Scheduling (sectilia >= 0.5.5 runs up to three jobs per machine, and the
service queue holds three per user): at most `--workers` commands run at once,
each in its own thread of this one process. Entries start in manifest order,
but an edit never starts while a generate (or upload/background) of the same
run is unfinished, so each server type is cold-started about once per phase;
an entry whose source or style key is made in the same run waits for it.

Each job id is read from that command's own stderr ("job <id> queued") as soon
as it is submitted, so a timed-out or interrupted command is always resumed
with `sectilia wait` on its own job. All writes to jobs.json and
jobs_failed.json happen under one lock in this process. Never run two runners.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as C  # noqa: E402

# Passed to sectilia as --timeout so a command exits 7 with the job id (resumable
# via _pending) rather than hanging.
CLI_TIMEOUT = 540
# sectilia extends --timeout by up to this while a job waits for a hammer server
# to start (jig_cli.waiting.MAX_SERVER_WAIT), so a queued command can run for
# CLI_TIMEOUT + 7200 s. Our own subprocess timeout has to cover that.
SERVER_WAIT = 7200
LOCAL_TIMEOUT = CLI_TIMEOUT + SERVER_WAIT + 300
MAX_PARALLEL = 3          # sectilia's per-machine job slots = default per-user queue
MAX_QUEUE_RETRIES = 10    # exit 7 with submitted:false -> wait, rerun same command
MAX_WAIT_ROUNDS = 6       # exit 7 with submitted:true -> sectilia wait again
QUEUE_SLEEP = 60
MAX_UNAVAILABLE_WAITS = 2   # exit 6 on a job we already submitted -> wait on it again
JOB_LINE = re.compile(r"^job ([0-9a-fA-F][0-9a-fA-F-]{7,}) ")
# sectilia 0.5.5 first waits out a job an earlier command left in its slot:
# "waiting for earlier job X to finish", then polls it ("job X running (0m00s)").
EARLIER_LINE = re.compile(r"waiting for earlier job ([0-9a-fA-F][0-9a-fA-F-]{7,})")


class StopBatch(Exception):
    pass


class EntryFailed(Exception):
    def __init__(self, msg, code=None, keep_pending=False):
        super().__init__(msg)
        self.code = code
        self.keep_pending = keep_pending


def load_jobs(path=None):
    path = path or C.JOBS_PATH
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save_jobs(jobs, path=None):
    path = path or C.JOBS_PATH
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(jobs, f, indent=1, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def resolve(key, jobs):
    if key not in jobs:
        raise EntryFailed("no job id recorded for key '%s'" % key)
    return jobs[key]


def build_argv(e, jobs, dry=False):
    """The sectilia argv for one entry. dry=True shows <job:key> placeholders."""
    a = e["args"]

    def ref(k):
        return "<job:%s>" % k if dry else resolve(k, jobs)

    out = e["out"]
    cmd = e["cmd"]
    argv = ["sectilia", cmd]
    if cmd == "generate":
        argv += ["--subject", a["subject"], "--spec", json.dumps(a["spec"])]
        if a.get("facing"):
            argv += ["--facing", a["facing"]]
        if a.get("theme"):
            argv += ["--theme", a["theme"]]
        for k in a.get("style_keys", []):
            argv += ["--style", ref(k)]
    elif cmd == "edit":
        argv += [ref(e["source_key"]), "--instruction", a["instruction"],
                 "--spec", json.dumps(a["spec"])]
        if a.get("facing"):
            argv += ["--facing", a["facing"]]
        for k in a.get("style_keys", []):
            argv += ["--style", ref(k)]
    elif cmd == "upload":
        argv += [a["file"], "--spec", json.dumps(a["spec"])]
    elif cmd == "background":
        argv += ["--description", a["description"], "--size", a["size"],
                 "--style", a.get("style", "painted")]
        for k in a.get("style_keys", []):
            argv += ["--style-job", ref(k)]
    else:
        raise EntryFailed("unknown cmd '%s'" % cmd)
    if cmd != "upload":   # upload is synchronous and takes no --timeout
        argv += ["--timeout", str(CLI_TIMEOUT)]
    argv += ["--out", out]
    return argv


def parse_stdout(text):
    """sectilia prints one JSON object, pretty-printed over many lines."""
    text = text.strip()
    if not text:
        return {}
    try:
        return json.loads(text)
    except ValueError:
        pass
    i = text.rfind("\n{")
    try:
        return json.loads(text[i + 1:] if i >= 0 else text.splitlines()[-1])
    except (ValueError, IndexError):
        return {}


def job_id_in(line):
    """The job id in a sectilia progress line ("job <id> queued (0m00s)"), else
    None. Lines about other jobs ("waiting for earlier job X") do not match."""
    m = JOB_LINE.match(line.strip())
    return m.group(1) if m else None


class OwnJob:
    """Finds this command's own job id in its stderr. Ids named by a "waiting
    for earlier job X" note, and every later "job X ..." line about them,
    belong to other commands and are skipped."""

    def __init__(self):
        self.earlier = set()
        self.own = None

    def feed(self, line):
        """Returns the own id the first time it is seen, else None."""
        m = EARLIER_LINE.search(line)
        if m:
            self.earlier.add(m.group(1))
            return None
        jid = job_id_in(line)
        if self.own is None and jid and jid not in self.earlier:
            self.own = jid
            return jid
        return None


def run(argv, timeout, on_job=None):
    """Run one sectilia command, return (exit_code, parsed stdout JSON or {}).

    stderr is read as it arrives; this command's own job id (see OwnJob) is
    passed to on_job as soon as it appears."""
    p = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         cwd=C.ROOT)
    err_lines = []

    own = OwnJob()

    def pump():
        for line in p.stderr:
            err_lines.append(line)
            jid = own.feed(line)
            if jid and on_job:
                on_job(jid)
    out_parts = []
    # Each pipe has exactly one reader (communicate() would race the stderr pump).
    readers = [threading.Thread(target=pump, daemon=True),
               threading.Thread(target=lambda: out_parts.append(p.stdout.read()), daemon=True)]
    for t in readers:
        t.start()
    try:
        p.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()
        raise
    finally:
        for t in readers:
            t.join(5)
        p.stdout.close()
        p.stderr.close()
    if p.returncode != 0 and err_lines:
        sys.stderr.write("".join(err_lines)[-1500:])
    return p.returncode, parse_stdout("".join(out_parts))


def err_of(data):
    err = data.get("error") if isinstance(data, dict) else None
    return err if isinstance(err, dict) else {}


def describe(code, data):
    err = err_of(data)
    return "exit %s %s: %s %s" % (code, err.get("kind", ""), err.get("message", ""),
                                  json.dumps(err.get("detail", "")))


def run_entry(e, jobs, runner=run, sleep=time.sleep, job_id=None, on_pending=None):
    """Run one entry to completion. Returns the job id. Raises EntryFailed
    (skip this entry) or StopBatch (start nothing new).

    `runner(argv, timeout, on_job)` calls on_job with the job id it sees on
    stderr. That id is ours: it is recorded as pending at once, and every later
    wait uses it. The id in an exit-7 `submitted:false` error belongs to another
    job and is never recorded."""
    argv = build_argv(e, jobs)
    out = e["out"]
    os.makedirs(os.path.dirname(os.path.join(C.ROOT, out)), exist_ok=True)
    queue_tries = 0
    wait_rounds = 0
    unavailable_waits = 0
    note = on_pending or (lambda jid: None)
    mine = [job_id]

    def seen(jid):
        if jid and jid != mine[0]:
            mine[0] = jid
            note(jid)
    while True:
        cmdline = argv if mine[0] is None else ["sectilia", "wait", mine[0], "--timeout",
                                                str(CLI_TIMEOUT), "--out", out]
        try:
            code, data = runner(cmdline, LOCAL_TIMEOUT, seen)
        except subprocess.TimeoutExpired:
            if mine[0] is None:
                raise StopBatch("local timeout after %ss before any job id was seen; "
                                "check `sectilia jobs`" % LOCAL_TIMEOUT)
            wait_rounds += 1
            if wait_rounds > MAX_WAIT_ROUNDS:
                raise EntryFailed("still running after local timeouts; resume with "
                                  "`sectilia wait %s --out %s`" % (mine[0], out),
                                  keep_pending=True)
            continue
        err = err_of(data)
        detail = err.get("detail") if isinstance(err.get("detail"), dict) else {}
        if code == 0:
            return data.get("id") or data.get("job_id") or mine[0]
        if code == 6 and mine[0] and unavailable_waits < MAX_UNAVAILABLE_WAITS:
            # Our job exists (often finished: "could not download the image");
            # a short pause and one `sectilia wait` usually collects it.
            unavailable_waits += 1
            sleep(QUEUE_SLEEP)
            continue
        if code in (3, 6):
            why = ("not logged in: ask the user to run `sectilia login`" if code == 3
                   else "service unavailable (not retrying in a loop)")
            raise StopBatch("%s -- %s" % (why, describe(code, data)))
        if code == 7:
            if detail.get("submitted") is False and mine[0] == err.get("job_id"):
                # A wrongly adopted id is the job we were waiting behind: drop it.
                mine[0] = None
                note(None)
            if detail.get("submitted") is False and mine[0] is None:
                # Our other jobs still fill the slots or the queue; sectilia has
                # already waited --timeout for room. Wait, rerun the same command.
                queue_tries += 1
                if queue_tries > MAX_QUEUE_RETRIES:
                    raise StopBatch("queue stayed full: " + describe(code, data))
                sleep(QUEUE_SLEEP)
                continue
            if detail.get("submitted") is not False:
                seen(err.get("job_id"))
            wait_rounds += 1
            if not mine[0] or wait_rounds > MAX_WAIT_ROUNDS:
                raise EntryFailed("still running after waits: " + describe(code, data),
                                  keep_pending=bool(mine[0]))
            continue
        if code == 130:
            if detail.get("submitted") is False and mine[0] in (None, err.get("job_id")):
                raise StopBatch("interrupted before submit")
            if detail.get("submitted") is not False:
                seen(err.get("job_id"))
            raise StopBatch("interrupted; job %s keeps running (sectilia wait %s --out %s)"
                            % (mine[0], mine[0], out))
        if code == 4:
            if detail.get("reason") == "insufficient_credits":
                raise StopBatch("insufficient credits: " + describe(code, data))
            raise EntryFailed("rejected: " + describe(code, data), 4)
        if code == 5:
            raise EntryFailed("job failed: " + describe(code, data), 5)
        if code == 1:
            if err.get("job_id"):
                c2, d2 = runner(["sectilia", "download", err["job_id"], "--out", out],
                                LOCAL_TIMEOUT, None)
                if c2 == 0:
                    return err["job_id"]
            raise EntryFailed("local error: " + describe(code, data))
        if code == 2:
            raise StopBatch("usage error (fix the manifest/flags): " + describe(code, data))
        raise EntryFailed("unexpected: " + describe(code, data))


def final_out(e):
    """The file an entry finally produces (the fitted copy for `fit` entries)."""
    return (e.get("fit") or {}).get("out") or e["out"]


def apply_fit(e):
    """Cover-fit (scale to cover, centre crop) the raw output to fit.size."""
    fit = e.get("fit")
    if not fit:
        return
    from PIL import Image
    src = Image.open(os.path.join(C.ROOT, e["out"])).convert("RGBA")
    bbox = src.getchannel("A").getbbox()
    if bbox:
        src = src.crop(bbox)
    w, h = fit["size"]
    s = max(w / src.width, h / src.height)
    im = src.resize((max(w, round(src.width * s)), max(h, round(src.height * s))), Image.LANCZOS)
    x, y = (im.width - w) // 2, (im.height - h) // 2
    dst = os.path.join(C.ROOT, fit["out"])
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    im.crop((x, y, x + w, y + h)).convert("RGB").save(dst)


def apply_post(e):
    """Post-process a finished asset in place: `clean` (clean_sprite: shadow,
    ground, pools, crop) then `align_to` (align_states against a source
    sprite, so edited states keep its framing)."""
    post = e.get("post")
    if not post:
        return
    from PIL import Image
    import clean_sprite
    import align_states
    path = os.path.join(C.ROOT, final_out(e))
    im = Image.open(path).convert("RGBA")
    c = post.get("clean")
    if c is not None:
        im, _ = clean_sprite.clean(im, shadow=c.get("shadow", True), pools=c.get("pools", False),
                                   ground=c.get("ground"))
        if c.get("crop"):
            box = im.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
            if box:
                im = im.crop(box)
    if post.get("align_to"):
        src = os.path.join(C.ROOT, post["align_to"])
        if os.path.exists(src):
            im = align_states.align(Image.open(src), im)
    im.save(path)


def load_failed(path=None):
    try:
        with open(path or C.FAILED_PATH, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save_failed(failed, path=None):
    path = path or C.FAILED_PATH
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(failed, f, indent=1, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def deps_of(e):
    """Keys this entry needs recorded before it can start (source + style refs)."""
    ks = [e["source_key"]] if e.get("source_key") else []
    return ks + list((e.get("args") or {}).get("style_keys") or [])


def phase_of(e):
    """Edits run after every non-edit of the same run (one cold start per phase)."""
    return 1 if e["cmd"] == "edit" else 0


def pick_ready(todo, state):
    """What to do next: ("start", i), ("fail", i) for an entry whose in-run
    dependency failed, or None when nothing may start yet.

    state[key] is None (not started), "run", "ok" or "fail"."""
    keys = set(state)
    live = [phase_of(e) for e in todo if state[e["key"]] in (None, "run")]
    open_phase = min(live) if live else 0
    for i, e in enumerate(todo):
        if state[e["key"]] is not None:
            continue
        need = [k for k in deps_of(e) if k in keys]
        if any(state[k] == "fail" for k in need):
            return "fail", i
        if phase_of(e) > open_phase:
            continue
        if all(state[k] == "ok" for k in need):
            return "start", i
    return None


def run_manifest(entries, limit=None, jobs_path=None, runner=run, sleep=time.sleep,
                 log=lambda m: sys.stderr.write(m + "\n"), failed_path=None,
                 retry_failed=False, workers=MAX_PARALLEL):
    """Returns (counts dict, stop_reason or None).

    Up to `workers` entries run at once (threads of this process). In-flight
    job ids live in jobs.json under "_pending" and are resumed with `sectilia
    wait` on the next run. Exit-5 failures go to jobs_failed.json and are not
    resubmitted unless retry_failed. A StopBatch starts nothing new; entries
    already running finish first."""
    workers = max(1, min(workers, MAX_PARALLEL))
    jobs = load_jobs(jobs_path)
    pending_map = jobs.setdefault("_pending", {})
    failed_log = load_failed(failed_path)
    skipped = 0
    pending = []
    for e in entries:
        if os.path.exists(os.path.join(C.ROOT, final_out(e))):
            skipped += 1
        elif e.get("fit") and os.path.exists(os.path.join(C.ROOT, e["out"])):
            apply_fit(e)
            skipped += 1
        else:
            pending.append(e)
    todo, blocked = [], 0
    for e in pending:
        if e["key"] in failed_log and not retry_failed:
            blocked += 1
            log("skip %s: failed before (%s); use --retry-failed" % (e["key"], failed_log[e["key"]][:120]))
        else:
            todo.append(e)
    if limit is not None:
        todo = todo[:limit]

    cv = threading.Condition()     # guards jobs, pending_map, failed_log, state, files
    state = {e["key"]: None for e in todo}
    tally = {"done": 0, "failed": blocked}
    stops = []

    def work(e):
        key = e["key"]

        def note(jid):
            with cv:
                if jid:
                    pending_map[key] = jid
                else:
                    pending_map.pop(key, None)
                save_jobs(jobs, jobs_path)
        result = "fail"
        try:
            with cv:
                snap = dict(jobs)
                start_id = pending_map.get(key)
            jid = run_entry(e, snap, runner, sleep, start_id, note)
            with cv:   # record before post-processing, so a post error never strands the job
                pending_map.pop(key, None)
                if jid:
                    jobs[key] = jid
                save_jobs(jobs, jobs_path)
                if failed_log.pop(key, None) is not None:
                    save_failed(failed_log, failed_path)
            apply_fit(e)
            apply_post(e)
            result = "ok"
            log("ok   %s -> %s" % (key, jid))
        except EntryFailed as ex:
            with cv:
                if not ex.keep_pending:
                    pending_map.pop(key, None)
                save_jobs(jobs, jobs_path)
                if ex.code == 5:
                    failed_log[key] = str(ex)
                    save_failed(failed_log, failed_path)
            log("FAIL %s: %s" % (key, ex))
        except StopBatch as ex:
            with cv:
                stops.append("%s: %s" % (key, ex))
            log("STOP %s: %s" % (key, ex))
        except Exception as ex:   # e.g. a post-processing error: never hang the scheduler
            log("FAIL %s: %s: %s" % (key, type(ex).__name__, ex))
        finally:
            with cv:
                state[key] = result
                tally["done" if result == "ok" else "failed"] += 1
                cv.notify_all()

    threads = []
    with cv:
        while True:
            running = sum(1 for v in state.values() if v == "run")
            nxt = None if stops or running >= workers else pick_ready(todo, state)
            if nxt is None:
                if running == 0:
                    break
                cv.wait()
                continue
            what, i = nxt
            key = todo[i]["key"]
            if what == "fail":
                state[key] = "fail"
                tally["failed"] += 1
                log("FAIL %s: a job it depends on failed" % key)
                continue
            state[key] = "run"
            t = threading.Thread(target=work, args=(todo[i],), daemon=True)
            threads.append(t)
            t.start()
    for t in threads:
        t.join()
    counts = {"done": tally["done"], "skipped": skipped, "failed": tally["failed"]}
    counts["remaining"] = len(pending) - counts["done"] - counts["failed"]
    return counts, ("; ".join(stops) if stops else None)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("manifest")
    ap.add_argument("--limit", type=int, help="run at most N pending entries")
    ap.add_argument("--workers", type=int, default=MAX_PARALLEL,
                    help="sectilia commands in flight at once (1-%d)" % MAX_PARALLEL)
    ap.add_argument("--retry-failed", action="store_true",
                    help="resubmit entries recorded in jobs_failed.json")
    ap.add_argument("--dry-run", action="store_true", help="print commands, run nothing")
    a = ap.parse_args(argv)
    with open(a.manifest, encoding="utf-8") as f:
        entries = json.load(f)
    if a.dry_run:
        n = 0
        for e in entries:
            if os.path.exists(os.path.join(C.ROOT, final_out(e))):
                continue
            if a.limit is not None and n >= a.limit:
                break
            n += 1
            print("[%s] " % e["key"] + " ".join(shell_quote(x) for x in build_argv(e, {}, dry=True)))
        return 0
    counts, stop = run_manifest(entries, a.limit, retry_failed=a.retry_failed,
                                workers=a.workers)
    print("done=%(done)d skipped=%(skipped)d failed=%(failed)d remaining=%(remaining)d" % counts)
    if stop:
        print("stopped: " + stop)
        return 1
    return 0


def shell_quote(s):
    import shlex
    return shlex.quote(s)


if __name__ == "__main__":
    sys.exit(main())
