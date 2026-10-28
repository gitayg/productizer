#!/usr/bin/env python3
"""score-reviewer-case.py --case CASE --record RECORD [--selftest] [--version] [--help]

Scores a reviewer against one reviewer case, with no model in the path. CASE
is a case file under `evals/reviewer/` (templates/reviewer-case.md): the change
that shipped a confirmed bug, that bug's `path:line`, and the fix. RECORD is
the review record a reviewer wrote for that change, in the format
`check-review-record.py` reads (templates/review-record.md), which this script
loads by path so the two never read a record two ways. A relative path is read
under the repository root (the git top level of the working directory), an
absolute one as given.

WHY THIS EXISTS (B170). A revert or an incident is the one place a reviewer's
miss is confirmed rather than guessed. Each becomes a case, and the reviewer is
re-scored on every case whenever its prompt, its tools, its model or the
review policy changes (templates/agent-evals.yml runs the reviewer; this
scores what it wrote). The score is a match, never a judgement: a model
deciding whether a model caught a bug is the noise this measures.

THE CASE, refused (exit 2) unless it holds, each on its own line before `---`:
  Change:  the commit that shipped the bug, 7 to 40 hex digits
  Bug:     `path:line` or `path:line-line` under the root
  Fix:     the commit or pull request that fixed it, not a placeholder
and, if given, `Base:` as a commit. `Source:` and `Class:` are read by people.
A key written twice is refused: which one counts would be a guess.

CAUGHT, exit 0, when all of these hold:
  shape     the record's rounds and findings read as check-review-record.py
            reads them: no `rounds` or `finding-shape` finding
  change    round 1's Head is the case's Change, and its Base the case's Base
            when the case names one, compared as prefixes
  bug       a round-1 finding of severity Important names the bug's path and a
            line range that overlaps the bug's
Otherwise MISSED, exit 1, naming which did not hold. Every run prints the
other round-1 findings as noise, and how the record's findings were answered.

Exit codes:
  0  caught: the record holds an Important finding at the case's bug
  1  missed: no such finding, a record of another change, or a malformed record
  2  could not run: bad usage, an unreadable case or record, a case missing
     Change, Bug or Fix, or check-review-record.py not loadable beside it
--selftest runs its cases in a temporary directory, and exits 0 when every case
held, 1 otherwise.
"""
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

VERSION = "score-reviewer-case 1.0"
HERE = os.path.dirname(os.path.abspath(__file__))
RECORD_CHECKER = os.path.join(HERE, "check-review-record.py")
SHARED = ("sections", "table", "check_record", "blank", "read", "SHA_RE", "LOC_RE", "STATUSES")
KEYS = ("Source", "Change", "Base", "Bug", "Class", "Fix")
USAGE = "usage: score-reviewer-case.py --case CASE --record RECORD [--selftest] [--version] [--help]\n"


class Refused(Exception):
    pass


def record_rules():
    """check-review-record.py, loaded by path: one reading of a review record."""
    try:
        spec = importlib.util.spec_from_file_location("check_review_record", RECORD_CHECKER)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except (OSError, SyntaxError, AttributeError) as exc:
        raise Refused("could not load %s: %s. Nothing was scored." % (RECORD_CHECKER, exc))
    gone = [n for n in SHARED if not hasattr(mod, n)]
    if gone:
        raise Refused("%s no longer defines %s. Nothing was scored." % (RECORD_CHECKER, ", ".join(gone)))
    return mod


def span(location, crr):
    """(path, first line, last line) of a `path:line` or `path:line-line`, or None."""
    loc = location.strip().strip("`")
    m = crr.LOC_RE.match(loc)
    if not m:
        return None
    path = m.group("path")
    if path.startswith("/") or ".." in path.split("/"):
        return None
    first = int(m.group("line"))
    tail = loc.rsplit(":", 1)[1]
    last = int(tail.split("-", 1)[1]) if "-" in tail else first
    return path, min(first, last), max(first, last)


