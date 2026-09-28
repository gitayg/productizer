#!/usr/bin/env bash
# check-suspect-links.sh [--version] [--help] [--root DIR] [--base REF]
#                        [--selftest]
#
# Flags SUSPECT LINKS: a requirement whose SENTENCE changed in place - its id
# and its status both unchanged - and every artifact still citing that id that
# was NOT touched in the same change.
#
# THE HOLE THIS FILLS
#
# Permanent ids are the reason citations survive, and they are also the reason
# a citation can go quietly wrong. `R5` means whatever R5 says today. Rewrite
# R5's sentence and every acceptance-criteria row, every check's coverage
# claim, every downstream requirement naming R5 keeps pointing at it, keeps
# resolving, and now describes something nobody re-read. Nothing in this
# repository invalidates anything: `Productizer-Req:` trailers record which
# requirement a commit served, which is provenance, not invalidation.
#
# The incumbents each void the link and each pay for it differently. DOORS
# marks every linked object suspect on change and makes a person clear the
# flag. OpenFastTrace puts a revision inside the id, so bumping it breaks the
# existing links by construction - which works, and costs the permanence that
# `references/ears.md` requires here. This check takes DOORS' half: the id
# stays permanent, and the change raises a flag against everything downstream.
#
# THREE THINGS THAT LOOK ALIKE, KEPT APART
#
#   ID CHANGED, OR STATUS CHANGED - a supersede, a withdrawal, a split. NOT
#   this check's business. `check-superseded-text.sh` owns it, and the two
#   must not be collapsed: a supersede leaves a forward pointer a reader can
#   follow, so the citation still leads somewhere honest. A rewrite in place
#   leaves nothing at all.
#
#   SENTENCE CHANGED IN PLACE - SUSPECT. The id resolves, the status is the
#   same, and the words moved. Every dependant may now be asserting, verifying
#   or citing something the spec no longer says.
#
#   A TYPO OR A RE-WRAP - INDISTINGUISHABLE FROM THE ABOVE, BY MACHINE. This
#   is the honest limit and it is printed on every run, clean or not. Re-wraps
#   and whitespace are normalised away by `spec-requirements.sh` and never
#   reach here; a single changed word does. `shall` to `should`, `all` to
#   `most`, `shall` to `shall not` and `recieve` to `receive` are the same
#   event to every measurement this script can take. It reports the shape of
#   the edit - words added, words removed, punctuation-only - and refuses to
#   pretend that shape is a verdict on meaning.
#
# WHAT COUNTS AS A DEPENDANT
#
# Every tracked file that cites the id, minus the requirement's own definition
# line. The acceptance-criteria row is the one that matters most and is
# labelled as such, but it is not privileged: a coverage claim in checks.yaml,
# a downstream requirement's sentence, a change-log row and a reference doc
# are all citations that go stale the same way.
#
# ONE REGION IS NOT A CITATION: the generated requirement index between its
# begin and end markers, in its own file beside the spec
# (.claude/productizer/requirement-index.md - moved out of the spec because
# inline it made every requirement lookup read its index row too). Its rows
# hold no sentence and cannot be cleared by hand, so counting them made every
# in-place rewrite of an indexed requirement one guaranteed, unclearable
# finding. Honoured only when that file's markers are well formed; a malformed
# index is scanned like any other line, and markers in any other file,
# the spec included, skip nothing.
#
# TWO TREES ARE EXCLUDED, AND THE REASON IS MEASURED, NOT ASSUMED. Any path
# with a `fixtures/` or `evals/` component holds its OWN example specs, with
# their own R-numbering. An `R3` in a fixture spec is a different requirement
# wearing the same name, and reporting it is not a false positive at the
# margin - it is most of the output. Measured on this repository: 81 tracked
# files match `R3`, of which 19 are outside those two trees. A check whose
# findings are three quarters noise is one people stop reading.
#
# A CITATION WHOSE OWN LINE CHANGED IN THIS CHANGE IS REPORTED AND IS NOT A
# FINDING. Somebody had both texts open. That is the whole of what clearing a
# suspect flag means, and demanding a second signal for it would make the flag
# unclearable. The line still prints, because "it was looked at" is a claim
# worth being able to check.
#
# CLEARING IS PER LINE, NEVER PER FILE, AND THAT IS NOT A DETAIL. The first
# version of this check asked whether the FILE had been edited, and on the
# fixture it reported the acceptance-criteria row - the primary dependant, and
# the reason this check exists - as reviewed. It had not been reviewed. It sits
# in the spec, and the spec is by definition the file the requirement was
# rewritten in, so every dependant inside the spec cleared itself the moment
# the requirement moved. A per-file rule is structurally blind to exactly the
# dependants that matter most. Caught by running the fixture, not by reading.
#
# WHY `advise` IN checks.yaml, AND NOT `block`
#
# A suspect flag is a prompt to re-read, not a proof of error - and this one
# cannot tell a typo from an inversion. A gate that holds the merge on that
# distinction is a gate people learn to route around, and a routed-around gate
# measures nothing at all. Exit 2 still blocks whatever the severity says,
# which is the right asymmetry: not knowing is worse than a flag.
#
# AN EMPTY SET IS NOT A PASS. There are four ways to compare nothing and they
# are all exit 2, never 0:
#
#   the base ref does not resolve      a shallow clone, or a wrong ref
#   the spec did not exist at the base  no earlier sentence to compare against
#   either spec version holds no requirements
#   the dependant scope resolved to no files at all
#
# A spec that is byte-identical to the base is NOT one of them. That is a
# comparison that ran and found nothing moved, and it exits 0.
#
# THE TEXT IS NEVER QUOTED. Findings name the id, the file and the line. This
# output is written into a committed result file, and a check that quotes the
# requirement it is guarding republishes it on every run - the same defect
# `check-hygiene.sh` fixed by reporting location instead of content.
#
# ONE BARE PATH PER LINE for each file the verdict rests on: the spec now, the
# spec at the base as `<path>@<short sha>`, and every file found citing a
# suspect id. The runner reads those as coverage and treats a clean exit that
# examined less than it declared as hollow.
#
# KNOWN LIMITATIONS, written down rather than discovered later:
#   - IT CANNOT TELL A SEMANTIC REWRITE FROM A TYPO FIX. Stated above, stated
#     again in the output of every run. This is the whole residual risk.
#   - An id in a TEMPLATE or an example is indistinguishable from a citation.
#     `templates/spec.md` carries an `R3` that cites nothing.
#   - It compares against ONE base ref. An edit merged before that ref is, to
#     this check, the agreed text - the diff-only blindness that
#     `check-superseded-text.sh` exists to cover from the other side.
#   - A dependant that cites the requirement WITHOUT naming its id - by
#     quoting the sentence, say - is invisible. Nothing here resolves prose.
#   - It reads one spec path. A requirement moved between files in a split
#     spec reads as gone.
#   - Clearing is line-level, so a dependant re-read and found still correct
#     stays flagged until its line is touched. There is no acknowledgement
#     file here: DOORS clears a suspect flag by a person's act, and nothing in
#     this repository records such an act yet.
#   - A citation is a LINE, not a record. A coverage claim in checks.yaml is
#     an `- id: R2` line and an `evidence:` paragraph beside it; rewriting the
#     evidence does not move the id line, so the claim stays flagged. The
#     finding says the file was edited, which is the triage signal; nothing
#     here parses YAML or Markdown into records.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  compared, and no suspect dependant
#   1  findings - a sentence moved under a live citation nobody touched
#   2  could not run, or could not measure. Never 0.
#
# Under --selftest (--self-test is accepted too) the same three mean: every
# case produced the exit code it declares and said what it was supposed to say
# (0), at least one did not (1), and the corpus could not be driven at all (2).
set -euo pipefail

