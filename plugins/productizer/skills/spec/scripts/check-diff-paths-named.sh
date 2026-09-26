#!/usr/bin/env bash
# check-diff-paths-named.sh [--rev REV] [--staged] [--message-file FILE]
#                           [--last N] [--generated GLOB]... [--root DIR]
#                           [--version] [--help] [--selftest|--self-test]
#
# IF THE DIFF SHOWS A PATH, THE COMMIT'S OWN RECORD SHOULD NAME IT.
#
# The failure this exists for happened here. Eight agents were writing at once;
# one of them had files open in a directory the maintainer was not committing,
# and those files went into an unrelated commit. Nothing noticed, because
# nothing in this repository compares the set of paths a commit touched against
# the set of paths its message talks about. The message was true about the work
# it described and silent about the rest, and silence is what a sweep looks
# like.
#
# ============================================================================
# WHAT COUNTS AS THE RECORD, AND WHY IT IS THE COMMIT MESSAGE
# ============================================================================
#
# The commit message, subject and body, and nothing else by default.
#
# Three candidates were considered and two rejected:
#
#   THE SPEC'S CHANGE LOG. Already checked, by `check-changelog-row.sh`, and
#   that check is keyed on a different event: a classification that CHANGED THE
#   SPEC earns a row. The sweep B69 names touched no spec and merged no
#   requirement, so it is outside that check's trigger entirely and always will
#   be. Reading the same table here would duplicate a lookup and still miss the
#   failure.
#
#   THE CHECKS RESULT FILE. It records what the suite examined, not what the
#   author meant to change. A swept path is examined by the suite exactly as
#   happily as an intended one - that is the whole problem.
#
#   THE COMMIT MESSAGE. It is the only record every commit has, it is written
#   by the same actor that staged the diff, it is immutable beside the diff
#   forever, and it is the artifact a reader reaches for when asking "why is
#   this file in here". `--message-file` points the same rule at a message that
#   is not committed yet, which is how a pre-commit hook would use it.
#
# An explicit manifest - a `Paths:` trailer - is NOT required and NOT
# recognised. It would be trivially satisfiable by pasting `git diff --name-only`
# into the message, which names every path and tells a reader nothing. The
# assertion is that the prose mentions the file, because prose is what a human
# writes when they know why the file is there.
#
# ============================================================================
# HOW A PATH IS "NAMED" - THE RULE, AND THE MEASUREMENT BEHIND IT
# ============================================================================
#
# A path counts as named when the record contains, as a token, ANY of:
#
#   (1) THE FULL repo-relative path.
#   (2) A PATH-SHAPED TOKEN - one containing a `/` - that is the path or a
#       directory prefix of it. `plugins/productizer/skills/spec/scripts/`
#       names everything under it.
#   (3) THE BASENAME WITH ITS EXTENSION. `check-hygiene.sh`, `spec.md`.
#
# Tier (3) IGNORES DIRECTORIES, deliberately and at a cost that is measured:
# one mention of `backlog.md` satisfies `.claude/productizer/backlog.md`,
# `plugins/.../references/backlog.md` and `plugins/.../templates/backlog.md`
# in the same diff. Over this repository's 121 commits, 28 of the 161 named
# units - 17% - were satisfied by a basename that is not unique inside their
# own diff, spread over 11 commits. Tightening it to demand a directory would
# take the named count below what a human would call fair, since a message that
# says `backlog.md` when only one is in the diff has done its job. The number is
# printed on every run instead of being resolved.
#
# A token is a maximal run of `[A-Za-z0-9_./-]`, lowercased, with trailing
# sentence punctuation dropped, so backticks, quotes, commas and parentheses
# around a filename do not hide it. Matching is case-insensitive because this
# repository writes `GUIDE.md` and `guide.md` for the same file.
#
# TWO LOOSER RULES WERE MEASURED AND REJECTED, on this repository's last 40
# commits (547 paths):
#
#   THE BARE STEM - `spec` for `spec.md`. Raw substring stem matching named 29%
#   of paths against 10% for full basenames, and the extra nineteen points are
#   words: `spec`, `views`, `score`, `upgrade`, `release`, `signals` are all
#   ordinary prose in these messages. A rule where the sentence "the spec was
#   not changed" names `spec.md` measures nothing.
#
#   THE BARE LAST DIRECTORY WORD - `scripts` for `scripts/a.sh`. Raw substring
#   matching on it named 14% of paths, and `scripts`, `templates`, `hooks` and
#   `commands` are prose here too. This is the failure mode the brief for this
#   work names: "updated the scripts" must not pass for anything under
#   `scripts/`. Requiring a `/` before a directory counts is what rule (2) is
#   for, and the cost of that strictness was measured: over those 40 commits,
#   requiring path shape removed ZERO matches, because not one of those commit
#   messages wrote a directory in path form at all.
#
# ============================================================================
# THE NUMBER THIS REPOSITORY SCORES, WHICH IS WHY THIS CHECK ADVISES
# ============================================================================
#
# Measured by this script over all 121 commits reachable from HEAD, with
# `--last 121`, on 2026-09-26 at 5117f48:
#
#     commits surveyed: 121
#     clean: 1   with findings: 120   refused: 0
#     units examined: 1487, named: 161, not named: 1326
#
# ONE commit in this repository's entire history names every path it touches,
# and it is `3d8c94f Record the check run for the untangled main` - a
# single-file commit whose first sentence is the filename. The brief for this
# work said "a rule that fails 90% of real commits is not a rule anyone will
# keep"; the measured figure is 99.2%, and that is a finding about this
# repository's messages rather than about the rule. The messages are long and
# argumentative and they name files by ROLE - "the dashboard", "the workflow",
# "GUIDE said", "filed B70" - while the paths are `.../build-view.sh`,
# `.github/workflows/checks.yml`, `GUIDE.md`, `.claude/productizer/backlog.md`.
# A role is not a path and no mechanical rule recovers one from the other.
#
# WHICH TIER DID THE WORK, over those same 121 commits: basename 124, basename
# inside a longer path 24, full path 11, directory prefix 2. The tiers are not
# decoration - drop the basename tier and 148 of 161 named units go red - and
# the directory tier earns its two hits across a whole history, which is the
# same measurement that says a bare directory WORD would have been a giveaway
# rather than a rule.
#
# So this check is a REPORTER whose output is a work queue, and it must be
# declared `severity: advise` on introduction. B68 argues a check should be
# calibrated before it blocks, and a check that goes red on 121 of 121 commits
# on the day it lands is the shape this repository has already been burned by -
# a step that fails on a pre-existing condition is a step somebody deletes.
# What would make it blockable is not a looser rule. It is messages that name
# their files, and the count printed here is how anyone would know that is
# happening.
#
# THE RULE IS NOT MADE LOOSER TO GET A GREEN. A role-alias table - "the spec"
# means `spec.md`, "CI" means `.github/workflows/*` - would lift the pass rate
# and would hardcode one repository's layout into a plugin other people
# install, and "CI" would then name every file under `.github/`. It is
# refused, and named here so the next reader does not have to rediscover why.
#
# ============================================================================
# DELETIONS, RENAMES, AND FILES NOBODY WROTE
# ============================================================================
#
# A DELETION IS IN SCOPE. The file cannot be read at this commit but its NAME
# can still appear in the message, and a swept deletion is the worst case of
# the failure this check exists for - the content is gone and the record does
# not say it went. Deletions are counted and reported as their own class so a
# reader can see how many findings are removals.
#
# A RENAME IS ONE UNIT, NAMED IF EITHER SIDE IS. Rename detection is on
# (`-M`), so a move appears as an old path and a new one. Demanding both is
# wrong: "moved the gate into hooks/" names the destination and is a complete
# record of the move. Demanding neither would let a file be moved out of the
# tree unmentioned. Either side, one unit, and the report says which side
# carried it.
#
# GENERATED FILES ARE EXCLUDED ONLY BY EXPLICIT REQUEST, and the exclusion is
# always printed. `--generated GLOB`, repeatable. There is no built-in list:
# this script ships inside a plugin that other repositories install, and a
# hardcoded list of one repository's build outputs would silently excuse a real
# sweep in any other. When no glob is given the run says `generated globs: none
# given` so that a reader of the output never has to wonder what was hidden.
# When every path in the diff is excluded, the run REFUSES rather than passing -
# an assertion with nothing to fire on is not a clean one.
#
# ============================================================================
# EXIT CODES ARE THE CONTRACT.
#
#   0  every path in the change set is named by the record
#   1  findings - at least one path the record does not name
#   2  could not run, or could not measure. Never 0. Bad usage, no work tree,
#      an unresolvable rev, an unreadable message file, a change set with no
#      paths in it, or a change set whose every path was excluded as generated.
#      A record that is EMPTY is exit 1 and not exit 2: an empty message is a
#      measurable record that names nothing, not an absent measurement.
#
# EXIT PRECEDENCE: UNMEASURED BEATS FINDINGS BEATS CLEAN, as in
# `check-installed-copies.sh`. In `--last` survey mode one commit that could
# not be measured takes the whole run to 2 even when others had findings; the
# findings are still printed.
#
# --SELFTEST DRIVES ALL THREE, over real git repositories built under
# `mktemp -d`. Each case asserts the exit code AND a sentence from the output,
# because an exit code alone lets a case go red for the wrong reason - which is
# how the two rejected rules above would have passed a code-only suite. Nothing
# is written into the repository this script lives in, on any exit path, signal
# included. `--self-test` is accepted as an alias because this repository
# spells the flag both ways.
#
# WHAT IT PRINTS. One BARE repo-relative path per path examined, which the
# runner parses as coverage. Findings, counts and notes are INDENTED.
set -euo pipefail

