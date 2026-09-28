#!/usr/bin/env bash
# build-requirement-index.sh [--root DIR] [--spec FILE] [--index FILE] [--check]
#                            [--selftest|--self-test] [--version] [--help]
#
# Regenerates the requirement index of a living spec FROM THAT SPEC, into its
# own file beside it, and with --check reports the drift without writing. Same
# shape as build-guide.sh and its `--check`: one generated region between two
# markers, every byte outside them left as its author left it.
#
# THE INDEX IS NOT IN THE SPEC, AND THE REASON IS MEASURED. It was generated
# inside the spec's `## Requirement index` section first. That made requirement
# lookup more expensive: a search for one id also hit its index row and read
# the rows around it. retrieval-budget.sh went red on 5 of 10 prompts, summed
# retrieval 7,916 -> 10,477 characters (+32%), `missing-tool` mix 24% -> 56%.
# So the table lives in .claude/productizer/requirement-index.md (--index), the
# spec's section is a pointer holding no id, and this file only READS the spec.
#
# WHY IT EXISTS. The index says to maintain it once the spec passes roughly
# thirty requirements. This repository's spec passed that and still carried the
# template's three example rows - `R2 ... superseded by R41`, `R3 ... withdrawn`
# - each FALSE about the requirement carrying that id. Nothing compared the
# index with the requirements, so it was a table that looked authoritative and
# described a spec that never existed. A hand-kept index goes stale the day
# nobody remembers it; a generated one is a function of the spec and nothing
# else, so its staleness is a finding a machine can name.
#
# WHERE EACH COLUMN COMES FROM. Nothing is typed by hand and nothing is guessed.
#
#   Id           the requirement id, one row per requirement, in id order.
#                Read through spec-requirements.sh, the one parser the checks
#                already share. This file does NOT parse requirements itself:
#                two parsers that disagree about what a requirement is make two
#                checks that are each green in their own terms.
#   Pattern      the `### ` heading under `## Requirements` the requirement is
#                FILED under - ubiquitous, event, state, unwanted, optional,
#                complex, the six of references/format-spec.md section 2.
#                Placement is grammar there ("the pattern must match the
#                section it is filed under"), so the heading is authoritative
#                and the sentence is never read. A requirement under a heading
#                that is none of the six, or under no heading, is REFUSED (3):
#                naming a pattern for it would be inventing one.
#   Status       `active`, `superseded by R<n>` with the target the parser read
#                off the marker, or `withdrawn`. A `malformed` status - two
#                markers, or a marker the grammar does not recognise - is
#                REFUSED (3), because its status is undefined and the index
#                would have to pick one.
#   Verified by  every check id the `## Acceptance criteria` row for that
#                requirement cites, in the order cited, duplicates dropped.
#                `—` where the requirement has NO row. `no check cited` where
#                it has a row that cites no check - a different fact, kept
#                apart, because "nobody wrote a row" and "the row names a
#                fixture, a path or a promise" are two different gaps.
#
# THE CHECK-ID RULE IS check-acceptance-rows.sh's, COPIED, NOT INVENTED. A
# check citation is a backticked span whose first word has the shape of a
# checks.yaml `id:` AND is followed by the word `check` / `checks`. Anywhere in
# the row, not only at its start: that is the rule the acceptance check applies,
# and an index that read citations differently from the check that audits them
# would disagree with it about the same row. The regexes below are that file's
# RE_ACROW, RE_MD_PIPE, RE_SPAN, RE_ID_SHAPE, RE_IS_CHECK and RE_LINE_SUFFIX,
# and its first-row-wins rule for a requirement with two rows. They live inline
# there, inside a heredoc, so there is nothing to import; if that file's rule
# changes, this copy must change with it. Two consequences, both deliberate:
#   - a row saying `same check, the ...` with no backticked id cites no check,
#     and its requirement reads `no check cited` even where the prose makes
#     clear which check was meant. The acceptance check reads it the same way.
#   - checks.yaml is NOT read. Whether a cited check is declared, enabled and
#     claims the requirement is acceptance-rows' assertion (R36.b, R36.c); the
#     index records what the row CITES, and asserts nothing about it.
#
# THE AREA COLUMN, AND WHY IT IS USUALLY ABSENT. The template's index carries
# an `Area` column. This spec has no area concept anywhere: the only grammar
# for one is a `#### area` sub-heading inside a pattern section (format-spec.md
# section 2), and this spec holds ZERO `#### ` headings - measured, not
# assumed. The `### <area>` under `## Design` is the template's unfilled
# placeholder and is not a requirement grouping. So the column is filled ONLY
# from `#### ` sub-headings, and is OMITTED ENTIRELY when no requirement in the
# spec sits under one. A column holding `—` or `<area>` on every row is a
# placeholder that reads like data, which is exactly the defect this file was
# written to remove. A spec that does use `#### area` gets the column, with
# `—` for a requirement filed directly under its pattern heading - a real
# absence, not a guess.
#
# MARKERS ABSENT IS A REFUSAL, NOT A BEST GUESS. The index file must exist and
# hold exactly one begin and one end marker, begin first. Anything else exits 2
# and prints what to paste - a generator that picks a plausible spot overwrites
# text somebody wrote. The old rule that the markers sit inside the spec's
# `## Requirement index` section is gone with the table; two rules replace it,
# both refusals (2), both because they would quietly undo the move:
#   - --index must not name the spec itself. Writing the table back into the
#     spec is exactly the lookup cost the move removed.
#   - the SPEC must carry no requirement-index marker. A marker pair left there
#     would hold a table this file no longer writes or checks - a stale copy
#     that looks generated. This file never writes the spec, so it refuses
#     rather than delete it.
#
# A HAND EDIT INSIDE THE MARKERS IS DRIFT. The region is compared byte for
# byte with a fresh render, and --check names what moved per id: a row missing,
# a row for no requirement, a row that differs, or the header. A hand edit that
# is TRUE is still drift - the fix is to change the spec and regenerate, so the
# two cannot disagree tomorrow.
#
# NO CLOCK IS WRITTEN, for build-guide.sh's reason: two runs against an
# unchanged spec must be byte-identical, or --check goes red every day.
#
# --ROOT DEFAULTS TO THE WORK TREE, NEVER THE WORKING DIRECTORY.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  written, or already current (--check: the region equals a fresh render)
#   1  --check only: the region between the markers differs from what the spec
#      produces today. Write mode never returns 1 - regenerating IS the fix.
#   2  cannot run - bad usage, no repository root, python3 absent, an index
#      file that is missing or unreadable, an index whose markers are missing,
#      duplicated or out of order, an --index naming the spec itself, or a spec
#      that still carries a requirement-index marker
#   3  COULD NOT READ THE SPEC INTO AN INDEX - unreadable, no `## Requirements`
#      or no requirement in it, no readable `## Acceptance criteria` table, a
#      duplicated id, a `malformed` status, or a requirement filed under no
#      recognised pattern heading. Never rendered as an empty or partial index:
#      an index built from a spec nobody could read describes nothing.
#
# --SELFTEST DRIVES ALL FOUR, each from a spec and an index file written into a
# temporary directory; nothing in the repository is touched. Under --selftest the exit
# code means: every case held (0), at least one did not or a documented code
# was never reached (1), the corpus could not be built (2). `--self-test` is
# accepted as an alias, as in build-guide.sh.
set -euo pipefail

