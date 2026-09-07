#!/usr/bin/env bash
# check-cannot-run-coverage.sh [--root DIR] [--fixture DIR] [--runner PATH]
#                              [--selftest|--self-test] [--version] [--help]
#
# A CHECK THAT REACHED NO VERDICT MUST RECORD NO COVERAGE COUNT.
#
# R26 and P1. This is the sibling of `no-fabricated-zero`, and it exists because
# that check's seventh assertion - sweep every cannot-run row for a recorded
# coverage count - had been sweeping an EMPTY SET since the day it was written.
# Its fixture produces only a `missing_tool` row, and `missing_tool` is the one
# status that never carried a coverage block. The assertion was correct and had
# never once seen the thing it was looking for.
#
# Measured, not argued: on the runner before this fixture existed, four of the
# five cannot-run statuses recorded `covered: 0`.
#
#   timeout        a scanner killed at its limit, before it printed anything
#   no_version     a tool that could not say what it was
#   refused        a command the runner would not run
#   unmapped_exit  a code the check's own map does not cover
#   missing_tool   the only clean one
#
# A killed scanner printed nothing. Nothing is not zero. A month later that 0
# reads exactly like a real one, and nobody can tell which they are looking at.
#
# WHAT IT ASSERTS. Two things, separately.
#
#   1. No row whose status means "no verdict" carries a `coverage` key at all.
#      Absent, not null and not zero - matching what the runner already does for
#      `missing_tool`, so no third convention is invented.
#   2. A check that RAN and genuinely covered nothing still records its zero.
#      That is a measurement and deleting it would be the same bug inverted.
#      The fixture carries such a check specifically so this cannot regress.
#
# THE PREMISE IS GUARDED, AND IT IS THE POINT. The fixture must actually produce
# a cannot-run row by a mechanism OTHER than an absent tool - otherwise this is
# just the existing fixture again and the empty-set problem is unfixed. If every
# cannot-run row is a `missing_tool`, or there is no cannot-run row at all, the
# case was never tested: exit 2, unmeasured, never a pass.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  no cannot-run row records coverage, and the measured zero survived
#   1  a check that reached no verdict recorded a coverage count
#   2  could not run - no fixture, no runner, an unreadable result, or a premise
#      that did not hold
#
# Under --selftest the same three mean: every case produced the exit code this
# contract declares for it (0), at least one did not (1), and the corpus could
# not be built at all (2). `--self-test` is accepted as an alias, because this
# repository spells the flag both ways and a tool that answers only one
# spelling has a self-test the next caller cannot find.
#
# WHAT IT PRINTS. One BARE repo-relative path per file examined, which is what
# the runner parses as coverage. Findings and notes are INDENTED. Nothing
# absolute is printed: this text is tailed into a committed result file.
set -euo pipefail

VERSION="check-cannot-run-coverage 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=""; FIXTURE=""; RUNNER=""; SELFTEST=""

die_unmeasured() { printf 'check-cannot-run-coverage: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)      [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)    ROOT="${1#--root=}";       shift ;;
    --fixture)   [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2"; shift 2 ;;
    --fixture=*) FIXTURE="${1#--fixture=}"; shift ;;
    --runner)    [ "$#" -ge 2 ] || die_unmeasured "--runner needs a path";  RUNNER="$2";  shift 2 ;;
    --runner=*)  RUNNER="${1#--runner=}";   shift ;;
    --selftest|--self-test) SELFTEST=1; shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1." ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1."


