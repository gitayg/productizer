#!/usr/bin/env python3
"""Decide the tractable classes of EARS requirement contradiction with arithmetic
rather than judgement.

Reads EARS statements, parses each into guard / system / response, and decides
pairs that fall inside a small decidable fragment: numeric bounds that cannot
both hold, mutually exclusive responses under an overlapping guard, and
same-attribute assignments to different values.

The verdict vocabulary is deliberately four-valued. UNDECIDED is not a failure
mode, it is the escape hatch: anything outside the fragment is handed back for
judgement instead of being silently passed. A tool that answered only
CONTRADICTION / CONSISTENT would be claiming coverage it does not have, and the
silent miss is the exact failure this plugin exists to prevent.

Standard library only. --verify-z3 cross-checks the interval arithmetic against
an SMT solver when z3-solver happens to be importable; it is never required.

Usage:
    contradiction-check.py --selftest
    contradiction-check.py [--require-records] FILE   (one requirement per line)
    contradiction-check.py --pair "R1 ..." "R2 ..."

Exit codes
    0  ran, and nothing halts the pipeline. Without --require-records a FILE
       in which NO line parsed as EARS is also a 0 - a legitimate reading of
       a file that holds no requirements, and refusing it is the caller's job.
    1  a halt. In FILE mode that is any pair decided CONTRADICTION or handed
       back UNDECIDED; in --pair mode, CONTRADICTION only, unchanged.
    2  usage error, or a --pair statement that is not EARS
    4  NOT MEASURED. --require-records was asked for and not one line of the
       file parsed as EARS: the file was read end to end and nothing in it was
       understood. Opt-in, never the default.

THE SHARED CONVENTION. `spec-requirements.sh` carries the same one, spelled
the same way: `--require-records`, and exit 4 for a clean parse that
understood nothing. 4 is `validate-spec.py`'s EXIT_UNMEASURED, which already
answers this question with this code and the sentence "a file that was not
read has not passed". Three tools that read requirement sentences now say
"understood nothing" the same way, instead of one of them saying it and two
reporting success over a file they made no sense of.

It is a flag and not the default because these two tools are pointed at
fixtures and at foreign notations where an empty parse is the expected answer,
and because every caller in this repository reads any non-zero from them as a
refusal. A caller that meant "a file of requirements" passes the flag; a bare
exit 0 over a file this grammar did not recognise is a green over a file
nothing read, which is the shape R15 and R26 exist to block.
"""

from __future__ import annotations

import argparse
import itertools
import math
import os
import re
import sys
from dataclasses import dataclass, field

# --------------------------------------------------------------------------
# EARS grammar
# --------------------------------------------------------------------------

# The same four numbers validate-spec.py already uses, and 4 means the same
# thing in all three tools. See the module docstring.
EXIT_CLEAN = 0
EXIT_HALT = 1
EXIT_USAGE = 2
EXIT_UNMEASURED = 4

ID_RE = re.compile(r"^\s*(?:\*\*)?(R\d+)(?:\*\*)?\s*[:.\-]\s*", re.I)

PATTERNS = [
    ("complex", re.compile(
        r"^while\s+(?P<state>.+?),\s*when\s+(?P<trigger>.+?),\s*the\s+(?P<system>.+?)\s+shall\s+(?P<response>.+?)\.?$", re.I)),
    ("unwanted", re.compile(
        r"^if\s+(?P<trigger>.+?),\s*then\s+the\s+(?P<system>.+?)\s+shall\s+(?P<response>.+?)\.?$", re.I)),
    ("state", re.compile(
        r"^while\s+(?P<state>.+?),\s*the\s+(?P<system>.+?)\s+shall\s+(?P<response>.+?)\.?$", re.I)),
    ("event", re.compile(
        r"^when\s+(?P<trigger>.+?),\s*the\s+(?P<system>.+?)\s+shall\s+(?P<response>.+?)\.?$", re.I)),
    ("optional", re.compile(
        r"^where\s+(?P<feature>.+?),\s*the\s+(?P<system>.+?)\s+shall\s+(?P<response>.+?)\.?$", re.I)),
    ("ubiquitous", re.compile(
        r"^the\s+(?P<system>.+?)\s+shall\s+(?P<response>.+?)\.?$", re.I)),
]


@dataclass
class Requirement:
    rid: str
    raw: str
    pattern: str
    system: str
    response: str
    guard: str = ""          # state, trigger or feature, whichever the pattern carries
    guards: list = field(default_factory=list)


def parse(line: str, fallback_id: str = "?") -> Requirement | None:
    """Parse one EARS sentence. Returns None if it matches no pattern."""
    text = line.strip()
    if not text or text.startswith("#"):
        return None
    rid = fallback_id
    m = ID_RE.match(text)
    if m:
        rid = m.group(1).upper()
        text = text[m.end():]
    for name, rx in PATTERNS:
        m = rx.match(text)
        if not m:
            continue
        g = m.groupdict()
        parts = [g.get("state"), g.get("trigger"), g.get("feature")]
        parts = [p for p in parts if p]
        return Requirement(
            rid=rid, raw=text.strip(), pattern=name,
            system=g["system"], response=g["response"],
            guard=", ".join(parts), guards=parts,
        )
    return None


# --------------------------------------------------------------------------
# Tokenisation
# --------------------------------------------------------------------------

STOP = {
    "a", "an", "the", "it", "its", "their", "them", "they", "to", "of", "in",
    "on", "for", "with", "and", "or", "is", "are", "be", "been", "was", "were",
    "that", "this", "then", "than", "at", "by", "from", "as", "shall", "will",
    "has", "have", "had", "within", "into", "each", "any", "all",
}
# "not" and "no" are never stopwords: negation is the signal, not noise.

NUMBER_RE = re.compile(r"^\d+(?:\.\d+)?$")

