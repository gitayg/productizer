#!/usr/bin/env python3
"""check-skill-body.py [SKILL_MD] [--selftest] [--version] [--help]

Static assertions over the spec skill's body, the SKILL.md a model loads whole
every time the skill triggers. With no argument it reads the SKILL.md one
directory above this script; a relative SKILL_MD is read under the repository
root (the git top level of the working directory), an absolute one as given.
The skill directory is the directory that holds SKILL_MD.

WHY THIS EXISTS (B162). The body went from 35,461 bytes to 12,586 when the
stage detail moved into references/stage-*.md and references/scripts.md, which
the body names at the stage that needs them (R153). One edit can undo that
while every other check stays green: a section pasted back in, a reference
renamed so the body names a file that is not there, or a stage reference left
without the instruction to read it first.

WHAT IT ASSERTS, each a separate finding:
  body-size      SKILL_MD is at most 13,000 bytes, frontmatter included
  paths-resolve  every references/, scripts/ or templates/ path the body
                 names, as a file name with an extension, exists under the
                 skill directory. A path preceded by a word, a dot, a slash or
                 a hyphen is another tree's (.claude/productizer/templates/,
                 ~/.claude/skills/spec/scripts/) and is not read
  stage-read-before
                 every references/stage-*.md the body names has the word
                 "before" or "Before" on the same line or the line above it

WHAT IT DOES NOT. It reads text. It cannot tell whether a model opens a named
reference when it enters a stage, whether the reference says what the body
promises, or whether anything that left the body is still said somewhere.

Exit codes:
  0  every assertion held
  1  at least one finding, each printed with its assertion
  2  could not run: bad usage, or SKILL_MD absent or unreadable
--selftest runs its cases in a temporary directory and over the real SKILL.md,
and exits 0 when every case held, 1 otherwise.
"""
import os
import re
import subprocess
import sys
import tempfile

VERSION = "check-skill-body 1.0"
MAX_BYTES = 13000
ASSERTIONS = ("body-size", "paths-resolve", "stage-read-before")
PATH_RE = re.compile(r"(?<![\w./-])((?:references|scripts|templates)/[A-Za-z0-9_.-]+\.[a-z]+)")
STAGE_RE = re.compile(r"(?<![\w./-])references/stage-[A-Za-z0-9_.-]+\.md")
BEFORE_RE = re.compile(r"\b[Bb]efore\b")
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(os.path.dirname(HERE), "SKILL.md")


def check(path):
    """Return (exit code, lines to print)."""
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
        text = raw.decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return 2, ["check-skill-body: cannot read %s: %s" % (path, exc)]
    skill_dir = os.path.dirname(os.path.abspath(path))
    lines = text.split("\n")
    findings = {a: [] for a in ASSERTIONS}
    if len(raw) > MAX_BYTES:
        findings["body-size"].append("%d bytes, over the %d-byte budget" % (len(raw), MAX_BYTES))
    named = sorted(set(PATH_RE.findall(text)))
    for rel in named:
        if not os.path.isfile(os.path.join(skill_dir, rel)):
            findings["paths-resolve"].append("%s names %s, which is not a file under %s" % (os.path.basename(path), rel, skill_dir))
    stage_refs = 0
    for i, line in enumerate(lines):
        for m in STAGE_RE.finditer(line):
            stage_refs += 1
            prev = lines[i - 1] if i > 0 else ""
            if not (BEFORE_RE.search(line) or BEFORE_RE.search(prev)):
                findings["stage-read-before"].append("line %d names %s with no \"before\" on it or the line above" % (i + 1, m.group(0)))
    shown = os.path.relpath(path) if os.path.abspath(path).startswith(os.getcwd() + os.sep) else path
    out = ["check-skill-body: %s, %d bytes, %d paths named, %d stage references" % (shown, len(raw), len(named), stage_refs)]
    held = 0
    for a in ASSERTIONS:
        if findings[a]:
            for f in findings[a]:
                out.append("FINDING %s: %s" % (a, f))
        else:
            held += 1
    out.append("%d of %d assertions held" % (held, len(ASSERTIONS)))
    return (0 if held == len(ASSERTIONS) else 1), out


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
    """The codes the docstring's Exit codes: block lists, in order."""
    block = __doc__.split("Exit codes:", 1)[1]
    return [int(m.group(1)) for m in re.finditer(r"^  (\d) ", block, re.M)]


