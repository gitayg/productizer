#!/usr/bin/env bash
# check-pending-ruling-scope.sh [--version] [--help] [--root DIR] [--selftest]
#
# Asserts R12: WHILE A CONTRADICTION IS UNRULED, THE LIFECYCLE SHALL MERGE NO
# SPEC CHANGE THAT DEPENDS ON IT.
#
# The load-bearing word is DEPENDS. `references/rulings.md` states the scope in
# one sentence and gives the reason in the next: "A pending ruling blocks its
# own delta and nothing else. Unrelated intents keep flowing. A halt that stops
# all work in the repo teaches people to route around intake, and an intake
# nobody runs detects no contradictions at all."
#
# So a check that refuses every spec change while any ruling is pending would
# be enforcing the opposite of R12 while passing for it. Blocking too much is
# not the safe direction here - it is the failure mode the requirement was
# written against, and it fails slowly, by teaching people to stop using the
# gate at all.
#
# WHAT COUNTS AS DEPENDING ON D<n>
#
# Dependence is derived from the ruling itself, never guessed from the diff.
# A pending `D<n>` names the requirement it was raised against in two places,
# and both are read:
#
#   - `## The conflict`, where the active requirement is quoted under its own
#     id as `**R<m>** — …`. This is the ruling's own statement of what it is
#     about.
#   - the spec's *Areas of concern* row whose status cites `D<n>`. Its cells
#     name the requirements the concern involves.
#
# The union of the two is the GUARDED SET. A spec change is refused when,
# between the commit that raised the ruling and the spec as it stands now, it:
#
#   1. EDITS a guarded requirement's sentence. The contested requirement cannot
#      be re-worded while the question of whether it survives is open.
#   2. SUPERSEDES or WITHDRAWS a guarded requirement. This is the ruling being
#      made by whoever committed last, which is the one thing the stop exists
#      to prevent.
#   3. ALLOCATES AN ID FOR THE INCOMING BEHAVIOUR. `rulings.md`: "Do not
#      allocate a requirement id for the incoming behaviour. An id in the spec
#      is a merge, whatever the surrounding prose says."
#
# A NEWLY ALLOCATED ID IS NOT AUTOMATICALLY THE INCOMING BEHAVIOUR, and that
# distinction is the whole difference between this check and a halt. An id
# added for an unrelated feature is an unrelated intent, and it keeps flowing.
# A new id `N` is treated as the incoming behaviour only on a structural tie
# back to the ruling:
#
#   (a) a guarded requirement's own marker points forward at `N` - the merge is
#       stated in the spec;
#   (b) `N` states the same behaviour as a guarded requirement.
#       `references/ears.md` is explicit that requirements are matched "on
#       trigger and system, not on wording", and a second requirement with the
#       same trigger as the contested one is by construction the other side of
#       the contradiction;
#   (c) `N`'s sentence states the same behaviour as the `**Incoming**` clause
#       the ruling quotes. The ruling records that sentence verbatim precisely
#       so the merge can be recognised later.
#
# WHAT "THE SAME BEHAVIOUR" MEANS, AND WHAT IT COST TO WIDEN IT
#
# Version 1.0 read (b) as byte equality of the clause before `shall`. That let
# through the case this check exists to catch: the SAME incoming behaviour
# merged under a different EARS keyword - state-driven `While <state>, the
# system shall ...` where the contested requirement is unwanted-behaviour `If
# <trigger>, then the system shall ...`. Same condition, same system, same
# obligation, two different keywords, and the byte comparison saw two unrelated
# sentences.
#
# The limitation recorded against 1.0 said closing this needed a similarity
# threshold, and that a threshold starts refusing unrelated intents - the
# failure at the top of this header. THAT ARGUMENT WAS MEASURED RATHER THAN
# BELIEVED, over every pair of requirements in this repository's own spec:
#
#   36 requirements, 630 pairs
#   1.0's rule           22 pairs called the same behaviour, 3 of them from
#                        DIFFERENT lineages - R1+R2, R1+R3, R2+R3
#   the rule below       19 pairs, 0 of them from different lineages
#
# So the widening did not cost false positives. It REMOVED three. All three
# were the same defect: R1, R2 and R3 are ubiquitous - `The lifecycle shall
# ...` - so the clause before `shall` is the system name and nothing else, and
# 1.0 matched every ubiquitous requirement against every other one. A ruling
# pending against R1 would have refused the allocation of R2.
#
# The rule is two disjuncts, in this order:
#
#   SAME CONDITION. Both sentences open with a real EARS keyword (`When`,
#   `While`, `If`, `Where`); with the keyword and the `then` connective
#   removed, the clause before `shall` is identical. This is structural, not a
#   threshold: it says the two sentences name the same condition and the same
#   system under different EARS categories, which is exactly the audit's case.
#   The keyword requirement is what stops it from collapsing every ubiquitous
#   requirement together.
#
#   NEAR-IDENTICAL. The condition clauses overlap by at least half their
#   content words AND the obligations do too. This is the threshold, and it is
#   there to catch the same behaviour merged under a REWORDED condition, which
#   the first disjunct misses. Its cost was measured on the same 630 pairs: it
#   adds nothing the first disjunct does not already flag, and the highest
#   score any pair from different lineages reaches anywhere in this spec is
#   27 percent - the bar is 50, so nothing unrelated is within 23 points of it.
#   Both halves must clear the bar, which is what separates a restatement from
#   a deliberate split: R33 `shall stop` and R34 `shall ask which wins` share a
#   condition and score 25 on the obligation.
#
# All 19 pairs the rule flags in this repository lie inside one of the six
# lineage families the spec's OWN change log names - R7/R32, R8/R35/R36,
# R14/R23/R24/R33/R34, R16/R25/R26, R21/R27/R28, R18/R29. It refuses nothing
# the spec does not already say is one behaviour restated or split.
#
# Anything else that was allocated is reported as allocated and NOT refused,
# on its own line, so the decision not to block it is visible rather than
# silent.
#
# THE WINDOW IS THE RULING'S OWN LIFETIME, NOT A DIFF RANGE. The baseline is
# the commit that ADDED the ruling file - which, per `rulings.md`, is the same
# commit that added its concern row. That is what "while unruled" means, and it
# needs no `--base` from the caller: a check whose window depends on a ref
# someone passes correctly is a check that reports clean when they do not. It
# also means the concern row added alongside the ruling is inside the baseline
# and never reads as a change. A ruling not yet committed has no such commit,
# and its window opens at HEAD.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   - It does not read `ruled`, `lapsed` or `superseded` rulings. A decided
#     question blocks nothing; that is what deciding it was for.
#   - It does not judge whether the ruling SHOULD have been raised, whether the
#     conflict is real, or which side ought to win. `contradiction-check.py`
#     answers the first and a human answers the third.
#   - It does not block changes elsewhere in the spec, to the backlog, to the
#     constitution, or to any code. R12 is about the spec change that depends
#     on the ruling.
#
# NO RULINGS DIRECTORY IS CLEAN, AND SAYS SO. R12 is state-driven: with no
# contradiction raised, the state it governs is never entered and there is
# nothing to refuse. That is different from COUNTING pending rulings, where an
# absent directory is no count rather than zero - and the difference is why the
# absence is printed as a note instead of folded into a number. A rulings
# directory that exists and cannot be read is exit 2, never clean: a directory
# nobody can open is exactly where an unruled contradiction hides.
#
# UNMEASURED CASES, each named separately, each exit 2:
#
#   a pending ruling naming no requirement    its scope cannot be derived, so
#                                             nothing can be said about what
#                                             depends on it
#   the ruling's commit is out of reach       a shallow clone; the window has
#                                             no start
#   the spec absent at that commit            there is nothing to compare to
#
# EXIT PRECEDENCE: UNMEASURED BEATS FINDINGS BEATS CLEAN, the same way
# `check-hygiene.sh` lets one unreadable file decide the whole run. A partial
# answer to "did anything merge" is not an answer.
#
# REPORTED BY LOCATION, NEVER BY QUOTING CONTENT. Ids, files, lines and short
# shas only. This matters more here than anywhere else in the repo: a ruling
# quotes an incoming intent, which is text a stranger can write, and this
# output lands in a committed result file. The incoming sentence is read into a
# temporary file, compared, and never printed.
#
# ONE LINE PER FILE EXAMINED, on stdout, unindented: the spec, every ruling
# file opened, and every historical spec version read as `<path>@<short sha>`.
# A loop over rulings that never executes prints nothing and exits 0, and the
# runner calls that hollow, which is a failure.
#
# THE SELF-ASSERTION, AND WHY IT IS NOT OPTIONAL
#
# This repository has no pending rulings, so the whole sweep above touches
# nothing and the run exits clean having asserted NOTHING about R12. A check
# that sweeps an empty set and prints PASS has already shipped here and sat
# green for weeks. So before it looks at the real repository, this script
# replays a committed fixture - `fixtures/ruling-scope/r12-different-trigger/`
# - into a temporary git repository and runs ITSELF against it, twice:
#
#   1. the audit's case: the incoming behaviour merged under a different EARS
#      keyword while the ruling is pending. Must be REFUSED.
#   2. an unrelated requirement allocated in the same window. Must be LET
#      THROUGH and reported as allocated - otherwise the assertion above would
#      also pass for a check that refuses everything, which is the failure
#      `rulings.md` names.
#
# The two are counted separately and both must hold; a run that could not set
# the fixture up is exit 2, never a pass. The fixture is copied into a
# temporary directory and the temporary repository is what gets written to -
# nothing is written into the repository being checked. The nested run is
# marked by an environment variable so it does not recurse.
#
# KNOWN LIMITATIONS, written down rather than discovered later:
#   - The same behaviour merged with BOTH its condition and its obligation
#     rewritten past the overlap bar is still not recognised. The bar was set
#     from measurement (0.5, against a measured worst case of 0.267 among
#     unrelated pairs) and lowering it further has no evidence behind it in a
#     spec this size.
#   - The measurement behind that bar is this repository's 630 pairs. A spec
#     whose requirements are written in a narrower vocabulary would score
#     higher on unrelated pairs, and the number to re-measure is the one in the
#     header above, not the threshold.
#   - A ruling raised and merged in a single commit leaves no window. Review of
#     that diff is what stands between the spec and that merge.
#   - Requirement ids are read from the whole concern row, not from the
#     Requirements column by position, so an id mentioned in the row's prose
#     joins the guarded set. Over-guarding one named requirement is the
#     cheaper error; the row named it.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  clean - both self-assertions upheld, and no pending ruling in the
#      repository whose delta reached the spec
#   1  findings - a spec change that depends on an unruled contradiction, or a
#      self-assertion that did not hold
#   2  could not run, or could not measure. Never 0.
#
# --SELFTEST IS NOT THE SELF-ASSERTION ABOVE, AND THE DIFFERENCE MATTERS. The
# self-assertion runs inside every ordinary run and asks whether the
# RECOGNITION RULE still works; it can only ever end in this check's own exit
# 0, because a self-assertion that did not hold turns into a finding and the
# ordinary run reports it as one. R39 asks something else: that the tool reach
# EACH exit code it can return. So --selftest replays the same committed
# fixture into a temporary git repository and drives THIS script against it
# five times - a spec where the incoming behaviour was merged under a
# different EARS keyword (1), a spec where an unrelated requirement was
# allocated in the same window (0), the spec as the ruling was raised (0), a
# root that is not a git work tree (2), and bad usage (2) - comparing each
# exit code with the one the case declares.
#
# The nested runs carry `PRODUCTIZER_RULING_SCOPE_SELFTEST` set to the fixture
# root, the same marker the self-assertion uses, so the nested run measures
# the fixture instead of recursing into a self-assertion of its own.
#
# Under --selftest the three codes mean: every case produced the code it
# declares (0), at least one did not (1), and the cases could not be built or
# driven at all (2). `--self-test` is accepted as an alias because the repo
# spells it both ways.
set -euo pipefail

