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

TIMEOUT = {"background": 3600}
DEFAULT_TIMEOUT = 600
MAX_QUEUE_RETRIES = 5     # exit 7 with submitted:false -> rerun same command
MAX_WAIT_ROUNDS = 6       # exit 7 with submitted:true -> sectilia wait again
QUEUE_SLEEP = 60


class StopBatch(Exception):
    pass


class EntryFailed(Exception):
    pass


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
    argv += ["--out", out]
    return argv


def run(argv, timeout):
    """Run one sectilia command, return (exit_code, parsed stdout JSON or {})."""
    p = subprocess.run(argv, capture_output=True, text=True, cwd=C.ROOT, timeout=timeout)
    try:
        data = json.loads(p.stdout.strip().splitlines()[-1]) if p.stdout.strip() else {}
    except (ValueError, IndexError):
        data = {}
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


def run_entry(e, jobs, runner=run, sleep=time.sleep):
    """Run one entry to completion. Returns the job id. Raises EntryFailed
    (skip this entry) or StopBatch (stop everything)."""
    argv = build_argv(e, jobs)
    timeout = TIMEOUT.get(e["cmd"], DEFAULT_TIMEOUT) + 100
    out = e["out"]
    os.makedirs(os.path.dirname(os.path.join(C.ROOT, out)), exist_ok=True)
    queue_tries = 0
    wait_rounds = 0
    job_id = None
    while True:
        if job_id is None:
            code, data = runner(argv, timeout)
        else:
            code, data = runner(["sectilia", "wait", job_id, "--out", out], timeout)
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
            wait_rounds += 1
            if not job_id or wait_rounds > MAX_WAIT_ROUNDS:
                raise EntryFailed("still running after waits: " + describe(code, data))
            continue
        if code == 130:
            if detail.get("submitted") is False:
                raise StopBatch("interrupted before submit")
            job_id = err.get("job_id") or job_id
            raise StopBatch("interrupted; job %s keeps running (sectilia wait %s --out %s)"
                            % (job_id, job_id, out))
        if code == 4:
            if detail.get("reason") == "insufficient_credits":
                raise StopBatch("insufficient credits: " + describe(code, data))
            raise EntryFailed("rejected: " + describe(code, data))
        if code == 5:
            raise EntryFailed("job failed: " + describe(code, data))
        if code == 1:
            if err.get("job_id"):
                c2, d2 = runner(["sectilia", "download", err["job_id"], "--out", out], timeout)
                if c2 == 0:
                    return err["job_id"]
            raise EntryFailed("local error: " + describe(code, data))
        if code == 2:
            raise StopBatch("usage error (fix the manifest/flags): " + describe(code, data))
        raise EntryFailed("unexpected: " + describe(code, data))


def run_manifest(entries, limit=None, jobs_path=None, runner=run, sleep=time.sleep,
                 log=lambda m: sys.stderr.write(m + "\n")):
    """Returns (counts dict, stop_reason or None)."""
    jobs = load_jobs(jobs_path)
    done = skipped = failed = attempted = 0
    stop = None
    pending = []
    for e in entries:
        if os.path.exists(os.path.join(C.ROOT, e["out"])):
            skipped += 1
        else:
            pending.append(e)
    todo = pending if limit is None else pending[:limit]
    for n, e in enumerate(todo):
        attempted += 1
        try:
            jid = run_entry(e, jobs, runner, sleep)
            if jid:
                jobs[e["key"]] = jid
                save_jobs(jobs, jobs_path)
            done += 1
            log("ok   %s -> %s" % (e["key"], jid))
        except EntryFailed as ex:
            failed += 1
            log("FAIL %s: %s" % (e["key"], ex))
        except StopBatch as ex:
            failed += 1
            stop = "%s: %s" % (e["key"], ex)
            log("STOP %s" % stop)
            break
    remaining = len(pending) - done - failed
    return {"done": done, "skipped": skipped, "failed": failed, "remaining": remaining}, stop


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("manifest")
    ap.add_argument("--limit", type=int, help="run at most N pending entries")
    ap.add_argument("--dry-run", action="store_true", help="print commands, run nothing")
    a = ap.parse_args(argv)
    with open(a.manifest, encoding="utf-8") as f:
        entries = json.load(f)
    if a.dry_run:
        n = 0
        for e in entries:
            if os.path.exists(os.path.join(C.ROOT, e["out"])):
                continue
            if a.limit is not None and n >= a.limit:
                break
            n += 1
            print("[%s] " % e["key"] + " ".join(shell_quote(x) for x in build_argv(e, {}, dry=True)))
        return 0
    counts, stop = run_manifest(entries, a.limit)
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
