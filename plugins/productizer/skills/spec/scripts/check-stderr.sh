#!/usr/bin/env bash
# check-stderr.sh [--version] [--allow ENTRY]... [--selftest] <file>...
#
# Refuses shell that throws stderr away. Discarding stderr makes an ERROR and a
# genuine NO-MATCH look identical, and once they look identical the run is
# green either way. In one session that cost three real defects: a count that
# was wrong, an absence that was not an absence, and a check that examined
# nothing and reported a pass.
#
# WHAT IT REFUSES (any of these on a line of shell):
#
#   stderr redirected to the bit bucket   - 2 > /dev/null, 2 >> /dev/null
#   stderr closed outright                - 2 >&-
#   both streams to the bit bucket        - &> /dev/null, >& /dev/null
#   stdout binned, then stderr folded in  - > /dev/null 2>&1
#
# Spelled with spaces above only so the list reads; the check matches the usual
# spelling with no spaces too. These lines are comments, and a comment cannot
# redirect anything, so they are skipped either way.
#
# WHAT IT DOES NOT REFUSE, ON PURPOSE:
#
#   > /dev/null on its own. Binning stdout says nothing about errors; stderr
#   still reaches the terminal, the log and the caller. Only stderr is at
#   stake here.
#
#   `command -v x > /dev/null 2>&1`. This is an existence TEST: the answer is
#   the exit status, and the only thing on stderr is "not found" noise about a
#   question already answered. It is exempt structurally, with no allowlist
#   entry, because writing it out per call site would train people to write
#   allowlist entries. Nothing else is exempt structurally.
#
#   A line whose first non-blank character is `#`. A comment cannot redirect
#   anything. KNOWN LIMITATION: a here-doc that writes a file in a language
#   where `#` is not a comment could hide a suppression on such a line. No
#   such case exists in this repo; it is a hole, and it is written down.
#
# HOW TO EXEMPT SOMETHING, AND WHY IT COSTS A SENTENCE
#
# Two mechanisms. Both demand a written reason, and BOTH REFUSE THE RUN when
# the reason is missing or shorter than MIN_REASON characters. A check that can
# be silenced without saying why is the thing this check exists to prevent, so
# a bare silencer is exit 2 - not a pass, and not even a finding.
#
#   1. INLINE, for code you can edit. Put a marker on the same line:
#
#          risky_thing 2>/dev/null   # stderr-ok: <reason>
#
#      The reason is everything after the colon. It exempts that whole line.
#
#   2. ALLOWLIST, for code you cannot or should not edit - a vendored script,
#      or a file another owner is holding. Entries are passed as arguments, so
#      they live in the committed checks.yaml next to the check that grants
#      them and are reviewed in the same diff:
#
#          --allow 'FILE::SNIPPET::REASON'
#
#      FILE     the scanned path, or any trailing path-segment suffix of it
#      SNIPPET  a LITERAL substring of the offending line, which MUST ITSELF
#               contain the redirection. An entry that does not is refused:
#               a snippet naming only the surrounding code exempts the whole
#               line forever, including a suppression added tomorrow. Every
#               occurrence of the snippet is cut out of the line and what
#               remains is scanned again, so an entry can only ever excuse the
#               exact redirection it quotes.
#      REASON   >= MIN_REASON characters. Empty is exit 2.
#
# THIS FILE IS SCANNED LIKE EVERY OTHER. It carries no self-exemption: the
# patterns are written so that the definitions do not match themselves. Run it
# on itself; that is the positive control.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every file read, no suppressed stderr
#   1  suppressed stderr found - reported by file and line
#   2  COULD NOT MEASURE. An unreadable file, or an exemption with no reason.
#      Never confused with 0: a file nobody could open is not a clean file.
#
# Under --selftest (--self-test is accepted too) the same three mean: every
# case produced the exit code it declares and said what it was supposed to say
# (0), at least one did not (1), and the corpus could not be driven at all (2).
set -euo pipefail

VERSION="check-stderr 1.0"
MIN_REASON=12
MODE="scan"

usage() { printf 'usage: check-stderr.sh [--version] [--allow FILE::SNIPPET::REASON]... [--selftest] <file>...\n' >&2; }

ALLOW_TMP="$(mktemp "${TMPDIR:-/tmp}/check-stderr.XXXXXX")"
trap 'rm -f "$ALLOW_TMP"' EXIT HUP INT TERM

