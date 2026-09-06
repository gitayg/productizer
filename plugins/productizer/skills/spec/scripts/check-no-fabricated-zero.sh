#!/usr/bin/env bash
# check-no-fabricated-zero.sh [--root DIR] [--fixture DIR] [--version] [--help]
#                             [--selftest]
#
# Asserts R26: IF A VALUE COULD NOT BE MEASURED, THEN THE LIFECYCLE SHALL NOT
# RECORD IT AS ZERO. Enforces P1 - a value that was not measured is never
# recorded as a measurement.
#
# WHY THIS EXISTS SEPARATELY FROM R25. R25 - report it as unmeasured - is
# already asserted, and it is a different claim. A run can print
# `spec coverage: UNMEASURED` on the terminal and, in the same breath, write
# `units_total: 0` into the result file that every downstream reader parses.
# R25 passes on that run. R26 fails on it, and nobody notices, because the
# fabricated zero is the one failure in this product that is invisible: a month
# later it reads exactly like a real zero. So this check reads THE RESULT FILE
# and never the printed line. The printed line is R25's evidence, not R26's.
#
# WHAT IT DOES. It copies `fixtures/fabricated-zero/` into a temporary
# directory and runs run-checks.sh against that copy. The temporary copy is the
# point: the runner writes a result file inside the repository it is checking,
# and pointing it at this repository would make a test of the runner a writer
# to the tree under test.
#
# The fixture makes TWO values genuinely unmeasurable in one run, because the
# runner records them in two different shapes and R26 has to hold for both:
#
#   THE DENOMINATOR. `policy.spec` names a file that is not there, so the count
#   of active requirements cannot be derived. Its fields must come back NULL.
#
#   ONE CHECK'S OWN COVERAGE. The declared tool is absent, so the check never
#   ran. Its coverage block must be ABSENT from the row.
#
# ABSENT, NULL AND ZERO ARE THREE STATES, and collapsing them is the whole
# defect. Every field below is classified into one of them and the
# classification is printed, so a failure says which state the field is in
# rather than only that something was wrong.
#
# WHAT IT ASSERTS, AND WHY EACH ONE IS SEPARATE.
#
#   1  `spec_coverage.units_total` is null. This is the field a reader divides
#      by; 0 here makes every "n of m covered" line downstream read 0 of 0.
#   2  `spec_coverage.counts` is null, not an object of zeros. An object whose
#      every value is 0 is the most convincing fabrication available: it has
#      the shape of a real measurement.
#   3  `spec_coverage.units` is null, not an empty list. A list of length 0 is
#      a recorded count of zero requirements.
#   4  `spec_coverage.satisfied` is null, not a boolean. `true` over an
#      underived denominator is the hollow green this whole stage refuses.
#   5  `counts.spec_units_unsatisfied` is null. Separate from 1-4 because it
#      sits in a different object, written by different code, and a fix to one
#      does not fix the other.
#   6  the unmeasurable check's `coverage` key is ABSENT from its row - not
#      present carrying `observed.covered: 0`. Asserted as absence, not as
#      null, because that is what the runner actually does and a check that
#      accepted either would not notice the two being swapped.
#   7  a sweep over EVERY check row whose status means it could not run: none
#      of them records a coverage count. Assertion 6 names the one row this
#      fixture creates; this one holds for rows a later runner adds.
#
# THE PREMISES ARE CHECKED FIRST AND ARE NOT ASSERTIONS. If the fixture's tool
# turns out to be installed, or its absent spec turns out to be readable, then
# nothing was unmeasurable and R26 was never exercised. That is exit 2 - could
# not run - and never a pass.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every assertion held
#   1  an assertion failed - the runner records a fabricated zero where a value
#      could not be measured
#   2  could not run - bad usage, no fixture, no runner, no python3, an
#      unreadable result, or a premise that did not hold
#
# --SELFTEST DRIVES ALL THREE, AND IT REACHES 1 THE ONLY HONEST WAY: BY
# FABRICATING THE ZERO. Exit 1 here means "the runner recorded an unmeasurable
# value as 0", and while the runner is correct no fixture can produce that -
# a self-test built only out of fixtures would watch exit 0 forever and call
# it coverage. So the mode copies the scripts directory into `mktemp -d` and
# changes ONE token in the COPY: the `units_total` field the runner
# initialises to None for an underived denominator becomes 0. That is the
# defect this check exists to catch, written out in full, and it is the field
# every downstream "n of m covered" line divides by. The change is verified to
# have applied before the case is driven; a patch that matched nothing would
# otherwise turn into a second copy of the clean case.
#
# NOTHING IN THIS REPOSITORY IS EDITED. The fabrication lives in a temporary
# copy that is removed on every exit path, signal included.
#
# Under --selftest the three codes mean: every case produced the code it
# declares (0), at least one did not (1), and the cases could not be built or
# driven at all (2). `--self-test` is accepted as an alias because the repo
# spells it both ways.
#
# WHAT IT PRINTS. One BARE PATH per line for every file examined, relative to
# the repository, which is what the runner parses as coverage. Classifications
# and assertions are INDENTED. The runner's own stderr is NOT reproduced: it
# names the temporary directory it ran in, and this output is tailed into a
# committed result file where an absolute path is somebody's home directory
# published to everyone who clones the repo.
set -euo pipefail

