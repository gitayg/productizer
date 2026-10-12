#!/usr/bin/env bash
# selftest.sh [--version] [--help] [--check PATH]
#
# The falsification suite for `check-import-marking.sh`, committed so it can be
# re-run rather than described. A check that has only ever been SEEN passing is
# not evidence; every case below was watched producing the wrong verdict under
# 1.0 before 1.1 was trusted, and this file is how anyone else watches it too.
#
# It builds throwaway git repositories in a temporary directory from the spec
# versions in `spec/`, runs the check against each, and compares the EXIT CODE
# and one load-bearing line of output against what that history should produce.
# Nothing is written into the repository this file lives in.
#
# THE THREE STATES R10 HAS TO KEEP APART, and the case that proves each:
#
#   1-never-imported.md        no marker, no `Stage 0c`, one change-log row per
#                              requirement. There is no import here, so there
#                              is nothing to assert - exit 2, UNMEASURED.
#                              UNDER 1.0 THIS EXITED 0.
#   2-import-marked-none.md    1 with the four rows collapsed into one row
#                              naming `Stage 0c`, and NOT ONE requirement
#                              marked. The complete violation - exit 1.
#                              UNDER 1.0 THIS EXITED 0, because every cohort
#                              anchored on a marker and there was none.
#   4-import-marked-some.md    2 with three of the four marked. The partial
#                              violation 1.0 already caught - exit 1, and it
#                              must print DIFFERENTLY from case 2.
#   3-import-marked-all.md     2 with all four settled: three marked inferred,
#                              one refused at import - exit 0. The positive
#                              control. Without it a check that failed
#                              everything would pass this suite.
#   6-import-promoted.md       2 with nothing marked and a decision-record row
#                              confirming all four. Promotion DELETES the
#                              marker, so a ratified import is bare by design
#                              and must not be a finding.
#   5-import-silent...md       2 with `Stage 0c` removed from the row. Nothing
#                              marked, no stage named, so nothing distinguishes
#                              it from a repository that never imported - exit
#                              2, UNMEASURED. THIS IS THE DECLARED HOLE, and it
#                              is a case so that the hole is measured rather
#                              than asserted.
#   5 + a commit message       5 again, committed with `Stage 0c` in the COMMIT
#                              MESSAGE. Marker-free detection with the spec
#                              itself silent - exit 1, four findings.
#   5 + the backlog            5 again, with `backlog/with-stage-0c.md` in
#                              the work tree and never committed. Under 1.1
#                              this was exit 2, COHORT UNRESOLVED: a backlog
#                              line was evidence by itself, so ANY appended
#                              row could turn this blocking check from 0 into
#                              2. Since 1.2 the backlog as it stands is not
#                              evidence (R73's rule) - exit 0.
#   5 + a later backlog append the same backlog, committed AFTER the spec in a
#                              commit that drafts nothing. Exit 0.
#   1 + an append naming R2    a never-imported spec, then a backlog row
#                              reading `Stage 0c drafted R2`. Under 1.1 that
#                              made R2 a finding, exit 1. Now exit 0, and the
#                              note says the line was seen and not counted.
#   5 + the backlog, one commit the spec and the backlog committed TOGETHER:
#                              the commit that drafted R1-R4 also wrote a
#                              backlog line naming the stage, which is step 5
#                              done in the pass it says. The cohort RESOLVES
#                              from that commit - exit 1, four findings.
#                              Under 1.1 this was exit 2.
#   7-import-stage-in-...md    5 with `Stage 0c` named in the spec's prose on
#                              a line holding no id. An import on the record
#                              and no cohort - exit 2, COHORT UNRESOLVED.
#   1 + backlog, no git        a root that is not a git work tree, with a
#                              backlog naming the stage. Whether an import
#                              commit wrote it cannot be read - exit 2,
#                              BACKLOG UNVERIFIED, never a quiet 0.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every case produced the verdict it should
#   1  a case produced the wrong verdict - the check is not measuring what it
#      says it measures, whatever it reports against the real spec
#   2  could not run - no git, no check to test, no temporary directory
set -euo pipefail

VERSION="import-marking-selftest 1.1"

HERE="$(cd "$(dirname "$0")" && pwd -P)"
CHECK="$HERE/../../scripts/check-import-marking.sh"

usage() {
  printf 'usage: selftest.sh [--version] [--help] [--check PATH]\n'
  printf '  --check PATH  the check to falsify. Defaults to\n'
  printf '                ../../scripts/check-import-marking.sh beside this fixture.\n'
}

die_unmeasured() { printf 'import-marking-selftest: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --check)
      [ "$#" -ge 2 ] || die_unmeasured "--check needs a path"
      CHECK="$2"; shift 2 ;;
    --check=*) CHECK="${1#--check=}"; shift ;;
    *) die_unmeasured "unknown argument: $1" ;;
  esac
done

[ -f "$CHECK" ] || die_unmeasured "no check to falsify at $CHECK"
command -v git >/dev/null || die_unmeasured "git is not installed"

WORK="$(mktemp -d)" || die_unmeasured "could not make a temporary directory"
# Nothing is written into the repository this fixture lives in, on any exit.
trap 'rm -rf "$WORK"' EXIT INT TERM

FAILURES=0
CASES=0

