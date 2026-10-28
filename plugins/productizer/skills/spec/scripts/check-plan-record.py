#!/usr/bin/env python3
"""check-plan-record.py [--kind plan|pr-body] FILE... [--selftest] [--version] [--help]

Static assertions over a change's plan (templates/plan.md), or over a pull
request body (templates/pull-request.md) saved to a file. A relative FILE is
read under the repository root (the git top level of the working directory),
an absolute one as given. --kind defaults to plan.

WHY THIS EXISTS (B168). Neither the plan nor the pull request said how the
change was tested or how to undo it, so a reviewer could not ask the second
question until it was needed. An agent may draft both answers; the author stays
responsible for them. A missing answer is a property of the text, so it is
checked on the text.

WHAT IT ASSERTS, each a separate finding:
  tested    the plan has a `Proof` section, or the body a `How it was tested`
            section, holding a line that is not the template's placeholder
  revert    the plan has a `Revert` section, or the body a `How to revert`
            section, holding a line that is not the template's placeholder
A section is a line holding only its name, with or without a leading `#`s, and
runs to the next such line of any section the template names. A section holds
only a placeholder when, with every `<...>` removed (across lines too), each of
its lines, less a leading `-`, `*` or `1.`, is empty, `—` or `-`.

WHAT IT DOES NOT. It reads text. It cannot tell whether the tests named were
run, whether they test the change, or whether the revert path works.

Exit codes:
  0  every assertion held in every file
  1  at least one finding, each printed with its assertion and file
  2  could not run: bad usage, or a file absent or unreadable
--selftest runs its cases in a temporary directory and over the shipped
templates, and exits 0 when every case held, 1 otherwise.
"""
import os
import re
import subprocess
import sys
import tempfile

VERSION = "check-plan-record 1.0"
ASSERTIONS = ("tested", "revert")
KINDS = {
    "plan": {"headings": ("Files that change", "Order of work", "Risks", "Proof", "Revert"),
             "tested": "Proof", "revert": "Revert"},
    "pr-body": {"headings": ("What changed", "How it was tested", "How to revert", "Spec delta"),
                "tested": "How it was tested", "revert": "How to revert"},
}
PLACEHOLDER_RE = re.compile(r"<[^<>]*>")
EMPTY_RE = re.compile(r"^(?:[-*]|\d+\.)?\s*(?:—|-)?\s*$")
USAGE = "usage: check-plan-record.py [--kind plan|pr-body] FILE... [--selftest] [--version] [--help]\n"


def sections(text, headings):
    names = dict((h.lower(), h) for h in headings)
    out, cur = {}, None
    for line in text.split("\n"):
        m = re.match(r"^#*\s*(.+?)\s*$", line)
        key = m.group(1).lower() if m else ""
        if key in names:
            cur = names[key]
            out.setdefault(cur, [])
        elif cur is not None:
            out[cur].append(line)
    return out


def check_text(text, kind):
    spec = KINDS[kind]
    secs = sections(text, spec["headings"])
    f = {}
    for a in ASSERTIONS:
        name = spec[a]
        if name not in secs:
            f[a] = "no `%s` section" % name
        elif all(EMPTY_RE.match(line.strip()) for line in PLACEHOLDER_RE.sub("", "\n".join(secs[name])).split("\n")):
            f[a] = "the `%s` section holds only a placeholder" % name
    return f


def run(kind, files):
    out = ["check-plan-record: kind %s" % kind]
    texts = []
    for p in files:
        try:
            with open(p, "rb") as fh:
                texts.append((p, fh.read().decode("utf-8")))
        except (OSError, UnicodeDecodeError) as exc:
            return 2, out + ["check-plan-record: cannot read %s: %s" % (p, exc)]
    ok = True
    for p, text in texts:
        p = shown(p)
        f = check_text(text, kind)
        for a in ASSERTIONS:
            if a in f:
                out.append("FINDING %s: %s: %s" % (a, p, f[a]))
        out.append("%s: %d of %d assertions held" % (p, len(ASSERTIONS) - len(f), len(ASSERTIONS)))
        out.append("examined %s" % p)
        ok = ok and not f
    return (0 if ok else 1), out


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


PLAN = """# Implementation plan: retry queue

Files that change
- src/queue.py - a bounded retry queue

Order of work
1. Write the failing test.

Risks
- A permanent error retried forever.

Proof
- tests/test_queue.py::test_stops_after_five; `make test`

Revert
- git revert the merge commit; the queue table is new and is dropped by migration 0042's down step.
"""

BODY = """## What changed
A bounded retry queue (R41).

## How it was tested
`make test`: 212 passed, including tests/test_queue.py::test_stops_after_five.

## How to revert
Revert the merge commit, then run migration 0042 down.
"""


