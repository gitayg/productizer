"""Adapt a GitHub spec-kit `spec.md` into Productizer spec grammar, in memory.

WHAT THIS IS FOR. Enforcement is separable from authoring. A spec-kit spec
carries the same semantic content a Productizer spec does -- one behaviour per
bullet, an id, a modal obligation -- written in a different notation. Seven
purely mechanical rewrites move the notation across, and the checks in
`validate-spec.py` then run against it unchanged. Measured, not argued: against
a real `specify-cli` spec, native `validate-spec.py` exits 4 (KIND_UNKNOWN) and
the adapted text exits 0 while raising a real finding the spec-kit-generated
checklist had already ticked off as clean. `references/speckit-format.md`
carries the evidence and the sources.

WHAT THIS IS NOT. It is not a translator and it must never become one. Every
rule is a substitution on ONE line, decided by that line alone. Nothing is
invented, reordered, merged, split or reworded. A line that matches no rule is
copied through byte for byte AND REPORTED, because a silent pass-through is
indistinguishable from a rule that worked, and the reader would credit the
adapter with something it did not do.

THE FILE ON DISK IS NEVER WRITTEN. The adapted text exists only for the length
of one validation run. A tool that rewrites somebody's spec in order to check
it has replaced the thing it was asked to measure.

LINE NUMBERS ARE MAPPED BACK. Rule 7 inserts lines, so an adapted-text line
number is not a source line number. Every adapted line carries the source line
it came from, and `Adaptation.source_line` translates a diagnostic back, so a
finding points at the line the author would have to edit rather than at an
offset in a file that only ever existed in memory.

NOT EVERY CHECK SURVIVES THE CROSSING. spec-kit has no per-requirement status,
no supersession, no permanence rule over ids and no named acceptance table, so
the checks that assert those have nothing to assert. `INAPPLICABLE` names them,
`validate-spec.py` prints them as `n/a` and suppresses them. A check that
cannot apply is `n/a`, never a pass -- reporting an untestable obligation as
green is the exact defect this repository's constitution P1 refuses.

Python 3.8+, standard library only. Deterministic: no clock, no environment,
no network. Two runs over the same input give byte-identical results.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

# --------------------------------------------------------------------------
# The seven rules
# --------------------------------------------------------------------------

# 1. `## Requirements *(mandatory)*` -> `## Requirements`. The suffix is
#    spec-kit template scaffolding. `detect_kind` matches `^##\s+Requirements$`
#    anchored at the end of the line, so the annotation alone is what makes an
#    otherwise well-formed spec unrecognisable.
HEADING_ANNOTATION_RE = re.compile(
    r"^(?P<head>#{1,6}\s+.*?)\s*\*\([^()]*\)\*\s*$")

# 2. `### Functional Requirements` -> `### Ubiquitous`. spec-kit has one
#    requirements sub-heading and no notion of EARS pattern classes, so the
#    heading carries no pattern claim to preserve. The claim this rule
#    SYNTHESISES is why EARS_SECTION_MISMATCH is n/a below: a mismatch would
#    measure this rule's guess, not the author's.
FUNCTIONAL_HEADING_RE = re.compile(r"^###\s+Functional Requirements\s*$")

# 3 + 4. `- **FR-007**: System MUST ...` -> `- **R7** — System MUST ...`.
#    Rule 3 is the id shape (leading zeros dropped, `FR-` prefix dropped);
#    rule 4 is the separator (`:` -> em dash). They land on the same line and
#    are counted apart, because either one alone would leave the bullet
#    unparseable and a single combined count would hide which half fired.
FR_BULLET_RE = re.compile(
    r"^(?P<indent>\s*)-\s+\*\*FR-(?P<num>\d+)\*\*(?P<sep>:)\s*(?P<body>.*)$")

# A bullet inside `## Requirements` that is NOT an FR bullet. Reported as a
# pass-through rather than guessed at.
ANY_BULLET_RE = re.compile(r"^\s*[-*+]\s+")

# 5. The modal rewrite. spec-kit writes RFC-2119 `MUST` with an implicit
#    subject; EARS wants a named system and `shall`. Three surface forms, all
#    anchored at the START of the requirement body, longest first so
#    `System MUST NOT` is never matched by the `System MUST` rule.
MODAL_RULES = (
    (re.compile(r"^System MUST NOT\b"), "The system shall not"),
    (re.compile(r"^System MUST\b"), "The system shall"),
    (re.compile(r"^Users MUST be able to\b"), "The system shall allow users to"),
)

# 6. `### Key Entities` -> `## Key Entities`. Not cosmetic: at level 3 the
#    section stays INSIDE `## Requirements`, and every entity bullet under it
#    is then read as a requirement bullet with no id -- one ID_MALFORMED error
#    per entity, all of them artefacts of the heading depth. Promoting it to
#    level 2 closes the requirements section where spec-kit means it to close.
KEY_ENTITIES_RE = re.compile(r"^###\s+Key Entities\s*$")

# 7. The `Next requirement id` field. spec-kit allocates ids per feature
#    directory and records the allocator nowhere, so there is no field to
#    translate -- this one is DERIVED from the file: one above the highest FR
#    id present. Being derived is exactly why the counter checks are n/a: a
#    number computed from the file cannot disagree with the file.
COUNTER_FIELD = "Next requirement id"
REQUIREMENTS_HEADING_RE = re.compile(r"^##\s+Requirements\s*$")

RULES = (
    (1, "heading annotation stripped",
     "`## Requirements *(mandatory)*` -> `## Requirements`"),
    (2, "requirements sub-heading",
     "`### Functional Requirements` -> `### Ubiquitous`"),
    (3, "requirement id shape", "`FR-0NN` -> `R<n>`"),
    (4, "id separator", "`:` after the id -> em dash"),
    (5, "modal verb",
     "`System MUST` -> `The system shall`, `System MUST NOT` -> "
     "`The system shall not`, `Users MUST be able to` -> "
     "`The system shall allow users to`"),
    (6, "key entities heading", "`### Key Entities` -> `## Key Entities`"),
    (7, "requirement id allocator",
     "`Next requirement id` synthesised from the highest FR id present"),
)

# --------------------------------------------------------------------------
# What does not survive the crossing
# --------------------------------------------------------------------------

# Each entry: (codes, why it cannot apply). `validate-spec.py` prints these as
# `n/a` and drops any problem carrying one of the codes. Most of them cannot
# fire at all against adapted text -- listing them is the point, because a
# check that silently never fires reads to a later reader as a check that
# passed. EARS_SECTION_MISMATCH is the one that genuinely could fire, and
# dropping it is a fairness rule, not a convenience: rule 2 wrote the heading
# it would be measured against.
INAPPLICABLE = (
    (("STATUS_DUPLICATE", "STATUS_MALFORMED", "STATUS_NO_REASON"),
     "spec-kit records no per-requirement status. Every adapted requirement "
     "is active by construction, so there is no status marker to check."),
    (("SUPERSEDE_SELF", "SUPERSEDE_BACKWARD", "SUPERSEDE_TARGET_ABSENT",
      "SUPERSEDED_TEXT_OVERWRITTEN"),
     "spec-kit has no supersession: a changed requirement is edited in place "
     "or appended, never marked as replaced by another id."),
    (("COUNTER_MISSING", "COUNTER_MALFORMED", "ID_AT_OR_ABOVE_COUNTER"),
     "the allocator is synthesised by rule 7 from the ids in the file, so it "
     "cannot disagree with them. Nothing was compared."),
    (("COUNT_MISMATCH",),
     "spec-kit's header declares no active/superseded/withdrawn totals, so "
     "there is no declared number to re-count against."),
    (("CITATION_UNKNOWN",),
     "spec-kit has no `## Acceptance criteria`, `## Change log`, "
     "`## Decision record` or `## Design` section, and its acceptance "
     "scenarios cite no requirement ids. No citation was resolved."),
    (("EARS_SECTION_MISMATCH",),
     "the pattern-section heading is written by rule 2, not by the author; a "
     "mismatch would measure this adapter's guess rather than the spec."),
)

# The permanence family reached only through --baseline. Named separately
# because its reason is a scope statement about spec-kit, not an absence.
BASELINE_NOTE = (
    ("RENUMBERED", "ID_DISAPPEARED", "ID_IDENTITY_CHANGED",
     "SUPERSEDED_TEXT_CHANGED", "COUNTER_REWOUND"),
    "reachable only with --baseline, and only against an earlier copy of the "
    "SAME feature directory's spec.md: spec-kit ids are unique within one "
    "`specs/<nnn>-<slug>/` directory and every directory starts again at "
    "FR-001, so R1 in two features is two different requirements.",
)


# --------------------------------------------------------------------------
# Result
# --------------------------------------------------------------------------

@dataclass
class Adaptation:
    """The adapted text plus everything needed to report on it honestly."""

    text: str = ""
    # `lines[i]` is the 1-based SOURCE line the adapted line `i` came from.
    lines: list = field(default_factory=list)
    # rule number -> how many lines that rule rewrote
    applied: dict = field(default_factory=dict)
    # (source line, what it is, the line itself) for every line inside
    # `## Requirements` that no rule matched
    passthrough: list = field(default_factory=list)
    requirements: int = 0
    next_id: int = 0
    # populated when there was nothing to adapt
    refusal: str = ""

    def source_line(self, adapted_line):
        """Translate an adapted-text line number back to the source file."""
        index = adapted_line - 1
        if 0 <= index < len(self.lines):
            return self.lines[index]
        return 1

    def count(self, rule):
        return self.applied.get(rule, 0)


def adapt(text):
    """Rewrite spec-kit notation into Productizer grammar. One line at a time.

    Returns an `Adaptation`. `refusal` is non-empty when the input carried no
    `- **FR-<n>**:` bullet at all, which is NOT MEASURED rather than clean:
    an adapter that found nothing to adapt has adapted nothing.
    """
    result = Adaptation()
    out = []
    src = []
    highest = 0
    in_requirements = False

    source_lines = text.splitlines()

    for lineno, raw in enumerate(source_lines, start=1):
        # Rule 6 first: it decides where `## Requirements` ends, and reading
        # it after the bullet rules would have already mis-read the entity
        # bullets it exists to move out of the way.
        if KEY_ENTITIES_RE.match(raw):
            out.append("## Key Entities")
            src.append(lineno)
            result.applied[6] = result.count(6) + 1
            in_requirements = False
            continue

        heading = re.match(r"^(?P<hashes>#{1,6})\s+", raw)
        if heading:
            line = raw
            annotated = HEADING_ANNOTATION_RE.match(line)
            if annotated:
                line = annotated.group("head")
                result.applied[1] = result.count(1) + 1
            if len(heading.group("hashes")) <= 2:
                in_requirements = bool(REQUIREMENTS_HEADING_RE.match(line))
            elif FUNCTIONAL_HEADING_RE.match(line):
                line = "### Ubiquitous"
                result.applied[2] = result.count(2) + 1
            out.append(line)
            src.append(lineno)
            continue

        bullet = FR_BULLET_RE.match(raw)
        if bullet:
            number = int(bullet.group("num"))
            highest = max(highest, number)
            result.requirements += 1
            result.applied[3] = result.count(3) + 1
            result.applied[4] = result.count(4) + 1
            body = bullet.group("body")
            rewritten = body
            for pattern, replacement in MODAL_RULES:
                candidate = pattern.sub(replacement, body, count=1)
                if candidate != body:
                    rewritten = candidate
                    result.applied[5] = result.count(5) + 1
                    break
            else:
                result.passthrough.append((
                    lineno, "FR-%s: no modal rule matched, so the requirement "
                            "body is carried over verbatim" % bullet.group("num"),
                    body[:70]))
            out.append("%s- **R%d** — %s"
                       % (bullet.group("indent"), number, rewritten))
            src.append(lineno)
            continue

        if in_requirements and raw.strip() and ANY_BULLET_RE.match(raw):
            result.passthrough.append((
                lineno, "a bullet inside `## Requirements` that is not an "
                        "`- **FR-<n>**:` requirement", raw.strip()[:70]))

        out.append(raw)
        src.append(lineno)

    if result.requirements == 0:
        result.refusal = ("no `- **FR-<n>**:` requirement bullet in this "
                          "file; there was nothing to adapt and nothing was "
                          "checked")
        return result

    result.next_id = highest + 1

    # Rule 7. Inserted immediately before the `## Requirements` heading, which
    # is a position every spec-kit spec has, rather than after a `**Status**`
    # value whose text the template is free to change.
    insert_at = None
    for index, line in enumerate(out):
        if REQUIREMENTS_HEADING_RE.match(line):
            insert_at = index
            break
    if insert_at is None:
        # Rule 1 could not produce a bare `## Requirements`; leave the text
        # alone and let NO_REQUIREMENTS_SECTION say so against the real file.
        result.text = "\n".join(out) + "\n"
        result.lines = src
        return result

    anchor = src[insert_at]
    block = ["", COUNTER_FIELD,
             ": `R%d` — synthesised by rule 7 from the highest FR id in "
             "this file." % result.next_id, ""]
    out[insert_at:insert_at] = block
    src[insert_at:insert_at] = [anchor] * len(block)
    result.applied[7] = 1

    result.text = "\n".join(out) + "\n"
    result.lines = src
    return result


def inapplicable_codes():
    """Every check code `--format speckit` reports as n/a and does not emit."""
    codes = set()
    for group, _reason in INAPPLICABLE:
        codes.update(group)
    return codes