# --------------------------------------------------------------- --selftest
#
# R39 - EVERY CHECK TOOL SHALL CARRY A SELF-TEST THAT REACHES EACH EXIT CODE IT
# CAN RETURN. All three of this file's are reachable and all three are driven
# below.
#
# THE FINDING CASE NEEDS A RUNNER THAT MISBEHAVES, and the real one does not -
# which is the whole reason `--runner` exists as an option. Each case here
# points this check at a STUB runner written into a temporary directory: one
# that records a coverage count on a row that reached no verdict (the defect
# this check was built for), one that records only `missing_tool` rows (the
# empty set this check exists to fill, which is a premise failure and not a
# pass), one that deletes the honest zero (the same bug inverted), and one that
# writes nothing at all. The stub is where the defect lives because the defect
# is a property of what a runner RECORDS, and this check's whole subject is the
# result file rather than the exit code that produced it.
#
# Nothing is written into the repository. The corpus is removed on every exit
# path, signal included.
if [ -n "$SELFTEST" ]; then
  SELF_TMP="$(mktemp -d)" || {
    printf 'check-cannot-run-coverage: cannot create a temporary directory to build the self-test corpus in. Unmeasured, not a pass.\n' >&2
    exit 2; }
  trap 'rm -rf "$SELF_TMP"' EXIT HUP INT TERM

  mkdir -p "$SELF_TMP/fixture"
  : > "$SELF_TMP/fixture/checks.yaml"
  : > "$SELF_TMP/fixture/changed.txt"

  # write_stub <name> <json body> - a runner that ignores every argument but
  # --out and writes the result this case needs the check to read.
  write_stub() {
    stub="$SELF_TMP/$1-runner.sh"
    cat > "$stub" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$out" ] || exit 2
cat > "$out" < "$0.json"
exit 3
STUB
    printf '%s' "$2" > "$stub.json"
    printf '%s\n' "$stub"
  }

  # A `timeout` row - no verdict - carrying a coverage count nobody measured,
  # beside a check that ran and recorded a real one. This is the defect.
  OFFENDER_JSON='{"checks":[{"id":"killed","status":"timeout","coverage":{"observed":{"covered":0}}},{"id":"ran","status":"pass","coverage":{"observed":{"covered":2}}}]}'
  # The same result with the offending key removed: clean.
  CLEAN_JSON='{"checks":[{"id":"killed","status":"timeout"},{"id":"ran","status":"pass","coverage":{"observed":{"covered":2}}}]}'
  # A cannot-run row by the ONE mechanism that never carried a coverage block.
  # The premise does not hold and the run must refuse rather than pass.
  MISSING_ONLY_JSON='{"checks":[{"id":"absent","status":"missing_tool"},{"id":"ran","status":"pass","coverage":{"observed":{"covered":2}}}]}'
  # No cannot-run row at all: same premise failure, different way in.
  NO_CANNOT_JSON='{"checks":[{"id":"ran","status":"pass","coverage":{"observed":{"covered":2}}}]}'
  # No rows at all.
  EMPTY_JSON='{"checks":[]}'
  # The mirror image: nothing records a coverage count, including the check
  # that RAN. Deleting a measured zero is this same bug pointed the other way.
  NO_HONEST_JSON='{"checks":[{"id":"killed","status":"timeout"},{"id":"ran","status":"pass"}]}'

  SELF_CASES=0
  SELF_UPHELD=0
  # R39.b: the reached half of the declaration below is ACCUMULATED here, one
  # entry per case as it ran. A literal list would satisfy the reader and prove
  # nothing. Every case in this mode - the stub-driven ones and the four driven
  # inline below - reaches `record`, so `record` is where the code is captured.
  CODES=""

  # The exit code is captured into a variable on the SAME LINE as the command.
  # A command substitution in an argument list resets $?, so reading the status
  # inside the call below would report the status of the call.
  record() { # <case> <expected> <observed> <what the case is>
    SELF_CASES=$((SELF_CASES + 1))
    CODES="$CODES$3
"
    if [ "$3" = "$2" ]; then
      SELF_UPHELD=$((SELF_UPHELD + 1)); verdict="held"
    else
      verdict="NOT HELD"
    fi
    printf '      %-28s expected %s  got %s  %s  %s\n' "$1" "$2" "$3" "$verdict" "$4"
  }

  drive() { # <case> <expected> <stub json> <what the case is>
    stub="$(write_stub "$1" "$3")"
    got=0
    bash "$0" --fixture "$SELF_TMP/fixture" --runner "$stub" \
      > "$SELF_TMP/$1.out" 2> "$SELF_TMP/$1.err" || got=$?
    record "$1" "$2" "$got" "$4"
  }

  printf '    selftest: %s\n' "$VERSION"

  # The committed fixture and the real runner: the case this check runs on
  # every CI invocation, driven here so a green self-test is not green over
  # stubs alone.
  got=0
  bash "$0" > "$SELF_TMP/real.out" 2> "$SELF_TMP/real.err" || got=$?
  record real-fixture 0 "$got" "the committed timeout-zero fixture through the real runner"

  drive clean 0 "$CLEAN_JSON" \
    "a row with no verdict carries no coverage key, and the measured zero survives"
  drive coverage-on-no-verdict 1 "$OFFENDER_JSON" \
    "a killed check recorded a count nobody measured"
  drive honest-zero-deleted 1 "$NO_HONEST_JSON" \
    "the mirror image: a check that RAN records no coverage at all"
  drive premise-missing-tool-only 2 "$MISSING_ONLY_JSON" \
    "the only cannot-run row is missing_tool, so the empty set is still empty"
  drive premise-no-cannot-run 2 "$NO_CANNOT_JSON" \
    "no row reached no verdict, so nothing was exercised"
  drive premise-no-rows 2 "$EMPTY_JSON" \
    "the result records no checks at all"

  got=0
  bash "$0" --fixture "$SELF_TMP/no-such-fixture" \
    > "$SELF_TMP/nofix.out" 2> "$SELF_TMP/nofix.err" || got=$?
  record missing-fixture 2 "$got" "the standing case is not there, which is unmeasured"

  got=0
  bash "$0" --runner "$SELF_TMP/no-such-runner.sh" \
    > "$SELF_TMP/norun.out" 2> "$SELF_TMP/norun.err" || got=$?
  record missing-runner 2 "$got" "there is no runner to drive"

  got=0
  bash "$0" --not-a-real-option > "$SELF_TMP/badopt.out" 2> "$SELF_TMP/badopt.err" || got=$?
  record unknown-option 2 "$got" "bad usage is refused, never answered"

  got=0
  bash "$0" --fixture > "$SELF_TMP/noval.out" 2> "$SELF_TMP/noval.err" || got=$?
  record option-without-value 2 "$got" "an option missing its argument is refused"

  if [ "$SELF_CASES" = "$SELF_UPHELD" ]; then self_verdict="held"; else self_verdict="NOT HELD"; fi
  printf '    R39  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$SELF_CASES" "$SELF_UPHELD" "$self_verdict" \
    "each case exits with the code this file's contract declares for it"
  # The R39.b declaration. The reached half is computed from the cases above;
  # the documented half is the contract in this file's header.
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  printf '    NOT ASSERTED: the WORDING of any finding, and the exit code of the runner itself, which this check deliberately does not read. A case that went red for the wrong reason is invisible here.\n'
  [ "$SELF_CASES" = "$SELF_UPHELD" ] || exit 1
  # A documented code nothing drove is the gap R39.b exists to make visible, so
  # it ends the run rather than being printed past.
  if [ -n "$MISSING" ]; then
    printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  exit 0
