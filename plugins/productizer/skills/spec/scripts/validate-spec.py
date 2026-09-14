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
    validate-spec.py --repo ROOT [--strict] [--quiet]
    validate-spec.py --repo ROOT --list-files
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

Scope
    MOST CHECKS HERE ARE PER FILE. Counts, EARS and supersession are judged
    inside one document, even when several are given on one command line. FIVE
    ARE NOT, and all five exist because the spec header promises ids "stay
    unique across the whole repo even if this spec is later split into several
    files" -- a promise no per-file check can keep:

      - ID_DEFINED_TWICE: an id defined in one spec file of the run and again
        in another spec file of the same run is an ERROR in both.
      - citations resolve against EVERY spec file of the run, so a plan or an
        acceptance row citing a requirement that lives in a sibling spec file
        is not CITATION_UNKNOWN.
      - COUNTER_DISAGREES: two spec files of the run declaring different
        `Next requirement id` values. One id space has one allocator, and
        which of the two is authoritative is stated nowhere.
      - SIBLING_ID_AT_OR_ABOVE_COUNTER: this file's declared next id is at or
        below an id another spec file already defines, so the next allocation
        hands out an id the repo is using. ID_DEFINED_TWICE catches that after
        the duplicate is written; this catches it before.
      - TEXT_DUPLICATE_ACROSS_FILES: one behaviour under two ids, one per
        file -- the shape the per-file TEXT_DUPLICATE cannot see, and the
        shape a split produces by construction.

    All five are inert on a single-file spec: the sibling index and the
    sibling document list are both empty, and the code paths they guard return
    before reading a requirement.

    WHICH FILES ARE "THE RUN" WAS THE CALLER'S DECISION until `--repo`. Every
    check above still fires only over the files one command line names, so a
    split whose halves were never listed together was unchecked again.
    `--repo ROOT` replaces that decision with a rule: the parts a repo
    DECLARES in `spec.path`, plus the constitution beside them, and an ERROR
    -- never a silent inclusion -- for any other file in the spec directory
    that reads as a spec. `--repo ROOT --list-files` prints the same list for
    another tool to consume, so two tools cannot disagree about what the spec
    is. See the `Discovery` section below for why declaration and not a
    filename glob is authoritative.

    `--repo` DESCRIBES A WORK TREE and nothing else. It opens no network
    connection, follows no repository binding, and joins to ROOT only
    `spec.path`. A repo whose spec lives elsewhere -- `product.spec_kind:
    store`, the layout in `references/spec-stores.md` -- is REFUSED at exit
    4 rather than read: the file at the local spec path there is a fetched
    cache of another repository, and a cache reported as checked is a pass
    over a file that is not the spec. `product.spec_path` is a path inside
    that other repository and is never joined to ROOT; a declared path that
    leaves ROOT is refused for the same reason `check-spec-home-stop.sh`
    refuses it.

    See the note on `check_spec_counts` for what was measured on a real
    two-file split, and for the one cost of a split that is STILL not enforced
    after this -- nothing sums the parts, so once each header carries its own
    total the product-level total is stated nowhere and checked by nothing.

