#!/usr/bin/env bash
# pre-push-checks.sh [--version] [--help] [--selftest|--self-test]
#                    [--remote NAME] [--config PATH] [--runner PATH]
#                    [--only ID] [--base REF [--head REV]]
#
# The cheap declared checks, run from a git pre-push hook over exactly what is
# being pushed. `templates/pre-push` is the hook; `install-hooks.sh` puts it in
# place. This script does the work.
#
# WHY. A full CI run here takes about nineteen minutes. The checks that catch a
# lint error, a shell warning or a leaked name take seconds. An agent that
# pushes and waits for CI to find one of those loses the nineteen minutes, and
# a sentence in a guide saying "run the checks before pushing" is skipped by
# exactly the agents it was written for. A hook cannot be skipped by
# forgetting. It CAN be skipped on purpose: `git push --no-verify` bypasses it,
# and that is stated in every refusal it prints rather than left for someone to
# discover. This is a convenience in front of CI, not a gate. CI is the gate.
#
# WHICH CHECKS. The ids listed in `pre_push.checks` in the TRUSTED commit's
# `.claude/productizer/config.json`, each of which must be an enabled check
# declared in its `checks.yaml`. Nothing else runs, whatever its trigger says.
# A missing or empty list, a list that is not a list of ids, or an id that is
# not an enabled declared check REFUSES the push (exit 2) and names what is
# wrong: a hook that silently runs nothing reads exactly like one that ran and
# found nothing.
#
# WHY A LIST IN config.json AND NOT A TAG IN checks.yaml. A `when.tags` entry
# shares the requirement-tag space, and the runner's `--tags` is an extra
# TRIGGER, not a filter - measured: with `--tags pre-push` every `always: true`
# check still runs (63 of 77 checks in this repository's own config are
# `always`), and a tagged check scoped to `src/*.sh` is handed every changed
# file instead of the one shell script, because a matched tag widens a check's
# scope to the whole change. A list of ids beside the checks changes nothing
# about how any check triggers. This script never passes `--tags`. It writes a
# DERIVED config to a temporary directory - the committed checks.yaml with
# every unlisted check removed - and runs the runner on that, with `--changed`.
# Each listed check keeps its own `when.paths` / `always` scope as declared.
#
# The derived config changes three policy keys and nothing else, and says so:
#   spec_coverage: off   a subset of the checks cannot measure the spec's
#                        coverage denominator; CI runs every check and does.
#   empty_run: pass      a pushed path no listed check scopes is CI's to
#                        examine, not a reason to stop the push. Since
#                        run-checks.sh 1.6 such a path is still NAMED, on the
#                        runner's PASS line, as examined by nothing.
#   allow_repo_local_tools: off, unless BOTH the trusted config sets it true
#                        AND this clone's .git/config sets
#                        `productizer.prePush.allowRepoLocalTools true`.
#                        The committed opt-in is the project's word that its
#                        own scripts are check tools; whether this machine
#                        runs a repository's scripts on push is the user's.
# Every other key - waivers, timeouts, exit-code maps, coverage assertions -
# is the trusted config's, untouched. This script adds nothing that would make
# a check run that the trusted config does not declare.
#
# WHOSE CONFIG (B190, security). The commit being pushed is not always your own
# work: a branch fetched from someone else and pushed on carries THEIR
# checks.yaml, and a hook that took its commands from there would let that
# commit choose what runs on your machine when you push - measured at 1.0, a
# fetched branch whose checks.yaml swapped a listed check's command for
# `touch <file>` ran it and passed. So the checks, and their commands, come
# from a TRUSTED commit, read with `git cat-file`, never from the pushed one:
#   the merge base of the pushed commit with the clone's TRUST ANCHOR - the
#   remote-tracking ref in `git config --local productizer.prePush.trustedRef`
#   (refs/remotes/<remote>/<branch>; install-hooks.sh --trusted-ref sets it),
#   else refs/remotes/origin/main, else refs/remotes/origin/master. An ancestor
#   of the anchor by definition. NOTHING ELSE. The anchor never depends on the
#   remote being pushed to, and no symbolic ref is followed or accepted.
#   With no anchor, or no history shared with it, no commit is trusted and the
#   push is refused (exit 2) unless the clone opts in, below. A first push of a
#   new repository is refused that way.
# Measured, each of these trusted a fetched branch's own config and ran its
# `touch`: the remote tip of the pushed ref (once the branch was on the
# remote); HEAD (the pushed commit whenever a fetched branch is checked out);
# the push target's `<remote>/main` (a fork's branch that is also the fork's
# main, pushed back to the fork); and `<remote>/HEAD` pointing at that branch.
# A stale anchor gives an older trusted commit, so more refusals, never a
# weaker check: fetch.
# If the pushed commit's checks.yaml differs from the trusted one by a byte,
# or its config.json `pre_push` block differs, the push is REFUSED (exit 2)
# and the files are named, because the trusted checks may not be the ones the
# commit means to be checked by, and running them silently would read as the
# commit's own verdict. The one way past it is a per-user, per-clone opt-in
# that lives outside the repository, which no commit can carry:
#     git config --local productizer.prePush.trustPushedConfig true
# Only `--local` (this clone's .git/config) is read for either opt-in - not
# the global or system config, and never a key in config.json or checks.yaml.
#
# THE CHECKER ITSELF is not chosen by the repository either: templates/pre-push
# runs the path install-hooks.sh recorded, refuses if its sha256 changed, and
# never falls back to a copy inside the repository. $PRODUCTIZER_PRE_PUSH_CHECKS
# overrides that path, and is trusted because you set it, not the repository.
#
# WHAT IS PUSHED. git writes one line per ref on stdin:
#     <local ref> <local sha> <remote ref> <remote sha>
# For each:
#   - local sha all zeros: the ref is being DELETED. Nothing to check; said so.
#   - remote sha known here: the files changed between the merge base of the
#     two and the local sha (a force push is handled by the merge base).
#   - remote sha all zeros (a new branch or tag), or a remote sha this
#     repository does not have: the base is the merge base with the remote's
#     default branch - `refs/remotes/<remote>/HEAD`, else `<remote>/main`,
#     else `<remote>/master` - and the line printed names which one it chose.
#     Only REMOTE-TRACKING refs are used: a local `main` is often the very
#     branch being pushed for the first time, and the merge base of a branch
#     with itself would make "nothing changed" out of "everything is new".
#     With no remote-tracking default branch at all (the first push to an
#     empty remote) every file in the commit is checked, and it says so.
#   - several refs at once: each distinct (base, commit) pair is checked once.
# Deleted paths are counted and left out: no check can open a file that is not
# there, and the runner rightly refuses a check whose whole scope is gone.
#
# WHICH TREE IS READ. The runner reads files from disk, not from a commit. When
# the pushed commit is HEAD and no tracked file differs from HEAD, the checks
# run in the work tree. Otherwise - pushing a branch that is not checked out,
# or with uncommitted edits - a temporary `git worktree` at the pushed commit is
# created, checked, and removed, and the line printed says which. Reading the
# work tree there would pass or fail the edits instead of what is pushed.
#
# A MANUAL RUN, AND THE RE-RUN LINE. `--base REF` skips stdin and checks HEAD
# (or `--head REV`) against its merge base with REF. Every refusal prints the
# exact `--base ... --head ... --only <check>` line that re-runs the one check
# that stopped the push over the same files.
#
# EXIT CODES ARE THE CONTRACT.
#   0  every listed check passed over the pushed files, or there was nothing to
#      check (a deletion, no changed file) - each said so.
#   1  a listed check found something. The push is stopped.
#   2  usage, the list of checks is missing, empty or names a check that is not
#      an enabled declared one, the pushed commit's checks config differs from
#      the trusted one, or the checks could not reach a verdict (a missing
#      tool, a hollow check, a repo-local tool the hook ran with the opt-in off,
#      a runner crash, an unreadable ref line).
#      The push is stopped: unverified is not a pass.
# Unmeasured beats findings beats clean, across refs.
#
# KNOWN LIMITS, written down rather than discovered later:
#   - `git push --no-verify` skips the hook. Stated on every refusal.
#   - Untracked files are not compared: an untracked file a listed check reads
#     beside the pushed ones is read from the work tree.
#   - Only the listed checks run. A push this hook passes can still fail CI.
#   - A stale remote-tracking ref gives an older merge base, so MORE files are
#     checked, never fewer.
#   - A local `checks.local.yaml` timeout override is not carried into the
#     derived config.
#   - The trusted commit is what the anchor branch accepted: a config change
#     that reached it is trusted from then on. If `origin` is a fork someone
#     else controls, origin/main is theirs: set trustedRef. With no anchor
#     nothing is trusted, and every push (a first push included) is refused
#     until the clone sets trustedRef or opts in.
#   - The new-branch diff base still comes from the push target's default
#     branch, <remote>/HEAD included: it narrows which files are checked,
#     never which commands run.
#   - With the trust opt-in on, the pushed commit's config is used whole.
set -euo pipefail

VERSION="pre-push-checks 1.1"
SELF="$0"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$SELF_DIR/run-checks.sh"
CONFIG_REL=".claude/productizer/checks.yaml"
SETTINGS_REL=".claude/productizer/config.json"
REMOTE="origin"
ONLY=""
BASE_REF=""
HEAD_REV=""
MODE="hook"

usage() {
  printf 'usage: pre-push-checks.sh [--remote NAME] [--config PATH] [--runner PATH]\n'
  printf '                          [--only ID] [--base REF [--head REV]]\n'
  printf '                          [--version] [--help] [--selftest]\n'
  printf '  reads git pre-push lines on stdin, unless --base is given.\n'
  printf '  --remote NAME  the remote being pushed to (the hook passes it). Default origin.\n'
  printf '  --config PATH  checks config, relative to the checked tree. Default %s\n' "$CONFIG_REL"
  printf '  --runner PATH  the checks runner. Default: run-checks.sh beside this script.\n'
  printf '  --only ID      run only this one of the listed checks.\n'
  printf '  the checks run are the ids in pre_push.checks in %s, read from a TRUSTED commit:\n' "$SETTINGS_REL"
  printf '  the merge base with the trust anchor - productizer.prePush.trustedRef, else\n'
  printf '  refs/remotes/origin/main, else refs/remotes/origin/master; never the push target, no symref.\n'
  printf '  With no anchor the push is refused unless trustPushedConfig is set - never the pushed config.\n'
  printf '  --base REF     manual run: check --head (default HEAD) against its merge base with REF;\n'
  printf '                 the trusted commit is still the merge base with the trust anchor.\n'
  printf '  A pushed commit whose checks config differs from the trusted one is refused (exit 2).\n'
  printf '  Per-clone opt-ins, read from .git/config only (git config --local), never from a commit:\n'
  printf '    git config --local productizer.prePush.trustPushedConfig true   use the pushed commit'"'"'s config\n'
  printf '    git config --local productizer.prePush.allowRepoLocalTools true run repo-local check tools\n'
  printf '    git config --local productizer.prePush.trustedRef refs/remotes/<remote>/<branch>  the trust anchor\n'
  printf '  A push changing a file a common tool reads as settings or plugin code (CONFIG_DENY in\n'
  printf '  this script: .shellcheckrc, pyproject.toml, eslint.config.*, package.json, Makefile, .envrc\n'
  printf '  and more, any depth, any case) is refused unless trustPushedConfig is set. The list can\n'
  printf '  never be complete: a tool loading code from a file not on it is not isolated. The hook is\n'
  printf '  for your own commits; push others'"'"' branches with git push --no-verify. CI checks everything.\n'
  printf '  PRODUCTIZER_PRE_PUSH_CHECKS, read by the hook, overrides the checker path install-hooks.sh\n'
  printf '  recorded. It is trusted because you set it in your environment; its sha256 is not compared.\n'
  printf '  git push --no-verify bypasses the hook. It is a convenience, not a gate.\n'
}

die_usage() { printf 'pre-push-checks: %s\n' "$1" >&2; exit 2; }
say() { printf 'pre-push: %s\n' "$1" >&2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --remote) [ "$#" -ge 2 ] || die_usage "--remote needs a name"; REMOTE="$2"; shift 2 ;;
    --config) [ "$#" -ge 2 ] || die_usage "--config needs a path"; CONFIG_REL="$2"; shift 2 ;;
    --runner) [ "$#" -ge 2 ] || die_usage "--runner needs a path"; RUNNER="$2"; shift 2 ;;
    --only)   [ "$#" -ge 2 ] || die_usage "--only needs a check id"; ONLY="$2"; shift 2 ;;
    --base)   [ "$#" -ge 2 ] || die_usage "--base needs a ref";    BASE_REF="$2"; shift 2 ;;
    --head)   [ "$#" -ge 2 ] || die_usage "--head needs a revision"; HEAD_REV="$2"; shift 2 ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h | --help) usage; exit 0 ;;
    --selftest | --self-test) MODE="selftest"; shift ;;
    *) usage >&2; die_usage "unknown argument: $1" ;;
  esac
done

[ -z "$HEAD_REV" ] || [ -n "$BASE_REF" ] || die_usage "--head is only meaningful with --base"

