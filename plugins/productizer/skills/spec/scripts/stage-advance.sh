#!/usr/bin/env bash
# stage-advance.sh [repo-root] --from STAGE --to STAGE
#                  (--patch FILE | --base REF [--head REF])
#                  [--mode plan|build] [--format text|json]
#                  [--selftest] [--version] [--help]
#
# MAY THIS WORK ITEM'S STAGE MOVE FROM --from TO --to, ON THE EVIDENCE OF THIS
# CHANGE? A pure decider: it reads the repository and the change, answers with
# an exit code, and writes nothing. No tracker, no network, no API. Every Jira
# transition and every GitHub stage label goes through it FIRST
# (references/integrations.md, "What syncs, and what never does"); the caller
# makes the move only on exit 0.
#
# Adapted from the forward-only, rank-gated status advance in the AI Unified
# Process (Apache-2.0, Simon Martinelli), `.github/workflows/aiup-generate.yml`:
# a run that produced nothing has no result for the status to take over, and a
# status at or beyond the one a run stands for never moves backwards. The idea
# is adopted; no code is copied. The forbidden-path rule is this repository's
# own: a stage run is the wrong actor to edit the rules it is judged by.
#
# THE THREE REFUSALS
#
#   1  PRODUCED NOTHING. The change is empty, or touches only the lifecycle's
#      own bookkeeping, or holds nothing the target stage counts as evidence.
#      Bookkeeping is exactly:
#        .claude/productizer/snapshots/**        (stage-snapshot.sh)
#        .claude/productizer/checks-result.json  (run-checks.sh output)
#        .claude/productizer/classifications/**  (record-classification.sh)
#   5  NOT A FORWARD MOVE. --to is at or before --from in the stage order.
#   3  FORBIDDEN PATH. The change touches a path the target stage may not.
#      THE FORBIDDEN SET lives in one function, forbidden_any_mode(), and is
#      matched on the path LOWER-CASED, so a case variant that a
#      case-insensitive checkout would fold onto a rule file is refused too:
#        any mode   .github/**             every workflow, composite action,
#                                          CODEOWNERS, dependabot: all of it
#                   .claude/**             DEFAULT-DENY: settings, hooks,
#                                          agents, commands, skills, and every
#                                          rule under .claude/productizer
#                                          (checks.yaml, calibration.yaml,
#                                          constitution.md, config.json, ...)
#                                          EXCEPT the bookkeeping below,
#                                          .claude/productizer/backlog.md, and
#                                          the spec outside build mode
#                   */.claude/**           a nested .claude directory, no
#                                          exceptions
#                   CLAUDE.md CLAUDE.local.md AGENTS.md .mcp.json
#                   .gitattributes .gitmodules   at any depth
#                   .git/**  .husky/**  .githooks/**  .pre-commit-config.yaml
#                   lefthook.yml  .lefthook.yml  lefthook-local.yml
#                   .lefthook-local.yml  CODEOWNERS  docs/CODEOWNERS
#                   REVIEW.md  .productizer-run/**  .productizer-tools/**
#        build mode also the spec (config.json spec.path)
#        plan mode  anything but the plan file, <artifacts.path>/plan.md
#                   (bookkeeping stays allowed; it is nothing, not a change)
#      These are the files that decide what CI runs, what an agent is told and
#      allowed, how git treats a path, and what the run is judged by. A stage
#      run is the wrong actor to edit any of them. An artifacts.path under
#      .claude/ or .github/ therefore cannot hold a plan an unattended run may
#      write: the any-mode set is checked first.
#
# STAGE ORDER is the key order of `github.issues.stage_labels` in
# .claude/productizer/config.json; a STAGE may be given as the key (`build`) or
# as its label (`sdlc:build`). With no such key the order is
# design < build < test < deploy < done. `intent` (the `github.issues.label`
# stage, Stage 1) ranks before every stage and is valid only as --from: without
# it the first advance, to `design`, could never be asked for.
#
# EVIDENCE PER TARGET STAGE
#
#   design  a requirement id ADDED, REFINED (its text changed), SUPERSEDED or
#           WITHDRAWN between base and head, judged by spec-requirements.sh on
#           both sides. That parser collapses whitespace, so a re-wrap or a
#           whitespace-only edit changes no record and is not evidence.
#   build   plan mode: a plan.md under artifacts.path in the change, not
#           deleted. build mode: a non-bookkeeping path outside
#           artifacts.path. --mode is required for --to build.
#   deploy  NOT DECIDABLE HERE - exit 4. Deploy and done move on a MERGE, and a
#   done    merge is not visible in a patch or a diff between two refs.
#   other   (test, or a stage a config adds) any non-bookkeeping path.
#
# INPUT. The patch text is never parsed here. --patch FILE is APPLIED BY GIT
# ITSELF, `git apply --cached --binary`, to a scratch index read from HEAD's
# tree, forward if it applies, else in reverse if it is already applied, else
# exit 4. New objects go to a temporary object directory, so the repository is
# not written. The changed paths are then git's own
# `git diff-tree -r -z --name-status --no-renames` between the two trees: the
# paths judged are the paths `git apply --index` writes, with a rename's old
# side as a deletion, and a section git applies but a header reader would skip
# (a traditional `---`/`+++` section, a CRLF or tab-suffixed name, hunk
# headers naming another file than `diff --git`) is judged like any other.
# --base REF reads `git diff --name-status --no-renames -z BASE...HEAD`. In
# both, deletions are marked, so a deleted plan.md is not evidence, and a path
# holding a control character (newline, tab, carriage return) is exit 4, never
# a guess. --patch needs a repository with a HEAD commit to apply against.
# For design with --patch, the spec's base and head are read from the two
# trees the patch was applied between.
#
# OUTPUT. On exit 0, the evidence paths, one per line, on stdout. The reason,
# on every exit, on stderr. --format json prints one object on stdout for
# every decision (exits 0, 1, 3, 4, 5); usage errors print only to stderr.
#
# Exit codes:
#   0  advance allowed; evidence paths printed on stdout
#   1  produced nothing
#   2  usage
#   3  produced a change the target stage forbids
#   4  cannot determine
#   5  not a forward move
# --selftest exits 0 when every case held, 1 when one did not.
set -euo pipefail
export LC_ALL=C

