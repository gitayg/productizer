#!/usr/bin/env bash
# Scaffold for one b18-mech eval case. It puts the living spec and the
# constitution where a repository using the plugin keeps them, under
# .claude/productizer/ in the working directory, and does nothing else: no
# network, no other command, no read outside evals/mech-fixtures/.
# evals/check-mech-corpus.py holds the only permitted text of this file and
# fails on any byte of difference.
#
# Each refusal has its own exit code, so one smoke run says where the harness
# ran it: 3 the fixtures are not beside this script, 4 the working directory is
# this case directory, 5 the working directory already holds a spec.
set -euo pipefail
here="${BASH_SOURCE[0]%/*}"
[ "$here" != "${BASH_SOURCE[0]}" ] || here=.
fixtures="$here/../../mech-fixtures"
if [ ! -r "$fixtures/booking-spec.md" ] || [ ! -r "$fixtures/booking-constitution.md" ]; then
  echo "scaffold: fixtures not readable under $fixtures" >&2
  exit 3
fi
if [ "$(cd "$here" && pwd -P)" = "$(pwd -P)" ]; then
  echo "scaffold: the working directory is the case directory; refusing to write into the corpus" >&2
  exit 4
fi
if [ -e .claude/productizer ]; then
  echo "scaffold: .claude/productizer already exists here; refusing to overwrite a spec" >&2
  exit 5
fi
mkdir -p .claude
mkdir .claude/productizer
cp "$fixtures/booking-spec.md" .claude/productizer/spec.md
cp "$fixtures/booking-constitution.md" .claude/productizer/constitution.md