# Byte-identical behaviour across machines and locales: character ranges,
# case folding and sort order all follow the locale otherwise, and this
# script's comparisons are all made out of them. `record-classification.sh`
# sets this for the same reason.
export LC_ALL=C

VERSION="check-pending-ruling-scope 1.1"
ROOT=""
MODE="measure"

usage() {
  printf 'usage: check-pending-ruling-scope.sh [--version] [--help] [--root DIR] [--selftest]\n'
  printf '  --root DIR  the repo work tree to examine. Defaults to the git\n'
  printf '              top level, never to the working directory.\n'
  printf '  --selftest  replay the committed fixture and read this check`s exit\n'
  printf '              code off each case. --self-test is an alias.\n'
}

die_unmeasured() { printf 'check-pending-ruling-scope: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)
      [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    -*) printf 'check-pending-ruling-scope: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'check-pending-ruling-scope: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# --selftest: replay the committed fixture into a temporary git repository and
# drive THIS script against it once per case. Nothing is written into the
# repository being checked, and the committed fixture is read, never written.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SELFDIR="$(cd "$(dirname "$0")" && pwd -P)" ||
    die_unmeasured "cannot resolve the directory this script lives in, so the committed fixture could not be located"
  FIXDIR="$SELFDIR/../fixtures/ruling-scope/r12-different-trigger"
  [ -d "$FIXDIR" ] ||
    die_unmeasured "the fixture is not at fixtures/ruling-scope/r12-different-trigger beside this script, so no case could be built. Unmeasured, not a pass"
  FIXDIR="$(cd "$FIXDIR" && pwd -P)" ||
    die_unmeasured "the fixture directory could not be entered"
  for fx in base-spec.md raised-spec.md merged-spec.md unrelated-spec.md D1-merge-nothing.md; do
    { [ -f "$FIXDIR/$fx" ] && [ -r "$FIXDIR/$fx" ]; } ||
      die_unmeasured "the fixture is missing or unreadable: $fx. Unmeasured, not a pass"
  done
  # The same premise guard the self-assertion applies: a ruling that is not
  # pending holds no window open, and every case below would then be testing
  # nothing while still going green.
  grep -qxF 'Status: pending' "$FIXDIR/D1-merge-nothing.md" ||
    die_unmeasured "the fixture's D1-merge-nothing.md is not pending, so the window the cases turn on is not open and none of them tests anything"

  SELFWORK="$(mktemp -d "${TMPDIR:-/tmp}/check-pending-ruling-scope-selftest.XXXXXX")" ||
    die_unmeasured "cannot create a temporary directory to replay the fixture into; nothing was driven"
  # Removed on every exit path, signal included.
  trap 'rm -rf "$SELFWORK"' EXIT HUP INT TERM

  mkdir -p "$SELFWORK/fixture/.claude/productizer" ||
    die_unmeasured "could not lay out the temporary repository"
  # Resolved, so the marker below and the nested run's own resolved ROOT are
  # the same string. On macOS $TMPDIR is a symlink and they would not be.
  FIXROOT="$(cd "$SELFWORK/fixture" && pwd -P)" ||
    die_unmeasured "the temporary repository could not be entered"
  git -c init.defaultBranch=main init -q "$FIXROOT" ||
    die_unmeasured "git could not create the temporary repository the cases replay the fixture into"
  selfcommit() {
    git -C "$FIXROOT" -c user.name=fixture -c user.email=fixture@example.invalid \
        -c commit.gpgsign=false commit -q -m "$1" ||
      die_unmeasured "git could not commit the fixture: $1"
  }
  cp "$FIXDIR/base-spec.md" "$FIXROOT/.claude/productizer/spec.md"
  git -C "$FIXROOT" add .claude || die_unmeasured "git could not stage the fixture"
  selfcommit "fixture: the spec before the contradiction was raised"
  mkdir -p "$FIXROOT/.claude/productizer/rulings"
  cp "$FIXDIR/raised-spec.md" "$FIXROOT/.claude/productizer/spec.md"
  cp "$FIXDIR/D1-merge-nothing.md" "$FIXROOT/.claude/productizer/rulings/D1-merge-nothing.md"
  git -C "$FIXROOT" add .claude || die_unmeasured "git could not stage the fixture"
  selfcommit "fixture: raise D1 and its concern row in one commit"

  CASES=0; UPHELD=0; REPORT=""
  REACHED_0=0; REACHED_1=0; REACHED_2=0

  tally() {
    NAME="$1"; WANT="$2"; GOT="$3"; WHY="$4"
    CASES=$((CASES + 1))
    if [ "$GOT" = "$WANT" ]; then UPHELD=$((UPHELD + 1)); V="held"; else V="NOT HELD"; fi
    case "$GOT" in
      0) REACHED_0=1 ;;
      1) REACHED_1=1 ;;
      2) REACHED_2=1 ;;
    esac
    REPORT="$REPORT      $NAME  expected $WANT  got $GOT  $V  $WHY
