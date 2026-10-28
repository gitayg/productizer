#!/usr/bin/env python3
"""The measurement behind check-governance-weakening.sh. See that file's header
for what the governance surface is, what weakening means, why the verdict is
advisory, and what is not asserted.

Reads the two files that decide what the check suite runs and how hard - the
declared checks and the CI workflow - at a BASE and in the WORKING TREE, and
reports every ATOM that moved DOWN the ladder. It never reports a tightening:
adding a check, raising a severity, widening a trigger, adding a workflow step
all move up and are counted as tightenings so the run can say how many it saw.

An atom whose move this rule cannot ORDER is reported as UNDECIDED and counts
as a finding, with both sides printed. It is not a claimed weakening and it is
not silence: a glob rewritten from one string to another is the standing case,
and glob subsumption is not decided here.

Renders three states apart and never as zero: a count is a count, `absent` is a
file that does not exist at that end, and a refusal is a file that could not be
read or parsed. A surface that could not be read is UNMEASURED, so the caller
exits 2 - there is no such thing as "nothing weakened" in a file nobody parsed.

stdout: bare relative paths, unindented, for the files the verdict rests on;
everything else indented by four spaces. This module prints and returns a
verdict; the exit code is the caller's.
"""

import argparse
import sys
from typing import Any, Dict, List, Optional, Tuple

try:
    import yaml
except ImportError:  # pragma: no cover - the caller probes for PyYAML first
    sys.stderr.write("governance-weakening: PyYAML is not importable\n")
    raise SystemExit(2)

ABSENT = "@absent"

# WEAKENED  the atom moved DOWN a ladder this rule orders.
# UNDECIDED the atom moved and this rule cannot say which way.
WEAKENED = "WEAKENED"
UNDECIDED = "UNDECIDED"


class Unmeasured(Exception):
    """A surface that could not be read. Never a pass."""


def load_yaml(path: str, what: str) -> Optional[Dict[str, Any]]:
    """Returns None for a file that is absent at this end, which is a state and
    not an error: a governance file introduced inside the range has no earlier
    version for anything in it to have weakened from."""
    if path == ABSENT:
        return None
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as exc:
        raise Unmeasured("%s could not be read: %s" % (what, exc))
    try:
        doc = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        raise Unmeasured(
            "%s is not valid YAML, so every atom in it is UNKNOWN rather than "
            "unchanged: %s" % (what, exc)
        )
    if doc is None:
        raise Unmeasured("%s is empty, so nothing in it could be compared" % what)
    if not isinstance(doc, dict):
        raise Unmeasured("%s does not parse to a mapping" % what)
    return doc


# --------------------------------------------------------------------------
# ladders. Each returns an integer rank, higher being STRONGER, or None when
# the value is one this rule does not order - which becomes UNDECIDED, never a
# silent equal.
# --------------------------------------------------------------------------

SEVERITY_RANK = {"block": 3, "advise": 2, "ignore": 1}


def severity_rank(value: Any) -> Optional[int]:
    if not isinstance(value, str):
        return None
    return SEVERITY_RANK.get(value.strip().lower())


MUST_COVER_RANK = {"all_triggering": 3, "all": 3, "some": 2, "none": 1}


def must_cover_rank(value: Any) -> Optional[int]:
    if value is None:
        return 0
    if not isinstance(value, str):
        return None
    return MUST_COVER_RANK.get(value.strip().lower())


def truthy_rank(value: Any) -> int:
    """For a key whose FALSE side is the stronger one - `enabled` inverted."""
    return 1 if value else 0


def trigger_rank(when: Any) -> Tuple[Optional[int], str]:
    """`always: true` fires on every run and is the strongest trigger there is.
    A `paths` or `tags` list fires on some runs. Neither is nothing at all."""
    if not isinstance(when, dict):
        return (0, "no trigger at all")
    if when.get("always"):
        return (3, "always")
    if when.get("paths") or when.get("tags"):
        kind = "paths" if when.get("paths") else "tags"
        return (2, kind)
    return (0, "no trigger at all")


def trigger_patterns(when: Any) -> List[str]:
    if not isinstance(when, dict):
        return []
    out = []
    for key in ("paths", "tags"):
        value = when.get(key)
        if isinstance(value, list):
            out.extend("%s:%s" % (key, item) for item in value)
    return sorted(out)


def as_int_set(value: Any) -> Optional[set]:
    if value is None:
        return set()
    if not isinstance(value, list):
        return None
    out = set()
    for item in value:
        if not isinstance(item, int):
            return None
        out.add(item)
    return out


def as_number(value: Any) -> Optional[float]:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


# --------------------------------------------------------------------------
# findings
# --------------------------------------------------------------------------


class Finding:
    def __init__(self, kind: str, atom: str, before: str, after: str, why: str,
                 is_self: bool = False):
        self.kind = kind
        self.atom = atom
        self.before = before
        self.after = after
        self.why = why
        self.is_self = is_self

    def line(self) -> str:
        return "  %s%s: %s  was %s  is now %s. %s" % (
            "SELF " if self.is_self else "",
            self.kind,
            self.atom,
            self.before,
            self.after,
            self.why,
        )


