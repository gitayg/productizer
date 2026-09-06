#!/usr/bin/env python3
"""Enforce the Productizer spec format as a grammar rather than as prose.

Checks `.claude/productizer/spec.md`, `constitution.md` and `backlog.md` against the
normative grammar in `references/format-spec.md`. Two invariants carry the
lifecycle and neither survives being stated only in prose:

  1. Requirements are EARS — one sentence, one `shall`, a named trigger and an
     observable response.
  2. Ids are permanent. Never reused, never renumbered, and a superseded
     requirement keeps its original text verbatim.

Severities
    ERROR  the document cannot be parsed, a permanence invariant is broken, or
           the header states a number about the file that disagrees with the
           file. Downstream citations (plans, tests, PR titles, review
           findings) stop resolving, or resolve to the wrong requirement; and a
           header count that nobody re-counted is a measurement nobody took,
           which is constitution P1 and not a matter of taste.
    WARN   the document parses and the ids hold, but the contract is violated
           in a way a later reader or tool silently mangles or half-tests.

Exit codes
    0  clean (no ERROR; with --strict, also no WARN)
    1  at least one ERROR (with --strict, at least one WARN)
    2  usage error
    3  --self-test failed
    4  NOT MEASURED — a file could not be read, its kind could not be
       determined, or it holds no requirements/principles to check. This is
       never reported as "0 errors": a spec that was not read has not passed.

Usage
    validate-spec.py [--strict] [--quiet] [--kind spec|constitution|backlog] FILE...
    validate-spec.py --baseline OLD_SPEC.md NEW_SPEC.md
    validate-spec.py --counts SPEC.md
    validate-spec.py --format speckit SPEC.md
    validate-spec.py --self-test

Input formats
    --format productizer  (default) the grammar above, read as written.
    --format speckit      a GitHub spec-kit `spec.md`. Seven mechanical
                          rewrites move the notation into this grammar IN
                          MEMORY -- the file on disk is never written -- and
                          the checks then run unchanged. Diagnostics are
                          reported against the SOURCE line. The checks that
                          cannot apply to spec-kit input are printed as `n/a`
                          and suppressed rather than passing silently. See
                          `speckit_adapt.py` and
                          `references/speckit-format.md`.

Deterministic: no wall clock, no environment, no network is read, and problems
are emitted sorted by (line, code, message). Two runs of the same input are
byte-identical. Python 3.8+, standard library only.
"""

from __future__ import annotations

import argparse
import difflib
import re
import sys
from dataclasses import dataclass, field

ERROR = "ERROR"
WARN = "WARN"

EXIT_CLEAN = 0
EXIT_FAILED = 1
EXIT_USAGE = 2
EXIT_SELFTEST = 3
EXIT_UNMEASURED = 4

# --------------------------------------------------------------------------
# Grammar
# --------------------------------------------------------------------------

EXAMPLE_BEGIN = "EXAMPLE:BEGIN"
EXAMPLE_END = "EXAMPLE:END"

# `- **R14** — When an intent arrives, the lifecycle shall ...`
BULLET_RE = re.compile(r"^-\s+\*\*(?P<id>[^*]+?)\*\*\s*(?P<sep>\S)?\s*(?P<text>.*)$")
REQ_ID_RE = re.compile(r"^R(?P<n>[1-9][0-9]*)$")
PRINCIPLE_ID_RE = re.compile(r"^P(?P<n>[1-9][0-9]*)$")
BACKLOG_ID_RE = re.compile(r"^B(?P<n>[1-9][0-9]*)$")
CANONICAL_SEP = "—"  # em dash

HEADING_RE = re.compile(r"^(?P<hashes>#{1,6})\s+(?P<title>.*?)\s*$")

# `### P1 — A value that was not measured is never recorded as a measurement`
PRINCIPLE_HEADING_RE = re.compile(
    r"^(?P<id>\S+)\s*(?P<sep>\S)?\s*(?P<title>.*)$")

SUPERSEDED_RE = re.compile(
    r"^Superseded by\s+(?P<target>R[0-9]+)\s*\.?\s*(?P<reason>.*)$")
WITHDRAWN_RE = re.compile(r"^Withdrawn\s*\.?\s*(?P<reason>.*)$")
STATUS_START_RE = re.compile(r"^(superseded|withdrawn)\b", re.I)

P_SUPERSEDED_RE = re.compile(
    r"^Superseded by\s+(?P<target>P[0-9]+)\s*(?P<date>\d{4}-\d{2}-\d{2})?\s*\.?\s*"
    r"(?P<reason>.*)$")
P_WITHDRAWN_RE = re.compile(
    r"^Withdrawn\s*(?P<date>\d{4}-\d{2}-\d{2})?\s*\.?\s*[—-]?\s*(?P<reason>.*)$")
P_ACTIVE_RE = re.compile(r"^Active\s*\.?\s*(?P<rest>.*)$")

PLACEHOLDER_RE = re.compile(r"<[^<>]*>")
DEFLIST_VALUE_RE = re.compile(r"^:\s*(?P<value>.*)$")
BACKTICK_RE = re.compile(r"`([^`]*)`")

COUNT_WORDS = ("active", "superseded", "withdrawn")
DECLARED_COUNT_RE = re.compile(r"(\d+)\s+(active|superseded|withdrawn)", re.I)

CITATION_RE = re.compile(r"\bR([1-9][0-9]*)\b")
CITATION_RANGE_RE = re.compile(r"\bR([1-9][0-9]*)\s*[–—-]\s*R?([1-9][0-9]*)\b")

# EARS clause openers, longest-first so `While ..., when ...` wins over `While`.
EARS_PATTERNS = [
    ("complex", re.compile(
        r"^While\s+.+?,\s*when\s+.+?,\s*(the|every)\s+.+?\s+shall\s+.+$", re.S)),
    ("state", re.compile(r"^While\s+.+?,\s*(the|every)\s+.+?\s+shall\s+.+$", re.S)),
    ("event", re.compile(r"^When\s+.+?,\s*(the|every)\s+.+?\s+shall\s+.+$", re.S)),
    ("unwanted", re.compile(
        r"^If\s+.+?,\s*(then\s+)?(the|every)\s+.+?\s+shall\s+.+$", re.S)),
    ("optional", re.compile(r"^Where\s+.+?,\s*(the|every)\s+.+?\s+shall\s+.+$", re.S)),
    ("ubiquitous", re.compile(r"^(The|Every)\s+.+?\s+shall\s+.+$", re.S)),
]

SECTION_PATTERNS = {
    "ubiquitous": "ubiquitous",
    "event-driven": "event",
    "event": "event",
    "state-driven": "state",
    "state": "state",
    "unwanted behaviour": "unwanted",
    "unwanted behavior": "unwanted",
    "unwanted": "unwanted",
    "optional": "optional",
    "optional feature": "optional",
    "complex": "complex",
}

# Adjectives that defer the argument to review instead of settling it. Each one
# is un-assertable: no test can decide whether it holds.
UNQUANTIFIED = [
    "adequate", "adequately", "appropriate", "appropriately", "as needed",
    "easy", "efficient", "efficiently", "fast", "flexible", "gracefully",
    "intuitive", "optimal", "performant", "properly", "quick", "quickly",
    "reasonable", "reasonably", "reliable", "reliably", "robust", "scalable",
    "seamless", "seamlessly", "sufficient", "sufficiently", "timely",
    "user-friendly", "where possible",
]
UNQUANTIFIED_RE = re.compile(
    r"\b(" + "|".join(re.escape(w) for w in UNQUANTIFIED) + r")\b", re.I)

# The same deferral wearing a number's clothes. `quickly` is caught above and
# `a second or two` was not, though neither can be asserted by a test - and
# `roughly 500 ms` is the worst of them, because it reads as measured. A hedge
# is only matched WHERE IT QUALIFIES A QUANTITY: "about" before a digit is a
# tolerance nobody stated, "about" before a noun is ordinary prose and is left
# alone, which is why the digit is required rather than the word being listed.
VAGUE_QUANTITY_RE = re.compile(
    r"\b("
    r"an?\s+(?:millisecond|second|minute|hour|day|week|month|year)s?\s+or\s+two"
    r"|(?:a\s+few|a\s+couple\s+of|a\s+handful\s+of|several)\s+"
    r"(?:ms|milliseconds?|seconds?|minutes?|hours?|days?|weeks?|months?|years?"
    r"|bytes?|kb|mb|gb|requests?|items?|records?|times?)"
    r"|(?:roughly|approximately|about|around|circa|~)\s*\d+"
    r"|\d+\s*ish"
    r")\b", re.I)

# Sections whose R-citations must resolve. Deliberately excludes
# "How to read this file" and "Requirement index" — see format-spec.md.
CITED_SECTIONS = {
    "acceptance criteria", "change log", "areas of concern",
    "decision record", "design",
}

BACKLOG_STATUSES = {"todo", "long-term", "in-progress", "blocked", "done"}

MAX_PRINCIPLES = 8
IDENTITY_RATIO = 0.5


# --------------------------------------------------------------------------
# Model
# --------------------------------------------------------------------------

@dataclass
class Problem:
    line: int
    severity: str
    code: str
    message: str

    def key(self):
        return (self.line, self.code, self.message)


