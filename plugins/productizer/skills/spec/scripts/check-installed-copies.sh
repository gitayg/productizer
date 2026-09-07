#!/usr/bin/env bash
# check-installed-copies.sh [--root DIR] [--templates DIR] [--hooks DIR]
#                           [--version] [--help] [--selftest]
#
# AN EXECUTABLE INSTALLED FROM A TEMPLATE MUST STILL BE THAT TEMPLATE.
#
# The publish gate exists twice: `templates/publish-gate.sh`, which every repo
# installing this plugin receives, and `.claude/hooks/publish-gate.sh`, which is
# this repo's own copy. They were byte-identical and nothing said so.
#
# Measured, not argued: editing one drifted them instantly, and the drift stayed
# invisible until a check that drives the TEMPLATE failed against a fix that had
# only landed in the hook. The dangerous direction is the other one - this repo
# hardening its own gate while every repo installing the plugin keeps the weaker
# copy, and the suite staying green because it only ever tests the template.
#
# WHAT IS COMPARED, AND WHAT IS DELIBERATELY NOT.
#
# Only executables that landed under the hooks directory. `templates/` also
# holds SEEDS - `spec.md`, `backlog.md`, `config.json`, `constitution.md`,
# `checks.yaml` - which are copied once and then edited, and which differ from
# their template the moment the repo is used. Comparing those would go red on
# five files for doing exactly what they are for. A hook is not a seed: it is
# code, and there is no per-repo edit it is meant to carry.
#
# Two assertions, separately.
#
#   1. Every template executable with a counterpart in the hooks directory is
#      byte-identical to it.
#   2. Every such counterpart is executable. A hook the shell will not run is a
#      gate that is not there, and it fails silently rather than loudly.
#
# THE PREMISE IS GUARDED. If no pair exists at all, nothing was compared and the
# run asserts nothing - exit 2, unmeasured, never a clean pass. An assertion
# sweeping an empty set is how a check in this repo passed for months without
# ever seeing the thing it looked for.
#
# CONTENT IS NEVER PRINTED, only the first differing LINE NUMBER. This output is
# tailed into a committed result file, and a diff there would put one copy of
# the gate inside the record of the other.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every installed executable matches its template and is runnable
#   1  a copy drifted, or lost its executable bit
#   2  could not run - bad usage, a missing directory, an unreadable file, or
#      no pair to compare
#
# --SELFTEST DRIVES EVERY ONE OF THOSE THREE. R39 - every check tool shall
# carry a self-test that reaches each exit code it can return - and a
# self-test that only ever watches the clean case is the thing this repository
# keeps shipping: an honest gap converted into a false assurance. So the mode
# builds six little installations under `mktemp -d`, each differing from the
# clean one in exactly one way, runs THIS script against each, and compares
# the exit code with the one the case declares. Nothing is written into the
# repository being checked, on any exit path, signal included.
#
# Under --selftest the three codes mean: every case produced the code it
# declares (0), at least one did not (1), and the cases could not be built or
# driven at all (2). `--self-test` is accepted as an alias because the repo
# spells it both ways.
#
# WHAT IT PRINTS. One BARE repo-relative path per file examined, which the
# runner parses as coverage. Findings and notes are INDENTED.
set -euo pipefail

VERSION="check-installed-copies 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=""; TEMPLATES=""; HOOKS=""; MODE="measure"

die_unmeasured() { printf 'check-installed-copies: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)        [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";      ROOT="$2";      shift 2 ;;
    --root=*)      ROOT="${1#--root=}";           shift ;;
    --templates)   [ "$#" -ge 2 ] || die_unmeasured "--templates needs a path"; TEMPLATES="$2"; shift 2 ;;
    --templates=*) TEMPLATES="${1#--templates=}"; shift ;;
    --hooks)       [ "$#" -ge 2 ] || die_unmeasured "--hooks needs a path";     HOOKS="$2";     shift 2 ;;
    --hooks=*)     HOOKS="${1#--hooks=}";         shift ;;
    --selftest|--self-test) MODE="selftest";      shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1." ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1."