class Surface:
    """One comparison. Accumulates findings, tightenings and the atom count, so
    the run can report how much was examined rather than only what it found."""

    def __init__(self) -> None:
        self.findings: List[Finding] = []
        self.tightenings: List[str] = []
        self.notes: List[str] = []
        self.atoms = 0

    def weakened(self, atom: str, before: Any, after: Any, why: str,
                 is_self: bool = False) -> None:
        self.findings.append(
            Finding(WEAKENED, atom, repr(before), repr(after), why, is_self))

    def undecided(self, atom: str, before: Any, after: Any, why: str,
                  is_self: bool = False) -> None:
        self.findings.append(
            Finding(UNDECIDED, atom, repr(before), repr(after), why, is_self))

    def tightened(self, atom: str, before: Any, after: Any) -> None:
        self.tightenings.append("%s: %r -> %r" % (atom, before, after))

    def ladder(self, atom: str, before: Any, after: Any, rank, why: str,
               is_self: bool = False) -> None:
        """Compare one atom on a ladder. An unorderable value on EITHER side is
        UNDECIDED: a rank this rule does not know is not a rank it may treat as
        equal."""
        self.atoms += 1
        rb, ra = rank(before), rank(after)
        if rb is None or ra is None:
            if before != after:
                self.undecided(atom, before, after,
                               "this rule does not order one of these values, "
                               "so which way it moved is for a person to say")
            return
        if ra < rb:
            self.weakened(atom, before, after, why, is_self)
        elif ra > rb:
            self.tightened(atom, before, after)

    def set_shrank(self, atom: str, before: List[str], after: List[str],
                   why: str) -> None:
        """A membership atom. Members lost is a weakening; members gained is a
        tightening; both at once is UNDECIDED, because a rewritten member is
        indistinguishable from one dropped and another added."""
        self.atoms += 1
        lost = [x for x in before if x not in after]
        gained = [x for x in after if x not in before]
        if lost and gained:
            self.undecided(atom, before, after,
                           "members were lost AND gained in one change, which "
                           "is what a rewrite looks like; whether the new set "
                           "fires on less is for a person to say")
        elif lost:
            self.weakened(atom, before, after, "%s Lost: %s" % (why, ", ".join(lost)))
        elif gained:
            self.tightened(atom, before, after)


# --------------------------------------------------------------------------
# checks.yaml
# --------------------------------------------------------------------------

PERMISSION_RANK = {"none": 0, "read": 1, "write": 2}


def effective_severity(check: Dict[str, Any], doc: Dict[str, Any]) -> Tuple[Any, str]:
    """The severity that ACTUALLY applies, and where it came from. Comparing the
    key alone would miss `defaults.severity` being lowered under checks that
    never mention severity at all."""
    if "severity" in check:
        return (check["severity"], "its own severity key")
    defaults = doc.get("defaults")
    if isinstance(defaults, dict) and "severity" in defaults:
        return (defaults["severity"], "the file's defaults.severity")
    return (None, "nothing declares it")


