#!/usr/bin/env bash
# install-hooks.sh [--repo DIR] [--dry-run] [--uninstall]
#                  [--allow-repo-local-tools] [--trust-pushed-config]
#                  [--trusted-ref REF] [--version] [--help] [--selftest|--self-test]
#
# Installs `templates/pre-push` as the pre-push hook of a repository. See
# pre-push-checks.sh for what the hook runs and why.
#
# THE HOOK RUNS COPIES, NEVER THE PLUGIN'S FILES. The checker, the runner and
# its helper (PRE_PUSH_FILES below) are copied to a directory under the git
# directory, `git rev-parse --git-path productizer-pre-push`, which no checkout
# touches and nothing tracks, with a MANIFEST of their sha256s; the hook
# records the MANIFEST's sha256. Before running anything the hook compares
# every file and refuses the push on a missing or changed one. Measured at the
# first 1.1: the hook hashed the checker only, and the checker then ran
# run-checks.sh from beside itself - inside the work tree in this repository,
# where a checkout of a foreign branch replaced it, and its code ran on push.
# The hook never falls back to a checker inside the repository. A plugin
# update changes the scripts: re-run this, and the run says "updated".
# $PRODUCTIZER_PRE_PUSH_CHECKS overrides the copies at push time; it is
# trusted because the user sets it, and nothing it runs is compared.
#
# THE TWO OPT-INS ARE NEVER SET BY DEFAULT. pre-push-checks.sh reads two keys
# from this clone's .git/config only (`git config --local`), never from a
# commit:
#   --allow-repo-local-tools  sets productizer.prePush.allowRepoLocalTools true:
#                             the hook may run check tools that live inside the
#                             repository, where its config also allows them.
#   --trust-pushed-config     sets productizer.prePush.trustPushedConfig true:
#                             a pushed commit whose checks config differs from
#                             the trusted one is checked by its own config
#                             instead of being refused.
#   --trusted-ref REF         sets productizer.prePush.trustedRef REF: the
#                             remote-tracking ref (refs/remotes/<remote>/<branch>)
#                             whose history the hook trusts. Unset, the hook uses
#                             refs/remotes/origin/main, then .../origin/master.
# Each prints the exact `git config --local` line it ran. Pass one only for a
# repository whose committed scripts you would run anyway; without it, nothing
# is written to .git/config.
#
# WHERE IT GOES. Wherever git will run it from: `git rev-parse
# --path-format=absolute --git-path hooks`, which honours `core.hooksPath`
# (relative or absolute) and resolves a linked worktree to the common hooks
# directory. Never a hardcoded `.git/hooks`: with `core.hooksPath` set, a hook
# written there is a file git never runs, and the install would report success
# over a hook that does nothing. When `core.hooksPath` is set the run says so.
#
# IT NEVER OVERWRITES A HOOK IT DID NOT WRITE. Its own file is recognised by
# the first-line marker `productizer-pre-push-hook`. A pre-push hook without
# it - or a symlink, whatever it points at - is someone else's: the install
# refuses, exits 2, changes nothing, and prints the two ways to chain them:
#   1. move the existing hook to `pre-push.chained` beside it and re-run this;
#      the installed hook runs `pre-push.chained` first with the same arguments
#      and stdin, and stops the push if it does;
#   2. or keep your hook and add one line to it that runs pre-push-checks.sh
#      with the remote name and the same stdin.
#
# IDEMPOTENT. Its own hook, byte-identical to what it would write: nothing to
# do, exit 0, file untouched. Its own hook with other bytes (an older version,
# or a plugin update moved the scripts): rewritten, and the run says "updated".
#
#   --dry-run    says what it would do and writes nothing. Same exit code as
#                the real run would have.
#   --uninstall  removes the hook ONLY if it is this script's own. Someone
#                else's hook is refused exactly as on install. No hook: nothing
#                to remove, exit 0. `pre-push.chained` is never touched, and
#                neither are the opt-ins (unset them with git config --unset).
#
# EXIT CODES ARE THE CONTRACT.
#   0  installed, updated, removed, or nothing to do - each said so
#   2  refused (a hook it did not write is in the way), or usage (not a git
#      repository, the template is missing, an unknown argument)
#
# KNOWN LIMITS. `git push --no-verify` skips the installed hook. A shared
# `core.hooksPath` directory is shared: installing there installs for every
# repository pointing at it, which the run states. The hook records an
# absolute path; moving the plugin means re-running this.
set -euo pipefail

