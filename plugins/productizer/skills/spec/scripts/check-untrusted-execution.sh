#!/usr/bin/env bash
# check-untrusted-execution.sh [--root DIR] [--fixture DIR] [--gate FILE]
#                              [--assert LIST] [--version] [--help]
#
# Asserts R17, R18 and R22, the three requirements that enforce P4 - A
# REPOSITORY BEING EXAMINED NEVER CHOOSES WHAT RUNS. None of the three had a
# check before this one.
#
#   R17  If a command would publish or deploy, then the gate shall block it
#        until a person decides.
#   R18  If a configured command names a shell or an interpreter with an inline
#        program, then the lifecycle shall refuse to run it.
#   R22  Where a repository declares its own check tools, the lifecycle shall
#        run them only where that is allowed.
#
# WHY THE ASSERTIONS ARE WRITTEN AGAINST THE OBLIGATION AND NOT THE CODE.
# R18's acceptance row in the spec reads "run-checks.sh argv[0] validation".
# That names the mechanism, so it is true whatever the mechanism does, and it
# could never have failed - it did not notice when three separate configs
# walked past that validation and executed their payloads. Every assertion here
# is a fact about behaviour that a wrong implementation makes false: a command
# was refused, a marker file does not exist, a command a person needs was not
# blocked. Not one of them reads the source of the thing it is testing.
#
# ---------------------------------------------------------------------------
# WHAT IT ASSERTS
#
# R17, first half - the gate blocks (`--assert r17-block`).
#   The real gate is driven with the corpus in `fixtures/untrusted-execution/
#   cases.yaml`, one process per row, and each row's verdict is asserted on its
#   own and named. BOTH DIRECTIONS, because a gate that blocks everything is as
#   broken as one that blocks nothing and only the allow rows tell them apart:
#   publishes and deploys must exit 2, and ordinary drafting, building,
#   reading and reviewing commands must exit 0. Commands the gate cannot
#   statically resolve - a $expansion, a $(...), a backtick, wrappers nested
#   deeper than it unwraps - must also exit 2, because failing closed on
#   ambiguity is the point of a gate.
#
#   One further assertion, separate from all of those: the gate JUDGES and does
#   not EXECUTE. One corpus row is shaped like a publish and would create a file
#   if it were ever run, and the directory that file would land in is asserted
#   empty afterwards.
#
# R17, second half - a person decides (`--assert r17-decision`).
#   THIS IS EXPECTED TO FAIL, and it is not narrowed to stop it failing. R17
#   says the gate blocks UNTIL A PERSON DECIDES. The gate implements the block
#   and implements no deciding: there is no environment variable, no marker
#   file, no field in the payload by which someone who has already said yes can
#   say so, and the only remaining route is retyping the command in their own
#   shell - which the gate's own closing paragraph argues against. So two
#   assertions: that the refusal names a route by which a decision reaches the
#   gate, and that at least one of the consent signals listed in the fixture
#   actually lifts a block. Both fail today. Rewriting them to match what the
#   code does would reproduce exactly the defect described above.
#
# R18 - the lifecycle refuses (`--assert r18`).
#   Each argv payload in the fixture becomes one checks.yaml in a temporary
#   repository, handed to the real run-checks.sh. The canonical pair - a shell
#   with -c, an interpreter with -c - plus the three bypasses that were
#   reproduced against the argv[0]-only ancestor and are the reason argv is now
#   validated in EVERY position:
#
#     a program taken POSITIONALLY rather than by flag   awk 'BEGIN{system(...)}'
#     a repo-local script passed as an ARGUMENT          python3 lint.py
#     a build tool named by neither list                 make check
#
#   And the other direction: an ordinary command must still run, or the rule is
#   a ban rather than a gate.
#
# R22 - only where that is allowed (`--assert r22`).
#   The same repo-local tool, twice. With `policy.allow_repo_local_tools` at its
#   default of false it must not run; with it true it must. A gate that never
#   opens is not a gate.
#
# TWO ASSERTIONS PER REFUSAL, NOT ONE. An exit code says the runner said no. It
# does not say the payload stayed unexecuted - a runner that ran the command and
# then exited 2 would satisfy the first and violate P4 completely. So the marker
# file each payload would create is asserted absent, separately and by name.
#
# ---------------------------------------------------------------------------
# THE PREMISES ARE CHECKED FIRST AND ARE NOT ASSERTIONS.
#
#   * Every refuse payload is LIVE-PROBED: the same argv is executed once in a
#     throwaway directory and its marker must appear there. A payload that is
#     inert for an unrelated reason - an interpreter that is not installed, a
#     tool that ignores its argument - makes the marker's absence in the gated
#     run prove nothing whatever. That is exit 2, unmeasured, never a pass.
#   * The gate must actually block the command the decision probes are run
#     against. If it does not, there was no block for a decision to lift.
#   * jq, python3, PyYAML and the fixture's own tools must be present, or the
#     thing under test never ran.
#
# EVERY PAYLOAD IS INERT. The worst a payload does if a guard fails open is
# create an empty marker file in a temporary directory that is removed on exit.
# Nothing deletes, nothing reaches the network, nothing pushes a tag. The R17
# corpus is never executed at all - it is text handed to a gate that judges it -
# and the canary row measures that rather than assuming it.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every selected assertion held
#   1  findings - at least one did not hold
#   2  could not run - bad usage, a missing fixture, a missing tool, or a
#      premise that did not hold
#
# The default selection is `all`, which includes R17's second half, so a bare
# run EXITS 1 TODAY and says why. `--assert` exists so the implemented
# obligations can be declared as a blocking check without the unimplemented one
# voiding their coverage claims, not so that the unimplemented one can be
# forgotten: it is declared too, and it is visibly red.
#
# WHAT IT PRINTS. One BARE PATH per line, relative to the repository, for every
# file examined - the runner parses those as coverage. Everything else is
# INDENTED. No temporary directory name is printed: this output is tailed into a
# committed result file, and an absolute path there is somebody's home directory
# published to everyone who clones the repo.
set -euo pipefail

