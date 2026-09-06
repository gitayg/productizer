#!/usr/bin/env bash
# scripts/check-hygiene.sh — this repo's hygiene gate.
#
# A thin wrapper. All the logic lives in the shipped check at
# `plugins/productizer/skills/spec/scripts/check-hygiene.sh`, which carries
# GENERIC rules only: credential shapes, personal filesystem paths, machine
# hostnames, private key headers. Everything a user of this plugin needs, and
# nothing that identifies anyone.
#
# The private half - an employer and several private project names - lives in
# `.claude/productizer/hygiene-local.txt`, which is gitignored, with the
# canonical copy outside every repository under the home directory. It is
# loaded at runtime and never committed.
#
# WHY THE SPLIT. A single list has to spell the private names in order to catch
# them, and this repo is public, so the gate published exactly which names its
# author was hiding. A deny list is a map of what someone is protecting. A
# security review flagged it directly: the list enumerated an employer plus
# seven private projects to anyone who cloned the plugin. Splitting keeps the
# catching without the publishing, and lets every other project reuse the same
# private list.
#
# If the local list is absent this still runs, with generic rules only. That is
# correct for a fresh clone or for CI, which has no private list and does not
# need one - but it is announced, never silent, because a run that checked
# fewer rules than the reader thinks is worse than one that refused.
#
# Exit: 0 clean · 1 findings · 2 could not run
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)" || {
  echo "check-hygiene: not inside a git work tree" >&2; exit 2; }

SHIPPED="$ROOT/plugins/productizer/skills/spec/scripts/check-hygiene.sh"
LOCAL="$ROOT/.claude/productizer/hygiene-local.txt"

[ -r "$SHIPPED" ] || {
  echo "check-hygiene: cannot read the shipped check under plugins/ - the gate is missing, which is not the same as clean" >&2
  exit 2; }

# --version and --help answer from the shipped check so the declared
# `version_command` records the version that actually did the work.
case "${1:-}" in
  --version) exec bash "$SHIPPED" --version ;;
  -h|--help) exec bash "$SHIPPED" --help ;;
  # The scanner behind R39 reads SOURCE rather than probing, so a flag that
  # only worked via the catch-all `"$@"` forward below was invisible to it -
  # the wrapper is the tool the declared check names, not the shipped copy.
  --selftest|--self-test) exec bash "$SHIPPED" --selftest ;;
esac

if [ -e "$LOCAL" ]; then
  # Named and present but unreadable is exit 2 inside the shipped check: a
  # configured private list that silently fell back to generic-only would
  # report clean while checking none of the names anyone cared about.
  exec bash "$SHIPPED" --patterns "$LOCAL" "$@"
fi

echo "check-hygiene: no private list at .claude/productizer/hygiene-local.txt - generic rules only" >&2
exec bash "$SHIPPED" "$@"