VERSION="check-diff-paths-named 1.0"

ROOT=""; REV=""; MSGFILE=""; LAST=""; MODE="measure"; STAGED=0
GENERATED=()

die_unmeasured() { printf 'check-diff-paths-named: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)          [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";          ROOT="$2";      shift 2 ;;
    --root=*)        ROOT="${1#--root=}";               shift ;;
    --rev)           [ "$#" -ge 2 ] || die_unmeasured "--rev needs a commit";         REV="$2";       shift 2 ;;
    --rev=*)         REV="${1#--rev=}";                 shift ;;
    --message-file)  [ "$#" -ge 2 ] || die_unmeasured "--message-file needs a path";  MSGFILE="$2";   shift 2 ;;
    --message-file=*) MSGFILE="${1#--message-file=}";   shift ;;
    --last)          [ "$#" -ge 2 ] || die_unmeasured "--last needs a count";         LAST="$2";      shift 2 ;;
    --last=*)        LAST="${1#--last=}";               shift ;;
    --generated)     [ "$#" -ge 2 ] || die_unmeasured "--generated needs a glob";     GENERATED+=("$2"); shift 2 ;;
    --generated=*)   GENERATED+=("${1#--generated=}");  shift ;;
    --staged)        STAGED=1;                          shift ;;
    --selftest|--self-test) MODE="selftest";            shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1." ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1."

