"""The failure-case rule: a new `When` requirement covers four failure cases.

Imported by `validate-spec.py`, never run on its own. B191, v4.83.0.

THE RULE. A requirement a change ADDS under the event-driven heading, or whose
sentence holds a `when` trigger clause ahead of its response - `When ...`,
`While ..., when ...`, `Where ..., when ...`, read from the sentence whatever
heading it is filed under - carries a `Failure cases` line. For each of four
cases the line names one or more unwanted-behaviour requirements (`If ...,
then ...`) or says `n/a because <reason>`:

    input       invalid input
    caller      a wrong caller or tenant
    repeat      a repeat or concurrent action
    dependency  a failing dependency

One `n/a because <reason>` with no case named covers all four: it declares
that the requirement changes no state, in writing, where a reviewer reads it.
"State-changing" is that declaration, never a guess made here.

<!-- EXAMPLE:BEGIN -->
    - **R12** — When a person files a ticket, the lifecycle shall store it.
    Failure cases: input R13 · caller R14 · repeat n/a because ... · dependency R15
<!-- EXAMPLE:END -->

WHY THE LINE IS NOT INDENTED. Every spec parser in this plugin -
`validate-spec.py`, `spec-requirements.sh` and so every check reading the spec
through it, and `build-guide.sh` - reads an indented line under a bullet as
more of the requirement's SENTENCE. Measured at 487799d: an indented line put
`EARS_NO_FULL_STOP` on the requirement under `--strict`, joined the text
`spec-requirements.sh` hands `contradiction-check.py`, `check-superseded-text.sh`
and `check-suspect-links.sh`, and was rendered into GUIDE.md as part of the
requirement. An unindented line directly under the item is a Markdown lazy
continuation - it renders inside the item - and every one of those parsers
closes the item on it and reads nothing. So the line goes LAST in the item,
unindented, after any status marker: a marker below it would be read by no
parser at all, which `validate-spec.py` reports as FAILURE_CASES_MISPLACED.

ON THE CHANGE ITSELF. Coverage is demanded of requirements that are new
against a base commit and have a trigger; of requirements active at the base
with no trigger that have one now (a refine that introduces the trigger
introduces the state change); and of every requirement that carried a
`Failure cases` line at the base, so a line deleted or weakened is judged
again. A requirement that was active at the base with a trigger and no line
is never examined for coverage, so the spec as it stood is not affected - and
such a requirement rewritten in place stays exempt, by design. A line that IS present is always parsed and its ids resolved,
whatever the base: a declaration nobody can read is a finding wherever it is.

THE BASE. `--base REF` names it. Without one: HEAD, when the spec in the work
tree differs from HEAD's - so the uncommitted edit is the change; otherwise
the first parent of the newest commit on HEAD's first-parent line that changed
the spec - so that ONE commit is the change, never a branch of several. A
branch or a pull request is measured whole only with --base, as CI passes it.
The base is read at the spec's CURRENT paths: a spec that moved reads as
absent at the base, and every requirement in it as new.
That walk is the one `check-changelog-row.sh` and `check-spec-integrity.sh`
take over `git log -- <spec>`, and like them it refuses a shallow clone. No
resolvable base is NOT MEASURED, never a pass.

Python 3.8+, standard library only. git is run with a fixed argv, its output
read as data; nothing from the repository selects what runs (P4).
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from dataclasses import dataclass, field

VERSION = "1.0"

CASES = (
    ("input", "invalid input"),
    ("caller", "a wrong caller or tenant"),
    ("repeat", "a repeat or concurrent action"),
    ("dependency", "a failing dependency"),
)
CASE_NAMES = tuple(name for name, _ in CASES)
CASE_WORDS = dict(CASES)

# The line's opener. Unindented on purpose; see the header.
LINE_RE = re.compile(r"^failure cases\s*:\s*(?P<body>.*)$", re.I)
SEPARATOR_RE = re.compile(r"\s*[·;]\s*")
NA_RE = re.compile(r"^n/a\b\s*(?:because\b\s*(?P<reason>.*))?$", re.I | re.S)
IDS_RE = re.compile(r"^R[1-9][0-9]*(?:\s*(?:,|\band\b|\s)\s*R[1-9][0-9]*)*$")
ID_RE = re.compile(r"R[1-9][0-9]*")


@dataclass
class Parsed:
    """What a `Failure cases` line says, and what could not be read in it."""
    cases: dict = field(default_factory=dict)   # name -> ("ids", [ids]) | ("na", reason)
    whole_na: str = ""                           # the reason, when one n/a covers all four
    errors: list = field(default_factory=list)

    def covered(self):
        if self.whole_na:
            return set(CASE_NAMES)
        return set(self.cases)


def parse(body):
    """Read the text after `Failure cases:`. Never raises; errors are listed."""
    found = Parsed()
    text = " ".join(body.split())
    if not text:
        found.errors.append("the line names no case and no `n/a because` "
                            "reason")
        return found
    whole = NA_RE.match(text)
    if whole and not SEPARATOR_RE.search(text):
        reason = (whole.group("reason") or "").strip()
        if not reason:
            found.errors.append("`n/a` covers all four cases only with a "
                                "reason after `because`")
        else:
            found.whole_na = reason
        return found
    for segment in SEPARATOR_RE.split(text):
        segment = segment.strip()
        if not segment:
            found.errors.append("an empty case between two separators")
            continue
        words = segment.split(None, 1)
        name = words[0].lower().rstrip(":")
        rest = words[1].strip() if len(words) > 1 else ""
        if name not in CASE_WORDS:
            found.errors.append("`%s` is not a failure case; the four are %s"
                                % (words[0], ", ".join(CASE_NAMES)))
            continue
        if name in found.cases:
            found.errors.append("the case `%s` is named twice" % name)
            continue
        na = NA_RE.match(rest)
        if na:
            reason = (na.group("reason") or "").strip()
            if not reason:
                found.errors.append("the case `%s` is `n/a` with no reason "
                                    "after `because`" % name)
                continue
            found.cases[name] = ("na", reason)
            continue
        if IDS_RE.match(rest):
            found.cases[name] = ("ids", ID_RE.findall(rest))
            continue
        found.errors.append("the case `%s` gives neither requirement ids nor "
                            "`n/a because` and a reason: `%s`"
                            % (name, rest[:60] or "(nothing)"))
    return found


# A trigger is read from the SENTENCE, never from the pattern validate-spec
# cached: a sentence holding `<...>` (a placeholder, or a code span such as
# `purge <ticket>`) is skipped by the EARS pass and carries no cached pattern,
# so a cached-pattern test let such a `When` requirement filed under any other
# heading through (B191 review, reproduced). `While ..., when ...` and
# `Where ..., when ...` carry a trigger too: a `when` clause before `shall`.
TRIGGER_RE = re.compile(r"^(?:When\b|(?:While|Where)\b[^\n]*?,\s*when\b)", re.S)
UNWANTED_RE = re.compile(
    r"^If\s+.+?,\s*then\s+(?:the|every)\s+.+?\s+shall\s+.+$", re.S)


def is_event(requirement):
    """Filed under Event-driven, or a `When` / `, when` trigger in the
    sentence before its `shall`."""
    if requirement.section == "event":
        return True
    text = requirement.text.strip()
    head = text.split(" shall ", 1)[0] if " shall " in text else text
    return bool(TRIGGER_RE.match(head))


def check_declared(doc, lookup, error):
    """Parse every active requirement's line and resolve the ids it names.

    `lookup` maps an id to its Requirement across every spec file of the run.
    Runs whatever the base, on every line present: a line with an id that
    resolves to nothing is wrong wherever it stands.
    """
    for requirement in doc.requirements:
        if requirement.status != "active" or not requirement.failure_cases_line:
            continue
        line = requirement.failure_cases_line
        parsed = parse(requirement.failure_cases)
        for message in parsed.errors:
            doc.add(line, error, "FAILURE_CASES_MALFORMED",
                    "%s's `Failure cases` line: %s"
                    % (requirement.ident, message))
        for name in CASE_NAMES:
            kind, value = parsed.cases.get(name, ("", None))
            if kind != "ids":
                continue
            for ident in value:
                target = lookup.get(ident)
                if target is None:
                    doc.add(line, error, "FAILURE_CASE_ID_UNKNOWN",
                            "%s covers `%s` with %s, which the spec does not "
                            "define" % (requirement.ident, name, ident))
                elif target.status != "active":
                    doc.add(line, error, "FAILURE_CASE_ID_INACTIVE",
                            "%s covers `%s` with %s, which is %s; a case is "
                            "covered by a requirement still in force"
                            % (requirement.ident, name, ident, target.status))
                elif not UNWANTED_RE.match(target.text.strip()):
                    doc.add(line, error, "FAILURE_CASE_ID_NOT_UNWANTED",
                            "%s covers `%s` with %s, which is not an "
                            "unwanted-behaviour requirement (`If ..., then "
                            "...`)" % (requirement.ident, name, ident))


def check_coverage(doc, checked, error):
    """Demand the four cases of each requirement in `checked`: ids, or a dict
    of id -> why it is checked, as `checked_ids` returns."""
    for requirement in doc.requirements:
        if requirement.ident not in checked:
            continue
        why = (checked.get(requirement.ident) if isinstance(checked, dict)
               else None) or WHY_NEW
        if not requirement.failure_cases_line:
            doc.add(requirement.line, error, "FAILURE_CASES_MISSING",
                    "%s %s and carries no `Failure cases` line; uncovered: %s. "
                    "Each needs an `If` requirement id or `n/a because "
                    "<reason>` (references/ears.md rule 6)"
                    % (requirement.ident, why,
                       ", ".join("%s (%s)" % c for c in CASES)))
            continue
        covered = parse(requirement.failure_cases).covered()
        for name, words in CASES:
            if name not in covered:
                doc.add(requirement.failure_cases_line, error,
                        "FAILURE_CASE_UNCOVERED",
                        "%s: the failure case `%s` (%s) is neither covered by "
                        "an `If` requirement id nor marked `n/a because "
                        "<reason>`" % (requirement.ident, name, words))


WHY_NEW = "is new against the base and has a trigger"
WHY_GAINED = "was active at the base with no trigger and has one now"
WHY_HAD_LINE = "carried a `Failure cases` line at the base"


def checked_ids(current_docs, base_docs):
    """Ids the rule examines. Active now, and one of: new and event-driven;
    event-driven now and not at the base; or carrying a `Failure cases` line at
    the base, so a line deleted or weakened is judged again (B191 review: a
    deleted line on an old requirement passed). An active event-driven
    requirement with no line at the base is left alone."""
    before = {}
    for doc in base_docs:
        for requirement in doc.requirements:
            before.setdefault(requirement.ident, requirement)
    checked = {}
    new = 0
    for doc in current_docs:
        for requirement in doc.requirements:
            if requirement.status != "active":
                continue
            old = before.get(requirement.ident)
            if old is None:
                new += 1
            had_line = (old is not None and old.status == "active"
                        and old.failure_cases_line)
            if had_line:
                checked[requirement.ident] = WHY_HAD_LINE
                continue
            if not is_event(requirement):
                continue
            if old is not None and old.status == "active" and is_event(old):
                continue
            checked[requirement.ident] = WHY_NEW if old is None else WHY_GAINED
    return checked, new


# --------------------------------------------------------------------------
# The base
# --------------------------------------------------------------------------

@dataclass
class Base:
    sha: str = ""
    how: str = ""
    texts: dict = field(default_factory=dict)   # repo-relative path -> text | None
    refusal: str = ""


def _git(top, *args):
    proc = subprocess.run(["git", "-C", top] + list(args),
                          capture_output=True)
    return proc.returncode, proc.stdout, proc.stderr.decode("utf-8", "replace")


def resolve_base(root, spec_paths, base_ref, stderr):
    """Resolve the commit the change is measured against, and read the spec
    there. `refusal` set means NOT MEASURED. git's own stderr is passed on to
    `stderr` whenever a git call the resolution depends on fails."""
    found = Base()
    if shutil.which("git") is None:
        found.refusal = ("git is not on PATH, so no base commit can be read "
                         "and no requirement can be told new from old")
        return found
    rc, out, err = _git(root, "rev-parse", "--show-toplevel")
    if rc != 0:
        stderr.write(err)
        found.refusal = ("%s is not inside a git work tree, so there is no "
                         "commit to measure the change against" % root)
        return found
    top = out.decode("utf-8", "replace").strip()
    rels = [os.path.relpath(os.path.realpath(p), os.path.realpath(top))
            for p in spec_paths]

    if base_ref is not None:
        rc, out, _err = _git(top, "rev-parse", "--verify", "--quiet",
                             "%s^{commit}" % base_ref)
        if rc != 0:
            found.refusal = ("--base %s names no commit in this repository"
                             % base_ref)
            return found
        found.sha = out.decode().strip()
        found.how = "named by --base %s" % base_ref
    else:
        rc, out, _err = _git(top, "rev-parse", "--verify", "--quiet",
                             "HEAD^{commit}")
        if rc != 0:
            found.refusal = "HEAD names no commit, so there is no base"
            return found
        head = out.decode().strip()
        differs = False
        for rel, path in zip(rels, spec_paths):
            rc, listing, err = _git(top, "ls-tree", head, "--", rel)
            if rc != 0:
                stderr.write(err)
                found.refusal = "git ls-tree failed reading %s at HEAD" % rel
                return found
            if not listing.strip():
                differs = True
                break
            rc, blob, err = _git(top, "cat-file", "blob", "%s:%s" % (head, rel))
            if rc != 0:
                stderr.write(err)
                found.refusal = "git cat-file failed reading %s at HEAD" % rel
                return found
            with open(path, "rb") as handle:
                if handle.read() != blob:
                    differs = True
                    break
        if differs:
            found.sha = head
            found.how = ("HEAD, because the spec in the work tree differs "
                         "from HEAD's")
        else:
            rc, out, err = _git(top, "rev-parse", "--is-shallow-repository")
            if rc != 0 or out.decode().strip() == "true":
                if rc != 0:
                    stderr.write(err)
                found.refusal = ("this is a shallow clone and the work tree "
                                 "matches HEAD, so the commit before the last "
                                 "spec change may not be reachable. Fetch "
                                 "full history or name the base with --base")
                return found
            rc, out, err = _git(top, "log", "--first-parent", "--format=%H",
                                "--", *rels)
            if rc != 0:
                stderr.write(err)
                found.refusal = "git log failed walking the spec's history"
                return found
            shas = [s for s in out.decode().split() if s]
            if not shas:
                found.refusal = ("no commit on HEAD's first-parent line "
                                 "changed the spec and the work tree matches "
                                 "HEAD, so there is no change to measure. "
                                 "Name the base with --base")
                return found
            rc, out, _err = _git(top, "rev-parse", "--verify", "--quiet",
                                 "%s^1^{commit}" % shas[0])
            if rc != 0:
                found.refusal = ("%s changed the spec last and has no parent "
                                 "here - it is the repository's first commit, "
                                 "so there is no earlier tree to measure it "
                                 "against. Name the base with --base"
                                 % shas[0][:12])
                return found
            found.sha = out.decode().strip()
            found.how = ("the first parent of %s, the newest commit on HEAD's "
                         "first-parent line that changed the spec; the work "
                         "tree matches HEAD" % shas[0][:12])

    for rel in rels:
        rc, listing, err = _git(top, "ls-tree", found.sha, "--", rel)
        if rc != 0:
            stderr.write(err)
            found.refusal = ("git ls-tree failed reading %s at %s"
                             % (rel, found.sha[:12]))
            return found
        if not listing.strip():
            found.texts[rel] = None
            continue
        rc, blob, err = _git(top, "cat-file", "blob",
                             "%s:%s" % (found.sha, rel))
        if rc != 0:
            stderr.write(err)
            found.refusal = ("git cat-file failed reading %s at %s"
                             % (rel, found.sha[:12]))
            return found
        found.texts[rel] = blob.decode("utf-8", "replace")
    return found


# --------------------------------------------------------------------------
# Self-test. Driven from `validate-spec.py --self-test`, which owns the case
# count, the exit code and the R39 exit-code protocol; these are its B191
# cases. The git cases build throwaway repositories and drive `main` itself,
# so the base resolution is measured through the entry point CI runs.
# --------------------------------------------------------------------------

# <!-- EXAMPLE:BEGIN -->
_HEAD = """# Fixture — living spec

