#!/usr/bin/env bash
# spec-doctor.sh [--version] [--help] [--root DIR] [--spec PATH] [--selftest]
#
# ONE COMMAND, ONE PAGE, EVERY SELF-CHECK THE SPEC ALREADY HAS. It runs the
# existing tools and lays their answers out together; it computes nothing a
# tool already computes, and it CHANGES NOTHING. A doctor that edits the file
# it is diagnosing is a doctor nobody can run twice and compare.
#
# WHY IT EXISTS. The checks are all here, and they are all separate. Nobody
# runs five scripts before touching the spec, so a defect that only one of
# them reports sits in that one script's output and becomes furniture. The
# repo's own header said `28 active, 4 superseded` while the file held 32 and
# 6 - reported the whole time, by a tool nobody was running.
#
# WHAT IT REPORTS.
#
#   1. GRAMMAR AND ID PERMANENCE      `validate-spec.py`
#   2. COUNTS, DECLARED v COUNTED     `validate-spec.py --counts`
#   3. SUPERSEDED CHAINS              `spec-requirements.sh`, walked
#   4. ACCEPTANCE ROWS                `check-acceptance-rows.sh`
#   5. RULINGS AWAITING A HUMAN       `pending-rulings.sh`
#
# Section 3 is the only place this script does arithmetic of its own, and it
# does it over the shared parser's output rather than over the file: one hop
# is what `validate-spec.py` already checks, and a CHAIN - R14 to R23 to R33 -
# is what no single check sees. A citation that lands on a superseded
# requirement leads a reader to a sentence nobody may act on.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every section ran, nothing found
#   1  every section ran, findings reported above
#   2  a section COULD NOT RUN - a missing tool, an unreadable spec, a tool
#      that refused. Never 0, and never 1 either: a report with a hole in it
#      has not found nothing, it has not looked. Constitution P1.
#
# --selftest DRIVES ALL THREE, over fixtures built under `mktemp -d`, and
# asserts both that each case exits the code its line declares and that the set
# of codes reached is the whole documented set. Its fixtures are STUB siblings,
# because the guards below fire when a sibling tool's wording, column order or
# exit code stops matching what a section parses - and the real tools agree
# with themselves, so a real spec cannot drive one. `--self-test` is an alias.
# Nothing in the repository is read or written by it. Its own exits: 0 every
# case held, 1 one did not or a documented code was never reached, 2 it could
# not run.
#
# COULD-NOT-MEASURE OUTRANKS FINDINGS, deliberately. Both are printed and
# both are counted on the summary line, so nothing is hidden by the ranking -
# but the exit code says the loudest true thing, which is that the page is
# incomplete.
#
# A WARN IS A FINDING HERE. `validate-spec.py` exits 0 on warnings because it
# gates CI and a pre-existing WARN must not block a merge. This is not a gate;
# it is the page you read before you touch the spec, and a warning nobody is
# told about is the failure mode it exists to end.
#
# STDERR IS NEVER SUPPRESSED. Each tool is run with its stderr merged into the
# section it belongs to, so a refusal is printed where it happened rather than
# vanishing. Nothing here writes `2>/dev/null`.
#
# 1.1 - A NUMBER THIS PAGE COULD NOT LIFT IS `unmeasured`, NEVER ZERO.
#
# Every tally above is DERIVED: an awk or a grep run over another tool's
# output. Until 1.1 a derivation that came back empty - because the tool had
# reworded a line or moved a column - was read as the number 0 and the section
# reported clean. That is the exact failure this whole page exists to end,
# committed by the page itself. Three were found, each by substituting a stub
# and reading what came out:
#
#   section 5  a stub printing `pending rulings: 3` and exiting 0 got the
#              `never raised one` explanation and no finding. Three rulings
#              waiting on a human, EXIT 0. And the real tool exits 1 when
#              rulings ARE pending, which fell through to the catch-all and was
#              reported as COULD NOT MEASURE - so the finding branch here could
#              never fire against the real tool at all.
#   section 1  a stub printing a reworded severity token and exiting 1 -
#              `validate-spec.py`'s own "at least one ERROR" - printed
#              `0 error line(s)` and EXIT 0, with the error line on screen.
#   section 3  a stub emitting the same fields in a different order exited 0
#              and the walk reported `0 superseded requirement(s)`, having
#              followed nothing.
#
# So: `is_count` gates every derived number, the exit code is read ALONGSIDE
# the number rather than instead of it, and a code that disagrees with the
# number it came with is two answers from one run - unmeasured, not a choice.
#
# SECTION 4 IS DELIBERATELY UNCHANGED, and it is worth saying why, because it
# looks like the same defect and is not. Its grep decides only what is
# DISPLAYED; its finding branch keys off `check-acceptance-rows.sh`'s EXIT
# CODE. Measured 2026-09-06: a stub whose output was reworded past every
# pattern still produced `EXIT 1 - findings above`, losing the detail and
# keeping the verdict. The converse was measured too - a stub printing
# `requirements missing an acceptance row: 99` and exiting 0 reports EXIT 0 -
# and that is the tool lying about its own contract, which this page relays
# faithfully and cannot second-guess.
#
# PORTABILITY. Developed on macOS/BSD. No GNU-only behaviour: no mapfile, no
# `grep -P`, no in-place sed.
set -euo pipefail

