#!/usr/bin/env bash
# learnings.sh <subcommand> [options]
#
#   learnings.sh add       --what-file FILE | --what TEXT --source SRC
#                          [--about R<n>[,R<m>...]] [--slug SLUG]
#   learnings.sh list      [--format table|ids|count] [--include-graduated]
#                          [--dormant-after DAYS]
#   learnings.sh check     [--dormant-after DAYS]
#   learnings.sh verify    --id L<n> --by SRC
#   learnings.sh graduate  --id L<n> --to R<n>
#
#   --root DIR   the repo holding .claude/productizer.
#                DEFAULT: `git rev-parse --show-toplevel`, NEVER the working
#                directory. A default of "." resolves to a different store from
#                every subdirectory and answers confidently from the wrong one.
#
# WHAT THIS STORE IS.
#
#   A committed record of things learned about this repo that are NOT
#   obligations. "The build breaks unless X is run first" is an observation
#   about the world; nobody is required to make it true, no test can hold
#   anyone to it, and it has no business in the living spec. The spec answers
#   "what does this system do", and an observation merged into it corrupts the
#   one thing that file is for.
#
#   So learnings live BESIDE the spec and BELOW it. A learning informs; it
#   never obligates and it never outranks a requirement. When one turns out to
#   be a real obligation it GRADUATES to an `R` id and stops being a learning -
#   `graduate` records the transition and the learning keeps its id as the
#   trail from "somebody noticed this" to "the spec now requires it".
#
# WHAT IT IS NOT.
#
#   Not a notes file. A free-text store with no ids, no dates and no ordering
#   cannot tell a current learning from a stale one, so every entry is read
#   with the same weight forever and the store rots into noise nobody trusts.
#   Every learning here has a permanent id, an observation date, and a
#   provenance line naming where it came from.
#
#   Not a second spec. Nothing here is agreed. A learning that CONTRADICTS an
#   active requirement is a finding, not a fact, and goes through intake like
#   any other intent.
#
# UNVERIFIED BY DEFAULT, AND WHY THE CORROBORATOR MUST DIFFER.
#
#   `add` writes `Status: unverified`. It is an observation until something
#   else confirms it. `verify` REFUSES when --by names the same source that
#   observed it: a run that can confirm its own learning promotes whatever it
#   just wrote, and the state means nothing from then on. That refusal is the
#   only thing separating this store from a file of assertions.
#
# STALENESS IS DERIVED, NEVER STORED.
#
#   Age comes from `Observed:`. There is no `stale` field, because a stored
#   flag has to be updated by someone and nobody will. A learning with an
#   unreadable date is reported with an age of an em dash - NEVER as infinitely
#   old, which would bury exactly the entries with the least provenance to
#   recover them by. Dormancy changes presentation only. It never deletes and
#   it never fails a check.
#
# THE ONE THING A PLAIN NOTES FILE CANNOT DO.
#
#   A learning may cite `R14` in its `About:` line, and because ids are
#   permanent that citation stays meaningful for as long as the spec does. So
#   "this learning is about a requirement that has since been superseded" is
#   mechanically detectable, and `check` detects it - the same class of check
#   drift-reverse.sh runs over code, against the same spec baseline, parsed
#   with the same awk pattern.
#
# IT REPORTS BY LOCATION, NEVER BY QUOTING CONTENT.
#
#   A learning is free text a stranger can write, and this output lands in a
#   model's context before a human has read a word of it. Every subcommand
#   emits ids, dates, counts and paths. Not the title, not the observation, not
#   the provenance string. `L7` cannot carry a sentence.
#
# NO FILE MEANS NO COUNT, NOT ZERO.
#
#   Three states, three exit codes, three words, never collapsed into one:
#
#     store absent      never-recorded   count is an em dash   exit 5
#     store unreadable  unknown          count is an em dash   exit 3
#     store empty       empty            count is 0            exit 0
#
#   Only the third is a measured zero. An unmatched glob arrives at bash as a
#   literal path, so the cases are told apart by an explicit directory test and
#   never by trusting a count.
#
# IT NEVER SUPPRESSES STDERR. An error and a genuine no-match look identical
# once hidden, and a store built to be trusted cannot afford that.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  did the thing; for `check`, a MEASURED clean result
#   1  `check` found at least one finding
#   2  usage - a missing, malformed or unknown argument
#   3  COULD NOT READ an input it needs: the spec, a learning file, or a store
#      directory that exists and cannot be opened. Never confused with 0
#   4  CANNOT DETERMINE - learnings cite requirement ids and the spec carries
#      none, so no citation could be resolved. Not a pass, and not a zero
#   5  the store has NEVER been created. Not an error and not zero: nothing has
#      ever been recorded here, and no count is reported
#   6  REFUSED - a dead requirement cited, a source corroborating itself, an id
#      that does not exist, or an id that already does
set -euo pipefail
export TZ=UTC
export LC_ALL=C

VERSION="learnings 1.0"
EMDASH="—"
DORMANT_AFTER_DEFAULT=180

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/learnings.md"