# ---------------------------------------------------------------------------
# --selftest. Every case runs in a throwaway repository with a bare remote, and
# the push cases push for real through templates/pre-push, the way a user hits
# it. Each asserts its exit code AND the sentence that says why.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SB="$(mktemp -d "${TMPDIR:-/tmp}/pre-push-checks-selftest.XXXXXX")" ||
    { printf 'pre-push-checks: could not create a sandbox, so no case was driven. Unmeasured.\n' >&2; exit 2; }
  trap 'rm -rf "$SB"' EXIT HUP INT TERM
  TEMPLATE="$SELF_DIR/../templates/pre-push"
  [ -f "$TEMPLATE" ] || { printf 'pre-push-checks: templates/pre-push is not beside this script, so the push cases cannot run. Unmeasured.\n' >&2; exit 2; }
  [ -x "$RUNNER" ] || { printf 'pre-push-checks: the runner %s is not executable here, so no case can run. Unmeasured.\n' "$RUNNER" >&2; exit 2; }
  SELF_ABS="$SELF_DIR/$(basename "$SELF")"

  export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
  export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

  # The fixture config: one LISTED check over *.txt whose tool refuses any file
  # that is not .txt (so a widened scope shows up as a refusal), and one
  # UNLISTED `always` check that fails on everything (so if it ever runs, the
  # push stops). config.json lists the first under pre_push.checks.
  write_fixture() {
    local d="$1"
    mkdir -p "$d/.claude/productizer"
    mkdir -p "$d/tools"
    cat > "$d/tools/check.sh" <<'FIXTURE_TOOL'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { echo "fixture-check 1"; exit 0; }
case "$1" in *.txt) ;; *) echo "handed a non-.txt file: $1"; exit 2 ;; esac
if grep -q FORBIDDEN "$1"; then echo "$1: FORBIDDEN found"; exit 1; fi
exit 0
FIXTURE_TOOL
    chmod +x "$d/tools/check.sh"
    cat > "$d/.claude/productizer/checks.yaml" <<'FIXTURE_CFG'
version: 1
policy:
  empty_run: refuse
  spec_coverage: require
  allow_repo_local_tools: true
defaults:
  timeout_seconds: 30
  severity: block
checks:
  - id: no-forbidden
    why: the cheap check, listed in pre_push.checks
    when:
      paths: ["**/*.txt", "*.txt"]
    requires: [./tools/check.sh]
    version_command: [./tools/check.sh, --version]
    mode: per_file
    command: [./tools/check.sh, "{file}"]
    exit_codes: {pass: [0], fail: [1], refused: [2]}
    coverage: {from: per_file_exit, examined_when_exit_in: [0, 1], must_cover: all_triggering, min_covered: 1}
  - id: untagged-trap
    why: unlisted and always failing, so it running at all stops the push
    when:
      always: true
    requires: [false]
    version_command: [git, --version]
    mode: batch
    command: [false]
    exit_codes: {pass: [0], fail: [1]}
    coverage: {from: stdout_paths, pattern: '^(\S+)$', must_cover: all_triggering, min_covered: 1}
FIXTURE_CFG
    printf '{\n  "version": 2,\n  "pre_push": {"checks": ["no-forbidden"]}\n}\n' > "$d/.claude/productizer/config.json"
  }
  # set_list REPO JSON: replace config.json's pre_push block and commit it.
  set_list() {
    printf '{\n  "version": 2%s\n}\n' "$2" > "$1/.claude/productizer/config.json"
    git -C "$1" add -A
    git -C "$1" commit -q -m "list: $2"
  }

  # The hook as a user has it: installed by install-hooks.sh beside this
  # script, which copies this checker, the runner and its helper under the
  # repository's git directory and runs only those copies.
  INSTALLER="$SELF_DIR/install-hooks.sh"
  [ -x "$INSTALLER" ] || { printf 'pre-push-checks: install-hooks.sh is not beside this script, so no push case has a hook. Unmeasured.\n' >&2; exit 2; }
  REAL_BASH="$(command -v bash)"; REAL_GREP="$(command -v grep)"; REAL_GIT="$(command -v git)"
  install_hook() { # WORK [INSTALLER]
    "${2:-$INSTALLER}" --repo "$1" > "$SB/install.out" 2>&1 ||
      { printf 'pre-push-checks: install-hooks.sh failed in %s, so the push cases have no hook. Unmeasured.\n' "$1" >&2; sed 's/^/  | /' "$SB/install.out" >&2; exit 2; }
  }

  # repo NAME: a work repo with a bare remote, main pushed, the hook in place.
  # The fixture's listed check runs ./tools/check.sh, a tool inside the repository,
  # so each repo opts in to repo-local tools the way a user would, in its own
  # .git/config; `repo-local-off` drives one without it.
  new_repo() {
    local r="$SB/$1"
    git init -q --bare "$r/remote.git"
    git init -q -b main "$r/work"
    write_fixture "$r/work"
    printf 'clean\n' > "$r/work/a.txt"
    printf 'notes\n' > "$r/work/b.md"
    git -C "$r/work" add -A
    git -C "$r/work" commit -q -m base
    git -C "$r/work" remote add origin "$r/remote.git"
    git -C "$r/work" push -q --no-verify origin main
    install_hook "$r/work"
    git -C "$r/work" config --local productizer.prePush.allowRepoLocalTools true
    printf '%s\n' "$r/work"
  }
  # fresh_repo NAME: a brand-new repository whose remote `origin` is empty,
  # so there is no refs/remotes/origin/main to anchor trust on.
  fresh_repo() {
    local r="$SB/$1"
    git init -q --bare "$r/remote.git"
    git init -q -b main "$r/work"
    write_fixture "$r/work"
    printf 'clean\n' > "$r/work/a.txt"
    git -C "$r/work" add -A
    git -C "$r/work" commit -q -m base
    git -C "$r/work" remote add origin "$r/remote.git"
    install_hook "$r/work"
    git -C "$r/work" config --local productizer.prePush.allowRepoLocalTools true
    printf '%s\n' "$r/work"
  }
  commit_file() { # repo path content message
    printf '%s\n' "$3" > "$1/$2"
    git -C "$1" add -A
    git -C "$1" commit -q -m "$4"
  }

  FAILED=0
  DRIVEN=0
  CODES=""
  record() { # name want rc marker outfile
    local name="$1" want="$2" rc="$3" marker="$4" out="$5" why=""
    DRIVEN=$((DRIVEN + 1))
    CODES="$CODES$rc
"
    [ "$rc" -eq "$want" ] || why="exit $rc, expected $want"
    if ! grep -qF -- "$marker" "$out"; then
      [ -n "$why" ] && why="$why; "
      why="${why}its output does not say what it was supposed to say"
    fi
    if [ -z "$why" ]; then
      printf '  ok   %-22s exit %d - %s\n' "$name" "$rc" "$marker"
    else
      printf '  FAIL %-22s %s - expected: %s\n' "$name" "$why" "$marker"
      sed 's/^/         | /' "$out" | tail -n 15
      FAILED=$((FAILED + 1))
    fi
  }
  # drive NAME WANT MARKER REPO [args...] < stdin
  drive() {
    local name="$1" want="$2" marker="$3" repo="$4" rc=0
    shift 4
    (cd "$repo" && "$SELF_ABS" "$@") > "$SB/$name.out" 2>&1 || rc=$?
    record "$name" "$want" "$rc" "$marker" "$SB/$name.out"
  }
  # push NAME WANT MARKER REPO [push args...]: a real git push through the hook.
  push_case() {
    local name="$1" want="$2" marker="$3" repo="$4" rc=0
    shift 4
    git -C "$repo" push "$@" > "$SB/$name.out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ] || rc=1
    record "$name" "$want" "$rc" "$marker" "$SB/$name.out"
  }
  Z=0000000000000000000000000000000000000000

  # 1. a clean change, pushed for real: the listed check runs over a.txt only,
  #    and the unlisted `always` trap does not run.
  W="$(new_repo clean)"
  commit_file "$W" a.txt "still clean" edit
  push_case clean-push 0 "1 of 2 declared checks are listed in pre_push.checks" "$W" origin main
  # 2. the same push with a finding: blocked, names the check, the re-run
  #    line and the bypass.
  W="$(new_repo finding)"
  commit_file "$W" a.txt "FORBIDDEN" bad
  push_case finding-blocks 1 "--only no-forbidden" "$W" origin main
  grep -qF -- "--no-verify" "$SB/finding-blocks.out" ||
    { printf '  FAIL finding-blocks         the refusal does not name git push --no-verify\n'; FAILED=$((FAILED + 1)); }
  [ "$(git -C "$W" rev-parse HEAD~1)" = "$(git -C "$W/../remote.git" rev-parse main)" ] ||
    { printf '  FAIL finding-blocks         the remote moved, so the push was not stopped\n'; FAILED=$((FAILED + 1)); }
  # 3. --no-verify is a real bypass: the same push goes through. The limit,
  #    shown rather than claimed.
  push_case no-verify-bypasses 0 "main -> main" "$W" --no-verify origin main
  # 4. a listed check is not widened to the whole change: a .md beside the
  #    .txt is not handed to a tool that refuses non-.txt files.
  W="$(new_repo scope)"
  printf 'more notes\n' > "$W/b.md"; commit_file "$W" a.txt "fine" both
  push_case scope-kept 0 "PASS" "$W" origin main
  # 5. a new branch: the base is the merge base with origin/main, so a
  #    FORBIDDEN file already on main is not re-examined.
  W="$(new_repo newbranch)"
  commit_file "$W" old.txt "FORBIDDEN" "on main already"
  git -C "$W" push -q --no-verify origin main
  git -C "$W" checkout -q -b feature
  commit_file "$W" c.txt "fine" feature
  push_case new-branch 0 "merge base with refs/remotes/origin/" "$W" origin feature
  # 6. the first push of a brand-new repository: no trust anchor, so nothing
  #    is trusted and the push is refused, naming both git config lines. With
  #    the opt-in, every file in the commit is checked, and it says so.
  W="$(fresh_repo firstpush)"
  commit_file "$W" old.txt "FORBIDDEN" "history"
  push_case first-push-refused 1 "no trust anchor: productizer.prePush.trustedRef is not set" "$W" origin main
  for line in "git config --local productizer.prePush.trustPushedConfig true" "git config --local productizer.prePush.trustedRef refs/remotes/<remote>/<branch>"; do
    grep -qF "$line" "$SB/first-push-refused.out" ||
      { printf '  FAIL first-push-refused     the refusal does not name: %s\n' "$line"; FAILED=$((FAILED + 1)); }
  done
  git -C "$W" config --local productizer.prePush.trustPushedConfig true
  push_case first-push-all-files 1 "checking every file in" "$W" origin main
  # 7. a deletion: nothing to check.
  W="$(new_repo deletion)"
  SHA="$(git -C "$W" rev-parse HEAD)"
  drive deletion 0 "is a deletion; nothing to check" "$W" <<<"(delete) $Z refs/heads/gone $SHA"
  # 8. a commit that only deletes a checked file: not handed to the runner.
  W="$(new_repo onlydel)"
  git -C "$W" rm -q a.txt; git -C "$W" commit -q -m rm
  push_case only-deletions 0 "only deletions" "$W" origin main
  # 9. two refs at once, one clean and one not: blocked, naming the bad ref.
  W="$(new_repo multi)"
  OLD="$(git -C "$W" rev-parse HEAD)"
  git -C "$W" checkout -q -b good; commit_file "$W" a.txt "fine" good
  GOOD="$(git -C "$W" rev-parse HEAD)"
  git -C "$W" checkout -q -b bad main; commit_file "$W" a.txt "FORBIDDEN" bad
  BAD="$(git -C "$W" rev-parse HEAD)"
  git -C "$W" checkout -q main
  drive multi-ref 1 "BLOCKED: 'no-forbidden' came back fail on refs/heads/bad." "$W" <<<"refs/heads/good $GOOD refs/heads/good $OLD
