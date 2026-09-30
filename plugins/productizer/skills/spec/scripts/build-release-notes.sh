#!/usr/bin/env bash
# build-release-notes.sh [repo-root] [--since TAG] [--version VERSION]
# build-release-notes.sh --selftest | --help
#
# Stage 8 says release notes are drafted from the spec deltas and the merged
# PRs, not from memory. This assembles the evidence for that draft and states
# plainly which of those sources was actually available - because "drafted from
# the spec" and "drafted from the commit subjects because there is no spec" are
# different claims, and only one of them is usually true.
#
# It does NOT write the prose. It produces the material a person or an agent
# writes from, with every item carrying its source. Anything it could not find
# is named as missing rather than quietly omitted, so the writer knows what
# they are working without.
#
# All three sources are bounded by the SAME range. A merged pull request belongs
# to this release when the commit it merged as is one of the commits in the
# range, so the section cannot credit another release's work to this one; and
# when tags exist but none is reachable from HEAD, so there is no previous
# release to bound the range with, stdout names that rather than presenting the
# whole history as if it were one release's worth.
#
# EXIT CODES ARE THE CONTRACT.
#   0  the evidence was assembled and printed - including the sections that
#      honestly read "none" or "unknown" - or --help was asked for.
#   2  usage, refused before any section is printed: an option this tool does
#      not know, --since or --version with no value, a repo-root that cannot be
#      entered, or a --since that does not name a commit in the repository.
#   3  there is no history to read: the root is not a git work tree, or it is
#      one with no commit yet.
# Nothing else is returned by design. An unresolvable --since used to exit 128
# from deep inside the commit section, AFTER stdout had already said "no
# requirement changed in this range" about a range nobody could read; a repo
# with no commit did the same. Both are refused up front now. A git failure
# nobody anticipated would still surface as git's own code under `set -e`, and
# that would be a defect in this file, not a code in this contract.
#
# --selftest (also --self-test) builds real git repositories under `mktemp -d`,
# drives this file over them as a subprocess, and asserts each case's exit code
# AND a sentence in its output. Its own exit: 0 every case held and every
# documented code was reached, 1 a case did not hold or a documented code was
# never reached, 2 it could not run (no temporary directory, or a tool it
# builds the sandbox from is missing).
set -euo pipefail

# Resolved before anything cds anywhere, because the self-test drives its
# cases through this same file and `$0` is relative for most callers.
SELF="$(cd -P "$(dirname "$0")" && pwd -P)/$(basename "$0")"

ROOT="."; SINCE=""; VERSION=""; SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --since)   [ -n "${2:-}" ] || { echo "build-release-notes: --since needs a tag or commit" >&2; exit 2; }
               SINCE="$2"; shift 2 ;;
    --version) [ -n "${2:-}" ] || { echo "build-release-notes: --version needs a version" >&2; exit 2; }
               VERSION="$2"; shift 2 ;;
    --selftest|--self-test) SELFTEST=1; shift ;;
    -h|--help) echo "usage: build-release-notes.sh [repo-root] [--since TAG] [--version V] | --selftest"; exit 0 ;;
    -*)        echo "build-release-notes: unknown option: $1" >&2; exit 2 ;;
    *)         ROOT="$1"; shift ;;
  esac
done