"
  }

  # $1 case name · $2 the spec version to put in the temporary repository ·
  # $3 the exit code the case declares · $4 the reason, one line.
  # The nested run's stdout is captured, never re-printed: its coverage lines
  # name paths inside a temporary directory, which are not this repository's
  # files. `|| GOT=$?` sits on the command's own line - a `$(...)` in an
  # argument list and a pipeline both RESET `$?`.
  drive_spec() {
    cp "$FIXDIR/$2" "$FIXROOT/.claude/productizer/spec.md" ||
      die_unmeasured "could not place $2 in the temporary repository"
    GOT=0
    PRODUCTIZER_RULING_SCOPE_SELFTEST="$FIXROOT" bash "$0" --root "$FIXROOT" \
      > "$SELFWORK/$1.out" 2> "$SELFWORK/$1.err" || GOT=$?
    tally "$1" "$3" "$GOT" "$4"
  }

  # 1 - the audit's case. The incoming behaviour merged under a different EARS
  # keyword while D1 is pending against the requirement it restates.
  drive_spec merged merged-spec.md 1 \
    "the incoming behaviour merged under a different EARS keyword - refused"

  # 0 - the other half. A pending ruling blocks its own delta and nothing
  # else; without this case the one above would also pass for a check that
  # refuses everything, which is the halt rulings.md calls the worse failure.
  drive_spec unrelated unrelated-spec.md 0 \
    "an unrelated requirement allocated in the same window - let through"

  # 0 - the window's own starting point, with nothing merged into it yet.
  drive_spec raised raised-spec.md 0 \
    "the spec as the ruling was raised - nothing has moved since"

  # 2 - could not measure. A directory that is not a git work tree has no
  # commit for the window to start at.
  mkdir -p "$SELFWORK/not-a-repo/.claude/productizer" ||
    die_unmeasured "could not lay out the not-a-repo case"
  cp "$FIXDIR/raised-spec.md" "$SELFWORK/not-a-repo/.claude/productizer/spec.md"
  GOT=0
  PRODUCTIZER_RULING_SCOPE_SELFTEST="$SELFWORK/not-a-repo" bash "$0" \
    --root "$SELFWORK/not-a-repo" \
    > "$SELFWORK/not-a-repo.out" 2> "$SELFWORK/not-a-repo.err" || GOT=$?
  tally not-a-repo 2 "$GOT" "a root outside any git work tree - the window has no start"

  # 2 - bad usage, reaching the same code through the argument parser.
  GOT=0
  bash "$0" --frobnicate > "$SELFWORK/bad-usage.out" 2> "$SELFWORK/bad-usage.err" || GOT=$?
  tally bad-usage 2 "$GOT" "an option this script does not take"

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"
  if [ "$CASES" = "$UPHELD" ]; then SELF_VERDICT="held"; else SELF_VERDICT="NOT HELD"; fi
  printf '    R39.s  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$CASES" "$UPHELD" "$SELF_VERDICT" \
    "each case exits with the code it declares"
  # `if`, not `[ ... ] && ...`: a false test as the last statement of a list is
  # a non-zero status, and `set -e` would end the run on the code that was NOT
  # reached - a self-test killed by its own summary line.
  REACHED=""
  if [ "$REACHED_0" = 1 ]; then REACHED="$REACHED 0"; fi
  if [ "$REACHED_1" = 1 ]; then REACHED="$REACHED 1"; fi
  if [ "$REACHED_2" = 1 ]; then REACHED="$REACHED 2"; fi
  printf '    exit codes this self-test reached:%s. The contract declares 0, 1 and 2; a code missing here is a code nothing drove\n' \
    "${REACHED:- none}"
  printf '    NOT ASSERTED: every nested run carries the marker that switches the self-assertion off, so this mode measures the SWEEP and never the self-assertion count the ordinary run prints\n'
  [ "$CASES" = "$UPHELD" ] || exit 1
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
# PHYSICAL PATH, because git reports one. `git rev-parse --show-toplevel`
# resolves symlinks and the containment test below compares the two as strings,
# so a root reached through a symlink was refused as "outside its own git top
# level". Measured, not argued: on macOS $TMPDIR is /var/folders/... symlinked
# to /private/var/folders/..., and every run rooted in a temporary directory
# died at that test.
ROOT="$(cd "$ROOT" && pwd -P)" ||
  die_unmeasured "--root could not be resolved to a real directory"

SELFDIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="$SELFDIR/spec-requirements.sh"
[ -x "$PARSER" ] ||
  die_unmeasured "spec-requirements.sh is not beside this script and executable. Without the parser nothing here read the spec."

SPECREL=".claude/productizer/spec.md"
SPEC="$ROOT/$SPECREL"
RULINGSREL=".claude/productizer/rulings"
RULINGS="$ROOT/$RULINGSREL"

[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unmeasured "cannot read $SPECREL under $ROOT. Without the spec there is no spec change to judge."

TOP="$(git -C "$ROOT" rev-parse --show-toplevel)" ||
  die_unmeasured "--root $ROOT is not inside a git work tree. The window a pending ruling holds open starts at a commit, and there are none."
case "$ROOT/" in
  "$TOP"/*) ;;
  *) die_unmeasured "--root $ROOT resolves outside its own git top level $TOP" ;;
esac
SPECGIT="${SPEC#"$TOP"/}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-pending-ruling-scope.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

found=0
unmeasured=0
finding() { printf '    %s\n' "$1"; found=1; }
unmeasurable() { printf '    UNMEASURED %s\n' "$1"; unmeasured=1; }

selftest_upheld=0
selftest_total=2

# The single exit point. Every path out of this script that is not
# `die_unmeasured` comes through here, so no path can reach a PASS without the
# self-assertion count being printed and checked - which is exactly how the
# absent-rulings shortcut used to return 0 having asserted nothing.
#
# UPHELD IS COUNTED PER ASSERTION, never taken from one flag: a single `ok`
# cannot tell "both held" apart from "neither ran".
verdict() {
  if [ "${PRODUCTIZER_RULING_SCOPE_SELFTEST:-}" = "$ROOT" ]; then
    printf 'self-assertions: not run - this is the nested pass over the fixture\n'
  else
    printf 'self-assertions upheld: %d of %d\n' "$selftest_upheld" "$selftest_total"
  fi
  if [ "$unmeasured" -ne 0 ]; then
    printf 'UNMEASURED: a pending ruling could not be scoped or its window could not be reached, so this run has no verdict on whether a dependent spec change merged. Not a pass.\n' >&2
    exit 2
  fi
  if [ "$found" -ne 0 ]; then
    printf 'FAIL: a spec change that depends on an unruled contradiction has reached the spec, or this check no longer recognises one. R12 merges nothing that depends on a pending ruling; rule the contradiction, then merge.\n' >&2
    exit 1
  fi
  if [ "${PRODUCTIZER_RULING_SCOPE_SELFTEST:-}" != "$ROOT" ] && [ "$selftest_upheld" -ne "$selftest_total" ]; then
    printf 'UNMEASURED: %d of %d self-assertions ran. A run that asserted less than it declares is not a pass, whatever the repository sweep found.\n' "$selftest_upheld" "$selftest_total" >&2
    exit 2
  fi
  printf 'PASS: %s. The recognition rule itself was exercised on the committed fixture in the same run.\n' "$1"
  exit 0
}

norm() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ //' -e 's/ $//'; }

# >>> same-behaviour rule - measured over this repo's 630 requirement pairs.
# Kept between these two markers so the rule that was measured and the rule
# that ships are the same bytes: the measurement harness extracts this block
# rather than reimplementing it, which is how two copies of a rule come to
# disagree. awk, not python3, so the check gains no new `requires:` entry.
#
# Two sentences on stdin, one per line. Prints a reason when they are the same
# behaviour and nothing at all when they are not.
SAME_BEHAVIOUR_AWK='
function nrm(s) {
  s = tolower(s)
  gsub(/[^a-z0-9 ]+/, " ", s)
  gsub(/  */, " ", s)
  sub(/^ /, "", s); sub(/ $/, "", s)
  return s
}
function cnd(s,   n, i) { n = nrm(s); i = index(n, " shall "); return (i ? substr(n, 1, i - 1) : n) }
function obl(s,   n, i) { n = nrm(s); i = index(n, " shall "); return (i ? substr(n, i + 7) : "") }
# A REAL EARS KEYWORD, not merely a clause before `shall`. Without this test a
# ubiquitous requirement - `The lifecycle shall ...` - has the system name as
# its whole condition, and every ubiquitous requirement matches every other.
# That was three of version 1.0s twenty-two matches, all of them wrong.
function haskw(c,   w) {
  w = c; sub(/ .*$/, "", w)
  return (w == "when" || w == "while" || w == "if" || w == "where")
}
function stripkw(c,   n, W, i, out) {
  n = split(c, W, " ")
  i = (n >= 1 && haskw(c)) ? 2 : 1
  out = ""
  for (; i <= n; i++) {
    if (W[i] == "then") continue
    out = (out == "" ? W[i] : out " " W[i])
  }
  return out
}
# INTEGER ARITHMETIC ONLY, and T is a percentage. A fraction compared against
# a decimal threshold puts the parse of "0.5" in the hands of the locale - some
# locales read a comma - and a threshold silently read as 0 refuses every pair.
# inter * 100 >= T * uni says the same thing with no decimal point anywhere.
function overlap(a, b,   A, B, na, nb, i, inter, uni) {
  delete SA; delete SB
  na = split(a, A, " "); nb = split(b, B, " ")
  for (i = 1; i <= na; i++) if (!(A[i] in STOP)) SA[A[i]] = 1
  for (i = 1; i <= nb; i++) if (!(B[i] in STOP)) SB[B[i]] = 1
  inter = 0; uni = 0
  for (i in SA) { uni++; if (i in SB) inter++ }
  for (i in SB) if (!(i in SA)) uni++
  if (uni == 0) return 0
  return (inter * 100 >= T * uni)
}
BEGIN {
  # Function words only. `not` and `no` are deliberately NOT here: they are the
  # difference between an obligation and its negation, which is the one word
  # pair a contradiction turns on.
  split("a an the of to in on for is are be by that it this and or", ST, " ")
  for (k in ST) STOP[ST[k]] = 1
}
NR == 1 { A = $0; next }
NR == 2 { B = $0 }
END {
  if (NR < 2 || A == "" || B == "") exit 0
  ca = cnd(A); cb = cnd(B)
  if (haskw(ca) && haskw(cb) && stripkw(ca) == stripkw(cb)) { print "same-condition"; exit 0 }
  if (overlap(stripkw(ca), stripkw(cb)) && overlap(obl(A), obl(B))) { print "near-identical"; exit 0 }
}
'
# <<< same-behaviour rule

