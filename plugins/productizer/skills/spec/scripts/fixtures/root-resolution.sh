#!/usr/bin/env bash
# Pins how run-checks.sh finds its config, its root, and its change list.
#
# THREE resolutions here were once relative to the working directory, and each
# hid the next:
#
#   1. the DEFAULT --config path, so from any subdirectory the runner said
#      "no config" and stopped - in front of every resolution below it;
#   2. ROOT, taken from `dirname <config>`, which for the default config is
#      `.claude/productizer` - so `./scripts/check-hygiene.sh` in `requires`
#      reported `missing_tool` for a tool that was present and executable, and
#      `policy.output` wrote `.claude/productizer/.claude/productizer/...`;
#   3. --changed, so a path that existed at the repository root was reported
#      as not existing.
#
# TWO THINGS THIS FIXTURE DOES ON PURPOSE, both learned from tests that passed
# while the bugs were live:
#
#   * It runs the BARE invocation - no --config, no absolute paths. A test that
#     supplies an absolute --config skips resolution 1 entirely and then agrees
#     with itself from every directory.
#   * It asserts the VALUE of the root, not merely that runs agree. The wrong
#     root was the SAME wrong root from every working directory, so a pure
#     cross-directory identity check passes on the broken code.
#
#   scripts/fixtures/root-resolution.sh [repo-root]
#
# Exit 0 = every assertion holds. Exit 1 = at least one does not.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="${1:-$(git -C "$HERE" rev-parse --show-toplevel)}"
REPO="$(cd "$REPO" && pwd)"
RUNNER="$REPO/plugins/productizer/skills/spec/scripts/run-checks.sh"
[ -x "$RUNNER" ] || [ -f "$RUNNER" ] || { printf 'fixture: no runner at %s\n' "$RUNNER" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/root-res.XXXXXX")"

# The change list must be named by a REPOSITORY-relative path, or resolution 3
# is never exercised. It therefore has to live in the repository; it is removed
# again, and the committed result file is put back byte for byte.
LIST_REL=".claude/productizer/.fixture-changed.txt"
LIST_ABS="$REPO/$LIST_REL"
RESULT="$REPO/.claude/productizer/checks-result.json"
SAVED="$WORK/checks-result.saved"
[ ! -f "$RESULT" ] || cp "$RESULT" "$SAVED"

restore() {
  rm -f "$LIST_ABS"
  if [ -f "$SAVED" ]; then
    cp "$SAVED" "$RESULT"
  else
    rm -f "$RESULT"
  fi
  rm -rf "$WORK"
}
trap restore EXIT

printf '%s\n' "plugins/productizer/skills/spec/scripts/run-checks.sh" > "$LIST_ABS"

fail=0
note() { printf 'fixture: %-4s %s\n' "$1" "$2"; [ "$1" = OK ] || fail=1; }

# Always bare: no --config, and a repository-relative --changed.
bare() { ( cd "$1" && bash "$RUNNER" --changed "$LIST_REL" "${@:2}" ); }

# --- 1. the bare invocation works at all, from the repository root ---------
rc=0
bare "$REPO" --out - >/dev/null 2>"$WORK/base.txt" || rc=$?
if [ "$rc" -eq 0 ]; then
  note OK "bare invocation succeeded from the repository root"
else
  note FAIL "bare invocation exited $rc from the repository root:"
  sed 's/^/          /' "$WORK/base.txt"
fi

# --- 2. no declared tool reads as absent ----------------------------------
if grep -q 'MISSING_TOOL' "$WORK/base.txt"; then
  note FAIL "a declared tool read as absent:"
  grep -A1 'MISSING_TOOL' "$WORK/base.txt" | sed 's/^/          /'
else
  note OK "no declared tool read as absent"
fi

# --- 3. config and root are the repository's, not a directory below it -----
got_config="$(sed -n 's/^config: \(.*\) (.*)$/\1/p' "$WORK/base.txt")"
got_root="$(sed -n 's/^root: \(.*\) (.*)$/\1/p' "$WORK/base.txt")"
if [ "$got_config" = "$REPO/.claude/productizer/checks.yaml" ]; then
  note OK "config is the repository's: $got_config"
else
  note FAIL "config is ${got_config:-<not reported>}, expected $REPO/.claude/productizer/checks.yaml"
fi
if [ "$got_root" = "$REPO" ]; then
  note OK "root is the repository: $got_root"
else
  note FAIL "root is ${got_root:-<not reported>}, expected $REPO"
fi

# --- 4. policy.output lands where the config asked, not in a nested shadow --
rc=0
bare "$REPO" >/dev/null 2>"$WORK/wrote.txt" || rc=$?
wrote="$(sed -n 's/^result: //p' "$WORK/wrote.txt")"
case "$wrote" in
  "$REPO"/.claude/productizer/.claude/*) note FAIL "result written into a nested shadow: $wrote" ;;
  "$RESULT")                             note OK   "result written where the config asked: $wrote" ;;
  *)                                     note FAIL "result written to an unexpected path: ${wrote:-<none>}" ;;
esac
if nested="$(find "$REPO/.claude" -mindepth 1 -type d -name '.claude' -print)" && grep -q . <<<"$nested"; then
  note FAIL "a nested .claude tree was created under $REPO/.claude"
else
  note OK "no nested .claude tree was created"
fi

# --- 5. the same bare invocation from four working directories -------------
# Including one OUTSIDE the repository, which is the only case that exercises
# falling back to the script's own work tree to find the default config.
DIRS=("$REPO" "$REPO/plugins/productizer/skills/spec" \
      "$REPO/plugins/productizer/skills/spec/scripts/fixtures" "$WORK")
agreed=1
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || { note FAIL "no such directory $d"; continue; }
  out="$WORK/cwd.$(printf '%s' "$d" | tr -c 'A-Za-z0-9' '_')"
  rc=0
  bare "$d" --out - >/dev/null 2>"$out" || rc=$?
  printf 'EXIT=%s\n' "$rc" >> "$out"
  # The provenance in parentheses on the `config:` line is EXPECTED to differ:
  # from inside the repository the default is found under the work tree holding
  # the working directory, and from outside it under the work tree holding this
  # script. Same file by a different route, and naming the route is the whole
  # point of that line. So the RESOLVED PATH and everything else must match
  # exactly, while that one parenthesis is allowed to vary. Nothing else is
  # normalised - the config path itself stays in the comparison, which is what
  # catches a default that resolved somewhere else entirely.
  sed 's/^\(config: .*\) (.*)$/\1/' "$out" > "$out.norm"
  if [ "$d" = "${DIRS[0]}" ]; then
    cp "$out.norm" "$WORK/first.txt"
  elif ! diff -u "$WORK/first.txt" "$out.norm" > "$WORK/diff.txt"; then
    agreed=0
    note FAIL "output differs when run from $d"
    sed 's/^/          /' "$WORK/diff.txt"
  fi
done
[ "$agreed" -eq 0 ] || note OK "identical from ${#DIRS[@]} working directories, one outside the repository"

if [ "$fail" -ne 0 ]; then
  printf 'fixture: FAILED\n' >&2
  exit 1
fi
printf 'fixture: PASSED\n'
