#!/usr/bin/env bash
# request-ruling.sh [--version] [--help] [--root DIR] --against R<n>
#                   --intent-file FILE [--issue REF] [--slug SLUG]
#
# Raises a ruling: writes .claude/productizer/rulings/D<n>-<slug>.md for a
# contradiction, BEFORE the question is asked out loud.
#
# WHY THIS IS A SCRIPT AND NOT A PARAGRAPH IN A REFERENCE FILE.
#
# `references/rulings.md` specifies "Raising one" in five steps and nothing
# executed them. The lifecycle correctly STOPS on a contradiction, but nobody
# was ever asked for the decision - so the work stopped and stayed stopped, and
# the reasoning that would have unblocked it was never written anywhere. A stop
# that ends in a chat message is the failure this whole lifecycle exists to
# prevent, one layer up. Making the ask mechanical is the only way it cannot be
# skipped.
#
# WHAT IT DOES, in order:
#
#   1. Reads the requirement named by --against out of the spec, VERBATIM.
#      Absent, superseded or withdrawn is a REFUSAL (4), never a warning: a
#      ruling against a dead requirement is a silent no-op that looks like
#      process.
#   2. Refuses (4) if a pending ruling already stands against that same
#      requirement. Two pending rulings on one requirement split the answer,
#      and whichever is ruled second is ruled against a spec the first already
#      moved.
#   3. Allocates the next D<n> from the rulings directory and the next C<n>
#      from the spec's *Areas of concern* table. max + 1, always - a gap is a
#      removed row, and filling it re-points every citation that named it.
#   4. Writes the ruling from templates/ruling.md with the header block, the
#      conflict, the question and both cost columns filled in.
#   5. Prints the path and the ids for the caller to name in the ask.
#
# WHAT IT DELIBERATELY DOES NOT DO.
#
#   No requirement id is allocated for the incoming behaviour. An id in the
#   spec is a merge, whatever the surrounding prose says - so allocating one
#   here would merge the losing side by accident.
#
#   The C<n> row is NOT added to the spec, and nothing is committed. This
#   script owns one file. Its caller adds the row and makes the single commit,
#   which is why the allocated C id is printed.
#
#   Nothing below `## Ruling` is filled. A human rules; the agent drafts every
#   section above that heading and none from there down. A stop that resolves
#   itself is not a stop.
#
# THE INTENT TEXT IS A STRANGER'S TEXT.
#
#   It is written INTO the ruling - that is the point of the file - but it is
#   never echoed on stdout or stderr, because those land in a model's context
#   before a human has read a word of them. `D7` cannot carry a sentence.
#   Inside the file it is quoted as a markdown blockquote, so no line of it can
#   forge a `Status:` header line for the pending-count to match, or a `##`
#   heading for a reader to trust.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  the ruling was written; its path and ids are on stdout
#   2  usage error - a missing, malformed or unknown argument
#   3  COULD NOT READ an input it needs: the spec, the rulings directory, the
#      intent file or the template. An unreadable rulings directory is NOT an
#      empty one: a repo with no rulings/ has never raised one and gets it
#      created; a directory that cannot be read is unknown, and allocating D1
#      into it would reuse every id already in there.
#   4  REFUSED - the requirement is absent, superseded or withdrawn, or a
#      pending ruling already stands against it.
set -euo pipefail

VERSION="request-ruling 1.0"

ROOT="."
AGAINST=""
INTENT_FILE=""
ISSUE=""
SLUG=""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/ruling.md"
EMDASH="—"

usage() {
  printf 'usage: request-ruling.sh [--version] [--help] [--root DIR] --against R<n> --intent-file FILE [--issue REF] [--slug SLUG]\n'
  printf '  --root DIR         repo root holding .claude/productizer (default: .)\n'
  printf '  --against R<n>     the active requirement the intent contradicts\n'
  printf '  --intent-file FILE the incoming behaviour, as text\n'
  printf '  --issue REF        the tracker item that raised it (default: an em dash)\n'
  printf '  --slug SLUG        filename slug (default: the requirement id, lower case)\n'
  printf 'exit: 0 written - 2 usage - 3 an input could not be read - 4 refused\n'
}