usage() {
  cat <<'USAGE'
usage: learnings.sh <subcommand> [options]

  add       --what-file FILE | --what TEXT --source SRC
            [--about R<n>[,R<m>...]] [--slug SLUG]
  list      [--format table|ids|count] [--include-graduated] [--dormant-after DAYS]
  check     [--dormant-after DAYS]
  verify    --id L<n> --by SRC
  graduate  --id L<n> --to R<n>

  --root DIR   repo holding .claude/productizer.
               Default: git rev-parse --show-toplevel (never the cwd).
  --version    print the version and exit 0
  --help       print this and exit 0

exit: 0 done / measured - 1 findings - 2 usage - 3 an input could not be read
      4 cannot determine - 5 store never created - 6 refused
USAGE
}

die_usage()  { printf 'learnings: %s\n' "$1" >&2; usage >&2; exit 2; }
die_unread() { printf 'learnings: %s\n' "$1" >&2; exit 3; }
refuse()     { printf 'learnings: REFUSED - %s\n' "$1" >&2; exit 6; }

# --- days between two YYYY-MM-DD dates, with no `date -d` -------------------
# BSD date has no -d and GNU date is not on this platform. The civil-to-days
# conversion is arithmetic, so it is done in awk and depends on nothing.
days_between() {
  awk -v a="$1" -v b="$2" '
    function dfc(y, m, d,   era, yoe, doy, doe) {
      if (m <= 2) y -= 1
      era = int((y >= 0 ? y : y - 399) / 400)
      yoe = y - era * 400
      doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      return era * 146097 + doe - 719468
    }
    BEGIN {
      if (a !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) { print ""; exit }
      if (b !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) { print ""; exit }
      split(a, x, "-"); split(b, y, "-")
      print dfc(y[1] + 0, y[2] + 0, y[3] + 0) - dfc(x[1] + 0, x[2] + 0, x[3] + 0)
    }
  '
}

# A markdown table cell. build-view.sh parses these tables, and one unescaped
# pipe tears the row and silently re-columns everything after it.
cell() { printf '%s' "$1" | sed -e 's/|/\\|/g'; }

# One `Key: value` per line, above the first blank line. A missing key and a
# blank value both come back empty here on purpose: the template requires an
# em dash for "unset", so blank and absent are the same defect and `check`
# reports them with one message.
header_field() {
  awk -v key="$2" '
    /^#[ \t]/ { next }
    /^[[:space:]]*$/ { if (inblock) exit; next }
    {
      inblock = 1
      pos = index($0, ":")
      if (pos == 0) next
      k = substr($0, 1, pos - 1)
      v = substr($0, pos + 1)
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      if (k == key) { print v; exit }
    }
  ' "$1"
}

# --- shared argument state ---------------------------------------------------
ROOT=""
FORMAT=table
INCLUDE_GRADUATED=0
DORMANT_AFTER="$DORMANT_AFTER_DEFAULT"
WHAT=""
WHAT_FILE=""
SOURCE=""
ABOUT=""
SLUG=""
ID=""
BY=""
TO=""

[ $# -gt 0 ] || die_usage "no subcommand. One of: add, list, check, verify, graduate."

CMD=""
case "$1" in
  add|list|check|verify|graduate) CMD="$1"; shift ;;
  --version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) usage; exit 0 ;;
  -*) die_usage "unknown option before the subcommand: $1" ;;
  *)  die_usage "unknown subcommand: $1" ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)          [ "$#" -ge 2 ] || die_usage "--root needs a directory";      ROOT="$2";      shift 2 ;;
    --format)        [ "$#" -ge 2 ] || die_usage "--format needs table, ids or count"; FORMAT="$2"; shift 2 ;;
    --include-graduated) INCLUDE_GRADUATED=1; shift ;;
    --dormant-after) [ "$#" -ge 2 ] || die_usage "--dormant-after needs a number of days"; DORMANT_AFTER="$2"; shift 2 ;;
    --what)          [ "$#" -ge 2 ] || die_usage "--what needs text";             WHAT="$2";      shift 2 ;;
    --what-file)     [ "$#" -ge 2 ] || die_usage "--what-file needs a path";      WHAT_FILE="$2"; shift 2 ;;
    --source)        [ "$#" -ge 2 ] || die_usage "--source needs a provenance";   SOURCE="$2";    shift 2 ;;
    --about)         [ "$#" -ge 2 ] || die_usage "--about needs R<n>[,R<m>...]";  ABOUT="$2";     shift 2 ;;
    --slug)          [ "$#" -ge 2 ] || die_usage "--slug needs a slug";           SLUG="$2";      shift 2 ;;
    --id)            [ "$#" -ge 2 ] || die_usage "--id needs L<n>";               ID="$2";        shift 2 ;;
    --by)            [ "$#" -ge 2 ] || die_usage "--by needs a corroborating source"; BY="$2";    shift 2 ;;
    --to)            [ "$#" -ge 2 ] || die_usage "--to needs R<n>";               TO="$2";        shift 2 ;;
    # An unknown flag is never accepted silently. A caller that misspells
    # --source and gets a learning with no provenance has written an anonymous
    # assertion that reads like a record.
    *) die_usage "unknown argument: $1" ;;
  esac