refs/heads/bad $BAD refs/heads/bad $OLD"
  # 10. pushing a branch that is not checked out: its commit is read from a
  #     temporary worktree, not from the clean work tree.
  push_case not-head 1 "is not the checked-out commit, so it is read from a temporary worktree" "$W" origin bad
  # 11. the pushed commit is HEAD, but the work tree has an uncommitted fix:
  #     the commit, not the edit, is checked.
  W="$(new_repo dirty)"
  commit_file "$W" a.txt "FORBIDDEN" bad
  printf 'fixed but not committed\n' > "$W/a.txt"
  push_case dirty-tree 1 "tracked files differ from the pushed commit" "$W" origin main
  # 12. the list is what selects, and a list that selects nothing is refused,
  #     never read as a clean push. Each change below carries a FORBIDDEN file
  #     a listed check would find, so a run that skipped every check and
  #     passed would exit 0, not 2.
  # The list changes below are the pushed commit's own, so this clone trusts
  # pushed configs; without it each would be refused as a changed config.
  W="$(new_repo lists)"
  git -C "$W" config --local productizer.prePush.trustPushedConfig true
  commit_file "$W" a.txt "FORBIDDEN" "a finding nothing must wave through"
  set_list "$W" ""
  drive list-missing 2 "has no pre_push.checks list" "$W" --base origin/main
  set_list "$W" ', "pre_push": {"checks": []}'
  drive list-empty 2 "is empty, so the hook would run nothing" "$W" --base origin/main
  set_list "$W" ', "pre_push": {"checks": ["no-forbidden", "not-declared"]}'
  drive list-undeclared 2 "names not-declared, not an enabled check declared in" "$W" --base origin/main
  awk '{ print } /^  - id: no-forbidden$/ { print "    enabled: false" }' "$W/.claude/productizer/checks.yaml" > "$SB/disabled.yaml"
  grep -qx '    enabled: false' "$SB/disabled.yaml" ||
    { printf 'pre-push-checks: the disabled-check fixture was not written, so list-disabled would not be about a disabled check. Unmeasured.\n' >&2; exit 2; }
  cp "$SB/disabled.yaml" "$W/.claude/productizer/checks.yaml"
  set_list "$W" ', "pre_push": {"checks": ["no-forbidden"]}'
  drive list-disabled 2 "names no-forbidden, not an enabled check declared in" "$W" --base origin/main
  # 13. a listed check whose tool is missing: unverified, and stopped.
  W="$(new_repo notool)"
  # Removing the tool changes it against the trusted commit, which the
  # tool-drift rule refuses; the clone's trust opt-in lets the runner reach it.
  git -C "$W" config --local productizer.prePush.trustPushedConfig true
  git -C "$W" rm -q tools/check.sh; commit_file "$W" a.txt "fine" "no tool"
  SHA="$(git -C "$W" rev-parse HEAD)"; OLD="$(git -C "$W" rev-parse HEAD~1)"
  drive missing-tool 2 "could not reach a verdict" "$W" <<<"refs/heads/main $SHA refs/heads/main $OLD"
  # 14. a malformed ref line: refused, never read as a pass.
  drive bad-stdin 2 "not a git pre-push line" "$W" <<<"refs/heads/main nothex refs/heads/main $Z"
  # 15. the manual re-run line works on its own.
  W="$(new_repo manual)"
  commit_file "$W" a.txt "FORBIDDEN" bad
  drive manual-base 1 "BLOCKED: 'no-forbidden' came back fail" "$W" --base origin/main --only no-forbidden
  # 16. --only naming a check that is not listed: usage.
  drive only-unlisted 2 "is not one of the checks listed in pre_push.checks" "$W" --base origin/main --only untagged-trap
  # 17. unknown argument.
  drive usage 2 "unknown argument" "$W" --frobnicate

  # 18-24. WHOSE CONFIG (B190 security). A branch fetched from someone else
  # whose checks.yaml swaps the listed check's command for one that writes a
  # marker outside the repository. The commands come from the trusted commit,
  # so the marker must never appear unless this clone opts in.
  PWN="$SB/pwned"
  foreign_branch() { # repo: check out `theirs` holding the swapped command
    git -C "$1" checkout -q -b theirs
    python3 -I - "$1/.claude/productizer/checks.yaml" "$PWN" <<'SWAP'
import sys
p, marker = sys.argv[1:3]
s = open(p).read()
old = '    command: [./tools/check.sh, "{file}"]'
assert old in s
s = s.replace(old, '    command: [touch, "%s"]' % marker)
s = s.replace('    mode: per_file\n    command: [touch', '    mode: batch\n    command: [touch')
s = s.replace("coverage: {from: per_file_exit, examined_when_exit_in: [0, 1], must_cover: all_triggering, min_covered: 1}",
              "coverage: {from: stdout_count, pattern: '(x)', min_covered: 0}", 1)
open(p, "w").write(s)
SWAP
    commit_file "$1" a.txt "FORBIDDEN" "their change"
  }
  # 18. a real push of the fetched branch: stopped, the files named, the
  #     marker absent and the remote not moved.
  W="$(new_repo foreign)"
  foreign_branch "$W"
  rm -f "$PWN"
  push_case foreign-config-push 1 "changes .claude/productizer/checks.yaml against the trusted commit" "$W" origin theirs
  [ ! -e "$PWN" ] || { printf '  FAIL foreign-config-push    the pushed commit'"'"'s command ran: %s exists\n' "$PWN"; FAILED=$((FAILED + 1)); }
  git -C "$W/../remote.git" rev-parse -q --verify refs/heads/theirs >/dev/null &&
    { printf '  FAIL foreign-config-push    the remote has refs/heads/theirs, so the push was not stopped\n'; FAILED=$((FAILED + 1)); }
  grep -qF "git config --local productizer.prePush.trustPushedConfig true" "$SB/foreign-config-push.out" ||
    { printf '  FAIL foreign-config-push    the refusal does not name the git config line that trusts it\n'; FAILED=$((FAILED + 1)); }
  # 19. the same refusal is exit 2, not a finding, and the trusted commit is
  #     the merge base with the remote's default branch.
  SHA="$(git -C "$W" rev-parse HEAD)"; OLD="$(git -C "$W" rev-parse main)"
  drive foreign-config-exit 2 "against the trusted commit, the merge base ${OLD:0:12} with the trust anchor refs/remotes/origin/main" "$W" <<<"refs/heads/theirs $SHA refs/heads/main $OLD"
  [ ! -e "$PWN" ] || { printf '  FAIL foreign-config-exit    the pushed commit'"'"'s command ran\n'; FAILED=$((FAILED + 1)); }
  # 19b. the fetched branch is ALREADY on the remote, as a branch fetched from
  #      someone else is: its remote tip carries its config, so trusting the
  #      remote tip would run its command. A commit on top, pushed for real.
  git -C "$W" push -q --no-verify origin theirs
  commit_file "$W" b.md "my commit on their branch" mine
  push_case foreign-on-remote 1 "with the trust anchor refs/remotes/origin/main" "$W" origin theirs
  [ ! -e "$PWN" ] || { printf '  FAIL foreign-on-remote      the remote branch tip'"'"'s command ran\n'; FAILED=$((FAILED + 1)); }
  SHA="$(git -C "$W" rev-parse HEAD)"
  # 20. a global setting does not trust it: only this clone's .git/config is read.
  printf '[productizer "prePush"]\n\ttrustPushedConfig = true\n' > "$SB/global.gitconfig"
  rc=0
  (cd "$W" && GIT_CONFIG_GLOBAL="$SB/global.gitconfig" "$SELF_ABS" <<<"refs/heads/theirs $SHA refs/heads/theirs $Z") > "$SB/global-optin-ignored.out" 2>&1 || rc=$?
  record global-optin-ignored 2 "$rc" "trust the pushed config for this clone" "$SB/global-optin-ignored.out"
  [ ! -e "$PWN" ] || { printf '  FAIL global-optin-ignored   the pushed commit'"'"'s command ran\n'; FAILED=$((FAILED + 1)); }
  # 21. this clone's opt-in: the pushed config is used, and says so. The marker
  #     appearing is what shows the opt-in really switches whose commands run.
  git -C "$W" config --local productizer.prePush.trustPushedConfig true
  drive trust-optin 0 "its own config is used because productizer.prePush.trustPushedConfig is true" "$W" <<<"refs/heads/theirs $SHA refs/heads/theirs $Z"
  [ -e "$PWN" ] || { printf '  FAIL trust-optin            the opt-in was on and the pushed config did not run\n'; FAILED=$((FAILED + 1)); }
  rm -f "$PWN"
  # 22. only the pre_push block changed: refused, naming config.json.
  W="$(new_repo foreignlist)"
  set_list "$W" ', "pre_push": {"checks": ["no-forbidden", "untagged-trap"]}'
  drive foreign-list 2 "changes the pre_push block of .claude/productizer/config.json" "$W" --base origin/main
  # 23. repo-local tools with the clone's opt-in off: the committed
  #     allow_repo_local_tools: true is not taken, ./check.sh is refused, and
  #     the line that enables it is printed.
  W="$(new_repo repolocal)"
  git -C "$W" config --local --unset productizer.prePush.allowRepoLocalTools
  commit_file "$W" a.txt "fine" edit
  drive repo-local-off 2 "allow it for this clone - a setting in .git/config, which no commit can carry: git config --local productizer.prePush.allowRepoLocalTools true" "$W" --base origin/main
  # 24. a pre_push block carrying an opt-in of its own, committed on the remote
  #     and so trusted, grants nothing: still refused.
  set_list "$W" ', "pre_push": {"checks": ["no-forbidden"], "allowRepoLocalTools": true, "allow_repo_local_tools": true, "trustPushedConfig": true}'
  git -C "$W" push -q --no-verify origin main
  commit_file "$W" a.txt "fine again" edit2
  drive committed-optin 2 "git config --local productizer.prePush.allowRepoLocalTools true" "$W" --base origin/main
  # 24b. NO TRUSTED COMMIT. A brand-new repository (no anchor) with the
  #      fetched branch checked out, so HEAD is the pushed commit and carries
  #      the swapped command: HEAD must not be trusted. Exit 2, marker absent;
  #      with the clone's opt-in it runs, marker present.
  W="$(fresh_repo noanchor)"
  foreign_branch "$W"
  SHA="$(git -C "$W" rev-parse HEAD)"
  rm -f "$PWN"
  drive no-anchor-head 2 "no trust anchor" "$W" <<<"refs/heads/theirs $SHA refs/heads/theirs $Z"
  [ ! -e "$PWN" ] || { printf '  FAIL no-anchor-head         HEAD, the pushed commit, was trusted: its command ran\n'; FAILED=$((FAILED + 1)); }
  git -C "$W" config --local productizer.prePush.trustPushedConfig true
  drive no-anchor-optin 0 "no trusted commit: no trust anchor" "$W" <<<"refs/heads/theirs $SHA refs/heads/theirs $Z"
  [ -e "$PWN" ] || { printf '  FAIL no-anchor-optin        the opt-in was on and the pushed config did not run\n'; FAILED=$((FAILED + 1)); }
  rm -f "$PWN"
  # 24c. the remote tip of the pushed ref is not trusted either: the fetched
  #      branch is on the remote, its tip holds the swapped command, there is
  #      no anchor, and a commit on top is pushed with main checked out.
  W="$(fresh_repo remotetip)"
  foreign_branch "$W"
  git -C "$W" push -q --no-verify origin theirs
  commit_file "$W" c.txt "mine on theirs" mine
  SHA="$(git -C "$W" rev-parse HEAD)"; TIP="$(git -C "$W" rev-parse refs/remotes/origin/theirs)"
  git -C "$W" checkout -q main
  rm -f "$PWN"
  drive no-anchor-tip 2 "no trust anchor" "$W" <<<"refs/heads/theirs $SHA refs/heads/theirs $TIP"
  [ ! -e "$PWN" ] || { printf '  FAIL no-anchor-tip          the remote tip of the pushed ref was trusted: its command ran\n'; FAILED=$((FAILED + 1)); }
  # 24f. the anchor is the user's: productizer.prePush.trustedRef names a
  #      remote-tracking ref of a remote that is not `origin`, and the push
  #      runs; a ref this repository does not have, or a short name, refuses.
  W="$(fresh_repo trustedref)"
  git -C "$W" remote add up "$SB/trustedref/remote.git"
  git -C "$W" push -q --no-verify up main
  git -C "$W" config --local productizer.prePush.trustedRef refs/remotes/up/main
  commit_file "$W" c.txt "fine" edit
  push_case trusted-ref-valid 0 "the trust anchor refs/remotes/up/main" "$W" up main
  commit_file "$W" d.txt "fine" edit2
  SHA="$(git -C "$W" rev-parse HEAD)"; OLD="$(git -C "$W" rev-parse HEAD~1)"
  git -C "$W" config --local productizer.prePush.trustedRef refs/remotes/up/nope
  drive trusted-ref-missing 2 "productizer.prePush.trustedRef in this clone's .git/config is 'refs/remotes/up/nope', which is not a full remote-tracking ref" "$W" --remote up <<<"refs/heads/main $SHA refs/heads/main $OLD"
  git -C "$W" config --local productizer.prePush.trustedRef main
  drive trusted-ref-short 2 "is 'main', which is not a full remote-tracking ref" "$W" --remote up <<<"refs/heads/main $SHA refs/heads/main $OLD"
  # 24d. THE ANCHOR IS NOT THE PUSH TARGET. A branch fetched from `fork`
  #      carrying the swapped command, which is also fork's main: pushing it
  #      back to fork must not trust fork's own history.
  W="$(new_repo forkback)"
  git init -q --bare "$SB/forkback/fork.git"
  git -C "$W" remote add fork "$SB/forkback/fork.git"
  foreign_branch "$W"
  git -C "$W" push -q --no-verify fork theirs:main
  commit_file "$W" c.txt "mine on theirs" mine
  rm -f "$PWN"
  push_case fork-push-back 1 "against the trusted commit, the merge base" "$W" fork theirs
  [ ! -e "$PWN" ] || { printf '  FAIL fork-push-back         the push target'"'"'s main was trusted: its command ran\n'; FAILED=$((FAILED + 1)); }
  # 24e. no remote's HEAD symref is followed: fork's and origin's both point at
  #      a branch carrying the swapped command, while each main is clean.
  W="$(new_repo forksym)"
  git init -q --bare "$SB/forksym/fork.git"
  git -C "$W" remote add fork "$SB/forksym/fork.git"
  git -C "$W" push -q --no-verify fork main:main
  foreign_branch "$W"
  git -C "$W" push -q --no-verify fork theirs:evil
  git -C "$W" push -q --no-verify origin theirs:evil
  git -C "$W" symbolic-ref refs/remotes/fork/HEAD refs/remotes/fork/evil
  git -C "$W" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/evil
  commit_file "$W" c.txt "mine on theirs" mine
  rm -f "$PWN"
  push_case fork-symref 1 "against the trusted commit, the merge base" "$W" fork theirs:feature
  [ ! -e "$PWN" ] || { printf '  FAIL fork-symref            a remote'"'"'s HEAD symref was followed: its command ran\n'; FAILED=$((FAILED + 1)); }
  # 25a. WHAT RUNS IS THE INSTALLED COPY. The plugin lives in the work tree,
  #      as it does in this repository, and is installed from there; a branch
  #      whose run-checks.sh writes a marker is checked out and pushed. The
  #      copies under the git directory run, the swapped runner never.
  W="$(new_repo inplugin)"
  mkdir -p "$W/plug/scripts" "$W/plug/templates"
  cp -p "$SELF_ABS" "$SELF_DIR/run-checks.sh" "$SELF_DIR/argv-classify.py" "$INSTALLER" "$W/plug/scripts/"
  cp -p "$TEMPLATE" "$W/plug/templates/pre-push"
  git -C "$W" add -A; git -C "$W" commit -q -m "the plugin, inside the work tree"
  git -C "$W" push -q --no-verify origin main
  install_hook "$W" "$W/plug/scripts/install-hooks.sh"
  git -C "$W" checkout -q -b theirs
  { head -n 1 "$W/plug/scripts/run-checks.sh"; printf 'echo runner >> "%s"\n' "$PWN"; tail -n +2 "$W/plug/scripts/run-checks.sh"; } > "$SB/swapped"
  cat "$SB/swapped" > "$W/plug/scripts/run-checks.sh"
  commit_file "$W" a.txt "fine" "their runner"
  rm -f "$PWN"
  push_case runner-in-tree 0 "PASS: refs/heads/theirs" "$W" origin theirs
  [ ! -e "$PWN" ] || { printf '  FAIL runner-in-tree         the work tree'"'"'s run-checks.sh ran, not the installed copy\n'; FAILED=$((FAILED + 1)); }
  # 25b. the copies are all it needs: installed from a plugin copy that is
  #      then deleted, a push still runs every listed check.
  W="$(new_repo copiesonly)"
  PLC="$SB/copiesonly/plugin"; mkdir -p "$PLC/scripts" "$PLC/templates"
  cp -p "$SELF_ABS" "$SELF_DIR/run-checks.sh" "$SELF_DIR/argv-classify.py" "$INSTALLER" "$PLC/scripts/"
  cp -p "$TEMPLATE" "$PLC/templates/pre-push"
  install_hook "$W" "$PLC/scripts/install-hooks.sh"
  rm -rf "$PLC"
  commit_file "$W" a.txt "still clean" edit
  push_case copies-only 0 "PASS: refs/heads/main" "$W" origin main
  # push_path NAME WANT MARKER REPO PATH-VALUE [push args...]: push_case with
  # PATH set for the git push alone, so the harness's own grep in record()
  # never looks there (measured: it did, and wrote a marker the hook did not).
  push_path() {
    local name="$1" want="$2" marker="$3" repo="$4" pv="$5" rc=0
    shift 5
    PATH="$pv" "$REAL_GIT" -C "$repo" push "$@" > "$SB/$name.out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ] || rc=1
    record "$name" "$want" "$rc" "$marker" "$SB/$name.out"
  }
  # 25c. REPO-LOCAL TOOLS FROM THE TRUSTED COMMIT. A branch whose ./check.sh
  #      - the listed check's own tool - writes a marker: refused, the marker
  #      absent; with the clone's trust opt-in it runs, the marker present.
  W="$(new_repo tooldrift)"
  git -C "$W" checkout -q -b theirs
  { head -n 1 "$W/tools/check.sh"; printf 'echo tool >> "%s"\n' "$PWN"; tail -n +2 "$W/tools/check.sh"; } > "$SB/drifted"
  cat "$SB/drifted" > "$W/tools/check.sh"
  commit_file "$W" a.txt "fine" "their tool"
  rm -f "$PWN"
  push_case tool-drift 1 "tools/check.sh (a tool a listed check runs)" "$W" origin theirs
  [ ! -e "$PWN" ] || { printf '  FAIL tool-drift             the pushed commit'"'"'s tool ran\n'; FAILED=$((FAILED + 1)); }
  git -C "$W" config --local productizer.prePush.trustPushedConfig true
  push_case tool-drift-optin 0 "PASS: refs/heads/theirs" "$W" origin theirs
  [ -e "$PWN" ] || { printf '  FAIL tool-drift-optin       the opt-in was on and the pushed tool did not run\n'; FAILED=$((FAILED + 1)); }
  rm -f "$PWN"
  # 25c2. a TOP-LEVEL tool that sources a top-level helper: the helper,
  #       changed in the push, is drift too. The trusted commit's config runs
  #       ./roottool.sh, which sources ./helper.sh; a branch changes only the
  #       helper, to write a marker.
  W="$(new_repo roothelper)"
  printf '#!/usr/bin/env bash\n. ./helper.sh\n[ "${1:-}" = --version ] && { echo roottool 1; exit 0; }\ncase "$1" in *.txt) ;; *) exit 2 ;; esac\nexit 0\n' > "$W/roottool.sh"
  chmod +x "$W/roottool.sh"
  printf '# helper\n' > "$W/helper.sh"
  sed -e 's#\./tools/check\.sh#./roottool.sh#g' "$W/.claude/productizer/checks.yaml" > "$SB/roottool.yaml"
  cat "$SB/roottool.yaml" > "$W/.claude/productizer/checks.yaml"
  git -C "$W" add -A; git -C "$W" commit -q -m "a top-level tool and its helper"
  git -C "$W" push -q --no-verify origin main
  git -C "$W" checkout -q -b theirs
  printf 'echo helper >> "%s"\n' "$PWN" > "$W/helper.sh"
  commit_file "$W" a.txt "fine" "their helper"
  rm -f "$PWN"
  push_case root-helper 1 "helper.sh (a top-level file, which" "$W" origin theirs
  [ ! -e "$PWN" ] || { printf '  FAIL root-helper            the pushed helper the top-level tool sources ran\n'; FAILED=$((FAILED + 1)); }
  # 25c3. `python3 -m pkg.tool`: the runner reads the dotted name as the module
  #       path it resolves to (pkg/tool.py); the gate must too. The trusted
  #       config runs it; a branch changes pkg/tool.py to write a marker.
  #       And `-m` puts the top level on sys.path, so a branch that changes
  #       only a top-level module the tool imports is drift as well.
  W="$(new_repo modm)"
  mkdir -p "$W/pkg"
  : > "$W/pkg/__init__.py"
  printf 'import sys\nimport rootmod\nf = sys.argv[1]\nif f == "--version":\n    print("pkgtool 1"); sys.exit(0)\nif not f.endswith(".txt"):\n    sys.exit(2)\nsys.exit(1 if "FORBIDDEN" in open(f).read() else 0)\n' > "$W/pkg/tool.py"
  printf '# a module pkg.tool imports\n' > "$W/rootmod.py"
  sed -e 's#\[\./tools/check\.sh, --version\]#[python3, -m, pkg.tool, --version]#' -e 's#\[\./tools/check\.sh, "{file}"\]#[python3, -m, pkg.tool, "{file}"]#' -e 's#requires: \[\./tools/check\.sh\]#requires: [python3]#' "$W/.claude/productizer/checks.yaml" > "$SB/modm.yaml"
  cat "$SB/modm.yaml" > "$W/.claude/productizer/checks.yaml"
  grep -qF 'pkg.tool' "$W/.claude/productizer/checks.yaml" ||
    { printf 'pre-push-checks: the -m fixture was not written, so the -m cases would not be about -m. Unmeasured.\n' >&2; exit 2; }
  git -C "$W" add -A; git -C "$W" commit -q -m "a module tool"
  git -C "$W" push -q --no-verify origin main
  git -C "$W" checkout -q -b theirs
  printf 'open("%s", "a").write("module\\n")\n' "$PWN" > "$SB/modm-head"
  cat "$SB/modm-head" "$W/pkg/tool.py" > "$SB/modm-tool"; cat "$SB/modm-tool" > "$W/pkg/tool.py"
  commit_file "$W" a.txt "fine" "their module"
  rm -f "$PWN"
  push_case m-module 1 "pkg/tool.py" "$W" origin theirs
  [ ! -e "$PWN" ] || { printf '  FAIL m-module               the pushed module -m runs ran\n'; FAILED=$((FAILED + 1)); }
  git -C "$W" checkout -q main
  git -C "$W" checkout -q -b theirs2
  printf 'open("%s", "a").write("rootmod\\n")\n' "$PWN" > "$W/rootmod.py"
  commit_file "$W" a.txt "fine too" "their top-level module"
  rm -f "$PWN"
  push_case m-rootimport 1 "rootmod.py" "$W" origin theirs2
  [ ! -e "$PWN" ] || { printf '  FAIL m-rootimport           the pushed top-level module the tool imports ran\n'; FAILED=$((FAILED + 1)); }
  # 25c4. a repo-local form the gate cannot map to files: the trusted config
  #       names the tool by an absolute path outside the repository that a
  #       symlink points back into it. The runner counts it repo-local; the
  #       gate must refuse rather than guess, and the pushed tool, changed to
  #       write a marker, must not run.
  W="$(new_repo unmapped)"
  ln -s "$W/tools" "$SB/unmapped/linked-tools"
  sed -e "s#\./tools/check\.sh#$SB/unmapped/linked-tools/check.sh#g" "$W/.claude/productizer/checks.yaml" > "$SB/unmapped.yaml"
  cat "$SB/unmapped.yaml" > "$W/.claude/productizer/checks.yaml"
  git -C "$W" add -A; git -C "$W" commit -q -m "the tool by a linked path"
  git -C "$W" push -q --no-verify origin main
  git -C "$W" checkout -q -b theirs
  { head -n 1 "$W/tools/check.sh"; printf 'echo linked >> "%s"\n' "$PWN"; tail -n +2 "$W/tools/check.sh"; } > "$SB/unmapped-tool"
  cat "$SB/unmapped-tool" > "$W/tools/check.sh"
  commit_file "$W" a.txt "fine" "their linked tool"
  rm -f "$PWN"
  push_case unmapped-tool 1 "cannot map" "$W" origin theirs
  [ ! -e "$PWN" ] || { printf '  FAIL unmapped-tool          the tool reached through a symlink ran from the pushed tree\n'; FAILED=$((FAILED + 1)); }
  # 25c5. FOREIGN CONFIG (maintainer decision "Refuse foreign config",
  #       2026-11-01). The trusted commit's own tool, tools/check.sh, sources
  #       a top-level .envrc - a helper outside its directory, which the
  #       tool-drift gate does not compare. A branch's .envrc writes a marker.
  #       Refused, the marker absent; with the trust opt-in it runs, present.
  #       (make, the obvious carrier, is refused by run-checks.sh itself as a
  #       program that takes a command as an operand.)
  W="$(new_repo envrc)"
  { head -n 1 "$W/tools/check.sh"; printf '[ -f ./.envrc ] && . ./.envrc\n'; tail -n +2 "$W/tools/check.sh"; } > "$SB/envrc-tool"
  cat "$SB/envrc-tool" > "$W/tools/check.sh"
  printf '# settings\n' > "$W/.envrc"
  git -C "$W" add -A; git -C "$W" commit -q -m "the tool reads .envrc"
  git -C "$W" push -q --no-verify origin main
  git -C "$W" checkout -q -b theirs
  printf 'echo envrc >> "%s"\n' "$PWN" > "$W/.envrc"
  commit_file "$W" a.txt "fine" "their .envrc"
  rm -f "$PWN"
  push_case config-envrc 1 ".envrc" "$W" origin theirs
  [ ! -e "$PWN" ] || { printf '  FAIL config-envrc           the pushed .envrc the tool sources ran\n'; FAILED=$((FAILED + 1)); }
  git -C "$W" config --local productizer.prePush.trustPushedConfig true
  commit_file "$W" a.txt "fine again" "another"
  push_case config-envrc-optin 0 "PASS: refs/heads/theirs" "$W" origin theirs
  [ -e "$PWN" ] || { printf '  FAIL config-envrc-optin     the opt-in was on and the pushed .envrc did not run\n'; FAILED=$((FAILED + 1)); }
  rm -f "$PWN"
  # 25c6. names on the list are matched without case and at any depth, and
  #       the refusal names each.
  W="$(new_repo cfgnames)"
  git -C "$W" checkout -q -b theirs
  printf 'disable=SC2034\n' > "$W/.ShellCheckRC"
  mkdir -p "$W/sub/dir"; printf '[tool.x]\n' > "$W/sub/dir/pyproject.toml"
  printf 'module.exports = {}\n' > "$W/sub/eslint.config.js"
  commit_file "$W" a.txt "fine" "their configs"
  push_case config-names 1 "sub/dir/pyproject.toml" "$W" origin theirs
  for f in .ShellCheckRC sub/eslint.config.js "git push --no-verify" "git config --local productizer.prePush.trustPushedConfig true"; do
    grep -qF -- "$f" "$SB/config-names.out" ||
      { printf '  FAIL config-names           the refusal does not name: %s\n' "$f"; FAILED=$((FAILED + 1)); }
  done
  # 25d. PATH. A branch ships a top-level `bash` and `grep` that write a marker
  #      and then run the real ones; checked out and pushed with `.` and an
  #      empty entry on PATH. The listed check's `#!/usr/bin/env bash` and its
  #      grep must not find them.
  W="$(new_repo pathdot)"
  git -C "$W" checkout -q -b theirs
  printf '#!/bin/sh\necho bash >> "%s"\nexec "%s" "$@"\n' "$PWN" "$REAL_BASH" > "$W/bash"
  printf '#!/bin/sh\necho grep >> "%s"\nexec "%s" "$@"\n' "$PWN" "$REAL_GREP" > "$W/grep"
  chmod +x "$W/bash" "$W/grep"
  commit_file "$W" a.txt "fine" "their bash and grep"
  rm -f "$PWN"
  push_path path-dot 0 "PASS: refs/heads/theirs" "$W" ".:$PATH:" origin theirs
  if [ -e "$PWN" ]; then
    printf '  FAIL path-dot              a program the pushed tree ships ran through PATH: %s\n' "$(tr '\n' ' ' < "$PWN")"; FAILED=$((FAILED + 1))
  fi
  #      The same tree, the checker run by hand (no hook in front of it):
  #      its own PATH cleaning is all that stands between `.` and the ./bash
  #      and ./grep the listed check would run. Its own interpreter is found
  #      before it can clean anything - measured, `#!/usr/bin/env bash` with
  #      `.` first ran ./bash - so it is started with a fixed bash here, and
  #      that limit is stated in KNOWN_LIMITATIONS.
  commit_file "$W" c.txt "fine" "for the manual run"
  rm -f "$PWN"
  rc=0
  (cd "$W" && PATH=".:$PATH:" "$REAL_BASH" "$SELF_ABS" --base origin/main) > "$SB/path-dot-manual.out" 2>&1 || rc=$?
  record path-dot-manual 0 "$rc" "PASS: HEAD - every listed check passed" "$SB/path-dot-manual.out"
  if [ -e "$PWN" ]; then
    printf '  FAIL path-dot-manual       a program the work tree ships ran through PATH: %s\n' "$(tr '\n' ' ' < "$PWN")"; FAILED=$((FAILED + 1))
  fi
  # 25d2. PATH entries that reach the work tree other than by its spelling: a
  #       symlink to it, a `..` detour, and (where the disk folds case) a
  #       case variant. Each must be dropped like the plain entry.
  #       The branch also ships `git`: the hook's own `git rev-parse` runs
  #       before it knows the work tree from git, so its first pass must
  #       already drop entries reaching it (found with builtins).
  W="$(new_repo pathcanon)"
  git -C "$W" checkout -q -b theirs
  printf '#!/bin/sh\necho bash >> "%s"\nexec "%s" "$@"\n' "$PWN" "$REAL_BASH" > "$W/bash"
  printf '#!/bin/sh\necho grep >> "%s"\nexec "%s" "$@"\n' "$PWN" "$REAL_GREP" > "$W/grep"
  printf '#!/bin/sh\necho git >> "%s"\nexec "%s" "$@"\n' "$PWN" "$REAL_GIT" > "$W/git"
  chmod +x "$W/bash" "$W/grep" "$W/git"
  commit_file "$W" a.txt "fine" "their bash and grep"
  ln -s "$W" "$SB/pathcanon/link-to-work"
  rm -f "$PWN"
  push_path path-symlink 0 "PASS: refs/heads/theirs" "$W" "$SB/pathcanon/link-to-work:$W/tools/..:$PATH" origin theirs
  if [ -e "$PWN" ]; then
    printf '  FAIL path-symlink          a program the pushed tree ships ran through a PATH entry reaching it: %s\n' "$(tr '\n' ' ' < "$PWN")"; FAILED=$((FAILED + 1))
  fi
  WUP="$(printf '%s' "$W" | tr '[:lower:]' '[:upper:]')"
  commit_file "$W" c.txt "fine" "another"
  rm -f "$PWN"
  push_path path-case 0 "PASS: refs/heads/theirs" "$W" "$WUP:$PATH" origin theirs
  if [ -e "$PWN" ]; then
    printf '  FAIL path-case             a program the pushed tree ships ran through a case variant of the work tree on PATH: %s\n' "$(tr '\n' ' ' < "$PWN")"; FAILED=$((FAILED + 1))
  fi
  #       By hand, with a case variant of the work tree alone on PATH, under
  #       /bin/bash where it is 3.x (no ${var,,}): the checker's own folding.
  BASH_OLD="$REAL_BASH"
  if [ -x /bin/bash ]; then BASH_OLD=/bin/bash; fi
  commit_file "$W" e.txt "fine" "for the case-only manual run"
  rm -f "$PWN"
  rc=0
  (cd "$W" && PATH="$WUP:$PATH" "$BASH_OLD" "$SELF_ABS" --base origin/main) > "$SB/path-case-manual.out" 2>&1 || rc=$?
  record path-case-manual 0 "$rc" "PASS: HEAD - every listed check passed" "$SB/path-case-manual.out"
  if [ -e "$PWN" ]; then
    printf '  FAIL path-case-manual      a program the work tree ships ran through a case variant on PATH: %s\n' "$(tr '\n' ' ' < "$PWN")"; FAILED=$((FAILED + 1))
  fi
  #       By hand, with a fixed bash, the checker's own cleaning alone.
  commit_file "$W" d.txt "fine" "for the manual run"
  rm -f "$PWN"
  rc=0
  (cd "$W" && PATH="$SB/pathcanon/link-to-work:$WUP:$PATH" "$REAL_BASH" "$SELF_ABS" --base origin/main) > "$SB/path-canon-manual.out" 2>&1 || rc=$?
  record path-canon-manual 0 "$rc" "PASS: HEAD - every listed check passed" "$SB/path-canon-manual.out"
  if [ -e "$PWN" ]; then
    printf '  FAIL path-canon-manual     a program the work tree ships ran through PATH: %s\n' "$(tr '\n' ' ' < "$PWN")"; FAILED=$((FAILED + 1))
  fi
  # 25e. GIT RUNS NOTHING THE PUSHED TREE SELECTS. This clone's own config
  #      defines a filter (as an installed filter tool would) and a
  #      post-checkout hook, each writing a marker. A branch's .gitattributes
  #      selects the filter for *.txt. Pushed while not checked out, it is read
  #      from a temporary worktree: neither the filter nor the hook may run.
  W="$(new_repo gitattr)"
  git -C "$W" config filter.evil.smudge "sh -c 'echo smudge >> \"$PWN\"; cat'"
  git -C "$W" config filter.evil.clean "sh -c 'echo clean >> \"$PWN\"; cat'"
  git -C "$W" checkout -q -b theirs
  printf '*.txt filter=evil\n' > "$W/.gitattributes"
  commit_file "$W" a.txt "fine" "their attributes"
  git -C "$W" checkout -q main
  printf '#!/bin/sh\necho post-checkout >> "%s"\n' "$PWN" > "$W/.git/hooks/post-checkout"
  chmod +x "$W/.git/hooks/post-checkout"
  rm -f "$PWN"
  push_case git-runs-nothing 0 "PASS: refs/heads/theirs" "$W" origin theirs
  if [ -e "$PWN" ]; then
    printf '  FAIL git-runs-nothing      git ran: %s\n' "$(tr '\n' ' ' < "$PWN")"; FAILED=$((FAILED + 1))
  fi
  # 25f. the same branch checked out, a tracked file stat-dirty but unchanged:
  #      the dirty check must not run the clean filter the branch selects.
  rm -f "$W/.git/hooks/post-checkout"
  git -C "$W" checkout -q theirs
  commit_file "$W" b.md "more notes" "another commit to push"
  sleep 1; touch "$W/a.txt"
  rm -f "$PWN"
  push_case dirty-check-filter 0 "PASS: refs/heads/theirs" "$W" origin theirs
  if [ -e "$PWN" ]; then
    printf '  FAIL dirty-check-filter    git ran: %s\n' "$(tr '\n' ' ' < "$PWN")"; FAILED=$((FAILED + 1))
  fi
  # 25. a branch that ships a top-level json.py and yaml.py, checked out and
  #     pushed for real: git runs the hook from the top level, and a python
  #     that put its current directory on sys.path would import them. Each
  #     writes a marker and then loads the real module, so a run that imported
  #     them still passes and only the marker tells.
  W="$(new_repo pyshadow)"
  git -C "$W" checkout -q -b theirs
  for m in json yaml; do
    printf 'import sys\nopen(%s, "a").write("%s\\n")\ndel sys.modules["%s"]\nsys.path[:] = [p for p in sys.path if p not in ("", ".")]\nimport importlib\nsys.modules["%s"] = importlib.import_module("%s")\n' \
      "'$SB/py-pwned'" "$m" "$m" "$m" "$m" > "$W/$m.py"
  done
  commit_file "$W" a.txt "fine" "ships json.py and yaml.py"
  rm -f "$SB/py-pwned"
  # PYTHONPATH at the work tree too, as a user's `PYTHONPATH=.` would put it:
  # -I must ignore it here, and the runner must not be handed it.
  PYTHONPATH="$W" push_case py-shadow 0 "PASS: refs/heads/theirs" "$W" origin theirs
  if [ -e "$SB/py-pwned" ]; then
    printf '  FAIL py-shadow             a module the pushed branch ships was imported: %s\n' "$(tr '\n' ' ' < "$SB/py-pwned")"; FAILED=$((FAILED + 1))
  fi

  printf '  cases driven: %d. Assertions that did not hold: %d\n' "$DRIVEN" "$FAILED"
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    grep -qx "$want" <<<"$CODES" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  printf '  NOT ASSERTED: a tag push, a remote without a HEAD symref but with master, sha256 repositories, untracked files read by a check, an unborn HEAD with no remote history, and timing.\n'
  if [ "$FAILED" -ne 0 ]; then
    printf 'FAIL: %d selftest case(s) did not produce the exit code and the sentence they declare.\n' "$FAILED" >&2
    exit 1
  fi
  if [ -n "$MISSING" ]; then
    printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# The run.