VERSION="install-hooks 1.1"
MARKER="productizer-pre-push-hook"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SELF_DIR/../templates/pre-push"
# The files the hook runs, copied under the git directory. Measured, not read:
# a push through the hook with bash and python3 wrapped to log their argv, and
# again with the plugin directory removed after install, ran exactly these -
# the checker, the runner it calls, and the argv reader the runner hands to
# python3. Nothing else is executed or sourced from beside them.
PRE_PUSH_FILES=(pre-push-checks.sh run-checks.sh argv-classify.py)
REPO="."
DRY=""
ACTION="install"
MODE="run"
OPTINS=()
TRUSTED_REF=""

usage() {
  printf 'usage: install-hooks.sh [--repo DIR] [--dry-run] [--uninstall]\n'
  printf '                        [--allow-repo-local-tools] [--trust-pushed-config]\n'
  printf '                        [--version] [--help] [--selftest]\n'
  printf '  installs templates/pre-push as the pre-push hook of DIR (default: the current directory),\n'
  printf '  recording the absolute path and sha256 of pre-push-checks.sh; the hook stops the push if\n'
  printf '  that file goes missing or changes, and never runs a checker inside the repository.\n'
  printf '  PRODUCTIZER_PRE_PUSH_CHECKS overrides that path at push time. It is trusted because you\n'
  printf '  set it in your own environment, and its sha256 is not compared.\n'
  printf '  --allow-repo-local-tools  git config --local productizer.prePush.allowRepoLocalTools true\n'
  printf '  --trust-pushed-config     git config --local productizer.prePush.trustPushedConfig true\n'
  printf '  --trusted-ref REF         git config --local productizer.prePush.trustedRef REF\n'
  printf '                            (a full remote-tracking ref; unset, the hook trusts origin/main, then origin/master)\n'
  printf '  None is ever set without its flag. Never overwrites a hook it did not write.\n'
  printf '  git push --no-verify bypasses the hook.\n'
}
# sha256_of FILE -> the hex digest, computed exactly as templates/pre-push does.
sha256_of() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{ print $1 }'
  elif command -v shasum >/dev/null; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    return 1
  fi
}
# The marker is looked for in the first three lines only, read by awk from the
# file: a pipe into an early-exiting grep can turn a match into SIGPIPE.
has_marker() { awk -v m="$MARKER" 'NR > 3 { exit } index($0, m) { found = 1; exit } END { exit !found }' "$1"; }
die_usage() { printf 'install-hooks: %s\n' "$1" >&2; exit 2; }
say() { printf 'install-hooks: %s%s\n' "${DRY:+(dry run) }" "$1"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) [ "$#" -ge 2 ] || die_usage "--repo needs a directory"; REPO="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --allow-repo-local-tools) OPTINS+=(allowRepoLocalTools); shift ;;
    --trust-pushed-config) OPTINS+=(trustPushedConfig); shift ;;
    --trusted-ref) [ "$#" -ge 2 ] || die_usage "--trusted-ref needs a ref"; TRUSTED_REF="$2"; shift 2 ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h | --help) usage; exit 0 ;;
    --selftest | --self-test) MODE="selftest"; shift ;;
    *) usage >&2; die_usage "unknown argument: $1" ;;
  esac
done

# ---------------------------------------------------------------------------
# --selftest. Every case in a throwaway repository.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SB="$(mktemp -d "${TMPDIR:-/tmp}/install-hooks-selftest.XXXXXX")" ||
    { printf 'install-hooks: could not create a sandbox, so no case was driven. Unmeasured.\n' >&2; exit 2; }
  trap 'rm -rf "$SB"' EXIT HUP INT TERM
  SELF_ABS="$SELF_DIR/$(basename "$0")"
  export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
  export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

  FAILED=0; DRIVEN=0; CODES=""
  fail() { printf '  FAIL %-22s %s\n' "$1" "$2"; FAILED=$((FAILED + 1)); }
  # drive NAME WANT MARKER [args...]
  drive() {
    local name="$1" want="$2" marker="$3" rc=0 why=""
    shift 3
    "$SELF_ABS" "$@" > "$SB/$name.out" 2>&1 || rc=$?
    DRIVEN=$((DRIVEN + 1))
    CODES="$CODES$rc
"
    [ "$rc" -eq "$want" ] || why="exit $rc, expected $want"
    if ! grep -qF -- "$marker" "$SB/$name.out"; then
      [ -n "$why" ] && why="$why; "
      why="${why}its output does not say what it was supposed to say"
    fi
    if [ -z "$why" ]; then
      printf '  ok   %-22s exit %d - %s\n' "$name" "$rc" "$marker"
    else
      fail "$name" "$why - expected: $marker"
      sed 's/^/         | /' "$SB/$name.out"
    fi
  }
  repo() { git init -q -b main "$SB/$1"; git -C "$SB/$1" commit -q --allow-empty -m init; printf '%s\n' "$SB/$1"; }
  FOREIGN='#!/bin/sh