VERSION="check-untrusted-execution 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$HERE")"

ROOT=""
FIXTURE="$SKILL/fixtures/untrusted-execution"
GATE="$SKILL/templates/publish-gate.sh"
SELECT="all"
MODE="measure"

die_unmeasured() { printf 'check-untrusted-execution: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    # `--self-test` is an alias, not a second flag: this repository spells the
    # same obligation both ways and a tool that answers only one spelling reads
    # as carrying no self-test to whichever scanner is looking for the other.
    --selftest|--self-test) MODE="selftest"; shift ;;
    --root)      [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)    ROOT="${1#--root=}";       shift ;;
    --fixture)   [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2"; shift 2 ;;
    --fixture=*) FIXTURE="${1#--fixture=}"; shift ;;
    --gate)      [ "$#" -ge 2 ] || die_unmeasured "--gate needs a path";    GATE="$2";    shift 2 ;;
    --gate=*)    GATE="${1#--gate=}";       shift ;;
    --assert)    [ "$#" -ge 2 ] || die_unmeasured "--assert needs a list";  SELECT="$2";  shift 2 ;;
    --assert=*)  SELECT="${1#--assert=}";   shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1" ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1"

WANT_R17B=0; WANT_R17D=0; WANT_R18=0; WANT_R22=0
OLD_IFS="$IFS"; IFS=','
for part in $SELECT; do
  case "$part" in
    all)          WANT_R17B=1; WANT_R17D=1; WANT_R18=1; WANT_R22=1 ;;
    r17-block)    WANT_R17B=1 ;;
    r17-decision) WANT_R17D=1 ;;
    r18)          WANT_R18=1 ;;
    r22)          WANT_R22=1 ;;
    "") ;;
    *) IFS="$OLD_IFS"; die_unmeasured "unknown --assert group: $part. Choose from all, r17-block, r17-decision, r18, r22." ;;
  esac
done
IFS="$OLD_IFS"
[ "$((WANT_R17B + WANT_R17D + WANT_R18 + WANT_R22))" -gt 0 ] ||
  die_unmeasured "--assert selected no group, so nothing would be asserted. That is not a pass."

# The work tree, never the working directory. --root does not decide what is
# tested - the fixture, the gate and the runner are all found beside this
# script, so the test is the same one wherever it is invoked from - it decides
# what the printed paths are relative to, so nothing absolute reaches the
# committed result.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" || ROOT=""
fi
if [ -n "$ROOT" ] && [ -d "$ROOT" ]; then
  ROOT="$(cd "$ROOT" && pwd -P)"
else
  # No work tree: an installed plugin is not a repository. Paths are then
  # printed relative to the skill directory, which is still not absolute.
  ROOT="$SKILL"
