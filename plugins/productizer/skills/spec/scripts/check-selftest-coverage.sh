#!/usr/bin/env bash
# check-selftest-coverage.sh [--version] [--help] [--root DIR] [--checks PATH]
#                           [--workflow PATH] [--no-probe] [--probe-timeout N]
#                           [--selftest]
#
# Asserts R39 and R40, which are two obligations over the same set and must not
# be collapsed:
#
#   R39  Every check tool shall carry a self-test that reaches each exit code
#        it can return.
#   R40  When the check suite runs, the lifecycle shall run the self-test of
#        every check tool it invokes.
#
# R39 obliges a self-test to EXIST. R40 obliges it to RUN. A tool that carries
# one nobody invokes satisfies the first and fails the second, and that is not
# hypothetical here: `check-acceptance-rows.sh --selftest` is a real corpus
# driver that no declared check and no workflow step reaches.
#
# THE SET THIS IS MEASURED OVER. "Check tool" is read as: a program the check
# suite invokes in order to reach a verdict. Two sources, both machine-read,
# neither guessed:
#
#   - every `command` argv in checks.yaml, for checks that are not switched off
#   - every token in a `run:` block of the workflow that resolves to a tracked
#     `.sh` or `.py` file in this repository
#
# The workflow half matters. `validate-spec.py` carries a self-test and is
# invoked by no declared check at all; reading checks.yaml alone would leave it
# out of the denominator and out of the numerator, and the shortfall would look
# smaller than it is.
#
# A TOOL THIS REPOSITORY DID NOT WRITE IS `n/a`, NOT A FINDING. `shellcheck` is
# a check tool the suite invokes and nobody here can add a self-test to it. It
# is counted, named, and rendered `n/a` with that reason, which is a shut guard
# and not a measurement of zero. Externals are reported separately from the
# repo-local shortfall so neither number contaminates the other.
#
# HOW "CARRIES A SELF-TEST" IS MEASURED, AND WHAT THAT MEASUREMENT IS WORTH.
# Structurally, on the tool's own source: a non-comment line that DISPATCHES on
# a self-test flag - a shell `case` pattern `--selftest)`, a `[ "$1" = --selftest ]`
# comparison, or an argparse `add_argument("--self-test"...)`. A line that only
# MENTIONS the flag does not count, and that distinction is load-bearing rather
# than fussy: `check-nothing-merged.sh` names `--selftest` in its header comment
# while its argument parser rejects it with exit 2, and a grep for the string
# reports it as covered.
#
# THE STRUCTURAL POSITIVES ARE THEN CONFIRMED BY EXECUTION. Every tool the
# scanner says carries a self-test is RUN with the flag it found, and the exit
# code is recorded. A tool whose parser rejects the flag - exit 2 with an
# unknown-option or unknown-argument line on stderr - is reported as NOT
# carrying one however its source reads, and the disagreement is printed. The
# structural negatives are NOT executed: running twenty-odd tools with a flag
# they do not know, on every suite run, buys a weaker signal than it costs. The
# consequence is written down under KNOWN LIMITATIONS rather than left to be
# discovered.
#
# R39's SECOND CLAUSE - "that reaches each exit code it can return" - IS NOW
# COUNTED, AND STILL NOT ENFORCED. It cannot be measured from the outside: what
# codes a self-test drove is known only to the self-test. So the tool half of
# the clause is a REPORTING PROTOCOL the self-test emits and this reader parses.
#
#   THE R39.b DECLARATION PROTOCOL. One line, any indentation, anywhere in the
#   self-test's output:
#
#       exit codes reached: 0 2 3 4 5 6   documented: 0 2 3 4 5 6
#
#   - the literal `exit codes reached:`, then the codes the cases actually
#     drove, then the literal `documented:`, then the codes the tool's own
#     contract says it can return;
#   - both halves are NON-EMPTY lists of non-negative integers separated by
#     spaces or commas, and nothing else may share the line - no prose, no
#     trailing sentence, no `and`;
#   - the reached half must be COMPUTED from the cases as they ran, not written
#     out as a literal. This reader cannot tell the difference and does not
#     pretend to; see NOT ASSERTED in the output.
#   - stdout is the stream to use. stderr is read too, because the probe
#     captures both.
#   - at most one such line per run. Two are ambiguous and read as unparsed.
#
#   THE SHAPE IS NOT INVENTED HERE. `retrieval-budget.sh --selftest` already
#   prints exactly this line, and printed it before anything read it, because a
#   tool documenting six exit codes had to prove its cases drove all six. The
#   only change is that the separator between the halves is now defined, and
#   that an empty or prose half is defined to be unreadable rather than zero.
#
#   THE `documented:` HALF IS WHAT MAKES THE LINE A MEASUREMENT. Twenty
#   self-tests in this repository already print `exit codes reached: 0, 1 and
#   2 - the whole contract.` - a hardcoded literal with nothing to check it
#   against, which is a claim wearing a measurement's clothes. Those lines do
#   not parse, deliberately, and are reported `unparsed`.
#
# WHAT THIS READER DOES WITH IT, AND WHAT IT REFUSES TO DO. It counts three
# things separately and never adds them up: how many self-tests DECLARE, how
# many of those declarations are COMPLETE - every documented code reached - and
# how many were NOT ASKED, because they emit no declaration. A tool that does
# not declare has NOT been shown incomplete. It reads `not asked`, never 0, and
# no exit code of this check rests on any of those figures. Making the gap
# visible and counted is the product; enforcing it would turn 32 unasked
# questions into 32 false findings on the day the reader shipped.
#
# HOW "IS RUN" IS MEASURED. A self-test is REACHED when the tool path and the
# flag both appear in one declared check's `command` argv, or on one line of a
# workflow `run:` block. That is a static reading of the two files that decide
# what executes, not an observation of an execution. A check that runs but
# whose failure is swallowed is not a check, so the propagation half is
# measured too: for a declared check, no non-zero code may sit in
# `exit_codes.pass`; for the workflow, no `continue-on-error` and no `|| ` on
# the invoking line.
#
# FOUR RENDERINGS, KEPT APART. `0` is a measured count. `n/a` is a guard that
# does not apply - an external tool, or an answered/reached column for a tool
# with no self-test to answer or reach. `-` is never run - the probe was
# switched off with --no-probe. `?` is unreadable - a file that could not be
# read, or a probe that timed out. None of them is written as a zero, because a
# tool nobody could read is not a tool with no self-test.
#
# THIS FILE IS MEASURED LIKE EVERY OTHER, AND IT CARRIES NO SELF-EXEMPTION. It
# has a `--selftest`, and the check declared over it in checks.yaml invokes the
# measurement rather than the self-test, so this tool appears in its own output
# as a carried self-test that nothing reaches - one of the R40 findings. That
# is the correct reading of R40 and it is left standing deliberately: a
# verifier that writes itself out of its own denominator is the defect this
# whole stage exists to refuse.
#
# NOTHING FROM THE FILES IT READS IS QUOTED BACK. Findings name a path, a flag
# and a check id. `why` prose, exemption reasons and workflow text are repo
# text and this output is tailed into a committed result file.
#
# PATHS ARE PRINTED RELATIVE to the work tree, so no absolute path - which is
# somebody's home directory - reaches a committed file.
#
# ONE BARE PATH PER LINE, unindented, for every file the verdict rests on: the
# two config files and every repo-local tool examined. The runner reads those
# as coverage and calls a clean exit having examined nothing HOLLOW. Assertions
# and the table are INDENTED.
#
# PORTABILITY. macOS/BSD bash. No mapfile, no `grep -P`, no GNU in-place sed.
# The measurement is done in python3, which the runner already requires.
#
# KNOWN LIMITATIONS, written down rather than discovered later:
#   - R39's "reaches each exit code it can return" is COUNTED, not asserted.
#     A declaration is the self-test's own account of its run: this reader
#     checks the two halves against each other, and cannot tell a computed
#     reached-list from a literal one. A tool that documents fewer codes than
#     it can return declares a complete run over an incomplete contract, and
#     that reads `complete` here.
#   - The count is over the tools that answer a self-test flag. A tool with no
#     self-test contributes to the R39 shortfall and is `n/a` for R39.b - one
#     shortfall, counted once.
#   - The structural negatives are never executed, so a tool that dispatches a
#     self-test in a shape this scanner does not recognise reads as carrying
#     none. That direction is the safe one - it over-reports the shortfall -
#     but it is still a wrong line in the table.
#   - Reachability is read off checks.yaml and the workflow. A self-test
#     invoked from somewhere else - a Makefile, a git hook, a human - is
#     invisible, and a declared check whose tool is missing at run time reads
#     as reached here while running nothing.
#   - The workflow is parsed as YAML and its `run:` blocks are scanned by
#     token. A tool invoked through a variable, a wrapper or a shell function
#     is not seen.
#   - It reads ONE checks.yaml and ONE workflow file. A second workflow that
#     runs checks is outside the measurement.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every repo-local check tool carries a self-test, and every self-test
#      found is reached by a declared check or by the workflow with its failure
#      still able to set the run's exit code
#   1  at least one does not - reported by path, with which half failed
#   2  COULD NOT MEASURE - bad usage, no python3, no PyYAML, a checks.yaml or a
#      workflow that could not be read or parsed, or a checks.yaml that
#      declares no checks. Never confused with 0.
#
# NO R39.b FIGURE SETS ANY OF THEM. A tool that declares an incomplete run, one
# that declares nothing and one whose declaration will not parse all leave the
# exit code where it was. The figure is reported; the clause is not enforced.
#
# Under --selftest the same three mean: every case produced the exit code it
# declares AND this self-test drove every code the contract above documents
# (0), a case did not or a documented code was never driven (1), and the corpus
# could not be driven at all (2).
set -euo pipefail