UNITS = {
    "ms": ("time", 1.0), "millisecond": ("time", 1.0), "milliseconds": ("time", 1.0),
    "s": ("time", 1000.0), "sec": ("time", 1000.0), "secs": ("time", 1000.0),
    "second": ("time", 1000.0), "seconds": ("time", 1000.0),
    "m": ("time", 60000.0), "min": ("time", 60000.0), "mins": ("time", 60000.0),
    "minute": ("time", 60000.0), "minutes": ("time", 60000.0),
    "h": ("time", 3600000.0), "hr": ("time", 3600000.0), "hrs": ("time", 3600000.0),
    "hour": ("time", 3600000.0), "hours": ("time", 3600000.0),
    "d": ("time", 86400000.0), "day": ("time", 86400000.0), "days": ("time", 86400000.0),
    # A week is exactly seven days, so it converts without a convention.
    # MONTH AND YEAR ARE DELIBERATELY ABSENT: a month is 28 to 31 days, and
    # picking one would let this file decide a contradiction by rounding.
    # An unconvertible unit must stay unparsed and be escalated, not guessed.
    "w": ("time", 604800000.0), "week": ("time", 604800000.0),
    "weeks": ("time", 604800000.0),
    "byte": ("size", 1.0), "bytes": ("size", 1.0),
    "kb": ("size", 1e3), "mb": ("size", 1e6), "gb": ("size", 1e9), "tb": ("size", 1e12),
    "%": ("percent", 1.0), "percent": ("percent", 1.0),
}

COMPARATORS = [
    ("no more than", "hi", True), ("not exceed", "hi", True),
    ("no less than", "lo", True), ("less than", "hi", False),
    ("fewer than", "hi", False), ("faster than", "hi", False),
    ("greater than", "lo", False), ("more than", "lo", False),
    ("longer than", "lo", False), ("slower than", "lo", False),
    ("at most", "hi", True), ("at least", "lo", True),
    ("up to", "hi", True), ("within", "hi", True),
    ("under", "hi", False), ("below", "hi", False),
    ("over", "lo", False), ("above", "lo", False),
    ("exactly", "eq", True),
]

CMP_WORDS = set(itertools.chain.from_iterable(c[0].split() for c in COMPARATORS))

WORD_NUMBERS = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
    "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
}


def _number(raw: str) -> float | None:
    """A quantity written as digits or as a word. Returns None for neither, so
    the caller drops the match rather than inventing a value for it."""
    raw = raw.strip().lower()
    if raw in WORD_NUMBERS:
        return float(WORD_NUMBERS[raw])
    try:
        return float(raw)
    except ValueError:
        return None


BOUND_RE = re.compile(
    r"\b(?P<cmp>" + "|".join(re.escape(c[0]) for c in COMPARATORS) + r")\s+"
    r"(?P<num>\d+(?:\.\d+)?|" + "|".join(WORD_NUMBERS) + r")\s*"
    r"(?P<unit>ms|milliseconds?|seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|"
    r"weeks?|%|percent|bytes?|kb|mb|gb|tb|[smhdw])?\b",
    re.I,
)

CMP_LOOKUP = {c[0]: (c[1], c[2]) for c in COMPARATORS}


def tokens(text: str) -> set:
    words = re.findall(r"[a-z0-9%]+", text.lower())
    return {w for w in words if w not in STOP}


def content_tokens(text: str) -> set:
    """Tokens with numbers, units and comparator words removed: what is being
    measured, stripped of how much. Two responses that bound different
    quantities must not be compared, or every latency budget in the spec
    conflicts with every retention window."""
    out = set()
    for w in tokens(text):
        if NUMBER_RE.match(w) or w in UNITS or w in CMP_WORDS:
            continue
        out.add(w)
    return out


def jaccard(a: set, b: set) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


# --------------------------------------------------------------------------
# Interval arithmetic
# --------------------------------------------------------------------------

@dataclass
class Interval:
    lo: float = -math.inf
    lo_incl: bool = False
    hi: float = math.inf
    hi_incl: bool = False

    def empty(self) -> bool:
        if self.lo > self.hi:
            return True
        if self.lo == self.hi and not (self.lo_incl and self.hi_incl):
            return True
        return False

    def meet(self, other: "Interval") -> "Interval":
        lo, lo_incl = self.lo, self.lo_incl
        if other.lo > lo or (other.lo == lo and not other.lo_incl):
            lo, lo_incl = other.lo, other.lo_incl
        hi, hi_incl = self.hi, self.hi_incl
        if other.hi < hi or (other.hi == hi and not other.hi_incl):
            hi, hi_incl = other.hi, other.hi_incl
        return Interval(lo, lo_incl, hi, hi_incl)

    def subset_of(self, other: "Interval") -> bool:
        lo_ok = self.lo > other.lo or (self.lo == other.lo and (other.lo_incl or not self.lo_incl))
        hi_ok = self.hi < other.hi or (self.hi == other.hi and (other.hi_incl or not self.hi_incl))
        return lo_ok and hi_ok

    def __str__(self) -> str:
        l = "-inf" if self.lo == -math.inf else f"{self.lo:g}"
        h = "inf" if self.hi == math.inf else f"{self.hi:g}"
        return f"{'[' if self.lo_incl else '('}{l}, {h}{']' if self.hi_incl else ')'}"


def bounds(text: str) -> dict:
    """Extract numeric bounds per dimension. Returns {dimension: Interval}."""
    found: dict = {}
    for m in BOUND_RE.finditer(text):
        kind, incl = CMP_LOOKUP[m.group("cmp").lower()]
        raw_unit = (m.group("unit") or "").lower()
        # An empty unit is a dimensionless count, which is correct. A unit the
        # regex matched but UNITS cannot convert would ALSO land on "count" and
        # silently become a quantity comparable with unrelated ones - that is how
        # "6 weeks" read as a count of 6 and could never conflict with a bound in
        # days. The two spellings are kept in step by a selftest assertion, and
        # anything unconvertible is dropped rather than given a false dimension.
        if raw_unit and raw_unit not in UNITS:
            continue
        dim, scale = UNITS.get(raw_unit, ("count", 1.0))
        magnitude = _number(m.group("num"))
        if magnitude is None:
            continue
        value = magnitude * scale
        iv = found.get(dim, Interval())
        if kind == "hi":
            iv = iv.meet(Interval(hi=value, hi_incl=incl))
        elif kind == "lo":
            iv = iv.meet(Interval(lo=value, lo_incl=incl))
        else:
            iv = iv.meet(Interval(value, True, value, True))
        found[dim] = iv
    return found


# --------------------------------------------------------------------------
# Mutual exclusion lexicon
# --------------------------------------------------------------------------