@dataclass
class Requirement:
    ident: str
    number: int
    line: int
    text: str
    section: str = ""
    pattern: str = ""
    status: str = "active"
    status_line: int = 0
    supersedes_target: str = ""
    reason: str = ""


@dataclass
class Principle:
    ident: str
    number: int
    line: int
    title: str
    status: str = "active"
    status_line: int = 0
    target: str = ""
    checked_by: str = ""
    enforced_by: list = field(default_factory=list)


@dataclass
class BacklogItem:
    ident: str
    number: int
    line: int
    status: str
    jira: str


@dataclass
class Document:
    path: str
    kind: str = "unknown"
    requirements: list = field(default_factory=list)
    principles: list = field(default_factory=list)
    items: list = field(default_factory=list)
    citations: list = field(default_factory=list)
    fields: dict = field(default_factory=dict)
    sections: set = field(default_factory=set)
    problems: list = field(default_factory=list)
    unmeasured: bool = False

    def add(self, line, severity, code, message):
        self.problems.append(Problem(line, severity, code, message))


def normalise(text):
    """Comparison form: case, whitespace, markup and trailing stop removed."""
    stripped = text.replace("`", "").replace("*", "").replace("_", "")
    stripped = re.sub(r"\s+", " ", stripped).strip().lower()
    return stripped.rstrip(".")


def strip_placeholders(text):
    return PLACEHOLDER_RE.sub("", text)


def has_placeholder(text):
    return bool(PLACEHOLDER_RE.search(text))


def slug(title):
    plain = title.replace("`", "").strip().lower()
    plain = plain.split("—")[0].split(" - ")[0]
    return re.sub(r"\s+", " ", plain).strip()


# --------------------------------------------------------------------------
# Shared line walking
# --------------------------------------------------------------------------

def iter_lines(text):
    """Yield (lineno, line) skipping EXAMPLE blocks and HTML comments.

    Scaffolding deletes EXAMPLE blocks, so their contents are template prose
    and never agreed content. Validating them would report a template as a
    broken spec.
    """
    in_example = False
    for index, raw in enumerate(text.splitlines(), start=1):
        if EXAMPLE_BEGIN in raw:
            in_example = True
            continue
        if EXAMPLE_END in raw:
            in_example = False
            continue
        if in_example:
            continue
        yield index, raw


def read_fields(text):
    """Definition-list header fields: a name line followed by `: value`."""
    fields = {}
    lines = list(iter_lines(text))
    for position, (lineno, raw) in enumerate(lines):
        if not raw.strip() or raw.startswith(("#", "-", "|", " ", "\t", ":")):
            continue
        if position + 1 >= len(lines):
            continue
        following = lines[position + 1][1]
        match = DEFLIST_VALUE_RE.match(following)
        if match:
            fields[raw.strip()] = (lineno, match.group("value"))
    return fields


def field_number(doc, name, prefix, missing_code, malformed_code):
    """Read a `Next <thing> id` counter. Returns None when unusable."""
    entry = doc.fields.get(name)
    if entry is None:
        doc.add(1, ERROR, missing_code,
                "no `%s` field: allocation cannot be checked, so id reuse "
                "cannot be ruled out" % name)
        return None
    lineno, value = entry
    backtick = BACKTICK_RE.search(value)
    if backtick:
        token = backtick.group(1).strip()
    else:
        words = value.split()
        token = words[0].strip() if words else ""
    if not token:
        doc.add(lineno, ERROR, malformed_code,
                "`%s` has no value; allocation cannot be checked, so id reuse "
                "cannot be ruled out" % name)
        return None
    if has_placeholder(token):
        return None  # unscaffolded template: tolerated, see format-spec.md
    match = re.match(r"^%s([1-9][0-9]*)$" % prefix, token)
    if not match:
        doc.add(lineno, ERROR, malformed_code,
                "`%s` is `%s`, not `%s<n>`; allocation cannot be checked"
                % (name, token, prefix))
        return None
    return int(match.group(1))


# --------------------------------------------------------------------------
# Spec parsing
# --------------------------------------------------------------------------

def parse_spec(doc, text):
    section = ""
    pattern_section = ""
    in_requirements = False
    current = None
    blank_since_bullet = False

    for lineno, raw in iter_lines(text):
        heading = HEADING_RE.match(raw)
        if heading:
            level = len(heading.group("hashes"))
            title = slug(heading.group("title"))
            if level <= 2:
                section = title
                doc.sections.add(title)
                in_requirements = title == "requirements"
                pattern_section = ""
                current = None
            elif level == 3 and in_requirements:
                pattern_section = SECTION_PATTERNS.get(title, "")
                current = None
            continue

        if not raw.strip():
            blank_since_bullet = True
            continue

        if in_requirements:
            bullet = BULLET_RE.match(raw)
            if bullet:
                current = read_requirement(doc, lineno, bullet, pattern_section)
                blank_since_bullet = False
                continue
            if raw.startswith("- "):
                doc.add(lineno, ERROR, "ID_MALFORMED",
                        "bullet in the Requirements section carries no "
                        "`**R<n>**` id: %s" % raw.strip()[:70])
                current = None
                continue
            if current is not None and not blank_since_bullet and raw[:1] in " \t":
                read_continuation(doc, lineno, raw.strip(), current)
                continue
            current = None
            continue

        if section in CITED_SECTIONS:
            collect_citations(doc, lineno, raw)


def read_requirement(doc, lineno, bullet, pattern_section):
    ident = bullet.group("id").strip()
    sep = bullet.group("sep") or ""
    text = bullet.group("text").strip()
    match = REQ_ID_RE.match(ident)
    if not match:
        doc.add(lineno, ERROR, "ID_MALFORMED",
                "requirement id `%s` is not `R<n>` with no leading zero; "
                "citations elsewhere name `R<n>` and will not resolve" % ident)
        return None
    if sep and sep != CANONICAL_SEP:
        doc.add(lineno, WARN, "ID_SEPARATOR",
                "`%s` uses `%s` after the id, not an em dash" % (ident, sep))
    elif not sep:
        text = ""
    requirement = Requirement(ident=ident, number=int(match.group("n")),
                              line=lineno, text=text,
                              section=pattern_section, pattern="")
    doc.requirements.append(requirement)
    return requirement


def read_continuation(doc, lineno, stripped, current):
    if STATUS_START_RE.match(stripped):
        if current.status != "active":
            doc.add(lineno, ERROR, "STATUS_DUPLICATE",
                    "%s carries a second status marker; a requirement has one "
                    "status" % current.ident)
            return
        superseded = SUPERSEDED_RE.match(stripped)
        if superseded:
            current.status = "superseded"
            current.status_line = lineno
            current.supersedes_target = superseded.group("target")
            current.reason = superseded.group("reason").strip()
            return
        withdrawn = WITHDRAWN_RE.match(stripped)
        if withdrawn:
            current.status = "withdrawn"
            current.status_line = lineno
            current.reason = withdrawn.group("reason").strip()
            return
        doc.add(lineno, ERROR, "STATUS_MALFORMED",
                "%s has a status marker that is neither `Superseded by R<n>.` "
                "nor `Withdrawn.`: %s" % (current.ident, stripped[:60]))
        return
    if current.status == "active":
        current.text = (current.text + " " + stripped).strip()


def collect_citations(doc, lineno, raw):
    if has_placeholder(raw):
        return
    for start, end in CITATION_RANGE_RE.findall(raw):
        low, high = int(start), int(end)
        if low <= high:
            for number in range(low, high + 1):
                doc.citations.append((lineno, "R%d" % number))
    for number in CITATION_RE.findall(raw):
        doc.citations.append((lineno, "R%s" % number))


# --------------------------------------------------------------------------
# Spec checks
# --------------------------------------------------------------------------

def check_spec(doc):
    if "requirements" not in doc.sections:
        doc.add(1, ERROR, "NO_REQUIREMENTS_SECTION",
                "no `## Requirements` heading: nothing in this file was "
                "checked")
        doc.unmeasured = True
        return
    if not doc.requirements:
        doc.add(1, ERROR, "NO_REQUIREMENTS",
                "`## Requirements` holds no `- **R<n>** —` bullets: nothing "
                "was measured, which is not the same as nothing being wrong")
        doc.unmeasured = True
        return

    counter = field_number(doc, "Next requirement id", "R",
                           "COUNTER_MISSING", "COUNTER_MALFORMED")
    check_spec_ids(doc, counter)
    check_spec_ears(doc)
    check_spec_status(doc)
    check_spec_counts(doc)
    check_spec_citations(doc)


def check_spec_ids(doc, counter):
    seen = {}
    for requirement in doc.requirements:
        first = seen.get(requirement.ident)
        if first is not None:
            doc.add(requirement.line, ERROR, "ID_REUSED",
                    "%s is already defined at line %d; an id names one "
                    "requirement for the life of the repo"
                    % (requirement.ident, first.line))
        else:
            seen[requirement.ident] = requirement
        if counter is not None and requirement.number >= counter:
            doc.add(requirement.line, ERROR, "ID_AT_OR_ABOVE_COUNTER",
                    "%s is at or above the declared next id R%d; the next "
                    "allocation will reuse it"
                    % (requirement.ident, counter))

    highest = {}
    for requirement in doc.requirements:
        previous = highest.get(requirement.section)
        if previous is not None and requirement.number < previous.number:
            doc.add(requirement.line, WARN, "ID_OUT_OF_ORDER",
                    "%s follows %s in the same section; ids are appended, so "
                    "a descending id is the signature of an insertion or a "
                    "renumber" % (requirement.ident, previous.ident))
        if previous is None or requirement.number > previous.number:
            highest[requirement.section] = requirement

    by_text = {}
    for requirement in doc.requirements:
        if requirement.status != "active" or not requirement.text:
            continue
        key = normalise(requirement.text)
        if key in by_text:
            doc.add(requirement.line, WARN, "TEXT_DUPLICATE",
                    "%s repeats the text of %s; one behaviour under two ids "
                    "splits its citations and only one gets tested"
                    % (requirement.ident, by_text[key].ident))
        else:
            by_text[key] = requirement


