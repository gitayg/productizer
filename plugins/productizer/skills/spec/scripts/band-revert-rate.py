#!/usr/bin/env python3
"""band-revert-rate.py [--days N] [--windows N] [--now EPOCH] [--selftest] [--version] [--help]

The detection command of the revert-rate band (B171): one number a scheduled
band task reads, computed from git with no model in the path. Run it in the
repository's work tree; a binding names it as `band_bindings.revert_rate` in
`.claude/productizer/config.json`, and the band's own scheduled task
(templates/scheduled-band-metric.md) runs it only when the binding matches the
literal frozen in that task.

THE METRIC, as the maintainer ruled it on 2026-10-28: commits carrying a
`This reverts commit <id>` line, divided by changes merged, over the last DAYS
days (default 30). A change merged is a commit on HEAD's first-parent line: a
merge commit, a squashed pull request or a direct commit is one change each. A
revert is any commit reachable from HEAD whose message holds the line, read as
check-revert-cases.py reads it (loaded by path), so a revert inside a merged
branch counts once in the numerator and its merge once in the denominator.
Both are placed in a window by committer date.

THE BASELINE AND THE TIER come from band-baseline.py (loaded by path): the same
metric over the WINDOWS earlier windows of DAYS days (default 6), the value's
distance above their mean in their sample standard deviations, and a tier of
within, 1sigma, 2sigma or 3sigma, printed last on a `tier:` line. The
scheduled task acts on that line and never recomputes it.

Exit codes:
  0  measured: value, baseline, sigma and tier printed
  2  could not run: bad usage, not a git work tree with a commit, or a shared
     script not loadable beside it
  3  not measured: no change merged in the current window, fewer than 3
     earlier windows with one, or an earlier run of equal values the current
     one rises above
--selftest runs its cases in temporary repositories, and exits 0 when every
case held, 1 otherwise.
"""
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import time

VERSION = "band-revert-rate 1.0"
HERE = os.path.dirname(os.path.abspath(__file__))
METRIC = "revert_rate"
USAGE = "usage: band-revert-rate.py [--days N] [--windows N] [--now EPOCH] [--selftest] [--version] [--help]\n"
# What an install of the single, first band holds, as v4.74.1 shipped it. A
# band added beside it must leave all three as they were (B171, option b).
PINNED = {
    "templates/bands.yaml": "518e5981a0d75ccef2f2a7c1ef55c943888587bd2fbb657ac424c8f699fb33e1",
    "templates/scheduled-bands.md": "937cd5f710e6f2cf0ab3e03e206eb3023d4f658f43efe33c0ced964ad9f1bcb8",
}
PINNED_BINDING = {
    "_note": "The scheduled band check executes detection_command from HERE, never a path read out of "
             "bands.yaml. Two sources must agree: this binding and the literal frozen into the scheduled "
             "prompt when a human installed it.",
    "config": "ops/bands.yaml",
    "detection_command": "python3 ops/ci-failure-rate.py",
}


class Refused(Exception):
    pass


def load(name, attrs):
    path = os.path.join(HERE, name)
    try:
        spec = importlib.util.spec_from_file_location(name.replace("-", "_")[:-3], path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except (OSError, SyntaxError, AttributeError) as exc:
        raise Refused("could not load %s: %s" % (path, exc))
    gone = [a for a in attrs if not hasattr(mod, a)]
    if gone:
        raise Refused("%s no longer defines %s" % (path, ", ".join(gone)))
    return mod


def git(args, cwd):
    try:
        p = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True, check=False)
    except OSError as exc:
        raise Refused("git could not run: %s" % exc)
    if p.returncode != 0:
        raise Refused("git %s: %s" % (" ".join(args), p.stderr.strip()))
    return p.stdout


def run(opts, cwd):
    tool = "band-revert-rate"
    try:
        bb = load("band-baseline.py", ("windows", "inside", "report"))
        rc_mod = load("check-revert-cases.py", ("reverted_ids",))
        git(["rev-parse", "--verify", "--quiet", "HEAD^{commit}"], cwd)
        merged = [int(t) for t in git(["log", "--first-parent", "--format=%ct", "HEAD"], cwd).split()]
        reverts = []
        for c in git(["log", "--format=%ct%x00%B%x1e", "HEAD"], cwd).split("\x1e"):
            t, _, msg = c.strip("\n").partition("\x00")
            if t and rc_mod.reverted_ids(msg):
                reverts.append(int(t))
    except Refused as exc:
        return 2, ["%s: %s. Nothing was measured." % (tool, exc)]
    now = opts["now"] if opts["now"] is not None else int(time.time())
    rows = []
    for w in bb.windows(now, opts["days"], opts["windows"]):
        n = sum(1 for t in merged if bb.inside(t, w))
        r = sum(1 for t in reverts if bb.inside(t, w))
        rows.append(("%d revert(s) / %d merged change(s)" % (r, n), (float(r) / n) if n else None))
    return bb.report(tool, METRIC, opts["days"], now, rows, "no merged change")


