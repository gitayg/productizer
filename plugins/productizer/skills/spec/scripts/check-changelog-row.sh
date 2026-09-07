#!/usr/bin/env bash
# check-changelog-row.sh [--version] [--help] [--root DIR] [--max-versions N]
#                        [--selftest|--self-test]
#
# Asserts R32: WHEN A CLASSIFICATION CHANGES THE SPEC, THE LIFECYCLE SHALL
# RECORD IT IN THE SPEC'S CHANGE LOG.
#
# R32 is the narrowed replacement for R7, and the narrowing is the whole
# problem this check has to solve. R7 said EVERY classification earns a
# change-log row. The `## Change log` section defines itself as ONE ROW PER
# COMMIT TO THIS FILE - so a classification that merged nothing was being
# asked for a row in a table keyed on an event that never happened. Three
# classifications on one day merged nothing, wrote nothing, and were right to.
# R32 keeps only the half that is satisfiable: the classifications that
# actually CHANGED the spec.
#
# So this check has a TRIGGER and a CONSEQUENCE, and the trigger is the hard
# half. The consequence - "is there a row naming it" - is a table lookup. The
# trigger - "did a classification change the spec" - is a judgement, and the
# whole value of the check is whether that judgement is made from evidence or
# from a guess.
#
# ============================================================================
# WHAT IS COUNTED AS "A CLASSIFICATION CHANGED THE SPEC", AND WHY
# ============================================================================
#
# A commit that touched the spec is counted as a spec-changing classification
# when, compared against THE SPEC AT THE PREVIOUS COMMIT THAT TOUCHED IT, any
# of these three STRUCTURAL facts is true:
#
#   (a) AN ID APPEARED.  A requirement id is defined at this commit and was
#       not defined at the one before. Nothing but a merged classification
#       adds an id - `references/rulings.md` is explicit that "an id in the
#       spec is a merge, whatever the surrounding prose says".
#
#   (b) A REQUIREMENT WAS REPLACED.  An id that was `active` at the previous
#       commit is `superseded` or `withdrawn` at this one. That is a refine or
#       a contradiction ruling landing; a typo fix cannot produce it.
#
#   (c) THE COUNTER MOVED.  `Next requirement id` is strictly higher than at
#       the previous commit. Ids are allocated from it and it never rewinds,
#       so a move is an allocation.
#
# All three are read through `spec-requirements.sh`, the parser
# `check-superseded-text.sh` and `check-pending-ruling-scope.sh` already read
# the spec through, and from the same `git log -- <spec>` walk those two
# checks already do. A third private notion of what a requirement IS would go
# green on its own terms on the day it disagreed with theirs.
#
# WHAT IS DELIBERATELY *NOT* COUNTED - THIS IS THE ANTI-CRY-WOLF HALF
#
# A spec commit that only edits WORDS is NOT a classification changing the
# spec, and no row is demanded for it. Typo fixes, a reworded acceptance row,
# a reflowed paragraph, a new note under an existing requirement, a rewritten
# section of prose: all of them leave every id, every status and the counter
# exactly where they were, and all of them are excluded.
#
# This is a decision, not an oversight, and it costs something. A REFINE that
# rewrites a requirement's sentence and keeps the id IS a classification
# changing the spec, and this check cannot see it - because from the outside
# it is character-for-character the same event as fixing a typo in that
# sentence. There is no evidence in the repository that separates them. A
# check that demanded a change-log row for every edited character would go red
# on the next typo fix, and a check that goes red on typo fixes gets switched
# off - after which it detects the real omissions it was built for at exactly
# the same rate as no check at all. Measured on this repository at the time of
# writing: 11 spec commits after the founding one, 4 structural, 7 word-only.
# A text-diff trigger would have demanded 11 rows and been wrong 7 times.
#
# That gap is REPORTED, not hidden: the run prints every spec commit it
# excluded and why, so a reader can disagree with the LIST rather than with
# the verdict.
#
# THE FOUNDING COMMIT IS EXEMPT. The oldest reachable commit that holds the
# spec introduced every id in it at once; those ids were not added by a
# classification, they are what the lifecycle started from. Demanding rows for
# them would go permanently red against this repository's own correct spec -
# R1 to R22 arrived in one commit and correctly have no rows. Same exemption,
# same reason, as `check-spec-integrity.sh`'s R8.2.
#
# ============================================================================
# THE FOUR ASSERTIONS - EACH NAMED, EACH COUNTED WHERE ITS OWN LOOP RUNS
# ============================================================================
#
# `examined` and `upheld` are computed per assertion from the items THAT
# assertion looked at. Neither is derived from a shared `ok` flag: a check in
# this repo once printed `upheld: 0` above six lines saying `held:`, which is
# what a single flag buys you.
#
#   R32.1  recorded-in-the-change-log
#          Every spec-changing commit has at least one row in the change log
#          recording at least one of the ids that moved in it AS THE KIND OF
#          MOVE IT WAS - an added id under `Added`, a replaced id on the left
#          of `Superseded / withdrawn`. This is R32's consequence at the
#          granularity R32 states it: the change was recorded, or it was not.
#
#          "Named anywhere in the table" was the first version of this test and
#          IT WAS WRONG - measured, not argued. On a fixture whose founding row
#          reads `| ... | R2 | - | - |`, a later commit that superseded R2 and
#          added R3 and wrote NO ROW AT ALL came back green: the founding row
#          named R2, R2 was one of the moved ids, and the match was made
#          against a record of a different event. Every id in a spec is named
#          in the log eventually, so `named anywhere` converges on `always
#          satisfied`. The case is `unrecorded-row` in the fixture.
#
#   R32.2  addition-recorded-as-an-addition
#          Every id that APPEARED at a spec-changing commit is named in the
#          `Added` column of some row. A row that mentions the id only in its
#          summary prose records a sentence, not a change.
#
#   R32.3  supersession-recorded-as-a-supersession
#          Every id that went active -> superseded/withdrawn at a spec-changing
#          commit is named on the LEFT of the `Superseded / withdrawn` column -
#          the `R7` in `R7 -> R32`. The right-hand side is the replacement, and
#          a row that lists a replaced id only as a replacement records the
#          opposite of what happened.
#
#   R32.4  recorded-in-the-same-commit
#          The row was already in the change log AT the commit that made the
#          change - not added afterwards. `references/rulings.md` requires the
#          spec change and its record in ONE commit, "because a spec that has
#          been changed and a ruling that has not yet been written are two
#          files disagreeing about what was agreed". Asserted separately from
#          R32.1 on purpose: a row added one commit late fails R32.4 and
#          upholds R32.1, and the finding says which of the two happened.
#          Proven that way - the row for an added id was committed one commit
#          after the id, and R32.4 went red alone at 4 of 5.
#
# R32.1 to R32.3 read the change log OF THE SPEC AS IT STANDS TODAY. R32.4
# applies the same column rule to the change log at each historical commit.
#
# THE FIXTURE IS THE FALSIFICATION, COMMITTED. `fixtures/changelog-row/`
# carries five spec versions differing by one thing each and a `selftest.sh`
# that builds throwaway git histories from them: a recorded classification is
# green, THE SAME HISTORY MINUS ITS ONE ROW is red on all four assertions, a
# reworded requirement is not demanded, and a one-commit history, a
# counter-only commit and a shallow clone are each refused rather than passed.
# Run it before trusting a green run here.
#
#   R32.5  refine-recorded-as-a-refine - REPORTED, NEVER DEMANDED
#          A requirement whose id and status are unchanged and whose SENTENCE
#          changed is a refine landing - and it is character-for-character the
#          same event as fixing a typo in that sentence. 1.0 left it out
#          entirely. 2.0 detects it, lists it by location, and calls it
#          RESOLVED when a `Refined` entry names it at that commit and
#          UNRESOLVED when nothing does. UNRESOLVED does not set the exit code.
#
#          THE DECISION NOT TO DEMAND IT WAS MEASURED, not argued. This
#          repository's entire spec history - 14 versions, 13 commits after the
#          founding one - holds ZERO in-place requirement rewrites. The 8
#          word-only commits changed acceptance rows and prose, never a
#          requirement definition. So the repository carries no evidence at all
#          about how often such a rewrite is a refine and how often it is a
#          typo: a demand would have fired 0 times, caught 0 refines and cried
#          wolf 0 times, and a rule with no observations behind it is a guess.
#          Meanwhile the ONLY in-place rewrite committed anywhere here is the
#          fixture `spec/2-word-only.md`, which exists to be the anti-cry-wolf
#          control - 1 of 1 observed rewrites is a rewording. Demanding a row
#          there would demand one for a typo, which is what got the text-diff
#          trigger rejected in the first place.
#
#          WHAT WOULD CLOSE IT is named in the report rather than guessed at:
#          an author writing the id into `Refined`, which R32.5 then upholds
#          (the fixture proves both halves), or a classification record whose
#          `Classification` is `refine`, joined to the merge commit. The second
#          is the upstream fix and it does not exist to be read today.
#
# ONLY THE `Added`, `Refined` AND `Superseded / withdrawn` COLUMNS ARE PARSED,
# never `Summary`. Summary is prose, ids are cited inside it in passing, and
# an id matched there would let any row satisfy any commit. `Refined` is read
# for the undefined-id probe and, since 2.0, for R32.5 - which reports against
# it and never demands it, for the measured reason above.
#
# THE COLUMNS ARE LOCATED BY HEADER NAME, never by position. A column inserted
# tomorrow would otherwise shift every cell silently, and the check would go on
# reading `Added` out of whatever now sits fourth.
#
# THE TEMPLATE ROW IS SKIPPED - and skipping it is load-bearing rather than
# cosmetic. The committed table carries a placeholder row whose superseded
# cell reads `R7 -> R41`. Read as a real row it satisfies R32.3 for R7 on its
# own, which is the exact id this requirement was born from. A row whose date
# cell is a `<placeholder>` is not a record of anything.
#
# ============================================================================
# GUARDING THE PREMISE - EVERY ONE OF THESE IS EXIT 2, NEVER A PASS
# ============================================================================
#
#   no git work tree, or --root outside its own top level
#   the spec is missing, unreadable, or not tracked
#   `spec-requirements.sh` is not beside this script
#   the spec holds no requirement definitions
#   THE CLONE IS SHALLOW. It reaches the spec and reaches nothing before it,
#     so no commit can be compared to its predecessor and "every change was
#     recorded" would be a statement about one commit dressed as a statement
#     about history. A green run there is a green that measured nothing.
#   fewer than two reachable spec versions - there is only the founding
#     commit, and nothing has ever been changed
#   more spec commits than --max-versions - a truncated walk cannot tell an id
#     that was never there from one added before the window
#   no `## Change log` section, or a change log that yields no id at all
#   NO SPEC-CHANGING COMMIT IN THE WHOLE WALK, and no counter-only one
#     either. Nothing was asserted. "0 unrecorded changes out of 0 changes" is
#     an assertion whose loop never executed, and this repository has already
#     shipped one of those. When there IS a counter-only commit the run does
#     not take this exit - it exits 2 through the unmeasured path below, which
#     carries the true reason instead of claiming no classification happened.
#   A COMMIT WHERE ONLY THE COUNTER MOVED. Signal (c) fired, (a) and (b) did
#     not, so there is no id to look for in any column. That commit has no
#     verdict and the run says so rather than passing it.
#
# NEGATIVES ARE PROBED, NOT ASSUMED. Before "every change was recorded" is
# reported, the change-log parse must yield at least one id, and every id it
# yields must be defined in the spec today. An id in the log that the spec has
# never heard of means a placeholder row was read as a real one, and every
# count in the run is then inflated by a table nobody wrote.
#
# WHAT IT PRINTS. One BARE repo-relative path per line for every file
# examined, unindented and canonicalised so no `..` appears - the runner reads
# those as coverage. The spec, then every historical version of it that was
# read, as `<path>@<short sha>`. A history walk is exactly where hollowness
# hides: a loop over commits that never executes prints nothing and succeeds.
#
# COST. Every commit that touched the SPEC is read and parsed once - linear in
# the spec's own history, not the repository's, and not in the number of
# requirements. Twelve commits here.
#
# KNOWN LIMITATIONS, written down rather than discovered later:
#   - A refine that rewrites a requirement in place, keeping its id, is
#     DETECTED since 2.0 and still not DEMANDED. See R32.5: it is
#     indistinguishable from a typo fix by any evidence in the repository, so
#     the run names it and renders no verdict on which it was. An unresolved
#     rewrite is a real gap and the report is where it is admitted, not hidden.
#   - A classification that merged nothing is correct by construction under
#     R32 and is not looked for. It leaves no commit to the spec, so there is
#     nothing to find; its record lives where the intent lives - a `D` ruling
#     for a contradiction, the cited id for a duplicate.
#   - Attribution is by ID, never by date. The change-log dates in this
#     repository already disagree with the commit dates by a day, and a row is
#     a record of a change, not of a calendar.
#   - A requirement moved between spec files in a split spec reads as
#     appeared/disappeared here; this check reads one spec path.
#   - A rewritten history (rebase, filter-branch) is trusted as given.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  clean
#   1  findings - a spec-changing classification with no row recording it
#   2  could not run, or could not measure. Never 0.
#
# --SELFTEST RUNS THE COMMITTED FALSIFICATION SUITE, and does not reimplement
# it. R39 asks every check tool to carry a self-test that reaches each exit
# code it can return; this one has had that suite since 2.0, in
# `fixtures/changelog-row/selftest.sh`, and it drives all three codes over
# throwaway git histories built from the six spec versions beside it. A second
# corpus written into this file would be a second notion of what these
# assertions mean, and the two would disagree the day one of them was edited.
# The flag therefore delegates, prints each case the suite drove, and takes the
# suite's own verdict as its own: 0 every case produced the verdict it should,
# 1 a case did not, 2 the suite could not be run at all. `--self-test` is
# accepted as an alias, because this repository spells the flag both ways and a
# tool that answers only one spelling has a self-test the next caller cannot
# find.
#
# R32.5 SETS NONE OF THEM. An unresolved in-place rewrite is printed and
# counted and leaves the exit code exactly where the other four assertions put
# it, because this check cannot tell which of two events it saw and an exit
# code is a verdict.
#
# EXIT PRECEDENCE: UNMEASURED BEATS FINDINGS BEATS CLEAN, as in
# `check-superseded-text.sh`. A run that could not reach a verdict on some
# commit exits 2 even when it also found a real omission; the findings are
# still printed. 1 is a complete verdict and such a run does not have one.
set -euo pipefail