def check_spec_ears(doc):
    for requirement in doc.requirements:
        # Only active requirements are held to the EARS rules. A superseded or
        # withdrawn one is a frozen record of what was once agreed, and its text
        # must be retained verbatim (SUPERSEDED_TEXT_CHANGED is an ERROR). Judging
        # it against the current style makes a warning that cannot be cleared
        # without breaking the retention rule -- two of this skill's own rules in
        # direct collision. Found by splitting R14/R16/R21: the split could never
        # silence the warning, because the originals keep the text that raised it.
        if requirement.status != "active":
            continue
        text = requirement.text.strip()
        if not text:
            doc.add(requirement.line, ERROR, "EARS_EMPTY",
                    "%s has an id and no requirement text" % requirement.ident)
            continue
        if has_placeholder(text):
            continue  # unscaffolded template line; see format-spec.md
        shalls = len(re.findall(r"\bshall\b", text, re.I))
        if shalls == 0:
            doc.add(requirement.line, ERROR, "EARS_NO_SHALL",
                    "%s states no obligation: an EARS requirement says "
                    "`shall`" % requirement.ident)
            continue
        pattern = ""
        for name, regex in EARS_PATTERNS:
            if regex.match(text):
                pattern = name
                break
        requirement.pattern = pattern
        if not pattern:
            doc.add(requirement.line, ERROR, "EARS_PATTERN",
                    "%s matches no EARS pattern; it must open with `The`/"
                    "`Every`, `When`, `While`, `If`, or `Where` and name the "
                    "system before `shall`" % requirement.ident)
            continue
        if shalls > 1:
            doc.add(requirement.line, WARN, "EARS_MULTIPLE_SHALL",
                    "%s carries %d `shall` clauses; each is a separate "
                    "obligation under one id and will be half-tested"
                    % (requirement.ident, shalls))
        if pattern == "unwanted" and not re.match(r"^If\s+.+?,\s*then\b", text):
            doc.add(requirement.line, WARN, "EARS_IF_MISSING_THEN",
                    "%s is an `If` requirement without `then`; the grammar is "
                    "`If <trigger>, then the <system> shall <response>.`"
                    % requirement.ident)
        if requirement.section and pattern != requirement.section:
            doc.add(requirement.line, WARN, "EARS_SECTION_MISMATCH",
                    "%s is a %s requirement under the %s heading"
                    % (requirement.ident, pattern, requirement.section))
        if not text.endswith("."):
            doc.add(requirement.line, WARN, "EARS_NO_FULL_STOP",
                    "%s does not end in a full stop; one requirement is one "
                    "sentence" % requirement.ident)
        found = UNQUANTIFIED_RE.search(text)
        if found:
            doc.add(requirement.line, WARN, "EARS_UNQUANTIFIED",
                    "%s uses the unquantified term `%s`; give a number or "
                    "drop it" % (requirement.ident, found.group(1)))
        vague = VAGUE_QUANTITY_RE.search(text)
        if vague:
            doc.add(requirement.line, WARN, "EARS_VAGUE_QUANTITY",
                    "%s says `%s`, which states a quantity without settling "
                    "it; a bound a test can assert has one number and no "
                    "hedge" % (requirement.ident, vague.group(1).strip()))


def check_spec_status(doc):
    by_id = {}
    for requirement in doc.requirements:
        by_id.setdefault(requirement.ident, requirement)

    for requirement in doc.requirements:
        if requirement.status == "active":
            continue
        if not requirement.reason:
            doc.add(requirement.status_line, WARN, "STATUS_NO_REASON",
                    "%s is %s with no reason; the marker records that it "
                    "changed, not why" % (requirement.ident, requirement.status))
        if requirement.status != "superseded":
            continue
        target = requirement.supersedes_target
        if target == requirement.ident:
            doc.add(requirement.status_line, ERROR, "SUPERSEDE_SELF",
                    "%s is superseded by itself" % requirement.ident)
            continue
        replacement = by_id.get(target)
        if replacement is None:
            doc.add(requirement.status_line, WARN, "SUPERSEDE_TARGET_ABSENT",
                    "%s points at %s, which is not in this file; a citation "
                    "following the marker leads nowhere unless %s lives in "
                    "another file of a split spec"
                    % (requirement.ident, target, target))
            continue
        if replacement.number < requirement.number:
            doc.add(requirement.status_line, WARN, "SUPERSEDE_BACKWARD",
                    "%s is superseded by the lower id %s; a replacement takes "
                    "a newly allocated id" % (requirement.ident, target))
        if requirement.text and normalise(requirement.text) == normalise(
                replacement.text):
            doc.add(requirement.line, ERROR, "SUPERSEDED_TEXT_OVERWRITTEN",
                    "%s carries the text of %s, the requirement that replaced "
                    "it; a superseded requirement keeps its own original "
                    "sentence" % (requirement.ident, target))


def spec_counts(doc):
    """What the header declares, and what the requirements actually come to.

    Returns `(lineno, value, declared, counted)`. `declared` is empty when the
    header carries no counts or still carries a `<placeholder>`; `counted` is
    always all three words, because a status that is absent is zero of it and
    that zero WAS counted.

    The check and `--counts` both read this. Two callers counting the same
    file separately is how a report and a header end up disagreeing while each
    is self-consistent.
    """
    counted = {"active": 0, "superseded": 0, "withdrawn": 0}
    for requirement in doc.requirements:
        if requirement.status in counted:
            counted[requirement.status] += 1
    entry = doc.fields.get("Requirements")
    if entry is None:
        return 0, "", {}, counted
    lineno, value = entry
    if has_placeholder(value):
        return lineno, value, {}, counted
    declared = {}
    for number, word in DECLARED_COUNT_RE.findall(value):
        declared[word.lower()] = int(number)
    return lineno, value, declared, counted


def derived_count_value(value, counted):
    """`value` with every declared number replaced by the number counted.

    The surrounding prose and punctuation are kept, so a caller correcting the
    header substitutes a line this script derived rather than one a person
    typed from memory - which is the defect this check exists to catch.
    """
    def swap(match):
        return "%d %s" % (counted[match.group(2).lower()], match.group(2))
    return DECLARED_COUNT_RE.sub(swap, value)


def check_spec_counts(doc):
    lineno, _value, declared, counted = spec_counts(doc)
    if not declared:
        return
    for word in sorted(declared):
        if declared[word] != counted[word]:
            doc.add(lineno, ERROR, "COUNT_MISMATCH",
                    "header declares %d %s, the file holds %d; the header "
                    "states a number about this file that nobody re-counted"
                    % (declared[word], word, counted[word]))


def check_spec_citations(doc):
    known = {requirement.ident for requirement in doc.requirements}
    reported = set()
    for lineno, ident in doc.citations:
        if ident in known or (lineno, ident) in reported:
            continue
        reported.add((lineno, ident))
        doc.add(lineno, WARN, "CITATION_UNKNOWN",
                "cites %s, which this file does not define" % ident)


# --------------------------------------------------------------------------
# Constitution
# --------------------------------------------------------------------------

def parse_constitution(doc, text):
    section = ""
    current = None
    pending_field = ""

    for lineno, raw in iter_lines(text):
        heading = HEADING_RE.match(raw)
        if heading:
            level = len(heading.group("hashes"))
            title = heading.group("title")
            if level <= 2:
                section = slug(title)
                doc.sections.add(section)
                current = None
            elif level == 3 and section == "principles":
                current = read_principle(doc, lineno, title)
            continue

        if not raw.strip():
            pending_field = ""
            continue
        if current is None:
            continue

        stripped = raw.strip()
        if current.status_line == 0:
            read_principle_status(doc, lineno, stripped, current)
            continue
        value = DEFLIST_VALUE_RE.match(stripped)
        if value and pending_field:
            if pending_field.lower() == "checked by":
                current.checked_by = value.group("value").strip()
            elif pending_field.lower() == "enforced by":
                current.enforced_by = re.findall(r"\bR[1-9][0-9]*\b",
                                                 value.group("value"))
            pending_field = ""
            continue
        pending_field = stripped