fi

RUNNER="$HERE/run-checks.sh"
CASES="$FIXTURE/cases.yaml"
SKELETON="$FIXTURE/checks.yaml.in"

[ -d "$FIXTURE" ] || die_unmeasured "no fixture directory; the standing case is missing, which is unmeasured and not a pass"
[ -f "$CASES" ]   || die_unmeasured "the fixture has no cases.yaml"
command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the fixture could not be read"
python3 -c 'import yaml' || die_unmeasured "python3 has no yaml module; the fixture could not be read"

# ---------------------------------------------------------------------------
# --selftest - R39: THIS TOOL REACHES EACH EXIT CODE IT CAN RETURN, ON PURPOSE.
#
# Four cases, one per way the contract above can be reached, each driven
# through THIS script so the argument handling and the premise guards are on
# the path too. No case is asserted by reading source: the exit code is read
# off a real run.
#
#   clean           the committed gate and corpus, over the three groups
#                   the declared check selects                            -> 0
#   gate-allows-all a gate that exits 0 on every command it is handed,
#                   asserted over r17-block alone                         -> 1
#   bad-group       an --assert group this tool does not know             -> 2
#   no-fixture      a fixture directory that is not there                 -> 2
#
# THE SELECTION MATTERS AND IS NOT COSMETIC. A bare run asserts `all`, and this
# file's own contract says a bare run exits 1 today - so `all` is useless as
# the clean case. The clean case drives exactly the argv the declared check
# `untrusted-execution` declares, which is the invocation whose exit code the
# suite actually reads.
#
# THE CLEAN CASE GUARDS THE OTHERS' PREMISE. If the committed gate and corpus
# do not exit 0 over that selection, every case below would be red for that
# reason rather than its own - exit 2 for the whole self-test, never a pass on
# the three that followed.
#
# EVERY PAYLOAD STAYS INERT AND NOTHING IS WRITTEN INTO THE REPOSITORY. The
# broken gate is a copy under mktemp that judges nothing and runs nothing, and
# the directory goes on every exit path, signal included.
#
# WHAT THIS SELF-TEST DOES NOT ASSERT, printed rather than passed silently: it
# reads the exit CODE and never the wording of a finding, so a case that went
# red for the wrong reason is invisible here.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-untrusted-execution-selftest.XXXXXX")" \
    || die_unmeasured "cannot create a temporary directory to build the self-test's inputs in; nothing was driven"
  trap 'rm -rf "$SB"' EXIT HUP INT TERM

  # The production defect the r17-block assertions exist to catch: a gate that
  # lets every command through, publishes and deploys included. It EXECUTES
  # NOTHING - it reads the payload and exits 0 - so the corpus stays as inert
  # under this gate as it is under the real one.
  cat > "$SB/gate-allows-all.sh" <<'SELFTEST_GATE'