VERSION="stage-advance 1.1"
SELF="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"

die_usage() { printf 'stage-advance: %s\n' "$1" >&2; exit 2; }

usage() {
  printf 'usage: stage-advance.sh [repo-root] --from STAGE --to STAGE\n'
  printf '                        (--patch FILE | --base REF [--head REF])\n'
  printf '                        [--mode plan|build] [--format text|json]\n'
  printf '       stage-advance.sh --selftest | --version | --help\n'
  printf 'exit: 0 advance allowed, 1 produced nothing, 2 usage, 3 forbidden path,\n'
  printf '      4 cannot determine, 5 not a forward move\n'
}

ROOT=""; FROM=""; TO=""; PATCH=""; BASE=""; HEAD_REF=""; MODE=""; FORMAT="text"
SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --selftest|--self-test) SELFTEST=1; shift ;;
    --from)   [ $# -ge 2 ] || die_usage "--from needs a stage";      FROM="$2";     shift 2 ;;
    --from=*) FROM="${1#--from=}"; shift ;;
    --to)     [ $# -ge 2 ] || die_usage "--to needs a stage";        TO="$2";       shift 2 ;;
    --to=*)   TO="${1#--to=}"; shift ;;
    --patch)  [ $# -ge 2 ] || die_usage "--patch needs a file";      PATCH="$2";    shift 2 ;;
    --patch=*) PATCH="${1#--patch=}"; shift ;;
    --base)   [ $# -ge 2 ] || die_usage "--base needs a ref";        BASE="$2";     shift 2 ;;
    --base=*) BASE="${1#--base=}"; shift ;;
    --head)   [ $# -ge 2 ] || die_usage "--head needs a ref";        HEAD_REF="$2"; shift 2 ;;
    --head=*) HEAD_REF="${1#--head=}"; shift ;;
    --mode)   [ $# -ge 2 ] || die_usage "--mode needs plan or build"; MODE="$2";    shift 2 ;;
    --mode=*) MODE="${1#--mode=}"; shift ;;
    --format) [ $# -ge 2 ] || die_usage "--format needs text or json"; FORMAT="$2"; shift 2 ;;
    --format=*) FORMAT="${1#--format=}"; shift ;;
    -*) die_usage "unknown option: $1. Run with --help for the contract." ;;
    *)  [ -z "$ROOT" ] || die_usage "only one repo-root; got a second: $1"; ROOT="$1"; shift ;;
  esac
done

