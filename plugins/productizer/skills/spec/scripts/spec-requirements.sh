#!/usr/bin/env bash
# spec-requirements.sh [--version] [--help] [--selftest] [--require-records]
#                      <spec-file>
#
# Parses the `## Requirements` section of a living spec and emits one TSV
# record per requirement DEFINITION:
#
#     <id> TAB <line> TAB <status> TAB <target> TAB <text>
#
#   status  one of active, superseded, withdrawn, malformed
#   target  R<n> for `superseded`, otherwise a single `-`
#   text    the requirement sentence with the status marker removed and all
#           whitespace collapsed to single spaces, so two spellings of the
#           same sentence across a re-wrap do not read as an edit
#
# NOT A CHECK. It has no findings and no coverage output; it is the one parser
# both `check-superseded-text.sh` and `check-pending-ruling-scope.sh` read the
# spec through. Two checks that must agree on what R14's text IS cannot each
# carry their own parser: the day the two disagree, one of them reports a
# requirement unchanged and the other reports it edited, and both are green in
# their own terms.
#
# THE GRAMMAR IS `references/format-spec.md`, not this file. Section 1 for the
# id form, section 3 for the status markers. Where this parser is deliberately
# more permissive than the normative grammar it is noted below - a parser that
# refuses a non-canonical spelling reports a requirement as absent, which is
# the one wrong answer that looks like nothing to do.
#
#   - The id separator may be an em dash, an en dash or a hyphen. format-spec
#     says a hyphen "parses but is non-canonical"; `validate-spec.py` warns on
#     it and this parser accepts it, because a warning about punctuation must
#     not make a superseded requirement invisible to the retention check.
#   - A requirement that wraps over several lines is joined. Only the first
#     marker-shaped line in the item is read as the status.
#   - A continuation line is read as a MARKER only when it begins with
#     `Superseded` or `Withdrawn` in any case. Anything else is requirement
#     text. Guessing more widely would let ordinary continuation prose flip a
#     requirement's status, and the status is what the whole retention rule
#     turns on.
#   - A second marker in one item is `malformed`, never "the first one wins".
#     Two markers is a requirement whose status is undefined, and picking one
#     is inventing the answer.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  parsed, and something was found. Without `--require-records` a zero
#      record parse is also a 0: it is a legitimate parse of a spec with no
#      requirements, and refusing it is the CALLER's job. That division of
#      responsibility is kept, because every caller in this repository reads
#      any non-zero as "the parser refused" and dies unmeasured on it.
#   2  could not run - bad usage, or a file that could not be read.
#   3  --selftest failed.
#   4  NOT MEASURED. `--require-records` was asked for and the parse found
#      nothing: the file was read end to end and no requirement in it was
#      understood. Opt-in, never the default.
#
# There is no exit 1: this parser has no opinion about what it read.
#
# THE SHARED CONVENTION. 4 is `validate-spec.py`'s EXIT_UNMEASURED, which
# answers the identical question with the identical code and the sentence "a
# file that was not read has not passed". `contradiction-check.py` uses the
# same 4 - and there it is the DEFAULT, with `--allow-empty` to opt out.
#
# WHY IT IS NOT THE DEFAULT HERE, MEASURED RATHER THAN ARGUED. This file's exit
# 0 on zero records is a PARSER's answer, never a check's verdict, and every
# caller turns it into a refusal of its own. Measured over a git repository
# whose spec was a spec-kit file, and again with an empty spec - all six exit
# 2 with their own sentence, and none reads the 0 as a pass:
#
#   check-superseded-text.sh       "holds no requirement definitions"
#   check-pending-ruling-scope.sh  "holds no requirement definitions"
#   check-changelog-row.sh         "holds no requirement definitions"
#   check-spec-integrity.sh        "holds no requirement definitions"
#   check-suspect-links.sh         "holds no requirement definitions"
#   spec-doctor.sh                 "exited 0 and returned no requirement rows"
#
# Flipping the default was then tried in a scratch clone. It broke four
# self-test cases in three of those callers - check-superseded-text.sh
# `no-requirements`, check-spec-integrity.sh `no-requirements`,
# check-suspect-links.sh `no-requirements-now` and `no-requirements-at-base` -
# each still exiting 2, but through "the parser refused" instead of the
# sentence its contract declares. Passing `--require-records` from those
# callers has the same effect, so it is not a cheaper route. The callers also
# parse HISTORICAL revisions (every version git can reach, or a base commit),
# where a revision that predates any requirement is an expected zero. Driven
# in a two-commit repository whose first commit held an empty `## Requirements`
# and whose second added R1: `check-superseded-text.sh` exits 0 with PASS
# today, and under a refusing default it exits 4 - the parser's code, escaping
# its history loop, which pipes the parser under `set -o pipefail` with no
# `||`. None of the 23 revisions of this repository's own spec parse empty, so
# no run here would have shown it.
#
# So the rule is: 0 with no records means "read, found none", and the CALLER
# owns refusing it. A caller that cannot own that - a new one, or one run by
# hand - passes `--require-records`. A caller that moves to the flag must
# read 4 as its own "no requirement definitions" refusal, not as a generic
# parser failure, and must not pass it on historical revisions.
set -euo pipefail