VERSION="spec-doctor 1.2"

ROOT="."
SPEC=""
SELFTEST=0

refuse() { printf 'spec-doctor: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)
      [ "$#" -ge 2 ] || refuse "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --spec)
      [ "$#" -ge 2 ] || refuse "--spec needs a file"
      SPEC="$2"; shift 2 ;;
    --selftest|--self-test) SELFTEST=1; shift ;;
    *) refuse "unknown argument: $1" ;;
  esac
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Resolved here, because the self-test drives its cases through a COPY of this
# file and `$0` is relative for most callers.
SELF="$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"
[ -n "$SPEC" ] || SPEC="$ROOT/.claude/productizer/spec.md"

VALIDATE="$SCRIPT_DIR/validate-spec.py"
PARSE="$SCRIPT_DIR/spec-requirements.sh"
ROWS="$SCRIPT_DIR/check-acceptance-rows.sh"
RULINGS="$SCRIPT_DIR/pending-rulings.sh"

# ---------------------------------------------------------------------------
# --selftest: drive the whole exit-code contract over fixtures that are stubs.
#
# R39 obliges a check tool to carry a self-test that REACHES EACH EXIT CODE it
# can return. This page documents three - 0, 1 and 2 - so the cases below are
# organised by exit code rather than by section, and the run asserts two
# separate things: that every case exited the code its line declares, AND that
# the set of codes actually reached is the whole documented set. The second
# assertion is the one that catches a contract growing a fourth code nobody
# drove.
#
# WHY THE FIXTURES ARE STUBS AND NOT SPECS. Every number on this page is
# DERIVED from a sibling tool's output, and the guards added in 1.1 fire when a
# sibling's wording, column order or exit code stops matching what the section
# parses. A real spec cannot drive those: the real tools agree with themselves.
# So each fixture is a directory holding a COPY of this file and stub siblings
# beside it - the same hand substitution the 1.1 falsifications used, done by
# the machine so it happens on every run instead of once.
#
# NOTHING IN THE REPOSITORY IS READ OR WRITTEN. Every fixture lives under
# `mktemp -d` and is removed on every exit path, signal included. No case runs
# against the committed spec, and no case runs the real sibling tools.
#
# EXIT CODES OF THE SELF-TEST ITSELF: 0 every case held, 1 at least one did not
# or a documented code was never reached, 2 it could not run - no temporary
# directory. That last one is a guard no case drives, which is said again in
# the NOT ASSERTED line the run prints.
# ---------------------------------------------------------------------------
if [ "$SELFTEST" -eq 1 ]; then
  SCRATCH="$(mktemp -d)" || { printf 'spec-doctor: cannot create a temporary directory, so no case was driven\n' >&2; exit 2; }
  trap 'rm -rf "$SCRATCH"' EXIT HUP INT TERM

  TAB=$'\t'

  # A stub is a two-line shell script beside a `.out` file and a `.rc` file.
  # Keeping the payload in files rather than in generated source is what lets a
  # case declare a reworded line or a moved column without quoting it twice.
  write_tool() { # write_tool <dir> <name> <rc> <stdout-text>
    printf '%s' "$4" > "$1/scripts/$2.out"
    printf '%s\n' "$3" > "$1/scripts/$2.rc"
    { printf '#!/usr/bin/env bash\n'
      printf 'd="$(dirname "$0")"\n'
      printf 'cat "$d/%s.out"\n' "$2"
      printf 'rc="$(cat "$d/%s.rc")"\n' "$2"
      printf 'exit "$rc"\n'
    } > "$1/scripts/$2"
    chmod +x "$1/scripts/$2"
  }

  # `validate-spec.py` is handed to python3 and is run TWICE per page, plain and
  # then with --counts, so its stub answers on both paths and each half carries
  # its own exit code. A single-mode stub would make section 2 a copy of
  # section 1 and neither could be driven alone.
  write_validate() { # write_validate <dir> <grammar-rc> <grammar-text> <counts-rc> <counts-text>
    printf '%s' "$3" > "$1/scripts/vs-grammar.out"
    printf '%s\n' "$2" > "$1/scripts/vs-grammar.rc"
    printf '%s' "$5" > "$1/scripts/vs-counts.out"
    printf '%s\n' "$4" > "$1/scripts/vs-counts.rc"
    { printf 'import os, sys\n'
      printf 'h = os.path.dirname(os.path.abspath(__file__))\n'
      printf 'p = "vs-counts" if "--counts" in sys.argv else "vs-grammar"\n'
      printf 'sys.stdout.write(open(os.path.join(h, p + ".out")).read())\n'
      printf 'sys.exit(int(open(os.path.join(h, p + ".rc")).read().strip()))\n'
    } > "$1/scripts/validate-spec.py"
  }

  # The healthy fixture: four siblings that agree with themselves, and a page
  # that therefore exits 0. Every case below is this fixture with exactly one
  # thing moved, so a case that goes red names the thing it moved.
  GRAMMAR_CLEAN='1 file(s) checked: 0 error(s), 0 warning(s)
'
  COUNTS_CLEAN="COUNT${TAB}spec.md${TAB}active${TAB}2${TAB}2
