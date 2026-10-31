#!/usr/bin/env python3
"""plan-answers.py [--root DIR] [--plan PATH] [--apply] [FILE|-] [--selftest] [--version] [--help]

Validates the answers block a plan page hands back (build-plan-page.sh,
references/plan-page.md) and prints the normalised summary the agent works
from. FILE holds the block, with or without text around it; `-` or no FILE
reads standard input. --root defaults to the git top level, else the working
directory. --plan PATH also requires the block to name that plan.

WHAT IT REFUSES, each a finding:
  block    no answers block, more than one, an unclosed one, a header that is
           not `format: 1`, `plan: <path>`, `plan-sha256: <hex>`, or a line
           that is not a `decide` or a `comment` of the fixed shape
  path     a plan path that is absolute, holds `..` or a control character,
           is not a file named plan.md, is reached through a symbolic link,
           does not exist, or is not the --plan given
  stale    the plan's sha256 as it stands now is not the block's: the page was
           built from another version of the plan, so its answers are not
           applied to this one. Rebuild the page and answer again.
  question a decision for a question the plan does not hold open, one decided
           twice, an option that question does not offer, or `other` with no
           text
  anchor   a comment on a passage the plan does not hold, or quoting text that
           passage does not hold

--apply, and only then, writes the decisions into the plan's `Decisions`
section, one entry per answered question with its answer and note, and takes
those questions out of `Open questions`. It writes that one file, in place,
and no other - never the spec, never a file the block could name that is not
a plan.md. Comments are printed, never written: they are free text the agent
reads and works into the plan itself.

WHAT IT DOES NOT KNOW. Whether the person read the page; what a comment
means; whether an answer is a good one.

Exit codes:
  0  the block is valid, and with --apply its decisions were written
  1  the block was refused; every finding is printed, and nothing was written
  2  could not run: bad usage, an unreadable FILE, or a plan whose open
     questions do not follow the fixed syntax
--selftest runs its cases in a temporary directory and exits 0 when every
case held, 1 otherwise.
"""
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

VERSION = "plan-answers 1.0"
HERE = os.path.dirname(os.path.abspath(__file__))
USAGE = "usage: plan-answers.py [--root DIR] [--plan PATH] [--apply] [FILE|-] | --selftest | --version\n"


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


model = load("plan-model")


def flat(text):
    return " ".join(text.split())


def plan_file(root, rel, want):
    """(absolute path, finding or None) for the plan the block names."""
    if want is not None and os.path.normpath(want) != os.path.normpath(rel):
        return None, "the block names %s, and this run was told the plan is %s" % (rel, want)
    if os.path.isabs(rel) or re.search(r"[\x00-\x1f\x7f]", rel) or ".." in rel.split("/"):
        return None, "the block's plan path %r is not a plain path inside the repository" % rel
    if os.path.basename(rel) != "plan.md":
        return None, "the block names %s, which is not a plan.md; answers reach a plan and nothing else" % rel
    real_root = os.path.realpath(root)
    path = os.path.join(real_root, os.path.normpath(rel))
    if os.path.realpath(path) != path:
        return None, "%s is reached through a symbolic link; answers are written to a plan file itself" % rel
    if not os.path.isfile(path):
        return None, "%s does not exist" % rel
    return path, None


