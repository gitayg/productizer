#!/usr/bin/env python3
"""check-review-record.py --policy REVIEW_MD RECORD... [--selftest] [--version] [--help]

Static assertions over a review record: the findings of every review round of
one change and how each was answered (templates/review-record.md), committed
beside the change's plan.md as <artifacts.path>/review.md. REVIEW_MD is the
review policy (templates/REVIEW.md), read for its `## Ignored paths` list. A
relative path is read under the repository root (the git top level of the
working directory), an absolute one as given.

WHY THIS EXISTS (B166, B167, B169). A review's findings were advisory and
nothing tracked them. A finding with no location cannot be checked; a summary
with no count cannot be told from one that was never written; an agent author
and an agent reviewer can loop all night re-finding the same bugs; and an
Important finding nobody answered merged anyway. Each is a property of the
record's text, so it is checked on the record.

WHAT IT ASSERTS, each a separate finding:
  rounds         the Rounds table numbers its rounds 1, 2, 3 ... with no gap,
                 and every Base and Head is a commit id of 7 to 40 hex digits
  round-base     every round after the first starts from the commit the round
                 before it ended at, so a later round reviews only the new diff
  count          every round states its finding count, equal to the findings
                 recorded for that round, and a round with none says
                 `no issues` - never 0 and never blank
  finding-shape  every finding has a unique id, names a round the Rounds table
                 holds, a severity of Important, Nit or Pre-existing, a
                 location `path:line` (or `path:line-line`) relative to the
                 root, and a bug class that is not a placeholder
  ignored-path   no finding is located under a path REVIEW_MD lists under
                 `## Ignored paths` (fnmatch globs; a `*` crosses `/`)
  re-reported    no finding repeats the location and bug class of a finding of
                 an earlier round
  rethink        a record with more than 3 rounds states, on its `Rethink:`
                 line, the approach that replaced patching
  answered       every finding's status is open, fixed, rejected, intentional
                 or irrelevant, and every status but open states a reason
  important-open no Important finding is still open

Every record read prints how its findings were answered - fixed, rejected,
intentional, irrelevant, open - so the noise a reviewer makes is counted,
never estimated, and `examined <path>` once it was parsed.

WHAT IT DOES NOT. It reads text. It cannot tell whether a finding is true,
whether a fix fixed it, whether a reason is a good one, or whether the review
the record describes happened. A cell holding a literal `|` splits the row.

Exit codes:
  0  every assertion held in every record
  1  at least one finding, each printed with its assertion and record
  2  could not run: bad usage, or REVIEW_MD or a record absent or unreadable
--selftest runs its cases in a temporary directory, and exits 0 when every case
held, 1 otherwise.
"""
import fnmatch
import os
import re
import subprocess
import sys
import tempfile

VERSION = "check-review-record 1.0"
ASSERTIONS = ("rounds", "round-base", "count", "finding-shape", "ignored-path",
              "re-reported", "rethink", "answered", "important-open")
SEVERITIES = ("Important", "Nit", "Pre-existing")
STATUSES = ("open", "fixed", "rejected", "intentional", "irrelevant")
ROUND_CAP = 3
SHA_RE = re.compile(r"^[0-9a-fA-F]{7,40}$")
LOC_RE = re.compile(r"^(?P<path>[^\s:]+):(?P<line>[1-9][0-9]*)(?:-[1-9][0-9]*)?$")
NONE_RE = re.compile(r"^(|—|-|–)$")
USAGE = "usage: check-review-record.py --policy REVIEW_MD RECORD... [--selftest] [--version] [--help]\n"


def blank(cell):
    cell = cell.strip()
    return bool(NONE_RE.match(cell)) or (cell.startswith("<") and cell.endswith(">"))


def sections(text):
    """{lower-cased heading: [lines]} for every `## ` heading."""
    out, cur = {}, None
    for line in text.split("\n"):
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            cur = m.group(1).lower()
            out.setdefault(cur, [])
        elif cur is not None:
            out[cur].append(line)
    return out