COUNT${TAB}spec.md${TAB}superseded${TAB}1${TAB}1
DECLARED${TAB}spec.md${TAB}9${TAB}2 active, 1 superseded, 0 withdrawn.
DERIVED${TAB}spec.md${TAB}9${TAB}2 active, 1 superseded, 0 withdrawn.
"
  PARSE_CLEAN="R1${TAB}10${TAB}active${TAB}-${TAB}The lifecycle shall do the thing.
R2${TAB}12${TAB}active${TAB}-${TAB}The lifecycle shall do the other thing.
R3${TAB}14${TAB}superseded${TAB}R1${TAB}The lifecycle shall do the old thing.
"
  ROWS_CLEAN='    active requirements examined: 2
    requirements missing an acceptance row: 0
'
  fixture() { # fixture <name>  -> echoes the fixture root
    d="$SCRATCH/$1"
    mkdir -p "$d/.claude/productizer" "$d/scripts"
    cp "$SELF" "$d/scripts/spec-doctor.sh"
    chmod +x "$d/scripts/spec-doctor.sh"
    printf '%s\n' '# fixture spec' > "$d/.claude/productizer/spec.md"
    write_validate "$d" 0 "$GRAMMAR_CLEAN" 0 "$COUNTS_CLEAN"
    write_tool "$d" spec-requirements.sh 0 "$PARSE_CLEAN"
    write_tool "$d" check-acceptance-rows.sh 0 "$ROWS_CLEAN"
    write_tool "$d" pending-rulings.sh 0 'none
'
    printf '%s\n' "$d"
  }

  CASES=0
  UPHELD=0
  REPORT=""
  CODES=""

  # Each case is driven through a COPY of this file, so the argument handling,
  # the tool resolution and every guard ahead of the summary are on the path.
  # `|| got=$?` because most of these exit non-zero on purpose and `set -e`
  # would otherwise end the run at the first one - right exit code, nothing
  # reported.
  drive() { # drive <name> <expected> <reason> <script> [argv...]
    name="$1"; expected="$2"; reason="$3"; shift 3
    got=0
    bash "$@" > "$SCRATCH/$name.out" 2> "$SCRATCH/$name.err" || got=$?
    CASES=$((CASES + 1))
    if [ "$got" = "$expected" ]; then
      UPHELD=$((UPHELD + 1)); verdict="held"
    else
      verdict="NOT HELD"
    fi
    CODES="$CODES$got
"
    REPORT="$REPORT      $name  expected $expected  got $got  $verdict  $reason
"
  }

  drive_fixture() { # drive_fixture <name> <expected> <reason> <dir>
    drive "$1" "$2" "$3" "$4/scripts/spec-doctor.sh" --root "$4"
  }

  # --- 0: the page ran end to end and found nothing -------------------------
  drive version 0 "--version states which build produced a verdict" "$SELF" --version
  drive help 0 "--help prints this header and reads nothing" "$SELF" --help

  CLEAN_DIR="$(fixture clean)"
  drive_fixture clean 0 "four siblings that agree with themselves: five sections ran, nothing found" "$CLEAN_DIR"

  ZERO_DIR="$(fixture rulings-zero)"
  write_tool "$ZERO_DIR" pending-rulings.sh 0 '0
'
  drive_fixture rulings-measured-zero 0 "a measured 0 pending with the exit 0 its contract gives it is clean, and is not the word none" "$ZERO_DIR"

  # --- 1: every section ran, and something was found ------------------------
  WARN_DIR="$(fixture validate-warn)"
  write_validate "$WARN_DIR" 0 'spec.md:12: WARN EARS_TWO_SHALL two shall clauses
1 file(s) checked: 0 error(s), 1 warning(s)
' 0 "$COUNTS_CLEAN"
  drive_fixture validate-warn 1 "a WARN is a finding here even though validate-spec.py exits 0 on one, because this page is not a merge gate" "$WARN_DIR"

  ERR_DIR="$(fixture validate-error)"
  write_validate "$ERR_DIR" 1 'spec.md:12: ERROR EARS_NO_SHALL no shall clause
1 file(s) checked: 1 error(s), 0 warning(s)
' 0 "$COUNTS_CLEAN"
  drive_fixture validate-error 1 "exit 1 and a line matching the grep agree, so the finding is counted and the count is a measurement" "$ERR_DIR"

  STALE_DIR="$(fixture counts-stale)"
  write_validate "$STALE_DIR" 0 "$GRAMMAR_CLEAN" 1 "COUNT${TAB}spec.md${TAB}active${TAB}7${TAB}2
DECLARED${TAB}spec.md${TAB}9${TAB}7 active.
DERIVED${TAB}spec.md${TAB}9${TAB}2 active.
"
  drive_fixture counts-stale 1 "a header that disagrees with the file is validate-spec.py --counts exit 1, and this page relays it as a finding" "$STALE_DIR"

  CHAIN_DIR="$(fixture chain-two-hop)"
  write_tool "$CHAIN_DIR" spec-requirements.sh 0 "R1${TAB}10${TAB}active${TAB}-${TAB}The lifecycle shall do the thing.