VERSION="check-selftest-coverage 1.0"

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

ROOT=""
CHECKS=".claude/productizer/checks.yaml"
WORKFLOW=".github/workflows/checks.yml"
PROBE=1
PROBE_TIMEOUT=30
MODE="measure"

die_unmeasured() { printf 'check-selftest-coverage: %s\n' "$1" >&2; exit 2; }

usage() {
  printf 'usage: check-selftest-coverage.sh [--version] [--help] [--root DIR]\n'
  printf '                                  [--checks PATH] [--workflow PATH]\n'
  printf '                                  [--no-probe] [--probe-timeout N] [--selftest]\n'
  printf '  --root DIR         the work tree. Defaults to the git top level, never\n'
  printf '                     to the working directory.\n'
  printf '  --checks PATH      the declared checks, relative to --root.\n'
  printf '  --workflow PATH    the CI workflow that runs the suite, relative to --root.\n'
  printf '  --no-probe         do not execute the self-tests found. The answered\n'
  printf '                     column then reads - (never run), never 0.\n'
  printf '  --probe-timeout N  seconds one self-test may take. A timeout is ?, not a\n'
  printf '                     failure and not a pass.\n'
  printf '  --selftest         drive the built-in corpus instead of this repository.\n'
  printf 'exit: 0 every tool carries a self-test and every self-test is run\n'
  printf '      1 at least one does not - 2 could not measure\n'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)     [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";     ROOT="$2";     shift 2 ;;
    --root=*)   ROOT="${1#--root=}";         shift ;;
    --checks)   [ "$#" -ge 2 ] || die_unmeasured "--checks needs a path";   CHECKS="$2";   shift 2 ;;
    --checks=*) CHECKS="${1#--checks=}";     shift ;;
    --workflow) [ "$#" -ge 2 ] || die_unmeasured "--workflow needs a path"; WORKFLOW="$2"; shift 2 ;;
    --workflow=*) WORKFLOW="${1#--workflow=}"; shift ;;
    --no-probe) PROBE=0; shift ;;
    --probe-timeout)   [ "$#" -ge 2 ] || die_unmeasured "--probe-timeout needs a number"; PROBE_TIMEOUT="$2"; shift 2 ;;
    --probe-timeout=*) PROBE_TIMEOUT="${1#--probe-timeout=}"; shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --) shift; break ;;
    -*) printf 'check-selftest-coverage: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *)  printf 'check-selftest-coverage: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1"

