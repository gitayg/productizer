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

AND WHY A BODY CARRIES PROOF (B184). Tests that pass say the code does what
its tests say. A reviewer still has to read the diff to learn whether the
change does what was asked. A body's `Proof it works` shows it: what a person
sees when they use the change the way a user would meet it, each item naming
the requirement or intent it answers and carrying the evidence - a screenshot,
a recording, a log, a link to a run's artifact. The lifecycle checks the proof
is there and says what it answers; it does not produce it.

WHAT IT ASSERTS, each a separate finding:
  tested    the plan has a `Proof` section, or the body a `How it was tested`
            section, holding a line that is not the template's placeholder
  proof     (--kind pr-body) the body has a `Proof it works` section that
            holds either list items, each naming a requirement id `R<n>`, a
            backlog id `B<n>` or an issue `#<n>` and carrying evidence - a
            link, an image or a closed fenced block holding a line - or else
            only the line `**n/a** - <reason>`, the reason not empty
  revert    the plan has a `Revert` section, or the body a `How to revert`
            section, holding a line that is not the template's placeholder
A section is a line holding only its name, with or without a leading `#`s, and
runs to the next such line of any section the template names - `Open
questions` and `Decisions` included, so a placeholder `Revert` above them is
still a placeholder (B185). A section holds
only a placeholder when, with every `<...>` removed (across lines too), each of
its lines, less a leading `-`, `*` or `1.`, is empty, `—` or `-`. In `Proof it
works` an `<img ...>`, a `<video ...>` and an `<https://...>` are evidence, not
placeholders. A proof item is a line starting `-`, `*` or `1.` at the left
margin, outside a fence, and the lines under it up to the next; an id is read
outside its fences, and an `n/a` line stands alone in its section.

WHAT IT DOES NOT. It reads text. It cannot tell whether the tests named were
run, whether they test the change, or whether the revert path works; nor a
real screenshot from a wrong one, whether a link opens, or whether what the
evidence shows is what the request asked.

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

VERSION = "check-plan-record 1.2"
KINDS = {
    "plan": {"headings": ("Open questions", "Decisions", "Files that change", "Order of work", "Risks", "Proof", "Revert"),
             "assertions": ("tested", "revert"), "tested": "Proof", "revert": "Revert"},
    "pr-body": {"headings": ("What changed", "How it was tested", "Proof it works", "How to revert", "Spec delta"),
                "assertions": ("tested", "proof", "revert"),
                "tested": "How it was tested", "proof": "Proof it works", "revert": "How to revert"},
}
PLACEHOLDER_RE = re.compile(r"<[^<>]*>")
EMPTY_RE = re.compile(r"^(?:[-*]|\d+\.)?\s*(?:—|-)?\s*$")
EVIDENCE_TAG_RE = re.compile(r"<(?:(?:img|video)\b|https?://)")
ITEM_RE = re.compile(r"^(?:[-*]|\d+\.)(?:\s|$)")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
ID_RE = re.compile(r"\b[RB]\d+\b|(?<![\w&])#\d+\b")
LINK_RE = re.compile(r"https?://\S|\]\((?!#)[^()\s]+\)|<(?:img|video)\b[^<>]*\bsrc=")
NA_RE = re.compile(r"^\*\*n/a\*\*")
NA_SHAPE_RE = re.compile(r"^\*\*n/a\*\* - \S")
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


def placeholder_only(lines):
    return all(EMPTY_RE.match(line.strip()) for line in lines)


def closes(line, fence):
    return line.strip().startswith(fence) and not line.strip().strip("`~")


def proof_items(lines):
    """A proof section's items, each a list of (line, inside a fence) pairs.
    A list marker inside a fence starts no item."""
    items, fence = [], None
    for line in lines:
        if fence is None and ITEM_RE.match(line):
            items.append([])
        opens = FENCE_RE.match(line) if fence is None else None
        if items:
            items[-1].append((line, fence is not None or opens is not None))
        if opens:
            fence = opens.group(1)
        elif fence is not None and closes(line, fence):
            fence = None
    return items


def fenced_log(item):
    fence, body = None, False
    for line, _ in item:
        if fence is None:
            m = FENCE_RE.match(line)
            if m:
                fence, body = m.group(1), False
        elif closes(line, fence):
            if body:
                return True
            fence = None
        elif line.strip():
            body = True
    return False


