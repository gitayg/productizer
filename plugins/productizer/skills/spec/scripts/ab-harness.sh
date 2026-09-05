#!/usr/bin/env bash
# ab-harness.sh <run|report> [repo-root] --task ID [--min-n N] [--config PATH] [--runs PATH]
#
# Harness-isolated A/B. One task, one model, two arms: `process` runs it through
# the nine stages, `bare` runs the same model on the same task with none of it.
# The variable under test is the harness, and nothing else - same model, same
# task text, same machine.
#
# This is a scaffold, deliberately. It does not know how to invoke a model and
# does not try: the two arm commands come from a config file, and the harness
# times them, records what they cost, and compares. What it contributes is the
# discipline around the comparison, which is where this kind of benchmark
# usually goes wrong.
#
# THE SMALL-n RULE
#
# The only published benchmark that isolates the harness this way carries the
# disclosure "Results are directional (n=1 per arm)", and it is right to. Two
# runs of a stochastic system differ by more than most process effects. So:
#
#   - Every figure prints its arm count beside it. A median with no n is a
#     claim, not a measurement.
#   - Below --min-n (default 5) complete runs in the smaller arm, the comparison
#     is labelled DIRECTIONAL and the harness will not call the difference
#     meaningful. It prints the delta - hiding it would be its own dishonesty -
#     and refuses the conclusion.
#   - Even above the threshold this reports a difference between two medians. It
#     is not a significance test and never claims to be one.
#
# HOUSE RULE: a value that could not be measured is never rendered as zero. An
# arm with no runs, an arm whose runs all failed, a task that did not complete,
# a cost the arm never reported - each has its own word. `0` here would mean
# free, or instant, and none of them are.
#
# Config - `.claude/productizer/ab-task.tsv`, tab separated:
#
#   # task  arm      command
#   T1      process  claude -p "$(cat prompt.md)" --append-system-prompt "$(spec)"
#   T1      bare     claude -p "$(cat prompt.md)"
#
# The command runs under `bash -c` with AB_OUT_DIR, AB_TASK and AB_ARM exported.
# Its stdout and stderr are written into AB_OUT_DIR - captured, never discarded.
# To report a cost, the arm writes a plain number of dollars to
# "$AB_OUT_DIR/cost.usd"; anything else is recorded as `unavailable`, which is
# what an unreported cost is.
#
# Runs - `.claude/productizer/ab-runs.tsv`, appended by `run`, read by `report`:
#
#   task  arm  run  status  duration_ms  cost_usd  output_bytes
#
# No timestamp is recorded. A run's identity is its index within its arm, so the
# same recorded runs produce the same report bytes in any timezone.
#
# Exit: 0 run completed, or report emitted
#       2 usage
#       3 no such directory, no config, or the task has no two arms
#       5 no runs recorded for the task - not a zero difference
#       6 an arm has no complete run (`report` only) - there is no result to read
#       7 an arm did not complete (`run` only) - recorded as incomplete
set -euo pipefail
export LC_ALL=C

MODE=""
ROOT=""
TASK=""
MIN_N=5
CONFIG=""
RUNS=""
while [ $# -gt 0 ]; do
  case "$1" in
    run|report)  [ -z "$MODE" ] || { echo "ab-harness: only one mode" >&2; exit 2; }; MODE="$1"; shift ;;
    --task)      TASK="${2:-}"; [ -n "$TASK" ] || { echo "ab-harness: --task needs an id" >&2; exit 2; }; shift 2 ;;
    --task=*)    TASK="${1#--task=}"; shift ;;
    --min-n)     MIN_N="${2:-}"; [ -n "$MIN_N" ] || { echo "ab-harness: --min-n needs a number" >&2; exit 2; }; shift 2 ;;
    --min-n=*)   MIN_N="${1#--min-n=}"; shift ;;
    --config)    CONFIG="${2:-}"; [ -n "$CONFIG" ] || { echo "ab-harness: --config needs a path" >&2; exit 2; }; shift 2 ;;
    --config=*)  CONFIG="${1#--config=}"; shift ;;
    --runs)      RUNS="${2:-}"; [ -n "$RUNS" ] || { echo "ab-harness: --runs needs a path" >&2; exit 2; }; shift 2 ;;
    --runs=*)    RUNS="${1#--runs=}"; shift ;;
    -h|--help)   echo "usage: ab-harness.sh <run|report> [repo-root] --task ID [--min-n N] [--config PATH] [--runs PATH]"; exit 0 ;;
    -*)          echo "ab-harness: unknown option: $1" >&2; exit 2 ;;
    *)           [ -z "$ROOT" ] || { echo "ab-harness: only one repo-root" >&2; exit 2; }; ROOT="$1"; shift ;;
  esac