# 1.1 added --require-records and the self-test that drives it. The record
# format and the default exit codes are unchanged from 1.0.
VERSION="spec-requirements 1.1"

usage() {
  printf 'usage: spec-requirements.sh [--version] [--help] [--selftest]\n'
  printf '                            [--require-records] <spec-file>\n'
  printf '  Emits: <id> TAB <line> TAB <status> TAB <target> TAB <text>\n'
  printf '  --require-records  exit 4 when the parse found nothing\n'
}

die_unmeasured() { printf 'spec-requirements: %s\n' "$1" >&2; exit 2; }

# --------------------------------------------------------------------------
# SELF-TEST. R39: every exit code this parser can return is driven here, and
# the ones the `--require-records` convention added - a 4 for a clean parse
# that understood nothing, and the 0 that must still come back when the same
# file DOES hold requirements - are the reason it exists. Each case names the
# exit code it expects, so a case that stops driving one is visible rather
# than quietly passing on a different code. Exit 3 when a case disagrees.
#
# It re-invokes this file rather than calling the parser in-process: what a
# caller sees is a process exit status, and an in-process test of the awk
# program would not have caught a flag the argument loop never reached.
SELF="${BASH_SOURCE[0]}"
ST_DIR=""
ST_FAILS=0
ST_TOTAL=0

st_case() {
  # st_case <name> <expected-exit> <expected-records> [args...]
  local name="$1" want_rc="$2" want_n="$3"
  shift 3
  local rc=0 n=0
  ST_TOTAL=$((ST_TOTAL + 1))
  bash "$SELF" "$@" > "$ST_DIR/out" 2> "$ST_DIR/err" || rc=$?
  n="$(awk 'END { print NR }' "$ST_DIR/out")"
  if [ "$rc" -eq "$want_rc" ] && [ "$n" -eq "$want_n" ]; then
    printf '  ok    %-46s exit %s, %s records\n' "$name" "$rc" "$n"
    return 0
  fi
  ST_FAILS=$((ST_FAILS + 1))
  printf '  FAIL  %-46s exit %s (wanted %s), %s records (wanted %s)\n' \
    "$name" "$rc" "$want_rc" "$n" "$want_n"
  sed 's/^/          stderr: /' "$ST_DIR/err"
  return 0
}

selftest() {
  ST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spec-requirements-selftest.XXXXXX")" ||
    die_unmeasured "could not create a temporary directory for the self-test"
  trap 'rm -rf "$ST_DIR"' EXIT HUP INT TERM

  # A spec this parser understands.
  {
    printf '## Requirements\n\n'
    printf -- '- **R1** \342\200\224 When an intent arrives, the lifecycle shall classify it.\n'
    printf -- '- **R2** \342\200\224 The lifecycle shall hold one living spec.\n'
  } > "$ST_DIR/good.md"

  # A file shaped like a foreign spec: headings this parser has no grammar
  # for, and not one line it can read as a requirement. This is the case the
  # flag exists for - a real spec-kit spec parses to exactly this, zero
  # records with nothing on stderr.
  {
    printf '# Feature Specification: Archive old files\n\n'
    printf '## User Scenarios & Testing\n\n'
    printf -- '- **FR-001**: System MUST archive files older than the threshold.\n'
    printf -- '- **FR-002**: System MUST skip symbolic links.\n'
  } > "$ST_DIR/foreign.md"

  printf 'spec-requirements self-test\n\n'
  st_case "a spec with requirements"                 0 2 "$ST_DIR/good.md"
  st_case "the same spec, --require-records"         0 2 --require-records "$ST_DIR/good.md"
  st_case "a foreign file, default"                  0 0 "$ST_DIR/foreign.md"
  st_case "a foreign file, --require-records"        4 0 --require-records "$ST_DIR/foreign.md"
  st_case "a file that is not there"                 2 0 "$ST_DIR/absent.md"
  st_case "not there, --require-records"             2 0 --require-records "$ST_DIR/absent.md"
  st_case "no file given"                            2 0
  st_case "two spec files"                           2 0 "$ST_DIR/good.md" "$ST_DIR/foreign.md"
  st_case "an option this parser does not know"      2 0 --nonsense "$ST_DIR/good.md"

  # The refusal must SAY it was not measured, or a caller reading the log
  # cannot tell 4 from any other non-zero.
  ST_TOTAL=$((ST_TOTAL + 1))
  local rc=0
  bash "$SELF" --require-records "$ST_DIR/foreign.md" > "$ST_DIR/out" 2> "$ST_DIR/err" || rc=$?
  if grep -q 'NOT MEASURED' "$ST_DIR/err"; then
    printf '  ok    %-46s exit %s\n' "the 4 names itself NOT MEASURED" "$rc"
  else
    ST_FAILS=$((ST_FAILS + 1))
    printf '  FAIL  %-46s exit %s, stderr said: %s\n' \
      "the 4 names itself NOT MEASURED" "$rc" "$(cat "$ST_DIR/err")"
  fi

  printf '\n%s of %s cases held\n' "$((ST_TOTAL - ST_FAILS))" "$ST_TOTAL"
  [ "$ST_FAILS" -eq 0 ] || return 3
  return 0
}

