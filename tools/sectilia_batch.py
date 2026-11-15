#!/usr/bin/env python3
"""Run a manifest of Sectilia jobs serially in the foreground.

usage: sectilia_batch.py manifest.json [--limit N] [--dry-run]

Skips entries whose `out` exists, resolves style/source keys through
assets/map/jobs.json, records each finished job id under its key, and handles
exit codes per the Sectilia skill ("When a command fails").
"""
import argparse
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as C  # noqa: E402

# Passed to sectilia as --timeout so it exits 7 with the job id (resumable via
# _pending) before an agent shell or our own subprocess timeout kills it.
CLI_TIMEOUT = 540
MAX_QUEUE_RETRIES = 5     # exit 7 with submitted:false -> rerun same command
MAX_WAIT_ROUNDS = 6       # exit 7 with submitted:true -> sectilia wait again
QUEUE_SLEEP = 60


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
    elif cmd == "background":
        argv += ["--description", a["description"], "--size", a["size"],
                 "--style", a.get("style", "painted")]
        for k in a.get("style_keys", []):
            argv += ["--style-job", ref(k)]
    else:
        raise EntryFailed("unknown cmd '%s'" % cmd)
    argv += ["--timeout", str(CLI_TIMEOUT), "--out", out]
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


def run(argv, timeout):
    """Run one sectilia command, return (exit_code, parsed stdout JSON or {})."""
    p = subprocess.run(argv, capture_output=True, text=True, cwd=C.ROOT, timeout=timeout)
    data = parse_stdout(p.stdout)
    if p.stderr:
        sys.stderr.write(p.stderr[-2000:])
    return p.returncode, data


def err_of(data):
    err = data.get("error") if isinstance(data, dict) else None
    return err if isinstance(err, dict) else {}


def describe(code, data):
    err = err_of(data)
    return "exit %s %s: %s %s" % (code, err.get("kind", ""), err.get("message", ""),
                                  json.dumps(err.get("detail", "")))


def newest_job_since(t0, kind, runner=None):
    """Id of the newest job of `kind` created at or after epoch t0, else None."""
    try:
        code, data = (runner or run)(["sectilia", "jobs", "--limit", "1"], 60)
        j = (data.get("jobs") or [])[0]
    except (subprocess.TimeoutExpired, IndexError, AttributeError):
        return None
    if code != 0 or (j.get("request") or {}).get("kind") != kind:
        return None
    from datetime import datetime
    try:
        created = datetime.fromisoformat(j["created_at"].replace("Z", "+00:00")).timestamp()
    except (KeyError, ValueError):
        return None
    return j.get("id") if created >= t0 - 5 else None