VERSION="check-changelog-row 2.0"
ROOT=""
SELFTEST=""
MAX_VERSIONS=400

usage() {
  printf 'usage: check-changelog-row.sh [--version] [--help] [--root DIR] [--max-versions N]\n'
  printf '  --root DIR       the repo work tree to examine. Defaults to the git\n'
  printf '                   top level, never to the working directory.\n'
  printf '  --max-versions N refuse rather than truncate a spec history longer\n'
  printf '                   than N commits. Default 400.\n'
  printf '  --selftest       run the committed falsification suite beside this\n'
  printf '                   script and report each case it drove.\n'
}

die_unmeasured() { printf 'check-changelog-row: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)
      [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --max-versions)
      [ "$#" -ge 2 ] || die_unmeasured "--max-versions needs a number"
      MAX_VERSIONS="$2"; shift 2 ;;
    --max-versions=*) MAX_VERSIONS="${1#--max-versions=}"; shift ;;
    --selftest|--self-test) SELFTEST=1; shift ;;
    -*) printf 'check-changelog-row: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'check-changelog-row: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$MAX_VERSIONS" in
  ''|*[!0-9]*) die_unmeasured "--max-versions must be a whole number, got '$MAX_VERSIONS'" ;;
esac
[ "$MAX_VERSIONS" -ge 1 ] || die_unmeasured "--max-versions must be at least 1"