#!/usr/bin/env bash
# Built by check-untrusted-execution.sh --selftest. Never registered, never
# reachable from the repository: it lives under mktemp for one run.
cat >/dev/null
exit 0
SELFTEST_GATE
  chmod +x "$SB/gate-allows-all.sh"

  SELF_CASES=0
  SELF_FAILED=0

  # $1 case, $2 expected exit, $3 what the case is, then the argv to drive.
  #
  # `|| _rc=$?` on the SAME LINE as the command. Three of the four cases exit
  # non-zero on purpose, `set -e` would end the run at the first one, and a
  # `$(...)` or a pipeline between the command and the read of `$?` resets it -
  # which is how a self-test reports four passes having measured none.
  self_drive() {
    _name="$1"; _want="$2"; _why="$3"
    shift 3
    _rc=0
    bash "$0" "$@" > "$SB/$_name.out" 2> "$SB/$_name.err" || _rc=$?
    SELF_CASES=$((SELF_CASES + 1))
    if [ "$_rc" = "$_want" ]; then
      printf '  held:    case %-16s expected %s  observed %s  %s\n' "$_name" "$_want" "$_rc" "$_why"
    else
      printf '  FINDING: case %-16s expected %s  observed %s  %s\n' "$_name" "$_want" "$_rc" "$_why"
      SELF_FAILED=$((SELF_FAILED + 1))
    fi
  }

  SELF_RC=0
  bash "$0" --root "$ROOT" --fixture "$FIXTURE" --gate "$GATE" \
    --assert r17-block,r18,r22 > "$SB/clean.out" 2> "$SB/clean.err" || SELF_RC=$?
  if [ "$SELF_RC" -ne 0 ]; then
    printf '  the clean case exited %d, not 0.\n' "$SELF_RC"
    die_unmeasured "the committed gate and corpus did not produce a clean run over r17-block,r18,r22 - the selection the declared check uses - so every failing case below would be red for that reason instead of its own. Unmeasured, not a corpus that held"
  fi
  SELF_CASES=1
  printf '  held:    case %-16s expected %s  observed %s  %s\n' "clean" "0" "0" \
    "the committed gate and corpus over r17-block,r18,r22: every publish and deploy blocked, every ordinary command let through, and no payload executed"

  self_drive gate-allows-all 1 \
    "a gate that exits 0 on everything it is handed: the publishes and deploys R17 obliges it to block are not blocked" \
    --root "$ROOT" --fixture "$FIXTURE" --gate "$SB/gate-allows-all.sh" --assert r17-block
  self_drive bad-group 2 \
    "an --assert group this tool does not know: a selection it cannot read is refused rather than silently narrowed to nothing" \
    --root "$ROOT" --assert there-is-no-such-group
  self_drive no-fixture 2 \
    "no fixture directory at the path given, so no case was driven at all - unmeasured, never a pass" \
    --root "$ROOT" --fixture "$SB/there-is-no-fixture-here" --assert r17-block

  printf '  self-test cases driven: %d, exit codes reached: 0, 1, 2. Cases that did not hold: %d\n' \
    "$SELF_CASES" "$SELF_FAILED"
  printf '  NOT ASSERTED: the wording of any finding. Each case reads the exit CODE, so a case that went red for the wrong reason is invisible here and is read off the case output by hand.\n'
  if [ "$SELF_FAILED" -ne 0 ]; then
    printf 'check-untrusted-execution: %d self-test case(s) did not produce the exit code the contract declares for them.\n' "$SELF_FAILED" >&2
    exit 1
  fi
  printf '  R39 for this tool: the self-test exists and reaches 0, 1 and 2 by driving the real check, not by reading its source.\n'
  exit 0
fi

if [ "$((WANT_R17B + WANT_R17D))" -gt 0 ]; then
  [ -f "$GATE" ] || die_unmeasured "no publish gate at the path given; there is nothing to drive"
  command -v jq >/dev/null 2>&1 ||
    die_unmeasured "jq is not installed, and the gate refuses every payload without it. A gate that blocks because its own dependency is absent has told us nothing about R17"
fi
if [ "$((WANT_R18 + WANT_R22))" -gt 0 ]; then
  [ -f "$RUNNER" ]   || die_unmeasured "no run-checks.sh beside this script; there is nothing to test"
  [ -f "$SKELETON" ] || die_unmeasured "the fixture has no checks.yaml.in"
  for f in changed.txt lint.py Makefile tool.sh; do
    [ -f "$FIXTURE/$f" ] || die_unmeasured "the fixture is missing $f"
  done
fi

rel() {
  case "$1" in
    "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;;
    *)         printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;;
  esac
}

# --- coverage: one bare path per file examined ----------------------------
rel "$CASES"
if [ "$((WANT_R17B + WANT_R17D))" -gt 0 ]; then
  rel "$GATE"
fi
if [ "$((WANT_R18 + WANT_R22))" -gt 0 ]; then
  rel "$RUNNER"
  rel "$SKELETON"
  rel "$FIXTURE/changed.txt"
  rel "$FIXTURE/lint.py"
  rel "$FIXTURE/Makefile"
  rel "$FIXTURE/tool.sh"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
COUNTS="$TMP/counts"
: > "$COUNTS"

# --- R17: drive the real gate ---------------------------------------------
cat > "$TMP/r17.py" <<'PY'
"""Drive templates/publish-gate.sh with the committed corpus and report.

Every row is one process and one assertion, named. Nothing here reads the
gate's source: a row holds because the gate returned the exit code the
obligation requires, which is a fact a wrong gate makes false.

stdout: indented lines. Exit 0 all held, 1 at least one did not, 2 a premise
did not hold - which is unmeasured and never a pass.
"""
import json
import os
import re
import subprocess
import sys

import yaml

gate, cases_path, markerdir, rundir, mode, countfile = sys.argv[1:7]

out = sys.stdout
EVALUATED = 0
UPHELD = 0
ok = True