def read_principle(doc, lineno, title):
    match = PRINCIPLE_HEADING_RE.match(title.strip())
    if match is None:
        doc.add(lineno, ERROR, "PRINCIPLE_MALFORMED",
                "principle heading carries no id: %s"
                % (title.strip()[:60] or "(empty heading)"))
        return None
    ident = match.group("id").strip()
    if REQ_ID_RE.match(ident):
        doc.add(lineno, ERROR, "PRINCIPLE_ID_PREFIX",
                "`%s` uses the requirement prefix inside `## Principles`; "
                "`R` and `P` never share a counter or a prefix" % ident)
        return None
    number = PRINCIPLE_ID_RE.match(ident)
    if not number:
        doc.add(lineno, ERROR, "PRINCIPLE_MALFORMED",
                "principle heading does not open with `P<n> — `: %s"
                % title.strip()[:60])
        return None
    principle = Principle(ident=ident, number=int(number.group("n")),
                          line=lineno, title=match.group("title").strip())
    doc.principles.append(principle)
    return principle


def read_principle_status(doc, lineno, stripped, current):
    superseded = P_SUPERSEDED_RE.match(stripped)
    if superseded:
        current.status = "superseded"
        current.status_line = lineno
        current.target = superseded.group("target")
        if not superseded.group("date"):
            doc.add(lineno, WARN, "PRINCIPLE_NO_DATE",
                    "%s is superseded without a `YYYY-MM-DD` date"
                    % current.ident)
        return
    if stripped.lower().startswith("withdrawn"):
        withdrawn = P_WITHDRAWN_RE.match(stripped)
        current.status = "withdrawn"
        current.status_line = lineno
        if withdrawn is None:
            doc.add(lineno, ERROR, "PRINCIPLE_STATUS_MALFORMED",
                    "%s has a withdrawal marker that is not "
                    "`Withdrawn <YYYY-MM-DD>.`: %s"
                    % (current.ident, stripped[:40]))
        elif not withdrawn.group("date"):
            doc.add(lineno, WARN, "PRINCIPLE_NO_DATE",
                    "%s is withdrawn without a `YYYY-MM-DD` date"
                    % current.ident)
        return
    active = P_ACTIVE_RE.match(stripped)
    if active:
        current.status = "active"
        current.status_line = lineno
        rest = active.group("rest")
        if not re.search(r"\d{4}-\d{2}-\d{2}", rest) or not re.search(
                r"\bby\b", rest, re.I):
            doc.add(lineno, WARN, "PRINCIPLE_NO_RATIFIER",
                    "%s is `Active.` without a ratification date and who "
                    "ratified it; an unratified bound is a draft"
                    % current.ident)
        return
    doc.add(lineno, ERROR, "PRINCIPLE_STATUS_MALFORMED",
            "%s opens with `%s`, not `Active.`, `Superseded by P<n> <date>.` "
            "or `Withdrawn <date>.`" % (current.ident, stripped[:40]))
    current.status_line = lineno


def check_constitution(doc, spec=None):
    if "principles" not in doc.sections:
        doc.add(1, ERROR, "NO_PRINCIPLES_SECTION",
                "no `## Principles` heading: nothing in this file was checked")
        doc.unmeasured = True
        return
    if not doc.principles:
        doc.add(1, ERROR, "NO_PRINCIPLES",
                "`## Principles` holds no `### P<n> — ` headings: nothing "
                "was measured")
        doc.unmeasured = True
        return

    counter = field_number(doc, "Next principle id", "P",
                           "PRINCIPLE_COUNTER_MISSING",
                           "PRINCIPLE_COUNTER_MALFORMED")
    seen = {}
    known = {principle.ident for principle in doc.principles}
    for principle in doc.principles:
        first = seen.get(principle.ident)
        if first is not None:
            doc.add(principle.line, ERROR, "PRINCIPLE_ID_REUSED",
                    "%s is already defined at line %d" % (principle.ident,
                                                          first.line))
        else:
            seen[principle.ident] = principle
        if counter is not None and principle.number >= counter:
            doc.add(principle.line, ERROR, "PRINCIPLE_ID_AT_OR_ABOVE_COUNTER",
                    "%s is at or above the declared next id P%d; the next "
                    "allocation will reuse it" % (principle.ident, counter))
        if principle.status_line == 0:
            doc.add(principle.line, ERROR, "PRINCIPLE_STATUS_MISSING",
                    "%s has no status line under its heading" % principle.ident)
        if principle.status == "superseded" and principle.target not in known:
            doc.add(principle.status_line, WARN,
                    "PRINCIPLE_SUPERSEDE_TARGET_ABSENT",
                    "%s points at %s, which this file does not define"
                    % (principle.ident, principle.target))
        if principle.status == "active" and not principle.checked_by:
            doc.add(principle.line, WARN, "PRINCIPLE_NO_CHECK",
                    "%s names no `Checked by`; a principle nothing checks is "
                    "a slogan" % principle.ident)
        if spec is not None:
            spec_ids = {r.ident for r in spec.requirements}
            for cited in principle.enforced_by:
                if cited not in spec_ids:
                    doc.add(principle.line, WARN, "PRINCIPLE_ENFORCED_UNKNOWN",
                            "%s says it is enforced by %s, which the spec does "
                            "not define" % (principle.ident, cited))

    active = [p for p in doc.principles if p.status == "active"]
    if len(active) > MAX_PRINCIPLES:
        doc.add(doc.principles[0].line, WARN, "PRINCIPLE_TOO_MANY",
                "%d active principles; a constitution past %d is a second "
                "spec and is read by nobody" % (len(active), MAX_PRINCIPLES))


# --------------------------------------------------------------------------
# Backlog
# --------------------------------------------------------------------------

def parse_backlog(doc, text):
    section = ""
    for lineno, raw in iter_lines(text):
        heading = HEADING_RE.match(raw)
        if heading:
            if len(heading.group("hashes")) <= 2:
                section = slug(heading.group("title"))
                doc.sections.add(section)
            continue
        if section != "items" or not raw.strip().startswith("|"):
            continue
        cells = [cell.strip() for cell in raw.strip().strip("|").split("|")]
        if len(cells) < 4 or has_placeholder(raw):
            continue
        ident = cells[0].replace("`", "")
        if ident.lower() in ("id", "") or set(ident) <= set("-: "):
            continue
        if not ident.startswith("B"):
            continue
        number = BACKLOG_ID_RE.match(ident)
        if not number:
            doc.add(lineno, ERROR, "BACKLOG_ID_MALFORMED",
                    "backlog id `%s` is not `B<n>`" % ident)
            continue
        doc.items.append(BacklogItem(ident=ident, number=int(number.group("n")),
                                     line=lineno,
                                     status=cells[2].replace("`", "").strip(),
                                     jira=cells[3].strip()))


def check_backlog(doc):
    if "items" not in doc.sections:
        doc.add(1, ERROR, "NO_BACKLOG_ITEMS_SECTION",
                "no `## Items` heading: nothing in this file was checked")
        doc.unmeasured = True
        return
    if not doc.items:
        doc.add(1, ERROR, "NO_BACKLOG_ITEMS",
                "`## Items` holds no `B<n>` rows: nothing was measured")
        doc.unmeasured = True
        return
    counter = field_number(doc, "Next backlog id", "B",
                           "BACKLOG_COUNTER_MISSING",
                           "BACKLOG_COUNTER_MALFORMED")
    seen = {}
    for item in doc.items:
        first = seen.get(item.ident)
        if first is not None:
            doc.add(item.line, ERROR, "BACKLOG_ID_REUSED",
                    "%s is already used at line %d" % (item.ident, first.line))
        else:
            seen[item.ident] = item
        if counter is not None and item.number >= counter:
            doc.add(item.line, ERROR, "BACKLOG_ID_AT_OR_ABOVE_COUNTER",
                    "%s is at or above the declared next id B%d; the next "
                    "allocation will reuse it" % (item.ident, counter))
        jira = item.jira.replace("—", "").replace("-", "").strip()
        if not jira and item.status.lower() not in BACKLOG_STATUSES:
            doc.add(item.line, WARN, "BACKLOG_STATUS_UNKNOWN",
                    "%s has status `%s`, which is not one of %s, and names no "
                    "Jira key that would own its status"
                    % (item.ident, item.status,
                       ", ".join(sorted(BACKLOG_STATUSES))))


# --------------------------------------------------------------------------
# Baseline comparison — the only place renumbering is fully decidable
# --------------------------------------------------------------------------

