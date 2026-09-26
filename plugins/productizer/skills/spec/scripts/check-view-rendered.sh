#!/usr/bin/env bash
# check-view-rendered.sh [--root DIR] [--builder PATH] [--fixture DIR]
#                       [--node PATH] [--probe PATH]
#                       [--page FILE --case NAME] [--selftest] [--version] [--help]
#
# Asserts what the dashboard DRAWS, in a browser, against fixtures whose right
# answers are written down. Everything else in this repository that touches the
# view reads the generator: `build-view.sh --selftest` asserts the VZ_ARCH graph
# it DERIVES, and `check-view-readonly.sh` reads the page's bytes for what it
# reaches for. Between the derived graph and the pixels sits a page of
# JavaScript and 1200 lines of CSS that nothing committed has ever exercised.
# Two page-level breaks were caught there once, by a scratch script that was
# never committed - so the next one would not be. That is B62.
#
# THE THREE THINGS IT MUST CATCH, which are the three shapes of this failure:
#
#   1. A DELTA STATE DRAWN AS ANOTHER STATE. NEW, CHANGED, SUPERSEDED,
#      WITHDRAWN and REMOVED are five different facts about a requirement and
#      lead to five different next actions. The fixture puts one row of each on
#      the page with its id written down, and this asserts the row's word, its
#      glyph and its badge class - and that no two of the five share any of
#      them.
#
#   2. `unreadable` OR `absent` DRAWN AS A MEASURED ZERO. A result file that
#      could not be read and a result file that is not there must both draw the
#      `?` box and NO graph: no node, no count. A page that answers "0 checks,
#      0 failures" for a reading nobody took is the hollow green this whole
#      repository is built against. Asserted as: exactly one `?` box, and zero
#      nodes, zero stat tiles and zero delta rows on the same page. The same
#      for a spec delta with no base - `?`, never "nothing changed".
#
#   3. THE FIVE OVERLAY STATES BECOMING INDISTINGUISHABLE WITHOUT COLOUR.
#      `measured`, `never_ran`, `void`, `guard_shut` and `missing` are carried
#      by a glyph, a word and a border STYLE precisely so that they survive a
#      reader who cannot use the hue. This asserts that the five are pairwise
#      distinct on (border-style, border-width, fill) AND on the glyph AND on
#      the word - three times over, under the plain page, under
#      `forced-colors: active`, and under `prefers-contrast: more`.
#
#      Measured while writing this, and the reason the fill is in that tuple:
#      under forced colours Chrome THROWS THE HATCH AWAY, so `guard shut` comes
#      back as a flat fill and is left leaning on a border width that the
#      forced-colors block in the template supplies. The state that looks
#      safest in the template is the one the browser strips.
#
#   The `prefers-contrast` case also carries B57's regression guard: the
#   reading under that mode must DIFFER from the plain reading. v4.57.0 said
#   that media query was written when it was not, and for four releases
#   emulating the mode produced a page identical to the default - which is
#   exactly what this assertion goes red on.
#
# NO NETWORK, AND A SKIP IS LOUD. The probe aborts every request that is not
# file:, so the page's font link cannot make this depend on a name server. If
# node, puppeteer or a browser is missing, this exits 2 with what to install -
# never 0. A check that passes quietly when it could not run is the failure
# this repository refuses, and it is worse here than elsewhere: "the page draws
# the states correctly" would be asserted by a run in which no page was ever
# drawn.
#
# WHAT IT DRIVES. Four pages, built by the real `build-view.sh` from committed
# fixtures under `fixtures/arch-graph` and `fixtures/unmeasured-report/view`:
#
#   states, delta   the delta fixture repository, built here the way
#                   build-view.sh's own self-test builds it - `base-spec.md`
#                   committed with every sha input pinned, `spec.md` written
#                   over it uncommitted. One page carries all five overlay
#                   states AND all five delta words.
#   unreadable      a result file that is not parseable JSON
#   absent          a repository with no result file at all
#   no-base         `five-states.json`, which records no base, so the spec
#                   delta has nothing to difference against
#
# THE FIXTURE'S ANSWERS ARE HARDCODED HERE, and that is deliberate. Reading the
# expectation out of `build-view.sh --arch` would assert only that the page
# agrees with the deriver, and a deriver that lost a state would take the page
# with it and stay green. The ids and words below come from
# `fixtures/arch-graph/README.md`, which is where a person decided what each
# fixture row means.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every case drew what the fixture says it must
#   1  findings - a state drawn as another state, a `?` drawn as a zero, two
#      states a reader without colour cannot tell apart, or a mode that changed
#      nothing
#   2  could not run - bad usage, no work tree, no builder, no fixture, no
#      node, no puppeteer, no browser, or a page that would not build. Findings
#      win over unmeasured, so a run that broke something says so even when
#      another case could not be measured.
#
# WHAT IT PRINTS. One BARE repo-relative path per line for every file examined,
# which the runner parses as coverage. Case lines, findings and counts are
# INDENTED. No absolute path is printed: this output is tailed into a committed
# result file, and a home directory in it would be published to everyone who
# clones the repo.
#
# THE PROBE'S OWN EXIT CODES, since it is not separately declared anywhere:
# `view-render-probe.js` exits 0 having printed a reading, or 2 having printed
# why it could not - no page, no puppeteer, no browser. It never prints an
# empty reading and exits 0.
set -euo pipefail

