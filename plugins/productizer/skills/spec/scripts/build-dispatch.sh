#!/usr/bin/env bash
# build-dispatch.sh prepare [repo-root] --mode plan|build --issue N
#                           --default-branch NAME --out DIR [--spec-base SHA]
#                           [--permissions repo-settings|edits-only]
# build-dispatch.sh deliver [repo-root] --mode plan|build --issue N
#                           --patch FILE --run-id ID --default-branch NAME
#                           [--spec-base SHA] [--dry-run]
# build-dispatch.sh --selftest | --version | --help
#
# THE TWO ENDS OF AN UNATTENDED RUN. `templates/build-from-spec.yml` is a
# workflow a repository owner copies into their own repository; it runs one
# stage of the lifecycle with no person at the keyboard. This script is
# everything that workflow does on either side of the model, so that none of
# it lives as untested shell inside YAML:
#
#   prepare  runs BEFORE the model, with a read-only token. It decides whether
#            there is anything to do at all, and writes the data the agent
#            reads: the spec's diff against the base it builds from, the plan
#            path, and the model flags taken from config.json. Nothing here
#            calls a model, so a refusal here costs nothing.
#   deliver  runs AFTER the model, in the only job holding a write token. It
#            asks stage-advance.sh whether the patch the agent produced is a
#            change this stage may make, and only then commits it to a new
#            branch. Then it asks AGAIN, on that commit (--base HEAD --head
#            the commit), so the decision that gates the push is made on what
#            `git apply --index` actually staged, never on the patch text.
#            Only then does it push the branch and open a DRAFT pull request.
#            A refusal at either point is exit 6, and the branch is deleted.
#
# Adapted from the AI Unified Process generate workflow (Apache-2.0, Simon
# Martinelli), `.github/workflows/aiup-generate.yml`: a dispatched run whose
# only output is a pull request, the spec's diff travelling with the prompt,
# git denied to the agent, and the run's id named in the pull request. The
# idea is adopted; no code is copied.
#
# WHAT IT NEVER DOES. It never writes to the default branch: the branch it
# pushes is always `productizer/<mode>-<issue>-<run-id>`, pushed by an explicit
# refspec. It never opens a pull request that is not a draft. It never takes a
# requirement id from the model: the ids in the commit trailer are the ones
# whose records differ between the spec at the base and the spec at HEAD, read
# by spec-requirements.sh. And it refuses to act on a HEAD that is not the tip
# of the default branch, because a run dispatched on one commit and delivered
# onto another is a change nobody looked at.
#
# STAGES. plan mode asks stage-advance.sh for design -> build with --mode plan
# (the evidence is a plan.md under artifacts.path, and every other path is
# forbidden). build mode asks for build -> test with --mode build (the spec is
# forbidden; any non-bookkeeping path is evidence). intent -> design was
# considered for plan mode and rejected: design's evidence is a requirement
# record that moved, and plan mode is forbidden to touch the spec, so it could
# only ever answer "produced nothing".
#
# THE BASE. --spec-base when given (a full 40-character commit id). Otherwise
# the first parent of the newest commit in HEAD's first-parent history that
# changed the spec or the constitution: the state of the default branch just
# before the spec change this run builds from was merged.
#
# THE PLAN PATH. artifacts.path from config.json with its <slug> placeholder
# replaced by `issue-<N>`, then `/plan.md`. plan mode writes it; build mode
# requires it to be committed at HEAD.
#
# THE MODEL. models.build in config.json, for both modes. config.json has no
# plan key, and plan.md is Stage 3 work (references/models.md, "3 build");
# models.intake is Stage 2 contradiction detection. `inherit` passes no flag
# and the action's default model runs. `cheap` names no model in CI and is
# refused rather than guessed at.
#
# THE AGENT'S PERMISSIONS (maintainer ruling, 2026-10-10). The agent gets the
# permission rules the repository owner committed for Claude Code -
# .claude/settings.json and .claude/settings.local.json - and the person who
# dispatches the run may only NARROW them, never widen them:
#   repo-settings  the committed rules. When they set no permissions.defaultMode,
#                  `--permission-mode acceptEdits` is added, because a headless
#                  run with no mode was measured to deny every file write, and
#                  a stage whose output is file edits would produce nothing.
#                  When they DO set a defaultMode, no mode flag is passed and
#                  the owner's choice stands - including bypassPermissions,
#                  which is warned about and never produced here.
#   edits-only     the same, plus `--disallowedTools Bash`: no shell at all.
# A third option, read-only (no edit but the plan file), was dropped: a deny
# rule beats an allow rule, so "deny Write except plan.md" cannot be written
# as a permission rule (measured, references/ci-build.md "Permissions").
# The claude-args file holds one flag per line, from a fixed set; nothing a
# dispatcher typed reaches it.
#
# Exit codes:
#   0  ok, or the dry run printed what it would have pushed and opened
#   2  usage
#   3  the repository cannot be read as needed: not a work tree, a shallow
#      clone, an unreadable config, or HEAD is not the default-branch tip
#   4  the spec is unchanged against the base; no model call should follow
#   5  build mode, and no plan is committed at the plan path
#   6  refused by stage-advance.sh, on the patch or on the commit made from
#      it; its reason is relayed verbatim
#   7  delivery failed after the decision: the body, the branch, the commit,
#      the push or gh - the step is named
# --selftest exits 0 when every case held, 1 when one did not.
set -euo pipefail
export LC_ALL=C

VERSION="build-dispatch 1.0"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HERE/$(basename -- "${BASH_SOURCE[0]}")"

SPEC_REL=".claude/productizer/spec.md"
CONST_REL=".claude/productizer/constitution.md"
CONFIG_REL=".claude/productizer/config.json"

die_usage() { printf 'build-dispatch: %s\n' "$1" >&2; exit 2; }
fail() { local code="$1"; shift; printf 'build-dispatch: %s\n' "$*" >&2; exit "$code"; }
say() { printf '%s\n' "$*"; }

