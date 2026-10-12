#!/usr/bin/env bash
# stage-advance.sh [repo-root] --from STAGE --to STAGE
#                  (--patch FILE | --base REF [--head REF])
#                  [--mode plan|build] [--unattended] [--format text|json]
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
#   1  PRODUCED NOTHING. The change is empty, or ADDS only the lifecycle's
#      own bookkeeping, or holds nothing the target stage counts as evidence.
#      Bookkeeping is exactly:
#        .claude/productizer/snapshots/**        (stage-snapshot.sh)
#        .claude/productizer/checks-result.json  (run-checks.sh output)
#        .claude/productizer/classifications/**  (record-classification.sh)
#      Bookkeeping ADDED is "nothing"; bookkeeping DELETED is refusal 3, not 1.
#      These records are an audit trail the governance checks read, and a run
#      that erases one can flip a check from a finding to clean, so a stage run
#      - the wrong actor to edit the rules it is judged by - may not delete
#      one either. A snapshot or a classification MODIFIED (git status M, or T
#      for a change of type) is refusal 3 too: stage-snapshot.sh and
#      record-classification.sh both refuse to overwrite one (their exit 1),
#      and in this repository's history neither store was ever modified, only
#      added to, so a rewrite is never their writer's. The checks result is
#      rewritten by every run of run-checks.sh, so in an ATTENDED run its
#      modification is "nothing", like an addition. Under --unattended it is
#      refusal 3 instead, whatever the change (see UNATTENDED below).
#      `.claude/productizer/backlog.md` is never evidence either: it is the
#      queue in front of intake, and a row is a wish, not a result.
#   5  NOT A FORWARD MOVE. --to is at or before --from in the stage order.
#   3  FORBIDDEN PATH. The change touches a path the target stage may not.
#      THE FORBIDDEN SET lives in four lists, FORBID_*, read by one function,
#      forbidden_any_mode(), and is matched on a FOLDED KEY of the path - format characters removed, NFKC,
#      Unicode case folding - so a variant that a case- or normalisation-
#      insensitive checkout would fold onto a rule file is refused too (case,
#      NFD, the long s, the Kelvin sign; and a fullwidth letter, which only a
#      reader folds). Every exception below is granted on the exact bytes, so
#      a variant spelling never inherits one. A name is matched with its
#      subtree, so `.github` itself, as a file or a link, is in `.github/**`:
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
#        build mode also the spec (config.json spec.path), and any line of
#                   .claude/productizer/backlog.md removed or rewritten: a
#                   build run may ADD a backlog item, never change one (checks
#                   read its lines; a row's status is what was agreed)
#        plan mode  anything but the plan file, <artifacts.path>/plan.md
#                   (bookkeeping stays allowed; it is nothing, not a change)
#        LINKS, any mode and any path: a symbolic link created or retargeted
#                   (mode 120000), and a gitlink - a submodule entry, mode
#                   160000 - added, repointed or removed. A link makes a name
#                   stand for another path or for code outside the change, and
#                   this decider judges names. Deleting a symlink, or turning
#                   one into a file, is judged by its path like any other.
#        HOMOGLYPHS, any mode: a path whose bytes are not ASCII, when a
#                   READING of it - each non-ASCII character taken as any one
#                   character (none or one for a combining mark or a filler,
#                   one or two for a Latin letter) - is a path refused above,
#                   or when a component of it begins with a dot. No
#                   confusables table is used; the reading is a superset of
#                   one. A component with no ASCII letter or digit is not read.
#      These are the files that decide what CI runs, what an agent is told and
#      allowed, how git treats a path, and what the run is judged by. A stage
#      run is the wrong actor to edit any of them. An artifacts.path under
#      .claude/ or .github/ therefore cannot hold a plan an unattended run may
#      write: the any-mode set is checked first.
#      The set is a LIST, and nothing proves a list complete. Under
#      --unattended it is bounded by an allowlist instead (UNATTENDED below).
#
# UNATTENDED. --unattended says no person is at the keyboard: the copyable CI
# template's deliver (build-dispatch.sh) passes it on both of its calls. Under
# it, ANY change to .claude/productizer/checks-result.json - added, modified,
# deleted, or a change of type - is refusal 3, in every mode and beside any
# other change. Nothing in an unattended pipeline writes that file (the
# template runs no run-checks.sh), so a change to it is the run's own: a forged
# verdict that whatever reads the file after the merge would take as a
# measurement (maintainer ruling 2026-10-12, B126). Without the flag nothing
# changes: a person's run legitimately rewrites the file every time it runs
# run-checks.sh, so attended, its addition or modification stays "nothing".
#
# THE UNATTENDED ALLOWLIST (B125). Under --unattended a changed path is also
# refused (3) unless it has the shape a build's own output takes: its bytes
# are ASCII, and no component of it begins with a dot. The exceptions, on
# their exact bytes only, are the backlog, the plan in plan mode, and the spec
# outside build mode; the bookkeeping rules above are unchanged. Configuration
# of nearly every tool lives under a dot name - CI (.gitlab-ci.yml,
# .circleci/), editors that run tasks on open (.vscode/), dev containers,
# direnv, npm, linters that execute their config, other agents' rule files -
# so the files a reader must still trust the named list for are the ASCII,
# dot-free ones, and the list names those it knows (CLAUDE.md, AGENTS.md,
# REVIEW.md, CODEOWNERS, lefthook.yml). Attended runs keep the list alone: an
# allowlist would refuse a person's legitimate `.gitignore` edit, and a person
# sees the change. Measured by replaying this repository's 143 non-root
# commits at v4.69.1 as build -> test in build mode: the allowlist refuses 23
# that the list allows - 22 touch a plugin manifest under `.claude-plugin/`,
# which declares hooks and MCP servers and so steers an agent the list never
# named, and 1 touches `.gitignore`. An adopter's unattended build that edits
# a dot file exits 3, and that edit is a person's to make.
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
#           artifacts.path (on the folded key) that is not the backlog.
#           --mode is required for --to build.
#   deploy  NOT DECIDABLE HERE - exit 4. Deploy and done move on a MERGE, and a
#   done    merge is not visible in a patch or a diff between two refs.
#   other   (test, or a stage a config adds) with --mode build: the build-mode
#           evidence above, so a patch that edits only the plan does not move
#           build -> test (build-dispatch.sh asks exactly that). Otherwise:
#           any non-bookkeeping path that is not the backlog.
#
# INPUT. The patch text is never parsed here. --patch FILE is APPLIED BY GIT
# ITSELF, `git apply --cached --binary`, to a scratch index read from HEAD's
# tree, forward if it applies, else in reverse if it is already applied, else
# exit 4. New objects go to a temporary object directory, so the repository is
# not written. The changed paths are then git's own
# `git diff-tree -r -z --raw --no-renames` between the two trees: the
# paths judged are the paths `git apply --index` writes, with a rename's old
# side as a deletion, and a section git applies but a header reader would skip
# (a traditional `---`/`+++` section, a CRLF or tab-suffixed name, hunk
# headers naming another file than `diff --git`) is judged like any other.
# --base REF reads `git diff --raw --no-renames -z BASE...HEAD`. In both,
# git's status (A M D T) and both modes are kept, so a deleted plan.md is not
# evidence, a modified record is told from an added one, and a link is seen. A
# path holding a control character (newline, tab, carriage return) is exit 4,
# never a guess. --patch needs a repository with a HEAD commit to apply against.
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

