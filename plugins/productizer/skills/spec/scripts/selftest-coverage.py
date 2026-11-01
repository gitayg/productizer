#!/usr/bin/env python3
"""The measurement behind check-selftest-coverage.sh. See that file's header
for what is asserted, what is not, and why.

Reads two files that decide what the check suite executes - the declared checks
and the CI workflow - and answers two questions over the tools they name:

    R39   does the tool carry a self-test?
    R39.b does that self-test DECLARE which exit codes it drove and which its
          contract documents - and if it declares, did it drive them all?
    R40   does anything actually run it, with its failure still able to set the
          run's exit code?

R39.b is COUNTED, never enforced. A self-test that emits no declaration has not
been shown incomplete; it has not been asked. That reads `not asked`, never 0.

Renders five states apart and never collapses them into a zero: a count is a
count, `n/a` is a guard that does not apply, `-` is never run, `?` is
unreadable, `absent` is an argv naming a file that is not in the work tree.

The tool set is built over what the suite EXERCISES. A check with
`enabled: false` never runs, so its tool is neither counted with the rest nor
dropped: it is a third figure on its own line. A repo-local path that is not on
disk is an absent tool, never a third party.


B186: given --records, a self-test the CI workflow already ran is read from
the record `--record` wrote as it ran, instead of being run a second time - but
only when the record is about this commit, this unchanged tracked tree and this
tool file. Without a usable record the self-test is probed, as before.

B187: a probe that times out while other probes run beside it is probed once
more, alone, with the full limit, before it counts as a timeout; the report
says whether a timeout happened alone or under contention, and how long it ran.

stdout: bare relative paths, unindented, for every file the verdict rests on;
everything else indented. Exit 0 all held, 1 a finding, 2 could not measure.
"""

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
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
    # a comparison against a list or tuple literal holding the flag:
    # argv == ["--selftest"] / sys.argv[1:] == ["--self-test"] /
    # args == ("--selftest",). Missed until B88: replay-ci.py dispatched that
    # way, passed 16 of 16, and read `carries no self-test`. `==` or `!=` only,
    # because a bare `=` before a list is an assignment and a list with no
    # operator before it is an argv being BUILT - subprocess.run([..,
    # "--selftest"]) - which is a mention. No bracket may open or close between
    # the literal's start and the flag, so the match cannot run on out of one
    # compared literal into a call that merely passes the flag.
    re.compile(r"""[=!]=\s*[\[(][^\[\]()]*["']--self[-_]?test["']"""),
    # membership in a literal collection holding the flag, one level of nesting
    # allowed: args in (["--selftest"], ["--self-test"]) / arg in ("--selftest",
    # "--self-test") / not in {...}. Missed until B109: check-ci-template.py
    # dispatched `args in (["--selftest"], ["--self-test"])`, passed 18 of 18,
    # and read `carries no self-test`. A line holding `for ... in` is excluded
    # whole, because iterating over a list of flags builds argv - a mention.
    re.compile(r"""^(?!.*\bfor\b.*\bin\b).*\bin\s*[\[({](?:[^\[\](){}]|[\[(][^\[\](){}]*[\])])*?"""
               r"""[\[(]?\s*["']--self[-_]?test["']"""),
)
FLAG_RE = re.compile(r"--self[-_]?test\b")
REJECTED_RE = re.compile(r"unknown (option|argument|flag)", re.I)
PLACEHOLDER_RE = re.compile(r"[{}]")

# THREE KINDS OF TOOL, AND WHY THE THIRD ONE HAD TO EXIST. An argv token that
# names no file on disk used to fall into one bucket with `shellcheck`, `npm`
# and `gitleaks`, and that bucket is printed under the sentence "third-party
# tools, which nobody here can add a self-test to". `./scripts/check-pii-logging.sh`
# is named in this repository's own checks.yaml and exists nowhere in the tree,
# so the sentence is false about it - and the false reading is the reassuring
# one. A repo-local path that is not there is an ABSENT tool: a measured fact
# about this work tree, not a boundary of ownership. It gets its own kind, its
# own line, and - when an ENABLED check names it - its own finding.
#
# The test is on SHAPE, because an argv carries nothing else. A token beginning
# `./` or `../`, or ending `.sh` or `.py`, is this repository naming a file of
# its own; a bare `semgrep` is a program name that resolves through PATH and is
# nobody's file here. A misread in this direction over-reports absence, which is
# the safe side: it names a path and asks for it, rather than telling the reader
# nobody could have written a self-test for it.
KIND_REPO = "repo"
KIND_ABSENT = "absent"
KIND_EXTERNAL = "external"
REPO_SHAPED = re.compile(r"^\.{1,2}/|\.(sh|py)$")