def checks_by_id(doc: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    out = {}
    entries = doc.get("checks")
    if not isinstance(entries, list):
        raise Unmeasured(
            "the declared checks are not a list, so no check could be located "
            "in it and every atom below is UNKNOWN")
    for entry in entries:
        if isinstance(entry, dict) and isinstance(entry.get("id"), str):
            out[entry["id"]] = entry
    if not out:
        raise Unmeasured(
            "no check with an id was found, so there was nothing to compare")
    return out


def compare_policy(surface: Surface, base: Dict[str, Any], tree: Dict[str, Any]) -> None:
    bp = base.get("policy") if isinstance(base.get("policy"), dict) else {}
    tp = tree.get("policy") if isinstance(tree.get("policy"), dict) else {}

    surface.ladder(
        "policy.empty_run", bp.get("empty_run"), tp.get("empty_run"),
        lambda v: 2 if v == "refuse" else (1 if v is not None else 0),
        "a run that examined nothing no longer refuses, so an empty scope "
        "reads as a clean one")
    surface.ladder(
        "policy.spec_coverage", bp.get("spec_coverage"), tp.get("spec_coverage"),
        lambda v: 2 if v == "require" else (1 if v is not None else 0),
        "a requirement no check names no longer refuses the run, so a check "
        "can be deleted and its obligation go quiet")
    surface.ladder(
        "policy.waivers", bp.get("waivers"), tp.get("waivers"),
        lambda v: 2 if v is None else 1,
        "the waiver directory in the repository under examination is now read, "
        "so that repository can soften its own blocking checks")
    surface.ladder(
        "policy.allow_repo_local_tools",
        bp.get("allow_repo_local_tools"), tp.get("allow_repo_local_tools"),
        lambda v: 1 if v else 2,
        "the repository under examination may now select the executables that "
        "check it")
    defaults_b = base.get("defaults") if isinstance(base.get("defaults"), dict) else {}
    defaults_t = tree.get("defaults") if isinstance(tree.get("defaults"), dict) else {}
    surface.ladder(
        "defaults.severity", defaults_b.get("severity"), defaults_t.get("severity"),
        severity_rank,
        "every check that does not name its own severity now blocks less")


def compare_check(surface: Surface, cid: str, base_check: Dict[str, Any],
                  tree_check: Dict[str, Any], base_doc: Dict[str, Any],
                  tree_doc: Dict[str, Any]) -> None:
    at = lambda key: "checks[%s].%s" % (cid, key)  # noqa: E731

    surface.ladder(at("enabled"), base_check.get("enabled", True),
                   tree_check.get("enabled", True), truthy_rank,
                   "the check is switched off and never runs, so its finding "
                   "cannot happen rather than not happening")

    sev_b, from_b = effective_severity(base_check, base_doc)
    sev_t, from_t = effective_severity(tree_check, tree_doc)
    surface.ladder(
        at("severity (effective)"), sev_b, sev_t, severity_rank,
        "a finding here no longer stops anything. Severity came from %s and now "
        "comes from %s" % (from_b, from_t))

    rank_b, kind_b = trigger_rank(base_check.get("when"))
    rank_t, kind_t = trigger_rank(tree_check.get("when"))
    surface.atoms += 1
    if rank_t < rank_b:
        surface.weakened(
            at("when"), kind_b, kind_t,
            "the check fires on fewer changes than it did, so a change it used "
            "to see now passes it by")
    elif rank_t > rank_b:
        surface.tightened(at("when"), kind_b, kind_t)
    elif kind_b == kind_t:
        surface.set_shrank(
            at("when patterns"), trigger_patterns(base_check.get("when")),
            trigger_patterns(tree_check.get("when")),
            "the check no longer fires on some of what it used to.")

    ec_b = base_check.get("exit_codes") if isinstance(base_check.get("exit_codes"), dict) else {}
    ec_t = tree_check.get("exit_codes") if isinstance(tree_check.get("exit_codes"), dict) else {}
    pass_b, pass_t = as_int_set(ec_b.get("pass")), as_int_set(ec_t.get("pass"))
    surface.atoms += 1
    if pass_b is None or pass_t is None:
        if ec_b.get("pass") != ec_t.get("pass"):
            surface.undecided(at("exit_codes.pass"), ec_b.get("pass"), ec_t.get("pass"),
                              "one side is not a list of integers, so the set "
                              "could not be ordered")
    else:
        widened = sorted(c for c in pass_t - pass_b if c != 0)
        if widened:
            surface.weakened(
                at("exit_codes.pass"), sorted(pass_b), sorted(pass_t),
                "exit code(s) %s now read as a PASS. A non-zero exit is the "
                "tool saying something; this makes the run stop hearing it"
                % ", ".join(str(c) for c in widened))
        elif pass_t != pass_b:
            surface.tightened(at("exit_codes.pass"), sorted(pass_b), sorted(pass_t))

    fail_b, fail_t = as_int_set(ec_b.get("fail")), as_int_set(ec_t.get("fail"))
    surface.atoms += 1
    if fail_b is None or fail_t is None:
        if ec_b.get("fail") != ec_t.get("fail"):
            surface.undecided(at("exit_codes.fail"), ec_b.get("fail"), ec_t.get("fail"),
                              "one side is not a list of integers, so the set "
                              "could not be ordered")
    else:
        dropped = sorted(fail_b - fail_t)
        if dropped:
            surface.weakened(
                at("exit_codes.fail"), sorted(fail_b), sorted(fail_t),
                "exit code(s) %s no longer read as a FAIL"
                % ", ".join(str(c) for c in dropped))
        elif fail_t != fail_b:
            surface.tightened(at("exit_codes.fail"), sorted(fail_b), sorted(fail_t))

    cov_b = base_check.get("coverage")
    cov_t = tree_check.get("coverage")
    surface.atoms += 1
    if isinstance(cov_b, dict) and not isinstance(cov_t, dict):
        surface.weakened(
            at("coverage"), "declared", "absent",
            "the check no longer has to have examined anything, so a tool that "
            "looked at nothing and exited 0 now reads as a pass")
    elif isinstance(cov_b, dict) and isinstance(cov_t, dict):
        surface.ladder(at("coverage.must_cover"), cov_b.get("must_cover"),
                       cov_t.get("must_cover"), must_cover_rank,
                       "the check may now leave some of what triggered it "
                       "unexamined and still pass")
        for key in ("min_covered", "min_rules"):
            nb, nt = as_number(cov_b.get(key)), as_number(cov_t.get(key))
            surface.atoms += 1
            if key in cov_b and key not in cov_t:
                surface.weakened(at("coverage." + key), cov_b.get(key), "absent",
                                 "the floor under how much this check must have "
                                 "examined is gone")
            elif nb is not None and nt is not None and nt < nb:
                surface.weakened(at("coverage." + key), cov_b.get(key), cov_t.get(key),
                                 "the floor under how much this check must have "
                                 "examined was lowered")
            elif nb is not None and nt is not None and nt > nb:
                surface.tightened(at("coverage." + key), cov_b.get(key), cov_t.get(key))


def compare_checks_file(surface: Surface, base: Optional[Dict[str, Any]],
                        tree: Optional[Dict[str, Any]], rel: str) -> None:
    if tree is None:
        if base is not None:
            surface.atoms += 1
            surface.weakened(rel, "declared", "deleted",
                             "the file that declares every check is gone, so "
                             "the suite has nothing to run")
        return
    if base is None:
        surface.notes.append(
            "%s does not exist at the base, so nothing in it has an earlier "
            "state to have weakened from. Every atom in it is NEW, not clean."
            % rel)
        return

    base_checks = checks_by_id(base)
    tree_checks = checks_by_id(tree)
    compare_policy(surface, base, tree)

    for cid, base_check in sorted(base_checks.items()):
        surface.atoms += 1
        if cid not in tree_checks:
            surface.weakened(
                "checks[%s]" % cid, "declared", "deleted",
                "the whole check is gone. Whatever it was measuring is now "
                "unmeasured, which is not the same as clean")
            continue
        compare_check(surface, cid, base_check, tree_checks[cid], base, tree)
    for cid in sorted(set(tree_checks) - set(base_checks)):
        surface.tightened("checks[%s]" % cid, "absent", "declared")


# --------------------------------------------------------------------------
# the workflow
# --------------------------------------------------------------------------

SWALLOW = ("|| true", "|| :", "|| exit 0", "||true", "|| /bin/true")
TOOL_SUFFIXES = (".sh", ".py")


def step_label(step: Dict[str, Any], index: int) -> str:
    """A step's identity inside its job, from what the step SAYS it is, never
    from where it sits. Measured on this repository (B138): at ba343ed the
    `release-draft` job lost its unnamed checkout and gained an unnamed
    download step in the same position, and a reader keyed on `#0` compared the
    download against the checkout as one step and reported nothing. So: the
    `id` when there is one; else the `name` and the action `uses` names, with
    its `@ref` dropped so a pin bump is the same step; else the first line of
    `run`. A position is the last resort, for a step that says nothing."""
    sid = step.get("id")
    if isinstance(sid, str) and sid.strip():
        return "id=%s" % sid.strip()
    name = step.get("name")
    uses = step.get("uses")
    action = uses.split("@", 1)[0].strip() if isinstance(uses, str) else ""
    if isinstance(name, str) and name.strip():
        return "%s (uses %s)" % (name, action) if action else name
    if action:
        return "uses %s" % action
    run = step.get("run")
    if isinstance(run, str):
        lines = logical_lines(run)
        if lines:
            return "run: %s" % lines[0][:80]
    return "#%d" % index


def workflow_steps(doc: Dict[str, Any]) -> List[Tuple[str, Dict[str, Any]]]:
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict):
        raise Unmeasured(
            "the workflow declares no jobs mapping, so no step could be located")
    out = []
    for jname, job in sorted(jobs.items()):
        if not isinstance(job, dict):
            continue
        steps = job.get("steps")
        if not isinstance(steps, list):
            continue
        seen: Dict[str, int] = {}
        for index, step in enumerate(steps):
            if not isinstance(step, dict):
                continue
            label = step_label(step, index)
            # Two steps that say the same thing - two bare checkouts - are told
            # apart by their order AMONG THEMSELVES, which a step of another
            # kind inserted between them does not shift.
            seen[label] = seen.get(label, 0) + 1
            if seen[label] > 1:
                label = "%s #%d" % (label, seen[label])
            out.append(("%s/%s" % (jname, label), step))
    if not out:
        raise Unmeasured("the workflow holds no steps, so there was nothing to compare")
    return out