done

case "$FORMAT" in table|ids|count) ;; *) die_usage "--format must be table, ids or count, not '$FORMAT'" ;; esac
case "$DORMANT_AFTER" in ''|*[!0-9]*) die_usage "--dormant-after must be a whole number of days, not '$DORMANT_AFTER'" ;; esac

# --- the root, which is NOT the working directory ---------------------------
if [ -z "$ROOT" ]; then
  if ! ROOT="$(git rev-parse --show-toplevel)"; then
    die_usage "--root was not given and this is not a git repository, so the repo root could not be resolved. Defaulting to the working directory would pick a different store from every subdirectory; pass --root."
  fi
fi
[ -d "$ROOT" ] || die_usage "no such directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"

SPEC_REL=".claude/productizer/spec.md"
STORE_REL=".claude/productizer/learnings"
SPEC="$ROOT/$SPEC_REL"
STORE="$ROOT/$STORE_REL"
TODAY="$(TZ=UTC date +%Y-%m-%d)"

# --- the store's three states ------------------------------------------------
# Told apart by an explicit directory test, because an unmatched glob reaches
# bash as a literal path and a count taken from one is a fabricated count.
STORE_STATE=""
if [ ! -e "$STORE" ]; then
  STORE_STATE="never-recorded"
elif [ ! -d "$STORE" ]; then
  STORE_STATE="not-a-directory"
elif [ -r "$STORE" ] && [ -x "$STORE" ]; then
  STORE_STATE="readable"
else
  STORE_STATE="unknown"
fi

require_readable_store() {
  case "$STORE_STATE" in
    readable) : ;;
    never-recorded)
      printf 'learnings: no learnings store at %s. None has ever been recorded here, so there is no count to report. That is not zero.\n' "$STORE_REL" >&2
      printf 'store: never-recorded\ncount: %s\n' "$EMDASH"
      exit 5
      ;;
    not-a-directory)
      die_unread "$STORE_REL exists and is not a directory. Nothing was read."
      ;;
    unknown)
      printf 'learnings: %s exists and cannot be opened, so the store is UNKNOWN. That is not an empty store and it is not zero learnings.\n' "$STORE_REL" >&2
      printf 'store: unknown\ncount: %s\n' "$EMDASH"
      exit 3
      ;;
  esac
}

# The spec baseline: which requirement ids are current and which have been
# replaced. This awk is copied deliberately from drift-reverse.sh, which takes
# it from stage-status.sh and build-view.sh. Four readers of one pattern
# disagree the moment one is edited, so the copy is noted in all of them.
spec_ids() {
  awk '
    /^([-*][ \t]+)?\*\*R[0-9]+\*\*/ {
      if (match($0, /R[0-9]+/)) {
        cur = substr($0, RSTART, RLENGTH)
        st[cur] = "active"
        if (!(cur in seen)) { seen[cur] = 1; order[++n] = cur }
      }
      next
    }
    cur != "" {
      t = $0; sub(/^[ \t]+/, "", t)
      if (t ~ /^Superseded by/) { st[cur] = "superseded"; cur = ""; next }
      if (t ~ /^Withdrawn\./)   { st[cur] = "withdrawn";  cur = ""; next }
      cur = ""
    }
    END { for (i = 1; i <= n; i++) printf "%s\t%s\n", order[i], st[order[i]] }
  ' "$1"
}

require_spec() {
  { [ -f "$SPEC" ] && [ -r "$SPEC" ]; } ||
    die_unread "cannot read the living spec at $SPEC_REL. A learning store is subordinate to a spec; with no spec to be subordinate to, no citation could be resolved and nothing was checked."
}

# Every learning file, sorted by numeric id. Unreadable is exit 3, never a
# shorter list.
collect_files() {
  local f base n
  for f in "$STORE"/L*.md; do
    [ -f "$f" ] || continue
    [ -r "$f" ] || die_unread "$f cannot be read, so neither the count nor the next free id is known."
    base="${f##*/}"
    n="${base#L}"
    n="${n%%[!0-9]*}"
    [ -n "$n" ] || continue
    printf '%s\t%s\n' "$n" "$f"
  done | sort -n -k1,1
}

next_id() {
  local max=0 n
  while IFS=$'\t' read -r n _; do
    [ -n "$n" ] || continue
    if [ "$n" -gt "$max" ]; then max="$n"; fi
  done < <(collect_files)
  printf '%s' "$((max + 1))"
}

find_by_id() {
  local want="${1#L}" n f
  while IFS=$'\t' read -r n f; do
    if [ "$n" = "$want" ]; then printf '%s' "$f"; return 0; fi
  done < <(collect_files)
  return 1
}

validate_l_id() {
  case "$1" in
    L0|L0[0-9]*) die_usage "--id $1: ids carry no leading zero; L7 is not L07" ;;
    L[1-9]*) case "${1#L}" in *[!0-9]*) die_usage "--id $1 is not L<n>" ;; esac ;;
    *) die_usage "--id $1 is not L<n>" ;;
  esac
}

