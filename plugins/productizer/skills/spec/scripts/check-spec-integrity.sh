#!/usr/bin/env bash
# check-spec-integrity.sh [--version] [--help] [--root DIR] [--max-versions N]
#                         [--reuse-floor F] [--selftest]
#
# Asserts the spec's three STRUCTURAL INVARIANTS, separately, against the real
# spec of this repository. Everything else in the lifecycle is built on ids
# meaning one thing forever; these are the requirements that say so.
#
#   R1  The lifecycle shall hold exactly one living spec per product.
#   R2  The lifecycle shall keep requirement ids permanent: never reused,
#       never renumbered.
#   R8  When a requirement is added, the lifecycle shall allocate the next
#       unused id and record it.
#
# NINE ASSERTIONS, EACH NAMED, EACH COUNTED ON ITS OWN. `examined` and
# `upheld` are printed per assertion and are derived from the items that
# assertion actually looked at - never from one shared `ok` flag. A check here
# once printed `upheld: 0` above six lines saying `held:`; the two numbers must
# be computed where the loop runs or they are decoration.
#
# ============================================================================
# R1 - AND THE UNIVERSE IT IS COUNTED OVER
# ============================================================================
#
# "Exactly one" is meaningless without a stated universe, so here is the one
# this check uses, and why it is not the obvious one.
#
#   THE UNIVERSE IS: every `*.md` file - tracked, or present on disk - inside
#   the SPEC HOME DIRECTORY, which is the directory component of `spec.path`
#   from the config (`.claude/productizer/`). Nothing else in the repository
#   is counted.
#
# THE NAIVE UNIVERSE - "any file called spec.md" - IS MEASURABLY WRONG HERE.
# Measured on this repository at the time of writing: 35 tracked markdown
# files carry both a `Next requirement id` field and at least one
# `- **R<n>**` requirement definition. They are eval prompts, eval fixtures,
# a check fixture, the scaffolding template and the normative grammar
# document. Every one of them is an INPUT to a test or a generator. Counting
# them would make this check permanently red against a correct repository,
# and a check that is red against a correct repository gets switched off -
# which is how R1 came to have nothing asserting it in the first place.
#
# WHY THE DIRECTORY IS THE RIGHT LINE, and not merely the convenient one: the
# spec home is the only place any tool in this lifecycle LOOKS. `spec.path` is
# the single path `check-spec-home.sh`, `check-acceptance-rows.sh`,
# `check-superseded-text.sh`, `validate-spec.py` and the intake stage all
# read. A spec-shaped markdown file somewhere else is not a second allocator,
# because nothing allocates from it. A second file in the spec home is,
# because that is where a tool would find it.
#
# So the rule is not "named spec.md" and it is not "looks like a spec". It is
# BOTH structure AND location: a file in the spec home that carries a
# `Next requirement id` counter AND at least one requirement definition the
# shared parser can read. `backlog.md`, `constitution.md` and `checks.yaml`
# sit in that directory and are correctly not living specs.
#
# WHAT THIS LEAVES UNASSERTED, stated rather than discovered later:
#   - A second living spec OUTSIDE the spec home directory is invisible here.
#     The count of spec-shaped files elsewhere is printed on every run so the
#     size of that blind spot is visible rather than implied.
#   - Repositories OTHER than this one are not reached. `check-spec-home.sh`
#     owns the cross-repo half of R1 and does reach them; this check owns the
#     within-repo half, which that one does not do. Neither is the whole of
#     R1 alone.
#
# ============================================================================
# R2 - A CLAIM ABOUT HISTORY, SO IT READS HISTORY
# ============================================================================
#
# "Never reused, never renumbered" cannot be answered by the file in front of
# you. The spec always says whatever it currently says: an id deleted last
# month, or handed to a different requirement, leaves the file looking
# perfectly consistent. The only place the answer survives is git, so this
# check parses EVERY reachable version of the spec, exactly as
# `check-superseded-text.sh` does, and chooses its baseline PER REQUIREMENT.
#
#   ids-retained         every id defined in any reachable commit is still
#                        defined today. A superseded or withdrawn requirement
#                        is RETAINED in the file with a marker, so a marker
#                        cannot rescue a disappearance: an id that is gone is
#                        gone, and the plans, tests and PR titles citing it
#                        now point at nothing. `check-superseded-text.sh`
#                        cannot see this - it iterates over the requirements
#                        the spec has TODAY, and a deleted id is not one.
#
#   ids-not-renumbered   no requirement's sentence has moved from one id to
#                        another. For every historical id, its sentence at
#                        that commit is not now carried by a DIFFERENT id.
#                        Renumbering trips this and `ids-retained` together;
#                        a plain deletion trips only `ids-retained`, which is
#                        how the two are told apart.
#
#   ids-not-reused       no id's meaning has been swapped underneath it. Two
#                        signals, both counted here:
#                          a) STATUS REVIVAL - superseded or withdrawn in some
#                             reachable commit, active today. The id was
#                             retired and then handed out again, which is the
#                             unambiguous form of reuse.
#                          b) TEXT DIVERGENCE - the sentence under an active
#                             id has drifted past `--reuse-floor` (default
#                             0.50 Jaccard similarity over lowercased word
#                             sets) from its oldest reachable sentence.
#                             Refining KEEPS the id and edits the text, so
#                             some drift is correct and expected; a sentence
#                             sharing less than half its vocabulary with what
#                             was agreed is a different requirement wearing an
#                             old number.
#                        The similarity floor is a THRESHOLD, not a proof. A
#                        rewrite that keeps half the words reads as a
#                        refinement here, and a genuine refinement that
#                        rewrites more than half reads as reuse. The floor is
#                        printed on every run and is settable, so the number
#                        being argued with is visible rather than buried.
#
#   ids-permanent-declared   `spec.ids_are_permanent` is true in the config.
#                        A configuration that disclaims the invariant is a
#                        repository that has opted out of R2 in writing, and
#                        that is a finding about the repository, not about
#                        the spec text.
#
# A SHALLOW CLONE IS REFUSED, NEVER PASSED. `--depth 1` reaches the spec and
# reaches nothing before it, so "no id disappeared" would be a statement about
# one commit dressed up as a statement about history. CI must fetch full
# history (fetch-depth: 0) for this to measure anything, and a green run on a
# shallow clone is a green that measured nothing.
#
# ============================================================================
# R8 - TWO OBLIGATIONS, ASSERTED SEPARATELY
# ============================================================================
#
#   counter-above-every-id-used
#       `Next requirement id` is strictly greater than EVERY id ever used -
#       active, superseded, withdrawn, and ids visible only in history. A
#       superseded id is used forever: it is the one number that must never be
#       handed out again, and a counter that has slipped back below it will
#       hand it out on the next allocation.
#
#   added-ids-recorded-in-changelog
#       Every id ADDED after the spec's founding commit - present at a commit,
#       absent at the commit before - is named in the `## Change log` table.
#
#       THE ACCEPTANCE ROW IS NOT RE-ASSERTED HERE. `check-acceptance-rows.sh`
#       already owns exactly that: every active requirement has a row in the
#       `## Acceptance criteria` table. Repeating it would give R8 two checks
#       that go red together and neither of which adds evidence. The half
#       nothing asserted is the CHANGE LOG - the audit join between the id and
#       the commit, branch and issue that introduced it. A requirement can hold
#       a perfectly good acceptance row and still have arrived from nowhere.
#
#       THE FOUNDING COMMIT IS EXEMPT, and this is not a loophole. The oldest
#       reachable commit that touched the spec introduced every id it contains
#       at once; those ids were not "added" by the lifecycle, they are what the
#       lifecycle started from. Demanding change-log rows for them would go
#       permanently red against this repository's own correct spec - R1 to R22
#       arrived in the first commit and have no rows, correctly.
#
#       IF NOTHING WAS EVER ADDED AFTER THE FOUNDING COMMIT, this assertion is
#       UNMEASURED and the run exits 2. A spec whose every id arrived in one
#       commit has never exercised the allocate-and-record path, and "0
#       unrecorded additions" out of 0 additions is not evidence that the path
#       works.
#
# ============================================================================
# GUARDING THE PREMISES - EVERY ONE OF THESE IS EXIT 2, NEVER A PASS
# ============================================================================
#
#   no git work tree, or --root outside its own top level
#   python3 absent, or `spec-requirements.sh` not beside this script
#   the config unreadable, unparseable, or naming no spec path
#   the spec unreadable, or holding no requirement definitions
#   the spec not tracked by git - there is no history to read
#   a SHALLOW clone
#   more spec commits than --max-versions - the walk would be truncated, and a
#     truncated walk cannot tell an id that was never there from one that was
#     dropped before the window
#   no `Next requirement id` field, or no `## Change log` section
#   nothing added after the founding commit
#
# NEGATIVES ARE PROBED, NOT ASSUMED. An empty result is not a confirmed
# absence, and this repository has produced confident false negatives from a
# grep that silently matched nothing. So before any "none found" is reported:
#
#   the living-spec detector must recognise the DECLARED spec. If the file we
#     know is a living spec does not trip the detector, "no second living
#     spec" is a statement about a broken detector.
#   the historical parse must contain at least one id the spec defines today.
#     A history walk that produced no usable records would otherwise report
#     "no id disappeared" having compared nothing.
#   the change-log parse must yield at least one id.
#
# Each probe failing is exit 2.
#
# COST, AND WHAT IS BOUNDED. Every commit that touched the SPEC is read and
# parsed once - linear in the spec's own history, not the repository's, and
# not in the number of requirements. That is nine commits here. The walk is
# bounded at --max-versions (default 400) and EXCEEDING THE BOUND REFUSES
# rather than silently measuring the newest N, because a truncated history
# answers R2 wrongly and confidently.
#
# WHAT IT PRINTS. One BARE repo-relative path per line for every file
# examined, canonicalised so no `..` appears - the runner reads those as
# coverage. Historical versions are printed as `<path>@<short sha>`, the same
# form `check-superseded-text.sh` uses. Everything else is INDENTED.
# Requirement TEXT IS NEVER PRINTED, only ids, lines and similarity numbers:
# this output lands in a committed result file, and a check that quotes the
# spec it protects publishes it on every run.
#
# EXIT PRECEDENCE: UNMEASURED BEATS FINDINGS BEATS CLEAN. A run that could not
# reach a premise exits 2 even when it also found a real violation; the
# findings are still printed. 1 is a complete verdict and such a run does not
# have one.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  clean - all nine assertions held
#   1  findings - at least one assertion did not hold
#   2  could not run, or could not measure. Never 0.
#
# Under --selftest (--self-test is accepted too) the same three mean: every
# case produced the exit code it declares and said what it was supposed to say
# (0), at least one did not (1), and the corpus could not be driven at all (2).
set -euo pipefail

