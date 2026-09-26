#!/usr/bin/env bash
# check-governance-weakening.sh [--root DIR] [--base REF] [--self-only]
#                              [--self-id ID] [--version] [--help] [--selftest]
#
# LOOSENING A DECLARED CHECK IS AN ORDINARY DIFF, AND NOTHING HERE READ IT.
#
# Measured on this repository at v4.60.0, five ways, each committed on its own
# clone and each run through the whole suite with the founding commit as base:
# deleting a check from `checks.yaml`, flipping its `severity: block` to
# `advise`, adding `enabled: false` to it, replacing its `always: true` trigger
# with a glob that matches nothing in the tree, and removing one tool's
# `--selftest` line from the workflow. All five exited 0 PASS. The gate over the
# publish hook is real - `check-installed-copies.sh` compares the installed copy
# against its template and `check-view-publish-refused.sh` drives the real hook -
# but nothing at all was reading the file that decides which gates exist.
#
# So this reports MOVEMENT, between a base and the working tree, of the
# declarations that decide WHAT IS CHECKED AND HOW HARD.
#
# WHAT THE GOVERNANCE SURFACE IS. Two files, and named FIELDS in them, not their
# text. A comment, a `why:`, a `limitations:` entry and a reflow are outside it
# on purpose: they are where the reasoning lives, they change constantly, and a
# rule that went red on them would be switched off inside a week.
#
#   .claude/productizer/checks.yaml
#     - a check's EXISTENCE. Present at the base, absent now.
#     - `enabled`. True or absent, then false.
#     - EFFECTIVE `severity` - the check's own key, else `defaults.severity`.
#       Resolving it is load-bearing: lowering `defaults.severity` weakens every
#       check that never mentions severity, and no check's own line moves.
#     - `when`. `always: true` outranks a `paths` or `tags` list, which outranks
#       nothing at all; and within one kind, a pattern LOST is a weakening.
#     - `exit_codes.pass` gaining a NON-ZERO code - the run stops hearing the
#       tool say something - and `exit_codes.fail` losing one.
#     - `coverage` removed entirely; `must_cover` lowered; `min_covered` or
#       `min_rules` lowered or removed.
#     - `policy.empty_run`, `policy.spec_coverage`, `policy.waivers`,
#       `policy.allow_repo_local_tools`, `defaults.severity`.
#
#   .github/workflows/checks.yml
#     - `on`: a trigger, branch or tag pattern lost.
#     - `permissions`: a scope raised or added. This is the one atom whose
#       weakening is not about checking less; a job token that can do more is a
#       step worth compromising, and it belongs to the same file and the same
#       review.
#     - a STEP lost, by name.
#     - `continue-on-error` gaining a true - a step that runs and decides
#       nothing - and an `if:` arriving on a step that had none.
#     - an INVOCATION lost: any line of any `run:` block naming a `.sh` or `.py`
#       file. FILE-WIDE, so moving one between steps is not read as a loss.
#     - an invocation gaining `|| true`, `|| :` or `|| exit 0`.
#
# WHAT IS DELIBERATELY NOT ON IT, each for a reason, because an unargued
# exclusion is the hole:
#   - `coverage.spec_units`. Dropping a requirement's only claim is already
#     refused, by `policy.spec_coverage: require`, which renders it `Missing`
#     and ends the run. A second reader of the same fact is a second place to
#     disagree, not double coverage.
#   - `timeout_seconds`. Lowering one makes a timeout likelier, which is a
#     REFUSAL and not a pass, and the numbers here move for unrelated reasons.
#   - `limitations`, `why`, `evidence`, `reason` and every comment. Prose.
#   - a check tool's own SOURCE. Weakening a check by editing its script is real
#     and this does not see it. Named under NOT ASSERTED, not quietly skipped.
#
# WHAT WEAKENING MEANS. A TRANSITION DOWN A LADDER, never a state. Three of this
# repository's checks carry `enabled: false` and two carry `severity: advise`,
# each with a written reason; a rule that read the STATE would go red on all
# five forever. What is reported is the MOVE: block to advise, absent to false,
# always to paths, a pattern or a step or an invocation that was there and is
# not. The reverse move - a check added, a severity raised, a trigger widened, a
# step added - is counted as a TIGHTENING and printed, and is never a finding.
#
# AND A MOVE THIS RULE CANNOT ORDER IS SAID SO. A `paths` list that lost one
# glob and gained another is what a REWRITE looks like, and whether the new
# glob fires on less is glob subsumption, which is not decided here. Those are
# UNDECIDED: they count as findings, with both sides printed, because a change
# this reader could not order is the one a person most needs to see. They are
# not counted as weakenings, and the two figures are never added up.
#
# WHY ADVISORY, ARGUED. A weakening is not automatically wrong. Every disabled
# check in this repository is disabled correctly, and `checks.yaml`'s own policy
# comment already says the thing that decides this: "a gate that cannot be
# satisfied is one somebody switches off". A blocking rule here would demand a
# ceremony for every honest disable, and the first person to hit it at 6pm would
# delete this check - which this check would then be the only thing to report,
# once, in the run that removed it.
#
# Advisory is not the same as quiet. `run-checks.sh` writes every check's output
# into `.claude/productizer/checks-result.json`, which is COMMITTED. An advisory
# finding here is not a line scrolling past a terminal; it is a sentence landing
# in a reviewed file, in the same diff as the weakening, saying what moved and
# what it was. That is the output this is for.
#
# The exception is its own footing, and `--self-only` exists to be declared as a
# SECOND check at `severity: block`. There is no ordinary change that deletes
# the weakening reporter, switches it off, lowers its severity, points its
# declaration at a different script, or stops CI running the suite. A weakening
# that only this check can see, reported only advisorily, is the same hole one
# level up.
#
# IT IS MEASURED AGAINST THIS REPOSITORY'S REAL HISTORY, not argued against it.
# All 36 commits that ever touched either governance file, each run with its own
# parent as the base and its own tree checked out:
#
#   32 of 36   exit 0. Nothing moved down a ladder.
#    2 of 36   exit 1, and BOTH are UNDECIDED with zero claimed weakenings.
#              3b7d2d4 renamed a step and edited its body while everything it
#              invoked kept running; 145d934 replaced one tool's argv with
#              `--repo .`. Both are changes a person should glance at and
#              neither is asserted to be a weakening.
#    2 of 36   exit 2. At 1534065 `checks.yaml` was not valid YAML - that commit
#              broke it and 98aa436 is the commit that fixed it, confirmed by
#              parsing both blobs - so the one before and the one after each have
#              an unparseable end. Refusing there is the contract: an unparsed
#              config is UNKNOWN, and the suite itself was down at that commit.
#
#   ZERO of the 36 are reported as a weakening. That number is not a boast about
#   the first draft: the first draft flagged two of them, one for a step RENAME
#   and one for a backslash CONTINUATION reflowed onto a single line. Both are
#   now corrected, both corrections are named in `governance-weakening.py` beside
#   the commit that forced them, and both have a self-test case whose whole job
#   is to stay 0.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  nothing on the governance surface moved down a ladder in this range
#   1  a weakening, or a move this rule cannot order. Each one is printed with
#      the atom, what it was, and what it is now
#   2  could not measure - bad usage, no git, a base that does not resolve, a
#      shallow clone, no python3 or no PyYAML, a governance file that is not
#      readable or not parseable YAML at either end, or `--self-only` asked to
#      assert a footing that is declared at neither end. A surface nobody
#      parsed has not been shown clean. Unmeasured, not clean.
#
# --SELFTEST DRIVES ALL THREE, over real git repositories built under
# `mktemp -d`. Every case is a two-state repository: the base is committed, the
# weakening is in the working tree, and the run uses the default base, which is
# the production path rather than a path only the self-test takes. Nothing is
# written into the repository this script lives in, on any exit path, signal
# included. `--self-test` is accepted as an alias because the repo spells it
# both ways.
#
# WHAT IT PRINTS. One BARE repo-relative path per governance file examined,
# which the runner parses as coverage. Findings, tightenings and notes are
# INDENTED.
#
# NOT ASSERTED, and none of it is inferable from a green run here:
#   - a check weakened by editing its SCRIPT rather than its declaration. The
#     declaration is what this reads.
#   - that a weakening cannot be hidden by doing it in the same change as an
#     addition. A deleted step whose invocations all still run, and an argv that
#     changed, both read UNDECIDED rather than WEAKENED, and those two branches
#     are exactly where a deliberate hider would aim.
#   - `.claude/settings.json` and the installed hooks. Real governance, another
#     check's ground: `check-installed-copies.sh` compares the hook against its
#     template and `check-view-publish-refused.sh` drives the real one.
#   - a weakening BEFORE the base. The default base is HEAD, so a weakening
#     committed and then built on is the agreed state to this reader, exactly as
#     `check-suspect-links.sh` says of its own one-base-ref blindness. CI should
#     pass the merge base of the pull request.
#   - the `.local` override file `run-checks.sh` reads beside `checks.yaml`.
#     Uncommitted and outside this comparison.
#   - whether a weakening was RIGHT. This reports the move, never the judgement.
set -euo pipefail