VERSION="check-suspect-links 1.0"
ROOT=""
BASE="HEAD"
BASE_SOURCE="the default: the change in the work tree, against the last commit"
MODE="measure"

usage() {
  printf 'usage: check-suspect-links.sh [--version] [--help] [--root DIR] [--base REF]\n'
  printf '  --root DIR  the repo work tree to examine. Defaults to the git\n'
  printf '              top level, never to the working directory.\n'
  printf '  --base REF  the ref the change is measured against. Defaults to\n'
  printf '              HEAD, which compares the work tree to the last commit.\n'
  printf '  --selftest  drive the built-in corpus instead of a repository.\n'
}

die_unmeasured() { printf 'check-suspect-links: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)
      [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --base)
      [ "$#" -ge 2 ] || die_unmeasured "--base needs a ref"
      BASE="$2"; BASE_SOURCE="given with --base"; shift 2 ;;
    --base=*) BASE="${1#--base=}"; BASE_SOURCE="given with --base"; shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    -*) printf 'check-suspect-links: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'check-suspect-links: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# --selftest. R39: one case per exit code this tool can return, each built as
# a real git history in a sandbox, so nothing here reads or writes the
# repository under test.
#
# THE HISTORIES ARE BUILT, NOT COMMITTED AS FIXTURES. This check compares the
# work tree against a base commit, and a case directory under `fixtures/`
# cannot carry a git history of its own inside this repository.
#
# THE THREE THINGS THAT LOOK ALIKE EACH GET A CASE, and that is the point of
# the corpus rather than a flourish. `suspect` must be a finding; `supersede`
# must NOT be, because a status change leaves a forward pointer a reader can
# follow; and `cleared` must not be either, because a citation whose own line
# moved in the same change is a citation somebody had open. Collapsing any two
# of those three is the failure mode this check was written around, and an
# exit-code-only corpus would not see it - so every case asserts a sentence.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  [ -f "$SELF" ] ||
    die_unmeasured "cannot re-invoke this script for the self-test, so no case was driven"
  command -v git >/dev/null ||
    die_unmeasured "git is not on PATH, so no history could be built and no case was driven"

  # `pwd -P` because the temporary directory is reached through a symlink on
  # macOS and this check compares --root against a resolved `git rev-parse
  # --show-toplevel`. An unresolved sandbox refuses every case for a reason
  # about the sandbox rather than about the case.
  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-suspect-links-selftest.XXXXXX")" ||
    die_unmeasured "could not create a sandbox, so no case was driven"
  SB="$(cd "$SB" && pwd -P)"
  trap 'rm -rf "$SB"' EXIT HUP INT TERM

  new_repo() {
    mkdir -p "$1/.claude/productizer"
    git -c init.defaultBranch=main init -q "$1"
    git -C "$1" config user.email "fixture@example.invalid"
    git -C "$1" config user.name "check-suspect-links selftest"
  }
  commit_all() {
    git -C "$1" add -A
    git -C "$1" -c commit.gpgsign=false commit -q -m "$2"
  }

  # The agreed spec, and one dependant outside it so a citation exists that
  # the spec's own edit cannot clear by accident.
  agreed_spec() {
    cat > "$1/.claude/productizer/spec.md" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.

## Acceptance criteria

| requirement | asserted by |
| --- | --- |
| R1 | spec-home |
| R2 | spec-integrity |
SPEC
  }
  agreed_dependant() {
    printf 'notes\n\nThe home check is what asserts R1 today.\n' > "$1/notes.md"
  }

  base_repo() {
    new_repo "$SB/$1"
    agreed_spec "$SB/$1"
    agreed_dependant "$SB/$1"
    commit_all "$SB/$1" "the agreed spec and one dependant citing R1"
  }

  # The same spec with R1's SENTENCE rewritten in place - same id, same
  # status, different words.
  rewritten_spec() {
    cat > "$1/.claude/productizer/spec.md" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle should usually prefer at most one living spec.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.

## Acceptance criteria

| requirement | asserted by |
| --- | --- |
| R1 | spec-home |
| R2 | spec-integrity |
SPEC
  }

  # The agreed spec with its generated requirement index in its OWN file
  # beside it, laid out as build-requirement-index.sh lays it out. $2 is R1's
  # sentence; $3 and $4 are the index's opening and closing marker lines, so a
  # case can duplicate or drop one. The index row for R1 is a citation-shaped
  # line that holds no sentence. The spec's own index section is a pointer and
  # carries no id and no marker.
  indexed_spec() {
    {
      printf '# Requirement index\n\nGenerated. Do not edit by hand.\n\n'
      printf '%b' "$3"
      printf '| Id | Pattern | Status | Verified by |\n|---|---|---|---|\n'
      printf '| R1 | ubiquitous | active | `spec-home` |\n'
      printf '| R2 | ubiquitous | active | `spec-integrity` |\n'
      printf '%b' "$4"
    } > "$1/.claude/productizer/requirement-index.md"
    {
      printf '# Living spec — sandbox\n\n## Requirement index\n\nGenerated into requirement-index.md.\n'
      printf '\n## Requirements\n\n- **R1** — %s\n' "$2"
      printf -- '- **R2** — The lifecycle shall keep requirement ids permanent, never reused.\n'
      printf '\n## Acceptance criteria\n\n| requirement | asserted by |\n| --- | --- |\n'
      printf '| R1 | spec-home |\n| R2 | spec-integrity |\n'
    } > "$1/.claude/productizer/spec.md"
  }
  IDX_B='<!-- productizer:requirement-index:begin -->\n'
  IDX_E='<!-- productizer:requirement-index:end -->\n'
  R1_AGREED='The lifecycle shall hold exactly one living spec per product.'
  R1_REWRITTEN='The lifecycle should usually prefer at most one living spec.'
  # $1 case, $2 opening, $3 closing: an agreed indexed spec and the dependant
  # committed, then R1 rewritten in place under the same index.
  indexed_case() {
    new_repo "$SB/$1"
    indexed_spec "$SB/$1" "$R1_AGREED" "$2" "$3"
    agreed_dependant "$SB/$1"
    commit_all "$SB/$1" "an indexed spec and one dependant citing R1"
    indexed_spec "$SB/$1" "$R1_REWRITTEN" "$2" "$3"
  }

  FAILED=0
  DRIVEN=0
  # R39.b: the reached half of the declaration below is ACCUMULATED here, one
  # entry per case as it ran. A literal list would satisfy the reader and prove
  # nothing.
  CODES=""

  drive() {
    # $1 case name, $2 expected exit, $3 expected sentence, $4.. argv override
    local case_name="$1" want="$2" marker="$3"
    shift 3
    local rc=0
    if [ "$#" -eq 0 ]; then set -- --root "$SB/$case_name"; fi
    bash "$SELF" "$@" > "$SB/$case_name.out" 2> "$SB/$case_name.err" || rc=$?
    DRIVEN=$((DRIVEN + 1))
    CODES="$CODES$rc
"
    local why=""
    [ "$rc" -eq "$want" ] || why="exit $rc, expected $want"
    # Both files handed to grep directly, never piped into it: under
    # `set -o pipefail` a `cat a b | grep -q` reports 141 whenever grep matches
    # early enough to SIGPIPE the cat, and `if !` reads that as no match.
    if ! grep -q -- "$marker" "$SB/$case_name.out" "$SB/$case_name.err"; then
      [ -n "$why" ] && why="$why; "
      why="${why}its output does not say what it was supposed to say"
    fi
    if [ -z "$why" ]; then
      printf '  held: case %-22s exit %d, and said so - %s\n' "$case_name" "$rc" "$marker"
      return 0
    fi
    printf '  FINDING: case %-22s %s - expected: %s\n' "$case_name" "$why" "$marker"
    FAILED=$((FAILED + 1))
    return 0
  }

  # clean: nothing moved since the base at all.
  base_repo clean

  # suspect: R1's sentence rewritten, every citation left where it was.
  base_repo suspect
  rewritten_spec "$SB/suspect"

  # cleared: the same rewrite, with every line citing R1 rewritten alongside
  # it. Per LINE, never per file - the acceptance row lives in the spec, and a
  # per-file rule would clear it the moment the requirement above it moved.
  base_repo cleared
  cat > "$SB/cleared/.claude/productizer/spec.md" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle should usually prefer at most one living spec.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.