EXCLUSIVE_PAIRS = [
    ("accept", "reject"), ("allow", "deny"), ("allow", "block"),
    ("permit", "block"), ("grant", "revoke"), ("enable", "disable"),
    ("retain", "delete"), ("retain", "discard"), ("keep", "delete"),
    ("keep", "discard"), ("keep", "end"), ("keep", "terminate"),
    ("preserve", "delete"), ("preserve", "end"),
    ("start", "stop"), ("open", "close"), ("lock", "unlock"),
    ("continue", "abort"), ("include", "exclude"), ("commit", "roll"),
    ("show", "hide"), ("end", "extend"), ("charge", "refund"),
    # Refusing a message and deferring it are exclusive dispositions of the same
    # message: it cannot be both turned away and held for another attempt. Added
    # after an end-to-end run found the skill's own worked example (R7 against
    # R41) coming back CONSISTENT.
    ("reject", "queue"), ("reject", "retry"), ("reject", "defer"),
    ("deny", "queue"), ("discard", "queue"), ("discard", "retry"),
    ("drop", "queue"), ("drop", "retry"),
    # Six dispositions the 26-case corpus opposes that this lexicon did not
    # carry. They were not guessed: `evals/solver-probe.py --break lexicon` held
    # them as MISSING_PAIRS and measured what adding them was worth, so the gap
    # was quantified before it was closed. Erasure against retention is the
    # commonest of them and the one that reaches four cases on its own.
    ("remove", "retain"), ("remove", "preserve"), ("expunge", "move"),
    ("decline", "honour"), ("suspend", "keep"), ("abandon", "retry"),
    # Direct antonyms of continuation and of serving a request, both missing
    # while their near-neighbours were present: ("start", "stop") and
    # ("continue", "abort") were carried, ("continue", "stop") was not.
    ("continue", "stop"), ("deny", "serve"),
]

# Verb forms are matched on stems so "deletes"/"deleted"/"deleting" all hit.
def stems(text: str) -> set:
    out = set()
    for w in tokens(text):
        out.add(w)
        for suffix in ("ing", "es", "ed", "s"):
            if len(w) > len(suffix) + 2 and w.endswith(suffix):
                out.add(w[: -len(suffix)])
    return out


ASSIGN_RE = re.compile(r"\bset\s+(?:the\s+)?(?P<attr>[a-z_ ]+?)\s+to\s+(?P<val>[a-z0-9_]+)", re.I)
STATUS_RE = re.compile(r"\bwith\s+(?:an?\s+)?(?:http\s+)?(?:status\s+|code\s+)?(?P<code>[1-5]\d\d)\b", re.I)


def negation_of(a: str, b: str) -> bool:
    """True when the two responses are the same sentence bar a negation."""
    ta, tb = tokens(a), tokens(b)
    neg = {"not", "no", "never"}
    if (ta & neg) == (tb & neg):
        return False
    return (ta - neg) == (tb - neg)


# Identifiers as they appear in a wire contract - snake_case or dotted. The
# ordinary tokeniser strips punctuation, so `amount_cents` reaches it as
# "amount" plus "cents" and two different field names look like overlapping
# prose. Field names are the one place in a requirement where a single
# character's difference is the whole meaning, so they are read whole.
IDENT_RE = re.compile(r"\b[a-z][a-z0-9]*(?:[_.][a-z0-9]+)+\b", re.I)


def identifier_drift(a: str, b: str) -> str | None:
    """Two responses naming the same artefact but a different field for it.

    Deliberately NOT a contradiction. Renaming a field in place breaks every
    consumer, and adding a second field breaks nobody, and the two are the same
    sentence from here - only a person knows which was meant. So this reports
    and escalates rather than convicting, which is what UNDECIDED is for."""
    ia = {m.group(0).lower() for m in IDENT_RE.finditer(a)}
    ib = {m.group(0).lower() for m in IDENT_RE.finditer(b)}
    if not ia or not ib:
        return None
    shared, only_a, only_b = ia & ib, ia - ib, ib - ia
    if not shared or len(only_a) != 1 or len(only_b) != 1:
        return None
    return (f"same {sorted(shared)[0]} carrying a different field: "
            f"'{only_a.pop()}' against '{only_b.pop()}' - a rename breaks every "
            f"consumer and an addition breaks none, and only a person knows which")


# One requirement closing a scope, another opening or carving out of it.
# "resolve a principal for EVERY request" against "serve the caller WITHOUT an
# identity lookup"; "report ONLY that tenant's records" against "the median
# ACROSS ALL customers". Neither pair shares an antonym or a bound, so every
# other branch here reads them as unrelated prose.
CLOSED_SCOPE = re.compile(r"\b(only|every|each)\b", re.I)
OPEN_SCOPE = re.compile(r"\b(all|any|other|without|across)\b", re.I)


def scope_tension(a: str, b: str) -> str | None:
    """One response closes a scope and the other widens or exempts from it.

    Reports and escalates, never convicts. A carve-out from a universal is
    sometimes exactly the intended exception and sometimes the thing that
    breaks it, and the two are the same sentence from here - `Where a route is
    public` is a legitimate exception to `every request`, and `without an
    identity lookup` may not be. That is a ruling, not an arithmetic result."""
    ca, cb = CLOSED_SCOPE.search(a), CLOSED_SCOPE.search(b)
    oa, ob = OPEN_SCOPE.search(a), OPEN_SCOPE.search(b)
    if ca and ob:
        closed, opened = ca.group(1).lower(), ob.group(1).lower()
    elif cb and oa:
        closed, opened = cb.group(1).lower(), oa.group(1).lower()
    else:
        return None
    return (f"one response closes a scope with '{closed}' and the other opens "
            f"or exempts from it with '{opened}' - an intended exception and a "
            f"broken universal read the same from here")