done
[ -n "$MODE" ] || { echo "usage: ab-harness.sh <run|report> [repo-root] --task ID" >&2; exit 2; }
[ -n "$TASK" ] || { echo "ab-harness: --task is required - a benchmark with no task named is not reproducible" >&2; exit 2; }
case "$MIN_N" in ''|*[!0-9]*) echo "ab-harness: --min-n must be a whole number, not: $MIN_N" >&2; exit 2 ;; esac
[ "$MIN_N" -ge 1 ] || { echo "ab-harness: --min-n must be at least 1" >&2; exit 2; }

[ -n "$ROOT" ] || ROOT="."
cd "$ROOT" || { echo "ab-harness: no such directory: $ROOT" >&2; exit 3; }
[ -n "$CONFIG" ] || CONFIG=".claude/productizer/ab-task.tsv"
[ -n "$RUNS" ]   || RUNS=".claude/productizer/ab-runs.tsv"

ARMS="bare process"   # fixed order, so two reports over the same runs match byte for byte

# Monotonic milliseconds. python3 is already a dependency of this skill. Where
# it is missing the duration is `unavailable` - an unmeasured duration is not a
# duration of zero, and a benchmark that silently reports 0 ms is worse than one
# that reports nothing.
HAVE_CLOCK=0
if command -v python3 >/dev/null; then HAVE_CLOCK=1; fi
now_ms() { python3 -c 'import time; print(int(time.monotonic()*1000))'; }

records_for() { # records_for <arm>  -> the recorded lines for this task and arm
  [ -f "$RUNS" ] || return 0
  awk -F'\t' -v t="$TASK" -v a="$1" '$1 == t && $2 == a' "$RUNS"
}