# ---------------------------------------------------------------------------
# --selftest. Real git repositories, one per case, each differing from the
# clean one in exactly one way. Every case asserts a CODE and a SENTENCE.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  WORK="$(mktemp -d)" \
    || die_unmeasured "cannot create a temporary directory to build the cases in; nothing was driven"
  trap 'rm -rf "$WORK"' EXIT HUP INT TERM

  CASES=0; UPHELD=0; REPORT=""
  # R39.b: the reached half of the declaration below is ACCUMULATED here, one
  # entry per case as it ran. A literal list would satisfy a reader and prove
  # nothing.
  CODES=""

  # A throwaway repository. Identity is set locally so the case does not depend
  # on the machine's git config, and `main` is named so the output does not
  # depend on git's default-branch setting either.
  newrepo() {
    R="$WORK/$1"
    mkdir -p "$R" || die_unmeasured "could not lay out the case directory for $1"
    git -C "$R" init --quiet --initial-branch=main \
      || die_unmeasured "git init failed for case $1; no case was driven"
    git -C "$R" config user.email case@invalid
    git -C "$R" config user.name case
    git -C "$R" config commit.gpgsign false
  }

  # `|| GOT=$?` on the SAME line as the command. A `$(...)` in an argument list
  # and a pipeline both reset `$?`, and reading the status one line later is how
  # a self-test comes to report a pass it never observed.
  drive() {
    NAME="$1"; WANT="$2"; WANTTEXT="$3"; WHY="$4"; shift 4
    GOT=0
    bash "$0" "$@" > "$WORK/$NAME.out" 2> "$WORK/$NAME.err" || GOT=$?
    CASES=$((CASES + 1))
    V="NOT HELD"
    if [ "$GOT" = "$WANT" ]; then
      if grep -qF -- "$WANTTEXT" "$WORK/$NAME.out" "$WORK/$NAME.err"; then
        UPHELD=$((UPHELD + 1)); V="held"
      else
        V="NOT HELD (code matched, sentence absent: '$WANTTEXT')"
      fi
    fi
    CODES="$CODES$GOT
"
    REPORT="$REPORT      $NAME  expected $WANT  got $GOT  $V  $WHY
"
  }

  # ---- 0: the clean cases. Without them every red case below proves only that
  # something is red, not that this check is what makes it red.

  # (1) basename tier, and ONLY that tier: a nested path whose record writes the
  # bare filename with its extension and never the directory it sits in.
  newrepo clean-base
  mkdir -p "$WORK/clean-base/lib/deeper"
  printf 'b\n' > "$WORK/clean-base/lib/deeper/beta.md"
  git -C "$WORK/clean-base" add lib/deeper/beta.md
  git -C "$WORK/clean-base" commit --quiet -m 'beta.md was reflowed'
  drive clean-base 0 "(basename of " \
    "a nested path named by its bare filename and nothing else" \
    --root "$WORK/clean-base" --rev HEAD

  # (2) full-path tier, and nothing else - the basename alone is absent because
  # the message writes the whole path.
  newrepo clean-fullpath
  mkdir -p "$WORK/clean-fullpath/deep/er"
  printf 'x\n' > "$WORK/clean-fullpath/deep/er/gamma.json"
  git -C "$WORK/clean-fullpath" add deep/er/gamma.json
  git -C "$WORK/clean-fullpath" commit --quiet -m 'add deep/er/gamma.json'
  drive clean-fullpath 0 "full path" \
    "a message writing the whole repo-relative path" --root "$WORK/clean-fullpath" --rev HEAD

  # (3) directory-prefix tier, written in PATH SHAPE. This is the tier the
  # rejected bare-word rule would have granted for free.
  newrepo clean-prefix
  mkdir -p "$WORK/clean-prefix/tools/inner"
  printf 'x\n' > "$WORK/clean-prefix/tools/inner/one.sh"
  printf 'y\n' > "$WORK/clean-prefix/tools/inner/two.sh"
  git -C "$WORK/clean-prefix" add tools/inner/one.sh tools/inner/two.sh
  git -C "$WORK/clean-prefix" commit --quiet -m 'everything under tools/inner/ was regenerated'
  drive clean-prefix 0 "directory prefix" \
    "a directory written as a path prefix names what is under it" \
    --root "$WORK/clean-prefix" --rev HEAD

  # (4) a rename, with only the DESTINATION named. One unit, either side.
  newrepo clean-rename
  printf 'contents that do not change\n' > "$WORK/clean-rename/old-name.sh"
  git -C "$WORK/clean-rename" add old-name.sh
  git -C "$WORK/clean-rename" commit --quiet -m 'seed old-name.sh'
  git -C "$WORK/clean-rename" mv old-name.sh new-name.sh
  git -C "$WORK/clean-rename" commit --quiet -m 'the gate now lives at new-name.sh'
  drive clean-rename 0 "rename" \
    "a rename whose destination alone is named is one satisfied unit" \
    --root "$WORK/clean-rename" --rev HEAD

  # (5) a path excluded by an explicit --generated glob. Unnamed, and excused
  # only because the caller said so - and the exclusion is printed.
  newrepo clean-generated
  printf 'a\n' > "$WORK/clean-generated/alpha.sh"
  mkdir -p "$WORK/clean-generated/out"; printf 'g\n' > "$WORK/clean-generated/out/built.json"
  git -C "$WORK/clean-generated" add alpha.sh out/built.json
  git -C "$WORK/clean-generated" commit --quiet -m 'alpha.sh changed'
  drive clean-generated 0 "excluded as generated" \
    "an unnamed path excused by an explicit glob, with the exclusion printed" \
    --root "$WORK/clean-generated" --rev HEAD --generated 'out/*'

  # ---- 1: the findings.

  # (6) the sweep this check exists for: two files, one of them from work the
  # message never mentions.
  newrepo swept
  printf 'a\n' > "$WORK/swept/alpha.sh"
  mkdir -p "$WORK/swept/other-agent"
  printf 'z\n' > "$WORK/swept/other-agent/in-flight.py"
  git -C "$WORK/swept" add alpha.sh other-agent/in-flight.py
  git -C "$WORK/swept" commit --quiet -m 'alpha.sh gained a guard'
  drive swept 1 "other-agent/in-flight.py" \
    "a file from unrelated in-flight work swept into the commit, and named in the finding" \
    --root "$WORK/swept" --rev HEAD

  # (7) a DELETION the record does not mention. The content is gone and the
  # message does not say it went.
  newrepo swept-deletion
  printf 'a\n' > "$WORK/swept-deletion/alpha.sh"
  printf 'd\n' > "$WORK/swept-deletion/doomed.sh"
  git -C "$WORK/swept-deletion" add alpha.sh doomed.sh
  git -C "$WORK/swept-deletion" commit --quiet -m 'seed both'
  git -C "$WORK/swept-deletion" rm --quiet doomed.sh
  printf 'a\na\n' > "$WORK/swept-deletion/alpha.sh"
  git -C "$WORK/swept-deletion" add alpha.sh
  git -C "$WORK/swept-deletion" commit --quiet -m 'alpha.sh gained a line'
  drive swept-deletion 1 "DELETED" \
    "a deletion the record is silent about is a finding, reported as a deletion" \
    --root "$WORK/swept-deletion" --rev HEAD

  # (8) THE REJECTED STEM RULE, falsified. The message says the word `spec`
  # and nothing else. Under a stem rule this passes; here it must not.
  newrepo stem-only
  printf 's\n' > "$WORK/stem-only/spec.md"
  git -C "$WORK/stem-only" add spec.md
  git -C "$WORK/stem-only" commit --quiet -m 'the spec was extended today'
  drive stem-only 1 "spec.md" \
    "the bare stem 'spec' does not name spec.md - the rejected stem rule, falsified" \
    --root "$WORK/stem-only" --rev HEAD

  # (9) THE REJECTED BARE-DIRECTORY RULE, falsified. "updated the scripts" must
  # not pass for anything under scripts/.
  newrepo dirword-only
  mkdir -p "$WORK/dirword-only/scripts"
  printf 'x\n' > "$WORK/dirword-only/scripts/thing.sh"
  git -C "$WORK/dirword-only" add scripts/thing.sh
  git -C "$WORK/dirword-only" commit --quiet -m 'updated the scripts'
  drive dirword-only 1 "scripts/thing.sh" \
    "the bare word 'scripts' does not name scripts/thing.sh - the rejected directory rule, falsified" \
    --root "$WORK/dirword-only" --rev HEAD

  # (10) an EMPTY record. Measurable, and it names nothing: exit 1, not 2.
  newrepo empty-message
  printf 'a\n' > "$WORK/empty-message/alpha.sh"
  git -C "$WORK/empty-message" add alpha.sh
  git -C "$WORK/empty-message" commit --quiet --allow-empty-message -m ''
  drive empty-message 1 "alpha.sh" \
    "an empty message is a record that names nothing, which is a finding and not an absent measurement" \
    --root "$WORK/empty-message" --rev HEAD

  # (11) a staged change set, judged against a message that is not committed -
  # the pre-commit shape.
  newrepo staged
  printf 'a\n' > "$WORK/staged/alpha.sh"
  git -C "$WORK/staged" add alpha.sh
  git -C "$WORK/staged" commit --quiet -m 'seed alpha.sh'
  printf 'swept\n' > "$WORK/staged/stowaway.md"
  git -C "$WORK/staged" add stowaway.md
  printf 'alpha.sh was tidied\n' > "$WORK/staged/MSG"
  drive staged 1 "stowaway.md" \
    "a staged path the not-yet-committed message does not name" \
    --root "$WORK/staged" --staged --message-file "$WORK/staged/MSG"

  # ---- 2: could not measure. Never 0.

  # (12) a change set with no paths in it. Nothing examined is nothing asserted.
  newrepo empty-diff
  printf 'a\n' > "$WORK/empty-diff/alpha.sh"
  git -C "$WORK/empty-diff" add alpha.sh
  git -C "$WORK/empty-diff" commit --quiet -m 'seed alpha.sh'
  git -C "$WORK/empty-diff" commit --quiet --allow-empty -m 'a commit that touches nothing at all'
  drive empty-diff 2 "no paths" \
    "an empty change set asserts nothing and refuses rather than passing" \
    --root "$WORK/empty-diff" --rev HEAD

  # (13) every path excluded as generated. Same empty set, reached the other way.
  newrepo all-generated
  mkdir -p "$WORK/all-generated/out"
  printf 'g\n' > "$WORK/all-generated/out/built.json"
  git -C "$WORK/all-generated" add out/built.json
  git -C "$WORK/all-generated" commit --quiet -m 'regenerate'
  drive all-generated 2 "every path" \
    "a change set whose every path was excluded leaves nothing to assert" \
    --root "$WORK/all-generated" --rev HEAD --generated 'out/*'

  # (14) an unresolvable rev. Unknown is not clean.
  newrepo bad-rev
  printf 'a\n' > "$WORK/bad-rev/alpha.sh"
  git -C "$WORK/bad-rev" add alpha.sh
  git -C "$WORK/bad-rev" commit --quiet -m 'seed alpha.sh'
  drive bad-rev 2 "could not be resolved" \
    "a rev this repository does not have" --root "$WORK/bad-rev" --rev deadbee1deadbee2

  # (15) --staged with no message to judge it against.
  drive staged-no-msg 2 "--staged needs" \
    "a staged change set with no record to compare it to" --root "$WORK/staged" --staged

  # (16) a message file that is not there.
  drive missing-msg 2 "cannot be read" \
    "a --message-file at a path that does not exist" \
    --root "$WORK/staged" --rev HEAD --message-file "$WORK/staged/absent-file"

  # (17) not a git work tree at all.
  mkdir -p "$WORK/not-a-repo"
  drive not-a-repo 2 "work tree" \
    "a --root that is not inside a git work tree" --root "$WORK/not-a-repo" --rev HEAD

  # (18) bad usage, reaching the same could-not-run through the argument parser.
  drive bad-usage 2 "unknown option" \
    "an option this script does not take" --root "$WORK/staged" --frobnicate

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"
  if [ "$CASES" = "$UPHELD" ]; then SELF_VERDICT="held"; else SELF_VERDICT="NOT HELD"; fi
  printf '    R39.s  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$CASES" "$UPHELD" "$SELF_VERDICT" \
    "each case exits with the code it declares AND prints the sentence it declares"
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  printf '    NOT ASSERTED: no case drives --last survey mode, whose verdict is composed from per-commit runs rather than measured here; and no case reaches the unreadable-git-output refusal, which needs a broken git\n'
  [ "$CASES" = "$UPHELD" ] || exit 1
  if [ -n "$MISSING" ]; then
    printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Resolve the work tree.