# ---------------------------------------------------------------------------
# keep_path [TOP]: PATH with every empty or relative entry dropped, and every
# entry inside TOP when TOP is given. git runs a hook from the repository's top
# level, so an empty or relative entry - or one inside the work tree - lets the
# checked-out tree supply `bash`, `grep` or `shellcheck` to this script, to the
# runner and to every check (measured: with PATH starting `.`, a branch's own
# top-level `bash` ran as the interpreter of a listed check). templates/pre-push
# does the same before it runs anything; this repeats it for manual runs and
# the $PRODUCTIZER_PRE_PUSH_CHECKS override. BASH_ENV and ENV go too.
# Each entry is resolved to its physical directory (`cd ... && pwd -P`, judged
# by its exit status; an entry that does not resolve is dropped) and compared
# with TOP's, always without case - so a symlink, a `..` detour or a case
# variant that reaches the work tree is dropped like its plain spelling. A
# false match only drops an extra entry; a missed fold would let one in.
# Measured: each of those three kept a branch's top-level `bash` on PATH.
# tr by absolute path, never through the PATH being cleaned; the work tree's
# top found with builtins before any PATH lookup (walking up to a `.git`).
# Both work under /bin/bash 3.2, which has no ${var,,}.
TR=""
for _t in /usr/bin/tr /bin/tr; do
  if [ -x "$_t" ]; then TR="$_t"; break; fi