# ===========================================================================
# SELF-TEST. Real git repositories under mktemp -d, no network. Every case
# asserts an exit code AND a sentence of output.
# ===========================================================================
selftest() {
  # Global, not local: the EXIT trap runs after this function has returned.
  WORK="$(mktemp -d)" || die_usage "cannot create a temporary directory for the self-test"
  trap 'rm -rf "$WORK"' EXIT HUP INT TERM
  local CASES=0 HELD=0 CODES=""

  G() { git -C "$1" -c user.email=selftest@example.invalid -c user.name=selftest \
          -c commit.gpgsign=false "${@:2}"; }

  # A repository with a config, a spec holding R1, and one commit. The tag
  # `base` marks it, so every case diffs against the same starting point.
  newrepo() {
    local R="$WORK/$1"
    mkdir -p "$R/.claude/productizer" "$R/src"
    G "$R" init --quiet --initial-branch=main
    cat > "$R/.claude/productizer/config.json" <<'JSON'
{
  "spec": { "path": ".claude/productizer/spec.md" },
  "artifacts": { "path": "docs/sdlc/<slug>" },
  "github": { "issues": { "label": "sdlc:intent", "stage_labels": {
    "design": "sdlc:design", "build": "sdlc:build", "test": "sdlc:test",
    "deploy": "sdlc:deploy", "done": "sdlc:done" } } }
}
JSON
    printf '# Spec\n\n## Requirements\n\n- **R1** \342\200\224 The tool shall greet.\n' \
      > "$R/.claude/productizer/spec.md"
    printf 'echo hi\n' > "$R/src/app.sh"
    G "$R" add -A
    G "$R" commit --quiet -m base
    G "$R" tag base
  }
  commit() { G "$1" add -A; G "$1" commit --quiet -m change; }

  drive() {
    local name="$1" want="$2" text="$3"; shift 3
    local got=0
    bash "$SELF" "$@" > "$WORK/$name.out" 2> "$WORK/$name.err" || got=$?
    CASES=$((CASES + 1)); CODES="$CODES $got"
    if [ "$got" = "$want" ] && grep -qF -- "$text" "$WORK/$name.out" "$WORK/$name.err"; then
      HELD=$((HELD + 1))
      printf '  ok    %-44s exit %s\n' "$name" "$got"
    else
      printf '  FAIL  %-44s exit %s (wanted %s and the text: %s)\n' "$name" "$got" "$want" "$text"
      sed 's/^/          stdout: /' "$WORK/$name.out"
      sed 's/^/          stderr: /' "$WORK/$name.err"
    fi
  }

  printf 'stage-advance self-test\n\n'
  local R

  newrepo design-added; R="$WORK/design-added"
  printf -- '- **R2** \342\200\224 The tool shall wave.\n' >> "$R/.claude/productizer/spec.md"
  commit "$R"
  drive design-requirement-added 0 "R2 added" "$R" --from intent --to design --base base

  newrepo design-ws; R="$WORK/design-ws"
  printf '# Spec\n\n## Requirements\n\n-   **R1** \342\200\224 The  tool shall   greet.\n' \
    > "$R/.claude/productizer/spec.md"
  commit "$R"
  drive design-whitespace-only 1 "no requirement id was added, refined, superseded or withdrawn" \
    "$R" --from intent --to design --base base

  newrepo design-refined; R="$WORK/design-refined"
  printf '# Spec\n\n## Requirements\n\n- **R1** \342\200\224 The tool shall greet by name.\n' \
    > "$R/.claude/productizer/spec.md"
  commit "$R"
  drive design-requirement-refined 0 "R1 refined" "$R" --from intent --to design --base base

  newrepo design-superseded; R="$WORK/design-superseded"
  printf -- '  Superseded by R2.\n- **R2** \342\200\224 The tool shall wave.\n' \
    >> "$R/.claude/productizer/spec.md"
  commit "$R"
  drive design-requirement-superseded 0 "R1 superseded" "$R" --from intent --to design --base base

  newrepo bookkeeping; R="$WORK/bookkeeping"
  mkdir -p "$R/.claude/productizer/snapshots/stage-3" "$R/.claude/productizer/classifications"
  printf 'x\n' > "$R/.claude/productizer/snapshots/stage-3/a.snap"
  printf 'x\n' > "$R/.claude/productizer/classifications/12.md"
  commit "$R"
  drive bookkeeping-only 1 "produced nothing outside the lifecycle's own bookkeeping" \
    "$R" --from design --to build --mode build --base base

  : > "$WORK/empty.patch"
  drive empty-patch 1 "produced nothing outside the lifecycle's own bookkeeping" \
    "$R" --from design --to build --mode build --patch "$WORK/empty.patch"

  drive backward-move 5 "not a forward move: build is at or after design" \
    "$R" --from build --to design --base base
  drive same-stage 5 "not a forward move: test is at or after test" \
    "$R" --from test --to test --base base

  newrepo workflow; R="$WORK/workflow"
  mkdir -p "$R/.github/workflows"; printf 'on: push\n' > "$R/.github/workflows/ci.yml"
  printf 'echo bye\n' > "$R/src/app.sh"
  commit "$R"
  drive workflow-forbidden 3 "forbidden for build: .github/workflows/ci.yml" \
    "$R" --from design --to build --mode build --base base

  newrepo build-spec; R="$WORK/build-spec"
  printf -- '- **R2** \342\200\224 The tool shall wave.\n' >> "$R/.claude/productizer/spec.md"
  printf 'echo bye\n' > "$R/src/app.sh"
  commit "$R"
  drive build-mode-spec-forbidden 3 "forbidden for build: .claude/productizer/spec.md" \
    "$R" --from design --to build --mode build --base base

  newrepo plan-src; R="$WORK/plan-src"
  mkdir -p "$R/docs/sdlc/greet"; printf '# Plan\n' > "$R/docs/sdlc/greet/plan.md"
  printf 'echo bye\n' > "$R/src/app.sh"
  commit "$R"
  drive plan-mode-code-forbidden 3 "forbidden for build: src/app.sh" \
    "$R" --from design --to build --mode plan --base base
  drive build-mode-code-allowed 0 "src/app.sh" \
    "$R" --from design --to build --mode build --base base

  newrepo plan-ok; R="$WORK/plan-ok"
  mkdir -p "$R/docs/sdlc/greet"; printf '# Plan\n' > "$R/docs/sdlc/greet/plan.md"
  commit "$R"
  drive plan-mode-plan-committed 0 "docs/sdlc/greet/plan.md" \
    "$R" --from design --to build --mode plan --base base
  drive build-mode-only-plan 1 "no path outside the lifecycle's artifacts" \
    "$R" --from design --to build --mode build --base base
  drive json-format 0 '"verdict": "advance"' \
    "$R" --from sdlc:design --to sdlc:build --mode plan --base base --format json

  newrepo patch-design; R="$WORK/patch-design"
  cp "$R/.claude/productizer/spec.md" "$WORK/spec.orig"
  printf -- '- **R2** \342\200\224 The tool shall wave.\n' >> "$R/.claude/productizer/spec.md"
  G "$R" diff > "$WORK/design.patch"
  drive patch-already-applied 0 "R2 added" \
    "$R" --from intent --to design --patch "$WORK/design.patch"
  cp "$WORK/spec.orig" "$R/.claude/productizer/spec.md"
  drive patch-not-yet-applied 0 "R2 added" \
    "$R" --from intent --to design --patch "$WORK/design.patch"

  CASES=$((CASES + 1)); CODES="$CODES 0"
  if cmp -s "$WORK/spec.orig" "$R/.claude/productizer/spec.md" && [ -z "$(G "$R" status --porcelain)" ]; then
    HELD=$((HELD + 1)); printf '  ok    %-44s exit 0\n' "the patch was not applied to the repo"
  else
    printf '  FAIL  %-44s the repository changed under a decider that writes nothing\n' "the patch was not applied to the repo"
  fi

  newrepo plan-deleted; R="$WORK/plan-deleted"
  mkdir -p "$R/docs/sdlc/greet"; printf '# Plan\n' > "$R/docs/sdlc/greet/plan.md"
  commit "$R"; G "$R" tag with-plan
  G "$R" rm --quiet docs/sdlc/greet/plan.md
  G "$R" diff --cached > "$WORK/delete.patch"
  drive plan-deleted-not-evidence 1 "no plan.md under docs/sdlc/<slug> is in this change" \
    "$R" --from design --to build --mode plan --patch "$WORK/delete.patch"

  printf 'diff --git "a/sp ace\\t.sh" "b/sp ace\\t.sh"\nnew file mode 100644\n--- /dev/null\n+++ "b/sp ace\\t.sh"\n@@ -0,0 +1 @@\n+x\n' > "$WORK/quoted.patch"
  drive quoted-path-with-tab 4 "holds a control character" \
    "$R" --from design --to build --mode build --patch "$WORK/quoted.patch"
  printf 'diff --git "a/sp ace\\t.sh" "b/sp ace\\t.sh"\nindex 1..2 100644\n' > "$WORK/garbage.patch"
  drive patch-git-cannot-apply 4 "applies the patch to HEAD neither forward nor in reverse" \
    "$R" --from design --to build --mode build --patch "$WORK/garbage.patch"

  # --- THE PARSER DIFFERENTIAL. Each patch below was accepted (exit 0) by the
  # header-reading parser of stage-advance 1.0 while `git apply --index` wrote
  # the forbidden path. The paths judged now are the paths git writes.
  newrepo diff; R="$WORK/diff"
  mkdir -p "$R/.github/workflows" "$R/docs/sdlc/greet"
  printf 'on: push\n' > "$R/.github/workflows/ci.yml"
  printf 'checks: []\n' > "$R/.claude/productizer/checks.yaml"
  commit "$R"
  local wf_mod='--- a/.github/workflows/ci.yml\n+++ b/.github/workflows/ci.yml\n@@ -1 +1 @@\n-on: push\n+on: pull_request_target\n'
  # shellcheck disable=SC2059  # the format strings are the patch fixtures
  {
    printf 'diff --git a/src/app.sh b/.github/workflows/x.yml\n--- a/src/app.sh\n+++ b/.github/workflows/x.yml\n@@ -1 +1 @@\n-echo hi\n+on: push\n' > "$WORK/d-names.patch"
    printf "diff --git a/src/app.sh b/src/app.sh\n$wf_mod" > "$WORK/d-hunk-names.patch"
    printf "diff --git a/src/app.sh b/src/app.sh\n--- a/src/app.sh\n+++ b/src/app.sh\n@@ -1 +1 @@\n-echo hi\n+echo bye\n$wf_mod" > "$WORK/d-traditional.patch"
    printf 'diff --git a/src/app.sh b/.claude/productizer/checks.yaml\r\n--- a/.claude/productizer/checks.yaml\r\n+++ b/.claude/productizer/checks.yaml\r\n@@ -1 +1 @@\n-checks: []\n+checks: [x]\n' > "$WORK/d-crlf.patch"
    printf 'diff --git a/src/app.sh b/.claude/productizer/checks.yaml\n--- a/.claude/productizer/checks.yaml\tx\n+++ b/.claude/productizer/checks.yaml\tx\n@@ -1 +1 @@\n-checks: []\n+checks: [x]\n' > "$WORK/d-tab-suffix.patch"
    printf 'diff --git a/src/app.sh b/.github/workflows/x.yml\n--- a/src/app.sh\n+++ b/.github/workflows/x.yml\n@@ -1 +1 @@\n-echo hi\n+on: push\n\\ No newline at end of file\n' > "$WORK/d-no-newline.patch"
    printf "diff --git a/docs/sdlc/greet/plan.md b/docs/sdlc/greet/plan.md\n$wf_mod" > "$WORK/d-plan-hunk-names.patch"
    printf "diff --git a/docs/sdlc/greet/plan.md b/docs/sdlc/greet/plan.md\nnew file mode 100644\n--- /dev/null\n+++ b/docs/sdlc/greet/plan.md\n@@ -0,0 +1 @@\n+# Plan\n$wf_mod" > "$WORK/d-plan-traditional.patch"
    printf 'diff --git a/src/app.sh b/.github/workflows/x.yml\nsimilarity index 100%%\nrename from src/app.sh\nrename to .github/workflows/x.yml\n' > "$WORK/d-rename.patch"
    printf 'diff --git a/src/link b/src/link\nnew file mode 120000\n--- /dev/null\n+++ b/src/link\n@@ -0,0 +1 @@\n+../.github/workflows\n\\ No newline at end of file\ndiff --git a/src/link/x.yml b/src/link/x.yml\nnew file mode 100644\n--- /dev/null\n+++ b/src/link/x.yml\n@@ -0,0 +1 @@\n+on: push\n' > "$WORK/d-symlink.patch"
    printf 'diff --git a/./.github/workflows/x.yml b/./.github/workflows/x.yml\nnew file mode 100644\n--- /dev/null\n+++ b/./.github/workflows/x.yml\n@@ -0,0 +1 @@\n+on: push\n' > "$WORK/d-dot-slash.patch"
  }
  drive diff-header-names-differ 3 "forbidden for test: .github/workflows/x.yml" \
    "$R" --from build --to test --mode build --patch "$WORK/d-names.patch"
  drive diff-hunk-names-another-file 3 "forbidden for test: .github/workflows/ci.yml" \
    "$R" --from build --to test --mode build --patch "$WORK/d-hunk-names.patch"
  drive diff-traditional-section 3 "forbidden for test: .github/workflows/ci.yml" \
    "$R" --from build --to test --mode build --patch "$WORK/d-traditional.patch"
  drive diff-crlf-header 3 "forbidden for test: .claude/productizer/checks.yaml" \
    "$R" --from build --to test --mode build --patch "$WORK/d-crlf.patch"
  drive diff-tab-suffixed-name 3 "forbidden for test: .claude/productizer/checks.yaml" \
    "$R" --from build --to test --mode build --patch "$WORK/d-tab-suffix.patch"
  drive diff-no-newline-marker 3 "forbidden for test: .github/workflows/x.yml" \
    "$R" --from build --to test --mode build --patch "$WORK/d-no-newline.patch"
  drive diff-plan-hunk-names 3 "forbidden for build: .github/workflows/ci.yml" \
    "$R" --from design --to build --mode plan --patch "$WORK/d-plan-hunk-names.patch"
  drive diff-plan-traditional-section 3 "forbidden for build: .github/workflows/ci.yml" \
    "$R" --from design --to build --mode plan --patch "$WORK/d-plan-traditional.patch"
  drive diff-rename-into-forbidden 3 "forbidden for test: .github/workflows/x.yml" \
    "$R" --from build --to test --mode build --patch "$WORK/d-rename.patch"
  drive diff-write-beyond-symlink 4 "beyond a symbolic link" \
    "$R" --from build --to test --mode build --patch "$WORK/d-symlink.patch"
  drive diff-dot-slash-path 4 "invalid path" \
    "$R" --from build --to test --mode build --patch "$WORK/d-dot-slash.patch"
  local objs_before objs_after
  objs_before="$(find "$R/.git/objects" -type f | wc -l)"
  drive diff-patch-applied-in-scratch 3 "forbidden for test: .github/workflows/x.yml" \
    "$R" --from build --to test --mode build --patch "$WORK/d-names.patch"
  objs_after="$(find "$R/.git/objects" -type f | wc -l)"
  CASES=$((CASES + 1)); CODES="$CODES 0"
  if [ "$objs_before" = "$objs_after" ] && [ -z "$(G "$R" status --porcelain)" ]; then
    HELD=$((HELD + 1)); printf '  ok    %-44s exit 0\n' "applying the patch wrote nothing to the repo"
  else
    printf '  FAIL  %-44s objects %s -> %s, or the tree changed\n' "applying the patch wrote nothing to the repo" "$objs_before" "$objs_after"
  fi

  # A NEWLINE IN A PATH, --base mode: 1.0 split git's -z output on newlines,
  # so a name ending in "\nM" swallowed the next path's status line.
  newrepo nl; R="$WORK/nl"
  printf 'x\n' > "$R/.a"$'\n'"M"
  mkdir -p "$R/.github/workflows"; printf 'on: push\n' > "$R/.github/workflows/x.yml"
  commit "$R"
  drive base-newline-in-path 4 "holds a control character" \
    "$R" --from build --to test --mode build --base base

  # --- THE FORBIDDEN SET. Each path below changes what CI runs, what an agent
  # is told or allowed, or how git treats a path, and 1.0 allowed it.
  newrepo rules; R="$WORK/rules"
  local p n=0
  for p in .github/actions/setup/action.yml .github/CODEOWNERS .github/dependabot.yml \
           .claude/agents/a.md .claude/commands/c.md .claude/skills/s/SKILL.md \
           .claude/productizer/risk-tiers.yaml .claude/productizer/bands.yaml sub/.claude/settings.json \
           .mcp.json CLAUDE.md src/CLAUDE.md AGENTS.md REVIEW.md CODEOWNERS \
           .gitattributes src/.gitattributes .gitmodules .husky/pre-commit .pre-commit-config.yaml \
           lefthook.yml .productizer-tools/x.sh .GitHub/workflows/x.yml .Claude/Settings.json; do
    n=$((n + 1))
    # Written as text, not made on disk: a case-insensitive file system
    # would fold .Claude onto .claude before git saw it.
    printf 'diff --git a/%s b/%s\nnew file mode 100644\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1 @@\n+x\n' \
      "$p" "$p" "$p" > "$WORK/rule-$n.patch"
    drive "rule-$(printf "%s" "$p" | tr / :)" 3 "forbidden for test: $p" \
      "$R" --from build --to test --mode build --patch "$WORK/rule-$n.patch"
  done
  # config.json decides the stage order, the spec path and the plan path.
  printf '{}\n' > "$R/.claude/productizer/config.json"
  G "$R" diff > "$WORK/config.patch"; G "$R" restore -- .claude/productizer/config.json
  drive rule-config-json-modified 3 "forbidden for test: .claude/productizer/config.json" \
    "$R" --from build --to test --mode build --patch "$WORK/config.patch"
  # The two exceptions under .claude, so the rule is not refusing everything.
  printf 'diff --git a/.claude/productizer/backlog.md b/.claude/productizer/backlog.md\nnew file mode 100644\n--- /dev/null\n+++ b/.claude/productizer/backlog.md\n@@ -0,0 +1 @@\n+- B1\n' > "$WORK/backlog.patch"
  drive backlog-allowed 0 ".claude/productizer/backlog.md" \
    "$R" --from build --to test --mode build --patch "$WORK/backlog.patch"

  drive deploy-not-visible 4 "a merge is not visible to this script" \
    "$R" --from test --to deploy --base base
  drive unknown-base 4 "does not resolve to a commit" \
    "$R" --from design --to build --mode build --base no-such-ref
  drive build-needs-mode 2 "--to build needs --mode plan or --mode build" \
    "$R" --from design --to build --base base
  drive unknown-stage 2 "unknown stage: review" \
    "$R" --from design --to review --base base
  drive no-input 2 "one of --patch or --base" \
    "$R" --from design --to build --mode build

  newrepo custom-order; R="$WORK/custom-order"
  cat > "$R/.claude/productizer/config.json" <<'JSON'
{ "github": { "issues": { "stage_labels": { "design": "s:d", "review": "s:r", "build": "s:b" } } } }
JSON
  commit "$R"
  drive order-from-config 5 "not a forward move: review is at or after design" \
    "$R" --from review --to design --base base

  newrepo bad-config; R="$WORK/bad-config"
  printf '{ "github": \n' > "$R/.claude/productizer/config.json"
  commit "$R"
  drive malformed-config 4 "cannot read the stage order" \
    "$R" --from design --to build --mode build --base base

  drive version 0 "stage-advance 1." --version

  printf '\n%s of %s cases held\n' "$HELD" "$CASES"
  local reached documented
  reached="$(printf '%s' "$CODES" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  documented="$(awk '/^# Exit codes:/{f=1;next} f&&/^#   [0-9] /{printf "%s ", $2; next} f{exit}' "$SELF" | sed 's/  *$//')"
  printf '    exit codes reached: %s   documented: %s\n' "$reached" "$documented"
  printf '    NOT ASSERTED: a header with an unquoted space; the label form of --from for every stage; a custom stage other than design/build with evidence; --head other than HEAD (build-dispatch.sh drives it); a requirement WITHDRAWN; that nothing is written outside the two fixtures checked for it; a Unicode-normalisation variant of a forbidden path; a gitlink (submodule entry) or a symlink at an allowed path, both allowed; that the forbidden set is every file that steers CI or an agent.\n'
  [ "$reached" = "$documented" ] || { printf 'FAIL: reached and documented exit codes differ\n'; return 1; }
  [ "$HELD" -eq "$CASES" ] || return 1
  return 0
}