die_usage()  { printf 'request-ruling: %s\n' "$1" >&2; usage >&2; exit 2; }
die_unread() { printf 'request-ruling: %s\n' "$1" >&2; exit 3; }
refuse()     { printf 'request-ruling: REFUSED - %s\n' "$1" >&2; exit 4; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)        [ "$#" -ge 2 ] || die_usage "--root needs a directory";   ROOT="$2";        shift 2 ;;
    --against)     [ "$#" -ge 2 ] || die_usage "--against needs R<n>";       AGAINST="$2";     shift 2 ;;
    --intent-file) [ "$#" -ge 2 ] || die_usage "--intent-file needs a path"; INTENT_FILE="$2"; shift 2 ;;
    --issue)       [ "$#" -ge 2 ] || die_usage "--issue needs a reference";  ISSUE="$2";       shift 2 ;;
    --slug)        [ "$#" -ge 2 ] || die_usage "--slug needs a slug";        SLUG="$2";        shift 2 ;;
    # An unknown flag is never accepted silently. A caller that misspells
    # --intent-file and gets a ruling with no incoming behaviour in it has
    # written a stub that reads like an ask.
    *) die_usage "unknown argument: $1" ;;
  esac
done

[ -n "$AGAINST" ] || die_usage "--against is required"
[ -n "$INTENT_FILE" ] || die_usage "--intent-file is required"

case "$AGAINST" in
  # <!-- EXAMPLE:BEGIN -->
  R0|R0[0-9]*) die_usage "--against $AGAINST: ids carry no leading zero; R7 is not R07" ;;
  # <!-- EXAMPLE:END -->
  R[1-9]*) case "${AGAINST#R}" in *[!0-9]*) die_usage "--against $AGAINST is not R<n>" ;; esac ;;
  *) die_usage "--against $AGAINST is not R<n>" ;;
esac