case "$PROBE_TIMEOUT" in
  ''|*[!0-9]*) die_unmeasured "--probe-timeout must be a whole number of seconds, got: $PROBE_TIMEOUT" ;;
esac
[ "$PROBE_TIMEOUT" -gt 0 ] || die_unmeasured "--probe-timeout must be greater than zero"

# The existence test's only stderr is noise about a question the exit status
# already answers; check-stderr.sh exempts this shape structurally.
command -v python3 >/dev/null 2>&1 \
  || die_unmeasured "python3 is not installed, so neither file was ever parsed"

# The work tree, never the working directory. A check rooted at wherever it
# happened to be invoked from reads different files depending on the caller and
# answers confidently either way.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" \
    || die_unmeasured "no --root given and this is not a git work tree"
fi
[ -d "$ROOT" ] || die_unmeasured "--root is not a directory: $ROOT"
ROOT="$(cd -P "$ROOT" && pwd -P)" \
  || die_unmeasured "cannot resolve --root to an absolute path"

MEASURE="$HERE/selftest-coverage.py"
[ -f "$MEASURE" ] && [ -r "$MEASURE" ] \
  || die_unmeasured "no selftest-coverage.py beside this script, so nothing could be measured"

run_measure() {
  # $1 root, $2 checks path, $3 workflow path
  local args
  args=(--root "$1" --checks "$2" --workflow "$3" --probe-timeout "$PROBE_TIMEOUT")
  if [ "$PROBE" -eq 0 ]; then
    args+=(--no-probe)
  fi
  python3 "$MEASURE" "${args[@]}"
}