VERSION="build-requirement-index 1.1"

usage() {
  printf 'usage: build-requirement-index.sh [--root DIR] [--spec FILE] [--index FILE] [--check] [--selftest] [--version] [--help]\n'
}

ROOT=""; SPEC=""; INDEX=""; MODE="write"

need_value() {
  [ -n "${2:-}" ] || { printf 'build-requirement-index: %s needs a value\n' "$1" >&2; usage >&2; exit 2; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root)    need_value "$1" "${2:-}"; ROOT="$2"; shift 2 ;;
    --spec)    need_value "$1" "${2:-}"; SPEC="$2"; shift 2 ;;
    --index)   need_value "$1" "${2:-}"; INDEX="$2"; shift 2 ;;
    --check)   MODE="check"; shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *)         printf 'build-requirement-index: unknown argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$HERE/spec-requirements.sh"

# --------------------------------------------------------------- --selftest
#
# Every case is a spec written into a temporary directory, this script run
# against it as a child process, and the exit code read off the child. The
# clean case is a ROUND TRIP - write, then --check - so there is no golden file
# to drift. Each red case also asserts a SENTENCE on the child's output, so a
# case that goes red for the wrong reason is not counted as held.
if [ "$MODE" = "selftest" ]; then
  SELF_TMP="$(mktemp -d "${TMPDIR:-/tmp}/build-requirement-index-selftest.XXXXXX")" || {
    printf 'build-requirement-index: cannot create a temporary directory to build the self-test corpus in. Unmeasured, not a pass.\n' >&2
    exit 2; }
  trap 'rm -rf "$SELF_TMP"' EXIT HUP INT TERM
  command -v python3 >/dev/null 2>&1 || {
    printf 'build-requirement-index: python3 is not installed, so no case could be driven. Unmeasured, not a pass.\n' >&2
    exit 2; }

  CASE_ROOT="$SELF_TMP/repo"
  mkdir -p "$CASE_ROOT/.claude/productizer"
  FIX="$CASE_ROOT/.claude/productizer/requirement-index.md"
  SPECFIX="$CASE_ROOT/.claude/productizer/spec.md"
  # The index file as a repository starts it: a header and an empty marker
  # pair. The header line is asserted to survive a write.
  cat > "$FIX" <<'FIXTURE_INDEX'
# Requirement index

GENERATED from the fixture spec. Do not edit by hand.