def validate(root, text, want=None):
    """(rc, lines, context). context is what --apply needs when rc is 0."""
    try:
        header, items = model.answers_block(text)
    except model.Malformed as exc:
        return 1, ["REFUSED block: %s" % exc], None
    rel = header["plan"]
    path, bad = plan_file(root, rel, want)
    if bad:
        return 1, ["REFUSED path: %s" % bad], None
    try:
        with open(path, "rb") as fh:
            data = fh.read()
        plan = model.parse(data.decode("utf-8").replace("\r\n", "\n"))
    except (OSError, UnicodeDecodeError) as exc:
        return 2, ["plan-answers: cannot read %s: %s" % (rel, exc.__class__.__name__)], None
    except model.Malformed as exc:
        return 2, ["plan-answers: %s: the open questions do not follow the fixed syntax: %s" % (rel, exc)], None
    now = model.sha256(data)
    if now != header["plan-sha256"]:
        return 1, ["REFUSED stale: %s has changed since the page was built (the block was built from sha256 %s, "
                   "the plan is now %s). Rebuild the page with build-plan-page.sh %s and answer again; nothing "
                   "from this block is applied." % (rel, header["plan-sha256"][:12], now[:12], rel)], None
    open_q = dict((q["id"], q) for q in plan["questions"])
    found, seen, decisions, comments = [], set(), [], []
    where = model.passages(plan)
    for it in items:
        if it["kind"] == "decide":
            q = open_q.get(it["id"])
            if q is None:
                why = "is already under Decisions" if it["id"] in plan["decided"] else "is not an open question there"
                found.append("REFUSED question: %s %s in %s" % (it["id"], why, rel))
                continue
            if it["id"] in seen:
                found.append("REFUSED question: %s is decided twice in the block" % it["id"])
                continue
            seen.add(it["id"])
            keys = dict((o["key"], o["text"]) for o in q["options"])
            if it["option"] != "other" and it["option"] not in keys:
                found.append("REFUSED question: %s offers %s; the block chose %s"
                             % (it["id"], ", ".join(sorted(keys)), it["option"]))
                continue
            decisions.append((q, it, keys.get(it["option"])))
        else:
            hit = where.get(it["anchor"])
            if hit is None:
                found.append("REFUSED anchor: %s holds no passage %s" % (rel, it["anchor"]))
                continue
            if it["quote"] and flat(it["quote"]) not in flat(hit[1]["plain"]):
                found.append("REFUSED anchor: passage %s does not hold the quoted text %r"
                             % (it["anchor"], flat(it["quote"])[:60]))
                continue
            comments.append((hit, it))
    if found:
        return 1, found + ["plan-answers: %d finding(s); nothing was applied" % len(found)], None
    out = ["plan-answers: %s at sha256 %s: the block is valid, %d decision(s) and %d comment(s)"
           % (rel, now[:12], len(decisions), len(comments))]
    for q, it, opt in decisions:
        out.append("decision %s: %s" % (q["id"], flat(q["text"])))
        out.append("  answer: %s" % entry_answer(it, opt))
        if it["option"] != "other" and it["text"]:
            out.append("  note: %s" % flat(it["text"]))
    for (sec, b), it in comments:
        out.append("comment on %s (%s): %s" % (it["anchor"], sec["title"], flat(b["plain"])[:100]))
        if it["quote"]:
            out.append("  quote: %s" % flat(it["quote"]))
        out.append("  note: %s" % it["note"].replace("\n", "\n        "))
    left = [q["id"] for q in plan["questions"] if q["id"] not in seen]
    out.append("still open: %s" % (", ".join(left) if left else "none"))
    return 0, out, {"path": path, "rel": rel, "data": data, "decisions": decisions}


def entry_answer(it, opt):
    return "other - %s" % flat(it["text"]) if it["option"] == "other" else "%s - %s" % (it["option"], flat(opt))