def parse_case(text, crr):
    """{key: value} of a case, or raise Refused naming what is missing."""
    head = text.split("\n---", 1)[0]
    found = {}
    for line in head.split("\n"):
        m = re.match(r"^(%s):[ \t]*(.*?)\s*$" % "|".join(KEYS), line)
        if not m:
            continue
        if m.group(1) in found:
            raise Refused("the case names %s: twice" % m.group(1))
        found[m.group(1)] = m.group(2)
    problems = []
    change = found.get("Change", "")
    if not crr.SHA_RE.match(change):
        problems.append("Change: %r is not a commit id" % change)
    base = found.get("Base", "")
    if not crr.blank(base) and not crr.SHA_RE.match(base):
        problems.append("Base: %r is not a commit id" % base)
    if span(found.get("Bug", ""), crr) is None:
        problems.append("Bug: %r is not path:line under the root" % found.get("Bug", ""))
    if crr.blank(found.get("Fix", "")):
        problems.append("Fix: names no fix")
    if problems:
        raise Refused("; ".join(problems))
    return found


def same_commit(a, b):
    a, b = a.strip().lower(), b.strip().lower()
    return bool(a and b and (a.startswith(b) or b.startswith(a)))


def score(case_text, record_text, crr):
    """(exit code, lines). Raises Refused for a case it cannot score."""
    case = parse_case(case_text, crr)
    bug = span(case["Bug"], crr)
    out = ["  change %s, bug %s" % (case["Change"], case["Bug"])]
    f, tally, nr, nf = crr.check_record(record_text, [])
    secs = crr.sections(record_text)
    rounds = crr.table(secs.get("rounds", []))
    findings = [r for r in crr.table(secs.get("findings", [])) if r.get("round", "") == "1"]
    out.append("  answered: " + ", ".join("%s %d" % (s, tally[s]) for s in crr.STATUSES))
    missed = []
    shape = f["rounds"] + f["finding-shape"]
    if shape:
        missed.append("shape: the record is not a review record check-review-record.py can read: "
                      + "; ".join(shape))
    first = rounds[0] if rounds else {}
    if not same_commit(first.get("head", ""), case["Change"]):
        missed.append("change: round 1 reviewed %r, not the case's change %s"
                      % (first.get("head", ""), case["Change"]))
    elif not crr.blank(case.get("Base", "")) and not same_commit(first.get("base", ""), case["Base"]):
        missed.append("change: round 1 diffed from %r, not the case's base %s"
                      % (first.get("base", ""), case["Base"]))
    hit = None
    for r in findings:
        s = span(r.get("location", ""), crr)
        if (r.get("severity", "") == "Important" and s and s[0] == bug[0]
                and s[1] <= bug[2] and bug[1] <= s[2]):
            hit = r
            break
    if hit is None:
        missed.append("bug: no round-1 Important finding covers %s" % case["Bug"])
    noise = len(findings) - (1 if hit is not None else 0)
    if hit is not None:
        out.append("  at the bug: %s, %s, %s" % (hit.get("id", ""), hit.get("location", ""), hit.get("class", "")))
    out.append("  noise: %d other round-1 finding(s)" % noise)
    if missed:
        return 1, out + ["MISSED %s" % m for m in missed]
    return 0, out + ["CAUGHT"]


def run(case_path, record_path):
    out = ["score-reviewer-case: case %s, record %s" % (shown(case_path), shown(record_path))]
    try:
        crr = record_rules()
        texts = []
        for p in (case_path, record_path):
            text, err = crr.read(p)
            if text is None:
                raise Refused("cannot read %s: %s" % (p, err))
            texts.append(text)
        rc, lines = score(texts[0], texts[1], crr)
    except Refused as exc:
        return 2, out + ["score-reviewer-case: %s" % exc]
    return rc, out + lines


def shown(path):
    cwd = os.getcwd() + os.sep
    return path[len(cwd):] if path.startswith(cwd) else path


def resolve(arg):
    if os.path.isabs(arg):
        return arg
    try:
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=False)
    except OSError:
        top = None
    root = top.stdout.strip() if top is not None and top.returncode == 0 else os.getcwd()
    return os.path.join(root, arg)


