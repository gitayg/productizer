#!/usr/bin/env bash
# spec-diff.sh [repo-root] [--base REF] [--format text|prompt]
#              [--selftest] [--version] [--help]
#
# The living spec keeps every requirement id for ever, and a superseded or
# withdrawn requirement keeps its original sentence in place. That invariant is
# what makes the spec a record rather than a snapshot - and it is also what
# hides a removal from Stage 3. Handed only the current spec, the Build stage
# reads a document the existing code already satisfies, finds nothing to do,
# and the dropped behaviour survives in the code.
#
# So Build is handed the spec *and* how the spec moved. This assembles the
# second half: the diff of the living spec and the constitution between a base
# ref and HEAD, fenced so it can be pasted into the Build prompt, followed by
# the instruction to reconcile the code with the change rather than with the
# current text.
#
# Nothing here is rendered as an empty success. "The spec did not change", "the
# file is new and has no baseline" and "the base ref does not resolve" are three
# different answers leading to three different actions; an empty diff would read
# as the first one in all three cases, so each has its own message and its own
# exit code.
#
# Exit: 0 a diff was emitted
#       2 usage
#       3 not a git repository, or no such directory
#       4 the files are unchanged against the base - nothing to reconcile
#       5 no baseline - no commits, or the files are new / absent at the base
#       6 the base ref does not resolve
#       7 the diff exceeds the cap; the run must work from the spec alone
#
# --selftest builds real repositories under mktemp -d and runs every case from
# the repo root, from two nested subdirectories and with an explicit
# subdirectory argument, and requires the same stdout and exit code from all
# four. It exits 0 when every case held and 1 when one did not.
set -euo pipefail

VERSION="spec-diff 1.0"
SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"

# A spec edit is small. Anything larger is not a spec edit, and a truncated diff
# pasted into a prompt is worse than no diff at all - it reads as complete. Same
# order of magnitude as the AI Unified Process workflow this is adapted from.
DIFF_MAX_CHARS=20000

ROOT=""
BASE=""
FORMAT=text
SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base)     BASE="${2:-}"; [ -n "$BASE" ] || { echo "spec-diff: --base needs a ref" >&2; exit 2; }; shift 2 ;;
    --base=*)   BASE="${1#--base=}"; [ -n "$BASE" ] || { echo "spec-diff: --base needs a ref" >&2; exit 2; }; shift ;;
    --format)   FORMAT="${2:-}"; [ -n "$FORMAT" ] || { echo "spec-diff: --format needs text or prompt" >&2; exit 2; }; shift 2 ;;
    --format=*) FORMAT="${1#--format=}"; shift ;;
    --version)  echo "$VERSION"; exit 0 ;;
    --selftest|--self-test) SELFTEST=1; shift ;;
    -h|--help)  echo "usage: spec-diff.sh [repo-root] [--base REF] [--format text|prompt]"
                echo "       spec-diff.sh --selftest | --version | --help"; exit 0 ;;
    -*)         echo "spec-diff: unknown option: $1" >&2; exit 2 ;;
    *)          [ -z "$ROOT" ] || { echo "spec-diff: only one repo-root" >&2; exit 2; }; ROOT="$1"; shift ;;
  esac
done

