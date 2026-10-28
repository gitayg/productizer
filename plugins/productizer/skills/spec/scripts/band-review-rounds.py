#!/usr/bin/env python3
"""band-review-rounds.py [--records GLOB] [--days N] [--windows N] [--now EPOCH] [--selftest] [--version] [--help]

The detection command of the review-rounds band (B171): one number a scheduled
band task reads, with no model in the path. Run it in the repository's work
tree; a binding names it as `band_bindings.review_rounds` in
`.claude/productizer/config.json`, and the band's own scheduled task
(templates/scheduled-band-metric.md) runs it only when the binding matches the
literal frozen in that task.

THE METRIC, as the maintainer ruled it on 2026-10-28: review rounds per change,
read from the review records. A review record (templates/review-record.md) is
one change's; its rounds are the rows of its Rounds table, read by
check-review-record.py's own parser, loaded by path, so the record is never
read two ways. The records are the files HEAD tracks matching GLOB (default
`docs/sdlc/*/review.md`, the default artifacts path; an fnmatch glob, where `*`
crosses `/`), each read as HEAD holds it and placed in a window by the
committer date of the last commit that changed it. The value is the mean
number of rounds over the records of the last DAYS days (default 30). A record
with no Rounds row is named and not counted.

THE BASELINE AND THE TIER come from band-baseline.py, as for the revert-rate
band: the WINDOWS earlier windows (default 6), the value's distance above their
mean in their standard deviations, and a last line `tier:`.

Exit codes:
  0  measured: value, baseline, sigma and tier printed
  2  could not run: bad usage, not a git work tree with a commit, or a shared
     script not loadable beside it
  3  not measured: no review record in the current window, fewer than 3
     earlier windows with one, or an earlier run of equal values the current
     one rises above
--selftest runs its cases in temporary repositories, and exits 0 when every
case held, 1 otherwise.
"""
import fnmatch
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import time

VERSION = "band-review-rounds 1.0"
HERE = os.path.dirname(os.path.abspath(__file__))
METRIC = "review_rounds_per_change"
DEFAULT_GLOB = "docs/sdlc/*/review.md"
USAGE = ("usage: band-review-rounds.py [--records GLOB] [--days N] [--windows N] [--now EPOCH] "
         "[--selftest] [--version] [--help]\n")


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
    tool = "band-review-rounds"
    try:
        bb = load("band-baseline.py", ("windows", "inside", "report"))
        crr = load("check-review-record.py", ("sections", "table"))
        git(["rev-parse", "--verify", "--quiet", "HEAD^{commit}"], cwd)
        paths = [p for p in git(["ls-tree", "-r", "--name-only", "-z", "HEAD"], cwd).split("\0")
                 if p and fnmatch.fnmatchcase(p, opts["records"])]
        records, skipped = [], []
        for p in sorted(paths):
            text = git(["show", "HEAD:" + p], cwd)
            rounds = crr.table(crr.sections(text).get("rounds", []))
            if not rounds:
                skipped.append(p)
                continue
            t = int(git(["log", "-1", "--format=%ct", "HEAD", "--", p], cwd).strip())
            records.append((t, len(rounds)))
    except Refused as exc:
        return 2, ["%s: %s. Nothing was measured." % (tool, exc)]
    now = opts["now"] if opts["now"] is not None else int(time.time())
    rows = []
    for w in bb.windows(now, opts["days"], opts["windows"]):
        got = [n for t, n in records if bb.inside(t, w)]
        rows.append(("%d round(s) / %d record(s)" % (sum(got), len(got)),
                     (float(sum(got)) / len(got)) if got else None))
    rc, out = bb.report(tool, METRIC, opts["days"], now, rows, "no review record")
    head = ["  records: %d matching %s, %d counted" % (len(paths), opts["records"], len(records))]
    head += ["  not counted, no Rounds row: %s" % p for p in skipped]
    return rc, out[:1] + head + out[1:]


def documented_codes():
    block = __doc__.split("Exit codes:", 1)[1]
    return [int(m.group(1)) for m in re.finditer(r"^  (\d) ", block, re.M)]


NOW = 1800000000
DAY = 86400


def record(rounds):
    rows = "\n".join("| %d | %07d | %07d | no issues |" % (i, i, i + 1) for i in range(1, rounds + 1))
    return ("# Review record\n\nRethink: -\n\n## Rounds\n\n| Round | Base | Head | Findings |\n|---|---|---|---|\n"
            + rows + "\n\n## Findings\n\n| Id | Round | Severity | Location | Class | Status | Reason |\n"
            "|---|---|---|---|---|---|---|\n")