VERSION="stage-advance 1.4"
SELF="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"

die_usage() { printf 'stage-advance: %s\n' "$1" >&2; exit 2; }

usage() {
  printf 'usage: stage-advance.sh [repo-root] --from STAGE --to STAGE\n'
  printf '                        (--patch FILE | --base REF [--head REF])\n'
  printf '                        [--mode plan|build] [--unattended] [--format text|json]\n'
  printf '       stage-advance.sh --selftest | --version | --help\n'
  printf '  --unattended  no person is at the keyboard: any change to\n'
  printf '                .claude/productizer/checks-result.json is refused (exit 3),\n'
  printf '                and so is any path that is not ASCII or has a component\n'
  printf '                beginning with a dot (bar the backlog, the plan, the spec)\n'
  printf 'exit: 0 advance allowed, 1 produced nothing, 2 usage, 3 forbidden path,\n'
  printf '      4 cannot determine, 5 not a forward move\n'
}

ROOT=""; FROM=""; TO=""; PATCH=""; BASE=""; HEAD_REF=""; MODE=""; FORMAT="text"
SELFTEST=0; UNATTENDED=0
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
    --unattended) UNATTENDED=1; shift ;;
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

  # A run that DELETES a bookkeeping record is refused, even when it also
  # produces a real plan.md: erasing a classification silences the governance
  # check that reads it. The committed record is at HEAD; the patch removes it
  # and adds a plan.md, so the real evidence cannot launder the deletion past.
  newrepo bk-delete; R="$WORK/bk-delete"
  mkdir -p "$R/.claude/productizer/classifications"
  printf 'Intent: 9\nClassification: contradict\n' \
    > "$R/.claude/productizer/classifications/9.md"
  commit "$R"
  mkdir -p "$R/docs/sdlc/greet"; printf '# Plan\n' > "$R/docs/sdlc/greet/plan.md"
  G "$R" rm --quiet .claude/productizer/classifications/9.md
  G "$R" add -A; G "$R" diff --cached > "$WORK/bk-delete.patch"
  drive bk-delete-record-refused 3 "a stage run may not erase an audit record" \
    "$R" --from design --to build --mode plan --patch "$WORK/bk-delete.patch"

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
  drive unattended-plan-exception 0 "docs/sdlc/greet/plan.md" \
    "$R" --from design --to build --mode plan --unattended --base base

  newrepo patch-design; R="$WORK/patch-design"
  cp "$R/.claude/productizer/spec.md" "$WORK/spec.orig"
  printf -- '- **R2** \342\200\224 The tool shall wave.\n' >> "$R/.claude/productizer/spec.md"
  G "$R" diff > "$WORK/design.patch"
  drive patch-already-applied 0 "R2 added" \
    "$R" --from intent --to design --patch "$WORK/design.patch"
  cp "$WORK/spec.orig" "$R/.claude/productizer/spec.md"
  drive patch-not-yet-applied 0 "R2 added" \
    "$R" --from intent --to design --patch "$WORK/design.patch"
  # B125: the spec's own exception under --unattended, outside build mode -
  # its path begins with a dot, and the allowlist must not refuse it there.
  drive unattended-spec-exception 0 "R2 added" \
    "$R" --from intent --to design --unattended --patch "$WORK/design.patch"

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
  # The backlog is allowed beside real work, and is not itself evidence (B120).
  local bl_add='diff --git a/.claude/productizer/backlog.md b/.claude/productizer/backlog.md\nnew file mode 100644\n--- /dev/null\n+++ b/.claude/productizer/backlog.md\n@@ -0,0 +1 @@\n+- B1\n'
  local app_mod='diff --git a/src/app.sh b/src/app.sh\n--- a/src/app.sh\n+++ b/src/app.sh\n@@ -1 +1 @@\n-echo hi\n+echo bye\n'
  # shellcheck disable=SC2059  # the format strings are the patch fixtures
  {
    printf "$bl_add$app_mod" > "$WORK/backlog.patch"
    printf "$bl_add" > "$WORK/backlog-only.patch"
  }
  drive backlog-allowed 0 "advance allowed: build -> test in build mode" \
    "$R" --from build --to test --mode build --patch "$WORK/backlog.patch"
  drive backlog-only-not-evidence 1 "a plan or a backlog row is not a build" \
    "$R" --from build --to test --mode build --patch "$WORK/backlog-only.patch"
  drive backlog-only-no-mode 1 "the backlog is the queue in front of intake, not a result" \
    "$R" --from build --to test --patch "$WORK/backlog-only.patch"

  # --- B114. A FOLDED VARIANT of a forbidden name. Each was allowed by 1.1,
  # which matched on ASCII lower case only. The long s (U+017F) and the Kelvin
  # sign (U+212A) open the ASCII file on a case-insensitive APFS volume
  # (measured); the fullwidth g (U+FF47) and the zero-width non-joiner
  # (U+200C) fold for a reader; an exception is granted on exact bytes only,
  # so a case variant of the backlog is not the backlog.
  local u
  for u in '.hu\305\277ky/pre-commit' '.hus\342\204\252y/pre-commit' 'AGENT\305\277.md' \
           'src/.gitattribute\305\277' '.\357\275\207ithub/workflows/x.yml' \
           '.git\342\200\214hub/workflows/x.yml' '.githooks' '.claude/productizer/BACKLOG.md'; do
    p="$(printf '%b' "$u")"; n=$((n + 1))
    printf 'diff --git a/%s b/%s\nnew file mode 100644\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1 @@\n+x\n' \
      "$p" "$p" "$p" > "$WORK/rule-$n.patch"
    drive "fold-variant-$n" 3 "forbidden for test: $p" \
      "$R" --from build --to test --mode build --patch "$WORK/rule-$n.patch"
  done
  # A non-ASCII name and a name that is not UTF-8 are judged, not refused.
  for u in 'src/caf\303\251.sh' 'src/\377.sh'; do
    p="$(printf '%b' "$u")"; n=$((n + 1))
    printf 'diff --git a/%s b/%s\nnew file mode 100644\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1 @@\n+x\n' \
      "$p" "$p" "$p" > "$WORK/rule-$n.patch"
    drive "fold-allowed-$n" 0 "$p" \
      "$R" --from build --to test --mode build --patch "$WORK/rule-$n.patch"
  done
  # --- B125. A HOMOGLYPH of a forbidden name, from another script. 1.3 folded
  # none of these and exited 0: a Cyrillic i, A, C and o; a division slash; a
  # Hangul filler, which is invisible and not a format character; and a dot
  # name no list holds, with a Cyrillic es.
  addpatch() {
    printf 'diff --git a/%s b/%s\nnew file mode 100644\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1 @@\n+x\n' \
      "$1" "$1" "$1" > "$2"
  }
  local reads
  for u in '.g\321\226thub/workflows/x.yml=.github/workflows/x.yml' '\320\220GENTS.md=agents.md' \
           'src/\320\241LAUDE.md=src/claude.md' 'd\320\276cs/CODEOWNERS=docs/codeowners' \
           'docs\342\210\225codeowners=docs/codeowners' '.git\343\205\244hub/workflows/x.yml=.github/workflows/x.yml' \
           '.vs\321\201ode/tasks.json=' ; do
    p="$(printf '%b' "${u%%=*}")"; reads="${u#*=}"; n=$((n + 1))
    addpatch "$p" "$WORK/rule-$n.patch"
    if [ -n "$reads" ]; then
      drive "homoglyph-$n" 3 "$p (not ASCII, and can be read as $reads)" \
        "$R" --from build --to test --mode build --patch "$WORK/rule-$n.patch"
    else
      drive "homoglyph-dot-name-$n" 3 "$p (not ASCII, under a name that begins with a dot)" \
        "$R" --from build --to test --mode build --patch "$WORK/rule-$n.patch"
    fi
  done
  # Precision: a reading that is no rule file, and a component with no ASCII
  # letter or digit (four Japanese characters are not read as `.git`).
  for u in 'd\320\276cs/readme.md' 'docs/ja/\343\201\257\343\201\230\343\202\201\343\201\253/x.md'; do
    p="$(printf '%b' "$u")"; n=$((n + 1))
    addpatch "$p" "$WORK/rule-$n.patch"
    drive "homoglyph-allowed-$n" 0 "$p" \
      "$R" --from build --to test --mode build --patch "$WORK/rule-$n.patch"
  done

  # --- B125. THE UNATTENDED ALLOWLIST: no dot component, ASCII bytes. 1.3
  # allowed each of these under --unattended; attended they stay allowed.
  for u in '.vscode/tasks.json=a name that begins with a dot' 'src/.eslintrc.js=a name that begins with a dot' \
           'plugins/x/.claude-plugin/plugin.json=a name that begins with a dot' 'src/caf\303\251.sh=not ASCII'; do
    p="$(printf '%b' "${u%%=*}")"; reads="${u#*=}"; n=$((n + 1))
    addpatch "$p" "$WORK/rule-$n.patch"
    drive "unattended-shape-$n" 3 "$p (unattended: $reads)" \
      "$R" --from build --to test --mode build --unattended --patch "$WORK/rule-$n.patch"
  done
  drive attended-dot-path-allowed 0 ".vscode/tasks.json" \
    "$R" --from build --to test --mode build --patch "$WORK/rule-$((n - 3)).patch"
  drive unattended-backlog-exception 0 "advance allowed: build -> test in build mode" \
    "$R" --from build --to test --mode build --unattended --patch "$WORK/backlog.patch"

  # A case variant of the artifacts directory is not "outside artifacts.path"
  # in build mode, so it is not evidence either (B106 meets B114).
  printf 'diff --git a/Docs/SDLC/greet/notes.md b/Docs/SDLC/greet/notes.md\nnew file mode 100644\n--- /dev/null\n+++ b/Docs/SDLC/greet/notes.md\n@@ -0,0 +1 @@\n+x\n' > "$WORK/art-variant.patch"
  drive build-mode-artifacts-variant-not-evidence 1 "a plan or a backlog row is not a build" \
    "$R" --from build --to test --mode build --patch "$WORK/art-variant.patch"

  # --- B114. LINKS. 1.1 allowed every one of these with exit 0.
  # shellcheck disable=SC2059  # the format strings are the patch fixtures
  {
    printf 'diff --git a/src/wf b/src/wf\nnew file mode 120000\n--- /dev/null\n+++ b/src/wf\n@@ -0,0 +1 @@\n+../.github/workflows\n\\ No newline at end of file\n' > "$WORK/l-sym.patch"
    printf 'diff --git a/sub/.claude b/sub/.claude\nnew file mode 120000\n--- /dev/null\n+++ b/sub/.claude\n@@ -0,0 +1 @@\n+../docs\n\\ No newline at end of file\n' > "$WORK/l-nested-claude.patch"
    printf 'diff --git a/.github b/.github\nnew file mode 120000\n--- /dev/null\n+++ b/.github\n@@ -0,0 +1 @@\n+docs/ci\n\\ No newline at end of file\n' > "$WORK/l-github.patch"
    printf 'diff --git a/vendor/lib b/vendor/lib\nnew file mode 160000\nindex 0000000..%s\n--- /dev/null\n+++ b/vendor/lib\n@@ -0,0 +1 @@\n+Subproject commit %s\n' \
      "$(G "$R" rev-parse --short=7 HEAD)" "$(G "$R" rev-parse HEAD)" > "$WORK/l-gitlink.patch"
  }
  drive link-symlink-at-allowed-path 3 "src/wf (symbolic link)" \
    "$R" --from build --to test --mode build --patch "$WORK/l-sym.patch"
  drive link-nested-claude-symlink 3 "sub/.claude (symbolic link)" \
    "$R" --from build --to test --mode build --patch "$WORK/l-nested-claude.patch"
  drive link-github-symlink 3 ".github (symbolic link)" \
    "$R" --from build --to test --patch "$WORK/l-github.patch"
  drive link-gitlink-added 3 "vendor/lib (gitlink)" \
    "$R" --from build --to test --mode build --patch "$WORK/l-gitlink.patch"
  newrepo links; R="$WORK/links"
  ln -s app.sh "$R/src/l"; commit "$R"; G "$R" tag with-link
  G "$R" update-index --add --cacheinfo "160000,$(G "$R" rev-parse HEAD),vendor/lib"
  G "$R" commit --quiet -m gitlink
  drive link-gitlink-base-mode 3 "vendor/lib (gitlink)" \
    "$R" --from build --to test --mode build --base with-link
  G "$R" rm --quiet --cached vendor/lib; G "$R" commit --quiet -m no-gitlink
  G "$R" rm --quiet src/l; G "$R" diff --cached > "$WORK/l-delete.patch"
  G "$R" commit --quiet -m no-link
  drive link-symlink-deleted-judged-by-path 0 "src/l" \
    "$R" --from build --to test --mode build --patch "$WORK/l-delete.patch"

  # --- B114. An NFD spelling of a non-ASCII spec path, in build mode. git
  # stores the bytes, so it is a new file in the index; a normalisation-
  # insensitive checkout (APFS) writes it onto the spec. 1.1 exited 0.
  newrepo nfd; R="$WORK/nfd"
  mkdir -p "$R/docs"
  printf '{ "spec": { "path": "docs/sp\303\251c.md" } }\n' > "$R/.claude/productizer/config.json"
  printf -- '- **R1** \342\200\224 The tool shall greet.\n' > "$R/docs/sp"$'\303\251'"c.md"
  commit "$R"
  p="$(printf 'docs/spe\314\201c.md')"
  printf 'diff --git a/%s b/%s\nnew file mode 100644\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1 @@\n+x\n' \
    "$p" "$p" "$p" > "$WORK/nfd.patch"
  drive nfd-variant-of-spec-forbidden 3 "forbidden for test: $p" \
    "$R" --from build --to test --mode build --patch "$WORK/nfd.patch"
  # B125: a homoglyph of the spec's directory, read against the spec's key.
  p="$(printf 'd\320\276cs/sp\303\251c.md')"
  addpatch "$p" "$WORK/spec-homoglyph.patch"
  drive homoglyph-of-spec-build-mode 3 "$p (not ASCII, and can be read as docs/sp"$'\303\251'"c.md)" \
    "$R" --from build --to test --mode build --patch "$WORK/spec-homoglyph.patch"

  # --- B117. A write-once record MODIFIED. Their writers refuse to overwrite
  # one, so a rewrite is never theirs; 1.1 let it pass beside a real plan.
  newrepo bk-rewrite; R="$WORK/bk-rewrite"
  mkdir -p "$R/.claude/productizer/classifications" "$R/.claude/productizer/snapshots/stage-3"
  printf 'Intent: 9\nClassification: contradict\n' > "$R/.claude/productizer/classifications/9.md"
  printf 'x\n' > "$R/.claude/productizer/snapshots/stage-3/a.snap"
  printf '{"pass": false}\n' > "$R/.claude/productizer/checks-result.json"
  commit "$R"; G "$R" tag records
  mkdir -p "$R/docs/sdlc/greet"; printf '# Plan\n' > "$R/docs/sdlc/greet/plan.md"
  printf 'Intent: 9\nClassification: extend\n' > "$R/.claude/productizer/classifications/9.md"
  G "$R" add -A; G "$R" diff --cached > "$WORK/bk-rewrite.patch"; G "$R" reset --quiet --hard
  drive bk-classification-rewritten 3 "a stage run may not alter an audit record" \
    "$R" --from design --to build --mode plan --patch "$WORK/bk-rewrite.patch"
  printf 'y\n' > "$R/.claude/productizer/snapshots/stage-3/a.snap"
  printf 'echo bye\n' > "$R/src/app.sh"
  commit "$R"
  drive bk-snapshot-rewritten 3 "Rewritten: .claude/productizer/snapshots/stage-3/a.snap" \
    "$R" --from build --to test --mode build --base records
  G "$R" tag snap-rewritten
  printf '{"pass": true}\n' > "$R/.claude/productizer/checks-result.json"
  commit "$R"
  drive bk-checks-result-rewritten-inert 1 "produced nothing outside the lifecycle's own bookkeeping" \
    "$R" --from build --to test --mode build --base snap-rewritten

  # --- B126. --unattended: ANY change to the checks result is refused, alone
  # or beside code, under --patch and --base. Attended, nothing changes: an
  # addition or a modification is inert, and a deletion is R66's refusal.
  local CR=".claude/productizer/checks-result.json"
  newrepo un-cr; R="$WORK/un-cr"
  printf '{"pass": true}\n' > "$R/$CR"
  G "$R" add -A; G "$R" diff --cached > "$WORK/un-add.patch"; G "$R" reset --quiet --hard
  drive unattended-checks-result-added 3 "Changed: $CR (added)" \
    "$R" --from build --to test --mode build --unattended --patch "$WORK/un-add.patch"
  drive attended-checks-result-added-inert 1 "produced nothing outside the lifecycle's own bookkeeping" \
    "$R" --from build --to test --mode build --patch "$WORK/un-add.patch"
  printf '{"pass": false}\n' > "$R/$CR"; commit "$R"; G "$R" tag with-result
  printf '{"pass": true}\n' > "$R/$CR"
  G "$R" diff > "$WORK/un-mod.patch"
  printf 'echo bye\n' > "$R/src/app.sh"
  G "$R" diff > "$WORK/un-mod-code.patch"; G "$R" restore -- .
  G "$R" rm --quiet "$CR"; G "$R" diff --cached > "$WORK/un-del.patch"; G "$R" reset --quiet --hard
  printf 'echo bye\n' > "$R/src/app.sh"; G "$R" diff > "$WORK/un-code.patch"; G "$R" restore -- src/app.sh
  drive unattended-checks-result-modified 3 "Changed: $CR (modified)" \
    "$R" --from build --to test --mode build --unattended --patch "$WORK/un-mod.patch"
  drive attended-checks-result-modified-inert 1 "produced nothing outside the lifecycle's own bookkeeping" \
    "$R" --from build --to test --mode build --patch "$WORK/un-mod.patch"
  drive unattended-checks-result-deleted 3 "Changed: $CR (deleted)" \
    "$R" --from build --to test --mode build --unattended --patch "$WORK/un-del.patch"
  drive attended-checks-result-deleted-r66 3 "a stage run may not erase an audit record" \
    "$R" --from build --to test --mode build --patch "$WORK/un-del.patch"
  drive unattended-checks-result-beside-code 3 "a stage run may not write the verdict it is judged by" \
    "$R" --from build --to test --mode build --unattended --patch "$WORK/un-mod-code.patch"
  drive attended-checks-result-beside-code 0 "src/app.sh" \
    "$R" --from build --to test --mode build --patch "$WORK/un-mod-code.patch"
  drive unattended-code-allowed 0 "src/app.sh" \
    "$R" --from build --to test --mode build --unattended --patch "$WORK/un-code.patch"
  printf '{"pass": true}\n' > "$R/$CR"; printf 'echo bye\n' > "$R/src/app.sh"; commit "$R"
  drive unattended-checks-result-base-mode 3 "Changed: $CR (modified)" \
    "$R" --from build --to test --mode build --unattended --base with-result

  # --- B125. The allowlist on a commit (--base), as deliver's second ask
  # reads it: a .gitignore beside code is refused unattended, allowed attended.
  newrepo un-dot; R="$WORK/un-dot"
  printf 'x\n' > "$R/.gitignore"; printf 'echo bye\n' > "$R/src/app.sh"; commit "$R"
  drive unattended-dot-path-base-mode 3 ".gitignore (unattended: a name that begins with a dot)" \
    "$R" --from build --to test --mode build --unattended --base base
  drive attended-dot-path-base-mode 0 ".gitignore" \
    "$R" --from build --to test --mode build --base base

  # --- B120. The backlog in build mode: an item may be added, none changed.
  newrepo bl; R="$WORK/bl"
  printf '| B1 | a wish | todo |\n' > "$R/.claude/productizer/backlog.md"
  commit "$R"
  printf '| B1 | a wish | done |\n' > "$R/.claude/productizer/backlog.md"
  printf 'echo bye\n' > "$R/src/app.sh"
  G "$R" diff > "$WORK/bl-rewrite.patch"; G "$R" restore -- .claude/productizer/backlog.md src/app.sh
  drive backlog-row-rewritten-build-mode 3 "a build run may add an item to the backlog but not change one" \
    "$R" --from build --to test --mode build --patch "$WORK/bl-rewrite.patch"
  drive backlog-row-rewritten-no-mode 0 "src/app.sh" \
    "$R" --from build --to test --patch "$WORK/bl-rewrite.patch"
  printf '| B2 | another wish | todo |\n' >> "$R/.claude/productizer/backlog.md"
  printf 'echo bye\n' > "$R/src/app.sh"
  commit "$R"
  drive backlog-row-added-build-mode 0 "src/app.sh" \
    "$R" --from build --to test --mode build --base base

  # --- B106. build mode asks build -> test, and a plan alone is not a build.
  R="$WORK/plan-ok"
  drive build-mode-test-only-plan 1 "a plan or a backlog row is not a build" \
    "$R" --from build --to test --mode build --base base
  drive no-mode-test-plan-counts 0 "docs/sdlc/greet/plan.md" \
    "$R" --from build --to test --base base
  R="$WORK/plan-src"
  drive build-mode-test-code 0 "src/app.sh" \
    "$R" --from build --to test --mode build --base base
  R="$WORK/rules"

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
  printf '    NOT ASSERTED: a header with an unquoted space; the label form of --from for every stage; a custom stage other than design/build with evidence; --head other than HEAD (build-dispatch.sh drives it); a requirement WITHDRAWN; that nothing is written outside the fixtures checked for it; that build-mode evidence outside artifacts.path is code rather than prose (a README edit counts); a backlog line ADDED in build mode that satisfies a check reading the backlog (check-import-marking reads a named stage there); the checks result MODIFIED in an ATTENDED run, which stays inert because run-checks.sh rewrites it every run, so a forged one is caught only under --unattended; the checks result RETYPED under --unattended (into a symlink it is refused as a link; out of one, no case drives it); that a caller which should pass --unattended does (build-dispatch.sh'"'"'s self-test drives its two calls); a write-once record MODIFIED by its own writer, which never happens (both refuse to overwrite); that the forbidden set is every file that steers CI or an agent - attended it is a list, and under --unattended the allowlist still admits an ASCII, dot-free file the list does not name (Jenkinsfile, azure-pipelines.yml, GEMINI.md, a package.json script, a script checks.yaml runs); a homoglyph read as more than two characters, or one a component with no ASCII letter or digit holds; a homoglyph made of ASCII alone (rn for m); that no legitimate non-ASCII name is refused attended (a six-letter Cyrillic name ending .md is read as agents.md and refused); a bookkeeping record ADDED under --unattended, which stays inert.\n'
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