VERSION="check-no-fabricated-zero 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$HERE")"

ROOT=""
FIXTURE="$SKILL/fixtures/fabricated-zero"
MODE="measure"

die_unmeasured() { printf 'check-no-fabricated-zero: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)       [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)     ROOT="${1#--root=}";       shift ;;
    --fixture)    [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2"; shift 2 ;;
    --fixture=*)  FIXTURE="${1#--fixture=}"; shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1" ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1"

# ---------------------------------------------------------------------------
# --selftest: drive this check against the committed fixture with the runner
# correct, and again with the fabricated zero written into a temporary copy of
# it. Nothing in this repository is edited.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  [ -d "$FIXTURE" ] \
    || die_unmeasured "no fixture directory, so the clean case has nothing to drive. Unmeasured, not a pass"
  SELFWORK="$(mktemp -d)" \
    || die_unmeasured "cannot create a temporary directory to build the cases in; nothing was driven"
  # Removed on every exit path, signal included.
  trap 'rm -rf "$SELFWORK"' EXIT HUP INT TERM

  CASES=0; UPHELD=0; REPORT=""
  REACHED_0=0; REACHED_1=0; REACHED_2=0

  # `|| GOT=$?` on the same line as the command. A `$(...)` in an argument list
  # and a pipeline both RESET `$?`, and reading the status one line later is
  # how a self-test comes to report a pass it never observed.
  drive() {
    NAME="$1"; WANT="$2"; WHY="$3"; shift 3
    GOT=0
    bash "$@" > "$SELFWORK/$NAME.out" 2> "$SELFWORK/$NAME.err" || GOT=$?
    CASES=$((CASES + 1))
    if [ "$GOT" = "$WANT" ]; then UPHELD=$((UPHELD + 1)); V="held"; else V="NOT HELD"; fi
    case "$GOT" in
      0) REACHED_0=1 ;;
      1) REACHED_1=1 ;;
      2) REACHED_2=1 ;;
    esac
    REPORT="$REPORT      $NAME  expected $WANT  got $GOT  $V  $WHY
