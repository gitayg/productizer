#!/usr/bin/env bash
# check-calibration-recorded.sh [--root DIR] [--checks FILE] [--calibration FILE]
#                               [--version] [--help] [--selftest]
#
# A BLOCKING CHECK PROVES ITS ALARMS ARE REAL BEFORE IT MAY BLOCK, AND THE PROOF
# IS A RECORD, NOT PROSE.
#
# R50: if a check is declared blocking, the lifecycle records its fire rate over
# merged history, the number of commits that returned a verdict, and a person's
# ruling on every fire in that window. R51: if the rate could not be measured,
# the lifecycle records that its severity was never calibrated. Until this
# existed the only rulings in the repository lived in prose in
# `references/risk-and-calibration.md`, and nothing re-read them (B76).
#
# What is enforced is the RECORD, not a threshold. No false-positive ceiling and
# no verdict floor is applied here; the 10% and the 20 proposed beside the rule
# were not adopted.
#
# WHICH CHECKS. Every check in `checks.yaml` whose EFFECTIVE severity is `block`
# - its own `severity` key, else `defaults.severity`, else `block`, exactly as
# `run-checks.sh` resolves it - and which is not `enabled: false`. Resolving the
# default is load-bearing: a check that never names its severity blocks when the
# default says so, and reading only the key would let it skip its record.
#
# THE RECORD, `.claude/productizer/calibration.yaml`:
#
#   version: 1
#   checks:
#     - id: <check id>
#       status: measured
#       window:   {first: <sha>, last: <sha>, commits: <n>, history: empty|clone}
#       verdicts: <n>            # commits that returned pass or fail; > 0
#       fires:    <n>            # <= verdicts
#       fire_rate: "<fires>/<verdicts> = <pct>%"   # must agree with the two counts
#       measured_by: {tool: ..., version: ..., date: YYYY-MM-DD}
#       rulings:                 # exactly one per fire
#         - {commit: <sha>, ruling: genuine|false-positive|pending,
#            by: <a person>, date: YYYY-MM-DD, note: ...}
#     - id: <check id>
#       status: uncalibrated     # R51
#       reason: <why the rate could not be measured, as measured>
#       measured_by: {tool: ..., version: ..., date: YYYY-MM-DD}
#
# A RULING IS A PERSON'S. `pending` is how a fire an agent has looked at, but no
# person has ruled, is recorded - with the agent's note beside it - and it does
# NOT count. A `by` that names an agent (claude, gpt, bot, agent, assistant, ...,
# word-boundaried) does not count either.
#
# PATH OPTIONS.
#   --root DIR          the repo work tree; a relative one is read from the
#                       working directory, once. Default: the git top level.
#                       Outside a work tree with no --root this REFUSES, exit 2.
#   --checks FILE       default .claude/productizer/checks.yaml
#   --calibration FILE  default .claude/productizer/calibration.yaml
# A relative --checks or --calibration is read under the ROOT, NOT the working
# directory; an absolute one is used as given. A file inside the root is
# printed by its repo-relative name, never by a path naming a home directory.
#
# Through 1.0 (B141, ruled "converge on repo root") the two options were read
# from the working directory while their defaults lived under the root; outside
# a work tree the root silently fell back to the working directory, which then
# answered for a repository nobody named; and the first line printed both
# files absolute, so a clean run put the home directory into its output.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every enabled blocking check has a measured record with every fire ruled
#      by a person, or an uncalibrated record with its reason
#   1  at least one FINDING: no record, a malformed record (no window, no verdict
#      count, zero verdicts, a fire_rate that disagrees with its counts, no
#      measured_by), a fire with no ruling, a `pending` ruling, a ruling by an
#      agent, or two records for one check. Each names the check and what is
#      missing
#   2  could not run - bad usage, no work tree and no --root, no python3 or
#      PyYAML, or either file unreadable
#      or unparseable. Nothing examined is nothing upheld: unmeasured, not clean
#
# A record for a check that does not exist, is disabled or is not blocking is a
# NOTE, never a finding.
#
# WHAT IT PRINTS. One unindented line per blocking check examined, beginning
# `upheld` or `FINDING` and then the id, which the runner counts as coverage.
# Detail is indented.
#
# NOT ASSERTED:
#   - that a `by` names a real PERSON. An agent word list is refused; a made-up
#     human name is not detectable from a string.
#   - that the window, counts or fire SHAs are TRUE. The record is checked for
#     shape and internal agreement; re-measuring is measure-check-overfire.sh's
#     job, and nothing here notices a record going stale as the branch moves.
#   - that a ruled commit lies inside the recorded window. No git is read.
set -euo pipefail