def run_entry(e, jobs, runner=run, sleep=time.sleep, job_id=None, on_pending=None):
    """Run one entry to completion. Returns the job id. Raises EntryFailed
    (skip this entry) or StopBatch (stop everything)."""
    argv = build_argv(e, jobs)
    timeout = CLI_TIMEOUT + 120
    out = e["out"]
    os.makedirs(os.path.dirname(os.path.join(C.ROOT, out)), exist_ok=True)
    queue_tries = 0
    wait_rounds = 0
    started = time.time()
    note = on_pending or (lambda jid: None)
    while True:
        cmdline = argv if job_id is None else ["sectilia", "wait", job_id, "--timeout",
                                               str(CLI_TIMEOUT), "--out", out]
        try:
            code, data = runner(cmdline, timeout)
        except subprocess.TimeoutExpired:
            if job_id is None:
                # sectilia ignores --timeout while a job is queued for a cold
                # server; recover the id of the job we just submitted.
                job_id = newest_job_since(started, e["cmd"], runner)
                if job_id:
                    note(job_id)
            raise StopBatch("local timeout after %ss running %s; %s" % (
                timeout, cmdline[1], "resume later with `sectilia wait %s --out %s` "
                "(rerun this batch, it resumes pending jobs)" % (job_id, out)
                if job_id else "no job id known, check `sectilia jobs`"))
        err = err_of(data)
        detail = err.get("detail") if isinstance(err.get("detail"), dict) else {}
        if code == 0:
            return data.get("id") or data.get("job_id") or job_id
        if code in (3, 6):
            why = ("not logged in: ask the user to run `sectilia login`" if code == 3
                   else "service unavailable (not retrying in a loop)")
            raise StopBatch("%s -- %s" % (why, describe(code, data)))
        if code == 7:
            if detail.get("submitted") is False and job_id is None:
                queue_tries += 1
                if queue_tries > MAX_QUEUE_RETRIES:
                    raise StopBatch("queue stayed full: " + describe(code, data))
                sleep(QUEUE_SLEEP)
                continue
            job_id = err.get("job_id") or job_id
            if job_id:
                note(job_id)
            wait_rounds += 1
            if not job_id or wait_rounds > MAX_WAIT_ROUNDS:
                raise EntryFailed("still running after waits: " + describe(code, data),
                                  keep_pending=bool(job_id))
            continue
        if code == 130:
            if detail.get("submitted") is False:
                raise StopBatch("interrupted before submit")
            job_id = err.get("job_id") or job_id
            if job_id:
                note(job_id)
            raise StopBatch("interrupted; job %s keeps running (sectilia wait %s --out %s)"
                            % (job_id, job_id, out))
        if code == 4:
            if detail.get("reason") == "insufficient_credits":
                raise StopBatch("insufficient credits: " + describe(code, data))
            raise EntryFailed("rejected: " + describe(code, data), 4)
        if code == 5:
            raise EntryFailed("job failed: " + describe(code, data), 5)
        if code == 1:
            if err.get("job_id"):
                c2, d2 = runner(["sectilia", "download", err["job_id"], "--out", out], timeout)
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
    with open(path or C.FAILED_PATH, "w", encoding="utf-8") as f:
        json.dump(failed, f, indent=1, sort_keys=True)
        f.write("\n")


def run_manifest(entries, limit=None, jobs_path=None, runner=run, sleep=time.sleep,
                 log=lambda m: sys.stderr.write(m + "\n"), failed_path=None,
                 retry_failed=False):
    """Returns (counts dict, stop_reason or None).

    In-flight job ids live in jobs.json under "_pending" and are resumed with
    `sectilia wait` on the next run. Exit-5 failures go to jobs_failed.json and
    are not resubmitted unless retry_failed."""
    jobs = load_jobs(jobs_path)
    pending_map = jobs.setdefault("_pending", {})
    failed_log = load_failed(failed_path)
    done = skipped = failed = 0
    stop = None
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
    failed += blocked
    for e in todo:
        key = e["key"]

        def note(jid, key=key):
            pending_map[key] = jid
            save_jobs(jobs, jobs_path)
        try:
            jid = run_entry(e, jobs, runner, sleep, pending_map.get(key), note)
            pending_map.pop(key, None)
            apply_fit(e)
            apply_post(e)
            if jid:
                jobs[key] = jid
            save_jobs(jobs, jobs_path)
            if failed_log.pop(key, None) is not None:
                save_failed(failed_log, failed_path)
            done += 1
            log("ok   %s -> %s" % (key, jid))
        except EntryFailed as ex:
            failed += 1
            if not ex.keep_pending:
                pending_map.pop(key, None)
            save_jobs(jobs, jobs_path)
            if ex.code == 5:
                failed_log[key] = str(ex)
                save_failed(failed_log, failed_path)
            log("FAIL %s: %s" % (key, ex))
        except StopBatch as ex:
            failed += 1
            stop = "%s: %s" % (key, ex)
            log("STOP %s" % stop)
            break
    remaining = len(pending) - done - failed
    return {"done": done, "skipped": skipped, "failed": failed, "remaining": remaining}, stop


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("manifest")
    ap.add_argument("--limit", type=int, help="run at most N pending entries")
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
    counts, stop = run_manifest(entries, a.limit, retry_failed=a.retry_failed)
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