def logical_lines(run: str) -> List[str]:
    """A shell line, with backslash continuations JOINED and whitespace
    collapsed. Measured on this repository's history: at 145d934 an invocation
    was reformatted from a three-line continuation into one line, and a reader
    that split on newlines called `python3 ... validate-spec.py \\` a lost
    invocation. A continuation is one command however it is wrapped."""
    joined = []
    buffer = ""
    for raw in run.split("\n"):
        stripped = raw.rstrip()
        if stripped.endswith("\\"):
            buffer += stripped[:-1] + " "
            continue
        joined.append(" ".join((buffer + stripped).split()))
        buffer = ""
    if buffer:
        joined.append(" ".join(buffer.split()))
    return [line for line in joined if line and not line.startswith("#")]


def invocations(steps: List[Tuple[str, Dict[str, Any]]]) -> Dict[str, str]:
    """Every logical line of every `run:` block that names a `.sh` or `.py`
    file, keyed by that line. FILE-WIDE rather than per step, so moving an
    invocation from one step to another is not read as a loss."""
    out = {}
    for key, step in steps:
        run = step.get("run")
        if not isinstance(run, str):
            continue
        for line in logical_lines(run):
            if any(tok.endswith(TOOL_SUFFIXES) for tok in line.split()):
                out[line] = key
    return out


def step_body(step: Dict[str, Any], keys=("uses", "with", "env", "run", "shell")) -> str:
    """What a step DOES, with its name and its formatting taken out. Steps are
    keyed by name, and a name is documentation: measured on this repository, at
    3b7d2d4 a step was renamed from `... the 2026-09-05 baseline` to
    `... 2026-09-06`, and a reader keyed on the name alone called that a deleted
    step. The body is what decides whether anything stopped happening."""
    parts = []
    for key in keys:
        value = step.get(key)
        if isinstance(value, str):
            parts.append("%s=%s" % (key, " ".join(logical_lines(value))))
        elif value is not None:
            parts.append("%s=%r" % (key, value))
    return "\n".join(parts)


def trigger_set(doc: Dict[str, Any]) -> List[str]:
    """PyYAML reads the bare key `on` as the boolean True under YAML 1.1, so
    both spellings are looked for. A trigger read as absent when it is present
    would report every workflow as having lost its triggers."""
    node = doc.get("on", doc.get(True))
    out = []
    if isinstance(node, str):
        return [node]
    if isinstance(node, list):
        return sorted(str(x) for x in node)
    if isinstance(node, dict):
        for event, body in node.items():
            if not isinstance(body, dict):
                out.append(str(event))
                continue
            wrote = False
            for filt, values in body.items():
                if isinstance(values, list):
                    for value in values:
                        out.append("%s.%s:%s" % (event, filt, value))
                        wrote = True
            if not wrote:
                out.append(str(event))
    return sorted(out)


REST = "*"
LEVEL_NAME = {0: "none", 1: "read", 2: "write"}
INHERITED = "the repository's default, which this file does not state"


def token_levels(node: Any) -> Optional[Dict[str, Optional[int]]]:
    """A `permissions` block as scope -> rank, with REST standing for every
    scope it does not name. None is a token this file does not state at all -
    no block here or above it, so GitHub's repository default applies - and a
    rank of None is a value this rule does not order."""
    if node is None:
        return None
    if isinstance(node, str):
        return {REST: {"read-all": 1, "write-all": 2}.get(node.strip().lower())}
    if isinstance(node, dict):
        out: Dict[str, Optional[int]] = {REST: 0}
        for scope, value in node.items():
            out[str(scope)] = PERMISSION_RANK.get(str(value).strip().lower())
        return out
    return {REST: None}