# ===========================================================================
# SELF-TEST. Real repositories under mktemp -d, no network. Each placement
# case runs four ways - from the repo root, from src/deep, from src/deep/er,
# and from outside the repo with src/deep as the explicit repo-root - and holds
# only when all four give the root run's exit code and byte-identical stdout,
# and the root run's output carries the case's sentence. That is the property
# references/build-diff.md claims: the answer does not depend on where the
# script was run from.
# ===========================================================================
selftest() {
  # Global, not local: the EXIT trap runs after this function has returned.
  ST="$(mktemp -d)" || { echo "spec-diff: cannot create a temporary directory for the self-test" >&2; exit 2; }
  trap 'rm -rf "$ST"' EXIT
  export GIT_CEILING_DIRECTORIES="$ST"
  local CASES=0 HELD=0 CODES="" DIVERGED=0

  G() { git -C "$1" -c user.email=selftest@example.invalid -c user.name=selftest \
          -c commit.gpgsign=false "${@:2}"; }
  # newrepo <name> [nospec]: a repository on main with src/deep/er, and - unless
  # nospec - a spec holding R1 and a constitution, committed and tagged `base`.
  newrepo() {
    local R="$ST/$1"
    mkdir -p "$R/.claude/productizer" "$R/src/deep/er"
    G "$R" init --quiet --initial-branch=main
    printf 'keep\n' > "$R/src/deep/er/keep"
    if [ "${2:-}" != nospec ]; then
      printf '# Spec\n\n## Requirements\n\n- **R1** \342\200\224 The tool shall greet.\n' \
        > "$R/.claude/productizer/spec.md"
      printf '# Constitution\n\n1. Small steps.\n' > "$R/.claude/productizer/constitution.md"
    fi
    G "$R" add -A
    G "$R" commit --quiet -m base
    G "$R" tag base
  }
  commit() { G "$1" add -A; G "$1" commit --quiet -m change; }

  placed() { # placed <name> <want> <text> <repo> [args...]
    local name="$1" want="$2" text="$3" R="$4"; shift 4
    local i got rc1="" off=0
    for i in 1 2 3 4; do
      got=0
      case "$i" in
        1) ( cd "$R" && bash "$SELF" "$@" ) >"$ST/$name.$i.out" 2>"$ST/$name.$i.err" || got=$? ;;
        2) ( cd "$R/src/deep" && bash "$SELF" "$@" ) >"$ST/$name.$i.out" 2>"$ST/$name.$i.err" || got=$? ;;
        3) ( cd "$R/src/deep/er" && bash "$SELF" "$@" ) >"$ST/$name.$i.out" 2>"$ST/$name.$i.err" || got=$? ;;
        4) ( cd "$ST" && bash "$SELF" "$R/src/deep" "$@" ) >"$ST/$name.$i.out" 2>"$ST/$name.$i.err" || got=$? ;;
      esac
      if [ "$i" = 1 ]; then rc1="$got"
      elif [ "$got" != "$rc1" ] || ! cmp -s "$ST/$name.1.out" "$ST/$name.$i.out"; then off=$((off + 1)); fi
    done
    CASES=$((CASES + 1)); CODES="$CODES $rc1"
    [ "$off" -eq 0 ] || DIVERGED=$((DIVERGED + 1))
    if [ "$rc1" = "$want" ] && [ "$off" -eq 0 ] && grep -qF -- "$text" "$ST/$name.1.out" "$ST/$name.1.err"; then
      HELD=$((HELD + 1))
      printf '  ok    %-34s exit %s, identical from all 4 placements\n' "$name" "$rc1"
    else
      printf '  FAIL  %-34s exit %s (wanted %s), %s of 3 other placements diverged, text: %s\n' \
        "$name" "$rc1" "$want" "$off" "$text"
      head -n 8 "$ST/$name.1.out" | sed 's/^/          stdout: /'
      head -n 8 "$ST/$name.1.err" | sed 's/^/          stderr: /'
    fi
  }
  single() { # single <name> <want> <text> <dir> [args...]
    local name="$1" want="$2" text="$3" D="$4"; shift 4
    local got=0
    ( cd "$D" && bash "$SELF" "$@" ) >"$ST/$name.out" 2>"$ST/$name.err" || got=$?
    CASES=$((CASES + 1)); CODES="$CODES $got"
    if [ "$got" = "$want" ] && grep -qF -- "$text" "$ST/$name.out" "$ST/$name.err"; then
      HELD=$((HELD + 1)); printf '  ok    %-34s exit %s\n' "$name" "$got"
    else
      printf '  FAIL  %-34s exit %s (wanted %s and the text: %s)\n' "$name" "$got" "$want" "$text"
      head -n 8 "$ST/$name.out" | sed 's/^/          stdout: /'
      head -n 8 "$ST/$name.err" | sed 's/^/          stderr: /'
    fi
  }

  printf 'spec-diff self-test\n\n'
  local R

  newrepo changed; R="$ST/changed"
  printf -- '- **R2** \342\200\224 The tool shall wave.\n' >> "$R/.claude/productizer/spec.md"
  commit "$R"
  placed spec-changed 0 "spec.md\` - changed against \`base\`" "$R" --base base

  newrepo const-only; R="$ST/const-only"
  printf '2. Say why.\n' >> "$R/.claude/productizer/constitution.md"
  commit "$R"
  placed constitution-only-changed 0 "constitution.md\` - changed against \`base\`" "$R" --base base

  newrepo default-base; R="$ST/default-base"
  G "$R" switch --quiet -c feature
  printf -- '- **R2** \342\200\224 The tool shall wave.\n' >> "$R/.claude/productizer/spec.md"
  commit "$R"
  placed default-branch-as-base 0 "(default branch," "$R"

  newrepo unchanged; R="$ST/unchanged"
  printf 'other\n' > "$R/src/deep/er/other"
  commit "$R"
  placed unchanged 4 "this is a measured absence of change, not a missing baseline" "$R" --base base

  newrepo new-file nospec; R="$ST/new-file"
  printf '# Spec\n\n## Requirements\n\n- **R1** \342\200\224 The tool shall greet.\n' \
    > "$R/.claude/productizer/spec.md"
  commit "$R"
  placed new-no-baseline 5 "spec.md\` - new, no baseline" "$R" --base base

  newrepo absent nospec; R="$ST/absent"
  printf 'other\n' > "$R/src/deep/er/other"
  commit "$R"
  placed absent-at-both-ends 5 "The file is tracked at neither" "$R" --base base

  R="$ST/no-commits"; mkdir -p "$R/src/deep/er"
  G "$R" init --quiet --initial-branch=main
  placed no-commits 5 "this repository has no commits" "$R"

  newrepo bad-base; R="$ST/bad-base"
  placed base-does-not-resolve 6 "the base ref does not resolve: no-such-ref" "$R" --base no-such-ref

  newrepo over-cap; R="$ST/over-cap"
  awk 'BEGIN { for (i = 1; i <= 400; i++) printf "- **R%d** \342\200\224 The tool shall do thing number %d, padded to length.\n", i + 1, i }' \
    >> "$R/.claude/productizer/spec.md"
  commit "$R"
  placed over-the-cap 7 "over the 20000 cap, and is **not included**" "$R" --base base

  R="$ST/changed"
  single prompt-format 0 "### Reconcile against the change, not the current text" "$R" --base base --format prompt
  CASES=$((CASES + 1)); CODES="$CODES 0"
  if grep -q '^# Spec diff' "$ST/prompt-format.out"; then
    printf '  FAIL  %-34s the human header leaked into the prompt block\n' "prompt-format-has-no-header"
  else
    HELD=$((HELD + 1)); printf '  ok    %-34s exit 0\n' "prompt-format-has-no-header"
  fi
  single bad-format 2 "--format must be text or prompt, not: html" "$R" --format html
  mkdir -p "$ST/plain"
  single not-a-repository 3 "not a git repository" "$ST" "$ST/plain"
  single version 0 "spec-diff 1." "$ST" --version

  printf '\n%s of %s cases held\n' "$HELD" "$CASES"
  printf '    placement cases where a non-root run diverged from the root run: %s\n' "$DIVERGED"
  local reached documented
  reached="$(printf '%s' "$CODES" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  documented="$(awk '/^# Exit:/ { f = 1; sub(/^# Exit:/, "#      ") } f && /^#[[:space:]]+[0-9] / { printf "%s ", $2; next } f { exit }' "$SELF" | sed 's/  *$//')"
  printf '    exit codes reached: %s   documented: %s\n' "$reached" "$documented"
  printf '    NOT ASSERTED: a shallow clone; a base given as a bare commit id; a payload line that begins with a tilde (the fence width rule); TZ independence of the printed date; stderr content beyond the one sentence per case.\n'
  [ "$reached" = "$documented" ] || { printf 'FAIL: reached and documented exit codes differ\n'; return 1; }
  [ "$HELD" -eq "$CASES" ] || return 1
  return 0
}

