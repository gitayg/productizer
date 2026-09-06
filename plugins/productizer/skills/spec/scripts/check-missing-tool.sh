#!/usr/bin/env bash
# check-missing-tool.sh [--root DIR] [--fixture DIR] [--version] [--help]
#                       [--selftest]
#
# Asserts R13: WHILE A CHECK TOOL NAMED BY THE CONFIGURATION IS ABSENT, THE
# LIFECYCLE SHALL REPORT THAT CHECK AS MISSING RATHER THAN SKIPPED.
#
# The behaviour is in run-checks.sh and was demonstrated by hand. A
# demonstration is not a test. Nothing stopped a refactor turning
# `missing_tool` back into a skip while every run stayed green, because a
# skipped check is invisible: it produces no finding, no failure and no line
# anybody reads. This is the standing case that would go red.
#
# TWO RESOLUTION BRANCHES, BECAUSE THE RUNNER HAS TWO. run-checks.sh decides
# what a `requires:` entry means from the SHAPE of the string:
#
#     */*) [ -x "$req" ] || MISSING="$MISSING $req" ;;
#     *)   command -v "$req" >/dev/null 2>&1 || MISSING="$MISSING $req" ;;
#
# A bare name is looked up on PATH; anything holding a slash is tested as an
# executable path. Version 1.0 of this check declared only a bare name, so
# only the second line was ever exercised - and the first is the one that
# carries the traffic: the large majority of the `requires:` entries in this
# repo's own checks.yaml are `./plugins/...` paths. That was measured, not
# suspected. Regressing ONLY the executable-path branch to a silent skip left
# all six of 1.0's assertions holding and the check exiting 0.
#
# So the fixture now declares three cases, each in its own config file:
#
#   bare-name        `definitely-not-a-real-tool`             -> command -v
#   executable-path  `./definitely-not-a-real-tool.sh`        -> [ -x ]
#   per-file         `./definitely-not-a-real-per-file-tool.sh`, `mode: per_file`
#
# The third is not a third branch and is not reported as one. In run-checks.sh
# the `requires:` loop and its `continue` run BEFORE `mode` is ever branched
# on - the value is read a few lines earlier, but `if [ "$mode" = "per_file" ]`
# sits well below the `continue` - so a per-file check with an absent tool
# reaches exactly the lines a batch one does. Read, not assumed.
# It is committed because it is nearly free and because it is what goes red if
# that ordering is ever reversed - batch would keep working while per_file
# quietly stopped reporting.
#
# ONE RUN PER CASE, NOT ONE RUN WITH THREE CHECKS. A single run holding all
# three would exit 3 because SOME check refused, which says nothing about any
# particular one: a regressed executable-path branch would ride the bare-name
# check's refusal straight to a green assertion. That is the exact failure this
# version exists to remove, so each case gets its own run and its own verdict.
#
# WHAT IT DOES. It copies `fixtures/missing-tool/` into a temporary directory
# and runs run-checks.sh against that copy, once per case. The temporary copy
# is the point: the runner writes a result file inside the repository it is
# checking, and pointing it at this repository would make a test of the runner
# a writer to the tree under test.
#
# WHAT IT ASSERTS PER CASE, AND WHY EACH ONE IS SEPARATE.
#
#   1  the run exits 3 - REFUSED. A missing tool has to stop the stage.
#   2  the human-readable line reads MISSING_TOOL for that check. A machine
#      status nobody sees is half the obligation; R13 says REPORT.
#   3  that line says it was not skipped, in those words.
#   4  the result JSON records `missing_tool` for the check.
#   5  the check is recorded as TRIGGERED, and its status is none of the
#      statuses that would mean it was passed over. This is the assertion that
#      actually catches a regression to skipping: a refactor that dropped the
#      check would leave `not_triggered`, `disabled` or `pass` behind, and each
#      of those reads green.
#   6  it counts as a BLOCKING failure and the verdict is `refused`, with this
#      check named in the run's own REFUSED line. A status recorded in a file
#      that does not change the verdict is a skip wearing a different name.
#
# EVERY RESULT IS REPORTED PER CASE, never summed. `bare-name: 6 upheld` beside
# `executable-path: 6 upheld` says which branch regressed; `12 upheld` does not,
# and a total is exactly what hid this gap for as long as it was hidden.
#
# THE PREMISE IS CHECKED FIRST, ONCE PER CASE. A bare name that turns out to be
# installed, or a path that turns out to exist, proves nothing about an absent
# tool - so that is exit 2, could not run, and never a pass. Each case also
# asserts that its declared entry really takes the branch it was written for: a
# path case whose string lost its slash would silently become a second copy of
# the bare-name case.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every assertion held, in every case
#   1  an assertion failed - the runner no longer reports an absent tool the
#      way R13 requires, on at least one resolution branch
#   2  could not run - bad usage, no fixture, no runner, no python3, or a
#      premise that did not hold
#
# --SELFTEST DRIVES ALL THREE, AND IT REACHES 1 THE ONLY HONEST WAY: BY
# REGRESSING THE RUNNER. Exit 1 here means "run-checks.sh no longer reports an
# absent tool the way R13 requires", and no fixture can produce that while the
# runner is correct - a self-test built only out of fixtures would watch exit
# 0 forever and call it coverage. So the mode copies the scripts directory
# into `mktemp -d`, deletes the one line in the COPY that writes the
# `missing_tool` status override - which is precisely the refactor to a silent
# skip this check exists to catch - and runs the copied check against the same
# committed fixture. The regression is verified to have applied before the
# case is driven; a patch that matched nothing would otherwise turn into a
# second copy of the clean case.
#
# NOTHING IN THIS REPOSITORY IS EDITED. The regression lives in a temporary
# copy that is removed on every exit path, signal included.
#
# Under --selftest the three codes mean: every case produced the code it
# declares (0), at least one did not (1), and the cases could not be built or
# driven at all (2). `--self-test` is accepted as an alias because the repo
# spells it both ways.
#
# WHAT IT PRINTS. One BARE PATH per line for every file examined, relative to
# the repository, which is what the runner parses as coverage. Assertions are
# INDENTED and tagged with the case they belong to. The runner's own stderr is
# NOT reproduced: it names the temporary directory it ran in, and this output
# is tailed into a committed result file where an absolute path is somebody's
# home directory published to everyone who clones the repo.
#
# PORTABILITY. Developed on macOS/BSD. No GNU-only behaviour: no mapfile, no
# `grep -P`, no `date -d`, no in-place sed. Nothing suppresses stderr.
set -euo pipefail