def documented_codes():
    block = __doc__.split("Exit codes:", 1)[1]
    return [int(m.group(1)) for m in re.finditer(r"^  (\d) ", block, re.M)]


NOW = 1800000000
DAY = 86400


def install_checks():
    """The single-metric install unchanged, and each added band bound apart."""
    problems = []
    tdir = os.path.join(HERE, "..")
    for rel, want in sorted(PINNED.items()):
        try:
            with open(os.path.join(tdir, rel), "rb") as fh:
                got = hashlib.sha256(fh.read()).hexdigest()
        except OSError as exc:
            problems.append("%s: %s" % (rel, exc))
            continue
        if got != want:
            problems.append("%s changed: sha256 %s, v4.74.1 shipped %s" % (rel, got, want))
    try:
        with open(os.path.join(tdir, "templates", "config.json"), encoding="utf-8") as fh:
            cfg = json.load(fh)
    except (OSError, ValueError) as exc:
        return problems + ["templates/config.json: %s" % exc]
    if cfg.get("bands") != PINNED_BINDING:
        problems.append("templates/config.json `bands` is not the binding v4.74.1 shipped")
    added = cfg.get("band_bindings", {})
    seen = {cfg.get("bands", {}).get("config"), cfg.get("bands", {}).get("detection_command")}
    for metric in ("revert_rate", "review_rounds"):
        b = added.get(metric)
        if not isinstance(b, dict) or not b.get("config") or not b.get("detection_command"):
            problems.append("templates/config.json band_bindings.%s has no config and detection_command" % metric)
            continue
        for k in ("config", "detection_command"):
            if b[k] in seen:
                problems.append("band_bindings.%s.%s %r is shared with another band" % (metric, k, b[k]))
            seen.add(b[k])
        if not os.path.isfile(os.path.join(tdir, "templates", os.path.basename(b["config"]))):
            problems.append("no templates/%s for band_bindings.%s" % (os.path.basename(b["config"]), metric))
    try:
        with open(os.path.join(tdir, "templates", "scheduled-band-metric.md"), encoding="utf-8") as fh:
            prompt = fh.read()
        if "band_bindings.<METRIC>" not in prompt or "<DETECTION COMMAND>" not in prompt:
            problems.append("templates/scheduled-band-metric.md does not read its own binding against a frozen literal")
    except OSError as exc:
        problems.append("templates/scheduled-band-metric.md: %s" % exc)
    return problems