# --- the changed paths: one "STATUS<TAB>OLDMODE<TAB>NEWMODE<TAB>path" per line
# read_raw: git's NUL-separated `--raw -z` stream on stdin -> one line per
# path, STATUS one of A M D T, the modes as git reports them (000000 for "no
# such side"). The list below is newline-separated, so a path holding a
# control character is printed as "?<TAB><quoted path>" and refused: a name is
# never split, joined or guessed at. The modes are kept because a symbolic
# link (120000) and a gitlink (160000) are judged by what they are, not only by
# their name; the status is kept because a bookkeeping record ADDED and one
# MODIFIED are different acts, and git reports them differently (A and M).
read_raw() {
  local meta p om nm st
  while IFS= read -r -d '' meta && IFS= read -r -d '' p; do
    if [[ "$p" == *[[:cntrl:]]* ]]; then printf '?\t%q\n' "$p"; continue; fi
    read -r om nm _ _ st <<< "${meta#:}"
    printf '%s\t%s\t%s\t%s\n' "${st:0:1}" "$om" "$nm" "$p"
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
    CHANGES="$(SG diff-tree -r -z --raw --no-renames "$PT_BASE" "$PT_HEAD" | read_raw)" \
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
  CHANGES="$(git -C "$ROOT" diff --raw --no-renames -z "$BASE...$HEAD_REF" | read_raw)" \
    || finish 4 "cannot determine the changed paths: git diff $BASE...$HEAD_REF failed"
fi
if grep -q '^?' <<<"$CHANGES"; then
  bad="$(grep '^?' <<<"$CHANGES")"
  finish 4 "cannot determine the changed paths: a changed path holds a control character (newline, tab or carriage return), and such a name is not judged: $(head -n 1 <<<"$bad" | cut -f2-)"
fi
CHANGES="$(printf '%s\n' "$CHANGES" | awk 'NF' | sort -u)"

# THE FORBIDDEN SET, every mode. The one place it is written - four lists of
# folded names and the function that reads them; the header's FORBIDDEN PATH
# list and references/ci-build.md describe them. The homoglyph rule reads the
# same lists, so a name added here is guarded against a homoglyph too.
#   ROOT_TREES    the name at the root, and everything under it
#   NESTED_TREES  the name below the root, and everything under it
#   ROOT_FILES    exactly this path from the root
#   BASENAMES     a file of this name at any depth
FORBID_ROOT_TREES=".github .claude .git .husky .githooks .productizer-run .productizer-tools"
FORBID_NESTED_TREES=".claude .git"
FORBID_ROOT_FILES=".pre-commit-config.yaml lefthook.yml .lefthook.yml lefthook-local.yml .lefthook-local.yml codeowners docs/codeowners review.md"
FORBID_BASENAMES="claude.md claude.local.md agents.md .mcp.json .gitattributes .gitmodules"

# --- the folded key ---------------------------------------------------------
# A forbidden name is matched on a FOLDED KEY of the path, not on its bytes:
# format characters (Unicode category Cf: zero-width joiners, direction marks,
# the byte-order mark) removed, then NFKC, then full Unicode case folding, then
# NFKC again. That folds what a file system folds onto the same file - case,
# NFD against NFC, the long s and the Kelvin sign onto `s` and `k` (measured on
# a case-insensitive APFS volume: `.hu<U+017F>ky/pre-commit` and
# `.hus<U+212A>y/pre-commit` both opened `.husky/pre-commit`) - and also a
# compatibility form such as a fullwidth letter, which no file system folds but
# a reader does. The key only ever REFUSES: an exception (bookkeeping, the
# backlog, the spec outside build mode, the plan in plan mode) is granted on
# the exact bytes, never on the key, so a variant spelling never inherits one.
# A bytes-invalid name is folded through surrogate escapes and judged, not
# guessed at.
#
# A HOMOGLYPH from another script (a Cyrillic letter for a Latin one) is not
# folded by any file system or by git, and Python's standard library carries
# no Unicode confusables table (TR39) to fold it with. So no table is used:
# every character the key still holds outside ASCII is READ as ANY character,
# a slash included - exactly one, or none to one for a combining mark or a
# filler (the Hangul filler is invisible and not a format character), or one
# to two for a Latin letter (a digraph such as U+02A3). A component of the
# key that holds such a character and at least one ASCII letter or digit is
# matched, so read, against every name in the forbidden lists and the spec's
# key, and every component of each; each name it can be read as gives a
# CANDIDATE key with that component replaced, and a candidate the forbidden
# set refuses refuses the path. That is a superset of every one-for-one
# confusable a table would list. A component with no ASCII letter or digit is
# not read (a Japanese directory of four characters is not `.git`), and a
# non-ASCII path with a component that begins with a dot is refused outright
# (any tool's configuration hides there, listed or not). Measured on this
# repository's history at v4.69.1: 0 of 2127 changed paths in 144 commits
# hold a byte outside ASCII.
# shellcheck disable=SC2086  # each FORBID_* list splits into one name per argument
FOLDED="$(printf '%s\n' "$CHANGES" | python3 -I -c '
import itertools, re, sys, unicodedata
def key(s):
    s = "".join(c for c in s if unicodedata.category(c) != "Cf")
    return unicodedata.normalize("NFKC", unicodedata.normalize("NFKC", s).casefold())
def b2s(b): return b.decode("utf-8", "surrogateescape")
def s2b(s): return s.encode("utf-8", "surrogateescape")
out = sys.stdout.buffer
spec, art = (key(b2s(s2b(a))) for a in sys.argv[1:3])
names = set(sys.argv[3:]) | {spec}
names |= {part for n in names for part in n.split("/")}
def span(ch):
    # How many characters one non-ASCII character can be read as.
    n = unicodedata.name(ch, "")
    if unicodedata.category(ch) in ("Mn", "Me") or "FILLER" in n or "BLANK" in n:
        return (0, 1)
    if n.startswith("LATIN "):
        return (1, 2)
    return (1, 1)
def reading(comp):
    rx = ""
    for ch in comp:
        if ch.isascii():
            rx += re.escape(ch)
        else:
            lo, hi = span(ch)
            rx += ".{%d,%d}" % (lo, hi)
    return re.compile(rx, re.S)
def candidates(k):
    comps = k.split("/")
    opts = []
    for c in comps:
        if c.isascii() or not re.search(r"[a-z0-9]", c):
            opts.append([c])
        else:
            rx = reading(c)
            opts.append([c] + sorted(n for n in names if rx.fullmatch(n)))
    cands = []
    for combo in itertools.product(*opts):
        cand = "/".join(combo)
        if cand != k and cand not in cands:
            cands.append(cand)
        if len(cands) >= 64: break
    return cands
out.write(s2b(spec) + b"\n" + s2b(art) + b"\n")
for line in sys.stdin.buffer.read().split(b"\n"):
    if not line: continue
    f = line.split(b"\t", 3)
    k = key(b2s(f[3]))
    ascii_ = b"1" if f[3].isascii() else b"0"
    cands = candidates(k) if not k.isascii() else []
    out.write(line + b"\t" + s2b(k) + b"\t" + ascii_ + b"\t" + b"\x1f".join(s2b(c) for c in cands) + b"\n")
' "$SPEC" "$ART" $FORBID_ROOT_TREES $FORBID_NESTED_TREES $FORBID_ROOT_FILES $FORBID_BASENAMES)" \
  || finish 4 "cannot fold the changed paths to their comparison key (python3 failed)"
SPEC_KEY="$(printf '%s\n' "$FOLDED" | sed -n 1p)"
ART_KEY="$(printf '%s\n' "$FOLDED" | sed -n 2p)"
CHANGES="$(printf '%s\n' "$FOLDED" | sed 1,2d)"

# --- classify ---------------------------------------------------------------
ere_escape() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'; }
ART_RE="^$(ere_escape "$ART" | sed 's/<[^>]*>/[^\/]+/g')/"
ART_KEY_RE="^$(ere_escape "$ART_KEY" | sed 's/<[^>]*>/[^\/]+/g')/"
PLAN_RE="${ART_RE}plan\\.md\$"
BACKLOG=".claude/productizer/backlog.md"
CHECKS_RESULT=".claude/productizer/checks-result.json"

is_bookkeeping() {
  case "$1" in
    .claude/productizer/snapshots/*|.claude/productizer/classifications/*) return 0 ;;
    .claude/productizer/checks-result.json) return 0 ;;
  esac
  return 1
}
# Written once by their writers and never updated: stage-snapshot.sh and
# record-classification.sh both refuse to overwrite (exit 1).
is_write_once() {
  case "$1" in
    .claude/productizer/snapshots/*|.claude/productizer/classifications/*) return 0 ;;
  esac
  return 1
}
# THE FORBIDDEN SET is the four FORBID_* lists above the folded key, read by
# this function.
# forbidden_any_mode <path> <folded key>
forbidden_any_mode() {
  local raw="$1" k="$2" n
  for n in $FORBID_ROOT_TREES; do
    case "$k" in
      "$n"|"$n"/*)
        if [ "$n" = .claude ]; then
          is_bookkeeping "$raw" && return 1
          [ "$raw" = "$BACKLOG" ] && return 1
          [ "$MODE" != "build" ] && [ "$raw" = "$SPEC" ] && return 1
        fi
        return 0 ;;
    esac
  done
  for n in $FORBID_NESTED_TREES; do
    case "$k" in */"$n"|*/"$n"/*) return 0 ;; esac
  done
  for n in $FORBID_ROOT_FILES; do
    [ "$k" = "$n" ] && return 0
  done
  for n in $FORBID_BASENAMES; do
    [ "${k##*/}" = "$n" ] && return 0
  done
  return 1
}
# An exception granted on the exact bytes: the backlog, the spec outside build
# mode, and in plan mode the plan. The shape rules below never refuse one.
is_exact_exception() {
  [ "$1" = "$BACKLOG" ] && return 0
  [ "$MODE" != "build" ] && [ "$1" = "$SPEC" ] && return 0
  [ "$MODE" = "plan" ] && [[ "$1" =~ $PLAN_RE ]] && return 0
  return 1
}
# has_dot_component <folded key>: a component begins with a dot.
has_dot_component() { case "/$1" in */.*) return 0 ;; esac; return 1; }
# is_forbidden <path> <folded key>
is_forbidden() {
  forbidden_any_mode "$1" "$2" && return 0
  [ "$MODE" = "build" ] && [ "$2" = "$SPEC_KEY" ] && return 0
  [ "$MODE" = "plan" ] && ! [[ "$1" =~ $PLAN_RE ]] && ! is_bookkeeping "$1" && return 0
  return 1
}