validate_r_id() {
  case "$1" in
    # <!-- EXAMPLE:BEGIN -->
    R0|R0[0-9]*) die_usage "$2 $1: ids carry no leading zero; R7 is not R07" ;;
    # <!-- EXAMPLE:END -->
    R[1-9]*) case "${1#R}" in *[!0-9]*) die_usage "$2 $1 is not R<n>" ;; esac ;;
    *) die_usage "$2 $1 is not R<n>" ;;
  esac
}

# A provenance string lands in a header line read one Key: value per line. One
# carrying a newline breaks that block for every reader of it, so it is refused
# rather than reshaped into something that parses and says the wrong thing.
validate_oneline() {
  case "$1" in
    *[$'\n\r']*) die_usage "$2 must be a single line with no newline" ;;
    '') die_usage "$2 must not be empty" ;;
  esac
}

# =============================================================================
case "$CMD" in

add)
  [ -n "$SOURCE" ] || die_usage "--source is required. A learning with no provenance is an anonymous assertion, and nothing can ever go back and judge it."
  validate_oneline "$SOURCE" "--source"
  if [ -n "$WHAT_FILE" ] && [ -n "$WHAT" ]; then
    die_usage "pass --what or --what-file, not both"
  fi
  if [ -n "$WHAT_FILE" ]; then
    { [ -f "$WHAT_FILE" ] && [ -r "$WHAT_FILE" ]; } ||
      die_unread "cannot read $WHAT_FILE. There is no observation to record."
    WHAT="$(sed -e 's/[[:space:]]*$//' "$WHAT_FILE")"
  fi
  [ -n "${WHAT//[[:space:]]/}" ] || die_usage "--what or --what-file is required, and must not be empty"

  require_spec

  # Citations are resolved BEFORE anything is written. A learning created
  # citing a requirement that is already superseded is a stale citation on the
  # day it was born, and the check that would have caught it later would then
  # be reporting the store's own scaffolding.
  ABOUT_OUT="$EMDASH"
  if [ -n "$ABOUT" ] && [ "$ABOUT" != "$EMDASH" ]; then
    IDS_TSV="$(spec_ids "$SPEC")"
    [ -n "$IDS_TSV" ] ||
      die_unread "$SPEC_REL holds no requirement ids matching '**R<n>**', so --about could not be resolved against anything."
    NORMALISED=""
    OLD_IFS="$IFS"; IFS=','
    for rid in $ABOUT; do
      IFS="$OLD_IFS"
      rid="${rid#"${rid%%[![:space:]]*}"}"
      rid="${rid%"${rid##*[![:space:]]}"}"
      [ -n "$rid" ] || continue
      validate_r_id "$rid" "--about"
      state="$(printf '%s\n' "$IDS_TSV" | awk -F'\t' -v id="$rid" '$1 == id { print $2; exit }')"
      case "$state" in
        active) : ;;
        '') refuse "--about names $rid, which the spec does not define. A citation that resolves to nothing is not a citation." ;;
        *)  refuse "--about names $rid, which the spec marks $state. Cite the requirement that governs now, or record the learning with no citation at all." ;;
      esac
      NORMALISED="${NORMALISED:+$NORMALISED, }$rid"
      IFS=','
    done
    IFS="$OLD_IFS"
    [ -n "$NORMALISED" ] || die_usage "--about was given and named no requirement id"
    ABOUT_OUT="$NORMALISED"
  fi

  { [ -f "$TEMPLATE" ] && [ -r "$TEMPLATE" ]; } ||
    die_unread "cannot read the learning template at $TEMPLATE"

  case "$STORE_STATE" in
    readable) : ;;
    never-recorded) mkdir -p "$STORE" || die_unread "cannot create $STORE_REL" ;;
    not-a-directory) die_unread "$STORE_REL exists and is not a directory. Nothing was written." ;;
    unknown) die_unread "$STORE_REL cannot be opened. That is not an empty store - allocating into it would reuse an id." ;;
  esac

  # The slug is decoration for humans scanning `ls`; the id is the handle. It
  # is reduced to a safe filename charset and NEVER derived from the
  # observation, which is a stranger's text and would end up in a path this
  # script prints.
  if [ -n "$SLUG" ]; then
    SLUG="$(printf '%s' "$SLUG" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | tr -s '-')"
    SLUG="${SLUG#-}"; SLUG="${SLUG%-}"
    SLUG="$(printf '%.40s' "$SLUG")"
    SLUG="${SLUG%-}"
  fi
  [ -n "$SLUG" ] || SLUG="observation"

  N="$(next_id)"
  L="L$N"
  OUT="$STORE/$L-$SLUG.md"
  [ -e "$OUT" ] && refuse "$OUT already exists, and ids are never reused. Nothing was written."

  # Everything from `## Corroboration` down is carried over from the template
  # unedited. `add` never fills it: a run that writes its own corroboration has
  # verified nothing.
  TAIL="$(awk '/^## Corroboration[[:space:]]*$/ { f = 1 } f' "$TEMPLATE")"
  [ -n "$TAIL" ] ||
    die_unread "the learning template at $TEMPLATE has no '## Corroboration' section, so the half this script must not fill cannot be carried over."

  TMP="$(mktemp "$STORE/.learnings.XXXXXX")"
  trap 'rm -f "$TMP"' EXIT HUP INT TERM
  {
    printf '# %s — an observation, not a requirement\n\n' "$L"
    printf 'Status: unverified\n'
    printf 'Observed: %s\n' "$TODAY"
    printf 'Observed by: %s\n' "$SOURCE"
    printf 'Corroborated: %s\n' "$EMDASH"
    printf 'Corroborated by: %s\n' "$EMDASH"
    printf 'About: %s\n' "$ABOUT_OUT"
    printf 'Graduated to: %s\n' "$EMDASH"
    printf '\n## What was observed\n\n'
    # Quoted, so no line of it can forge a `Status:` header for a counter to
    # match or a `##` heading for a reader to trust.
    printf '%s\n' "$WHAT" | sed -e 's/^/> /' -e 's/[[:space:]]*$//'
    printf '\n## Why this is not a requirement\n\n'
    printf 'Nobody is obliged to make the above true. It is an observation about\n'
    printf 'how things are, and no test can hold anyone to it. If that stops being\n'
    printf 'so, it graduates: `learnings.sh graduate --id %s --to R<n>`.\n' "$L"
    printf '\n## What would corroborate it\n\n'
    printf '<One thing a DIFFERENT source could do that would confirm or refute this.\n'
    printf 'Written now, while the observation is fresh, because after the fact any\n'
    printf 'evidence that turned up looks like the evidence that was wanted.>\n'
    printf '\n%s\n' "$TAIL"
  } > "$TMP"
  mv "$TMP" "$OUT"
  trap - EXIT HUP INT TERM

  # `.claude/` is routinely gitignored, and a store that cannot be committed is
  # a local notes folder that looks like a record.
  if git -C "$ROOT" check-ignore -q "$OUT"; then
    printf 'learnings: WARNING - %s is gitignored. An uncommittable store is a local notes folder wearing the name of a record.\n' "$STORE_REL/$L-$SLUG.md" >&2
  fi

  # Ids, a status and a path. Never the observation, never the provenance.
  printf 'learning: %s\n' "$STORE_REL/$L-$SLUG.md"
  printf 'id: %s\n' "$L"
  printf 'status: unverified\n'
  printf 'observed: %s\n' "$TODAY"
  printf 'about: %s\n' "$ABOUT_OUT"
  exit 0
  ;;