R2${TAB}12${TAB}superseded${TAB}R3${TAB}The lifecycle shall do the old thing.
R3${TAB}14${TAB}superseded${TAB}R1${TAB}The lifecycle shall do the older thing.
"
  drive_fixture chain-two-hop 1 "R2 to R3 to R1 - a citation that lands on a superseded id and needs two hops to reach a live one" "$CHAIN_DIR"

  ROWSF_DIR="$(fixture rows-findings)"
  write_tool "$ROWSF_DIR" check-acceptance-rows.sh 1 '    requirements missing an acceptance row: 4
'
  drive_fixture rows-findings 1 "section 4 keys off that tool exit code, deliberately, and relays a 1 as a finding" "$ROWSF_DIR"

  PEND_DIR="$(fixture rulings-pending)"
  write_tool "$PEND_DIR" pending-rulings.sh 1 '3
'
  drive_fixture rulings-pending 1 "3 pending and the exit 1 its contract gives that - the finding branch 1.1 made reachable at all" "$PEND_DIR"

  # --- 2: a section could not run, and that outranks any finding ------------
  drive unknown-argument 2 "an argument this page does not know is refused rather than ignored" "$SELF" --nope
  drive root-without-value 2 "--root with nothing after it is a refusal, never a silent default" "$SELF" --root
  drive spec-without-value 2 "--spec with nothing after it is a refusal" "$SELF" --spec

  ABSENT_DIR="$(fixture spec-absent)"
  rm -f "$ABSENT_DIR/.claude/productizer/spec.md"
  drive_fixture spec-absent 2 "a spec that cannot be read is unmeasured before any section runs, never a clean page" "$ABSENT_DIR"

  NOVAL_DIR="$(fixture validate-absent)"
  rm -f "$NOVAL_DIR/scripts/validate-spec.py"
  drive_fixture validate-absent 2 "a tool that is not there is reported, never skipped - R13, twice, for sections 1 and 2" "$NOVAL_DIR"

  NOPARSE_DIR="$(fixture parse-absent)"
  rm -f "$NOPARSE_DIR/scripts/spec-requirements.sh"
  drive_fixture parse-absent 2 "no parser, so no supersede pointer was followed" "$NOPARSE_DIR"

  UNEXEC_DIR="$(fixture parse-not-executable)"
  chmod -x "$UNEXEC_DIR/scripts/spec-requirements.sh"
  drive_fixture parse-not-executable 2 "a parser present but not executable is the same hole as an absent one" "$UNEXEC_DIR"

  NOROWS_DIR="$(fixture rows-absent)"
  rm -f "$NOROWS_DIR/scripts/check-acceptance-rows.sh"
  drive_fixture rows-absent 2 "whether every active requirement has a row is unknown, not zero" "$NOROWS_DIR"

  NORUL_DIR="$(fixture rulings-absent)"
  rm -f "$NORUL_DIR/scripts/pending-rulings.sh"
  drive_fixture rulings-absent 2 "whether a contradiction is waiting on a human is unknown" "$NORUL_DIR"

  # 1.1, section 1. The falsification this branch was written from: a severity
  # token reworded, nothing else, and the page printed `0 error line(s)` and
  # EXIT 0 with the error line on screen directly above it.
  REWORD_DIR="$(fixture validate-severity-reworded)"
  write_validate "$REWORD_DIR" 1 'spec.md:12: [error] EARS_NO_SHALL no shall clause
1 file(s) checked: 1 error(s), 0 warning(s)
' 0 "$COUNTS_CLEAN"
  drive_fixture validate-severity-reworded 2 "1.1 section 1: exit 1 - at least one ERROR - and not one line matches the grep, so the count printed is not a measurement" "$REWORD_DIR"

  VRC_DIR="$(fixture validate-rc-unmapped)"
  write_validate "$VRC_DIR" 4 'spec.md could not be read
' 0 "$COUNTS_CLEAN"
  drive_fixture validate-rc-unmapped 2 "validate-spec.py exit 4 is its own NOT MEASURED, and this page will not read it as a pass" "$VRC_DIR"

  CRC_DIR="$(fixture counts-rc-unmapped)"
  write_validate "$CRC_DIR" 0 "$GRAMMAR_CLEAN" 4 'nothing to count
'
  drive_fixture counts-rc-unmapped 2 "--counts exit 4 means no comparison was made, so the header was compared against nothing" "$CRC_DIR"

  # 1.1, section 3. The falsification: a stub emitting the same fields in a
  # different order exited 0, and the walk reported `0 superseded requirement(s)`
  # having followed nothing.
  MOVED_DIR="$(fixture chain-columns-moved)"
  write_tool "$MOVED_DIR" spec-requirements.sh 0 "active${TAB}R1${TAB}10${TAB}-${TAB}The lifecycle shall do the thing.
superseded${TAB}R3${TAB}14${TAB}R1${TAB}The lifecycle shall do the old thing.
"
  drive_fixture chain-columns-moved 2 "1.1 section 3: the same fields in a different order - the status column now holds a line number, so no chain was followed" "$MOVED_DIR"

  EMPTY_DIR="$(fixture chain-no-rows)"
  write_tool "$EMPTY_DIR" spec-requirements.sh 0 ''
  drive_fixture chain-no-rows 2 "a parser that exits 0 and returns no requirement rows at all walked nothing; a spec holding no requirements is NO_REQUIREMENTS, never a clean walk" "$EMPTY_DIR"

  PRC_DIR="$(fixture parse-rc-nonzero)"
  write_tool "$PRC_DIR" spec-requirements.sh 3 'spec-requirements: cannot read the spec