usage() {
  printf 'usage: build-dispatch.sh prepare [repo-root] --mode plan|build --issue N\n'
  printf '                         --default-branch NAME --out DIR [--spec-base SHA]\n'
  printf '                         [--permissions repo-settings|edits-only]\n'
  printf '       build-dispatch.sh deliver [repo-root] --mode plan|build --issue N\n'
  printf '                         --patch FILE --run-id ID --default-branch NAME\n'
  printf '                         [--spec-base SHA] [--dry-run]\n'
  printf '       build-dispatch.sh --selftest | --version | --help\n'
  printf 'exit: 0 ok, 2 usage, 3 repository not usable or HEAD not the default-branch tip,\n'
  printf '      4 spec unchanged, 5 no committed plan, 6 refused by stage-advance.sh,\n'
  printf '      7 delivery failed (named)\n'
}

CMD=""; ROOT=""; MODE=""; ISSUE=""; SPEC_BASE=""; OUT=""; PATCH=""; RUN_ID=""
DEFAULT=""; DRY_RUN=0; SELFTEST=0; PERMS=""; PERMS_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --selftest|--self-test) SELFTEST=1; shift ;;
    --mode)    [ $# -ge 2 ] || die_usage "--mode needs plan or build"; MODE="$2"; shift 2 ;;
    --issue)   [ $# -ge 2 ] || die_usage "--issue needs a number"; ISSUE="$2"; shift 2 ;;
    --spec-base) [ $# -ge 2 ] || die_usage "--spec-base needs a commit id"; SPEC_BASE="$2"; shift 2 ;;
    --out)     [ $# -ge 2 ] || die_usage "--out needs a directory"; OUT="$2"; shift 2 ;;
    --patch)   [ $# -ge 2 ] || die_usage "--patch needs a file"; PATCH="$2"; shift 2 ;;
    --run-id)  [ $# -ge 2 ] || die_usage "--run-id needs the workflow run id"; RUN_ID="$2"; shift 2 ;;
    --default-branch) [ $# -ge 2 ] || die_usage "--default-branch needs a branch name"; DEFAULT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --permissions) [ $# -ge 2 ] || die_usage "--permissions needs repo-settings or edits-only"; PERMS="$2"; PERMS_SET=1; shift 2 ;;
    -*) die_usage "unknown option: $1. Run with --help for the contract." ;;
    *)
      if [ -z "$CMD" ]; then CMD="$1"
      elif [ -z "$ROOT" ]; then ROOT="$1"
      else die_usage "only one repo-root; got a second: $1"; fi
      shift ;;
  esac
done

# ===========================================================================
# SELF-TEST. Real repositories under mktemp -d, each cloned from a local bare
# "origin" so the default-branch tip is a real remote-tracking ref. `gh` is a
# stub placed first on PATH that records its arguments and the body file; the
# push goes to the local bare repository. Nothing touches the network. Every
# case asserts an exit code AND a sentence of output.
# ===========================================================================
selftest() {
  # Global, not local: the EXIT trap runs after this function has returned.
  ST="$(mktemp -d)" || die_usage "cannot create a temporary directory for the self-test"
  trap 'rm -rf "$ST"' EXIT HUP INT TERM
  export GIT_CEILING_DIRECTORIES="$ST"
  export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
  export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
  local CASES=0 HELD=0 CODES=""

  mkdir -p "$ST/bin"
  cat > "$ST/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh for the build-dispatch self-test: records, never networks.
printf '%s\n' "$@" > "$GH_LOG.args"
while [ $# -gt 0 ]; do
  case "$1" in --body-file) cp "$2" "$GH_LOG.body"; shift 2 ;; *) shift ;; esac