list)
  require_readable_store

  COUNT=0
  ROWS=""
  while IFS=$'\t' read -r n f; do
    [ -n "$n" ] || continue
    st="$(header_field "$f" 'Status')"
    [ -n "$st" ] || st="$EMDASH"
    if [ "$INCLUDE_GRADUATED" -eq 0 ] && [ "$st" = "graduated" ]; then continue; fi
    obs="$(header_field "$f" 'Observed')"
    [ -n "$obs" ] || obs="$EMDASH"
    about="$(header_field "$f" 'About')"
    [ -n "$about" ] || about="$EMDASH"
    age="$(days_between "$obs" "$TODAY")"
    if [ -z "$age" ]; then
      age_out="$EMDASH"
      serve="$EMDASH"
    else
      age_out="${age}d"
      if [ "$age" -ge "$DORMANT_AFTER" ]; then serve="dormant"; else serve="served"; fi
    fi
    ROWS="$ROWS$(printf 'L%s\t%s\t%s\t%s\t%s\t%s\t%s' "$n" "$st" "$obs" "$age_out" "$serve" "$about" "${f#"$ROOT/"}")"$'\n'
    COUNT=$((COUNT + 1))
  done < <(collect_files)

  case "$FORMAT" in
    count)
      if [ "$COUNT" -eq 0 ]; then
        printf 'store: empty\n'
      else
        printf 'store: populated\n'
      fi
      printf 'count: %s\n' "$COUNT"
      ;;
    ids)
      if [ "$COUNT" -eq 0 ]; then
        printf 'store: empty\ncount: 0\n'
      else
        printf '%s' "$ROWS" | awk -F'\t' '{ print $1 }'
      fi
      ;;
    table)
      printf '| Id | Status | Observed | Age | Serving | About | Where |\n'
      printf '|---|---|---|---|---|---|---|\n'
      if [ "$COUNT" -eq 0 ]; then
        printf '| %s | %s | %s | %s | %s | %s | store present, no learning recorded |\n' \
          "$EMDASH" "$EMDASH" "$EMDASH" "$EMDASH" "$EMDASH" "$EMDASH"
      else
        while IFS=$'\t' read -r lid st obs age serve about where; do
          [ -n "$lid" ] || continue
          # An unverified learning is never rendered as a plain row. Read at a
          # glance, a bare status word disappears; the marker does not.
          if [ "$st" = "unverified" ]; then st="UNVERIFIED - not corroborated"; fi
          printf '| %s | %s | %s | %s | %s | %s | %s |\n' \
            "$(cell "$lid")" "$(cell "$st")" "$(cell "$obs")" "$(cell "$age")" \
            "$(cell "$serve")" "$(cell "$about")" "$(cell "$where")"
        done <<< "$ROWS"
      fi
      printf '\n'
      if [ "$COUNT" -eq 0 ]; then
        printf 'store: empty — the directory exists and holds no learning. This is a MEASURED zero.\n'
      else
        printf 'store: populated\n'
      fi
      printf 'count: %s\n' "$COUNT"
      printf 'dormant after: %s day(s), derived from Observed. No stale flag is stored.\n' "$DORMANT_AFTER"
      printf 'Nothing above is agreed. A learning informs; it never obligates and never outranks a requirement.\n'
      printf 'Ids and locations only — open the file to read what was observed.\n'
      ;;
  esac
  exit 0
  ;;

