#!/usr/bin/env python3
"""The measurement behind check-selftest-coverage.sh. See that file's header
for what is asserted, what is not, and why.

Reads two files that decide what the check suite executes - the declared checks
and the CI workflow - and answers two questions over the tools they name:

    R39  does the tool carry a self-test?
    R40  does anything actually run it, with its failure still able to set the
         run's exit code?

Renders four states apart and never collapses them into a zero: a count is a
count, `n/a` is a guard that does not apply, `-` is never run, `?` is
unreadable.

stdout: bare relative paths, unindented, for every file the verdict rests on;
everything else indented. Exit 0 all held, 1 a finding, 2 could not measure.
"""

import argparse
import os
import re
import subprocess
import sys
from typing import NoReturn

NA = "n/a"
NEVER_RUN = "-"
UNREADABLE = "?"

# A line that DISPATCHES on a self-test flag. A line that merely names one does
# not count: check-nothing-merged.sh describes `--selftest` in its header and
# its parser rejects it, and a grep for the string reports it as covered.
DISPATCH = (
    # shell `case` pattern, bare or quoted: --selftest) / "--self-test")
    re.compile(r"""["']?--self[-_]?test["']?\s*\)"""),
    # argparse
    re.compile(r"""add_argument\(\s*["']--self[-_]?test["']"""),
    # a comparison: [ "$1" = --selftest ] / if arg == "--self-test"
    re.compile(r"""[=!]=?\s*["']?--self[-_]?test\b"""),
)
FLAG_RE = re.compile(r"--self[-_]?test\b")
REJECTED_RE = re.compile(r"unknown (option|argument|flag)", re.I)
PLACEHOLDER_RE = re.compile(r"[{}]")


def out(line=""):
    sys.stdout.write(line + "\n")


def refuse(msg) -> "NoReturn":
    sys.stderr.write("check-selftest-coverage: %s\n" % msg)
    raise SystemExit(2)


def rel(root, path):
    path = os.path.normpath(path)
    if os.path.isabs(path):
        try:
            path = os.path.relpath(path, root)
        except ValueError:
            return path
    return path.replace(os.sep, "/")


def resolve_tool(root, argv):
    """The program an argv actually runs.

    Left to right, the first token that is a real file under the root. That
    skips interpreters (`python3 foo.py`) and option values that happen to name
    a file (`--config config.json` never wins, because the script it configures
    came first). A token carrying a `{files}` placeholder is not a path.
    """
    for tok in argv:
        if not isinstance(tok, str) or not tok:
            continue
        if PLACEHOLDER_RE.search(tok):
            continue
        cand = os.path.normpath(os.path.join(root, tok))
        if os.path.isfile(cand):
            return rel(root, cand), True
    first = argv[0] if argv and isinstance(argv[0], str) else None
    return first, False