if [ "$SELFTEST" -eq 1 ]; then
  ST_RC=0
  selftest || ST_RC=$?
  exit "$ST_RC"
fi
case "$FORMAT" in
  text|prompt) ;;
  *) echo "spec-diff: --format must be text or prompt, not: $FORMAT" >&2; exit 2 ;;
esac
[ -n "$ROOT" ] || ROOT="."
cd "$ROOT" || { echo "spec-diff: no such directory: $ROOT" >&2; exit 3; }
git rev-parse --is-inside-work-tree >/dev/null || { echo "spec-diff: not a git repository: $ROOT" >&2; exit 3; }

# Anchor at the repository root before any pathspec is used. `git ls-tree` and
# `git diff` resolve a pathspec against the *current directory*, not against the
# repository, so the same commit read from a subdirectory reported the spec as
# tracked nowhere - a false "absent", delivered with prose calling it a
# considered verdict. A skill script normally runs from its own directory, so
# that was the ordinary case rather than the corner one. The answer must not
# depend on where the script was invoked from, and the repo root is printed
# below so the reader can see which repository was actually read.
TOPLEVEL="$(git rev-parse --show-toplevel)"
cd "$TOPLEVEL"

SPEC=".claude/productizer/spec.md"
CONST=".claude/productizer/constitution.md"