<!-- productizer:requirement-index:begin -->
<!-- productizer:requirement-index:end -->
FIXTURE_INDEX
  # Three patterns, one superseded requirement, one requirement with a row
  # citing a check, one with a row citing none, one with no row at all. The
  # spec's index section is a pointer and carries no marker.
  cat > "$SPECFIX" <<'FIXTURE_SPEC'
# Fixture spec

## Requirement index

Generated into requirement-index.md.

## Requirements

### Ubiquitous

- **R1** — The lifecycle shall do the first thing.

### Event-driven

- **R2** — When a thing arrives, the lifecycle shall do the second thing.
  Superseded by R4. Narrowed.
- **R4** — When a thing arrives, the lifecycle shall do the narrower thing.

### Unwanted behaviour

- **R3** — If a thing fails, then the lifecycle shall stop.

## Acceptance criteria

| Requirement | Verified by |
|---|---|
| R1 | `first-check` check over `first.sh`, and `other` with no citation word |
| R3 | reviewed at intake |

## Change log

Nothing.
FIXTURE_SPEC

  SELF_CASES=0
  SELF_UPHELD=0
  # R39.b: the reached half of the declaration is ACCUMULATED here, one entry
  # per case as it ran. A literal list would satisfy the reader and prove
  # nothing.
  CODES=""
  # Set when a fixture edit did not apply. The next case is then NOT HELD for
  # that reason, rather than the whole self-test aborting under `set -e` - an
  # abort would be exit 2, "the corpus could not be built", which misnames a
  # renderer that produced something the fixture edits could not find.
  FIXTURE_BROKEN=""

  # run_case <name> <expected-exit> <sentence-or-empty> <what> -- <args...>
  # The sentence is a fixed string that must appear on the child's stdout or
  # stderr; empty means the exit code alone is asserted.
  run_case() {
    local name="$1" want="$2" sentence="$3" what="$4"
    shift 5
    local got=0 verdict
    bash "$0" "$@" > "$SELF_TMP/out" 2> "$SELF_TMP/err" || got=$?
    SELF_CASES=$((SELF_CASES + 1))
    CODES="$CODES$got
"
    verdict="held"
    if [ -n "$FIXTURE_BROKEN" ]; then
      verdict="NOT HELD (fixture did not apply: $FIXTURE_BROKEN)"
      FIXTURE_BROKEN=""
    elif [ "$got" != "$want" ]; then
      verdict="NOT HELD"
    elif [ -n "$sentence" ] && ! cat "$SELF_TMP/out" "$SELF_TMP/err" | grep -qF -- "$sentence"; then
      verdict="NOT HELD (right code, wrong reason)"
    fi
    if [ "$verdict" = "held" ]; then SELF_UPHELD=$((SELF_UPHELD + 1)); fi
    printf '      %-28s expected %s  got %s  %s  %s\n' "$name" "$want" "$got" "$verdict" "$what"
    if [ "$verdict" != "held" ]; then
      sed 's/^/          stdout: /' "$SELF_TMP/out"
      sed 's/^/          stderr: /' "$SELF_TMP/err"
    fi
  }

  # variant <name> <python-replace-old> <python-replace-new> [file]: a copy of
  # the CURRENT fixture tree with one literal substitution in its spec (or in
  # the named file under .claude/productizer), asserted to have applied - a
  # substitution that matched nothing would leave a case that is red or green
  # for a reason unrelated to its name.
  variant() {
    rm -rf "${SELF_TMP:?}/${1:?}"
    cp -R "$CASE_ROOT" "$SELF_TMP/$1"
    if python3 - "$SELF_TMP/$1/.claude/productizer/${4:-spec.md}" "$2" "$3" <<'SUBST'
import io
import sys
path, old, new = sys.argv[1:4]
old = old.replace("\\n", "\n")
new = new.replace("\\n", "\n")
with io.open(path, encoding="utf-8") as fh:
    text = fh.read()
if old not in text:
    sys.stderr.write("self-test fixture: substitution matched nothing: %r\n" % old)
    raise SystemExit(2)
with io.open(path, "w", encoding="utf-8") as fh:
    fh.write(text.replace(old, new, 1))
SUBST
    then :; else FIXTURE_BROKEN="variant $1"; fi
  }

  printf '    selftest: %s\n' "$VERSION"

  SPEC_SUM_BEFORE="$(cksum < "$SPECFIX")"
  run_case write-into-markers 0 "wrote the requirement index" \
    "the table is generated between the two markers" -- --root "$CASE_ROOT"
  run_case check-current 0 "up to date with the spec" \
    "the table just written is what the spec produces today" -- --root "$CASE_ROOT" --check
  run_case write-again-is-a-no-op 0 "nothing written" \
    "an unchanged spec renders byte-identically" -- --root "$CASE_ROOT"

  # The rows the fixture must produce. Asserted on the written file, because
  # every case above passes on a renderer that is merely self-consistent.
  # Not an exit code: no process ran, so nothing is added to CODES.
  SELF_CASES=$((SELF_CASES + 1))
  if grep -qxF '| R1 | ubiquitous | active | `first-check` |' "$FIX" &&
     grep -qxF '| R2 | event | superseded by R4 | — |' "$FIX" &&
     grep -qxF '| R3 | unwanted | active | no check cited |' "$FIX" &&
     grep -qxF '| R4 | event | active | — |' "$FIX" &&
     grep -qxF '| Id | Pattern | Status | Verified by |' "$FIX" &&
     grep -qxF 'GENERATED from the fixture spec. Do not edit by hand.' "$FIX"; then
    SELF_UPHELD=$((SELF_UPHELD + 1))
    printf '      %-28s expected rows  held  pattern from heading, status from marker, three Verified-by cases, no Area column, header kept\n' rendered-rows
  else
    printf '      %-28s expected rows  NOT HELD\n' rendered-rows
    sed 's/^/          index: /' "$FIX"
  fi

  # The spec is READ, never written: byte-identical after three runs.
  SELF_CASES=$((SELF_CASES + 1))
  if [ "$(cksum < "$SPECFIX")" = "$SPEC_SUM_BEFORE" ] &&
     ! grep -qF 'productizer:requirement-index' "$SPECFIX"; then
    SELF_UPHELD=$((SELF_UPHELD + 1))
    printf '      %-28s expected same  held  the spec is byte-identical after writing the index\n' spec-untouched
  else
    printf '      %-28s expected same  NOT HELD  the spec changed while the index was written\n' spec-untouched
  fi

  variant hand-edit '| R3 | unwanted | active |' '| R3 | unwanted | withdrawn |' requirement-index.md
  run_case check-hand-edited-row 1 "R3 row differs" \
    "a row edited by hand inside the markers is drift" -- --root "$SELF_TMP/hand-edit" --check

  variant added '### Unwanted behaviour\n' '### Unwanted behaviour\n\n- **R5** — If a thing leaks, then the lifecycle shall report it.\n'
  run_case check-requirement-added 1 "R5 is in the spec and has no index row" \
    "a requirement added with no index row" -- --root "$SELF_TMP/added" --check

  variant status '- **R3** — If a thing fails, then the lifecycle shall stop.\n' '- **R3** — If a thing fails, then the lifecycle shall stop.\n  Withdrawn. Gone.\n'
  run_case check-status-changed 1 "R3 row differs" \
    "a requirement withdrawn in the spec and still active in the index" -- --root "$SELF_TMP/status" --check

  variant acrow '| R3 | reviewed at intake |' '| R3 | `third-check` check |'
  run_case check-acceptance-changed 1 "R3 row differs" \
    "an acceptance row that now cites a check" -- --root "$SELF_TMP/acrow" --check

  variant area '### Ubiquitous\n' '### Ubiquitous\n\n#### Storage\n'
  run_case check-area-appears 1 "the table header differs" \
    "a first #### area sub-heading adds the Area column" -- --root "$SELF_TMP/area" --check

  variant nomark '<!-- productizer:requirement-index:begin -->\n' '' requirement-index.md
  run_case markers-deleted 2 "0 begin marker(s)" \
    "a missing marker is refused, never guessed around" -- --root "$SELF_TMP/nomark" --check
  if python3 - "$SELF_TMP/nomark/.claude/productizer/requirement-index.md" <<'STRIP_END'