VERSION="check-governance-weakening 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEASURE="$HERE/governance-weakening.py"

CHECKS_REL=".claude/productizer/checks.yaml"
WORKFLOW_REL=".github/workflows/checks.yml"
# The id this check expects to be declared under, the script that declaration
# must name, and the runner the workflow must still invoke for a declared check
# to reach CI at all.
SELF_ID_DEFAULT="governance-weakening"
SELF_SCRIPT="check-governance-weakening.sh"
RUNNER="run-checks.sh"

ROOT=""; BASE="HEAD"; MODE="measure"; SELF_ONLY=""
SELF_ID="$SELF_ID_DEFAULT"
BASE_SOURCE="the default: the change in the work tree, against the last commit"

die_unmeasured() { printf 'check-governance-weakening: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)      [ "$#" -ge 2 ] || die_unmeasured "--root needs a path"; ROOT="$2"; shift 2 ;;
    --root=*)    ROOT="${1#--root=}"; shift ;;
    --base)      [ "$#" -ge 2 ] || die_unmeasured "--base needs a ref"
                 BASE="$2"; BASE_SOURCE="given with --base"; shift 2 ;;
    --base=*)    BASE="${1#--base=}"; BASE_SOURCE="given with --base"; shift ;;
    --self-id)   [ "$#" -ge 2 ] || die_unmeasured "--self-id needs an id"; SELF_ID="$2"; shift 2 ;;
    --self-id=*) SELF_ID="${1#--self-id=}"; shift ;;
    --self-only) SELF_ONLY="yes"; shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1." ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1."