if [ "$SELFTEST" -eq 1 ]; then
  ST_RC=0
  selftest || ST_RC=$?
  exit "$ST_RC"
fi

# ===========================================================================
# THE DECISION
# ===========================================================================
[ -n "$FROM" ] || die_usage "--from is required"
[ -n "$TO" ]   || die_usage "--to is required"
if [ -n "$PATCH" ] && [ -n "$BASE" ]; then die_usage "give one of --patch or --base, not both"; fi
[ -n "$PATCH" ] || [ -n "$BASE" ] || die_usage "give one of --patch or --base: there is no change to judge"
[ -z "$HEAD_REF" ] || [ -n "$BASE" ] || die_usage "--head goes with --base"
case "$MODE" in ""|plan|build) ;; *) die_usage "--mode is plan or build; got: $MODE" ;; esac
case "$FORMAT" in text|json) ;; *) die_usage "--format is text or json; got: $FORMAT" ;; esac
[ -n "$ROOT" ] || ROOT="."
[ -d "$ROOT" ] || die_usage "no such directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"
if [ -n "$PATCH" ]; then
  [ -f "$PATCH" ] && [ -r "$PATCH" ] || die_usage "cannot read the patch: $PATCH"
  PATCH="$(cd "$(dirname "$PATCH")" && pwd)/$(basename "$PATCH")"