VERSION="check-calibration-recorded 1.1"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$HERE/calibration-recorded.py"
SELF="${BASH_SOURCE[0]}"

CHECKS_REL=".claude/productizer/checks.yaml"
CAL_REL=".claude/productizer/calibration.yaml"
ROOT=""; CHECKS=""; CAL=""; MODE="check"

die_unmeasured() { printf 'check-calibration-recorded: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)        [ "$#" -ge 2 ] || die_unmeasured "--root needs a path"; ROOT="$2"; shift 2 ;;
    --checks)      [ "$#" -ge 2 ] || die_unmeasured "--checks needs a file"; CHECKS="$2"; shift 2 ;;
    --calibration) [ "$#" -ge 2 ] || die_unmeasured "--calibration needs a file"; CAL="$2"; shift 2 ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1." ;;
  esac
done

command -v python3 >/dev/null 2>&1 \
  || die_unmeasured "python3 is not on PATH, so neither file could be read"
python3 -c 'import yaml' \
  || die_unmeasured "PyYAML is not importable by python3, so neither file could be read"
[ -f "$HELPER" ] || die_unmeasured "its helper $HELPER is missing"

if [ "$MODE" = "check" ]; then
  # The work tree or nothing. Through 1.0 a failed lookup fell back to the
  # working directory and the check answered for whatever directory the caller
  # stood in. git speaks for itself on stderr.
  if [ -z "$ROOT" ]; then
    ROOT="$(git rev-parse --show-toplevel)" \
      || die_unmeasured "no git work tree here, and --root was not given. Refusing rather than reading the working directory, which is not a repository anyone named - unmeasured, not clean."
  fi
  [ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
  ROOT="$(cd "$ROOT" && pwd -P)"
  # Relative is joined to the root, absolute is used as given. The helper is
  # run FROM the root and handed each file by its shortest honest name - repo-
  # relative inside the root, as written outside it - so the names it prints
  # are the names it read, and no home directory reaches the output.
  under_root() {
    case "$1" in
      /*) printf '%s' "$1" ;;
      *)  printf '%s' "$ROOT/$1" ;;
    esac
  }
  shown() {
    local p="$1" d
    d="$(dirname "$p")"
    if [ -d "$d" ] && d="$(cd "$d" && pwd -P)"; then
      p="$d/$(basename "$p")"
    fi
    case "$p" in
      "$ROOT"/*) printf '%s' "${p#"$ROOT"/}" ;;
      *)         printf '%s' "$1" ;;
    esac
  }
  CHECKS="$(shown "$(under_root "${CHECKS:-$CHECKS_REL}")")"
  CAL="$(shown "$(under_root "${CAL:-$CAL_REL}")")"
  cd "$ROOT"
  exec python3 "$HELPER" "$CHECKS" "$CAL"
fi

# ---------------------------------------------------------------------------
# --selftest. Each case builds its own two files under a temporary directory,
# runs this script on them, and asserts the exit code AND a sentence, so a case
# red for the wrong reason is visible.
# ---------------------------------------------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-calibration-recorded.XXXXXX")" \
  || die_unmeasured "cannot create a temporary directory for the self-test"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

CASES=0; FAILS=0; CODES=""
SELF_ABS="$HERE/${SELF##*/}"
DRIVE_CWD=""

# A config: `alpha` blocks by its own key, `beta` blocks only by the default,
# `gamma` is advisory, `delta` blocks and is disabled.
checks_yaml() {
  cat <<YAML
version: 1
defaults:
  severity: ${1:-block}
checks:
  - id: alpha
    severity: block
  - id: beta
  - id: gamma
    severity: advise
  - id: delta
    severity: block
    enabled: false
YAML
}

MB='    measured_by: {tool: measure-check-overfire.sh, version: "1.1", date: "2026-10-02"}'
W='    window: {first: 1029c5975ddb, last: 547684e9cef4, commits: 30, history: empty}'

# alpha: measured, one fire ruled genuine by a person.
rec_alpha() {
  printf '  - id: alpha\n    status: measured\n%s\n    verdicts: 17\n    fires: 1\n' "$W"
  printf '    fire_rate: "1/17 = 5.9%%"\n%s\n' "$MB"
  printf '    rulings:\n      - {commit: 434bd790abcd, ruling: %s, by: %s, date: "2026-10-02"}\n' \
    "${1:-genuine}" "${2:-Itay Glick}"
}
# beta: uncalibrated, with its reason.
rec_beta() {
  printf '  - id: beta\n    status: uncalibrated\n    reason: "%s"\n%s\n' \
    "${1-reads git history}" "$MB"
}

case_run() {
  # case_run <name> <want-rc> <want-sentence> <checks-file> <cal-file> [extra args]
  # --root is the case directory unless the extra args name another (the last
  # --root wins). DRIVE_CWD, when set, is the working directory it runs from.
  local name="$1" want="$2" sentence="$3" ck="$4" cal="$5" rc=0
  shift 5
  CASES=$((CASES + 1))
  ( cd "${DRIVE_CWD:-.}" && bash "$SELF_ABS" --root "$WORK" --checks "$ck" --calibration "$cal" "$@" ) \
    >"$WORK/out" 2>"$WORK/err" || rc=$?
  CODES="$CODES $rc"
  if [ "$rc" -eq "$want" ] && grep -qF -- "$sentence" "$WORK/out" "$WORK/err"; then
    printf '  ok    %-58s exit %s\n' "$name" "$rc"
  else
    FAILS=$((FAILS + 1))
    printf '  FAIL  %-58s exit %s (wanted %s), sentence %s\n' "$name" "$rc" "$want" \
      "$(grep -qF -- "$sentence" "$WORK/out" "$WORK/err" && echo present || echo "ABSENT: $sentence")"
    sed 's/^/          | /' "$WORK/out" "$WORK/err"
  fi
}

mk() {  # mk <name> - writes $WORK/<name>.yaml from stdin
  cat >"$WORK/$1.yaml"
}

checks_yaml block  | mk checks
checks_yaml advise | mk checks-advise
printf 'checks:\n  - id: alpha\n    severity: block\n    enabled: "yes"\n' | mk checks-bad-enabled
printf 'checks: [unclosed\n' | mk unparseable

{ echo 'version: 1'; echo 'checks:'; rec_alpha; rec_beta; } | mk good
{ echo 'version: 1'; echo 'checks:'; rec_alpha; } | mk no-beta
{ echo 'version: 1'; echo 'checks:'; rec_alpha pending null; rec_beta; } | mk pending
{ echo 'version: 1'; echo 'checks:'; rec_alpha genuine claude; rec_beta; } | mk agent
{ echo 'version: 1'; echo 'checks:'; rec_alpha false-positive "Itay Glick"; rec_beta; } | mk fp
{ echo 'version: 1'; echo 'checks:'; rec_alpha | sed '/rulings:/,$d'; rec_beta; } | mk unruled
{ echo 'version: 1'; echo 'checks:'; rec_alpha | sed '/verdicts:/d'; rec_beta; } | mk no-verdicts
{ echo 'version: 1'; echo 'checks:'; rec_alpha | sed 's/verdicts: 17/verdicts: 0/'; rec_beta; } | mk zero-verdicts
{ echo 'version: 1'; echo 'checks:'; rec_alpha | sed 's/5.9%/0.0%/'; rec_beta; } | mk bad-rate
{ echo 'version: 1'; echo 'checks:'; rec_alpha | sed '/window:/d'; rec_beta; } | mk no-window
{ echo 'version: 1'; echo 'checks:'; rec_alpha; rec_beta ""; } | mk no-reason
{ echo 'version: 1'; echo 'checks:'; rec_alpha; rec_beta; rec_beta; } | mk duplicate
{ echo 'version: 1'; echo 'checks:'; rec_alpha; rec_beta
  printf '  - id: ghost\n    status: uncalibrated\n    reason: "x"\n%s\n' "$MB"
  printf '  - id: gamma\n    status: uncalibrated\n    reason: "x"\n%s\n' "$MB"; } | mk extras
{ echo 'version: 1'; echo 'checks:'; rec_alpha; } | mk alpha-only

C="$WORK/checks.yaml"
printf 'check-calibration-recorded self-test\n\n'
case_run "every blocking check recorded, every fire ruled by a person" 0 \
  "PASS: every enabled blocking check has its calibration recorded" "$C" "$WORK/good.yaml"
case_run "a fire ruled false-positive by a person" 0 \
  "upheld   alpha  measured 1/17 = 5.9%" "$C" "$WORK/fp.yaml"
case_run "an uncalibrated record with its reason upholds R51" 0 \
  "upheld   beta  uncalibrated (R51): reads git history" "$C" "$WORK/good.yaml"
case_run "a check blocking only by defaults.severity, no record" 1 \
  "FINDING  beta  no calibration record" "$C" "$WORK/no-beta.yaml"
case_run "the same check when defaults.severity is advise" 0 \
  "blocking checks examined: 1" "$WORK/checks-advise.yaml" "$WORK/alpha-only.yaml"
case_run "a disabled blocking check needs no record" 0 \
  "skipped, enabled: false: delta" "$C" "$WORK/good.yaml"
case_run "a pending ruling is not a ruling" 1 \
  "is ruled \`pending\` - not a person's ruling" "$C" "$WORK/pending.yaml"
case_run "a ruling by an agent is not a ruling" 1 \
  "which names an agent (claude)" "$C" "$WORK/agent.yaml"
case_run "a fire with no ruling at all" 1 \
  "1 of 1 fire(s) in the window have no ruling at all" "$C" "$WORK/unruled.yaml"
case_run "a measured record with no verdict count" 1 \
  "malformed record: no verdict count" "$C" "$WORK/no-verdicts.yaml"
case_run "a measured record with zero verdicts" 1 \
  "zero verdicts is not a measured rate" "$C" "$WORK/zero-verdicts.yaml"
case_run "a fire_rate that disagrees with its counts" 1 \
  "malformed record: \`fire_rate\` reads" "$C" "$WORK/bad-rate.yaml"
case_run "a measured record with no window" 1 \
  "malformed record: no \`window\`" "$C" "$WORK/no-window.yaml"
case_run "an uncalibrated record with no reason" 1 \
  "an uncalibrated record with no reason" "$C" "$WORK/no-reason.yaml"
case_run "two records for one check" 1 \
  "FINDING  beta  2 records" "$C" "$WORK/duplicate.yaml"
case_run "a record for an unknown check is a note" 0 \
  "NOTE  record for 'ghost': checks.yaml declares no such check" "$C" "$WORK/extras.yaml"
case_run "a record for an advisory check is a note" 0 \
  "NOTE  record for 'gamma': the check is not blocking" "$C" "$WORK/extras.yaml"
case_run "no calibration record file" 2 \
  "could not read the calibration record" "$C" "$WORK/absent.yaml"
case_run "an unparseable calibration record" 2 \
  "is not parseable YAML" "$C" "$WORK/unparseable.yaml"
case_run "an unparseable checks.yaml" 2 \
  "the declared checks at" "$WORK/unparseable.yaml" "$WORK/good.yaml"
case_run "enabled that is not a boolean" 2 \
  "enabled must be true or false" "$WORK/checks-bad-enabled.yaml" "$WORK/good.yaml"
case_run "an option this check does not know" 2 \
  "unknown option: --nonsense" "$C" "$WORK/good.yaml" --nonsense

# B141: PATHS. A relative --checks or --calibration is read under the root -
# run from a working directory holding an unparseable decoy of each, which read
# by mistake would exit 2 - and the first line names both repo-relative.
mkdir -p "$WORK/repo/.claude/productizer" "$WORK/decoy-cwd/.claude/productizer"
cp "$WORK/checks.yaml" "$WORK/repo/.claude/productizer/checks.yaml"
cp "$WORK/good.yaml" "$WORK/repo/.claude/productizer/calibration.yaml"
cp "$WORK/unparseable.yaml" "$WORK/decoy-cwd/.claude/productizer/checks.yaml"
cp "$WORK/unparseable.yaml" "$WORK/decoy-cwd/.claude/productizer/calibration.yaml"
REPO_LINE="declared in .claude/productizer/checks.yaml; records read from .claude/productizer/calibration.yaml"
DRIVE_CWD="$WORK/decoy-cwd"
case_run "relative --checks and --calibration are read under the root" 0 \
  "$REPO_LINE" .claude/productizer/checks.yaml .claude/productizer/calibration.yaml --root "$WORK/repo"
DRIVE_CWD=""
case_run "absolute paths inside the root are printed repo-relative" 0 \
  "$REPO_LINE" "$WORK/repo/.claude/productizer/checks.yaml" "$WORK/repo/.claude/productizer/calibration.yaml" \
  --root "$WORK/repo"

# The defaults, run with only --root: under the root, and printed
# repo-relative - through 1.0 this line carried both absolute paths.
CASES=$((CASES + 1)); rc=0
bash "$SELF_ABS" --root "$WORK/repo" >"$WORK/out" 2>"$WORK/err" || rc=$?
CODES="$CODES $rc"
if [ "$rc" -eq 0 ] && grep -qF -- "$REPO_LINE" "$WORK/out"; then
  printf '  ok    %-58s exit %s\n' "the defaults are read under the root, printed repo-relative" "$rc"
else
  FAILS=$((FAILS + 1))
  printf '  FAIL  %-58s exit %s (wanted 0), sentence %s\n' "the defaults are read under the root, printed repo-relative" "$rc" "$REPO_LINE"
  sed 's/^/          | /' "$WORK/out" "$WORK/err"
fi

# No work tree and no --root: refused, never answered from the working
# directory. The working directory holds VALID files, so the 1.0 fallback
# would have read them and exited 0. GIT_CEILING_DIRECTORIES keeps git from
# finding a repository above the temporary directory.
mkdir -p "$WORK/nogit/.claude/productizer"
cp "$WORK/checks.yaml" "$WORK/nogit/.claude/productizer/checks.yaml"
cp "$WORK/good.yaml" "$WORK/nogit/.claude/productizer/calibration.yaml"
CASES=$((CASES + 1)); rc=0
( cd "$WORK/nogit" && GIT_CEILING_DIRECTORIES="$WORK" bash "$SELF_ABS" ) >"$WORK/out" 2>"$WORK/err" || rc=$?
CODES="$CODES $rc"
if [ "$rc" -eq 2 ] && grep -qF -- "no git work tree here, and --root was not given" "$WORK/err"; then
  printf '  ok    %-58s exit %s\n' "no work tree and no --root is refused, not read from cwd" "$rc"
else
  FAILS=$((FAILS + 1))
  printf '  FAIL  %-58s exit %s (wanted 2)\n' "no work tree and no --root is refused, not read from cwd" "$rc"
  sed 's/^/          | /' "$WORK/out" "$WORK/err"
fi

printf '\n%s of %s cases held\n' "$((CASES - FAILS))" "$CASES"
REACHED="$(printf '%s' "$CODES" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/  *$//')"
CODE_LINES="$(printf '%s' "$CODES" | tr ' ' '\n')"
MISSING=""
for want in 0 1 2; do
  grep -qx "$want" <<< "$CODE_LINES" || MISSING="$MISSING $want"
done
printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
printf '    NOT ASSERTED: that a by names a real person (only agent words are refused), that a record is still TRUE of the branch as it moves, or that a ruled commit lies inside its window.\n'
if [ -n "$MISSING" ]; then
  printf 'FAIL: documented code(s)%s never driven by any case\n' "$MISSING" >&2
  FAILS=$((FAILS + 1))
fi
[ "$FAILS" -eq 0 ] || exit 1
exit 0