# ---------------------------------------------------------------------------
# --selftest. Every case is a real two-commit-shaped git repository: the base is
# committed, the weakening sits in the working tree, and the default base is
# used, so the case drives the production path.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  command -v git >/dev/null 2>&1 \
    || die_unmeasured "git is not on PATH, so no case repository could be built and nothing was driven"
  command -v python3 >/dev/null 2>&1 \
    || die_unmeasured "python3 is not on PATH, so the measurement could not be driven"
  python3 -c 'import yaml' \
    || die_unmeasured "PyYAML is not importable by python3, so the measurement could not be driven"

  WORK="$(mktemp -d)" \
    || die_unmeasured "cannot create a temporary directory to build the cases in; nothing was driven"
  trap 'rm -rf "$WORK"' EXIT HUP INT TERM

  CASES=0; UPHELD=0; REPORT=""
  # R39.b: the reached half of the declaration at the end is ACCUMULATED here,
  # one entry per case as it ran. A literal list would satisfy the reader and
  # prove nothing.
  CODES=""

  write_checks() {
    # $1 case dir. A small but SHAPED config: a policy block, a defaults block,
    # one ordinary check with every atom this rule reads, and this check's own
    # declaration, so the self-footing atoms have something to stand on.
    mkdir -p "$1/.claude/productizer"
    cat > "$1/$CHECKS_REL" <<'YAML'
version: 1
policy:
  empty_run: refuse
  spec_coverage: require
  output: .claude/productizer/checks-result.json
defaults:
  timeout_seconds: 180
  severity: block
checks:
  - id: alpha
    why: a reason nobody reads
    when:
      always: true
    severity: block
    requires: [./tool.sh]
    command: [./tool.sh]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
    coverage:
      from: stdout_paths
      pattern: '^(\S+)$'
      must_cover: all_triggering
      min_covered: 2
  - id: beta
    why: another reason
    when:
      paths: ["**/*.sh", "**/*.bash"]
    command: [./beta.sh]
    exit_codes:
      pass: [0]
      fail: [1]
  - id: governance-weakening
    why: loosening a declared check is an ordinary diff
    when:
      always: true
    severity: advise
    command: [./plugins/productizer/skills/spec/scripts/check-governance-weakening.sh]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
YAML
  }

  write_workflow() {
    mkdir -p "$1/.github/workflows"
    cat > "$1/$WORKFLOW_REL" <<'YAML'
name: checks
on:
  pull_request:
  push:
    branches: [main]
    tags: ['v*']
permissions:
  contents: read
jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - name: Self-tests
        run: |
          bash scripts/check-alpha.sh --selftest
          bash scripts/check-beta.sh --selftest
      - name: Stage 5
        run: |
          bash scripts/check-delta.sh \
            --flag one
          bash plugins/productizer/skills/spec/scripts/run-checks.sh --base "$SHA"
YAML
  }

  build() {
    B="$WORK/$1"
    mkdir -p "$B"
    ( cd "$B" \
      && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init --quiet \
      && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git config user.email s@s \
      && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git config user.name s ) \
      >> "$WORK/build.log" \
      || die_unmeasured "could not initialise the case repository for $1; nothing was driven"
    write_checks "$B"
    write_workflow "$B"
    ( cd "$B" \
      && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git add -A \
      && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git commit --quiet -m base ) \
      >> "$WORK/build.log" \
      || die_unmeasured "could not commit the base state for $1, so there is no base to diff against"
  }

  # `|| GOT=$?` on the SAME LINE as the command. A `$(...)` in an argument list
  # and a pipeline both reset `$?`, and reading the status one line later is how
  # a self-test comes to report a pass it never observed.
  drive() {
    NAME="$1"; WANT="$2"; WHY="$3"; shift 3
    GOT=0
    bash "$0" "$@" > "$WORK/$NAME.out" 2> "$WORK/$NAME.err" || GOT=$?
    CASES=$((CASES + 1))
    if [ "$GOT" = "$WANT" ]; then UPHELD=$((UPHELD + 1)); V="held"; else V="NOT HELD"; fi
    CODES="$CODES$GOT
"
    REPORT="$REPORT      $NAME  expected $WANT  got $GOT  $V  $WHY
"
  }

  # A case asserts a SENTENCE as well as a code. Eleven cases below share exit 1
  # and the code alone cannot tell any of them apart, so each reads back the
  # atom it moved.
  says() {
    NAME="$1"; NEEDLE="$2"; WHY="$3"
    CASES=$((CASES + 1))
    if grep -qF -- "$NEEDLE" "$WORK/$NAME.out" "$WORK/$NAME.err"; then
      UPHELD=$((UPHELD + 1)); V="held"
    else
      V="NOT HELD"
    fi
    REPORT="$REPORT      $NAME/says  $V  $WHY
"
  }

  # -- 0: the clean case. Without it, every red case below proves only that
  # something is red, not that this check is what makes it red.
  build clean
  drive clean 0 "a working tree identical to its base: no atom moved" \
    --root "$WORK/clean" --self-id "$SELF_ID_DEFAULT"
  says clean "Nothing on the governance surface moved down a ladder" \
    "the clean case says so in words, not only in its code"

  # -- 0: THE CASE THAT DECIDES WHETHER THIS IS USABLE. A check added, a
  # severity raised, a trigger widened, a workflow step added, a comment
  # rewritten - all in one change. Ordinary work. If this is not 0 the rule is
  # unusable, whatever the weakening cases do.
  build tightened
  python3 - "$WORK/tightened/$CHECKS_REL" "$WORK/tightened/$WORKFLOW_REL" <<'PY'