VERSION="check-spec-integrity 1.0"
ROOT=""
MAX_VERSIONS=400
REUSE_FLOOR="0.50"
MODE="measure"

usage() {
  printf 'usage: check-spec-integrity.sh [--version] [--help] [--root DIR]\n'
  printf '                               [--max-versions N] [--reuse-floor F]\n'
  printf '  --root DIR        the repo work tree to examine. Defaults to the git\n'
  printf '                    top level, never to the working directory.\n'
  printf '  --max-versions N  refuse rather than truncate the spec history walk\n'
  printf '                    beyond N commits (default 400).\n'
  printf '  --reuse-floor F   word-set similarity below which an edited\n'
  printf '                    requirement reads as reuse (default 0.50).\n'
  printf '  --selftest        drive the built-in corpus instead of a repository.\n'
}

die_unmeasured() { printf 'check-spec-integrity: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)
      [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --max-versions)
      [ "$#" -ge 2 ] || die_unmeasured "--max-versions needs a number"
      MAX_VERSIONS="$2"; shift 2 ;;
    --max-versions=*) MAX_VERSIONS="${1#--max-versions=}"; shift ;;
    --reuse-floor)
      [ "$#" -ge 2 ] || die_unmeasured "--reuse-floor needs a number"
      REUSE_FLOOR="$2"; shift 2 ;;
    --reuse-floor=*) REUSE_FLOOR="${1#--reuse-floor=}"; shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    -*) printf 'check-spec-integrity: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'check-spec-integrity: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# --selftest. R39: one case per exit code this tool can return, each built as