done
if [ "${STUB_GH_FAIL:-0}" = 1 ]; then echo "stub gh: failing as the case asked" >&2; exit 1; fi
echo "https://example.invalid/pull/1"
STUB
  chmod +x "$ST/bin/gh"
  export PATH="$ST/bin:$PATH"

  G() { git -C "$1" -c user.email=selftest@example.invalid -c user.name=selftest \
          -c commit.gpgsign=false "${@:2}"; }

  # newrepo <name>: seed a repository whose history is base -> spec change
  # (R2 added), push it to a bare origin, and clone that origin to <name>.
  newrepo() {
    local S="$ST/$1.seed" R="$ST/$1"
    mkdir -p "$S/.claude/productizer" "$S/src"
    G "$S" init --quiet --initial-branch=main
    cat > "$S/.claude/productizer/config.json" <<'JSON'
{ "artifacts": { "path": "docs/sdlc/<slug>" },
  "models": { "build": { "model": "inherit", "effort": "inherit" } } }
JSON
    printf '# Spec\n\n## Requirements\n\n- **R1** \342\200\224 The tool shall greet.\n' \
      > "$S/.claude/productizer/spec.md"
    printf '# Constitution\n\n1. Small steps.\n' > "$S/.claude/productizer/constitution.md"
    printf 'echo hi\n' > "$S/src/app.sh"
    G "$S" add -A; G "$S" commit --quiet -m base
    printf -- '- **R2** \342\200\224 The tool shall wave.\n' >> "$S/.claude/productizer/spec.md"
    G "$S" add -A; G "$S" commit --quiet -m "spec: R2"
    G "$ST" init --quiet --bare "$ST/$1.origin.git"
    G "$S" push --quiet "$ST/$1.origin.git" main
    G "$ST" -c init.defaultBranch=main clone --quiet "$ST/$1.origin.git" "$R"
  }
  commit_push() { G "$1" add -A; G "$1" commit --quiet -m "$2"; G "$1" push --quiet origin main; }
  # mkpatch <repo> <out> <path> <content>: a patch adding one file, made in a
  # scratch copy so the repository itself stays at the tip.
  mkpatch() {
    local R="$1" P="$2" path="$3" content="$4" W="$ST/patch-work"
    rm -rf "$W"; G "$ST" clone --quiet "$R" "$W"
    mkdir -p "$W/$(dirname "$path")"; printf '%s\n' "$content" > "$W/$path"
    G "$W" add -N .; G "$W" diff --binary > "$P"
  }

  drive() { # drive <name> <want> <text> [args...]
    local name="$1" want="$2" text="$3"; shift 3
    local got=0
    GH_LOG="$ST/$name.gh" bash "${DRIVE_SCRIPT:-$SELF}" "$@" > "$ST/$name.out" 2> "$ST/$name.err" || got=$?
    CASES=$((CASES + 1)); CODES="$CODES $got"
    if [ "$got" = "$want" ] && grep -qF -- "$text" "$ST/$name.out" "$ST/$name.err"; then
      HELD=$((HELD + 1)); printf '  ok    %-40s exit %s\n' "$name" "$got"
    else
      printf '  FAIL  %-40s exit %s (wanted %s and the text: %s)\n' "$name" "$got" "$want" "$text"
      sed 's/^/          stdout: /' "$ST/$name.out" | head -n 12
      sed 's/^/          stderr: /' "$ST/$name.err" | head -n 12
    fi
  }
  # also <name> <description> <command...>: an extra assertion on state the
  # last drive left behind. Counted as a case that reached exit 0.
  # args_are <file> <expected>: the claude-args file is exactly these lines.
  # shellcheck disable=SC2329  # invoked through also's "$@"
  args_are() { printf '%s\n' "$2" | cmp -s - "$1"; }
  # shellcheck disable=SC2329  # invoked through also's "$@"
  is_empty_file() { [ -f "$1" ] && [ ! -s "$1" ]; }
  also() {
    local name="$1" what="$2"; shift 2
    CASES=$((CASES + 1)); CODES="$CODES 0"
    if "$@"; then HELD=$((HELD + 1)); printf '  ok    %-40s %s\n' "$name" "$what"
    else printf '  FAIL  %-40s %s\n' "$name" "$what"; fi
  }

  printf 'build-dispatch self-test\n\n'
  local R P

  # --- prepare ---------------------------------------------------------------
  newrepo prep; R="$ST/prep"
  drive prepare-plan 0 "prepared plan for issue #7" \
    prepare "$R" --mode plan --issue 7 --default-branch main --out "$ST/out-plan"
  also plan-data-has-fenced-diff "spec-diff.md carries the fenced diff" \
    grep -q 'PRODUCTIZER-SPEC-DIFF-' "$ST/out-plan/spec-diff.md"
  also repo-settings-no-mode-adds-accept-edits "no committed defaultMode: exactly acceptEdits" \
    args_are "$ST/out-plan/claude-args" '--permission-mode acceptEdits'
  drive prepare-edits-only 0 "permissions edits-only" \
    prepare "$R" --mode plan --issue 7 --default-branch main --out "$ST/out-edits" --permissions edits-only
  also edits-only-denies-bash "edits-only adds --disallowedTools Bash and nothing else" \
    args_are "$ST/out-edits/claude-args" $'--permission-mode acceptEdits\n--disallowedTools Bash'
  drive prepare-unknown-permissions 2 "--permissions must be repo-settings or edits-only; got: bypass" \
    prepare "$R" --mode plan --issue 7 --default-branch main --out "$ST/out-x" --permissions bypass
  drive deliver-refuses-permissions 2 "--permissions belongs to prepare" \
    deliver "$R" --mode plan --issue 7 --patch "$ST/out-plan/mode" --run-id 1 \
    --default-branch main --permissions edits-only
  also plan-base-is-parent-of-spec-change "the derived base is the parent of the spec commit" \
    test "$(cat "$ST/out-plan/spec-base")" = "$(G "$R" rev-parse HEAD^1)"

  drive prepare-unchanged 4 "the spec is unchanged against" \
    prepare "$R" --mode plan --issue 7 --default-branch main --out "$ST/out-x" \
    --spec-base "$(G "$R" rev-parse HEAD)"
  drive prepare-bad-base 2 "--spec-base must be a full 40-character commit id" \
    prepare "$R" --mode plan --issue 7 --default-branch main --out "$ST/out-x" --spec-base main
  drive prepare-build-no-plan 5 "no plan is committed at docs/sdlc/issue-7/plan.md" \
    prepare "$R" --mode build --issue 7 --default-branch main --out "$ST/out-x"

  newrepo built; R="$ST/built"
  mkdir -p "$R/docs/sdlc/issue-7"; printf '# Plan\n' > "$R/docs/sdlc/issue-7/plan.md"
  cat > "$R/.claude/productizer/config.json" <<'JSON'
{ "artifacts": { "path": "docs/sdlc/<slug>" },
  "models": { "build": { "model": "claude-x-1", "effort": "high" } } }