echo "someone else'"'"'s hook"
'

  R="$(repo fresh)"; H="$R/.git/hooks/pre-push"
  drive install 0 "installed" --repo "$R"
  D="$(git -C "$R" rev-parse --path-format=absolute --git-path productizer-pre-push)"
  { [ -x "$H" ] && has_marker "$H" && grep -qF "INSTALLED_DIR='$D'" "$H"; } ||
    fail install "the hook is not executable, lacks the marker, or does not name the copies directory $D"
  for f in "${PRE_PUSH_FILES[@]}"; do
    { cmp -s "$D/$f" "$SELF_DIR/$f" && grep -qF "$(sha256_of "$SELF_DIR/$f")  $f" "$D/MANIFEST"; } ||
      fail install "$f was not copied to $D, or the MANIFEST does not record its sha256"
  done
  grep -qF "MANIFEST_SHA256='$(sha256_of "$D/MANIFEST")'" "$H" ||
    fail install "the hook does not record the MANIFEST's sha256"
  for k in allowRepoLocalTools trustPushedConfig trustedRef; do
    rc=0; git -C "$R" config --local --get "productizer.prePush.$k" > "$SB/optin.out" || rc=$?
    [ "$rc" -eq 1 ] || fail install "an install without its flag set productizer.prePush.$k (git config exit $rc)"
  done
  cp "$H" "$SB/first"
  drive idempotent 0 "already installed" --repo "$R"
  cmp -s "$H" "$SB/first" || fail idempotent "a second install changed the hook's bytes"
  printf '# older\n' >> "$H"
  drive update-own 0 "updated" --repo "$R"
  cmp -s "$H" "$SB/first" || fail update-own "an outdated own hook was not rewritten to the template"
  drive dry-uninstall 0 "would remove" --repo "$R" --uninstall --dry-run
  [ -f "$H" ] || fail dry-uninstall "a dry run removed the hook"
  drive uninstall 0 "removed" --repo "$R" --uninstall
  { [ ! -e "$H" ] && [ ! -e "$D" ]; } || fail uninstall "the hook or the copies directory is still there"
  drive uninstall-absent 0 "nothing to remove" --repo "$R" --uninstall

  R="$(repo dry)"
  drive dry-install 0 "would install" --repo "$R" --dry-run
  [ ! -e "$R/.git/hooks/pre-push" ] || fail dry-install "a dry run wrote the hook"

  R="$(repo foreign)"; H="$R/.git/hooks/pre-push"
  printf '%s' "$FOREIGN" > "$H"; chmod +x "$H"; cp "$H" "$SB/foreign.copy"
  drive foreign-refused 2 "pre-push.chained" --repo "$R"
  cmp -s "$H" "$SB/foreign.copy" || fail foreign-refused "someone else's hook was changed"
  drive foreign-dry 2 "refusing" --repo "$R" --dry-run
  drive foreign-uninstall 2 "refusing" --repo "$R" --uninstall
  [ -f "$H" ] && cmp -s "$H" "$SB/foreign.copy" || fail foreign-uninstall "someone else's hook was removed or changed"

  R="$(repo symlink)"; H="$R/.git/hooks/pre-push"
  # The link points at one of OUR hooks, outdated, so an install that followed
  # it would "update" a file outside the hooks directory.
  cp "$SB/first" "$SB/linked-target"; printf '# older\n' >> "$SB/linked-target"; cp "$SB/linked-target" "$SB/linked-target.copy"
  ln -s "$SB/linked-target" "$H"
  drive symlink-refused 2 "is a symlink" --repo "$R"
  { [ -L "$H" ] && cmp -s "$SB/linked-target" "$SB/linked-target.copy"; } ||
    fail symlink-refused "the symlink was replaced, or the file it points at was written through it"

  R="$(repo hookspath)"
  git -C "$R" config core.hooksPath shared-hooks
  drive hookspath 0 "core.hooksPath" --repo "$R"
  { [ -f "$R/shared-hooks/pre-push" ] && [ ! -e "$R/.git/hooks/pre-push" ]; } ||
    fail hookspath "the hook did not land in core.hooksPath, or also landed in .git/hooks"

  R="$(repo worktree)"
  git -C "$R" worktree add -q "$SB/worktree-linked"
  drive linked-worktree 0 "installed" --repo "$SB/worktree-linked"
  [ -f "$R/.git/hooks/pre-push" ] || fail linked-worktree "a linked worktree's install did not reach the common hooks directory"

  # The chain, end to end: a real push runs pre-push.chained first, and its
  # refusal stops the push before the checker is reached.
  R="$(repo chain)"
  git init -q --bare "$SB/chain.git"; git -C "$R" remote add origin "$SB/chain.git"
  printf '#!/bin/sh\ntouch "%s/chained-ran"\nexit 7\n' "$SB" > "$R/.git/hooks/pre-push.chained"
  chmod +x "$R/.git/hooks/pre-push.chained"
  drive chain-install 0 "installed" --repo "$R"
  rc=0; git -C "$R" push -q origin main > "$SB/chain-push.out" 2>&1 || rc=$?
  DRIVEN=$((DRIVEN + 1))
  if [ "$rc" -ne 0 ] && [ -f "$SB/chained-ran" ] && grep -qF "pre-push.chained stopped the push (exit 7)" "$SB/chain-push.out"; then
    printf '  ok   %-22s push refused - the chained hook ran first and its exit 7 stopped it\n' chain-push
  else
    fail chain-push "push exit $rc; chained hook ran: $([ -f "$SB/chained-ran" ] && echo yes || echo no)"
    sed 's/^/         | /' "$SB/chain-push.out"
  fi

  # The opt-ins: set only by their flags, each with the line it ran.
  R="$(repo optins)"
  drive optin-flags 0 "ran: git config --local productizer.prePush.allowRepoLocalTools true" --repo "$R" --allow-repo-local-tools --trust-pushed-config --trusted-ref refs/remotes/upstream/main
  grep -qF "ran: git config --local productizer.prePush.trustedRef refs/remotes/upstream/main" "$SB/optin-flags.out" ||
    fail optin-flags "the run does not print the trustedRef line it ran"
  [ "$(git -C "$R" config --local --get productizer.prePush.trustedRef)" = refs/remotes/upstream/main ] ||
    fail optin-flags "productizer.prePush.trustedRef is not the ref given"
  grep -qF "ran: git config --local productizer.prePush.trustPushedConfig true" "$SB/optin-flags.out" ||
    fail optin-flags "the run does not print the trustPushedConfig line it ran"
  for k in allowRepoLocalTools trustPushedConfig; do
    [ "$(git -C "$R" config --local --type=bool --get "productizer.prePush.$k")" = true ] ||
      fail optin-flags "productizer.prePush.$k is not true in .git/config after its flag"
  done
  R="$(repo optindry)"
  drive optin-dry 0 "would run: git config --local productizer.prePush.allowRepoLocalTools true" --repo "$R" --dry-run --allow-repo-local-tools
  rc=0; git -C "$R" config --local --get productizer.prePush.allowRepoLocalTools > "$SB/optin.out" || rc=$?
  [ "$rc" -eq 1 ] || fail optin-dry "a dry run set productizer.prePush.allowRepoLocalTools"
  drive optin-uninstall 2 "go with an install, not --uninstall" --repo "$R" --uninstall --trust-pushed-config
  drive trusted-ref-short 2 "is not a full remote-tracking ref" --repo "$R" --trusted-ref main

  # WHAT THE HOOK RUNS (B190 security), end to end through real pushes. A
  # copy of the plugin layout whose checker and runner are stubs: the checker
  # leaves a marker and runs the runner beside it, which leaves another. The
  # repository holds checkers of its own at both paths 1.0 fell back to, each
  # leaving a third marker: none of those may ever run.
  PL="$SB/plugin"; mkdir -p "$PL/scripts" "$PL/templates"
  cp "$SELF_ABS" "$PL/scripts/install-hooks.sh"; cp "$TEMPLATE" "$PL/templates/pre-push"
  stub() { printf '#!/bin/sh\ncat > /dev/null\ntouch "%s"\nexit 0\n' "$2" > "$1"; chmod +x "$1"; }
  printf '#!/bin/sh\ncat > /dev/null\ntouch "%s"\nexec "$(dirname "$0")/run-checks.sh"\n' "$SB/recorded-ran" > "$PL/scripts/pre-push-checks.sh"
  chmod +x "$PL/scripts/pre-push-checks.sh"
  stub "$PL/scripts/run-checks.sh" "$SB/runner-ran"
  printf '# argv reader stub\n' > "$PL/scripts/argv-classify.py"
  R="$(repo tmpl)"
  git init -q --bare "$SB/tmpl.git"; git -C "$R" remote add origin "$SB/tmpl.git"
  mkdir -p "$R/.claude/productizer/bin" "$R/plugins/productizer/skills/spec/scripts"
  stub "$R/.claude/productizer/bin/pre-push-checks.sh" "$SB/repo-ran"
  stub "$R/plugins/productizer/skills/spec/scripts/pre-push-checks.sh" "$SB/repo-ran"
  git -C "$R" add -A; git -C "$R" commit -q -m "the repository ships checkers"
  "$PL/scripts/install-hooks.sh" --repo "$R" > "$SB/tmpl-install.out" 2>&1 ||
    { printf 'install-hooks: the plugin copy did not install, so the checker cases have no hook. Unmeasured.\n' >&2; sed 's/^/         | /' "$SB/tmpl-install.out" >&2; exit 2; }
  D="$(git -C "$R" rev-parse --path-format=absolute --git-path productizer-pre-push)"
  N=0
  # tpush NAME WANT(0 pushed, 1 stopped) MARKER [VAR=value...]: a new commit,
  # then a real push through the hook.
  tpush() {
    local name="$1" want="$2" marker="$3" rc=0 why=""
    shift 3
    N=$((N + 1)); git -C "$R" commit -q --allow-empty -m "push $N"
    rm -f "$SB/recorded-ran" "$SB/runner-ran" "$SB/repo-ran" "$SB/env-ran" "$SB/source-ran"
    env "$@" git -C "$R" push origin main > "$SB/$name.out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ] || rc=1
    DRIVEN=$((DRIVEN + 1))
    [ "$rc" -eq "$want" ] || why="push exit $rc, expected $want"
    if ! grep -qF -- "$marker" "$SB/$name.out"; then why="${why:+$why; }its output does not say: $marker"; fi
    if [ -e "$SB/repo-ran" ]; then why="${why:+$why; }a checker inside the repository ran"; fi
    if [ -e "$SB/source-ran" ]; then why="${why:+$why; }a plugin file, not its installed copy, ran"; fi
    if [ -z "$why" ]; then
      printf '  ok   %-22s push %s - %s\n' "$name" "$([ "$rc" -eq 0 ] && echo through || echo stopped)" "$marker"
    else
      fail "$name" "$why"
      sed 's/^/         | /' "$SB/$name.out"
    fi
  }
  tpush recorded-runs 0 "main -> main"
  { [ -e "$SB/recorded-ran" ] && [ -e "$SB/runner-ran" ]; } || fail recorded-runs "the copied checker or the copied runner did not run"
  # The plugin's own runner replaced after install, as a checkout replaces a
  # plugin that lives in the work tree: the copy runs, the replacement never.
  stub "$PL/scripts/run-checks.sh" "$SB/source-ran"
  tpush source-swapped 0 "main -> main"
  [ -e "$SB/runner-ran" ] || fail source-swapped "the copied runner did not run"
  # Each copied file changed, then one removed, then the MANIFEST changed:
  # stopped, and nothing ran.
  for f in pre-push-checks.sh run-checks.sh argv-classify.py; do
    cp -p "$D/$f" "$SB/keep"; printf '# changed after install\n' >> "$D/$f"
    tpush "copy-changed-${f%%.*}" 1 "has changed since install-hooks.sh recorded it"
    { [ ! -e "$SB/recorded-ran" ] && [ ! -e "$SB/runner-ran" ]; } || fail "copy-changed-${f%%.*}" "a changed copy did not stop the run"
    cp -p "$SB/keep" "$D/$f"
  done
  mv "$D/run-checks.sh" "$SB/keep"
  tpush copy-missing 1 "is missing"
  mv "$SB/keep" "$D/run-checks.sh"
  printf '0000  extra.sh\n' >> "$D/MANIFEST"
  tpush manifest-changed 1 "MANIFEST' has changed since install-hooks.sh wrote it"
  "$PL/scripts/install-hooks.sh" --repo "$R" > "$SB/tmpl-reinstall.out" 2>&1 || fail reinstall "re-running the installer failed"
  stub "$PL/scripts/run-checks.sh" "$SB/runner-ran"
  "$PL/scripts/install-hooks.sh" --repo "$R" > "$SB/tmpl-reinstall.out" 2>&1 || fail reinstall "re-running the installer failed"
  tpush reinstall-accepts 0 "main -> main"
  [ -e "$SB/recorded-ran" ] || fail reinstall-accepts "after the re-install the copied checker did not run"
  stub "$SB/env-checker" "$SB/env-ran"
  tpush env-override 0 "trusted because you set it" PRODUCTIZER_PRE_PUSH_CHECKS="$SB/env-checker"
  [ -e "$SB/env-ran" ] && [ ! -e "$SB/recorded-ran" ] || fail env-override "the override did not replace the copies"
  rm -rf "$D"
  tpush checker-missing 1 "Re-run install-hooks.sh"

  drive not-a-repo 2 "not a git repository" --repo "$SB"
  drive usage 2 "unknown argument" --frobnicate

  printf '  cases driven: %d. Assertions that did not hold: %d\n' "$DRIVEN" "$FAILED"
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 2; do
    grep -qx "$want" <<<"$CODES" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 2\n' "$REACHED"
  printf '  NOT ASSERTED: a bare repository, an absolute core.hooksPath shared by several repositories, file permissions other than the executable bit, and a git older than 2.31 (no --path-format).\n'
  if [ "$FAILED" -ne 0 ]; then
    printf 'FAIL: %d selftest case(s) did not hold.\n' "$FAILED" >&2
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
[ -f "$TEMPLATE" ] || die_usage "the hook template is not at $TEMPLATE."
[ "$ACTION" = install ] || { [ "${#OPTINS[@]}" -eq 0 ] && [ -z "$TRUSTED_REF" ]; } ||
  die_usage "--allow-repo-local-tools, --trust-pushed-config and --trusted-ref go with an install, not --uninstall; unset them with git config --local --unset."