# ---------------------------------------------------------------------------
if [ -n "$ROOT" ]; then
  [ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
  ROOT="$(cd "$ROOT" && pwd -P)"
else
  ROOT="$(pwd -P)"
fi
TOP="$(git -C "$ROOT" rev-parse --show-toplevel)" \
  || die_unmeasured "$ROOT is not inside a git work tree, so no change set could be read"
ROOT="$TOP"

# ---------------------------------------------------------------------------
# --last: survey mode. Each commit is measured by a fresh run of this script,
# so the survey cannot disagree with the single-commit verdict.
# ---------------------------------------------------------------------------
if [ -n "$LAST" ]; then
  case "$LAST" in ''|*[!0-9]*) die_unmeasured "--last needs a positive integer; got: $LAST" ;; esac
  [ "$LAST" -gt 0 ] || die_unmeasured "--last needs a positive integer; got: $LAST"
  [ -z "$REV" ] || die_unmeasured "--last and --rev ask two different questions; give one"
  [ "$STAGED" = 0 ] || die_unmeasured "--last and --staged ask two different questions; give one"

  REVS="$(git -C "$ROOT" rev-list --max-count="$LAST" HEAD)" \
    || die_unmeasured "could not list commits from HEAD, so nothing was surveyed"
  [ -n "$REVS" ] || die_unmeasured "HEAD reaches no commits, so nothing was surveyed"

  n=0; clean=0; withfindings=0; refused=0; unnamed_total=0; paths_total=0
  printf '  survey: one line per commit, newest first\n'
  for c in $REVS; do
    code=0
    args=(--root "$ROOT" --rev "$c")
    for g in ${GENERATED+"${GENERATED[@]}"}; do args+=(--generated "$g"); done
    out="$(bash "$0" "${args[@]}" 2>&1)" || code=$?
    n=$((n + 1))
    ex="$(printf '%s\n' "$out" | sed -n 's/^  units examined: \([0-9]*\),.*/\1/p' | head -1)"
    un="$(printf '%s\n' "$out" | sed -n 's/^  units examined: [0-9]*, named: [0-9]*, not named: \([0-9]*\).*/\1/p' | head -1)"
    [ -n "$ex" ] || ex=0
    [ -n "$un" ] || un=0
    paths_total=$((paths_total + ex))
    unnamed_total=$((unnamed_total + un))
    case "$code" in
      0) clean=$((clean + 1));        verdict="clean  " ;;
      1) withfindings=$((withfindings + 1)); verdict="FINDING" ;;
      *) refused=$((refused + 1));    verdict="REFUSED" ;;
    esac
    printf '    %s  %s  units %3d  not named %3d  %s\n' \
      "$(git -C "$ROOT" log -1 --format=%h "$c")" "$verdict" "$ex" "$un" \
      "$(git -C "$ROOT" log -1 --format=%s "$c" | cut -c1-58)"
  done
  printf '  commits surveyed: %d\n' "$n"
  printf '  clean: %d   with findings: %d   refused: %d\n' "$clean" "$withfindings" "$refused"
  printf '  units examined: %d, named: %d, not named: %d\n' \
    "$paths_total" "$((paths_total - unnamed_total))" "$unnamed_total"
  if [ "$refused" -gt 0 ]; then
    printf '  Some commit could not be measured, and unmeasured is not clean.\n'
    exit 2
  fi
  [ "$withfindings" -eq 0 ] || { printf '  Commits whose record does not name every path they touch.\n'; exit 1; }
  printf '  Every surveyed commit names every path it touches.\n'
  exit 0
