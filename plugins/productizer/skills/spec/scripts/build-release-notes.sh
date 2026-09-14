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
  {
    echo '#!/bin/sh'
    echo 'case "${GH_STUB:-}" in'
    echo '  prs)  echo "  - #7 fixture pull request" ;;'
    echo '  fail) echo "gh stub: authentication failed" >&2; exit 1 ;;'
    echo 'esac'
  } > "$WITHGH/gh"
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
  - v0.1.0 - untagged start' "$UNTAGGED"

  drive empty-range 0 "$NOGH" "" 'Range: `HEAD..HEAD`
is empty' "$TAGGED" --since HEAD

  drive gh-lists-prs 0 "$WITHGH" prs '  - #7 fixture pull request
!is not installed
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
  NDOC="$(printf '%s\n' $DOCUMENTED | wc -l | tr -d ' ')"
  if [ -n "$MISSING" ]; then CODE_VERDICT="NOT HELD"; else CODE_VERDICT="held"; fi
  printf '    R39.b  %-40s examined %3d  upheld %3d  %s\n' \
    "every-documented-exit-code-reached" "$NDOC" "$((NDOC - $(printf '%s' "$MISSING" | wc -w | tr -d ' ')))" "$CODE_VERDICT"
  [ -z "$MISSING" ] || echo "build-release-notes: documented exit code(s) never reached by any case:$MISSING" >&2

  printf '    NOT ASSERTED: the PR section is a stub, never a real gh call, so the shape of real gh output is not tested here; the self-test own exit 2 is a guard no case drives; a tag present but unreachable from HEAD is not a case.\n'

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
if [ -z "$SINCE" ] && [ -n "$(git tag -l)" ]; then
  SINCE="$(git describe --tags --abbrev=0 || echo "")"
fi
RANGE="${SINCE:+$SINCE..}HEAD"
SPEC=".claude/productizer/spec.md"

say() { printf '%s\n' "$*"; }

say "# Release notes — evidence"
say ""
say "Range: \`${RANGE}\`${SINCE:+  (since $SINCE)}"
[ -n "$VERSION" ] && say "Version: \`$VERSION\`"
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
  if prs="$(gh pr list --state merged --limit 50 --json number,title,mergedAt \
           --jq '.[] | "  - #\(.number) \(.title)"')"; then
    if [ -z "$prs" ]; then
      say "**None found.** Either nothing was merged through a PR in this range, or"
      say "the work went straight to the branch. If it went straight to the branch,"
      say "the notes have no PR to trace a claim to and should say so."
    else
      printf '%s\n' "$prs"
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