case "$TRUSTED_REF" in
  "" | refs/remotes/?*/?*) ;;
  *) die_usage "--trusted-ref $TRUSTED_REF is not a full remote-tracking ref; name one as refs/remotes/<remote>/<branch>." ;;
esac
for f in "${PRE_PUSH_FILES[@]}"; do
  [ -f "$SELF_DIR/$f" ] || die_usage "$f is not beside install-hooks.sh at $SELF_DIR; the hook runs it, so nothing is installed without it."
done
[ -d "$REPO" ] || die_usage "--repo $REPO is not a directory."
if ! git -C "$REPO" rev-parse --git-dir >/dev/null; then
  die_usage "$REPO is not a git repository."
fi
HOOKS="$(git -C "$REPO" rev-parse --path-format=absolute --git-path hooks)" ||
  die_usage "git could not name the hooks directory of $REPO (git 2.31 or later is needed for --path-format)."
HOOK="$HOOKS/pre-push"
DEST="$(git -C "$REPO" rev-parse --path-format=absolute --git-path productizer-pre-push)" ||
  die_usage "git could not name a directory under the git directory of $REPO."

HOOKSPATH=""
if HOOKSPATH="$(git -C "$REPO" config --get core.hooksPath)"; then
  say "core.hooksPath is set to '$HOOKSPATH', so the hook goes to $HOOKS. Every repository using that directory gets it."