Next requirement id
: `R%d` — allocate from here.

Requirements
: %d active, %d superseded, %d withdrawn.

## Requirements
"""

_SECTIONS = (("ubiquitous", "### Ubiquitous — always active"),
             ("event", "### Event-driven"),
             ("state", "### State-driven"),
             ("unwanted", "### Unwanted behaviour"),
             ("optional", "### Optional"))


def _spec(**sections):
    """A fixture spec whose header counts and counter are computed, so a case
    fails on the rule under test and never on a stale fixture header."""
    body = []
    for key, heading in _SECTIONS:
        lines = sections.get(key, [])
        body.append("\n%s\n" % heading)
        if lines:
            body.append("\n" + "\n".join(lines) + "\n")
    text = "".join(body)
    ids = [int(n) for n in re.findall(r"^- \*\*R([0-9]+)\*\*", text, re.M)]
    superseded = len(re.findall(r"^  Superseded by R", text, re.M))
    withdrawn = len(re.findall(r"^  Withdrawn\.", text, re.M))
    return (_HEAD % (max(ids) + 1, len(ids) - superseded - withdrawn,
                     superseded, withdrawn)) + text


IF_A = "- **R2** — If the store is unreachable, then the widget shall stop."
IF_B = "- **R3** — If a ticket is filed twice, then the widget shall keep one."
WHEN_OLD = "- **R1** — When a ticket arrives, the widget shall store it."
UBI_OLD = "- **R4** — The widget shall keep one store."
FULL = ("Failure cases: input R2 · caller n/a because the widget has one "
        "caller · repeat R3 · dependency R2")
# <!-- EXAMPLE:END -->


def self_test(case, failures, validate_text, main, version):
    import io
    import sys
    import tempfile

    def codes(doc, code):
        return [p for p in doc.problems if p.code == code]

    def run(name, text):
        case(name)
        return validate_text(name + ".md", text, kind="spec")

    # <!-- EXAMPLE:BEGIN -->
    # ---- the line, read in one file: no base, no git -------------------
    doc = run("fc-line-valid", _spec(
        event=[WHEN_OLD, FULL],
        unwanted=[IF_A, IF_B]))
    if [p for p in doc.problems if p.severity == "ERROR"]:
        failures.append("fc-line-valid: %s" % [p.code for p in doc.problems])
    first = doc.requirements[0]
    if first.failure_cases_line == 0 or "Failure" in first.text:
        failures.append("fc-line-valid: the line was not read as R1's "
                        "Failure cases line (line %d, text %r)"
                        % (first.failure_cases_line, first.text))

    doc = run("fc-whole-na", _spec(event=[
        WHEN_OLD, "Failure cases: n/a because the widget only reads"]))
    if [p for p in doc.problems if p.severity == "ERROR"]:
        failures.append("fc-whole-na: %s" % [p.code for p in doc.problems])
    if parse("n/a because it only reads").covered() != set(CASE_NAMES):
        failures.append("fc-whole-na: one n/a with a reason did not cover "
                        "all four cases")

    doc = run("fc-malformed", _spec(event=[
        "- **R1** — When a ticket arrives, the widget shall store it.",
        "Failure cases: input R2 · input R2 · tenant R2 · repeat n/a · "
        "dependency maybe later",
        "- **R2** — When a ticket closes, the widget shall archive it.",
        "Failure cases: n/a",
        "- **R3** — When a ticket reopens, the widget shall restore it.",
        "Failure cases:"]))
    got = codes(doc, "FAILURE_CASES_MALFORMED")
    if len(got) != 6:
        failures.append("fc-malformed: %d FAILURE_CASES_MALFORMED, expected 6 "
                        "(twice, unknown case, n/a with no reason, a body "
                        "that is neither, a bare n/a, an empty line): %s"
                        % (len(got), [p.message for p in got]))

    doc = run("fc-ids", _spec(
        ubiquitous=["- **R5** — The widget shall keep one store."],
        event=["- **R1** — When a ticket arrives, the widget shall store it.",
               "Failure cases: input R9 · caller R4 · repeat R5 · "
               "dependency R2"],
        unwanted=[IF_A,
                  "- **R4** — If a ticket is lost, then the widget shall "
                  "say so.",
                  "  Superseded by R2. Merged.",
                  "- **R9** — If a ticket is late, then the widget shall "
                  "flag it.",
                  "  Withdrawn. Nothing is late."]))
    for code, ident in (("FAILURE_CASE_ID_INACTIVE", "R4"),
                        ("FAILURE_CASE_ID_NOT_UNWANTED", "R5")):
        hits = codes(doc, code)
        if not any(ident in p.message for p in hits):
            failures.append("fc-ids: expected %s naming %s, got %s"
                            % (code, ident, [p.code for p in doc.problems]))
    inactive = codes(doc, "FAILURE_CASE_ID_INACTIVE")
    if len(inactive) != 2:
        failures.append("fc-ids: a superseded and a withdrawn id should each "
                        "be FAILURE_CASE_ID_INACTIVE, got %d" % len(inactive))
    doc = run("fc-ids-no-then", _spec(event=[
        "- **R1** — When a ticket arrives, the widget shall store it.",
        "Failure cases: input R6 · caller R2 · repeat R2 · dependency R2"],
        unwanted=[IF_A, "- **R6** — If the store is unreachable, the widget "
                  "shall keep the ticket in memory."]))
    hits = codes(doc, "FAILURE_CASE_ID_NOT_UNWANTED")
    if len(hits) != 1 or "R6" not in hits[0].message:
        failures.append("fc-ids-no-then: an `If` with no `then` should be "
                        "FAILURE_CASE_ID_NOT_UNWANTED, got %s"
                        % [p.code for p in doc.problems])
    doc = run("fc-ids-unknown", _spec(event=[
        "- **R1** — When a ticket arrives, the widget shall store it.",
        "Failure cases: input R7 · caller R2 · repeat R2 · dependency R2"],
        unwanted=[IF_A]))
    hits = codes(doc, "FAILURE_CASE_ID_UNKNOWN")
    if len(hits) != 1 or "R7" not in hits[0].message:
        failures.append("fc-ids-unknown: an id the spec does not define "
                        "should be FAILURE_CASE_ID_UNKNOWN, got %s"
                        % [p.code for p in doc.problems])

    doc = run("fc-misplaced", _spec(
        event=["- **R1** — When a ticket arrives, the widget shall store it.",
               "  " + FULL,
               "- **R5** — When a ticket closes, the widget shall archive it.",
               "",
               FULL,
               "- **R6** — When a ticket reopens, the widget shall restore it.",
               FULL,
               "  Superseded by R8. Reopening was retired.",
               "- **R7** — When a ticket moves, the widget shall log it.",
               FULL,
               FULL,
               "- **R8** — When a ticket reopens, the widget shall log it."],
        unwanted=[IF_A, IF_B]))
    got = codes(doc, "FAILURE_CASES_MISPLACED")
    if len(got) != 4:
        failures.append("fc-misplaced: %d FAILURE_CASES_MISPLACED, expected 4 "
                        "(indented, after a blank, a marker after it, a "
                        "second line): %s" % (len(got), [p.message for p in got]))
    if codes(doc, "EARS_NO_FULL_STOP"):
        failures.append("fc-misplaced: the indented line was read into R1's "
                        "sentence")
    if doc.requirements[0].failure_cases_line:
        failures.append("fc-misplaced: an indented line was accepted as R1's "
                        "Failure cases line")

    # ---- coverage and the checked set, as functions ---------------------
    case("fc-coverage")
    doc = validate_text("fc-coverage.md", _spec(event=[
        "- **R1** — When a ticket arrives, the widget shall store it.",
        "- **R5** — When a ticket closes, the widget shall archive it.",
        "Failure cases: input R2 · repeat R3",
        "- **R6** — When a ticket reopens, the widget shall restore it.",
        "Failure cases: n/a because it only reads"],
        unwanted=[IF_A, IF_B]), kind="spec")
    check_coverage(doc, {"R1", "R5", "R6"}, "ERROR")
    missing = codes(doc, "FAILURE_CASES_MISSING")
    uncovered = codes(doc, "FAILURE_CASE_UNCOVERED")
    if len(missing) != 1 or "R1" not in missing[0].message:
        failures.append("fc-coverage: R1 has no line and was not reported "
                        "FAILURE_CASES_MISSING: %s" % [p.message for p in missing])
    named = sorted(p.message.split("`")[1] for p in uncovered)
    if named != ["caller", "dependency"]:
        failures.append("fc-coverage: R5 covers input and repeat; the "
                        "uncovered cases reported were %s, expected caller "
                        "and dependency" % named)
    for name, words in CASES:
        if missing and name not in missing[0].message:
            failures.append("fc-coverage: the MISSING finding does not name "
                            "the case %s" % name)

    case("fc-checked-ids")
    base = validate_text("fc-base.md", _spec(
        ubiquitous=[UBI_OLD], event=[WHEN_OLD,
                                     "- **R9** — When a ticket moves, the "
                                     "widget shall log it.",
                                     "Failure cases: n/a because a log "
                                     "changes no ticket"],
        unwanted=[IF_A]), kind="spec")
    now = validate_text("fc-now.md", _spec(
        event=[WHEN_OLD,
               "- **R4** — When a ticket closes, the widget shall keep one "
               "store.",
               "- **R5** — When a ticket reopens, the widget shall restore it.",
               "- **R8** — While a ticket is open, the widget shall show it."],
        unwanted=[IF_A,
                  "- **R7** — If a ticket is lost, then the widget shall say "
                  "so."],
        optional=["- **R6** — Where tickets are archived, the widget shall "
                  "compress them.",
                  "- **R9** — Where tickets are logged, the widget shall log "
                  "a move."]), kind="spec")
    checked, new = checked_ids([now], [base])
    if set(checked) != {"R4", "R5", "R8", "R9"} or new != 4:
        failures.append("fc-checked-ids: checked %s with %d new; expected R4 "
                        "(made event-driven), R5 (new), R8 (filed under "
                        "Event-driven), R9 (carried a line at the base) and 4 "
                        "new - R1 was an active event-driven requirement at "
                        "the base with no line" % (sorted(checked), new))
    if checked.get("R9") != WHY_HAD_LINE or checked.get("R4") != WHY_GAINED:
        failures.append("fc-checked-ids: the reasons were %s" % checked)

    # A trigger read from the sentence, never from a cached pattern: a
    # placeholder-bearing `When` (EARS skips it), and `While/Where ..., when`.
    case("fc-trigger-sentence")
    now = validate_text("fc-trigger.md", _spec(
        ubiquitous=["- **R5** — When a person runs `purge <ticket>`, the "
                    "widget shall delete that ticket."],
        state=["- **R6** — While a ticket is open, when a person deletes it, "
               "the widget shall purge it."],
        optional=["- **R7** — Where tickets are archived, when a person "
                  "closes a ticket, the widget shall delete it.",
                  "- **R8** — Where tickets are archived, the widget shall "
                  "compress them when asked."]), kind="spec")
    checked, new = checked_ids([now], [])
    if set(checked) != {"R5", "R6", "R7"}:
        failures.append("fc-trigger-sentence: checked %s; expected R5 (a "
                        "`When` holding `<ticket>`), R6 (`While ..., when`) "
                        "and R7 (`Where ..., when`), not R8 (its `when` is "
                        "after `shall`)" % sorted(checked))
    # <!-- EXAMPLE:END -->

    # ---- through main, against real git history -------------------------
    sandbox = tempfile.mkdtemp(prefix="validate-spec-failure-cases.")
    genv = dict(os.environ, GIT_CONFIG_NOSYSTEM="1",
                GIT_CONFIG_GLOBAL=os.devnull, GIT_AUTHOR_NAME="t",
                GIT_AUTHOR_EMAIL="t@example.invalid", GIT_COMMITTER_NAME="t",
                GIT_COMMITTER_EMAIL="t@example.invalid")

    def git(repo, *args):
        proc = subprocess.run(["git", "-C", repo] + list(args), env=genv,
                              capture_output=True, text=True)
        if proc.returncode != 0:
            raise RuntimeError("git %s: %s" % (" ".join(args), proc.stderr))
        return proc.stdout

    def write(repo, text):
        home = os.path.join(repo, ".claude", "productizer")
        os.makedirs(home, exist_ok=True)
        with open(os.path.join(home, "spec.md"), "w", encoding="utf-8") as fh:
            fh.write(text)

    def commit(repo, message):
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "--no-verify", "-m", message)
        return git(repo, "rev-parse", "HEAD").strip()

    def drive(name, argv, want, needles=(), absent=()):
        case(name)
        out, err = io.StringIO(), io.StringIO()
        saved = sys.stdout, sys.stderr
        sys.stdout, sys.stderr = out, err
        try:
            status = main(argv)
        finally:
            sys.stdout, sys.stderr = saved
        text = out.getvalue() + err.getvalue()
        if status != want:
            failures.append("%s: exit %d, expected %d: %s"
                            % (name, status, want, text.strip()[-400:]))
        for needle in needles:
            if needle not in text:
                failures.append("%s: output lacks %r: %s"
                                % (name, needle, text.strip()[-400:]))
        for needle in absent:
            if needle in text:
                failures.append("%s: output holds %r: %s"
                                % (name, needle, text.strip()[-400:]))
        return text

    # <!-- EXAMPLE:BEGIN -->
    BASE = _spec(ubiquitous=[UBI_OLD], event=[WHEN_OLD], unwanted=[IF_A, IF_B])
    NEW_WHEN = "- **R5** — When a ticket closes, the widget shall archive it."
    try:
        if shutil.which("git") is None:
            failures.append("fc-git: git is not on PATH, so no base case was "
                            "driven. Unmeasured, not clean")
            return
        repo = os.path.join(sandbox, "repo")
        os.makedirs(repo)
        git(repo, "init", "-q")
        write(repo, BASE)
        base_sha = commit(repo, "base")
        fc = ["--repo", repo, "--failure-cases"]

        # The gap B191 closed: the per-file run passes a new `When` with no
        # line, and the rule against the base does not.
        write(repo, _spec(ubiquitous=[UBI_OLD], event=[WHEN_OLD, NEW_WHEN],
                          unwanted=[IF_A, IF_B]))
        drive("fc-gap-plain", ["--repo", repo], 0, ("0 error(s)",))
        drive("fc-gap", fc, 1,
              ("FAILURE_CASES_MISSING: R5", "HEAD, because the spec in the "
               "work tree differs", "examined: .claude/productizer/spec.md@",
               "failure cases (R5)"), ("MISSING: R1 ",))

        write(repo, _spec(ubiquitous=[UBI_OLD,
                                      "- **R5** — The widget shall keep one "
                                      "log."],
                          event=[WHEN_OLD], unwanted=[IF_A, IF_B],
                          state=["- **R6** — While a ticket is open, the "
                                 "widget shall show it."],
                          optional=["- **R7** — Where tickets are archived, "
                                    "the widget shall compress them."]))
        drive("fc-old-exempt", fc, 0,
              ("3 requirement(s) new against the base, 0 requirement(s) "
               "checked",
               "0 finding(s)"), ("FAILURE_CASES_MISSING",))

        write(repo, _spec(ubiquitous=[UBI_OLD],
                          event=[WHEN_OLD, NEW_WHEN, FULL],
                          unwanted=[IF_A, IF_B]))
        drive("fc-covered", fc, 0, ("failure cases (R5)", "0 finding(s)"))

        write(repo, _spec(ubiquitous=[UBI_OLD],
                          event=[WHEN_OLD, NEW_WHEN,
                                 "Failure cases: input R2 · repeat R3 · "
                                 "dependency R2"],
                          unwanted=[IF_A, IF_B]))
        drive("fc-uncovered", fc, 1,
              ("FAILURE_CASE_UNCOVERED: R5: the failure case `caller`",),
              ("`input` (", "`repeat` (", "`dependency` ("))

        write(repo, _spec(event=[WHEN_OLD,
                                 "- **R4** — When a ticket closes, the widget "
                                 "shall keep one store."],
                          unwanted=[IF_A, IF_B]))
        drive("fc-refine", fc, 1, ("FAILURE_CASES_MISSING: R4",))

        write(repo, _spec(ubiquitous=[UBI_OLD],
                          event=[WHEN_OLD,
                                 "- **R5** — While a ticket is open, the "
                                 "widget shall show it."],
                          unwanted=[IF_A, IF_B]))
        drive("fc-section", fc, 1, ("FAILURE_CASES_MISSING: R5",))

        # Committed: the work tree matches HEAD, so the base is the commit
        # before the last spec change - and stays there across a commit that
        # changes something else.
        write(repo, _spec(ubiquitous=[UBI_OLD], event=[WHEN_OLD, NEW_WHEN],
                          unwanted=[IF_A, IF_B]))
        spec_sha = commit(repo, "add R5 with no line")
        drive("fc-walk", fc, 1,
              ("FAILURE_CASES_MISSING: R5", "base %s (the first parent of %s"
               % (base_sha, spec_sha[:12])))
        with open(os.path.join(repo, "notes.txt"), "w") as fh:
            fh.write("unrelated\n")
        commit(repo, "touch something else")
        drive("fc-walk-later", fc, 1,
              ("FAILURE_CASES_MISSING: R5", "base %s" % base_sha))
        drive("fc-base-named", fc + ["--base", base_sha], 1,
              ("named by --base", "FAILURE_CASES_MISSING: R5"))
        drive("fc-base-head", fc + ["--base", "HEAD"], 0,
              ("0 requirement(s) new against the base",))

        shallow = os.path.join(sandbox, "shallow")
        git(sandbox, "clone", "-q", "--depth", "1", "file://" + repo, shallow)
        drive("fc-no-base-shallow", ["--repo", shallow, "--failure-cases"], 4,
              ("FAILURE_CASES_NO_BASE", "shallow clone", "NOT MEASURED"),
              ("file(s) checked",))
        write(shallow, _spec(ubiquitous=[UBI_OLD],
                             event=[WHEN_OLD, NEW_WHEN,
                                    "- **R6** — When a ticket moves, the "
                                    "widget shall log it."],
                             unwanted=[IF_A, IF_B]))
        drive("fc-shallow-dirty", ["--repo", shallow, "--failure-cases"], 1,
              ("FAILURE_CASES_MISSING: R6", "HEAD, because"),
              ("FAILURE_CASES_MISSING: R5",))

        # Coverage removed or weakened on a requirement that carried a line
        # at the base is judged again (review #3); an untouched line passes.
        lined = os.path.join(sandbox, "lined")
        os.makedirs(lined)
        git(lined, "init", "-q")
        write(lined, _spec(ubiquitous=[UBI_OLD],
                           event=[WHEN_OLD, NEW_WHEN, FULL],
                           unwanted=[IF_A, IF_B]))
        lined_sha = commit(lined, "R5 with its line")
        lfc = ["--repo", lined, "--failure-cases", "--base", lined_sha]
        drive("fc-line-kept", lfc, 0,
              ("failure cases (R5)", "0 finding(s)"))
        write(lined, _spec(ubiquitous=[UBI_OLD], event=[WHEN_OLD, NEW_WHEN],
                           unwanted=[IF_A, IF_B]))
        drive("fc-line-deleted", lfc, 1,
              ("FAILURE_CASES_MISSING: R5 carried a `Failure cases` line at "
               "the base",))
        write(lined, _spec(ubiquitous=[UBI_OLD],
                           event=[WHEN_OLD, NEW_WHEN,
                                  "Failure cases: input R2 · repeat R3 · "
                                  "dependency R2"],
                           unwanted=[IF_A, IF_B]))
        drive("fc-line-weakened", lfc, 1,
              ("FAILURE_CASE_UNCOVERED: R5: the failure case `caller`",))

        single = os.path.join(sandbox, "single")
        os.makedirs(single)
        git(single, "init", "-q")
        write(single, BASE)
        commit(single, "founding")
        drive("fc-no-base-single", ["--repo", single, "--failure-cases"], 4,
              ("FAILURE_CASES_NO_BASE", "repository's first commit",
               "NOT MEASURED"))
        # One spec commit that HAS a parent: the base resolves to that parent,
        # where the spec is absent, so every requirement is new (review #9).
        founding = os.path.join(sandbox, "founding")
        os.makedirs(founding)
        git(founding, "init", "-q")
        with open(os.path.join(founding, "README"), "w") as fh:
            fh.write("first\n")
        commit(founding, "an unrelated first commit")
        write(founding, BASE)
        commit(founding, "the spec arrives")
        drive("fc-founding-with-parent",
              ["--repo", founding, "--failure-cases"], 1,
              ("absent at the base", "FAILURE_CASES_MISSING: R1",
               "the first parent of"))
        drive("fc-no-base-ref", fc + ["--base", "no-such-ref"], 4,
              ("FAILURE_CASES_NO_BASE", "--base no-such-ref names no commit"))

        loose = os.path.join(sandbox, "loose")
        os.makedirs(loose)
        write(loose, BASE)
        saved_ceiling = os.environ.get("GIT_CEILING_DIRECTORIES")
        os.environ["GIT_CEILING_DIRECTORIES"] = sandbox
        try:
            drive("fc-no-base-not-git", ["--repo", loose, "--failure-cases"],
                  4, ("FAILURE_CASES_NO_BASE", "not inside a git work tree",
                      "fatal:"))
        finally:
            if saved_ceiling is None:
                os.environ.pop("GIT_CEILING_DIRECTORIES", None)
            else:
                os.environ["GIT_CEILING_DIRECTORIES"] = saved_ceiling

        drive("fc-usage-no-repo", ["--failure-cases", "x.md"], 2,
              ("takes --repo ROOT",))
        drive("fc-usage-base-alone", ["--repo", repo, "--base", "HEAD"], 2,
              ("without --failure-cases",))
        drive("fc-version", ["--version"], 0, (version,))
    except RuntimeError as exc:
        failures.append("fc-git: a fixture repository could not be built, so "
                        "the base cases were not driven: %s" % exc)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)
    # <!-- EXAMPLE:END -->