JSON
  commit_push "$R" "plan for #7"
  drive prepare-build 0 "prepared build for issue #7" \
    prepare "$R" --mode build --issue 7 --default-branch main --out "$ST/out-build"
  also build-args-from-config "model and effort come from models.build; build mode adds no mode of its own" \
    args_are "$ST/out-build/claude-args" $'--model claude-x-1\n--effort high\n--permission-mode acceptEdits'

  # The owner's committed defaultMode stands: no mode flag at all.
  newrepo owner-mode; R="$ST/owner-mode"
  printf '{ "permissions": { "defaultMode": "acceptEdits", "deny": ["Bash(curl:*)"] } }\n' > "$R/.claude/settings.json"
  commit_push "$R" "owner settings"
  drive prepare-owner-default-mode 0 "the committed settings set defaultMode acceptEdits; no mode flag is passed" \
    prepare "$R" --mode plan --issue 7 --default-branch main --out "$ST/out-owner" \
    --spec-base "$(G "$R" rev-parse HEAD~2)"
  also owner-mode-passes-no-flag "repo-settings with a committed defaultMode: an empty args file" \
    is_empty_file "$ST/out-owner/claude-args"
  drive prepare-owner-edits-only 0 "permissions edits-only" \
    prepare "$R" --mode plan --issue 7 --default-branch main --out "$ST/out-owner-e" \
    --spec-base "$(G "$R" rev-parse HEAD~2)" --permissions edits-only
  also owner-mode-edits-only-narrows "edits-only over a committed defaultMode: only the Bash deny" \
    args_are "$ST/out-owner-e/claude-args" '--disallowedTools Bash'

  newrepo owner-bypass; R="$ST/owner-bypass"
  printf '{ "permissions": { "defaultMode": "bypassPermissions" } }\n' > "$R/.claude/settings.local.json"
  # -f: a global excludes file commonly ignores settings.local.json.
  G "$R" add -f .claude/settings.local.json
  commit_push "$R" "owner bypass"
  drive prepare-owner-bypass-warned 0 "WARNING the committed Claude Code settings set defaultMode bypassPermissions" \
    prepare "$R" --mode plan --issue 7 --default-branch main --out "$ST/out-bypass" \
    --spec-base "$(G "$R" rev-parse HEAD~2)"
  also owner-bypass-not-produced "the owner's bypass is not written into the args" \
    is_empty_file "$ST/out-bypass/claude-args"

  newrepo bad-settings; R="$ST/bad-settings"
  printf '{ "permissions": \n' > "$R/.claude/settings.json"
  commit_push "$R" "broken settings"
  drive prepare-bad-settings 3 "cannot read the repository's committed Claude Code settings" \
    prepare "$R" --mode plan --issue 7 --default-branch main --out "$ST/out-x" \
    --spec-base "$(G "$R" rev-parse HEAD~2)"

  # spec-diff.sh's exit 5 is passed through, not refused. A base WITHOUT the
  # spec needs an orphan commit.
  newrepo nobase; R="$ST/nobase"
  G "$R" switch --quiet --orphan empty
  G "$R" commit --quiet --allow-empty -m empty
  local EMPTY; EMPTY="$(G "$R" rev-parse HEAD)"
  G "$R" switch --quiet main
  drive prepare-new-spec-passes-through 0 "new, no baseline" \
    prepare "$R" --mode plan --issue 7 --default-branch main --out "$ST/out-new" --spec-base "$EMPTY"
  also new-spec-line-reaches-the-agent "the no-baseline line is in the data file" \
    grep -q 'new, no baseline' "$ST/out-new/spec-diff.md"

  newrepo cheap; R="$ST/cheap"
  printf '{ "models": { "build": { "model": "cheap" } } }\n' > "$R/.claude/productizer/config.json"
  commit_push "$R" "cheap model"
  drive prepare-cheap-refused 3 "names no model in CI" \
    prepare "$R" --mode plan --issue 7 --default-branch main --out "$ST/out-x" \
    --spec-base "$(G "$R" rev-parse HEAD~2)"

  newrepo ahead; R="$ST/ahead"
  printf 'x\n' > "$R/local.txt"; G "$R" add -A; G "$R" commit --quiet -m local
  drive prepare-not-tip 3 "HEAD is not the tip of the default branch" \
    prepare "$R" --mode plan --issue 7 --default-branch main --out "$ST/out-x"

  mkdir -p "$ST/plain"
  drive prepare-not-a-work-tree 3 "not a git work tree" \
    prepare "$ST/plain" --mode plan --issue 7 --default-branch main --out "$ST/out-x"

  # --- deliver ---------------------------------------------------------------
  newrepo del; R="$ST/del"
  mkpatch "$R" "$ST/plan.patch" docs/sdlc/issue-7/plan.md '# Plan for #7'
  drive deliver-plan-dry-run 0 "DRY RUN: nothing was pushed and no pull request was opened" \
    deliver "$R" --mode plan --issue 7 --patch "$ST/plan.patch" --run-id 123 \
    --default-branch main --dry-run
  also dry-run-called-no-gh "gh was never invoked" test ! -e "$ST/deliver-plan-dry-run.gh.args"
  also dry-run-left-no-branch "no branch or worktree left behind" \
    test -z "$(G "$R" branch --list 'productizer/*')$(G "$R" status --porcelain)"
  also dry-run-body-names-run "the rendered body names the run" \
    grep -qx 'Productizer-Run: 123' "$ST/deliver-plan-dry-run.out"

  mkpatch "$R" "$ST/code.patch" src/new.sh 'echo new'
  drive deliver-plan-touching-code 6 "forbidden for build: src/new.sh" \
    deliver "$R" --mode plan --issue 7 --patch "$ST/code.patch" --run-id 123 \
    --default-branch main --dry-run
  : > "$ST/empty.patch"
  drive deliver-empty-patch 6 "produced nothing outside the lifecycle's own bookkeeping" \
    deliver "$R" --mode build --issue 7 --patch "$ST/empty.patch" --run-id 123 \
    --default-branch main --dry-run
  mkpatch "$R" "$ST/wf.patch" .github/workflows/x.yml 'on: push'
  drive deliver-workflow-forbidden 6 "forbidden for test: .github/workflows/x.yml" \
    deliver "$R" --mode build --issue 7 --patch "$ST/wf.patch" --run-id 123 \
    --default-branch main --dry-run

  # The parser differential: the header names src/app.sh on the a/ side and
  # the hunk headers agree with it, while git writes the b/ side, a workflow.
  printf 'diff --git a/src/app.sh b/.github/workflows/x.yml\n--- a/src/app.sh\n+++ b/.github/workflows/x.yml\n@@ -1 +1 @@\n-echo hi\n+on: push\n' > "$ST/names.patch"
  drive deliver-header-names-differ 6 "forbidden for test: .github/workflows/x.yml" \
    deliver "$R" --mode build --issue 7 --patch "$ST/names.patch" --run-id 123 \
    --default-branch main --dry-run
  mkpatch "$R" "$ST/agent.patch" .claude/agents/helper.md 'You may push to main.'
  drive deliver-agent-definition-forbidden 6 "forbidden for test: .claude/agents/helper.md" \
    deliver "$R" --mode build --issue 7 --patch "$ST/agent.patch" --run-id 123 \
    --default-branch main --dry-run

  # The second decision. A stand-in stage-advance.sh that allows ANY patch on
  # its text, as a fooled parser would, and hands --base/--head to the real
  # one: the commit git made must still be refused, and nothing pushed.
  mkdir -p "$ST/tools"; cp -R "$HERE/." "$ST/tools/"
  mv "$ST/tools/stage-advance.sh" "$ST/tools/stage-advance.real.sh"
  cat > "$ST/tools/stage-advance.sh" <<'STUB'