REAL=""; BK_DELETED=""; BK_REWRITTEN=""; BK_UNATTENDED=""; LINKS=""; BACKLOG_ST=""
SHAPE_REFUSED=0
while IFS=$'\t' read -r st om nm p k a c; do
  [ -n "$p" ] || continue
  # A LINK, any path, any mode. A symbolic link makes one name stand for
  # another path, and a gitlink makes one name stand for a commit of code that
  # is not in this change. This decider judges names, so it cannot judge what
  # either points at: a symlink `sub/.claude` -> an allowed directory the run
  # also wrote would hand an agent started in sub/ the run's own settings.
  # Refused when a symlink is created or retargeted, and when a gitlink is
  # added, repointed or removed. Deleting a symlink, or replacing one by a
  # file, is judged like any other path.
  if [ "$nm" = 120000 ] && [ "$st" != D ]; then LINKS="$LINKS$p (symbolic link)"$'\n'; continue; fi
  if [ "$nm" = 160000 ] || [ "$om" = 160000 ]; then LINKS="$LINKS$p (gitlink)"$'\n'; continue; fi
  if is_bookkeeping "$p"; then
    # Bookkeeping ADDED is inert - the "produced nothing" case. Bookkeeping
    # DELETED is not: a classification, a snapshot or the checks result is an
    # audit record a later stage and the governance checks read, and erasing
    # one lets a run flip a check from a finding to clean. A stage run is the
    # wrong actor to erase the record it is judged by, so a deletion here is
    # forbidden in every mode, exactly as editing a rule file is. A snapshot
    # or a classification MODIFIED (or retyped) is refused the same way: their
    # writers never update one, so a rewrite is never theirs. The checks
    # result is rewritten by every run of run-checks.sh, so its modification
    # stays inert, like an addition - when a person runs it. UNATTENDED, any
    # change to the checks result is the run's own: nothing in an unattended
    # pipeline writes it (B126).
    if [ "$UNATTENDED" = 1 ] && [ "$p" = "$CHECKS_RESULT" ]; then
      case "$st" in A) w=added ;; D) w=deleted ;; T) w=retyped ;; *) w=modified ;; esac
      BK_UNATTENDED="$BK_UNATTENDED$p ($w)"$'\n'
    elif [ "$st" = D ]; then BK_DELETED="$BK_DELETED$p"$'\n'
    elif [ "$st" != A ] && is_write_once "$p"; then BK_REWRITTEN="$BK_REWRITTEN$p"$'\n'
    fi
    continue
  fi
  [ "$p" = "$BACKLOG" ] && BACKLOG_ST="$st"
  REAL="$REAL$st"$'\t'"$p"$'\t'"$k"$'\n'
  if is_forbidden "$p" "$k"; then FORBIDDEN="$FORBIDDEN$p"$'\n'; continue; fi
  is_exact_exception "$p" && continue
  # A HOMOGLYPH, any mode: a path whose bytes are not ASCII is refused when a
  # reading of it (see "the folded key") is a path the set above refuses, or
  # when it has a component that begins with a dot.
  if [ "$a" = 0 ]; then
    hit=""
    if [ -n "$c" ]; then
      IFS=$'\x1f' read -r -a cands <<< "$c"
      for cand in "${cands[@]}"; do
        if is_forbidden "$p" "$cand"; then hit="$cand"; break; fi
      done
    fi
    if [ -n "$hit" ]; then FORBIDDEN="$FORBIDDEN$p (not ASCII, and can be read as $hit)"$'\n'; continue; fi
    if has_dot_component "$k"; then FORBIDDEN="$FORBIDDEN$p (not ASCII, under a name that begins with a dot)"$'\n'; continue; fi
  fi
  # THE UNATTENDED ALLOWLIST. With no person at the keyboard, a path is
  # allowed only in the shape a build's own output takes: ASCII bytes, and no
  # component that begins with a dot. Everything else is refused, listed or
  # not, so the files a reader must trust the list for are the ASCII ones with
  # no dot - and the named set above still refuses those it names.
  if [ "$UNATTENDED" = 1 ]; then
    if [ "$a" = 0 ]; then
      FORBIDDEN="$FORBIDDEN$p (unattended: not ASCII)"$'\n'; SHAPE_REFUSED=1
    elif has_dot_component "$k"; then
      FORBIDDEN="$FORBIDDEN$p (unattended: a name that begins with a dot)"$'\n'; SHAPE_REFUSED=1
    fi
  fi