Deterministic: no wall clock, no environment, no network is read, and problems
are emitted sorted by (line, code, message). Two runs of the same input are
byte-identical. Python 3.8+, standard library only.
"""

from __future__ import annotations

import argparse
import difflib
import glob
import json
import os
import re
import shutil
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

def spec_id_locations(documents):
    """`{id: [(path, line), ...]}` for every requirement id in this run.

    Built in command-line order, so the message a duplicate produces is the
    same on every run of the same command. Only spec documents contribute: a
    constitution's `Enforced by` ids and a backlog's citations name
    requirements, they do not define them.
    """
    index = {}
    for doc in documents:
        if doc.kind != "spec":
            continue
        for requirement in doc.requirements:
            index.setdefault(requirement.ident, []).append(
                (doc.path, requirement.line))
    return index


def siblings_for(index, doc):
    """The ids of this run defined in a spec file OTHER than `doc`.

    Empty for a run holding one spec, which is exactly why nothing below
    changes on a repository whose spec is a single file. Sameness is decided
    on the path as given, so passing the same file twice on one command line
    reports nothing rather than reporting every id as a duplicate of itself.
    """
    siblings = {}
    for ident, places in index.items():
        elsewhere = [place for place in places if place[0] != doc.path]
        if elsewhere:
            siblings[ident] = elsewhere
    return siblings


def spec_siblings(documents, doc):
    """The OTHER spec documents of this run, in command-line order.

    `siblings_for` answers "which ids are defined elsewhere", and that is all
    ID_DEFINED_TWICE and the citation union need. Three later checks need more
    than the ids -- a sibling's declared allocator, and a sibling's requirement
    TEXT -- so they are handed the documents themselves.

    Sameness is decided on the path as given, the same rule `siblings_for`
    uses, so the same file named twice on one command line is still one file
    and compares against nothing.
    """
    return [other for other in documents
            if other.kind == "spec" and other.path != doc.path]


def declared_counter(doc, name="Next requirement id", prefix="R"):
    """A document's `Next <thing> id` as an int, or None. ADDS NO DIAGNOSTICS.

    `field_number` is the reporting reader and is right for the file being
    checked. A SIBLING's counter is read silently on purpose: a malformed
    counter in part B is part B's own COUNTER_MALFORMED, emitted against part
    B's line when part B is checked, and emitting it a second time against
    part A would name the wrong file for the defect.
    """
    entry = doc.fields.get(name)
    if entry is None:
        return None
    value = entry[1]
    backtick = BACKTICK_RE.search(value)
    if backtick:
        token = backtick.group(1).strip()
    else:
        words = value.split()
        token = words[0].strip() if words else ""
    match = re.match(r"^%s([1-9][0-9]*)$" % prefix, token)
    return int(match.group(1)) if match else None


def check_spec(doc, siblings=None, others=None):
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
    check_spec_siblings(doc, siblings)
    check_spec_citations(doc, siblings)
    check_spec_allocator(doc, counter, others)
    check_spec_text_siblings(doc, others)


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
    """COUNT_MISMATCH: the header states a number about THIS FILE that nobody re-counted.

    IF YOU ARE SPLITTING THE SPEC ACROSS SEVERAL FILES, READ THIS FIRST.

    The spec header says ids "stay unique across the whole repo even if this
    spec is later split into several files". Every check in this script is
    nevertheless per-FILE, and a split is where that stops being a distinction
    without a difference. B44 was raised on the theory that COUNT_MISMATCH goes
    permanently red under a split, with no correct value to write in either
    header. That theory is WRONG, and it was measured rather than argued:
    `.claude/productizer/spec.md` at 91318de was really split in two - 15
    active + 2 superseded in part A, 20 + 4 in part B, summing to the 35 and 6
    the single file held - and both header states were run.

        both headers left at the PRODUCT total (35 active, 6 superseded):
            2 file(s) checked: 4 error(s), 84 warning(s)     exit 1
        each header rewritten to its OWN file's total:
            2 file(s) checked: 0 error(s), 84 warning(s)     exit 0

    So green IS reachable, in one edit, and the severity here stays ERROR. The
    message already scopes the claim to "this file", and per-file is the only
    thing a per-file count can honestly assert.

    WHAT A SPLIT ACTUALLY COSTS is three things, none of which is this check
    being too loud, and all three of which are this script going QUIET:

      1. NOTHING STATES OR CHECKS THE PRODUCT TOTAL any more. Once each header
         carries its own file's total, "35 active" exists nowhere and no check
         sums the parts. The count survives; the product-level claim does not.
      2. FIXED 2026-09-06 - see `check_spec_siblings`. ID_REUSED still does
         not cross files, and now ID_DEFINED_TWICE does. Measured on the same
         split: R25 was copied into the second file as well, each header
         corrected to its own count, and the run reported
             2 file(s) checked: 0 error(s), 88 warning(s)     exit 0
         with R25 defined twice in the repo. Nothing went red. (Before the
         headers were corrected the only red was COUNT_MISMATCH, at 16 rather
         than 15 - a duplicate id caught by accident, as an off-by-one in a
         count, and lost the moment someone believed the DERIVED line.) The
         same split re-run with this script now reports 2 error(s), exit 1,
         one against each copy of R25.
      3. FIXED 2026-09-06 - see `check_spec_citations`. Every cross-file
         citation used to become `CITATION_UNKNOWN`, because the check
         resolved against one document's ids. That was the 84 warnings in
         every run above, none of which is a real defect, and a check that
         emits 84 false warnings on the day of the split is a check somebody
         switches off that week - B44's real worry, aimed at the wrong code.
         Citations now resolve against every spec file of the run: the same
         split re-runs at 0 warnings.

    ONLY 1 IS STILL OPEN, and it is the one this function is about: nothing
    sums the parts. 2 and 3 were a cross-file pass over the spec documents
    `main` loaded, which made them per-RUN and not per-repo - a split whose
    halves were never given to one invocation was unchecked again, and the
    caller that listed the spec files decided how much of the promise held.
    FIXED 2026-09-07 - see the `Discovery` section. `--repo ROOT` derives the
    file list from `spec.path` instead of taking it from the caller, and
    reports any undeclared spec file in the spec directory rather than
    reporting a clean result over a file it did not read. Three further
    per-file blind spots went with it: COUNTER_DISAGREES,
    SIBLING_ID_AT_OR_ABOVE_COUNTER and TEXT_DUPLICATE_ACROSS_FILES, each
    measured at `0 error(s), 0 warning(s)`, exit 0, on a two-file split the
    day before.

    NOTHING SUMS THE PARTS EVEN SO. `--repo` now knows every part, which is
    what a product-level total would need, and computing one is still not
    done: the header field is per file, and changing what it means is a spec
    change rather than a check change.
    """
    lineno, _value, declared, counted = spec_counts(doc)
    if not declared:
        return
    for word in sorted(declared):
        if declared[word] != counted[word]:
            doc.add(lineno, ERROR, "COUNT_MISMATCH",
                    "header declares %d %s, the file holds %d; the header "
                    "states a number about this file that nobody re-counted"
                    % (declared[word], word, counted[word]))


def check_spec_siblings(doc, siblings):
    """ID_DEFINED_TWICE: an id this file defines is defined in another spec file too.

    THE ONLY CHECK HERE THAT LOOKS OUTSIDE ONE DOCUMENT, together with the
    citation union below. It exists because the spec header promises ids "stay
    unique across the whole repo even if this spec is later split into several
    files", and until this landed that promise stopped being enforced by
    anything at exactly the moment the header started making it -- measured on
    a real split and recorded under `check_spec_counts`.

    BOTH files are reported, not one. There is no way to tell which copy is the
    original from the text, and naming one of them the winner would be this
    script guessing; two errors say plainly that the repo defines one id twice.

    Inert by construction on a single-file spec: `siblings` is empty and this
    returns before reading a requirement.
    """
    if not siblings:
        return
    for requirement in doc.requirements:
        elsewhere = siblings.get(requirement.ident)
        if not elsewhere:
            continue
        where = ", ".join("%s line %d" % (path, line)
                          for path, line in elsewhere)
        doc.add(requirement.line, ERROR, "ID_DEFINED_TWICE",
                "%s is also defined in %s; an id names one requirement for the "
                "life of the repo, and a spec split across several files is "
                "still one spec" % (requirement.ident, where))


def check_spec_citations(doc, siblings=None):
    """CITATION_UNKNOWN: a cited id no spec file in this run defines.

    `siblings` widens what counts as defined to every OTHER spec file on the
    command line. Without it a split spec reports every cross-file citation as
    unknown -- 84 such warnings on a real two-file split, not one of them a
    defect -- and a check that emits 84 false warnings on the day of the split
    is a check somebody switches off that week.
    """
    known = {requirement.ident for requirement in doc.requirements}
    if siblings:
        known.update(siblings)
        unknown = "cites %s, which no spec file in this run defines"
    else:
        unknown = "cites %s, which this file does not define"
    reported = set()
    for lineno, ident in doc.citations:
        if ident in known or (lineno, ident) in reported:
            continue
        reported.add((lineno, ident))
        doc.add(lineno, WARN, "CITATION_UNKNOWN", unknown % ident)


def check_spec_allocator(doc, counter, others):
    """The allocator is a claim about the REPO, and it stops being checked at
    the file boundary exactly like the id space did.

    Two defects, both measured on a two-file split on 2026-09-06 and both
    reported as `0 error(s), 0 warning(s)`, exit 0, before this landed:

      COUNTER_DISAGREES -- part A declares `R9`, part B declares `R4`. Which
        one the next allocation reads from is undefined, and whichever it is,
        the other file's header is a false statement about the repo. Reported
        against BOTH files for the same reason ID_DEFINED_TWICE is: there is
        nothing in the text that says which is authoritative, and naming a
        winner would be this script guessing.

      SIBLING_ID_AT_OR_ABOVE_COUNTER -- part A declares `R2` while part B
        already defines R2 and R3. `ID_AT_OR_ABOVE_COUNTER` catches this
        inside one file and cannot see part B; ID_DEFINED_TWICE catches the
        consequence only AFTER somebody has written the duplicate. This
        catches it BEFORE the allocation.

    Both are reported at this file's counter line, not at the sibling's
    requirement line: the defect is what THIS header claims, and the file the
    diagnostic names has to be the file whose edit clears it.

    Inert by construction on a single-file spec: `others` is empty.
    """
    if not others or counter is None:
        return
    entry = doc.fields.get("Next requirement id")
    if entry is None:
        return
    lineno = entry[0]
    for other in others:
        theirs = declared_counter(other)
        if theirs is not None and theirs != counter:
            doc.add(lineno, ERROR, "COUNTER_DISAGREES",
                    "this file allocates from R%d and %s allocates from R%d; "
                    "a spec split across several files is one id space with "
                    "one allocator, and which of the two is authoritative is "
                    "stated nowhere" % (counter, other.path, theirs))
    for other in others:
        for requirement in other.requirements:
            if requirement.number < counter:
                continue
            doc.add(lineno, ERROR, "SIBLING_ID_AT_OR_ABOVE_COUNTER",
                    "%s is defined at %s line %d and this file declares the "
                    "next id as R%d; the next allocation hands out an id the "
                    "repo already uses"
                    % (requirement.ident, other.path, requirement.line,
                       counter))


def check_spec_text_siblings(doc, others):
    """TEXT_DUPLICATE_ACROSS_FILES: one behaviour under two ids, one per file.

    The per-file `TEXT_DUPLICATE` above compares a file with itself, so the
    cheapest way to hide a duplicated behaviour from it has always been to put
    the two ids in different files -- which is what a split does by
    construction. Measured: two halves each holding one copy of the same
    sentence under a different id reported `0 error(s), 0 warning(s)`, exit 0.

    A separate code rather than the per-file one: the message has to name a
    file and a line the per-file message has no room for, and a consumer that
    parses `TEXT_DUPLICATE` should not have to learn a second message shape.

    BOTH copies are reported, once each, when their own file is checked --
    there is no original, the same as for ID_DEFINED_TWICE. Only active
    requirements take part, matching the per-file check: a superseded one is a
    frozen record and its text is REQUIRED to stay verbatim.

    THE SAME id in both files is skipped: that is ID_DEFINED_TWICE, already an
    ERROR against both copies, and "R30 repeats the text of R30" adds a second
    finding about one defect. Measured on a spec literally copied under a
    second name -- 82 errors, and 70 warnings of which every one was that
    sentence about an id and itself. This check is about ONE behaviour under
    TWO ids.
    """
    if not others:
        return
    mine = {}
    for requirement in doc.requirements:
        if requirement.status != "active" or not requirement.text:
            continue
        mine.setdefault(normalise(requirement.text), requirement)
    if not mine:
        return
    for other in others:
        for requirement in other.requirements:
            if requirement.status != "active" or not requirement.text:
                continue
            match = mine.get(normalise(requirement.text))
            if match is None or match.ident == requirement.ident:
                continue
            doc.add(match.line, WARN, "TEXT_DUPLICATE_ACROSS_FILES",
                    "%s repeats the text of %s at %s line %d; one behaviour "
                    "under two ids splits its citations and only one gets "
                    "tested, and a spec split across several files is still "
                    "one spec"
                    % (match.ident, requirement.ident, other.path,
                       requirement.line))


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


def check_document(doc, spec=None, siblings=None, others=None):
    if doc.kind == "spec":
        check_spec(doc, siblings=siblings, others=others)
    elif doc.kind == "constitution":
        check_constitution(doc, spec=spec)
    elif doc.kind == "backlog":
        check_backlog(doc)


def validate_text(path, text, kind=None, spec=None, siblings=None,
                  others=None):
    doc = load_document(path, text, kind=kind)
    check_document(doc, spec=spec, siblings=siblings, others=others)
    return doc


def read_text(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


# --------------------------------------------------------------------------
# Discovery -- which files ARE the spec
# --------------------------------------------------------------------------
#
# Everything above is per RUN. A cross-file check only runs over the files one
# command line happens to name, so before this section the caller decided how
# much of the header's promise held, and a split whose halves were never listed
# together was unchecked again. `--repo ROOT` moves that decision out of the
# caller and into a rule.
#
# THE RULE, in one sentence: a repo's spec is what its config DECLARES, and
# every other file in the spec directory that reads as a spec is an ERROR
# rather than a silent inclusion.
#
# Declaration, not inference, is the load-bearing half. Inferring the parts
# from a filename glob (`spec-*.md`) would mean a file named to look like a
# part joins the id space by accident and a part named anything else never
# does -- a discovery rule whose answer depends on a naming convention nobody
# wrote down. So the config is authoritative, and the glob is used only in the
# other direction: to find files the config does NOT list and refuse to report
# a clean result over them. A repo that splits its spec and forgets to say so
# gets an error naming the file, not a confident pass.
#
# THE SECOND HALF OF THE RULE: `spec.path` is the ONLY key resolved against
# ROOT. Two neighbouring keys look like they answer the same question and do
# not, and both were read by nothing until the refusals below existed:
#
#   `product.spec_path`  a path inside `product.spec_repo` at
#                        `product.spec_ref`. `references/spec-stores.md`
#                        reads it as "Fetch `spec_path` from `spec_repo` at
#                        `spec_ref`" -- remote-scoped by construction.
#                        Joining it to ROOT names a local file nobody
#                        declared, so it is never joined; when it disagrees
#                        with `spec.path` that is two answers to one
#                        question, and neither is used.
#   `product.spec_kind`  `store` says the spec is not in this work tree at
#                        all. Whatever sits at the local spec path is then
#                        the cache every consuming repo keeps, and checking
#                        a cache and printing `0 error(s)` is the confident
#                        wrong answer this file exists to refuse. Measured
#                        before the guard: a store-shaped tree with a
#                        cached spec exited 0, reporting `1 file(s)
#                        checked: 0 error(s), 0 warning(s)`.
#
# P4 -- A REPOSITORY BEING EXAMINED NEVER CHOOSES WHAT RUNS -- is what
# bounds how far a config may aim this. Reading a path a config names is NOT
# executing something it names, and nothing here execs, forks or fetches:
# the whole discovery surface is `open()` on files under ROOT. What a config
# can still choose is WHICH file, and two of those choices are refused:
#
#   - a path that LEAVES ROOT (absolute, or climbing out with `..`). A
#     cloned repo would otherwise aim a reader at any file on the machine,
#     and the contents of what is read are quoted back in these
#     diagnostics -- so the escape is a disclosure surface even though it is
#     not code execution. `check-spec-home-stop.sh` already refuses this
#     shape; the two disagreeing was a gap of its own.
#   - a config VALUE reaching the report unshaped. These lines are parsed
#     one per line by other tools, so `as_datum` collapses whitespace and
#     truncates before any config string is printed: a repo does not get to
#     write a diagnostic line of its own either.
#
# What is deliberately NOT done: no binding is followed. `--repo` never
# fetches `spec_repo`, never runs a command a config names, and never reads
# a credential. A store is checked by pointing `--repo` at a checkout of the
# store -- an operator's decision, not a config's.

CONFIG_PATH = ".claude/productizer/config.json"
DEFAULT_SPEC_PATH = ".claude/productizer/spec.md"
CONSTITUTION_NAME = "constitution.md"
SPEC_KINDS = ("home", "store")


def as_datum(value, limit=120):
    """A config-supplied string, rendered safe to put in a one-line message.

    P4 -- a repository being examined never chooses what runs -- has a quieter
    second half here: it does not get to choose the SHAPE of the report
    either. Every line this script prints is read line by line by other tools
    (`check-superseded-text.sh` reads `--list-files` that way), so a config
    value carrying a newline could forge a diagnostic line of its own, and one
    carrying a megabyte could bury the real finding. Whitespace is collapsed,
    the value is truncated and quoted, and it is never interpreted.
    """
    text = " ".join(str(value).split())
    if not text:
        return "(empty)"
    if len(text) > limit:
        text = text[:limit] + "..."
    return "`%s`" % text


def json_datum(value):
    """`as_datum`, but a non-string is spelled as the JSON that was written.

    `str(None)` is `None`, which is a word the config never contained; the
    reader of a refusal has to find `null` in the file."""
    if isinstance(value, str):
        return as_datum(value)
    return as_datum(json.dumps(value))


@dataclass
class Discovery:
    """What `--repo` found. `refusal` non-empty means nothing was measured."""
    spec_paths: list = field(default_factory=list)
    other_paths: list = field(default_factory=list)
    undeclared: list = field(default_factory=list)
    refusal: str = ""

    def files(self):
        return self.spec_paths + self.other_paths


def declared_spec_paths(root):
    """The spec parts a repo declares, as `(paths, refusal)`.

    `.claude/productizer/config.json` -> `spec.path`, which is EITHER a string
    (one file, the shape every repo has today) OR a list of strings (a split
    spec, in the order the product reads them). No config, or a config with no
    `spec.path`, means the default single file -- so a repo that has never
    heard of this still discovers correctly.

    A config that exists and cannot be parsed is a REFUSAL, not a fallback to
    the default. Falling back would answer confidently about a repo whose own
    statement of where its spec lives could not be read.

    `spec.path` IS THE ONLY KEY RESOLVED AGAINST ROOT, and the three refusals
    below exist because two other keys look like they name the same thing and
    do not. `product.spec_path` is a path INSIDE `product.spec_repo` at
    `product.spec_ref` -- `references/spec-stores.md` reads it as *"Fetch
    `spec_path` from `spec_repo` at `spec_ref`"* -- so joining it to ROOT
    names a local file nobody declared. `product.spec_kind: store` says the
    spec is not in this work tree at all, which makes anything at the local
    path a fetched cache. Both are refusals rather than picks, because the
    failure they otherwise produce is the one this file exists to refuse: a
    confident `0 error(s)` over the wrong file.
    """
    config = os.path.normpath(os.path.join(root, CONFIG_PATH))
    declared = [DEFAULT_SPEC_PATH]
    if os.path.isfile(config):
        try:
            with open(config, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError) as exc:
            return [], ("%s exists and could not be read as JSON (%s). It is "
                        "the file that says where this repo's spec lives, so "
                        "nothing was discovered and nothing was checked"
                        % (config, exc))
        # A WRITTEN KEY IS A DECLARATION; ONLY AN ABSENT ONE IS "OMITTED".
        # `references/spec-stores.md` says `spec_kind` is `home` by default and
        # to "omit it" -- omit, not null it. JSON `null` is a value somebody (or
        # a templater that failed to substitute) put under the key, and it is
        # neither `home` nor `store`. Reading it as `home` is the unknown-kind
        # fall-through through a quieter door: a config meant for a store
        # whose kind came out null would read the local cache and print
        # `0 error(s)`. Measured before this: `"spec_kind": null` exited 0.
        # Nothing in this repository writes null there (no template, fixture
        # or config), so refusing it moves no existing reader. The same rule
        # governs `product` itself: absent is the default, and a `product` that
        # is present and not an object -- a string, a list, null -- is a
        # declaration nothing here can read, so it refuses rather than being
        # read as an empty one. Measured before this: `"product": "orders"`
        # exited 0 over the default path.
        product = data.get("product", {}) if isinstance(data, dict) else {}
        if not isinstance(product, dict):
            return [], ("%s declares `product` as %s, which is not an object. "
                        "It is where this repo says whether its spec is in "
                        "this work tree or in a store of its own, and a "
                        "declaration that cannot be read is not one that "
                        "said `home`. Nothing was discovered and nothing was "
                        "checked" % (config, json_datum(product)))
        if "spec_kind" in product:
            kind = product["spec_kind"]
            name = kind.strip() if isinstance(kind, str) else None
            if name not in SPEC_KINDS:
                return [], ("%s declares `product.spec_kind` as %s. The only "
                            "values are \"home\" (the spec is in this work "
                            "tree) and \"store\" (it is in a repository of "
                            "its own). Which was meant decides whether the "
                            "file at the local path is the spec or a cache of "
                            "it, and guessing is how a typo becomes a "
                            "confident read of the wrong file. Nothing was "
                            "discovered and nothing was checked"
                            % (config, json_datum(kind)))
            if name == "store":
                repo = product.get("spec_repo")
                where = (as_datum(repo)
                         if isinstance(repo, str) and repo.strip()
                         else "the repository `product.spec_repo` names")
                ref = product.get("spec_ref")
                at = (as_datum(ref) if isinstance(ref, str) and ref.strip()
                      else "its default branch")
                return [], ("%s declares `product.spec_kind` as \"store\", "
                            "so this repo's spec lives in %s at %s and not in "
                            "this work tree. `--repo` only ever opens files "
                            "under ROOT, so anything at the local spec path "
                            "here is a fetched cache -- and a cache reported "
                            "as checked is a pass over a file that is not the "
                            "spec, at whatever sha it was fetched. Point "
                            "`--repo` at a checkout of the store instead. "
                            "Nothing was discovered here and nothing was "
                            "checked" % (config, where, at))
        block = data.get("spec") if isinstance(data, dict) else None
        value = block.get("path") if isinstance(block, dict) else None
        if isinstance(value, str):
            declared = [value]
        elif isinstance(value, list):
            if not value or not all(isinstance(item, str) for item in value):
                return [], ("%s declares `spec.path` as a list that is empty "
                            "or holds a non-string. It is the file that says "
                            "where this repo's spec lives, so nothing was "
                            "discovered and nothing was checked" % config)
            declared = list(value)
        elif value is not None:
            return [], ("%s declares `spec.path` as %s; it must be a string "
                        "(one file) or a list of strings (a split spec). "
                        "Nothing was discovered and nothing was checked"
                        % (config, type(value).__name__))
        remote = product.get("spec_path")
        if isinstance(remote, str) and remote.strip():
            if len(declared) != 1 or remote.strip() != declared[0]:
                return [], ("%s declares `product.spec_path` as %s and "
                            "`spec.path` as %s. Those are two answers to "
                            "where this repo's spec is, and only `spec.path` "
                            "is resolved against ROOT: `product.spec_path` "
                            "names a path inside `product.spec_repo` (see "
                            "references/spec-stores.md) and is never joined "
                            "to a local tree. Reading either one while they "
                            "disagree is a confident answer about the wrong "
                            "file, so make them agree or drop one. Nothing "
                            "was discovered and nothing was checked"
                            % (config, as_datum(remote),
                               ", ".join(as_datum(d) for d in declared)))
    paths = []
    for rel in declared:
        # The rule is LEXICAL and deliberately over-refuses: `a/../b.md`
        # normalises back inside ROOT and is still rejected. Deciding by
        # normalising first would mean the answer depends on which segments
        # happen to cancel, and `check-spec-home-stop.sh` already draws the
        # line here -- one of the two being cleverer than the other is how a
        # path one tool refuses becomes a path the other reads.
        if os.path.isabs(rel) or ".." in re.split(r"[\\/]", rel):
            return [], ("%s declares the spec file %s, which leaves ROOT. "
                        "`--repo` describes a work tree, and a declaration "
                        "pointing outside it aims a reader at a file the repo "
                        "does not contain -- P4: a repository being examined "
                        "does not choose what gets read on the machine that "
                        "cloned it, and the contents of what is read are "
                        "quoted back in these diagnostics. "
                        "`check-spec-home-stop.sh` already refuses this shape "
                        "and this draws the line in the same place: any "
                        "`..` segment or absolute path, judged before "
                        "normalising. Nothing was discovered and nothing "
                        "was checked" % (config, as_datum(rel)))
        path = os.path.normpath(os.path.join(root, rel))
        if path not in paths:
            paths.append(path)
    for path in paths:
        if not os.path.isfile(path):
            return [], ("%s is declared as a spec file of this repo and is "
                        "not a readable file. A declared part that is not "
                        "there is not a part that is empty" % path)
    return paths, ""


def discover_repo(root):
    """Every governed document of a repo, discovered rather than listed by hand.

    Returns a `Discovery`. `spec_paths` are the declared parts, in declared
    order. `other_paths` adds the constitution beside them when there is one,
    because its `Enforced by` ids resolve against the spec and a run that
    dropped it would report ids as unknown that are not.

    `undeclared` holds the files this refuses to be quiet about: any other
    `.md` in the spec directory that `detect_kind` reads as a spec, and any
    that could not be read at all -- an unreadable file is not a file ruled
    out. The backlog is deliberately NOT discovered: it is not part of the id
    space this exists to protect, and pulling a document nothing checks today
    into a gate is a separate decision from closing this gap.
    """
    found = Discovery()
    paths, refusal = declared_spec_paths(root)
    if refusal:
        found.refusal = refusal
        return found
    found.spec_paths = paths
    spec_dir = os.path.dirname(paths[0])
    constitution = os.path.normpath(os.path.join(spec_dir, CONSTITUTION_NAME))
    if os.path.isfile(constitution):
        found.other_paths.append(constitution)
    known = set(found.files())
    for candidate in sorted(glob.glob(os.path.join(spec_dir, "*.md"))):
        candidate = os.path.normpath(candidate)
        if candidate in known:
            continue
        try:
            text = read_text(candidate)
        except OSError as exc:
            found.undeclared.append(
                (candidate,
                 "is in the spec directory and could not be read (%s), so it "
                 "could not be ruled out as a spec file. A file nobody read "
                 "is not a file that is not a spec" % exc))
            continue
        if detect_kind(text) == "spec":
            found.undeclared.append(
                (candidate,
                 "reads as a spec file and `spec.path` in %s does not list "
                 "it, so its ids, its allocator and its requirement text took "
                 "part in no cross-file check. Declare it there or it is not "
                 "part of this spec"
                 % os.path.normpath(os.path.join(root, CONFIG_PATH))))
    return found


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

# VALID_SPEC cut in two at the section boundary, the way a real spec is split
# when it outgrows one file: each part carries its own header, its own count of
# ITSELF, and the same allocator. Part A's acceptance table cites R3, which
# lives in part B -- the cross-file citation that used to be a warning.
SPLIT_A_SPEC = """# Widget — living spec, part A