# --- the R39.b declaration protocol ----------------------------------------
# One line, any indent, on stdout or stderr:
#
#     exit codes reached: <codes>   documented: <codes>
#
# Both halves are non-empty lists of non-negative integers separated by spaces
# or commas, and nothing else may share the line. The shape is lifted from
# retrieval-budget.sh, which invented it for itself because it had to.
#
# The `documented:` half is what makes the line a measurement rather than a
# claim. Twenty self-tests here already print a hardcoded `exit codes reached:
# 0, 1 and 2 - the whole contract.`, which asserts nothing: the list is a
# literal in the source, not a record of what the cases drove, and there is no
# second list to check it against. Those lines do NOT parse, on purpose, and
# are reported `unparsed` - unmeasured, never compliant and never zero.
CODES_LINE_HINT = "exit codes reached"
CODES_LINE = re.compile(
    r"^\s*exit codes reached:(?P<reached>.*?)\bdocumented:(?P<documented>.*)$")
CODE_LIST = re.compile(r"^[0-9]+(?:[,\s]+[0-9]+)*$")
SPLIT_CODES = re.compile(r"[,\s]+")

CODES_COMPLETE = "complete"
CODES_INCOMPLETE = "INCOMPLETE"
CODES_SILENT = "not asked"
CODES_UNPARSED = "unparsed"


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
    """The program an argv actually runs, and which of the three kinds it is.

    Left to right, the first token that is a real file under the root. That
    skips interpreters (`python3 foo.py`) and option values that happen to name
    a file (`--config config.json` never wins, because the script it configures
    came first). A token carrying a `{files}` placeholder is not a path.

    Nothing resolved: the argv's head is classified by SHAPE. A repo-local path
    that is not on disk is KIND_ABSENT and is never reported as a third party.
    """
    for tok in argv:
        if not isinstance(tok, str) or not tok:
            continue
        if PLACEHOLDER_RE.search(tok):
            continue
        cand = os.path.normpath(os.path.join(root, tok))
        if os.path.isfile(cand):
            return rel(root, cand), KIND_REPO
    first = argv[0] if argv and isinstance(argv[0], str) else None
    if first is None:
        return None, KIND_EXTERNAL
    if REPO_SHAPED.search(first):
        return first, KIND_ABSENT
    return first, KIND_EXTERNAL


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


def parse_code_list(text):
    """A half of the declaration line, as a sorted set of ints. None if it is
    not a bare list of non-negative integers - prose is not a declaration."""
    text = text.strip()
    if not text or not CODE_LIST.match(text):
        return None
    return sorted({int(tok) for tok in SPLIT_CODES.split(text) if tok})


def declared_codes(text):
    """Read the R39.b declaration out of a self-test's own output.

    Returns (state, reached, documented, detail). Nothing here can produce a
    finding: an absent or unreadable declaration is unmeasured, and the count
    of unmeasured tools is the point of the exercise.
    """
    parsed = []
    unparsed = 0
    for line in text.split("\n"):
        if CODES_LINE_HINT not in line:
            continue
        m = CODES_LINE.match(line)
        pair = None
        if m:
            reached = parse_code_list(m.group("reached"))
            documented = parse_code_list(m.group("documented"))
            if reached and documented:
                pair = (reached, documented)
        if pair is None:
            unparsed += 1
        else:
            parsed.append(pair)
    if len(parsed) > 1:
        return (CODES_UNPARSED, None, None,
                "declares its exit-code coverage on more than one line, and "
                "which of them governs is undefined")
    if not parsed:
        if unparsed:
            return (CODES_UNPARSED, None, None,
                    "names exit codes reached in a shape this protocol does "
                    "not define - no `documented:` half to check them against")
        return (CODES_SILENT, None, None,
                "emits no exit-code declaration, so what it drove is unknown")
    reached, documented = parsed[0]
    missing = [c for c in documented if c not in reached]
    extra = [c for c in reached if c not in documented]
    detail = "drove %s of the %s it documents" % (
        " ".join(str(c) for c in sorted(set(documented)) if c in reached) or "none",
        " ".join(str(c) for c in documented))
    if missing:
        detail = "documents %s and never reached %s" % (
            " ".join(str(c) for c in documented),
            " ".join(str(c) for c in missing))
    if extra:
        detail += ("; it also drove %s, which its contract does not document"
                   % " ".join(str(c) for c in extra))
    state = CODES_INCOMPLETE if missing else CODES_COMPLETE
    return state, reached, documented, detail


