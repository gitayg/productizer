#!/usr/bin/env python3
"""ci-timing.py --workflow FILE [--repo OWNER/NAME] [--branch B] [--limit N]
             [--setup-pattern REGEX]... [--min-seconds S] [--format text|json]
             [--from DIR] [--selftest] [--version] [--help]

Where a workflow's time goes, job by job, over its last N runs (default 30).

WHY THIS EXISTS (B188). CI time hides where nobody looks: waiting for a
machine, and setup - checkout, installs, caches - as opposed to the checks
themselves. A cache that misses on most runs goes unnoticed for months,
because an agent just retries. Only the same job measured over many runs
shows it.

WHERE THE NUMBERS COME FROM. It runs `gh api` as a subprocess, read-only:
the workflow's runs (`repos/R/actions/workflows/W/runs`, newest first,
filtered by --branch when given), then each run's jobs (`.../runs/ID/jobs`,
the latest attempt). It never reads, holds or passes a token; the gh it runs
uses its own authentication, and gh's standard error reaches the terminal as
gh wrote it. --repo defaults to `{owner}/{repo}`, which gh resolves from the
working directory's remote. --from DIR reads saved API JSON instead: DIR holds
`runs.json` (the runs response) and one `jobs-<run id>.json` per run (the jobs
response); there --repo and --workflow only label the report, and --branch
filters on each run's `head_branch`.

EACH JOB'S TIME IN THREE PARTS:
  waiting  the job's started_at minus its created_at - the queue for a machine
  setup    the summed durations of its setup steps (below)
  running  the job's completed_at minus its started_at, less setup, so the
           three parts add up to the job's time from queued to done
THE SETUP RULE IS A HEURISTIC OVER STEP NAMES, case-insensitive, and nothing
more: a step is setup when its name matches any of
  ^Set up job$          GitHub's own preparation step
  ^Complete job$        GitHub's own teardown step
  ^Post\\b               GitHub's post-step of an action (cache saves included)
  actions/checkout      the checkout action, as GitHub names a step that `uses:` it
  actions/setup-        the setup-* actions
  \\bcach(e|es|ing)\\b    cache actions, and steps whose names say cache
  \\binstall(s|ed|ing)?\\b steps whose names say they install
A step named for what it installs without the word ("semgrep, for the sast
check") counts as running; --setup-pattern REGEX, repeatable, adds a pattern.
A skipped step is not timed.

PER JOB IT PRINTS the median and the p90 (nearest rank: the ceil(0.9 n)-th
smallest) of each part over the measured runs, and each part's share of the
summed time.

WHAT IT FLAGS:
  waiting  a job whose median waiting exceeds its median running
  setup    a job whose median setup exceeds its median running
  bimodal  a step whose durations fall into two modes - a cache that hits on
           some runs and misses on others. Over at least 5 measured runs, the
           durations sorted are split where the slowest of the fast side and
           the fastest of the slow side are furthest apart, each side holding
           at least 20% of the runs; it is flagged when the slow side's median
           is at least 3x the fast side's, the fastest slow run at least 2x
           the slowest fast run (so a steady spread is not two modes), and the
           slow median at least --min-seconds (default 5: GitHub's step
           timestamps are whole seconds, so 1s against 3s is resolution, not a
           mode). A fast median under 1s is taken as 1s.

WHAT IS NOT MEASURED, AND SAID SO. A run that has not completed, a run whose
jobs could not be read, and a job missing any of created_at, started_at or
completed_at, a non-skipped step missing either timestamp, or timestamps out
of order, is counted as unmeasured, with its reason - never as zero. A job
skipped or cancelled is counted as such and not timed. A run is measured when
every job it ran was.

Exit codes:
  0  measured, nothing flagged
  1  measured, at least one flag, each printed
  2  could not run: bad usage, gh absent or failing, or saved JSON unreadable
  3  not measured: no job in the runs read was measured
--selftest runs its cases over fixtures/ci-timing, offline, and exits 0 when
every case held, 1 otherwise.
"""
import json
import math
import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import urllib.parse
from datetime import datetime, timezone

VERSION = "ci-timing 1.0"
HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(os.path.dirname(HERE), "fixtures", "ci-timing")
USAGE = ("usage: ci-timing.py --workflow FILE [--repo OWNER/NAME] [--branch B] [--limit N] [--setup-pattern REGEX]..."
         " [--min-seconds S] [--format text|json] [--from DIR] [--selftest] [--version] [--help]\n")