# --------------------------------------------------------------- --selftest
#
# Delegated to the committed suite for the reason in the header: a second
# corpus here would be a second notion of what R32.1 to R32.5 mean. This block
# locates the suite, runs it against THIS file, prints every case it drove with
# the exit code that case observed, and reports which of this check's three
# exit codes the corpus actually reached - the half of R39 that a self-test
# which merely exists does not answer.
if [ -n "$SELFTEST" ]; then
  SUITEDIR="$(cd "$(dirname "$0")" && pwd -P)"
  SUITE="$SUITEDIR/../fixtures/changelog-row/selftest.sh"
  [ -f "$SUITE" ] && [ -r "$SUITE" ] ||
    die_unmeasured "the committed falsification suite is not at fixtures/changelog-row/selftest.sh beside this script. There is nothing to falsify with, which is unmeasured and not a self-test that passed."

  SELF_TMP="$(mktemp -d)" ||
    die_unmeasured "cannot create a temporary directory to capture the suite's output in"
  trap 'rm -rf "$SELF_TMP"' EXIT HUP INT TERM

  printf '    selftest: %s, driven by the committed suite in fixtures/changelog-row/\n' "$VERSION"

  SUITE_RC=0
  bash "$SUITE" --check "$0" > "$SELF_TMP/suite.out" 2> "$SELF_TMP/suite.err" || SUITE_RC=$?

  # One line per case, as the suite printed it. Each already names the case,
  # the exit code observed, and - where a case did not hold - the code it
  # wanted instead.
  sed 's/^/      /' < "$SELF_TMP/suite.out"
  if [ -s "$SELF_TMP/suite.err" ]; then
    sed 's/^/      /' < "$SELF_TMP/suite.err"
  fi

  # The exit codes the corpus actually reached, read off the case lines rather
  # than asserted in prose. R39 asks for each code the tool can return, and a
  # suite that only ever drove one of the three would be a suite that exists
  # without covering the contract.
  # `sed -E`, not a BRE with `\|`: BSD sed does not support alternation in a
  # basic regular expression, and the pattern silently matches nothing there -
  # which prints `examined 0` and reads exactly like a corpus that drove
  # nothing. Measured on this machine, not anticipated.
  CODES="$(sed -n -E 's/^(PASS|FAIL) +[^ ]+ +exit ([0-9]+).*/\2/p' \
    < "$SELF_TMP/suite.out" | sort -u)"
  DRIVEN="$(sed -n -E 's/^(PASS|FAIL) +[^ ]+ +exit [0-9]+.*/x/p' \
    < "$SELF_TMP/suite.out" | wc -l | tr -d ' ')"

  case "$SUITE_RC" in
    0) SELF_VERDICT="held" ;;
    1) SELF_VERDICT="NOT HELD" ;;
    *) die_unmeasured "the committed suite could not be run (it exited $SUITE_RC). Its own contract reserves that for no git, no check to test and no temporary directory - which is unmeasured, and not a corpus that held." ;;
  esac

  printf '    R39  %-38s examined %3s  %s: %s\n' \
    "selftest-cases-produce-declared-verdict" "$DRIVEN" "$SELF_VERDICT" \
    "each committed case produces the exit code and the load-bearing line that history should produce"
  # The R39.b declaration. The reached half is the list read off the case lines
  # above; the documented half is the contract in this file's header.
  REACHED="$(printf '%s' "$CODES" | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    printf '%s\n' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "${REACHED:-none - the corpus drove nothing}"
  printf '    NOT ASSERTED: anything outside the six committed spec versions. The corpus is six histories differing by one thing each; a defect that needs a seventh shape is invisible to it, and R32.5 sets no exit code by design.\n'
  if [ "$SUITE_RC" -ne 0 ]; then
    exit "$SUITE_RC"
  fi
  if [ -n "$MISSING" ]; then
    printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  exit 0