## Acceptance criteria

| requirement | asserted by |
| --- | --- |
| R1 | spec-home, re-read against the new wording |
| R2 | spec-integrity |
SPEC
  printf 'notes\n\nThe home check is what asserts R1 today, re-read against the new wording.\n' \
    > "$SB/cleared/notes.md"

  # supersede: the id resolves and the STATUS moved. A supersede leaves a
  # forward pointer a reader can follow, so it is not suspect here.
  base_repo supersede
  cat > "$SB/supersede/.claude/productizer/spec.md" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
  Superseded by R3. Narrowed.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall hold exactly one living spec in the declared home.

## Acceptance criteria

| requirement | asserted by |
| --- | --- |
| R1 | spec-home |
| R2 | spec-integrity |
SPEC

  # index-skipped: R1 rewritten under a well-formed generated index. The index
  # row must NOT be a dependant; the acceptance row and notes.md still must.
  # Counted without the skip it is 3 cited, 3 left suspect.
  indexed_case index-skipped "$IDX_B" "$IDX_E"

  # index-two-begins / index-no-end: the same rewrite under a MALFORMED index.
  # The row is reported, so a broken index never silences the check.
  indexed_case index-two-begins "$IDX_B$IDX_B" "$IDX_E"
  indexed_case index-no-end "$IDX_B" ''

  # index-markers-in-spec: the OLD layout - a well-formed marker pair and its
  # rows left inside the spec, and no index file. The skip belongs to the
  # index file only, so the spec's row is reported: a table left behind in the
  # spec is one nothing regenerates, and silencing it would hide that.
  new_repo "$SB/index-markers-in-spec"
  inline_indexed_spec() {
    {
      printf '# Living spec — sandbox\n\n## Requirement index\n\n%b' "$IDX_B"
      printf '| R1 | ubiquitous | active | `spec-home` |\n%b' "$IDX_E"
      printf '\n## Requirements\n\n- **R1** — %s\n' "$2"
      printf -- '- **R2** — The lifecycle shall keep requirement ids permanent, never reused.\n'
      printf '\n## Acceptance criteria\n\n| requirement | asserted by |\n| --- | --- |\n'
      printf '| R1 | spec-home |\n| R2 | spec-integrity |\n'
    } > "$1/.claude/productizer/spec.md"
  }
  inline_indexed_spec "$SB/index-markers-in-spec" "$R1_AGREED"
  agreed_dependant "$SB/index-markers-in-spec"
  commit_all "$SB/index-markers-in-spec" "an inline index left in the spec"
  inline_indexed_spec "$SB/index-markers-in-spec" "$R1_REWRITTEN"

  # base-unresolvable: a ref that names no commit.
  base_repo base-unresolvable

  # shallow: the base was never fetched, which is a different sentence from a
  # wrong ref and must not be reported as one.
  git clone -q --depth 1 "file://$SB/clean" "$SB/shallow" ||
    die_unmeasured "could not build a shallow clone, so the case that separates a shallow clone from a wrong ref was never driven"

  # spec-new-at-base: the spec did not exist at the base at all.
  new_repo "$SB/spec-new-at-base"
  agreed_dependant "$SB/spec-new-at-base"
  commit_all "$SB/spec-new-at-base" "a repository with a dependant and no spec yet"
  agreed_spec "$SB/spec-new-at-base"

  # no-requirements-now
  new_repo "$SB/no-requirements-now"
  agreed_spec "$SB/no-requirements-now"
  commit_all "$SB/no-requirements-now" "the agreed spec"
  printf '# Living spec — sandbox\n\n## Design\n\nProse, and no requirement definitions.\n' \
    > "$SB/no-requirements-now/.claude/productizer/spec.md"

  # no-requirements-at-base: today's spec parses, the base's does not, so
  # there is no earlier sentence for anything to have moved from.
  new_repo "$SB/no-requirements-at-base"
  printf '# Living spec — sandbox\n\n## Design\n\nProse, and no requirement definitions.\n' \
    > "$SB/no-requirements-at-base/.claude/productizer/spec.md"
  commit_all "$SB/no-requirements-at-base" "a spec with nothing in it yet"
  agreed_spec "$SB/no-requirements-at-base"

  # no-spec: a work tree with no spec at the declared path.
  new_repo "$SB/no-spec"
  printf 'no spec here\n' > "$SB/no-spec/README"
  commit_all "$SB/no-spec" "founding"
  rmdir "$SB/no-spec/.claude/productizer" "$SB/no-spec/.claude"

  # not-a-work-tree: the spec is readable and git knows nothing about it.
  mkdir -p "$SB/not-a-work-tree/.claude/productizer"
  agreed_spec "$SB/not-a-work-tree"

  printf 'not a directory\n' > "$SB/a-file"

  # THE CLEAN CASE GUARDS THE OTHERS' PREMISE. If a tree that moved nothing
  # does not exit 0 and say so, every red case below would be red for that
  # reason instead of its own and nothing would have been measured.
  CLEAN_RC=0
  bash "$SELF" --root "$SB/clean" > "$SB/clean.out" 2> "$SB/clean.err" || CLEAN_RC=$?
  if [ "$CLEAN_RC" -ne 0 ] || ! grep -q 'sentence changed in place: 0' "$SB/clean.out"; then
    printf '  the clean case exited %d and did not report nothing changed in place.\n' "$CLEAN_RC"
    die_unmeasured "the corpus premise did not hold; unmeasured, not a pass"
  fi
  printf '  held: case %-22s exit 0, and said so - %s\n' "clean" "sentence changed in place: 0"
  CODES="$CODES$CLEAN_RC