# The issue ref lands in a header line that is read by machine, one Key: value
# per line. A ref carrying a space or a newline breaks that block for every
# reader of it, so it is refused rather than mangled into shape.
if [ -n "$ISSUE" ]; then
  case "$ISSUE" in
    *[!A-Za-z0-9#:._/-]*) die_usage "--issue must be a bare reference like #123, PROJ-123 or a URL (no spaces or newlines)" ;;
  esac
else
  ISSUE="$EMDASH"
fi

# The slug is decoration for humans scanning `ls`; the id is the handle. It is
# reduced to a safe filename charset rather than trusted, and it defaults to
# the requirement id - never to anything derived from the intent text, which is
# a stranger's and would end up in a path this script prints.
if [ -n "$SLUG" ]; then
  SLUG="$(printf '%s' "$SLUG" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | tr -s '-')"
  SLUG="${SLUG#-}"
  SLUG="${SLUG%-}"
  SLUG="$(printf '%.40s' "$SLUG")"
  SLUG="${SLUG%-}"
fi
[ -n "$SLUG" ] || SLUG="$(printf '%s' "$AGAINST" | tr '[:upper:]' '[:lower:]')"

[ -f "$INTENT_FILE" ] && [ -r "$INTENT_FILE" ] ||
  die_unread "cannot read the intent file $INTENT_FILE. There is no incoming behaviour to write down, and a ruling with one side blank is not an ask."
INTENT_TEXT="$(sed -e 's/[[:space:]]*$//' "$INTENT_FILE" | sed -e '/./,$!d')"
INTENT_TEXT="${INTENT_TEXT%"${INTENT_TEXT##*[![:space:]]}"}"
[ -n "$INTENT_TEXT" ] || die_usage "the intent file $INTENT_FILE is empty"

[ -f "$TEMPLATE" ] && [ -r "$TEMPLATE" ] ||
  die_unread "cannot read the ruling template at $TEMPLATE"
# Everything from `## Ruling` down is the human's half and is carried over from
# the template unedited, guidance included. The agent drafts every section
# above it and none from there down.
TAIL="$(awk '/^## Ruling[[:space:]]*$/ { f = 1 } f' "$TEMPLATE")"
[ -n "$TAIL" ] ||
  die_unread "the ruling template at $TEMPLATE has no '## Ruling' section, so the human's half of the file cannot be carried over"

SPEC="$ROOT/.claude/productizer/spec.md"
RULINGS="$ROOT/.claude/productizer/rulings"

[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unread "cannot read the spec at $SPEC. A requirement that could not be looked up is not an absent requirement."

# The requirement, verbatim, and its status. Only DEFINITIONS count: an id
# written anywhere but a top-level list item under `## Requirements` is a
# citation, and ruling against a citation rules against nothing. The status
# marker is the line directly beneath the definition.
REQ="$(awk -v id="$AGAINST" '
BEGIN {
  pat = "^[ \t]*[-*][ \t]+\\*\\*" id "\\*\\*"
  inreq = 0; awaiting = 0; found = 0; state = ""; text = ""
}
{
  if (awaiting) {
    awaiting = 0
    if ($0 ~ /^[ \t]+Superseded by/) state = "superseded"
    else if ($0 ~ /^[ \t]+Withdrawn/) state = "withdrawn"
    else state = "active"
  }
  if ($0 ~ /^## /) { inreq = ($0 ~ /^## Requirements[ \t]*$/) ? 1 : 0; next }
  if (!inreq) next
  if ($0 ~ pat) {
    line = $0
    sub(/^[ \t]*[-*][ \t]+/, "", line)
    text = line; found = 1; awaiting = 1; state = ""
  }
}
END {
  if (!found) { print "absent"; exit }
  if (state == "") state = "active"      # the definition was the last line
  printf "%s\n%s\n", state, text
}
' "$SPEC")"

if [ "$REQ" = "absent" ]; then
  refuse "$AGAINST is not defined in $SPEC. Ruling against a requirement that does not exist changes nothing and looks like it did."
fi
REQ_STATE="${REQ%%$'\n'*}"
REQ_TEXT="${REQ#*$'\n'}"
case "$REQ_STATE" in
  active) : ;;
  superseded) refuse "$AGAINST is already superseded, so it governs nothing and a ruling on it is a silent no-op. Rule against the requirement that replaced it." ;;
  withdrawn)  refuse "$AGAINST is withdrawn. The behaviour no longer exists, so there is nothing for the intent to contradict." ;;
esac

# The rulings directory. Absent means this repo has never raised one, which is
# a first ruling, not an error. Present but unreadable is UNKNOWN - and an
# unknown directory allocated as if it were empty hands out an id that is
# already taken.
if [ -e "$RULINGS" ]; then
  [ -d "$RULINGS" ] || die_unread "$RULINGS exists but is not a directory"
  { [ -r "$RULINGS" ] && [ -x "$RULINGS" ]; } ||
    die_unread "$RULINGS cannot be read. That is not an empty directory - allocating into it would reuse an id."
else
  mkdir -p "$RULINGS" || die_unread "cannot create $RULINGS"
fi

# One pass over the same file list answers both questions: the highest id ever
# used, and whether a pending ruling already stands against this requirement.
# An unmatched glob arrives as a literal path in bash, so every entry is tested
# rather than counted.
max_d=0
max_c_raised=0
dup=""
for f in "$RULINGS"/D*.md; do
  [ -f "$f" ] || continue
  [ -r "$f" ] || die_unread "$f cannot be read, so neither the next free id nor the pending set is known."
  base="${f##*/}"
  n="${base#D}"
  n="${n%%[!0-9]*}"
  if [ -n "$n" ] && [ "$n" -gt "$max_d" ]; then
    max_d="$n"
  fi
  # A C id claimed by a ruling that has not yet had its row committed to the
  # spec is still claimed. Without this, two contradictions raised before the
  # caller writes the rows both allocate the same concern - and the second row
  # to be written either collides or renumbers.
  cn="$(sed -n 's/^Concern:[[:space:]]*C\([0-9][0-9]*\)[[:space:]]*$/\1/p' "$f" | sed -n 1p)"
  if [ -n "$cn" ] && [ "$cn" -gt "$max_c_raised" ]; then
    max_c_raised="$cn"
  fi
  # -x and -F, never a substring: `Status: pending` appears in the template's
  # own prose and in any ruling that discusses being pending.
  if [ -z "$dup" ] &&
     grep -qxF 'Status: pending' "$f" &&
     grep -qE "^\*\*${AGAINST}\*\*" "$f"; then
    dup="${base%%[-.]*}"
  fi
done

if [ -n "$dup" ]; then
  refuse "$dup is already pending against $AGAINST. A second ruling splits the answer, and whichever is ruled second is ruled against a spec the first already moved. Answer $dup, or lapse it."
fi

D="D$((max_d + 1))"

# The next concern id, from the *Areas of concern* table. Resolved rows stay in
# the table, so the highest row carries the highest id ever used - including a
# row still inside the template's commented-out example, which is deliberately
# counted as taken rather than handed out twice.
max_c="$(awk '
BEGIN { inc = 0; max = 0 }
/^## / { inc = ($0 ~ /^## Areas of concern/) ? 1 : 0; next }
inc && match($0, /^[ \t]*(<!--[^|]*)?\|[ \t]*C[0-9]+[ \t]*\|/) {
  row = substr($0, RSTART, RLENGTH)
  sub(/^[^C]*C/, "", row)
  sub(/[^0-9].*$/, "", row)
  if (row + 0 > max) max = row + 0
}
END { print max }
' "$SPEC")"
if [ "$max_c_raised" -gt "$max_c" ]; then
  max_c="$max_c_raised"
fi
C="C$((max_c + 1))"

RAISED="$(TZ=UTC date +%Y-%m-%d)"
OUT="$RULINGS/$D-$SLUG.md"

if [ -e "$OUT" ]; then
  die_unread "$OUT already exists, and ids are never reused. Nothing was written."
fi

TMP="$(mktemp "$RULINGS/.request-ruling.XXXXXX")"
trap 'rm -f "$TMP"' EXIT HUP INT TERM

{
  printf '# %s — %s contradicted by an incoming intent\n\n' "$D" "$AGAINST"

  printf 'Status: pending\n'
  printf 'Raised: %s\n' "$RAISED"
  printf 'Concern: %s\n' "$C"
  printf 'Intent: %s\n' "$ISSUE"
  printf 'Ruled: %s\n' "$EMDASH"
  printf 'Ruled by: %s\n' "$EMDASH"
  printf 'Supersedes: %s\n' "$EMDASH"
  printf 'Superseded by: %s\n' "$EMDASH"

  printf '\n## The conflict\n\n'
  printf '%s\n\n' "$REQ_TEXT"
  printf '**Incoming** — the behaviour the intent requires, quoted from the intent\nfile. No requirement id is allocated for it: an id in the spec is a merge.\n\n'
  printf '%s\n' "$INTENT_TEXT" | sed -e 's/^/> /' -e 's/[[:space:]]*$//'
  printf '\n'
  printf 'These cannot both hold: %s and the incoming behaviour require different\nresponses from the same system, so honouring either one violates the other.\n' "$AGAINST"

  printf '\n## The question\n\n'
  printf 'Does %s continue to govern, or does the incoming behaviour replace it?\nAnswer exactly one of:\n\n' "$AGAINST"
  # `printf -- ` because a format string opening with a dash is read as an
  # option, and the bullet is the first character of both of these lines.
  printf -- '- **%s stands** — the intent is refused and the spec is unchanged.\n' "$AGAINST"
  printf -- '- **The incoming behaviour governs** — %s is superseded, and a new\n  requirement id is allocated for the incoming behaviour.\n' "$AGAINST"

  printf '\n## What each side costs\n\n'
  printf '| If %s governs | If the incoming behaviour governs |\n' "$AGAINST"
  printf '|---|---|\n'
  printf '| The intent is refused and whoever raised it stays blocked on this behaviour; nothing in the spec, the checks or the acceptance criteria changes, and the same intent arrives again unless this ruling records why it lost. | %s is superseded by a newly allocated id and keeps its text as a record; every acceptance-criteria row, check and test pinned to %s moves with it, and anything already built against %s is building behaviour the spec no longer asks for. |\n' \
    "$AGAINST" "$AGAINST" "$AGAINST"

  printf '\n%s\n' "$TAIL"
} > "$TMP"

mv "$TMP" "$OUT"
trap - EXIT HUP INT TERM

# Step 3 of references/rulings.md: the concern row. This used to be left to the
# caller, and leaving it to the caller is the failure this whole script exists
# to remove. The ruling file existed, the spec's Areas of concern stayed empty,
# and intake - which reads the spec, not this directory - saw nothing waiting.
# check-ruling-requested.sh fails exactly that state, so the documented flow
# produced a red check out of the box. A step a human has to remember is a step
# that gets skipped; that is the whole finding behind this work.
#
# The row carries ids and a fixed sentence only. The conflict is described in
# the ruling file, which is the thing built to hold a stranger's text - a spec
# table is not, and a table cell cannot hold a pipe without tearing the row.
CONCERN_ROW="| $C | Contradiction raised against $AGAINST — see $D | $AGAINST | — | intake, $RAISED | open: $D |"
SPEC_TMP="$(mktemp "${TMPDIR:-/tmp}/request-ruling.spec.XXXXXX")"
trap 'rm -f "$SPEC_TMP"' EXIT HUP INT TERM

# Append after the last existing row of the Areas of concern table, or after its
# separator when the table is empty. Never sorted, never renumbered: ids are
# permanent and the table is a log, so a new row goes at the end.
awk -v row="$CONCERN_ROW" '
  /^[[:space:]]*##[[:space:]]/ {
    if (in_c && !done) { print row; done = 1 }
    in_c = ($0 ~ /Areas of concern/) ? 1 : 0
  }
  { line[NR] = $0; print }
  END { if (in_c && !done) print row }
' "$SPEC" > "$SPEC_TMP"

if ! grep -qxF "$CONCERN_ROW" "$SPEC_TMP"; then
  rm -f "$SPEC_TMP"
  printf 'request-ruling: wrote %s but could not add the %s row to Areas of concern in %s. The ruling exists and intake cannot see it; add the row by hand before asking.\n' \
    "$OUT" "$C" "$SPEC" >&2
  exit 5
fi
cat "$SPEC_TMP" > "$SPEC"
rm -f "$SPEC_TMP"
trap - EXIT HUP INT TERM

# Ids and the path this script wrote. Never the intent text, and never a word
# of the requirement: this output is read by the agent that asks the question.
printf 'ruling: %s\n' "$OUT"
printf 'id: %s\n' "$D"
printf 'concern: %s\n' "$C"
printf 'against: %s\n' "$AGAINST"