done
[ -n "$TR" ] || die_usage "neither /usr/bin/tr nor /bin/tr is here, so PATH cannot be compared with the work tree without case."
top_by_builtins() {
  local d
  d="$(pwd -P)"
  while :; do
    if [ -e "$d/.git" ]; then printf '%s' "$d"; return 0; fi
    [ -n "$d" ] && [ "$d" != / ] || return 1
    d="${d%/*}"
  done
}
keep_path() {
  local out="" rest="$PATH:" entry real cmp top
  while [ -n "$rest" ]; do
    entry="${rest%%:*}"; rest="${rest#*:}"
    case "$entry" in /*) ;; *) continue ;; esac
    if ! real="$(cd "$entry" 2>&1 && pwd -P)"; then
      continue
    fi
    if [ -n "${1:-}" ]; then
      cmp="$("$TR" '[:upper:]' '[:lower:]' <<<"$real")"; top="$("$TR" '[:upper:]' '[:lower:]' <<<"$1")"
      case "$cmp" in "$top" | "$top"/*) continue ;; esac
    fi
    out="${out:+$out:}$entry"
  done
  printf '%s' "$out"
}
TOP_FIRST="$(top_by_builtins)" || TOP_FIRST=""
PATH="$(keep_path "$TOP_FIRST")"; export PATH
unset BASH_ENV ENV

if ! TOP="$(git rev-parse --show-toplevel)"; then
  die_usage "not inside a git work tree."
fi
[ -x "$RUNNER" ] || die_usage "the checks runner $RUNNER is not there or not executable."
TOP_REAL="$(cd "$TOP" 2>&1 && pwd -P)" || die_usage "the work tree $TOP does not resolve to a directory: $TOP_REAL"
PATH="$(keep_path "$TOP_REAL")"; export PATH
command -v python3 >/dev/null || die_usage "python3 is not on PATH; the checks runner needs it too."
# --attr-source (git 2.40): every checkout and content comparison below reads
# .gitattributes from the trusted commit, never the pushed one. Measured: a
# `git worktree add` of the pushed commit ran the smudge filter its
# .gitattributes selected, and `git diff --quiet HEAD` the clean filter.
git -C "$TOP" --attr-source="$(git -C "$TOP" hash-object -t tree /dev/null)" rev-parse -q --git-dir >/dev/null ||
  die_usage "this git ($(git --version)) has no --attr-source; git 2.40 or later is needed, because without it a checkout of the pushed commit runs the filters its .gitattributes select."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pre-push-checks.XXXXXX")" || die_usage "cannot create a temporary directory."
WORKTREES=()
cleanup() {
  local wt
  for wt in ${WORKTREES[@]+"${WORKTREES[@]}"}; do
    git -C "$TOP" worktree remove --force "$wt" || say "could not remove the temporary worktree $wt; 'git worktree prune' will."
  done
  rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM

EMPTY_TREE="$(git -C "$TOP" hash-object -t tree /dev/null)"
UNITS="$WORK/units"
: > "$UNITS"

is_zero() { [[ "$1" =~ ^0+$ ]]; }
is_sha() { [[ "$1" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; }

# optin NAME -> "true" or "false", from this clone's .git/config ONLY. Never the
# global or system config (one setting there would trust every repository on
# the machine), and never a file a commit carries.
optin() {
  local v rc=0
  v="$(git -C "$TOP" config --local --type=bool --get "productizer.prePush.$1")" || rc=$?
  case "$rc" in
    0) printf '%s\n' "$v" ;;
    1) printf 'false\n' ;;
    *) die_usage "productizer.prePush.$1 in this clone's .git/config is not true or false (git config exit $rc). Set it with: git config --local productizer.prePush.$1 true" ;;
  esac
}
TRUST_PUSHED="$(optin trustPushedConfig)"
ALLOW_LOCAL="$(optin allowRepoLocalTools)"
TRUST_LINE="git config --local productizer.prePush.trustPushedConfig true"

# FOREIGN CONFIG (maintainer decision "Refuse foreign config", 2026-11-01).
# Tools load settings, and sometimes code, from files in the tree they check -
# an eslint config is JavaScript - and an allowed repository script can source
# a helper from anywhere. So a push that changes, against the trusted commit,
# any file with one of these names, at any depth and in any case, is refused
# unless the clone trusts pushed configs. The list is data, kept here and
# nowhere else, and it can NEVER be complete: a tool that loads code from a file
# not named here is not isolated. The hook is for your own commits; push
# someone else's branch with `git push --no-verify`, and CI still checks
# everything.
CONFIG_DENY=(
  .shellcheckrc
  pyproject.toml setup.cfg tox.ini .flake8 .pylintrc ruff.toml .ruff.toml mypy.ini
  conftest.py sitecustomize.py '*.pth'
  '.eslintrc*' 'eslint.config.*' '.prettierrc*' 'prettier.config.*' package.json .npmrc
  '.yarnrc*' 'tsconfig*.json' 'biome.json*'
  .editorconfig '.semgrep*' .gitleaks.toml .pre-commit-config.yaml Makefile .envrc
  .tool-versions .python-version .nvmrc
)
LOCAL_LINE="git config --local productizer.prePush.allowRepoLocalTools true"

# The remote's default branch, as a remote-tracking ref, or nothing.
default_branch_ref() {
  local r
  if r="$(git -C "$TOP" symbolic-ref -q "refs/remotes/$REMOTE/HEAD")"; then
    printf '%s\n' "$r"; return 0
  fi
  for r in "refs/remotes/$REMOTE/main" "refs/remotes/$REMOTE/master"; do
    if git -C "$TOP" rev-parse -q --verify "$r^{commit}" >/dev/null; then
      printf '%s\n' "$r"; return 0
    fi
  done
  return 1
}

# add_unit SHA BASE LABEL HOW TRUSTED TWHY: one (base, commit) pair to check,
# and the trusted commit its checks config is read from ("-" for none).
add_unit() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$UNITS"; }

# THE TRUST ANCHOR is chosen by the user, never by the push: the full
# remote-tracking ref in this clone's `productizer.prePush.trustedRef`, else
# refs/remotes/origin/main, else refs/remotes/origin/master. Not the push
# target's branches and not any remote's HEAD symref: measured at the first
# 1.1, a branch fetched from `fork` that was also fork's main, pushed back to
# fork, was its own trust anchor (the merge base of a commit with itself), and
# a HEAD symref pointing at that branch did the same - both ran its `touch`.
# A symbolic ref is refused as an anchor for the same reason.
TRUSTED_REF=""
TRUSTED_REF_WHY=""
anchor_ok() { # REF -> 0 when it is a remote-tracking ref this repository has, not a symref
  case "$1" in refs/remotes/?*/?*) ;; *) return 1 ;; esac
  ! git -C "$TOP" symbolic-ref -q "$1" >/dev/null && git -C "$TOP" rev-parse -q --verify "$1^{commit}" >/dev/null
}
TRUSTED_REF_SET=""
trc=0
TRUSTED_REF_SET="$(git -C "$TOP" config --local --get productizer.prePush.trustedRef)" || trc=$?
case "$trc" in
  0)
    if anchor_ok "$TRUSTED_REF_SET"; then
      TRUSTED_REF="$TRUSTED_REF_SET"
    else
      TRUSTED_REF_WHY="productizer.prePush.trustedRef in this clone's .git/config is '$TRUSTED_REF_SET', which is not a full remote-tracking ref (refs/remotes/<remote>/<branch>) this repository has - or it is a symbolic ref; fetch it, or name one that exists with: git config --local productizer.prePush.trustedRef refs/remotes/<remote>/<branch>"
    fi ;;
  1)
    for r in refs/remotes/origin/main refs/remotes/origin/master; do
      if anchor_ok "$r"; then TRUSTED_REF="$r"; break; fi
    done
    [ -n "$TRUSTED_REF" ] || TRUSTED_REF_WHY="no trust anchor: productizer.prePush.trustedRef is not set and this repository has neither refs/remotes/origin/main nor refs/remotes/origin/master; name the remote-tracking branch whose history you trust with: git config --local productizer.prePush.trustedRef refs/remotes/<remote>/<branch>" ;;
  *) die_usage "could not read productizer.prePush.trustedRef from this clone's .git/config (git config exit $trc)." ;;