VERSION="check-missing-tool 2.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$HERE")"

ROOT=""
FIXTURE="$SKILL/fixtures/missing-tool"
MODE="measure"

die_unmeasured() { printf 'check-missing-tool: %s\n' "$1" >&2; exit 2; }

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
# correct, and again with the runner deliberately regressed in a temporary
# copy. Nothing in this repository is edited.
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

  # THE REGRESSED COPY. `$HERE` is copied whole because run-checks.sh is found
  # beside the check and reaches for its neighbours; a copy of one file would
  # be a different program.
  cp -R "$HERE" "$SELFWORK/scripts" \
    || die_unmeasured "could not copy the scripts directory, so the regressed case could not be built"
  REGRESSED="$SELFWORK/scripts/run-checks.sh"
  [ -f "$REGRESSED" ] \
    || die_unmeasured "the copy has no run-checks.sh, so there is nothing to regress"
  cp "$REGRESSED" "$SELFWORK/run-checks.before" \
    || die_unmeasured "could not keep a copy of the runner to compare the regression against"
  # The regression: the status override that makes an absent tool REPORT as
  # missing is dropped, leaving the skip R13 forbids.
  sed -e 's|printf .missing_tool.n. > "$D/status_override"|:|' \
    "$SELFWORK/run-checks.before" > "$REGRESSED" \
    || die_unmeasured "the deliberate regression could not be written"
  # A PATCH THAT MATCHED NOTHING IS THE CLEAN CASE WEARING A SECOND NAME. If
  # the line has moved, this run has not falsified anything and says so.
  if cmp -s "$SELFWORK/run-checks.before" "$REGRESSED"; then
    die_unmeasured "the deliberate regression changed nothing in the copied runner - the line that writes the \`missing_tool\` status override is no longer where this self-test looks for it. The regressed case would have been a second copy of the clean one, which is unmeasured, not a pass"
  fi

  # A FIXTURE WHOSE PREMISE FAILS: the declared tool is `sh`, which is
  # installed, so an absent tool was never tested.
  cp -R "$FIXTURE" "$SELFWORK/present-tool" \
    || die_unmeasured "could not copy the fixture for the premise case"
  sed -e 's|requires: \[definitely-not-a-real-tool\]|requires: [sh]|' \
    "$FIXTURE/checks.yaml" > "$SELFWORK/present-tool/checks.yaml" \
    || die_unmeasured "could not write the premise case's config"
  if cmp -s "$FIXTURE/checks.yaml" "$SELFWORK/present-tool/checks.yaml"; then
    die_unmeasured "the premise case's config is unchanged - the fixture no longer declares \`definitely-not-a-real-tool\` in the shape this self-test edits, so the case would not have tested a present tool"
  fi

  # 0 - the runner as this repository ships it. Without this case every red
  # case below proves only that something is red.
  drive reports-missing 0 "the shipped runner, against the committed fixture" \
    "$0" --fixture "$FIXTURE"

  # 1 - the regression this check exists to catch: an absent tool skipped
  # instead of reported.
  drive runner-skips 1 "a copied runner with the missing_tool status override removed" \
    "$SELFWORK/scripts/${0##*/}" --fixture "$FIXTURE"

  # 2 - the premise. A tool that turns out to be installed proves nothing
  # about an absent one.
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
  printf '    NOT ASSERTED: one regression is driven, not one per assertion, so this says the six assertions can go red together and not that each of them can go red alone\n'
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