def selftest():
    held = total = 0
    codes = set()
    with tempfile.TemporaryDirectory() as tmp:
        def repo(name, plan, extra=None):
            """plan: [(window, [rounds per record])]; extra: [(path, text, window)]."""
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

            def put(path, text, at):
                full = os.path.join(r, path)
                os.makedirs(os.path.dirname(full), exist_ok=True)
                with open(full, "w") as fh:
                    fh.write(text)
                g("add", path)
                g("commit", "-q", "-m", "add " + path, at=at)
            g("init", "-q", "-b", "main")
            g("commit", "-q", "--allow-empty", "-m", "root", at=NOW - 400 * DAY)
            for k, counts in plan:
                for i, n in enumerate(counts):
                    put("docs/sdlc/c%d-%d/review.md" % (k, i), record(n), NOW - k * DAY - 60 * (i + 1))
            for path, text, k in extra or []:
                put(path, text, NOW - k * DAY - 7)
            return r

        base4 = [(1, [1, 1]), (2, [1, 2]), (3, [1, 1]), (4, [2, 1])]
        cases = [
            ("within-band", repo("within", [(0, [1, 1])] + base4), 0, "tier: within"),
            ("value-printed", repo("value", [(0, [2, 2, 1])] + base4), 0, "value: 1.6667"),
            ("baseline-printed", repo("base", [(0, [1])] + base4), 0,
             "baseline: 4 earlier window(s) with a value, mean 1.2500, sd 0.2887"),
            ("two-sigma", repo("two", [(0, [2, 2])] + base4), 0, "tier: 2sigma"),
            ("three-sigma", repo("three", [(0, [3, 2])] + base4), 0, "tier: 3sigma"),
            ("no-record-in-window", repo("empty", base4), 3, "NOT MEASURED: the current window holds no review record"),
            ("too-few-earlier", repo("few", [(0, [2]), (1, [1]), (2, [2])]), 3, "2 earlier window(s) hold a value"),
            ("no-spread-rise", repo("flat", [(0, [2]), (1, [1]), (2, [1]), (3, [1])]), 3, "no spread"),
            ("record-without-rounds", repo("bare", [(0, [1, 1])] + base4,
                                           [("docs/sdlc/bare/review.md", "# Review record\n\nnothing\n", 0)]), 0,
             "not counted, no Rounds row: docs/sdlc/bare/review.md"),
            ("other-path-ignored", repo("other", [(0, [1, 1])] + base4,
                                        [("notes/review.md", record(9), 0)]), 0, "tier: within"),
            ("dated-by-last-change", repo("moved", [(0, [1, 1])] + base4,
                                          [("docs/sdlc/c4-0/review.md", record(1), 0)]), 0,
             "window 0 (current): 3 round(s) / 3 record(s)"),
        ]
        for name, r, want_rc, want_text in cases:
            total += 1
            rc, out = run({"days": 1, "windows": 4, "now": NOW, "records": DEFAULT_GLOB}, r)
            codes.add(rc)
            text = "\n".join(out)
            if rc == want_rc and want_text in text:
                held += 1
                print("  ok   %s (exit %d)" % (name, rc))
            else:
                print("  FAIL %s: exit %d, wanted %d with %r\n%s" % (name, rc, want_rc, want_text, text))
        total += 1
        rc, out = run({"days": 1, "windows": 4, "now": NOW, "records": DEFAULT_GLOB}, tmp)
        codes.add(rc)
        if rc == 2 and "Nothing was measured" in "\n".join(out):
            held += 1
            print("  ok   not-a-repo (exit 2)")
        else:
            print("  FAIL not-a-repo: exit %d\n%s" % (rc, "\n".join(out)))
        for name, argv in (("bad-windows", ["--windows", "x"]), ("unknown-option", ["--metric", "y"])):
            total += 1
            proc = subprocess.run([sys.executable, os.path.abspath(__file__)] + argv, cwd=tmp,
                                  capture_output=True, text=True, check=False)
            codes.add(proc.returncode)
            if proc.returncode == 2 and "usage" in proc.stderr:
                held += 1
                print("  ok   %s (exit 2)" % name)
            else:
                print("  FAIL %s: exit %d, stderr %r" % (name, proc.returncode, proc.stderr))
    documented = documented_codes()
    print("    exit codes reached: %s   documented: %s" % (" ".join(str(c) for c in sorted(codes)), " ".join(str(c) for c in documented)))
    print("    NOT ASSERTED: that a record holds every round the change had, a change with no record, or a scheduled task actually installed")
    print("band-review-rounds selftest: %d of %d cases held" % (held, total))
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
        sys.stderr.write("band-review-rounds: %s. Nothing was measured.\n" % exc)
        return 2
    opts = bb.parse_args(list(args), {"records": DEFAULT_GLOB})
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