FILES=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --allow)
      [ "$#" -ge 2 ] || { printf 'check-stderr: --allow needs FILE::SNIPPET::REASON\n' >&2; exit 2; }
      printf '%s\n' "$2" >> "$ALLOW_TMP"
      shift 2
      ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do FILES+=("$1"); shift; done ;;
    -*) printf 'check-stderr: unknown option %s\n' "$1" >&2; usage; exit 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

# ---------------------------------------------------------------------------
# --selftest. R39: one case per exit code this tool can return, each built in
# a sandbox so nothing here reads or writes the tree under test.
#
# EVERY CASE ASSERTS ITS OWN SENTENCE, NOT ONLY ITS EXIT CODE. Nine of the
# cases below share exit 2 - a short inline reason, four shapes of refused
# --allow entry, an unreadable file and an empty file list - so a corpus
# reading exit codes alone cannot tell one refusal from another, and a bug
# that turned a snippet refusal into a usage refusal would stay green.
#
# THE FIXTURES ARE ASSEMBLED, NEVER WRITTEN LITERALLY. A line in THIS file
# spelling out a suppression would be a suppression in this file, and this
# file is scanned by the declared check like every other. So the bit bucket
# and the closing dash arrive through printf arguments and the marker's own
# hyphen does too: what the fixture holds is a real suppression, and what this
# source holds is not. That is the same reason the pattern definitions above
# need no self-exemption.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  [ "${#FILES[@]}" -eq 0 ] ||
    { printf 'check-stderr: --selftest drives its own sandbox and takes no files; got %s\n' "${FILES[0]}" >&2; exit 2; }

  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-stderr-selftest.XXXXXX")" ||
    { printf 'check-stderr: could not create a sandbox, so no case was driven. Unmeasured.\n' >&2; exit 2; }
  trap 'rm -rf "$SB"; rm -f "$ALLOW_TMP"' EXIT HUP INT TERM

  NUL="/dev/null"
  DASH="-"
  HYPHEN="-"

  printf '#!/usr/bin/env bash\nls somewhere > %s\ngrep -q x file || echo no\n' "$NUL" > "$SB/clean.sh"
  printf '#!/usr/bin/env bash\ncommand -v jq > %s 2>&1\ncommand -v git > %s\n' "$NUL" "$NUL" > "$SB/cmdv.sh"
  printf '#!/usr/bin/env bash\n# a comment naming 2>%s redirects nothing\necho fine\n' "$NUL" > "$SB/comment.sh"
  printf '#!/usr/bin/env bash\nrisky_thing 2>%s\n' "$NUL" > "$SB/suppressed.sh"
  printf '#!/usr/bin/env bash\nrisky_thing &>%s\n' "$NUL" > "$SB/both-streams.sh"
  printf '#!/usr/bin/env bash\nrisky_thing 2>&%s\n' "$DASH" > "$SB/closed.sh"
  printf '#!/usr/bin/env bash\nrisky_thing >%s 2>&1\n' "$NUL" > "$SB/stdout-first.sh"
  printf '#!/usr/bin/env bash\nrisky_thing 2>%s  # stderr%sok: the caller already reports this failure by hand\n' "$NUL" "$HYPHEN" > "$SB/marked.sh"
  printf '#!/usr/bin/env bash\nrisky_thing 2>%s  # stderr%sok: too short\n' "$NUL" "$HYPHEN" > "$SB/short-marker.sh"

  ALLOW_GOOD="suppressed.sh::2>$NUL::a sandbox line this corpus owns, with a reason long enough to count"
  ALLOW_NO_REASON="suppressed.sh::2>$NUL"
  ALLOW_SHORT_REASON="suppressed.sh::2>$NUL::short"
  ALLOW_NO_REDIRECT="suppressed.sh::risky_thing::the snippet names the surrounding code and not the redirection"
  ALLOW_MALFORMED="this entry has no separator at all"

  FAILED=0
  DRIVEN=0
  # R39.b: the reached half of the declaration below is ACCUMULATED here, one
  # entry per case as it ran. A literal list would satisfy the reader and prove
  # nothing.
  CODES=""

  drive() {
    # $1 case name, $2 expected exit, $3 expected sentence, $4.. argv
    local case_name="$1" want="$2" marker="$3"
    shift 3
    local rc=0
    bash "$0" "$@" > "$SB/$case_name.out" 2> "$SB/$case_name.err" || rc=$?
    DRIVEN=$((DRIVEN + 1))
    CODES="$CODES$rc
"
    local why=""
    [ "$rc" -eq "$want" ] || why="exit $rc, expected $want"
    # BOTH FILES ARE HANDED TO grep DIRECTLY, NEVER PIPED INTO IT. Under
    # `set -o pipefail` a `cat a b | grep -q` reports 141 whenever grep matches
    # early enough to SIGPIPE the cat, and the `if !` then reads that as no
    # match - a race on buffering that passes from a terminal and fails on a
    # pipe, which is how the runner invokes this.
    if ! grep -q -- "$marker" "$SB/$case_name.out" "$SB/$case_name.err"; then
      [ -n "$why" ] && why="$why; "
      why="${why}its output does not say what it was supposed to say"
    fi
    if [ -z "$why" ]; then
      printf '  held: case %-20s exit %d, and said so - %s\n' "$case_name" "$rc" "$marker"
      return 0
    fi
    printf '  FINDING: case %-20s %s - expected: %s\n' "$case_name" "$why" "$marker"
    FAILED=$((FAILED + 1))
    return 0
  }

  # THE CLEAN CASE GUARDS THE OTHERS' PREMISE. If a file with no suppression
  # in it does not exit 0 and name itself, every red case below would be red
  # for that reason instead of its own and nothing would have been measured.
  CLEAN_RC=0
  bash "$0" "$SB/clean.sh" > "$SB/clean.out" 2> "$SB/clean.err" || CLEAN_RC=$?
  if [ "$CLEAN_RC" -ne 0 ] || ! grep -q 'clean.sh' "$SB/clean.out"; then
    printf '  the clean case exited %d and did not name the file it read.\n' "$CLEAN_RC"
    printf 'check-stderr: the corpus premise did not hold; unmeasured, not a pass.\n' >&2
    exit 2
  fi
  printf '  held: case %-20s exit 0, and said so - %s\n' "clean" "clean.sh"
  CODES="${CODES}0