def job_token(doc: Dict[str, Any], jname: str) -> Any:
    """The `permissions` node a job's token is actually cut from: its own block
    when it has one - which REPLACES the workflow's, it does not add to it - and
    the workflow's otherwise. None when neither says."""
    job = (doc.get("jobs") or {}).get(jname)
    if isinstance(job, dict) and "permissions" in job:
        return job.get("permissions")
    return doc.get("permissions")


def render_level(levels: Optional[Dict[str, Optional[int]]], scope: str) -> str:
    if levels is None:
        return INHERITED
    rank = levels.get(scope, levels[REST])
    return LEVEL_NAME.get(rank, "a value this rule does not order") if rank is not None \
        else "a value this rule does not order"


def render_token(node: Any) -> str:
    levels = token_levels(node)
    if levels is None:
        return INHERITED
    named = ["%s: %s" % (s, render_level(levels, s)) for s in sorted(levels) if s != REST]
    if levels[REST] != 0 or not named:
        named.append("every other scope: %s" % render_level(levels, REST))
    return ", ".join(named)


def compare_token(surface: Surface, prefix: str, base_node: Any, tree_node: Any,
                  why: str) -> None:
    """Every scope either side names, plus the rest. A scope that can do more
    than it could is a weakening whatever else moved; a token this file does not
    state on one side only is UNDECIDED, because the repository default it
    stands for may be wider or narrower than the block on the other side."""
    lb, lt = token_levels(base_node), token_levels(tree_node)
    if lb is None and lt is None:
        return
    scopes = sorted(set(lb or {}) | set(lt or {}))
    for scope in scopes:
        if scope == REST and (lb or {}).get(REST) == 0 and (lt or {}).get(REST) == 0:
            continue
        surface.atoms += 1
        atom = "%s.%s" % (prefix, "(every scope not named)" if scope == REST else scope)
        rb = None if lb is None else lb.get(scope, lb[REST])
        rt = None if lt is None else lt.get(scope, lt[REST])
        before, after = render_level(lb, scope), render_level(lt, scope)
        if rb is None or rt is None:
            if before != after:
                surface.undecided(atom, before, after,
                                  "one side is a token this rule cannot rank, so "
                                  "whether it can do more is for a person to say")
        elif rt > rb:
            surface.weakened(atom, before, after, why)
        elif rt < rb:
            surface.tightened(atom, before, after)


def token_move(base_node: Any, tree_node: Any) -> Tuple[str, str]:
    """Which way a step moved when it left one job for another: by the most the
    token can do first - a step that could write and now cannot write anything
    is a tightening even where the new token reads one more scope - then scope
    by scope. Returns (verdict, rendered tokens)."""
    lb, lt = token_levels(base_node), token_levels(tree_node)
    shown = "%s -> %s" % (render_token(base_node), render_token(tree_node))
    if lb is None or lt is None:
        return ("same" if lb is None and lt is None else UNDECIDED, shown)
    pairs = [(lb.get(s, lb[REST]), lt.get(s, lt[REST])) for s in set(lb) | set(lt)]
    if any(b is None or t is None for b, t in pairs):
        return (UNDECIDED, shown)
    mb, mt = max(b for b, _ in pairs), max(t for _, t in pairs)
    if mt != mb:
        return (WEAKENED if mt > mb else "tightened", shown)
    wider = any(t > b for b, t in pairs)
    narrower = any(t < b for b, t in pairs)
    if wider and narrower:
        return (UNDECIDED, shown)
    if wider:
        return (WEAKENED, shown)
    return ("tightened" if narrower else "same", shown)


def compare_tokens(surface: Surface, base: Dict[str, Any], tree: Dict[str, Any]) -> None:
    """The workflow's default token, then every job's. Before B138 only the
    top-level block was read: at ba343ed a new job was given `pull-requests:
    read`, which no token in the workflow had held, and nothing was reported,
    because a job-level block was never looked at - new job or old."""
    compare_token(surface, "workflow.permissions", base.get("permissions"),
                  tree.get("permissions"),
                  "the token this job holds can do more than it could, so a "
                  "compromised step has more to steal")
    bjobs = base.get("jobs") if isinstance(base.get("jobs"), dict) else {}
    tjobs = tree.get("jobs") if isinstance(tree.get("jobs"), dict) else {}
    for jname in sorted(set(bjobs) | set(tjobs)):
        bjob, tjob = bjobs.get(jname), tjobs.get(jname)
        own_b = isinstance(bjob, dict) and "permissions" in bjob
        own_t = isinstance(tjob, dict) and "permissions" in tjob
        prefix = "workflow.jobs[%s].permissions" % jname
        if bjob is not None and tjob is not None:
            # A job that inherits on both sides moves only with the workflow's
            # default, which is the atom above. Reading it again here would
            # report one fact twice.
            if own_b or own_t:
                compare_token(surface, prefix, job_token(base, jname),
                              job_token(tree, jname),
                              "this job's token can do more than it could, so a "
                              "compromised step in it has more to steal")
        elif tjob is not None and own_t:
            # A NEW job has no earlier token of its own. What it is measured
            # against is what a job added to this workflow at the base would
            # have held without a block: the workflow's default there. Every
            # scope it names is printed, so a narrow one is seen as well.
            surface.notes.append(
                "workflow.jobs[%s] is new and cuts its own token: %s. Each scope "
                "is compared against the workflow's default at the base (%s)."
                % (jname, render_token(tjob.get("permissions")),
                   render_token(base.get("permissions"))))
            compare_token(surface, prefix, base.get("permissions"),
                          tjob.get("permissions"),
                          "a new job holds a token that can do more than the "
                          "workflow's default at the base allowed, so a "
                          "compromised step in it has more to steal")
        elif bjob is not None and own_b and tjob is None:
            surface.tightened(prefix, render_token(bjob.get("permissions")),
                              "the job is gone, and its token with it")