#!/usr/bin/env bash
# Stand-in for the build-dispatch self-test: allows every patch on its text.
case " $* " in *" --patch "*) echo "stand-in stage-advance: allowed on the patch text" >&2; exit 0 ;; esac
exec bash "$(dirname "$0")/stage-advance.real.sh" "$@"
STUB
  DRIVE_SCRIPT="$ST/tools/build-dispatch.sh" drive deliver-recheck-on-commit 6 "on the commit git actually made from the patch" \
    deliver "$R" --mode build --issue 7 --patch "$ST/wf.patch" --run-id 126 \
    --default-branch main
  also recheck-names-the-path "the second refusal names the workflow" \
    grep -qF "forbidden for test: .github/workflows/x.yml" "$ST/deliver-recheck-on-commit.err"
  also recheck-pushed-nothing "origin has no productizer/build-7-126" \
    test -z "$(G "$ST/del.origin.git" branch --list 'productizer/build-7-126')"
  also recheck-deleted-the-branch "no productizer branch or worktree is left locally" \
    test -z "$(G "$R" branch --list 'productizer/*')$(G "$R" worktree list --porcelain | grep -c '^worktree' | grep -vx 1)"
  also recheck-called-no-gh "gh was never invoked" test ! -e "$ST/deliver-recheck-on-commit.gh.args"

  drive deliver-build 0 "opened draft pull request https://example.invalid/pull/1" \
    deliver "$R" --mode build --issue 7 --patch "$ST/code.patch" --run-id 123 \
    --default-branch main
  # shellcheck disable=SC2016  # $1 is expanded by the inner sh, on purpose
  also pushed-the-run-branch "origin has productizer/build-7-123" \
    sh -c 'git -C "$1" rev-parse --verify --quiet refs/heads/productizer/build-7-123 > /dev/null' _ "$ST/del.origin.git"
  also default-branch-untouched "origin's main did not move" \
    test "$(G "$ST/del.origin.git" rev-parse main)" = "$(G "$R" rev-parse HEAD)"
  # shellcheck disable=SC2016  # $1 is expanded by the inner sh, on purpose
  also commit-carries-req-trailer "the commit says Productizer-Req: R2" \
    sh -c 'git -C "$1" log -1 --format=%B productizer/build-7-123 | grep -qx "Productizer-Req: R2"' _ "$ST/del.origin.git"
  # shellcheck disable=SC2016  # $1 is expanded by the inner sh, on purpose
  also commit-carries-assisted-by "the commit says Assisted-by: LLM" \
    sh -c 'git -C "$1" log -1 --format=%B productizer/build-7-123 | grep -qx "Assisted-by: LLM"' _ "$ST/del.origin.git"
  also gh-asked-for-a-draft "gh pr create was given --draft" \
    grep -qx -- '--draft' "$ST/deliver-build.gh.args"
  also body-names-the-run "the body says Productizer-Run: 123" \
    grep -qx 'Productizer-Run: 123' "$ST/deliver-build.gh.body"

  STUB_GH_FAIL=1 drive deliver-gh-fails 7 "gh pr create failed" \
    deliver "$R" --mode build --issue 7 --patch "$ST/code.patch" --run-id 124 \
    --default-branch main
  rm -rf "$ST/del.origin.git"
  drive deliver-push-fails 7 "the push of productizer/build-7-125 failed" \
    deliver "$R" --mode build --issue 7 --patch "$ST/code.patch" --run-id 125 \
    --default-branch main

  drive deliver-bad-run-id 2 "--run-id must be digits" \
    deliver "$R" --mode build --issue 7 --patch "$ST/code.patch" --run-id 'x;y' \
    --default-branch main --dry-run
  drive no-subcommand 2 "give a subcommand: prepare or deliver" --mode plan
  drive version 0 "build-dispatch 1." --version

  # shellcheck disable=SC2016  # $1 is expanded by the inner sh, on purpose
  also no-args-file-ever-says-bypass "no claude-args file this self-test produced names bypassPermissions" \
    sh -c '! cat "$1"/out-*/claude-args | grep -q bypassPermissions' _ "$ST"

  printf '\n%s of %s cases held\n' "$HELD" "$CASES"
  local reached documented
  reached="$(printf '%s' "$CODES" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  documented="$(awk '/^# Exit codes:/{f=1;next} f&&/^#   [0-9] /{printf "%s ", $2; next} f&&/^#      /{next} f{exit}' "$SELF" | sed 's/  *$//')"
  printf '    exit codes reached: %s   documented: %s\n' "$reached" "$documented"
  printf '    NOT ASSERTED: a shallow clone (exit 3, its own check); an unreadable config.json; a patch git cannot apply to HEAD (stage-advance.sh refuses it, exit 4, in its own self-test); a requirement superseded or withdrawn as the trailer source; a spec change with no requirement id (no Productizer-Req trailer); the real gh and a real GitHub; that the workflow template calls this script the way these cases do.\n'
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
# ARGUMENTS
# ===========================================================================
case "$CMD" in
  prepare|deliver) ;;
  "") die_usage "give a subcommand: prepare or deliver. Run with --help for the contract." ;;
  *)  die_usage "unknown subcommand: $CMD (prepare or deliver)" ;;