DEFAULT_SETUP = (r"^Set up job$", r"^Complete job$", r"^Post\b", r"actions/checkout", r"actions/setup-",
                 r"\bcach(e|es|ing)\b", r"\binstall(s|ed|ing)?\b")
PARTS = ("waiting", "setup", "running")
MIN_RUNS, MIN_SHARE, MODE_RATIO, GAP_RATIO = 5, 0.20, 3.0, 2.0
NOT_TIMED = ("skipped", "cancelled")


class Refused(Exception):
    def __init__(self, msg, usage=False):
        Exception.__init__(self, msg)
        self.usage = usage


def when(value):
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()
    except ValueError:
        return None


def is_setup(name, patterns):
    return any(p.search(name or "") for p in patterns)


def time_job(job, patterns):
    """(parts, steps, None) for a measured job, or (None, None, reason)."""
    if job.get("status") != "completed":
        return None, None, "status %s" % job.get("status")
    t = [when(job.get(k)) for k in ("created_at", "started_at", "completed_at")]
    missing = [k for k, v in zip(("created_at", "started_at", "completed_at"), t) if v is None]
    if missing:
        return None, None, "no %s" % ", ".join(missing)
    if not t[0] <= t[1] <= t[2]:
        return None, None, "timestamps out of order"
    setup, steps = 0, []
    for s in job.get("steps") or []:
        if s.get("conclusion") == "skipped":
            continue
        a, b = when(s.get("started_at")), when(s.get("completed_at"))
        if a is None or b is None:
            return None, None, "step %r has no %s" % (s.get("name"), "started_at" if a is None else "completed_at")
        if b < a:
            return None, None, "step %r ends before it starts" % s.get("name")
        steps.append((s.get("name") or "", b - a))
        if is_setup(s.get("name"), patterns):
            setup += b - a
    running = (t[2] - t[1]) - setup
    if running < 0:
        return None, None, "setup steps outlast the job"
    return {"waiting": t[1] - t[0], "setup": setup, "running": running}, steps, None


def p90(values):
    s = sorted(values)
    return s[max(0, math.ceil(0.9 * len(s)) - 1)]


def bimodal(durations, min_seconds):
    """The two modes of a step's durations, or None."""
    n = len(durations)
    if n < MIN_RUNS:
        return None
    s = sorted(durations)
    need = math.ceil(MIN_SHARE * n)
    best = None
    for k in range(need, n - need + 1):
        gap = s[k] / max(s[k - 1], 1)
        if best is None or gap > best[0]:
            best = (gap, k)
    if best is None:
        return None
    gap, k = best
    fast, slow = statistics.median(s[:k]), statistics.median(s[k:])
    if slow >= MODE_RATIO * max(fast, 1) and gap >= GAP_RATIO and slow >= min_seconds:
        return {"fast": fast, "fast_runs": k, "slow": slow, "slow_runs": n - k}
    return None


def gh_json(path):
    if shutil.which("gh") is None:
        raise Refused("gh is not on PATH; it reads the GitHub Actions API, and --from DIR reads saved JSON instead")
    proc = subprocess.run(["gh", "api", path], stdout=subprocess.PIPE, text=True, check=False)
    if proc.returncode != 0:
        raise Refused("gh api %s exited %d" % (path, proc.returncode))
    try:
        return json.loads(proc.stdout)
    except ValueError as exc:
        raise Refused("gh api %s returned no JSON: %s" % (path, exc))


def read_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except OSError as exc:
        if not os.path.exists(path):
            return None
        raise Refused("cannot read %s: %s" % (path, exc.strerror))
    except ValueError as exc:
        raise Refused("%s is not JSON: %s" % (path, exc))