done <<< "$CHANGES"

if [ -n "$BK_UNATTENDED" ]; then
  FORBIDDEN="$CHECKS_RESULT"
  finish 3 "the change touches the lifecycle's checks result in an unattended run; nothing in an unattended pipeline writes $CHECKS_RESULT, so any change to it is the run's own, and a stage run may not write the verdict it is judged by. Changed: $(printf '%s' "$BK_UNATTENDED" | tr '\n' ' ' | sed 's/ $//')"
fi
if [ -n "$BK_DELETED" ]; then
  FORBIDDEN="$BK_DELETED"
  finish 3 "the change deletes lifecycle bookkeeping that a later stage and the governance checks read; a stage run may not erase an audit record (a classification, a snapshot or the checks result). Deleted: $(printf '%s' "$BK_DELETED" | tr '\n' ' ' | sed 's/ $//')"
fi
if [ -n "$BK_REWRITTEN" ]; then
  FORBIDDEN="$BK_REWRITTEN"
  finish 3 "the change rewrites lifecycle bookkeeping that is written once and never updated; a stage run may not alter an audit record (a stage snapshot or a classification), and its writer never would. Rewritten: $(printf '%s' "$BK_REWRITTEN" | tr '\n' ' ' | sed 's/ $//')"
fi
if [ -n "$LINKS" ]; then
  FORBIDDEN="$LINKS"
  finish 3 "the change creates or retargets a symbolic link, or adds, repoints or removes a gitlink (submodule entry); a link makes a name stand for another path or for code outside the change, which a decider that judges names cannot judge, so a stage run may not make one. Links: $(printf '%s' "$LINKS" | tr '\n' ' ' | sed 's/ $//')"
