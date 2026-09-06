#!/usr/bin/env bash
# spec-doctor.sh [--version] [--help] [--root DIR] [--spec PATH]
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

VERSION="spec-doctor 1.1"

ROOT="."
SPEC=""

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
    *) refuse "unknown argument: $1" ;;
  esac
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[ -n "$SPEC" ] || SPEC="$ROOT/.claude/productizer/spec.md"

VALIDATE="$SCRIPT_DIR/validate-spec.py"
PARSE="$SCRIPT_DIR/spec-requirements.sh"
ROWS="$SCRIPT_DIR/check-acceptance-rows.sh"
RULINGS="$SCRIPT_DIR/pending-rulings.sh"

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