# The overlap bar for the second disjunct, AS A PERCENTAGE - see the note on
# integer arithmetic in the rule above. Measured, not chosen: 27 percent is the
# highest either half reaches between requirements from different lineages
# anywhere in this spec, so the bar sits 23 points clear of everything
# unrelated the repository actually contains.
SAME_BEHAVIOUR_THRESHOLD="50"

# Prints `same-condition`, `near-identical`, or nothing. Neither sentence is
# ever echoed: one of them is a quote of an incoming intent, and this output
# lands in a committed file.
same_behaviour() {
  printf '%s\n%s\n' "$1" "$2" |
    awk -v T="$SAME_BEHAVIOUR_THRESHOLD" "$SAME_BEHAVIOUR_AWK"
}

# --- the self-assertion ----------------------------------------------------
# Runs first, and always, because the sweep that follows it is allowed to find
# nothing. See THE SELF-ASSERTION in the header. Skipped in the nested run, or
# it would recurse forever.
# THE MARKER NAMES THE ROOT IT SUPPRESSES, and is honoured only for that root.
# A bare on/off variable is a premise guard anything in the environment can
# switch off in silence - one stray export in CI and every run here prints PASS
# having asserted nothing, which is the exact failure this block exists to
# close. Naming the temporary fixture root means a value that arrived from
# anywhere else does not match, and the self-assertion runs anyway.
if [ "${PRODUCTIZER_RULING_SCOPE_SELFTEST:-}" != "$ROOT" ]; then
  FIXREL="plugins/productizer/skills/spec/fixtures/ruling-scope/r12-different-trigger"
  FIXDIR="$SELFDIR/../fixtures/ruling-scope/r12-different-trigger"
  [ -d "$FIXDIR" ] ||
    die_unmeasured "the self-assertion fixture is not at $FIXREL beside this script. Without it this run asserts nothing about R12 in a repository that has no pending rulings, and a sweep over an empty set is not a pass."
  FIXDIR="$(cd "$FIXDIR" && pwd)"

  # Coverage lines for the fixture are printed only when the fixture really is
  # inside the tree being checked. Pointed at another repository with --root,
  # the fixture is not one of that repository's files and claiming it as
  # examined coverage would be a lie about which tree was read.
  fixcov() {
    case "$FIXDIR/" in
      "$TOP"/*) printf '%s/%s\n' "${FIXDIR#"$TOP"/}" "$1" ;;
      # The path is NOT printed: outside the checked tree it is an absolute
      # path naming somebody's home directory, and this output is committed.
      *) printf '  fixture file read from outside the tree being checked: %s\n' "$1" ;;
    esac
  }

  for fx in base-spec.md raised-spec.md merged-spec.md unrelated-spec.md D1-merge-nothing.md; do
    { [ -f "$FIXDIR/$fx" ] && [ -r "$FIXDIR/$fx" ]; } ||
      die_unmeasured "the self-assertion fixture is missing or unreadable: $FIXREL/$fx"
    fixcov "$fx"
  done

  # PREMISE GUARDS. Each of these is a way the fixture could stop testing what
  # it claims to test while still going green, which is the failure mode this
  # whole block exists to close.
  grep -qxF 'Status: pending' "$FIXDIR/D1-merge-nothing.md" ||
    die_unmeasured "$FIXREL/D1-merge-nothing.md is not pending, so the window it is supposed to hold open is not open and neither assertion below tests anything."
  for fx in merged-spec.md unrelated-spec.md; do
    "$PARSER" "$FIXDIR/$fx" | awk -F'\t' '$1 == "R3"' | grep -q . ||
      die_unmeasured "$FIXREL/$fx does not define R3, so the allocation the assertions turn on is not in the fixture."
  done
  if "$PARSER" "$FIXDIR/base-spec.md" | awk -F'\t' '$1 == "R3"' | grep -q .; then
    die_unmeasured "$FIXREL/base-spec.md already defines R3, so R3 is not an allocation made inside the window and neither assertion tests anything."
  fi

  mkdir -p "$WORK/fixture/.claude/productizer"
  # Resolved, so the marker below and the nested run's own resolved ROOT are
  # the same string.
  FIXROOT="$(cd "$WORK/fixture" && pwd -P)"
  git -c init.defaultBranch=main init -q "$FIXROOT" ||
    die_unmeasured "git could not create the temporary repository the self-assertion replays the fixture into."
  gitc() {
    git -C "$FIXROOT" -c user.name=fixture -c user.email=fixture@example.invalid \
        -c commit.gpgsign=false commit -q -m "$1" ||
      die_unmeasured "git could not commit the self-assertion fixture: $1"
  }
  cp "$FIXDIR/base-spec.md" "$FIXROOT/.claude/productizer/spec.md"
  git -C "$FIXROOT" add .claude || die_unmeasured "git could not stage the self-assertion fixture"
  gitc "fixture: the spec before the contradiction was raised"

  mkdir -p "$FIXROOT/.claude/productizer/rulings"
  cp "$FIXDIR/raised-spec.md" "$FIXROOT/.claude/productizer/spec.md"
  cp "$FIXDIR/D1-merge-nothing.md" "$FIXROOT/.claude/productizer/rulings/D1-merge-nothing.md"
  git -C "$FIXROOT" add .claude || die_unmeasured "git could not stage the self-assertion fixture"
  gitc "fixture: raise D1 and its concern row in one commit"

  SELF="$SELFDIR/${0##*/}"
  [ -x "$SELF" ] ||
    die_unmeasured "cannot re-invoke this script as $SELF for the self-assertion."

  # The nested run's stdout is captured, never re-printed: its coverage lines
  # name paths inside a temporary directory, and those are not this
  # repository's files.
  run_fixture() {
    cp "$FIXDIR/$1" "$FIXROOT/.claude/productizer/spec.md"
    FIXRC=0
    PRODUCTIZER_RULING_SCOPE_SELFTEST="$FIXROOT" "$SELF" --root "$FIXROOT" \
      > "$WORK/fix.out" 2> "$WORK/fix.err" || FIXRC=$?
    # The nested run's STDOUT is held back - its coverage lines name paths in a
    # temporary directory and are not this repository's files. Its STDERR is
    # not: that is where the reason lives, and a reason nobody prints is a
    # reason nobody has.
    if [ -s "$WORK/fix.err" ]; then
      printf 'self-assertion, nested run over %s - its own stderr follows, and a FAIL line from it is the expected result for the refused case:\n' "$1" >&2
      sed 's/^/  /' < "$WORK/fix.err" >&2
    fi
  }

  # 1. THE AUDIT'S CASE. R3 is R1's behaviour under a state-driven keyword
  #    while D1 is pending against R1. It must be refused.
  run_fixture merged-spec.md
  if [ "$FIXRC" = "2" ]; then
    die_unmeasured "the self-assertion's nested run could not measure the fixture (exit 2). Its reason was printed to stderr just above. Nothing was asserted about R12."
  fi
  # `grep -q` on a deliberate no-match exits 1, which `set -e` would take as
  # the script failing. `if` is the branch, so the non-zero is expected here.
  if [ "$FIXRC" = "1" ] && grep -q 'R3 was allocated while D1 is pending' "$WORK/fix.out"; then
    selftest_upheld=$((selftest_upheld + 1))
    printf '  self-assertion 1 upheld: the incoming behaviour merged under a different EARS keyword is refused.\n'
  else
    finding "$FIXREL/merged-spec.md:1: the incoming behaviour of a pending ruling, merged under a different EARS keyword from the requirement the ruling names, was NOT refused (nested run exited $FIXRC). That is the gap R12 was reopened to close, and this check no longer closes it."
  fi

  # 2. THE OTHER HALF. An unrelated allocation in the same window must be let
  #    through, or assertion 1 would also pass for a check that refuses
  #    everything - the halt rulings.md names as the worse failure.
  run_fixture unrelated-spec.md
  if [ "$FIXRC" = "2" ]; then
    die_unmeasured "the self-assertion's nested run could not measure the unrelated-allocation fixture (exit 2). Its reason was printed to stderr just above."
  fi
  if [ "$FIXRC" = "0" ] && grep -q 'R3 allocated at' "$WORK/fix.out"; then
    selftest_upheld=$((selftest_upheld + 1))
    printf '  self-assertion 2 upheld: an unrelated requirement allocated in the same window is let through and reported.\n'
  else
    finding "$FIXREL/unrelated-spec.md:1: an UNRELATED requirement allocated while a ruling is pending was refused rather than let through (nested run exited $FIXRC). A pending ruling blocks its own delta and nothing else; a halt that stops all work teaches people to route around intake."
  fi