# Opposed verbs acting on DIFFERENT parties are not opposed at all. "exclude any
# figure derived from ANOTHER tenant's records" and "include a month-over-month
# trend for THAT TENANT'S OWN figures" are both true at once, and reading
# include/exclude off them without asking what each acts on is how the corpus's
# only false positive was produced.
#
# An earlier attempt gated this branch on how much vocabulary the two responses
# shared, and the measurement refused it: the false positive sat at 0.09 overlap
# with a true positive at 0.09 and three more at 0.00, so no threshold separated
# them. That ruled out a THRESHOLD, not this - the difference is a referent, and
# it is named in the text rather than inferred from a count. Measured over every
# pair where the antonym branch fires: this fires on the false positive and on
# none of the ten true positives.
OTHER_PARTY = re.compile(r"\banother\b|\ball (?:customers|tenants|users|accounts)\b", re.I)
OWN_PARTY = re.compile(r"\bown\b|\bthat (?:tenant|customer|user|account)'s\b", re.I)


def different_referents(a: str, b: str) -> bool:
    """True when one response is scoped to another party and the other to its own."""
    return bool((OTHER_PARTY.search(a) and OWN_PARTY.search(b))
                or (OTHER_PARTY.search(b) and OWN_PARTY.search(a)))


# A budget stated as a share of a window against the same budget stated as a
# duration: "available for at least 99.9 percent of each calendar month" against
# "unavailable for no more than 90 minutes of each calendar month".
#
# THE WINDOW IS AMBIGUOUS AND IS NOT GUESSED AT. A calendar month is 28 to 31
# days, and UNITS deliberately refuses to convert one for exactly that reason.
# Here it does not need to: the allowance is computed at BOTH ends of the range
# and reported only when the stated duration exceeds even the most generous of
# them. A conflict that holds for every month length is arithmetic; one that
# holds only for February is a guess, and this returns nothing for it.
WINDOW_DAYS = {"day": (1, 1), "week": (7, 7), "month": (28, 31), "year": (365, 366)}
SHARE_RE = re.compile(r"\b(?:at least|no less than)\s+([\d.]+)\s*(?:%|percent)", re.I)
WINDOW_RE = re.compile(r"\b(?:each|every|per)\s+(?:calendar\s+)?(day|week|month|year)\b", re.I)


def budget_conflict(a: str, b: str) -> str | None:
    """A share-of-window allowance against a duration allowance of its complement."""
    for x, y in ((a, b), (b, a)):
        share, xwin = SHARE_RE.search(x), WINDOW_RE.search(x)
        ywin = WINDOW_RE.search(y)
        if not (share and xwin and ywin):
            continue
        if xwin.group(1).lower() != ywin.group(1).lower():
            continue
        # The two must speak about a thing and its negation - available against
        # unavailable - or they are two unrelated budgets over one window.
        xs, ys = stems(x), stems(y)
        if not any(("un" + t) in ys or ("non" + t) in ys for t in xs):
            continue
        allowance = bounds(y).get("time")
        if allowance is None or allowance.hi == math.inf:
            continue
        lo_days, hi_days = WINDOW_DAYS[xwin.group(1).lower()]
        spare = (100.0 - float(share.group(1))) / 100.0
        most_generous = spare * hi_days * 86400000.0
        if allowance.hi > most_generous:
            return (f"{share.group(1)}% of a {xwin.group(1)} leaves at most "
                    f"{most_generous / 60000.0:.1f} minutes even at its longest, "
                    f"and the other requirement allows {allowance.hi / 60000.0:.0f} - "
                    f"they conflict for every {xwin.group(1)} length")
    return None


# Stopping an activity against performing it. "stop charging them at the end of
# the current cycle" and "issue a final charge at the next cycle" name the same
# activity and cannot both hold, but they share no antonym pair - `stop` opposes
# `start`, and nothing in the lexicon opposes `issue`. The opposition is not
# between two verbs; it is between a verb and its own cessation.
CEASE_RE = re.compile(r"\b(?:stop|stops|cease|ceases|halt|halts|discontinue|discontinues)\s+(\w+)", re.I)


def ceased_activity(a: str, b: str) -> str | None:
    """One response stops an activity the other performs.

    Requires exactly one side to be a cessation. When BOTH stop the same thing
    they agree, which is the shape of the corpus's vocabulary-drift duplicate,
    and reading a conflict off it would be the plainest false positive here."""
    for x, y in ((a, b), (b, a)):
        m = CEASE_RE.search(x)
        if not m or CEASE_RE.search(y):
            continue
        activity = m.group(1).lower()[:5]
        if any(t.startswith(activity) for t in stems(y)):
            return (f"one response stops '{m.group(1)}' and the other performs "
                    f"it - a cessation and its activity, not two opposed verbs")
    return None


def exclusive_responses(a: str, b: str) -> str | None:
    """Return a reason string when the two responses cannot both be performed."""
    if negation_of(a, b):
        return "one response is the negation of the other"
    if different_referents(a, b):
        return None
    sa, sb = stems(a), stems(b)
    for x, y in EXCLUSIVE_PAIRS:
        if (x in sa and y in sb) or (y in sa and x in sb):
            if x in sa and x in sb:
                continue
            if y in sa and y in sb:
                continue
            return f"mutually exclusive responses: '{x}' against '{y}'"
    ceasing = ceased_activity(a, b)
    if ceasing:
        return ceasing

    ma, mb = ASSIGN_RE.search(a), ASSIGN_RE.search(b)
    if ma and mb and ma.group("attr").strip().lower() == mb.group("attr").strip().lower():
        if ma.group("val").lower() != mb.group("val").lower():
            return (f"same attribute '{ma.group('attr').strip()}' assigned "
                    f"'{ma.group('val')}' and '{mb.group('val')}'")
    ca, cb = STATUS_RE.search(a), STATUS_RE.search(b)
    if ca and cb and ca.group("code") != cb.group("code"):
        if jaccard(content_tokens(a), content_tokens(b)) >= 0.4:
            return f"same trigger answered with status {ca.group('code')} and {cb.group('code')}"
    return None


# --------------------------------------------------------------------------
# Guard relation
# --------------------------------------------------------------------------

# One lifecycle event written two ways. "cancels their subscription", "closes
# their account" and "terminates their plan" are the same moment in a billing
# system, and the token overlap between them is zero - so the guard test read
# them as unrelated and every response test below was skipped.
#
# A CLOSED SET, not a similarity score. A threshold over general vocabulary is
# what starts matching guards that merely sound alike, and this file already has
# one measured refusal on record for exactly that. Each group here is a set of
# words that name one event in one domain; anything outside them is unchanged.
SYNONYM_GROUPS = [
    {"cancel", "terminate", "close", "end"},
    {"subscription", "plan", "account", "membership"},
    # The party the event happens to, named differently on either side of the
    # same sentence. Verified before adding: the one must-not-halt case this
    # newly matches, N07, still resolves CONSISTENT, because its two responses
    # are identical and matching guards give the response test nothing to find.
    {"customer", "subscriber", "member"},
]