def table(lines):
    """Rows of the first markdown table in lines, as dicts keyed by header."""
    rows, head = [], None
    for line in lines:
        s = line.strip()
        if not s.startswith("|"):
            if head is not None:
                break
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if head is None:
            head = [c.lower() for c in cells]
        elif all(re.match(r"^:?-+:?$", c) for c in cells if c):
            continue
        else:
            rows.append(dict(zip(head, cells + [""] * (len(head) - len(cells)))))
    return rows


def ignored_globs(policy_text):
    globs = []
    for line in sections(policy_text).get("ignored paths", []):
        m = re.match(r"^\s*[-*]\s+`?([^`\s]+)`?", line)
        if m:
            globs.append(m.group(1))
    return globs


def read(path):
    try:
        with open(path, "rb") as fh:
            return fh.read().decode("utf-8"), None
    except (OSError, UnicodeDecodeError) as exc:
        return None, str(exc)


def check_record(text, globs):
    """{assertion: [findings]} and the answered tally for one record."""
    f = {a: [] for a in ASSERTIONS}
    secs = sections(text)
    rounds = table(secs.get("rounds", []))
    findings = table(secs.get("findings", []))
    m = re.search(r"^Rethink:[ \t]*(.*)$", text, re.M)
    rethink = m.group(1) if m else ""

    if not rounds:
        f["rounds"].append("no Rounds table, or one with no rows")
    numbers = []
    for i, r in enumerate(rounds, 1):
        n = r.get("round", "")
        if n != str(i):
            f["rounds"].append("row %d reads round %r, wanted %d" % (i, n, i))
        for col in ("base", "head"):
            if not SHA_RE.match(r.get(col, "")):
                f["rounds"].append("round %s %s %r is not a commit id" % (n, col.title(), r.get(col, "")))
        numbers.append(n)
    for prev, cur in zip(rounds, rounds[1:]):
        a, b = prev.get("head", "").lower(), cur.get("base", "").lower()
        if not (a and b and (a.startswith(b) or b.startswith(a))):
            f["round-base"].append("round %s starts from %r, not from round %s's head %r"
                                   % (cur.get("round"), cur.get("base"), prev.get("round"), prev.get("head")))
    if len(rounds) > ROUND_CAP and blank(rethink):
        f["rethink"].append("%d rounds, more than %d, and no Rethink: line naming the new approach" % (len(rounds), ROUND_CAP))

    seen_ids, earlier = set(), {}
    per_round = {}
    tally = dict((s, 0) for s in STATUSES)
    for r in findings:
        fid = r.get("id", "")
        where = "finding %s" % (fid or "with no id")
        if blank(fid) or fid in seen_ids:
            f["finding-shape"].append("%s: an id that is empty or repeated" % where)
        seen_ids.add(fid)
        rnd = r.get("round", "")
        if rnd not in numbers:
            f["finding-shape"].append("%s: round %r is not in the Rounds table" % (where, rnd))
        per_round[rnd] = per_round.get(rnd, 0) + 1
        sev = r.get("severity", "")
        if sev not in SEVERITIES:
            f["finding-shape"].append("%s: severity %r is not one of %s" % (where, sev, ", ".join(SEVERITIES)))
        loc = LOC_RE.match(r.get("location", "").strip("`"))
        path = loc.group("path") if loc else ""
        if not loc or path.startswith("/") or ".." in path.split("/"):
            f["finding-shape"].append("%s: location %r is not path:line under the root" % (where, r.get("location", "")))
        cls = r.get("class", "")
        if blank(cls):
            f["finding-shape"].append("%s: names no bug class" % where)
        if loc:
            for g in globs:
                if fnmatch.fnmatchcase(path, g) or fnmatch.fnmatchcase(path, g.rstrip("/") + "/*"):
                    f["ignored-path"].append("%s: %s is under the ignored path %s" % (where, path, g))
                    break
            key = (path, loc.group("line"), cls.strip().lower())
            if key in earlier and earlier[key][1] != rnd:
                f["re-reported"].append("%s (round %s) repeats %s of round %s at %s"
                                        % (where, rnd, earlier[key][0], earlier[key][1], r.get("location")))
            earlier.setdefault(key, (fid, rnd))
        status = r.get("status", "").lower()
        if status not in STATUSES:
            f["answered"].append("%s: status %r is not one of %s" % (where, r.get("status", ""), ", ".join(STATUSES)))
        else:
            tally[status] += 1
            if status != "open" and blank(r.get("reason", "")):
                f["answered"].append("%s: answered %s with no reason" % (where, status))
        if sev == "Important" and status == "open":
            f["important-open"].append("%s at %s is Important and still open" % (where, r.get("location")))

    for r in rounds:
        n, said = r.get("round", ""), r.get("findings", "").strip()
        got = per_round.get(n, 0)
        if got == 0:
            if said.lower() != "no issues":
                f["count"].append("round %s records no findings and says %r, not `no issues`" % (n, said))
        elif said != str(got):
            f["count"].append("round %s says %r and records %d finding(s)" % (n, said, got))
    return f, tally, len(rounds), len(findings)