fi

[ -n "$REAL" ] \
  || finish 1 "the run produced nothing outside the lifecycle's own bookkeeping; $FROM_KEY -> $TO_KEY has no result to take over"
if [ -n "$FORBIDDEN" ]; then
  SHAPE_NOTE=""
  [ "$SHAPE_REFUSED" = 0 ] || SHAPE_NOTE="; under --unattended a path is allowed only when its bytes are ASCII and no component of it begins with a dot, bar the backlog, the plan in plan mode and the spec outside build mode on their exact bytes"
  finish 3 "the change touches a path the target stage does not permit${MODE:+ in $MODE mode}; forbidden for $TO_KEY: $(printf '%s' "$FORBIDDEN" | tr '\n' ' ' | sed 's/ $//')$SHAPE_NOTE"
fi

# THE BACKLOG IN BUILD MODE: an item may be ADDED, none removed or rewritten.
# Checks read its lines - a `classified` line demands a classification record
# (check-classification-provenance.sh), so deleting one silences that demand -
# and a row's status is the record of what was agreed. A build run has no
# reason to change either. Plan mode already forbids the file.
if [ "$MODE" = "build" ] && [ -n "$BACKLOG_ST" ]; then
  if [ "$BACKLOG_ST" = D ]; then
    BL_DEL="all"
  elif [ -n "$PATCH" ]; then
    BL_DEL="$(SG diff-tree -r --numstat "$PT_BASE" "$PT_HEAD" -- "$BACKLOG" | cut -f2)" \
      || finish 4 "cannot count the lines the change removes from $BACKLOG"
  else
    BL_DEL="$(git -C "$ROOT" diff --numstat "$BASE...$HEAD_REF" -- "$BACKLOG" | cut -f2)" \
      || finish 4 "cannot count the lines the change removes from $BACKLOG"
  fi
  if [ "$BL_DEL" != 0 ]; then
    FORBIDDEN="$BACKLOG"
    finish 3 "the change removes or rewrites existing lines of $BACKLOG in build mode ($BL_DEL line(s) removed); a build run may add an item to the backlog but not change one, because checks read its lines and a row's status is the record of what was agreed"
  fi