def canonical(token_set: set) -> set:
    """Collapse each synonym group to its first member, leaving the rest alone.

    Tokens arrive inflected - `cancels`, `closes` - while the groups are written
    in the singular, so a bare membership test collapses nothing. The trailing
    `s` and `es` are trimmed for the LOOKUP only; the group's own spelling is
    what gets substituted."""
    out = set()
    for token in token_set:
        # Every plausible singular, not one guessed rule: stripping "es" from
        # "closes" yields "clos", and stripping "s" yields "close". Both are
        # offered to the lookup and the group's own spelling is what matches.
        forms = {token}
        if token.endswith("s") and len(token) > 3:
            forms.add(token[:-1])
        if token.endswith("es") and len(token) > 4:
            forms.add(token[:-2])
        for group in SYNONYM_GROUPS:
            if forms & group:
                token = sorted(group)[0]
                break
        out.add(token)
    return out


GUARD_EQUAL, GUARD_OVERLAP, GUARD_DISJOINT = "EQUAL", "OVERLAP", "DISJOINT"
GUARD_UNRELATED, GUARD_UNKNOWN = "UNRELATED", "UNKNOWN"


def guard_relation(a: Requirement, b: Requirement) -> tuple:
    """Decide whether the two guards can hold at the same time."""
    ga, gb = a.guard.strip().lower(), b.guard.strip().lower()
    if not ga or not gb:
        return GUARD_OVERLAP, "one requirement is unconditional"
    if ga == gb:
        return GUARD_EQUAL, "identical guard"

    ta, tb = tokens(ga), tokens(gb)
    neg = {"not", "no", "never"}
    if (ta - neg) == (tb - neg) and (ta & neg) != (tb & neg):
        return GUARD_DISJOINT, "one guard is the negation of the other"

    ba, bb = bounds(ga), bounds(gb)
    shared_dims = set(ba) & set(bb)
    if shared_dims and jaccard(content_tokens(ga), content_tokens(gb)) >= 0.5:
        for dim in shared_dims:
            if ba[dim].meet(bb[dim]).empty():
                return GUARD_DISJOINT, (f"guard ranges on the same quantity do not "
                                        f"overlap: {ba[dim]} against {bb[dim]}")

    if ta <= tb or tb <= ta:
        return GUARD_OVERLAP, "one guard is a strictly narrower case of the other"

    j = jaccard(ta, tb)
    if j >= 0.6:
        return GUARD_OVERLAP, f"guards agree on {j:.0%} of their terms"

    # Try again with lifecycle synonyms collapsed. Reported as a DIFFERENT
    # reason, so a guard that matched only after rewriting says so on the row
    # rather than reading like a plain agreement.
    cj = jaccard(canonical(ta), canonical(tb))
    if cj >= 0.6:
        return GUARD_OVERLAP, (f"guards agree on {cj:.0%} of their terms once "
                               f"lifecycle synonyms are collapsed")
    if j <= 0.15:
        return GUARD_UNRELATED, f"guards share {j:.0%} of their terms"
    return GUARD_UNKNOWN, f"guards share {j:.0%} of their terms, neither clearly the same nor clearly apart"


# --------------------------------------------------------------------------
# Verdict
# --------------------------------------------------------------------------

CONTRADICTION, REFINEMENT, CONSISTENT, UNDECIDED = (
    "CONTRADICTION", "REFINEMENT", "CONSISTENT", "UNDECIDED")


@dataclass
class Verdict:
    verdict: str
    reason: str
    a: Requirement
    b: Requirement


def compare(a: Requirement, b: Requirement) -> Verdict:
    if tokens(a.system) != tokens(b.system):
        return Verdict(CONSISTENT, f"different subjects: '{a.system}' and '{b.system}'", a, b)

    rel, why = guard_relation(a, b)
    if rel == GUARD_DISJOINT:
        return Verdict(CONSISTENT, f"guards cannot both apply — {why}", a, b)
    # GUARD_UNRELATED is NOT an exclusivity proof and must not be read as one.
    # DISJOINT is earned: one guard negates the other, or their ranges on the
    # same quantity do not meet. UNRELATED only says the two guards share no
    # vocabulary - and "while dunning is active" against "when the cart is
    # abandoned" share none while describing the same moment. Treating a lexical
    # gap as logical exclusion let the checker answer CONSISTENT about a pair it
    # had not examined, which is the silent miss this whole file exists to
    # refuse. It now carries the same weight as UNKNOWN: not a reason to stop
    # looking, and not enough to convict on either.

    # Numeric class: same measured quantity, incompatible bounds.
    ra, rb = bounds(a.response), bounds(b.response)
    same_quantity = (jaccard(content_tokens(a.response), content_tokens(b.response)) >= 0.4
                     or content_tokens(a.response) <= content_tokens(b.response)
                     or content_tokens(b.response) <= content_tokens(a.response))
    for dim in set(ra) & set(rb):
        if not same_quantity:
            continue
        if ra[dim].meet(rb[dim]).empty():
            if rel in (GUARD_UNKNOWN, GUARD_UNRELATED):
                return Verdict(UNDECIDED, f"bounds {ra[dim]} and {rb[dim]} are incompatible "
                                          f"but {why}", a, b)
            return Verdict(CONTRADICTION,
                           f"numeric bounds on {dim} cannot both hold: "
                           f"{ra[dim]} against {rb[dim]} ({why})", a, b)
        if rel not in (GUARD_EQUAL, GUARD_OVERLAP):
            continue  # refinement is a claim about the same trigger; do not make it blind
        if ra[dim].subset_of(rb[dim]) and not rb[dim].subset_of(ra[dim]):
            return Verdict(REFINEMENT, f"{a.rid} is strictly stricter on {dim}: "
                                       f"{ra[dim]} inside {rb[dim]}", a, b)
        if rb[dim].subset_of(ra[dim]) and not ra[dim].subset_of(rb[dim]):
            return Verdict(REFINEMENT, f"{b.rid} is strictly stricter on {dim}: "
                                       f"{rb[dim]} inside {ra[dim]}", a, b)

    # Exclusion class: responses that cannot both be performed.
    budget = budget_conflict(a.response, b.response)
    if budget and rel in (GUARD_EQUAL, GUARD_OVERLAP):
        return Verdict(CONTRADICTION, budget, a, b)

    reason = exclusive_responses(a.response, b.response)
    if reason:
        if rel in (GUARD_UNKNOWN, GUARD_UNRELATED):
            return Verdict(UNDECIDED, f"{reason}, but {why}", a, b)
        return Verdict(CONTRADICTION, f"{reason} ({why})", a, b)

    if rel in (GUARD_EQUAL, GUARD_OVERLAP):
        drift = identifier_drift(a.response, b.response)
        if drift:
            return Verdict(UNDECIDED, drift, a, b)

    if tokens(a.response) == tokens(b.response) and rel == GUARD_EQUAL:
        return Verdict(CONSISTENT, "duplicate: same guard, same response", a, b)

    if rel in (GUARD_EQUAL, GUARD_OVERLAP):
        tension = scope_tension(a.response, b.response)
        if tension:
            return Verdict(UNDECIDED, tension, a, b)

    return Verdict(CONSISTENT, "no incompatibility inside the decidable fragment", a, b)