say() { printf '%s\n' "$*"; }

# git's own stderr is kept and reprinted on the failure paths rather than
# discarded. An error and a genuine no-match look identical once hidden, and a
# base ref that failed to resolve for a reason nobody was shown is exactly the
# silent empty diff this script exists to prevent.
ERR="$(mktemp)"
trap 'rm -f "$ERR"' EXIT
show_err() { [ -s "$ERR" ] && cat "$ERR" >&2 || true; }

# --- HEAD ------------------------------------------------------------------
# Checked before the base, because a repository with no commits has no baseline
# at all and saying "the base ref does not resolve" would name the wrong cause.
if ! HEAD_SHA="$(git rev-parse --verify 'HEAD^{commit}' 2>"$ERR")"; then
  show_err
  echo "spec-diff: HEAD does not resolve - this repository has no commits, so there is no baseline to diff against." >&2
  exit 5
fi

# --- base ------------------------------------------------------------------
# The repository's own default branch, tried in the order a real clone carries
# it. A clone made with --single-branch has no origin/HEAD; a repository created
# locally has no origin at all.
BASE_SOURCE="--base"
if [ -z "$BASE" ]; then
  BASE_SOURCE="default branch"
  for cand in "$(git symbolic-ref --short refs/remotes/origin/HEAD 2>"$ERR" || true)" \
              origin/main origin/master main master; do
    [ -n "$cand" ] || continue
    if git rev-parse --verify "$cand^{commit}" >/dev/null 2>"$ERR"; then BASE="$cand"; break; fi
  done
  if [ -z "$BASE" ]; then
    show_err
    echo "spec-diff: no default branch resolves (tried origin/HEAD, origin/main, origin/master, main, master)." >&2
    echo "spec-diff: pass --base REF. Falling back to an empty diff would report 'no changes', which is a different and untrue answer." >&2
    exit 6
  fi
fi
if ! BASE_SHA="$(git rev-parse --verify "$BASE^{commit}" 2>"$ERR")"; then
  show_err
  echo "spec-diff: the base ref does not resolve: $BASE" >&2
  echo "spec-diff: not falling back to an empty diff - that would report 'no changes', which is a different and untrue answer." >&2
  exit 6
fi
# TZ-pinned. The same repository read in two timezones must produce the same
# text, or two runs of the same stage disagree over a date that did not move.
BASE_DATE="$(TZ=UTC git show -s --date=format-local:'%Y-%m-%d %H:%M' --format='%ad' "$BASE_SHA")"

# --- fencing ---------------------------------------------------------------
# Tildes, not backticks: the spec is Markdown and may carry backtick fences of
# its own. Every line of `git diff` output is prefixed by a diff marker - a
# space, +, -, \, or a header word - so no line of the payload can begin with a
# tilde and close the block early. That is argued rather than measured, so the
# width is measured too: one tilde wider than the longest run of leading tildes
# anywhere in the payload. The opening fence then carries a marker derived from
# HEAD's commit id, the same trick the AI Unified Process workflow uses, so the
# block stays identifiable after it is pasted into a larger prompt.
fence_for() { # fence_for <payload> -> a tilde run no payload line can match
  local widest width
  widest="$(awk '{ n = 0; while (substr($0, n + 1, 1) == "~") n++; if (n > m) m = n } END { print m + 0 }' <<<"$1")"
  width=$((widest + 1))
  [ "$width" -ge 3 ] || width=3
  printf '%*s' "$width" '' | tr ' ' '~'
}

# --- per file --------------------------------------------------------------
# 0 emitted · 4 unchanged · 5 no baseline · 7 over the cap. The run's exit is
# the strongest of the per-file outcomes, in that order: one real diff is worth
# emitting even if the other file is new.
RESULT=4
rank() { case "$1" in 0) echo 3 ;; 7) echo 2 ;; 5) echo 1 ;; *) echo 0 ;; esac; }
record() { [ "$(rank "$1")" -gt "$(rank "$RESULT")" ] && RESULT="$1" || true; }