fi

# --- evidence per target stage ----------------------------------------------
spec_records() {
  # spec_records <file> -> "id<TAB>status<TAB>target<TAB>text", line dropped
  bash "$SCRIPT_DIR/spec-requirements.sh" "$1" | cut -f1,3,4,5 | sort
}

# BUILD-MODE EVIDENCE, for EVERY target --mode build is asked about, not only
# `build`: build-dispatch.sh asks build -> test in build mode, and a patch that
# edits only the plan is not a build. Evidence is a changed path outside
# artifacts.path, compared on the folded key so a variant spelling of the
# artifacts directory does not count as outside it, and never the backlog.
build_mode_evidence() {
  printf '%s' "$REAL" | RE="$ART_KEY_RE" BL="$BACKLOG" \
    awk -F'\t' '$3 !~ ENVIRON["RE"] && $2 != ENVIRON["BL"] { print $2 }'
}
build_mode_nothing() {
  printf "produced nothing for %s in build mode: no path outside the lifecycle's artifacts (%s) and the backlog changed; a plan or a backlog row is not a build" "$1" "$ART"
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
      EVIDENCE="$(build_mode_evidence)"
      [ -n "$EVIDENCE" ] || finish 1 "$(build_mode_nothing build)"
    fi
    finish 0 "advance allowed: $FROM_KEY -> build in $MODE mode"
    ;;
  *)
    if [ "$MODE" = "build" ]; then
      EVIDENCE="$(build_mode_evidence)"
      [ -n "$EVIDENCE" ] || finish 1 "$(build_mode_nothing "$TO_KEY")"
    else
      EVIDENCE="$(printf '%s' "$REAL" | BL="$BACKLOG" awk -F'\t' '$2 != ENVIRON["BL"] { print $2 }')"
      [ -n "$EVIDENCE" ] \
        || finish 1 "produced nothing for $TO_KEY: the only change outside the lifecycle's bookkeeping is $BACKLOG, and the backlog is the queue in front of intake, not a result"
    fi
    finish 0 "advance allowed: $FROM_KEY -> $TO_KEY${MODE:+ in $MODE mode}"
    ;;
esac