'
  drive_fixture parse-rc-nonzero 2 "a parser that refused followed no chain, and its refusal is printed where it happened" "$PRC_DIR"

  RRC_DIR="$(fixture rows-rc-unmapped)"
  write_tool "$RRC_DIR" check-acceptance-rows.sh 3 'check-acceptance-rows: refused
'
  drive_fixture rows-rc-unmapped 2 "an exit code that check has no verdict for is a hole in this page, not a pass" "$RRC_DIR"

  # 1.1, section 5, three ways. The falsification: a stub printing
  # `pending rulings: 3` and exiting 0 printed that line, then printed the
  # `never raised one` explanation underneath it, counted no finding and exited
  # 0 - three rulings waiting on a human, and the page said the spec was clean.
  UNPARSE_DIR="$(fixture rulings-unparseable)"
  write_tool "$UNPARSE_DIR" pending-rulings.sh 0 'pending rulings: 3
'
  drive_fixture rulings-unparseable 2 "1.1 section 5: --format count promises one token, a whole number or none, and this is neither - what is waiting is UNKNOWN" "$UNPARSE_DIR"

  DISAGREE_DIR="$(fixture rulings-count-code-disagree)"
  write_tool "$DISAGREE_DIR" pending-rulings.sh 0 '3
'
  drive_fixture rulings-count-code-disagree 2 "1.1 section 5: 3 pending with exit 0 is two different answers from one run, not a choice between them" "$DISAGREE_DIR"

  ZDIS_DIR="$(fixture rulings-zero-code-disagree)"
  write_tool "$ZDIS_DIR" pending-rulings.sh 1 '0
'
  drive_fixture rulings-zero-code-disagree 2 "1.1 section 5, the other direction: 0 pending with exit 1 is the same disagreement" "$ZDIS_DIR"

  NONE1_DIR="$(fixture rulings-none-exit-1)"
  write_tool "$NONE1_DIR" pending-rulings.sh 1 'none
'
  drive_fixture rulings-none-exit-1 2 "nothing can be waiting where nothing was raised, so none with exit 1 is unknown rather than clean" "$NONE1_DIR"

  RRC5_DIR="$(fixture rulings-rc-unmapped)"
  write_tool "$RRC5_DIR" pending-rulings.sh 7 'pending-rulings: refused
'
  drive_fixture rulings-rc-unmapped 2 "an exit code outside that tool contract is a hole, whatever is on stdout" "$RRC5_DIR"

  # The ranking itself, which is the one thing no single-section case can show.
  RANK_DIR="$(fixture unmeasured-outranks-findings)"
  write_tool "$RANK_DIR" pending-rulings.sh 1 '3
'
  write_tool "$RANK_DIR" check-acceptance-rows.sh 3 'check-acceptance-rows: refused
'
  drive_fixture unmeasured-outranks-findings 2 "one real finding AND one hole on the same page exits 2: a report with a hole in it has not found nothing, it has not looked" "$RANK_DIR"

  # --- the two assertions ---------------------------------------------------
  [ "$CASES" -gt 0 ] || { printf 'spec-doctor: no case was driven, so nothing was measured\n' >&2; exit 2; }

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"

  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/ *$//')"
  MISSING=""
  for want in 0 1 2; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"

  if [ "$CASES" = "$UPHELD" ]; then SELF_VERDICT="held"; else SELF_VERDICT="NOT HELD"; fi
  printf '    R39.a  %-40s examined %3d  upheld %3d  %s: %s\n' \
    "each-case-exits-the-declared-code" "$CASES" "$UPHELD" "$SELF_VERDICT" \
    "every case exits with the code its line declares"
  if [ -n "$MISSING" ]; then CODE_VERDICT="NOT HELD"; else CODE_VERDICT="held"; fi
  printf '    R39.b  %-40s examined %3d  upheld %3d  %s: %s\n' \
    "every-documented-exit-code-reached" 3 "$((3 - $(printf '%s' "$MISSING" | wc -w | tr -d ' ')))" "$CODE_VERDICT" \
    "the codes the header documents are the codes the cases drove"
  [ -z "$MISSING" ] || printf 'spec-doctor: documented exit code(s) never reached by any case:%s\n' "$MISSING" >&2

  printf '    NOT ASSERTED: the cases drive the exit CODE, never the wording of a finding, so a case red for the wrong reason is invisible here. Section 3 `is_count` guard is NOT driven: the walk own awk always prints four %%d, so no sibling output can make those four tallies non-numeric - it guards a change to that awk, which only a diff can reach. Section 4 display grep is not asserted; 1.1 measured by hand that rewording past it keeps the verdict and loses the detail. The self-test own exit 2 - no temporary directory - is a guard no case drives. Every fixture is a stub under mktemp; no case reads the committed spec or runs a real sibling tool.\n'

  [ "$CASES" = "$UPHELD" ] || exit 1
  [ -z "$MISSING" ] || exit 1
  exit 0
fi

FINDINGS=0
UNMEASURED=0

finding() { FINDINGS=$((FINDINGS + 1)); }
unmeasured() {
  UNMEASURED=$((UNMEASURED + 1))
  printf '    COULD NOT MEASURE: %s\n' "$1"
}