fi
[ -n "$HEAD_REF" ] || HEAD_REF="HEAD"

EVIDENCE=""; REQS=""; FORBIDDEN=""
TMP=""
trap '[ -z "$TMP" ] || rm -rf "$TMP"' EXIT HUP INT TERM

finish() {
  local code="$1" reason="$2" verdict
  case "$code" in
    0) verdict="advance" ;; 1) verdict="produced-nothing" ;; 3) verdict="forbidden" ;;
    4) verdict="cannot-determine" ;; 5) verdict="not-forward" ;; *) verdict="error" ;;
  esac
  printf 'stage-advance: %s\n' "$reason" >&2
  if [ "$FORMAT" = "json" ]; then
    python3 -I -c '
import json, sys
def lines(s): return [l for l in s.split("\n") if l]
code, verdict, frm, to, mode, reason, ev, reqs, forb = sys.argv[1:]
print(json.dumps({"verdict": verdict, "exit": int(code), "from": frm, "to": to,
  "mode": mode or None, "reason": reason, "evidence": lines(ev),
  "requirements": lines(reqs), "forbidden": lines(forb)}, indent=2))
' "$code" "$verdict" "$FROM" "$TO" "$MODE" "$reason" "$EVIDENCE" "$REQS" "$FORBIDDEN"
  elif [ "$code" -eq 0 ]; then
    printf '%s\n' "$EVIDENCE" | awk 'NF'
  fi
  exit "$code"
}