"

  drive cleared              0 'dependants: 2 cited, 2 re-read (their line moved too), 0 left suspect'
  drive supersede            0 'status changed: 1'

  drive suspect              1 'dependants: 2 cited, 0 re-read (their line moved too), 2 left suspect'
  drive index-skipped        1 'dependants: 2 cited, 0 re-read (their line moved too), 2 left suspect'
  drive index-two-begins     1 'SUSPECT .claude/productizer/requirement-index.md:[0-9]*  requirement-index row'
  drive index-no-end         1 'SUSPECT .claude/productizer/requirement-index.md:[0-9]*  requirement-index row'
  drive index-markers-in-spec 1 'SUSPECT .claude/productizer/spec.md:[0-9]*  requirement-index row'

  drive base-unresolvable    2 'does not resolve to a commit' --root "$SB/base-unresolvable" --base no-such-ref
  drive shallow              2 'the clone is SHALLOW'         --root "$SB/shallow" --base HEAD~1
  drive spec-new-at-base     2 'does not exist at'
  drive no-requirements-now  2 'holds no requirement definitions'
  drive no-requirements-at-base 2 'There is no earlier sentence to compare against'
  drive no-spec              2 'cannot read .claude/productizer/spec.md'
  drive not-a-work-tree      2 'is not inside a git work tree'
  drive root-not-a-dir       2 'is not a directory'           --root "$SB/a-file"

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
  printf '  R39 for this tool: the self-test exists, reaches 0, 1 and 2, and every case asserts which verdict it produced as well as which code.\n'
  printf '  NOT ASSERTED, two of them. The ONE-BASE-REF blindness in the header is not a case and cannot be: an edit merged before the base IS the agreed text to this check, by construction, and a corpus cannot demonstrate a hole by exercising it. And the empty-dependant-scope refusal is unreachable from any corpus this tool can be pointed at - the spec itself is a tracked file outside the fixtures and evals trees, so the scope is never empty in a tree that got that far.\n'
  exit 0