# ---------------------------------------------------------------- run --------
if [ "$MODE" = "run" ]; then
  [ -f "$CONFIG" ] || {
    echo "ab-harness: no config at $CONFIG" >&2
    echo "  Write one line per arm: <task>TAB<arm>TAB<command>" >&2
    exit 3
  }
  for arm in $ARMS; do
    cmd="$(awk -F'\t' -v t="$TASK" -v a="$arm" '$1 == t && $2 == a { sub(/^[^\t]*\t[^\t]*\t/, ""); print; exit }' "$CONFIG")"
    if [ -z "$cmd" ]; then
      echo "ab-harness: task $TASK has no '$arm' arm in $CONFIG" >&2
      echo "  Both arms are required. One arm is not an A/B; it is a run." >&2
      exit 3
    fi
    eval "CMD_$arm=\$cmd"
  done

  mkdir -p "$(dirname "$RUNS")"
  if [ ! -f "$RUNS" ]; then
    printf '# task\tarm\trun\tstatus\tduration_ms\tcost_usd\toutput_bytes\n' > "$RUNS"
  fi

  FAILED=0
  for arm in $ARMS; do
    eval "cmd=\$CMD_$arm"
    idx=$(( $(records_for "$arm" | wc -l | tr -d ' ') + 1 ))
    out=".claude/productizer/ab-out/$TASK/$arm/$idx"
    mkdir -p "$out"

    # An `x && y` list is the classic way to trip `set -e`: when x is false the
    # whole list is false and the script exits. Written as `if`, deliberately.
    start=""
    if [ "$HAVE_CLOCK" -eq 1 ]; then start="$(now_ms)"; fi
    rc=0
    AB_OUT_DIR="$out" AB_TASK="$TASK" AB_ARM="$arm" \
      bash -c "$cmd" > "$out/stdout" 2> "$out/stderr" || rc=$?
    stop=""
    if [ "$HAVE_CLOCK" -eq 1 ]; then stop="$(now_ms)"; fi

    if [ -n "$start" ] && [ -n "$stop" ]; then dur=$(( stop - start )); else dur="unavailable"; fi
    if [ "$rc" -eq 0 ]; then status="complete"; else status="incomplete"; FAILED=$((FAILED + 1)); fi

    # A cost is one decimal number. The character-class test this replaced
    # accepted `1.2.3`, `...` and `.` as costs, wrote them into the runs file,
    # and left `report` to drop them again - so a row could carry a cost that
    # every reader had to re-validate, and the two validators disagreed about
    # what a cost was. This pattern is the one `median` already applies, so a
    # value that survives `run` is a value `report` can use.
    cost="unavailable"
    if [ -f "$out/cost.usd" ]; then
      raw="$(tr -d ' \n' < "$out/cost.usd")"
      if printf '%s\n' "$raw" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then cost="$raw"; fi
    fi
    bytes="$(wc -c < "$out/stdout" | tr -d ' ')"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$TASK" "$arm" "$idx" "$status" "$dur" "$cost" "$bytes" >> "$RUNS"
    echo "ab-harness: $TASK/$arm run $idx - $status, ${dur} ms, cost ${cost}, ${bytes} bytes stdout"
    echo "  output   $out/stdout"
    echo "  stderr   $out/stderr"
    if [ "$status" = "incomplete" ]; then
      echo "ab-harness: $TASK/$arm run $idx exited $rc. Recorded as incomplete and excluded from every figure." >&2
      echo "  A task that did not complete is not a slow task and not a cheap one." >&2
    fi
  done
  [ "$FAILED" -eq 0 ] || exit 7
  exit 0
fi

# ------------------------------------------------------------- report --------
if [ ! -f "$RUNS" ]; then
  echo "ab-harness: no runs file at $RUNS" >&2
  echo "  outcome: no-runs. Nothing was measured, which is not a difference of zero." >&2
  exit 5
fi

# Lower median, so an even count still lands on a value that was actually
# observed. Prints "<median> <count>", or "unmeasured 0" when the arm gave
# nothing numeric to work with.
median() { # median <printf-format>   (values on stdin, one per line)
  awk -v fmt="$1" '
    /^[0-9]+(\.[0-9]+)?$/ { v[++n] = $0 + 0 }
    END {
      if (n == 0) { print "unmeasured 0"; exit }
      for (i = 2; i <= n; i++) { x = v[i]; j = i - 1; while (j > 0 && v[j] > x) { v[j+1] = v[j]; j-- } v[j+1] = x }
      printf fmt " %d\n", v[int((n + 1) / 2)], n
    }'
}

TOTAL=0
for arm in $ARMS; do
  n_all="$(records_for "$arm" | wc -l | tr -d ' ')"
  n_ok="$(records_for "$arm" | awk -F'\t' '$4 == "complete"' | wc -l | tr -d ' ')"
  n_bad=$(( n_all - n_ok ))
  read -r d_med d_n <<EOF
$(records_for "$arm" | awk -F'\t' '$4 == "complete" { print $5 }' | median '%d')
EOF
  read -r c_med c_n <<EOF
$(records_for "$arm" | awk -F'\t' '$4 == "complete" { print $6 }' | median '%.4f')
EOF
  eval "N_ALL_$arm=\$n_all; N_OK_$arm=\$n_ok; N_BAD_$arm=\$n_bad"
  eval "D_MED_$arm=\$d_med; D_N_$arm=\$d_n; C_MED_$arm=\$c_med; C_N_$arm=\$c_n"
  TOTAL=$(( TOTAL + n_all ))