# a real git history in a sandbox, so nothing here reads or writes the
# repository under test.
#
# THE HISTORIES ARE BUILT, NOT COMMITTED AS FIXTURES. R2 is a claim about
# history and R8.2 is a claim about what a commit ADDED, so neither can be
# posed by a directory of files: a case under `fixtures/` cannot carry a git
# history of its own inside this repository. Every case is one or two commits
# made at run time in the temporary directory this run already owns.
#
# EVERY CASE ASSERTS ITS OWN SENTENCE, NOT ONLY ITS EXIT CODE, and here that
# is load-bearing rather than tidy: NINE assertions share exit 1. A retained
# id, a renumbering, a revival, a drift past the floor, a counter below a used
# id, a second living spec, a config that disclaims the invariant and an
# unrecorded addition are one number to an exit-code-only corpus. A change
# that turned a renumbering into a plain deletion - they differ by exactly
# which of R2.2 and R2.3 fires - would stay green through it.
#
# THE PRECEDENCE IS DRIVEN TOO. `unmeasured-beats-findings` holds a real
# counter violation AND has nothing added after its founding commit; the
# header says the run must then exit 2 with the finding still printed.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SELF="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"
  [ -f "$SELF" ] ||
    die_unmeasured "cannot re-invoke this script for the self-test, so no case was driven"
  command -v git >/dev/null ||
    die_unmeasured "git is not on PATH, so no history could be built and no case was driven"

  # `pwd -P` because the temporary directory is reached through a symlink on
  # macOS and this check compares --root against a resolved git top level.
  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-spec-integrity-selftest.XXXXXX")" ||
    die_unmeasured "could not create a sandbox, so no case was driven"
  SB="$(cd "$SB" && pwd -P)"
  trap 'rm -rf "$SB"' EXIT HUP INT TERM

  ST=".claude/productizer"

  new_repo() {
    mkdir -p "$SB/$1/$ST"
    git -c init.defaultBranch=main init -q "$SB/$1"
    git -C "$SB/$1" config user.email "fixture@example.invalid"
    git -C "$SB/$1" config user.name "check-spec-integrity selftest"
  }
  commit_all() {
    git -C "$SB/$1" add -A
    git -C "$SB/$1" -c commit.gpgsign=false commit -q -m "$2"
  }
  good_config() {
    cat > "$SB/$1/$ST/config.json" <<'JSON'
{ "product": { "name": "sandbox",
               "spec_home": "example/home-repo",
               "repos": ["example/home-repo"] },
  "spec": { "path": ".claude/productizer/spec.md", "ids_are_permanent": true } }
JSON
  }
  founding_spec() {
    cat > "$SB/$1/$ST/spec.md" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R4` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
SPEC
  }
  # A case is: a founding commit, then a second commit carrying whatever the
  # caller pipes in. `added` below then means "present here, absent at the
  # commit before", which is the shape R8.2 is asserted over.
  found_case() { new_repo "$1"; good_config "$1"; founding_spec "$1"; commit_all "$1" "founding"; }
  head_spec()  { cat > "$SB/$1/$ST/spec.md"; commit_all "$1" "$2"; }

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
      printf '  held: case %-26s exit %d, and said so - %s\n' "$case_name" "$rc" "$marker"
      return 0
    fi
    printf '  FINDING: case %-26s %s - expected: %s\n' "$case_name" "$why" "$marker"
    FAILED=$((FAILED + 1))
    return 0
  }

  # --- clean: R4 allocated, counter raised, addition recorded --------------
  found_case clean
  head_spec clean "allocate R4 and record it" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R5` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
| 2026-01-02 | R4 | the view requirement was added |
SPEC

  # --- exit 1 --------------------------------------------------------------
  # R4 is allocated and recorded in the same commit, so R8.2 is MEASURED here
  # and the deletion of R2 is the only thing left to report. Without that the
  # run exits 2 - nothing added after the founding commit - and the case would
  # be asserting the precedence rule instead of the retention one. Measured,
  # not reasoned: the first build of this case exited 2 and said so.
  found_case id-deleted
  head_spec id-deleted "delete R2 outright while allocating R4" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R5` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
| 2026-01-02 | R4 | the view requirement was added |
SPEC

  found_case renumbered
  head_spec renumbered "hand R2's sentence to R5" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R6` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R3** — The lifecycle shall record every classification in the change log.
- **R5** — The lifecycle shall keep requirement ids permanent, never reused.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
| 2026-01-02 | R5 | renumbered from R2 |
SPEC

  # revived: superseded in a reachable commit, active again today.
  found_case revived
  head_spec revived "supersede R3" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R5` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.
  Superseded by R4. Narrowed.
- **R4** — The lifecycle shall record every merging classification.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
| 2026-01-02 | R4 | the narrowed requirement was added |
SPEC
  head_spec revived "hand R3 back out as if it had never been retired" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R5` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall record every merging classification.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
| 2026-01-02 | R4 | the narrowed requirement was added |
SPEC

  found_case drifted
  head_spec drifted "rewrite R2 past the similarity floor" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R5` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — Nightly evaluation jobs must publish cost figures to the finance dashboard.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
| 2026-01-02 | R4 | the view requirement was added |
SPEC

  found_case counter-low
  head_spec counter-low "allocate R4 and drop the counter below it" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R3` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
| 2026-01-02 | R4 | the view requirement was added |
SPEC

  found_case not-permanent
  head_spec not-permanent "allocate R4" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R5` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
| 2026-01-02 | R4 | the view requirement was added |
SPEC
  cat > "$SB/not-permanent/$ST/config.json" <<'JSON'
{ "product": { "name": "sandbox",
               "spec_home": "example/home-repo",
               "repos": ["example/home-repo"] },
  "spec": { "path": ".claude/productizer/spec.md", "ids_are_permanent": false } }
JSON

  found_case home-not-in-repos
  head_spec home-not-in-repos "allocate R4" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R5` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
| 2026-01-02 | R4 | the view requirement was added |
SPEC
  cat > "$SB/home-not-in-repos/$ST/config.json" <<'JSON'
{ "product": { "name": "sandbox",
               "spec_home": "example/somewhere-else",
               "repos": ["example/home-repo"] },
  "spec": { "path": ".claude/productizer/spec.md", "ids_are_permanent": true } }
JSON

  # A second allocator in the spec home: a counter AND requirement definitions.
  found_case second-living-spec
  head_spec second-living-spec "allocate R4" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R5` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
| 2026-01-02 | R4 | the view requirement was added |
SPEC
  cat > "$SB/second-living-spec/$ST/spec-draft.md" <<'SPEC'
# A second living spec in the same home

Next requirement id
: `R9` — allocate from here, then increment.

## Requirements

- **R7** — The lifecycle shall do something else entirely.
SPEC

  found_case unrecorded-addition
  head_spec unrecorded-addition "allocate R4 and record nothing" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R5` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
SPEC

  # --- exit 2 --------------------------------------------------------------
  found_case nothing-added

  # A finding AND a premise that was never measured. 1 is a complete verdict
  # and this run does not have one, so it exits 2 with the finding printed.
  new_repo unmeasured-beats-findings
  good_config unmeasured-beats-findings
  cat > "$SB/unmeasured-beats-findings/$ST/spec.md" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R2` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
SPEC
  commit_all unmeasured-beats-findings "founding, with the counter already below a used id"

  found_case empty-changelog
  head_spec empty-changelog "allocate R4 and empty the change log" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R5` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.

## Change log

| date | ids | why |
|---|---|---|
SPEC

  found_case no-changelog
  head_spec no-changelog "allocate R4 and drop the change log" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R5` — allocate from here, then increment.

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
SPEC

  found_case no-counter
  head_spec no-counter "drop the counter" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
SPEC

  found_case no-requirements
  head_spec no-requirements "empty the requirements section" <<'SPEC'
# Living spec — sandbox

Next requirement id
: `R4` — allocate from here, then increment.

## Design

Prose, and no requirement definitions at all.

## Change log

| date | ids | why |
|---|---|---|
| 2026-01-01 | R1 | the founding commit |
SPEC

  new_repo no-config
  founding_spec no-config
  commit_all no-config "a spec with no config beside it"

  new_repo no-spec-path
  founding_spec no-spec-path
  printf '{ "product": { "repos": ["example/home-repo"] }, "spec": {} }\n' \
    > "$SB/no-spec-path/$ST/config.json"
  commit_all no-spec-path "a config that names no spec path"

  new_repo spec-absent
  good_config spec-absent
  commit_all spec-absent "a config naming a spec that is not there"

  new_repo untracked
  good_config untracked
  printf 'a repository that committed something other than its spec\n' > "$SB/untracked/README"
  commit_all untracked "founding, without the spec"
  founding_spec untracked

  git clone -q --depth 1 "file://$SB/clean" "$SB/shallow" ||
    die_unmeasured "could not build a shallow clone, so the case that refuses one was never driven"

  mkdir -p "$SB/not-a-work-tree/$ST"
  good_config not-a-work-tree
  founding_spec not-a-work-tree

  printf 'not a directory\n' > "$SB/a-file"

  # THE CLEAN CASE GUARDS THE OTHERS' PREMISE. If a repository where all nine
  # assertions hold does not exit 0 and say so, every red case below would be
  # red for that reason instead of its own and nothing would have been
  # measured.
  CLEAN_RC=0
  bash "$SELF" --root "$SB/clean" > "$SB/clean.out" 2> "$SB/clean.err" || CLEAN_RC=$?
  if [ "$CLEAN_RC" -ne 0 ] || ! grep -q 'assertions upheld: 9 of 9' "$SB/clean.out"; then
    printf '  the clean case exited %d and did not report all nine assertions holding.\n' "$CLEAN_RC"
    die_unmeasured "the corpus premise did not hold; unmeasured, not a pass"
  fi
  printf '  held: case %-26s exit 0, and said so - %s\n' "clean" "assertions upheld: 9 of 9"
  CODES="$CODES$CLEAN_RC
"

  drive id-deleted           1 'is not defined in the spec today'
  drive renumbered           1 'The requirement was renumbered'
  drive revived              1 'which is reuse in its unambiguous form'
  drive drifted              1 'a different requirement wearing an old number'
  drive counter-low          1 'which is not above'
  drive not-permanent        1 'not true. A configuration that disclaims'
  drive home-not-in-repos    1 'is not one of the entries in'
  drive second-living-spec   1 'a second file in the spec home presents itself as a living spec'
  drive unrecorded-addition  1 'no row in the `## Change log` table names it'

  drive nothing-added        2 'the allocate-and-record path has never run'
  drive unmeasured-beats-findings 2 'which is not above'
  drive empty-changelog      2 'yielded no requirement id at all'
  drive no-changelog         2 'has no `## Change log` section'
  drive no-counter           2 'has no `Next requirement id` field'
  drive no-requirements      2 'holds no requirement definitions'
  drive no-config            2 'cannot read or parse'
  drive no-spec-path         2 'declares no `spec.path` string'
  drive spec-absent          2 'cannot read .claude/productizer/spec.md'
  drive untracked            2 'is not tracked by git'
  drive shallow              2 'this is a SHALLOW clone'
  drive not-a-work-tree      2 'is not inside a git work tree'
  drive max-versions         2 'Refusing rather than walking the newest' --root "$SB/clean" --max-versions 1
  drive bad-max-versions     2 'must be a whole number'                  --root "$SB/clean" --max-versions x
  drive bad-reuse-floor      2 'must lie between 0 and 1'                --root "$SB/clean" --reuse-floor 2
  drive root-not-a-dir       2 'is not a directory'                      --root "$SB/a-file"

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
  printf '  R39 for this tool: the self-test exists, reaches 0, 1 and 2, and every case asserts which of the nine assertions produced its finding as well as which code.\n'
  printf '  NOT ASSERTED: the two blind spots the header names - a second living spec OUTSIDE the spec home directory, and repositories other than this one - are out of scope by design rather than untested, so no case here can pose them.\n'
  exit 0
fi

case "$MAX_VERSIONS" in
  ''|*[!0-9]*) die_unmeasured "--max-versions must be a whole number, got '$MAX_VERSIONS'" ;;