import io
import sys
p = sys.argv[1]
with io.open(p, encoding="utf-8") as fh:
    t = fh.read()
E = "<!-- productizer:requirement-index:end -->\n"
if E not in t:
    raise SystemExit(2)
with io.open(p, "w", encoding="utf-8") as fh:
    fh.write(t.replace(E, "", 1))
STRIP_END
  then :; else FIXTURE_BROKEN="strip the end marker"; fi
  run_case both-markers-deleted 2 "carries no requirement-index markers" \
    "no markers at all, in write mode" -- --root "$SELF_TMP/nomark"

  variant twobegin '<!-- productizer:requirement-index:end -->\n' '<!-- productizer:requirement-index:end -->\n<!-- productizer:requirement-index:begin -->\n' requirement-index.md
  run_case marker-duplicated 2 "2 begin marker(s)" \
    "a second begin marker in the index file" -- --root "$SELF_TMP/twobegin" --check

  # The two markers swapped in place: one of each, in the wrong order.
  rm -rf "$SELF_TMP/reversed"
  cp -R "$CASE_ROOT" "$SELF_TMP/reversed"
  if python3 - "$SELF_TMP/reversed/.claude/productizer/requirement-index.md" <<'SWAP_MARKERS'
import io
import sys
p = sys.argv[1]
B = "<!-- productizer:requirement-index:begin -->"
E = "<!-- productizer:requirement-index:end -->"
with io.open(p, encoding="utf-8") as fh:
    t = fh.read()
if t.count(B) != 1 or t.count(E) != 1:
    raise SystemExit(2)
t = t.replace(B, "\0").replace(E, B).replace("\0", E)
with io.open(p, "w", encoding="utf-8") as fh:
    fh.write(t)