# ---------------------------------------------------------------------------
# --selftest: build the cases, drive THIS script against each, read the exit
# code off it. Every case differs from the clean one in exactly one way, so a
# case that goes the wrong colour names the assertion that moved.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  WORK="$(mktemp -d)" \
    || die_unmeasured "cannot create a temporary directory to build the cases in; nothing was driven"
  # Removed on every exit path, signal included. Nothing is written into the
  # repository this script lives in.
  trap 'rm -rf "$WORK"' EXIT HUP INT TERM

  CASES=0; UPHELD=0; REPORT=""
  # R39.b: the reached half of the declaration below is ACCUMULATED here, one
  # entry per case as it ran. A literal list would satisfy the reader and prove
  # nothing.
  CODES=""

  # One little installation per case: a templates directory holding the gate
  # and a hooks directory holding whatever this case says landed there.
  build() {
    B="$WORK/$1"
    mkdir -p "$B/templates" "$B/hooks" \
      || die_unmeasured "could not lay out the case directory for $1"
    printf '#!/usr/bin/env bash\n# a gate\nexit 0\n' > "$B/templates/publish-gate.sh"
  }

  # `|| GOT=$?` on the same line as the command. A `$(...)` in an argument list
  # and a pipeline both RESET `$?`, and reading the status one line later is
  # how a self-test comes to report a pass it never observed.
  drive() {
    NAME="$1"; WANT="$2"; WHY="$3"; shift 3
    GOT=0
    bash "$0" "$@" > "$WORK/$NAME.out" 2> "$WORK/$NAME.err" || GOT=$?
    CASES=$((CASES + 1))
    if [ "$GOT" = "$WANT" ]; then UPHELD=$((UPHELD + 1)); V="held"; else V="NOT HELD"; fi
    CODES="$CODES$GOT
"
    REPORT="$REPORT      $NAME  expected $WANT  got $GOT  $V  $WHY
"
  }

  # 0 - the clean case. Without it every failing case below proves only that
  # something is red, not that this check is what makes it red.
  build clean
  cp "$WORK/clean/templates/publish-gate.sh" "$WORK/clean/hooks/publish-gate.sh"
  chmod +x "$WORK/clean/hooks/publish-gate.sh"
  drive clean 0 "an installed copy identical to its template, and executable" \
    --root "$WORK/clean" --templates "$WORK/clean/templates" --hooks "$WORK/clean/hooks"

  # 1 - assertion 1, the drift. The dangerous direction: the installed gate
  # hardened while every repo installing the plugin keeps the weaker copy.
  build drifted
  cp "$WORK/drifted/templates/publish-gate.sh" "$WORK/drifted/hooks/publish-gate.sh"
  printf 'exit 1\n' >> "$WORK/drifted/hooks/publish-gate.sh"
  chmod +x "$WORK/drifted/hooks/publish-gate.sh"
  drive drifted 1 "the installed copy gained a line its template does not have" \
    --root "$WORK/drifted" --templates "$WORK/drifted/templates" --hooks "$WORK/drifted/hooks"

  # 1 - assertion 2, separately, because a gate the shell will not run is a
  # gate that is absent quietly rather than one that drifted.
  build unrunnable
  cp "$WORK/unrunnable/templates/publish-gate.sh" "$WORK/unrunnable/hooks/publish-gate.sh"
  chmod -x "$WORK/unrunnable/hooks/publish-gate.sh"
  drive unrunnable 1 "an identical copy that lost its executable bit" \
    --root "$WORK/unrunnable" --templates "$WORK/unrunnable/templates" --hooks "$WORK/unrunnable/hooks"

  # 2 - the premise guard. Nothing compared is nothing asserted.
  build no-pair
  drive no-pair 2 "a templates directory whose gate landed nowhere, so no pair was compared" \
    --root "$WORK/no-pair" --templates "$WORK/no-pair/templates" --hooks "$WORK/no-pair/hooks"

  # 2 - an absent hooks directory. UNKNOWN drift is not no drift.
  build absent-hooks
  drive absent-hooks 2 "no hooks directory at the path given, so drift is unknown rather than absent" \
    --root "$WORK/absent-hooks" --templates "$WORK/absent-hooks/templates" \
    --hooks "$WORK/absent-hooks/nowhere"

  # 2 - bad usage, which is the same could-not-run and reaches it through the
  # argument parser rather than through the premise guards.
  build bad-usage
  drive bad-usage 2 "an option this script does not take" \
    --root "$WORK/bad-usage" --frobnicate

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"
  if [ "$CASES" = "$UPHELD" ]; then SELF_VERDICT="held"; else SELF_VERDICT="NOT HELD"; fi
  printf '    R39.s  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$CASES" "$UPHELD" "$SELF_VERDICT" \
    "each case exits with the code it declares"
  # The R39.b declaration. The reached half is computed from the cases above;
  # the documented half is the contract in this file's header.
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  printf '    NOT ASSERTED: the cases compare the exit CODE and never the wording of a finding, so a case that went red for the wrong reason is invisible here and is read off its captured output by hand\n'
  [ "$CASES" = "$UPHELD" ] || exit 1
  # A documented code nothing drove is the gap R39.b exists to make visible, so
  # it ends the run rather than being printed past.
  if [ -n "$MISSING" ]; then
    printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  exit 0