esac
[ "$MAX_VERSIONS" -ge 1 ] || die_unmeasured "--max-versions must be at least 1"

# Defaulting to the working directory has caused four separate silent-wrong-
# answer bugs in this repository: the script reads a directory that is not the
# repo and reports a confident clean result. git names the work tree or
# nothing does.
if [ -z "$ROOT" ]; then
  if ! ROOT="$(git rev-parse --show-toplevel)"; then
    die_unmeasured "no git work tree here, and --root was not given. Refusing rather than reading the working directory, which is not the repo often enough to matter."
  fi
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

command -v python3 >/dev/null ||
  die_unmeasured "python3 is not on PATH, so the config cannot be parsed and the history cannot be compared. Refusing rather than guessing."

SELFDIR="$(cd "$(dirname "$0")" && pwd -P)"
PARSER="$SELFDIR/spec-requirements.sh"
[ -x "$PARSER" ] ||
  die_unmeasured "spec-requirements.sh is not beside this script and executable. It is the one parser check-superseded-text.sh and check-pending-ruling-scope.sh already read the spec through, and two checks that must agree on what R14's text IS cannot each carry their own. Without it nothing here read the spec, and a run that read nothing is not a run that found nothing."

TOP="$(git -C "$ROOT" rev-parse --show-toplevel)" ||
  die_unmeasured "--root $ROOT is not inside a git work tree. R2 is a claim about history, and there is no history here."