SWAP_MARKERS
  then :; else FIXTURE_BROKEN="swap the markers"; fi
  run_case markers-reversed 2 "end marker comes before the begin marker" \
    "one of each, in the wrong order, is not a region" -- --root "$SELF_TMP/reversed"

  rm -rf "$SELF_TMP/noindex"
  cp -R "$CASE_ROOT" "$SELF_TMP/noindex"
  rm -f "$SELF_TMP/noindex/.claude/productizer/requirement-index.md"
  run_case index-file-missing 2 "cannot read the index file" \
    "no index file is refused, never created at a guessed path" -- --root "$SELF_TMP/noindex"

  # The move undone two ways: the table pointed back into the spec, and a
  # marker pair left behind in the spec beside a well-formed index file.
  run_case index-is-the-spec 2 "names the spec itself" \
    "writing the index into the spec is the lookup cost the move removed" -- --root "$CASE_ROOT" --index "$SPECFIX"
  variant leftover 'Generated into requirement-index.md.\n' 'Generated into requirement-index.md.\n\n<!-- productizer:requirement-index:begin -->\n<!-- productizer:requirement-index:end -->\n'
  run_case markers-left-in-spec 2 "still carries a requirement-index marker" \
    "a marker pair in the spec would hold a table nothing checks" -- --root "$SELF_TMP/leftover" --check

  run_case root-does-not-exist 2 "no such directory" \
    "a root that is not a directory is refused" -- --root "$SELF_TMP/no-such-root" --check
  run_case unknown-argument 2 "unknown argument" \
    "bad usage is refused" -- --not-a-real-option
  run_case option-without-value 2 "needs a value" \
    "an option missing its argument is refused" -- --root

  run_case spec-unreadable 3 "cannot read the spec" \
    "a spec nobody could open" -- --root "$CASE_ROOT" --spec "$SELF_TMP/no-such-spec.md" --check

  printf '# nothing\n\n## Requirement index\n\n## Requirements\n\n## Acceptance criteria\n\n| R | V |\n|---|---|\n' > "$SELF_TMP/empty-spec.md"
  run_case spec-has-no-requirements 3 "holds no requirement" \
    "no requirement read is unmeasured, not an empty index" -- --root "$CASE_ROOT" --spec "$SELF_TMP/empty-spec.md" --check

  variant badhead '### Unwanted behaviour\n' '### Misc\n'
  run_case unrecognised-pattern-heading 3 "none of the six pattern headings" \
    "a requirement under a heading that names no pattern" -- --root "$SELF_TMP/badhead" --check

  variant malformed '  Superseded by R4. Narrowed.\n' '  Superseded by R4. Narrowed.\n  Withdrawn. Also.\n'
  run_case malformed-status 3 "malformed status marker" \
    "two markers on one requirement" -- --root "$SELF_TMP/malformed" --check

  variant noac '## Acceptance criteria\n' '## Acceptance notes\n'
  run_case no-acceptance-section 3 "no \`## Acceptance criteria\` section" \
    "Verified by cannot be read, which is not every requirement unverified" -- --root "$SELF_TMP/noac" --check

  if [ "$SELF_CASES" = "$SELF_UPHELD" ]; then self_verdict="held"; else self_verdict="NOT HELD"; fi
  printf '    R39  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$SELF_CASES" "$SELF_UPHELD" "$self_verdict" \
    "each case exits with the code this file's contract declares for it, for the reason it names"
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2 3; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2 3\n' "$REACHED"
  printf '    NOT ASSERTED: the citation rule against check-acceptance-rows.sh itself. The rule is a copy, and no case here runs both files over one row and compares their answers, so the two can drift apart and every case above stays green.\n'
  [ "$SELF_CASES" = "$SELF_UPHELD" ] || exit 1
  if [ -n "$MISSING" ]; then
    printf 'build-requirement-index: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  exit 0
fi

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" || {
    printf 'build-requirement-index: --root was not given and this is not a git work tree, so there is no repository root to default to. Pass --root DIR.\n' >&2
    exit 2
  }
fi
[ -d "$ROOT" ] || { printf 'build-requirement-index: no such directory: %s\n' "$ROOT" >&2; exit 2; }
[ -n "$SPEC" ] || SPEC="$ROOT/.claude/productizer/spec.md"
[ -n "$INDEX" ] || INDEX="$ROOT/.claude/productizer/requirement-index.md"

command -v python3 >/dev/null 2>&1 || {
  printf 'build-requirement-index: python3 is not installed, so the spec was never read. Missing, not clean.\n' >&2
  exit 2
}