"

  drive cmdv-exempt      0 'cmdv.sh'                                "$SB/cmdv.sh"
  drive comment-only     0 'comment.sh'                             "$SB/comment.sh"
  drive inline-marker    0 'marked.sh'                              "$SB/marked.sh"
  drive allow-entry      0 'suppressed.sh'                          --allow "$ALLOW_GOOD" "$SB/suppressed.sh"

  drive stderr-binned    1 'stderr suppressed'                      "$SB/suppressed.sh"
  drive both-streams     1 'stderr suppressed'                      "$SB/both-streams.sh"
  drive stderr-closed    1 'stderr suppressed'                      "$SB/closed.sh"
  drive stdout-first     1 'stderr suppressed'                      "$SB/stdout-first.sh"

  drive short-marker     2 'Refused, not exempted'                  "$SB/short-marker.sh"
  drive allow-no-reason  2 'carries no reason'                      --allow "$ALLOW_NO_REASON" "$SB/suppressed.sh"
  drive allow-short      2 'a reason must be at least'              --allow "$ALLOW_SHORT_REASON" "$SB/suppressed.sh"
  drive allow-no-redirect 2 'contains no stderr redirection'        --allow "$ALLOW_NO_REDIRECT" "$SB/suppressed.sh"
  drive allow-malformed  2 'is not FILE::SNIPPET::REASON'           --allow "$ALLOW_MALFORMED" "$SB/suppressed.sh"
  drive unreadable-file  2 'Unmeasured, not clean'                  "$SB/no-such-file.sh"
  drive no-files         2 'Nothing scanned is not a clean scan'

  printf '  cases driven: %d. Cases that did not hold: %d\n' \
    "$((DRIVEN + 1))" "$FAILED"

  # The R39.b declaration. The reached half is computed from the cases above;
  # the documented half is the contract in this file's header.
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
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
  printf '  R39 for this tool: the self-test exists, reaches 0, 1 and 2, and every case asserts which sentence it produced as well as which code.\n'
  printf '  NOT ASSERTED: the allowlist is driven through this script argv, so an entry that reaches the awk by another route is outside the corpus.\n'
  exit 0
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  printf 'check-stderr: no files given. Nothing scanned is not a clean scan.\n' >&2
  usage
  exit 2
fi

for f in "${FILES[@]}"; do
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then
    printf 'check-stderr: cannot read %s. Unmeasured, not clean.\n' "$f" >&2
    exit 2
  fi
done