esac
case "$MODE" in plan|build) ;; *) die_usage "--mode must be plan or build; got: ${MODE:-nothing}" ;; esac
[[ "$ISSUE" =~ ^[1-9][0-9]{0,9}$ ]] || die_usage "--issue must be a positive whole number; got: ${ISSUE:-nothing}"
[ -n "$DEFAULT" ] || die_usage "--default-branch is required: HEAD is checked against its tip"
git check-ref-format --branch "$DEFAULT" > /dev/null || die_usage "--default-branch is not a valid branch name: $DEFAULT"
if [ -n "$SPEC_BASE" ] && ! [[ "$SPEC_BASE" =~ ^[0-9a-f]{40}$ ]]; then
  die_usage "--spec-base must be a full 40-character commit id in lower-case hex; got: $SPEC_BASE"
fi
if [ "$CMD" = prepare ]; then
  [ -n "$OUT" ] || die_usage "prepare needs --out DIR"
  [ -z "$PATCH$RUN_ID" ] && [ "$DRY_RUN" = 0 ] || die_usage "--patch, --run-id and --dry-run belong to deliver"
  [ "$PERMS_SET" = 1 ] || PERMS="repo-settings"
  case "$PERMS" in
    repo-settings|edits-only) ;;
    *) die_usage "--permissions must be repo-settings or edits-only; got: ${PERMS:-nothing}. Each option only narrows the repository's committed settings, and there is no other." ;;
  esac
else
  [ "$PERMS_SET" = 0 ] || die_usage "--permissions belongs to prepare"
  [ -n "$PATCH" ] || die_usage "deliver needs --patch FILE"
  [ -f "$PATCH" ] && [ -r "$PATCH" ] || die_usage "cannot read the patch: $PATCH"
  [[ "$RUN_ID" =~ ^[0-9]{1,20}$ ]] || die_usage "--run-id must be digits, the workflow run id; got: ${RUN_ID:-nothing}"
  [ -z "$OUT" ] || die_usage "--out belongs to prepare"
  PATCH="$(cd "$(dirname "$PATCH")" && pwd)/$(basename "$PATCH")"
fi

# ===========================================================================
# THE REPOSITORY
# ===========================================================================
[ -n "$ROOT" ] || ROOT="."
[ -d "$ROOT" ] || fail 3 "no such directory: $ROOT"
git -C "$ROOT" rev-parse --is-inside-work-tree > /dev/null || fail 3 "not a git work tree: $ROOT"
ROOT="$(git -C "$ROOT" rev-parse --show-toplevel)"
cd "$ROOT"
[ "$(git rev-parse --is-shallow-repository)" = false ] \
  || fail 3 "this is a shallow clone, so the spec's history cannot be read. Check out with fetch-depth: 0."
HEAD_SHA="$(git rev-parse --verify 'HEAD^{commit}')" || fail 3 "HEAD does not resolve: this repository has no commits"

TIP=""; TIP_REF=""
for ref in "refs/remotes/origin/$DEFAULT" "refs/heads/$DEFAULT"; do
  if TIP="$(git rev-parse --verify --quiet "$ref^{commit}")"; then TIP_REF="$ref"; break; fi
done
[ -n "$TIP_REF" ] || fail 3 "the default branch $DEFAULT resolves neither as origin/$DEFAULT nor as a local branch"
[ "$HEAD_SHA" = "$TIP" ] \
  || fail 3 "HEAD is not the tip of the default branch: HEAD is ${HEAD_SHA:0:12}, $TIP_REF is ${TIP:0:12}. A run dispatched on one commit is not delivered onto another."

# --- config ------------------------------------------------------------------
CONF="$(python3 -I - "$CONFIG_REL" <<'PY'
import json, os, sys
path = sys.argv[1]
art, model, effort = "docs/sdlc/<slug>", "inherit", "inherit"
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        print("cannot read %s: %s" % (path, e), file=sys.stderr)
        sys.exit(3)
    if isinstance(cfg, dict):
        a = cfg.get("artifacts")
        if isinstance(a, dict) and isinstance(a.get("path"), str) and a["path"].strip():
            art = a["path"].strip()
        m = cfg.get("models")
        b = m.get("build") if isinstance(m, dict) else None
        if isinstance(b, dict):
            model = str(b.get("model", "inherit"))
            effort = str(b.get("effort", "inherit"))
print("ART\t" + art.rstrip("/"))
print("MODEL\t" + model)
print("EFFORT\t" + effort)
PY
)" || fail 3 "cannot read $CONFIG_REL; the reason is above"
ART="$(printf '%s\n' "$CONF" | awk -F'\t' '$1=="ART"{print $2}')"
MODEL="$(printf '%s\n' "$CONF" | awk -F'\t' '$1=="MODEL"{print $2}')"
EFFORT="$(printf '%s\n' "$CONF" | awk -F'\t' '$1=="EFFORT"{print $2}')"
PLAN_PATH="$(printf '%s' "$ART" | sed "s/<[^>]*>/issue-$ISSUE/g")/plan.md"

# --- the base ----------------------------------------------------------------
BASE_SHA=""; BASE_HOW=""
if [ -n "$SPEC_BASE" ]; then
  git rev-parse --verify --quiet "$SPEC_BASE^{commit}" > /dev/null \
    || die_usage "--spec-base $SPEC_BASE is not a commit this clone carries"
  BASE_SHA="$SPEC_BASE"; BASE_HOW="--spec-base"
else
  LAST="$(git log -1 --first-parent --format=%H HEAD -- "$SPEC_REL" "$CONST_REL")"
  [ -n "$LAST" ] \
    || fail 4 "the spec is unchanged against every base: no commit in HEAD's first-parent history touches $SPEC_REL or $CONST_REL. There is no spec change to build from, so no model should be called."
  if BASE_SHA="$(git rev-parse --verify --quiet "$LAST^1")"; then
    BASE_HOW="the parent of ${LAST:0:12}, the newest commit that changed the spec"
  else
    BASE_SHA=""; BASE_HOW="none: the spec was created in the root commit ${LAST:0:12}"
  fi
fi

