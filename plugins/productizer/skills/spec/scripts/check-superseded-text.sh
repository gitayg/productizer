#!/usr/bin/env bash
# check-superseded-text.sh [--version] [--help] [--root DIR] [--selftest]
#
# Asserts R3: THE LIFECYCLE SHALL KEEP A REPLACED REQUIREMENT'S ORIGINAL TEXT
# IN THE SPEC, MARKED SUPERSEDED.
#
# R3 is two obligations wearing one sentence, and only one of them is cheap.
#
#   MARKED SUPERSEDED is readable in the file in front of you: the marker is
#   there or it is not, it points forward or it does not, and the id it points
#   at is active or it is not.
#
#   THE ORIGINAL TEXT is not readable in the file in front of you AT ALL. The
#   spec always says whatever it currently says; a superseded requirement whose
#   sentence was quietly rewritten last month looks exactly like one that was
#   never touched. The only place the original survives is git.
#
# So this check reads what a commit USED TO SAY, not what a commit changed.
# That distinction is the whole design. A diff-only gate sees an edit at the
# moment it is proposed and never again; it cannot answer "is R14 still the
# sentence that was agreed", because the answer lives in a commit nobody is
# diffing today. This repo has twice found in history what a diff could not
# see, and this is the first check here to take git history as an input.
#
# WHY A PURPOSE-BUILT BASELINE, AND NOT `validate-spec.py --baseline`
#
# The validator already reports SUPERSEDED_TEXT_CHANGED, and it is the right
# code - but it compares against ONE baseline the caller supplies, which in
# practice is HEAD~1. That catches an edit made in the last commit and nothing
# else: an edit made three commits ago is, from HEAD~1's point of view, the
# agreed text. The baseline that answers R3 is DIFFERENT FOR EVERY
# REQUIREMENT - it is the last commit before THAT requirement was superseded -
# and no single ref is it. This check finds each one.
#
# WHAT IT ASSERTS
#
#   1. THE TEXT IS UNALTERED. For every superseded or withdrawn requirement,
#      the sentence in the spec today is the sentence it carried at the last
#      commit at which it was still active. Whitespace and re-wrapping are
#      normalised away; words are not.
#
#      Withdrawn is included with superseded. R3 names supersession, but
#      `references/format-spec.md` section 3 puts both under the same
#      retention rule, and the failure is identical: a status line without the
#      text it applies to is not a record. Excluding withdrawn would leave the
#      same defect undetected under a different marker.
#
#   2. THE MARKER WAS NOT REMOVED. A requirement that carried a supersede or
#      withdraw marker in any reachable commit and carries none today has had
#      its status quietly reverted - the text may well be intact, and the spec
#      now presents replaced behaviour as agreed behaviour.
#
#   3. THE MARKER IS WELL FORMED. `Superseded by R<n>.` or `Withdrawn.`,
#      exactly, on the line beneath the requirement. `Superseded.` with no
#      pointer is a dead end: the citation from two years ago leads nowhere,
#      which is the one thing supersession exists to prevent.
#
#   4. THE POINTER RESOLVES, AND RESOLVES TO SOMETHING LIVE. The target id
#      must be defined in the spec and must itself be active. A pointer to an
#      id that does not exist is a broken forward reference; a pointer to
#      another superseded requirement is a chain that ends in nothing agreed,
#      and a reader following it finds no current behaviour at either end.
#      Self-supersession is refused for the same reason.
#
# SHALLOW CLONES AND MISSING HISTORY ARE UNKNOWN, NOT CLEAN
#
# CI clones with fetch-depth: 0. A contributor's `--depth 1` clone reaches the
# spec, reaches the supersede marker, and CANNOT reach the version before it.
# There is exactly one honest answer to "was the text altered" in that repo -
# it is not known - and it is exit 2. Reporting clean there would mean the
# check passes most reliably in precisely the repo where it measured nothing.
#
# The unmeasured cases, each named separately in the output:
#
#   the repo is shallow                      the prior version was never fetched
#   the spec is not tracked                  there is no previous version at all
#   the requirement is not in any commit      it exists only in the working tree
#   the spec holds no requirements            nothing to examine; not a clean run
#
# A REQUIREMENT THAT WAS ALREADY SUPERSEDED IN ITS FIRST COMMIT, in a repo with
# complete history, is NOT unmeasured. Nothing preceded that commit, so the
# text as first committed IS the original, and it is compared against. This is
# the ordinary shape of an imported spec, and calling it unmeasured forever
# would make the check permanently refuse on every repo that imported one.
#
# EXIT PRECEDENCE: UNMEASURED BEATS FINDINGS BEATS CLEAN. A run that could not
# reach some baseline exits 2 even when it also found a real alteration; the
# findings are still printed. The reason is that 1 is a complete verdict and
# this run does not have one. This mirrors `check-hygiene.sh`, where one
# unreadable file makes the whole run exit 2 rather than reporting the files it
# did manage to read as a pass.
#
# REPORTED BY LOCATION, NEVER BY QUOTING CONTENT. A finding names the id, the
# file, the line and the short sha of the commit that holds the original. It
# never prints the requirement text, and never prints a diff of it. This
# output is written into a committed result file, and a check that quotes the
# text it is protecting publishes it on every run.
#
# THE SPEC MAY BE SEVERAL FILES. Everything above is written in the singular
# and holds per REQUIREMENT, not per file: a spec split across `spec.md` and
# siblings beside it is one set of requirements, forward pointers cross
# between them, and a requirement moved from one to another has not
# disappeared. Which files count is not decided here at all: it is asked of
# `validate-spec.py --list-files`, the repo's single source of that list - see
# the discovery block below the argument loop - and every message downstream
# of it names the file the record came from rather than a path in the source.
#
# ONE LINE PER FILE EXAMINED, on stdout, unindented: every spec file, then
# every historical version of each that was read, as `<path>@<short sha>`. The
# runner treats a clean exit having examined less than declared as HOLLOW,
# which is a failure - and a git check is exactly where hollowness hides,
# because a loop over commits that never executes prints nothing and succeeds.
#
# COST. Every commit that touched a spec file is read and parsed once per
# spec file present at it, so the run is linear in the spec's own history
# times the number of spec files, not in the repo's history. That is 22
# commits and one file here; it is not linear in the number of requirements,
# which is the axis that actually grows. A split does not multiply the work
# it looks like it should: part B is absent from every commit before the
# split, and the `ls-tree` probe skips those without reading anything.
#
# KNOWN LIMITATIONS, written down rather than discovered later:
#   - A requirement that enters the repo ALREADY SUPERSEDED and already
#     rewritten cannot be caught, because its first commit is the only
#     baseline there is and the rewrite is inside it. This is the residual
#     risk of the imported-spec case above, and it is the price of not
#     refusing every imported spec forever.
#     (Superseding and rewriting in one ORDINARY commit IS caught: the
#     baseline is the commit before, where the requirement was still active
#     carrying its original sentence. Proven on a fixture.)
#   - A spec RENAMED out of `.claude/productizer/spec.md` is refused, not
#     read. See the discovery block for why: the history would be reachable
#     only from the rename forward, and every requirement older than it would
#     silently compare against the rename commit.
#   - Discovery reads what is DECLARED NOW. A spec file that existed
#     only in the past - part B of a split that was later folded back in - is
#     not opened, so a requirement that lived and was superseded entirely
#     inside it is not compared. The ids it held are still checked for
#     PRESENCE, because that sweep runs over the union of every history read.
#   - A rewritten history (rebase, filter-branch) is trusted as given. The
#     check reads what the repo now says the past was.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  clean
#   1  findings
#   2  could not run, or could not measure - no work tree, no spec, no parser,
#      a spec with no requirements, or a baseline out of reach. Never 0.
#
# Under --selftest (--self-test is accepted too) the same three mean: every
# case produced the exit code it declares and said what it was supposed to say
# (0), at least one did not (1), and the corpus could not be driven at all (2).
set -euo pipefail