def apply(ctx):
    """Rewrite the plan with the decisions moved under Decisions."""
    lines = ctx["data"].decode("utf-8").split("\n")
    answered = set(q["id"] for q, _, _ in ctx["decisions"])
    heads = [i for i, line in enumerate(lines) if model.section_title(line) is not None]

    def span(name):
        for n, i in enumerate(heads):
            if model.section_title(lines[i]).lower() == name:
                return i, (heads[n + 1] if n + 1 < len(heads) else len(lines))
        return None
    keep, drop, cur = [], set(), None
    oq = span("open questions")
    if oq:
        for i in range(oq[0] + 1, oq[1]):
            m = re.match(r"^[-*]\s+(Q[1-9][0-9]{0,3}):", lines[i])
            if m or re.match(r"^(?:[-*]|\d+\.)\s", lines[i]):
                cur = m.group(1) if m else None
            if cur in answered and lines[i].strip():
                drop.add(i)
        if not any(lines[i].strip() for i in range(oq[0] + 1, oq[1]) if i not in drop):
            drop.update(range(oq[0], oq[1]))
    entries = []
    for q, it, opt in ctx["decisions"]:
        entries.append("- %s: %s" % (q["id"], flat(q["text"])))
        entries.append("  Decided: %s" % entry_answer(it, opt))
        if it["option"] != "other" and it["text"]:
            entries.append("  Note: %s" % flat(it["text"]))
    dec = span("decisions")
    if dec:
        body = [i for i in range(dec[0] + 1, dec[1]) if lines[i].strip()]
        for i in body:
            if model.placeholder_only(re.sub(r"^\s*(?:[-*]|\d+\.)\s*", "", lines[i])):
                drop.add(i)
        last = max([i for i in body if i not in drop] or [dec[0]])
        insert_at = last + 1
    else:
        insert_at = oq[1] if oq else (heads[0] if heads else len(lines))
        entries = ["Decisions"] + entries + [""]
    for i, line in enumerate(lines):
        if i == insert_at:
            keep.extend(entries)
        if i not in drop:
            keep.append(line)
    if insert_at >= len(lines):
        keep.extend(entries)
    text = "\n".join(keep)
    after = model.parse(text)
    assert not answered & set(q["id"] for q in after["questions"]) and answered <= set(after["decided"])
    with open(ctx["path"], "rb") as fh:
        if fh.read() != ctx["data"]:
            return 1, "REFUSED stale: %s changed while this ran; nothing was applied" % ctx["rel"]
    fd, tmp = tempfile.mkstemp(prefix=".plan-answers.", dir=os.path.dirname(ctx["path"]))
    with os.fdopen(fd, "wb") as fh:
        fh.write(text.encode("utf-8"))
    os.chmod(tmp, os.stat(ctx["path"]).st_mode & 0o777)
    os.replace(tmp, ctx["path"])
    return 0, ("applied: %d decision(s) written under Decisions in %s; comments are not written - work them "
               "into the plan yourself" % (len(ctx["decisions"]), ctx["rel"]))


def run(root, text, want=None, do_apply=False):
    rc, out, ctx = validate(root, text, want)
    if rc == 0 and do_apply:
        rc, line = apply(ctx)
        out.append(line)
    return rc, out


PLAN = """# Implementation plan: retry queue

Open questions
- Q1: How many retries before a job is dead-lettered?
  - A: three
  - B: five, with backoff
- Q2: Where does the dead-letter list live?
  - A: a table beside the queue
  - B: a file per day

Decisions
- <answered open questions land here, written by plan-answers.py --apply>

Files that change
- src/queue.py - a bounded retry queue (`MAX_RETRIES`)

Risks
- A permanent error retried forever.

Proof
- `make test`

Revert
- git revert the merge commit.
"""


def block(sha, *items, plan="docs/sdlc/B7/plan.md"):
    return "\n".join(["Here are my answers.", "", model.FENCE_OPEN, "format: 1", "plan: " + plan,
                      "plan-sha256: " + sha] + list(items) + [model.FENCE_CLOSE, ""])