def scan_dispatch(path):
    """(flags, unreadable). Flags this file DISPATCHES on, comments excluded."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return set(), True
    flags = set()
    for line in text.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue
        if not any(pat.search(line) for pat in DISPATCH):
            continue
        for m in FLAG_RE.finditer(line):
            flags.add(m.group(0))
    return flags, False


def probe(root, relpath, flag, timeout):
    """Run the self-test. (state, detail).

    state: "answered" | "rejected" | UNREADABLE
    """
    full = os.path.join(root, relpath)
    if relpath.endswith(".py"):
        argv = [sys.executable, full, flag]
    else:
        argv = ["bash", full, flag]
    try:
        proc = subprocess.run(argv, cwd=root, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return UNREADABLE, "timed out after %ds" % timeout
    except OSError as exc:
        return UNREADABLE, "could not be executed (%s)" % exc.__class__.__name__
    err = proc.stderr.decode("utf-8", "replace")
    if proc.returncode == 2 and REJECTED_RE.search(err):
        return "rejected", "exit 2, argument rejected"
    return "answered", "exit %d" % proc.returncode


def load_yaml(path, what):
    try:
        import yaml
    except ImportError:
        refuse("PyYAML is not installed, so %s was never parsed. Unmeasured, "
               "not a pass" % what)
    try:
        with open(path, encoding="utf-8") as fh:
            return yaml.safe_load(fh)
    except OSError:
        refuse("%s could not be read at %s. Unmeasured, not a pass" % (what, path))
    except Exception as exc:                       # yaml.YAMLError and friends
        refuse("%s at %s is not parseable YAML (%s). A file nobody parsed is "
               "not a file with nothing in it" % (what, path, exc.__class__.__name__))


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--root", required=True)
    ap.add_argument("--checks", required=True)
    ap.add_argument("--workflow", required=True)
    ap.add_argument("--no-probe", dest="probe", action="store_false")
    ap.add_argument("--probe-timeout", type=int, default=30)
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    checks_rel = rel(root, args.checks)
    workflow_rel = rel(root, args.workflow)
    checks_path = os.path.join(root, checks_rel)
    workflow_path = os.path.join(root, workflow_rel)

    cfg = load_yaml(checks_path, "the declared checks")
    if not isinstance(cfg, dict):
        refuse("%s does not parse to a mapping, so it declares no checks that "
               "could be read. Unmeasured, not a pass" % checks_rel)
    declared = cfg.get("checks")
    if not isinstance(declared, list) or not declared:
        refuse("%s declares no checks. There is no tool set to measure R39 and "
               "R40 over, which is unmeasured and not a clean run over an empty "
               "set" % checks_rel)

    wf = load_yaml(workflow_path, "the CI workflow")
    if not isinstance(wf, dict):
        refuse("%s does not parse to a mapping, so nothing could be read about "
               "what CI runs. Unmeasured, not a pass" % workflow_rel)

    # --- what CI runs -----------------------------------------------------
    # Every line of every `run:` block, kept whole: reachability needs the tool
    # and the flag on the SAME line, and swallowing needs the same line again.
    wf_lines = []
    jobs = wf.get("jobs")
    if isinstance(jobs, dict):
        for job in jobs.values():
            if not isinstance(job, dict):
                continue
            steps = job.get("steps")
            if not isinstance(steps, list):
                continue
            for step in steps:
                if not isinstance(step, dict):
                    continue
                run = step.get("run")
                if isinstance(run, str):
                    wf_lines.extend(run.split("\n"))
    try:
        with open(workflow_path, encoding="utf-8") as fh:
            wf_text = fh.read()
    except OSError:
        refuse("%s could not be re-read for its continue-on-error setting. "
               "Unmeasured, not a pass" % workflow_rel)
    # Parsed, never grepped. A raw substring here reads a COMMENT saying a step
    # sets no continue-on-error as proof that one does - measured 2026-09-06,
    # when exactly that comment turned all 32 tools into R40 findings. This is
    # the same mention-versus-dispatch distinction this tool already makes for
    # self-test flags; it simply was not applied here.
    try:
        import yaml as _yaml
        _wf = _yaml.safe_load(wf_text) or {}
        _steps = []
        for _job in (_wf.get("jobs") or {}).values():
            _steps.extend(_job.get("steps") or [])
        wf_continue_on_error = any(
            bool(_s.get("continue-on-error")) for _s in _steps
            if isinstance(_s, dict))
    except Exception:
        refuse("%s could not be parsed to read continue-on-error. Unmeasured, "
               "not a pass" % workflow_rel)

    # --- the tool set -----------------------------------------------------
    # rel path (or external name) -> record
    tools = {}

    def note(name, local, source, argv=None, check=None, line=None):
        rec = tools.setdefault(name, {
            "local": local, "sources": [], "checks": [], "wf_lines": [],
            "disabled": True,
        })
        if source not in rec["sources"]:
            rec["sources"].append(source)
        if check is not None:
            rec["checks"].append(check)
        if line is not None:
            rec["wf_lines"].append(line)
        if argv is not None:
            rec.setdefault("argvs", []).append(argv)
        return rec

    for chk in declared:
        if not isinstance(chk, dict):
            continue
        cid = chk.get("id")
        cid = cid if isinstance(cid, str) else "<unnamed>"
        cmd = chk.get("command")
        if not isinstance(cmd, list) or not cmd:
            continue
        argv = [t for t in cmd if isinstance(t, str)]
        if not argv:
            continue
        name, local = resolve_tool(root, argv)
        if name is None:
            continue
        rec = note(name, local, "checks.yaml", argv=argv,
                   check={"id": cid, "argv": argv,
                          "exit_codes": chk.get("exit_codes")})
        # `enabled: false` is a shut guard, not a tool with no self-test.
        if chk.get("enabled") is not False:
            rec["disabled"] = False

    for line in wf_lines:
        for tok in line.replace("\t", " ").split():
            tok = tok.strip("'\"`;()")
            if not (tok.endswith(".sh") or tok.endswith(".py")):
                continue
            cand = os.path.normpath(os.path.join(root, tok))
            if not os.path.isfile(cand):
                continue
            rec = note(rel(root, cand), True, args.workflow.replace(os.sep, "/"),
                       line=line)
            rec["disabled"] = False

    # --- measure ----------------------------------------------------------
    unreadable = []
    for name, rec in tools.items():
        if not rec["local"]:
            rec["flags"] = None                     # external: n/a, not zero
            rec["answered"] = NA
            continue
        flags, bad = scan_dispatch(os.path.join(root, name))
        if bad:
            rec["flags"] = None
            rec["answered"] = UNREADABLE
            rec["unreadable"] = True
            unreadable.append(name)
            continue
        rec["flags"] = sorted(flags)
        rec["answered"] = NA if not flags else NEVER_RUN

    probed = 0
    if args.probe:
        for name, rec in tools.items():
            if not rec.get("flags"):
                continue
            probed += 1
            flag = rec["flags"][0]
            state, detail = probe(root, name, flag, args.probe_timeout)
            if state == "rejected":
                # The source reads as if it dispatches and the parser says
                # otherwise. The parser is what runs, so it wins.
                rec["disagreed"] = detail
                rec["flags"] = []
                rec["answered"] = NA
            elif state == UNREADABLE:
                rec["answered"] = UNREADABLE
                rec["probe_note"] = detail
                unreadable.append(name)
            else:
                rec["answered"] = detail

    # --- reachability -----------------------------------------------------
    for name, rec in tools.items():
        if not rec.get("flags"):
            rec["reached"] = NA
            rec["swallowed"] = None
            continue
        reached = []
        swallowed = []
        for chk in rec["checks"]:
            if not any(FLAG_RE.match(t) for t in chk["argv"]):
                continue
            reached.append(chk["id"])
            ec = chk["exit_codes"]
            passing = ec.get("pass") if isinstance(ec, dict) else None
            if isinstance(passing, list) and any(
                    isinstance(c, int) and c != 0 for c in passing):
                swallowed.append("%s declares a non-zero exit code as a pass"
                                 % chk["id"])
        for line in rec["wf_lines"]:
            if not FLAG_RE.search(line):
                continue
            reached.append(workflow_rel)
            if "||" in line:
                swallowed.append("the workflow line guards the call with `||`")
            if wf_continue_on_error:
                swallowed.append("the workflow sets continue-on-error")
        rec["reached"] = reached
        rec["swallowed"] = swallowed

    # --- report -----------------------------------------------------------
    for p in (checks_rel, workflow_rel):
        out(p)
    local_names = sorted(n for n, r in tools.items() if r["local"])
    for name in local_names:
        out(name)

    external = sorted(n for n, r in tools.items() if not r["local"])

    out("  tool set: %d invoked by %s or %s - %d in this repository, %d "
        "third-party" % (len(tools), checks_rel, workflow_rel,
                         len(local_names), len(external)))
    out("  %-58s %-12s %-10s %s" % ("tool", "self-test", "answered", "run by"))
    for name in local_names + external:
        rec = tools[name]
        if rec.get("disagreed"):
            flag = "none"
        elif rec["flags"] is None:
            flag = NA if not rec["local"] else UNREADABLE
        elif rec["flags"]:
            flag = ",".join(rec["flags"])
        else:
            flag = "none"
        reached = rec.get("reached", NA)
        if isinstance(reached, list):
            reached = ", ".join(sorted(set(reached))) if reached else "nothing"
        out("  %-58s %-12s %-10s %s"
            % (name[:58], flag, rec["answered"], reached))

    findings = []
    for name in local_names:
        rec = tools[name]
        if rec.get("unreadable"):
            continue
        if rec["disabled"]:
            continue
        if not rec.get("flags"):
            extra = ""
            if rec.get("disagreed"):
                extra = (" - its source reads as if it dispatches on one and "
                         "its parser rejected the flag (%s)" % rec["disagreed"])
            findings.append("R39: %s carries no self-test%s" % (name, extra))
    for name in local_names:
        rec = tools[name]
        if not rec.get("flags"):
            continue
        if not rec.get("reached"):
            findings.append("R40: %s carries %s and no declared check or "
                            "workflow step invokes it" % (name, rec["flags"][0]))
        for why in rec.get("swallowed") or []:
            findings.append("R40: %s's self-test runs but %s, so its failure "
                            "cannot set the run's exit code" % (name, why))

    carried = sum(1 for n in local_names if tools[n].get("flags"))
    run_by = sum(1 for n in local_names if tools[n].get("reached")
                 and isinstance(tools[n]["reached"], list))
    out("  R39: %d of %d repository check tools carry a self-test that answers."
        % (carried, len(local_names)))
    out("  R40: %d of %d self-tests found are invoked by a declared check or by "
        "the workflow." % (run_by, carried))
    out("  third-party tools, which nobody here can add a self-test to: %s"
        % (", ".join(external) if external else "none"))
    if args.probe:
        out("  probe: %d self-test(s) executed with the flag their source "
            "dispatches on." % probed)
    else:
        out("  probe: not run (--no-probe). The answered column reads %s - never "
            "run - and is never read as a 0." % NEVER_RUN)
    out("  NOT ASSERTED: R39's `reaches each exit code it can return`. No "
        "self-test here reports which exit codes it drove, so this run "
        "measures that a self-test exists and answers, never that it is "
        "complete.")

    if unreadable:
        for name in sorted(set(unreadable)):
            note_txt = tools[name].get("probe_note", "could not be read")
            out("  %s: %s - reported ? and never as a tool without a self-test."
                % (name, note_txt))
        refuse("%d tool(s) could not be classified. A tool nobody could read is "
               "not a tool with no self-test, so this run is unmeasured rather "
               "than a shortfall it could not see" % len(set(unreadable)))

    if findings:
        for f in findings:
            out("  FINDING: %s" % f)
        sys.stderr.write(
            "FAIL: %d finding(s). R39 says every check tool shall carry a "
            "self-test; R40 says the suite shall run it.\n" % len(findings))
        return 1

    out("  R39 and R40 hold over the tool set above.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