TOP="$(cd "$TOP" && pwd -P)"
case "$ROOT/" in
  "$TOP"/*) ;;
  *) die_unmeasured "--root $ROOT resolves outside its own git top level $TOP" ;;
esac

python3 - "$ROOT" "$TOP" "$PARSER" "$MAX_VERSIONS" "$REUSE_FLOOR" <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

root, top, parser, max_versions_raw, reuse_floor_raw = sys.argv[1:6]
max_versions = int(max_versions_raw)

CONFIG_REL = ".claude/productizer/config.json"


def refuse(message):
    sys.stderr.write("check-spec-integrity: %s\n" % message)
    raise SystemExit(2)


try:
    reuse_floor = float(reuse_floor_raw)
except ValueError:
    refuse("--reuse-floor must be a number, got %r" % reuse_floor_raw)
if not 0.0 <= reuse_floor <= 1.0:
    refuse("--reuse-floor must lie between 0 and 1, got %r" % reuse_floor_raw)


def rel_to_root(path):
    """Repo-relative and canonical. A `..` here is a path the runner cannot
    match against the file set, so it is refused rather than printed."""
    shown = os.path.relpath(os.path.realpath(path), root)
    if shown == ".." or shown.startswith(".." + os.sep) or os.path.isabs(shown):
        refuse("%s resolves outside --root %s; a coverage path with a `..` in "
               "it is one the runner cannot match" % (path, root))
    return shown


examined_paths = []


def cover(shown):
    """One bare repo-relative path per line, on stdout, unindented. Printed
    only AFTER the file has actually been read - a path printed before the
    read is coverage claimed for a file nobody opened."""
    examined_paths.append(shown)
    sys.stdout.write("%s\n" % shown)


def git(*args):
    proc = subprocess.run(["git", "-C", top] + list(args),
                          stdout=subprocess.PIPE, universal_newlines=True)
    if proc.returncode != 0:
        refuse("git %s failed under %s; the history this check reads is "
               "unavailable" % (" ".join(args), top))
    return proc.stdout


# --- the shared parser ------------------------------------------------------
#
# spec-requirements.sh, not a third parser of our own. Two checks that must
# agree on what R14's text IS cannot each carry their own: the day the two
# disagree, one reports a requirement unchanged and the other reports it
# edited, and both are green in their own terms.
def parse_spec(path):
    proc = subprocess.run([parser, path], stdout=subprocess.PIPE,
                          universal_newlines=True)
    if proc.returncode != 0:
        refuse("spec-requirements.sh refused %s (exit %d)"
               % (path, proc.returncode))
    out = []
    for line in proc.stdout.split("\n"):
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) != 5:
            refuse("spec-requirements.sh emitted %d fields where the contract "
                   "is 5, reading %s" % (len(fields), path))
        out.append({"id": fields[0], "line": int(fields[1]),
                    "status": fields[2], "target": fields[3],
                    "text": fields[4]})
    return out


RE_COUNTER_HEAD = re.compile(r'^Next requirement id\s*$')
RE_ID = re.compile(r'R([0-9]+)')
RE_RANGE = re.compile(r'R([0-9]+)\s*[–—-]\s*R([0-9]+)')
RE_WORD = re.compile(r'[a-z0-9]+')


def counter_of(text):
    """`Next requirement id` / `: `R29` - ...`. Returns the integer, or None."""
    lines = text.split("\n")
    for index, line in enumerate(lines):
        if not RE_COUNTER_HEAD.match(line):
            continue
        for follow in lines[index + 1:index + 4]:
            if not follow.strip():
                continue
            match = RE_ID.search(follow)
            if match:
                return int(match.group(1))
            break
    return None


def looks_like_living_spec(path):
    """BOTH structure AND location decide a living spec; this is the structure
    half. A counter to allocate from, and at least one requirement definition
    the shared parser can read. Location is the caller's business."""
    try:
        with open(path, encoding="utf-8") as handle:
            body = handle.read()
    except (OSError, UnicodeDecodeError):
        return None
    if counter_of(body) is None:
        return False
    return bool(parse_spec(path))


def words(text):
    return set(RE_WORD.findall(text.lower()))


def similarity(a, b):
    """Jaccard over lowercased word sets. Whitespace, re-wrapping and
    punctuation do not move it; vocabulary does."""
    wa, wb = words(a), words(b)
    if not wa and not wb:
        return 1.0
    if not wa or not wb:
        return 0.0
    return len(wa & wb) / float(len(wa | wb))


def expand_ids(cell):
    """`R23-R28` is six ids, not two. The change log writes ranges with an en
    dash; a parser that reads only the endpoints reports the four ids between
    them as unrecorded."""
    found = set()
    for match in RE_RANGE.finditer(cell):
        low, high = int(match.group(1)), int(match.group(2))
        if low <= high and high - low <= 5000:
            for n in range(low, high + 1):
                found.add(n)
    for match in RE_ID.finditer(cell):
        found.add(int(match.group(1)))
    return found


# ---------------------------------------------------------------------------
# the config
# ---------------------------------------------------------------------------
config_path = os.path.join(root, CONFIG_REL)
try:
    with open(config_path, encoding="utf-8") as handle:
        config = json.load(handle)
except (OSError, ValueError) as exc:
    refuse("cannot read or parse %s: %s. A config nobody could open names no "
           "spec path at all; that is unmeasured, not a product with one spec."
           % (CONFIG_REL, exc))
if not isinstance(config, dict):
    refuse("%s is not a JSON object" % CONFIG_REL)
cover(rel_to_root(config_path))

spec_block = config.get("spec") if isinstance(config.get("spec"), dict) else {}
product = config.get("product") if isinstance(config.get("product"), dict) else {}

spec_path_decl = spec_block.get("path")
if not isinstance(spec_path_decl, str) or not spec_path_decl.strip():
    refuse("%s declares no `spec.path` string. Without a declared path there "
           "is no spec to count, and no directory to count it in." % CONFIG_REL)
spec_path_decl = spec_path_decl.strip()
if os.path.isabs(spec_path_decl):
    refuse("`spec.path` is absolute (%s); it must be repo-relative"
           % spec_path_decl)

spec_abs = os.path.join(root, spec_path_decl)
spec_home_dir = os.path.dirname(spec_abs)

# ---------------------------------------------------------------------------
# the spec as it stands now
# ---------------------------------------------------------------------------
if not (os.path.isfile(spec_abs) and os.access(spec_abs, os.R_OK)):
    refuse("cannot read %s under %s. Without the spec there is nothing to "
           "count, nothing to compare against history, and no counter to read."
           % (spec_path_decl, root))
with open(spec_abs, encoding="utf-8") as handle:
    spec_text = handle.read()
spec_rel = rel_to_root(spec_abs)
cover(spec_rel)

current = parse_spec(spec_abs)
if not current:
    refuse("%s holds no requirement definitions. That is nothing measured, "
           "not nothing wrong." % spec_rel)
current_by_id = {}
for req in current:
    current_by_id.setdefault(req["id"], req)

counter = counter_of(spec_text)
if counter is None:
    refuse("%s has no `Next requirement id` field this check could read. R8's "
           "first half is a claim about that number, and there is no number."
           % spec_rel)

# ---------------------------------------------------------------------------
# git: the history R2 is answered from
# ---------------------------------------------------------------------------
spec_git = os.path.relpath(os.path.realpath(spec_abs), top)
tracked = git("ls-files", "--", spec_git).strip()
if not tracked:
    refuse("%s is not tracked by git, so no previous version of any "
           "requirement exists. R2 is a claim about history and this "
           "repository has none for the spec - no measurement, not a measured "
           "zero." % spec_rel)

if git("rev-parse", "--is-shallow-repository").strip() == "true":
    refuse("this is a SHALLOW clone. It reaches the spec and reaches nothing "
           "before it, so 'no id disappeared' would be a statement about one "
           "commit dressed up as a statement about history. Fetch full "
           "history (fetch-depth: 0) and re-run. A green run here is a green "
           "that measured nothing.")

shas = [s for s in git("log", "--format=%H", "--", spec_git).split("\n") if s]
if len(shas) > max_versions:
    refuse("%s has %d commits and --max-versions is %d. Refusing rather than "
           "walking the newest %d: a truncated history cannot tell an id that "
           "was never there from one dropped before the window, and R2 would "
           "be answered confidently and wrongly. Raise --max-versions."
           % (spec_rel, len(shas), max_versions, max_versions))

work = tempfile.mkdtemp(prefix="check-spec-integrity.")
try:
    # Oldest first, so `added` below means "present here, absent at the
    # commit before" rather than the reverse.
    versions = []
    for sha in reversed(shas):
        listing = git("ls-tree", sha, "--", spec_git).strip()
        if not listing:
            continue          # the spec did not exist at that commit
        short = git("rev-parse", "--short", sha).strip()
        blob = os.path.join(work, "v.md")
        with open(blob, "w", encoding="utf-8") as handle:
            handle.write(git("show", "%s:%s" % (sha, spec_git)))
        parsed = parse_spec(blob)
        cover("%s@%s" % (spec_rel, short))
        versions.append({"sha": short, "reqs": parsed,
                         "ids": set(r["id"] for r in parsed)})

    if not versions:
        refuse("git lists %s as tracked but no reachable commit holds it. "
               "There is no history to compare against." % spec_rel)

    # ---- the universe R1 is counted over ---------------------------------
    candidates = set()
    for entry in git("ls-files", "--", spec_home_dir).split("\n"):
        entry = entry.strip()
        if entry.endswith(".md"):
            candidates.add(os.path.join(top, entry))
    if os.path.isdir(spec_home_dir):
        for name in os.listdir(spec_home_dir):
            if name.endswith(".md"):
                candidates.add(os.path.join(spec_home_dir, name))
    candidates.add(spec_abs)
    candidate_list = sorted(candidates, key=lambda p: rel_to_root(p))

    living = []
    unreadable = []
    for path in candidate_list:
        shown = rel_to_root(path)
        verdict = looks_like_living_spec(path)
        if verdict is None:
            unreadable.append(shown)
            continue
        if shown not in examined_paths:
            cover(shown)
        if verdict:
            living.append(shown)

    # ---- the change log ---------------------------------------------------
    lines = spec_text.split("\n")
    log_start = None
    for index, line in enumerate(lines):
        if re.match(r'^##\s+Change log\s*$', line):
            log_start = index + 1
            break
    if log_start is None:
        refuse("%s has no `## Change log` section. R8's recording half is a "
               "claim about that table, and the table does not exist - which "
               "is a different fact from every id being unrecorded."
               % spec_rel)
    log_end = len(lines)
    for index in range(log_start, len(lines)):
        if re.match(r'^##\s', lines[index]):
            log_end = index
            break
    logged_ids = set()
    for index in range(log_start, log_end):
        if lines[index].lstrip().startswith("|"):
            logged_ids |= expand_ids(lines[index])

    # =======================================================================
    # PROBE EVERY NEGATIVE BEFORE REPORTING IT
    # =======================================================================
    if spec_rel not in living:
        refuse("the living-spec detector does not recognise %s, which IS this "
               "product's living spec. Every 'no second living spec' this run "
               "could report would be a statement about a broken detector, not "
               "about the repository. Probed with a value known to exist, and "
               "it came back false." % spec_rel)

    historical_ids = set()
    for version in versions:
        historical_ids |= version["ids"]
    overlap = historical_ids & set(current_by_id)
    if not overlap:
        refuse("the history walk read %d version(s) of %s and produced no id "
               "the spec defines today. 'No id disappeared' out of that is a "
               "comparison against nothing. Probed with the current id set, "
               "and the intersection is empty."
               % (len(versions), spec_rel))

    if not logged_ids:
        refuse("the `## Change log` table in %s yielded no requirement id at "
               "all. 'Every added id is recorded' out of an empty parse is a "
               "grep that silently matched nothing - which is how this "
               "repository has produced confident false negatives before."
               % spec_rel)

    # =======================================================================
    # THE NINE ASSERTIONS
    # =======================================================================
    results = []
    findings = []
    unmeasured = []

    def assertion(key, requirement, name, examined, upheld, held, note=None):
        results.append({"key": key, "req": requirement, "name": name,
                        "examined": examined, "upheld": upheld,
                        "held": held, "note": note})

    def finding(text):
        findings.append(text)

    # ---- R1.1 the config names exactly one spec ---------------------------
    facts = 0
    ok = 0
    facts += 1
    if isinstance(spec_block.get("path"), str) and spec_block["path"].strip():
        ok += 1
    else:
        finding("%s: `spec.path` is not a single non-empty string. A product "
                "whose config names a list of specs, or none, cannot hold "
                "exactly one." % CONFIG_REL)
    facts += 1
    spec_home = product.get("spec_home")
    if isinstance(spec_home, str) and spec_home.strip():
        ok += 1
    else:
        finding("%s: `product.spec_home` is not a single non-empty string, so "
                "no one repository is named as the home of the one spec."
                % CONFIG_REL)
    facts += 1
    repos = product.get("repos")
    if (isinstance(repos, list) and repos
            and all(isinstance(r, str) and r.strip() for r in repos)
            and isinstance(spec_home, str) and spec_home.strip() in
            [r.strip() for r in repos]):
        ok += 1
    else:
        finding("%s: `product.spec_home` is not one of the entries in "
                "`product.repos`. The home of the spec has to be a repository "
                "the product admits to owning, or the count of specs is taken "
                "over a set that excludes the one that matters." % CONFIG_REL)
    assertion("R1.1", "R1", "config-names-one-spec", facts, ok,
              "the config names exactly one spec path, one home repo, and the "
              "home is among the product's repos")

    # ---- R1.2 that spec exists, is readable, and IS a living spec ---------
    assertion("R1.2", "R1", "declared-spec-present-and-living", 1, 1,
              "%s exists, is readable, carries a `Next requirement id` and "
              "%d requirement definitions" % (spec_rel, len(current)))

    # ---- R1.3 nothing else in the spec home presents as a living spec -----
    extras = [p for p in living if p != spec_rel]
    for path in extras:
        finding("%s: a second file in the spec home presents itself as a "
                "living spec - it carries a `Next requirement id` counter and "
                "requirement definitions. Two allocators both handing out the "
                "next id is R1's exact failure, and the divergence is found "
                "later by whoever trusted the wrong one." % path)
    for path in unreadable:
        unmeasured.append("%s: a file in the spec home could not be read, so "
                          "whether it presents as a living spec is UNKNOWN. "
                          "Unreadable is not absent." % path)
    assertion("R1.3", "R1", "no-second-living-spec",
              len(candidate_list), len(candidate_list) - len(extras),
              "exactly one file in the spec home is a living spec, and it is "
              "the one the config declares",
              "universe: *.md under %s. Spec-shaped markdown elsewhere in the "
              "repository is out of scope by design - see the header."
              % rel_to_root(spec_home_dir))

    # ---- R2.1 the config has not disclaimed the invariant -----------------
    permanent = spec_block.get("ids_are_permanent")
    if permanent is True:
        assertion("R2.1", "R2", "ids-permanent-declared", 1, 1,
                  "`spec.ids_are_permanent` is true in %s" % CONFIG_REL)
    else:
        finding("%s: `spec.ids_are_permanent` is %r, not true. A configuration "
                "that disclaims the invariant is a repository that has opted "
                "out of R2 in writing." % (CONFIG_REL, permanent))
        assertion("R2.1", "R2", "ids-permanent-declared", 1, 0,
                  "`spec.ids_are_permanent` is true in %s" % CONFIG_REL)

    # ---- R2.2 every id ever defined is still defined -----------------------
    first_seen = {}
    last_seen = {}
    for version in versions:
        for req in version["reqs"]:
            first_seen.setdefault(req["id"], {"sha": version["sha"],
                                              "req": req})
            last_seen[req["id"]] = {"sha": version["sha"], "req": req}
    retained = 0
    gone = []
    for rid in sorted(historical_ids, key=lambda i: int(i[1:])):
        if rid in current_by_id:
            retained += 1
        else:
            gone.append(rid)
            status = last_seen[rid]["req"]["status"]
            finding("%s: %s was defined at %s (last seen there as %s) and is "
                    "not defined in the spec today. A superseded or withdrawn "
                    "requirement is RETAINED in the file with its marker, so "
                    "no marker rescues a disappearance: every plan, test, "
                    "review finding and PR title citing %s now points at "
                    "nothing."
                    % (spec_rel, rid, last_seen[rid]["sha"], status, rid))
    assertion("R2.2", "R2", "ids-retained", len(historical_ids), retained,
              "every id defined in any of the %d reachable spec versions is "
              "still defined today" % len(versions))

    # ---- R2.3 no sentence moved from one id to another --------------------
    #
    # Examined over EVERY historical id, not only the ones that vanished: an
    # assertion whose loop runs zero times prints a clean line having compared
    # nothing, and that is the shape hollowness takes in a history check.
    current_text_owner = {}
    for req in current:
        current_text_owner.setdefault(req["text"], req["id"])
    not_renumbered = 0
    for rid in sorted(historical_ids, key=lambda i: int(i[1:])):
        old_text = first_seen[rid]["req"]["text"]
        owner = current_text_owner.get(old_text)
        if owner is not None and owner != rid:
            finding("%s: the sentence %s carried at %s is now carried by %s. "
                    "The requirement was renumbered, which is the failure R2 "
                    "names outright: the id is what every plan, test and PR "
                    "title cites, and it now cites a different number for the "
                    "same agreed behaviour."
                    % (spec_rel, rid, first_seen[rid]["sha"], owner))
        else:
            not_renumbered += 1
    assertion("R2.3", "R2", "ids-not-renumbered", len(historical_ids),
              not_renumbered,
              "no requirement's sentence has moved from the id it was agreed "
              "under to a different id")

    # ---- R2.4 no id's meaning was swapped underneath it --------------------
    comparable = [rid for rid in sorted(historical_ids, key=lambda i: int(i[1:]))
                  if rid in current_by_id]
    not_reused = 0
    drifted = []
    for rid in comparable:
        today = current_by_id[rid]
        oldest = first_seen[rid]
        revived = (today["status"] == "active"
                   and any(rid in v["ids"]
                           and any(r["id"] == rid
                                   and r["status"] in ("superseded", "withdrawn")
                                   for r in v["reqs"])
                           for v in versions))
        score = similarity(oldest["req"]["text"], today["text"])
        bad = False
        if revived:
            bad = True
            finding("%s:%d: %s is active today and was superseded or withdrawn "
                    "in a reachable commit. The id was retired and then handed "
                    "out again, which is reuse in its unambiguous form."
                    % (spec_rel, today["line"], rid))
        if score < reuse_floor:
            bad = True
            finding("%s:%d: the sentence under %s shares %.2f of its "
                    "vocabulary with the sentence it carried at %s, below the "
                    "%.2f floor. Refining keeps the id and edits the text; "
                    "this much drift is a different requirement wearing an old "
                    "number. The text is deliberately not quoted here; read it "
                    "with: git show %s:%s"
                    % (spec_rel, today["line"], rid, score, oldest["sha"],
                       reuse_floor, oldest["sha"], spec_git))
        if score < 1.0:
            drifted.append((rid, score, oldest["sha"]))
        if not bad:
            not_reused += 1
    assertion("R2.4", "R2", "ids-not-reused", len(comparable), not_reused,
              "no id was retired and reissued, and no sentence drifted below "
              "the %.2f similarity floor from what was agreed under it"
              % reuse_floor)

    # ---- R8.1 the counter is above every id ever used ---------------------
    all_used = set(int(i[1:]) for i in historical_ids)
    all_used |= set(int(i[1:]) for i in current_by_id)
    below = 0
    for number in sorted(all_used):
        if number < counter:
            below += 1
        else:
            rid = "R%d" % number
            state = (current_by_id[rid]["status"] if rid in current_by_id
                     else "seen only in history")
            finding("%s: `Next requirement id` is R%d, which is not above %s "
                    "(%s). A superseded id is used forever - it is the one "
                    "number that must never be handed out again - and this "
                    "counter will hand it out on the next allocation."
                    % (spec_rel, counter, rid, state))
    assertion("R8.1", "R8", "counter-above-every-id-used", len(all_used), below,
              "`Next requirement id` R%d is strictly above every one of the %d "
              "ids ever used, superseded and withdrawn included"
              % (counter, len(all_used)))

    # ---- R8.2 every added id is recorded in the change log ----------------
    founding = versions[0]
    added = {}
    seen = set(founding["ids"])
    for version in versions[1:]:
        for rid in sorted(version["ids"], key=lambda i: int(i[1:])):
            if rid not in seen:
                added[rid] = version["sha"]
                seen.add(rid)
    if not added:
        unmeasured.append(
            "no id was added to %s after its founding commit %s, so the "
            "allocate-and-record path has never run in this repository. "
            "'0 unrecorded additions' out of 0 additions is not evidence that "
            "recording works - it is an assertion whose loop never executed."
            % (spec_rel, founding["sha"]))
        assertion("R8.2", "R8", "added-ids-recorded-in-changelog", 0, 0,
                  "UNMEASURED - nothing was added after the founding commit")
    else:
        recorded = 0
        for rid in sorted(added, key=lambda i: int(i[1:])):
            if int(rid[1:]) in logged_ids:
                recorded += 1
            else:
                finding("%s: %s was added at %s and no row in the `## Change "
                        "log` table names it. The acceptance row is "
                        "check-acceptance-rows.sh's assertion, not this one; "
                        "what is missing here is the audit join between the id "
                        "and the commit, branch and issue that introduced it, "
                        "so the requirement arrived from nowhere."
                        % (spec_rel, rid, added[rid]))
        assertion("R8.2", "R8", "added-ids-recorded-in-changelog",
                  len(added), recorded,
                  "every id added after the founding commit %s is named in the "
                  "`## Change log` table" % founding["sha"])

    # =======================================================================
    # REPORT
    # =======================================================================
    sys.stdout.write("    spec: %s\n" % spec_rel)
    sys.stdout.write("    spec versions examined: %d (oldest %s, newest %s)\n"
                     % (len(versions), versions[0]["sha"], versions[-1]["sha"]))
    sys.stdout.write("    requirements read from the spec today: %d\n"
                     % len(current))
    sys.stdout.write("    distinct ids ever defined in reachable history: %d\n"
                     % len(historical_ids))
    sys.stdout.write("    spec-home candidates examined: %d, of which living "
                     "specs: %d\n" % (len(candidate_list), len(living)))
    sys.stdout.write("    `Next requirement id`: R%d   reuse floor: %.2f   "
                     "history bound: %d commits\n"
                     % (counter, reuse_floor, max_versions))
    sys.stdout.write("    change-log ids parsed: %d\n" % len(logged_ids))

    for entry in results:
        verdict = "held" if entry["upheld"] == entry["examined"] else "NOT HELD"
        if entry["examined"] == 0:
            verdict = "unmeasured"
        sys.stdout.write("    %-5s %-4s %-34s examined %3d  upheld %3d  %s: %s\n"
                         % (entry["key"], entry["req"], entry["name"],
                            entry["examined"], entry["upheld"], verdict,
                            entry["held"]))
        if entry["note"]:
            sys.stdout.write("          note: %s\n" % entry["note"])

    for text in findings:
        sys.stdout.write("    FINDING  %s\n" % text)
    for text in unmeasured:
        sys.stdout.write("    UNMEASURED  %s\n" % text)

    if drifted:
        sys.stdout.write("    ids whose sentence has been edited since it was "
                         "first committed (a refinement keeps the id and edits "
                         "the text, so this is not itself a finding): %s\n"
                         % ", ".join("%s %.2f@%s" % d for d in drifted))

    sys.stdout.write("    assertions upheld: %d of %d\n"
                     % (sum(1 for e in results
                            if e["examined"] > 0
                            and e["upheld"] == e["examined"]), len(results)))
    sys.stdout.write("    files examined: %d\n" % len(examined_paths))
finally:
    shutil.rmtree(work, ignore_errors=True)

if unmeasured:
    sys.stderr.write(
        "UNMEASURED: at least one of R1, R2 or R8 has no verdict from this "
        "run. Not a pass, whatever else held.\n")
    raise SystemExit(2)
if findings:
    sys.stderr.write(
        "FAIL: the spec's structural invariants do not hold. R1 says one "
        "living spec, R2 says ids are permanent, R8 says the next unused id is "
        "allocated and recorded; the findings above are where one of the three "
        "stopped being true.\n")
    raise SystemExit(1)

sys.stdout.write(
    "PASS: one living spec in the spec home and the config names it; every id "
    "ever defined is still defined, under its own number, meaning what it "
    "meant; and the counter is above every id ever used with every addition "
    "recorded in the change log.\n")
PY