VERSION="check-view-rendered 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$HERE")"

ROOT=""; BUILDER=""; FIXTURE=""; NODE_BIN=""; PROBE=""
PAGE=""; CASE=""
MODE="measure"

die_unmeasured() { printf 'check-view-rendered: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    # `--self-test` is an alias, not a second flag: this repository spells the
    # same obligation both ways, and a tool that answers only one spelling
    # reads as carrying no self-test to whichever scanner looks for the other.
    --selftest|--self-test) MODE="selftest"; shift ;;
    --root)       [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";     shift 2 ;;
    --root=*)     ROOT="${1#--root=}";       shift ;;
    --builder)    [ "$#" -ge 2 ] || die_unmeasured "--builder needs a path"; BUILDER="$2";  shift 2 ;;
    --builder=*)  BUILDER="${1#--builder=}"; shift ;;
    --fixture)    [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2";  shift 2 ;;
    --fixture=*)  FIXTURE="${1#--fixture=}"; shift ;;
    --node)       [ "$#" -ge 2 ] || die_unmeasured "--node needs a path";    NODE_BIN="$2"; shift 2 ;;
    --node=*)     NODE_BIN="${1#--node=}";   shift ;;
    --probe)      [ "$#" -ge 2 ] || die_unmeasured "--probe needs a path";   PROBE="$2";    shift 2 ;;
    --probe=*)    PROBE="${1#--probe=}";     shift ;;
    --page)       [ "$#" -ge 2 ] || die_unmeasured "--page needs a file";    PAGE="$2";     shift 2 ;;
    --page=*)     PAGE="${1#--page=}";       shift ;;
    --case)       [ "$#" -ge 2 ] || die_unmeasured "--case needs a name";    CASE="$2";     shift 2 ;;
    --case=*)     CASE="${1#--case=}";       shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1. The tree is named with --root." ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1. The tree is named with --root."

case "$CASE" in
  ""|states|delta|unreadable|absent|no-base) : ;;
  *) die_unmeasured "unknown --case $CASE. One of: states, delta, unreadable, absent, no-base." ;;
esac
if [ -n "$PAGE" ] && [ -z "$CASE" ]; then
  die_unmeasured "--page needs --case: a page with no case named asserts nothing, which is not a pass."
fi

# The work tree, never the working directory: run from a subdirectory this must
# assert the same thing it asserts from the root.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" \
    || die_unmeasured "no git work tree here, and --root was not given. Nothing was built and nothing is asserted."
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

[ -n "$BUILDER" ] || BUILDER="$HERE/build-view.sh"
[ -n "$FIXTURE" ] || FIXTURE="$SKILL/fixtures"
[ -n "$PROBE" ]   || PROBE="$HERE/view-render-probe.js"

[ -f "$BUILDER" ] || die_unmeasured "no view builder at the path given; there is no page to draw and nothing is asserted"
[ -f "$PROBE" ]   || die_unmeasured "no render probe at the path given; nothing can read a page and nothing is asserted"
[ -d "$FIXTURE/arch-graph/delta" ] \
  || die_unmeasured "no arch-graph delta fixture; the standing cases are missing, which is unmeasured and not a pass"

# --- the tools this cannot run without ------------------------------------
#
# Each of these is a LOUD refusal. The whole point of this check is that the
# page was drawn; a run that could not draw it has measured nothing.
NODE_NAMED=1
if [ -z "$NODE_BIN" ]; then
  NODE_BIN="${PRODUCTIZER_NODE:-}"
fi
if [ -z "$NODE_BIN" ]; then
  NODE_NAMED=0
  NODE_BIN="$(command -v node || true)"
fi
if [ -z "$NODE_BIN" ] || [ ! -x "$NODE_BIN" ]; then
  if [ "$NODE_NAMED" = "1" ]; then
    die_unmeasured "the node interpreter named with --node or PRODUCTIZER_NODE is not there or is not executable. The page was not drawn, so nothing about what it draws was measured."
  fi
  die_unmeasured "no node interpreter found. Install node, or name one with --node or PRODUCTIZER_NODE. The page was not drawn, so nothing about what it draws was measured."
fi