# 2.1 reads a SPLIT spec. Until it, one path was hardcoded here and a split
# that kept `spec.md` as part A checked part A and printed PASS - see the
# discovery block below the argument loop, which is where the rule now lives.
# The exit codes, the output shape and the per-requirement baseline are
# unchanged, and this repository's own run is byte for byte what 2.0 printed.
VERSION="check-superseded-text 2.1"
ROOT=""
MODE="measure"

usage() {
  printf 'usage: check-superseded-text.sh [--version] [--help] [--root DIR] [--selftest]\n'
  printf '  --root DIR  the repo work tree to examine. Defaults to the git\n'
  printf '              top level, never to the working directory.\n'
  printf '  --selftest  drive the built-in corpus instead of a repository.\n'
}

die_unmeasured() { printf 'check-superseded-text: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)
      [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    -*) printf 'check-superseded-text: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'check-superseded-text: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# --selftest. R39: one case per exit code this tool can return, each built as
# a real git history in a sandbox, so nothing here reads or writes the
# repository under test.
#
# THE HISTORIES ARE BUILT, NOT COMMITTED AS FIXTURES. What this check reads is
# what a commit USED TO SAY, and a case directory under `fixtures/` cannot
# carry a git history of its own inside this repository. So every case is two
# commits made at run time in the temporary directory this run already owns.
#
# EVERY CASE ASSERTS ITS OWN SENTENCE, NOT ONLY ITS EXIT CODE. Seven different
# things exit 1 here - a rewritten sentence, a removed marker, a self-pointer,
# a dangling pointer, a chain into a superseded id, a malformed marker and an
# outright deletion - and seven more exit 2. A corpus reading exit codes alone
# cannot tell them apart, so a change that turned a rewritten sentence into a
# broken pointer would stay green through it.
#
# THE PRECEDENCE IS DRIVEN TOO. `unmeasured-beats-findings` holds a real
# rewritten sentence AND a superseded requirement with no reachable baseline;
# the header says the run must then exit 2 with the finding still printed, and
# that case is what makes the sentence a measurement.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  [ -f "$SELF" ] ||
    die_unmeasured "cannot re-invoke this script for the self-test, so no case was driven"
  command -v git >/dev/null ||
    die_unmeasured "git is not on PATH, so no history could be built and no case was driven"

  # `pwd -P` because the temporary directory is reached through a symlink on
  # macOS, and this check compares --root against `git rev-parse
  # --show-toplevel`, which is always resolved. An unresolved sandbox path
  # refuses every case for a reason about the sandbox.
  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-superseded-text-selftest.XXXXXX")" ||
    die_unmeasured "could not create a sandbox, so no case was driven"
  SB="$(cd "$SB" && pwd -P)"
  trap 'rm -rf "$SB"' EXIT HUP INT TERM

  new_repo() {
    mkdir -p "$1/.claude/productizer"
    git -c init.defaultBranch=main init -q "$1"
    git -C "$1" config user.email "fixture@example.invalid"
    git -C "$1" config user.name "check-superseded-text selftest"
  }
  commit_all() {
    git -C "$1" add -A
    git -C "$1" -c commit.gpgsign=false commit -q -m "$2"
  }
  put_spec() { cat > "$1/.claude/productizer/spec.md"; }
  # The sibling half of a split spec. Its NAME is deliberately not `spec`-
  # shaped: the discovery rule is structural, and a fixture that also happened
  # to match a name-shaped glob would pass a check that only looked at names.
  put_partb() { cat > "$1/.claude/productizer/part-two.md"; }
  # A split spec is DECLARED, never inferred from a filename - see the
  # discovery block. These two lines are the whole of a fixture's declaration.
  declare_split() {
    printf '{"spec": {"path": [".claude/productizer/spec.md", ".claude/productizer/part-two.md"]}}\n' \
      > "$1/.claude/productizer/config.json"
  }

  # --- the agreed history every case starts from ---------------------------
  founding() {
    put_spec "$1" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
SPEC
  }

  case_repo() { new_repo "$SB/$1"; founding "$SB/$1"; commit_all "$SB/$1" "founding"; }

  FAILED=0
  DRIVEN=0
  CODES=""

  drive() {
    # $1 case name, $2 expected exit, $3 expected sentence, $4.. argv override
    local case_name="$1" want="$2" marker="$3"
    shift 3
    local rc=0
    if [ "$#" -eq 0 ]; then set -- --root "$SB/$case_name"; fi
    bash "$SELF" "$@" > "$SB/$case_name.out" 2> "$SB/$case_name.err" || rc=$?
    DRIVEN=$((DRIVEN + 1))
    CODES="$CODES$rc\n"
    local why=""
    [ "$rc" -eq "$want" ] || why="exit $rc, expected $want"
    # Both files handed to grep directly, never piped into it: under
    # `set -o pipefail` a `cat a b | grep -q` reports 141 whenever grep matches
    # early enough to SIGPIPE the cat, and `if !` reads that as no match.
    if ! grep -q -- "$marker" "$SB/$case_name.out" "$SB/$case_name.err"; then
      [ -n "$why" ] && why="$why; "
      why="${why}its output does not say what it was supposed to say"
    fi
    if [ -z "$why" ]; then
      printf '  held: case %-24s exit %d, and said so - %s\n' "$case_name" "$rc" "$marker"
      return 0
    fi
    printf '  FINDING: case %-24s %s - expected: %s\n' "$case_name" "$why" "$marker"
    FAILED=$((FAILED + 1))
    return 0
  }

  # clean: R2 superseded and R4 withdrawn, both carrying the sentence they had
  # at the commit before. The withdrawn half is here because R3 names
  # supersession and format-spec puts both under the same retention rule.
  case_repo clean
  put_spec "$SB/clean" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
  Superseded by R3. Narrowed to the classifications that change the spec.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
  Withdrawn.
SPEC
  commit_all "$SB/clean" "supersede R2, withdraw R4"

  # text-changed: superseded AND rewritten. The baseline is the commit before,
  # where it was still active carrying its original sentence.
  case_repo text-changed
  put_spec "$SB/text-changed" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle should probably prefer that ids not be reused often.
  Superseded by R3. Narrowed.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
SPEC
  commit_all "$SB/text-changed" "supersede R2 and rewrite what it used to say"

  # marker-removed: superseded in a reachable commit, active today.
  case_repo marker-removed
  put_spec "$SB/marker-removed" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
  Superseded by R3. Narrowed.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
SPEC
  commit_all "$SB/marker-removed" "supersede R2"
  founding "$SB/marker-removed"
  commit_all "$SB/marker-removed" "quietly revert R2 to active"

  # self-supersede, dangling, chain, malformed: the marker itself.
  case_repo pointer-self
  put_spec "$SB/pointer-self" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
  Superseded by R2. A pointer that never leaves the requirement it is on.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
SPEC
  commit_all "$SB/pointer-self" "supersede R2 by itself"

  case_repo pointer-dangling
  put_spec "$SB/pointer-dangling" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
  Superseded by R99. An id this spec does not define.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
SPEC
  commit_all "$SB/pointer-dangling" "supersede R2 by an id nothing defines"

  case_repo pointer-chain
  put_spec "$SB/pointer-chain" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
  Superseded by R3. Which is itself replaced.
- **R3** — The lifecycle shall record every classification in the change log.
  Superseded by R4. So the chain ends in nothing agreed.
- **R4** — The lifecycle shall publish every view read-only.
SPEC
  commit_all "$SB/pointer-chain" "supersede R2 into a requirement that is itself superseded"

  case_repo marker-malformed
  put_spec "$SB/marker-malformed" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
  Superseded. No pointer at all, so the citation leads nowhere.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
SPEC
  commit_all "$SB/marker-malformed" "supersede R2 with no forward pointer"

  # deleted: recorded superseded in history and not defined today at all. The
  # loop over today's requirements cannot see this one; the awk over both
  # files is what does.
  case_repo deleted
  put_spec "$SB/deleted" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
  Superseded by R3. Narrowed.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
SPEC
  commit_all "$SB/deleted" "supersede R2"
  put_spec "$SB/deleted" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
SPEC
  commit_all "$SB/deleted" "delete the superseded entry outright"

  # refined-then-superseded: THE BASELINE IS THE LAST ACTIVE COMMIT, NOT THE
  # FIRST ONE. R2 is REFINED while still active - which the spec permits, an
  # edit in place that keeps the id - and superseded a commit later carrying
  # the refined sentence unaltered. Nothing here is a defect, and only the
  # correct baseline says so: compared against the founding commit instead,
  # the legitimate refinement reads as a rewritten original and this case goes
  # red. Added 2026-09-07 after a falsification found the corpus could not
  # tell the two baselines apart - every other case here differs from BOTH, so
  # a wrong baseline still produced the right verdict for the wrong reason.
  case_repo refined-then-superseded
  put_spec "$SB/refined-then-superseded" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep every requirement id permanent, and shall never reuse one.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
SPEC
  commit_all "$SB/refined-then-superseded" "refine R2 while it is still active"
  put_spec "$SB/refined-then-superseded" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep every requirement id permanent, and shall never reuse one.
  Superseded by R3. Narrowed to the classifications that change the spec.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
SPEC
  commit_all "$SB/refined-then-superseded" "supersede R2, keeping the refined sentence"

  # ------------------------------------------------------------------------
  # THE TWO SPLIT CASES. Until 2.1 this check opened one hardcoded path, and a
  # split that RENAMED the spec failed closed - correctly - while a split that
  # KEPT `spec.md` as part A and added a sibling checked part A, printed PASS,
  # and left every superseded requirement in part B unexamined with no signal
  # at all. Both halves of the fix need driving, because they fail in opposite
  # directions: `split-sibling` fails if the sibling is not read, and
  # `split-clean` fails if reading it invents findings that are not defects.
  # ------------------------------------------------------------------------

  # split-clean: a legitimate, DECLARED split. Part B holds R2, superseded, carrying the
  # sentence it had in part A before the split, and pointing forward at R3 -
  # which is in part A. Nothing here is a defect: the text is faithful and the
  # pointer resolves, ACROSS FILES. Resolving pointers within one file instead
  # would report R2 as dangling, and a check that fires on every cross-file
  # pointer is a check switched off in the week of the split.
  case_repo split-clean
  put_spec "$SB/split-clean" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
SPEC
  put_partb "$SB/split-clean" <<'SPEC'
# Living spec — sandbox, part two

## Requirements

- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
  Superseded by R3. Narrowed to the classifications that change the spec.
SPEC
  declare_split "$SB/split-clean"
  commit_all "$SB/split-clean" "split the spec; R2 moves to part two and is superseded there"

  # split-sibling: THE SILENT PARTIAL PASS. R4 leaves part A and is superseded
  # AND rewritten in part B, in the one commit. Part A is clean, so the only
  # thing that can make this run exit 1 is the sibling having been read. The
  # baseline is in the OTHER file - the founding commit of `spec.md`, the last
  # commit at which R4 was active - so this drives cross-file baseline
  # resolution as well as discovery.
  case_repo split-sibling
  put_spec "$SB/split-sibling" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.
SPEC
  put_partb "$SB/split-sibling" <<'SPEC'
# Living spec — sandbox, part two

## Requirements

- **R4** — The lifecycle shall publish whatever view the operator asks for.
  Superseded by R3. Rewritten in the same commit that moved it.
SPEC
  declare_split "$SB/split-sibling"
  commit_all "$SB/split-sibling" "split the spec, and rewrite R4 on the way out"

  # split-undeclared: the same sibling, the same rewritten R4, and NOBODY
  # declared the split. The list is refused, and so is this run. It is the case
  # that says the fallback is not allowed: reading `spec.md` alone here would
  # produce a confident exit 0 over a spec whose extent nobody knew - which is
  # the defect 2.1 exists to remove, wearing a different name.
  case_repo split-undeclared
  put_spec "$SB/split-undeclared" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
- **R3** — The lifecycle shall record every classification in the change log.
SPEC
  put_partb "$SB/split-undeclared" <<'SPEC'
# Living spec — sandbox, part two

## Requirements

- **R4** — The lifecycle shall publish whatever view the operator asks for.
  Superseded by R3. Rewritten in the same commit that moved it.
SPEC
  commit_all "$SB/split-undeclared" "split the spec and declare nothing"

  # spec-home-unopenable: something in the spec directory matches `*.md` and
  # cannot be opened, so the extent of the spec is unknown and the lister
  # refuses. Driven as a DIRECTORY rather than a `chmod 000` file on purpose:
  # a directory fails for every uid, and a mode-000 file is readable when the
  # run happens to be root - a case that holds on a developer's machine and
  # silently stops driving anything in a container.
  case_repo spec-home-unopenable
  mkdir -p "$SB/spec-home-unopenable/.claude/productizer/archive.md"

  # uncommitted: superseded, and present only in the working tree.
  case_repo uncommitted
  put_spec "$SB/uncommitted" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent, never reused.
  Superseded by R3. Narrowed.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
- **R5** — The lifecycle shall declare what each check examined.
  Withdrawn.
SPEC

  # unmeasured-beats-findings: a real rewritten sentence AND a requirement
  # with no reachable baseline. 1 is a complete verdict and this run has none.
  case_repo unmeasured-beats-findings
  put_spec "$SB/unmeasured-beats-findings" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle should probably prefer that ids not be reused often.
  Superseded by R3. Narrowed.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
SPEC
  commit_all "$SB/unmeasured-beats-findings" "supersede R2 and rewrite it"
  put_spec "$SB/unmeasured-beats-findings" <<'SPEC'
# Living spec — sandbox

## Requirements

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle should probably prefer that ids not be reused often.
  Superseded by R3. Narrowed.
- **R3** — The lifecycle shall record every classification in the change log.
- **R4** — The lifecycle shall publish every view read-only.
- **R5** — The lifecycle shall declare what each check examined.
  Withdrawn.
SPEC

  # shallow: the version before the supersede was never fetched.
  git clone -q --depth 1 "file://$SB/clean" "$SB/shallow" ||
    die_unmeasured "could not build a shallow clone, so the case that proves a shallow clone is refused was never driven"

  # untracked: the spec is on disk and git has never seen it.
  new_repo "$SB/untracked"
  printf 'a repository that has committed something other than its spec\n' > "$SB/untracked/README"
  commit_all "$SB/untracked" "founding, without the spec"
  founding "$SB/untracked"

  # no-requirements: a spec with no `## Requirements` section.
  new_repo "$SB/no-requirements"
  printf '# Living spec — sandbox\n\n## Design\n\nProse and no requirement definitions.\n' \
    > "$SB/no-requirements/.claude/productizer/spec.md"
  commit_all "$SB/no-requirements" "a spec with nothing in it to retain"

  # no-spec: a work tree with no spec at the declared path.
  new_repo "$SB/no-spec"
  printf 'no spec here\n' > "$SB/no-spec/README"
  commit_all "$SB/no-spec" "founding"
  rmdir "$SB/no-spec/.claude/productizer" "$SB/no-spec/.claude"

  # not-a-work-tree: the spec is readable and git knows nothing about it.
  mkdir -p "$SB/not-a-work-tree/.claude/productizer"
  founding "$SB/not-a-work-tree"

  # root-not-a-directory
  printf 'not a directory\n' > "$SB/a-file"

  # THE CLEAN CASE GUARDS THE OTHERS' PREMISE. If a spec whose superseded and
  # withdrawn entries still carry their agreed sentences does not exit 0, every
  # red case below would be red for that reason instead of its own.
  CLEAN_RC=0
  bash "$SELF" --root "$SB/clean" > "$SB/clean.out" 2> "$SB/clean.err" || CLEAN_RC=$?
  CODES="$CODES$CLEAN_RC\n"
  if [ "$CLEAN_RC" -ne 0 ] || ! grep -q 'PASS: every superseded or withdrawn requirement' "$SB/clean.out"; then
    printf '  the clean case exited %d and did not report the retention holding.\n' "$CLEAN_RC"
    die_unmeasured "the corpus premise did not hold; unmeasured, not a pass"
  fi
  printf '  held: case %-24s exit 0, and said so - %s\n' "clean" "PASS: every superseded or withdrawn requirement"

  drive text-changed     1 'text CHANGED'
  drive marker-removed   1 'The marker was removed'
  drive pointer-self     1 'is superseded by itself'
  drive pointer-dangling 1 'which is not defined in'
  drive pointer-chain    1 'which is itself superseded'
  drive marker-malformed 1 'carries a status marker that is neither'
  drive deleted          1 'A replaced requirement is RETAINED'
  drive split-sibling    1 'part-two.md:'
  drive split-clean      0 'PASS: every superseded or withdrawn requirement'
  drive refined-then-superseded 0 '(pre-supersede)  text unchanged'

  drive uncommitted      2 'appears in no commit'
  drive split-undeclared 2 'SPEC_FILE_UNDECLARED'
  drive spec-home-unopenable 2 'could not be read'
  drive unmeasured-beats-findings 2 'text CHANGED'
  drive shallow          2 'the clone is shallow'
  drive untracked        2 'the spec is untracked'
  drive no-requirements  2 'holds no requirement definitions'
  drive no-spec          2 'cannot read .claude/productizer/spec.md'
  drive not-a-work-tree  2 'is not inside a git work tree'
  drive root-not-a-dir   2 'is not a directory' --root "$SB/a-file"

  # R39.b: the codes below are COMPUTED from the cases as they ran - every
  # `drive` return plus the one case driven outside that helper - not typed.
  # A hardcoded list here would be a claim with nothing checking it.
  REACHED="$(printf '%b' "$CODES" | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/ *$//')"
  printf '  cases driven: %d. Cases that did not hold: %d\n' \
    "$((DRIVEN + 1))" "$FAILED"
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  for want in 0 1 2; do
    printf '%b' "$CODES" | grep -qx "$want" ||
      printf '  R39.b: documented exit code %s was never driven by any case.\n' "$want" >&2
  done
  if [ "$FAILED" -ne 0 ]; then
    printf 'FAIL: %d selftest case(s) did not produce the exit code and the sentence they declare.\n' "$FAILED" >&2
    exit 1
  fi
  printf '  R39 for this tool: the self-test exists, reaches 0, 1 and 2, and every case asserts which finding it produced as well as which code.\n'
  printf '  NOT ASSERTED: the imported-spec residue in the header - a requirement that enters the repository ALREADY superseded and already rewritten - is unreachable by construction. Its first commit is the only baseline there is, so no corpus can tell that case from a faithful import.\n'
  exit 0
fi

# Defaulting to the working directory has caused four separate silent-wrong-
# answer bugs here: the script reads a directory that is not the repo and
# reports a confident clean result. git names the work tree or nothing does.
if [ -z "$ROOT" ]; then
  if ! ROOT="$(git rev-parse --show-toplevel)"; then
    die_unmeasured "no git work tree here, and --root was not given. Refusing rather than reading the working directory, which is not the repo often enough to matter."
  fi
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"

SELFDIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="$SELFDIR/spec-requirements.sh"
[ -x "$PARSER" ] ||
  die_unmeasured "spec-requirements.sh is not beside this script and executable. Without the parser nothing here read the spec, and a run that read nothing is not a run that found nothing."

SPECREL=".claude/productizer/spec.md"
SPEC="$ROOT/$SPECREL"
[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unmeasured "cannot read $SPECREL under $ROOT. Without the spec there is no superseded requirement to check the retention of."

TOP="$(git -C "$ROOT" rev-parse --show-toplevel)" ||
  die_unmeasured "--root $ROOT is not inside a git work tree. R3's second half is only answerable from history, and there is no history here."
case "$ROOT/" in
  "$TOP"/*) ;;
  *) die_unmeasured "--root $ROOT resolves outside its own git top level $TOP" ;;
esac

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-superseded-text.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# ---------------------------------------------------------------------------
# WHICH FILES ARE THE SPEC. THE RULE IS NOT STATED HERE - IT IS ASKED FOR.
# ---------------------------------------------------------------------------
#
# THE LIST COMES FROM `validate-spec.py --repo . --list-files`, which is the
# single source of it. The contract is written out in `checks.yaml` above the
# `superseded-text` entry; in one sentence, `spec.path` in the config is
# authoritative - a string is one file, a list is a split spec in reading
# order, no config means the default path - and any OTHER `.md` in the spec
# directory that reads as a spec, or that cannot be read at all, is an error
# rather than a silent inclusion.
#
# THIS CHECK DOES NOT RE-IMPLEMENT THAT RULE, and the reason is the defect
# being fixed. Until 2.1 the path here was a literal, and a split that KEPT
# `spec.md` as part A and added a sibling checked part A, printed PASS, and
# left every superseded requirement in part B unexamined WITH NO SIGNAL AT
# ALL. Measured on a real split of this repository's own spec: R38 moved to a
# sibling, was superseded there and its sentence rewritten, and the run
# reported `requirements examined: 38 ... PASS`, exit 0, never naming R38. A
# second literal - or a second glob, written here in this file - would put two
# answers to "which files are the spec" in one repository, and the day they
# disagree one of these tools reports a requirement checked and the other
# never opens the file it is in. Both are green in their own terms.
#
# EVERY REFUSAL OF THE LISTER IS A REFUSAL HERE. An undeclared spec file in
# the spec directory (its exit 1) is NOT a licence to fall back to the default
# path and check what is left: that is the silent partial pass under a new
# name. The lister's own sentence is printed and this run exits 2.
#
# WHAT IS STILL A LITERAL, deliberately: the DECLARED DEFAULT above must
# exist. A repository that moved its spec wholesale to another path is refused
# rather than read, because `git log` over the new path stops at the rename -
# every requirement older than the move would silently compare against the
# rename commit as though that were the original. Refusing is the honest
# answer to that; a `--follow`-shaped answer has not been measured here.
# Repo-relative path -> path as git names it, which is relative to the top
# level and not to --root.
git_path() { local abs="$ROOT/$1"; printf '%s\n' "${abs#"$TOP"/}"; }

LISTER="$SELFDIR/validate-spec.py"
[ -f "$LISTER" ] ||
  die_unmeasured "validate-spec.py is not beside this script. It is the one place that knows which files are the spec, and a run that guessed the extent of the spec has not measured it."
command -v python3 >/dev/null ||
  die_unmeasured "python3 is not on PATH, so the spec file list could not be asked for. Guessing it is the silent partial pass this check exists to refuse."

LIST_RC=0
SPECRELS="$(cd "$ROOT" && python3 "$LISTER" --repo . --list-files 2>&1)" || LIST_RC=$?
case "$LIST_RC" in
  0) ;;
  1) die_unmeasured "the spec file list was refused - a file in the spec directory reads as a spec and is not declared, so which files are the spec is UNKNOWN. Not a pass over the rest: $SPECRELS" ;;
  4) die_unmeasured "discovery refused: $SPECRELS" ;;
  *) die_unmeasured "validate-spec.py --list-files exited $LIST_RC and this run has no list of spec files to read: $SPECRELS" ;;
esac
[ -n "$SPECRELS" ] ||
  die_unmeasured "the spec file list came back empty at exit 0. Nothing to read is not nothing wrong."

# The declared spec is the anchor of this check's history reading - see above.
printf '%s\n' "$SPECRELS" | grep -qxF "$SPECREL" ||
  die_unmeasured "the spec file list does not include $SPECREL. A spec moved wholesale to another path takes its history with it, and every requirement older than the move would compare against the move rather than against what was agreed."

SPECLIST="$(printf '%s' "$SPECRELS" | tr '\n' ' ' | sed 's/ $//; s/ /, /g')"

found=0
unmeasured=0
finding() { printf '    %s\n' "$1"; found=1; }
unmeasurable() { printf '    UNMEASURED %s\n' "$1"; unmeasured=1; }

# --- the spec as it stands now ---------------------------------------------
#
# Every record carries the FILE it came from as its first column. A split spec
# is one set of requirements living in several files, and a finding that named
# only the id would send a reader to the wrong one.
: > "$WORK/cur.tsv"
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  printf '%s\n' "$rel"                   # coverage: one line per file examined
  "$PARSER" "$ROOT/$rel" |
    awk -F'\t' -v p="$rel" 'BEGIN{OFS="\t"} {print p, $1, $2, $3, $4, $5}' >> "$WORK/cur.tsv" ||
    die_unmeasured "the parser refused $rel"
done <<SPEC_FILES
$SPECRELS
SPEC_FILES

if [ ! -s "$WORK/cur.tsv" ]; then
  printf 'requirements examined: 0\n'
  die_unmeasured "$SPECREL holds no requirement definitions. That is nothing measured, not nothing wrong."
fi

# --- every version of every spec file that git can still reach --------------
SHALLOW="$(git -C "$TOP" rev-parse --is-shallow-repository)"

: > "$WORK/tracked"
: > "$WORK/untracked"
GITPATHS=()
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  gp="$(git_path "$rel")"
  if [ -n "$(git -C "$TOP" ls-files -- "$gp")" ]; then
    printf '%s\t%s\n' "$rel" "$gp" >> "$WORK/tracked"
    GITPATHS+=("$gp")
  else
    printf '%s\n' "$rel" >> "$WORK/untracked"
  fi
done <<SPEC_FILES
$SPECRELS
SPEC_FILES

: > "$WORK/hist.tsv"
versions=0
if [ "${#GITPATHS[@]}" -gt 0 ]; then
  # ONE `git log` OVER EVERY SPEC FILE AT ONCE, not one log per file. The
  # baseline for a requirement is the NEWEST commit at which it was still
  # active, and "newest" only means anything inside a single ordering.
  # Concatenating a log per file interleaves two orderings, and the first
  # matching row is then whichever file happened to be read first rather than
  # whichever commit came last - which is how a requirement that MOVED between
  # spec files would get compared against a baseline older than its own move.
  git -C "$TOP" log --format=%H -- "${GITPATHS[@]}" > "$WORK/commits" ||
    die_unmeasured "git log over $SPECLIST failed; the history this check reads is unavailable"

  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    short=""
    while IFS="$(printf '\t')" read -r rel gp; do
      [ -n "$rel" ] || continue
      # ls-tree, not `git show`, as the existence probe: it prints nothing and
      # exits 0 for a path absent at that commit, so a deletion commit costs no
      # error output. Suppressing git's stderr to find that out is exactly how a
      # sweep over git objects in this repo once reported CLEAN while every
      # command inside the loop was failing. It is also what makes a split
      # cheap: part B is absent from every commit before the split, and the
      # probe skips those without a word.
      [ -n "$(git -C "$TOP" ls-tree "$sha" -- "$gp")" ] || continue
      [ -n "$short" ] || short="$(git -C "$TOP" rev-parse --short "$sha")"
      git -C "$TOP" show "$sha:$gp" > "$WORK/v.md" ||
        die_unmeasured "cannot read $rel at $short, which git listed as a commit that touched it"
      printf '%s@%s\n' "$rel" "$short"    # coverage: one line per file examined
      versions=$((versions + 1))
      "$PARSER" "$WORK/v.md" |
        awk -F'\t' -v s="$short" -v p="$rel" 'BEGIN{OFS="\t"} {print s, p, $1, $2, $3, $4, $5}' >> "$WORK/hist.tsv"
    done < "$WORK/tracked"
  done < "$WORK/commits"
fi

printf 'spec versions examined: %d\n' "$versions"

# --- the requirements whose text must not have moved ------------------------
retained=0
compared=0

while IFS="$(printf '\t')" read -r path id line status target text; do
  [ -n "${id:-}" ] || continue

  # ---- 3 and 4: the marker itself, readable in the file in front of you ----
  if [ "$status" = "malformed" ]; then
    finding "$path:$line: $id carries a status marker that is neither 'Superseded by R<n>.' nor 'Withdrawn.', or carries two. A marker with no resolvable pointer is a citation that leads nowhere, which is the one thing supersession exists to prevent."
  fi

  if [ "$status" = "superseded" ]; then
    # Resolved across EVERY spec file of the run, not within one file. In a
    # split spec a forward pointer crosses files as a matter of course, and
    # resolving it per file turns every such pointer into a dangling one - a
    # wall of findings on the day of the split, which is how a check gets
    # switched off in the week of the split.
    tstatus="$(awk -F'\t' -v t="$target" '$2 == t { print $4; exit }' "$WORK/cur.tsv")"
    if [ "$target" = "$id" ]; then
      finding "$path:$line: $id is superseded by itself. The forward pointer has to leave the requirement it is written on."
    elif [ -z "$tstatus" ]; then
      finding "$path:$line: $id points forward at $target, which is not defined in any spec file this run read ($SPECLIST). A citation following that pointer resolves to nothing, and nothing errors."
    elif [ "$tstatus" != "active" ]; then
      finding "$path:$line: $id points forward at $target, which is itself $tstatus. The chain ends in behaviour nobody agreed to, so a reader following it finds no current requirement at either end."
    fi
  fi

  # ---- 2: a marker that was there and is not now --------------------------
  if [ "$status" = "active" ]; then
    was="$(awk -F'\t' -v i="$id" '$3 == i && ($5 == "superseded" || $5 == "withdrawn") { print $1; exit }' "$WORK/hist.tsv")"
    if [ -n "$was" ]; then
      finding "$path:$line: $id is active today and was $(awk -F'\t' -v i="$id" '$3 == i && ($5 == "superseded" || $5 == "withdrawn") { print $5; exit }' "$WORK/hist.tsv") at $was. The marker was removed, so replaced behaviour now reads as agreed behaviour."
    fi
    continue
  fi

  [ "$status" = "superseded" ] || [ "$status" = "withdrawn" ] || continue
  retained=$((retained + 1))

  # ---- 1: the text, which only git can answer -----------------------------
  #
  # The baseline is the newest commit at which THIS requirement was still
  # active - a different commit for every requirement, which is why one
  # `--baseline` ref cannot answer this.
  base_sha="$(awk -F'\t' -v i="$id" '$3 == i && $5 == "active" { print $1; exit }' "$WORK/hist.tsv")"
  base_kind="pre-supersede"

  if [ -z "$base_sha" ]; then
    # Never active in any reachable commit. Either the history is short, or
    # the requirement entered the repo already superseded.
    oldest_sha="$(awk -F'\t' -v i="$id" '$3 == i { s = $1 } END { if (s != "") print s }' "$WORK/hist.tsv")"
    if [ -z "$oldest_sha" ]; then
      printf '  %s %-10s baseline —  text —\n' "$id" "$status"
      unmeasurable "$path:$line: $id appears in no commit that touched $SPECLIST. It exists only in the working tree, so there is no previous version of its text to compare against. Commit it and re-run; this is not a clean result."
      continue
    fi
    if [ "$SHALLOW" = "true" ]; then
      printf '  %s %-10s baseline —  text —\n' "$id" "$status"
      unmeasurable "$path:$line: $id is $status in every commit this clone can reach, and the clone is shallow. The version before the supersede was never fetched, so whether the text was altered is UNKNOWN. Fetch full history (fetch-depth: 0) and re-run."
      continue
    fi
    # Full history, and the requirement was already superseded when it first
    # appeared: nothing preceded that commit, so what it said there IS the
    # original. This is the ordinary shape of an imported spec.
    base_sha="$oldest_sha"
    base_kind="first-commit"
  fi

  base_text="$(awk -F'\t' -v i="$id" -v s="$base_sha" '$1 == s && $3 == i { print $7; exit }' "$WORK/hist.tsv")"
  # The file that HELD the baseline, which in a split spec need not be the file
  # holding the requirement today. The reader is sent to the version that
  # exists, not to the path the requirement happens to sit at now.
  base_rel="$(awk -F'\t' -v i="$id" -v s="$base_sha" '$1 == s && $3 == i { print $2; exit }' "$WORK/hist.tsv")"
  base_git="$(git_path "$base_rel")"
  compared=$((compared + 1))

  if [ "$base_text" = "$text" ]; then
    printf '  %s %-10s baseline %s (%s)  text unchanged\n' "$id" "$status" "$base_sha" "$base_kind"
  else
    printf '  %s %-10s baseline %s (%s)  text CHANGED\n' "$id" "$status" "$base_sha" "$base_kind"
    finding "$path:$line: $id is $status, and its sentence is not the sentence it carried at $base_sha - the last commit at which it was still active. The original text was rewritten at or after the point the requirement was replaced, so the spec no longer records what was agreed, only what someone would prefer it had said. The text is deliberately not quoted here; read it with: git show $base_sha:$base_git"
  fi
done < "$WORK/cur.tsv"

# ---- 3: a requirement that is not there at all --------------------------
#
# The loop above walks requirements PRESENT IN THE SPEC TODAY, so a
# requirement that was deleted outright is simply not in it. Measured, not
# argued: deleting a superseded entry - sentence, marker and all - dropped the
# counts from 3 to 2 and the run stayed green, because the denominator was
# taken from what survived rather than from what should have.
#
# R3 says the original text is KEPT IN THE SPEC. Deletion is the largest
# possible violation of that, and it was the one this check could not see. So
# every id history ever recorded as superseded or withdrawn must still be
# defined today.
# Computed with awk over BOTH files rather than a `while read` loop. A first
# attempt used `IFS=<tab> read`, which silently gave the wrong answer: a tab is
# an IFS whitespace character, so runs of tabs collapse and an empty field
# shifts every column after it. The status column was then never `superseded`,
# the loop body never fired, and the check reported `0 missing` over a spec with
# a requirement deleted from it. Caught by falsifying, not by reading.
gone=0
: > "$WORK/missing.tsv"
# The presence half is asked across ALL spec files at once - `cur[]` is keyed
# on the id column of the union. A requirement MOVED from one spec file to
# another is therefore still present, which is the whole point of a split; only
# a requirement that is in none of them is gone.
awk -F'\t' '
  NR == FNR { cur[$2] = 1; next }
  ($5 == "superseded" || $5 == "withdrawn") && !($3 in cur) && !seen[$3]++ { print $3 "\t" $5 "\t" $1 "\t" $2 }
' "$WORK/cur.tsv" "$WORK/hist.tsv" > "$WORK/missing.tsv"

while IFS="$(printf '\t')" read -r hid hstatus hsha hrel; do
  [ -n "$hid" ] || continue
  gone=$((gone + 1))
  finding "$hrel: $hid was recorded $hstatus at $hsha and is not defined in any spec file this run read ($SPECLIST). A replaced requirement is RETAINED with its marker - deleting it is the largest way to stop keeping the original text, and every plan, test, review finding and PR title citing $hid now resolves to nothing."
done < "$WORK/missing.tsv"
printf 'superseded ids checked for presence: %d missing\n' "$gone"

printf 'requirements examined: %d\n' "$(wc -l < "$WORK/cur.tsv" | tr -d ' ')"
printf 'superseded or withdrawn: %d\n' "$retained"
if [ "$retained" -eq "$compared" ]; then
  printf 'text compared against history: %d\n' "$compared"
else
  printf 'text compared against history: %d of %d — the rest are unmeasured above, not clean\n' "$compared" "$retained"
fi
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  printf 'note: %s is not tracked by git, so no previous version of any requirement exists. That is no measurement, not a measured zero.\n' "$rel"
  unmeasurable "$rel:1: the spec is untracked. R3's retention half is unanswerable until it is committed."
done < "$WORK/untracked"

if [ "$unmeasured" -ne 0 ]; then
  printf 'UNMEASURED: at least one superseded requirement has no reachable earlier version, so this run has no verdict on whether its text was altered. Not a pass.\n' >&2
  exit 2
fi
if [ "$found" -ne 0 ]; then
  printf 'FAIL: a replaced requirement no longer carries the text that was agreed, or no longer points anywhere. R3 keeps the original; these findings are where it stopped being kept.\n' >&2
  exit 1
fi

printf 'PASS: every superseded or withdrawn requirement still carries the sentence it had at the commit before it was replaced, and every forward pointer resolves to an active id.\n'
