#!/usr/bin/env python3
"""check-revert-cases.py --base REF [--cases DIR] [--selftest] [--version] [--help]

Does every revert in a change come with a reviewer case? Reads the commits in
REF..HEAD of the git work tree of the working directory, and the case files
(templates/reviewer-case.md) under DIR, default `evals/reviewer` relative to
the repository root.

WHY THIS EXISTS (B170). A revert is a confirmed miss: the change shipped a bug
the review did not stop. The maintainer ruled on 2026-10-28 that each one
becomes a reviewer eval case, and that a revert landing without one is a
blocking finding, so the corpus grows from this repository's own failures and
not from whoever remembers to add one.

WHAT A REVERT IS: a commit whose message holds a line `This reverts commit
<id>`, as `git revert` writes it, the id 7 to 40 hex digits. One commit may
name several. The same reading is loaded by band-revert-rate.py.

WHAT IT ASSERTS, each a separate finding:
  case-shape    every case file under DIR names a Change, a Bug and a Fix as
                score-reviewer-case.py reads them (loaded by path)
  no-case       every commit a revert in the range names is the Change of a
                case under DIR, compared as prefixes
The case may land in the same change as the revert: the cases are read from
the working tree, not from the revert's own commit.

WHAT IT DOES NOT. An incident has no commit to find it by, so a missing
incident case is not seen. A revert made by hand, with no such line, is not a
revert to it. Whether the case's bug location is the real one is a person's to
judge.

Exit codes:
  0  every revert in the range has a case, and every case is well formed
  1  at least one finding, each printed
  2  could not run: bad usage, not a git work tree, a base git cannot resolve,
     or score-reviewer-case.py not loadable beside it
--selftest runs its cases in temporary repositories, and exits 0 when every
case held, 1 otherwise.
"""
import glob
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

VERSION = "check-revert-cases 1.0"
HERE = os.path.dirname(os.path.abspath(__file__))
SCORER = os.path.join(HERE, "score-reviewer-case.py")
REVERT_RE = re.compile(r"^[ \t]*This reverts commit ([0-9a-fA-F]{7,40})\b", re.M)
USAGE = "usage: check-revert-cases.py --base REF [--cases DIR] [--selftest] [--version] [--help]\n"


class Refused(Exception):
    pass


def reverted_ids(message):
    """The commit ids a commit message says it reverts."""
    return [m.group(1).lower() for m in REVERT_RE.finditer(message)]


def git(args, cwd):
    try:
        p = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True, check=False)
    except OSError as exc:
        raise Refused("git could not run: %s" % exc)
    if p.returncode != 0:
        raise Refused("git %s: %s" % (" ".join(args), p.stderr.strip()))
    return p.stdout


def scorer():
    try:
        spec = importlib.util.spec_from_file_location("score_reviewer_case", SCORER)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod, mod.record_rules()
    except (OSError, SyntaxError, AttributeError) as exc:
        raise Refused("could not load %s: %s" % (SCORER, exc))
    except Exception as exc:
        if type(exc).__name__ == "Refused":
            raise Refused(str(exc))
        raise


def run(base, cases_dir, cwd):
    """(exit code, lines)."""
    out = []
    try:
        root = git(["rev-parse", "--show-toplevel"], cwd).strip()
        git(["rev-parse", "--verify", "--quiet", base + "^{commit}"], cwd)
        log = git(["log", "--format=%H%x00%B%x1e", base + "..HEAD"], cwd)
        src, crr = scorer()
    except Refused as exc:
        return 2, ["check-revert-cases: %s. Nothing was checked." % exc]
    cdir = cases_dir if os.path.isabs(cases_dir) else os.path.join(root, cases_dir)
    shown_dir = os.path.relpath(cdir, root)
    findings = []
    changes = []
    paths = sorted(glob.glob(os.path.join(cdir, "*.md")))
    for p in paths:
        rel = os.path.relpath(p, root)
        text, err = crr.read(p)
        if text is None:
            findings.append("case-shape: %s cannot be read: %s" % (rel, err))
            continue
        try:
            case = src.parse_case(text, crr)
        except Exception as exc:
            if type(exc).__name__ != "Refused":
                raise
            findings.append("case-shape: %s: %s" % (rel, exc))
            continue
        changes.append((case["Change"].lower(), rel))
    commits = [c for c in log.split("\x1e") if c.strip()]
    reverts = 0
    for c in commits:
        sha, _, msg = c.strip("\n").partition("\x00")
        for rid in reverted_ids(msg):
            reverts += 1
            hits = [rel for ch, rel in changes if ch.startswith(rid) or rid.startswith(ch)]
            if hits:
                out.append("revert %s of %s: case %s" % (sha[:12], rid, ", ".join(hits)))
            else:
                findings.append("no-case: commit %s reverts %s and no case under %s/ names it as its Change"
                                % (sha[:12], rid, shown_dir))
    out.insert(0, "check-revert-cases: examined %d commit(s) in %s..HEAD, %d revert(s), %d case(s) under %s/"
               % (len(commits), base, reverts, len(paths), shown_dir))
    out += ["FINDING %s" % f for f in findings]
    return (1 if findings else 0), out


def documented_codes():
    block = __doc__.split("Exit codes:", 1)[1]
    return [int(m.group(1)) for m in re.finditer(r"^  (\d) ", block, re.M)]


def case_text(change):
    return ("# Reviewer case - x\n\nSource: revert\nChange: %s\nBug: src/a.py:3\nClass: c\nFix: the revert\n\n---\n"
            % change)