import sys
c, w = sys.argv[1], sys.argv[2]
t = open(c).read()
t = t.replace("  - id: beta\n    why: another reason\n    when:\n      paths: [\"**/*.sh\", \"**/*.bash\"]\n",
              "  - id: beta\n    why: a better reason\n    severity: block\n    when:\n      always: true\n")
t = t.replace("# nothing", "")
t += """  - id: gamma
    why: a brand new check
    when:
      always: true
    severity: block
    command: [./gamma.sh]
    exit_codes:
      pass: [0]
      fail: [1]
"""
open(c, "w").write(t)
t = open(w).read()
t = t.replace("      - name: Stage 5\n",
              "      - name: Extra guard\n        run: |\n          bash scripts/check-gamma.sh --selftest\n      - name: Stage 5\n")
open(w, "w").write(t)
PY
  drive tightened 0 "a check added, a trigger widened, a workflow step added, a severity written out explicitly where the default already said the same thing, and a comment rewritten: ordinary work, and not one finding" \
    --root "$WORK/tightened" --self-id "$SELF_ID_DEFAULT"
  says tightened "tightenings seen: 4" \
    "FOUR upward moves are counted and printed rather than merely not reported, and the fifth edit is counted as NEITHER: writing out severity: block under a defaults.severity that already said block moves the EFFECTIVE value nowhere, and a reader of the raw key would have called that a tightening it is not"

  # -- 0: TWO CORRECTIONS THIS REPOSITORY'S OWN HISTORY FORCED. Both were false
  # positives of the first version of this rule, found by sweeping the 36
  # commits that touched either governance file, not by imagining cases.
  build renamed-step
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("      - name: Self-tests\n","      - name: Self-tests, renamed in passing\n"))' \
    "$WORK/renamed-step/$WORKFLOW_REL"
  drive renamed-step 0 "a workflow step renamed with an identical body: at 3b7d2d4 this repository renamed a step's baseline date and the first version of this rule called it a deleted step" \
    --root "$WORK/renamed-step" --self-id "$SELF_ID_DEFAULT"
  says renamed-step "was renamed to" \
    "the rename is reported as a rename, so a reader can disagree with the pairing rather than with a verdict"

  build wrapped
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("          bash scripts/check-delta.sh \\\n            --flag one\n","          bash scripts/check-delta.sh --flag one\n"))' \
    "$WORK/wrapped/$WORKFLOW_REL"
  drive wrapped 0 "a backslash continuation reflowed onto one line: at 145d934 this repository did exactly that and the first version of this rule called the trailing backslash a lost invocation" \
    --root "$WORK/wrapped" --self-id "$SELF_ID_DEFAULT"
  says wrapped "atoms compared" "the run still compared the surface rather than skipping the workflow"

  # -- 1: UNDECIDED. The same tool, a different argv. Also from 145d934, where
  # `validate-spec.py <two paths>` became `validate-spec.py --repo .`.
  build argv-changed
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("          bash scripts/check-delta.sh \\\n            --flag one\n","          bash scripts/check-delta.sh --flag two --and-more\n"))' \
    "$WORK/argv-changed/$WORKFLOW_REL"
  drive argv-changed 1 "an invocation's arguments changed while the tool still runs: UNDECIDED, because whether the new argv asks for less is not decidable here" \
    --root "$WORK/argv-changed" --self-id "$SELF_ID_DEFAULT"
  says argv-changed "UNDECIDED: workflow.invocation" \
    "the tool still running is the difference between this and a tool nobody asks any more"

  # -- 1: a step REALLY deleted, which is the case the rename correction must
  # not have swallowed. Its invocations go with it, and that is the difference.
  build step-deleted
  python3 - "$WORK/step-deleted/$WORKFLOW_REL" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split("\n")