fi

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" \
    || die_unmeasured "no git work tree here, and --root was not given; the pair could not be located"
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

[ -n "$TEMPLATES" ] || TEMPLATES="$HERE/../templates"
[ -n "$HOOKS" ]     || HOOKS="$ROOT/.claude/hooks"
[ -d "$TEMPLATES" ] || die_unmeasured "no templates directory, so there is nothing to compare against"
[ -d "$HOOKS" ]     || die_unmeasured "no hooks directory at the path given; whether an installed copy drifted is UNKNOWN, which is not the same as no drift"
TEMPLATES="$(cd "$TEMPLATES" && pwd -P)"
HOOKS="$(cd "$HOOKS" && pwd -P)"

rel() { case "$1" in "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;; *) printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;; esac; }

pairs=0
findings=0
upheld_same=0
upheld_exec=0

for tpl in "$TEMPLATES"/*.sh; do
  [ -f "$tpl" ] || continue
  base="$(basename "$tpl")"
  inst="$HOOKS/$base"
  [ -f "$inst" ] || continue
  pairs=$((pairs + 1))
  rel "$tpl"
  rel "$inst"

  [ -r "$tpl" ] && [ -r "$inst" ] \
    || die_unmeasured "$base could not be read on one side, so whether the two agree is UNKNOWN"

  # ASSERTION 1. Byte-identical. Only the first differing line number is
  # reported; printing the difference itself would put one copy of a gate
  # inside the committed record of the other.
  if cmp -s "$tpl" "$inst"; then
    upheld_same=$((upheld_same + 1))
    printf '  held: %s matches its template byte for byte\n' "$base"
  else
    findings=$((findings + 1))
    # cmp's own message is NOT parsed and NOT printed: it names both files by
    # path, and this output is tailed into a committed result. What is reported
    # is derived here instead - the first differing line if there is one, or the
    # two sizes when one file is simply a prefix of the other, which is what an
    # append looks like and what cmp reports as EOF rather than as a line.
    #
    # `|| :` on the pipeline is load-bearing and is not tolerance of an unknown
    # failure: cmp exits 1 because the files differ, which is the case we are
    # already in, and `set -o pipefail` turns that into the pipeline's status
    # for `set -e` to kill the script on. Without it this branch died having
    # printed the paths and no finding - right exit code, invisible reason.
    line="$(cmp "$tpl" "$inst" 2>/dev/null | sed -n 's/.*line \([0-9][0-9]*\).*/\1/p' | head -1 || :)"  # stderr-ok: cmp's stderr names both files by absolute path and this text reaches a committed file; the line number is taken from stdout and the prefix case is reported from sizes below
    _ts="$(wc -c < "$tpl" | tr -d ' ')"
    _is="$(wc -c < "$inst" | tr -d ' ')"
    if [ -n "$line" ]; then
      where="first differing line $line"
    elif [ "$_ts" != "$_is" ]; then
      where="one file is a prefix of the other; template $_ts bytes, installed $_is bytes"
    else
      where="same length, and the differing position could not be read"
    fi
    printf '  FINDING: %s has drifted from its template: %s. This repo and every repo installing the plugin are no longer running the same code, and the suite tests only one of them. Content is not printed here.\n' \
      "$base" "$where"
  fi

  # ASSERTION 2. Runnable. A hook the shell will not execute is a gate that is
  # not there, and it fails silently rather than loudly.
  if [ -x "$inst" ]; then
    upheld_exec=$((upheld_exec + 1))
  else
    findings=$((findings + 1))
    printf '  FINDING: the installed %s is not executable, so it never runs. A gate that cannot run does not refuse anything; it is absent, quietly.\n' "$base"
  fi
done

# The empty set, guarded. Nothing compared is nothing asserted.
[ "$pairs" -gt 0 ] || die_unmeasured "no template executable has a counterpart in the hooks directory, so nothing was compared. An assertion with no pair to fire on holds vacuously forever; this refuses instead"

printf '  pairs compared: %d\n' "$pairs"
printf '  assertions evaluated: %d, upheld: %d\n' "$((pairs * 2))" "$((upheld_same + upheld_exec))"

if [ "$findings" -ne 0 ]; then
  printf '  An executable installed from a template is no longer that template.\n'
  exit 1
fi
printf '  Every installed executable is its template, and every one of them runs.\n'
exit 0