# ===========================================================================
# PREPARE
# ===========================================================================
if [ "$CMD" = prepare ]; then
  ARGS_LINES=()
  case "$MODEL" in
    inherit|"") ;;
    cheap) fail 3 "models.build.model is 'cheap', which names no model in CI. Set a model id, or inherit for the action's default." ;;
    *)
      [[ "$MODEL" =~ ^[A-Za-z0-9][A-Za-z0-9._:@-]*$ ]] \
        || fail 3 "models.build.model is not a model id this script will pass on: $MODEL"
      ARGS_LINES+=("--model $MODEL") ;;
  esac
  case "$EFFORT" in
    inherit|none|"") ;;
    low|medium|high|xhigh|max) ARGS_LINES+=("--effort $EFFORT") ;;
    *) fail 3 "models.build.effort is not one of low, medium, high, xhigh, max, inherit: $EFFORT" ;;
  esac

  # The repository's committed Claude Code settings decide the permission
  # mode. A settings.local.json that is committed is read too, and wins, as
  # it does for the CLI. Unparseable JSON is refused rather than read as none.
  REPO_MODE="$(python3 -I - .claude/settings.json .claude/settings.local.json <<'PY'
import json, os, sys
mode = ""
for path in sys.argv[1:]:
    if not os.path.exists(path):
        continue
    try:
        with open(path, encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        print("cannot read %s: %s" % (path, e), file=sys.stderr)
        sys.exit(3)
    perms = cfg.get("permissions") if isinstance(cfg, dict) else None
    if isinstance(perms, dict) and isinstance(perms.get("defaultMode"), str) and perms["defaultMode"]:
        mode = perms["defaultMode"]
print(mode)
PY
)" || fail 3 "cannot read the repository's committed Claude Code settings; the reason is above"
  if [ -z "$REPO_MODE" ]; then
    ARGS_LINES+=("--permission-mode acceptEdits")
    PERM_HOW="the committed settings set no defaultMode, so acceptEdits is added: a headless run with no mode denies every file write"
  else
    PERM_HOW="the committed settings set defaultMode $REPO_MODE; no mode flag is passed and the owner's choice stands"
    if [ "$REPO_MODE" = bypassPermissions ]; then
      printf 'build-dispatch: WARNING the committed Claude Code settings set defaultMode bypassPermissions. That is the repository owner'"'"'s choice and is passed through unchanged; this script never produces it. The agent then runs any tool the deny lists do not name, with the API key in its environment and the spec diff in its prompt.\n' >&2
    fi
  fi
  if [ "$PERMS" = edits-only ]; then
    ARGS_LINES+=("--disallowedTools Bash")
  fi

  mkdir -p "$OUT" || fail 3 "cannot create the output directory: $OUT"
  SD_RC=0
  if [ -n "$BASE_SHA" ]; then
    bash "$HERE/spec-diff.sh" . --base "$BASE_SHA" --format prompt > "$OUT/spec-diff.md" || SD_RC=$?
  else
    SD_RC=5
    say "The living spec was created in this repository's first commit, so it has no history to diff against. No diff is fenced here; this run works from the spec alone." > "$OUT/spec-diff.md"
  fi
  case "$SD_RC" in
    0) ;;
    4) fail 4 "the spec is unchanged against ${BASE_SHA:0:12} ($BASE_HOW). Nothing to reconcile, so no model should be called." ;;
    5|7) printf 'build-dispatch: spec-diff.sh exited %s; its line is passed to the agent as it stands:\n' "$SD_RC" >&2
         sed 's/^/  /' "$OUT/spec-diff.md" | grep -E 'no baseline|absent|not included' >&2 ;;
    6) die_usage "the base ${BASE_SHA:0:12} does not resolve for spec-diff.sh; its message is above" ;;
    *) fail 3 "spec-diff.sh exited $SD_RC, which this script cannot read; its message is above" ;;
  esac

  if [ "$MODE" = build ] && ! git cat-file -e "HEAD:$PLAN_PATH"; then
    fail 5 "build mode, and no plan is committed at $PLAN_PATH. Run plan mode for issue #$ISSUE and merge its pull request first."
  fi

  printf '%s\n' "$MODE" > "$OUT/mode"
  printf '%s\n' "$ISSUE" > "$OUT/issue"
  printf '%s\n' "$PLAN_PATH" > "$OUT/plan-path"
  printf '%s\n' "$BASE_SHA" > "$OUT/spec-base"
  printf '%s\n' "$PERMS" > "$OUT/permissions"
  if [ "${#ARGS_LINES[@]}" -gt 0 ]; then printf '%s\n' "${ARGS_LINES[@]}" > "$OUT/claude-args"; else : > "$OUT/claude-args"; fi
  say "build-dispatch: prepared $MODE for issue #$ISSUE at ${HEAD_SHA:0:12}, base ${BASE_SHA:0:12} ($BASE_HOW)."
  say "build-dispatch: permissions $PERMS: $PERM_HOW."
  say "build-dispatch: plan path $PLAN_PATH; claude args: ${ARGS_LINES[*]:-none}"
  say "build-dispatch: no model was called here."
  exit 0
fi

# ===========================================================================
# DELIVER
# ===========================================================================
if [ "$MODE" = plan ]; then FROM="design"; TO="build"; else FROM="build"; TO="test"; fi
BRANCH="productizer/$MODE-$ISSUE-$RUN_ID"
[ "$BRANCH" != "$DEFAULT" ] || die_usage "the run branch would be the default branch; refusing"

# 1. The decision. stage-advance.sh's reason goes to stderr as it wrote it.
SA_RC=0
bash "$HERE/stage-advance.sh" "$ROOT" --from "$FROM" --to "$TO" --patch "$PATCH" --mode "$MODE" || SA_RC=$?
[ "$SA_RC" -eq 0 ] \
  || fail 6 "refused by stage-advance.sh (exit $SA_RC) for $FROM -> $TO in $MODE mode; its reason is the line above. Nothing was committed, pushed or opened."