esac

# trusted_for SHA -> "<sha or -><TAB><why>": the commit the checks config is
# read from - the merge base of the pushed commit with the trust anchor, an
# ancestor of the anchor by definition, so the pushed commit itself only when
# the anchor already reaches it. With no anchor, or no history shared with it,
# "-": nothing is trusted, and the push is refused unless the clone opts in.
trusted_for() {
  local mb
  if [ -z "$TRUSTED_REF" ]; then
    printf '%s\t%s\n' "-" "$TRUSTED_REF_WHY"
  elif ! mb="$(git -C "$TOP" merge-base "$1" "$TRUSTED_REF")"; then
    printf '%s\t%s\n' "-" "${1:0:12} shares no history with the trust anchor $TRUSTED_REF, so no commit it reached can be trusted"
  else
    printf '%s\t%s\n' "$mb" "the merge base ${mb:0:12} with the trust anchor $TRUSTED_REF (fetch if it is stale)"
  fi
}

base_from_default() { # sha label why
  local dref mb t tw
  IFS="$(printf '\t')" read -r t tw < <(trusted_for "$1")
  if dref="$(default_branch_ref)" && mb="$(git -C "$TOP" merge-base "$1" "$dref")"; then
    add_unit "$1" "$mb" "$2" "$3; base: merge base with $dref (${mb:0:12})" "$t" "$tw"
  else
    add_unit "$1" "$EMPTY_TREE" "$2" "$3; no remote-tracking default branch for '$REMOTE', so checking every file in ${1:0:12}" "$t" "$tw"
  fi
}

if [ -n "$BASE_REF" ]; then
  H="${HEAD_REV:-HEAD}"
  SHA="$(git -C "$TOP" rev-parse --verify "$H^{commit}")" || die_usage "--head $H is not a commit."
  if is_sha "$BASE_REF" && [ "$BASE_REF" = "$EMPTY_TREE" ]; then
    IFS="$(printf '\t')" read -r T TW < <(trusted_for "$SHA")
    add_unit "$SHA" "$EMPTY_TREE" "$H" "manual run; checking every file in ${SHA:0:12}" "$T" "$TW"
  else
    MB="$(git -C "$TOP" merge-base "$BASE_REF" "$SHA")" || die_usage "no merge base between $BASE_REF and $H."
    IFS="$(printf '\t')" read -r T TW < <(trusted_for "$SHA")
    add_unit "$SHA" "$MB" "$H" "manual run; base: merge base with $BASE_REF (${MB:0:12})" "$T" "$TW"
  fi
else
  [ ! -t 0 ] || die_usage "reads git's pre-push lines on stdin. For a manual run use --base REF."
  LINES=0
  while IFS=' ' read -r lref lsha rref rsha extra || [ -n "${lref:-}" ]; do
    [ -n "${lref:-}" ] || continue
    LINES=$((LINES + 1))
    if [ -n "${extra:-}" ] || ! is_sha "${lsha:-}" || ! is_sha "${rsha:-}" || [ -z "${rref:-}" ]; then
      die_usage "line $LINES is not a git pre-push line (<local ref> <local sha> <remote ref> <remote sha>): '$lref ${lsha:-} ${rref:-} ${rsha:-}'. Refused rather than guessed."
    fi
    if is_zero "$lsha"; then
      say "$rref is a deletion; nothing to check."
      continue
    fi
    if ! SHA="$(git -C "$TOP" rev-parse -q --verify "$lsha^{commit}")"; then
      say "$lref (${lsha:0:12}) is not a commit; nothing to check."
      continue
    fi
    if is_zero "$rsha"; then
      base_from_default "$SHA" "$rref" "$rref is new on '$REMOTE'"
    elif ! git -C "$TOP" cat-file -e "$rsha^{commit}"; then
      base_from_default "$SHA" "$rref" "the remote tip ${rsha:0:12} of $rref is not in this repository (fetch to narrow this)"
    else
      MB="$(git -C "$TOP" merge-base "$rsha" "$SHA")" ||
        { base_from_default "$SHA" "$rref" "$rref shares no history with the remote tip ${rsha:0:12}"; continue; }
      IFS="$(printf '\t')" read -r T TW < <(trusted_for "$SHA")
      add_unit "$SHA" "$MB" "$rref" "$rref: ${MB:0:12}..${SHA:0:12}" "$T" "$TW"
    fi
  done
fi

if [ ! -s "$UNITS" ]; then
  say "nothing to check."
  exit 0
fi

# py ARGS... < program: every Python this script runs. `-I` (isolated): no
# current directory or script directory on sys.path, no PYTHON* variables, no
# user site. And from the temporary directory, never the work tree: git runs
# a hook from the repository's top level, so a plain `python3 -` there imports
# a json.py or yaml.py the pushed branch ships before the real one (measured:
# a branch's json.py ran twice and the push read PASS). Under -I PyYAML is not
# found where it is a user install, as on the machine this was written on, so
# the one program that needs it adds back the user site directory, by path,
# after the standard library - the user's own install, not the repository's.
py() { (cd "$WORK" && python3 -I - "$@"); }

# config_blob COMMIT PATH DST: write PATH as COMMIT holds it to DST, read with
# git, never from a disk a pushed commit could have written. Prints the blob
# id, or "-" when COMMIT does not hold PATH (and DST is then absent).
config_blob() {
  local b
  rm -f "$3"
  if b="$(git -C "$TOP" rev-parse -q --verify "$1:$2")"; then
    git -C "$TOP" cat-file blob "$b" > "$3"
    printf '%s\n' "$b"
  else
    printf -- '-\n'
  fi
}

# pre_push_differs A B -> exit 0 when the two config.json files' pre_push
# values differ (a file absent, or not JSON, reads as differing from one that
# is), exit 1 when they are equal.
pre_push_differs() {
  py "$1" "$2" <<'PY'
import json, sys
def block(p):
    try:
        with open(p) as fh:
            d = json.load(fh)
    except FileNotFoundError:
        return ("absent",)
    except ValueError:
        return ("not json", open(p, "rb").read())
    return ("block", json.dumps(d.get("pre_push") if isinstance(d, dict) else None, sort_keys=True))
sys.exit(0 if block(sys.argv[1]) != block(sys.argv[2]) else 1)
PY
}