def probe(root, relpath, flag, timeout):
    """Run the self-test. A dict: state, detail, output, elapsed, timed_out.

    state: "answered" | "rejected" | UNREADABLE
    output: stdout and stderr together, and empty for anything but "answered".
    Both streams are read because the probe captures both, so a declaration is
    a declaration wherever the self-test writes it.

    B187: the self-test runs in a session of its own, and a timeout kills that
    whole process group. Killing only the shell left its children running, so a
    self-test probed again "alone" after a timeout would still have the first
    attempt's processes beside it.
    """
    full = os.path.join(root, relpath)
    if relpath.endswith(".py"):
        argv = [sys.executable, full, flag]
    else:
        argv = ["bash", full, flag]
    started = time.monotonic()
    try:
        proc = subprocess.Popen(argv, cwd=root, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, start_new_session=True)
    except OSError as exc:
        return {"state": UNREADABLE, "timed_out": False, "output": "",
                "elapsed": time.monotonic() - started,
                "detail": "could not be executed (%s)" % exc.__class__.__name__}
    try:
        out_b, err_b = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            proc.kill()
        proc.wait()
        for pipe in (proc.stdout, proc.stderr):
            pipe.close()
        return {"state": UNREADABLE, "timed_out": True, "output": "",
                "elapsed": time.monotonic() - started,
                "detail": "timed out after %ds" % timeout}
    elapsed = time.monotonic() - started
    return answer(proc.returncode, out_b, err_b, elapsed)


def answer(returncode, out_b, err_b, elapsed):
    """What one run of a self-test says, whether it ran here or was recorded."""
    err = err_b.decode("utf-8", "replace")
    if returncode == 2 and REJECTED_RE.search(err):
        return {"state": "rejected", "timed_out": False, "output": "",
                "elapsed": elapsed, "detail": "exit 2, argument rejected"}
    out_text = out_b.decode("utf-8", "replace")
    return {"state": "answered", "timed_out": False, "elapsed": elapsed,
            "detail": "exit %d" % returncode, "output": out_text + "\n" + err}


def run_probes(root, wanted, timeout, jobs):
    """B160 and B187. Up to `jobs` probes at once, each under its own limit.

    A probe that TIMED OUT while another ran beside it is probed once more,
    alone, with the full limit, after every other probe has finished. Tag run
    41258217956 refused on `check-view-readonly.sh: timed out after 180s` with
    three other self-tests competing for four cores; the same self-test took
    69s alone on a machine at load 28 to 45, and the same commit passed on
    main. A timeout under contention measures the neighbours as much as the
    self-test, so it is not counted until the self-test has had the machine to
    itself. A timeout that happened ALONE is never retried: that one measured
    the self-test.

    Returns {name: result} where a result also carries `contended` (how many
    other probes overlapped it in time) and, when it was probed again,
    `first` (the contended attempt).
    """
    def one(item):
        name, flag = item
        started = time.monotonic()
        res = probe(root, name, flag, timeout)
        res["span"] = (started, time.monotonic())
        return name, res

    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        results = dict(pool.map(one, wanted))
    spans = {name: res["span"] for name, res in results.items()}
    for name, res in results.items():
        lo, hi = spans[name]
        res["contended"] = sum(1 for other, (olo, ohi) in spans.items()
                               if other != name and olo < hi and ohi > lo)
    # Alone: the pool has drained, and these run one at a time.
    for name, flag in wanted:
        res = results[name]
        if not (res["timed_out"] and res["contended"]):
            continue
        again = probe(root, name, flag, timeout)
        again["contended"] = 0
        again["first"] = res
        results[name] = again
    return results