Next requirement id
: `R4` — allocate from here.

Requirements
: 1 active, 0 superseded, 0 withdrawn.

## Requirements

### Ubiquitous — always active

- **R1** — The widget shall hold exactly one living spec.

## Acceptance criteria

| Requirement | Verified by |
|---|---|
| R1 | `test_one_spec` |
| R3 | `test_four_classes` |
"""

SPLIT_B_SPEC = """# Widget — living spec, part B

Next requirement id
: `R4` — allocate from here.

Requirements
: 1 active, 1 superseded, 0 withdrawn.

## Requirements

### Event-driven

- **R2** — When an intent arrives, the widget shall classify it.
  Superseded by R3. The classification became four-valued.
- **R3** — When an intent arrives, the widget shall classify it as one of four classes.
"""

# R1 copied into part B as well, and part B's own count corrected to match --
# which is the whole point: correcting the count is one edit, and before
# ID_DEFINED_TWICE it was the edit that turned the run green with an id
# defined twice in the repo.
SPLIT_B_DUPLICATE = SPLIT_B_SPEC.replace(
    ": 1 active, 1 superseded, 0 withdrawn.",
    ": 2 active, 1 superseded, 0 withdrawn.").replace(
    "### Event-driven",
    "### Ubiquitous — always active\n\n"
    "- **R1** — The widget shall hold exactly one living spec.\n\n"
    "### Event-driven")

# A citation NO part of the split defines. The union must widen what resolves,
# not switch the check off.
SPLIT_A_STRAY = SPLIT_A_SPEC.replace("| R3 | `test_four_classes` |",
                                     "| R3 | `test_four_classes` |\n"
                                     "| R9 | `test_absent` |")

# The allocator half of a split. Part B keeps its own ids and moves only the
# header, so the disagreement is the ONLY defect in the pair -- a fixture that
# also tripped an id check would not tell which check caught it.
SPLIT_B_OTHER_COUNTER = SPLIT_B_SPEC.replace("`R4` — allocate",
                                             "`R9` — allocate")

# Both halves wound back to `R2` while part B already defines R2 and R3. The
# counters AGREE here on purpose: part B trips the per-file
# ID_AT_OR_ABOVE_COUNTER on its own ids, and part A -- whose only id is R1 and
# which is clean by every per-file rule -- is the file the cross-file check has
# to catch.
SPLIT_A_LOW_COUNTER = SPLIT_A_SPEC.replace("`R4` — allocate",
                                           "`R2` — allocate")
SPLIT_B_LOW_COUNTER = SPLIT_B_SPEC.replace("`R4` — allocate",
                                           "`R2` — allocate")

# One behaviour, two ids, one per file. Deliberately not built from SPLIT_A/B:
# moving a sentence between those two sections trips EARS_SECTION_MISMATCH as
# well, and a fixture that raises two codes cannot falsify either one.
TEXT_SPLIT_A = """# Widget — living spec, part A