if [ "$MODE" = "measure" ]; then
  RC=0
  run_measure "$ROOT" "$CHECKS" "$WORKFLOW" || RC=$?
  exit "$RC"
fi

# ---------------------------------------------------------------------------
# --selftest. Three cases, one per exit code this tool can return, each built
# in a sandbox so nothing here reads or writes the repository under test.
#
# The clean case GUARDS THE OTHERS' PREMISE. If it does not exit 0, the red
# cases prove nothing - they would be red for whatever is wrong with the clean
# one - so a clean case that is not clean is exit 2 for the whole selftest and
# never a pass on the cases that followed.
# ---------------------------------------------------------------------------
SB="$(mktemp -d "${TMPDIR:-/tmp}/check-selftest-coverage.XXXXXX")" \
  || die_unmeasured "could not create a sandbox, so no case was driven"
trap 'rm -rf "$SB"' EXIT HUP INT TERM

# EACH CASE ASSERTS ITS OWN SENTENCE, NOT ONLY ITS EXIT CODE. Three of the
# findings this tool can report share exit 1 - a tool with no self-test, a
# self-test nothing runs, and a self-test whose failure is swallowed - so a
# corpus reading exit codes alone cannot tell them apart. That is not
# theoretical: removing the rule that a self-test must be DISPATCHED on rather
# than merely mentioned turned one R39 finding into an R40 finding, and an
# exit-code-only corpus stayed green through it. Found by falsifying, not by
# reading.
mk_tools() {
  # $1 case dir. Four tools, differing in exactly one way each.
  local d="$1"
  mkdir -p "$d/tools" "$d/.github/workflows"

  # carries a real self-test
  cat > "$d/tools/with-selftest.sh" <<'TOOL'
#!/usr/bin/env bash
case "${1:-}" in
  --selftest) printf '  fixture self-test held\n'; exit 0 ;;
  --version)  printf 'with-selftest 1.0\n'; exit 0 ;;