start = lines.index("      - name: Self-tests")
end = lines.index("      - name: Stage 5")
open(p, "w").write("\n".join(lines[:start] + lines[end:]))
PY
  drive step-deleted 1 "a whole step deleted, taking both its invocations with it: the correction for renames must not have swallowed this" \
    --root "$WORK/step-deleted" --self-id "$SELF_ID_DEFAULT"
  says step-deleted "WEAKENED: workflow.step[checks/Self-tests]" "a real deletion is still a weakening, not a rename"

  # -- 1: UNDECIDED, the third branch. The step is gone by name, a step was
  # added, and every tool it invoked still runs somewhere. Something was
  # reorganised and nothing measurably stopped; this rule will not call that
  # either way.
  build step-reorganised
  python3 - "$WORK/step-reorganised/$WORKFLOW_REL" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split("\n")
start = lines.index("      - name: Self-tests")
end = lines.index("      - name: Stage 5")
new = [
    "      - name: Self-tests, regrouped",
    "        run: |",
    "          echo regrouped",
    "          bash scripts/check-alpha.sh --selftest",
    "          bash scripts/check-beta.sh --selftest",
]
open(p, "w").write("\n".join(lines[:start] + new + lines[end:]))
PY
  drive step-reorganised 1 "a step gone by name, a step added, and every invocation it made still running: UNDECIDED rather than a claimed weakening" \
    --root "$WORK/step-reorganised" --self-id "$SELF_ID_DEFAULT"
  says step-reorganised "UNDECIDED: workflow.step[checks/Self-tests]" \
    "it is reported UNDECIDED, so the reorganisation is surfaced without being called a weakening"

  # -- 1: the five weakenings this repository was measured passing today.
  build deleted
  python3 - "$WORK/deleted/$CHECKS_REL" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split("\n")