def job_needs(job: Dict[str, Any]) -> List[str]:
    needs = job.get("needs")
    if isinstance(needs, str):
        return [needs]
    if isinstance(needs, list):
        return [str(x) for x in needs]
    return []


def compare_jobs(surface: Surface, base: Dict[str, Any], tree: Dict[str, Any]) -> None:
    """A job kept at both ends: what it waits for and when it runs (B149).
    Before 1.2 neither was read, so dropping `needs: checks` from a release job
    - the line that keeps it behind the checks - was not reported."""
    bjobs = base.get("jobs") if isinstance(base.get("jobs"), dict) else {}
    tjobs = tree.get("jobs") if isinstance(tree.get("jobs"), dict) else {}
    for jname in sorted(set(bjobs) & set(tjobs)):
        bjob, tjob = bjobs[jname], tjobs[jname]
        if not isinstance(bjob, dict) or not isinstance(tjob, dict):
            continue
        surface.set_shrank("workflow.jobs[%s].needs" % jname, job_needs(bjob), job_needs(tjob),
                           "the job no longer waits for those jobs, so it runs, and can "
                           "finish, where they failed or never ran.")
        surface.atoms += 1
        atom = "workflow.jobs[%s].if" % jname
        if "if" not in bjob and "if" in tjob:
            surface.weakened(atom, "unconditional", tjob.get("if"),
                             "the job became conditional, so there are now runs in "
                             "which none of its steps happen")
        elif "if" in bjob and "if" not in tjob:
            surface.tightened(atom, bjob.get("if"), "unconditional")
        elif bjob.get("if") != tjob.get("if"):
            surface.undecided(atom, bjob.get("if"), tjob.get("if"),
                              "the job's condition was rewritten. Whether it now runs "
                              "in fewer cases is for a person to say")