esac
exit 0
TOOL

  # NAMES --selftest in a comment and dispatches on nothing. The case that
  # separates a grep from a measurement.
  cat > "$d/tools/mention-only.sh" <<'TOOL'
#!/usr/bin/env bash
# Names the flag in a comment, and again below in a line that is NOT a comment.
# Neither is a dispatch: no case pattern, no comparison, no argument parser that
# would accept it. Both shapes are here because a scanner that only skips
# comments still reads the usage string as a self-test.
usage() { printf 'usage: mention-only.sh [--version]; --selftest is not a flag it takes\n'; }
case "${1:-}" in
  --version) printf 'mention-only 1.0\n'; exit 0 ;;
  -h|--help) usage; exit 0 ;;
esac
exit 0
TOOL

  # source reads as a dispatch, parser rejects the flag. The probe is what
  # settles it, and the probe is what runs.
  cat > "$d/tools/rejects-flag.sh" <<'TOOL'
#!/usr/bin/env bash
if [ "${1:-}" = "--selftest" ]; then
  printf 'rejects-flag: unknown option --selftest\n' >&2
  exit 2
fi
exit 0
TOOL

  # answers the flag, slowly. Drives the ? rendering against --probe-timeout.
  cat > "$d/tools/slow-selftest.sh" <<'TOOL'
#!/usr/bin/env bash
case "${1:-}" in
  --selftest) sleep 30; exit 0 ;;
esac
exit 0
TOOL

  # --- the three R39.b fixtures ---------------------------------------------
  # declares, and drove every code it documents.
  cat > "$d/tools/codes-complete.sh" <<'TOOL'
#!/usr/bin/env bash
case "${1:-}" in
  --selftest) printf '    exit codes reached: 0 1 2   documented: 0 1 2\n'; exit 0 ;;
esac
exit 0
TOOL

  # declares, and one documented code was never driven. THE FALSIFICATION: a
  # reader that only checks the line is PRESENT reports this one as covered.
  cat > "$d/tools/codes-missing.sh" <<'TOOL'
#!/usr/bin/env bash
case "${1:-}" in
  --selftest) printf '    exit codes reached: 0 1   documented: 0 1 2\n'; exit 0 ;;
esac
exit 0
TOOL

  # says something about exit codes in the prose shape twenty self-tests here
  # already use: a hardcoded list with nothing to check it against. Unparsed,
  # which is unmeasured - never compliant, and never a zero.
  cat > "$d/tools/codes-malformed.sh" <<'TOOL'
#!/usr/bin/env bash
case "${1:-}" in
  --selftest) printf '    exit codes reached: 0, 1 and 2 - the whole contract.\n'; exit 0 ;;
esac
exit 0
TOOL

  chmod +x "$d/tools/with-selftest.sh" "$d/tools/mention-only.sh" \
           "$d/tools/rejects-flag.sh" "$d/tools/slow-selftest.sh" \
           "$d/tools/codes-complete.sh" "$d/tools/codes-missing.sh" \
           "$d/tools/codes-malformed.sh"
  printf 'name: fixture\njobs:\n  checks:\n    steps:\n      - run: |\n          echo nothing\n' \
    > "$d/.github/workflows/checks.yml"
}

mk_case() { mkdir -p "$SB/$1"; mk_tools "$SB/$1"; }

# clean: one tool, it carries a self-test, and a declared check invokes it.
mk_case clean
cat > "$SB/clean/checks.yaml" <<'CFG'
version: 1
checks:
  - id: fixture-selftest
    command: [./tools/with-selftest.sh, --selftest]
CFG

# mention-only: the second tool NAMES the flag in a comment. R39 finding.
mk_case mention
cat > "$SB/mention/checks.yaml" <<'CFG'
version: 1
checks:
  - id: fixture-selftest
    command: [./tools/with-selftest.sh, --selftest]
  - id: fixture-mention
    command: [./tools/mention-only.sh]
CFG