def documented_codes():
    block = __doc__.split("Exit codes:", 1)[1]
    return [int(m.group(1)) for m in re.finditer(r"^  (\d) ", block, re.M)]


CASE = """# Reviewer case - retry loop on a permanent error

Source: revert 9999999
Change: 2222222
Base: 1111111
Bug: src/queue.py:41
Class: unbounded retry on a permanent error
Fix: 9999999 reverts it

---
"""

RECORD = """# Review record - eval of 2222222

Rethink: -

## Rounds

| Round | Base | Head | Findings |
|---|---|---|---|
| 1 | 1111111 | 2222222 | 2 |

## Findings

| Id | Round | Severity | Location | Class | Status | Reason |
|---|---|---|---|---|---|---|
| F1 | 1 | Nit | src/queue.py:9 | naming | open | - |
| F2 | 1 | Important | src/queue.py:38-44 | unbounded retry | open | - |
"""


def selftest():
    held = total = 0
    codes = set()
    with tempfile.TemporaryDirectory() as tmp:
        def write(name, body):
            p = os.path.join(tmp, name)
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(body)
            return p

        rec = RECORD
        cases = [
            ("caught-in-range", CASE, rec, 0, "CAUGHT"),
            ("noise-counted", CASE, rec, 0, "noise: 1 other round-1 finding(s)"),
            ("answered-tally", CASE, rec, 0, "answered: open 2, fixed 0"),
            ("caught-exact-line", CASE, rec.replace("src/queue.py:38-44", "src/queue.py:41"), 0, "CAUGHT"),
            ("caught-long-change", CASE.replace("Change: 2222222", "Change: 2222222abcdef"), rec, 0, "CAUGHT"),
            ("missed-line-outside", CASE, rec.replace("src/queue.py:38-44", "src/queue.py:42-44"), 1,
             "MISSED bug: no round-1 Important finding covers src/queue.py:41"),
            ("missed-other-file", CASE, rec.replace("src/queue.py:38-44", "src/worker.py:38-44"), 1, "MISSED bug"),
            ("missed-nit-at-bug", CASE, rec.replace("| Important | src/queue.py:38-44", "| Nit | src/queue.py:38-44"), 1,
             "MISSED bug"),
            ("missed-later-round", CASE,
             rec.replace("| 1 | 1111111 | 2222222 | 2 |", "| 1 | 1111111 | 2222222 | 1 |\n| 2 | 2222222 | 3333333 | 1 |")
             .replace("| F2 | 1 |", "| F2 | 2 |"), 1, "MISSED bug"),
            ("missed-other-change", CASE, rec.replace("| 1111111 | 2222222 |", "| 1111111 | 4444444 |"), 1,
             "MISSED change: round 1 reviewed '4444444'"),
            ("missed-other-base", CASE, rec.replace("| 1111111 | 2222222 |", "| 5555555 | 2222222 |"), 1,
             "MISSED change: round 1 diffed from '5555555'"),
            ("no-base-in-case", CASE.replace("Base: 1111111\n", ""), rec.replace("| 1111111 | 2222222 |", "| 5555555 | 2222222 |"),
             0, "CAUGHT"),
            ("missed-malformed-record", CASE, rec.replace("src/queue.py:9", "src/queue.py"), 1,
             "MISSED shape: the record is not a review record"),
            ("missed-no-rounds", CASE, rec.split("## Rounds")[0] + "## Findings\n", 1, "MISSED shape"),
            ("case-no-change", CASE.replace("Change: 2222222", "Change: <the commit>"), rec, 2, "Change: '<the commit>' is not a commit id"),
            ("case-no-bug-line", CASE.replace("Bug: src/queue.py:41", "Bug: src/queue.py"), rec, 2, "Bug: 'src/queue.py' is not path:line"),
            ("case-bug-outside-root", CASE.replace("Bug: src/queue.py:41", "Bug: ../queue.py:41"), rec, 2, "is not path:line under the root"),
            ("case-no-fix", CASE.replace("Fix: 9999999 reverts it", "Fix: —"), rec, 2, "Fix: names no fix"),
            ("case-key-twice", CASE.replace("Bug: src/queue.py:41", "Bug: src/queue.py:41\nBug: src/queue.py:90"), rec, 2,
             "names Bug: twice"),
            ("case-keys-after-rule-ignored", CASE.replace("Change: 2222222\n", "") + "Change: 2222222\n", rec, 2,
             "Change: '' is not a commit id"),
        ]
        for name, case, record, want_rc, want_text in cases:
            total += 1
            rc, out = run(write(name + ".case.md", case), write(name + ".review.md", record))
            codes.add(rc)
            text = "\n".join(out)
            if rc == want_rc and want_text in text:
                held += 1
                print("  ok   %s (exit %d)" % (name, rc))
            else:
                print("  FAIL %s: exit %d, wanted %d with %r\n%s" % (name, rc, want_rc, want_text, text))
        extra = [
            ("absent-record", lambda: run(write("e.case.md", CASE), os.path.join(tmp, "gone.md")), 2, "cannot read"),
            ("template-placeholders-refused",
             lambda: run(os.path.join(HERE, "..", "templates", "reviewer-case.md"), write("t.review.md", rec)), 2,
             "is not a commit id"),
        ]
        for name, fn, want_rc, want_text in extra:
            total += 1
            rc, out = fn()
            codes.add(rc)
            text = "\n".join(out)
            if rc == want_rc and want_text in text:
                held += 1
                print("  ok   %s (exit %d)" % (name, rc))
            else:
                print("  FAIL %s: exit %d, wanted %d with %r\n%s" % (name, rc, want_rc, want_text, text))
        for name, argv in (("no-record", ["--case", write("u.case.md", CASE)]), ("stray-operand", ["x.md"])):
            total += 1
            proc = subprocess.run([sys.executable, os.path.abspath(__file__)] + argv, capture_output=True, text=True, check=False)
            codes.add(proc.returncode)
            if proc.returncode == 2 and "usage" in proc.stderr:
                held += 1
                print("  ok   %s (exit 2)" % name)
            else:
                print("  FAIL %s: exit %d, stderr %r" % (name, proc.returncode, proc.stderr))
        total += 1
        wf = os.path.join(HERE, "..", "templates", "agent-evals.yml")
        try:
            with open(wf, encoding="utf-8") as fh:
                wtext = fh.read()
        except OSError as exc:
            wtext = ""
            print("  FAIL agent-evals-rescores-on-review-md: %s" % exc)
        m = re.search(r"^  pull_request:\n    paths: \[([^\]]*)\]", wtext, re.M)
        triggers = [p.strip().strip("'\"") for p in m.group(1).split(",")] if m else []
        if "REVIEW.md" in triggers and "score-reviewer-case.py" in wtext and "evals/reviewer/*.md" in wtext:
            held += 1
            print("  ok   agent-evals-rescores-on-review-md (templates/agent-evals.yml)")
        elif wtext:
            print("  FAIL agent-evals-rescores-on-review-md: pull_request paths %r" % triggers)
    documented = documented_codes()
    print("    exit codes reached: %s   documented: %s" % (" ".join(str(c) for c in sorted(codes)), " ".join(str(c) for c in documented)))
    print("    NOT ASSERTED: that the reviewer the workflow runs is the one installed, that a case's bug is the real one, or a run on a GitHub runner")
    print("score-reviewer-case selftest: %d of %d cases held" % (held, total))
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
    case = record = None
    while args:
        a = args.pop(0)
        if a == "--case" and args:
            case = args.pop(0)
        elif a == "--record" and args:
            record = args.pop(0)
        else:
            case = record = None
            break
    if not case or not record:
        sys.stderr.write(USAGE)
        return 2
    rc, out = run(resolve(case), resolve(record))
    stream = sys.stderr if rc == 2 else sys.stdout
    for line in out:
        stream.write(line + "\n")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