def selftest():
    held, total, codes = 0, 0, set()
    with tempfile.TemporaryDirectory() as tmp:
        root = os.path.realpath(tmp)
        os.makedirs(os.path.join(root, "docs/sdlc/B7"))
        os.makedirs(os.path.join(root, ".claude/productizer"))
        plan_path = os.path.join(root, "docs/sdlc/B7/plan.md")
        spec_path = os.path.join(root, ".claude/productizer/spec.md")

        def reset(text=PLAN):
            with open(plan_path, "w") as fh:
                fh.write(text)
            with open(spec_path, "w") as fh:
                fh.write("# spec\n")
            return model.sha256(text.encode())
        sha = reset()
        os.makedirs(os.path.join(root, "docs/sdlc/link"))
        os.symlink("../B7/plan.md", os.path.join(root, "docs/sdlc/link/plan.md"))
        spec_sha = model.sha256(b"# spec\n")
        good = block(sha, 'decide Q1 B "with a cap of 60s"',
                     'comment risks/1 "retried forever" "say how a permanent error is told apart"',
                     'comment files-that-change/1 "" "name the test file too"')
        cases = [
            ("valid", good, None, 0, "the block is valid, 1 decision(s) and 2 comment(s)"),
            ("valid-says-still-open", good, None, 0, "still open: Q2"),
            ("valid-other", block(sha, 'decide Q2 other "the errors table, with a type column"'), None, 0,
             "answer: other - the errors table, with a type column"),
            ("valid-quote-in-code-span", block(sha, 'comment files-that-change/1 "queue (MAX_RETRIES)" "x"'), None,
             0, "quote: queue (MAX_RETRIES)"),
            ("stale", block("0" * 64, "decide Q1 A"), None, 1, "has changed since the page was built"),
            ("stale-says-rebuild", block("0" * 64, "decide Q1 A"), None, 1, "Rebuild the page"),
            ("unknown-question", block(sha, "decide Q9 A"), None, 1, "Q9 is not an open question"),
            ("unknown-option", block(sha, "decide Q1 C"), None, 1, "Q1 offers A, B; the block chose C"),
            ("decided-twice", block(sha, "decide Q1 A", "decide Q1 B"), None, 1, "Q1 is decided twice"),
            ("other-no-text", block(sha, "decide Q1 other"), None, 1, "an `other` answer carries its text"),
            ("unknown-anchor", block(sha, 'comment risks/7 "" "x"'), None, 1, "holds no passage risks/7"),
            ("unknown-section", block(sha, 'comment rollout/1 "" "x"'), None, 1, "holds no passage rollout/1"),
            ("quote-not-there", block(sha, 'comment risks/1 "retried twice" "x"'), None, 1,
             "does not hold the quoted text"),
            ("no-block", "decide Q1 A\n", None, 1, "no answers block"),
            ("two-blocks", good + good, None, 1, "2 answers blocks"),
            ("unclosed", good.replace("\n```\n", "\n"), None, 1, "never closed"),
            ("bad-format", good.replace("format: 1", "format: 2"), None, 1, "format 2 is not one"),
            ("bad-line", block(sha, "decide Q1 A; rm -rf /"), None, 1, "neither `decide"),
            ("spec-named", block(spec_sha, "decide Q1 A", plan=".claude/productizer/spec.md"), None, 1,
             "which is not a plan.md"),
            ("dotdot", block(sha, "decide Q1 A", plan="docs/sdlc/../sdlc/B7/plan.md"), None, 1,
             "not a plain path"),
            ("absolute", block(sha, "decide Q1 A", plan=plan_path), None, 1, "not a plain path"),
            ("symlink", block(sha, "decide Q1 A", plan="docs/sdlc/link/plan.md"), None, 1, "symbolic link"),
            ("absent-plan", block(sha, "decide Q1 A", plan="docs/sdlc/B8/plan.md"), None, 1, "does not exist"),
            ("other-plan-than-asked", good, "docs/sdlc/B9/plan.md", 1, "this run was told the plan is"),
            ("asked-plan", good, "docs/sdlc/B7/plan.md", 0, "the block is valid"),
        ]
        for name, text, want, want_rc, want_text in cases:
            total += 1
            rc, out = run(root, text, want)
            codes.add(rc)
            msg = "\n".join(out)
            if rc == want_rc and want_text in msg:
                held += 1
                print("  ok   %s (exit %d)" % (name, rc))
            else:
                print("  FAIL %s: exit %d, wanted %d with %r\n%s" % (name, rc, want_rc, want_text, msg))

        def check(name, ok, detail):
            nonlocal held, total
            total += 1
            if ok:
                held += 1
                print("  ok   %s" % name)
            else:
                print("  FAIL %s: %s" % (name, detail))
        before_spec = open(spec_path, "rb").read()
        listing = sorted(os.path.join(d, f) for d, _, fs in os.walk(root) for f in fs)
        rc, out = run(root, good, None, True)
        codes.add(rc)
        text = open(plan_path).read()
        after = model.parse(text)
        check("apply-writes-decision", rc == 0 and "- Q1: How many retries before a job is dead-lettered?\n"
              "  Decided: B - five, with backoff\n  Note: with a cap of 60s" in text, "\n".join(out) + text)
        check("apply-moves-question", [q["id"] for q in after["questions"]] == ["Q2"] and after["decided"] == ["Q1"],
              text)
        check("apply-drops-placeholder", "<answered open questions" not in text, text)
        check("apply-keeps-the-rest", text.split("Files that change")[1] == PLAN.split("Files that change")[1], text)
        check("apply-touches-only-the-plan", open(spec_path, "rb").read() == before_spec and listing == sorted(
            os.path.join(d, f) for d, _, fs in os.walk(root) for f in fs), "a file beside the plan changed")
        check("apply-comments-not-written", "permanent error is told apart" not in text, text)
        rc, out = run(root, good, None, True)
        codes.add(rc)
        check("apply-twice-is-stale", rc == 1 and "has changed since" in "\n".join(out), "\n".join(out))
        sha2 = model.sha256(text.encode())
        rc, out = run(root, block(sha2, "decide Q1 A"), None, False)
        check("decided-is-not-open", rc == 1 and "Q1 is already under Decisions" in "\n".join(out), "\n".join(out))
        rc, out = run(root, block(sha2, "decide Q2 A"), None, True)
        text = open(plan_path).read()
        check("apply-last-removes-open-questions", rc == 0 and "Open questions" not in text
              and model.parse(text)["decided"] == ["Q1", "Q2"], text)
        no_dec = PLAN.replace("Decisions\n- <answered open questions land here, written by plan-answers.py "
                              "--apply>\n\n", "")
        sha3 = reset(no_dec)
        rc, out = run(root, block(sha3, "decide Q2 B"), None, True)
        text = open(plan_path).read()
        check("apply-adds-decisions-section", rc == 0 and "Decisions\n- Q2: Where does the dead-letter list live?\n"
              "  Decided: B - a file per day\n" in text and model.parse(text)["decided"] == ["Q2"], text)
        sha4 = reset(PLAN + "\nOpen questions\n- Q3: one way?\n  - A: yes\n")
        rc, out = run(root, block(sha4, "decide Q1 A"), None, False)
        codes.add(rc)
        check("malformed-plan", rc == 2 and "offers 1 option" in "\n".join(out), "\n".join(out))
        for name, argv, want_rc, want_err in (("bad-option", ["--bogus"], 2, "usage"),
                                              ("unreadable-file", [os.path.join(root, "none.txt")], 2, "cannot read")):
            total += 1
            proc = subprocess.run([sys.executable, os.path.abspath(__file__), "--root", root] + argv,
                                  capture_output=True, text=True, check=False)
            codes.add(proc.returncode)
            if proc.returncode == want_rc and want_err in proc.stderr:
                held += 1
                print("  ok   %s (exit %d)" % (name, proc.returncode))
            else:
                print("  FAIL %s: exit %d, stderr %r" % (name, proc.returncode, proc.stderr))
        reset()
        proc = subprocess.run([sys.executable, os.path.abspath(__file__), "--root", root, "-"], input=good,
                              capture_output=True, text=True, check=False)
        check("stdin", proc.returncode == 0 and "the block is valid" in proc.stdout, proc.stdout + proc.stderr)
    documented = [int(m.group(1)) for m in re.finditer(r"^  (\d) ", __doc__.split("Exit codes:", 1)[1], re.M)]
    print("    exit codes reached: %s   documented: %s" % (" ".join(str(c) for c in sorted(codes)),
                                                          " ".join(str(c) for c in documented)))
    print("    NOT ASSERTED: that the person read the page, what a comment means, or that an answer is a good one;"
          " a block a browser produced - every block here is written by this self-test")
    print("plan-answers selftest: %d of %d cases held" % (held, total))
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
    root, want, do_apply, src = None, None, False, None
    while args:
        a = args.pop(0)
        if a in ("--root", "--plan") and args:
            v = args.pop(0)
            if a == "--root":
                root = v
            else:
                want = v
        elif a == "--apply":
            do_apply = True
        elif a == "-" or not a.startswith("-"):
            if src is not None:
                sys.stderr.write(USAGE)
                return 2
            src = a
        else:
            sys.stderr.write(USAGE)
            return 2
    if root is None:
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=False)
        root = top.stdout.strip() if top.returncode == 0 else os.getcwd()
    try:
        if src in (None, "-"):
            text = sys.stdin.read()
        else:
            with open(src if os.path.isabs(src) else os.path.join(root, src), encoding="utf-8") as fh:
                text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        sys.stderr.write("plan-answers: cannot read %s: %s\n" % (src, exc.__class__.__name__))
        return 2
    rc, out = run(root, text, want, do_apply)
    stream = sys.stderr if rc == 2 else sys.stdout
    for line in out:
        stream.write(line + "\n")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