start = lines.index("  - id: beta")
end = lines.index("  - id: governance-weakening")
open(p, "w").write("\n".join(lines[:start] + lines[end:]))
PY
  drive deleted 1 "a whole check deleted from the declared set" \
    --root "$WORK/deleted" --self-id "$SELF_ID_DEFAULT"
  says deleted "WEAKENED: checks[beta]" "it names the check that vanished"

  build lowered
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("    severity: block\n    requires:","    severity: advise\n    requires:"))' \
    "$WORK/lowered/$CHECKS_REL"
  drive lowered 1 "severity: block flipped to advise on a check that had its own key" \
    --root "$WORK/lowered" --self-id "$SELF_ID_DEFAULT"
  says lowered "checks[alpha].severity (effective)" "it names the effective severity, not the raw key"

  build switched-off
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("  - id: alpha\n","  - id: alpha\n    enabled: false\n"))' \
    "$WORK/switched-off/$CHECKS_REL"
  drive switched-off 1 "enabled: false added to a check that had no such key" \
    --root "$WORK/switched-off" --self-id "$SELF_ID_DEFAULT"
  says switched-off "checks[alpha].enabled" "it names the key that switched the check off"

  build narrowed
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("    when:\n      always: true\n    severity: block\n    requires:","    when:\n      paths: [\"never-a-real-dir/**\"]\n    severity: block\n    requires:"))' \
    "$WORK/narrowed/$CHECKS_REL"
  drive narrowed 1 "an always-true trigger replaced by a glob, so the check stops firing" \
    --root "$WORK/narrowed" --self-id "$SELF_ID_DEFAULT"
  says narrowed "checks[alpha].when" "it names the trigger that stopped firing on everything"

  build dropped-line
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("          bash scripts/check-beta.sh --selftest\n",""))' \
    "$WORK/dropped-line/$WORKFLOW_REL"
  drive dropped-line 1 "one tool's --selftest line removed from the workflow" \
    --root "$WORK/dropped-line" --self-id "$SELF_ID_DEFAULT"
  says dropped-line "workflow.invocation" "it names the invocation the workflow stopped making"

  # -- 1: the atoms the five do not reach, one case each.
  # TWO CASES, NOT ONE, AND THE SPLIT WAS FORCED. A single case that widened
  # `pass` and emptied `fail` at the same time reached exit 1 through either
  # rule, so breaking the pass-widening line in production left the self-test
  # GREEN. One atom per case.
  build pass-widened
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("      pass: [0]\n      fail: [1]\n      refused: [2]\n    coverage:","      pass: [0, 1]\n      fail: [1]\n      refused: [2]\n    coverage:"))' \
    "$WORK/pass-widened/$CHECKS_REL"
  drive pass-widened 1 "a non-zero exit code moved into exit_codes.pass and nothing else changed, so the run stops hearing the tool" \
    --root "$WORK/pass-widened" --self-id "$SELF_ID_DEFAULT"
  says pass-widened "exit_codes.pass" "it names the code map that started calling a failure a pass"

  build fail-dropped
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("      pass: [0]\n      fail: [1]\n      refused: [2]\n    coverage:","      pass: [0]\n      fail: []\n      refused: [2]\n    coverage:"))' \
    "$WORK/fail-dropped/$CHECKS_REL"
  drive fail-dropped 1 "a code dropped out of exit_codes.fail and nothing else changed, so an exit that used to be a finding now classifies as nothing" \
    --root "$WORK/fail-dropped" --self-id "$SELF_ID_DEFAULT"
  says fail-dropped "exit_codes.fail" "it names the fail list that lost a code"

  build floor-lowered
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("      must_cover: all_triggering\n      min_covered: 2","      must_cover: none\n      min_covered: 1"))' \
    "$WORK/floor-lowered/$CHECKS_REL"
  drive floor-lowered 1 "must_cover lowered and the min_covered floor lowered with it" \
    --root "$WORK/floor-lowered" --self-id "$SELF_ID_DEFAULT"
  says floor-lowered "coverage.must_cover" "it names the coverage obligation that was lowered"

  build defaults-lowered
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("defaults:\n  timeout_seconds: 180\n  severity: block","defaults:\n  timeout_seconds: 180\n  severity: advise"))' \
    "$WORK/defaults-lowered/$CHECKS_REL"
  drive defaults-lowered 1 "defaults.severity lowered: no check's own line moved, and beta now blocks nothing" \
    --root "$WORK/defaults-lowered" --self-id "$SELF_ID_DEFAULT"
  says defaults-lowered "checks[beta].severity (effective)" \
    "the EFFECTIVE severity is what moved; beta declares no severity of its own, so a reader of the raw key would see nothing"

  build swallowed
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("          bash scripts/check-beta.sh --selftest\n","          bash scripts/check-beta.sh --selftest || true\n"))' \
    "$WORK/swallowed/$WORKFLOW_REL"
  drive swallowed 1 "an invocation gained || true, so the tool runs and the job stays green" \
    --root "$WORK/swallowed" --self-id "$SELF_ID_DEFAULT"
  says swallowed "swallowed" "it says the failure is discarded on the line that makes it"

  build tolerant-step
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("      - name: Self-tests\n","      - name: Self-tests\n        continue-on-error: true\n"))' \
    "$WORK/tolerant-step/$WORKFLOW_REL"
  drive tolerant-step 1 "continue-on-error: true added to a step, so it runs and decides nothing" \
    --root "$WORK/tolerant-step" --self-id "$SELF_ID_DEFAULT"
  says tolerant-step "continue-on-error" "it names the key that stopped the step deciding anything"

  build fewer-triggers
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("    tags: [\x27v*\x27]\n",""))' \
    "$WORK/fewer-triggers/$WORKFLOW_REL"
  drive fewer-triggers 1 "the tag trigger removed, so the commit a consumer installs is never checked as a tag" \
    --root "$WORK/fewer-triggers" --self-id "$SELF_ID_DEFAULT"
  says fewer-triggers "workflow.on" "it names the trigger set that shrank"

  build wider-token
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("  contents: read","  contents: write"))' \
    "$WORK/wider-token/$WORKFLOW_REL"
  drive wider-token 1 "the job token raised from read to write" \
    --root "$WORK/wider-token" --self-id "$SELF_ID_DEFAULT"
  says wider-token "permissions.contents" "it names the scope that was raised"

  # -- 1: UNDECIDED. A glob rewritten is a member lost and a member gained in
  # one change, and glob subsumption is not decided here.
  build rewritten-glob
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("      paths: [\"**/*.sh\", \"**/*.bash\"]","      paths: [\"**/*.sh\", \"**/*.zsh\"]"))' \
    "$WORK/rewritten-glob/$CHECKS_REL"
  drive rewritten-glob 1 "a glob rewritten: one pattern lost, one gained, and which way it moved is not decided here" \
    --root "$WORK/rewritten-glob" --self-id "$SELF_ID_DEFAULT"
  says rewritten-glob "UNDECIDED: checks[beta].when patterns" \
    "it is reported UNDECIDED and not as a claimed weakening"

  # -- 1: SELF. The reporter's own footing, four ways.
  build self-deleted
  python3 - "$WORK/self-deleted/$CHECKS_REL" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split("\n")