if [ ! -f "$SPEC" ] || [ ! -r "$SPEC" ]; then
  printf 'build-requirement-index: cannot read the spec at %s. Unmeasured, not empty - an index built from a spec nobody could open describes nothing.\n' "$SPEC" >&2
  exit 3
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/build-requirement-index.XXXXXX")" || {
  printf 'build-requirement-index: cannot create a temporary directory. Unmeasured, not a pass.\n' >&2
  exit 2; }
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# The parser's stderr is left on the terminal on purpose. --require-records
# turns "read, found nothing" into its 4, which this file reads as its own 3.
prc=0
bash "$PARSER" --require-records "$SPEC" > "$WORK/records.tsv" || prc=$?
if [ "$prc" -ne 0 ]; then
  if [ "$prc" -eq 4 ]; then
    printf 'build-requirement-index: the spec at %s holds no requirement spec-requirements.sh could read. Unmeasured, not an empty index.\n' "$SPEC" >&2
  else
    printf 'build-requirement-index: spec-requirements.sh refused the spec at %s (exit %s), so no requirement was read. Unmeasured, not an empty index.\n' "$SPEC" "$prc" >&2
  fi
  exit 3
fi

python3 - "$SPEC" "$WORK/records.tsv" "$MODE" "$ROOT" "$INDEX" <<'PY'
import os
import re
import sys
import tempfile

BEGIN = "<!-- productizer:requirement-index:begin -->"
END = "<!-- productizer:requirement-index:end -->"
SPEC_PATH, RECORDS, MODE, ROOT, INDEX_PATH = sys.argv[1:6]


# Relative to the work tree, as build-guide.sh does: this output is captured
# into checks-result.json, and an absolute path carries a home directory.
def disp(path):
    try:
        rel = os.path.relpath(os.path.abspath(path), os.path.abspath(ROOT))
    except ValueError:
        return path
    return path if rel.startswith("..") else rel


def die(code, msg):
    sys.stderr.write("build-requirement-index: " + msg + "\n")
    raise SystemExit(code)


try:
    with open(SPEC_PATH, encoding="utf-8") as fh:
        text = fh.read()
except (OSError, UnicodeDecodeError) as exc:
    die(3, "cannot read the spec at %s (%s). Unmeasured, not empty."
        % (disp(SPEC_PATH), exc))

lines = text.split("\n")


def section_bounds(title):
    start = None
    for i, ln in enumerate(lines):
        if re.match(r"^##\s+%s\s*$" % re.escape(title), ln):
            start = i + 1
            break
    if start is None:
        return None
    for j in range(start, len(lines)):
        if re.match(r"^##\s", lines[j]):
            return (start, j)
    return (start, len(lines))


# --- the requirements, through the shared parser ---------------------------
records = []
seen = {}
with open(RECORDS, encoding="utf-8") as fh:
    for raw in fh:
        parts = raw.rstrip("\n").split("\t")
        if len(parts) < 4:
            die(3, "spec-requirements.sh emitted a record this file cannot "
                   "split into id, line, status and target: %r" % raw)
        rid, line, status, target = parts[0], int(parts[1]), parts[2], parts[3]
        if rid in seen:
            die(3, "%s is defined twice in %s, at lines %d and %d. One row per "
                   "requirement is undefined for an id that names two."
                % (rid, disp(SPEC_PATH), seen[rid], line))
        seen[rid] = line
        if status == "malformed":
            die(3, "%s at %s:%d carries a malformed status marker - two "
                   "markers, or one the grammar does not recognise - so its "
                   "status is undefined and the index would have to invent it."
                % (rid, disp(SPEC_PATH), line))
        records.append((rid, line, status, target))

req_bounds = section_bounds("Requirements")
if req_bounds is None:
    die(3, "%s has no `## Requirements` section." % disp(SPEC_PATH))

# --- pattern and area, from the headings the requirement is filed under ----
# format-spec.md section 2. Matched on the heading's leading words, so
# `### Ubiquitous — always active` is ubiquitous.
PATTERNS = [
    ("ubiquitous", re.compile(r"^ubiquitous\b", re.I)),
    ("event", re.compile(r"^event-driven\b", re.I)),
    ("state", re.compile(r"^state-driven\b", re.I)),
    ("unwanted", re.compile(r"^unwanted behaviou?r\b", re.I)),
    ("optional", re.compile(r"^optional\b", re.I)),
    ("complex", re.compile(r"^complex\b", re.I)),
]

pattern_at = {}
area_at = {}
heading = None
area = None
first, last = req_bounds
for i in range(first, last):
    ln = lines[i]
    m3 = re.match(r"^###[ \t]+(.*?)[ \t]*$", ln)
    m4 = re.match(r"^####[ \t]+(.*?)[ \t]*$", ln)
    if m3:
        heading = m3.group(1)
        area = None
    elif m4:
        area = m4.group(1)
    pattern_at[i + 1] = heading
    area_at[i + 1] = area