# --- config: stage order, spec path, artifacts path -------------------------
CONF_OUT="$(python3 -I - "$ROOT/.claude/productizer/config.json" <<'PY'
import json, os, sys
path = sys.argv[1]
order = [("design", ""), ("build", ""), ("test", ""), ("deploy", ""), ("done", "")]
source = "default"
spec = ".claude/productizer/spec.md"
art = "docs/sdlc/<slug>"
intent = ""
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        print("cannot read the stage order: %s is not readable JSON (%s)" % (path, e), file=sys.stderr)
        sys.exit(4)
    gh = cfg.get("github") if isinstance(cfg, dict) else None
    issues = gh.get("issues") if isinstance(gh, dict) else None
    if isinstance(issues, dict) and "stage_labels" in issues:
        sl = issues["stage_labels"]
        if not isinstance(sl, dict) or not sl or not all(isinstance(k, str) and k and isinstance(v, str) for k, v in sl.items()):
            print("cannot read the stage order: github.issues.stage_labels is not a non-empty map of stage to label", file=sys.stderr)
            sys.exit(4)
        order = list(sl.items())
        source = "config"
    if isinstance(issues, dict) and isinstance(issues.get("label"), str):
        intent = issues["label"]
    s = cfg.get("spec") if isinstance(cfg, dict) else None
    if isinstance(s, dict) and isinstance(s.get("path"), str) and s["path"]:
        spec = s["path"]
    a = cfg.get("artifacts") if isinstance(cfg, dict) else None
    if isinstance(a, dict) and isinstance(a.get("path"), str) and a["path"]:
        art = a["path"]
print("SOURCE\t" + source)
print("SPEC\t" + spec)
print("ART\t" + art.rstrip("/"))
print("STAGE\tintent\t" + intent)
for k, v in order:
    print("STAGE\t%s\t%s" % (k, v))
PY
)" || finish 4 "cannot read the stage order from .claude/productizer/config.json; the error is above"

ORDER_SOURCE="$(printf '%s\n' "$CONF_OUT" | awk -F'\t' '$1=="SOURCE"{print $2}')"
SPEC="$(printf '%s\n' "$CONF_OUT" | awk -F'\t' '$1=="SPEC"{print $2}')"
ART="$(printf '%s\n' "$CONF_OUT" | awk -F'\t' '$1=="ART"{print $2}')"

# Rank of a stage given as a key or as its label. `intent` is rank 0, the
# stage labels 1..n in config order. Prints nothing for an unknown stage.
rank_of() {
  printf '%s\n' "$CONF_OUT" | awk -F'\t' -v s="$1" '
    $1=="STAGE" { r++; if ($2==s || ($3!="" && $3==s)) { print (r-1) "\t" $2; exit } }'
}
FROM_R="$(rank_of "$FROM")"; TO_R="$(rank_of "$TO")"
[ -n "$FROM_R" ] || die_usage "unknown stage: $FROM (stage order from $ORDER_SOURCE)"
[ -n "$TO_R" ]   || die_usage "unknown stage: $TO (stage order from $ORDER_SOURCE)"
FROM_N="${FROM_R%%$'\t'*}"; FROM_KEY="${FROM_R#*$'\t'}"
TO_N="${TO_R%%$'\t'*}";     TO_KEY="${TO_R#*$'\t'}"
[ "$TO_KEY" != "build" ] || [ -n "$MODE" ] \
  || die_usage "--to build needs --mode plan or --mode build: the evidence for the two differs"