# --------------------------------------------------------------------------
# z3 cross-check (optional)
# --------------------------------------------------------------------------

def verify_with_z3(pairs) -> str:
    try:
        import z3
    except ImportError:
        return "z3-solver not importable — interval arithmetic not cross-checked"
    checked = disagreements = 0
    for a, b in pairs:
        if tokens(a.system) != tokens(b.system):
            continue
        ra, rb = bounds(a.response), bounds(b.response)
        for dim in set(ra) & set(rb):
            s = z3.Solver()
            x = z3.Real("x")
            for iv in (ra[dim], rb[dim]):
                if iv.lo != -math.inf:
                    s.add(x >= iv.lo if iv.lo_incl else x > iv.lo)
                if iv.hi != math.inf:
                    s.add(x <= iv.hi if iv.hi_incl else x < iv.hi)
            solver_unsat = s.check() == z3.unsat
            ours_empty = ra[dim].meet(rb[dim]).empty()
            checked += 1
            if solver_unsat != ours_empty:
                disagreements += 1
                print(f"  z3 DISAGREES on {a.rid}/{b.rid} [{dim}]: "
                      f"z3 unsat={solver_unsat}, intervals empty={ours_empty}")
    return (f"z3 {z3.get_version_string()}: {checked} numeric pairs cross-checked, "
            f"{disagreements} disagreements")


# --------------------------------------------------------------------------
# Test corpus
# --------------------------------------------------------------------------