def check_baseline(doc, baseline):
    """Compare a spec against an earlier copy of itself.

    In-file checks cannot see a renumber: a spec renumbered wholesale is
    internally consistent. Against a baseline it is arithmetic.
    """
    old = {r.ident: r for r in baseline.requirements}
    new = {r.ident: r for r in doc.requirements}

    old_by_text = {}
    for requirement in baseline.requirements:
        if requirement.text:
            old_by_text.setdefault(normalise(requirement.text), requirement)

    for ident in sorted(old, key=lambda i: old[i].number):
        previous = old[ident]
        current = new.get(ident)
        if current is None:
            moved = None
            key = normalise(previous.text)
            for candidate in doc.requirements:
                if candidate.text and normalise(candidate.text) == key:
                    moved = candidate
                    break
            if moved is not None:
                doc.add(moved.line, ERROR, "RENUMBERED",
                        "the text of %s now carries the id %s; ids are never "
                        "renumbered, and every citation of %s now resolves to "
                        "different behaviour" % (ident, moved.ident, ident))
            else:
                doc.add(1, ERROR, "ID_DISAPPEARED",
                        "%s is in the baseline and not in this file; a "
                        "requirement is superseded or withdrawn, never deleted"
                        % ident)
            continue

        if previous.status in ("superseded", "withdrawn"):
            if normalise(previous.text) != normalise(current.text):
                doc.add(current.line, ERROR, "SUPERSEDED_TEXT_CHANGED",
                        "%s is %s and its text was edited; a %s requirement "
                        "keeps its original sentence verbatim, or the record "
                        "of what was agreed is gone"
                        % (ident, previous.status, previous.status))
            if current.status == "active":
                doc.add(current.line, WARN, "STATUS_REVERTED",
                        "%s was %s in the baseline and is active here"
                        % (ident, previous.status))
            continue

        if normalise(previous.text) == normalise(current.text):
            continue
        ratio = difflib.SequenceMatcher(
            None, normalise(previous.text), normalise(current.text)).ratio()
        if ratio < IDENTITY_RATIO:
            doc.add(current.line, ERROR, "ID_IDENTITY_CHANGED",
                    "%s was rewritten wholesale (similarity %.2f); a "
                    "refinement keeps the id, a different behaviour takes a "
                    "new one and supersedes the old" % (ident, ratio))
        elif previous.pattern and current.pattern and (
                previous.pattern != current.pattern):
            doc.add(current.line, ERROR, "PATTERN_CHANGED",
                    "%s changed EARS pattern from %s to %s; a different "
                    "trigger is a different requirement"
                    % (ident, previous.pattern, current.pattern))

    for ident, current in sorted(new.items(), key=lambda kv: kv[1].number):
        if ident in old:
            continue
        key = normalise(current.text)
        source = old_by_text.get(key)
        if source is not None and source.ident not in new:
            continue  # already reported as RENUMBERED above
        if source is not None:
            doc.add(current.line, ERROR, "RENUMBERED",
                    "%s repeats the text already agreed as %s; allocating a "
                    "second id for one behaviour splits its citations"
                    % (ident, source.ident))

    old_counter = field_number(baseline, "Next requirement id", "R",
                               "COUNTER_MISSING", "COUNTER_MALFORMED")
    new_counter = field_number(doc, "Next requirement id", "R",
                               "COUNTER_MISSING", "COUNTER_MALFORMED")
    baseline.problems = []
    if old_counter is not None and new_counter is not None:
        if new_counter < old_counter:
            doc.add(doc.fields["Next requirement id"][0], ERROR,
                    "COUNTER_REWOUND",
                    "next id went from R%d back to R%d; the counter never "
                    "rewinds" % (old_counter, new_counter))


# --------------------------------------------------------------------------
# Driving
# --------------------------------------------------------------------------

def detect_kind(text):
    if re.search(r"^##\s+Principles\s*$", text, re.M) or (
            "Next principle id" in text):
        return "constitution"
    if "Next backlog id" in text or re.search(r"^#\s+.*backlog\s*$", text,
                                              re.M | re.I):
        return "backlog"
    if re.search(r"^##\s+Requirements\s*$", text, re.M) or (
            "Next requirement id" in text):
        return "spec"
    return "unknown"


def build_document(path, text, kind):
    doc = Document(path=path, kind=kind)
    doc.fields = read_fields(text)
    if kind == "spec":
        parse_spec(doc, text)
    elif kind == "constitution":
        parse_constitution(doc, text)
    elif kind == "backlog":
        parse_backlog(doc, text)
    return doc


def load_document(path, text, kind=None):
    """Parse only. Checking is separate so a cross-document check never has to
    re-parse, and so no pass discards another pass's diagnostics."""
    resolved = kind or detect_kind(text)
    if resolved == "unknown":
        doc = Document(path=path, kind="unknown")
        doc.add(1, ERROR, "KIND_UNKNOWN",
                "not a Productizer spec, constitution or backlog: no "
                "`## Requirements`, `## Principles` or `Next backlog id`. "
                "Nothing was checked")
        doc.unmeasured = True
        return doc
    return build_document(path, text, resolved)


def check_document(doc, spec=None):
    if doc.kind == "spec":
        check_spec(doc)
    elif doc.kind == "constitution":
        check_constitution(doc, spec=spec)
    elif doc.kind == "backlog":
        check_backlog(doc)


def validate_text(path, text, kind=None, spec=None):
    doc = load_document(path, text, kind=kind)
    check_document(doc, spec=spec)
    return doc