def timeout_detail(res, timeout):
    """The sentence a final timeout is reported with: alone or under contention,
    and how long it actually ran."""
    if "first" in res:
        first = res["first"]
        return ("timed out after %ds under contention, beside %d other probe(s) "
                "(%.1fs elapsed); probed again alone, it timed out again after "
                "%ds (%.1fs elapsed)" % (timeout, first["contended"],
                                          first["elapsed"], timeout, res["elapsed"]))
    return "timed out after %ds, probed alone (%.1fs elapsed)" % (timeout, res["elapsed"])


# --- records: a self-test run once, read here instead of run again (B186) ---
#
# CI used to run every self-test twice: once in the workflow, where its exit
# code gates the run, and again here, as this check's probe. Measured on main
# run 41231708700: the self-test step took 424s and the declared checks 693s,
# with this probe inside the second. A RECORD is one workflow run of one
# self-test, written by `--record` as it ran: its stdout, its stderr, its exit
# code and how long it took, bound to the commit and to the tool file it ran.
#
# A record is read in place of a probe only when it is about THIS tree: HEAD is
# the commit it names, no tracked file differs from HEAD, the tool file is the
# blob it names, and the flag it ran is one the source dispatches on. Anything
# else and the self-test is probed here, as before - a record never turns a
# probe into a pass it could not have earned, it only saves running it twice.
# Locally no records are given, so every self-test is probed exactly as it was.
RECORD_META = "meta.json"


def git_out(root, args):
    proc = subprocess.run(["git", *args], cwd=root, capture_output=True)
    if proc.returncode != 0:
        return None
    return proc.stdout.decode("utf-8", "replace").strip()


def blob_id(path):
    """sha256 of the file's bytes, computed here so writer and reader agree
    whatever git's filters are. Not git's own blob id: that is sha1, which the
    declared sast check refuses, and nothing here needs git to agree."""
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def record_key(relpath):
    return relpath.replace("/", "__")


def record_main(argv):
    """`--record DIR -- CMD...`: run one self-test, pass its output and exit
    code through unchanged, and keep a record of it in DIR."""
    if len(argv) < 3 or argv[1] != "--":
        refuse("--record needs a directory, then --, then the self-test command")
    rec_dir, cmd = argv[0], argv[2:]
    root = git_out(os.getcwd(), ["rev-parse", "--show-toplevel"])
    head = git_out(os.getcwd(), ["rev-parse", "--verify", "HEAD^{commit}"])
    if not root or not head:
        refuse("--record must run inside a git work tree with a commit, so the "
               "record can name the commit it is about")
    root = os.path.realpath(root)
    tool = None
    for tok in cmd:
        cand = os.path.realpath(os.path.join(os.getcwd(), tok)) if tok else ""
        if tok and not PLACEHOLDER_RE.search(tok) and os.path.isfile(cand) \
                and cand.startswith(root + os.sep):
            tool = rel(root, cand)
            break
    flags = [t for t in cmd if FLAG_RE.fullmatch(t)]
    if tool is None or not flags:
        refuse("--record runs a self-test: the command must name a file in this "
               "work tree and a self-test flag; got: %s" % " ".join(cmd))
    started = time.monotonic()
    try:
        proc = subprocess.run(cmd, capture_output=True)
    except OSError as exc:
        refuse("--record could not execute %s (%s)" % (cmd[0], exc.__class__.__name__))
    elapsed = time.monotonic() - started
    sys.stdout.buffer.write(proc.stdout)
    sys.stdout.flush()
    sys.stderr.buffer.write(proc.stderr)
    sys.stderr.flush()
    dest = os.path.join(rec_dir, record_key(tool))
    try:
        os.makedirs(dest, exist_ok=True)
        with open(os.path.join(dest, "stdout"), "wb") as fh:
            fh.write(proc.stdout)
        with open(os.path.join(dest, "stderr"), "wb") as fh:
            fh.write(proc.stderr)
        with open(os.path.join(dest, RECORD_META), "w", encoding="utf-8") as fh:
            json.dump({"tool": tool, "flag": flags[0], "exit": proc.returncode,
                       "seconds": round(elapsed, 1), "head": head,
                       "blob": blob_id(os.path.join(root, tool))}, fh)
    except OSError as exc:
        refuse("--record could not write the record for %s (%s); the self-test "
               "itself exited %d" % (tool, exc.__class__.__name__, proc.returncode))
    return proc.returncode