def check_proof(lines):
    lines = PLACEHOLDER_RE.sub(lambda m: m.group(0) if EVIDENCE_TAG_RE.match(m.group(0)) else "", "\n".join(lines)).split("\n")
    if placeholder_only(lines):
        return ["the `Proof it works` section holds only a placeholder"]
    filled = [line.strip() for line in lines if line.strip()]
    if any(NA_RE.match(line) for line in filled):
        if not any(NA_SHAPE_RE.match(line) for line in filled):
            return ["the `n/a` line is not `**n/a** - <reason>` with a reason"]
        if len(filled) > 1:
            return ["an `**n/a** - <reason>` line stands alone in `Proof it works`; this section holds more beside it"]
        return []
    items = proof_items(lines)
    if not items:
        return ["the `Proof it works` section holds no proof item (a line starting `-`, `*` or `1.`) and no `**n/a** - <reason>` line"]
    out = []
    for n, item in enumerate(items, 1):
        head = item[0][0].strip()[:60]
        if not any(ID_RE.search(line) for line, fenced in item if not fenced):
            out.append("proof item %d names no requirement id (R<n>), backlog id (B<n>) or issue (#<n>): %s" % (n, head))
        if not (any(LINK_RE.search(line) for line, _ in item) or fenced_log(item)):
            out.append("proof item %d carries no evidence - a link, an image or a fenced log: %s" % (n, head))
    return out


def check_text(text, kind):
    spec = KINDS[kind]
    secs = sections(text, spec["headings"])
    f = {}
    for a in spec["assertions"]:
        name = spec[a]
        if name not in secs:
            f[a] = ["no `%s` section" % name]
        elif a == "proof":
            msgs = check_proof(secs[name])
            if msgs:
                f[a] = msgs
        elif placeholder_only(PLACEHOLDER_RE.sub("", "\n".join(secs[name])).split("\n")):
            f[a] = ["the `%s` section holds only a placeholder" % name]
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
        names = KINDS[kind]["assertions"]
        for a in names:
            for msg in f.get(a, []):
                out.append("FINDING %s: %s: %s" % (a, p, msg))
        out.append("%s: %d of %d assertions held" % (p, len(names) - len(f), len(names)))
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