def selftest():
    held = total = 0
    codes = set()
    with tempfile.TemporaryDirectory() as tmp:
        def sh(repo, *args):
            subprocess.run(["git"] + list(args), cwd=repo, check=True, capture_output=True, text=True)
            if args[0] not in ("commit", "revert", "rev-parse"):
                return ""
            return subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, check=True,
                                  capture_output=True, text=True).stdout.strip()

        def repo(name):
            r = os.path.join(tmp, name)
            os.makedirs(os.path.join(r, "src"))
            sh(r, "init", "-q", "-b", "main")
            sh(r, "config", "user.email", "t@example.invalid")
            sh(r, "config", "user.name", "t")
            sh(r, "config", "commit.gpgsign", "false")
            with open(os.path.join(r, "src", "a.py"), "w") as fh:
                fh.write("a\n")
            sh(r, "add", "-A")
            base = sh(r, "commit", "-q", "-m", "base")
            with open(os.path.join(r, "src", "a.py"), "a") as fh:
                fh.write("b\n")
            sh(r, "add", "-A")
            bad = sh(r, "commit", "-q", "-m", "add b")
            sh(r, "revert", "--no-edit", bad)
            return r, base, bad

        def add_case(r, name, body):
            d = os.path.join(r, "evals", "reviewer")
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, name), "w") as fh:
                fh.write(body)

        r1, b1, bad1 = repo("no-case")
        r2, b2, bad2 = repo("with-case")
        add_case(r2, "add-b.md", case_text(bad2))
        r3, b3, bad3 = repo("short-id")
        add_case(r3, "add-b.md", case_text(bad3[:8]))
        r4, b4, bad4 = repo("other-case")
        add_case(r4, "other.md", case_text("1234567"))
        r5, b5, bad5 = repo("bad-case")
        add_case(r5, "add-b.md", case_text(bad5))
        add_case(r5, "broken.md", case_text("<the commit>"))
        r6, b6, bad6 = repo("no-revert")
        head6 = sh(r6, "rev-parse", "HEAD")
        r7, b7, bad7 = repo("indented")
        with open(os.path.join(r7, "src", "a.py"), "a") as fh:
            fh.write("c\n")
        sh(r7, "add", "-A")
        sh(r7, "commit", "-q", "-m", "squash\n\n* Revert x\n\n  This reverts commit %s.\n" % b7)
        r8, b8, bad8 = repo("mid-line")
        with open(os.path.join(r8, "src", "a.py"), "a") as fh:
            fh.write("c\n")
        sh(r8, "add", "-A")
        sh(r8, "commit", "-q", "-m", "docs\n\nA line naming `This reverts commit %s` in passing.\n" % b8)
        cases = [
            ("revert-without-case", r1, b1, 1, "FINDING no-case: commit"),
            ("revert-with-case", r2, b2, 0, "examined 2 commit(s)"),
            ("revert-with-case-named", r2, b2, 0, "case evals/reviewer/add-b.md"),
            ("case-short-id", r3, b3, 0, "case evals/reviewer/add-b.md"),
            ("case-of-another-change", r4, b4, 1, "FINDING no-case"),
            ("malformed-case", r5, b5, 1, "FINDING case-shape: evals/reviewer/broken.md"),
            ("range-excludes-revert", r6, head6, 0, "examined 0 commit(s)"),
            ("indented-line-is-a-revert", r7, bad7, 1, "reverts %s" % b7),
            ("mid-line-mention-is-not", r8, bad8, 1, "2 commit(s) in %s..HEAD, 1 revert(s)" % bad8),
            ("unresolvable-base", r1, "no-such-ref", 2, "Nothing was checked"),
            ("not-a-repo", tmp, b1, 2, "Nothing was checked"),
        ]
        for name, cwd, base, want_rc, want_text in cases:
            total += 1
            rc, out = run(base, "evals/reviewer", cwd)
            codes.add(rc)
            text = "\n".join(out)
            if rc == want_rc and want_text in text:
                held += 1
                print("  ok   %s (exit %d)" % (name, rc))
            else:
                print("  FAIL %s: exit %d, wanted %d with %r\n%s" % (name, rc, want_rc, want_text, text))
        for name, argv in (("no-base", []), ("stray-operand", ["--base", b1, "x"])):
            total += 1
            proc = subprocess.run([sys.executable, os.path.abspath(__file__)] + argv, cwd=r1,
                                  capture_output=True, text=True, check=False)
            codes.add(proc.returncode)
            if proc.returncode == 2 and "usage" in proc.stderr:
                held += 1
                print("  ok   %s (exit 2)" % name)
            else:
                print("  FAIL %s: exit %d, stderr %r" % (name, proc.returncode, proc.stderr))
    documented = documented_codes()
    print("    exit codes reached: %s   documented: %s" % (" ".join(str(c) for c in sorted(codes)), " ".join(str(c) for c in documented)))
    print("    NOT ASSERTED: an incident with no case, a revert with no `This reverts commit` line, or that a case's bug is the real one")
    print("check-revert-cases selftest: %d of %d cases held" % (held, total))
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
    base, cases = None, "evals/reviewer"
    while args:
        a = args.pop(0)
        if a == "--base" and args:
            base = args.pop(0)
        elif a == "--cases" and args:
            cases = args.pop(0)
        else:
            base = None
            break
    if not base:
        sys.stderr.write(USAGE)
        return 2
    rc, out = run(base, cases, os.getcwd())
    stream = sys.stderr if rc == 2 else sys.stdout
    for line in out:
        stream.write(line + "\n")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