def selftest():
    held = total = 0
    codes = set()
    with tempfile.TemporaryDirectory() as tmp:
        def repo(name, plan, merge=None):
            """plan: [(window, changes, reverts)]; merge: a window holding one
            merge whose side branch carries a revert."""
            r = os.path.join(tmp, name)
            os.makedirs(r)
            env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
                       GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")

            def g(*args, at=None):
                e = dict(env)
                if at is not None:
                    e["GIT_COMMITTER_DATE"] = e["GIT_AUTHOR_DATE"] = "@%d +0000" % at
                subprocess.run(["git", "-c", "commit.gpgsign=false"] + list(args), cwd=r, env=e,
                               check=True, capture_output=True, text=True)
            g("init", "-q", "-b", "main")
            g("commit", "-q", "--allow-empty", "-m", "root", at=NOW - 400 * DAY)
            for k, changes, reverts in plan:
                for i in range(changes):
                    t = NOW - k * DAY - 60 * (i + 1)
                    msg = "change %d.%d" % (k, i)
                    if i < reverts:
                        msg = "Revert x\n\nThis reverts commit %s." % ("ab" * 20)
                    g("commit", "-q", "--allow-empty", "-m", msg, at=t)
            if merge is not None:
                t = NOW - merge * DAY - 30000
                g("checkout", "-q", "-b", "side")
                g("commit", "-q", "--allow-empty", "-m", "Revert y\n\nThis reverts commit %s." % ("cd" * 20), at=t)
                g("commit", "-q", "--allow-empty", "-m", "more", at=t + 1)
                g("checkout", "-q", "main")
                g("merge", "-q", "--no-ff", "-m", "merge side", "side", at=t + 2)
            return r

        base4 = [(1, 4, 0), (2, 4, 1), (3, 4, 0), (4, 4, 1)]
        cases = [
            ("within-band", repo("within", [(0, 4, 0)] + base4), 0, "tier: within"),
            ("value-printed", repo("value", [(0, 3, 1)] + base4), 0, "value: 0.3333"),
            ("one-sigma", repo("one", [(0, 3, 1)] + base4), 0, "tier: 1sigma"),
            ("two-sigma", repo("two", [(0, 4, 2)] + base4), 0, "tier: 2sigma"),
            ("three-sigma", repo("three", [(0, 4, 3)] + base4), 0, "tier: 3sigma"),
            ("baseline-printed", repo("base", [(0, 4, 0)] + base4), 0,
             "baseline: 4 earlier window(s) with a value, mean 0.1250, sd 0.1443"),
            ("drop-is-within", repo("drop", [(0, 4, 0), (1, 4, 2), (2, 4, 2), (3, 4, 1), (4, 4, 2)]), 0, "tier: within"),
            ("no-change-in-window", repo("empty", base4), 3, "NOT MEASURED: the current window holds no merged change"),
            ("too-few-earlier", repo("few", [(0, 4, 1), (1, 4, 0), (2, 4, 1)]), 3, "2 earlier window(s) hold a value"),
            ("no-spread-rise", repo("flat", [(0, 4, 1), (1, 4, 0), (2, 4, 0), (3, 4, 0)]), 3, "no spread"),
            ("no-spread-level", repo("level", [(0, 4, 0), (1, 4, 0), (2, 4, 0), (3, 4, 0)]), 0, "tier: within"),
            ("merged-branch-revert", repo("merge", [(1, 2, 0), (2, 2, 1), (3, 2, 0), (4, 2, 1)], merge=0), 0,
             "window 0 (current): 1 revert(s) / 1 merged change(s) = 1.0000"),
        ]
        for name, r, want_rc, want_text in cases:
            total += 1
            rc, out = run({"days": 1, "windows": 4, "now": NOW}, r)
            codes.add(rc)
            text = "\n".join(out)
            if rc == want_rc and want_text in text:
                held += 1
                print("  ok   %s (exit %d)" % (name, rc))
            else:
                print("  FAIL %s: exit %d, wanted %d with %r\n%s" % (name, rc, want_rc, want_text, text))
        total += 1
        rc, out = run({"days": 1, "windows": 4, "now": NOW}, tmp)
        codes.add(rc)
        if rc == 2 and "Nothing was measured" in "\n".join(out):
            held += 1
            print("  ok   not-a-repo (exit 2)")
        else:
            print("  FAIL not-a-repo: exit %d\n%s" % (rc, "\n".join(out)))
        for name, argv in (("bad-days", ["--days", "0"]), ("stray-operand", ["x"])):
            total += 1
            proc = subprocess.run([sys.executable, os.path.abspath(__file__)] + argv, cwd=tmp,
                                  capture_output=True, text=True, check=False)
            codes.add(proc.returncode)
            if proc.returncode == 2 and "usage" in proc.stderr:
                held += 1
                print("  ok   %s (exit 2)" % name)
            else:
                print("  FAIL %s: exit %d, stderr %r" % (name, proc.returncode, proc.stderr))
    total += 1
    problems = install_checks()
    if not problems:
        held += 1
        print("  ok   single-metric-install-unchanged (bands.yaml, scheduled-bands.md and the `bands` binding as v4.74.1 shipped them; each added band bound apart)")
    else:
        print("  FAIL single-metric-install-unchanged:\n    " + "\n    ".join(problems))
    documented = documented_codes()
    print("    exit codes reached: %s   documented: %s" % (" ".join(str(c) for c in sorted(codes)), " ".join(str(c) for c in documented)))
    print("    NOT ASSERTED: the Western Electric run rules, a revert written without the line, or a scheduled task actually installed")
    print("band-revert-rate selftest: %d of %d cases held" % (held, total))
    return 0 if held == total and codes == set(documented) else 1


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
        bb = load("band-baseline.py", ("parse_args",))
    except Refused as exc:
        sys.stderr.write("band-revert-rate: %s. Nothing was measured.\n" % exc)
        return 2
    opts = bb.parse_args(list(args), {})
    if opts is None:
        sys.stderr.write(USAGE)
        return 2
    rc, out = run(opts, os.getcwd())
    stream = sys.stderr if rc == 2 else sys.stdout
    for line in out:
        stream.write(line + "\n")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