fi

# Defaulting to the working directory is how a sibling check here once read a
# directory that was not the repository and reported a confident clean result.
# git names the work tree or nothing does.
if [ -z "$ROOT" ]; then
  if ! ROOT="$(git rev-parse --show-toplevel)"; then
    die_unmeasured "no git work tree here, and --root was not given. Refusing rather than reading the working directory, which is not the repo often enough to matter."
  fi
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"

SELFDIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="$SELFDIR/spec-requirements.sh"
[ -x "$PARSER" ] ||
  die_unmeasured "spec-requirements.sh is not beside this script and executable. Both spec versions are read through the one parser on purpose: two parsers that disagree about what R14 says report an edit and no edit from the same file."

SPECREL=".claude/productizer/spec.md"
SPEC="$ROOT/$SPECREL"
[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unmeasured "cannot read $SPECREL under $ROOT. Without the spec there is no requirement whose sentence could have moved."

TOP="$(git -C "$ROOT" rev-parse --show-toplevel)" ||
  die_unmeasured "--root $ROOT is not inside a git work tree. What a requirement USED to say is only answerable from git."
case "$ROOT/" in
  "$TOP"/*) ;;
  *) die_unmeasured "--root $ROOT resolves outside its own git top level $TOP" ;;
esac
SPECGIT="${SPEC#"$TOP"/}"
IDXREL=".claude/productizer/requirement-index.md"
IDX="$ROOT/$IDXREL"
IDXGIT="${IDX#"$TOP"/}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-suspect-links.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

found=0
finding() { printf '      SUSPECT %s\n' "$1"; found=1; }

# --- the base ---------------------------------------------------------------
SHALLOW="$(git -C "$TOP" rev-parse --is-shallow-repository)"
BASE_SHA="$(git -C "$TOP" rev-parse --verify --quiet "$BASE^{commit}")" || BASE_SHA=""
if [ -z "$BASE_SHA" ]; then
  if [ "$SHALLOW" = "true" ]; then
    die_unmeasured "the base ref $BASE does not resolve in this clone, and the clone is SHALLOW. The commit the change is measured against was never fetched, so whether any sentence moved is UNKNOWN. Fetch full history (fetch-depth: 0) and re-run. This is not a clean result."
  fi
  die_unmeasured "the base ref $BASE does not resolve to a commit. A wrong base makes every verdict below confidently wrong at once, so nothing below was computed."
fi
BASE_SHORT="$(git -C "$TOP" rev-parse --short "$BASE_SHA")"

if [ -z "$(git -C "$TOP" ls-tree "$BASE_SHA" -- "$SPECGIT")" ]; then
  die_unmeasured "$SPECREL does not exist at $BASE_SHORT. Every requirement in it is new as of this change and none of them has an earlier sentence to have moved from. That is nothing measured, not nothing wrong."
fi
git -C "$TOP" show "$BASE_SHA:$SPECGIT" > "$WORK/base.md" ||
  die_unmeasured "cannot read $SPECREL at $BASE_SHORT, which git lists as holding it"

# --- both versions, through the one parser ----------------------------------
printf '%s\n' "$SPECREL"                        # coverage: one path per file
printf '%s@%s\n' "$SPECREL" "$BASE_SHORT"       # coverage: one path per file

"$PARSER" "$SPEC" > "$WORK/cur.tsv" || die_unmeasured "the parser refused $SPECREL as it stands now"
"$PARSER" "$WORK/base.md" > "$WORK/base.tsv" || die_unmeasured "the parser refused $SPECREL at $BASE_SHORT"

[ -s "$WORK/cur.tsv" ] ||
  die_unmeasured "$SPECREL holds no requirement definitions. Nothing was compared; that is not a pass."
[ -s "$WORK/base.tsv" ] ||
  die_unmeasured "$SPECREL at $BASE_SHORT holds no requirement definitions. There is no earlier sentence to compare against, so this run has no verdict."

printf 'base: %s -> %s (%s)\n' "$BASE" "$BASE_SHORT" "$BASE_SOURCE"

# --- what moved -------------------------------------------------------------
#
# Four outcomes per id, and the point of the check is that they are FOUR and
# not two. Collapsing `status` into `suspect` would report every ordinary
# supersede as a stale citation, which is both wrong and loud enough to get
# the check switched off.
awk -F'\t' 'BEGIN { OFS = "\t" }
  NR == FNR { bstat[$1] = $3; btext[$1] = $5; bseen[$1] = 1; next }
  {
    if (!($1 in bseen))        { print "new",     $1, $2, $3; next }
    if ($3 != bstat[$1])       { print "status",  $1, $2, $3 " was " bstat[$1]; next }
    if ($5 != btext[$1])       { print "suspect", $1, $2, $3; next }
                                 print "same",    $1, $2, $3
  }' "$WORK/base.tsv" "$WORK/cur.tsv" > "$WORK/class.tsv"

awk -F'\t' '
  NR == FNR { cur[$1] = 1; next }
  !($1 in cur) && !seen[$1]++ { print $1 }
' "$WORK/cur.tsv" "$WORK/base.tsv" > "$WORK/gone.txt"

count_of() { awk -F'\t' -v k="$1" '$1 == k { n++ } END { print n + 0 }' "$WORK/class.tsv"; }
n_new="$(count_of new)"
n_status="$(count_of status)"
n_suspect="$(count_of suspect)"
n_same="$(count_of same)"
n_gone="$(wc -l < "$WORK/gone.txt" | tr -d ' ')"

printf 'requirements in the spec now: %s\n' "$(wc -l < "$WORK/cur.tsv" | tr -d ' ')"
printf 'requirements at the base: %s\n' "$(wc -l < "$WORK/base.tsv" | tr -d ' ')"
printf 'unchanged: %s\n' "$n_same"
printf 'added since the base: %s\n' "$n_new"
printf 'gone since the base: %s (deletion and retention are check-superseded-text.sh, not this)\n' "$n_gone"
printf 'status changed: %s (a supersede or a withdrawal leaves a pointer to follow, so it is not suspect here)\n' "$n_status"
printf 'sentence changed in place: %s\n' "$n_suspect"

# --- the files a citation could be in ---------------------------------------
#
# `fixtures/` and `evals/` are excluded because they hold their own example
# specs with their own numbering; see the header for the measurement.
git -C "$TOP" ls-files > "$WORK/tracked.txt" ||
  die_unmeasured "git ls-files failed under $TOP; the set of files a citation could live in is unknown"
grep -Ev '(^|/)(fixtures|evals)/' "$WORK/tracked.txt" > "$WORK/scope.txt" || : > "$WORK/scope.txt"
[ -s "$WORK/scope.txt" ] ||
  die_unmeasured "the dependant scope resolved to no tracked files at all. A scan that opened nothing found nothing, and the two are not the same."

# Binary files are NAMED, never silently skipped. `grep -I` was tried first and
# is the wrong tool here for the reason check-hygiene.sh records: it drops the
# file and still lets the run read as complete.
: > "$WORK/text.txt"
: > "$WORK/binary.txt"
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  f="$TOP/$rel"
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then
    printf '%s\n' "$rel" >> "$WORK/binary.txt"
    continue
  fi
  raw="$(head -c 4096 "$f" | wc -c | tr -d ' ')"
  stripped="$(head -c 4096 "$f" | tr -d '\000' | wc -c | tr -d ' ')"
  if [ "$raw" = "$stripped" ]; then
    printf '%s\n' "$rel" >> "$WORK/text.txt"
  else
    printf '%s\n' "$rel" >> "$WORK/binary.txt"
  fi
done < "$WORK/scope.txt"

n_scope="$(wc -l < "$WORK/text.txt" | tr -d ' ')"
n_binary="$(wc -l < "$WORK/binary.txt" | tr -d ' ')"
printf 'tracked files scanned for citations: %s (fixtures and evals trees excluded)\n' "$n_scope"
if [ "$n_binary" -gt 0 ]; then
  printf 'not scanned because they are not readable text: %s, each named below\n' "$n_binary"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf '    not scanned, not text or not readable: %s\n' "$rel"
  done < "$WORK/binary.txt"
fi

# --- what this change already touched ---------------------------------------
git -C "$TOP" diff --name-only "$BASE_SHA" -- > "$WORK/touched.txt" ||
  die_unmeasured "cannot diff the work tree against $BASE_SHORT, so whether a dependant was edited alongside is unknown"
printf 'files this change touches: %s\n' "$(wc -l < "$WORK/touched.txt" | tr -d ' ')"

# The NEW-SIDE line numbers this change rewrote in one file, cached per file.
# Per LINE and not per file: see the header. `@@ -a,b +c,d @@` with `d` absent
# means one line; with `d` zero means a pure deletion, which adds no new line
# and so clears nothing.
changed_lines_of() {
  key="$(printf '%s' "$1" | tr -c '[:alnum:]' '_')"
  out="$WORK/lines.$key"
  if [ ! -f "$out" ]; then
    git -C "$TOP" diff -U0 "$BASE_SHA" -- "$1" > "$WORK/hunks.txt" ||
      die_unmeasured "cannot diff $1 against $BASE_SHORT, so whether its citation was re-read is unknown"
    awk '/^@@ / {
           n = $3; sub(/^\+/, "", n); split(n, p, ",")
           start = p[1] + 0; cnt = (2 in p) ? p[2] + 0 : 1
           for (i = 0; i < cnt; i++) print start + i
         }' "$WORK/hunks.txt" > "$out"
  fi
  printf '%s' "$out"
}

# --- the section a spec line sits in, for labelling -------------------------
awk 'BEGIN { sec = "(before the first heading)" }
  /^## / { sec = substr($0, 4); next }
  { print FNR "\t" sec }' "$SPEC" > "$WORK/sections.tsv"

label_for() {  # <file> <line>
  case "$1" in
    "$SPECREL")
      case "$(awk -F'\t' -v n="$2" '$1 == n { print $2; exit }' "$WORK/sections.tsv")" in
        "Acceptance criteria")  printf 'acceptance-criteria row' ;;
        "Requirement index")    printf 'requirement-index row' ;;
        "Requirements")         printf "another requirement's sentence or its forward pointer" ;;
        "Change log")           printf 'change-log row' ;;
        "Decision record")      printf 'decision-record row' ;;
        "Areas of concern")     printf 'concern row' ;;
        "Design")               printf 'design note' ;;
        *)                      printf 'spec prose' ;;
      esac ;;
    "$IDXREL") printf 'requirement-index row' ;;
    *checks.yaml) printf 'check declaration' ;;
    */classifications/*) printf 'classification record - provenance, so a flag here says the decision was made against different words, not that the file should be edited' ;;
    *) printf 'cites it' ;;
  esac
}

# --- the generated requirement index -----------------------------------------
#
# The rows between these two markers are written by build-requirement-index.sh
# and carry an id, a pattern, a status and check ids - never the sentence. A
# row there cites every indexed id, and no person can clear it by re-reading:
# it is regenerated, and a hand edit is reported as drift. Measured before this
# skip existed, rewriting R2's sentence in place on a clone of this repository
# gave, on every such rewrite, one guaranteed and unclearable finding:
#   SUSPECT .claude/productizer/spec.md:96  requirement-index row ... The file
#   WAS edited in this change and this line was not, so read this one first.
# The index has since moved out of the spec into $IDXREL, so the skip reads
# the markers there and applies to that file ONLY. Markers anywhere else -
# the spec included - skip nothing.
#
# The index is honoured ONLY when that file holds exactly one begin marker and
# exactly one end marker, begin first. Missing, duplicated or reversed markers
# skip nothing, and the rows count as citations like any other line. A
# malformed index must fail toward reporting, never toward silence. Counted per
# occurrence, not per line, as build-requirement-index.sh counts them. No index
# file at all skips nothing either.
IDX_BEGIN_MARK='<!-- productizer:requirement-index:begin -->'
IDX_END_MARK='<!-- productizer:requirement-index:end -->'
: > "$WORK/idx.begin"
: > "$WORK/idx.end"
if [ -f "$IDX" ]; then
  irc=0
  grep -n -o -F -- "$IDX_BEGIN_MARK" "$IDX" > "$WORK/idx.begin" || irc=$?
  [ "$irc" -le 1 ] || die_unmeasured "grep failed reading $IDXREL for the requirement-index begin marker; which lines are generated is unknown"
  irc=0
  grep -n -o -F -- "$IDX_END_MARK" "$IDX" > "$WORK/idx.end" || irc=$?
  [ "$irc" -le 1 ] || die_unmeasured "grep failed reading $IDXREL for the requirement-index end marker; which lines are generated is unknown"
fi
n_idx_begin="$(wc -l < "$WORK/idx.begin" | tr -d ' ')"
n_idx_end="$(wc -l < "$WORK/idx.end" | tr -d ' ')"
# 0 and 0 skip nothing: no line number is both above 0 and below 0.
idx_begin_ln=0
idx_end_ln=0
if [ "$n_idx_begin" -eq 1 ] && [ "$n_idx_end" -eq 1 ]; then
  b="$(cut -d: -f1 "$WORK/idx.begin")"
  e="$(cut -d: -f1 "$WORK/idx.end")"
  if [ "$b" -lt "$e" ]; then idx_begin_ln="$b"; idx_end_ln="$e"; fi
fi
if [ "$idx_end_ln" -gt 0 ]; then
  printf 'requirement index: %s lines %s-%s are generated by build-requirement-index.sh and hold no sentence, so they are not counted as citations\n' \
    "$IDXREL" "$((idx_begin_ln + 1))" "$((idx_end_ln - 1))"
elif [ ! -f "$IDX" ]; then
  printf 'requirement index: no %s, so nothing is skipped\n' "$IDXREL"
elif [ "$n_idx_begin" -eq 0 ] && [ "$n_idx_end" -eq 0 ]; then
  printf 'requirement index: no markers in %s, so nothing is skipped\n' "$IDXREL"
else
  printf 'requirement index: MALFORMED in %s (%s begin marker(s), %s end marker(s), exactly one of each with begin first is required), so every line in it is counted as a citation\n' \
    "$IDXREL" "$n_idx_begin" "$n_idx_end"
fi

# --- per suspect requirement -------------------------------------------------
printf '\n'
: > "$WORK/citing.txt"
while IFS="$(printf '\t')" read -r kind id line status; do
  [ "$kind" = "suspect" ] || continue

  cur_text="$(awk -F'\t' -v i="$id" '$1 == i { print $5; exit }' "$WORK/cur.tsv")"
  base_text="$(awk -F'\t' -v i="$id" '$1 == i { print $5; exit }' "$WORK/base.tsv")"

  # The shape of the edit, never its content. Words, because the parser has
  # already collapsed whitespace and a re-wrap therefore cannot reach here.
  printf '%s\n' "$base_text" | tr ' ' '\n' > "$WORK/w.base"
  printf '%s\n' "$cur_text" | tr ' ' '\n' > "$WORK/w.cur"
  drc=0
  diff "$WORK/w.base" "$WORK/w.cur" > "$WORK/w.diff" || drc=$?
  [ "$drc" -le 1 ] || die_unmeasured "diff failed comparing the two versions of $id; the shape of the edit is unknown"
  removed="$(grep -c '^<' "$WORK/w.diff" || :)"
  added="$(grep -c '^>' "$WORK/w.diff" || :)"

  flat_base="$(printf '%s' "$base_text" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
  flat_cur="$(printf '%s' "$cur_text" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
  if [ "$flat_base" = "$flat_cur" ]; then
    shape="punctuation or capitalisation only"
  else
    shape="$removed word(s) removed, $added added"
  fi

  printf '  %s status %s unchanged, sentence CHANGED at %s:%s (%s)\n' \
    "$id" "$status" "$SPECREL" "$line" "$shape"
  printf '    read both: git diff %s -- %s\n' "$BASE_SHORT" "$SPECGIT"

  # `R5` must not match `R50`, `R5x` or `PR5`. The trailing class was `[^0-9]`
  # first, which let `R5x` through - found by probing the regex with strings
  # known to be non-citations rather than by reading it.
  re="(^|[^A-Za-z0-9_])${id}([^0-9A-Za-z_]|\$)"
  deps=0
  cleared=0
  idx_skipped=0
  : > "$WORK/hits.txt"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    grc=0
    grep -n -E "$re" "$TOP/$rel" > "$WORK/g.out" || grc=$?
    [ "$grc" -le 1 ] || die_unmeasured "grep failed reading $rel; the citations of $id are unknown"
    [ "$grc" -eq 0 ] || continue
    while IFS=: read -r ln _rest; do
      [ -n "$ln" ] || continue
      # The requirement's own definition line is where the sentence lives, not
      # a citation of it. Everything else in the file is.
      if [ "$rel" = "$SPECGIT" ] && [ "$ln" = "$line" ]; then continue; fi
      # A generated requirement-index row, strictly between well-formed
      # markers in the index file: it holds no sentence and nobody can clear it
      # by hand, so it would be one unclearable SUSPECT on every rewrite
      # (measured: spec.md:96 for R2, before the index left the spec; see the
      # index block above). Skipped BEFORE hits.txt, so it is neither a
      # dependant nor a reason to list the index file as a citing file.
      if [ "$rel" = "$IDXGIT" ] && [ "$ln" -gt "$idx_begin_ln" ] && [ "$ln" -lt "$idx_end_ln" ]; then
        idx_skipped=$((idx_skipped + 1))
        continue
      fi
      printf '%s\t%s\n' "$rel" "$ln" >> "$WORK/hits.txt"
    done < "$WORK/g.out"
  done < "$WORK/text.txt"

  while IFS="$(printf '\t')" read -r rel ln; do
    [ -n "$rel" ] || continue
    deps=$((deps + 1))
    printf '%s\n' "$rel" >> "$WORK/citing.txt"
    if grep -Fxq "$ln" "$(changed_lines_of "$rel")"; then
      cleared=$((cleared + 1))
      printf '      reviewed %s:%s  %s (this line was rewritten in the same change)\n' "$rel" "$ln" "$(label_for "$rel" "$ln")"
    else
      # A THIRD STATE, AND IT IS NOT A CLEARANCE. A citation whose own line did
      # not move but whose file did is still suspect - it is simply the one to
      # read first, because somebody was already in that file. Reporting it as
      # reviewed would clear, on the first fixture that had one, a coverage
      # claim in checks.yaml whose `- id: R2` line never changes by
      # construction while the evidence beside it was rewritten.
      near=""
      if grep -Fxq "$rel" "$WORK/touched.txt"; then
        near=" The file WAS edited in this change and this line was not, so read this one first."
      fi
      finding "$rel:$ln  $(label_for "$rel" "$ln") - this line is untouched, so it still points at wording that moved.$near"
    fi
  done < "$WORK/hits.txt"

  printf '    dependants: %s cited, %s re-read (their line moved too), %s left suspect\n' \
    "$deps" "$cleared" "$((deps - cleared))"
  if [ "$idx_skipped" -gt 0 ]; then
    printf '    generated requirement-index rows citing %s, not counted as dependants: %s\n' "$id" "$idx_skipped"
  fi
  if [ "$deps" -eq 0 ]; then
    printf '    nothing in scope cites %s. Not a finding, and not a clean bill either: a requirement nothing cites is one no artifact was traced to.\n' "$id"
  fi
done < "$WORK/class.tsv"

# Coverage: one bare path per citing file, deduplicated. Printed after the
# findings so the paths are not mistaken for the report.
if [ -s "$WORK/citing.txt" ]; then
  printf '\n'
  sort -u "$WORK/citing.txt"
fi

printf '\nLIMITATION, on every run: this check CANNOT tell a semantic rewrite from a typo fix.\n'
printf 'It measures that words moved, never what they now mean. "shall" to "should", "all" to\n'
printf '"most", "shall" to "shall not" and a corrected spelling are one event to it. A flag here\n'
printf 'is a prompt to re-read the dependant, not a claim that it is wrong.\n'

if [ "$found" -ne 0 ]; then
  printf 'FAIL: a requirement sentence moved under citations nobody touched. Each SUSPECT line is an artifact still asserting, verifying or citing wording that changed beneath it.\n' >&2
  exit 1
fi

printf 'PASS: every requirement whose sentence changed in place had every artifact citing it edited in the same change, or no sentence changed in place at all.\n'