fi

[ -n "$FIXTURE" ] || FIXTURE="$HERE/../fixtures/timeout-zero"
[ -d "$FIXTURE" ] || die_unmeasured "no fixture directory; the standing case is missing, which is unmeasured and not a pass"
[ -n "$RUNNER" ]  || RUNNER="$HERE/run-checks.sh"
[ -f "$RUNNER" ]  || die_unmeasured "no runner to drive; nothing was measured"
# Canonicalise both. Without this a default fixture path carries its `..`
# segment into the coverage lines, and the runner parses those lines as the
# files this check examined - a path it cannot match is a path it counts as
# uncovered.
FIXTURE="$(cd "$FIXTURE" && pwd -P)"
RUNNER="$(cd "$(dirname "$RUNNER")" && pwd -P)/$(basename "$RUNNER")"
command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the result could not be read"

rel() {
  case "$1" in
    "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;;
    *)         printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;;
  esac
}
if [ -z "$ROOT" ]; then ROOT="$(git rev-parse --show-toplevel)" || ROOT=""; fi
[ -z "$ROOT" ] || ROOT="$(cd "$ROOT" && pwd -P)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rel "$RUNNER"
rel "$FIXTURE/checks.yaml"
rel "$FIXTURE/changed.txt"

# The runner is EXPECTED to refuse here - the fixture contains a check that
# cannot reach a verdict, and refusing is the correct response to that. Its exit
# code is not the thing under test; what it RECORDED is.
bash "$RUNNER" --config "$FIXTURE/checks.yaml" --root "$FIXTURE" \
  --changed "$FIXTURE/changed.txt" --out "$TMP/res.json" > "$TMP/out" 2> "$TMP/err" || :