fi

# --- the spec as it stands now ---------------------------------------------
printf '%s\n' "$SPECREL"                 # coverage: one line per file examined
"$PARSER" "$SPEC" > "$WORK/cur.tsv" ||
  die_unmeasured "the parser refused $SPECREL"
[ -s "$WORK/cur.tsv" ] ||
  die_unmeasured "$SPECREL holds no requirement definitions. That is nothing measured, not nothing wrong."

# --- Areas of concern: which requirements each D<n> was raised over ---------
# Ids are taken from the whole row rather than from a column by position; see
# the known limitations in the header.
awk '
BEGIN { ins = 0; incomment = 0 }
/^## / { ins = ($0 ~ /^##[ \t]+Areas of concern[ \t]*$/) ? 1 : 0; next }
ins == 0 { next }
incomment == 1 { if ($0 ~ /-->/) incomment = 0; next }
/<!--/ { if ($0 !~ /-->/) incomment = 1; next }
$0 !~ /^[ \t]*\|/ { next }
{
  row = $0
  if (row !~ /\|[ \t]*C[0-9]+[ \t]*\|/) next
  ds = ""; rs = ""; rest = row
  while (match(rest, /D[0-9]+/)) { ds = ds " " substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH) }
  rest = row
  while (match(rest, /R[0-9]+/)) { rs = rs " " substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH) }
  n = split(ds, D, " ")
  for (i = 1; i <= n; i++) printf "%s\t%d\t%s\n", D[i], FNR, rs
}' "$SPEC" > "$WORK/concerns.tsv"