emit_file() { # emit_file <path>
  local path="$1" at_base at_head diff fence
  at_base="$(git ls-tree -r --name-only "$BASE_SHA" -- "$path")"
  at_head="$(git ls-tree -r --name-only "$HEAD_SHA" -- "$path")"

  if [ -z "$at_base" ] && [ -z "$at_head" ]; then
    say "### \`$path\` - absent"
    say ""
    say "The file is tracked at neither \`$BASE\` nor HEAD. There is nothing to diff, and this is not a spec that did not change."
    say ""
    record 5
    return 0
  fi

  if [ -z "$at_base" ]; then
    say "### \`$path\` - new, no baseline"
    say ""
    say "The file does not exist at \`$BASE\` ($BASE_SOURCE), so it has no history to diff against and every line of it is an addition. No diff is fenced below: it would be the file itself, which the Build stage already has. Nothing was removed, because there was nothing there to remove."
    say ""
    record 5
    return 0
  fi

  diff="$(git diff "$BASE_SHA" "$HEAD_SHA" -- "$path")"

  if [ -z "$diff" ]; then
    say "### \`$path\` - unchanged"
    say ""
    say "The file is identical at \`$BASE\` and HEAD. There is no change to reconcile against - this is a measured absence of change, not a missing baseline."
    say ""
    return 0
  fi

  if [ "${#diff}" -gt "$DIFF_MAX_CHARS" ]; then
    say "### \`$path\` - diff too large"
    say ""
    say "The diff against \`$BASE\` is ${#diff} characters, over the $DIFF_MAX_CHARS cap, and is **not included**. It is not truncated either: a cut-off diff reads as a complete one, and the Build stage would treat everything past the cut as unchanged. This run must work from the spec alone, and a removal made in this range will not be visible to it."
    say ""
    record 7
    return 0
  fi

  fence="$(fence_for "$diff")"
  say "### \`$path\` - changed against \`$BASE\`"
  say ""
  say "Diff of \`$path\` between \`$BASE\` ($BASE_SOURCE, ${BASE_SHA:0:12}, $BASE_DATE UTC) and HEAD (${HEAD_SHA:0:12}):"
  say ""
  say "${fence}diff PRODUCTIZER-SPEC-DIFF-$HEAD_SHA"
  printf '%s\n' "$diff"
  say "$fence"
  say ""
  record 0
}

# --- output ----------------------------------------------------------------
if [ "$FORMAT" = text ]; then
  say "# Spec diff - \`$BASE\` to HEAD"
  say ""
  say "Repo: $TOPLEVEL"
  say "Base: \`$BASE\` ($BASE_SOURCE) at ${BASE_SHA:0:12}, committed $BASE_DATE UTC"
  say "Head: ${HEAD_SHA:0:12}"
  say "Cap: $DIFF_MAX_CHARS characters per file"
  say ""
fi

emit_file "$SPEC"
emit_file "$CONST"

if [ "$RESULT" = 0 ]; then
  say "### Reconcile against the change, not the current text"
  say ""
  say "Reconcile the result with every change in the diff above, not only with the current text of the specification. A requirement that was removed, marked \`Superseded by R<n>.\` or marked \`Withdrawn.\` means the behaviour it described was dropped deliberately: delete the code and the tests that exist only for that behaviour."
  say ""
  say "Requirement ids are permanent and are never reused or renumbered, so an id that leaves the active set is a supersession to act on, never a renumbering to ignore. A superseded requirement keeps its original sentence in place, so the current spec cannot tell you it changed - this diff is the only place that says so."
  say ""
fi

if [ "$FORMAT" = text ]; then
  say "---"
  case "$RESULT" in
    0) say "Read from \`git diff\`. A file that did not change says so rather than being drawn as an empty diff." ;;
    4) say "Nothing changed in either file against \`$BASE\`. This is a measured result, not a missing baseline: the files were read at both ends and are identical." ;;
    5) say "At least one file has no baseline at \`$BASE\`. That is not the same as no changes, and it is not reported as one." ;;
    7) say "At least one diff was over the cap and was left out whole. The Build stage must be told it is working from the spec alone." ;;
  esac
fi

exit "$RESULT"