# rejected: the source reads as a dispatch and the parser refuses the flag.
mk_case rejected
cat > "$SB/rejected/checks.yaml" <<'CFG'
version: 1
checks:
  - id: fixture-selftest
    command: [./tools/with-selftest.sh, --selftest]
  - id: fixture-rejects
    command: [./tools/rejects-flag.sh]
CFG

# unreached: the tool carries a self-test and nothing invokes it. R39 holds,
# R40 does not - the case the two requirements were split over.
mk_case unreached
cat > "$SB/unreached/checks.yaml" <<'CFG'
version: 1
checks:
  - id: fixture-measure-only
    command: [./tools/with-selftest.sh]
CFG

# swallowed: invoked, but the check declares its failure code as a pass, so the
# self-test cannot set the run's exit code.
mk_case swallowed
cat > "$SB/swallowed/checks.yaml" <<'CFG'
version: 1
checks:
  - id: fixture-swallowed
    command: [./tools/with-selftest.sh, --selftest]
    exit_codes:
      pass: [0, 1]
CFG

# timeout: a self-test that does not answer inside the budget is ?, and ? is
# unmeasured. Never a tool reported as carrying none.
mk_case timeout
cat > "$SB/timeout/checks.yaml" <<'CFG'
version: 1
checks:
  - id: fixture-slow
    command: [./tools/slow-selftest.sh, --selftest]
CFG

# unmeasured: a checks.yaml that declares no checks. Nothing to measure over,
# which is exit 2 and never a clean run over an empty set.
mk_case unmeasured
cat > "$SB/unmeasured/checks.yaml" <<'CFG'
version: 1
checks: []
CFG

# unparseable: a checks.yaml that is not YAML at all.
mk_case unparseable
printf 'checks: [ this is not\n  - valid: yaml: at all\n' > "$SB/unparseable/checks.yaml"

# absent: no checks.yaml on disk.
mk_case absent
rm -f "$SB/absent/checks.yaml"

# no-probe: the clean tree with the probe switched off. The answered column
# must read "never run", and the run must say so in words.
mk_case noprobe
cp "$SB/clean/checks.yaml" "$SB/noprobe/checks.yaml"

# codes: the R39.b protocol, all four states in one tree - one self-test that
# declares and is complete, one that declares and is INCOMPLETE, one whose line
# does not parse, and one that says nothing at all. The whole case must exit 0:
# R39.b is counted, and a tool that never declared has not been shown
# incomplete, so none of this may turn into a finding.
mk_case codes
cat > "$SB/codes/checks.yaml" <<'CFG'
version: 1
checks:
  - id: fixture-selftest
    command: [./tools/with-selftest.sh, --selftest]
  - id: fixture-codes-complete
    command: [./tools/codes-complete.sh, --selftest]
  - id: fixture-codes-missing
    command: [./tools/codes-missing.sh, --selftest]
  - id: fixture-codes-malformed
    command: [./tools/codes-malformed.sh, --selftest]
CFG