WORK="$(mktemp -d)" || fail 7 "cannot create a temporary directory"
WT="$WORK/wt"
REFUSED=0
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() {
  if [ -d "$WT" ]; then git -C "$ROOT" worktree remove --force "$WT" || printf 'build-dispatch: could not remove the worktree %s\n' "$WT" >&2; fi
  if { [ "$DRY_RUN" = 1 ] || [ "$REFUSED" = 1 ]; } && git -C "$ROOT" rev-parse --verify --quiet "refs/heads/$BRANCH" > /dev/null; then
    git -C "$ROOT" branch -D --quiet "$BRANCH"
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# 2. The body, rendered from HEAD BEFORE the patch is applied anywhere: the
#    renderer runs the repository's own solver probe if there is one, and code
#    the model wrote must never execute in the job that holds a write token.
BODY="$WORK/body.md"
if [ -n "$BASE_SHA" ]; then
  PSC_RC=0
  bash "$HERE/pr-spec-comment.sh" "$ROOT" --base "$BASE_SHA" > "$BODY" || PSC_RC=$?
  case "$PSC_RC" in
    0|5) ;;
    *) fail 7 "could not render the pull request body: pr-spec-comment.sh exited $PSC_RC; its message is above" ;;
  esac
else
  say "**NOT MEASURED.** The spec was created in the root commit, so there is no base to render its movement against." > "$BODY"
fi
{
  say ""
  say "This pull request is a proposal to be reviewed, not a change that was accepted. A person dispatched the run that opened it; a person decides whether it merges."
  say ""
  say "Productizer-Run: $RUN_ID"
} >> "$BODY"

# 3. Requirement ids from the spec delta, never from the model.
spec_records() { bash "$HERE/spec-requirements.sh" "$1" | cut -f1,3,4,5 | sort; }
if [ -n "$BASE_SHA" ] && git cat-file -e "$BASE_SHA:$SPEC_REL"; then
  git show "$BASE_SHA:$SPEC_REL" > "$WORK/base.md"
else
  : > "$WORK/base.md"
fi
git show "HEAD:$SPEC_REL" > "$WORK/head.md" || fail 3 "cannot read $SPEC_REL at HEAD"
spec_records "$WORK/base.md" > "$WORK/base.tsv" || fail 3 "spec-requirements.sh refused the spec at the base"
spec_records "$WORK/head.md" > "$WORK/head.tsv" || fail 3 "spec-requirements.sh refused the spec at HEAD"
IDS="$(awk -F'\t' 'NR==FNR { base[$1] = $0; next } !($1 in base) || base[$1] != $0 { print $1 }' \
  "$WORK/base.tsv" "$WORK/head.tsv" | sort -u -V | paste -sd, -)"

# 4. The branch and the commit, in a worktree so the caller's tree is untouched.
git worktree add --quiet -b "$BRANCH" "$WT" HEAD || fail 7 "could not create the branch $BRANCH"
git -C "$WT" apply --index --binary "$PATCH" || fail 7 "the patch did not apply to HEAD; nothing was committed"
MSG="$WORK/msg"
{
  say "productizer $MODE: #$ISSUE"
  say ""
  say "Produced by an unattended $MODE run for issue #$ISSUE, dispatched by a person."
  say "stage-advance.sh allowed $FROM -> $TO in $MODE mode before this commit was made."
} > "$MSG"
if [ -n "$IDS" ]; then
  bash "$HERE/req-trailer.sh" --repo "$WT" --add "$IDS" --file "$MSG" --assisted-by > /dev/null \
    || fail 7 "req-trailer.sh could not write the trailers; its message is above"
else
  printf 'build-dispatch: the spec delta names no requirement id, so the commit carries no Productizer-Req trailer\n' >&2
  git interpret-trailers --in-place --trailer "Assisted-by: LLM" "$MSG" \
    || fail 7 "could not write the Assisted-by trailer"
fi
git interpret-trailers --in-place --trailer "Productizer-Run: $RUN_ID" "$MSG" \
  || fail 7 "could not write the Productizer-Run trailer"
git -C "$WT" commit --quiet -F "$MSG" || fail 7 "the commit on $BRANCH failed"
COMMIT="$(git -C "$WT" rev-parse HEAD)"

# 4b. The decision again, on what git ACTUALLY committed, before anything
#     leaves this job. The patch text is not trusted: stage-advance.sh now
#     reads HEAD..COMMIT with git's own diff, against the config at HEAD in
#     $ROOT, not the config in the commit being judged.
SA2_RC=0
bash "$HERE/stage-advance.sh" "$ROOT" --from "$FROM" --to "$TO" --base "$HEAD_SHA" --head "$COMMIT" --mode "$MODE" >&2 || SA2_RC=$?
if [ "$SA2_RC" -ne 0 ]; then
  REFUSED=1
  fail 6 "refused by stage-advance.sh (exit $SA2_RC) for $FROM -> $TO in $MODE mode on the commit git actually made from the patch, after it had allowed the patch itself; its reason is the line above. Nothing was pushed or opened, and the branch is deleted."
fi

PR_TITLE="productizer $MODE: #$ISSUE (run $RUN_ID)"
if [ "$DRY_RUN" = 1 ]; then
  say "DRY RUN: nothing was pushed and no pull request was opened."
  say "would push:  git push origin $COMMIT:refs/heads/$BRANCH"
  say "would open:  gh pr create --draft --base $DEFAULT --head $BRANCH --title \"$PR_TITLE\" --body-file <below>"
  say "requirement ids: ${IDS:-none}"
  say "--- body ---"
  cat "$BODY"
  exit 0
fi

# 5. Push the run's branch, by explicit refspec, and nothing else.
git -C "$WT" push --quiet origin "$COMMIT:refs/heads/$BRANCH" \
  || fail 7 "the push of $BRANCH failed; no pull request was opened"

# 6. The draft pull request. The title reaches gh through the environment.
export PR_TITLE
URL="$(cd "$WT" && gh pr create --draft --base "$DEFAULT" --head "$BRANCH" --title "$PR_TITLE" --body-file "$BODY")" \
  || fail 7 "gh pr create failed after $BRANCH was pushed; the branch exists and no pull request was opened"
say "build-dispatch: opened draft pull request $URL from $BRANCH (requirement ids: ${IDS:-none})."
exit 0