def fetch_live(repo, workflow, branch, limit):
    runs, page = [], 1
    while len(runs) < limit:
        q = {"per_page": min(limit, 100), "page": page}
        if branch:
            q["branch"] = branch
        got = gh_json("repos/%s/actions/workflows/%s/runs?%s" % (repo, urllib.parse.quote(workflow, safe=""),
                                                                urllib.parse.urlencode(q)))
        batch = got.get("workflow_runs") or []
        runs.extend(batch)
        if len(batch) < q["per_page"]:
            break
        page += 1
    runs = runs[:limit]
    jobs = {}
    for r in runs:
        out, page = [], 1
        while True:
            got = gh_json("repos/%s/actions/runs/%s/jobs?per_page=100&page=%d" % (repo, r.get("id"), page))
            batch = got.get("jobs") or []
            out.extend(batch)
            if len(batch) < 100:
                break
            page += 1
        jobs[r.get("id")] = out
    return runs, jobs


def fetch_saved(folder, branch, limit):
    if not os.path.isdir(folder):
        raise Refused("--from %s is not a directory" % folder)
    got = read_json(os.path.join(folder, "runs.json"))
    if got is None:
        raise Refused("--from %s holds no runs.json" % folder)
    runs = [r for r in got.get("workflow_runs") or [] if not branch or r.get("head_branch") == branch][:limit]
    jobs = {}
    for r in runs:
        j = read_json(os.path.join(folder, "jobs-%s.json" % r.get("id")))
        if j is not None:
            jobs[r.get("id")] = j.get("jobs") or []
    return runs, jobs


def analyse(runs, jobs, patterns, min_seconds):
    per_job, step_times, run_notes = {}, {}, []
    measured_runs = 0
    for r in runs:
        rid = r.get("id")
        if r.get("status") != "completed":
            run_notes.append((rid, "run status %s" % r.get("status")))
            continue
        if rid not in jobs:
            run_notes.append((rid, "its jobs could not be read"))
            continue
        whole = True
        for j in jobs[rid]:
            name = j.get("name") or "?"
            rec = per_job.setdefault(name, {"times": [], "unmeasured": [], "skipped": 0, "cancelled": 0})
            if j.get("conclusion") in NOT_TIMED:
                rec[j["conclusion"]] += 1
                continue
            parts, steps, reason = time_job(j, patterns)
            if parts is None:
                rec["unmeasured"].append((rid, reason))
                run_notes.append((rid, "job %s: %s" % (name, reason)))
                whole = False
                continue
            rec["times"].append(parts)
            for sname, d in steps:
                step_times.setdefault((name, sname), []).append(d)
        measured_runs += 1 if whole else 0
    report = {"runs_read": len(runs), "runs_measured": measured_runs,
              "runs_unmeasured": [{"run": rid, "reason": why} for rid, why in run_notes], "jobs": [], "bimodal": [],
              "flags": 0}
    for name in sorted(per_job):
        rec = per_job[name]
        out = {"job": name, "measured": len(rec["times"]), "unmeasured": len(rec["unmeasured"]),
               "skipped": rec["skipped"], "cancelled": rec["cancelled"], "parts": {}, "flags": []}
        if rec["times"]:
            total = sum(sum(t.values()) for t in rec["times"])
            for p in PARTS:
                vals = [t[p] for t in rec["times"]]
                out["parts"][p] = {"median": statistics.median(vals), "p90": p90(vals),
                                   "share": (sum(vals) / total) if total else None}
            for p in ("waiting", "setup"):
                if out["parts"][p]["median"] > out["parts"]["running"]["median"]:
                    out["flags"].append(p)
        report["flags"] += len(out["flags"])
        report["jobs"].append(out)
    for (jname, sname), ds in sorted(step_times.items()):
        b = bimodal(ds, min_seconds)
        if b:
            b.update({"job": jname, "step": sname, "setup": is_setup(sname, patterns)})
            report["bimodal"].append(b)
    report["flags"] += len(report["bimodal"])
    return report