start = lines.index("  - id: governance-weakening")
open(p, "w").write("\n".join(lines[:start]) + "\n")
PY
  drive self-deleted 1 "this check's own declaration deleted, which only this check can report" \
    --root "$WORK/self-deleted" --self-id "$SELF_ID_DEFAULT"
  says self-deleted "SELF WEAKENED: self.declaration" "the finding is labelled SELF"

  build self-repointed
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("    command: [./plugins/productizer/skills/spec/scripts/check-governance-weakening.sh]","    command: [/usr/bin/true]"))' \
    "$WORK/self-repointed/$CHECKS_REL"
  drive self-repointed 1 "the declaration kept its id and stopped naming this script" \
    --root "$WORK/self-repointed" --self-id "$SELF_ID_DEFAULT"
  says self-repointed "SELF WEAKENED: self.command" "the id declared and the measurement not"

  build self-no-ci
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("          bash plugins/productizer/skills/spec/scripts/run-checks.sh --base \"$SHA\"\n","          echo nothing\n"))' \
    "$WORK/self-no-ci/$WORKFLOW_REL"
  drive self-no-ci 1 "the workflow stopped running the suite, so no declared check reaches CI" \
    --root "$WORK/self-no-ci" --self-id "$SELF_ID_DEFAULT"
  says self-no-ci "SELF WEAKENED: self.ci" "it says the suite no longer runs off a maintainer's machine"

  # -- 0 and 1 under --self-only, which is the mode meant to be declared as a
  # second, BLOCKING check. The pair is the point: the same tree is 0 under
  # --self-only while the general sweep would be 1, and vice versa.
  build self-only-clean
  python3 -c 'import sys;p=sys.argv[1];t=open(p).read();open(p,"w").write(t.replace("  - id: alpha\n","  - id: alpha\n    enabled: false\n"))' \
    "$WORK/self-only-clean/$CHECKS_REL"
  drive self-only-clean 0 "a check switched off, under --self-only: a real weakening of the surface, and NOT of this check's footing" \
    --root "$WORK/self-only-clean" --self-only --self-id "$SELF_ID_DEFAULT"
  says self-only-clean "mode: self-footing only" "the mode is printed, so a run cannot be mistaken for the general sweep"

  build self-only-gone
  python3 - "$WORK/self-only-gone/$CHECKS_REL" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split("\n")
start = lines.index("  - id: governance-weakening")
open(p, "w").write("\n".join(lines[:start]) + "\n")
PY
  drive self-only-gone 1 "the declaration deleted, under --self-only: the blocking half fires" \
    --root "$WORK/self-only-gone" --self-only --self-id "$SELF_ID_DEFAULT"
  says self-only-gone "SELF WEAKENED: self.declaration" "the blocking half names the same atom"

  # -- 2: could not measure. Six routes, because a refusal that only ever
  # arrives through the argument parser is not the refusal that matters.
  build undeclared
  drive undeclared 2 "--self-only asked to assert a footing declared at neither end: nothing to assert" \
    --root "$WORK/undeclared" --self-only --self-id "not-declared-anywhere"
  says undeclared "declared at neither end" "the refusal says which premise was absent"

  build unparseable
  printf 'checks:\n  - id: [unclosed\n' > "$WORK/unparseable/$CHECKS_REL"
  drive unparseable 2 "the declared checks are not valid YAML in the working tree, so every atom in them is UNKNOWN" \
    --root "$WORK/unparseable" --self-id "$SELF_ID_DEFAULT"
  says unparseable "Unmeasured, not clean" "the refusal says unmeasured rather than reporting no findings"

  build no-governance
  rm -f "$WORK/no-governance/$CHECKS_REL" "$WORK/no-governance/$WORKFLOW_REL"
  drive no-governance 1 "both governance files deleted in the working tree: the loudest weakening there is, not a refusal" \
    --root "$WORK/no-governance" --self-id "$SELF_ID_DEFAULT"
  says no-governance "the file that declares every check is gone" "deletion is a finding, never an unmeasured"

  build bad-base
  drive bad-base 2 "a base ref that does not resolve to a commit" \
    --root "$WORK/bad-base" --base no-such-ref-anywhere --self-id "$SELF_ID_DEFAULT"
  says bad-base "does not resolve" "the refusal names the base, because a wrong base makes every verdict below confidently wrong at once"

  mkdir -p "$WORK/not-a-repo"
  drive not-a-repo 2 "a directory that is not a git work tree, so there is no base to read a governance file from" \
    --root "$WORK/not-a-repo" --self-id "$SELF_ID_DEFAULT"
  # The SENTENCE is asserted here and the code is not enough: with the work-tree
  # guard broken, this case still reached 2 through the unresolvable-base guard
  # one line later, and the break came back green on the code alone.
  says not-a-repo "is not inside a git work tree" \
    "the refusal names the missing work tree rather than arriving at the same code by another route"

  # 2 - a repository with NO governance file at either end. The surface is not
  # weak here; there is no surface, and a clean verdict would rest on nothing.
  build no-surface
  ( cd "$WORK/no-surface" \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git rm -r --quiet .claude .github \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git commit --quiet -m "no governance surface" ) \
    >> "$WORK/build.log" \
    || die_unmeasured "could not build the no-surface case"
  drive no-surface 2 "neither governance file exists at the base or in the working tree, so no atom could be compared and a clean verdict would rest on nothing" \
    --root "$WORK/no-surface" --base HEAD --self-id "$SELF_ID_DEFAULT"
  says no-surface "no atom was compared at all" \
    "the refusal says no atom was compared rather than reporting no findings"

  drive bad-usage 2 "an option this script does not take" --frobnicate

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"
  if [ "$CASES" = "$UPHELD" ]; then SELF_VERDICT="held"; else SELF_VERDICT="NOT HELD"; fi
  printf '    R39.s  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$CASES" "$UPHELD" "$SELF_VERDICT" \
    "each case exits with the code it declares and says the sentence it declares"
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  printf '    NOT ASSERTED: the cases assert an exit code and ONE substring of the output. A case that reached the right code and named the right atom while getting a second atom wrong is invisible here and is read off its captured output by hand. Nor does any case assert the WORDING of the argument for advisory severity - that is prose in this header, and prose is not measured.\n'
  [ "$CASES" = "$UPHELD" ] || exit 1
  if [ -n "$MISSING" ]; then
    printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# the measurement