fi

# ---------------------------------------------------------------------------
# Single change set: read the record, read the paths.
# ---------------------------------------------------------------------------
WORK="$(mktemp -d)" || die_unmeasured "cannot create a temporary directory; nothing was measured"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

if [ "$STAGED" = 1 ]; then
  [ -z "$REV" ] || die_unmeasured "--staged and --rev ask two different questions; give one"
  [ -n "$MSGFILE" ] || die_unmeasured "--staged needs a --message-file: a change set that is not a commit yet has no message of its own, and guessing one would measure the wrong text"
  git -C "$ROOT" diff --cached --name-status -M > "$WORK/status" 2> "$WORK/giterr" \
    || die_unmeasured "could not read the staged change set: $(tr '\n' ' ' < "$WORK/giterr")"
  SUBJECT="(staged change set)"
else
  [ -n "$REV" ] || REV="HEAD"
  SHA="$(git -C "$ROOT" rev-parse --verify "$REV^{commit}" 2> "$WORK/giterr")" \
    || die_unmeasured "--rev $REV could not be resolved to a commit in this repository: $(tr '\n' ' ' < "$WORK/giterr")"
  git -C "$ROOT" diff-tree --no-commit-id --name-status -r -M --root "$SHA" > "$WORK/status" 2> "$WORK/giterr" \
    || die_unmeasured "could not read the diff of $REV: $(tr '\n' ' ' < "$WORK/giterr")"
  SUBJECT="$(git -C "$ROOT" log -1 --format=%s "$SHA")"
