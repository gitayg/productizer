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
        for index, step in enumerate(steps):
            if not isinstance(step, dict):
                continue
            name = step.get("name")
            key = "%s/%s" % (jname, name if isinstance(name, str) else "#%d" % index)
            out.append((key, step))
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


def step_body(step: Dict[str, Any]) -> str:
    """What a step DOES, with its name and its formatting taken out. Steps are
    keyed by name, and a name is documentation: measured on this repository, at
    3b7d2d4 a step was renamed from `... the 2026-09-05 baseline` to
    `... 2026-09-06`, and a reader keyed on the name alone called that a deleted
    step. The body is what decides whether anything stopped happening."""
    parts = []
    for key in ("uses", "with", "env", "run", "shell"):
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


def permission_map(doc: Dict[str, Any]) -> Dict[str, Any]:
    node = doc.get("permissions")
    if isinstance(node, str):
        return {"__all__": node}
    if isinstance(node, dict):
        return dict(node)
    return {}


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

    pb, pt = permission_map(base), permission_map(tree)
    for scope in sorted(set(pb) | set(pt)):
        surface.atoms += 1
        rb = PERMISSION_RANK.get(str(pb.get(scope, "none")).lower())
        rt = PERMISSION_RANK.get(str(pt.get(scope, "none")).lower())
        if rb is None or rt is None:
            if pb.get(scope) != pt.get(scope):
                surface.undecided("workflow.permissions.%s" % scope,
                                  pb.get(scope, "none"), pt.get(scope, "none"),
                                  "this rule does not order one of these "
                                  "permission values")
        elif rt > rb:
            surface.weakened(
                "workflow.permissions.%s" % scope, pb.get(scope, "none"),
                pt.get(scope, "none"),
                "the token this job holds can do more than it could, so a "
                "compromised step has more to steal")
        elif rt < rb:
            surface.tightened("workflow.permissions.%s" % scope,
                              pb.get(scope, "none"), pt.get(scope, "none"))

    # A STEP GONE BY NAME IS NOT YET A STEP GONE. Two corrections, both forced
    # by this repository's own history rather than imagined:
    #   - an identical body under a new name is a RENAME. Neither a weakening
    #     nor a tightening; it is reported so the reader can disagree.
    #   - a body that changed too, while every tool the step invoked still runs
    #     somewhere in the file, is UNDECIDED. Something was reorganised and
    #     nothing measurably stopped. A real deletion takes its invocations with
    #     it, and those are reported by the invocation atom below.
    gained_bodies = {step_body(tree_steps[k]): k for k in set(tree_steps) - set(base_steps)}
    renamed_from = set()
    tree_invocations = set(invocations(list(tree_steps.items())))
    for key in sorted(base_steps):
        surface.atoms += 1
        if key not in tree_steps:
            body = step_body(base_steps[key])
            if body in gained_bodies:
                renamed_from.add(gained_bodies[body])
                surface.notes.append(
                    "workflow.step[%s] was renamed to [%s] with an identical "
                    "body. A name is documentation; nothing it runs changed."
                    % (key, gained_bodies[body]))
                continue
            lost_work = [line for line in invocations([(key, base_steps[key])])
                         if line not in tree_invocations]
            if gained_bodies and not lost_work:
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