def load_records(root, rec_dir, wanted):
    """({name: result}, [why a record was not used], header line)."""
    if not os.path.isdir(rec_dir):
        return {}, [], ("records: %s is not a directory, so every self-test was "
                        "executed here" % rec_dir)
    head = git_out(root, ["rev-parse", "--verify", "HEAD^{commit}"])
    dirty = git_out(root, ["status", "--porcelain", "--untracked-files=no"])
    whole = None
    if head is None or dirty is None:
        whole = "this work tree has no readable git HEAD to bind a record to"
    elif dirty:
        whole = ("%d tracked file(s) differ from HEAD, so no record can be about "
                 "this tree" % len(dirty.splitlines()))
    used, not_used = {}, []
    for name, flags in wanted:
        path = os.path.join(rec_dir, record_key(name))
        if not os.path.isdir(path):
            continue
        try:
            with open(os.path.join(path, RECORD_META), encoding="utf-8") as fh:
                meta = json.load(fh)
            with open(os.path.join(path, "stdout"), "rb") as fh:
                out_b = fh.read()
            with open(os.path.join(path, "stderr"), "rb") as fh:
                err_b = fh.read()
            code, seconds = int(meta["exit"]), float(meta["seconds"])
        except (OSError, ValueError, KeyError, TypeError):
            not_used.append("%s: its record could not be read" % name)
            continue
        if whole:
            not_used.append("%s: %s" % (name, whole))
        elif meta.get("tool") != name:
            not_used.append("%s: its record names %s" % (name, meta.get("tool")))
        elif meta.get("head") != head:
            not_used.append("%s: recorded at commit %s, and HEAD is %s"
                            % (name, str(meta.get("head"))[:12], head[:12]))
        elif meta.get("blob") != blob_id(os.path.join(root, name)):
            not_used.append("%s: the file is not the one the record ran" % name)
        elif meta.get("flag") not in flags:
            not_used.append("%s: recorded with %s, which its source does not "
                            "dispatch on" % (name, meta.get("flag")))
        else:
            res = answer(code, out_b, err_b, seconds)
            res["recorded"] = True
            res["contended"] = 0
            used[name] = res
    header = ("records: %s - %d self-test(s) read from records their own run "
              "wrote at HEAD %s, %d record(s) not used"
              % (rec_dir, len(used), (head or "?")[:12], len(not_used)))
    return used, not_used, header


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
    if sys.argv[1:2] == ["--record"]:
        return record_main(sys.argv[2:])
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--root", required=True)
    ap.add_argument("--checks", required=True)
    ap.add_argument("--workflow", required=True)
    ap.add_argument("--no-probe", dest="probe", action="store_false")
    ap.add_argument("--probe-timeout", type=int, default=30)
    ap.add_argument("--probe-jobs", type=int, default=1)
    ap.add_argument("--records", default=None)
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

    def note(name, kind, source, argv=None, check=None, line=None):
        rec = tools.setdefault(name, {
            "kind": kind, "sources": [], "checks": [], "wf_lines": [],
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
        name, kind = resolve_tool(root, argv)
        if name is None:
            continue
        rec = note(name, kind, "checks.yaml", argv=argv,
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
            rec = note(rel(root, cand), KIND_REPO,
                       args.workflow.replace(os.sep, "/"), line=line)
            rec["disabled"] = False

    # --- measure ----------------------------------------------------------
    unreadable = []
    for name, rec in tools.items():
        if rec["kind"] == KIND_EXTERNAL:
            rec["flags"] = None                     # external: n/a, not zero
            rec["answered"] = NA
            rec["codes"] = {"state": NA, "detail": "third-party"}
            continue
        if rec["kind"] == KIND_ABSENT:
            # Absence is MEASURED - the path was resolved and there is no file
            # there - so this is not `?`. It is also not a tool anybody could
            # have written a self-test for, so the self-test column reads
            # `absent` rather than `none`: `none` would be a count of zero
            # self-tests in a file, and there is no file.
            rec["flags"] = None
            rec["answered"] = NA
            rec["codes"] = {"state": NA,
                            "detail": "no such file in this work tree"}
            continue
        flags, bad = scan_dispatch(os.path.join(root, name))
        if bad:
            rec["flags"] = None
            rec["answered"] = UNREADABLE
            rec["codes"] = {"state": UNREADABLE, "detail": "could not be read"}
            rec["unreadable"] = True
            unreadable.append(name)
            continue
        rec["flags"] = sorted(flags)
        rec["answered"] = NA if not flags else NEVER_RUN
        # No self-test is no declaration to look for - a guard, not a shortfall.
        rec["codes"] = (
            {"state": NA, "detail": "no self-test to declare anything"}
            if not flags else
            {"state": NEVER_RUN, "detail": "the self-test was never run"})

    probed = 0
    records_header = None
    records_unused = []
    from_records = 0
    reprobed = []                                   # (name, first, final)
    slowest = None
    if args.probe:
        # The results are applied in the tools' own order, so the report does
        # not depend on which probe finished first.
        wanted = [(name, rec) for name, rec in tools.items() if rec.get("flags")]
        answers = {}
        if args.records is not None:
            answers, records_unused, records_header = load_records(
                root, os.path.abspath(args.records),
                [(name, rec["flags"]) for name, rec in wanted])
            from_records = len(answers)
        # B160: up to --probe-jobs self-tests run at once, each under its own
        # --probe-timeout. Serially, 62 probes took 644s on a loaded machine
        # against a 600s budget for the whole check. B187: one that timed out
        # beside others is probed again alone before it counts as a timeout.
        live = [(name, rec["flags"][0]) for name, rec in wanted if name not in answers]
        answers.update(run_probes(root, live, args.probe_timeout, args.probe_jobs))
        for name, rec in wanted:
            res = answers[name]
            probed += 1
            if "first" in res:
                reprobed.append((name, res["first"], res))
            if slowest is None or res["elapsed"] > slowest[1]["elapsed"]:
                slowest = (name, res)
            state, detail, output = res["state"], res["detail"], res["output"]
            if res["timed_out"]:
                detail = timeout_detail(res, args.probe_timeout)
            if state == "rejected":
                # The source reads as if it dispatches and the parser says
                # otherwise. The parser is what runs, so it wins.
                rec["disagreed"] = detail
                rec["flags"] = []
                rec["answered"] = NA
                rec["codes"] = {"state": NA,
                                "detail": "no self-test to declare anything"}
            elif state == UNREADABLE:
                rec["answered"] = UNREADABLE
                rec["probe_note"] = detail
                rec["codes"] = {"state": UNREADABLE, "detail": detail}
                unreadable.append(name)
            else:
                rec["answered"] = detail
                cstate, creached, cdocumented, cdetail = declared_codes(output)
                rec["codes"] = {"state": cstate, "reached": creached,
                                "documented": cdocumented, "detail": cdetail}

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
    local_names = sorted(n for n, r in tools.items() if r["kind"] == KIND_REPO)
    for name in local_names:
        out(name)

    absent_names = sorted(n for n, r in tools.items()
                          if r["kind"] == KIND_ABSENT)
    external = sorted(n for n, r in tools.items()
                      if r["kind"] == KIND_EXTERNAL)

    # WHAT THE SUITE EXERCISES, AND WHAT IT ONLY DECLARES. A check with
    # `enabled: false` never runs, so its tool's self-test is not part of what
    # the suite exercises and does not belong in R39's or R40's denominator: an
    # obligation nobody is under is not a shortfall.
    #
    # DROPPING IT ALTOGETHER WOULD BE THE OTHER ERROR. A check is switched back
    # on by editing one line, and a tool sitting behind a disabled check with no
    # self-test is a finding held in escrow - invisible is exactly how it gets
    # forgotten. So the switched-off tools are neither counted with the rest nor
    # discarded: they are a THIRD FIGURE, named on their own line, never added
    # to the other two. That is the treatment this file already gives
    # third-party tools, for the stated reason that figures which mean different
    # things are never added together.
    exercised = [n for n in local_names if not tools[n]["disabled"]]
    switched_off = [n for n in local_names if tools[n]["disabled"]]

    out("  tool set: %d invoked by %s or %s - %d in this repository, %d "
        "third-party, %d named by an argv and absent from this work tree; %d "
        "of them reached only by a check with `enabled: false`"
        % (len(tools), checks_rel, workflow_rel, len(local_names),
           len(external), len(absent_names),
           sum(1 for r in tools.values() if r["disabled"])))
    out("  %-58s %-12s %-10s %-10s %s"
        % ("tool", "self-test", "answered", "codes", "run by"))
    for name in local_names + absent_names + external:
        rec = tools[name]
        if rec["kind"] == KIND_ABSENT:
            flag = "absent"
        elif rec.get("disagreed"):
            flag = "none"
        elif rec["flags"] is None:
            flag = NA if rec["kind"] == KIND_EXTERNAL else UNREADABLE
        elif rec["flags"]:
            flag = ",".join(rec["flags"])
        else:
            flag = "none"
        reached = rec.get("reached", NA)
        if isinstance(reached, list):
            reached = ", ".join(sorted(set(reached))) if reached else "nothing"
        out("  %-58s %-12s %-10s %-10s %s"
            % (name[:58], flag, rec["answered"],
               rec.get("codes", {}).get("state", UNREADABLE), reached))

    findings = []
    for name in exercised:
        rec = tools[name]
        if rec.get("unreadable"):
            continue
        if not rec.get("flags"):
            extra = ""
            if rec.get("disagreed"):
                extra = (" - its source reads as if it dispatches on one and "
                         "its parser rejected the flag (%s)" % rec["disagreed"])
            findings.append("R39: %s carries no self-test%s" % (name, extra))
    # An argv naming a file that is not there. A finding when a check that RUNS
    # names it; when only a switched-off check does, it is reported on the absent
    # line and left there, for the same reason the R39 shortfall is.
    for name in absent_names:
        rec = tools[name]
        if rec["disabled"]:
            continue
        ids = ", ".join(sorted({c["id"] for c in rec["checks"]})) or "a check"
        findings.append("R39: %s is named by %s and no such file exists in this "
                        "work tree, so there is nothing here that could carry a "
                        "self-test - a missing repo-local tool, not a third "
                        "party" % (name, ids))
    for name in exercised:
        rec = tools[name]
        if not rec.get("flags"):
            continue
        if not rec.get("reached"):
            findings.append("R40: %s carries %s and no declared check or "
                            "workflow step invokes it" % (name, rec["flags"][0]))
        for why in rec.get("swallowed") or []:
            findings.append("R40: %s's self-test runs but %s, so its failure "
                            "cannot set the run's exit code" % (name, why))

    carried = sum(1 for n in exercised if tools[n].get("flags"))
    invoked = [n for n in exercised
               if isinstance(tools[n].get("reached"), list)
               and tools[n]["reached"]]
    swallowed_names = [n for n in invoked if tools[n].get("swallowed")]
    out("  R39: %d of %d check tools the suite exercises carry a self-test that "
        "answers." % (carried, len(exercised)))
    out("  R40: %d of %d self-tests found are invoked by a declared check or by "
        "the workflow." % (len(invoked), carried))
    # THE SUMMARY MAY NOT DISAGREE WITH THE FINDINGS. One `|| true` on a
    # workflow line used to leave this block reporting `36 of 36 are invoked`
    # while a FINDING below said that call's failure could not set the run's exit
    # code - both true, and the reader believes the summary. "Invoked" and "able
    # to fail the run" mean different things, so they are not merged into one
    # number; they are printed one under the other, and R40 rests on the second.
    out("  R40 propagation: %d of those %d can still set the run's exit code; "
        "%d run with their failure swallowed, each one a finding below."
        % (len(invoked) - len(swallowed_names), len(invoked),
           len(swallowed_names)))
    if switched_off:
        off_carried = [n for n in switched_off if tools[n].get("flags")]
        out("  switched off: %d repo-local tool(s) reached only by checks with "
            "`enabled: false`, counted here and in neither figure above - %d of "
            "them carry a self-test. A check that never runs does not exercise "
            "its tool, and a tool nobody exercises is not a shortfall: %s"
            % (len(switched_off), len(off_carried), ", ".join(switched_off)))
    else:
        out("  switched off: 0 repo-local tools are reached only by checks with "
            "`enabled: false`, so neither figure above is measured over a tool "
            "that cannot run.")
    out("  third-party tools, which nobody here can add a self-test to: %s"
        % (", ".join(external) if external else "none"))
    out("  named by an argv and absent from this work tree - a missing "
        "repo-local tool, never a third party: %s (%d of them named only by a "
        "check that is switched off)"
        % (", ".join(absent_names) if absent_names else "none",
           sum(1 for n in absent_names if tools[n]["disabled"])))
    if args.probe:
        out("  probe: %d self-test(s) executed with the flag their source "
            "dispatches on - %d read from records of the workflow's own run of "
            "them, %d executed here." % (probed, from_records, probed - from_records))
        if records_header is None:
            out("  records: none given, so every self-test was executed here.")
        else:
            out("  " + records_header + ".")
            for why in records_unused:
                out("  record not used, so probed here - %s" % why)
        if slowest is not None:
            out("  slowest probe: %s, %.1fs%s." % (
                slowest[0], slowest[1]["elapsed"],
                " (recorded)" if slowest[1].get("recorded") else ""))
        for name, first, final in reprobed:
            if final["timed_out"]:
                continue                            # reported with the ? below
            out("  %s: timed out after %ds under contention, beside %d other "
                "probe(s) (%.1fs elapsed); probed again alone, it answered %s "
                "in %.1fs, and that run is the one counted."
                % (name, args.probe_timeout, first["contended"], first["elapsed"],
                   final["detail"], final["elapsed"]))
    else:
        out("  probe: not run (--no-probe). The answered column reads %s - never "
            "run - and is never read as a 0." % NEVER_RUN)
    # --- R39.b: the second clause, counted and never enforced --------------
    by_state = {}
    for name in exercised:                          # the same set `carried` is over
        if not tools[name].get("flags"):
            continue                                # no self-test: n/a, not 0
        by_state.setdefault(tools[name]["codes"]["state"], []).append(name)
    complete = by_state.get(CODES_COMPLETE, [])
    incomplete = by_state.get(CODES_INCOMPLETE, [])
    silent = by_state.get(CODES_SILENT, [])
    unparsed_decl = by_state.get(CODES_UNPARSED, [])
    not_run = by_state.get(NEVER_RUN, []) + by_state.get(UNREADABLE, [])
    declaring = len(complete) + len(incomplete)

    out("  R39.b protocol: a self-test declares its own exit-code coverage as "
        "one line - `exit codes reached: <codes>   documented: <codes>` - both "
        "halves bare lists of integers. check-selftest-coverage.sh carries the "
        "full definition.")
    out("  R39.b: %d of %d check tools carrying a self-test declare which exit "
        "codes it drove and which their contract documents; %d of those %d "
        "drove every code they document." % (declaring, carried,
                                             len(complete), declaring))
    for name in incomplete:
        out("  R39.b INCOMPLETE: %s %s. Counted, not a finding - see NOT "
            "ASSERTED below." % (name, tools[name]["codes"]["detail"]))
    out("  R39.b unmeasured: %d of %d - %d emit no declaration (`not asked`), "
        "%d emit a line this protocol could not parse (`unparsed`), %d were "
        "not run. None of those is a measurement of zero: a self-test nobody "
        "asked which codes it drove has not been shown incomplete."
        % (len(silent) + len(unparsed_decl) + len(not_run), carried,
           len(silent), len(unparsed_decl), len(not_run)))
    out("  NOT ASSERTED: R39's `reaches each exit code it can return` is "
        "COUNTED HERE AND NOT ENFORCED. No exit code of this check rests on "
        "the R39.b figures, because a tool that does not declare has not been "
        "shown incomplete - and a declaration is still the self-test's own "
        "account of itself, not an observation of the codes it drove.")

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