check)
  require_readable_store
  require_spec

  IDS_TSV="$(spec_ids "$SPEC")"

  FINDINGS=0
  CITATIONS=0
  SCANNED=0
  NOT_EVALUATED=""
  REPORT=""

  finding() {
    REPORT="$REPORT$(printf '    %s: %s' "$1" "$2")"$'\n'
    FINDINGS=$((FINDINGS + 1))
  }

  while IFS=$'\t' read -r n f; do
    [ -n "$n" ] || continue
    SCANNED=$((SCANNED + 1))
    rel="${f#"$ROOT/"}"
    L="L$n"

    st="$(header_field "$f" 'Status')"
    obs="$(header_field "$f" 'Observed')"
    obsby="$(header_field "$f" 'Observed by')"
    corr="$(header_field "$f" 'Corroborated')"
    corrby="$(header_field "$f" 'Corroborated by')"
    about="$(header_field "$f" 'About')"
    grad="$(header_field "$f" 'Graduated to')"

    # --- required fields ----------------------------------------------------
    for pair in "Status:$st" "Observed:$obs" "Observed by:$obsby"; do
      key="${pair%%:*}"; val="${pair#*:}"
      if [ -z "$val" ]; then
        finding "$rel" "$L has no '$key' value. A blank field and a missing line are indistinguishable to anything counting these files."
      elif [ "$val" = "$EMDASH" ]; then
        finding "$rel" "$L sets '$key' to an em dash. Status, date and provenance are what make this a record rather than a note; none of the three may be unset."
      fi
    done
    for pair in "Corroborated:$corr" "Corroborated by:$corrby" "About:$about" "Graduated to:$grad"; do
      key="${pair%%:*}"; val="${pair#*:}"
      if [ -z "$val" ]; then
        finding "$rel" "$L has no '$key' line, or leaves it blank. An unset field is an em dash, never blank."
      fi
    done

    # --- the status must be one of the four ---------------------------------
    case "$st" in
      unverified|verified|graduated|withdrawn|'') : ;;
      *) finding "$rel" "$L carries status '$st', which is not one of unverified, verified, graduated, withdrawn." ;;
    esac

    # --- the date must parse, and staleness is derived from it --------------
    if [ -n "$obs" ] && [ "$obs" != "$EMDASH" ]; then
      if [ -z "$(days_between "$obs" "$TODAY")" ]; then
        finding "$rel" "$L has an 'Observed' value that is not YYYY-MM-DD, so its age cannot be derived. It is reported with an age of an em dash and is NOT treated as infinitely old."
      fi
    fi

    # --- the state must agree with itself -----------------------------------
    case "$st" in
      unverified)
        if [ -n "$corrby" ] && [ "$corrby" != "$EMDASH" ]; then
          finding "$rel" "$L is unverified and names a corroborating source. The state and the record disagree; one of them is wrong."
        fi
        ;;
      verified)
        if [ -z "$corrby" ] || [ "$corrby" = "$EMDASH" ] || [ -z "$corr" ] || [ "$corr" = "$EMDASH" ]; then
          finding "$rel" "$L is verified and names no corroborating source or date. A verified state nobody can trace back is an assertion with a better word on it."
        elif [ "$corrby" = "$obsby" ]; then
          finding "$rel" "$L was corroborated by the same source that observed it. A source that can confirm its own learning promotes whatever it just wrote, and the verified state stops meaning anything."
        fi
        ;;
      graduated)
        case "$grad" in
          R[1-9]*)
            case "${grad#R}" in
              *[!0-9]*) finding "$rel" "$L is graduated and its 'Graduated to' is not a bare R<n>." ;;
              *)
                CITATIONS=$((CITATIONS + 1))
                # With no baseline there is nothing to resolve against, and
                # "the spec does not define it" would be an invented finding
                # taken from an unmeasurable comparison. Left unevaluated.
                if [ -n "$IDS_TSV" ]; then
                  gs="$(printf '%s\n' "$IDS_TSV" | awk -F'\t' -v id="$grad" '$1 == id { print $2; exit }')"
                  case "$gs" in
                    active) : ;;
                    '') finding "$rel" "$L graduated to $grad and the spec does not define it. The trail from observation to obligation is broken at the obligation end." ;;
                    *)  finding "$rel" "$L graduated to $grad, which the spec marks $gs. The obligation it became no longer governs." ;;
                  esac
                fi
                ;;
            esac
            ;;
          *) finding "$rel" "$L is graduated and names no requirement it graduated to. Graduation without an R id records nothing." ;;
        esac
        ;;
    esac

    # --- citations: the thing a plain notes file cannot do ------------------
    if [ -n "$about" ] && [ "$about" != "$EMDASH" ]; then
      for rid in $(printf '%s' "$about" | tr ',' ' '); do
        case "$rid" in
          R[1-9]*)
            case "${rid#R}" in *[!0-9]*) finding "$rel" "$L cites '$rid' in About, which is not a bare R<n>."; continue ;; esac
            ;;
          *) finding "$rel" "$L cites '$rid' in About, which is not a requirement id."; continue ;;
        esac
        CITATIONS=$((CITATIONS + 1))
        # Same guard as above, and the reason it is here: on an early run this
        # loop reported every citation in the store as "the spec does not
        # define it" when the spec held no ids at all. Three findings, all
        # invented, and exit 1 - a red run that named the wrong problem and
        # hid the real one, which was that nothing could be measured.
        [ -n "$IDS_TSV" ] || continue
        state="$(printf '%s\n' "$IDS_TSV" | awk -F'\t' -v id="$rid" '$1 == id { print $2; exit }')"
        case "$state" in
          active) : ;;
          '') finding "$rel" "$L cites $rid, which the spec does not define. The spec never deletes, so this citation resolves to nothing." ;;
          *)  finding "$rel" "$L cites $rid, which the spec marks $state. The learning is about a requirement that no longer governs." ;;
        esac
      done
    fi

    # --- unverified content presented as established fact -------------------
    # Only the quoted observation is scanned, and only when nothing has
    # corroborated it. An observation written in the language of an obligation
    # reads as a requirement to every later reader, which is exactly the
    # confusion this store exists to prevent.
    if [ "$st" = "unverified" ]; then
      hits="$(awk '
        /^## What was observed[[:space:]]*$/ { inobs = 1; next }
        /^## / { inobs = 0 }
        inobs && /^>/ {
          low = tolower($0)
          if (low ~ /(^|[^a-z])(must|shall|always|never|required|mandatory|guaranteed)([^a-z]|$)/) print FNR
        }
      ' "$f")"
      if [ -n "$hits" ]; then
        while IFS= read -r ln; do
          [ -n "$ln" ] || continue
          finding "$rel:$ln" "$L is unverified and its observation is written in the language of an obligation. Nothing has corroborated it, so it must not read as established. Open the line and reword it as what was seen."
        done <<< "$hits"
      fi
    fi
  done < <(collect_files)

  if [ "$CITATIONS" -gt 0 ] && [ -z "$IDS_TSV" ]; then
    NOT_EVALUATED="$CITATIONS citation(s) could not be resolved: $SPEC_REL holds no requirement ids matching '**R<n>**'. That is undetermined, not clean."
  fi

  N_ACTIVE=0; N_SUPER=0; N_WITHDRAWN=0
  if [ -n "$IDS_TSV" ]; then
    N_ACTIVE=$(printf '%s\n' "$IDS_TSV" | awk -F'\t' '$2=="active"' | wc -l | tr -d ' ')
    N_SUPER=$(printf '%s\n' "$IDS_TSV" | awk -F'\t' '$2=="superseded"' | wc -l | tr -d ' ')
    N_WITHDRAWN=$(printf '%s\n' "$IDS_TSV" | awk -F'\t' '$2=="withdrawn"' | wc -l | tr -d ' ')
  fi

  printf 'Learnings check — %s\n' "$STORE_REL"
  printf '  Baseline    %s — %s active, %s superseded, %s withdrawn requirement id(s)\n' \
    "$SPEC_REL" "$N_ACTIVE" "$N_SUPER" "$N_WITHDRAWN"
  printf '  Scanned     %s learning(s), %s requirement citation(s)\n' "$SCANNED" "$CITATIONS"
  printf '\n'
  if [ "$FINDINGS" -gt 0 ]; then
    printf '  Findings    %s\n' "$FINDINGS"
    printf '%s' "$REPORT"
  elif [ -n "$NOT_EVALUATED" ]; then
    printf '  Findings    %s — nothing was measured\n' "$EMDASH"
  else
    printf '  Findings    0 — a measured zero: %s learning(s) were read and every citation resolved.\n' "$SCANNED"
  fi
  printf '\n  What was NOT determined\n'
  if [ -n "$NOT_EVALUATED" ]; then
    printf '      - %s\n' "$NOT_EVALUATED"
  else
    printf '      - nothing beyond the standing limits below.\n'
  fi
  cat <<'CAVEAT'
      - Whether a learning is TRUE is not checked and cannot be. This reads
        ids, dates, states and citations. A corroborated learning that is
        wrong passes every line of this.
      - Whether a learning contradicts an active requirement is not checked.
        That needs a reader, and it is a finding for intake, not for a script.
      - Dormancy is presentation. A dormant learning is not a finding, is not
        deleted, and an unreadable date is never read as infinitely old.