FILE=""
REQUIRE_RECORDS=0
SELFTEST=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --selftest) SELFTEST=1; shift ;;
    --require-records) REQUIRE_RECORDS=1; shift ;;
    -*) printf 'spec-requirements: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *)
      [ -z "$FILE" ] || die_unmeasured "one spec file at a time; got a second argument"
      FILE="$1"; shift ;;
  esac
done

if [ "$SELFTEST" -eq 1 ]; then
  [ -z "$FILE" ] || die_unmeasured "--selftest takes no spec file"
  # Captured on the same line: `set -e` would otherwise carry a failing case
  # out of the function before the status could be read back.
  ST_RC=0
  selftest || ST_RC=$?
  exit "$ST_RC"
fi

[ -n "$FILE" ] || die_unmeasured "no spec file given"
[ -f "$FILE" ] && [ -r "$FILE" ] || die_unmeasured "cannot read $FILE"

parse_file() {
awk '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

function emit(   t, i) {
  if (curid == "") return
  t = ""
  for (i = 1; i <= nbuf; i++) t = (t == "" ? buf[i] : t " " buf[i])
  gsub(/[\t]+/, " ", t)
  gsub(/  +/, " ", t)
  printf "%s\t%d\t%s\t%s\t%s\n", curid, curline, curstatus, curtarget, trim(t)
  curid = ""; nbuf = 0
}

function open_item(line,   rest, sep) {
  emit()
  match(line, /R[0-9]+/)
  curid = substr(line, RSTART, RLENGTH)
  curline = FNR
  curstatus = "active"
  curtarget = "-"
  nbuf = 0
  rest = substr(line, RSTART + RLENGTH)
  sub(/^\*\*/, "", rest)
  rest = trim(rest)
  # The separator: em dash, en dash or hyphen. See the header on why a
  # non-canonical one is accepted rather than treated as no requirement.
  # The dashes are written as octal escapes inside a STRING, not as \x inside
  # a regex literal: \x is a gawk extension that mawk does not read, and a
  # parser that silently stops recognising the em dash reports every
  # requirement in the file as text that begins with a dash.
  if (!sub("^" EMDASH "[ \t]*", "", rest))
    if (!sub("^" ENDASH "[ \t]*", "", rest))
      sub(/^-[ \t]*/, "", rest)
  if (rest != "") { nbuf++; buf[nbuf] = rest }
}

function marker(line,   l, t) {
  l = trim(line)
  if (l !~ /^[Ss]uperseded/ && l !~ /^[Ww]ithdrawn/) return 0
  if (curstatus != "active") { curstatus = "malformed"; curtarget = "-"; return 1 }
  if (match(l, /^Superseded by R[0-9]+\.([ \t].*)?$/)) {
    curstatus = "superseded"
    t = l; sub(/^Superseded by /, "", t)
    match(t, /^R[0-9]+/)
    curtarget = substr(t, RSTART, RLENGTH)
    return 1
  }
  if (l ~ /^Withdrawn\.([ \t].*)?$/) { curstatus = "withdrawn"; curtarget = "-"; return 1 }
  curstatus = "malformed"; curtarget = "-"
  return 1
}

BEGIN { ins = 0; curid = ""; nbuf = 0; EMDASH = "\342\200\224"; ENDASH = "\342\200\223" }

/^## / {
  emit()
  ins = ($0 ~ /^##[ \t]+Requirements[ \t]*$/) ? 1 : 0
  next
}
ins == 0 { next }
/^#/ { emit(); next }

/^-[ \t]+\*\*R[0-9]+\*\*/ { open_item($0); next }

# A blank line closes the list item. Anything unindented that is not a new
# item closes it too - the item ended and prose took over.
/^[ \t]*$/ { emit(); next }
/^[^ \t]/ { emit(); next }

curid != "" {
  if (marker($0)) next
  nbuf++; buf[nbuf] = trim($0)
  next
}

END { emit() }
' "$1"
}

if [ "$REQUIRE_RECORDS" -eq 0 ]; then
  # Unchanged from every release before this flag existed: the records go
  # straight to stdout and awk's own status is the script's.
  parse_file "$FILE"
  exit $?
fi

OUT="$(mktemp "${TMPDIR:-/tmp}/spec-requirements.XXXXXX")" ||
  die_unmeasured "could not create a temporary file to count the records in"
trap 'rm -f "$OUT"' EXIT HUP INT TERM
parse_file "$FILE" > "$OUT"
cat "$OUT"
RECORDS="$(awk 'END { print NR }' "$OUT")"
if [ "$RECORDS" -eq 0 ]; then
  printf 'spec-requirements: %s\n' \
    "$FILE parsed cleanly and no requirement in it was understood. --require-records was asked for, so this is NOT MEASURED and not an empty spec. A file that was not read has not passed." >&2
  exit 4
fi
exit 0