def say(held, text):
    # COUNTED, NEVER DERIVED. A summary that prints `upheld: 0` above six lines
    # saying `held:` disagrees with the evidence directly above it.
    global ok, EVALUATED, UPHELD
    EVALUATED += 1
    if held:
        UPHELD += 1
    else:
        ok = False
    out.write("  %s %s\n" % ("held:" if held else "FINDING: did not hold -", text))


def finish(code):
    with open(countfile, "a") as fh:
        fh.write("%d %d\n" % (EVALUATED, UPHELD))
    out.write("  R17 assertions evaluated: %d, upheld: %d\n" % (EVALUATED, UPHELD))
    sys.exit(code)


def premise_failed(text):
    out.write("  PREMISE did not hold - %s\n" % text)
    out.write("  R17 was not exercised. Unmeasured, not a pass.\n")
    with open(countfile, "a") as fh:
        fh.write("%d %d\n" % (EVALUATED, UPHELD))
    sys.exit(2)


with open(cases_path) as fh:
    fixture = yaml.safe_load(fh)

CANARY = os.path.join(markerdir, "r17-canary")


def redact(text):
    """Never print a temporary path: this output is tailed into a committed file."""
    return text.replace(markerdir, "<tmp>")


def ask(command, extra_env=None, extra_payload=None):
    payload = {"tool_name": "Bash", "tool_input": {"command": command}}
    if extra_payload:
        payload.update(extra_payload)
    env = dict(os.environ)
    if extra_env:
        env.update(extra_env)
    proc = subprocess.run(
        ["bash", gate], input=json.dumps(payload), env=env, cwd=rundir,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return proc.returncode, proc.stderr, proc.stdout


rows = fixture.get("publish_cases") or []
if mode in ("block", "both"):
    if not rows:
        premise_failed("the fixture holds no publish corpus, so nothing was put to the gate")
    blocks = [r for r in rows if r.get("expect") == "block"]
    allows = [r for r in rows if r.get("expect") == "allow"]
    if not blocks or not allows:
        premise_failed("the corpus is one-sided (%d block, %d allow). A gate that blocks "
                       "everything is as broken as one that blocks nothing, and only both "
                       "directions tell them apart" % (len(blocks), len(allows)))

    out.write("  R17, first half - the gate blocks. %d rows: %d that must be refused, "
              "%d that must be allowed.\n" % (len(rows), len(blocks), len(allows)))
    for row in rows:
        command = str(row["command"]).replace("@@MARKER@@", CANARY)
        want = 2 if row["expect"] == "block" else 0
        rc, _err, _o = ask(command)
        verb = "refused" if row["expect"] == "block" else "allowed"
        got = {0: "allowed", 2: "refused"}.get(rc, "exited %d" % rc)
        say(rc == want, "%s: %s  (%s)" % (verb, redact(command), row.get("why", "")))
        if rc != want:
            out.write("      the gate %s it instead\n" % got)

    # SEPARATE, AND NOT IMPLIED BY ANY OF THE ABOVE. Every row above says the
    # gate returned a verdict. None of them says it did not RUN what it judged.
    stray = sorted(os.listdir(markerdir))
    say(not stray,
        "the gate judged the corpus and executed none of it; the directory a payload "
        "would have written to is still empty%s"
        % ("" if not stray else " - found: " + ", ".join(stray)))

if mode in ("decision", "both"):
    out.write("  R17, second half - until a person decides.\n")
    baseline = next((r for r in rows if r.get("expect") == "block"
                     and "@@MARKER@@" not in str(r["command"])), None)
    if baseline is None:
        premise_failed("the corpus holds no blocked command to try a decision against")
    command = str(baseline["command"])
    rc, err, _out = ask(command)
    if rc != 2:
        premise_failed("the command the probes are run against was not blocked (exit %d), so "
                       "there was no block for a decision to lift" % rc)
    out.write("  premise held: the gate blocks `%s`, and the probes below are run against "
              "that same block.\n" % command)

    # Assertion 1. A person who has decided yes has to be told how to say so.
    # ASSERTION 1. THE DECISION REACHES A PERSON, CONSTRUCTED.
    #
    # This assertion was rewritten once the deciding half was built, and the
    # rewrite matters more than the code. It used to search the refusal text for
    # a route and then try to LIFT the block with an environment variable, a
    # marker file or a payload field - and it counted "none of them lifts it" as
    # the failure.
    #
    # That was demanding a hole. Every one of those signals is something the
    # agent this gate constrains can write for itself, so a gate that honoured
    # one would be a gate the agent could open. The old assertion would have
    # gone green on the worst possible design.
    #
    # What R17 actually wants is that the decision reaches A PERSON. The route
    # is Claude Code's own permission prompt: drawn by the harness, answered by
    # a keystroke, and unreachable from inside the process being gated. So the
    # assertion is now that a recognised publish, with a fresh checklist naming
    # that exact command, in a mode documented to prompt, returns
    # `permissionDecision: "ask"`.
    checklist = os.path.join(rundir, ".claude", "productizer", "publish-checklist.md")
    os.makedirs(os.path.dirname(checklist), exist_ok=True)
    with open(checklist, "w") as fh:
        fh.write("Command: %s\n\n# Pre-publish checklist (fixture)\n\n"
                 "- every item here is a fixture value, not a real verification\n" % command)
    rc_ask, err_ask, out_ask = ask(command, extra_payload={"permission_mode": "default"})
    decision = None
    try:
        decision = json.loads(out_ask)["hookSpecificOutput"]["permissionDecision"]
    except Exception:
        decision = None
    say(rc_ask == 0 and decision == "ask",
        "a recognised publish with a fresh, command-matching checklist hands the decision to a "
        "person: the gate returns permissionDecision `ask`%s"
        % ("" if decision == "ask" else
           " - it returned %r at exit %s, so nothing was put to anyone" % (decision, rc_ask)))

    # ASSERTION 2. THE SAME SIGNALS MUST STILL NOT ALLOW.
    #
    # The old probes are kept and their meaning is INVERTED. None of them may
    # turn a publish into `allow`, because each is something the agent can write
    # for itself. Turning the block into `ask` is fine - a person still decides.
    # Turning it into `allow` is the hole.
    probes = fixture.get("decision_probes") or {}
    forged = []
    tried = 0
    os.remove(checklist)   # no checklist, so nothing may pass on its own

    def _forges(rc2, out2):
        if rc2 != 0:
            return False
        try:
            return json.loads(out2)["hookSpecificOutput"]["permissionDecision"] == "allow"
        except Exception:
            return True    # exit 0 with no readable decision is an allow by default

    for assignment in probes.get("env") or []:
        name, _, value = str(assignment).partition("=")
        tried += 1
        rc2, _e, out2 = ask(command, extra_env={name: value})
        if _forges(rc2, out2):
            forged.append("env %s" % assignment)
    for path in probes.get("files") or []:
        target = os.path.join(rundir, str(path))
        os.makedirs(os.path.dirname(target) or rundir, exist_ok=True)
        open(target, "w").close()
        tried += 1
        rc2, _e, out2 = ask(command)
        if _forges(rc2, out2):
            forged.append("file %s" % path)
        os.remove(target)
    for blob in probes.get("payload_fields") or []:
        tried += 1
        rc2, _e, out2 = ask(command, extra_payload=json.loads(blob))
        if _forges(rc2, out2):
            forged.append("payload %s" % blob)
    if tried == 0:
        premise_failed("the fixture lists no consent signals, so nothing was tried and the "
                       "forgery question was never asked")
    say(not forged,
        "no signal the agent can write for itself turns a publish into `allow` (%d tried)%s"
        % (tried, "" if not forged else "; FORGED BY " + ", ".join(forged)))

    # ASSERTION 3. A MODE THAT CANNOT PROMPT MUST REFUSE.
    #
    # The documentation says a `deny` survives bypassPermissions and
    # --dangerously-skip-permissions. It does NOT say the same of `ask`, and it
    # says nothing about `ask` in a plain -p run. So the gate must not ask where
    # it cannot be sure a person sees it, and this asserts that it does not.
    # THE CHECKLIST IS PUT BACK FIRST, and that is not housekeeping. Assertion 2
    # deleted it, and without it the gate refuses for the WRONG REASON - "no
    # checklist" rather than "this mode cannot prompt". This assertion passed
    # against a gate deliberately patched to ask under bypassPermissions,
    # because it could not tell the two refusals apart. Caught by falsifying.
    with open(checklist, "w") as fh:
        fh.write("Command: %s\n\n# Pre-publish checklist (fixture)\n\n"
                 "- every item here is a fixture value, not a real verification\n" % command)
    unpromptable = []
    for pm in ("bypassPermissions", "", "somethingNobodyDefined"):
        rc3, _e3, out3 = ask(command, extra_payload={"permission_mode": pm})
        ok3 = rc3 != 0
        if not ok3:
            unpromptable.append(pm or "<empty>")
    say(not unpromptable,
        "a mode not documented to show a prompt gets the hard refusal, not an ask%s"
        % ("" if not unpromptable else "; asked anyway under " + ", ".join(unpromptable)))

finish(0 if ok else 1)
PY

R17_RC=0
if [ "$((WANT_R17B + WANT_R17D))" -gt 0 ]; then
  if [ "$WANT_R17B" = 1 ] && [ "$WANT_R17D" = 1 ]; then R17_MODE=both
  elif [ "$WANT_R17B" = 1 ];                        then R17_MODE=block
  else                                                   R17_MODE=decision
  fi
  mkdir -p "$TMP/canary" "$TMP/gate-cwd"
  python3 "$TMP/r17.py" "$GATE" "$CASES" "$TMP/canary" "$TMP/gate-cwd" "$R17_MODE" "$COUNTS" || R17_RC=$?
fi

# --- R18 and R22: drive the real runner -----------------------------------
cat > "$TMP/r18r22.py" <<'PY'
"""Hand each argv payload to run-checks.sh and report what it agreed to run.

Two assertions per refusal row and they are not the same claim: an exit code
says the runner said no, and a marker file says the payload never executed. A
runner that ran the command and then exited 2 satisfies the first and violates
P4 entirely.

Every refusal row is LIVE-PROBED first - the same argv executed once in a
throwaway directory, its marker required to appear - because the absence of a
marker left by a payload that could never have written one is not evidence.

stdout: indented lines. Exit 0 all held, 1 at least one did not, 2 a premise
did not hold.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

import yaml

runner, fixture_dir, cases_path, skeleton_path, countfile, groups = sys.argv[1:7]
WANT = set(groups.split(","))

out = sys.stdout
EVALUATED = 0
UPHELD = 0
ok = True
PAYLOAD_FILES = ("changed.txt", "lint.py", "Makefile", "tool.sh")


def say(held, text):
    global ok, EVALUATED, UPHELD
    EVALUATED += 1
    if held:
        UPHELD += 1
    else:
        ok = False
    out.write("  %s %s\n" % ("held:" if held else "FINDING: did not hold -", text))


def premise_failed(text):
    out.write("  PREMISE did not hold - %s\n" % text)
    out.write("  The requirement was not exercised. Unmeasured, not a pass.\n")
    with open(countfile, "a") as fh:
        fh.write("%d %d\n" % (EVALUATED, UPHELD))
    sys.exit(2)


def populate(target):
    for name in PAYLOAD_FILES:
        shutil.copy(os.path.join(fixture_dir, name), os.path.join(target, name))
    os.chmod(os.path.join(target, "tool.sh"), 0o755)


with open(cases_path) as fh:
    fixture = yaml.safe_load(fh)
with open(skeleton_path) as fh:
    skeleton = fh.read()

rows = [r for r in (fixture.get("argv_cases") or []) if r.get("requirement") in WANT]
if not rows:
    premise_failed("the fixture holds no argv case for %s, so nothing was put to the runner"
                   % ", ".join(sorted(WANT)))

for group in sorted(WANT):
    kinds = {r["expect"] for r in rows if r.get("requirement") == group}
    if kinds != {"refuse", "run"}:
        premise_failed("%s has only %s rows. A gate that never opens is not a gate and a gate "
                       "that never closes is not one either; both directions have to be asserted"
                       % (group, " and ".join(sorted(kinds))))

out.write("  R18 and R22 - %d argv payloads, each one config handed to the real runner.\n"
          % len(rows))

with tempfile.TemporaryDirectory() as work:
    # --- premise: every refusal payload is live ---------------------------
    for row in rows:
        marker = row.get("marker")
        if row["expect"] != "refuse" or not marker:
            continue
        probe = os.path.join(work, "live-" + row["id"])
        os.makedirs(probe)
        populate(probe)
        try:
            subprocess.run([str(a) for a in row["command"]], cwd=probe,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        except OSError as exc:
            premise_failed("`%s` could not be executed at all (%s), so its payload was never "
                           "live and its absence under the gate proves nothing"
                           % (row["id"], exc.__class__.__name__))
        if not os.path.exists(os.path.join(probe, marker)):
            premise_failed("`%s` left no %s when run directly, so the payload is inert for some "
                           "reason of its own and the gated run's empty directory is not evidence"
                           % (row["id"], marker))
    out.write("  premise held: every refusal payload was executed once in a throwaway directory "
              "and left its marker there, so its absence below is the gate's doing.\n")

    # --- the assertions ---------------------------------------------------
    for row in rows:
        sandbox = os.path.join(work, "repo-" + row["id"])
        os.makedirs(sandbox)
        populate(sandbox)
        config = (skeleton
                  .replace("@@ALLOW@@", "true" if row["allow_repo_local_tools"] else "false")
                  .replace("@@REQUIRES@@", json.dumps(row["requires"]))
                  .replace("@@VERSION@@", json.dumps(row["version_command"]))
                  .replace("@@COMMAND@@", json.dumps(row["command"])))
        with open(os.path.join(sandbox, "checks.yaml"), "w") as fh:
            fh.write(config)
        proc = subprocess.run(
            ["bash", runner, "--config", os.path.join(sandbox, "checks.yaml"),
             "--root", sandbox, "--changed", os.path.join(sandbox, "changed.txt"),
             "--out", os.path.join(work, "result-" + row["id"] + ".json")],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        opt = "opt-in on" if row["allow_repo_local_tools"] else "opt-in off"
        shown = " ".join(str(a) for a in row["command"])
        if row["expect"] == "refuse":
            say(proc.returncode == 2,
                "%s [%s, %s] refused the config (exit 2, got %d): %s"
                % (row["id"], row["requirement"], opt, proc.returncode, row.get("why", "")))
            say(not os.path.exists(os.path.join(sandbox, row["marker"])),
                "%s [%s] executed nothing - `%s` left no %s"
                % (row["id"], row["requirement"], shown, row["marker"]))
        else:
            say(proc.returncode == 0,
                "%s [%s, %s] ran the config to a clean verdict (exit 0, got %d): %s"
                % (row["id"], row["requirement"], opt, proc.returncode, row.get("why", "")))
            if row.get("marker"):
                say(os.path.exists(os.path.join(sandbox, row["marker"])),
                    "%s [%s] actually executed - `%s` left its %s, so the opt-in opens the "
                    "gate rather than merely not closing it"
                    % (row["id"], row["requirement"], shown, row["marker"]))

with open(countfile, "a") as fh:
    fh.write("%d %d\n" % (EVALUATED, UPHELD))
out.write("  R18/R22 assertions evaluated: %d, upheld: %d\n" % (EVALUATED, UPHELD))
sys.exit(0 if ok else 1)
PY

ARGV_RC=0
if [ "$((WANT_R18 + WANT_R22))" -gt 0 ]; then
  # Not named GROUPS: bash keeps the caller's group ids in that name, and an
  # assignment to it is silently dropped. This check spent one run asserting
  # against a requirement id of "20".
  GRP=""
  if [ "$WANT_R18" = 1 ]; then GRP="R18"; fi
  if [ "$WANT_R22" = 1 ]; then GRP="${GRP:+$GRP,}R22"; fi
  python3 "$TMP/r18r22.py" "$RUNNER" "$FIXTURE" "$CASES" "$SKELETON" "$COUNTS" "$GRP" || ARGV_RC=$?
fi

# --- the verdict ----------------------------------------------------------
TOTAL_EVAL=0
TOTAL_UPHELD=0
while read -r ev up; do
  TOTAL_EVAL=$((TOTAL_EVAL + ev))
  TOTAL_UPHELD=$((TOTAL_UPHELD + up))
done < "$COUNTS"
printf '  total assertions evaluated: %d, upheld: %d\n' "$TOTAL_EVAL" "$TOTAL_UPHELD"

if [ "$R17_RC" = 2 ] || [ "$ARGV_RC" = 2 ]; then
  die_unmeasured "a premise did not hold, so the requirement it guards was never exercised; unmeasured, not a pass"
fi
if [ "$R17_RC" = 0 ] && [ "$ARGV_RC" = 0 ]; then
  printf '  P4 upheld across the groups selected: a repository being examined chose nothing that ran.\n'
  exit 0
fi
printf '  see the findings above. Each names the obligation it is about, not the mechanism that was supposed to meet it.\n'
exit 1