def compare_workflow(surface: Surface, base: Optional[Dict[str, Any]],
                     tree: Optional[Dict[str, Any]], rel: str) -> None:
    if tree is None:
        if base is not None:
            surface.atoms += 1
            surface.weakened(rel, "declared", "deleted",
                             "the workflow is gone, so nothing off a "
                             "maintainer's own machine runs any of this")
        return
    if base is None:
        surface.notes.append(
            "%s does not exist at the base, so nothing in it has an earlier "
            "state to have weakened from." % rel)
        return

    base_steps = dict(workflow_steps(base))
    tree_steps = dict(workflow_steps(tree))

    surface.set_shrank("workflow.on", trigger_set(base), trigger_set(tree),
                       "the workflow no longer runs on some of what it used to, "
                       "so those pushes and pull requests are unchecked.")

    compare_tokens(surface, base, tree)
    compare_jobs(surface, base, tree)

    # A STEP GONE BY NAME IS NOT YET A STEP GONE. Three corrections, each forced
    # by this repository's own history rather than imagined:
    #   - an identical body under a new name IN THE SAME JOB is a RENAME.
    #     Neither a weakening nor a tightening; it is reported so the reader can
    #     disagree.
    #   - an identical body in ANOTHER job is a MOVE, and what moved is the
    #     token the step runs under. At ba343ed a checkout left the
    #     `contents: write` job for a read-only one; that is a tightening, and
    #     it is printed as one rather than read as nothing (B138).
    #   - a body that changed too, while every tool the step invoked still runs
    #     somewhere in the file, is UNDECIDED. Something was reorganised and
    #     nothing measurably stopped. A real deletion takes its invocations with
    #     it, and those are reported by the invocation atom below.
    gained_keys = sorted(set(tree_steps) - set(base_steps))
    gained_bodies: Dict[str, List[str]] = {}
    for k in gained_keys:
        gained_bodies.setdefault(step_body(tree_steps[k]), []).append(k)
    renamed_from = set()
    tree_invocations = set(invocations(list(tree_steps.items())))
    for key in sorted(base_steps):
        surface.atoms += 1
        if key not in tree_steps:
            body = step_body(base_steps[key])
            job = key.split("/", 1)[0]
            free = [k for k in gained_bodies.get(body, []) if k not in renamed_from]
            same_job = [k for k in free if k.split("/", 1)[0] == job]
            if same_job:
                renamed_from.add(same_job[0])
                surface.notes.append(
                    "workflow.step[%s] was renamed to [%s] with an identical "
                    "body. A name is documentation; nothing it runs changed."
                    % (key, same_job[0]))
                continue
            if free:
                dest = free[0]
                renamed_from.add(dest)
                verdict, shown = token_move(
                    job_token(base, job), job_token(tree, dest.split("/", 1)[0]))
                atom = "workflow.step[%s]" % key
                moved = "moved to [%s]" % dest
                if verdict == WEAKENED:
                    surface.weakened(atom, "in job %s" % job, moved,
                                     "the same step now runs holding a token "
                                     "that can do more (%s)" % shown)
                elif verdict == UNDECIDED:
                    surface.undecided(atom, "in job %s" % job, moved,
                                      "the step moved between tokens this rule "
                                      "cannot order (%s); whether it now runs "
                                      "with more is for a person to say" % shown)
                elif verdict == "tightened":
                    surface.tightened(atom, "in job %s" % job,
                                      "%s, under a token that can do less (%s)"
                                      % (moved, shown))
                else:
                    surface.notes.append(
                        "workflow.step[%s] %s with an identical body, under an "
                        "identical token (%s)." % (key, moved, shown))
                continue
            lost_work = [line for line in invocations([(key, base_steps[key])])
                         if line not in tree_invocations]
            if gained_keys and not lost_work:
                surface.undecided(
                    "workflow.step[%s]" % key, "declared", "gone by that name",
                    "the step is gone by name while every tool it invoked still "
                    "runs somewhere in this workflow, and step(s) were added in "
                    "the same change. Whether anything stopped happening is for "
                    "a person to say")
                continue
            surface.weakened("workflow.step[%s]" % key, "declared", "deleted",
                             "a whole step no longer runs. What it asserted is "
                             "now unasserted")
            continue
        bstep, tstep = base_steps[key], tree_steps[key]
        surface.ladder("workflow.step[%s].continue-on-error" % key,
                       bstep.get("continue-on-error", False),
                       tstep.get("continue-on-error", False),
                       lambda v: 0 if v else 1,
                       "the step's failure can no longer set the job's status, "
                       "so it is a step that runs and decides nothing")
        surface.atoms += 1
        if "if" not in bstep and "if" in tstep:
            surface.weakened("workflow.step[%s].if" % key, "unconditional",
                             tstep.get("if"),
                             "the step became conditional, so there are now "
                             "runs in which it does not happen at all")
        elif "if" in bstep and "if" not in tstep:
            surface.tightened("workflow.step[%s].if" % key, bstep.get("if"),
                              "unconditional")
        elif bstep.get("if") != tstep.get("if"):
            surface.undecided("workflow.step[%s].if" % key, bstep.get("if"),
                              tstep.get("if"),
                              "the step's condition was rewritten. Whether it now "
                              "runs in fewer cases is for a person to say")
        # A STEP THAT KEPT ITS KEY IS NOT YET A STEP THAT KEPT ITS WORK (B149).
        # Its key is its id, or its name and action, so a rewritten `run:` or
        # `with:` under the same name was never compared. The action's @ref is
        # left out, as in the key: a pin bump is the same step.
        surface.atoms += 1
        work_b = step_body(bstep, ("with", "env", "run", "shell"))
        work_t = step_body(tstep, ("with", "env", "run", "shell"))
        if work_b != work_t:
            surface.undecided("workflow.step[%s].body" % key, work_b, work_t,
                              "the step kept its key and what it runs changed. "
                              "Whether it now asserts less is for a person to say")
    for key in sorted(set(tree_steps) - set(base_steps)):
        if key not in renamed_from:
            surface.tightened("workflow.step[%s]" % key, "absent", "declared")

    inv_b = invocations(list(base_steps.items()))
    inv_t = invocations(list(tree_steps.items()))

    def tools(line: str) -> List[str]:
        return [tok for tok in line.split() if tok.endswith(TOOL_SUFFIXES)]

    tools_t = {tool for line in inv_t for tool in tools(line)}
    surface.atoms += 1
    for line in sorted(set(inv_b) - set(inv_t)):
        # AN INVOCATION LOST IS NOT YET A TOOL LOST. Measured on this
        # repository: at 145d934 `validate-spec.py <two paths>` became
        # `validate-spec.py --repo .`, and the first version of this rule called
        # that a tool nobody asks any more. The tool still runs; its argv
        # changed, and whether the new argv asks for less is for a person to
        # say. Only a tool that appears in no invocation at all is a weakening.
        if all(tool in tools_t for tool in tools(line)):
            surface.undecided(
                "workflow.invocation", line, "a different argv for the same tool",
                "every tool on this line still runs somewhere in the workflow "
                "with different arguments. Whether the new arguments ask for "
                "less is for a person to say")
        else:
            surface.weakened(
                "workflow.invocation", line, "absent",
                "the workflow no longer runs this, and %s appears in no "
                "invocation at all. It is not a tool that failed; it is a tool "
                "nobody asks any more"
                % ", ".join(t for t in tools(line) if t not in tools_t))
    for line in sorted(set(inv_t) - set(inv_b)):
        surface.tightened("workflow.invocation", "absent", line)
    for line in sorted(inv_t):
        surface.atoms += 1
        if any(s in line for s in SWALLOW):
            bare = line
            for s in SWALLOW:
                bare = bare.replace(s, "").strip()
            if not any(s in old for old in inv_b for s in SWALLOW if bare in old):
                surface.weakened(
                    "workflow.invocation swallowed", bare, line,
                    "the invocation's failure is discarded on the line that "
                    "makes it, so the tool runs and the job stays green")


# --------------------------------------------------------------------------
# this check's own footing
# --------------------------------------------------------------------------