def read_text(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def emit(doc, out):
    for problem in sorted(doc.problems, key=Problem.key):
        out.write("%s:%d: %s %s: %s\n" % (doc.path, problem.line,
                                          problem.severity, problem.code,
                                          problem.message))


# --------------------------------------------------------------------------
# spec-kit input
#
# The adapter lives in its own module and is imported LAZILY, so the default
# path -- `--format productizer`, which is every existing caller -- executes
# exactly the code it executed before, including when the adapter is absent or
# unimportable. A missing adapter is then NOT MEASURED and says so, rather than
# a run that quietly checked nothing.
# --------------------------------------------------------------------------

def import_adapter():
    """Import the adapter WITHOUT leaving a `__pycache__` beside it.

    `.gitignore` ignores `__pycache__/` on the stated premise that "nothing
    here imports these scripts as modules in normal use". This is the first
    thing that does, and an installed plugin directory is not the place to
    drop build output -- it may be read-only, and it is nobody's git work tree
    to have ignored the artefact for them. The flag is restored either way, so
    a caller that imported this module keeps whatever setting it had.
    """
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.insert(0, here)
    previous = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        import speckit_adapt
    finally:
        sys.dont_write_bytecode = previous
    return speckit_adapt


def load_speckit(path, text, adapter):
    """Adapt in memory, then parse the adapted text as a spec.

    Returns `(doc, adaptation)`. Nothing is written anywhere.
    """
    adaptation = adapter.adapt(text)
    if adaptation.refusal:
        doc = Document(path=path, kind="unknown")
        doc.add(1, ERROR, "SPECKIT_NOT_ADAPTED", adaptation.refusal)
        doc.unmeasured = True
        return doc, adaptation
    return load_document(path, adaptation.text, kind="spec"), adaptation


def resolve_speckit(doc, adaptation, adapter):
    """Map diagnostics back to source lines and drop the ones declared n/a.

    Both halves are the same obligation. A line number into a file that only
    existed in memory sends the reader to the wrong line, and a finding from a
    check this run has already declared inapplicable is a finding the adapter
    manufactured."""
    dropped = adapter.inapplicable_codes()
    doc.problems = [
        Problem(adaptation.source_line(problem.line), problem.severity,
                problem.code, problem.message)
        for problem in doc.problems if problem.code not in dropped
    ]


def report_adaptation(path, adaptation, adapter, out, baseline=False):
    """Print what the adapter did, what it did not do, and what cannot apply.

    Returns the number of check families reported `n/a`, which the summary
    line carries so a clean exit is never read as a clean bill of health.

    NOT SUPPRESSED BY --quiet, deliberately. `--quiet` drops the summary line,
    and a quiet spec-kit run that also dropped this block would be a run that
    silently skipped seven families of check and printed nothing about it --
    which is the failure this whole block exists to prevent. Every line is
    prefixed `speckit:` so a caller reading `path:line:` records can filter it.
    """
    out.write("speckit: %s adapted in memory; the file on disk was not "
              "written.\n" % path)
    if adaptation.refusal:
        out.write("speckit:   %s\n" % adaptation.refusal)
        return 0

    for number, name, _detail in adapter.RULES:
        if number == 7:
            shown = "R%d" % adaptation.next_id
        else:
            shown = "%d line(s)" % adaptation.count(number)
        out.write("speckit:   rule %d  %-28s %s\n" % (number, name, shown))
    out.write("speckit:   %-36s %d line(s)\n"
              % ("requirement bullets adapted", adaptation.requirements))
    out.write("speckit:   %-36s %d line(s)\n"
              % ("passed through, no rule matched", len(adaptation.passthrough)))
    for lineno, what, excerpt in adaptation.passthrough:
        out.write("speckit:     line %d: %s: %s\n" % (lineno, what, excerpt))

    out.write("speckit: n/a -- the checks below CANNOT apply to spec-kit "
              "input and were not run. n/a is never a pass.\n")
    families = 0
    for codes, reason in adapter.INAPPLICABLE:
        families += 1
        out.write("speckit:   n/a  %s\n" % ", ".join(codes))
        out.write("speckit:        %s\n" % reason)
    codes, reason = adapter.BASELINE_NOTE
    if baseline:
        out.write("speckit:   run  %s\n" % ", ".join(codes))
        out.write("speckit:        --baseline was given, so these DID run. "
                  "Scope: %s\n" % reason)
    else:
        families += 1
        out.write("speckit:   n/a  %s\n" % ", ".join(codes))
        out.write("speckit:        %s\n" % reason)
    out.write("speckit: %d check family(ies) n/a for %s. A check that could "
              "not apply has not passed.\n" % (families, path))
    return families


# --------------------------------------------------------------------------
# Self-test fixtures
# --------------------------------------------------------------------------

VALID_SPEC = """# Widget — living spec

Next requirement id
: `R4` — allocate from here.

Requirements
: 2 active, 1 superseded, 0 withdrawn.

## Requirements

### Ubiquitous — always active

- **R1** — The widget shall hold exactly one living spec.

### Event-driven

- **R2** — When an intent arrives, the widget shall classify it.
  Superseded by R3. The classification became four-valued.
- **R3** — When an intent arrives, the widget shall classify it as one of four classes.

## Acceptance criteria

| Requirement | Verified by |
|---|---|
| R1 | `test_one_spec` |
"""

BROKEN_SPEC = """# Widget — living spec

Next requirement id
: `R3` — allocate from here.

## Requirements

### Ubiquitous — always active

- **R1** — The widget shall hold exactly one living spec.
- **R1** — The widget shall do something else entirely.
- **R7** — The widget shall be fast.
- **R8** — The widget shall answer in a second or two.
- **R2** — The widget handles input.
- **RX** — The widget shall parse.

### Event-driven

- **R4** — When an intent arrives, the widget shall classify it, and shall log it.
  Superseded by R4. Because.
- **R5** — When a batch completes, the widget shall notify the caller, and shall write a log line.
"""

VALID_CONSTITUTION = """# Widget — constitution

Next principle id
: `P2` — allocate from here.

## Principles

### P1 — A value that was not measured is never recorded as a measurement
Active. Ratified 2026-08-28 by the maintainer.

Prose about the bound.

Checked by
: `run-checks.sh` fail-closed paths.
"""

BROKEN_CONSTITUTION = """# Widget — constitution

Next principle id
: `P1` — allocate from here.

## Principles

### P1 — A bound
Active.

### P1 — The same id again
Pending ratification.

### R2 — A requirement wearing a principle heading
Active. Ratified 2026-08-28 by the maintainer.

Checked by
: nothing.
"""

VALID_BACKLOG = """# Widget — backlog

Next backlog id
: `B3`

## Items

| Id | What is wanted | Status | Jira | Raised | Notes |
|---|---|---|---|---|---|
| B1 | A thing | `todo` | — | maintainer | — |
| B2 | Another thing | `long-term` | — | maintainer | — |
"""

BROKEN_BACKLOG = """# Widget — backlog

Next backlog id
: `B2`

## Items

| Id | What is wanted | Status | Jira | Raised | Notes |
|---|---|---|---|---|---|
| B1 | A thing | `todo` | — | maintainer | — |
| B1 | Same id | `wishlist` | — | maintainer | — |
| B9 | Above the counter | `todo` | — | maintainer | — |
"""

STALE_COUNT_SPEC = VALID_SPEC.replace("2 active, 1 superseded",
                                      "5 active, 9 superseded")

RENUMBERED_SPEC = """# Widget — living spec

Next requirement id
: `R3` — allocate from here.

## Requirements

### Ubiquitous — always active

- **R1** — The widget shall hold exactly one living spec.

### Event-driven

- **R2** — When an intent arrives, the widget shall classify it as one of four classes.
"""

DELETED_SPEC = """# Widget — living spec

Next requirement id
: `R4` — allocate from here.

## Requirements

### Ubiquitous — always active

- **R1** — Every operator shall approve a deploy before it runs.

### Event-driven

- **R2** — When an intent arrives, the widget shall classify it.
  Superseded by R3. The classification became four-valued.
"""

STATUS_SPEC = """# Widget — living spec

Next requirement id
: `R20` — allocate from here.

Requirements
: 9 active, 0 superseded, 0 withdrawn.

## Requirements

### Ubiquitous — always active

- **R1** — The widget shall hold exactly one living spec
- **R2** - The widget shall name its own separator.
- **R3** —
- **R4** — Given a request, the widget shall respond.
- **R5** — When an intent arrives, the widget shall classify it.
- **R6** — The widget shall hold exactly one living spec.

### Unwanted behaviour

- **R7** — If the store is unreachable, the widget shall stop.
- **R8** — If the store is unreachable, then the widget shall halt.
  Superseded by R7.
- **R9** — When a thing happens, the widget shall react.
  Superseded by R10. Replaced.
- **R10** — When a thing happens, the widget shall react.
- **R11** — The widget shall do a thing.
  Superseded by requirement fourteen.
- **R12** — The widget shall do another thing.
  Superseded by R19. Gone.
  Withdrawn. Also gone.

## Acceptance criteria

| Requirement | Verified by |
|---|---|
| R99 | `test_missing` |
"""

NOT_A_SPEC = "# Some other document\n\nJust prose.\n"

# spec-kit notation, in the shape `specify-cli` actually emits: an annotated
# `## Requirements` heading, one `### Functional Requirements` sub-heading,
# RFC-2119 `MUST` bullets under `FR-0NN` ids, `### Key Entities` nested at
# level 3, and no id allocator anywhere in the file.
SPECKIT_SPEC = """# Feature Specification: Widget

**Feature Branch**: `001-widget`

**Status**: Draft

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST hold exactly one living spec.
- **FR-002**: Users MUST be able to classify an intent.
- **FR-003**: System MUST NOT lose a requirement id.

### Key Entities

- **Widget**: the thing being specified.

## Success Criteria *(mandatory)*

- **SC-001**: A user can classify an intent in one command.
"""

# One FR whose body no modal rule matches, and one bullet that is not an FR at
# all. Both are carried through byte for byte and both are reported.
SPECKIT_PASSTHROUGH = SPECKIT_SPEC.replace(
    "- **FR-003**: System MUST NOT lose a requirement id.",
    "- **FR-003**: The tool SHALL retain every requirement id.\n"
    "- a bullet with no id at all.")

# An event-driven sentence under the `### Ubiquitous` heading rule 2 wrote.
# The mismatch is the adapter's, which is why it is dropped.
SPECKIT_SECTION_MISMATCH = SPECKIT_SPEC.replace(
    "- **FR-003**: System MUST NOT lose a requirement id.",
    "- **FR-003**: When an intent arrives, the system shall classify it.")


def self_test():
    failures = []

    def run(name, text, kind=None, spec=None):
        return validate_text(name, text, kind=kind, spec=spec)

    def codes(doc):
        return sorted({p.code for p in doc.problems})

    def expect(name, doc, wanted):
        present = codes(doc)
        for code in wanted:
            if code not in present:
                failures.append("%s: expected %s, got %s"
                                % (name, code, present))

    def forbid(name, doc, severity):
        for problem in doc.problems:
            if problem.severity == severity:
                failures.append("%s: unexpected %s %s: %s"
                                % (name, severity, problem.code,
                                   problem.message))

    doc = run("valid-spec.md", VALID_SPEC)
    forbid("valid-spec", doc, ERROR)
    forbid("valid-spec", doc, WARN)
    if len(doc.requirements) != 3:
        failures.append("valid-spec: parsed %d requirements, expected 3"
                        % len(doc.requirements))

    doc = run("broken-spec.md", BROKEN_SPEC)
    expect("broken-spec", doc, [
        "ID_REUSED", "ID_MALFORMED", "ID_AT_OR_ABOVE_COUNTER",
        "ID_OUT_OF_ORDER", "EARS_NO_SHALL", "EARS_UNQUANTIFIED",
        "EARS_VAGUE_QUANTITY", "EARS_MULTIPLE_SHALL", "SUPERSEDE_SELF",
    ])

    doc = run("valid-constitution.md", VALID_CONSTITUTION)
    forbid("valid-constitution", doc, ERROR)
    forbid("valid-constitution", doc, WARN)

    doc = run("broken-constitution.md", BROKEN_CONSTITUTION)
    expect("broken-constitution", doc, [
        "PRINCIPLE_ID_REUSED", "PRINCIPLE_ID_AT_OR_ABOVE_COUNTER",
        "PRINCIPLE_STATUS_MALFORMED", "PRINCIPLE_ID_PREFIX",
        "PRINCIPLE_NO_RATIFIER",
    ])

    doc = run("valid-backlog.md", VALID_BACKLOG)
    forbid("valid-backlog", doc, ERROR)
    forbid("valid-backlog", doc, WARN)

    doc = run("broken-backlog.md", BROKEN_BACKLOG)
    expect("broken-backlog", doc, [
        "BACKLOG_ID_REUSED", "BACKLOG_ID_AT_OR_ABOVE_COUNTER",
        "BACKLOG_STATUS_UNKNOWN",
    ])

    doc = run("not-a-spec.md", NOT_A_SPEC)
    expect("not-a-spec", doc, ["KIND_UNKNOWN"])
    if not doc.unmeasured:
        failures.append("not-a-spec: should be reported as NOT MEASURED")

    doc = run("empty-spec.md", "# S\n\nNext requirement id\n: `R1`\n\n"
                               "## Requirements\n\nNothing yet.\n")
    expect("empty-spec", doc, ["NO_REQUIREMENTS"])
    if not doc.unmeasured:
        failures.append("empty-spec: should be reported as NOT MEASURED")

    doc = run("status-spec.md", STATUS_SPEC)
    expect("status-spec", doc, [
        "EARS_NO_FULL_STOP", "ID_SEPARATOR", "EARS_EMPTY", "EARS_PATTERN",
        "EARS_SECTION_MISMATCH", "TEXT_DUPLICATE", "EARS_IF_MISSING_THEN",
        "SUPERSEDE_BACKWARD", "STATUS_NO_REASON",
        "SUPERSEDED_TEXT_OVERWRITTEN", "STATUS_MALFORMED",
        "SUPERSEDE_TARGET_ABSENT", "STATUS_DUPLICATE", "COUNT_MISMATCH",
        "CITATION_UNKNOWN",
    ])

    doc = run("no-counter.md", VALID_SPEC.replace(
        "Next requirement id\n: `R4` — allocate from here.", "Spec home\n: here."))
    expect("no-counter", doc, ["COUNTER_MISSING"])
    doc = run("bad-counter.md", VALID_SPEC.replace("`R4`", "`four`"))
    expect("bad-counter", doc, ["COUNTER_MALFORMED"])
    doc = run("empty-counter.md", VALID_SPEC.replace(
        ": `R4` — allocate from here.", ":"))
    expect("empty-counter", doc, ["COUNTER_MALFORMED"])
    doc = run("no-section.md", "# S\n\nNext requirement id\n: `R1`\n\n## Scope\n\nx\n")
    expect("no-section", doc, ["NO_REQUIREMENTS_SECTION"])

    baseline = build_document("baseline.md", VALID_SPEC, "spec")
    check_spec(baseline)
    current = build_document("renumbered.md", RENUMBERED_SPEC, "spec")
    check_spec(current)
    check_baseline(current, baseline)
    expect("renumbered", current, ["RENUMBERED", "SUPERSEDED_TEXT_CHANGED",
                                   "COUNTER_REWOUND"])

    baseline = build_document("baseline.md", VALID_SPEC, "spec")
    check_spec(baseline)
    current = build_document("deleted.md", DELETED_SPEC, "spec")
    check_spec(current)
    check_baseline(current, baseline)
    expect("deleted", current, ["ID_DISAPPEARED", "ID_IDENTITY_CHANGED"])

    constitution = run("c.md", VALID_CONSTITUTION)
    spec = build_document("s.md", VALID_SPEC, "spec")
    check_spec(spec)
    enforced = VALID_CONSTITUTION.replace(
        "Checked by\n: `run-checks.sh` fail-closed paths.",
        "Checked by\n: `run-checks.sh`.\n\nEnforced by\n: R99.")
    doc = run("c2.md", enforced, spec=spec)
    expect("enforced-unknown", doc, ["PRINCIPLE_ENFORCED_UNKNOWN"])
    if constitution.problems:
        failures.append("valid-constitution: re-run was not clean")

    # Regression: each of these once raised instead of diagnosing.
    doc = run("lowercase-withdrawn.md", VALID_CONSTITUTION.replace(
        "Active. Ratified 2026-08-28 by the maintainer.",
        "withdrawn 2026-05-02 — the product changed."))
    expect("lowercase-withdrawn", doc, ["PRINCIPLE_STATUS_MALFORMED"])

    doc = Document(path="crafted.md", kind="spec")
    doc.requirements = [
        Requirement(ident="R2", number=2, line=10, text="The widget shall a.",
                    status="superseded", status_line=11,
                    supersedes_target="R1", reason="why"),
        Requirement(ident="R1", number=1, line=20, text="The widget shall b."),
    ]
    check_spec_status(doc)
    expect("supersede-backward", doc, ["SUPERSEDE_BACKWARD"])

    doc = Document(path="crafted.md", kind="constitution")
    if read_principle(doc, 1, "") is not None:
        failures.append("empty-principle-heading: should not parse")
    expect("empty-principle-heading", doc, ["PRINCIPLE_MALFORMED"])

    # A header count that disagrees with the file is an ERROR, not a WARN, and
    # the corrected line is DERIVED rather than typed. Both halves are asserted
    # because both are the promotion: a severity nobody pins drifts back, and a
    # corrected number nobody derived is the same defect wearing new digits.
    doc = run("stale-counts.md", STALE_COUNT_SPEC)
    expect("stale-counts", doc, ["COUNT_MISMATCH"])
    for problem in doc.problems:
        if problem.code == "COUNT_MISMATCH" and problem.severity != ERROR:
            failures.append("stale-counts: COUNT_MISMATCH is %s, expected %s"
                            % (problem.severity, ERROR))
    lineno, value, declared, counted = spec_counts(doc)
    if declared != {"active": 5, "superseded": 9, "withdrawn": 0}:
        failures.append("stale-counts: read the header as %s" % declared)
    if counted != {"active": 2, "superseded": 1, "withdrawn": 0}:
        failures.append("stale-counts: counted %s, expected 2/1/0" % counted)
    corrected = derived_count_value(value, counted)
    if corrected != "2 active, 1 superseded, 0 withdrawn.":
        failures.append("stale-counts: derived %r" % corrected)
    if lineno != 6:
        failures.append("stale-counts: header at line %d, expected 6" % lineno)

    # The other half of the falsification: substituting the derived line clears
    # it. A check only ever seen red proves nothing about the green.
    doc = run("corrected-counts.md",
              STALE_COUNT_SPEC.replace("5 active, 9 superseded, 0 withdrawn.",
                                       corrected))
    forbid("corrected-counts", doc, ERROR)
    forbid("corrected-counts", doc, WARN)

    # ----------------------------------------------------------------------
    # --format speckit. Four fixtures, one per thing the adapter can be wrong
    # about: the rules firing, a line no rule matched, nothing to adapt at all,
    # and a finding the adapter itself manufactured.
    # ----------------------------------------------------------------------
    try:
        adapter = import_adapter()
    except ImportError as exc:
        failures.append("speckit: speckit_adapt.py could not be imported, so "
                        "the adapter was not measured at all: %s" % exc)
        adapter = None

    if adapter is not None:
        doc, adaptation = load_speckit("speckit-clean.md", SPECKIT_SPEC,
                                       adapter)
        check_document(doc)
        resolve_speckit(doc, adaptation, adapter)
        forbid("speckit-clean", doc, ERROR)
        forbid("speckit-clean", doc, WARN)
        counts = {n: adaptation.count(n) for n in range(1, 8)}
        if counts != {1: 2, 2: 1, 3: 3, 4: 3, 5: 3, 6: 1, 7: 1}:
            failures.append("speckit-clean: rules fired %s" % counts)
        if adaptation.next_id != 4:
            failures.append("speckit-clean: rule 7 synthesised R%d, expected R4"
                            % adaptation.next_id)
        if [r.ident for r in doc.requirements] != ["R1", "R2", "R3"]:
            failures.append("speckit-clean: parsed %s"
                            % [r.ident for r in doc.requirements])
        if adaptation.passthrough:
            failures.append("speckit-clean: %d line(s) passed through, "
                            "expected none" % len(adaptation.passthrough))
        # NEVER REWRITE THE USER'S FILE, asserted structurally on the adapter's
        # own source. Comparing the fixture string with itself afterwards would
        # be the obvious assertion and is a hollow one -- Python strings are
        # immutable, so it cannot fail whatever the adapter does. This one can:
        # it goes red the moment a write appears in the module.
        import inspect
        source = inspect.getsource(adapter)
        for shape in (r"\bopen\s*\(", r"\.write\s*\(", r"\bos\.replace\b",
                      r"\bshutil\b"):
            if re.search(shape, source):
                failures.append(
                    "speckit: speckit_adapt.py matches %s; --format speckit "
                    "adapts in memory and must never write a file" % shape)

        doc, adaptation = load_speckit("speckit-passthrough.md",
                                       SPECKIT_PASSTHROUGH, adapter)
        check_document(doc)
        resolve_speckit(doc, adaptation, adapter)
        if len(adaptation.passthrough) != 2:
            failures.append("speckit-passthrough: reported %d pass-through "
                            "line(s), expected 2"
                            % len(adaptation.passthrough))
        expect("speckit-passthrough", doc, ["ID_MALFORMED", "EARS_PATTERN"])
        # Rule 7 inserts four lines, so an unremapped diagnostic points four
        # lines past the bullet it is about. Asserted on a real line number
        # rather than on the mapping function, which would only prove the
        # mapping agrees with itself.
        wanted = SPECKIT_PASSTHROUGH.splitlines().index(
            "- a bullet with no id at all.") + 1
        got = [p.line for p in doc.problems if p.code == "ID_MALFORMED"]
        if got != [wanted]:
            failures.append("speckit-passthrough: ID_MALFORMED reported at %s, "
                            "expected the source line %d" % (got, wanted))

        doc, adaptation = load_speckit(
            "speckit-no-fr.md",
            "# Feature Specification: X\n\n## Requirements *(mandatory)*\n\n"
            "### Functional Requirements\n\nNone yet.\n", adapter)
        expect("speckit-no-fr", doc, ["SPECKIT_NOT_ADAPTED"])
        if not doc.unmeasured:
            failures.append("speckit-no-fr: should be reported as NOT MEASURED")
        if not adaptation.refusal:
            failures.append("speckit-no-fr: the adapter did not refuse")

        # The n/a drop, falsified in both directions. Rule 2 wrote the
        # `### Ubiquitous` heading this requirement is judged against, so the
        # mismatch is the adapter's and must not reach the reader -- but it has
        # to be shown firing first, or the drop proves nothing.
        doc, adaptation = load_speckit("speckit-section.md",
                                       SPECKIT_SECTION_MISMATCH, adapter)
        check_document(doc)
        if "EARS_SECTION_MISMATCH" not in codes(doc):
            failures.append("speckit-section: EARS_SECTION_MISMATCH did not "
                            "fire before the n/a drop, so the drop below "
                            "asserts nothing: %s" % codes(doc))
        resolve_speckit(doc, adaptation, adapter)
        if "EARS_SECTION_MISMATCH" in codes(doc):
            failures.append("speckit-section: EARS_SECTION_MISMATCH survived "
                            "the n/a drop")

    if failures:
        for failure in failures:
            sys.stdout.write("SELF-TEST FAIL: " + failure + "\n")
        sys.stdout.write("self-test FAILED: %d problem(s)\n" % len(failures))
        return EXIT_SELFTEST
    sys.stdout.write("self-test passed: 25 fixtures, 0 failures\n")
    return EXIT_CLEAN


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def report_counts(paths, kind, out):
    """Print the header's declared totals beside the totals counted from the file.

    Three tab-separated record kinds, one file at a time:

        COUNT     <path> <word> <declared or `-`> <counted>
        DECLARED  <path> <line> <the header value as it stands>
        DERIVED   <path> <line> <the header value with the counted numbers>

    A spec whose header declares nothing is NOT MEASURED rather than clean:
    nothing was compared, and a run that compared nothing must not exit 0.
    """
    unmeasured = []
    mismatched = 0
    for path in paths:
        try:
            text = read_text(path)
        except OSError as exc:
            out.write("%s:1: %s IO: %s\n" % (path, ERROR, exc))
            unmeasured.append(path)
            continue
        doc = load_document(path, text, kind=kind)
        if doc.kind != "spec":
            out.write("%s:1: %s KIND_NOT_SPEC: counts are declared by a spec; "
                      "this file is a %s\n" % (path, ERROR, doc.kind))
            unmeasured.append(path)
            continue
        if not doc.requirements:
            out.write("%s:1: %s NO_REQUIREMENTS: no `- **R<n>** —` bullets to "
                      "count\n" % (path, ERROR))
            unmeasured.append(path)
            continue
        lineno, value, declared, counted = spec_counts(doc)
        for word in COUNT_WORDS:
            shown = str(declared[word]) if word in declared else "-"
            out.write("COUNT\t%s\t%s\t%s\t%d\n"
                      % (path, word, shown, counted[word]))
            if word in declared and declared[word] != counted[word]:
                mismatched += 1
        if not declared:
            out.write("%s:%d: %s COUNTS_NOT_DECLARED: the header declares no "
                      "counts, so none were compared\n" % (path, lineno, ERROR))
            unmeasured.append(path)
            continue
        out.write("DECLARED\t%s\t%d\t%s\n" % (path, lineno, value))
        out.write("DERIVED\t%s\t%d\t%s\n"
                  % (path, lineno, derived_count_value(value, counted)))

    if unmeasured:
        out.write("NOT MEASURED: %s. No counts are reported for %s -- a file "
                  "whose counts were not compared has not passed.\n"
                  % (", ".join(sorted(set(unmeasured))),
                     "it" if len(set(unmeasured)) == 1 else "them"))
        return EXIT_UNMEASURED
    return EXIT_FAILED if mismatched else EXIT_CLEAN


def main(argv):
    parser = argparse.ArgumentParser(
        description="Validate a Productizer living spec, constitution or "
                    "backlog against references/format-spec.md.")
    parser.add_argument("files", nargs="*",
                        help="spec.md / constitution.md / backlog.md")
    parser.add_argument("--strict", action="store_true",
                        help="treat WARN as failure")
    parser.add_argument("--quiet", action="store_true",
                        help="problems only, no summary line")
    parser.add_argument("--kind", choices=["spec", "constitution", "backlog"],
                        help="override document kind detection")
    parser.add_argument("--baseline", metavar="PATH",
                        help="an earlier copy of the same spec; enables the "
                             "renumber, deletion and text-retention checks")
    parser.add_argument("--counts", action="store_true",
                        help="print the header's declared requirement totals "
                             "beside the totals counted from the file, and "
                             "the header line the counts derive")
    parser.add_argument("--format", choices=["productizer", "speckit"],
                        default="productizer",
                        help="input notation. `speckit` adapts a GitHub "
                             "spec-kit spec.md into this grammar in memory "
                             "before checking it; the file is never written")
    parser.add_argument("--self-test", "--selftest", dest="self_test",
                        action="store_true",
                        help="run the built-in fixtures and exit")
    args = parser.parse_args(argv)

    out = sys.stdout
    if args.self_test:
        return self_test()
    if not args.files:
        parser.print_usage(sys.stderr)
        sys.stderr.write("validate-spec.py: no files given\n")
        return EXIT_USAGE
    if args.baseline and len(args.files) != 1:
        sys.stderr.write("validate-spec.py: --baseline takes exactly one "
                         "file to compare against\n")
        return EXIT_USAGE
    speckit = args.format == "speckit"
    if speckit and args.kind not in (None, "spec"):
        sys.stderr.write("validate-spec.py: --format speckit produces a spec; "
                         "it cannot be read as a %s\n" % args.kind)
        return EXIT_USAGE
    if args.counts:
        if args.baseline:
            sys.stderr.write("validate-spec.py: --counts and --baseline "
                             "answer different questions; run them "
                             "separately\n")
            return EXIT_USAGE
        if speckit:
            sys.stderr.write("validate-spec.py: --counts compares the header's "
                             "declared totals with the file; a spec-kit spec "
                             "declares none, so there is nothing to compare "
                             "and nothing to report\n")
            return EXIT_USAGE
        return report_counts(args.files, args.kind, out)

    adapter = None
    if speckit:
        try:
            adapter = import_adapter()
        except ImportError as exc:
            out.write("%s:1: %s ADAPTER_MISSING: --format speckit needs "
                      "speckit_adapt.py beside this script: %s. Nothing was "
                      "checked\n" % (args.files[0], ERROR, exc))
            if not args.quiet:
                out.write("NOT MEASURED: %s. No counts are reported for it -- "
                          "a file that was not read has not passed.\n"
                          % args.files[0])
            return EXIT_UNMEASURED

    documents = []
    unmeasured = []
    adaptations = {}
    families = 0
    for path in args.files:
        try:
            text = read_text(path)
        except OSError as exc:
            out.write("%s:1: %s IO: %s\n" % (path, ERROR, exc))
            unmeasured.append(path)
            continue
        if speckit:
            doc, adaptation = load_speckit(path, text, adapter)
            adaptations[id(doc)] = adaptation
            families += report_adaptation(path, adaptation, adapter, out,
                                          baseline=bool(args.baseline))
            documents.append(doc)
            continue
        documents.append(load_document(path, text, kind=args.kind))

    # The spec is checked first so a constitution given alongside it can have
    # its `Enforced by` ids resolved against real requirements.
    spec = next((d for d in documents if d.kind == "spec"), None)
    if spec is not None:
        check_spec(spec)
    for doc in documents:
        if doc is spec:
            continue
        check_document(doc, spec=spec)

    if args.baseline and spec is not None:
        baseline_text = None
        try:
            baseline_text = read_text(args.baseline)
        except OSError as exc:
            out.write("%s:1: %s IO: %s\n" % (args.baseline, ERROR, exc))
            unmeasured.append(args.baseline)
        # The baseline is adapted by the same seven rules as the file it is
        # compared with. Comparing an adapted spec against an unadapted one
        # would report every id as renumbered, which is the adapter's doing
        # and not the author's.
        if baseline_text is not None and speckit:
            baseline_adapted = adapter.adapt(baseline_text)
            if baseline_adapted.refusal:
                out.write("%s:1: %s SPECKIT_NOT_ADAPTED: %s\n"
                          % (args.baseline, ERROR, baseline_adapted.refusal))
                unmeasured.append(args.baseline)
                baseline_text = None
            else:
                baseline_text = baseline_adapted.text
        if baseline_text is not None:
            baseline = build_document(args.baseline, baseline_text, "spec")
            check_spec(baseline)
            if baseline.unmeasured:
                out.write("%s:1: %s BASELINE_UNMEASURED: the baseline holds "
                          "no requirements; nothing was compared\n"
                          % (args.baseline, ERROR))
                unmeasured.append(args.baseline)
            else:
                baseline.problems = []
                check_baseline(spec, baseline)

    # Source-line remapping and the n/a drop happen once every check that can
    # add a problem has run, `--baseline` included.
    for doc in documents:
        adaptation = adaptations.get(id(doc))
        if adaptation is not None and not adaptation.refusal:
            resolve_speckit(doc, adaptation, adapter)

    errors = warnings = 0
    for doc in documents:
        emit(doc, out)
        if doc.unmeasured:
            unmeasured.append(doc.path)
            continue
        for problem in doc.problems:
            if problem.severity == ERROR:
                errors += 1
            else:
                warnings += 1

    if unmeasured:
        if not args.quiet:
            out.write("NOT MEASURED: %s. No counts are reported for %s -- a "
                      "file that was not read has not passed.\n"
                      % (", ".join(sorted(set(unmeasured))),
                         "it" if len(set(unmeasured)) == 1 else "them"))
        return EXIT_UNMEASURED

    if not args.quiet:
        # Under --format speckit the n/a families ride on the summary line, so
        # a zero-error run cannot be quoted as a clean bill of health for
        # obligations this input shape cannot carry.
        suffix = (", %d check family(ies) n/a" % families) if speckit else ""
        out.write("%d file(s) checked: %d error(s), %d warning(s)%s\n"
                  % (len(documents), errors, warnings, suffix))
    if errors or (args.strict and warnings):
        return EXIT_FAILED
    return EXIT_CLEAN


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