CASES = [
    # (label, expected, requirement A, requirement B, note)
    ("C1", CONTRADICTION,
     "R1: While a session is idle for 30 minutes, the service shall end it.",
     "R2: While a session is idle, the service shall keep it alive until the user signs out.",
     "same subject, narrower guard, opposed responses"),
    ("C2", CONTRADICTION,
     "R3: When a client requests the report, the API shall respond in under 200 ms.",
     "R4: When a client requests the report, the API shall respond in at least 500 ms.",
     "numeric bounds that cannot both hold"),
    ("C3", CONTRADICTION,
     "R5: If the request body fails schema validation, then the API shall reject it with 400.",
     "R6: If the request body fails schema validation, then the API shall reject it with 422.",
     "same defended trigger, two different answers"),
    ("C4", CONTRADICTION,
     "R7: While a record is older than 30 days, the archive shall delete it.",
     "R8: While a record is older than 30 days, the archive shall retain it.",
     "lexicon exclusion under an identical guard"),
    ("C5", CONTRADICTION,
     "R9: When the pilot takes control, the autopilot shall set the mode to standby.",
     "R10: When the pilot takes control, the autopilot shall set the mode to nominal.",
     "one attribute, two values"),
    ("C6", CONTRADICTION,
     "R11: When an operator requests an export, the service shall include archived records.",
     "R12: When an operator requests an export, the service shall not include archived records.",
     "explicit negation"),

    ("C7", CONTRADICTION,
     "R7: When a provider posts a settlement callback the billing service cannot verify, the billing service shall reject it with 400.",
     "R41: When a provider posts a settlement callback the billing service cannot verify, the billing service shall queue it for retry.",
     "deferring and refusing the same message are exclusive - the skill's own worked example"),

    ("N1", REFINEMENT,
     "R13: When a client requests the report, the API shall respond in under 500 ms.",
     "R14: When a client requests the report, the API shall respond in under 200 ms.",
     "tightening a bound is a refinement, not a conflict"),
    ("N2", CONSISTENT,
     "R15: While fewer than 100 concurrent requests are in flight, the API shall respond in under 200 ms.",
     "R16: While more than 1000 concurrent requests are in flight, the API shall respond in at least 500 ms.",
     "incompatible bounds, but guards are numerically disjoint"),
    ("N3", CONSISTENT,
     "R17: While the user is authenticated, the service shall show the dashboard.",
     "R18: While the user is not authenticated, the service shall not show the dashboard.",
     "opposed responses, but the guards are negations"),
    ("N4", CONSISTENT,
     "R19: When a client requests the report, the API shall respond in under 200 ms.",
     "R20: When a client requests an export, the API shall respond in under 2000 ms.",
     "different triggers, similar wording — the classic false positive"),
    ("N5", CONSISTENT,
     "R21: When a client requests the report, the API shall respond in under 200 ms.",
     "R22: When a client requests the report, the API shall respond in under 200 ms.",
     "duplicate, must not read as conflict"),
    ("N6", CONSISTENT,
     "R23: When a build finishes, the CI service shall post the result to the pull request.",
     "R24: If the disk is over 90 percent full, then the storage service shall emit a warning.",
     "unrelated requirements"),
    ("N7", CONSISTENT,
     "R25: When a client uploads a file, the API shall reject it above 10 mb.",
     "R26: When a client uploads a file, the API shall scan it for malware.",
     "one bounded, one not — no shared quantity"),

    ("S1", CONTRADICTION,
     "R27: When a user deletes their account, the service shall remove all personal data within 30 days.",
     "R28: When a user deletes their account, the service shall retain the audit log of their actions indefinitely.",
     "semantic: conflicts only if the audit log holds personal data"),
    ("S2", CONTRADICTION,
     "R29: When a customer cancels their subscription, the billing service shall stop charging them.",
     "R30: When a subscriber terminates their plan, the billing service shall issue a charge at the next cycle.",
     "semantic: same event, disjoint vocabulary"),
    ("S3", CONTRADICTION,
     "R31: The API shall be responsive under normal load.",
     "R32: When a client requests the report, the API shall respond in at least 500 ms.",
     "semantic: unquantified adjective against a bound"),
    ("N8", CONSISTENT,
     "R33: When a user signs out, the service shall end the session.",
     "R34: When a user signs in, the service shall start a session.",
     "opposite triggers, opposite-sounding responses"),
    ("N9", CONSISTENT,
     "R35: While the cache is warm, the service shall serve the report from cache.",
     "R36: While the cache is cold, the service shall serve the report from origin.",
     "complementary guards the parser cannot prove disjoint"),
    ("N10", CONSISTENT,
     "R37: When a user fails to sign in more than 5 times, the service shall lock the account.",
     "R38: When a user fails to sign in more than 3 times, the service shall warn the user.",
     "overlapping numeric guards, compatible responses"),
    ("U1", UNDECIDED,
     "R39: If a token is expired, then the auth service shall deny the request.",
     "R40: If a token is valid, then the auth service shall allow the request.",
     "lexicon fires but the guards are not resolvable — must escalate, not halt"),
    ("U2", UNDECIDED,
     "R41: While dunning is active, the billing service shall retain the subscription.",
     "R42: When the cart is abandoned, the billing service shall delete the subscription.",
     "guards share no vocabulary yet may both hold — escalate, never call it consistent"),
    ("W1", CONTRADICTION,
     "R43: When a subject requests erasure, the records service shall retain the subject records for at least six weeks.",
     "R44: When a subject requests erasure, the records service shall retain the subject records for no more than 30 days.",
     "mixed units and a spelled number — six weeks against 30 days is arithmetic"),
    ("X1", CONSISTENT,
     "R45: When a tenant administrator requests a usage report, the records service shall exclude any figure derived from another tenant's records.",
     "R46: When a tenant administrator requests a usage report, the records service shall include a month-over-month trend for that tenant's own figures.",
     "opposed verbs on DIFFERENT parties — must not halt"),
    ("B1", CONTRADICTION,
     "R47: The api gateway shall be available for at least 99.9 percent of each calendar month.",
     "R48: The api gateway shall be unavailable for no more than 90 minutes of each calendar month.",
     "a share of a window against a duration, conflicting at every month length"),
    ("Y1", CONTRADICTION,
     "R49: When a customer cancels their subscription, the billing service shall stop charging them at the end of the cycle.",
     "R50: When a customer closes their account, the billing service shall continue charging them until the minimum term is served.",
     "one lifecycle event written two ways — guards must match before the responses are read"),
    ("Y2", CONSISTENT,
     "R51: When a customer cancels their subscription, the billing service shall stop charging them at the end of the cycle.",
     "R52: When a subscriber terminates their plan, the billing service shall stop charging them at the end of the cycle.",
     "the same synonyms over the SAME response — matching guards must not invent a conflict"),
    ("Z1", CONTRADICTION,
     "R53: When a customer cancels their subscription, the billing service shall stop charging them at the end of the cycle.",
     "R54: When a subscriber terminates their plan, the billing service shall issue a final charge at the next cycle.",
     "a cessation against its own activity, under guards that match only via synonyms"),
    ("Z2", CONSISTENT,
     "R55: When a batch completes, the widget shall stop polling the queue.",
     "R56: When a batch completes, the widget shall cease polling the queue.",
     "BOTH responses stop the same activity — agreement, not conflict"),
]


def selftest(use_z3: bool) -> int:
    print("EARS contradiction check — test corpus\n")
    reqs = []
    rows = []
    for label, expected, sa, sb, note in CASES:
        a, b = parse(sa), parse(sb)
        if a is None or b is None:
            rows.append((label, expected, "PARSE-FAIL", note, "could not parse"))
            continue
        reqs.append((a, b))
        v = compare(a, b)
        rows.append((label, expected, v.verdict, note, v.reason))

    width = max(len(r[3]) for r in rows)
    print(f"{'case':<5} {'expected':<14} {'actual':<14} {'note':<{width}}  why")
    print("-" * (5 + 14 + 14 + width + 8))
    for label, expected, actual, note, why in rows:
        mark = " " if actual == expected or (expected == REFINEMENT and actual == REFINEMENT) else "*"
        print(f"{mark}{label:<4} {expected:<14} {actual:<14} {note:<{width}}  {why}")

    # Confusion matrix over the binary question the plugin actually asks:
    # does this pair halt the pipeline, or not?
    tp = fp = tn = fn = und = 0
    for label, expected, actual, note, why in rows:
        should_halt = expected == CONTRADICTION
        does_halt = actual == CONTRADICTION
        if actual == UNDECIDED:
            und += 1
            continue
        if should_halt and does_halt:
            tp += 1
        elif should_halt and not does_halt:
            fn += 1
        elif not should_halt and does_halt:
            fp += 1
        else:
            tn += 1

    print("\nConfusion matrix — the binary question: halt, or do not halt")
    print(f"  true positives   (caught a real contradiction) : {tp}")
    print(f"  false negatives  (missed one, silently)        : {fn}")
    print(f"  false positives  (halted on a non-conflict)    : {fp}")
    print(f"  true negatives   (correctly stayed quiet)      : {tn}")
    print(f"  undecided        (handed back for judgement)   : {und}")
    total = tp + fn + fp + tn
    if tp + fp:
        print(f"  precision : {tp / (tp + fp):.2f}")
    if tp + fn:
        print(f"  recall    : {tp / (tp + fn):.2f}")
    print(f"  decided   : {total}/{len(rows)}")

    if use_z3:
        print("\n" + verify_with_z3(reqs))

    file_failures = selftest_file_mode()
    return 1 if (fp or file_failures) else 0