section() { printf '\n%s\n' "$1"; printf '%s\n' "----------------------------------------------------------------------"; }

# A tool that is not there is REPORTED, never skipped - R13. `runnable`
# answers for the file; the caller decides what its section says without it.
# `validate-spec.py` is handed to `python3`, so only the shell tools, which
# are executed directly, need the execute bit.
runnable() { [ -f "$1" ] && [ -x "$1" ]; }

# EVERY NUMBER BELOW IS DERIVED FROM ANOTHER TOOL'S OUTPUT, AND A DERIVATION IS
# A MEASUREMENT THAT CAN FAIL. When a tool's wording or column layout moves, the
# awk or the grep that lifts its number returns nothing - and nothing, read as a
# number, is the most flattering answer there is. `is_count` is the gate: what is
# not a whole number is a hole in this page, reported through `unmeasured`, never
# treated as zero. That is P1 applied to this script's own arithmetic rather than
# only to the tools it runs.
is_count() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

printf 'spec-doctor %s\n' "${VERSION#spec-doctor }"
printf 'spec: %s\n' "$SPEC"
if [ ! -f "$SPEC" ] || [ ! -r "$SPEC" ]; then
  printf 'spec-doctor: cannot read %s. An unreadable spec is unmeasured, not clean - no section below could run.\n' "$SPEC" >&2
  exit 2
fi
printf 'root: %s\n' "$ROOT"

# ------------------------------------------------- 1. grammar and id permanence

section "1. GRAMMAR AND ID PERMANENCE  (validate-spec.py)"
if [ ! -f "$VALIDATE" ]; then
  unmeasured "$VALIDATE is not there; the grammar and the ids were not checked"
else
  set +e
  VALIDATE_OUT="$(python3 "$VALIDATE" "$SPEC" 2>&1)"
  VALIDATE_RC=$?
  set -e
  printf '%s\n' "$VALIDATE_OUT" | sed 's/^/    /'
  case "$VALIDATE_RC" in
    0|1) ;;
    *) unmeasured "validate-spec.py exited $VALIDATE_RC; its own contract calls that unmeasured or a usage error, not a pass" ;;
  esac
  V_ERRORS="$(printf '%s\n' "$VALIDATE_OUT" | grep -c ' ERROR ' || true)"
  V_WARNS="$(printf '%s\n' "$VALIDATE_OUT" | grep -c ' WARN ' || true)"
  printf '    -> %s error line(s), %s warning line(s)\n' "$V_ERRORS" "$V_WARNS"
  # THE EXIT CODE IS THE MEASUREMENT AND THE TWO COUNTS ARE THE DETAIL, and
  # where they disagree this page says so rather than believing the quiet one.
  # `validate-spec.py` documents 1 as "at least one ERROR", so a 1 is a finding
  # whatever the grep matched - and a 1 with no line matching ` ERROR ` means
  # its report format has moved out from under this grep, which makes the count
  # printed above UNKNOWN rather than zero.
  #
  # Falsified 2026-09-06: a stub printing `spec.md:12: [error] EARS_NO_SHALL`
  # and exiting 1 - a severity token reworded, nothing else - printed
  # `0 error line(s)` and `EXIT 0 - every section ran and found nothing`, with
  # the error line itself on screen directly above it.
  [ "$V_WARNS" -eq 0 ] || finding
  if [ "$VALIDATE_RC" -eq 1 ]; then
    finding
    [ "$V_ERRORS" -gt 0 ] ||
      unmeasured "validate-spec.py exited 1 - its own contract's \"at least one ERROR\" - and not one line above matched \` ERROR \`. Its report format has moved, so the error count printed here is not a measurement."
  elif [ "$V_ERRORS" -ne 0 ]; then
    finding
  fi
fi

# --------------------------------------------------- 2. counts, declared v counted

section "2. COUNTS, DECLARED VERSUS COUNTED  (validate-spec.py --counts)"
if [ ! -f "$VALIDATE" ]; then
  unmeasured "$VALIDATE is not there; the header counts were compared against nothing"
else
  set +e
  COUNTS_OUT="$(python3 "$VALIDATE" --counts "$SPEC" 2>&1)"
  COUNTS_RC=$?
  set -e
  printf '    %-12s %10s %10s   %s\n' status declared counted verdict
  printf '%s\n' "$COUNTS_OUT" | awk -F'\t' '
    $1 == "COUNT" {
      verdict = ($4 == "-") ? "NOT DECLARED" : ($4 == $5 ? "agrees" : "STALE")
      printf "    %-12s %10s %10s   %s\n", $3, $4, $5, verdict
    }'
  printf '%s\n' "$COUNTS_OUT" | awk -F'\t' '
    $1 == "DECLARED" { printf "    the header says   : %s   (line %s)\n", $4, $3 }
    $1 == "DERIVED"  { printf "    the file counts to: %s\n", $4 }
    $1 !~ /^(COUNT|DECLARED|DERIVED)$/ { printf "    %s\n", $0 }'
  case "$COUNTS_RC" in
    0) ;;
    1) finding ;;
    *) unmeasured "validate-spec.py --counts exited $COUNTS_RC; no comparison was made" ;;
  esac
fi

# ------------------------------------------------------- 3. superseded chains