def selftest():
    held = total = 0
    codes = set()
    tpl = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "templates")
    with tempfile.TemporaryDirectory() as tmp:
        def write(name, body):
            p = os.path.join(tmp, name)
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(body)
            return p

        cases = [
            ("plan-good", "plan", [write("p1.md", PLAN)], 0, "2 of 2 assertions held"),
            ("plan-headed", "plan", [write("p2.md", PLAN.replace("Proof\n", "## Proof\n").replace("Revert\n", "### Revert\n"))], 0,
             "2 of 2 assertions held"),
            ("plan-no-revert", "plan", [write("p3.md", PLAN.split("Revert\n")[0])], 1, "FINDING revert: %s: no `Revert` section" % os.path.join(tmp, "p3.md")),
            ("plan-placeholder-revert", "plan", [write("p4.md", PLAN.split("Revert\n")[0] + "Revert\n- <how to undo it>\n")], 1,
             "the `Revert` section holds only a placeholder"),
            ("plan-empty-revert", "plan", [write("p5.md", PLAN.split("Revert\n")[0] + "Revert\n\n—\n")], 1,
             "the `Revert` section holds only a placeholder"),
            ("plan-no-proof", "plan", [write("p6.md", PLAN.replace("Proof\n- tests/test_queue.py::test_stops_after_five; `make test`\n", ""))], 1,
             "FINDING tested: "),
            ("plan-proof-runs-into-revert", "plan", [write("p7.md", PLAN.replace("- tests/test_queue.py::test_stops_after_five; `make test`\n", ""))], 1,
             "FINDING tested: "),
            ("body-good", "pr-body", [write("b1.md", BODY)], 0, "2 of 2 assertions held"),
            ("body-no-tested", "pr-body", [write("b2.md", BODY.replace("## How it was tested", "## Notes"))], 1, "no `How it was tested` section"),
            ("body-placeholder-revert", "pr-body", [write("b3.md", BODY.split("## How to revert")[0] + "## How to revert\n<the steps>\n")], 1,
             "FINDING revert: "),
            ("plan-as-body", "pr-body", [write("b4.md", PLAN)], 1, "FINDING tested: "),
            ("two-files-one-bad", "plan", [write("p8.md", PLAN), write("p9.md", PLAN.split("Revert\n")[0])], 1, "examined %s" % os.path.join(tmp, "p8.md")),
            ("plan-template-is-placeholder", "plan", [os.path.join(tpl, "plan.md")], 1, "the `Revert` section holds only a placeholder"),
            ("body-template-is-placeholder", "pr-body", [os.path.join(tpl, "pull-request.md")], 1, "the `How to revert` section holds only a placeholder"),
            ("absent-file", "plan", [os.path.join(tmp, "gone.md")], 2, "cannot read"),
        ]
        for name, kind, files, want_rc, want_text in cases:
            total += 1
            rc, out = run(kind, files)
            codes.add(rc)
            text = "\n".join(out)
            if rc == want_rc and want_text in text:
                held += 1
                print("  ok   %s (exit %d)" % (name, rc))
            else:
                print("  FAIL %s: exit %d, wanted %d with %r\n%s" % (name, rc, want_rc, want_text, text))
        for name, argv in (("no-files", []), ("bad-kind", ["--kind", "ticket", write("p10.md", PLAN)])):
            total += 1
            proc = subprocess.run([sys.executable, os.path.abspath(__file__)] + argv, capture_output=True, text=True, check=False)
            codes.add(proc.returncode)
            if proc.returncode == 2 and "usage" in proc.stderr:
                held += 1
                print("  ok   %s (exit 2)" % name)
            else:
                print("  FAIL %s: exit %d, stderr %r" % (name, proc.returncode, proc.stderr))
    documented = documented_codes()
    print("    exit codes reached: %s   documented: %s" % (" ".join(str(c) for c in sorted(codes)), " ".join(str(c) for c in documented)))
    print("    NOT ASSERTED: that the tests named were run, that they test the change, or that the revert path works")
    print("check-plan-record selftest: %d of %d cases held" % (held, total))
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
    kind, files = "plan", []
    while args:
        a = args.pop(0)
        if a == "--kind" and args:
            kind = args.pop(0)
        elif a.startswith("--kind="):
            kind = a.split("=", 1)[1]
        elif a.startswith("-"):
            files = []
            break
        else:
            files.append(a)
    if kind not in KINDS or not files:
        sys.stderr.write(USAGE)
        return 2
    rc, out = run(kind, [resolve(f) for f in files])
    stream = sys.stderr if rc == 2 else sys.stdout
    for line in out:
        stream.write(line + "\n")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