"
  }

  # THE FABRICATING COPY. `$HERE` is copied whole because run-checks.sh is
  # found beside the check and reaches for its neighbours; a copy of one file
  # would be a different program.
  cp -R "$HERE" "$SELFWORK/scripts" \
    || die_unmeasured "could not copy the scripts directory, so the fabricated case could not be built"
  FABRICATING="$SELFWORK/scripts/run-checks.sh"
  [ -f "$FABRICATING" ] \
    || die_unmeasured "the copy has no run-checks.sh, so there is nothing to fabricate a zero in"
  cp "$FABRICATING" "$SELFWORK/run-checks.before" \
    || die_unmeasured "could not keep a copy of the runner to compare the fabrication against"
  # The defect, written out: an underived denominator recorded as a count of
  # zero requirements instead of as null.
  sed -e 's|"units_total": None, "counts": None|"units_total": 0, "counts": None|' \
    "$SELFWORK/run-checks.before" > "$FABRICATING" \
    || die_unmeasured "the deliberate fabrication could not be written"
  # A PATCH THAT MATCHED NOTHING IS THE CLEAN CASE WEARING A SECOND NAME. If
  # the field has moved, this run has not falsified anything and says so.
  if cmp -s "$SELFWORK/run-checks.before" "$FABRICATING"; then
    die_unmeasured "the deliberate fabrication changed nothing in the copied runner - the unmeasured \`units_total\` initialiser is no longer where this self-test looks for it. The fabricated case would have been a second copy of the clean one, which is unmeasured, not a pass"
  fi

  # A FIXTURE WHOSE PREMISE FAILS: the declared tool is `sh`, which is
  # installed, so the check ran and its coverage was measurable after all.
  cp -R "$FIXTURE" "$SELFWORK/present-tool" \
    || die_unmeasured "could not copy the fixture for the premise case"
  sed -e 's|requires: \[definitely-not-a-real-tool\]|requires: [sh]|' \
    "$FIXTURE/checks.yaml" > "$SELFWORK/present-tool/checks.yaml" \
    || die_unmeasured "could not write the premise case's config"
  if cmp -s "$FIXTURE/checks.yaml" "$SELFWORK/present-tool/checks.yaml"; then
    die_unmeasured "the premise case's config is unchanged - the fixture no longer declares \`definitely-not-a-real-tool\` in the shape this self-test edits, so the case would not have tested a tool that is present"
  fi

  # 0 - the runner as this repository ships it. Without this case every red
  # case below proves only that something is red.
  drive records-null 0 "the shipped runner, against the committed fixture" \
    "$0" --fixture "$FIXTURE"

  # 1 - the defect itself: the denominator nobody could derive, recorded as 0.
  drive fabricates-zero 1 "a copied runner whose unmeasured units_total is 0 rather than null" \
    "$SELFWORK/scripts/${0##*/}" --fixture "$FIXTURE"

  # 2 - the premise. A tool that turns out to be installed means the check ran
  # and nothing about it was unmeasurable.
  drive premise-not-met 2 "a fixture declaring a tool that IS installed" \
    "$0" --fixture "$SELFWORK/present-tool"

  # 2 - no fixture at all. The standing case missing is unmeasured, not a pass.
  drive absent-fixture 2 "no fixture directory at the path given" \
    "$0" --fixture "$SELFWORK/nowhere"

  # 2 - bad usage, reaching the same code through the argument parser.
  drive bad-usage 2 "an option this script does not take" "$0" --frobnicate

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"
  if [ "$CASES" = "$UPHELD" ]; then SELF_VERDICT="held"; else SELF_VERDICT="NOT HELD"; fi
  printf '    R39.s  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$CASES" "$UPHELD" "$SELF_VERDICT" \
    "each case exits with the code it declares"
  # `if`, not `[ ... ] && ...`: a false test as the last statement of a list is
  # a non-zero status, and `set -e` would end the run on the code that was NOT
  # reached - a self-test killed by its own summary line.
  REACHED=""
  if [ "$REACHED_0" = 1 ]; then REACHED="$REACHED 0"; fi
  if [ "$REACHED_1" = 1 ]; then REACHED="$REACHED 1"; fi
  if [ "$REACHED_2" = 1 ]; then REACHED="$REACHED 2"; fi
  printf '    exit codes this self-test reached:%s. The contract declares 0, 1 and 2; a code missing here is a code nothing drove\n' \
    "${REACHED:- none}"
  printf '    NOT ASSERTED: ONE of the seven assertions is falsified - assertion 1, units_total. The other six are not driven red here, so this says the check catches a fabricated denominator and not that it catches a fabricated counts object, units list, satisfied flag or coverage block\n'
  [ "$CASES" = "$UPHELD" ] || exit 1
  exit 0
fi

# The work tree, never the working directory. --root does not decide what is
# tested - the fixture and the runner are found beside this script, so the test
# is the same one wherever it is invoked from - it decides what the printed
# paths are relative to, so nothing absolute reaches the committed result.
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
[ -f "$RUNNER" ] || die_unmeasured "no run-checks.sh beside this script; there is nothing to test"
[ -d "$FIXTURE" ] || die_unmeasured "no fixture directory; the standing case is missing, which is unmeasured and not a pass"
[ -f "$FIXTURE/checks.yaml" ] || die_unmeasured "the fixture has no checks.yaml"
[ -f "$FIXTURE/changed.txt" ] || die_unmeasured "the fixture has no changed.txt"
command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the result could not be read"

rel() {
  case "$1" in
    "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;;
    *)         printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;;
  esac
}