done

if [ "$TOTAL" -eq 0 ]; then
  echo "ab-harness: no runs recorded for task $TASK in $RUNS" >&2
  echo "  outcome: no-runs. Nothing was measured, which is not a difference of zero." >&2
  exit 5
fi

echo "A/B - task $TASK"
echo "  variable  the harness. Same model, same task, both arms."
echo "  runs      $RUNS"
echo
printf '%-10s %-9s %-11s %-10s %-22s %s\n' "arm" "runs" "complete" "incomplete" "median duration_ms" "median cost_usd"
for arm in $ARMS; do
  eval "n_all=\$N_ALL_$arm; n_ok=\$N_OK_$arm; n_bad=\$N_BAD_$arm"
  eval "d_med=\$D_MED_$arm; d_n=\$D_N_$arm; c_med=\$C_MED_$arm; c_n=\$C_N_$arm"
  if [ "$n_ok" -eq 0 ]; then
    d_cell="no-complete-runs"; c_cell="no-complete-runs"
  else
    if [ "$d_med" = "unmeasured" ]; then d_cell="unmeasured"; else d_cell="$d_med (n=$d_n)"; fi
    if [ "$c_med" = "unmeasured" ]; then c_cell="unavailable"; else c_cell="$c_med (n=$c_n)"; fi
  fi
  printf '%-10s %-9s %-11s %-10s %-22s %s\n' "$arm" "$n_all" "$n_ok" "$n_bad" "$d_cell" "$c_cell"
done
echo

compare() { # compare <label> <bare> <bare-n> <process> <process-n> <format>
  local label="$1" b="$2" bn="$3" p="$4" pn="$5" fmt="$6"
  if [ "$b" = "unmeasured" ] || [ "$p" = "unmeasured" ]; then
    printf '  %-14s not comparable - %s\n' "$label" "one arm has no measured value"
    return 0
  fi
  awk -v l="$label" -v b="$b" -v p="$p" -v bn="$bn" -v pn="$pn" -v fmt="$fmt" '
    BEGIN {
      d = p - b
      s = (d >= 0) ? "+" : ""
      pct = (b == 0) ? "n/a" : sprintf("%+.1f%%", 100 * d / b)
      printf "  %-14s bare " fmt " (n=%d)   process " fmt " (n=%d)   delta %s" fmt "   %s\n",
             l, b, bn, p, pn, s, d, pct
    }'
}

echo "comparison - process against bare"
# shellcheck disable=SC2154
compare "duration_ms" "$D_MED_bare" "$D_N_bare" "$D_MED_process" "$D_N_process" '%d'
# shellcheck disable=SC2154
compare "cost_usd"    "$C_MED_bare" "$C_N_bare" "$C_MED_process" "$C_N_process" '%.4f'
echo

# shellcheck disable=SC2154
SMALLEST="$N_OK_bare"
# shellcheck disable=SC2154
if [ "$N_OK_process" -lt "$SMALLEST" ]; then SMALLEST="$N_OK_process"; fi

if [ "$SMALLEST" -eq 0 ]; then
  echo "NOT A RESULT. One arm has no complete run (bare n=$N_OK_bare, process n=$N_OK_process)."
  echo "  An arm that never completed is not an arm that scored zero. Run it, then report."
  exit 6
elif [ "$SMALLEST" -lt "$MIN_N" ]; then
  echo "DIRECTIONAL. Results are directional (n=$SMALLEST per arm)."
  echo "  This harness will not call the difference above meaningful, and neither should the"
  echo "  reader. Below $MIN_N complete runs per arm the delta is inside the noise of two runs"
  echo "  of the same arm. Quote it as directional or not at all."
else
  echo "Difference of medians over $SMALLEST+ complete runs per arm (bare n=$N_OK_bare, process n=$N_OK_process)."
  echo "  Still a difference of medians, not a significance test. It does not establish that"
  echo "  the harness caused it."
fi