# --- forward only -----------------------------------------------------------
if [ "$TO_N" -le "$FROM_N" ]; then
  finish 5 "not a forward move: $FROM_KEY is at or after $TO_KEY in the stage order ($ORDER_SOURCE); a stage never moves backwards and never re-enters itself"
fi

# --- deploy and done move on a merge ----------------------------------------
case "$TO_KEY" in
  deploy|done)
    finish 4 "cannot determine whether $TO_KEY may be entered: it moves on a MERGE, and a merge is not visible to this script, which reads a patch or a diff between two refs. The merge itself is the evidence; check it where it happened." ;;
esac

# --- the changed paths: one "STATUS<TAB>path" per line, STATUS M or D ---------
# read_name_status: git's NUL-separated `--name-status -z` stream on stdin ->
# one "M|D<TAB>path" line per path. The list below is newline-separated, so a
# path holding a control character is printed as "?<TAB><quoted path>" and
# refused: a name is never split, joined or guessed at.
read_name_status() {
  local st p
  while IFS= read -r -d '' st && IFS= read -r -d '' p; do
    if [[ "$p" == *[[:cntrl:]]* ]]; then printf '?\t%q\n' "$p"; continue; fi
    if [ "$st" = D ]; then printf 'D\t%s\n' "$p"; else printf 'M\t%s\n' "$p"; fi
  done
}

if [ -n "$PATCH" ]; then
  if ! grep -q '[^[:space:]]' "$PATCH"; then
    CHANGES=""
  else
    git -C "$ROOT" rev-parse --verify --quiet 'HEAD^{commit}' > /dev/null \
      || finish 4 "cannot determine the changed paths: a patch is judged by applying it to HEAD, and $ROOT has no HEAD commit"
    TMP="$(mktemp -d)" || finish 4 "cannot create a temporary directory to apply the patch in"
    mkdir "$TMP/objects"
    OBJ="$(git -C "$ROOT" rev-parse --path-format=absolute --git-path objects)" \
      || finish 4 "cannot find the object directory of $ROOT"
    # Git with a scratch index and a scratch object directory: it reads the
    # repository's objects and writes only under $TMP.
    SG() { GIT_INDEX_FILE="$TMP/index" GIT_OBJECT_DIRECTORY="$TMP/objects" \
           GIT_ALTERNATE_OBJECT_DIRECTORIES="$OBJ" git -C "$ROOT" "$@"; }
    HEAD_TREE="$(git -C "$ROOT" rev-parse 'HEAD^{tree}')"
    SG read-tree "$HEAD_TREE" || finish 4 "cannot read HEAD's tree into a scratch index"
    if SG apply --cached --binary "$PATCH" 2> "$TMP/apply.err"; then
      PT_BASE="$HEAD_TREE"
      PT_HEAD="$(SG write-tree)" || finish 4 "cannot write the tree the patch produced"
    else
      SG read-tree "$HEAD_TREE" || finish 4 "cannot read HEAD's tree into a scratch index"
      if SG apply -R --cached --binary "$PATCH" 2>> "$TMP/apply.err"; then
        PT_BASE="$(SG write-tree)" || finish 4 "cannot write the tree the reversed patch produced"
        PT_HEAD="$HEAD_TREE"
      else
        finish 4 "cannot determine the changed paths: git apply applies the patch to HEAD neither forward nor in reverse, so what it would write is unknown ($(head -1 "$TMP/apply.err"))"
      fi
    fi
    CHANGES="$(SG diff-tree -r -z --name-status --no-renames "$PT_BASE" "$PT_HEAD" | read_name_status)" \
      || finish 4 "cannot determine the changed paths: git diff-tree between the patch's trees failed"
  fi
else
  git -C "$ROOT" rev-parse --is-inside-work-tree > /dev/null \
    || finish 4 "cannot determine the changed paths: $ROOT is not a git repository"
  git -C "$ROOT" rev-parse --verify --quiet "$BASE^{commit}" > /dev/null \
    || finish 4 "cannot determine the changed paths: --base $BASE does not resolve to a commit"
  git -C "$ROOT" rev-parse --verify --quiet "$HEAD_REF^{commit}" > /dev/null \
    || finish 4 "cannot determine the changed paths: --head $HEAD_REF does not resolve to a commit"
  MB="$(git -C "$ROOT" merge-base "$BASE" "$HEAD_REF")" \
    || finish 4 "cannot determine the changed paths: $BASE and $HEAD_REF share no merge base"
  CHANGES="$(git -C "$ROOT" diff --name-status --no-renames -z "$BASE...$HEAD_REF" | read_name_status)" \
    || finish 4 "cannot determine the changed paths: git diff $BASE...$HEAD_REF failed"
fi
if printf '%s\n' "$CHANGES" | grep -q '^?'; then
  finish 4 "cannot determine the changed paths: a changed path holds a control character (newline, tab or carriage return), and such a name is not judged: $(printf '%s\n' "$CHANGES" | grep '^?' | head -1 | cut -f2-)"
fi
CHANGES="$(printf '%s\n' "$CHANGES" | awk 'NF' | sort -u)"

# --- classify ---------------------------------------------------------------
ere_escape() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'; }
ART_RE="^$(ere_escape "$ART" | sed 's/<[^>]*>/[^\/]+/g')/"
PLAN_RE="${ART_RE}plan\\.md\$"
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
SPEC_LC="$(lower "$SPEC")"