rc=0
awk -v allowfile="$ALLOW_TMP" -v minreason="$MIN_REASON" '
function strip_literal(s, lit,   i) {
  if (lit == "") return s
  while ((i = index(s, lit)) > 0)
    s = substr(s, 1, i - 1) substr(s, i + length(lit))
  return s
}
function suffix_match(path, f,   tail) {
  if (path == f) return 1
  tail = "/" f
  if (length(path) <= length(tail)) return 0
  return substr(path, length(path) - length(tail) + 1) == tail
}
function rindex(s, t,   i, at, last) {
  last = 0; i = 1
  while ((at = index(substr(s, i), t)) > 0) {
    last = i + at - 1
    i = last + 1
  }
  return last
}
function trim(s) {
  sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
  return s
}
BEGIN {
  # The one definition of "stderr was thrown away". Deliberately written so
  # that this very line does not match it: every branch needs a literal
  # /dev/null or a - immediately after the redirection, and here a bracket
  # follows instead. That is why this file needs no self-exemption.
  SUP = "2[ \t]*>>?[ \t]*/dev/null|2[ \t]*>&[ \t]*-|&>>?[ \t]*/dev/null|>&[ \t]*/dev/null|1?>>?[ \t]*/dev/null[ \t]+2[ \t]*>&[ \t]*1"
  CMDV = "command[ \t]+-v[ \t]+[^ \t;|&()]+[ \t]*(1?>>?[ \t]*/dev/null([ \t]*2[ \t]*>&[ \t]*1)?|&>>?[ \t]*/dev/null)"
  MARK = "#[ \t]*stderr-ok:"

  na = 0; bad = 0; found = 0
  while ((getline entry < allowfile) > 0) {
    if (entry == "") continue
    p1 = index(entry, "::")
    if (p1 == 0) {
      printf("check-stderr: allow entry %s is not FILE::SNIPPET::REASON\n", entry) > "/dev/stderr"
      bad = 1; continue
    }
    af = substr(entry, 1, p1 - 1)
    rest = substr(entry, p1 + 2)
    # LAST separator, not the first. A snippet very often ends in a colon -
    # `2>/dev/null || :` is the commonest shape in this repo - and splitting on
    # the first `::` silently ate the trailing colon, widening the snippet to
    # `2>/dev/null || ` and exempting every line that happened to contain it.
    # That was a real bug in this file, caught by fixture 4f. The cost is that
    # a REASON may not contain `::`.
    p2 = rindex(rest, "::")
    if (p2 == 0) {
      printf("check-stderr: allow entry for %s carries no reason. An exemption with no reason is refused, not honoured.\n", af) > "/dev/stderr"
      bad = 1; continue
    }
    as = substr(rest, 1, p2 - 1)
    ar = trim(substr(rest, p2 + 2))
    if (af == "" || as == "") {
      printf("check-stderr: allow entry %s names no file or no snippet\n", entry) > "/dev/stderr"
      bad = 1; continue
    }
    if (length(ar) < minreason) {
      printf("check-stderr: allow entry for %s gives reason %s (%d chars); a reason must be at least %d characters. Refused.\n", af, "\"" ar "\"", length(ar), minreason) > "/dev/stderr"
      bad = 1; continue
    }
    if (as !~ SUP) {
      printf("check-stderr: allow entry for %s quotes %s, which contains no stderr redirection. An entry that does not quote the redirection exempts the whole line forever. Refused.\n", af, "\"" as "\"") > "/dev/stderr"
      bad = 1; continue
    }
    na++
    AF[na] = af; AS[na] = as; AR[na] = ar
  }
  close(allowfile)
  if (bad) exit 2
}
FNR == 1 { print FILENAME }          # one line per file examined
{
  line = $0
  if (line ~ /^[ \t]*#/) next        # a comment cannot redirect

  if (match(line, MARK)) {
    reason = trim(substr(line, RSTART + RLENGTH))
    if (length(reason) < minreason) {
      printf("    %s:%d: stderr-ok marker with reason %s (%d chars); a reason must be at least %d characters. Refused, not exempted.\n", FILENAME, FNR, "\"" reason "\"", length(reason), minreason) > "/dev/stderr"
      bad = 1
    }
    next
  }

  gsub(CMDV, "", line)               # `command -v` is an existence test

  for (i = 1; i <= na; i++)
    if (suffix_match(FILENAME, AF[i]))
      line = strip_literal(line, AS[i])

  if (line ~ SUP) {
    printf("    %s:%d: stderr suppressed. An error and a genuine no-match are now indistinguishable. Remove it, or add a same-line `# stderr-ok: <reason>`, or an --allow entry quoting the redirection and giving a reason.\n", FILENAME, FNR)
    found = 1
  }
}
END {
  if (bad) exit 2
  if (found) exit 1
  exit 0
}
' "${FILES[@]}" || rc=$?
exit "$rc"