# --- the rulings directory: absent, unreadable and present are three answers
if [ ! -e "$RULINGS" ]; then
  printf 'rulings examined: 0\n'
  printf 'pending rulings: 0\n'
  printf 'note: no %s directory - no contradiction has ever been raised here, so R12 governs a state this repo has not entered. Nothing is blocked. That is an absence, and it is reported as one rather than as a measured zero.\n' "$RULINGSREL"
  verdict "no unruled contradiction in this repository, so no spec change here can depend on one"
fi
[ -d "$RULINGS" ] ||
  die_unmeasured "$RULINGSREL exists and is not a directory. A path that is not the directory the contract names says nothing about what is pending."
{ [ -r "$RULINGS" ] && [ -x "$RULINGS" ]; } ||
  die_unmeasured "$RULINGSREL exists and cannot be listed. What is pending is UNKNOWN, not zero - a directory nobody can open is exactly where an unruled contradiction hides."

# --- one pass per ruling ----------------------------------------------------
ruling_count=0
pending_count=0
guarded_total=0

for f in "$RULINGS"/D*.md; do
  [ -e "$f" ] || continue
  base="${f##*/}"
  rel="${f#"$ROOT"/}"
  printf '%s\n' "$rel"                   # coverage: one line per file examined
  ruling_count=$((ruling_count + 1))

  { [ -f "$f" ] && [ -r "$f" ]; } ||
    die_unmeasured "cannot read $rel. A ruling nobody could open is not a ruling that is fine."

  id="${base%.md}"; id="${id%%-*}"
  case "$id" in
    D[0-9]*) ;;
    *) finding "$rel:1: filename is not D<n>[-<slug>].md, so nothing can key this ruling to the requirement it guards"; continue ;;
  esac

  # Status is read from the HEADER BLOCK only, matched whole. `Status: pending`
  # appears in the template's own prose and in any ruling that discusses being
  # pending; a substring match reports questions that do not exist.
  awk '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  { L[NR] = $0 }
  END {
    N = NR
    firsth = 0
    for (i = 1; i <= N; i++) if (L[i] ~ /^## /) { firsth = i; break }
    lim = (firsth ? firsth - 1 : N)
    st = "-"
    for (i = 1; i <= lim; i++) {
      if (L[i] == "Status: pending")     { st = "pending"; break }
      if (L[i] == "Status: ruled")       { st = "ruled"; break }
      if (L[i] == "Status: lapsed")      { st = "lapsed"; break }
      if (L[i] == "Status: superseded")  { st = "superseded"; break }
    }
    printf "STATUS\t%s\n", st

    cs = 0; ce = 0
    for (i = 1; i <= N; i++) if (L[i] ~ /^##[ \t]+The conflict[ \t]*$/) { cs = i; break }
    if (cs) { ce = N; for (i = cs + 1; i <= N; i++) if (L[i] ~ /^## /) { ce = i - 1; break } }
    inc = ""; collecting = 0
    for (i = cs + 1; cs && i <= ce; i++) {
      line = L[i]
      if (line ~ /^\*\*R[0-9]+\*\*/) {
        collecting = 0
        match(line, /R[0-9]+/)
        printf "GUARD\t%s\n", substr(line, RSTART, RLENGTH)
        continue
      }
      if (line ~ /^\*\*Incoming\*\*/) {
        collecting = 1
        sub(/^\*\*Incoming\*\*[ \t]*/, "", line)
        sub("^\342\200\224[ \t]*", "", line)
        sub("^\342\200\223[ \t]*", "", line)
        sub(/^-[ \t]*/, "", line)
        inc = trim(line)
        continue
      }
      if (collecting) {
        if (line ~ /^[ \t]*$/) { collecting = 0; continue }
        inc = inc " " trim(line)
      }
    }
    # The incoming sentence is a quote of somebody else text. It is written to
    # a file for comparison and never reaches this check own stdout.
    if (inc != "") { gsub(/\t/, " ", inc); printf "INCOMING\t%s\n", inc }
  }' "$f" > "$WORK/r.tsv"

  status="$(awk -F'\t' '$1 == "STATUS" { print $2; exit }' "$WORK/r.tsv")"
  [ "$status" = "pending" ] || continue
  pending_count=$((pending_count + 1))

  # The guarded set: the ids the ruling quotes, plus the ids its concern row
  # names. Two independent statements of the same thing, unioned, because a
  # ruling that lost one of them still names what it is about in the other.
  GUARD="$(
    {
      awk -F'\t' '$1 == "GUARD" { print $2 }' "$WORK/r.tsv"
      awk -F'\t' -v d="$id" '$1 == d { n = split($3, R, " "); for (i = 1; i <= n; i++) print R[i] }' "$WORK/concerns.tsv"
    } | sort -u
  )"

  if [ -z "$GUARD" ]; then
    unmeasurable "$rel:1: $id is pending and names no requirement id, in its '## The conflict' section or in any Areas of concern row citing it. What depends on it cannot be derived, so nothing can be said about whether a dependent change merged."
    continue
  fi

  # --- the window: the commit that raised this ruling ----------------------
  RULGIT="${f#"$TOP"/}"
  ADD="$(git -C "$TOP" log --diff-filter=A --format=%H -- "$RULGIT" | tail -1)"
  window="raised"

  # A SHALLOW CLONE MAKES ITS BOUNDARY COMMIT LOOK LIKE A ROOT, so every file
  # present there looks ADDED there and this window would silently open at the
  # wrong commit - reporting clean for everything merged before the boundary.
  # A parentless commit in a shallow clone is a graft until proven otherwise,
  # and unknown is the only honest answer.
  if [ -n "$ADD" ] && [ "$(git -C "$TOP" rev-parse --is-shallow-repository)" = "true" ]; then
    if [ "$(git -C "$TOP" rev-list --parents -n 1 "$ADD" | wc -w | tr -d ' ')" = "1" ]; then
      unmeasurable "$rel:1: $id appears to have been added at $(git -C "$TOP" rev-parse --short "$ADD"), which is a parentless commit in a SHALLOW clone - that is a graft boundary, not necessarily the commit that raised the ruling. The window has no trustworthy start, so whether a dependent change merged inside it is UNKNOWN. Fetch full history (fetch-depth: 0) and re-run."
      continue
    fi
  fi

  if [ -z "$ADD" ]; then
    if [ -n "$(git -C "$TOP" ls-files -- "$RULGIT")" ]; then
      unmeasurable "$rel:1: $id is tracked and the commit that added it is not reachable - a shallow clone. The window this ruling holds open has no start, so whether a dependent change merged inside it is UNKNOWN. Fetch full history (fetch-depth: 0) and re-run."
      continue
    fi
    ADD="$(git -C "$TOP" rev-parse HEAD)" ||
      unmeasurable "$rel:1: $id is not committed and the repo has no commits, so there is no baseline spec to compare the working tree against."
    [ -n "$ADD" ] || continue
    window="uncommitted"
  fi
  SHORT="$(git -C "$TOP" rev-parse --short "$ADD")"

  if [ -z "$(git -C "$TOP" ls-tree "$ADD" -- "$SPECGIT")" ]; then
    unmeasurable "$rel:1: $SPECREL does not exist at $SHORT, the commit this ruling's window opens at. There is no earlier spec to compare against."
    continue
  fi

  if [ ! -f "$WORK/base.$SHORT.tsv" ]; then
    git -C "$TOP" show "$ADD:$SPECGIT" > "$WORK/base.md" ||
      die_unmeasured "cannot read $SPECREL at $SHORT, which git says exists there"
    printf '%s@%s\n' "$SPECREL" "$SHORT"  # coverage: one line per file examined
    "$PARSER" "$WORK/base.md" > "$WORK/base.$SHORT.tsv" ||
      die_unmeasured "the parser refused $SPECREL at $SHORT"
  fi
  BASE="$WORK/base.$SHORT.tsv"

  printf '  %s pending, window opens at %s (%s), guards %s\n' \
    "$id" "$SHORT" "$window" "$(printf '%s' "$GUARD" | tr '\n' ' ' | sed -e 's/ $//')"

  # --- 1 and 2: the contested requirements themselves ----------------------
  for g in $GUARD; do
    guarded_total=$((guarded_total + 1))
    cline="$(awk -F'\t' -v i="$g" '$1 == i { print $2; exit }' "$WORK/cur.tsv")"
    cstat="$(awk -F'\t' -v i="$g" '$1 == i { print $3; exit }' "$WORK/cur.tsv")"
    ctext="$(awk -F'\t' -v i="$g" '$1 == i { print $5; exit }' "$WORK/cur.tsv")"
    bstat="$(awk -F'\t' -v i="$g" '$1 == i { print $3; exit }' "$BASE")"
    btext="$(awk -F'\t' -v i="$g" '$1 == i { print $5; exit }' "$BASE")"

    if [ -z "$bstat" ]; then
      if [ -z "$cstat" ]; then
        unmeasurable "$rel:1: $id guards $g, which is defined neither in $SPECREL now nor at $SHORT. The ruling names a requirement the spec does not have."
      else
        finding "$SPECREL:$cline: $g was allocated while $id is pending against it. An id in the spec is a merge, whatever the surrounding prose says - $id has to be ruled first."
      fi
      continue
    fi
    if [ -z "$cstat" ]; then
      finding "$SPECREL:1: $g was defined at $SHORT and is gone from $SPECREL now, while $id is pending against it. Nothing is ever deleted from the spec, and least of all the requirement a live contradiction is about."
      continue
    fi
    if [ "$cstat" != "$bstat" ]; then
      finding "$SPECREL:$cline: $g went from $bstat to $cstat while $id is unruled. That is the ruling being made by whoever committed last, which is exactly what the stop exists to prevent."
    elif [ "$(norm "$ctext")" != "$(norm "$btext")" ]; then
      finding "$SPECREL:$cline: $g's sentence was edited while $id is pending against it. The contested requirement cannot be re-worded while the question of whether it survives is open. The text is not quoted here; read it with: git show $SHORT:$SPECGIT"
    fi
  done

  # --- 3: an id allocated for the incoming behaviour -----------------------
  INCOMING="$(awk -F'\t' '$1 == "INCOMING" { print $2; exit }' "$WORK/r.tsv")"
  NEWIDS="$(awk -F'\t' 'NR == FNR { seen[$1] = 1; next } !($1 in seen) { print $1 }' "$BASE" "$WORK/cur.tsv")"

  for n in $NEWIDS; do
    ntext="$(awk -F'\t' -v i="$n" '$1 == i { print $5; exit }' "$WORK/cur.tsv")"
    nline="$(awk -F'\t' -v i="$n" '$1 == i { print $2; exit }' "$WORK/cur.tsv")"
    why=""
    for g in $GUARD; do
      [ "$n" != "$g" ] || continue
      gtarget="$(awk -F'\t' -v i="$g" '$1 == i { print $4; exit }' "$WORK/cur.tsv")"
      gtext="$(awk -F'\t' -v i="$g" '$1 == i { print $5; exit }' "$WORK/cur.tsv")"
      if [ "$gtarget" = "$n" ]; then why="$g's marker points forward at it"; break; fi
      if [ -n "$gtext" ]; then
        case "$(same_behaviour "$ntext" "$gtext")" in
          same-condition)
            why="it names the same condition and the same system as $g under a different EARS keyword, and ears.md matches requirements on trigger and system rather than on wording"
            break ;;
          near-identical)
            why="its condition and its obligation each overlap $g's by at least half their content words"
            break ;;
        esac
      fi
    done
    if [ -z "$why" ] && [ -n "$INCOMING" ]; then
      if [ "$(norm "$ntext")" = "$(norm "$INCOMING")" ]; then
        why="its sentence is the incoming behaviour $id quotes"
      else
        case "$(same_behaviour "$ntext" "$INCOMING")" in
          same-condition|near-identical)
            why="it states the incoming behaviour $id quotes, re-worded" ;;
        esac
      fi
    fi
    if [ -n "$why" ]; then
      finding "$SPECREL:$nline: $n was allocated while $id is pending, and $why. An id in the spec is a merge, whatever the surrounding prose says."
    else
      printf '  %s allocated at %s:%s while %s is pending — unrelated to it, so not refused. A pending ruling blocks its own delta and nothing else.\n' \
        "$n" "$SPECREL" "$nline" "$id"
    fi
  done
done

printf 'rulings examined: %d\n' "$ruling_count"
printf 'pending rulings: %d\n' "$pending_count"
printf 'guarded requirements: %d\n' "$guarded_total"

verdict "no spec change depending on a pending ruling has reached the spec. Unrelated changes were not examined for approval and were not blocked"