fi

CHAIN_HELP="To chain them: move it to $HOOKS/pre-push.chained and re-run this (the installed hook runs pre-push.chained first, with the same arguments and stdin), or keep it and add a line to it that runs: $DEST/pre-push-checks.sh --remote \"\$1\" with the same stdin."

ours() { [ -f "$1" ] && [ ! -L "$1" ] && has_marker "$1"; }

if [ -L "$HOOK" ]; then
  printf 'install-hooks: refusing: %s is a symlink, and a hook this script did not write is never replaced or removed. %s\n' "$HOOK" "$CHAIN_HELP" >&2
  exit 2
fi
if [ -e "$HOOK" ] && ! ours "$HOOK"; then
  printf 'install-hooks: refusing: %s is a pre-push hook this script did not write, and it is never replaced or removed. %s\n' "$HOOK" "$CHAIN_HELP" >&2
  exit 2
fi

if [ "$ACTION" = "uninstall" ]; then
  if [ ! -e "$HOOK" ] && [ ! -e "$DEST" ]; then
    say "no pre-push hook at $HOOK; nothing to remove."
    exit 0
  fi
  if [ -n "$DRY" ]; then
    [ ! -e "$HOOK" ] || say "would remove $HOOK."
    [ ! -e "$DEST" ] || say "would remove the copies in $DEST."
  else
    if [ -e "$HOOK" ]; then rm -f "$HOOK"; say "removed $HOOK."; fi
    if [ -e "$DEST" ]; then rm -rf "$DEST"; say "removed the copies in $DEST."; fi
  fi
  [ ! -e "$HOOKS/pre-push.chained" ] || say "$HOOKS/pre-push.chained was left in place; it is yours."
  exit 0
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/install-hooks.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM
NEW="$STAGE/pre-push.hook"
mkdir "$STAGE/copies"
# The paths are written with a `#` delimiter, between single quotes; a path
# holding `#`, `&` or a quote would break that, so it is refused.
case "$DEST" in *'#'* | *'&'* | *"'"*) die_usage "the path $DEST contains a character the hook cannot carry ('#', '&' or a single quote)." ;; esac
: > "$STAGE/copies/MANIFEST"
for f in "${PRE_PUSH_FILES[@]}"; do
  cp -p "$SELF_DIR/$f" "$STAGE/copies/$f"
  h="$(sha256_of "$STAGE/copies/$f")" && [ -n "$h" ] ||
    die_usage "neither sha256sum nor shasum could hash $f, and the hook refuses a file whose sha256 it cannot compare."
  printf '%s  %s\n' "$h" "$f" >> "$STAGE/copies/MANIFEST"