# Where puppeteer lives. NODE_PATH first because a caller who set it meant it;
# then an explicit variable; then the repository's own node_modules; then an
# npx cache under the home directory, which is how a machine that has ever run
# `npx puppeteer` already has both the module and a browser. No path is printed
# and none is written into a page.
find_puppeteer() {
  local cand
  if [ -n "${NODE_PATH:-}" ] && [ -d "$NODE_PATH/puppeteer" ]; then
    printf '%s\n' "$NODE_PATH"; return 0
  fi
  if [ -n "${PRODUCTIZER_PUPPETEER:-}" ] && [ -d "$PRODUCTIZER_PUPPETEER/puppeteer" ]; then
    printf '%s\n' "$PRODUCTIZER_PUPPETEER"; return 0
  fi
  if [ -d "$ROOT/node_modules/puppeteer" ]; then
    printf '%s\n' "$ROOT/node_modules"; return 0
  fi
  for cand in "${HOME:-/nonexistent}"/.npm/_npx/*/node_modules; do
    [ -d "$cand/puppeteer" ] && { printf '%s\n' "$cand"; return 0; }
  done
  return 1
}
PUPPET_PATH="$(find_puppeteer || true)"
[ -n "$PUPPET_PATH" ] \
  || die_unmeasured "puppeteer was not found. Install it (npm i puppeteer, which also fetches a browser) and name its node_modules with PRODUCTIZER_PUPPETEER or NODE_PATH. Nothing was rendered, so nothing about the rendering was measured."

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-view-rendered.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

FINDINGS=0
CASES=0
UPHELD=0
EXAMINED=""

note()    { printf '    %s\n' "$1"; }
finding() { FINDINGS=$((FINDINGS + 1)); printf '    FINDING  %s\n' "$1"; }
examined() { EXAMINED="$EXAMINED$1
"; }

# One assertion. `said` is what the case means, so a red line says which
# property broke rather than that something did.
hold() {  # hold <name> <ok:0|1> <said>
  CASES=$((CASES + 1))
  if [ "$2" = "0" ]; then
    UPHELD=$((UPHELD + 1))
    printf '    %-34s held     %s\n' "$1" "$3"
  else
    FINDINGS=$((FINDINGS + 1))
    printf '    %-34s FAILED   %s\n' "$1" "$3"
  fi
}

# --- building the fixture pages -------------------------------------------

# The delta fixture's repository, built exactly as build-view.sh's own
# self-test builds it: every input to the commit sha pinned, and the user's git
# configuration shut out so a signing setting cannot change the sha or refuse
# the commit. The sha is a constant the fixture's result.json names.
build_delta_repo() {  # build_delta_repo <dst>
  local dst="$1"
  mkdir -p "$dst/.claude/productizer"
  cp "$FIXTURE/arch-graph/delta/base-spec.md" "$dst/.claude/productizer/spec.md"
  (
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
    export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
    export GIT_AUTHOR_DATE=2000-01-01T00:00:00Z GIT_COMMITTER_DATE=2000-01-01T00:00:00Z
    git -C "$dst" init -q
    git -C "$dst" add .claude/productizer/spec.md
    git -C "$dst" -c commit.gpgsign=false commit -q --no-verify -m 'the base of the delta fixture'
  ) || return 1
  cp "$FIXTURE/arch-graph/delta/spec.md" "$dst/.claude/productizer/spec.md"
  cp "$FIXTURE/arch-graph/delta/result.json" "$dst/.claude/productizer/checks-result.json"
}

# A repository holding one result file and the delta fixture's spec. No git
# history: these cases are about a graph that cannot be drawn, and a base would
# only add a second thing to explain.
build_plain_repo() {  # build_plain_repo <dst> [result-file]
  local dst="$1" res="${2:-}"
  mkdir -p "$dst/.claude/productizer"
  cp "$FIXTURE/arch-graph/delta/spec.md" "$dst/.claude/productizer/spec.md"
  [ -z "$res" ] || cp "$res" "$dst/.claude/productizer/checks-result.json"
}

build_page() {  # build_page <repo> <out.html>
  bash "$BUILDER" "$1" --out "$2" >"$TMP/build.log" 2>&1
}

read_page() {  # read_page <page.html> <out.tsv>
  NODE_PATH="$PUPPET_PATH" "$NODE_BIN" "$PROBE" "$1" >"$2" 2>"$TMP/probe.err"
}

# --- reading the reading ---------------------------------------------------
#
# Every query below is a field selection over the probe's tab-separated
# records. Nothing greps the page itself: what the page draws is what the
# browser resolved, and the source is what build-view.sh's own self-test reads.

rd_count() {  # rd_count <tsv> <mode> <key>   -> the integer
  awk -F'\t' -v m="$2" -v k="$3" '$1=="count" && $2==m {
    for (i = 3; i <= NF; i++) { split($i, p, "="); if (p[1] == k) { print p[2]; exit } } }' "$1"
}
rd_nodes() {  # rd_nodes <tsv> <mode> <id-regex>  -> id word glyph style width fill
  awk -F'\t' -v m="$2" -v re="$3" '$1=="node" && $2==m && $3 ~ re {
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", $3, $4, $5, $6, $7, $8 }' "$1"
}
rd_drows() {  # rd_drows <tsv> <mode>  -> id word glyph class
  awk -F'\t' -v m="$2" '$1=="drow" && $2==m { printf "%s\t%s\t%s\t%s\n", $3, $4, $5, $8 }' "$1"
}
rd_dcount() { # rd_dcount <tsv> <mode> <label>  -> the value
  awk -F'\t' -v m="$2" -v l="$3" '$1=="dcount" && $2==m && $3==l { print $4; exit }' "$1"
}
rd_unread() { # rd_unread <tsv> <mode>  -> glyph + text
  awk -F'\t' -v m="$2" '$1=="unread" && $2==m { printf "%s %s\n", $3, $4 }' "$1"
}
rd_dunk() {   # rd_dunk <tsv> <mode>  -> glyph + text
  awk -F'\t' -v m="$2" '$1=="dunk" && $2==m { printf "%s %s\n", $3, $4 }' "$1"
}
rd_stat() {   # rd_stat <tsv> <mode> <label-fragment>  -> the value
  awk -F'\t' -v m="$2" -v f="$3" '$1=="stat" && $2==m && index($3, f) { print $4; exit }' "$1"
}

# A column of a reading, pairwise distinct. `sort -u` against the line count is
# the whole test: two states that resolved to the same tuple collapse into one
# line and the counts disagree.
all_distinct() {  # all_distinct <file> <field-list>   -> 0 distinct, 1 collapsed
  local n u
  n="$(cut -f "$2" < "$1" | wc -l | tr -d ' ')"
  u="$(cut -f "$2" < "$1" | sort -u | wc -l | tr -d ' ')"
  [ "$n" = "$u" ]
}

MODES="default forced-colors prefers-contrast"

# --- the cases -------------------------------------------------------------

case_states() {  # case_states <tsv>
  local tsv="$1" m f n
  for m in $MODES; do
    rd_nodes "$tsv" "$m" '^R[1-5]$' >"$TMP/states.$m"
    n="$(wc -l <"$TMP/states.$m" | tr -d ' ')"
    if [ "$n" != "5" ]; then
      hold "five-states-drawn/$m" 1 "the page drew $n of the fixture's 5 overlay states, so the rest are not asserted"
      continue
    fi
    hold "five-states-drawn/$m" 0 "R1..R5 are on the page, one per overlay state"

    # Field 2 is the word, 3 the glyph, and 4-6 the (style, width, fill) tuple
    # a reader keeps when the hue is gone.
    f=0; all_distinct "$TMP/states.$m" 4,5,6 || f=1
    hold "border-distinct/$m" "$f" "no two states share a (border style, width, fill), which is what is left without colour"
    f=0; all_distinct "$TMP/states.$m" 3 || f=1
    hold "glyph-distinct/$m" "$f" "the five glyphs are five glyphs"
    f=0; all_distinct "$TMP/states.$m" 2 || f=1
    hold "word-distinct/$m" "$f" "the five words are five words"
    f=0
    cut -f2 <"$TMP/states.$m" | grep -q '^$' && f=1
    hold "word-present/$m" "$f" "every state carries its word on the node, not only in a legend"
  done

  # The fixture's own table, from fixtures/arch-graph/README.md. A page that
  # renumbered the states would pass every distinctness assertion above.
  local id word ok
  ok=0
  while IFS='	' read -r id word; do
    awk -F'\t' -v id="$id" -v w="$word" \
      'BEGIN{bad=1} $1==id && index($2, w)==1 {bad=0} END{exit bad}' "$TMP/states.default" || ok=1
  done <<'NAMED'
R1	MEASURED
R2	VOID
R3	NEVER RAN
R4	GUARD SHUT
R5	MISSING
NAMED
  hold "states-named-right" "$ok" "each fixture id wears the state its README says it reaches"

  # B57's guard. `prefers-contrast: more` must change the drawing. For four
  # releases it changed nothing, and the release notes said it did.
  local same=1
  cmp -s "$TMP/states.default" "$TMP/states.prefers-contrast" || same=0
  hold "contrast-mode-changes-drawing" "$same" "the five states are drawn differently under prefers-contrast: more than under the plain page"
  # This one says LESS than it looks like it says, and the wording is the
  # measurement. Neutering the template's forced-colors block does NOT make it
  # go red - driven, 2026-09-26 - because the browser throws the hatch away by
  # itself, so the reading changes whether or not the block is there. What it
  # proves is that the mode reaches this page at all, which is the thing that
  # was false about `prefers-contrast` for four releases. That the block is
  # what keeps the two greys apart is NOT asserted here.
  same=1
  cmp -s "$TMP/states.default" "$TMP/states.forced-colors" || same=0
  hold "forced-colors-reaches-page" "$same" "the forced-colors mode changes what is drawn - the hatch goes. It does NOT assert that the template's block is what changed it"
}

case_delta() {  # case_delta <tsv>
  local tsv="$1" m f n rows
  for m in $MODES; do
    rd_drows "$tsv" "$m" >"$TMP/drows.$m"
    n="$(wc -l <"$TMP/drows.$m" | tr -d ' ')"
    if [ "$n" != "6" ]; then
      hold "delta-rows-drawn/$m" 1 "the page drew $n delta rows where the fixture moves 6 requirements"
      continue
    fi
    hold "delta-rows-drawn/$m" 0 "six requirements moved between the base and the working tree, and six rows are drawn"

    # Five change words, five glyphs, five classes - counted over the DISTINCT
    # words, because CHANGED legitimately appears twice.
    cut -f2,3,4 <"$TMP/drows.$m" | sort -u >"$TMP/dwords.$m"
    # Five rows out of six carry a change nothing else carries, and the sixth
    # is the second CHANGED. So the six rows must resolve to exactly five
    # drawings. Counting them is what catches one state drawn AS another: two
    # states that collapse onto one word, glyph and class leave four, and every
    # per-column distinctness test below still passes on four.
    f=0
    [ "$(wc -l <"$TMP/dwords.$m" | tr -d ' ')" = "5" ] || f=1
    hold "delta-five-drawings/$m" "$f" "the six rows resolve to exactly five drawings, one per change state"
    f=0; all_distinct "$TMP/dwords.$m" 1 || f=1
    hold "delta-word-per-state/$m" "$f" "no two change states share a word"
    f=0; all_distinct "$TMP/dwords.$m" 2 || f=1
    hold "delta-glyph-per-state/$m" "$f" "no two change states share a glyph"
    f=0; all_distinct "$TMP/dwords.$m" 3 || f=1
    hold "delta-class-per-state/$m" "$f" "no two change states share a badge class"
    f=0
    grep -q "UNREADABLE CHANGE" "$TMP/drows.$m" && f=1
    hold "delta-no-unreadable/$m" "$f" "no row fell through to the change word this page has no rendering for"
  done

  # The fixture's table again, by id.
  rows=0
  while IFS='	' read -r id word; do
    awk -F'\t' -v id="$id" -v w="$word" \
      'BEGIN{bad=1} $1==id && index($2, w) {bad=0} END{exit bad}' "$TMP/drows.default" || rows=1
  done <<'ROWS'
R2	CHANGED
R4	NEW
R6	SUPERSEDED
R7	WITHDRAWN
R8	REMOVED
R10	CHANGED
ROWS
  hold "delta-named-right" "$rows" "each moved id wears the change its README says it reaches, R10's moved pointer included"

  # The counts, which are a second drawing of the same fact and can disagree
  # with the rows.
  f=0
  [ "$(rd_dcount "$tsv" default '+|NEW')" = "1" ] || f=1
  [ "$(rd_dcount "$tsv" default 'Δ|CHANGED')" = "2" ] || f=1
  [ "$(rd_dcount "$tsv" default '↦|SUPERSEDED')" = "1" ] || f=1
  [ "$(rd_dcount "$tsv" default '⊖|WITHDRAWN')" = "1" ] || f=1
  [ "$(rd_dcount "$tsv" default '−|REMOVED')" = "1" ] || f=1
  [ "$(rd_dcount "$tsv" default 'unchanged')" = "4" ] || f=1
  hold "delta-counts" "$f" "the counts strip reads 1 new, 2 changed, 1 superseded, 1 withdrawn, 1 removed and 4 unchanged"

  # A base that WAS differenced against gets its number, not a question mark.
  f=0
  [ "$(rd_stat "$tsv" default 'files changed since')" = "2" ] || f=1
  hold "delta-base-counted" "$f" "with a base recorded the changed-file count is the number, not ?"
}

# The two shapes of "no reading", and the one shape they must never take.
case_nothing_drawn() {  # case_nothing_drawn <tsv> <case> <phrase>
  local tsv="$1" name="$2" phrase="$3" m f
  for m in $MODES; do
    f=0
    [ "$(rd_count "$tsv" "$m" unread)" = "1" ] || f=1
    hold "$name-box-drawn/$m" "$f" "exactly one ? box is drawn for a reading nobody could take"
    f=0
    rd_unread "$tsv" "$m" | grep -q '?' || f=1
    hold "$name-carries-glyph/$m" "$f" "the box carries the ? glyph this page means by read, and could not be determined"
    f=0
    rd_unread "$tsv" "$m" | grep -qi -- "$phrase" || f=1
    hold "$name-says-why/$m" "$f" "the box says which of the two it is, in words"
    f=0
    [ "$(rd_count "$tsv" "$m" nodes)" = "0" ] || f=1
    [ "$(rd_count "$tsv" "$m" stats)" = "0" ] || f=1
    [ "$(rd_count "$tsv" "$m" drows)" = "0" ] || f=1
    hold "$name-no-zeros/$m" "$f" "no node, no count tile and no delta row is drawn - a figure nobody took is never drawn as a zero"
  done
}

case_no_base() {  # case_no_base <tsv>
  local tsv="$1" m f
  for m in $MODES; do
    f=0
    [ "$(rd_count "$tsv" "$m" dunk)" = "1" ] || f=1
    hold "no-base-box-drawn/$m" "$f" "a spec delta with no base draws the ? block"
    f=0
    rd_dunk "$tsv" "$m" | grep -q '?' || f=1
    hold "no-base-carries-glyph/$m" "$f" "that block carries ?, not a count"
    f=0
    [ "$(rd_count "$tsv" "$m" drows)" = "0" ] || f=1
    hold "no-base-no-rows/$m" "$f" "no requirement is drawn as new, changed or removed against a base nobody recorded"
    f=0
    [ "$(rd_stat "$tsv" "$m" 'no base ref')" = "?" ] || f=1
    hold "no-base-files-unknown/$m" "$f" "the changed-file tile reads ?, not 0: 0 changed files is a measurement, and nobody made it"
  done
  # The graph itself IS readable here, so this case also proves the two are
  # independent: a page can draw every node and still know it has no base.
  f=0
  [ "$(rd_count "$tsv" default nodes)" = "16" ] || f=1
  hold "no-base-graph-still-drawn" "$f" "the graph is drawn in full - only the delta is unknown"
}

# --- one page, one case ----------------------------------------------------

run_case() {  # run_case <case> <page.html>
  local name="$1" page="$2" tsv="$TMP/reading-$1.tsv"
  read_page "$page" "$tsv" || {
    note "the probe could not read the page for case $name:"
    sed 's/^/      /' "$TMP/probe.err" >&2
    return 2
  }
  if grep -q '^pageerror	' "$tsv"; then
    finding "the page threw while drawing case $name, so what it drew is not what it meant to draw"
  fi
  case "$name" in
    states)     case_states "$tsv" ;;
    delta)      case_delta "$tsv" ;;
    unreadable) case_nothing_drawn "$tsv" unreadable "could not be read" ;;
    absent)     case_nothing_drawn "$tsv" absent "no result" ;;
    no-base)    case_no_base "$tsv" ;;
  esac
  return 0
}

# --- --page: assert one case against a page somebody else built ------------

if [ -n "$PAGE" ]; then
  [ -f "$PAGE" ] || die_unmeasured "no page at the path given; nothing was read and nothing is asserted"
  printf '  case %s, against a page handed over\n' "$CASE"
  run_case "$CASE" "$PAGE" || die_unmeasured "the page could not be read, so case $CASE is unmeasured"
  printf '    cases %d  upheld %d  findings %d\n' "$CASES" "$UPHELD" "$FINDINGS"
  [ "$FINDINGS" -eq 0 ] || exit 1
  exit 0
fi

# --- --selftest ------------------------------------------------------------

if [ "$MODE" = "selftest" ]; then
  SELF_CASES=0; SELF_UPHELD=0; CODES=""; MUTATIONS_LOST=0
  ST="$TMP/self"; mkdir -p "$ST"

  record() {  # record <name> <want> <got> <said>
    SELF_CASES=$((SELF_CASES + 1))
    CODES="$CODES$3
"
    if [ "$2" = "$3" ]; then
      SELF_UPHELD=$((SELF_UPHELD + 1))
      printf '  %-28s exit %s  as declared  %s\n' "$1" "$3" "$4"
    else
      printf '  %-28s exit %s  WANTED %s   %s\n' "$1" "$3" "$2" "$4"
    fi
  }

  # A break that does not apply is a case that proves nothing, so every
  # mutation is checked for having changed the page before it is driven.
  mutate() {  # mutate <src> <dst> <perl-expr> <what>
    perl -0pe "$3" <"$1" >"$2"
    if cmp -s "$1" "$2"; then
      # A break that did not apply is a case that drove nothing, and a self
      # test that quietly runs fewer cases than it lists is the failure this
      # whole check exists to refuse. So it ends the run rather than being
      # skipped past: the usual cause is a template edit that moved the text
      # the break matches, and the fix is to move the break with it.
      MUTATIONS_LOST=$((MUTATIONS_LOST + 1))
      printf '  %-28s MUTATION DID NOT APPLY   %s\n' "mutation-lost" "$4"
      return 1
    fi
    return 0
  }

  build_delta_repo "$ST/repo" || die_unmeasured "the delta fixture repository would not build; no case was driven"
  build_page "$ST/repo" "$ST/page.html" || {
    sed 's/^/      /' "$TMP/build.log" >&2
    die_unmeasured "the fixture page would not build; no case was driven"
  }
  build_plain_repo "$ST/corrupt" "$FIXTURE/unmeasured-report/view/checks-result-corrupt.json"
  build_page "$ST/corrupt" "$ST/corrupt.html" || die_unmeasured "the unreadable-result page would not build"

  got=0; bash "$0" --page "$ST/page.html" --case states >"$ST/s1.out" 2>&1 || got=$?
  record states-holds 0 "$got" "the five overlay states are drawn distinctly in all three modes"
  got=0; bash "$0" --page "$ST/page.html" --case delta >"$ST/s2.out" 2>&1 || got=$?
  record delta-holds 0 "$got" "the five change words are drawn, each as itself"
  got=0; bash "$0" --page "$ST/corrupt.html" --case unreadable >"$ST/s3.out" 2>&1 || got=$?
  record unreadable-holds 0 "$got" "a result that could not be read draws ? and no graph"

  # Break one: the prefers-contrast block is deleted. This is B57 as it stood
  # for four releases, and the case that would have caught it.
  if mutate "$ST/page.html" "$ST/no-contrast.html" \
      's/\@media \(prefers-contrast: more\)/\@media (prefers-contrast: never-matches)/g' \
      "the prefers-contrast block could not be found in the built page"; then
    got=0; bash "$0" --page "$ST/no-contrast.html" --case states >"$ST/s4.out" 2>&1 || got=$?
    record contrast-block-removed 1 "$got" "a mode that changes nothing is a finding, not a pass"
  fi

  # Break two: two states drawn the same way once the colour is gone. `shut`
  # loses its hatch and takes `never`'s border.
  if mutate "$ST/page.html" "$ST/collapsed.html" \
      's/\.ag-n\.a-shut\{border-width:1px;border-style:solid;border-color:var\(--muted\);\s*\n\s*background-image:repeating-linear-gradient\(135deg,\s*\n\s*color-mix\(in srgb,var\(--muted\) 24%,transparent\) 0 2px,transparent 2px 7px\)\}/.ag-n.a-shut{border-width:1px;border-style:dashed;border-color:var(--muted)}/' \
      "the guard-shut fill could not be found in the built page"; then
    got=0; bash "$0" --page "$ST/collapsed.html" --case states >"$ST/s5.out" 2>&1 || got=$?
    record two-states-collapsed 1 "$got" "a hatch traded for another state's border is caught without reading a colour"
  fi

  # Break three: a delta state drawn as another state.
  if mutate "$ST/page.html" "$ST/samewords.html" \
      's/withdrawn:\s*\{g:"⊖",\s*w:"WITHDRAWN",\s*k:"d-wd",/withdrawn:    {g:"↦", w:"SUPERSEDED", k:"d-sup",/' \
      "the delta change-word table could not be found in the built page"; then
    got=0; bash "$0" --page "$ST/samewords.html" --case delta >"$ST/s6.out" 2>&1 || got=$?
    record delta-state-as-another 1 "$got" "withdrawn drawn as superseded is a finding"
  fi

  # Break four: the unreadable branch is skipped, so a reading nobody took
  # falls through to whatever the rest of the code draws.
  if mutate "$ST/corrupt.html" "$ST/zeros.html" \
      's/if \(A\.state !== "read"\)\{/if (false){/' \
      "the unreadable branch could not be found in the built page"; then
    got=0; bash "$0" --page "$ST/zeros.html" --case unreadable >"$ST/s7.out" 2>&1 || got=$?
    record unreadable-drawn-as-graph 1 "$got" "a result that could not be read must never fall through to a drawing"
  fi

  # Break five: a base nobody recorded drawn as a number rather than as ?. The
  # graph on this page is perfectly readable, so nothing else on it goes red -
  # which is the point: the count tile is the only thing that lies.
  build_plain_repo "$ST/nobase" "$FIXTURE/arch-graph/five-states.json"
  build_page "$ST/nobase" "$ST/nobase.html" || die_unmeasured "the no-base page would not build"
  got=0; bash "$0" --page "$ST/nobase.html" --case no-base >"$ST/s13.out" 2>&1 || got=$?
  record no-base-holds 0 "$got" "a spec delta with no base draws ? and no row"
  if mutate "$ST/nobase.html" "$ST/nobase-zero.html" \
      's/strip\.appendChild\(stat\(hasBase && num\(D\.changed_files\) \? D\.changed_files : null,/strip.appendChild(stat(num(D.changed_files) ? D.changed_files : 0,/' \
      "the changed-file tile could not be found in the built page"; then
    got=0; bash "$0" --page "$ST/nobase-zero.html" --case no-base >"$ST/s14.out" 2>&1 || got=$?
    record no-base-drawn-as-number 1 "$got" "a count against a base nobody recorded is a figure nobody took"
  fi

  # Break six: the same fall-through as break four, on the page where the
  # result file is ABSENT rather than unreadable. The two lead to different
  # sentences and the page must not offer one for the other.
  build_plain_repo "$ST/absent"
  build_page "$ST/absent" "$ST/absent.html" || die_unmeasured "the no-result page would not build"
  got=0; bash "$0" --page "$ST/absent.html" --case absent >"$ST/s15.out" 2>&1 || got=$?
  record absent-holds 0 "$got" "no result file at all draws ? and says so"
  if mutate "$ST/absent.html" "$ST/absent-fallthrough.html" \
      's/if \(A\.state !== "read"\)\{/if (false){/' \
      "the unreadable branch could not be found in the no-result page"; then
    got=0; bash "$0" --page "$ST/absent-fallthrough.html" --case absent >"$ST/s16.out" 2>&1 || got=$?
    record absent-drawn-as-empty 1 "$got" "a result that is not there must not be drawn as a reading that came back empty"
  fi

  got=0; bash "$0" --page "$ST/no-such-page.html" --case states >"$ST/s8.out" 2>&1 || got=$?
  record missing-page 2 "$got" "a page that is not there is unmeasured, never clean"
  got=0; bash "$0" --not-a-real-option >"$ST/s9.out" 2>&1 || got=$?
  record unknown-option 2 "$got" "bad usage is refused, never answered"
  got=0; bash "$0" --case >"$ST/s10.out" 2>&1 || got=$?
  record option-without-value 2 "$got" "an option missing its argument is refused"
  got=0; bash "$0" --case not-a-case >"$ST/s11.out" 2>&1 || got=$?
  record unknown-case 2 "$got" "a case nobody declared is refused rather than skipped"
  got=0; bash "$0" --page "$ST/page.html" >"$ST/s12.out" 2>&1 || got=$?
  record page-without-case 2 "$got" "a page with no case named asserts nothing, which is not a pass"

  if [ "$SELF_CASES" = "$SELF_UPHELD" ]; then self_verdict="held"; else self_verdict="NOT HELD"; fi
  printf '    R39  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$SELF_CASES" "$SELF_UPHELD" "$self_verdict" \
    "each case exits with the code this file's contract declares for it"
  REACHED="$(printf '%s' "$CODES" | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  printf '    NOT ASSERTED: the WORDING of any finding, and that a case went red for the reason its break names rather than for another. The six breaks are applied to a BUILT page, so a template edit that moves the text they match reads as a mutation that did not apply, which is printed and fails the run rather than silently driving one case fewer.\n'
  [ "$SELF_CASES" = "$SELF_UPHELD" ] || exit 1
  if [ "$MUTATIONS_LOST" -ne 0 ]; then
    printf 'FAIL: %d break(s) could not be applied, so that many cases drove nothing\n' \
      "$MUTATIONS_LOST" >&2
    exit 1
  fi
  if [ -n "$MISSING" ]; then
    printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  exit 0
fi

# --- the standing run ------------------------------------------------------

# Coverage is printed as repo-relative paths, and ONLY for files that really
# are under the work tree. An installed copy of this plugin lives outside it,
# and printing an absolute path there would put somebody's home directory into
# a committed result file - the leak that shipped once in v4.2.0.
for path in "$SKILL/templates/view.html" "$PROBE"; do
  rel="${path#"$ROOT"/}"
  if [ "$rel" = "$path" ]; then
    note "examined a file outside the work tree, so it is not reported as coverage: the view template"
  else
    examined "$rel"
  fi
done

build_delta_repo "$TMP/delta" \
  || die_unmeasured "the delta fixture repository would not build - git refused. No page was drawn and no case was driven."
build_page "$TMP/delta" "$TMP/delta.html" || {
  sed 's/^/      /' "$TMP/build.log" >&2
  die_unmeasured "the fixture page would not build; no case was driven"
}
build_plain_repo "$TMP/corrupt" "$FIXTURE/unmeasured-report/view/checks-result-corrupt.json"
build_page "$TMP/corrupt" "$TMP/corrupt.html" \
  || die_unmeasured "the unreadable-result page would not build; that case is unmeasured"
build_plain_repo "$TMP/absent"
build_page "$TMP/absent" "$TMP/absent.html" \
  || die_unmeasured "the no-result page would not build; that case is unmeasured"
build_plain_repo "$TMP/nobase" "$FIXTURE/arch-graph/five-states.json"
build_page "$TMP/nobase" "$TMP/nobase.html" \
  || die_unmeasured "the no-base page would not build; that case is unmeasured"

UNMEASURED=0
for spec in "states:$TMP/delta.html" "delta:$TMP/delta.html" \
            "unreadable:$TMP/corrupt.html" "absent:$TMP/absent.html" \
            "no-base:$TMP/nobase.html"; do
  name="${spec%%:*}"; page="${spec#*:}"
  printf '  case %s\n' "$name"
  run_case "$name" "$page" || UNMEASURED=1
done

printf '%s' "$EXAMINED"
printf '    cases %d  upheld %d  findings %d\n' "$CASES" "$UPHELD" "$FINDINGS"
printf '    NOT ASSERTED: colour. Every assertion here is deliberately blind to hue, because a reader who cannot use it must still be able to tell the five states apart. Contrast RATIOS are not measured either - the ones behind the prefers-contrast block were computed by hand and written into the template beside the tokens. Nor is the forced-colors BLOCK: deleting it leaves the five states distinct in this browser, because the hatch is thrown away by the browser and not by the rule, so of the two contrast modes only prefers-contrast has a case here that goes red when its block is removed.\n'

# Findings win over unmeasured: a run that definitely broke something says so
# even when some other case could not be read.
[ "$FINDINGS" -eq 0 ] || exit 1
[ "$UNMEASURED" -eq 0 ] || die_unmeasured "a case could not be read, so it is unmeasured and not a pass"
exit 0