# ---------------------------------------------------------------------------
[ -r "$MEASURE" ] \
  || die_unmeasured "cannot read $MEASURE, which holds the comparison. The reader is missing, which is not the same as nothing having weakened"
command -v git >/dev/null 2>&1 \
  || die_unmeasured "git is not on PATH, so the base state of the governance files cannot be read"
command -v python3 >/dev/null 2>&1 \
  || die_unmeasured "python3 is not on PATH, so the comparison cannot be run"
python3 -c 'import yaml' \
  || die_unmeasured "PyYAML is not importable by python3, so neither governance file could be parsed. Unparsed is UNKNOWN, not unchanged"

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" \
    || die_unmeasured "no git work tree here, and --root was not given; there is no base to compare against"
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"
TOP="$(git -C "$ROOT" rev-parse --show-toplevel)" \
  || die_unmeasured "$ROOT is not inside a git work tree, so the governance files have no earlier state to compare against"

BASE_SHA="$(git -C "$TOP" rev-parse --verify --quiet "$BASE^{commit}")" || BASE_SHA=""
if [ -z "$BASE_SHA" ]; then
  if [ -f "$(git -C "$TOP" rev-parse --git-dir)/shallow" ]; then
    die_unmeasured "the base ref $BASE does not resolve in this clone, and the clone is SHALLOW. The commit the change is measured against was never fetched, so whether the governance surface weakened is UNKNOWN. Fetch full history (fetch-depth: 0) and re-run. This is not a clean result"
  fi
  die_unmeasured "the base ref $BASE does not resolve to a commit ($BASE_SOURCE). A wrong base makes every verdict below confidently wrong at once, so nothing below was computed"
fi
BASE_SHORT="$(git -C "$TOP" rev-parse --short "$BASE_SHA")"

WORK="$(mktemp -d)" || die_unmeasured "cannot create a temporary directory to read the base state into"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# `@absent` is a STATE, not an error: a governance file introduced inside this
# range has no earlier version for anything in it to have weakened from, and a
# file deleted in this range is the loudest finding there is. Both are told
# apart from a file that could not be read, which is a refusal.
read_base() {
  rel="$1"; dest="$2"
  if [ -z "$(git -C "$TOP" ls-tree "$BASE_SHA" -- "$rel")" ]; then
    printf '@absent\n'
    return 0
  fi
  git -C "$TOP" show "$BASE_SHA:$rel" > "$dest" \
    || die_unmeasured "cannot read $rel at $BASE_SHORT, which git lists as holding it"
  printf '%s\n' "$dest"
}

tree_path() {
  rel="$1"
  if [ -f "$TOP/$rel" ]; then printf '%s\n' "$TOP/$rel"; else printf '@absent\n'; fi
}

BASE_CHECKS="$(read_base "$CHECKS_REL" "$WORK/base-checks.yaml")"
BASE_WORKFLOW="$(read_base "$WORKFLOW_REL" "$WORK/base-workflow.yml")"
TREE_CHECKS="$(tree_path "$CHECKS_REL")"
TREE_WORKFLOW="$(tree_path "$WORKFLOW_REL")"

# A repository with NO governance surface at either end is a refusal, and the
# comparison OWNS that decision rather than this wrapper second-guessing it.
# Two guards for one fact is two places to disagree, and a wrapper guard that
# fired first made the comparison's own guard unreachable by any case - which is
# how an untested line gets shipped.

set -- --base-checks "$BASE_CHECKS" --tree-checks "$TREE_CHECKS" \
       --base-workflow "$BASE_WORKFLOW" --tree-workflow "$TREE_WORKFLOW" \
       --checks-rel "$CHECKS_REL" --workflow-rel "$WORKFLOW_REL" \
       --self-id "$SELF_ID" --self-script "$SELF_SCRIPT" --runner "$RUNNER" \
       --base-label "$BASE -> $BASE_SHORT ($BASE_SOURCE)"
[ -z "$SELF_ONLY" ] || set -- "$@" --self-only

STATUS=0
python3 "$MEASURE" "$@" || STATUS=$?
exit "$STATUS"