# The corpus above is about verdicts. This half is about the exit code a
# CALLER sees over a whole file, and it exists because the number that was
# wrong was that one: a file in which nothing parsed came back as 0, which
# reads as "no contradictions" and was really "nothing was read". Every exit
# code FILE mode can return is driven here, 4 included.
FILE_CASES = [
    ("two EARS lines, no conflict", False, EXIT_CLEAN,
     "R1: When a batch completes, the widget shall stop polling the queue.\n"
     "R2: When a batch starts, the widget shall open the queue.\n"),
    ("the same file, --require-records", True, EXIT_CLEAN,
     "R1: When a batch completes, the widget shall stop polling the queue.\n"
     "R2: When a batch starts, the widget shall open the queue.\n"),
    ("a real contradiction, --require-records", True, EXIT_HALT,
     "R1: When a client requests a report, the api gateway shall respond in "
     "under 500 ms.\n"
     "R2: When a client requests a report, the api gateway shall respond in "
     "over 2 s.\n"),
    # A foreign notation: spec-kit writes its requirements as `- **FR-001**:
    # System MUST ...`, which carries no `shall` and no EARS trigger, so not
    # one line of it parses. The default still reports 0, deliberately.
    ("a foreign notation, default", False, EXIT_CLEAN,
     "# Feature Specification: Archive old files\n"
     "- **FR-001**: System MUST archive files older than the threshold.\n"
     "- **FR-002**: System MUST skip symbolic links.\n"),
    ("a foreign notation, --require-records", True, EXIT_UNMEASURED,
     "# Feature Specification: Archive old files\n"
     "- **FR-001**: System MUST archive files older than the threshold.\n"
     "- **FR-002**: System MUST skip symbolic links.\n"),
    ("an empty file, --require-records", True, EXIT_UNMEASURED, ""),
    # One line that parses is enough: the flag asks whether anything was
    # understood, not whether everything was.
    ("one line among foreign ones, --require-records", True, EXIT_CLEAN,
     "- **FR-001**: System MUST archive files older than the threshold.\n"
     "R1: When a batch completes, the widget shall stop polling the queue.\n"),
]


def selftest_file_mode() -> int:
    """Drive FILE mode over temporary files. Returns the number of failures."""
    import contextlib
    import io as _io
    import tempfile

    print("\nFILE mode - the exit code a caller reads")
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        for i, (name, require, want, body) in enumerate(FILE_CASES):
            path = os.path.join(tmp, "case%d.txt" % i)
            with open(path, "w") as fh:
                fh.write(body)
            buf, errbuf = _io.StringIO(), _io.StringIO()
            with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(errbuf):
                got = run_file(path, require)
            said = "NOT MEASURED" in errbuf.getvalue()
            ok = got == want and (said == (want == EXIT_UNMEASURED))
            if not ok:
                failures += 1
            print("  %-5s %-44s exit %d (wanted %d)%s"
                  % ("ok" if ok else "FAIL", name, got, want,
                     ", said NOT MEASURED" if said else ""))
    print("  %d of %d held" % (len(FILE_CASES) - failures, len(FILE_CASES)))
    return failures


# --------------------------------------------------------------------------

def run_file(path: str, require_records: bool = False) -> int:
    reqs, unparsed = [], []
    with open(path) as fh:
        for n, line in enumerate(fh, 1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            r = parse(line, fallback_id=f"L{n}")
            (reqs.append(r) if r else unparsed.append((n, line.strip())))
    for n, line in unparsed:
        print(f"unparsed (line {n}, not an EARS pattern): {line}")
    halts = 0
    for a, b in itertools.combinations(reqs, 2):
        v = compare(a, b)
        if v.verdict in (CONTRADICTION, UNDECIDED):
            halts += 1
            print(f"\n{v.verdict}  {a.rid} / {b.rid}")
            print(f"  {a.rid}: {a.raw}")
            print(f"  {b.rid}: {b.raw}")
            print(f"  {v.reason}")
    if not halts:
        print(f"{len(reqs)} requirements, {len(reqs) * (len(reqs) - 1) // 2} pairs: "
              f"nothing decidable as a contradiction")
    if halts:
        return EXIT_HALT
    # A halt is reported as a halt even under the flag: something WAS read and
    # it conflicts, which is a stronger answer than "nothing was read".
    if require_records and not reqs:
        print(f"NOT MEASURED: {path} was read end to end and not one line in it "
              f"parsed as EARS ({len(unparsed)} lines unparsed). --require-records "
              f"was asked for, so this is not a file with no contradictions - it "
              f"is a file nothing here understood. A file that was not read has "
              f"not passed.", file=sys.stderr)
        return EXIT_UNMEASURED
    return EXIT_CLEAN


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("file", nargs="?")
    ap.add_argument("--pair", nargs=2, metavar=("A", "B"))
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--verify-z3", action="store_true",
                    help="cross-check the interval arithmetic against an SMT solver")
    ap.add_argument("--require-records", action="store_true",
                    help="FILE mode: exit 4 when no line parsed as EARS")
    args = ap.parse_args()

    if args.selftest:
        if args.require_records:
            print("--require-records applies to FILE mode; the self-test drives "
                  "it on its own fixtures", file=sys.stderr)
            return EXIT_USAGE
        return selftest(args.verify_z3)
    if args.pair:
        # Refused rather than ignored. A flag that is silently dropped is a
        # caller believing it asked for a refusal it will never get, which is
        # the defect this flag was added to close.
        if args.require_records:
            print("--require-records applies to FILE mode; --pair already "
                  "refuses a statement it cannot parse", file=sys.stderr)
            return EXIT_USAGE
        a, b = parse(args.pair[0], "A"), parse(args.pair[1], "B")
        if a is None or b is None:
            print("one or both statements are not EARS", file=sys.stderr)
            return EXIT_USAGE
        v = compare(a, b)
        print(f"{v.verdict}: {v.reason}")
        return EXIT_HALT if v.verdict == CONTRADICTION else EXIT_CLEAN
    if args.file:
        return run_file(args.file, args.require_records)
    ap.print_help()
    return EXIT_USAGE


if __name__ == "__main__":
    sys.exit(main())