[ -s "$TMP/res.json" ] || die_unmeasured "the runner wrote no result, so nothing about what it records was measured"

python3 - "$TMP/res.json" <<'PY'
import json
import sys

# The runner's own list of statuses meaning "this check reached no verdict".
# `nothing_to_examine` added 2026-09-07 with run-checks 2.x: every path in a
# per-file check's scope was gone from the tree, so no tool was invoked at all.
# It is a run that could not happen, not a run that found nothing. This set is a
# SECOND COPY of the runner's own - they must be changed together, and a status
# the runner can emit that is missing here reads as "ran" to this check.
CANNOT_RUN = {"missing_tool", "timeout", "no_version", "refused", "unmapped_exit",
              "nothing_to_examine"}

out = sys.stdout
try:
    with open(sys.argv[1], errors="replace") as fh:
        res = json.load(fh)
except (OSError, ValueError) as exc:
    out.write("  the runner's result could not be read: %s\n" % type(exc).__name__)
    out.write("  assertions evaluated: 0 of 2. Unmeasured, not a pass.\n")
    sys.exit(2)

rows = res.get("checks") or []
if not rows:
    out.write("  PREMISE did not hold - the result records no checks at all\n")
    out.write("  R26 was not exercised. Unmeasured, not a pass.\n")
    sys.exit(2)

cannot = [r for r in rows if r.get("status") in CANNOT_RUN]
other_mechanism = [r for r in cannot if r.get("status") != "missing_tool"]
ran = [r for r in rows if r.get("status") not in CANNOT_RUN]

# THE PREMISE. Without a cannot-run row produced by something other than an
# absent tool, this is the existing fixture again and the empty set stays empty.
if not other_mechanism:
    out.write("  PREMISE did not hold - the fixture produced no cannot-run row other than "
              "`missing_tool`, which is the one status that never carried a coverage block. "
              "The empty set this check exists to fill is still empty.\n")
    out.write("  R26 was not exercised. Unmeasured, not a pass.\n")
    sys.exit(2)

out.write("  premise held: %d row(s) reached no verdict by a mechanism other than an absent tool (%s).\n"
          % (len(other_mechanism), ", ".join(sorted({r["status"] for r in other_mechanism}))))

upheld = 0
evaluated = 0
findings = []


def say(held, text):
    global upheld, evaluated
    evaluated += 1
    if held:
        upheld += 1
        out.write("  held: %s\n" % text)
    else:
        findings.append(text)
        out.write("  FINDING: did not hold - %s\n" % text)


for r in cannot:
    out.write("  %-16s status=%-14s coverage key present: %s\n"
              % (r.get("id", "?"), r.get("status"), "coverage" in r))

offenders = ["%s records covered=%r"
             % (r.get("id"), (r.get("coverage") or {}).get("observed", {}).get("covered"))
             for r in cannot if "coverage" in r]
say(not offenders,
    "1 no row that reached no verdict records a coverage count%s"
    % ("" if not offenders else "; offenders: " + "; ".join(offenders)))

# THE MIRROR IMAGE. A check that RAN and covered nothing measured a real zero,
# and deleting that would be this same bug pointed the other way.
measured = [r for r in ran if "coverage" in r]
say(bool(measured),
    "2 a check that ran still records its coverage (%d row(s) that reached a verdict carry one)"
    % len(measured))

out.write("  assertions evaluated: %d, upheld: %d\n" % (evaluated, upheld))
if findings:
    out.write("  R26 not satisfied: a check that reached no verdict recorded a count nobody measured.\n")
    sys.exit(1)
out.write("  R26 satisfied for the cannot-run path: no verdict, no count; and a measured zero survives.\n")
PY