Next requirement id
: `R4` — allocate from here.

Requirements
: 1 active, 0 superseded, 0 withdrawn.

## Requirements

### Event-driven

- **R1** — When an intent arrives, the widget shall classify it.
"""

TEXT_SPLIT_B = TEXT_SPLIT_A.replace("part A", "part B").replace("**R1**",
                                                                "**R2**")
TEXT_SPLIT_B_DISTINCT = TEXT_SPLIT_B.replace(
    "When an intent arrives, the widget shall classify it.",
    "When a batch completes, the widget shall notify the caller.")

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

    # The fixture count on the last line is DERIVED from this list, not typed.
    # It used to be a literal, and a literal is a number that goes stale the
    # first time somebody adds a case -- which is a measurement nobody re-took,
    # the defect COUNT_MISMATCH exists to catch, in this file's own output.
    # THE RULE, so a later reader can re-derive it: one entry per named case,
    # registered by `run`, `run_set`, or an explicit `case(...)` for a fixture
    # built by hand. Supporting documents another case needs -- a baseline, a
    # spec a constitution resolves against -- are not cases and are not
    # registered. Under that rule the fixtures present before the cross-file
    # checks landed count 26, not the 25 the line used to print.
    fixtures = []

    def case(name):
        if name not in fixtures:
            fixtures.append(name)
        return name

    def run(name, text, kind=None, spec=None):
        case(name)
        return validate_text(name, text, kind=kind, spec=spec)

    def run_set(name, pairs):
        """Load several spec files and check them as ONE run, as `main` does.

        Going through `spec_id_locations`/`siblings_for` rather than a
        hand-built sibling dict is the point: the wiring is what regressed
        before, and a fixture that assembles its own index would pass over a
        `main` that never calls them.
        """
        case(name)
        documents = [load_document(path, text, kind="spec")
                     for path, text in pairs]
        index = spec_id_locations(documents)
        for doc in documents:
            check_spec(doc, siblings=siblings_for(index, doc),
                       others=spec_siblings(documents, doc))
        return documents

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

    case("renumbered")
    baseline = build_document("baseline.md", VALID_SPEC, "spec")
    check_spec(baseline)
    current = build_document("renumbered.md", RENUMBERED_SPEC, "spec")
    check_spec(current)
    check_baseline(current, baseline)
    expect("renumbered", current, ["RENUMBERED", "SUPERSEDED_TEXT_CHANGED",
                                   "COUNTER_REWOUND"])

    case("deleted")
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

    case("supersede-backward")
    doc = Document(path="crafted.md", kind="spec")
    doc.requirements = [
        Requirement(ident="R2", number=2, line=10, text="The widget shall a.",
                    status="superseded", status_line=11,
                    supersedes_target="R1", reason="why"),
        Requirement(ident="R1", number=1, line=20, text="The widget shall b."),
    ]
    check_spec_status(doc)
    expect("supersede-backward", doc, ["SUPERSEDE_BACKWARD"])

    case("empty-principle-heading")
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
    # The two cross-file checks, falsified in both directions on the same
    # split. Part A alone is measured FIRST: without the sibling, its citation
    # of R3 has to be seen going red, or the clean set below proves only that
    # some other change also made it quiet.
    # ----------------------------------------------------------------------
    doc = run("split-a-alone.md", SPLIT_A_SPEC)
    expect("split-a-alone", doc, ["CITATION_UNKNOWN"])
    unknown = [p.message for p in doc.problems if p.code == "CITATION_UNKNOWN"]
    if unknown != ["cites R3, which this file does not define"]:
        failures.append("split-a-alone: reported %s" % unknown)

    documents = run_set("split-clean", [("split-a.md", SPLIT_A_SPEC),
                                        ("split-b.md", SPLIT_B_SPEC)])
    for doc in documents:
        forbid("split-clean:" + doc.path, doc, ERROR)
        forbid("split-clean:" + doc.path, doc, WARN)

    # The stray citation. The union widens what resolves; it must not switch
    # the check off, and the message must say what was actually searched.
    documents = run_set("split-citation-unknown",
                        [("split-a.md", SPLIT_A_STRAY),
                         ("split-b.md", SPLIT_B_SPEC)])
    expect("split-citation-unknown", documents[0], ["CITATION_UNKNOWN"])
    unknown = [p.message for p in documents[0].problems
               if p.code == "CITATION_UNKNOWN"]
    if unknown != ["cites R9, which no spec file in this run defines"]:
        failures.append("split-citation-unknown: reported %s" % unknown)

    # R1 in both halves, each header counting its own file correctly. Before
    # ID_DEFINED_TWICE this input was 0 errors, exit 0.
    documents = run_set("split-duplicate", [("split-a.md", SPLIT_A_SPEC),
                                            ("split-b.md", SPLIT_B_DUPLICATE)])
    for doc in documents:
        expect("split-duplicate:" + doc.path, doc, ["ID_DEFINED_TWICE"])
        for problem in doc.problems:
            if problem.code == "ID_DEFINED_TWICE" and problem.severity != ERROR:
                failures.append("split-duplicate: ID_DEFINED_TWICE is %s, "
                                "expected %s" % (problem.severity, ERROR))
    # Named in BOTH directions: an id defined twice has no original, and a
    # check that reported only the second copy would let the first file pass.
    if not any("split-b.md line" in p.message for p in documents[0].problems):
        failures.append("split-duplicate: part A does not name part B")
    if not any("split-a.md line" in p.message for p in documents[1].problems):
        failures.append("split-duplicate: part B does not name part A")

    # INERT ON ONE FILE, which is what this repository is today. Both halves:
    # the sibling index of a one-spec run is empty, and the same spec named
    # twice on one command line is one file, not two definitions of every id.
    documents = [load_document("split-a.md", SPLIT_A_SPEC, kind="spec")]
    if siblings_for(spec_id_locations(documents), documents[0]):
        failures.append("single-file: a one-spec run built a sibling index")
    documents = run_set("split-same-file-twice",
                        [("split-a.md", SPLIT_A_SPEC),
                         ("split-a.md", SPLIT_A_SPEC)])
    for doc in documents:
        for problem in doc.problems:
            if problem.code == "ID_DEFINED_TWICE":
                failures.append("split-same-file-twice: %s" % problem.message)

    # THE WIRING, through `main`, on real files. Every case above assembles the
    # sibling index itself, and that is not the same assertion: deleting the
    # `spec_id_locations` call from `main` was tried and left all of them
    # green while a real two-file split went back to 0 errors and 29 false
    # warnings. This is the only fixture here that touches the filesystem, and
    # it is why -- a check reached only by the code under test is a check.
    case("split-main-wiring")
    import io
    import os
    import shutil
    import tempfile
    sandbox = tempfile.mkdtemp(prefix="validate-spec-selftest.")
    try:
        part_a = os.path.join(sandbox, "spec-a.md")
        part_b = os.path.join(sandbox, "spec-b.md")
        with open(part_a, "w", encoding="utf-8") as handle:
            handle.write(SPLIT_A_SPEC)

        def drive(argv):
            captured = io.StringIO()
            saved = sys.stdout
            sys.stdout = captured
            try:
                status = main(argv)
            finally:
                sys.stdout = saved
            return status, captured.getvalue()

        with open(part_b, "w", encoding="utf-8") as handle:
            handle.write(SPLIT_B_SPEC)
        status, output = drive([part_a, part_b])
        if status != EXIT_CLEAN or "0 error(s), 0 warning(s)" not in output:
            failures.append("split-main-wiring: the clean split exited %d: %s"
                            % (status, output.strip()))

        with open(part_b, "w", encoding="utf-8") as handle:
            handle.write(SPLIT_B_DUPLICATE)
        status, output = drive([part_a, part_b])
        if status != EXIT_FAILED:
            failures.append("split-main-wiring: an id defined in both files "
                            "exited %d, expected %d" % (status, EXIT_FAILED))
        if output.count("ERROR ID_DEFINED_TWICE") != 2:
            failures.append("split-main-wiring: %d ID_DEFINED_TWICE line(s), "
                            "expected one per file: %s"
                            % (output.count("ERROR ID_DEFINED_TWICE"),
                               output.strip()))
        # Single file, same content, through the same entry point: the check
        # this repository actually runs today must be unreachable.
        status, output = drive([part_b])
        if "ID_DEFINED_TWICE" in output:
            failures.append("split-main-wiring: a one-file run reported "
                            "ID_DEFINED_TWICE: %s" % output.strip())
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    # ----------------------------------------------------------------------
    # The allocator and the requirement text, across files. Each of the three
    # was MEASURED as `0 error(s), 0 warning(s)`, exit 0, on 2026-09-06 before
    # the check that catches it existed, so each red case below has a green
    # case beside it and the green case is the one that used to be the only
    # answer.
    # ----------------------------------------------------------------------
    documents = run_set("split-counter-disagrees",
                        [("split-a.md", SPLIT_A_SPEC),
                         ("split-b.md", SPLIT_B_OTHER_COUNTER)])
    for doc in documents:
        expect("split-counter-disagrees:" + doc.path, doc,
               ["COUNTER_DISAGREES"])
        for problem in doc.problems:
            if problem.code == "COUNTER_DISAGREES" and problem.severity != ERROR:
                failures.append("split-counter-disagrees: %s is %s, expected %s"
                                % (problem.code, problem.severity, ERROR))
    # Named in BOTH directions, for ID_DEFINED_TWICE's reason: nothing in the
    # text says which header is authoritative, so a check that reported one of
    # them would be guessing which file to edit.
    if not any("split-b.md" in p.message for p in documents[0].problems
               if p.code == "COUNTER_DISAGREES"):
        failures.append("split-counter-disagrees: part A does not name part B")
    if not any("split-a.md" in p.message for p in documents[1].problems
               if p.code == "COUNTER_DISAGREES"):
        failures.append("split-counter-disagrees: part B does not name part A")
    # The green half: the same two files with the same allocator are silent.
    documents = run_set("split-counter-agrees",
                        [("split-a.md", SPLIT_A_SPEC),
                         ("split-b.md", SPLIT_B_SPEC)])
    for doc in documents:
        for problem in doc.problems:
            if problem.code == "COUNTER_DISAGREES":
                failures.append("split-counter-agrees: %s" % problem.message)

    documents = run_set("split-sibling-above-counter",
                        [("split-a.md", SPLIT_A_LOW_COUNTER),
                         ("split-b.md", SPLIT_B_LOW_COUNTER)])
    expect("split-sibling-above-counter", documents[0],
           ["SIBLING_ID_AT_OR_ABOVE_COUNTER"])
    above = [p for p in documents[0].problems
             if p.code == "SIBLING_ID_AT_OR_ABOVE_COUNTER"]
    # R2 and R3 both sit at or above R2, and both are named: reporting only
    # the lowest would leave the second allocation still broken after the fix.
    if len(above) != 2:
        failures.append("split-sibling-above-counter: %d id(s) reported, "
                        "expected R2 and R3" % len(above))
    if any(p.severity != ERROR for p in above):
        failures.append("split-sibling-above-counter: not an ERROR")
    # Part A is clean under every per-file rule -- that is the whole point.
    if any(p.code == "ID_AT_OR_ABOVE_COUNTER" for p in documents[0].problems):
        failures.append("split-sibling-above-counter: part A tripped the "
                        "per-file check, so this fixture proves nothing about "
                        "the cross-file one")
    # The green half: the same pair with the allocator ahead of every id.
    documents = run_set("split-counter-ahead",
                        [("split-a.md", SPLIT_A_SPEC),
                         ("split-b.md", SPLIT_B_SPEC)])
    for doc in documents:
        for problem in doc.problems:
            if problem.code == "SIBLING_ID_AT_OR_ABOVE_COUNTER":
                failures.append("split-counter-ahead: %s" % problem.message)

    documents = run_set("split-text-duplicate",
                        [("text-a.md", TEXT_SPLIT_A),
                         ("text-b.md", TEXT_SPLIT_B)])
    for doc in documents:
        expect("split-text-duplicate:" + doc.path, doc,
               ["TEXT_DUPLICATE_ACROSS_FILES"])
        for problem in doc.problems:
            if (problem.code == "TEXT_DUPLICATE_ACROSS_FILES"
                    and problem.severity != WARN):
                failures.append("split-text-duplicate: %s is %s, expected %s"
                                % (problem.code, problem.severity, WARN))
    documents = run_set("split-text-distinct",
                        [("text-a.md", TEXT_SPLIT_A),
                         ("text-b.md", TEXT_SPLIT_B_DISTINCT)])
    for doc in documents:
        for problem in doc.problems:
            if problem.code == "TEXT_DUPLICATE_ACROSS_FILES":
                failures.append("split-text-distinct: %s" % problem.message)
    # One id in both files with one text is ID_DEFINED_TWICE and nothing else.
    # Without the same-id skip, a spec copied under a second name reports the
    # sentence "R30 repeats the text of R30" once per requirement -- 70 of them
    # on this repository's own spec, next to the 82 errors that are the defect.
    documents = run_set("split-text-same-id",
                        [("text-a.md", TEXT_SPLIT_A),
                         ("text-b.md", TEXT_SPLIT_A)])
    for doc in documents:
        expect("split-text-same-id:" + doc.path, doc, ["ID_DEFINED_TWICE"])
        for problem in doc.problems:
            if problem.code == "TEXT_DUPLICATE_ACROSS_FILES":
                failures.append("split-text-same-id: an id duplicated across "
                                "files also reported %s" % problem.message)

    # INERT ON ONE FILE, the three new checks together. `others` is empty for a
    # one-spec run, and this repository is a one-spec repository today.
    doc = run("single-file-allocator.md", SPLIT_A_LOW_COUNTER)
    for problem in doc.problems:
        if problem.code in ("COUNTER_DISAGREES",
                            "SIBLING_ID_AT_OR_ABOVE_COUNTER",
                            "TEXT_DUPLICATE_ACROSS_FILES"):
            failures.append("single-file-allocator: a one-file run reported "
                            "%s" % problem.code)

    # ----------------------------------------------------------------------
    # DISCOVERY, through `main`, on a real directory tree. Everything above is
    # per RUN: it proves the checks fire when a caller lists both halves. This
    # is the part that stops depending on the caller, so nothing here may be
    # asserted against a hand-built file list -- the list is the thing under
    # test.
    # ----------------------------------------------------------------------
    case("repo-discovery")
    sandbox = tempfile.mkdtemp(prefix="validate-spec-selftest-repo.")
    try:
        home = os.path.join(sandbox, ".claude", "productizer")
        os.makedirs(home)
        part_a = os.path.join(home, "spec.md")
        part_b = os.path.join(home, "spec-b.md")
        config = os.path.join(home, "config.json")

        def write(path, text):
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text)

        def declare(paths):
            write(config, json.dumps({"spec": {"path": paths}}))

        write(part_a, SPLIT_A_SPEC)
        write(part_b, SPLIT_B_DUPLICATE)

        # 1. Both halves declared: the duplicate id is caught with no file
        #    named on the command line at all.
        declare([".claude/productizer/spec.md",
                 ".claude/productizer/spec-b.md"])
        status, output = drive(["--repo", sandbox])
        if status != EXIT_FAILED:
            failures.append("repo-discovery: a declared split with an id in "
                            "both halves exited %d, expected %d"
                            % (status, EXIT_FAILED))
        if output.count("ERROR ID_DEFINED_TWICE") != 2:
            failures.append("repo-discovery: %d ID_DEFINED_TWICE line(s) from "
                            "a discovered split: %s"
                            % (output.count("ERROR ID_DEFINED_TWICE"),
                               output.strip()))

        # 2. THE FALSIFICATION OF DISCOVERY ITSELF. The same two files on disk,
        #    with the config listing only one of them. Before the undeclared
        #    detector this is a confident `1 file(s) checked: 0 error(s)` over
        #    a repo whose spec is split and whose ids collide -- the
        #    per-invocation gap moved one layer down.
        declare(".claude/productizer/spec.md")
        status, output = drive(["--repo", sandbox])
        if status != EXIT_FAILED:
            failures.append("repo-discovery: an undeclared spec part exited "
                            "%d, expected %d" % (status, EXIT_FAILED))
        if output.count("ERROR SPEC_FILE_UNDECLARED") != 1:
            failures.append("repo-discovery: undeclared part not reported "
                            "exactly once: %s" % output.strip())
        if "spec-b.md" not in output:
            failures.append("repo-discovery: the undeclared file is not named")
        # It is reported and NOT checked: joining it silently would be the
        # inference this refuses to make.
        if "1 file(s) checked" not in output:
            failures.append("repo-discovery: an undeclared part was pulled "
                            "into the run: %s" % output.strip())

        # 3. `--list-files` is the contract another tool reads. It refuses on
        #    an undeclared part rather than printing a list it knows is short.
        status, output = drive(["--repo", sandbox, "--list-files"])
        if status != EXIT_FAILED or part_a in output:
            failures.append("repo-discovery: --list-files printed a list over "
                            "an undeclared part: %d %s"
                            % (status, output.strip()))
        declare([".claude/productizer/spec.md",
                 ".claude/productizer/spec-b.md"])
        status, output = drive(["--repo", sandbox, "--list-files"])
        if status != EXIT_CLEAN:
            failures.append("repo-discovery: --list-files exited %d" % status)
        if output.splitlines() != [os.path.normpath(part_a),
                                   os.path.normpath(part_b)]:
            failures.append("repo-discovery: --list-files printed %r"
                            % output.splitlines())

        # 4. The allocator, discovered rather than listed: part A wound back to
        #    R2 while part B defines R2 and R3, which is the exact input
        #    measured at exit 0 before this landed.
        write(part_a, SPLIT_A_LOW_COUNTER)
        write(part_b, SPLIT_B_SPEC)
        status, output = drive(["--repo", sandbox])
        if "ERROR SIBLING_ID_AT_OR_ABOVE_COUNTER" not in output:
            failures.append("repo-discovery: the discovered split did not "
                            "reach the allocator check: %s" % output.strip())
        if "ERROR COUNTER_DISAGREES" not in output:
            failures.append("repo-discovery: the discovered split did not "
                            "reach the counter check: %s" % output.strip())

        # 5. A repo with no config and one spec: the default, and silent.
        os.remove(config)
        os.remove(part_b)
        write(part_a, SPLIT_B_SPEC)
        status, output = drive(["--repo", sandbox])
        if status != EXIT_CLEAN or "1 file(s) checked" not in output:
            failures.append("repo-discovery: a one-file repo with no config "
                            "exited %d: %s" % (status, output.strip()))

        # 6. A config that exists and cannot be read is a REFUSAL. Falling back
        #    to the default would answer confidently about a repo whose own
        #    statement of where its spec lives was unreadable.
        write(config, "{not json")
        status, output = drive(["--repo", sandbox])
        if status != EXIT_UNMEASURED:
            failures.append("repo-discovery: an unparseable config exited %d, "
                            "expected %d" % (status, EXIT_UNMEASURED))
        if "DISCOVERY_REFUSED" not in output or "NOT MEASURED" not in output:
            failures.append("repo-discovery: an unparseable config did not "
                            "report NOT MEASURED: %s" % output.strip())

        # 7. A declared part that is not on disk. NOT MEASURED, not "the other
        #    part was clean": a part that is not there is not a part that is
        #    empty, and reporting the rest as checked would be the confident
        #    partial answer this whole file exists to refuse.
        declare([".claude/productizer/spec.md",
                 ".claude/productizer/spec-gone.md"])
        status, output = drive(["--repo", sandbox])
        if status != EXIT_UNMEASURED:
            failures.append("repo-discovery: a declared part that is not on "
                            "disk exited %d, expected %d"
                            % (status, EXIT_UNMEASURED))
        if "DISCOVERY_REFUSED" not in output or "spec-gone.md" not in output:
            failures.append("repo-discovery: a declared part that is not on "
                            "disk was reported as an ordinary read failure "
                            "over a discovery that had already succeeded: %s"
                            % output.strip())
        # `--list-files` is where refusing rather than reading-and-failing is
        # load-bearing: the consumer of the list never opens the file itself,
        # so a path printed here is asserted to exist.
        status, output = drive(["--repo", sandbox, "--list-files"])
        if status != EXIT_UNMEASURED or "spec.md\n" in output:
            failures.append("repo-discovery: --list-files printed a list that "
                            "names a part which is not on disk: %d %s"
                            % (status, output.strip()))

        # 8. The constitution beside the spec is discovered too, because its
        #    `Enforced by` ids resolve against the spec and a run that dropped
        #    it would report ids as unknown that are not.
        declare(".claude/productizer/spec.md")
        write(os.path.join(home, "constitution.md"), VALID_CONSTITUTION)
        status, output = drive(["--repo", sandbox])
        if "2 file(s) checked" not in output:
            failures.append("repo-discovery: the constitution beside the spec "
                            "was not discovered: %s" % output.strip())
        os.remove(os.path.join(home, "constitution.md"))

        # 9. A `.md` in the spec directory that cannot be read at all. A
        #    directory with that name is used because it raises OSError for
        #    every user, root included -- a permission bit does not.
        os.makedirs(os.path.join(home, "notes.md"))
        status, output = drive(["--repo", sandbox])
        if "ERROR SPEC_FILE_UNDECLARED" not in output or status != EXIT_FAILED:
            failures.append("repo-discovery: an unreadable file in the spec "
                            "directory was treated as ruled out: %d %s"
                            % (status, output.strip()))
        os.rmdir(os.path.join(home, "notes.md"))

        # 10. The usage guards. Two answers to "which files are the spec" is
        #     the defect --repo removes, so it refuses rather than picking one.
        def quiet_main(argv):
            captured = io.StringIO()
            saved_out, saved_err = sys.stdout, sys.stderr
            sys.stdout = sys.stderr = captured
            try:
                return main(argv)
            finally:
                sys.stdout, sys.stderr = saved_out, saved_err

        for argv in (["--repo", sandbox, part_a],
                     ["--repo", sandbox, "--baseline", part_a],
                     ["--repo", sandbox, "--counts"],
                     ["--repo", sandbox, "--format", "speckit"],
                     ["--list-files", part_a]):
            if quiet_main(argv) != EXIT_USAGE:
                failures.append("repo-discovery: %s was not a usage error"
                                % " ".join(argv))
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    # ----------------------------------------------------------------------
    # A STORE-SHAPED REPO, which is where discovery read the wrong file and
    # said PASS. `references/spec-stores.md` describes a layout where the
    # living spec is a repository of its own and every consuming repo caches
    # it -- "a clone, a CI checkout, a mirrored file". Discovery is a WORK
    # TREE operation, so in a consuming repo the file sitting at the local
    # spec path IS that cache. Before this block, the tree built by
    # `store_config()` below discovered it, checked it and printed
    # `1 file(s) checked: 0 error(s), 0 warning(s)` at exit 0 -- a clean
    # result over a file that is not the spec, at a sha nobody printed. The
    # three keys the layout introduces (`spec_kind`, `spec_repo`, `spec_path`)
    # were read by nothing at all.
    #
    # Every case here ends in a REFUSAL rather than a pick, because there is
    # no honest pick: the spec is in another repository and `--repo` cannot
    # reach it. Two cases go the other way on purpose -- a `home` kind and a
    # `product.spec_path` that AGREES stay silent -- so that a guard which
    # refuses everything fails here rather than passing.
    # ----------------------------------------------------------------------
    case("repo-store-shaped")
    sandbox = tempfile.mkdtemp(prefix="validate-spec-selftest-store.")
    try:
        home = os.path.join(sandbox, ".claude", "productizer")
        os.makedirs(home)
        cache = os.path.normpath(os.path.join(home, "spec.md"))
        config = os.path.join(home, "config.json")

        def write(path, text):
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text)

        def configure(payload):
            write(config, json.dumps(payload))

        def store_config():
            return {"product": {"name": "orders",
                                "spec_repo": "example/orders-spec",
                                "spec_kind": "store",
                                "spec_ref": "main",
                                "spec_path": ".claude/productizer/spec.md",
                                "repos": ["example/orders-api"]}}

        def refuses(note, *needles):
            """Both `--repo` shapes refuse, and neither names the local file.

            `--list-files` is checked separately from the checking run
            because it is the half another tool consumes: a path printed
            there is asserted to BE the spec, and printing the cache would
            hand `check-superseded-text.sh` a file to read as authoritative.
            """
            for argv in ([], ["--list-files"]):
                status, output = drive(["--repo", sandbox] + argv)
                shown = " ".join(argv) or "(check)"
                if status != EXIT_UNMEASURED:
                    failures.append("repo-store-shaped/%s: %s exited %d, "
                                    "expected %d"
                                    % (note, shown, status, EXIT_UNMEASURED))
                if "DISCOVERY_REFUSED" not in output:
                    failures.append("repo-store-shaped/%s: %s did not refuse: "
                                    "%s" % (note, shown, output.strip()))
                if cache in output.splitlines():
                    failures.append("repo-store-shaped/%s: %s named the local "
                                    "file as the spec anyway" % (note, shown))
                for needle in needles:
                    if needle not in output:
                        failures.append("repo-store-shaped/%s: the refusal "
                                        "never says %r: %s"
                                        % (note, needle, output.strip()))

        # 1. THE REPRODUCTION. A consuming repo of a store, with a cached copy
        #    of the store's spec at the default path. This is the exit 0 that
        #    was measured before the guard, and the file it reported on is a
        #    cache of another repository.
        write(cache, VALID_SPEC)
        configure(store_config())
        refuses("store-with-cache", "spec_kind", "store",
                "example/orders-spec", "cache")

        # 2. The same store binding with nothing cached. The refusal must
        #    still be about the STORE, not "a declared part is not a readable
        #    file" -- the spec is not missing, it is elsewhere, and a message
        #    that says the wrong one sends the reader to create a local file
        #    that must not exist.
        os.remove(cache)
        refuses("store-no-cache", "spec_kind", "store")
        write(cache, VALID_SPEC)

        # 3. An unrecognised `spec_kind`. Falling back to `home` on a value
        #    nobody wrote would make a typo -- "Store", "STORE" -- read the
        #    cache silently, which is case 1 again through a different door.
        configure({"product": {"spec_kind": "Store"}})
        refuses("unknown-kind", "spec_kind", "home")

        # 3b. `null` is a written value, not an omitted key. It exited 0 over
        #     the local file before, because `null` and "absent" were one
        #     `is not None` test. The refusal must spell what the file holds.
        configure({"product": {"spec_kind": None}})
        refuses("null-kind", "spec_kind", "`null`")

        # 3c. A `product` that is present and not an object. Each of these
        #     exited 0 before, read as an empty `product` -- so the store
        #     declaration it might have been was never asked about.
        for note, value in (("product-string", "orders"),
                            ("product-list", ["example/orders-spec"]),
                            ("product-null", None)):
            configure({"product": value})
            refuses(note, "`product`", "not an object")

        # 4. P4, the report-shaping half. These lines are parsed one per line
        #    by other tools, so a config value carrying a newline must not
        #    become a diagnostic line of its own. The value is collapsed and
        #    quoted, never emitted raw.
        configure({"product": {"spec_kind":
                               "store\nforged.md:1: ERROR FORGED: written "
                               "by the config under examination"}})
        status, output = drive(["--repo", sandbox, "--list-files"])
        if status != EXIT_UNMEASURED:
            failures.append("repo-store-shaped/forged-line: exited %d, "
                            "expected %d" % (status, EXIT_UNMEASURED))
        if len([l for l in output.splitlines() if ": ERROR " in l]) != 1:
            failures.append("repo-store-shaped/forged-line: a config value "
                            "wrote a diagnostic line of its own: %r" % output)

        # 5. `product.spec_path` disagreeing with `spec.path`. They are not
        #    two spellings of one key: `spec_path` is a path INSIDE
        #    `spec_repo`, and joining it to ROOT names a local file nobody
        #    declared. Two answers, so neither is used.
        configure({"product": {"spec_home": "example/home",
                               "spec_path": "docs/spec.md"},
                   "spec": {"path": ".claude/productizer/spec.md"}})
        refuses("spec-path-disagrees", "product.spec_path", "spec.path")

        # 6. AND THE OTHER WAY. A `home` kind, and a `product.spec_path` that
        #    agrees, are ordinary repos and stay silent. Without these two a
        #    guard that refused every config would pass every case above.
        for note, payload in (
                ("home-kind", {"product": {"spec_kind": "home",
                                           "spec_home": "example/home"}}),
                # Absent `product`, absent `spec_kind`: omitted is still the
                # default. Without these a guard that refused every missing
                # key would pass 3b and 3c.
                ("no-product", {"spec": {"path": ".claude/productizer/spec.md"}}),
                ("no-kind", {"product": {"spec_home": "example/home"}}),
                ("spec-path-agrees",
                 {"product": {"spec_home": "example/home",
                              "spec_path": ".claude/productizer/spec.md"},
                  "spec": {"path": ".claude/productizer/spec.md"}})):
            configure(payload)
            status, output = drive(["--repo", sandbox, "--list-files"])
            if status != EXIT_CLEAN or output.splitlines() != [cache]:
                failures.append("repo-store-shaped/%s: an ordinary repo was "
                                "refused: %d %s" % (note, status,
                                                    output.strip()))

        # 7. A declared path that leaves ROOT. `--repo` describes a work tree;
        #    a config that aims it at `/etc/passwd` or at a sibling directory
        #    is choosing what gets read on the machine that cloned the repo.
        #    `check-spec-home-stop.sh` already refuses this shape, and the two
        #    disagreeing was a gap of its own.
        #
        #    THE TARGET IS A REAL FILE AND A REAL SPEC, and it is created
        #    OUTSIDE the sandbox on purpose. A first attempt put it inside,
        #    where `../outside/spec.md` resolved to nothing -- removing the
        #    guard then still refused, for "not a readable file", and the
        #    falsification proved only that the message wording had changed.
        #    Sited outside, removing the guard reads the file and exits 0,
        #    which is the behaviour the guard exists to stop.
        outside = tempfile.mkdtemp(prefix="validate-spec-selftest-outside.")
        try:
            target = os.path.join(outside, "spec.md")
            write(target, VALID_SPEC)
            for note, rel in (("escapes-up",
                               os.path.relpath(target, sandbox)),
                              ("absolute", target)):
                configure({"spec": {"path": rel}})
                refuses(note, "leaves ROOT", "P4")
        finally:
            shutil.rmtree(outside, ignore_errors=True)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

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
        case("speckit-clean")
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

        case("speckit-passthrough")
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

        case("speckit-no-fr")
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
        case("speckit-section")
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

    # ------------------------------------------------------------------
    # R39.b - WHICH EXIT CODES THIS SELF-TEST ACTUALLY DROVE.
    #
    # The fixtures above call functions; they never leave the process, so
    # they drive no exit code at all. Every code below is taken from a REAL
    # subprocess whose status is read, and the list printed at the end is
    # computed from those statuses - not typed. A hardcoded list here would
    # be a claim with nothing checking it, which is the thing this protocol
    # exists to refuse.
    #
    # Exit 3 is the self-test's OWN failure code, so it cannot be driven by
    # asking this file to succeed. It is driven from a patched COPY with one
    # deliberate failure injected. The copy runs with the guard variable set,
    # which is what stops it copying itself forever.
    # ------------------------------------------------------------------
    reached = set()
    if not os.environ.get("VALIDATE_SPEC_CHILD"):
        import subprocess
        import tempfile
        env = dict(os.environ, VALIDATE_SPEC_CHILD="1")
        me = os.path.abspath(__file__)

        def drive_exit(args, want, note):
            proc = subprocess.run([sys.executable, me] + args,
                                  capture_output=True, text=True, env=env)
            reached.add(proc.returncode)
            if proc.returncode != want:
                failures.append("r39b-%s: expected exit %d, got %d"
                                % (note, want, proc.returncode))

        work = tempfile.mkdtemp(prefix="validate-spec-r39b.")
        try:
            clean = os.path.join(work, "clean.md")
            with open(clean, "w", encoding="utf-8") as fh:
                fh.write(VALID_SPEC)
            drive_exit([clean, "--quiet"], EXIT_CLEAN, "clean")

            broken = os.path.join(work, "broken.md")
            with open(broken, "w", encoding="utf-8") as fh:
                fh.write(BROKEN_SPEC)
            drive_exit([broken, "--quiet"], EXIT_FAILED, "errors")

            drive_exit(["--counts", "--baseline", clean, clean], EXIT_USAGE, "usage")
            drive_exit([os.path.join(work, "absent.md")], EXIT_UNMEASURED, "unread")

            copy = os.path.join(work, "patched.py")
            source = open(me, encoding="utf-8").read()
            injected = source.replace(
                "    if failures:\n        for failure in failures:",
                '    failures.append("deliberate injection, driving exit 3")\n'
                "    if failures:\n        for failure in failures:", 1)
            if injected == source:
                failures.append("r39b-selftest: the injection anchor moved, so "
                                "exit 3 was NOT driven. Unmeasured, not clean.")
            else:
                with open(copy, "w", encoding="utf-8") as fh:
                    fh.write(injected)
                drive_copy = subprocess.run(
                    [sys.executable, copy, "--self-test"],
                    capture_output=True, text=True, env=env)
                reached.add(drive_copy.returncode)
                if drive_copy.returncode != EXIT_SELFTEST:
                    failures.append("r39b-selftest: a self-test with an injected "
                                    "failure exited %d, not %d"
                                    % (drive_copy.returncode, EXIT_SELFTEST))
        finally:
            shutil.rmtree(work, ignore_errors=True)

    if failures:
        for failure in failures:
            sys.stdout.write("SELF-TEST FAIL: " + failure + "\n")
        sys.stdout.write("self-test FAILED: %d problem(s)\n" % len(failures))
        return EXIT_SELFTEST
    sys.stdout.write("self-test passed: %d fixtures, 0 failures\n"
                     % len(fixtures))
    if reached:
        documented = [EXIT_CLEAN, EXIT_FAILED, EXIT_USAGE,
                      EXIT_SELFTEST, EXIT_UNMEASURED]
        sys.stdout.write("    exit codes reached: %s   documented: %s\n"
                         % (" ".join(str(c) for c in sorted(reached)),
                            " ".join(str(c) for c in documented)))
        missing = [c for c in documented if c not in reached]
        if missing:
            sys.stderr.write("R39.b: documented exit code(s) no case reached: "
                             "%s\n" % " ".join(str(c) for c in missing))
            return EXIT_SELFTEST
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
    parser.add_argument("--repo", metavar="ROOT",
                        help="discover this repo's spec files instead of "
                             "listing them: `spec.path` in "
                             "ROOT/.claude/productizer/config.json, plus the "
                             "constitution beside them. Any other file in the "
                             "spec directory that reads as a spec is an error, "
                             "not a silent inclusion")
    parser.add_argument("--list-files", dest="list_files", action="store_true",
                        help="with --repo, print the discovered spec files one "
                             "per line and check nothing, so another tool can "
                             "read the same list this does")
    parser.add_argument("--self-test", "--selftest", dest="self_test",
                        action="store_true",
                        help="run the built-in fixtures and exit")
    args = parser.parse_args(argv)

    out = sys.stdout
    if args.self_test:
        return self_test()
    discovery = None
    if args.repo is not None:
        for flag, given in (("files", bool(args.files)),
                            ("--baseline", bool(args.baseline)),
                            ("--counts", args.counts),
                            ("--format speckit", args.format == "speckit")):
            if given:
                sys.stderr.write("validate-spec.py: --repo discovers which "
                                 "files are the spec; %s names them, and two "
                                 "answers to the same question is the defect "
                                 "--repo exists to remove\n" % flag)
                return EXIT_USAGE
        discovery = discover_repo(args.repo)
        if discovery.refusal:
            out.write("%s:1: %s DISCOVERY_REFUSED: %s\n"
                      % (os.path.normpath(os.path.join(args.repo,
                                                       CONFIG_PATH)),
                         ERROR, discovery.refusal))
            if not args.quiet:
                out.write("NOT MEASURED: no file under %s was read -- a repo "
                          "whose spec could not be located has not passed.\n"
                          % args.repo)
            return EXIT_UNMEASURED
        if args.list_files:
            for path, why in discovery.undeclared:
                out.write("%s:1: %s SPEC_FILE_UNDECLARED: %s\n"
                          % (path, ERROR, why))
            if discovery.undeclared:
                return EXIT_FAILED
            for path in discovery.spec_paths:
                out.write("%s\n" % path)
            return EXIT_CLEAN
        args.files = discovery.files()
    elif args.list_files:
        sys.stderr.write("validate-spec.py: --list-files reports what --repo "
                         "discovered; without --repo there is no discovery to "
                         "report\n")
        return EXIT_USAGE
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

    # The two cross-file checks need every spec document of the run in hand
    # before any of them is checked, which is why loading and checking are
    # separate passes. `index` is empty for a run holding one spec, so a
    # single-file repository takes exactly the path it took before.
    #
    # NOT UNDER --format speckit. Adapter rule 3 renumbers each file's FR ids
    # from R1 independently, so two adapted files collide on nearly every id
    # and every collision would be the adapter's doing rather than the
    # author's -- the same fairness rule that makes EARS_SECTION_MISMATCH n/a.
    # Suppressed loudly rather than silently: a cross-file check that quietly
    # did not run reads to a later reader as a cross-file check that passed.
    specs = [d for d in documents if d.kind == "spec"]
    index = {}
    cross = documents
    if speckit and len(specs) > 1:
        cross = []
        out.write("speckit: %d spec files adapted in one run. The cross-file "
                  "checks (ID_DEFINED_TWICE, COUNTER_DISAGREES, "
                  "SIBLING_ID_AT_OR_ABOVE_COUNTER, TEXT_DUPLICATE_ACROSS_FILES, "
                  "and citations resolved against sibling spec files) were NOT "
                  "applied: rule 7 synthesises each file's allocator and rule 3 "
                  "renumbers each file's ids from R1, so ids from two spec-kit "
                  "files are not comparable. Not applied is not a pass.\n"
                  % len(specs))
    elif not speckit:
        index = spec_id_locations(documents)

    # The spec is checked first so a constitution given alongside it can have
    # its `Enforced by` ids resolved against real requirements.
    spec = specs[0] if specs else None
    if spec is not None:
        check_spec(spec, siblings=siblings_for(index, spec),
                   others=spec_siblings(cross, spec))
    for doc in documents:
        if doc is spec:
            continue
        check_document(doc, spec=spec, siblings=siblings_for(index, doc),
                       others=spec_siblings(cross, doc))

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

    # A file the run did NOT check has no document to carry a diagnostic, so
    # it is emitted here, in the same format, and counted like any other error.
    # Discovery that found an undeclared spec part and stayed quiet about it
    # would be the per-invocation gap moved one layer down.
    if discovery is not None:
        for path, why in discovery.undeclared:
            out.write("%s:1: %s SPEC_FILE_UNDECLARED: %s\n"
                      % (path, ERROR, why))
            errors += 1

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