# Builds one throwaway repository and runs the check against it.
#   $1 case name · $2 spec fixture · $3 commit message · $4 backlog fixture
#   ("" for none) · $5 expected exit · $6 a line the output must contain
#   $7 where the backlog goes: `worktree` (default, never committed),
#   `with-spec` (in the commit that adds the spec), `later` (its own commit
#   after it), or `no-git` (the root is not a git work tree at all)
run_case() {
  name="$1"; fixture="$2"; message="$3"; backlog="$4"
  want_exit="$5"; want_line="$6"; how="${7:-worktree}"
  CASES=$((CASES + 1))

  repo="$WORK/$name"
  mkdir -p "$repo/.claude/productizer"
  cp "$HERE/spec/$fixture" "$repo/.claude/productizer/spec.md"
  [ -n "$backlog" ] && cp "$HERE/backlog/$backlog" "$repo/.claude/productizer/backlog.md"

  if [ "$how" != no-git ]; then
    git -c init.defaultBranch=main init -q "$repo"
    git -C "$repo" add .claude/productizer/spec.md
    [ "$how" = with-spec ] && git -C "$repo" add .claude/productizer/backlog.md
    git -C "$repo" \
      -c user.name=fixture -c user.email=fixture@example.invalid \
      commit -q -m "$message"
    if [ "$how" = later ]; then
      git -C "$repo" add .claude/productizer/backlog.md
      git -C "$repo" \
        -c user.name=fixture -c user.email=fixture@example.invalid \
        commit -q -m "append a backlog row"
    fi
  fi

  got_exit=0
  out="$(bash "$CHECK" --root "$repo" 2>&1)" || got_exit=$?

  ok=1
  [ "$got_exit" = "$want_exit" ] || ok=0
  # grep -q exits 1 when the line is absent, which is the answer, not an
  # error - `|| :` keeps `set -e` from killing the script before it can
  # report which case failed.
  grep -qF -- "$want_line" <<<"$out" || ok=0

  if [ "$ok" = 1 ]; then
    printf 'ok    %-28s exit %s\n' "$name" "$got_exit"
  else
    FAILURES=$((FAILURES + 1))
    printf 'FAIL  %-28s wanted exit %s and a line containing:\n' "$name" "$want_exit"
    printf '        %s\n' "$want_line"
    printf '      got exit %s and:\n' "$got_exit"
    printf '%s\n' "$out" | sed 's/^/        /'
  fi
}

# Exit 0, not 2. R10 is event-driven: where no import has happened the
# obligation never arose, which is a MEASUREMENT of the premise and not a
# refusal to look. Same shape as `jira-unbound`. This case briefly wanted 2, on
# the theory that nothing had been measured - but four sources were read and
# none records an import, and that is a fact that stops holding the moment one
# leaves a trace.
run_case never-imported 1-never-imported.md \
  "the founding spec, agreed one requirement at a time" "" \
  0 "NO IMPORT ON THE RECORD."

run_case import-marked-none 2-import-marked-none.md \
  "draft the spec from the existing repository" "" \
  1 "IMPORT MARKED NOTHING."

run_case import-marked-some 4-import-marked-some.md \
  "draft the spec from the existing repository" "" \
  1 "MARKERS MISSING."

run_case import-marked-all 3-import-marked-all.md \
  "draft the spec from the existing repository" "" \
  0 "attributed requirements with no inferred marking: 0"

run_case import-promoted 6-import-promoted.md \
  "draft the spec from the existing repository" "" \
  0 "source D - decision record rows promoting an imported requirement: 1"

# Also 0, and this is the honest limit of the check rather than a success: an
# import that marked nothing AND left no record anywhere is byte-identical from
# outside to a repository that was never imported. It is reported as no import,
# not as a finding. Closing it needs Stage 0c to write a machine record of its
# own id range - named in the check's header as the upstream fix.
run_case silent-import 5-import-silent-in-the-spec.md \
  "draft the spec from the existing repository" "" \
  0 "NO IMPORT ON THE RECORD."

run_case stage-in-the-commit 5-import-silent-in-the-spec.md \
  "Stage 0c: draft the spec from the existing repository" "" \
  1 "IMPORT MARKED NOTHING."

# The backlog as it stands is not evidence: an appended row, committed or
# not, cannot put an import on the record or name a requirement into a cohort.
run_case stage-in-the-backlog 5-import-silent-in-the-spec.md \
  "draft the spec from the existing repository" with-stage-0c.md \
  0 "NO IMPORT ON THE RECORD."

run_case backlog-appended-later 5-import-silent-in-the-spec.md \
  "draft the spec from the existing repository" with-stage-0c.md \
  0 "NO IMPORT ON THE RECORD." later

run_case backlog-append-names-id 1-never-imported.md \
  "the founding spec, agreed one requirement at a time" append-names-an-id.md \
  0 "1 line(s) of .claude/productizer/backlog.md name \`Stage 0c\` as it stands. A backlog line is not evidence of an import on its own" later

# The commit that drafted the requirements wrote the backlog line in the same
# pass: that commit is the evidence, and it names the cohort.
run_case stage-in-the-import-commit 5-import-silent-in-the-spec.md \
  "draft the spec from the existing repository" with-stage-0c.md \
  1 "drafted it and named \`Stage 0c\` in .claude/productizer/backlog.md" with-spec

run_case stage-in-the-spec-prose 7-import-stage-in-the-spec-prose.md \
  "draft the spec from the existing repository" "" \
  2 "IMPORT ON THE RECORD, COHORT UNRESOLVED."

run_case backlog-without-git 1-never-imported.md \
  "unused: this root is never committed" with-stage-0c.md \
  2 "BACKLOG UNVERIFIED." no-git

printf '%d case(s), %d failure(s)\n' "$CASES" "$FAILURES"
[ "$FAILURES" = 0 ] || exit 1
exit 0