# derive_config CHECKS SETTINGS DST ALLOW -> prints "<committed allow_repo_local
# _tools: 0|1> <listed> <declared> <ids>".
# Exit 3: --only names a check that is not listed. Exit 4: the list itself is
# wrong - missing, empty, not a list of ids, or naming a check that is not an
# enabled declared one - and the reason is the one line on standard output.
derive_config() {
  py "$1" "$2" "$3" "$ONLY" "$SETTINGS_REL" "$CONFIG_REL" "$4" <<'PY'
import json, site, sys
site.addsitedir(site.getusersitepackages())
import yaml
src, settings, dst, only, settings_rel, checks_rel, allow = sys.argv[1:8]
def refuse(why):
    print(why)
    sys.exit(4)
try:
    with open(settings) as fh:
        cfg = json.load(fh)
except FileNotFoundError:
    refuse("there is no %s, so no pre_push.checks list says which checks to run" % settings_rel)
except ValueError as e:
    refuse("%s is not valid JSON (%s)" % (settings_rel, e))
pp = cfg.get("pre_push") if isinstance(cfg, dict) else None
if not isinstance(pp, dict) or "checks" not in pp:
    refuse("%s has no pre_push.checks list, so nothing says which checks to run" % settings_rel)
listed = pp["checks"]
if not isinstance(listed, list) or not all(isinstance(i, str) and i for i in listed):
    refuse("pre_push.checks in %s is not a list of check ids" % settings_rel)
if not listed:
    refuse("pre_push.checks in %s is empty, so the hook would run nothing" % settings_rel)
with open(src) as fh:
    doc = yaml.safe_load(fh)
checks = (doc.get("checks") or []) if isinstance(doc, dict) else []
by_id = {c.get("id"): c for c in checks if isinstance(c, dict)}
bad = [i for i in listed if i not in by_id or by_id[i].get("enabled", True) is False]
if bad:
    refuse("pre_push.checks names %s, not an enabled check declared in %s" % (", ".join(bad), checks_rel))
keep = [by_id[i] for i in dict.fromkeys(listed)]
if only:
    keep = [c for c in keep if c.get("id") == only]
    if not keep:
        sys.exit(3)
doc["checks"] = keep
pol = doc.setdefault("policy", {})
if not isinstance(pol, dict):
    pol = doc["policy"] = {}
committed = pol.get("allow_repo_local_tools", False) is True
pol["spec_coverage"] = "off"
pol["empty_run"] = "pass"
# Never more than BOTH the committed config and this clone's opt-in allow.
pol["allow_repo_local_tools"] = committed and allow == "true"
with open(dst, "w") as fh:
    yaml.safe_dump(doc, fh, sort_keys=False)
print(1 if committed else 0, len(dict.fromkeys(listed)), len(checks), " ".join(str(c.get("id")) for c in keep))
PY
}

# summarise RESULT -> lines "<id>\t<status>" for every triggered check that did
# not pass; first line "fail" when any of them is a plain finding.
summarise() {
  py "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
bad = [c for c in d.get("checks", []) if c.get("triggered") and c.get("status") != "pass"]
print("fail" if any(c.get("status") == "fail" for c in bad) else "unmeasured")
for c in bad:
    print("%s\t%s" % (c.get("id"), c.get("status")))
PY
}

# tool_drift CHECKS TRUSTED_FILES PUSHED_FILES CHANGED TREE TOP: which files
# the listed checks run from the repository, read the way run-checks.sh reads
# them - through the same argv-classify.py (the copy beside this script),
# clause by clause: the program, every value a literal argument can name, and
# a dotted name as the module path it resolves to. Prints "TOOLS <n>", then
# "DRIFT<TAB>path (why)" for each changed path (trusted against pushed) that is
# a tool, under a tool's directory, or - for a tool at the top level or one run
# as a module, whose imports start at the top level - any top-level file; and
# "UNMAPPED<TAB>reason" for a repository-local form it cannot pin to a path
# both commits spell the same way: a symlink, a case variant, a file neither
# commit tracks, or a path into the work tree while another tree is read.
# Measured at the first gate, which matched words to paths by string:
# `python3 -m pkg.tool` and a tool named through a symlink both ran the pushed
# commit's code.
tool_drift() {
  py "$1" "$2" "$3" "$4" "$5" "$6" "$SELF_DIR/argv-classify.py" <<'PY'
import os, posixpath, site, sys, types
site.addsitedir(site.getusersitepackages())
import yaml
cfg, tf, pf, ch, tree, top, classifier = sys.argv[1:8]
AC = types.ModuleType("argv_classify")
with open(classifier) as fh:
    exec(compile(fh.read(), classifier, "exec"), AC.__dict__)
def names(p):
    return set(x for x in open(p, "rb").read().decode("utf-8", "surrogateescape").split("\0") if x)
files = names(tf) | names(pf)
dirs = set()
for f in files:
    parts = f.split("/")
    for n in range(1, len(parts)):
        dirs.add("/".join(parts[:n]))
changed = sorted(names(ch))
TREE_REAL, TOP_REAL = os.path.realpath(tree), os.path.realpath(top)
def under(p, root):
    return p == root or p.startswith(root.rstrip("/") + "/")
def reaches_repo(p):
    r = os.path.realpath(p)
    return under(r, TREE_REAL) or under(r, TOP_REAL)
tool_files, tool_dirs, unmapped = set(), set(), []
root_wide = []
def add(rel, where):
    """A repository path a check runs or reads as code. False when it cannot
    be pinned to a path both commits spell this way."""
    full = os.path.join(tree, rel)
    if rel in files:
        if os.path.islink(full):
            unmapped.append("%s names %s, a symlink" % (where, rel))
            return
        tool_files.add(rel)
        d = posixpath.dirname(rel)
        if d:
            tool_dirs.add(d)
        else:
            root_wide.append(where)
        return
    if rel in dirs:
        tool_dirs.add(rel)
        return
    if os.path.lexists(full):
        unmapped.append("%s names %s, which is on disk but tracked under no such name in either commit (a case variant, a path through a symlink, or an untracked file)" % (where, rel))
        return
    # Spelled as a path neither commit has: nothing to compare yet, and the
    # pushed commit adding it would show in the changed paths.
    tool_files.add(rel)
    if not posixpath.dirname(rel):
        root_wide.append(where)
def value(v, shaped, where):
    if not v or "\0" in v or AC.has_placeholder(v):
        return
    if v.startswith("/"):
        for root in (tree, TREE_REAL):
            rel = AC.normalise(v, root)
            if rel is not None:
                add(rel, where)
                return
        if reaches_repo(v):
            unmapped.append("%s names an absolute path that reaches the repository%s" % (
                where, " through a symlink" if not (under(v, top) or under(v, tree)) else " in the work tree while another tree is read"))
        return
    rel = AC.normalise(v, tree)
    if rel is None:
        return
    full = os.path.join(tree, rel)
    counts = (rel in files or rel in dirs or os.path.lexists(full)
              or AC.SCRIPT_EXT.search(rel) or v.startswith("./")
              or (shaped and "/" in v and AC.path_shaped(v)))
    if counts:
        add(rel, where)
    elif reaches_repo(full) and os.path.lexists(full):
        unmapped.append("%s names %s, which reaches the repository through a symlink" % (where, v))
def module(v, where):
    if v in files or not AC.module_paths(v):
        return
    paths = AC.module_paths(v)
    if not any(m in files or m in dirs or os.path.lexists(os.path.join(tree, m)) for m in paths):
        return
    top_pkg = v.split(".")[0]
    dotted = v.replace(".", "/")
    if top_pkg in dirs:
        tool_dirs.add(top_pkg)
    for rel in (top_pkg + ".py", dotted + ".py", dotted + "/__init__.py"):
        if rel in files or not os.path.lexists(os.path.join(tree, rel)):
            tool_files.add(rel)
        else:
            unmapped.append("%s runs module %s, whose %s is on disk but tracked under no such name" % (where, v, rel))
    root_wide.append(where)
def program(prog, where):
    if not prog or AC.has_placeholder(prog) or prog in (".", ".."):
        return
    if "/" in prog:
        value(prog, True, where)
        return
    if prog in files or os.path.lexists(os.path.join(tree, prog)):
        add(prog, where)
        return
    for d in os.environ.get("PATH", "").split(os.pathsep):
        cand = os.path.join(d if d and os.path.isabs(d) else os.path.join(tree, d or "."), prog)
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            if reaches_repo(cand):
                unmapped.append("%s's program is found through a PATH entry inside the repository" % where)
            return
doc = yaml.safe_load(open(cfg)) or {}
for c in doc.get("checks") or []:
    cid = str(c.get("id"))
    argvs = []
    for k in ("command", "version_command"):
        if isinstance(c.get(k), list):
            argvs.append(("%s.%s" % (cid, k), c[k]))
    cov = c.get("coverage") or {}
    for k in ("command", "rules_command"):
        if isinstance(cov.get(k), list):
            argvs.append(("%s.coverage.%s" % (cid, k), cov[k]))
    for i, r in enumerate(c.get("requires") or []):
        if isinstance(r, str):
            program(r, "%s.requires[%d]" % (cid, i))
    for where, argv in argvs:
        if not argv or not all(isinstance(t, str) for t in argv):
            unmapped.append("%s is not a list of strings" % where)
            continue
        program(argv[0], "%s[0]" % where)
        for k in range(1, len(argv)):
            tok = argv[k]
            if AC.has_placeholder(tok):
                continue
            for v, shaped in AC.values(tok):
                value(v, shaped, "%s[%d]" % (where, k))
                module(v, "%s[%d]" % (where, k))
print("TOOLS\t%d" % (len(tool_files) + len(tool_dirs) + (1 if root_wide else 0)))
for p in changed:
    if p in tool_files:
        print("DRIFT\t%s (a tool a listed check runs)" % p)
    elif any(p.startswith(d + "/") for d in tool_dirs):
        print("DRIFT\t%s (in a tool's directory)" % p)
    elif root_wide and "/" not in p:
        print("DRIFT\t%s (a top-level file, which %s can load)" % (p, root_wide[0]))
for u in dict.fromkeys(unmapped):
    print("UNMAPPED\t%s" % u)
PY
}