index_rows = []
for rid, line, status, target in records:
    if line not in pattern_at:
        die(3, "%s is reported at %s:%d, outside `## Requirements`; the parser "
               "and this file disagree about where the section is."
            % (rid, disp(SPEC_PATH), line))
    heading = pattern_at[line]
    pattern = None
    for name, rx in PATTERNS:
        if heading is not None and rx.match(heading):
            pattern = name
            break
    if pattern is None:
        die(3, "%s at %s:%d is filed under %s, which is none of the six pattern "
               "headings in format-spec.md. The heading IS the pattern, so "
               "naming one for it would be a guess."
            % (rid, disp(SPEC_PATH), line,
               "no `### ` heading" if heading is None
               else "`### %s`" % heading))
    if status == "superseded":
        shown = "superseded by %s" % target
    else:
        shown = status
    index_rows.append({"id": rid, "pattern": pattern, "status": shown,
                       "area": area_at[line]})

# --- verified by: check-acceptance-rows.sh's citation rule, copied ---------
RE_ACROW = re.compile(r'^\|\s*`?(R[0-9]+)`?\s*(?<!\\)\|')
RE_SEP = re.compile(r'^[\s:|-]+$')
RE_MD_PIPE = re.compile(r'(?<!\\)\|')
RE_SPAN = re.compile(r'`([^`]+)`')
RE_ID_SHAPE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*$')
RE_IS_CHECK = re.compile(r'^\s*checks?\b', re.I)
RE_LINE_SUFFIX = re.compile(r':[0-9]+$')


def cells(row):
    return [c.strip().replace('\\|', '|') for c in RE_MD_PIPE.split(row)]


def check_citations(evidence):
    found = []
    for span in RE_SPAN.finditer(evidence):
        inner = span.group(1).strip()
        if not inner:
            continue
        token = inner.split()[0]
        token = RE_LINE_SUFFIX.sub('', token).rstrip(',;')
        if not token:
            continue
        if RE_ID_SHAPE.match(token) and RE_IS_CHECK.match(evidence[span.end():]):
            if token not in found:
                found.append(token)
    return found


ac_bounds = section_bounds("Acceptance criteria")
if ac_bounds is None:
    die(3, "%s has no `## Acceptance criteria` section, so no requirement's "
           "`Verified by` can be read. That is unmeasured, not every "
           "requirement unverified." % disp(SPEC_PATH))
rows_by_id = {}
header_width = None
first, last = ac_bounds
for i in range(first, last):
    raw = lines[i]
    if not raw.lstrip().startswith('|'):
        continue
    parts = cells(raw)
    if header_width is None:
        header_width = len(parts)
        continue
    if RE_SEP.match(raw):
        continue
    if len(parts) != header_width:
        die(3, "%s:%d - the acceptance table row has %d cells where its header "
               "declares %d, so its evidence cannot be lined up with a column."
            % (disp(SPEC_PATH), i + 1, len(parts), header_width))
    m = RE_ACROW.match(raw)
    if m:
        rows_by_id.setdefault(m.group(1),
                              check_citations(' '.join(parts[2:]).strip()))
if header_width is None:
    die(3, "%s has an `## Acceptance criteria` section holding no table."
        % disp(SPEC_PATH))

# --- the render --------------------------------------------------------------
with_area = any(r["area"] for r in index_rows)
if with_area:
    head = ["| Id | Area | Pattern | Status | Verified by |",
            "|---|---|---|---|---|"]
else:
    head = ["| Id | Pattern | Status | Verified by |",
            "|---|---|---|---|"]


def verified(rid):
    if rid not in rows_by_id:
        return "—"
    ids = rows_by_id[rid]
    if not ids:
        return "no check cited"
    return ", ".join("`%s`" % c for c in ids)


def cell(s):
    return re.sub(r"(?<!\\)\|", r"\\|", s)


fresh = {}
body = []
for r in sorted(index_rows, key=lambda r: int(r["id"][1:])):
    cols = [r["id"]]
    if with_area:
        cols.append(cell(r["area"]) if r["area"] else "—")
    cols += [r["pattern"], r["status"], verified(r["id"])]
    row = "| " + " | ".join(cols) + " |"
    fresh[r["id"]] = row
    body.append(row)

block = "\n".join(
    [BEGIN,
     "<!-- Generated by plugins/productizer/skills/spec/scripts/build-requirement-index.sh",
     "     from the Requirements and Acceptance criteria sections of the living spec.",
     "     Edit those and regenerate; a hand edit here is reported as drift. -->",
     ""] + head + body + [END])

# --- the index file and its markers -------------------------------------------
SKELETON = ("# Requirement index\n\nGENERATED by build-requirement-index.sh from "
            "the living spec. Do not edit by hand.\n\n%s\n%s\n" % (BEGIN, END))
PASTE = ("  Create %s holding, at least:\n%s  then run again."
         % (disp(INDEX_PATH), "".join("    " + ln + "\n"
                                       for ln in SKELETON.rstrip("\n").split("\n"))))
if os.path.exists(INDEX_PATH) and os.path.samefile(INDEX_PATH, SPEC_PATH):
    die(2, "refusing to write the index into %s: --index names the spec itself. "
           "The index is kept out of the spec because a lookup for one id also "
           "read its index row (retrieval +32%%, measured); writing it back "
           "undoes that." % disp(SPEC_PATH))