# ---------------------------------------------------------------------------
# --selftest: drive the whole exit-code contract over throwaway repositories.
#
# Every case asserts the exit code AND at least one sentence of the output,
# because a case that checks only the code goes green when the tool exits the
# right number for the wrong reason. A sentence prefixed `!` must NOT appear.
#
# THE SANDBOX IS HERMETIC. No user or system git config is read (a signing or
# log-format setting would change the output), git discovery stops at the
# scratch directory, and the tool runs on a PATH of symlinks to exactly the
# commands it uses - with a stub `gh` or with none - so the PR section is a
# fixture, never a network call.
# ---------------------------------------------------------------------------
if [ "$SELFTEST" -eq 1 ]; then
  SCRATCH="$(mktemp -d)" || { echo "build-release-notes: cannot create a temporary directory, so no case was driven" >&2; exit 2; }
  trap 'rm -rf "$SCRATCH"' EXIT HUP INT TERM

  mkdir -p "$SCRATCH/home"
  printf '[init]\n\tdefaultBranch = main\n' > "$SCRATCH/gitconfig"
  export HOME="$SCRATCH/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig"
  export GIT_CEILING_DIRECTORIES="$SCRATCH"
  export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
  export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid

  NOGH="$SCRATCH/bin-no-gh"; WITHGH="$SCRATCH/bin-stub-gh"
  mkdir -p "$NOGH" "$WITHGH"
  for t in dirname basename git grep sort sed wc tr tail; do
    p="$(type -P "$t")" || { echo "build-release-notes: $t is not on PATH, so the self-test cannot build its sandbox" >&2; exit 2; }
    ln -s "$p" "$NOGH/$t"; ln -s "$p" "$WITHGH/$t"
  done
  # The stub answers in the shape the real `--jq` asks for - a merge-commit oid,
  # then the line - and it reads the oids out of the repository it is standing
  # in, so the fixtures are REAL commits on real sides of the range. `scoped`
  # therefore asserts that the tool applied the range; it cannot pass because the
  # stub happened to know one.
  cat > "$WITHGH/gh" <<'GHSTUB'
#!/bin/sh
case "${GH_STUB:-}" in
  prs)  echo "$(git rev-parse HEAD) #7 fixture pull request" ;;
  fail) echo "gh stub: authentication failed" >&2; exit 1 ;;
  scoped)
    echo "$(git rev-parse HEAD) #7 fixture PR merged inside the range"
    echo "$(git rev-parse 'v1.1.0^{commit}') #9 fixture PR merged earlier in the range"
    echo "$(git rev-parse 'v1.0.0^{commit}') #5 fixture PR merged AS the range start"
    echo "0000000000000000000000000000000000000000 #6 fixture PR merged on another branch"
    echo "unplaceable #4 fixture PR with no merge commit"
    ;;
  flood)
    i=1
    while [ "$i" -le 50 ]; do
      echo "$(git rev-parse HEAD) #$i fixture PR at the cap"
      i=$((i + 1))
    done ;;