# PREMISE ONE. The tool the fixture names must really be absent, or the check
# ran, examined something, and its coverage was measurable after all.
DECLARED_TOOL="$(sed -n 's/^ *requires: *\[\([^]]*\)\].*/\1/p' "$FIXTURE/checks.yaml" | head -1 | tr -d ' ')"
[ -n "$DECLARED_TOOL" ] || die_unmeasured "the fixture declares no tool to be absent"
if command -v "$DECLARED_TOOL" >/dev/null 2>&1; then
  die_unmeasured "the fixture's declared tool is installed on this machine, so a check that could not run was never tested. The premise failed; this is unmeasured, not a pass"
fi

# PREMISE TWO. The spec path the fixture names must really be missing from the
# sandbox, or the denominator was derivable and no unmeasured count existed.
DECLARED_SPEC="$(sed -n 's/^ *spec: *\([^ #][^#]*\)$/\1/p' "$FIXTURE/checks.yaml" | head -1 | sed 's/[[:space:]]*$//')"
[ -n "$DECLARED_SPEC" ] || die_unmeasured "the fixture names no spec path, so the denominator's premise cannot be established"
case "$DECLARED_SPEC" in
  /*) die_unmeasured "the fixture's spec path is absolute; it would name a different file on every machine" ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SANDBOX="$TMP/repo"
mkdir -p "$SANDBOX"
cp "$FIXTURE/checks.yaml" "$FIXTURE/changed.txt" "$SANDBOX/"
if [ -e "$SANDBOX/$DECLARED_SPEC" ]; then
  die_unmeasured "the fixture's spec path exists in the sandbox, so the coverage denominator was derivable and an unmeasured denominator was never tested. The premise failed; this is unmeasured, not a pass"
fi

rel "$RUNNER"
rel "$FIXTURE/checks.yaml"
rel "$FIXTURE/changed.txt"

RC=0
bash "$RUNNER" --config "$SANDBOX/checks.yaml" --root "$SANDBOX" \
  --changed "$SANDBOX/changed.txt" --out "$TMP/result.json" \
  > "$TMP/runner.out" 2> "$TMP/runner.err" || RC=$?

cat > "$TMP/assert.py" <<'PY'
"""Read what the runner recorded and say whether R26 still holds.

Reads the RESULT FILE. The printed stream is read only to report, without
asserting, whether R25's half is in the state that makes the two requirements
separable - which is the whole reason R26 needs its own check.

stdout: one indented line per classification and per assertion. Exit 0 all
held, 1 one did not, 2 the result could not be read or a premise did not hold -
neither of which is ever reported as a pass.
"""
import json
import sys

result_path, err_path, check_id = sys.argv[1:4]
out = sys.stdout
ok = True

UPHELD = 0
EVALUATED = 0
# The statuses that mean the check reached no verdict of its own. A row in any
# of these examined nothing measurable, so a recorded coverage count on it is
# a number nobody produced.
VOID_RUN = {"missing_tool", "timeout", "no_version", "refused", "unmapped_exit"}

MISSING = object()


def classify(container, key):
    """-> (state, value). The three states R26 is about, told apart.

    absent      the key is not in the object at all
    null        the key is present and holds null
    zero        the key is present and holds 0, [], {} or an all-zero mapping
    value       anything else, printed so a wrong non-zero is still visible
    """
    if not isinstance(container, dict) or key not in container:
        return "absent", MISSING
    v = container[key]
    if v is None:
        return "null", v
    if v is True or v is False:
        return "value", v
    if isinstance(v, int) and v == 0:
        return "zero", v
    if isinstance(v, (list, dict)) and len(v) == 0:
        return "zero", v
    if isinstance(v, dict) and v and all(x == 0 for x in v.values()):
        return "zero", v
    return "value", v


def show(label, state, value):
    shown = "-" if value is MISSING else json.dumps(value)[:70]
    out.write("  %-38s state=%-6s %s\n" % (label, state, shown))


def say(held, text):
    # UPHELD IS COUNTED, NOT DERIVED FROM `ok`. It used to print `7 if ok else 0`,
    # which reported nothing upheld the moment one assertion failed - six lines
    # saying `held:` above a total saying zero held. That is a summary that
    # disagrees with the evidence directly above it, in the one check that
    # exists to assert P1. Each call now increments its own counter.
    global ok, UPHELD, EVALUATED
    EVALUATED += 1
    if held:
        UPHELD += 1
    else:
        ok = False
    out.write("  %s %s\n" % ("held:" if held else "FINDING: did not hold -", text))


def premise_failed(text):
    out.write("  PREMISE did not hold - %s\n" % text)
    out.write("  R26 was not exercised. Unmeasured, not a pass.\n")
    sys.exit(2)


try:
    with open(result_path, errors="replace") as fh:
        doc = json.load(fh)
except (OSError, ValueError) as exc:
    out.write("  the runner's result could not be read: %s\n" % exc.__class__.__name__)
    out.write("  assertions evaluated: 0 of 7. Unmeasured, not a pass.\n")
    sys.exit(2)

try:
    with open(err_path, errors="replace") as fh:
        err = fh.read()
except OSError:
    err = ""

sc = doc.get("spec_coverage")
if not isinstance(sc, dict):
    premise_failed("the result carries no `spec_coverage` object, so no denominator was reported")
if sc.get("status") == "measured":
    premise_failed("the coverage denominator came back `measured`, so nothing about it was "
                   "unmeasurable and there was no unmeasured value to fabricate")

rows = {c.get("id"): c for c in doc.get("checks") or []}
row = rows.get(check_id)
if row is None:
    premise_failed("the result records no row for `%s`, so the unmeasurable check never ran"
                   % check_id)
if row.get("status") not in VOID_RUN:
    premise_failed("`%s` came back %r, which is a verdict of its own; the check measured "
                   "something and its coverage was not unmeasurable"
                   % (check_id, row.get("status")))

out.write("  premises held: the denominator is %r (not measured) and `%s` is %r (no verdict).\n"
          % (sc.get("status"), check_id, row.get("status")))

# What R25 did with the same run, reported and NOT asserted. If this says the
# printed line reads UNMEASURED while an assertion below fails, that is the
# split: R25 satisfied and R26 violated on one run.
r25 = any(ln.startswith("spec coverage: UNMEASURED") for ln in err.splitlines())
out.write("  note (R25, not asserted here): the printed line %s\n"
          % ("reads UNMEASURED" if r25 else "does NOT read UNMEASURED"))

counts = doc.get("counts") if isinstance(doc.get("counts"), dict) else {}

out.write("  three-state classification of every field that would carry an unmeasured count:\n")
fields = [
    ("spec_coverage.units_total", sc, "units_total", "null"),
    ("spec_coverage.counts", sc, "counts", "null"),
    ("spec_coverage.units", sc, "units", "null"),
    ("spec_coverage.satisfied", sc, "satisfied", "null"),
    ("counts.spec_units_unsatisfied", counts, "spec_units_unsatisfied", "null"),
    ("checks[%s].coverage" % check_id, row, "coverage", "absent"),
]
seen = {}
for label, container, key, want in fields:
    state, value = classify(container, key)
    seen[label] = state
    show(label, state, value)

for label, _c, _k, want in fields:
    state = seen[label]
    say(state == want,
        "%s is %s, the state for a value nobody could measure; it is %s"
        % (label, want, state))

# Assertion 7: the same rule over every row a later runner might add, not only
# the one this fixture creates.
offenders = []
for c in doc.get("checks") or []:
    if c.get("status") not in VOID_RUN:
        continue
    cov = c.get("coverage")
    if not isinstance(cov, dict):
        continue
    obs = cov.get("observed") or {}
    offenders.append("%s records covered=%r" % (c.get("id"), obs.get("covered")))
say(not offenders,
    "no check that reached no verdict records a coverage count%s"
    % ("" if not offenders else "; offenders: " + ", ".join(offenders)))

out.write("  assertions evaluated: %d, upheld: %d\n" % (EVALUATED, UPHELD))
sys.exit(0 if ok else 1)
PY

ARC=0
python3 "$TMP/assert.py" "$TMP/result.json" "$TMP/runner.err" unmeasurable || ARC=$?

case "$RC" in
  3) : ;;
  *) printf '  note: the run exited %s. R26 constrains what was recorded, not the exit code; the exit code is R13 and R15 territory.\n' "$RC" ;;
esac

case "$ARC" in
  0) printf '  R26 satisfied: a value that could not be measured is recorded as absent or null, never as zero.\n'; exit 0 ;;
  1) printf '  R26 not satisfied: see the findings above. A value nobody could measure has been recorded as zero, which a month from now reads exactly like a real zero.\n'; exit 1 ;;
  *) die_unmeasured "the assertions could not be evaluated; unmeasured, not a pass" ;;
esac