def run(policy, records):
    """Return (exit code, lines to print)."""
    ptext, err = read(policy)
    if ptext is None:
        return 2, ["check-review-record: cannot read the review policy %s: %s" % (policy, err)]
    globs = ignored_globs(ptext)
    out = ["check-review-record: policy %s, ignored paths: %s"
           % (shown(policy), ", ".join(globs) if globs else "none listed")]
    texts = []
    for rec in records:
        text, err = read(rec)
        if text is None:
            return 2, out + ["check-review-record: cannot read %s: %s" % (rec, err)]
        texts.append((rec, text))
    held_all = True
    for rec, text in texts:
        rec = shown(rec)
        f, tally, nr, nf = check_record(text, globs)
        out.append("%s: %d round(s), %d finding(s)" % (rec, nr, nf))
        out.append("  answered: " + ", ".join("%s %d" % (s, tally[s]) for s in STATUSES))
        held = 0
        for a in ASSERTIONS:
            if f[a]:
                for line in f[a]:
                    out.append("FINDING %s: %s: %s" % (a, rec, line))
            else:
                held += 1
        out.append("  %d of %d assertions held" % (held, len(ASSERTIONS)))
        out.append("examined %s" % rec)
        held_all = held_all and held == len(ASSERTIONS)
    return (0 if held_all else 1), out


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


GOOD = """# Review record - #12 retry queue

Rethink: —

## Rounds

| Round | Base | Head | Findings |
|---|---|---|---|
| 1 | 1111111 | 2222222 | 3 |
| 2 | 2222222 | 3333333 | no issues |

## Findings

| Id | Round | Severity | Location | Class | Status | Reason |
|---|---|---|---|---|---|---|
| F1 | 1 | Important | src/queue.py:41 | unbounded retry on a permanent error | fixed | 3333333 stops after five attempts |
| F2 | 1 | Nit | src/queue.py:9 | naming | intentional | matches the provider's field name |
| F3 | 1 | Pre-existing | src/export.py:120 | off-by-one at a page boundary | open | — |
"""

POLICY = "# Review policy\n\n## Ignored paths\n- `dist/**`\n- `*.lock`\n- vendor/\n\n## Passes\n- Bugs.\n"