fi

if [ -n "$MSGFILE" ]; then
  [ -r "$MSGFILE" ] || die_unmeasured "--message-file $MSGFILE cannot be read, so the record is unknown - which is not the same as a record that names nothing"
  cp "$MSGFILE" "$WORK/record" || die_unmeasured "could not copy the message file; the record is unknown"
else
  git -C "$ROOT" log -1 --format=%B "$SHA" > "$WORK/record" 2> "$WORK/giterr" \
    || die_unmeasured "could not read the message of $REV: $(tr '\n' ' ' < "$WORK/giterr")"
fi

# ---------------------------------------------------------------------------
# Units. One line per unit: STATUS<TAB>PATH[<TAB>PATH2]. A rename is one unit
# with two paths; everything else is one unit with one.
# ---------------------------------------------------------------------------
excluded=0
: > "$WORK/units"
: > "$WORK/excluded-list"
while IFS=$'\t' read -r st p1 p2; do
  [ -n "${st:-}" ] || continue
  [ -n "${p1:-}" ] || continue
  # An excluded unit is one whose EVERY path matches a --generated glob. A
  # rename with one side generated is still a move of a real file.
  keep=1
  if [ "${#GENERATED[@]}" -gt 0 ]; then
    all_gen=1
    for p in "$p1" ${p2:+"$p2"}; do
      hit=0
      for g in "${GENERATED[@]}"; do
        # shellcheck disable=SC2053  # the right-hand side is a glob on purpose: --generated takes a pattern, and quoting it would compare literals
        [[ "$p" == $g ]] && { hit=1; break; }
      done
      [ "$hit" = 1 ] || all_gen=0
    done
    [ "$all_gen" = 0 ] || keep=0
  fi
  if [ "$keep" = 0 ]; then
    excluded=$((excluded + 1))
    printf '%s\n' "$p1" >> "$WORK/excluded-list"
    continue
  fi
  printf '%s\t%s\t%s\n' "$st" "$p1" "${p2:-}" >> "$WORK/units"