# label : config file : the check id inside it. One check per config, so that
# each case's refusal is its own and not borrowed from a neighbour.
CASES="bare-name:checks.yaml:ghost
executable-path:checks-executable-path.yaml:ghost-path
per-file:checks-per-file.yaml:ghost-per-file"

RUNNER="$HERE/run-checks.sh"
[ -f "$RUNNER" ] || die_unmeasured "no run-checks.sh beside this script; there is nothing to test"
[ -d "$FIXTURE" ] || die_unmeasured "no fixture directory; the standing case is missing, which is unmeasured and not a pass"
[ -f "$FIXTURE/changed.txt" ] || die_unmeasured "the fixture has no changed.txt"
command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the result could not be read"

for spec in $CASES; do
  cfg="${spec#*:}"; cfg="${cfg%:*}"
  [ -f "$FIXTURE/$cfg" ] || die_unmeasured "the fixture has no $cfg, so the ${spec%%:*} case was never run. A case that is absent is unmeasured, not a pass"
done

rel() {
  case "$1" in
    "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;;
    *)         printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;;
  esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SANDBOX="$TMP/repo"
mkdir -p "$SANDBOX"
cp "$FIXTURE/changed.txt" "$SANDBOX/"
for spec in $CASES; do
  cfg="${spec#*:}"; cfg="${cfg%:*}"
  cp "$FIXTURE/$cfg" "$SANDBOX/"
done

rel "$RUNNER"
rel "$FIXTURE/changed.txt"
for spec in $CASES; do
  cfg="${spec#*:}"; cfg="${cfg%:*}"
  rel "$FIXTURE/$cfg"
done