def selftest():
    held = total = 0
    codes = set()
    with tempfile.TemporaryDirectory() as tmp:
        skill = os.path.join(tmp, "skill")
        for d in ("references", "scripts", "templates"):
            os.makedirs(os.path.join(skill, d))
        for f in ("references/stage-1-x.md", "references/other.md", "scripts/run.sh", "templates/t.md"):
            with open(os.path.join(skill, f), "w", encoding="utf-8") as fh:
                fh.write("x\n")
        good = ("---\nname: t\n---\n# T\n\nBefore Stage 1, read `references/stage-1-x.md`.\n"
                "Run `scripts/run.sh` with `templates/t.md`; see `references/other.md`.\n"
                "Repo copies in `.claude/productizer/templates/x.md` and "
                "`~/.claude/skills/spec/scripts/gone.sh` are another tree's.\n")

        def write(name, body):
            p = os.path.join(skill, name)
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(body)
            return p

        def pad(body, size):
            return body + "x" * (size - len(body.encode("utf-8")))

        cases = [
            ("good", write("good.md", good), 0, "3 of 3 assertions held"),
            ("size-at-budget", write("at.md", pad(good, MAX_BYTES)), 0, "13000 bytes"),
            ("size-over-budget", write("over.md", pad(good, MAX_BYTES + 1)), 1, "FINDING body-size: 13001 bytes"),
            ("missing-stage-file", write("missing.md", good.replace("stage-1-x.md", "stage-2-y.md")), 1,
             "FINDING paths-resolve: missing.md names references/stage-2-y.md"),
            ("missing-script", write("noscript.md", good.replace("scripts/run.sh", "scripts/gone.sh")), 1,
             "FINDING paths-resolve: noscript.md names scripts/gone.sh"),
            ("stage-without-before", write("nobefore.md", good.replace("Before Stage 1, read", "For Stage 1, read")), 1,
             "FINDING stage-read-before: line 6 names references/stage-1-x.md"),
            ("before-on-line-above", write("above.md", good.replace("Before Stage 1, read `references", "Before Stage 1, read\n`references")), 0,
             "3 of 3 assertions held"),
            ("before-two-lines-above", write("twoabove.md", good.replace("Before Stage 1, read `references", "Before Stage 1,\nread\n`references")), 1,
             "FINDING stage-read-before: line 8"),
            ("absent-file", os.path.join(skill, "absent.md"), 2, "cannot read"),
            ("real-skill-md", DEFAULT, 0, "3 of 3 assertions held"),
        ]
        for name, path, want_rc, want_text in cases:
            total += 1
            rc, out = check(path)
            codes.add(rc)
            text = "\n".join(out)
            if rc == want_rc and want_text in text:
                held += 1
                print("  ok   %s (exit %d)" % (name, rc))
            else:
                print("  FAIL %s: exit %d, wanted %d with %r\n%s" % (name, rc, want_rc, want_text, text))
        total += 1
        proc = subprocess.run([sys.executable, os.path.abspath(__file__), "--bogus"], capture_output=True, text=True, check=False)
        codes.add(proc.returncode)
        if proc.returncode == 2 and "usage" in proc.stderr:
            held += 1
            print("  ok   bad-usage (exit 2)")
        else:
            print("  FAIL bad-usage: exit %d, stderr %r" % (proc.returncode, proc.stderr))
    documented = documented_codes()
    print("    exit codes reached: %s   documented: %s" % (" ".join(str(c) for c in sorted(codes)), " ".join(str(c) for c in documented)))
    print("    NOT ASSERTED: that a model opens a named reference when it enters a stage, or that the references say what the body promises")
    print("check-skill-body selftest: %d of %d cases held" % (held, total))
    return 0 if held == total and codes == set(documented) else 1


def main(argv):
    args = argv[1:]
    if args == ["--version"]:
        print(VERSION)
        return 0
    if args in (["--help"], ["-h"]):
        print(__doc__)
        return 0
    if args == ["--selftest"]:
        return selftest()
    if len(args) > 1 or (args and args[0].startswith("-")):
        sys.stderr.write("usage: check-skill-body.py [SKILL_MD] [--selftest] [--version] [--help]\n")
        return 2
    rc, out = check(resolve(args[0]) if args else DEFAULT)
    stream = sys.stderr if rc == 2 else sys.stdout
    for line in out:
        stream.write(line + "\n")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