FAILED=0
CASES=0
# Every exit code a case actually produced, one per line. The R39.b line this
# self-test prints is COMPUTED from this, never written out as a literal - a
# hardcoded list is the claim the protocol exists to replace.
CODES_SEEN=""
drive() {
  # $1 case, $2 expected exit code, $3 expected sentence, $4.. extra argv
  local case_name="$1" want="$2" marker="$3"
  shift 3
  local rc=0
  python3 "$MEASURE" --root "$SB/$case_name" --checks checks.yaml \
    --workflow .github/workflows/checks.yml --probe-timeout "$PROBE_TIMEOUT" \
    "$@" > "$SB/$case_name.out" 2> "$SB/$case_name.err" || rc=$?
  CASES=$((CASES + 1))
  CODES_SEEN="${CODES_SEEN}${rc}
"
  local why=""
  [ "$rc" -eq "$want" ] || why="exit $rc, expected $want"
  # stdout AND stderr: a could-not-measure sentence is written to stderr, and a
  # corpus that only reads stdout cannot tell exit 2 for the declared reason
  # from exit 2 for some other one.
  #
  # BOTH FILES ARE HANDED TO grep DIRECTLY, NEVER PIPED INTO IT. `cat a b |
  # grep -q` under `set -o pipefail` reports 141 whenever grep matches early
  # enough to SIGPIPE the cat, and `if !` then reads that as NO MATCH. It is a
  # race on how much of the output is buffered, so it passed from a terminal
  # and failed the `swallowed` case the moment this script was run with its
  # stdout on a pipe - which is how the runner and this tool own probe run it.
  # Found by running it, not by reading it.
  if ! grep -q -- "$marker" "$SB/$case_name.out" "$SB/$case_name.err"; then
    [ -n "$why" ] && why="$why; "
    why="${why}its output does not say what it was supposed to say"
  fi
  if [ -z "$why" ]; then
    printf '  held: case %-12s exit %d, and said so - %s\n' "$case_name" "$rc" "$marker"
    return 0
  fi
  printf '  FINDING: case %-12s %s - expected: %s\n' "$case_name" "$why" "$marker"
  FAILED=$((FAILED + 1))
  return 0
}

printf 'selftest-coverage.py\n'
printf 'check-selftest-coverage.sh\n'

# The clean case GUARDS THE OTHERS' PREMISE. If it does not exit 0 and say so,
# every red case below would be red for that reason instead of its own, and
# nothing would have been measured.
CLEAN_RC=0
python3 "$MEASURE" --root "$SB/clean" --checks checks.yaml \
  --workflow .github/workflows/checks.yml --probe-timeout "$PROBE_TIMEOUT" \
  > "$SB/clean.out" 2> "$SB/clean.err" || CLEAN_RC=$?
if [ "$CLEAN_RC" -ne 0 ] || ! grep -q 'R39 and R40 hold' "$SB/clean.out"; then
  printf '  the clean case exited %d and did not report both requirements holding.\n' "$CLEAN_RC"
  die_unmeasured "the corpus premise did not hold; unmeasured, not a pass"
fi
printf '  held: case %-12s exit 0, and said so - R39 and R40 hold\n' "clean"
CASES=$((CASES + 1))
CODES_SEEN="${CODES_SEEN}0
"

drive mention     1 "mention-only.sh carries no self-test"
drive rejected    1 "its parser rejected the flag"
drive unreached   1 "no declared check or workflow step invokes it"
drive swallowed   1 "cannot set the run's exit code"
drive timeout     2 "timed out after"                                    --probe-timeout 1
drive unmeasured  2 "declares no checks"
drive unparseable 2 "not parseable YAML"
drive absent      2 "could not be read"
drive noprobe     0 "probe: not run"                                     --no-probe

# The R39.b protocol, driven over the four states a declaration can be in. All
# three cases are exit 0: non-compliance is a figure this check reports, never
# a finding it fails on.
drive codes       0 "R39.b: 2 of 4 check tools carrying a self-test declare"
drive codes       0 "codes-missing.sh documents 0 1 2 and never reached 2"
drive codes       0 "1 emit a line this protocol could not parse"

printf '  cases driven: %d. Cases that did not hold: %d\n' "$CASES" "$FAILED"

# This tool's own R39.b declaration, in the protocol it defines. The reached
# half is computed from the cases above; the documented half is the contract in
# this file's header.
REACHED="$(printf '%s' "$CODES_SEEN" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
MISSING=""
for want in 0 1 2; do
  printf '%s' "$CODES_SEEN" | grep -qx "$want" || MISSING="$MISSING $want"
done
printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"

if [ "$FAILED" -ne 0 ]; then
  printf 'FAIL: %d selftest case(s) did not produce the exit code and the sentence they declare.\n' "$FAILED" >&2
  exit 1
fi
if [ -n "$MISSING" ]; then
  printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
  exit 1
fi
printf '  R39 for this tool: the self-test exists, drove every exit code its contract documents, and each case asserts which finding it produced.\n'
exit 0