def dur(s):
    if s is None:
        return "-"
    s = int(round(s))
    if s < 60:
        return "%ds" % s
    if s < 3600:
        return "%dm%02ds" % (s // 60, s % 60)
    return "%dh%02dm" % (s // 3600, (s % 3600) // 60)


def render_text(rep):
    lines = ["%s: %s, workflow %s, branch %s, last %d run(s)" % (VERSION, rep["repo"], rep["workflow"],
                                                                rep["branch"] or "(any)", rep["limit"]),
             "setup rule: a heuristic over step names - %d default pattern(s)%s" % (
                 len(DEFAULT_SETUP), "" if not rep["setup_added"] else " plus " + ", ".join(rep["setup_added"])),
             "runs: %d read, %d measured, %d unmeasured" % (rep["runs_read"], rep["runs_measured"],
                                                            rep["runs_read"] - rep["runs_measured"])]
    for u in rep["runs_unmeasured"]:
        lines.append("  unmeasured run %s: %s" % (u["run"], u["reason"]))
    for j in rep["jobs"]:
        lines.append("")
        lines.append("job %s: %d measured, %d unmeasured, %d skipped, %d cancelled" % (
            j["job"], j["measured"], j["unmeasured"], j["skipped"], j["cancelled"]))
        if not j["parts"]:
            continue
        lines.append("  %-8s %8s %8s %7s" % ("part", "median", "p90", "share"))
        for p in PARTS:
            v = j["parts"][p]
            share = "-" if v["share"] is None else "%.1f%%" % (100 * v["share"])
            lines.append("  %-8s %8s %8s %7s" % (p, dur(v["median"]), dur(v["p90"]), share))
        for f in j["flags"]:
            lines.append("  FLAG %s: median %s %s exceeds median running %s" % (
                f, f, dur(j["parts"][f]["median"]), dur(j["parts"]["running"]["median"])))
    lines.append("")
    for b in rep["bimodal"]:
        lines.append("FLAG bimodal: job %s, step %r (%s): fast mode %s over %d run(s), slow mode %s over %d run(s)" % (
            b["job"], b["step"], "setup" if b["setup"] else "running", dur(b["fast"]), b["fast_runs"], dur(b["slow"]),
            b["slow_runs"]))
    measured = sum(j["measured"] for j in rep["jobs"])
    lines.append("ci-timing: %d job run(s) measured, %d flag(s)%s" % (
        measured, rep["flags"], "" if measured else " - NOT MEASURED: no job in the runs read was measured"))
    return "\n".join(lines)


def run(opts):
    patterns = [re.compile(p, re.I) for p in DEFAULT_SETUP + tuple(opts["setup"])]
    if opts["from"]:
        runs, jobs = fetch_saved(opts["from"], opts["branch"], opts["limit"])
    else:
        runs, jobs = fetch_live(opts["repo"], opts["workflow"], opts["branch"], opts["limit"])
    rep = analyse(runs, jobs, patterns, opts["min_seconds"])
    rep.update({"version": VERSION, "repo": opts["repo"], "workflow": opts["workflow"], "branch": opts["branch"],
                "limit": opts["limit"], "setup_default": list(DEFAULT_SETUP), "setup_added": list(opts["setup"])})
    measured = sum(j["measured"] for j in rep["jobs"])
    rc = 3 if not measured else (1 if rep["flags"] else 0)
    return rc, (json.dumps(rep, indent=2, sort_keys=True) if opts["format"] == "json" else render_text(rep))


def parse(args):
    opts = {"workflow": None, "repo": "{owner}/{repo}", "branch": None, "limit": 30, "setup": [], "min_seconds": 5,
            "format": "text", "from": None}
    flags = {"--workflow": "workflow", "--repo": "repo", "--branch": "branch", "--limit": "limit",
             "--setup-pattern": "setup", "--min-seconds": "min_seconds", "--format": "format", "--from": "from"}
    args = list(args)
    while args:
        a = args.pop(0)
        key, val = a, None
        if "=" in a and a.split("=", 1)[0] in flags:
            key, val = a.split("=", 1)
        if key not in flags:
            raise Refused("unknown argument %r" % a, usage=True)
        if val is None:
            if not args:
                raise Refused("%s needs a value" % key, usage=True)
            val = args.pop(0)
        name = flags[key]
        if name == "setup":
            try:
                re.compile(val)
            except re.error as exc:
                raise Refused("--setup-pattern %r is not a regular expression: %s" % (val, exc), usage=True)
            opts["setup"].append(val)
        elif name in ("limit", "min_seconds"):
            if not re.match(r"^\d+$", val) or (name == "limit" and not 1 <= int(val) <= 1000):
                raise Refused("%s must be a whole number%s, not %r" % (key, " from 1 to 1000" if name == "limit" else "",
                                                                     val), usage=True)
            opts[name] = int(val)
        else:
            opts[name] = val
    if opts["format"] not in ("text", "json"):
        raise Refused("--format must be text or json, not %r" % opts["format"], usage=True)
    if not opts["from"] and not opts["workflow"]:
        raise Refused("--workflow is required unless --from DIR is given", usage=True)
    if not opts["from"] and not re.match(r"^(\{owner\}/\{repo\}|[\w.-]+/[\w.-]+)$", opts["repo"]):
        raise Refused("--repo must be OWNER/NAME, not %r" % opts["repo"], usage=True)
    if opts["from"]:
        opts["workflow"] = opts["workflow"] or "(saved)"
        opts["repo"] = "(saved)" if opts["repo"] == "{owner}/{repo}" else opts["repo"]
    return opts


def documented_codes():
    block = __doc__.split("Exit codes:", 1)[1]
    return [int(m.group(1)) for m in re.finditer(r"^  (\d) ", block, re.M)]


def selftest():
    held = total = 0
    codes = set()
    base = os.path.join(FIXTURES, "base")
    if not os.path.isfile(os.path.join(base, "runs.json")):
        print("  FAIL no fixture at %s" % base)
        return 1
    with tempfile.TemporaryDirectory() as tmp:
        n = [0]

        def variant(change):
            """A copy of the base fixture with ONE change, made by change(runs, jobs)."""
            n[0] += 1
            d = os.path.join(tmp, "v%d" % n[0])
            shutil.copytree(base, d)
            with open(os.path.join(d, "runs.json"), encoding="utf-8") as fh:
                runs = json.load(fh)
            jobs = {}
            for r in runs["workflow_runs"]:
                p = os.path.join(d, "jobs-%s.json" % r["id"])
                with open(p, encoding="utf-8") as fh:
                    jobs[r["id"]] = json.load(fh)
            change(runs["workflow_runs"], jobs)
            with open(os.path.join(d, "runs.json"), "w", encoding="utf-8") as fh:
                json.dump(runs, fh)
            for rid, j in jobs.items():
                p = os.path.join(d, "jobs-%s.json" % rid)
                if j is None:
                    os.remove(p)
                else:
                    with open(p, "w", encoding="utf-8") as fh:
                        json.dump(j, fh)
            return d

        def job(jobs, rid, name):
            return [j for j in jobs[rid]["jobs"] if j["name"] == name][0]

        def step(jobs, rid, jname, sname):
            return [s for s in job(jobs, rid, jname)["steps"] if s["name"] == sname][0]

        def iso(t):
            return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        def stretch(jobs, rid, jname, sname, seconds):
            """Make one step last `seconds`, moving every later step and the job's end by the difference."""
            j = job(jobs, rid, jname)
            s = step(jobs, rid, jname, sname)
            delta = seconds - (when(s["completed_at"]) - when(s["started_at"]))
            after = False
            for x in j["steps"]:
                if after:
                    x["started_at"] = iso(when(x["started_at"]) + delta)
                    x["completed_at"] = iso(when(x["completed_at"]) + delta)
                if x is s:
                    x["completed_at"] = iso(when(x["completed_at"]) + delta)
                    after = True
            j["completed_at"] = iso(when(j["completed_at"]) + delta)

        def per_run(fn):
            def change(runs, jobs):
                for i, r in enumerate(runs):
                    fn(i, r, jobs)
            return change

        def cache_modes(slow_runs, fast=10, slow=60):
            return per_run(lambda i, r, jobs: stretch(jobs, r["id"], "test", "Run actions/cache@v4", slow if i < slow_runs else fast))

        def cache_each(seconds):
            return per_run(lambda i, r, jobs: stretch(jobs, r["id"], "test", "Run actions/cache@v4", seconds[i]))

        def queue(seconds, jname="lint"):
            def fn(i, r, jobs):
                j = job(jobs, r["id"], jname)
                j["created_at"] = iso(when(j["started_at"]) - seconds)
            return per_run(fn)

        def drop(rid_index, jname, key):
            def change(runs, jobs):
                job(jobs, runs[rid_index]["id"], jname)[key] = None
            return change

        def step_drop(jname, sname, key):
            def change(runs, jobs):
                step(jobs, runs[0]["id"], jname, sname)[key] = None
            return change

        def all_missing(runs, jobs):
            for r in runs:
                for j in jobs[r["id"]]["jobs"]:
                    j["started_at"] = None

        def no_jobs_file(runs, jobs):
            jobs[runs[1]["id"]] = None

        def in_progress(runs, jobs):
            runs[2]["status"] = "in_progress"

        def out_of_order(runs, jobs):
            j = job(jobs, runs[0]["id"], "lint")
            j["created_at"] = iso(when(j["started_at"]) + 5)

        def cancelled(runs, jobs):
            job(jobs, runs[0]["id"], "test")["conclusion"] = "cancelled"

        def spread(runs, jobs):
            for i, r in enumerate(runs):
                stretch(jobs, r["id"], "test", "Run actions/cache@v4", 10 + 10 * i)

        def install_named_tool(runs, jobs):
            for r in runs:
                step(jobs, r["id"], "test", "Run pytest")["name"] = "pytest, which the suite runs"

        def setup_heavy(runs, jobs):
            for r in runs:
                stretch(jobs, r["id"], "lint", "Install linters", 500)

        def tiny_modes(runs, jobs):
            for i, r in enumerate(runs):
                stretch(jobs, r["id"], "lint", "Run actions/checkout@v4", 4 if i < 5 else 1)

        def unmeasured_not_zero(runs, jobs):
            for r in runs[:5]:
                job(jobs, r["id"], "lint")["started_at"] = None

        B = base
        cases = [
            # name, argv after --from DIR, dir, exit, needles that must appear, needles that must not.
            # Base: test waits 3,4,4,5,6,3,4,2,5,4 s, sets up 42 s (2+3+5+10+20+1+1+0) and runs 300 s; lint waits 5,
            # sets up 12 and runs 60; release is skipped. Shares: 40, 420 and 3000 of 3460 s.
            ("base-steady", [], B, 0, ["runs: 10 read, 10 measured, 0 unmeasured",
                                       "job test: 10 measured, 0 unmeasured, 0 skipped, 0 cancelled",
                                       "  waiting        4s       5s    1.2%", "  setup         42s      42s   12.1%",
                                       "  running     5m00s    5m00s   86.7%",
                                       "job release: 0 measured, 0 unmeasured, 10 skipped", "0 flag(s)"], ["FLAG"]),
            ("p90-nearest-rank", [], variant(per_run(lambda i, r, jobs: stretch(jobs, r["id"], "test", "Run pytest", 300 + 10 * i))),
             0, ["  running     5m45s    6m20s"], []),
            ("waiting-exceeds-running", [], variant(queue(200)), 1, ["FLAG waiting: median waiting 3m20s exceeds median running 1m00s"], []),
            ("waiting-equals-running-no-flag", [], variant(queue(60)), 0, ["0 flag(s)"], ["FLAG waiting"]),
            ("setup-exceeds-running", [], variant(setup_heavy), 1, ["FLAG setup: median setup 8m22s exceeds median running 1m00s"],
             ["FLAG waiting"]),
            ("cache-bimodal-30pct", [], variant(cache_modes(3)), 1,
             ["FLAG bimodal: job test, step 'Run actions/cache@v4' (setup): fast mode 10s over 7 run(s), slow mode 1m00s over 3 run(s)"], []),
            ("cache-bimodal-20pct-boundary", [], variant(cache_modes(2)), 1, ["slow mode 1m00s over 2 run(s)"], []),
            ("cache-10pct-no-flag", [], variant(cache_modes(1)), 0, ["0 flag(s)"], ["FLAG bimodal"]),
            ("cache-3x-boundary", [], variant(cache_modes(4, 10, 30)), 1, ["slow mode 30s over 4 run(s)"], []),
            ("cache-2.5x-no-flag", [], variant(cache_modes(4, 10, 25)), 0, ["0 flag(s)"], ["FLAG bimodal"]),
            ("steady-spread-no-flag", [], variant(spread), 0, ["0 flag(s)"], ["FLAG bimodal"]),
            ("modes-1.9x-apart-no-flag", [], variant(cache_each([35, 35, 35, 19, 10, 10, 10, 10, 10, 10])), 0, ["0 flag(s)"],
             ["FLAG bimodal"]),
            ("modes-2x-apart-flags", [], variant(cache_each([35, 35, 35, 17, 10, 10, 10, 10, 10, 10])), 1,
             ["fast mode 10s over 7 run(s), slow mode 35s over 3 run(s)"], []),
            ("whole-second-noise-no-flag", [], variant(tiny_modes), 0, ["0 flag(s)"], ["FLAG bimodal"]),
            ("min-seconds-lowered-flags-it", ["--min-seconds", "3"], variant(tiny_modes), 1, ["FLAG bimodal: job lint"], []),
            ("job-missing-started-unmeasured", [], variant(drop(0, "lint", "started_at")), 0,
             ["runs: 10 read, 9 measured, 1 unmeasured", "job lint: no started_at", "job lint: 9 measured, 1 unmeasured"], []),
            ("unmeasured-is-not-zero", [], variant(unmeasured_not_zero), 0,
             ["job lint: 5 measured, 5 unmeasured", "  waiting        5s       5s"], []),
            ("job-missing-completed-unmeasured", [], variant(drop(4, "test", "completed_at")), 0,
             ["job test: no completed_at", "job test: 9 measured, 1 unmeasured"], []),
            ("step-missing-timestamp-unmeasured", [], variant(step_drop("test", "Run pytest", "completed_at")), 0,
             ["job test: step 'Run pytest' has no completed_at", "job test: 9 measured, 1 unmeasured"], []),
            ("timestamps-out-of-order-unmeasured", [], variant(out_of_order), 0, ["job lint: timestamps out of order"], []),
            ("run-in-progress-unmeasured", [], variant(in_progress), 0, ["run status in_progress", "runs: 10 read, 9 measured"], []),
            ("run-jobs-unreadable-unmeasured", [], variant(no_jobs_file), 0, ["its jobs could not be read"], []),
            ("cancelled-job-not-timed", [], variant(cancelled), 0, ["job test: 9 measured, 0 unmeasured, 0 skipped, 1 cancelled"], []),
            ("nothing-measured-exit-3", [], variant(all_missing), 3, ["NOT MEASURED"], []),
            ("default-rule-misses-unnamed-install", [], variant(install_named_tool), 0, ["  setup         42s      42s"], []),
            ("setup-pattern-adds", ["--setup-pattern", r"^pytest\b"], variant(install_named_tool), 1,
             ["plus ^pytest\\b", "FLAG setup: median setup 5m42s exceeds median running 0s"], []),
            ("limit-reads-newest", ["--limit", "4"], B, 0, ["last 4 run(s)", "runs: 4 read, 4 measured"], []),
            ("branch-filter", ["--branch", "feature"], B, 0, ["branch feature", "runs: 2 read"], []),
        ]
        for name, argv, d, want_rc, needles, absent in cases:
            total += 1
            try:
                rc, out = run(parse(["--from", d] + argv))
            except Refused as exc:
                rc, out = 2, str(exc)
            codes.add(rc)
            bad = [x for x in needles if x not in out] + ["(unwanted) " + x for x in absent if x in out]
            if rc == want_rc and not bad:
                held += 1
                print("  ok   %s (exit %d)" % (name, rc))
            else:
                print("  FAIL %s: exit %d, wanted %d; %s\n%s" % (name, rc, want_rc, "; ".join(bad), out))

        total += 1
        rc, out = run(parse(["--from", B, "--format", "json"]))
        rep = json.loads(out)
        t = [j for j in rep["jobs"] if j["job"] == "test"][0]["parts"]
        if rc == 0 and t["waiting"]["median"] == 4 and t["setup"]["median"] == 42 and abs(
                sum(t[p]["share"] for p in PARTS) - 1) < 1e-9 and rep["setup_default"] == list(DEFAULT_SETUP):
            held += 1
            print("  ok   json-format (exit 0)")
        else:
            print("  FAIL json-format: exit %d\n%s" % (rc, out))

        total += 1
        pats = [re.compile(p, re.I) for p in DEFAULT_SETUP]
        setup_names = ["Set up job", "Complete job", "Post Run actions/checkout@abc", "Run actions/checkout@abc",
                       "Run actions/setup-node@abc", "Run actions/cache@v4", "Restore the npm cache", "Install the CLI",
                       "pip installs PyYAML"]
        check_names = ["Run pytest", "Lint", "semgrep, which the sast check runs", "Postgres migrations",
                       "Reinstallation guard", "Run setup.py"]
        wrong = [x for x in setup_names if not is_setup(x, pats)] + [x for x in check_names if is_setup(x, pats)]
        if not wrong:
            held += 1
            print("  ok   default-setup-rule (%d setup, %d running names)" % (len(setup_names), len(check_names)))
        else:
            print("  FAIL default-setup-rule: misread %s" % wrong)

        # The live path, offline: a gh stub on PATH serves the base fixture and logs every call.
        stubdir = os.path.join(tmp, "bin")
        os.makedirs(stubdir)
        log = os.path.join(tmp, "gh.log")
        with os.fdopen(os.open(os.path.join(stubdir, "gh"), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o700), "w") as fh:
            fh.write("#!/bin/sh\nprintf '%%s\\n' \"$*\" >> %s\n"
                     "[ -n \"$GH_STUB_FAIL\" ] && { echo 'gh: HTTP 404' >&2; exit 1; }\n"
                     "case \"$2\" in\n"
                     "  */jobs\\?*) id=${2%%%%/jobs\\?*}; id=${id##*/}; cat %s/jobs-$id.json ;;\n"
                     "  *) cat %s/runs.json ;;\nesac\n" % (shq(log), shq(base), shq(base)))
        me = [sys.executable, os.path.abspath(__file__)]
        for name, argv, env_add, want_rc, needle in (
                ("live-via-gh", ["--workflow", "checks.yml", "--repo", "o/n", "--branch", "main", "--limit", "3"], {}, 0,
                 "runs: 3 read, 3 measured"),
                ("live-gh-fails", ["--workflow", "checks.yml", "--repo", "o/n"], {"GH_STUB_FAIL": "1"}, 2, "exited 1"),
                ("live-no-gh", ["--workflow", "checks.yml", "--repo", "o/n"], {"PATH": os.path.join(tmp, "empty")}, 2,
                 "gh is not on PATH"),
                ("no-workflow", [], {}, 2, "--workflow is required"),
                ("bad-limit", ["--workflow", "w.yml", "--limit", "0"], {}, 2, "--limit must be"),
                ("bad-pattern", ["--from", B, "--setup-pattern", "("], {}, 2, "not a regular expression"),
                ("bad-repo", ["--workflow", "w.yml", "--repo", "x y"], {}, 2, "--repo must be"),
                ("from-missing", ["--from", os.path.join(tmp, "none")], {}, 2, "is not a directory")):
            total += 1
            env = dict(os.environ, PATH=stubdir + os.pathsep + os.environ.get("PATH", ""))
            env.update(env_add)
            if os.path.exists(log):
                os.remove(log)
            proc = subprocess.run(me + argv, capture_output=True, text=True, check=False, env=env)
            codes.add(proc.returncode)
            calls = open(log).read() if os.path.exists(log) else ""
            extra = True
            if name == "live-via-gh":
                extra = ("api repos/o/n/actions/workflows/checks.yml/runs?per_page=3&page=1&branch=main" in calls
                         and calls.count("/jobs?per_page=100&page=1") == 3 and "token" not in calls)
            if proc.returncode == want_rc and needle in proc.stdout + proc.stderr and extra:
                held += 1
                print("  ok   %s (exit %d)" % (name, proc.returncode))
            else:
                print("  FAIL %s: exit %d, wanted %d with %r\ncalls: %s\n%s%s" % (name, proc.returncode, want_rc, needle,
                                                                                calls, proc.stdout, proc.stderr))
    documented = documented_codes()
    print("    exit codes reached: %s   documented: %s" % (" ".join(str(c) for c in sorted(codes)),
                                                           " ".join(str(c) for c in documented)))
    print("    NOT ASSERTED: that the default setup rule matches any real workflow's setup steps (it reads names);"
          " that GitHub's timestamps are accurate below a second; that a bimodal step is a cache")
    print("ci-timing selftest: %d of %d cases held" % (held, total))
    return 0 if held == total and codes == set(documented) else 1


def shq(s):
    return "'" + s.replace("'", "'\\''") + "'"


def main(argv):
    args = argv[1:]
    if args == ["--version"]:
        print(VERSION)
        return 0
    if args in (["--help"], ["-h"]):
        print(__doc__)
        return 0
    if args in (["--selftest"], ["--self-test"]):
        return selftest()
    try:
        rc, out = run(parse(args))
    except Refused as exc:
        sys.stderr.write("ci-timing: %s\n" % exc)
        if exc.usage:
            sys.stderr.write(USAGE)
        return 2
    print(out)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