esac
GHSTUB
  chmod +x "$WITHGH/gh"

  commit() { # commit <repo> <subject>
    git -C "$1" add -A
    git -C "$1" commit -q -m "$2"
  }

  # repo-tagged: a spec, two annotated version tags, and a commit after the last.
  TAGGED="$SCRATCH/repo-tagged"
  mkdir -p "$TAGGED/.claude/productizer"
  git init -q "$TAGGED"
  printf '# spec\n\n- **R1** - The lifecycle shall draft notes from evidence.\n' \
    > "$TAGGED/.claude/productizer/spec.md"
  commit "$TAGGED" "v1.0.0 - first release"
  git -C "$TAGGED" tag -a v1.0.0 -m "v1.0.0 - first release"
  printf '# spec\n\n- **R1** - The lifecycle shall draft release notes from evidence only.\n- **R2** - The lifecycle shall name a missing source.\n' \
    > "$TAGGED/.claude/productizer/spec.md"
  commit "$TAGGED" "v1.1.0 - R1 refined and R2 added"
  git -C "$TAGGED" tag -a v1.1.0 -m "v1.1.0 - R1 refined and R2 added"
  echo "readme" > "$TAGGED/README.md"
  commit "$TAGGED" "v1.1.1 - readme only"

  # repo-untagged: no tag and no spec.
  UNTAGGED="$SCRATCH/repo-untagged"
  mkdir -p "$UNTAGGED"
  git init -q "$UNTAGGED"
  echo "one" > "$UNTAGGED/a.txt"; commit "$UNTAGGED" "v0.1.0 - untagged start"
  echo "two" > "$UNTAGGED/a.txt"; commit "$UNTAGGED" "v0.2.0 - untagged follow-up"

  # repo-tag-unreachable: one tagged commit, then an orphan root. `git tag -l` is
  # not empty, so describe runs, and it fails with `No tags can describe` - the
  # state where the range silently became the whole history.
  UNREACHABLE="$SCRATCH/repo-tag-unreachable"
  mkdir -p "$UNREACHABLE"
  git init -q "$UNREACHABLE"
  echo "tagged" > "$UNREACHABLE/a.txt"; commit "$UNREACHABLE" "v1.0.0 - the tagged commit"
  git -C "$UNREACHABLE" tag -a v1.0.0 -m "v1.0.0 - the tagged commit"
  git -C "$UNREACHABLE" checkout -q --orphan work-on-a-new-root
  git -C "$UNREACHABLE" rm -q -f a.txt
  echo "orphan" > "$UNREACHABLE/b.txt"; commit "$UNREACHABLE" "v0.0.1 - on a root no tag names"

  EMPTY="$SCRATCH/repo-no-commit"
  git init -q "$EMPTY"
  NOTGIT="$SCRATCH/not-a-repo"
  mkdir -p "$NOTGIT"

  DOCUMENTED="0 2 3"
  CASES=0; UPHELD=0; REPORT=""; CODES=""

  drive() { # drive <name> <expected> <bin> <gh-stub-mode> <sentences> [argv...]
    name="$1"; expected="$2"; bin="$3"; ghmode="$4"; want="$5"; shift 5
    got=0
    env PATH="$bin" GH_STUB="$ghmode" "$BASH" "$SELF" "$@" \
      > "$SCRATCH/$name.out" 2> "$SCRATCH/$name.err" || got=$?
    cat "$SCRATCH/$name.out" "$SCRATCH/$name.err" > "$SCRATCH/$name.all"
    CASES=$((CASES + 1))
    CODES="$CODES$got
"
    why=""
    [ "$got" = "$expected" ] || why="exited $got"
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      case "$s" in
        '!'*) if grep -Fq -- "${s#!}" "$SCRATCH/$name.all"; then why="${why:+$why; }printed what it must not: ${s#!}"; fi ;;
        *)    grep -Fq -- "$s" "$SCRATCH/$name.all" || why="${why:+$why; }missing sentence: $s" ;;
      esac
    done <<EOF
$want
EOF
    if [ -z "$why" ]; then
      UPHELD=$((UPHELD + 1))
      REPORT="$REPORT      $name  expected $expected  got $got  held
"
    else
      REPORT="$REPORT      $name  expected $expected  got $got  NOT HELD: $why
"
    fi
  }

  # --- 0: the evidence is assembled ----------------------------------------
  drive range-since 0 "$NOGH" "" 'Range: `v1.0.0..HEAD`  (since v1.0.0)
Version: `1.1.1`
Requirement ids added or changed in this range:
  - R1
  - R2
2 commit(s):
  - v1.1.1 - readme only
  - v1.1.0 - R1 refined and R2 added
!  - v1.0.0 - first release
`gh` is not installed, so no PR could be read.' "$TAGGED" --since v1.0.0 --version 1.1.1

  drive nearest-tag-no-delta 0 "$NOGH" "" 'Range: `v1.1.0..HEAD`  (since v1.1.0)
The spec exists but no requirement changed in this range.
!Requirement ids added or changed
1 commit(s):
  - v1.1.1 - readme only
!Version:' "$TAGGED"

  drive untagged-no-spec 0 "$NOGH" "" 'Range: `HEAD`