def selftest():
    held = total = 0
    codes = set()
    with tempfile.TemporaryDirectory() as tmp:
        def write(name, body):
            p = os.path.join(tmp, name)
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(body)
            return p

        policy = write("REVIEW.md", POLICY)
        bare_policy = write("BARE.md", "# Review policy\n\n## Passes\n- Bugs.\n")
        four = (GOOD.replace("| 2 | 2222222 | 3333333 | no issues |",
                             "| 2 | 2222222 | 3333333 | no issues |\n| 3 | 3333333 | 4444444 | no issues |\n"
                             "| 4 | 4444444 | 5555555 | no issues |"))
        cases = [
            ("good", policy, GOOD, 0, "9 of 9 assertions held"),
            ("answered-tally", policy, GOOD, 0, "answered: open 1, fixed 1, rejected 0, intentional 1, irrelevant 0"),
            ("no-ignored-section", bare_policy, GOOD, 0, "ignored paths: none listed"),
            ("important-open", policy, GOOD.replace("| fixed | 3333333 stops after five attempts |", "| open | — |"), 1,
             "FINDING important-open"),
            ("closed-without-reason", policy, GOOD.replace("| intentional | matches the provider's field name |", "| rejected | — |"), 1,
             "FINDING answered"),
            ("unknown-status", policy, GOOD.replace("| intentional |", "| wontfix |"), 1, "status 'wontfix' is not one of"),
            ("no-line", policy, GOOD.replace("src/queue.py:9", "src/queue.py"), 1, "FINDING finding-shape"),
            ("absolute-location", policy, GOOD.replace("src/queue.py:9", "/etc/queue.py:9"), 1, "is not path:line under the root"),
            ("parent-location", policy, GOOD.replace("src/queue.py:9", "../queue.py:9"), 1, "is not path:line under the root"),
            ("range-location", policy, GOOD.replace("src/queue.py:9", "src/queue.py:9-14"), 0, "9 of 9 assertions held"),
            ("bad-severity", policy, GOOD.replace("| Nit |", "| Minor |"), 1, "severity 'Minor' is not one of"),
            ("no-class", policy, GOOD.replace("| naming |", "| <the bug class> |"), 1, "names no bug class"),
            ("repeated-id", policy, GOOD.replace("| F2 |", "| F1 |"), 1, "an id that is empty or repeated"),
            ("unknown-round", policy, GOOD.replace("| F2 | 1 |", "| F2 | 7 |"), 1, "round '7' is not in the Rounds table"),
            ("count-wrong", policy, GOOD.replace("| 2222222 | 3 |", "| 2222222 | 2 |"), 1, "FINDING count: "),
            ("count-zero-not-no-issues", policy, GOOD.replace("| no issues |", "| 0 |"), 1, "says '0', not `no issues`"),
            ("count-blank", policy, GOOD.replace("| no issues |", "|  |"), 1, "says '', not `no issues`"),
            ("no-issues-with-findings", policy, GOOD.replace("| 2222222 | 3 |", "| 2222222 | no issues |"), 1,
             "says 'no issues' and records 3"),
            ("ignored-glob", policy, GOOD.replace("src/export.py:120", "dist/app.js:120"), 1, "under the ignored path dist/**"),
            ("ignored-dir", policy, GOOD.replace("src/export.py:120", "vendor/lib/a.py:3"), 1, "under the ignored path vendor/"),
            ("ignored-suffix", policy, GOOD.replace("src/export.py:120", "app/package.lock:3"), 1, "under the ignored path *.lock"),
            ("round-base-gap", policy, GOOD.replace("| 2 | 2222222 |", "| 2 | 1111111 |"), 1, "FINDING round-base"),
            ("round-base-other-commit", policy, GOOD.replace("| 2 | 2222222 |", "| 2 | 2222223 |"), 1, "FINDING round-base"),
            ("round-base-long-head", policy, GOOD.replace("| 2 | 2222222 |", "| 2 | 2222222abc |").replace("| 1111111 | 2222222 |", "| 1111111 | 2222222abcdef |"), 0,
             "9 of 9 assertions held"),
            ("round-gap", policy, GOOD.replace("| 2 | 2222222 |", "| 3 | 2222222 |"), 1, "row 2 reads round '3', wanted 2"),
            ("round-not-sha", policy, GOOD.replace("| 1111111 |", "| main |"), 1, "Base 'main' is not a commit id"),
            ("no-rounds", policy, GOOD.split("## Rounds")[0] + "## Findings\n", 1, "no Rounds table"),
            ("re-reported", policy, GOOD.replace("| 2 | 2222222 | 3333333 | no issues |", "| 2 | 2222222 | 3333333 | 1 |")
             + "| F4 | 2 | Pre-existing | src/export.py:120 | Off-by-one at a page boundary | open | — |\n", 1,
             "FINDING re-reported: "),
            ("same-place-other-class", policy, GOOD.replace("| 2 | 2222222 | 3333333 | no issues |", "| 2 | 2222222 | 3333333 | 1 |")
             + "| F4 | 2 | Pre-existing | src/export.py:120 | unescaped log field | open | — |\n", 0, "9 of 9 assertions held"),
            ("three-rounds-no-rethink", policy, four.replace("| 4 | 4444444 | 5555555 | no issues |\n", "").replace(
                "| 4 | 4444444 | 5555555 | no issues |", ""), 0, "9 of 9 assertions held"),
            ("fourth-round-no-rethink", policy, four, 1, "FINDING rethink: "),
            ("fourth-round-placeholder-rethink", policy, four.replace("Rethink: —", "Rethink: <the new approach>"), 1, "FINDING rethink: "),
            ("fourth-round-rethink", policy, four.replace("Rethink: —", "Rethink: replaced per-call retries with one queue consumer"), 0,
             "9 of 9 assertions held"),
        ]
        for name, pol, body, want_rc, want_text in cases:
            total += 1
            rc, out = run(pol, [write(name + ".md", body)])
            codes.add(rc)
            text = "\n".join(out)
            if rc == want_rc and want_text in text:
                held += 1
                print("  ok   %s (exit %d)" % (name, rc))
            else:
                print("  FAIL %s: exit %d, wanted %d with %r\n%s" % (name, rc, want_rc, want_text, text))
        extra = [
            ("two-records-one-bad", lambda: run(policy, [write("a.md", GOOD), write("b.md", GOOD.replace("| fixed |", "| open |"))]),
             1, "examined %s" % os.path.join(tmp, "a.md")),
            ("absent-policy", lambda: run(os.path.join(tmp, "nope.md"), [write("c.md", GOOD)]), 2, "cannot read the review policy"),
            ("absent-record", lambda: run(policy, [os.path.join(tmp, "gone.md")]), 2, "cannot read"),
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
        for name, argv in (("no-records", ["--policy", policy]), ("no-policy", [write("d.md", GOOD)])):
            total += 1
            proc = subprocess.run([sys.executable, os.path.abspath(__file__)] + argv, capture_output=True, text=True, check=False)
            codes.add(proc.returncode)
            if proc.returncode == 2 and "usage" in proc.stderr:
                held += 1
                print("  ok   %s (exit 2)" % name)
            else:
                print("  FAIL %s: exit %d, stderr %r" % (name, proc.returncode, proc.stderr))
        total += 1
        tpl = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "templates", "review-record.md")
        rc, out = run(policy, [tpl])
        codes.add(rc)
        if rc == 1 and "FINDING finding-shape" in "\n".join(out):
            held += 1
            print("  ok   template-placeholders-refused (exit 1)")
        else:
            print("  FAIL template-placeholders-refused: exit %d\n%s" % (rc, "\n".join(out)))
    documented = documented_codes()
    print("    exit codes reached: %s   documented: %s" % (" ".join(str(c) for c in sorted(codes)), " ".join(str(c) for c in documented)))
    print("    NOT ASSERTED: that a finding is true, that a fix fixed it, that a reason is a good one, or that the review happened")
    print("check-review-record selftest: %d of %d cases held" % (held, total))
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
    policy, records = None, []
    while args:
        a = args.pop(0)
        if a == "--policy" and args:
            policy = args.pop(0)
        elif a.startswith("--policy="):
            policy = a.split("=", 1)[1]
        elif a.startswith("-"):
            policy = records = None
            break
        else:
            records.append(a)
    if not policy or not records:
        sys.stderr.write(USAGE)
        return 2
    rc, out = run(resolve(policy), [resolve(r) for r in records])
    stream = sys.stderr if rc == 2 else sys.stdout
    for line in out:
        stream.write(line + "\n")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