done
MANIFEST_SHA="$(sha256_of "$STAGE/copies/MANIFEST")"
sed -e "s#@@PRE_PUSH_DIR@@#$DEST#" -e "s#@@PRE_PUSH_MANIFEST_SHA256@@#$MANIFEST_SHA#" "$TEMPLATE" > "$NEW"

# copies_current: DEST holds exactly the staged copies, byte for byte.
copies_current() {
  local f
  for f in MANIFEST "${PRE_PUSH_FILES[@]}"; do
    cmp -s "$STAGE/copies/$f" "$DEST/$f" || return 1
  done
}

# set_optins: the opt-ins named by flag, and nothing else, each said with the
# exact line it ran. Called on every path an install exits 0 by.
set_optins() {
  local k
  for k in ${OPTINS[@]+"${OPTINS[@]}"}; do
    if [ -n "$DRY" ]; then
      say "would run: git config --local productizer.prePush.$k true"
    else
      git -C "$REPO" config --local "productizer.prePush.$k" true
      say "ran: git config --local productizer.prePush.$k true (in $(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/config; unset it with git config --local --unset productizer.prePush.$k)"
    fi
  done
  [ -n "$TRUSTED_REF" ] || return 0
  if [ -n "$DRY" ]; then
    say "would run: git config --local productizer.prePush.trustedRef $TRUSTED_REF"
  else
    git -C "$REPO" config --local productizer.prePush.trustedRef "$TRUSTED_REF"
    say "ran: git config --local productizer.prePush.trustedRef $TRUSTED_REF"
  fi
}

if [ -e "$HOOK" ]; then
  if cmp -s "$HOOK" "$NEW" && [ -x "$HOOK" ] && copies_current; then
    say "already installed at $HOOK; nothing to do."
    set_optins
    exit 0
  fi
  VERB="update"
else
  VERB="install"
fi

if [ -n "$DRY" ]; then
  say "would $VERB $HOOK, running copies in $DEST of: ${PRE_PUSH_FILES[*]}."
  set_optins
  exit 0
fi
rm -rf "$DEST"
mkdir -p "$DEST" "$HOOKS"
cp -p "$STAGE/copies/"* "$DEST/"
cp "$NEW" "$HOOK"
chmod +x "$HOOK"
if [ "$VERB" = update ]; then
  say "updated $HOOK, running copies in $DEST of: ${PRE_PUSH_FILES[*]}."
else
  say "installed $HOOK, running copies in $DEST of: ${PRE_PUSH_FILES[*]}. 'git push --no-verify' skips it; CI is still the gate."
fi
set_optins
exit 0