def compare_self(surface: Surface, self_id: str, self_script: str,
                 base: Optional[Dict[str, Any]], tree: Optional[Dict[str, Any]],
                 wf_tree: Optional[Dict[str, Any]], runner: str) -> bool:
    """Returns True when the footing could be measured at all. A reporter whose
    own removal is invisible to it is the same hole one level up, so these atoms
    are examined in both modes and labelled SELF."""
    if tree is None:
        surface.weakened("self.declaration", "declared", "no checks file",
                         "there is no declared-checks file, so this check is "
                         "declared nowhere and runs nowhere", is_self=True)
        return True
    tree_checks = checks_by_id(tree)
    base_checks = checks_by_id(base) if base is not None else {}
    if self_id not in tree_checks and self_id not in base_checks:
        surface.notes.append(
            "this check is not declared as %r at the base or in the working "
            "tree. It is UNCOUNTED: check-selftest-coverage.sh measures the "
            "tools the suite invokes, and a script nothing declares is in "
            "neither its numerator nor its denominator. Its own footing could "
            "not be asserted." % self_id)
        return False

    surface.atoms += 1
    if self_id not in tree_checks:
        surface.weakened("self.declaration", "declared as %s" % self_id, "deleted",
                         "the check that reports weakenings was itself removed, "
                         "and this run is the last one that could say so",
                         is_self=True)
        return True

    mine = tree_checks[self_id]
    base_mine = base_checks.get(self_id)

    surface.ladder("self.enabled", (base_mine or {}).get("enabled", True),
                   mine.get("enabled", True), truthy_rank,
                   "the check that reports weakenings is switched off",
                   is_self=True)
    if base_mine is not None:
        sev_b, _ = effective_severity(base_mine, base or {})
        sev_t, _ = effective_severity(mine, tree)
        surface.ladder("self.severity (effective)", sev_b, sev_t, severity_rank,
                       "the check that reports weakenings carries less weight "
                       "than it did", is_self=True)

    surface.atoms += 1
    argv = mine.get("command") if isinstance(mine.get("command"), list) else []
    if not any(isinstance(tok, str) and tok.endswith(self_script) for tok in argv):
        surface.weakened(
            "self.command", "names %s" % self_script, " ".join(str(a) for a in argv),
            "the declared check no longer runs this script, so the id is "
            "declared and the measurement is not", is_self=True)

    surface.atoms += 1
    if wf_tree is None:
        surface.weakened("self.ci", "the workflow runs %s" % runner, "no workflow",
                         "nothing off a maintainer's own machine runs the "
                         "declared checks, this one included", is_self=True)
    else:
        found = any(runner in line for line in invocations(workflow_steps(wf_tree)))
        if not found:
            surface.weakened(
                "self.ci", "the workflow runs %s" % runner, "absent",
                "the workflow no longer runs the suite, so this check only ever "
                "runs where someone chooses to run it", is_self=True)
    return True


# --------------------------------------------------------------------------
# entry point
# --------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--base-checks", required=True)
    parser.add_argument("--tree-checks", required=True)
    parser.add_argument("--base-workflow", required=True)
    parser.add_argument("--tree-workflow", required=True)
    parser.add_argument("--checks-rel", required=True)
    parser.add_argument("--workflow-rel", required=True)
    parser.add_argument("--self-id", required=True)
    parser.add_argument("--self-script", required=True)
    parser.add_argument("--runner", required=True)
    parser.add_argument("--base-label", required=True)
    parser.add_argument("--self-only", action="store_true")
    return parser


def main(argv: List[str]) -> int:
    args = build_parser().parse_args(argv)
    surface = Surface()
    try:
        base_checks = load_yaml(args.base_checks, "%s at the base" % args.checks_rel)
        tree_checks = load_yaml(args.tree_checks, "%s in the working tree" % args.checks_rel)
        base_wf = load_yaml(args.base_workflow, "%s at the base" % args.workflow_rel)
        tree_wf = load_yaml(args.tree_workflow, "%s in the working tree" % args.workflow_rel)
        if args.self_only:
            measured = compare_self(surface, args.self_id, args.self_script,
                                    base_checks, tree_checks, tree_wf, args.runner)
        else:
            compare_checks_file(surface, base_checks, tree_checks, args.checks_rel)
            compare_workflow(surface, base_wf, tree_wf, args.workflow_rel)
            measured = compare_self(surface, args.self_id, args.self_script,
                                    base_checks, tree_checks, tree_wf, args.runner)
    except Unmeasured as exc:
        sys.stderr.write("governance-weakening: %s\n" % exc)
        sys.stderr.write(
            "governance-weakening: the governance surface was NOT compared. "
            "Unmeasured, not clean.\n")
        return 2

    # Bare, unindented: the files this verdict rests on. The runner reads these
    # as coverage, and a run whose verdict rests on a file it did not name is
    # one nobody can check.
    if args.tree_checks != ABSENT:
        sys.stdout.write("%s\n" % args.checks_rel)
    if args.tree_workflow != ABSENT:
        sys.stdout.write("%s\n" % args.workflow_rel)

    print("    base: %s" % args.base_label)
    print("    mode: %s" % ("self-footing only" if args.self_only else "the whole surface"))
    print("    atoms compared: %d" % surface.atoms)
    print("    tightenings seen: %d (never a finding)" % len(surface.tightenings))
    for note in surface.notes:
        print("    NOTE: %s" % note)
    for tightening in surface.tightenings:
        print("      tightened: %s" % tightening)
    for finding in surface.findings:
        print("  " + finding.line().strip("\n"))

    if args.self_only and not measured:
        sys.stderr.write(
            "governance-weakening: --self-only was asked to assert this check's "
            "own footing and the check is declared at neither end, so there was "
            "nothing to assert. Unmeasured, not clean.\n")
        return 2
    if surface.atoms == 0 and not surface.notes:
        sys.stderr.write(
            "governance-weakening: no atom was compared at all, so a verdict of "
            "clean would rest on nothing. Neither governance file exists at the "
            "base or in the working tree: there is no surface here to have "
            "weakened. Unmeasured, not clean.\n")
        return 2
    if surface.findings:
        weak = sum(1 for f in surface.findings if f.kind == WEAKENED)
        und = len(surface.findings) - weak
        print("    %d weakening(s) and %d undecided move(s) of the governance "
              "surface. A weakening is not automatically wrong; this run says "
              "what moved and what it was, and leaves the judgement to a "
              "person." % (weak, und))
        return 1
    print("    Nothing on the governance surface moved down a ladder in this range.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