section "3. SUPERSEDED CHAINS  (spec-requirements.sh, walked)"
if ! runnable "$PARSE"; then
  unmeasured "$PARSE is not there; the supersede pointers were not followed"
else
  set +e
  PARSE_OUT="$("$PARSE" "$SPEC" 2>&1)"
  PARSE_RC=$?
  set -e
  if [ "$PARSE_RC" -ne 0 ]; then
    printf '%s\n' "$PARSE_OUT" | sed 's/^/    /'
    unmeasured "spec-requirements.sh exited $PARSE_RC; no chain was followed"
  else
    CHAIN_OUT="$(printf '%s\n' "$PARSE_OUT" | awk -F'\t' '
      # `printf %s\n` on an empty capture emits one blank line, which awk
      # counts as a record. Dropping it here is what lets "no rows at all" and
      # "rows whose columns moved" be told apart below instead of both arriving
      # as one unrecognised status.
      /^[[:space:]]*$/ { next }
      { status[$1] = $3; target[$1] = $4; order[++n] = $1
        # spec-requirements.sh documents four status words and no others. A row
        # carrying a fifth means this walk is reading the wrong COLUMN, and a
        # walk over the wrong column finds no bad chains for the same reason a
        # walk over an empty file does.
        if ($3 != "active" && $3 != "superseded" && $3 != "withdrawn" && $3 != "malformed") unrecognised++ }
      END {
        bad = 0
        shown = 0
        for (i = 1; i <= n; i++) {
          id = order[i]
          if (status[id] != "superseded") continue
          shown++
          chain = id
          cur = id
          hops = 0
          note = ""
          while (1) {
            nxt = target[cur]
            if (nxt == "" || nxt == "-") { note = "POINTS AT NOTHING"; break }
            chain = chain " -> " nxt
            if (!(nxt in status)) { note = "TARGET NOT IN THIS FILE"; break }
            if (++hops > 50) { note = "CYCLE"; break }
            if (status[nxt] != "superseded") break
            cur = nxt
          }
          # A chain longer than one hop means this marker points at a
          # requirement that is ITSELF superseded - the exact thing the R14
          # note in this repo says was avoided by moving the pointer, because
          # a citation has to reach a sentence someone may still act on. It is
          # a finding, not decoration.
          if (note == "" && hops > 1) note = "POINTS AT A SUPERSEDED ID, " hops " HOPS TO A LIVE ONE"
          if (note != "") bad++
          if (note == "") note = "ends on active " nxt
          printf "    %-52s %s\n", chain, note
        }
        printf "COUNTS %d %d %d %d\n", shown, bad, n, unrecognised + 0
      }')"
    printf '%s\n' "$CHAIN_OUT" | grep -v '^COUNTS ' || true
    CHAIN_SHOWN="$(printf '%s\n' "$CHAIN_OUT" | awk '/^COUNTS /{print $2}')"
    CHAIN_BAD="$(printf '%s\n' "$CHAIN_OUT" | awk '/^COUNTS /{print $3}')"
    CHAIN_ROWS="$(printf '%s\n' "$CHAIN_OUT" | awk '/^COUNTS /{print $4}')"
    CHAIN_UNRECOGNISED="$(printf '%s\n' "$CHAIN_OUT" | awk '/^COUNTS /{print $5}')"
    # This is the one section that does arithmetic of its own, so it is the one
    # section whose arithmetic can be reading a file layout that no longer
    # exists. Falsified 2026-09-06: a spec-requirements.sh stub emitting the
    # same fields in a different order exited 0 and this page printed
    # `0 superseded requirement(s), 0 chain(s)` and `EXIT 0`, having walked
    # nothing.
    if ! is_count "$CHAIN_SHOWN" || ! is_count "$CHAIN_BAD" ||
       ! is_count "$CHAIN_ROWS" || ! is_count "$CHAIN_UNRECOGNISED"; then
      unmeasured "the chain walk produced no tallies of its own, so nothing above was counted and no chain was followed"
    elif [ "$CHAIN_ROWS" -eq 0 ]; then
      unmeasured "spec-requirements.sh exited 0 and returned no requirement rows at all. No chain was followed; a spec holding no requirements is validate-spec.py's NO_REQUIREMENTS, never a clean chain walk"
    elif [ "$CHAIN_UNRECOGNISED" -gt 0 ]; then
      unmeasured "$CHAIN_UNRECOGNISED of $CHAIN_ROWS row(s) from spec-requirements.sh carry a status this page does not recognise - its contract has only active, superseded, withdrawn and malformed. The column this walk reads has moved, so \"no unfollowable chains\" is a statement about the wrong field"
    else
      printf '    -> %s superseded requirement(s), %s chain(s) a reader cannot follow to a live id in one hop\n' \
        "$CHAIN_SHOWN" "$CHAIN_BAD"
      [ "$CHAIN_BAD" -eq 0 ] || finding
    fi
  fi
fi

# --------------------------------------------------------- 4. acceptance rows

section "4. ACCEPTANCE ROWS  (check-acceptance-rows.sh)"
if ! runnable "$ROWS"; then
  unmeasured "$ROWS is not there; whether every active requirement has a row is unknown"