CAVEAT
  printf '\n'

  if [ "$FINDINGS" -gt 0 ]; then exit 1; fi
  if [ -n "$NOT_EVALUATED" ]; then exit 4; fi
  exit 0
  ;;

verify)
  [ -n "$ID" ] || die_usage "--id is required"
  validate_l_id "$ID"
  [ -n "$BY" ] || die_usage "--by is required. A corroboration with no source named is the assertion again, one word louder."
  validate_oneline "$BY" "--by"
  require_readable_store

  F="$(find_by_id "$ID")" || refuse "$ID does not exist in $STORE_REL. Nothing was changed."
  [ -w "$F" ] || die_unread "$F is not writable."

  st="$(header_field "$F" 'Status')"
  obsby="$(header_field "$F" 'Observed by')"
  case "$st" in
    unverified) : ;;
    verified)   refuse "$ID is already verified. A second corroboration is a new line under ## Corroboration, not a state change." ;;
    *)          refuse "$ID carries status '$st'. Only an unverified learning can be corroborated." ;;
  esac

  # The whole point of the state. A run that corroborates its own learning
  # graduates whatever it just wrote, and every verified learning after it is
  # worth exactly nothing.
  if [ "$BY" = "$obsby" ]; then
    refuse "--by names the same source that observed $ID. The same source can never confirm its own learning; corroboration must come from somewhere else."
  fi

  TMP="$(mktemp "$STORE/.learnings.XXXXXX")"
  trap 'rm -f "$TMP"' EXIT HUP INT TERM
  awk -v today="$TODAY" -v by="$BY" '
    BEGIN { done_s = 0; done_c = 0; done_b = 0 }
    !done_s && /^Status:/            { print "Status: verified"; done_s = 1; next }
    !done_c && /^Corroborated:/      { print "Corroborated: " today; done_c = 1; next }
    !done_b && /^Corroborated by:/   { print "Corroborated by: " by; done_b = 1; next }
    { print }
  ' "$F" > "$TMP"
  printf '\n- %s — corroborated by an independent source.\n' "$TODAY" >> "$TMP"
  grep -qxF 'Status: verified' "$TMP" ||
    die_unread "the rewrite of $F did not produce a 'Status: verified' line. Nothing was moved into place."
  cat "$TMP" > "$F"
  rm -f "$TMP"
  trap - EXIT HUP INT TERM

  printf 'learning: %s\n' "${F#"$ROOT/"}"
  printf 'id: %s\n' "$ID"
  printf 'status: verified\n'
  printf 'corroborated: %s\n' "$TODAY"
  exit 0
  ;;