cat > "$TMP/assert.py" <<'PY'
"""Read what one run reported and say whether R13 still holds for that case.

stdout: one indented, case-tagged line per assertion. Exit 0 all held, 1 one
did not, 2 the result could not be read at all - which is never reported as a
pass, because a result nobody could read is not a result that said
missing_tool.

`upheld` is COUNTED, one increment per assertion that held. It is never
derived from a single ok flag: a check in this repo once printed `upheld: 0`
directly above six lines that each said `held:`.
"""
import json
import re
import sys

result_path, err_path, rc_txt, check_id, tool, label, tally_path = sys.argv[1:8]
out = sys.stdout
TOTAL = 6
upheld = 0


def say(held, text):
    global upheld
    if held:
        upheld += 1
    out.write("  [%s] %s %s\n" % (label, "held:" if held else "FINDING: did not hold -", text))


def finish(code):
    with open(tally_path, "w") as fh:
        fh.write("%d/%d\n" % (upheld, TOTAL))
    out.write("  [%s] assertions evaluated: %d, upheld: %d\n" % (label, TOTAL, upheld))
    sys.exit(code)


try:
    with open(result_path, errors="replace") as fh:
        doc = json.load(fh)
except (OSError, ValueError) as exc:
    with open(tally_path, "w") as fh:
        fh.write("0/%d unreadable\n" % TOTAL)
    out.write("  [%s] the runner's result could not be read: %s\n" % (label, exc.__class__.__name__))
    out.write("  [%s] assertions evaluated: 0 of %d. Unmeasured, not a pass.\n" % (label, TOTAL))
    sys.exit(2)

try:
    with open(err_path, errors="replace") as fh:
        err = fh.read()
except OSError:
    err = ""

say(rc_txt == "3",
    "the run exits 3 (refused); it exited %s" % rc_txt)

# The reported line, not the whole stream: the stream names the temporary
# directory the run happened in and must not be echoed anywhere near a
# committed file.
line = ""
for ln in err.splitlines():
    if re.match(r"^\s*MISSING_TOOL\s+%s\b" % re.escape(check_id), ln):
        line = ln
        break
say(bool(line), "the reported line reads MISSING_TOOL for `%s`" % check_id)

detail = ""
for ln in err.splitlines():
    if "not installed" in ln and tool in ln:
        detail = ln
        break
say("Not skipped" in detail,
    "that report says in words that the check was not skipped, and names `%s`" % tool)

rows = {c.get("id"): c for c in doc.get("checks") or []}
# A missing row is not a reason to stop evaluating. The remaining assertions
# are about that row, so they FAIL - which is the honest answer - rather than
# going unevaluated and leaving a partial count nobody can compare.
row = rows.get(check_id) or {}
if check_id not in rows:
    out.write("  [%s] note: the result records no row for `%s` at all; the "
              "assertions below fail for that reason.\n" % (label, check_id))

say(row.get("status") == "missing_tool",
    "the result records status `missing_tool`; it records %r" % (row.get("status"),))

SKIP_LIKE = {"pass", "disabled", "not_triggered", "skipped", "skip"}
say(row.get("triggered") is True and row.get("status") not in SKIP_LIKE,
    "the check is triggered and its status is none of %s - the statuses a skip "
    "would leave behind" % ", ".join(sorted(SKIP_LIKE)))

# The verdict AND this check's own name in the line that announces the refusal.
# `counts.blocking_failures` alone is a number that some other row could have
# put there; the REFUSED line is the runner naming this row as the reason.
counts = doc.get("counts") or {}
refused_line = ""
for ln in err.splitlines():
    if ln.startswith("REFUSED: "):
        refused_line = ln
        break
named = bool(re.search(r"\b%s\s+\(" % re.escape(check_id), refused_line))
say(doc.get("verdict") == "refused" and (counts.get("blocking_failures") or 0) >= 1 and named,
    "it counts as a blocking failure and the verdict is `refused`, with `%s` named in the "
    "run's REFUSED line; verdict %r, blocking failures %r, named %s"
    % (check_id, doc.get("verdict"), counts.get("blocking_failures"), named))

finish(0 if upheld == TOTAL else 1)
PY

FAILED=0
SUMMARY=""