!(since
There is no living spec at
2 commit(s):
  - v0.1.0 - untagged start
!which release this follows
!could not name one that is reachable' "$UNTAGGED"

  # B72. The range reads `HEAD` here exactly as it does above, and the reason is
  # not the same one: there the whole history IS the range, here the range could
  # not be found. stdout has to carry that difference, not only stderr.
  drive tag-unreachable 0 "$NOGH" "" 'Range: `HEAD`
!(since
**Unknown — which release this follows. This repository has tags, but `git
describe` could not name one that is reachable from HEAD, so the range above
Pass `--since` to bound the range.**
1 commit(s):
  - v0.0.1 - on a root no tag names' "$UNREACHABLE"

  drive empty-range 0 "$NOGH" "" 'Range: `HEAD..HEAD`
is empty' "$TAGGED" --since HEAD

  drive gh-lists-prs 0 "$WITHGH" prs '  - #7 fixture pull request
!is not installed
!None found' "$UNTAGGED"

  # B71. Five merged pull requests come back: two on commits `v1.0.0..HEAD`
  # contains, one on the range's own start commit which the range EXCLUDES, one
  # on a commit this repository does not have, and one GitHub reports no merge
  # commit for. Only the first two belong in these notes, and the last is named
  # rather than dropped.
  drive gh-scopes-prs 0 "$WITHGH" scoped '  - #7 fixture PR merged inside the range
  - #9 fixture PR merged earlier in the range
**Unknown for 1 of them — GitHub reported no merge commit, so whether they
!#5 fixture PR merged AS the range start
!#6 fixture PR merged on another branch
!None found' "$TAGGED" --since v1.0.0

  # The cap is GitHub's and is applied before the range filter, so a range that
  # fills it is a range this cannot claim to have read all of.
  drive gh-at-the-cap 0 "$WITHGH" flood '**Possibly incomplete — the read is capped at 50 merged pull requests and
returned 50, so one in this range but older than those is not listed here.**
  - #1 fixture PR at the cap
!None found' "$UNTAGGED"

  drive gh-finds-none 0 "$WITHGH" "" '**None found.**
!failed, so no PR could be read' "$UNTAGGED"

  drive gh-fails 0 "$WITHGH" fail '`gh pr list` failed, so no PR could be read.
!None found' "$UNTAGGED"

  drive help 0 "$NOGH" "" 'usage: build-release-notes.sh' --help

  # --- 2: usage, refused before any section is printed ---------------------
  drive unknown-option 2 "$NOGH" "" 'unknown option: --nope
!## Spec deltas' "$TAGGED" --nope

  drive since-without-value 2 "$NOGH" "" '--since needs a tag or commit
!## Spec deltas' "$TAGGED" --since

  drive version-without-value 2 "$NOGH" "" '--version needs a version
!## Spec deltas' "$TAGGED" --version

  drive no-such-directory 2 "$NOGH" "" 'no such directory:
!## Spec deltas' "$SCRATCH/absent-root"

  drive since-unresolvable 2 "$NOGH" "" 'does not name a commit
!no requirement changed
!## Spec deltas' "$TAGGED" --since v9.9.9

  # --- 3: no history to read -----------------------------------------------
  drive not-a-git-repo 3 "$NOGH" "" 'not a git repository:
!## Spec deltas' "$NOTGIT"

  drive no-commit 3 "$NOGH" "" 'has no commit
!## Spec deltas' "$EMPTY"

  # --- the assertions ------------------------------------------------------
  [ "$CASES" -gt 0 ] || { echo "build-release-notes: no case was driven, so nothing was measured" >&2; exit 2; }

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"

  REACHED="$(printf '%s' "$CODES" | sort -un | tr '\n' ' ' | sed 's/ *$//')"
  MISSING=""
  for want in $DOCUMENTED; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: %s\n' "$REACHED" "$DOCUMENTED"

  if [ "$CASES" = "$UPHELD" ]; then CASE_VERDICT="held"; else CASE_VERDICT="NOT HELD"; fi
  printf '    R39.a  %-40s examined %3d  upheld %3d  %s\n' \
    "each-case-exits-the-declared-code-and-says-why" "$CASES" "$UPHELD" "$CASE_VERDICT"
  NDOC="$(printf '%s' "$DOCUMENTED" | wc -w | tr -d ' ')"
  if [ -n "$MISSING" ]; then CODE_VERDICT="NOT HELD"; else CODE_VERDICT="held"; fi
  printf '    R39.b  %-40s examined %3d  upheld %3d  %s\n' \
    "every-documented-exit-code-reached" "$NDOC" "$((NDOC - $(printf '%s' "$MISSING" | wc -w | tr -d ' ')))" "$CODE_VERDICT"
  [ -z "$MISSING" ] || echo "build-release-notes: documented exit code(s) never reached by any case:$MISSING" >&2

  printf '    NOT ASSERTED: the PR section is a stub, never a real gh call, so the shape of real gh output is not tested here - that `mergeCommit.oid` is a full 40-character sha was read from a real repository out of band, and no case would notice if GitHub stopped sending it; a squash and a rebase merge are asserted only through the oid the stub hands back, never against a repository that merged either way; the self-test own exit 2 is a guard no case drives.\n'

  [ "$CASE_VERDICT" = "held" ] && [ "$CODE_VERDICT" = "held" ] || exit 1
  exit 0
fi

cd "$ROOT" || { echo "no such directory: $ROOT" >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null || { echo "not a git repository: $ROOT" >&2; exit 3; }
git rev-parse --verify --quiet HEAD >/dev/null \
  || { echo "build-release-notes: $ROOT has no commit, so there is no history to assemble notes from" >&2; exit 3; }
if [ -n "$SINCE" ] && ! git rev-parse --verify --quiet "$SINCE^{commit}" >/dev/null; then
  echo "build-release-notes: --since $SINCE does not name a commit in this repository; refusing rather than reporting on a range that could not be read" >&2
  exit 2
fi

# `git describe` writes `fatal: No names found, cannot describe anything.` when the repo has no
# tags at all - normal before a first release. Ask whether a tag exists first, so describe only
# runs when it can succeed and a failure it does report (tags present, none reachable from HEAD)
# is a real one worth reading.
NO_TAG_REACHABLE=0
if [ -z "$SINCE" ] && [ -n "$(git tag -l)" ]; then
  SINCE="$(git describe --tags --abbrev=0 || echo "")"
  # Tags exist and describe still could not name one: none of them is reachable
  # from HEAD. Its reason is on stderr, and stdout has to say it too, or every
  # section below reads exactly like a bounded range that happens to be long.
  # Not an error - the evidence is still assembled, with the gap named.
  [ -n "$SINCE" ] || NO_TAG_REACHABLE=1
fi
RANGE="${SINCE:+$SINCE..}HEAD"
SPEC=".claude/productizer/spec.md"
PR_LIMIT=50

say() { printf '%s\n' "$*"; }

say "# Release notes — evidence"
say ""
say "Range: \`${RANGE}\`${SINCE:+  (since $SINCE)}"
[ -n "$VERSION" ] && say "Version: \`$VERSION\`"
if [ "$NO_TAG_REACHABLE" -eq 1 ]; then
  say ""
  say "**Unknown — which release this follows. This repository has tags, but \`git"
  say "describe\` could not name one that is reachable from HEAD, so the range above"
  say "is the whole history and not one release's worth of it. describe's own reason"
  say "is on stderr. Pass \`--since\` to bound the range.**"
fi
say ""

# --- source 1: the spec ------------------------------------------------------
say "## Spec deltas"
say ""
if [ ! -f "$SPEC" ]; then
  say "**None. There is no living spec at \`$SPEC\`.**"
  say ""
  say "Stage 8 says notes are drafted from the spec deltas. Without a spec there"
  say "are none, so anything written here is drawn from commit subjects instead."
  say "That is a weaker source and the draft should say so rather than implying"
  say "the requirements were consulted."
else
  # Requirement ids touched in this range, from the spec's own diff.
  ids="$(git log "$RANGE" -p -- "$SPEC" \
        | grep -E '^\+.*\*\*R[0-9]+\*\*' | grep -oE 'R[0-9]+' | sort -u -V || true)"
  if [ -z "$ids" ]; then
    say "The spec exists but no requirement changed in this range."
  else
    say "Requirement ids added or changed in this range:"
    say ""
    printf '%s\n' "$ids" | sed 's/^/  - /'
  fi
fi
say ""

# --- source 2: merged PRs ----------------------------------------------------
say "## Merged pull requests"
say ""
if ! command -v gh >/dev/null 2>&1; then
  say "**Unknown — \`gh\` is not installed, so no PR could be read.**"
  say "This is not the same as \"no PRs merged\"; nobody looked."
else
  # A gh auth or network failure also comes back empty. Reading the exit code keeps it from
  # reaching the "None found" branch, which would announce an absence that was not an absence.
  if raw="$(gh pr list --state merged --limit "$PR_LIMIT" --json number,title,mergeCommit \
           --jq '.[] | "\(.mergeCommit.oid // "unplaceable") #\(.number) \(.title)"')"; then
    # The range is applied HERE, by commit, and not by date. GitHub's `merged:`
    # search qualifiers do filter correctly - measured against a real repository:
    # `merged:>` is strict, `merged:<=` is inclusive, and a stamp's offset is
    # honoured rather than ignored - but their bounds would have to be the
    # range's commit dates, and in THIS repository those are equal: v4.59.0 and
    # v4.60.0 both read 2026-09-14T07:00:00-04:00, so the window for
    # `v4.59.0..HEAD` is empty and every pull request in it would come back as
    # "None found". An absence that was not an absence is the one thing this
    # section must never print, so the bound that decides is the range's own
    # commit list. `mergeCommit` is the commit a PR merged as under all three
    # merge strategies - a merge commit, a squash's single commit, or the tip of
    # a rebase - and the job that calls this checks out the full history, so the
    # oid is there to test. A pull request GitHub reports no merge commit for
    # cannot be placed either way and is counted, never dropped in silence.
    fetched=0; unplaceable=0; kept=""
    range_commits="$(git rev-list "$RANGE")"
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      fetched=$((fetched + 1))
      oid="${row%% *}"
      if [ "$oid" = unplaceable ]; then
        unplaceable=$((unplaceable + 1))
        continue
      fi
      printf '%s\n' "$range_commits" | grep -qxF "$oid" || continue
      kept="$kept  - ${row#* }
"
    done <<PULLS
$raw
PULLS
    # The read is capped, and the cap is applied by GitHub BEFORE this filter
    # runs. A repository that merges more than the cap between releases would
    # have the older half of its range cut off by the cap rather than by the
    # range, and a short list would look like a complete one.
    if [ "$fetched" -ge "$PR_LIMIT" ]; then
      say "**Possibly incomplete — the read is capped at $PR_LIMIT merged pull requests and"
      say "returned $fetched, so one in this range but older than those is not listed here.**"
      say ""
    fi
    if [ "$unplaceable" -gt 0 ]; then
      say "**Unknown for $unplaceable of them — GitHub reported no merge commit, so whether they"
      say "belong to this range could not be decided. They are neither listed nor dismissed.**"
      say ""
    fi
    if [ -z "$kept" ]; then
      say "**None found.** Either nothing was merged through a PR in this range, or"
      say "the work went straight to the branch. If it went straight to the branch,"
      say "the notes have no PR to trace a claim to and should say so."
    else
      printf '%s' "$kept"
    fi
  else
    say "**Unknown — \`gh pr list\` failed, so no PR could be read.**"
    say "Its error is on stderr. This is not the same as \"no PRs merged\"; the read did not succeed."
  fi
fi
say ""

# --- source 3: the commits ---------------------------------------------------
say "## Commits in range"
say ""
n="$(git log --oneline "$RANGE" | wc -l | tr -d ' ')"
if [ "$n" = "0" ]; then
  say "**None.** \`$RANGE\` is empty — there is nothing to release."
else
  say "$n commit(s):"
  say ""
  git log "$RANGE" --pretty=format:'  - %s  (`%h`)'
  say ""
  say ""
  say "### Files changed"
  say ""
  say '```'
  git diff --stat "$RANGE" | tail -20
  say '```'
fi
say ""

# --- the checklist the writer must not skip ---------------------------------
say "## Before this becomes a post"
say ""
say "Each line is a \`no\` that stops it, not a comment."
say ""
say "- [ ] Every claim traces to a commit, a merged PR, or a requirement id above."
say "- [ ] Every number was measured, and the measurement is stated."
say "- [ ] Every screenshot came from THIS version's build."
say "- [ ] The version named is live and installable, and that was verified."
say "- [ ] No customer, repo, internal hostname or employer name appears anywhere."
say "- [ ] The release names what it does NOT do."
say "- [ ] Names and bylines of anyone credited are correct."
say ""
say "Where a source above says **none** or **unknown**, the draft says so too."
say "A note written from commit subjects while implying it was written from the"
say "spec is the kind of claim this lifecycle exists to prevent."