## Proof it works
- R41: a job that fails five times leaves the queue and lands in the dead-letter list.
  ![dead-letter list after five failures](https://example.invalid/proof/dead-letter.png)

## How to revert
Revert the merge commit, then run migration 0042 down.
"""

PROOF = BODY.split("## Proof it works\n")[0] + "## Proof it works\n%s\n## How to revert\n" + BODY.split("## How to revert\n")[1]

FENCED = """- R41, on the staging queue:
```
* worker 3: job 17 failed (5 of 5)
- job 17 moved to dead-letter
```
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
            ("plan-revert-runs-into-decisions", "plan", [write("p11.md", PLAN.split("Revert\n")[0] + "Revert\n- <how to undo it>\n\n"
             "Decisions\n- Q1: How many retries?\n  Decided: B - five, with backoff\n")], 1,
             "the `Revert` section holds only a placeholder"),
            ("plan-proof-runs-into-revert", "plan", [write("p7.md", PLAN.replace("- tests/test_queue.py::test_stops_after_five; `make test`\n", ""))], 1,
             "FINDING tested: "),
            ("body-good", "pr-body", [write("b1.md", BODY)], 0, "3 of 3 assertions held"),
            ("body-no-proof", "pr-body", [write("b5.md", BODY.replace("## Proof it works", "## Notes"))], 1,
             "FINDING proof: %s: no `Proof it works` section" % os.path.join(tmp, "b5.md")),
            ("body-placeholder-proof", "pr-body", [write("b6.md", PROOF % "<what a person sees,\nand the evidence>")], 1,
             "the `Proof it works` section holds only a placeholder"),
            ("body-empty-proof", "pr-body", [write("b7.md", PROOF % "\n-\n")], 1, "the `Proof it works` section holds only a placeholder"),
            ("proof-item-no-id", "pr-body", [write("b8.md", PROOF % "- the dead-letter list https://example.invalid/run/9")], 1,
             "proof item 1 names no requirement id"),
            ("proof-item-no-evidence", "pr-body", [write("b9.md", PROOF % "- R41: it works on staging")], 1,
             "proof item 1 carries no evidence"),
            ("proof-anchor-is-no-evidence", "pr-body", [write("b10.md", PROOF % "- R41: see [the tests](#how-it-was-tested)")], 1,
             "proof item 1 carries no evidence"),
            ("proof-second-item-bad", "pr-body", [write("b11.md", PROOF % "- R41 https://example.invalid/run/9\n- B7: the retry banner")], 1,
             "proof item 2 carries no evidence"),
            ("proof-fenced-log", "pr-body", [write("b12.md", PROOF % FENCED)], 0, "3 of 3 assertions held"),
            ("proof-empty-fence-is-no-evidence", "pr-body", [write("b13.md", PROOF % "- R41, on staging:\n```\n\n```")], 1,
             "proof item 1 carries no evidence"),
            ("proof-unclosed-fence-is-no-evidence", "pr-body", [write("b14.md", PROOF % "- R41, on staging:\n```\njob 17 moved")], 1,
             "proof item 1 carries no evidence"),
            ("proof-id-only-in-a-log-is-not-named", "pr-body", [write("b15.md", PROOF % FENCED.replace("R41, on", "on").replace("dead-letter", "dead-letter, R41"))], 1,
             "proof item 1 names no requirement id"),
            ("proof-img-tag", "pr-body", [write("b16.md", PROOF % '- #42: <img alt="banner" src="https://example.invalid/a.png">')], 0,
             "3 of 3 assertions held"),
            ("proof-relative-image", "pr-body", [write("b17.md", PROOF % "1. B7: ![banner](docs/proof/banner.png)")], 0, "3 of 3 assertions held"),
            ("proof-no-item", "pr-body", [write("b18.md", PROOF % "R41 works: https://example.invalid/run/9")], 1, "holds no proof item"),
            ("proof-na", "pr-body", [write("b19.md", PROOF % "**n/a** - a rename inside the queue module; nothing a user meets changed")], 0,
             "3 of 3 assertions held"),
            ("proof-na-no-reason", "pr-body", [write("b20.md", PROOF % "**n/a** - ")], 1, "is not `**n/a** - <reason>` with a reason"),
            ("proof-na-placeholder-reason", "pr-body", [write("b21.md", PROOF % "**n/a** - <the reason>")], 1,
             "is not `**n/a** - <reason>` with a reason"),
            ("proof-na-beside-an-item", "pr-body", [write("b22.md", PROOF % "**n/a** - internal\n- R41 https://example.invalid/run/9")], 1,
             "stands alone in `Proof it works`"),
            ("proof-not-applicable-is-no-na", "pr-body", [write("b23.md", PROOF % "Not applicable: internal")], 1, "holds no proof item"),
            ("body-no-tested", "pr-body", [write("b2.md", BODY.replace("## How it was tested", "## Notes"))], 1, "no `How it was tested` section"),
            ("body-placeholder-revert", "pr-body", [write("b3.md", BODY.split("## How to revert")[0] + "## How to revert\n<the steps>\n")], 1,
             "FINDING revert: "),
            ("plan-as-body", "pr-body", [write("b4.md", PLAN)], 1, "FINDING tested: "),
            ("two-files-one-bad", "plan", [write("p8.md", PLAN), write("p9.md", PLAN.split("Revert\n")[0])], 1, "examined %s" % os.path.join(tmp, "p8.md")),
            ("plan-template-is-placeholder", "plan", [os.path.join(tpl, "plan.md")], 1, "the `Revert` section holds only a placeholder"),
            ("body-template-is-placeholder", "pr-body", [os.path.join(tpl, "pull-request.md")], 1, "the `How to revert` section holds only a placeholder"),
            ("body-template-proof-is-placeholder", "pr-body", [os.path.join(tpl, "pull-request.md")], 1,
             "the `Proof it works` section holds only a placeholder"),
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
    print("    NOT ASSERTED: that the tests named were run, that they test the change, or that the revert path works; that a"
          " proof's evidence is real, opens, or shows what the request asked")
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