else
  set +e
  ROWS_OUT="$("$ROWS" --root "$ROOT" --spec "$SPEC" 2>&1)"
  ROWS_RC=$?
  set -e
  # The per-citation dump is that check's own page. What belongs on THIS page
  # is the tallies and the ids it could not verify - the rest is one command
  # away and printing it here buries the two lines somebody came for.
  printf '%s\n' "$ROWS_OUT" \
    | grep -E 'requirements read:|active requirements examined:|no row required:|acceptance criteria rows read:|requirements missing an acceptance row:|rows naming something that does not resolve:|^ *NOT VERIFIED|^ *R[0-9]+ +[^ ]+:[0-9]+$' \
    | sed 's/^ */    /' || true
  case "$ROWS_RC" in
    0) ;;
    1) finding
       printf '    -> check-acceptance-rows.sh reported findings; run it directly for the full page\n' ;;
    *) printf '%s\n' "$ROWS_OUT" | sed 's/^/    /'
       unmeasured "check-acceptance-rows.sh exited $ROWS_RC" ;;
  esac
fi

# ------------------------------------------------------------- 5. rulings

section "5. RULINGS AWAITING A HUMAN  (pending-rulings.sh)"
if ! runnable "$RULINGS"; then
  unmeasured "$RULINGS is not there; whether a contradiction is waiting is unknown"
else
  set +e
  RULINGS_OUT="$("$RULINGS" --root "$ROOT" --format count 2>&1)"
  RULINGS_RC=$?
  set -e
  printf '%s\n' "$RULINGS_OUT" | sed 's/^/    /'
  # `--format count` promises ONE token on stdout: a whole number, or the word
  # `none`. Nothing else is that contract, and this page will not guess which of
  # the two an unrecognised line meant.
  #
  # Falsified 2026-09-05 and again 2026-09-06 (B41): a stub printing
  # `pending rulings: 3` and exiting 0 made this section print that line, then
  # print the `never raised one` explanation underneath it, count no finding and
  # exit 0 - three rulings waiting on a human, and the page said the spec was
  # clean. The word `none` had become the only thing the section could tell
  # apart from a number, so every OTHER output read as `none`.
  #
  # The exit code is read alongside the token, not instead of it. pending-rulings.sh
  # documents 1 as "at least one pending ruling exists", so a 1 is where the
  # finding lives; before this, a 1 fell through to the catch-all and a REAL
  # pending ruling was reported as COULD NOT MEASURE - which meant the finding
  # branch below could never fire against the real tool at all. And a code that
  # disagrees with the token is two answers from one run: unmeasured, not a
  # choice between them.
  PENDING="$(printf '%s\n' "$RULINGS_OUT" | awk '/^[0-9]+$/{print; exit}')"
  NEVER_RAISED="$(printf '%s\n' "$RULINGS_OUT" | awk '/^none$/{print; exit}')"
  case "$RULINGS_RC" in
    0|1)
      if is_count "$PENDING"; then
        if [ "$PENDING" -gt 0 ] && [ "$RULINGS_RC" -ne 1 ]; then
          unmeasured "pending-rulings.sh reported $PENDING pending and exited $RULINGS_RC; its contract makes that exit 1, so the count and the code are two different answers from one run"
        elif [ "$PENDING" -eq 0 ] && [ "$RULINGS_RC" -ne 0 ]; then
          unmeasured "pending-rulings.sh reported 0 pending and exited $RULINGS_RC; its contract makes a true zero exit 0, so the count and the code are two different answers from one run"
        elif [ "$PENDING" -gt 0 ]; then
          finding
          printf '    -> %s ruling(s) pending; R12 says nothing that depends on them may merge\n' "$PENDING"
        else
          printf '    -> 0 pending, measured.\n'
        fi
      elif [ -n "$NEVER_RAISED" ] && [ "$RULINGS_RC" -eq 0 ]; then
        printf '    -> `none` is the word that tool uses for "never raised one". It is\n'
        printf '       not a measured 0, and it is not a hole in this page either: nothing\n'
        printf '       can be waiting where nothing was ever raised.\n'
      elif [ -n "$NEVER_RAISED" ]; then
        unmeasured "pending-rulings.sh printed \`none\` - never raised one - and exited $RULINGS_RC rather than 0. Nothing can be waiting where nothing was raised, so what this run measured is UNKNOWN"
      else
        unmeasured "pending-rulings.sh exited $RULINGS_RC and printed no count this page can read: \`--format count\` promises one token, a whole number or the word \`none\`, and neither is on stdout above. What is waiting on a human is UNKNOWN, and this page will not read an unparseable line as nothing"
      fi ;;
    *) unmeasured "pending-rulings.sh exited $RULINGS_RC" ;;
  esac
fi

# ------------------------------------------------------------------ summary

section "SUMMARY"
printf '    sections that could not run: %d\n' "$UNMEASURED"
printf '    sections reporting findings: %d\n' "$FINDINGS"
printf '    this command reports; it changes nothing. Nothing above was fixed.\n'

if [ "$UNMEASURED" -gt 0 ]; then
  printf '    EXIT 2 - the page has a hole in it. What did not run is not what was found to be clean.\n'
  exit 2
fi
if [ "$FINDINGS" -gt 0 ]; then
  printf '    EXIT 1 - findings above.\n'
  exit 1
fi
printf '    EXIT 0 - every section ran and found nothing.\n'
exit 0