if BEGIN in text or END in text:
    die(2, "refusing to run: %s still carries a requirement-index marker "
           "(%d begin, %d end). The index lives in %s now, so a table between "
           "markers in the spec is one nothing writes or checks - a stale copy "
           "that looks generated. Delete the markers and whatever sits between "
           "them from the spec, then run again."
        % (disp(SPEC_PATH), text.count(BEGIN), text.count(END), disp(INDEX_PATH)))
try:
    with open(INDEX_PATH, encoding="utf-8") as fh:
        itext = fh.read()
except (OSError, UnicodeDecodeError) as exc:
    die(2, "refusing to run: cannot read the index file %s (%s). Creating it "
           "where one was expected is guessing at a path somebody may have "
           "meant differently.\n%s" % (disp(INDEX_PATH), exc, PASTE))
n_begin, n_end = itext.count(BEGIN), itext.count(END)
if n_begin != 1 or n_end != 1:
    if n_begin == 0 and n_end == 0:
        why = "it carries no requirement-index markers"
    else:
        why = ("it carries %d begin marker(s) and %d end marker(s), and exactly "
               "one of each is needed to know what to replace" % (n_begin, n_end))
    die(2, "refusing to touch %s: %s. Guessing where the table belongs would "
           "overwrite text somebody wrote.\n%s" % (disp(INDEX_PATH), why, PASTE))
b = itext.index(BEGIN)
e = itext.index(END)
if e < b:
    die(2, "refusing to touch %s: the end marker comes before the begin marker, "
           "so there is no region between them to replace." % disp(INDEX_PATH))

old_block = itext[b:e + len(END)]
new_text = itext[:b] + block + itext[e + len(END):]

n_active = sum(1 for r in index_rows if r["status"] == "active")
n_sup = sum(1 for r in index_rows if r["status"].startswith("superseded"))
n_wd = sum(1 for r in index_rows if r["status"] == "withdrawn")
n_norow = sum(1 for r in index_rows if r["id"] not in rows_by_id)
n_nocheck = sum(1 for r in index_rows
                if r["id"] in rows_by_id and not rows_by_id[r["id"]])
print("%s -> %s" % (disp(SPEC_PATH), disp(INDEX_PATH)))
print("%d requirement(s) indexed: %d active, %d superseded, %d withdrawn"
      % (len(index_rows), n_active, n_sup, n_wd))
print("    verified by: %d cite at least one check, %d have an acceptance row "
      "citing no check, %d have no acceptance row"
      % (len(index_rows) - n_norow - n_nocheck, n_nocheck, n_norow))
print("    area column: %s" % ("rendered, from `#### ` sub-headings" if with_area
                               else "omitted - no requirement sits under a "
                                    "`#### ` area sub-heading"))
print("    NOT ASSERTED: that a cited check is declared, enabled or claims the "
      "requirement (check-acceptance-rows.sh asserts that), nor that any "
      "requirement's pattern heading agrees with its sentence "
      "(validate-spec.py reads that).")

if old_block == block:
    if MODE == "check":
        print("    the requirement index is up to date with the spec.")
    else:
        print("    the requirement index is already up to date; nothing written.")
    raise SystemExit(0)

if MODE == "check":
    committed = {}
    committed_head = []
    for ln in old_block.split("\n"):
        m = re.match(r"^\|\s*(R[0-9]+)\s*\|", ln)
        if m:
            committed.setdefault(m.group(1), ln)
        elif ln.startswith("|"):
            committed_head.append(ln)

    def by_id(ids):
        return sorted(ids, key=lambda s: int(s[1:]))

    print("    %s is OUT OF DATE with the requirements of %s."
          % (disp(INDEX_PATH), disp(SPEC_PATH)))
    reasons = 0
    if committed_head != head:
        reasons += 1
        print("    the table header differs: committed %s, generated %s"
              % (" / ".join(committed_head) or "(none)", " / ".join(head)))
    for rid in by_id([i for i in fresh if i not in committed]):
        reasons += 1
        print("    %s is in the spec and has no index row" % rid)
    for rid in by_id([i for i in committed if i not in fresh]):
        reasons += 1
        print("    %s has an index row and no requirement in the spec" % rid)
    for rid in by_id([i for i in fresh if i in committed and committed[i] != fresh[i]]):
        reasons += 1
        print("    %s row differs:\n      committed: %s\n      generated: %s"
              % (rid, committed[rid], fresh[rid]))
    if not reasons:
        print("    every row matches by id; the order, a duplicated row, or the "
              "text between the markers differs.")
    print("    Regenerate with: build-requirement-index.sh --root <repo>")
    raise SystemExit(1)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(INDEX_PATH)),
                           prefix=".build-requirement-index.")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(new_text)
    os.chmod(tmp, os.stat(INDEX_PATH).st_mode & 0o7777)
    os.replace(tmp, INDEX_PATH)
except Exception:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise
print("    wrote the requirement index into %s" % disp(INDEX_PATH))
raise SystemExit(0)
PY