graduate)
  [ -n "$ID" ] || die_usage "--id is required"
  validate_l_id "$ID"
  [ -n "$TO" ] || die_usage "--to R<n> is required. Graduation without a requirement id records nothing."
  validate_r_id "$TO" "--to"
  require_readable_store
  require_spec

  IDS_TSV="$(spec_ids "$SPEC")"
  [ -n "$IDS_TSV" ] ||
    die_unread "$SPEC_REL holds no requirement ids matching '**R<n>**', so --to could not be resolved against anything."
  state="$(printf '%s\n' "$IDS_TSV" | awk -F'\t' -v id="$TO" '$1 == id { print $2; exit }')"
  case "$state" in
    active) : ;;
    '') refuse "--to names $TO, which the spec does not define. Merge the requirement first: an id in the spec is the merge, and this command only records that it happened." ;;
    *)  refuse "--to names $TO, which the spec marks $state. Graduating into a requirement that no longer governs records a trail to nowhere." ;;
  esac

  F="$(find_by_id "$ID")" || refuse "$ID does not exist in $STORE_REL. Nothing was changed."
  [ -w "$F" ] || die_unread "$F is not writable."
  st="$(header_field "$F" 'Status')"
  case "$st" in
    graduated) refuse "$ID has already graduated. It stopped being a learning then." ;;
    withdrawn) refuse "$ID is withdrawn. A withdrawn observation does not become an obligation." ;;
  esac

  TMP="$(mktemp "$STORE/.learnings.XXXXXX")"
  trap 'rm -f "$TMP"' EXIT HUP INT TERM
  awk -v to="$TO" '
    BEGIN { done_s = 0; done_g = 0 }
    !done_s && /^Status:/        { print "Status: graduated"; done_s = 1; next }
    !done_g && /^Graduated to:/  { print "Graduated to: " to; done_g = 1; next }
    { print }
  ' "$F" > "$TMP"
  printf '\n## Graduated\n\n%s became an obligation and is now %s in the living spec.\nIt stops being served as a learning; the id stays so the trail from the\nobservation to the requirement survives. Nothing here is edited afterwards.\n' \
    "$ID" "$TO" >> "$TMP"
  grep -qxF "Graduated to: $TO" "$TMP" ||
    die_unread "the rewrite of $F did not produce a 'Graduated to: $TO' line. Nothing was moved into place."
  cat "$TMP" > "$F"
  rm -f "$TMP"
  trap - EXIT HUP INT TERM

  printf 'learning: %s\n' "${F#"$ROOT/"}"
  printf 'id: %s\n' "$ID"
  printf 'status: graduated\n'
  printf 'graduated to: %s\n' "$TO"
  exit 0
  ;;

esac