is_bookkeeping() {
  case "$1" in
    .claude/productizer/snapshots/*|.claude/productizer/classifications/*) return 0 ;;
    .claude/productizer/checks-result.json) return 0 ;;
  esac
  return 1
}
# THE FORBIDDEN SET, every mode. The one place it is written; the header's
# FORBIDDEN PATH list and references/ci-build.md describe this function.
forbidden_any_mode() {
  local lc base
  lc="$(lower "$1")"; base="${lc##*/}"
  case "$lc" in
    .github/*) return 0 ;;
    .claude/*)
      is_bookkeeping "$1" && return 1
      [ "$lc" = ".claude/productizer/backlog.md" ] && return 1
      [ "$MODE" != "build" ] && [ "$lc" = "$SPEC_LC" ] && return 1
      return 0 ;;
    */.claude/*|.git/*|*/.git/*) return 0 ;;
    .husky/*|.githooks/*|.productizer-run/*|.productizer-tools/*) return 0 ;;
    .pre-commit-config.yaml|lefthook.yml|.lefthook.yml|lefthook-local.yml|.lefthook-local.yml) return 0 ;;
    codeowners|docs/codeowners|review.md) return 0 ;;
  esac
  case "$base" in
    claude.md|claude.local.md|agents.md|.mcp.json|.gitattributes|.gitmodules) return 0 ;;
  esac
  return 1
}
is_forbidden() {
  forbidden_any_mode "$1" && return 0
  [ "$MODE" = "build" ] && [ "$(lower "$1")" = "$SPEC_LC" ] && return 0
  [ "$MODE" = "plan" ] && ! [[ "$1" =~ $PLAN_RE ]] && ! is_bookkeeping "$1" && return 0
  return 1
}

REAL=""
while IFS=$'\t' read -r st p; do
  [ -n "$p" ] || continue
  is_bookkeeping "$p" || REAL="$REAL$st"$'\t'"$p"$'\n'
  if is_forbidden "$p"; then FORBIDDEN="$FORBIDDEN$p"$'\n'; fi
done <<< "$CHANGES"

[ -n "$REAL" ] \
  || finish 1 "the run produced nothing outside the lifecycle's own bookkeeping; $FROM_KEY -> $TO_KEY has no result to take over"
if [ -n "$FORBIDDEN" ]; then
  finish 3 "the change touches a path the target stage does not permit${MODE:+ in $MODE mode}; forbidden for $TO_KEY: $(printf '%s' "$FORBIDDEN" | tr '\n' ' ' | sed 's/ $//')"
fi

# --- evidence per target stage ----------------------------------------------
spec_records() {
  # spec_records <file> -> "id<TAB>status<TAB>target<TAB>text", line dropped
  bash "$SCRIPT_DIR/spec-requirements.sh" "$1" | cut -f1,3,4,5 | sort
}

case "$TO_KEY" in
  design)
    [ -f "$SCRIPT_DIR/spec-requirements.sh" ] \
      || finish 4 "cannot judge the spec: spec-requirements.sh is not beside this script"
    [ -n "$TMP" ] || TMP="$(mktemp -d)" || finish 4 "cannot create a temporary directory to rebuild the spec in"
    if [ -n "$PATCH" ]; then
      # The two trees the patch was applied between, in the scratch objects.
      if SG cat-file -e "$PT_BASE:$SPEC" 2> "$TMP/cat.err"; then
        SG show "$PT_BASE:$SPEC" > "$TMP/base.md"
      fi
      if SG cat-file -e "$PT_HEAD:$SPEC" 2>> "$TMP/cat.err"; then
        SG show "$PT_HEAD:$SPEC" > "$TMP/head.md"
      fi
    else
      if git -C "$ROOT" cat-file -e "$MB:$SPEC" 2> "$TMP/cat.err"; then
        git -C "$ROOT" show "$MB:$SPEC" > "$TMP/base.md"
      fi
      if git -C "$ROOT" cat-file -e "$HEAD_REF:$SPEC" 2>> "$TMP/cat.err"; then
        git -C "$ROOT" show "$HEAD_REF:$SPEC" > "$TMP/head.md"
      fi
    fi
    [ -f "$TMP/head.md" ] || finish 4 "cannot judge the spec: $SPEC is absent at head"
    [ -f "$TMP/base.md" ] || : > "$TMP/base.md"
    spec_records "$TMP/base.md" > "$TMP/base.tsv" || finish 4 "spec-requirements.sh refused the base spec"
    spec_records "$TMP/head.md" > "$TMP/head.tsv" || finish 4 "spec-requirements.sh refused the head spec"
    REQS="$(awk -F'\t' '
      NR==FNR { base[$1] = $0; bstat[$1] = $2; next }
      !($1 in base) { print $1 " added"; next }
      base[$1] == $0 { next }
      $2 != bstat[$1] && ($2 == "superseded" || $2 == "withdrawn") { print $1 " " $2; next }
      { print $1 " refined" }
    ' "$TMP/base.tsv" "$TMP/head.tsv")"
    [ -n "$REQS" ] \
      || finish 1 "produced nothing for design: no requirement id was added, refined, superseded or withdrawn in $SPEC (a whitespace-only edit is not a change)"
    EVIDENCE="$SPEC"
    finish 0 "advance allowed: $FROM_KEY -> design: $(printf '%s' "$REQS" | tr '\n' ',' | sed 's/,/, /g')"
    ;;
  build)
    if [ "$MODE" = "plan" ]; then
      EVIDENCE="$(printf '%s' "$REAL" | RE="$PLAN_RE" awk -F'\t' '$1!="D" && $2 ~ ENVIRON["RE"] { print $2 }')"
      [ -n "$EVIDENCE" ] \
        || finish 1 "produced nothing for build in plan mode: no plan.md under $ART is in this change"
    else
      EVIDENCE="$(printf '%s' "$REAL" | RE="$ART_RE" awk -F'\t' '$2 !~ ENVIRON["RE"] { print $2 }')"
      [ -n "$EVIDENCE" ] \
        || finish 1 "produced nothing for build in build mode: no path outside the lifecycle's artifacts ($ART) changed"
    fi
    finish 0 "advance allowed: $FROM_KEY -> build in $MODE mode"
    ;;
  *)
    EVIDENCE="$(printf '%s' "$REAL" | cut -f2)"
    finish 0 "advance allowed: $FROM_KEY -> $TO_KEY"
    ;;
esac