# config_hits FILE: each NUL-separated path in FILE whose base name matches a
# CONFIG_DENY pattern, compared in lower case on both sides, one per line.
config_hits() {
  local p b g
  local -a deny=()
  for g in "${CONFIG_DENY[@]}"; do deny+=("$("$TR" '[:upper:]' '[:lower:]' <<<"$g")"); done
  while IFS= read -r -d '' p; do
    b="$("$TR" '[:upper:]' '[:lower:]' <<<"${p##*/}")"
    for g in "${deny[@]}"; do
      # shellcheck disable=SC2053  # the right side is a glob on purpose
      if [[ $b == $g ]]; then printf '%s\n' "$p"; break; fi
    done
  done < "$1"
}

# local_off_again: at a refusal, repeat why repo-local tools were off. The
# runner's own advice, "set policy.allow_repo_local_tools: true", is about the
# derived copy this script wrote; the committed config already sets it.
local_off_again() {
  [ -n "$LOCAL_OFF" ] || return 0
  say "the runner's advice above to set policy.allow_repo_local_tools is about the derived copy, which this hook writes with it off; the committed config already sets it."
  say "$LOCAL_OFF"
}

WORST=0
raise() { [ "$1" -le "$WORST" ] || WORST="$1"; }
UNIT_N=0
SEEN=""

while IFS="$(printf '\t')" read -r SHA BASE LABEL HOW TRUSTED TWHY; do
  key="$SHA:$BASE:$TRUSTED"
  case " $SEEN " in *" $key "*) continue ;; esac
  SEEN="$SEEN $key"
  UNIT_N=$((UNIT_N + 1))
  U="$WORK/u$UNIT_N"
  mkdir -p "$U"
  say "$HOW"

  # Paths present in the pushed commit, and the deletions counted apart.
  git -C "$TOP" diff --no-renames --name-only --diff-filter=d -z "$BASE" "$SHA" > "$U/present.z"
  DELETED="$(git -C "$TOP" diff --no-renames --name-only --diff-filter=D -z "$BASE" "$SHA" | tr -cd '\0' | wc -c | tr -d ' ')"
  : > "$U/changed.txt"
  while IFS= read -r -d '' f; do
    case "$f" in *$'\n'*) die_usage "a pushed path contains a newline, which the runner's change list cannot carry. Refused." ;; esac
    printf '%s\n' "$f" >> "$U/changed.txt"
  done < "$U/present.z"
  NFILES="$(wc -l < "$U/changed.txt" | tr -d ' ')"
  if [ "$NFILES" -eq 0 ]; then
    if [ "$DELETED" -gt 0 ]; then
      say "$LABEL carries only deletions ($DELETED path(s)); no check can open a file that is gone. Nothing to check."
    else
      say "$LABEL changes no file; nothing to check."
    fi
    continue
  fi

  # Whose config: the trusted commit's, read with git. The pushed commit's is
  # compared with it and, when it differs, used only under the clone's opt-in.
  CB_T="-"
  if [ "$TRUSTED" != "-" ]; then
    CB_T="$(config_blob "$TRUSTED" "$CONFIG_REL" "$U/trusted.checks.yaml")"
    config_blob "$TRUSTED" "$SETTINGS_REL" "$U/trusted.config.json" > /dev/null
  fi
  CB_P="$(config_blob "$SHA" "$CONFIG_REL" "$U/pushed.checks.yaml")"
  config_blob "$SHA" "$SETTINGS_REL" "$U/pushed.config.json" > /dev/null
  CHANGED_CFG=""
  [ "$CB_T" = "$CB_P" ] || CHANGED_CFG="$CONFIG_REL"
  prc=0
  pre_push_differs "$U/trusted.config.json" "$U/pushed.config.json" || prc=$?
  case "$prc" in
    0) CHANGED_CFG="${CHANGED_CFG:+$CHANGED_CFG and }the pre_push block of $SETTINGS_REL" ;;
    1) ;;
    *) say "could not compare $SETTINGS_REL in ${SHA:0:12} with the trusted commit (exit $prc). Unverified, not a pass."; raise 2; continue ;;
  esac
  if [ "$TRUSTED" = "-" ] || [ -n "$CHANGED_CFG" ]; then
    if [ "$TRUST_PUSHED" != true ]; then
      if [ "$TRUSTED" = "-" ]; then
        say "REFUSED: $TWHY, so there is no trusted commit to read the checks and their commands from, and the pushed commit's own config is never taken by default: it would choose what runs on this machine."
      else
        say "REFUSED: ${SHA:0:12} changes $CHANGED_CFG against the trusted commit, $TWHY. The checks and their commands come from the trusted commit, never from the one being pushed: a commit fetched from someone else would otherwise choose what runs on this machine when you push it."
      fi
      say "  if the change is your own, trust the pushed config for this clone - a setting in .git/config, which no commit can carry: $TRUST_LINE"
      raise 2; continue
    fi
    if [ "$TRUSTED" = "-" ]; then
      say "no trusted commit: ${TWHY}. ${SHA:0:12}'s own config is used because productizer.prePush.trustPushedConfig is true in this clone's .git/config."
    else
      say "${SHA:0:12} changes $CHANGED_CFG against ${TWHY}; its own config is used because productizer.prePush.trustPushedConfig is true in this clone's .git/config."
    fi
    SRC_C="$U/pushed.checks.yaml"; SRC_S="$U/pushed.config.json"; SRC_AT="${SHA:0:12}, the pushed commit"
  else
    SRC_C="$U/trusted.checks.yaml"; SRC_S="$U/trusted.config.json"; SRC_AT="${TRUSTED:0:12}, $TWHY"
    say "checks and their commands read from the trusted commit, $TWHY; the pushed commit's checks config is the same."
  fi

  # Foreign config: a file a common tool reads as settings or plugin code,
  # changed against the trusted commit, refuses unless the clone trusts
  # pushed configs.
  if [ "$TRUSTED" != "-" ] && [ "$TRUST_PUSHED" != true ]; then
    git -C "$TOP" diff --no-renames --name-only -z "$TRUSTED" "$SHA" > "$U/cfgdiff.z"
    CFG_HITS="$(config_hits "$U/cfgdiff.z")"
    if [ -n "$CFG_HITS" ]; then
      say "REFUSED: ${SHA:0:12} changes, against the trusted commit, file(s) a common tool reads as its settings or plugin code: $(tr '\n' ' ' <<<"$CFG_HITS")- the checks would run under the pushed commit's settings. The list of such names is in pre-push-checks.sh and can never be complete; this hook is for your own commits. Push someone else's branch with git push --no-verify - CI still checks everything."
      say "  if the change is your own, trust the pushed config for this clone - a setting in .git/config, which no commit can carry: $TRUST_LINE"
      raise 2; continue
    fi
  fi

  # Which tree to read. Attributes come from the trusted commit (the pushed
  # one only under trustPushedConfig), and the temporary worktree is made with
  # no hooks: measured, `git worktree add` runs post-checkout.
  ATTR_SRC="$TRUSTED"
  [ "$ATTR_SRC" != "-" ] || ATTR_SRC="$SHA"
  mkdir -p "$WORK/no-hooks"
  TREE="$TOP"
  HEAD_SHA="$(git -C "$TOP" rev-parse -q --verify 'HEAD^{commit}' || true)"
  if [ "$HEAD_SHA" != "$SHA" ] || ! git -C "$TOP" --attr-source="$ATTR_SRC" diff --quiet HEAD --; then
    TREE="$WORK/tree$UNIT_N"
    git -C "$TOP" --attr-source="$ATTR_SRC" -c core.hooksPath="$WORK/no-hooks" worktree add -q --detach "$TREE" "$SHA" || { say "could not create a temporary worktree at ${SHA:0:12}. Unverified."; raise 2; continue; }
    WORKTREES+=("$TREE")
    if [ "$HEAD_SHA" != "$SHA" ]; then
      say "${SHA:0:12} is not the checked-out commit, so it is read from a temporary worktree."
    else
      say "tracked files differ from the pushed commit, so ${SHA:0:12} is read from a temporary worktree, not the work tree."
    fi
  fi

  if [ ! -f "$SRC_C" ]; then
    say "REFUSED: there is no $CONFIG_REL in $SRC_AT, so no check the hook could run is declared. A hook that runs nothing is not a pass."
    raise 2; continue
  fi
  drc=0
  INFO="$(derive_config "$SRC_C" "$SRC_S" "$U/checks.yaml" "$ALLOW_LOCAL")" || drc=$?
  if [ "$drc" -eq 3 ]; then
    die_usage "--only $ONLY is not one of the checks listed in pre_push.checks in $SETTINGS_REL."
  elif [ "$drc" -eq 4 ]; then
    say "REFUSED: $INFO, in $SRC_AT. List the ids of the cheap declared checks under pre_push.checks; a hook that runs nothing is not a pass."
    raise 2; continue
  elif [ "$drc" -ne 0 ]; then
    say "could not read $CONFIG_REL in $SRC_AT (exit $drc). Unverified, not a pass."
    raise 2; continue
  fi
  read -r WANTS_LOCAL NLIST NDECL IDS <<<"$INFO"
  LOCAL_OFF=""
  if [ "$WANTS_LOCAL" = 1 ] && [ "$ALLOW_LOCAL" != true ]; then
    LOCAL_OFF="the checks config sets policy.allow_repo_local_tools: true, and the hook runs with it OFF: on a push it would let the repository choose programs inside itself to run on this machine, so the runner refuses a listed check whose tool lives in the repository, and the push stops. If this is your own repository, allow it for this clone - a setting in .git/config, which no commit can carry: $LOCAL_LINE"
    say "$LOCAL_OFF"
  fi
  RL_STATE="off"
  if [ "$WANTS_LOCAL" = 1 ] && [ "$ALLOW_LOCAL" = true ]; then RL_STATE="on (the config and productizer.prePush.allowRepoLocalTools both allow it)"; fi
  say "$NLIST of $NDECL declared checks are listed in pre_push.checks ($IDS); $NFILES pushed file(s), $DELETED deletion(s) left out."
  say "the runner below reads a derived copy of $CONFIG_REL: unlisted checks removed, spec_coverage off, empty_run pass, allow_repo_local_tools $RL_STATE. Its \"committed opt-out\" line is about that copy; CI runs the committed config."

  # REPO-LOCAL TOOLS ARE THE TRUSTED COMMIT'S, OR NOTHING RUNS. With them
  # allowed, the runner runs a repository script from the tree being checked,
  # which is the pushed commit. Running it from the trusted commit's tree while
  # handing it the pushed files is not something run-checks.sh can do: one
  # root serves both, and a pushed change to a tool is at once a file to check
  # and a program to run. So the push is refused when the pushed commit
  # differs from the trusted one in any file a listed check names in its argv,
  # or under the directory of one (for a top-level tool, every top-level
  # file), unless the clone trusts
  # pushed configs. Measured: a branch whose ./check.sh wrote a marker ran it.
  if [ "$WANTS_LOCAL" = 1 ] && [ "$ALLOW_LOCAL" = true ] && [ "$TRUSTED" != "-" ] && [ "$TRUST_PUSHED" != true ]; then
    git -C "$TOP" ls-tree -r -z --name-only "$TRUSTED" > "$U/trusted.files"
    git -C "$TOP" ls-tree -r -z --name-only "$SHA" > "$U/pushed.files"
    git -C "$TOP" diff --no-renames --name-only -z "$TRUSTED" "$SHA" > "$U/drift.z"
    trc=0
    DRIFT="$(tool_drift "$U/checks.yaml" "$U/trusted.files" "$U/pushed.files" "$U/drift.z" "$TREE" "$TOP")" || trc=$?
    if [ "$trc" -ne 0 ]; then
      say "could not compare the repo-local tools of ${SHA:0:12} with the trusted commit (exit $trc). Unverified, not a pass."
      raise 2; continue
    fi
    NTOOLS="$(awk -F '	' '$1 == "TOOLS" { print $2 }' <<<"$DRIFT")"
    UNMAPPED="$(awk -F '	' '$1 == "UNMAPPED" { print $2 }' <<<"$DRIFT")"
    DRIFTED="$(awk -F '	' '$1 == "DRIFT" { print $2 }' <<<"$DRIFT")"
    if [ -z "$NTOOLS" ]; then
      say "could not read which repo-local tools the listed checks run (no TOOLS line). Unverified, not a pass."
      raise 2; continue
    fi
    if [ -n "$UNMAPPED" ]; then
      say "REFUSED: a listed check runs something in the repository that the hook cannot map to files both commits name, so it cannot show the pushed commit left it unchanged: $(sed -n '1,3p' <<<"$UNMAPPED" | tr '\n' ';') - fail closed. Name the tool by a plain repository path in checks.yaml."
      say "  if the change is your own, trust the pushed config for this clone - a setting in .git/config, which no commit can carry: $TRUST_LINE"
      raise 2; continue
    fi
    if [ -n "$DRIFTED" ]; then
      say "REFUSED: ${SHA:0:12} changes, against the trusted commit, files the listed checks run or can load: $(sed -n '1,5p' <<<"$DRIFTED" | tr '\n' ' ')- with productizer.prePush.allowRepoLocalTools the hook runs repository scripts from the tree it checks, and these would be the pushed commit's code, not the trusted commit's."
      say "  if the change is your own, trust the pushed config for this clone - a setting in .git/config, which no commit can carry: $TRUST_LINE"
      raise 2; continue
    fi
    say "repo-local tools: $NTOOLS path(s) the listed checks name, and their directories, are the same in the pushed commit as in the trusted one."
  fi

  rrc=0
  # The runner runs its own Python, which this script does not write: every
  # PYTHON* variable is dropped for it, so a PYTHONPATH reaching into the
  # pushed tree cannot put a module there ahead of the real one (measured:
  # with PYTHONPATH at the work tree, the runner imported its json.py twice).
  # A PyYAML found only through such a variable is then not found, and the
  # runner refuses, saying so - never a pass.
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    for v in $(compgen -e); do case "$v" in PYTHON*) unset "$v" ;; esac; done
    export GIT_ATTR_SOURCE="$ATTR_SRC"
    "$RUNNER" --config "$U/checks.yaml" --root "$TREE" --changed "$U/changed.txt" --out "$U/result.json" < /dev/null ) >&2 || rrc=$?

  if [ "$BASE" = "$EMPTY_TREE" ]; then RERUN_BASE="$EMPTY_TREE"; else RERUN_BASE="$BASE"; fi
  case "$rrc" in
    0) say "PASS: $LABEL - every listed check passed over the pushed files." ;;
    3)
      if [ ! -f "$U/result.json" ]; then
        say "the runner refused without a result file. Unverified, not a pass."; raise 2; continue
      fi
      KIND=""
      while IFS="$(printf '\t')" read -r cid cstatus; do
        if [ -z "$KIND" ]; then KIND="$cid"; continue; fi
        say "BLOCKED: '$cid' came back $cstatus on $LABEL."
        say "  re-run it: $(printf '%q' "$SELF") --base $RERUN_BASE --head $SHA --only $(printf '%q' "$cid")"
      done < <(summarise "$U/result.json")
      if [ "$KIND" = fail ]; then raise 1; else
        say "a listed check could not reach a verdict on $LABEL, which is not a pass."
        local_off_again
        raise 2
      fi
      ;;
    *)
      say "the checks runner could not reach a verdict on $LABEL (exit $rrc). Unverified, not a pass."
      local_off_again
      raise 2
      ;;
  esac
done < "$UNITS"

if [ "$WORST" -ne 0 ]; then
  say "push stopped. 'git push --no-verify' skips this hook - a known limit: it is a convenience in front of CI, not a gate, and nothing above was checked if you use it."
fi
exit "$WORST"