fi

# Defaulting to the working directory has caused four separate silent-wrong-
# answer bugs in this repository: the script reads a directory that is not the
# repo and reports a confident clean result. git names the work tree or
# nothing does.
if [ -z "$ROOT" ]; then
  # `git rev-parse` writes its own diagnosis to stderr and it is kept: the
  # error IS the answer to "is there a work tree here".
  if ! ROOT="$(git rev-parse --show-toplevel)"; then
    die_unmeasured "no git work tree here, and --root was not given. Refusing rather than reading the working directory, which is not the repo often enough to matter."
  fi
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

command -v python3 >/dev/null ||
  die_unmeasured "python3 is not on PATH, so the history cannot be walked. Refusing rather than guessing."

SELFDIR="$(cd "$(dirname "$0")" && pwd -P)"
PARSER="$SELFDIR/spec-requirements.sh"
[ -x "$PARSER" ] ||
  die_unmeasured "spec-requirements.sh is not beside this script and executable. It is the one parser check-superseded-text.sh and check-pending-ruling-scope.sh already read the spec through, and a third private notion of what a requirement IS goes green on its own terms the day it disagrees with theirs. Without it nothing here read the spec, and a run that read nothing is not a run that found nothing."

SPECREL=".claude/productizer/spec.md"
SPEC="$ROOT/$SPECREL"
[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unmeasured "cannot read $SPECREL under $ROOT. Without the spec there is neither a change to detect nor a change log to look in."

TOP="$(git -C "$ROOT" rev-parse --show-toplevel)" ||
  die_unmeasured "--root $ROOT is not inside a git work tree. R32's trigger is a claim about what a commit CHANGED, and there is no history here."
TOP="$(cd "$TOP" && pwd -P)"
case "$ROOT/" in
  "$TOP"/*) ;;
  *) die_unmeasured "--root $ROOT resolves outside its own git top level $TOP" ;;
esac

python3 - "$ROOT" "$TOP" "$PARSER" "$SPECREL" "$MAX_VERSIONS" <<'PY'
import os
import re
import shutil
import subprocess
import sys
import tempfile

root, top, parser, spec_rel, max_versions_raw = sys.argv[1:6]
max_versions = int(max_versions_raw)

spec_abs = os.path.join(root, spec_rel)


def refuse(message):
    sys.stderr.write("check-changelog-row: %s\n" % message)
    raise SystemExit(2)


examined_paths = []


def cover(shown):
    """One bare repo-relative path per line, unindented, on stdout. Printed
    only AFTER the file has been read - a path printed before the read is
    coverage claimed for a file nobody opened. A `..` in it is a path the
    runner cannot match against the changed set, so it is refused."""
    if shown.startswith("..") or os.path.isabs(shown):
        refuse("%s is not a canonical repo-relative path; a coverage line with "
               "a `..` in it is one the runner cannot match" % shown)
    examined_paths.append(shown)
    sys.stdout.write("%s\n" % shown)


def git(*args):
    """stderr is NOT captured and NOT discarded: it flows to the caller, so a
    git failure says why instead of arriving as an empty result."""
    proc = subprocess.run(["git", "-C", top] + list(args),
                          stdout=subprocess.PIPE, universal_newlines=True)
    if proc.returncode != 0:
        refuse("git %s failed under %s; the history this check reads is "
               "unavailable" % (" ".join(args), top))
    return proc.stdout


# ---------------------------------------------------------------------------
# reading the spec: requirements through the shared parser, the change log here
# ---------------------------------------------------------------------------
def parse_requirements(path):
    """spec-requirements.sh, not a fourth parser of our own. Emits
    <id> TAB <line> TAB <status> TAB <target> TAB <text>."""
    proc = subprocess.run([parser, path], stdout=subprocess.PIPE,
                          universal_newlines=True)
    if proc.returncode != 0:
        refuse("spec-requirements.sh refused %s (exit %d); nothing here read "
               "the spec" % (path, proc.returncode))
    status, text = {}, {}
    for line in proc.stdout.split("\n"):
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) < 5:
            refuse("spec-requirements.sh emitted a record with %d fields, not "
                   "5, while reading %s" % (len(fields), path))
        if fields[0] not in status:
            status[fields[0]] = fields[2]
            # The parser collapses whitespace, so a re-wrap is not an edit and
            # a reflowed paragraph does not read as a rewritten requirement.
            text[fields[0]] = fields[4]
    return status, text


RE_COUNTER_HEAD = re.compile(r'^Next requirement id\s*$')
RE_ID = re.compile(r'R([0-9]+)')
# An id RANGE: `R23-R28`, with a hyphen, an en dash or an em dash between the
# two. Written as an explicit character class rather than a bare `-` so an
# en-dashed range in a hand-written row is not read as a single id.
RE_RANGE = re.compile('R([0-9]+)\\s*[-–—]\\s*R([0-9]+)')
# The supersession arrow: `R7 -> R32`, spelled with U+2192 in the committed
# table and with an ASCII arrow by anyone typing one.
RE_ARROW = re.compile('→|->')


def counter_of(text):
    """`Next requirement id` / `: `R33` - ...`. Returns the int, or None."""
    lines = text.split("\n")
    for index, line in enumerate(lines):
        if RE_COUNTER_HEAD.match(line):
            for follow in lines[index + 1:index + 4]:
                found = RE_ID.search(follow)
                if found:
                    return int(found.group(1))
            return None
    return None


def ids_in(cell):
    """Every id named in one table cell, ranges expanded. `R23-R28` is six
    ids; a range that runs backwards or absurdly long is refused rather than
    expanded, because a typo there would silently satisfy every assertion."""
    out = set()
    for low, high in RE_RANGE.findall(cell):
        low, high = int(low), int(high)
        if high < low:
            refuse("the change log names the range R%d-R%d, which runs "
                   "backwards. Refusing rather than reading it as one id or as "
                   "none." % (low, high))
        if high - low > 200:
            refuse("the change log names the range R%d-R%d, which is %d ids. "
                   "Refusing rather than expanding it: a range that wide "
                   "satisfies every assertion by accident."
                   % (low, high, high - low + 1))
        for number in range(low, high + 1):
            out.add("R%d" % number)
    for number in RE_ID.findall(cell):
        out.add("R%s" % number)
    return out


def superseded_ids_in(cell):
    """The ids that were REPLACED, which are the ones on the LEFT of each
    arrow. `R14 -> R23, R24; R16 -> R25, R26` replaced R14 and R16; R23 to R26
    are the replacements and recording them as replaced is the opposite of
    what happened. A group with no arrow is taken whole - `R7` alone is a
    withdrawal, and withdrawals have nothing to point at."""
    out = set()
    for group in cell.split(";"):
        left = RE_ARROW.split(group)[0]
        out |= ids_in(left)
    return out


def parse_change_log(text, where):
    """Returns (added, refined, superseded, all_ids, rows_read).

    Rows come from the `## Change log` table only, and only from its `Added`,
    `Refined` and `Superseded / withdrawn` columns - located by HEADER NAME,
    not by position, so a column inserted tomorrow does not silently shift
    what is read. `Summary` is never parsed: it is prose that cites ids in
    passing, and an id matched there lets any row satisfy any commit."""
    lines = text.split("\n")
    start = None
    for index, line in enumerate(lines):
        if re.match(r'^##\s+Change log\s*$', line):
            start = index + 1
            break
    if start is None:
        refuse("%s has no `## Change log` section. R32's consequence is a "
               "claim about that table, and the table does not exist - which "
               "is a different fact from every change being unrecorded."
               % where)
    end = len(lines)
    for index in range(start, len(lines)):
        if re.match(r'^##\s', lines[index]):
            end = index
            break

    def cells(line):
        parts = line.strip().split("|")
        if parts and parts[0].strip() == "":
            parts = parts[1:]
        if parts and parts[-1].strip() == "":
            parts = parts[:-1]
        return [part.strip() for part in parts]

    columns = None
    added, refined, superseded, every = set(), set(), set(), set()
    rows_read = 0
    for index in range(start, end):
        line = lines[index]
        if not line.lstrip().startswith("|"):
            continue
        row = cells(line)
        if not row:
            continue
        if all(re.match(r'^:?-{2,}:?$', cell) for cell in row):
            continue                      # the |---|---| separator
        if columns is None:
            lowered = [cell.lower() for cell in row]
            if "added" in lowered:
                columns = {}
                for position, name in enumerate(lowered):
                    if name == "added":
                        columns["added"] = position
                    elif name == "refined":
                        columns["refined"] = position
                    elif name.startswith("superseded"):
                        columns["superseded"] = position
                if "added" not in columns or "superseded" not in columns:
                    refuse("the `## Change log` table in %s has no `Added` and "
                           "`Superseded / withdrawn` column pair this check "
                           "could locate by name. Reading the columns by "
                           "position instead would attribute the wrong ids to "
                           "the wrong half of every change." % where)
                continue
            refuse("the first table row under `## Change log` in %s is not a "
                   "header naming an `Added` column. Without the header there "
                   "is no way to tell which cell holds which half of a change."
                   % where)
        # The committed table carries a placeholder row - `<YYYY-MM-DD>`,
        # `R41-R43`, `R7 -> R41`. Read as a real row it satisfies R32.3 for R7
        # on its own, which is the very id R32 was born from. A row whose date
        # cell is a placeholder is not a record of anything.
        if row and re.match(r'^<[^>]*>$', row[0]):
            continue
        rows_read += 1
        this_added = ids_in(row[columns["added"]]) if columns["added"] < len(row) else set()
        this_sup = (superseded_ids_in(row[columns["superseded"]])
                    if columns["superseded"] < len(row) else set())
        this_ref = set()
        if "refined" in columns and columns["refined"] < len(row):
            this_ref = ids_in(row[columns["refined"]])
        added |= this_added
        refined |= this_ref
        superseded |= this_sup
        every |= this_added | this_ref | this_sup
    return added, refined, superseded, every, rows_read


# ---------------------------------------------------------------------------
# the spec as it stands now
# ---------------------------------------------------------------------------
with open(spec_abs, encoding="utf-8") as handle:
    spec_text = handle.read()
current_status, _current_text = parse_requirements(spec_abs)
cover(spec_rel)

if not current_status:
    refuse("%s holds no requirement definitions. That is nothing measured, "
           "not nothing wrong." % spec_rel)

log_added, log_refined, log_superseded, log_ids, log_rows = parse_change_log(
    spec_text, spec_rel)

# ---------------------------------------------------------------------------
# git: the history the trigger is read from
# ---------------------------------------------------------------------------
spec_git = os.path.relpath(os.path.realpath(spec_abs), top)
if not git("ls-files", "--", spec_git).strip():
    refuse("%s is not tracked by git. R32's trigger is 'a classification "
           "CHANGED the spec', which is a comparison between two commits, and "
           "this repository has none for the spec - no measurement, not a "
           "measured zero." % spec_rel)

if git("rev-parse", "--is-shallow-repository").strip() == "true":
    refuse("this is a SHALLOW clone. It reaches the spec and reaches nothing "
           "before it, so no commit can be compared with its predecessor and "
           "no change can be detected at all. 'Every change was recorded' out "
           "of that is a statement about one commit dressed up as a statement "
           "about history. Fetch full history (fetch-depth: 0) and re-run. A "
           "green run here is a green that measured nothing.")

shas = [sha for sha in git("log", "--format=%H", "--", spec_git).split("\n") if sha]
if len(shas) > max_versions:
    refuse("%s has %d commits and --max-versions is %d. Refusing rather than "
           "walking the newest %d: a truncated history reads the oldest commit "
           "in the window as the founding commit and exempts everything it "
           "introduced. Raise --max-versions."
           % (spec_rel, len(shas), max_versions, max_versions))

work = tempfile.mkdtemp(prefix="check-changelog-row.")
try:
    versions = []
    for sha in reversed(shas):            # oldest first
        # ls-tree, not `git show`, as the existence probe: it prints nothing
        # and exits 0 for a path absent at that commit, so a deletion commit
        # costs no error output and no suppressed stderr to hide it.
        if not git("ls-tree", sha, "--", spec_git).strip():
            continue
        short = git("rev-parse", "--short", sha).strip()
        blob = os.path.join(work, "v.md")
        text = git("show", "%s:%s" % (sha, spec_git))
        with open(blob, "w", encoding="utf-8") as handle:
            handle.write(text)
        statuses, texts = parse_requirements(blob)
        added_at, refined_at, superseded_at, _ids_at, _rows_at = (
            parse_change_log(text, "%s@%s" % (spec_rel, short)))
        cover("%s@%s" % (spec_rel, short))
        versions.append({"sha": short, "status": statuses, "text": texts,
                         "counter": counter_of(text),
                         "log_added": added_at,
                         "log_refined": refined_at,
                         "log_superseded": superseded_at})

    if len(versions) < 2:
        refuse("only %d reachable commit holds %s. There is a founding commit "
               "and nothing after it, so no classification has ever changed "
               "this spec and nothing was asserted. Not a clean run."
               % (len(versions), spec_rel))

    # =======================================================================
    # PROBE EVERY NEGATIVE BEFORE REPORTING IT
    # =======================================================================
    if not log_ids:
        refuse("the `## Change log` table in %s yielded no requirement id at "
               "all, from %d row(s). 'Every change is recorded' out of an "
               "empty parse is a grep that silently matched nothing - which is "
               "how this repository has produced confident false negatives "
               "before." % (spec_rel, log_rows))

    unknown = sorted(log_ids - set(current_status), key=lambda i: int(i[1:]))
    if unknown:
        refuse("the `## Change log` table in %s names %s, which %s not defined "
               "in the spec at all. That is a placeholder or template row being "
               "read as a real record, and every count in this run would be "
               "inflated by a table nobody wrote. Fix the parse before "
               "trusting the verdict."
               % (spec_rel, ", ".join(unknown),
                  "is" if len(unknown) == 1 else "are"))

    # =======================================================================
    # THE TRIGGER: which commits changed the spec, and which did not
    # =======================================================================
    changing = []       # commits a classification changed the spec at
    rewrites = []       # commits that rewrote a requirement sentence in place
    excluded = []       # commits that touched the spec and changed no structure
    counter_only = []   # signal (c) alone - no id to attribute, no verdict
    counter_pairs = 0

    for index in range(1, len(versions)):
        before, after = versions[index - 1], versions[index]
        appeared = sorted(set(after["status"]) - set(before["status"]),
                          key=lambda i: int(i[1:]))
        replaced = sorted(
            [rid for rid, status in after["status"].items()
             if before["status"].get(rid) == "active"
             and status in ("superseded", "withdrawn")],
            key=lambda i: int(i[1:]))
        moved_counter = False
        if before["counter"] is not None and after["counter"] is not None:
            counter_pairs += 1
            moved_counter = after["counter"] > before["counter"]

        # THE REFINE THAT KEEPS ITS ID. An id present on both sides, with the
        # same status, whose SENTENCE changed. That is a refine landing - and
        # it is character-for-character the same event as fixing a typo.
        rewritten = sorted(
            [rid for rid, body in after["text"].items()
             if rid in before["text"]
             and before["status"].get(rid) == after["status"].get(rid)
             and before["text"][rid] != body],
            key=lambda i: int(i[1:]))

        entry = {"sha": after["sha"], "before": before["sha"],
                 "appeared": appeared, "replaced": replaced,
                 "rewritten": rewritten,
                 "counter": moved_counter,
                 "log_added": after["log_added"],
                 "log_refined": after["log_refined"],
                 "log_superseded": after["log_superseded"]}
        if rewritten:
            rewrites.append(entry)
        if appeared or replaced:
            changing.append(entry)
        elif moved_counter:
            counter_only.append(entry)
        else:
            excluded.append(entry)

    findings = []
    unmeasured = []
    results = []

    def assertion(key, name, examined, upheld, held, note=None):
        results.append({"key": key, "name": name, "examined": examined,
                        "upheld": upheld, "held": held, "note": note})

    def describe(entry):
        """What the commit did, in ids. Findings name ids and shas and never
        quote requirement text: this output is written into a committed result
        file, and a check that quotes what it protects republishes it on every
        run."""
        parts = []
        if entry["appeared"]:
            parts.append("added %s" % ", ".join(entry["appeared"]))
        if entry["replaced"]:
            parts.append("replaced %s" % ", ".join(entry["replaced"]))
        return "; ".join(parts)

    for entry in counter_only:
        unmeasured.append(
            "%s@%s: `Next requirement id` moved between %s and %s, but no id "
            "appeared and none changed status. Something was allocated and "
            "there is no id to look for in any column, so this run has NO "
            "verdict on whether that change was recorded. Not a pass."
            % (spec_rel, entry["sha"], entry["before"], entry["sha"]))

    # =======================================================================
    # R32.5  THE REFINE THAT KEEPS ITS ID - REPORTED, NOT DEMANDED
    # =======================================================================
    #
    # 1.0's header said a refine that rewrites a requirement in place is
    # invisible here because nothing in the repository separates it from a typo
    # fix. The `Refined` column was then put forward as the separator: a commit
    # that rewrites a requirement's sentence and writes nothing in that column
    # is arguably exactly the violation.
    #
    # IT WAS MEASURED BEFORE IT WAS BELIEVED, and the measurement says do not
    # make it a finding:
    #
    #   this repository's whole spec history - 14 versions, 13 commits after
    #   the founding one - contains ZERO commits that rewrote a requirement's
    #   sentence in place. The 8 word-only commits changed acceptance rows and
    #   prose, never a requirement definition. So there is no evidence at all
    #   about how often such a rewrite is a refine and how often it is a typo:
    #   the rule would have fired 0 times, caught 0 refines and cried wolf 0
    #   times, and a rule with no observations behind it is a guess.
    #
    #   the only in-place rewrite committed anywhere in this repository is the
    #   fixture `spec/2-word-only.md`, whose own case name is `word-only` and
    #   whose purpose is to be the anti-cry-wolf control. 1 of 1 observed
    #   rewrites is a rewording. Demanding a row there would demand a
    #   change-log row for a typo, which is the failure mode that got the
    #   text-diff trigger rejected in the first place.
    #
    # So this assertion REPORTS. Every in-place rewrite is listed by location
    # and by id, and each is called RESOLVED when a `Refined` entry names it at
    # that commit and UNRESOLVED when nothing does. UNRESOLVED does not set the
    # exit code, because the check cannot tell which of the two events it was
    # and saying so is more honest than picking. What WOULD tell them apart is
    # named in the report: an author writing the id into `Refined`, or a
    # classification record whose `Classification` is `refine`. Neither exists
    # to be read today, and the second is the upstream fix.
    r5_examined = 0
    r5_resolved = 0
    r5_unresolved = []
    for entry in rewrites:
        for rid in entry["rewritten"]:
            r5_examined += 1
            if rid in entry["log_refined"]:
                r5_resolved += 1
            else:
                r5_unresolved.append(
                    "%s: %s kept its id and its status at %s and its sentence "
                    "changed, and no row names it in the `Refined` column at "
                    "that commit. A refine that keeps its id and a typo fix "
                    "are the same diff; nothing in this repository separates "
                    "them, so this run renders NO verdict on which it was. "
                    "Reported, not demanded - the `Refined` column is what "
                    "would settle it."
                    % (spec_rel, rid, entry["sha"]))

    sys.stdout.write("    IN-PLACE REQUIREMENT REWRITES (R32.5, reported and "
                     "never demanded):\n")
    if not rewrites:
        sys.stdout.write("      none - no commit in this history rewrote a "
                         "requirement's sentence while keeping its id and "
                         "status, so R32.5 was NOT ASSERTED by this run. Not a "
                         "hold: an assertion with nothing to fire on holds "
                         "vacuously.\n")
    for entry in rewrites:
        sys.stdout.write("      %s  rewrote %-18s `Refined` at that commit "
                         "names %s\n"
                         % (entry["sha"], ", ".join(entry["rewritten"]),
                            ", ".join(sorted(entry["log_refined"],
                                             key=lambda i: int(i[1:]))) or "-"))
    sys.stdout.write("    R32.5  refine-recorded-as-a-refine%s"
                     "        examined %3d  upheld %3d  %s\n"
                     % ("", r5_examined, r5_resolved,
                        "unmeasured - nothing to fire on" if r5_examined == 0
                        else ("held" if r5_resolved == r5_examined
                              else "REPORTED, not a finding")))
    for text in r5_unresolved:
        sys.stdout.write("    UNRESOLVED  %s\n" % text)

    # Refused only when there is NOTHING to say. A counter-only commit is a
    # different fact - the trigger fired and could not be attributed - and it
    # exits 2 further down through the unmeasured path, carrying its own
    # reason instead of being reported as "no classification changed the
    # spec", which would be false.
    if not changing and not counter_only:
        refuse("%d commit(s) touched %s after the founding commit and not one "
               "of them added an id or replaced a requirement. No "
               "classification changed the spec in this history, so R32's "
               "trigger never fired and NOTHING WAS ASSERTED. '0 unrecorded "
               "changes out of 0 changes' is an assertion whose loop never "
               "executed; this repository has already shipped one of those. "
               "Exit 2, unmeasured."
               % (len(versions) - 1, spec_rel))

    def recorded_by(entry, in_added, in_superseded):
        """The ids this commit moved that a row records AS THE KIND OF MOVE IT
        WAS: an id that appeared, named in `Added`; an id that was replaced,
        named on the left of `Superseded / withdrawn`.

        MATCHING THE ID ANYWHERE IN THE TABLE IS NOT ENOUGH, and this is not
        theoretical - it was measured. The first version of this check asked
        only whether some row named one of the moved ids. On a fixture whose
        founding row read `| ... | R2 | - | - |`, a LATER commit that
        superseded R2 and added R3 and wrote no row at all came back GREEN:
        the founding row named R2 in the `Added` column, R2 was one of the
        moved ids, and the match was made against a row recording a different
        event years earlier. Every id in a spec appears in the log eventually,
        so `named anywhere` converges on `always satisfied`."""
        return ((set(entry["appeared"]) & in_added)
                | (set(entry["replaced"]) & in_superseded))

    # =======================================================================
    # R32.1  every spec-changing commit has a row naming it
    # =======================================================================
    upheld = 0
    for entry in changing:
        if recorded_by(entry, log_added, log_superseded):
            upheld += 1
        else:
            findings.append(
                "%s: the commit %s changed the spec - %s - and no row in the "
                "`## Change log` table records any of those ids as the kind of "
                "change this was: an added id under `Added`, a replaced id on "
                "the left of `Superseded / withdrawn`. The change was merged "
                "and left no record, so the join between the requirement and "
                "the commit, branch and issue that moved it does not exist."
                % (spec_rel, entry["sha"], describe(entry)))
    assertion("R32.1", "recorded-in-the-change-log", len(changing), upheld,
              "every commit that added an id or replaced a requirement has a "
              "row recording that id under the column for that kind of change")

    # =======================================================================
    # R32.2  an addition is recorded in the `Added` column
    # =======================================================================
    examined = 0
    upheld = 0
    for entry in changing:
        for rid in entry["appeared"]:
            examined += 1
            if rid in log_added:
                upheld += 1
            else:
                findings.append(
                    "%s: %s was added at %s and no row names it in the `Added` "
                    "column%s. A row that mentions an id only in its summary "
                    "prose records a sentence, not a change."
                    % (spec_rel, rid, entry["sha"],
                       " (it is named elsewhere in the table)"
                       if rid in log_ids else ""))
    assertion("R32.2", "addition-recorded-as-an-addition", examined, upheld,
              "every id that appeared at a spec-changing commit is in the "
              "`Added` column of a row")

    # =======================================================================
    # R32.3  a supersession is recorded in the supersession column
    # =======================================================================
    examined = 0
    upheld = 0
    for entry in changing:
        for rid in entry["replaced"]:
            examined += 1
            if rid in log_superseded:
                upheld += 1
            else:
                findings.append(
                    "%s: %s was superseded or withdrawn at %s and no row names "
                    "it on the LEFT of the `Superseded / withdrawn` column%s. "
                    "The left-hand side is the id that was replaced; a row "
                    "listing it only as a replacement records the opposite of "
                    "what happened."
                    % (spec_rel, rid, entry["sha"],
                       " (it is named elsewhere in the table)"
                       if rid in log_ids else ""))
    assertion("R32.3", "supersession-recorded-as-a-supersession", examined,
              upheld,
              "every id replaced at a spec-changing commit is on the left of "
              "the `Superseded / withdrawn` column of a row")

    # =======================================================================
    # R32.4  the row landed in the same commit as the change
    # =======================================================================
    upheld = 0
    for entry in changing:
        if recorded_by(entry, entry["log_added"], entry["log_superseded"]):
            upheld += 1
        else:
            findings.append(
                "%s: the commit %s changed the spec - %s - and the change log "
                "AT THAT COMMIT recorded none of those ids. %s "
                "references/rulings.md requires the change and its record in "
                "one commit, because a spec that has been changed and a record "
                "that has not yet been written are two halves of one file "
                "disagreeing about what was agreed."
                % (spec_rel, entry["sha"], describe(entry),
                   "The row exists in the spec today, so it was written later."
                   if recorded_by(entry, log_added, log_superseded) else
                   "No row records them today either."))
    assertion("R32.4", "recorded-in-the-same-commit", len(changing), upheld,
              "the row was already in the change log at the commit that made "
              "the change, not added afterwards")

    # =======================================================================
    # REPORT
    # =======================================================================
    sys.stdout.write("    spec: %s\n" % spec_rel)
    sys.stdout.write("    spec versions examined: %d (oldest %s, newest %s)\n"
                     % (len(versions), versions[0]["sha"], versions[-1]["sha"]))
    sys.stdout.write("    founding commit %s is exempt: it introduced every id "
                     "it holds at once, and those were not added by a "
                     "classification\n" % versions[0]["sha"])
    sys.stdout.write("    change-log rows read today: %d, naming %d id(s)\n"
                     % (log_rows, len(log_ids)))
    sys.stdout.write("    `Next requirement id` readable on both sides of %d "
                     "of %d commit pairs\n"
                     % (counter_pairs, len(versions) - 1))
    sys.stdout.write("    commits after the founding one: %d - %d changed the "
                     "spec, %d changed no id, status or counter, %d moved the "
                     "counter alone\n"
                     % (len(versions) - 1, len(changing), len(excluded),
                        len(counter_only)))

    sys.stdout.write("    SPEC-CHANGING COMMITS (a row is demanded for each):\n")
    if not changing:
        sys.stdout.write("      none\n")
    for entry in changing:
        sys.stdout.write("      %s  added %-18s replaced %-14s counter %s\n"
                         % (entry["sha"],
                            ", ".join(entry["appeared"]) or "-",
                            ", ".join(entry["replaced"]) or "-",
                            "moved" if entry["counter"] else "still"))
    sys.stdout.write("    SPEC COMMITS EXCLUDED (word-only: no id appeared, no "
                     "status moved, the counter did not move - so no row is "
                     "demanded):\n")
    if excluded:
        for entry in excluded:
            sys.stdout.write("      %s  (vs %s)\n"
                             % (entry["sha"], entry["before"]))
    elif changing:
        sys.stdout.write("      none - every commit after the founding one "
                         "changed the spec, so the discriminator that keeps "
                         "word-only commits out was not exercised in this "
                         "history\n")
    else:
        sys.stdout.write("      none\n")

    for entry in results:
        verdict = "held" if entry["upheld"] == entry["examined"] else "NOT HELD"
        if entry["examined"] == 0:
            verdict = "unmeasured"
        sys.stdout.write("    %-6s %-40s examined %3d  upheld %3d  %s: %s\n"
                         % (entry["key"], entry["name"], entry["examined"],
                            entry["upheld"], verdict, entry["held"]))
        if entry["note"]:
            sys.stdout.write("           note: %s\n" % entry["note"])

    for text in findings:
        sys.stdout.write("    FINDING  %s\n" % text)
    for text in unmeasured:
        sys.stdout.write("    UNMEASURED  %s\n" % text)

    sys.stdout.write("    assertions upheld: %d of %d\n"
                     % (sum(1 for entry in results
                            if entry["examined"] > 0
                            and entry["upheld"] == entry["examined"]),
                        len(results)))
    sys.stdout.write("    files examined: %d\n" % len(examined_paths))
finally:
    shutil.rmtree(work, ignore_errors=True)

if unmeasured:
    sys.stderr.write(
        "UNMEASURED: at least one commit that changed the spec has no verdict "
        "from this run. Not a pass, whatever else held.\n")
    raise SystemExit(2)
if findings:
    sys.stderr.write(
        "FAIL: a classification changed the spec and the change log does not "
        "record it. R32 says the record is part of the change; the findings "
        "above are where a requirement moved and left no trace of who moved "
        "it, when, or under which issue.\n")
    raise SystemExit(1)

sys.stdout.write(
    "PASS: every commit at which a classification changed the spec - an id "
    "appeared, or a requirement was replaced - is recorded in the `## Change "
    "log` table, in the right column, in the commit that made the change. "
    "Word-only spec commits are listed above and no row is demanded for "
    "them.\n")
PY