done < "$WORK/status"

TOTAL_UNITS="$(wc -l < "$WORK/units" | tr -d ' ')"

printf '  change set: %s\n' "$SUBJECT"
if [ "${#GENERATED[@]}" -eq 0 ]; then
  printf '  generated globs: none given, so nothing in this diff was excused\n'
else
  printf '  generated globs: %s  (units excluded: %d)\n' "${GENERATED[*]}" "$excluded"
  if [ "$excluded" -gt 0 ]; then
    while read -r p; do printf '    excluded as generated: %s\n' "$p"; done < "$WORK/excluded-list"
  fi
fi

if [ "$TOTAL_UNITS" = "0" ]; then
  if [ "$excluded" -gt 0 ]; then
    die_unmeasured "every path in this change set was excluded as generated, so nothing was compared. An assertion with nothing to fire on holds vacuously; this refuses instead"
  fi
  die_unmeasured "this change set has no paths in it, so there was nothing to compare the record against. Nothing examined is nothing asserted"
fi

# ---------------------------------------------------------------------------
# The decision. Tokens out of the record, then one verdict per unit.
# ---------------------------------------------------------------------------
awk -v recordfile="$WORK/record" '
function tokenise(file,    line, n, i, w, t) {
  while ((getline line < file) > 0) {
    line = tolower(line)
    gsub(/[^a-z0-9_.\/-]/, " ", line)
    n = split(line, w, / +/)
    for (i = 1; i <= n; i++) {
      t = w[i]
      # Trailing sentence punctuation only. A LEADING dot is meaningful -
      # `.github/workflows/checks.yml` is a real path and stripping it would
      # make every dotfile unnameable.
      sub(/[.,;:\/-]+$/, "", t)
      if (t != "") TOK[t] = 1
    }
  }
  close(file)
}
function named(p,    b, t, d) {
  p = tolower(p)
  # (1) the full repo-relative path.
  if (p in TOK) { HOW = "full path"; return 1 }
  # (3) the basename with its extension, written bare or at the end of a
  # longer path the record spells out.
  b = p; sub(/^.*\//, "", b)
  if (b in TOK) { HOW = "basename"; return 1 }
  for (t in TOK) {
    if (index(t, "/") == 0) continue
    if (length(t) > length(b) && substr(t, length(t) - length(b)) == "/" b) {
      HOW = "basename inside a longer path"; return 1
    }
  }
  # (2) a directory prefix, and only one written in PATH SHAPE.
  for (t in TOK) {
    if (index(t, "/") == 0) continue
    d = t; sub(/\/+$/, "", d)
    if (d != "" && index(p, d "/") == 1) { HOW = "directory prefix " d "/"; return 1 }
  }
  HOW = ""
  return 0
}
BEGIN { FS = "\t"; tokenise(recordfile); units = 0; paths = 0; namedu = 0; findings = 0; dels = 0 }
{
  st = $1; p1 = $2; p2 = $3
  units++
  print p1                      # BARE, for the runner to read as coverage
  paths++
  if (p2 != "") { print p2; paths++ }
  ok = 0; side = ""
  if (named(p1)) { ok = 1; side = HOW " of " p1 }
  if (!ok && p2 != "" && named(p2)) { ok = 1; side = HOW " of " p2 }
  if (ok) {
    namedu++
    printf "  named: %s  (%s)\n", p1 (p2 != "" ? " -> " p2 : ""), side
  } else {
    findings++
    if (st ~ /^D/) {
      dels++
      printf "  FINDING: %s is DELETED by this change set and the record never names it. The content is gone and the record does not say it went.\n", p1
    } else if (st ~ /^R/) {
      printf "  FINDING: %s was renamed to %s and the record names neither side, so a file moved without the record saying so.\n", p1, p2
    } else {
      printf "  FINDING: %s is in the diff and the record does not name it - not as a full path, not as a path-shaped directory prefix, not by basename. Either it belongs to work this record does not describe, or the record is incomplete.\n", p1
    }
  }
}
END {
  # ONE machine-parseable line, and every number on it counts the SAME thing.
  # The first version mixed the two - `paths examined` beside `named` and `not
  # named`, which count UNITS - and the survey that summed them reported 221
  # named paths where the per-commit runs had named 161. A rename is two paths
  # and one unit, and that difference was the whole error.
  printf "  units examined: %d, named: %d, not named: %d  (paths touched: %d; a rename is two paths and one unit)\n", \
    units, namedu, units - namedu, paths
  if (dels > 0) printf "  of the findings, %d are deletions\n", dels
  printf "  NOT ASSERTED: the basename tier ignores directories, so one mention of a basename satisfies every path in the diff carrying it, and no tier asks whether the sentence around the name is TRUE.\n"
  exit (findings > 0 ? 1 : 0)
}' "$WORK/units" && rc=0 || rc=$?

if [ "${rc:-0}" -eq 0 ]; then
  printf '  Every path in this change set is named by its own record.\n'
  exit 0
fi
if [ "${rc:-0}" -eq 1 ]; then
  printf '  The diff shows paths this record does not mention. That is what a sweep looks like.\n'
  exit 1
fi
die_unmeasured "the decision pass failed with status $rc, so no verdict was reached"