for spec in $CASES; do
  label="${spec%%:*}"
  cfg="${spec#*:}"; cfg="${cfg%:*}"
  cid="${spec##*:}"

  # WHAT THE CONFIG ACTUALLY DECLARES, read from the config rather than
  # hard-coded here. A fixture edited to name a different tool must move this
  # check's premise with it, or the premise would be guarding a string the
  # runner never sees.
  tool="$(sed -n 's/^ *requires: *\[\([^]]*\)\].*/\1/p' "$SANDBOX/$cfg" | tr -d ' ' | sed -n '1p')"
  [ -n "$tool" ] || die_unmeasured "$label: $cfg declares no tool to be absent"

  # PREMISE 1 - the entry takes the branch this case was written for. A path
  # case that lost its slash would quietly become a second copy of the
  # bare-name case, and two runs of one branch look exactly like coverage of
  # two.
  case "$label:$tool" in
    bare-name:*/*)
      die_unmeasured "$label: the declared entry \`$tool\` holds a slash, so run-checks.sh resolves it as a path, not on PATH. The bare-name branch was not the one tested; unmeasured, not a pass" ;;
    bare-name:*) : ;;
    *:*/*) : ;;
    *) die_unmeasured "$label: the declared entry \`$tool\` holds no slash, so run-checks.sh looks it up on PATH rather than testing it as an executable path. The executable-path branch was not the one tested; unmeasured, not a pass" ;;
  esac

  # PREMISE 2 - the tool is really absent. Present, and this run proves nothing.
  case "$tool" in
    */*)
      # The runner does `cd "$ROOT"` before resolving, so the sandbox is where
      # a `./`-relative entry is looked for. That is the only place the
      # absence has to hold, and the only place it is claimed.
      if [ -e "$SANDBOX/$tool" ] || [ -x "$SANDBOX/$tool" ]; then
        die_unmeasured "$label: the fixture's declared path \`$tool\` exists in the directory the runner resolves against, so an absent tool was never tested. The premise failed; this is unmeasured, not a pass"
      fi ;;
    *)
      if command -v "$tool" >/dev/null 2>&1; then
        die_unmeasured "$label: the fixture's declared tool \`$tool\` is installed on this machine, so an absent tool was never tested. The premise failed; this is unmeasured, not a pass"
      fi ;;
  esac

  RC=0
  # A refused run exits non-zero and that is the expected outcome, so the
  # status is captured rather than allowed to kill the script: under `set -e`
  # an uncaught 3 here would end the run mid-case, printing an exit code and
  # no reason, with the remaining cases never attempted.
  bash "$RUNNER" --config "$SANDBOX/$cfg" --root "$SANDBOX" \
    --changed "$SANDBOX/changed.txt" --out "$TMP/$label.json" \
    > "$TMP/$label.out" 2> "$TMP/$label.err" || RC=$?

  ARC=0
  # Same reason: 1 means an assertion did not hold, which is a result to
  # report, not a reason to abandon the other cases.
  python3 "$TMP/assert.py" "$TMP/$label.json" "$TMP/$label.err" "$RC" \
    "$cid" "$tool" "$label" "$TMP/$label.tally" || ARC=$?

  tally="$(cat "$TMP/$label.tally")"
  SUMMARY="$SUMMARY | $label: $tally upheld"

  case "$ARC" in
    0) : ;;
    1) FAILED=$((FAILED + 1)) ;;
    *) die_unmeasured "$label: the assertions could not be evaluated; unmeasured, not a pass" ;;
  esac
done

printf '  per branch:%s\n' "${SUMMARY# |}"

if [ "$FAILED" -eq 0 ]; then
  printf '  R13 satisfied on every resolution branch: an absent tool is reported as missing and refuses the stage, whether the configuration named it by bare name or by executable path. It is not skipped.\n'
  exit 0
fi
printf '  R13 not satisfied on %d of the cases above: see the findings, which name the branch. An absent tool is no longer reported the way R13 requires.\n' "$FAILED"
exit 1
