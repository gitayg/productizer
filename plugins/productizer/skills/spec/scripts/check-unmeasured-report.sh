#!/usr/bin/env bash
# check-unmeasured-report.sh [--root DIR] [--fixture DIR] [--scripts DIR] [--version] [--help]
#
# WHAT COULD NOT BE MEASURED HAS TO SAY SO, OUT LOUD, ON THE LINE A PERSON READS.
#
# Three requirements, all of them consequences of P1 - an unreadable file, an
# absent tool, a failed API call and a refused permission all produce unmeasured;
# none of them produce zero and none of them produce a pass. They are asserted
# separately here because they live in three different code paths and a fix to
# one does not fix the others.
#
#   R11  WHEN A PUBLISHED VIEW IS REGENERATED, THE LIFECYCLE SHALL READ EVERY
#        FIGURE IN IT FROM A FILE IN THE REPOSITORY.
#   R20  IF A SURVEY FINDS TOO LITTLE EVIDENCE TO DRAFT FROM, THEN THE LIFECYCLE
#        SHALL REFUSE TO DRAFT.
#   R25  IF A VALUE COULD NOT BE MEASURED, THEN THE LIFECYCLE SHALL REPORT IT AS
#        UNMEASURED.
#
# WHY R25 IS NOT ALREADY COVERED. Its pair R26 - do not RECORD it as zero - is
# asserted by `no-fabricated-zero` and `cannot-run-coverage`, and both of those
# read the RESULT FILE on purpose. R25 is about the PRINTED line, and the two are
# separable: this repository has already produced a run that printed UNMEASURED
# while writing 0. So every R25 assertion below reads a printed stream and never
# the JSON. Duplicating the JSON assertions here would leave R25 unasserted while
# looking like it was covered, which is worse than leaving it uncovered.
#
# WHAT IT ASSERTS, AND WHY EACH ONE IS SEPARATE. Twelve assertions, each named,
# each counted on its own. `upheld` is incremented per assertion and never
# derived from a single ok flag - a summary that reads `upheld: 0` above six
# lines saying `held:` disagrees with the evidence printed directly above it.
#
#   R11.1  A FIGURE MOVES WITH ITS FILE. The same repository is built twice,
#          differing only in the spec, and the Living spec tile has to read the
#          number of active requirements each spec actually holds. A figure that
#          does not move when its source moves was not read from the source.
#   R11.2  AN UNREADABLE SOURCE RENDERS A MARKER, NEVER A DIGIT. The spec is made
#          unreadable by permission and the tile must render one of the four
#          renderings the page has - a number, `n/a`, an em dash for never run, a
#          question mark for read-and-not-understood - and specifically not a
#          number, and above all not 0.
#   R11.3  A SECOND SOURCE, A SECOND RENDERING. The result file is left present
#          and unparseable, which is a different state from absent, and the
#          checks tile must render the unknown marker rather than a count or a
#          verdict word. Separate from R11.2 because it is a different file read
#          by different code down a different branch.
#   R11.4  THE HONEST INVERSE. With every source readable the same two tiles must
#          render their measured values. A page that rendered a marker
#          everywhere would satisfy R11.2 and R11.3 and be worthless.
#   R20.1  A BARREN REPOSITORY REACHES THE REFUSAL. The survey must print that
#          there is not enough evidence to draft, and must name no draft tier.
#   R20.2  THE REFUSAL IS GROUNDED, NOT UNCONDITIONAL. The verdict's own printed
#          tally must show both tiers under the floors it printed beside them.
#          Without this, a survey hard-wired to refuse would pass R20.1.
#   R20.3  THE OTHER DIRECTION. A repository that does state its behaviour must
#          reach a draft tier and must not refuse. A surveyor that always refuses
#          is as useless as one that never does.
#   R25.1  THE RUNNER SAYS UNMEASURED. With a denominator that has no source, the
#          printed line must read `spec coverage: UNMEASURED`.
#   R25.2  THE RUNNER'S INVERSE. With a denominator that has a source, the same
#          line must report the measured count and must not say UNMEASURED.
#   R25.3  THE HYGIENE CHECK SAYS UNMEASURED. A file it cannot open must be
#          reported as `Unmeasured, not clean`, and the run must exit 2 rather
#          than 0. R25 is inherited from R16 and spans several tools, so it is
#          asserted in more than one of them.
#   R25.4  THE HYGIENE CHECK'S INVERSE. A readable, clean file exits 0 and says
#          nothing about being unmeasured.
#   R25.5  THE STATUS REPORT KEEPS TWO WORDS FOR TWO FACTS. A result file that is
#          present and will not parse is reported `unknown`; one that was never
#          written is reported `not run`. Collapsing them would let one word
#          cover both and R25 would be satisfied by an accident.
#
# THE PREMISES ARE CHECKED FIRST AND ARE NOT ASSERTIONS. If the file this check
# made unreadable turns out to be readable - running as root does exactly that -
# then nothing was unmeasurable and R11.2 was never exercised. Same for a corrupt
# fixture that parses, a missing spec that is present, and a survey sandbox that
# turns out to sit inside a git work tree, where the survey would read this
# repository's own history as evidence and the barren case would stop being
# barren. Every one of those is exit 2 - could not run - and never a pass.
#
# IT WRITES NOTHING INTO THE REPOSITORY IT CHECKS. R4 makes views read-only with
# respect to the spec, and `view-read-only` hashes every file in the tree before
# and after a build; a check that mutated the tree while that one ran would make
# a sibling check fail for a reason nobody could find. Every fixture is COPIED
# into a temporary directory, every generated page and result is written there,
# every permission change is made there, and the directory is removed on exit.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every assertion held
#   1  an assertion failed - something that could not be measured was reported as
#      a number, or a survey drafted from nothing, or a tool went quiet about it
#   2  could not run - bad usage, a missing fixture, a missing script, no
#      python3, or a premise that did not hold
#
# WHAT IT PRINTS. One BARE repo-relative path per line for every file examined,
# which is what the runner parses as coverage; a path holding a `..` is a path
# the runner cannot match, so every one of them is canonicalised first.
# Assertions, classifications and notes are INDENTED. The stderr of the tools it
# drives is NOT reproduced: it names temporary directories, and this output is
# tailed into a committed result file where an absolute path is somebody's home
# directory published to everyone who clones the repository.
#
# PORTABILITY. Developed on macOS/BSD. No GNU-only behaviour: no mapfile, no
# `grep -P`, no `date -d`, no in-place sed. Nothing suppresses stderr.
#
# --scripts DIR points at the `scripts` directory of a skill tree, not at a lone
# file: build-view.sh finds its template and stage-status.sh relative to its own
# location. It exists so the tools can be falsified on a patched COPY of the
# skill - make a builder render 0 for an unreadable source and watch exactly one
# assertion go red - without ever editing the repository's own scripts.
set -euo pipefail

VERSION="check-unmeasured-report 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$(dirname "$HERE")"

ROOT=""
FIXTURE=""
SCRIPTS=""
MODE="measure"

die_unmeasured() { printf 'check-unmeasured-report: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    # `--self-test` is an alias, not a second flag: this repository spells the
    # same obligation both ways and a tool that answers only one spelling reads
    # as carrying no self-test to whichever scanner is looking for the other.
    --selftest|--self-test) MODE="selftest"; shift ;;
    --root)       [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)     ROOT="${1#--root=}";       shift ;;
    --fixture)    [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2"; shift 2 ;;
    --fixture=*)  FIXTURE="${1#--fixture=}"; shift ;;
    --scripts)    [ "$#" -ge 2 ] || die_unmeasured "--scripts needs a path"; SCRIPTS="$2"; shift 2 ;;
    --scripts=*)  SCRIPTS="${1#--scripts=}"; shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1" ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1"

# The work tree, never the working directory. --root does not decide what is
# tested - the fixture and the tools are found beside this script, so the test is
# the same one wherever it is invoked from - it decides what the printed paths
# are relative to, so nothing absolute reaches the committed result.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" || ROOT=""
fi
if [ -n "$ROOT" ] && [ -d "$ROOT" ]; then
  ROOT="$(cd "$ROOT" && pwd -P)"
else
  # No work tree: an installed plugin is not a repository. Paths are then printed
  # relative to the skill directory, which is still not absolute.
  ROOT="$SKILL"
fi

[ -n "$FIXTURE" ] || FIXTURE="$SKILL/fixtures/unmeasured-report"
[ -d "$FIXTURE" ] || die_unmeasured "no fixture directory; the standing case is missing, which is unmeasured and not a pass"
FIXTURE="$(cd "$FIXTURE" && pwd -P)"

[ -n "$SCRIPTS" ] || SCRIPTS="$HERE"
[ -d "$SCRIPTS" ] || die_unmeasured "no scripts directory at the path given to --scripts; there is nothing to drive"
SCRIPTS="$(cd "$SCRIPTS" && pwd -P)"

BUILD_VIEW="$SCRIPTS/build-view.sh"
IMPORT_SURVEY="$SCRIPTS/import-survey.sh"
RUN_CHECKS="$SCRIPTS/run-checks.sh"
HYGIENE="$SCRIPTS/check-hygiene.sh"
STAGE_STATUS="$SCRIPTS/stage-status.sh"

for t in "$BUILD_VIEW" "$IMPORT_SURVEY" "$RUN_CHECKS" "$HYGIENE" "$STAGE_STATUS"; do
  [ -f "$t" ] || die_unmeasured "no $(basename "$t") in the scripts directory; the tool under test is missing, which is unmeasured and not a pass"
done
command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the generated page and the reports could not be read"

FIXTURE_FILES="
view/config.json
view/spec.md
view/spec-extra.md
view/constitution.md
view/backlog.md
view/checks-result.json
view/checks-result-corrupt.json
survey/barren/notes.txt
survey/evidenced/package.json
survey/evidenced/README.md
survey/evidenced/src/index.js
survey/evidenced/src/cli.js
survey/evidenced/tests/widget.test.js
runner/checks.yaml
runner/checks-measured.yaml
runner/spec.md
runner/changed.txt
hygiene/patterns.txt
hygiene/clean.txt
"
for f in $FIXTURE_FILES; do
  [ -f "$FIXTURE/$f" ] || die_unmeasured "the fixture has no $f; the standing case is incomplete, which is unmeasured and not a pass"
done

# ---------------------------------------------------------------------------
# --selftest - R39: THIS TOOL REACHES EACH EXIT CODE IT CAN RETURN, ON PURPOSE.
#
# Four cases, one per way the contract above can be reached, each driven
# through THIS script so the argument handling and the seven premises are on
# the path too. No case is asserted by reading source: the exit code is read
# off a real run.
#
#   clean          a byte copy of the skill's own tools                  -> 0
#   quiet-hygiene  the same copy with check-hygiene.sh replaced by one
#                  that exits 0 without a word on a file it could not
#                  open, which is exactly what R25.3 forbids             -> 1
#   no-scripts     a --scripts directory that is not there               -> 2
#   bad-usage      an option the parser does not take                    -> 2
#
# THE CLEAN CASE IS DRIVEN AGAINST THE COPY, NOT AGAINST THE COMMITTED TOOLS,
# and that is deliberate. The two runs then differ in ONE FILE, so the exit
# code moving from 0 to 1 is attributable to that file and to nothing else. A
# clean case run against the committed tree and a finding case run against a
# copy would also differ in every consequence of having been copied.
#
# THE CLEAN CASE GUARDS THE OTHER THREE. If the copy does not exit 0, the
# quiet-hygiene case would be red for whatever is wrong with the copy - exit 2
# for the whole self-test, never a pass on the cases that followed.
#
# THE TWO HEAVY CASES RUN CONCURRENTLY. Each is a full drive of five tools over
# eleven sandboxes and takes most of ten seconds; run one after the other they
# would come close to the probe budget check-selftest-coverage.sh allows a
# self-test, and a self-test that times out is reported `?` - unreadable - and
# refuses that check rather than answering it. They share nothing but the
# read-only fixture, so running them at once changes no verdict.
#
# NOTHING IS WRITTEN INTO THE REPOSITORY. The copy and the broken tool live
# under mktemp and the directory goes on every exit path, signal included.
#
# WHAT THIS SELF-TEST DOES NOT ASSERT, printed rather than passed silently: it
# reads the exit CODE and never which of the twelve assertions moved, so a case
# that went red for the wrong reason is invisible here.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-unmeasured-report-selftest.XXXXXX")" \
    || die_unmeasured "cannot create a temporary directory to build the self-test's inputs in; nothing was driven"
  trap 'rm -rf "$SB"' EXIT HUP INT TERM

  # The whole skill directory, not just the scripts: the tools resolve their
  # own templates and references through `..`, and a directory of the five
  # scripts alone would fail for that reason rather than for the mutation.
  cp -R "$SKILL" "$SB/intact" \
    || die_unmeasured "the skill directory could not be copied, so neither drive had tools to run. Unmeasured, not a pass"
  cp -R "$SB/intact" "$SB/quiet" \
    || die_unmeasured "the second copy could not be made, so the case that must go red was never built. Unmeasured, not a pass"

  # R25.3 says a file the hygiene check cannot open is reported `Unmeasured,
  # not clean` and exits 2. This one exits 0 and says nothing - the silent pass
  # over an unread file, which is the defect P1 exists to refuse and the
  # single difference between the two drives below.
  cat > "$SB/quiet/scripts/check-hygiene.sh" <<'SELFTEST_HYGIENE'
#!/usr/bin/env bash
# Built by check-unmeasured-report.sh --selftest. Never installed, never
# reachable from the repository: it lives under mktemp for one run.
exit 0
SELFTEST_HYGIENE
  chmod +x "$SB/quiet/scripts/check-hygiene.sh"
  if cmp -s "$SB/intact/scripts/check-hygiene.sh" "$SB/quiet/scripts/check-hygiene.sh"; then
    die_unmeasured "the two copies hold the same hygiene check, so the quiet-hygiene case is identical to the clean one and would prove only that the clean case passes twice. Unmeasured, not a pass"
  fi

  # $1 case, then the argv. `_r=$?` on the SAME LINE as the command: a `$(...)`
  # or a pipeline between the two resets it, which is how a self-test reports
  # passes having measured none.
  self_bg() {
    _n="$1"
    shift
    ( _r=0
      bash "$0" "$@" > "$SB/$_n.out" 2> "$SB/$_n.err" || _r=$?
      printf '%s\n' "$_r" > "$SB/$_n.rc" ) &
  }

  SELF_CASES=0
  SELF_FAILED=0
  self_report() { # $1 case, $2 expected exit, $3 what the case is
    _rc="$(cat "$SB/$1.rc")"
    SELF_CASES=$((SELF_CASES + 1))
    if [ "$_rc" = "$2" ]; then
      printf '  held:    case %-14s expected %s  observed %s  %s\n' "$1" "$2" "$_rc" "$3"
    else
      printf '  FINDING: case %-14s expected %s  observed %s  %s\n' "$1" "$2" "$_rc" "$3"
      SELF_FAILED=$((SELF_FAILED + 1))
    fi
  }

  self_bg clean --root "$ROOT" --fixture "$FIXTURE" --scripts "$SB/intact/scripts"
  self_bg quiet-hygiene --root "$ROOT" --fixture "$FIXTURE" --scripts "$SB/quiet/scripts"
  self_bg no-scripts --root "$ROOT" --fixture "$FIXTURE" --scripts "$SB/there-are-no-scripts-here"
  self_bg bad-usage --root "$ROOT" --no-such-option
  wait

  CLEAN_RC="$(cat "$SB/clean.rc")"
  if [ "$CLEAN_RC" != 0 ]; then
    printf '  the clean case exited %s, not 0.\n' "$CLEAN_RC"
    die_unmeasured "a byte copy of the committed tools did not produce a clean run, so the quiet-hygiene case below would be red for that reason instead of its own. Unmeasured, not a corpus that held"
  fi

  self_report clean 0 \
    "a byte copy of the committed tools over the committed fixture: all twelve assertions held"
  self_report quiet-hygiene 1 \
    "the same copy, with a hygiene check that exits 0 without a word on a file it could not open - R25.3 is the assertion that must catch it"
  self_report no-scripts 2 \
    "no scripts directory at the path given, so there was nothing to drive - unmeasured, never a pass"
  self_report bad-usage 2 \
    "an option this parser does not take: bad usage is refused rather than ignored"

  printf '  self-test cases driven: %d, exit codes reached: 0, 1, 2. Cases that did not hold: %d\n' \
    "$SELF_CASES" "$SELF_FAILED"
  printf '  NOT ASSERTED: which of the twelve assertions moved. Each case reads the exit CODE, so a case that went red for the wrong reason is invisible here and is read off the case output by hand.\n'
  if [ "$SELF_FAILED" -ne 0 ]; then
    printf 'check-unmeasured-report: %d self-test case(s) did not produce the exit code the contract declares for them.\n' "$SELF_FAILED" >&2
    exit 1
  fi
  printf '  R39 for this tool: the self-test exists and reaches 0, 1 and 2 by driving the real check, not by reading its source.\n'
  exit 0
fi

rel() {
  case "$1" in
    "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;;
    *)         printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;;
  esac
}

# --- coverage: one bare repo-relative path per file examined ---------------
rel "$BUILD_VIEW"
rel "$IMPORT_SURVEY"
rel "$RUN_CHECKS"
rel "$HYGIENE"
rel "$STAGE_STATUS"
for f in $FIXTURE_FILES; do rel "$FIXTURE/$f"; done

TMP="$(mktemp -d)"
# The permission change is undone before the directory is removed: `rm -rf` on a
# tree holding a mode-000 file is fine on this platform, but a trap that depends
# on that is a trap that leaves a directory behind on the platform where it is
# not.
cleanup() {
  [ -d "$TMP" ] || return 0
  chmod -R u+rwX "$TMP" || :
  rm -rf "$TMP"
}
trap cleanup EXIT

# PREMISE ONE. The sandbox must not sit inside a git work tree. The survey reads
# change history as weak evidence, so a barren fixture surveyed under a
# repository inherits that repository's history and stops being barren - the
# refusal this check exists to reach would quietly become unreachable.
if git -C "$TMP" rev-parse --show-toplevel >/dev/null 2>&1; then  # stderr-ok: asking whether the sandbox is inside a work tree; git's "not a git repository" IS the answer we want, not an error to surface
  die_unmeasured "the temporary sandbox is inside a git work tree, so the survey would read that repository's history as evidence and the barren case would not be barren. The premise failed; this is unmeasured, not a pass"
fi

# PREMISE TWO. The unmeasurable runner config must name a spec that is not in the
# sandbox it runs against, or the denominator was derivable and nothing was
# unmeasured.
DECLARED_SPEC="$(sed -n 's/^ *spec: *\([^ #][^#]*\)$/\1/p' "$FIXTURE/runner/checks.yaml" | head -1 | sed 's/[[:space:]]*$//')"
[ -n "$DECLARED_SPEC" ] || die_unmeasured "the runner fixture names no spec path, so the denominator's premise cannot be established"
case "$DECLARED_SPEC" in
  /*) die_unmeasured "the runner fixture's spec path is absolute; it would name a different file on every machine" ;;
esac

# PREMISE THREE. The fixture spec must carry no superseded or withdrawn marker.
# The page counts ACTIVE requirements; a marker here would make the page's figure
# legitimately differ from a plain count of the bullets and R11.1 would be
# comparing two different quantities.
if grep -Eq '^(Superseded by R[0-9]+|Withdrawn)\b' "$FIXTURE/view/spec.md" "$FIXTURE/view/spec-extra.md"; then
  die_unmeasured "the view fixture's spec carries a superseded or withdrawn marker, so a plain count of its bullets is not the active count and the figure comparison would not mean what it says. The premise failed; this is unmeasured, not a pass"
fi

SPEC_N="$(grep -c '^- \*\*R[0-9][0-9]*\*\*' "$FIXTURE/view/spec.md" | tr -d ' ')"
SPEC_X_N="$(grep -c '^- \*\*R[0-9][0-9]*\*\*' "$FIXTURE/view/spec-extra.md" | tr -d ' ')"
[ "$SPEC_N" -gt 0 ] || die_unmeasured "the view fixture's spec holds no requirement bullet, so there is no figure to compare against"
[ "$SPEC_N" != "$SPEC_X_N" ] || die_unmeasured "the two view fixture specs hold the same number of requirements, so a figure that never moved would still match both. The premise failed; this is unmeasured, not a pass"

# PREMISE FOUR. The corrupt result must really not parse.
if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$FIXTURE/view/checks-result-corrupt.json" >/dev/null 2>&1; then  # stderr-ok: asking whether the fixture parses; the decode traceback IS the expected answer and printing it would look like a fault
  die_unmeasured "the fixture's corrupt result parses as JSON, so the page was never asked to render an unreadable source. The premise failed; this is unmeasured, not a pass"
fi

# --------------------------------------------------------------------------
# build the sandboxes. Everything under TMP; nothing under the tree being
# checked is created, moved, chmodded or removed.
# --------------------------------------------------------------------------
mk_view_repo() { # mk_view_repo <dir> <spec-file> <result-file>
  mkdir -p "$1/.claude/productizer"
  cp "$FIXTURE/view/config.json"       "$1/.claude/productizer/config.json"
  cp "$FIXTURE/$2"                     "$1/.claude/productizer/spec.md"
  cp "$FIXTURE/view/constitution.md"   "$1/.claude/productizer/constitution.md"
  cp "$FIXTURE/view/backlog.md"        "$1/.claude/productizer/backlog.md"
  cp "$FIXTURE/$3"                     "$1/.claude/productizer/checks-result.json"
  chmod u+rw "$1/.claude/productizer/spec.md" "$1/.claude/productizer/checks-result.json"
}

mk_view_repo "$TMP/v-three"   view/spec.md              view/checks-result.json
mk_view_repo "$TMP/v-five"    view/spec-extra.md        view/checks-result.json
mk_view_repo "$TMP/v-locked"  view/spec.md              view/checks-result.json
mk_view_repo "$TMP/v-corrupt" view/spec.md              view/checks-result-corrupt.json

chmod 000 "$TMP/v-locked/.claude/productizer/spec.md"

# PREMISE FIVE. The file just made unreadable has to be genuinely unreadable.
# Running as root reads a mode-000 file without complaint, and then the case was
# never tested. This asks by reading, not by testing the mode bits.
if head -c 1 "$TMP/v-locked/.claude/productizer/spec.md" >/dev/null 2>&1; then  # stderr-ok: asking whether a deliberately unreadable file is still readable; the permission error IS the answer
  die_unmeasured "the file this check made unreadable can still be read - running as root will do that - so a view was never asked to render an unreadable source. The premise failed; this is unmeasured, not a pass"
fi

for name in v-three v-five v-locked v-corrupt; do
  bash "$BUILD_VIEW" "$TMP/$name" --out "$TMP/$name.html" \
    >"$TMP/$name.out" 2>"$TMP/$name.err" || die_unmeasured "build-view.sh did not complete on the $name sandbox; the page was not generated, which is unmeasured and not a pass"
  [ -s "$TMP/$name.html" ] || die_unmeasured "build-view.sh wrote no page for the $name sandbox; there is nothing to read"
done

# --- the survey ------------------------------------------------------------
# Copied out of the repository first, so no repository history is in reach.
mkdir -p "$TMP/survey"
cp -R "$FIXTURE/survey/barren"    "$TMP/survey/barren"
cp -R "$FIXTURE/survey/evidenced" "$TMP/survey/evidenced"
bash "$IMPORT_SURVEY" "$TMP/survey/barren"    >"$TMP/barren.report"    2>"$TMP/barren.err"    || :
bash "$IMPORT_SURVEY" "$TMP/survey/evidenced" >"$TMP/evidenced.report" 2>"$TMP/evidenced.err" || :
[ -s "$TMP/barren.report" ]    || die_unmeasured "the survey printed no report for the barren fixture; there is nothing to read"
[ -s "$TMP/evidenced.report" ] || die_unmeasured "the survey printed no report for the evidenced fixture; there is nothing to read"

# --- the runner ------------------------------------------------------------
mkdir -p "$TMP/rc-unmeasured" "$TMP/rc-measured"
cp "$FIXTURE/runner/checks.yaml"          "$TMP/rc-unmeasured/checks.yaml"
cp "$FIXTURE/runner/changed.txt"          "$TMP/rc-unmeasured/changed.txt"
cp "$FIXTURE/runner/checks-measured.yaml" "$TMP/rc-measured/checks.yaml"
cp "$FIXTURE/runner/changed.txt"          "$TMP/rc-measured/changed.txt"
cp "$FIXTURE/runner/spec.md"              "$TMP/rc-measured/spec.md"

# PREMISE SIX. The spec the unmeasurable config names must be absent from its own
# sandbox, or the denominator was derivable after all.
[ -e "$TMP/rc-unmeasured/$DECLARED_SPEC" ] && die_unmeasured "the runner fixture's spec path exists in its sandbox, so the denominator was derivable and an unmeasured denominator was never tested. The premise failed; this is unmeasured, not a pass"

# The runner is EXPECTED to refuse: its fixture holds a check whose tool is
# absent, and refusing is the correct answer to that. Its exit code is not what
# is under test here; what it PRINTED is.
bash "$RUN_CHECKS" --config "$TMP/rc-unmeasured/checks.yaml" --root "$TMP/rc-unmeasured" \
  --changed "$TMP/rc-unmeasured/changed.txt" --out "$TMP/rc-unmeasured/result.json" \
  >"$TMP/rc-unmeasured.out" 2>"$TMP/rc-unmeasured.err" || :
bash "$RUN_CHECKS" --config "$TMP/rc-measured/checks.yaml" --root "$TMP/rc-measured" \
  --changed "$TMP/rc-measured/changed.txt" --out "$TMP/rc-measured/result.json" \
  >"$TMP/rc-measured.out" 2>"$TMP/rc-measured.err" || :
[ -s "$TMP/rc-unmeasured.err" ] || die_unmeasured "the runner printed nothing on the unmeasurable config; there is no reported line to read"
[ -s "$TMP/rc-measured.err" ]   || die_unmeasured "the runner printed nothing on the measurable config; there is no reported line to read"

# --- the hygiene check -----------------------------------------------------
mkdir -p "$TMP/hy"
cp "$FIXTURE/hygiene/patterns.txt" "$TMP/hy/patterns.txt"
cp "$FIXTURE/hygiene/clean.txt"    "$TMP/hy/clean.txt"
cp "$FIXTURE/hygiene/clean.txt"    "$TMP/hy/locked.txt"
chmod u+rw "$TMP/hy/patterns.txt" "$TMP/hy/clean.txt"
chmod 000 "$TMP/hy/locked.txt"

# PREMISE SEVEN. Same guard, second file: an unreadable file that reads is not an
# unreadable file.
if head -c 1 "$TMP/hy/locked.txt" >/dev/null 2>&1; then  # stderr-ok: same premise probe on the second file; the permission error IS the answer
  die_unmeasured "the file handed to the hygiene check as unreadable can still be read, so the tool was never asked about one. The premise failed; this is unmeasured, not a pass"
fi

HY_LOCKED_RC=0
bash "$HYGIENE" --patterns "$TMP/hy/patterns.txt" "$TMP/hy/locked.txt" \
  >"$TMP/hy-locked.out" 2>"$TMP/hy-locked.err" || HY_LOCKED_RC=$?
HY_CLEAN_RC=0
bash "$HYGIENE" --patterns "$TMP/hy/patterns.txt" "$TMP/hy/clean.txt" \
  >"$TMP/hy-clean.out" 2>"$TMP/hy-clean.err" || HY_CLEAN_RC=$?

# --- the status report -----------------------------------------------------
mkdir -p "$TMP/ss-corrupt/.claude/productizer" "$TMP/ss-absent/.claude/productizer"
cp "$FIXTURE/view/checks-result-corrupt.json" "$TMP/ss-corrupt/.claude/productizer/checks-result.json"
bash "$STAGE_STATUS" "$TMP/ss-corrupt" >"$TMP/ss-corrupt.out" 2>"$TMP/ss-corrupt.err" || :
bash "$STAGE_STATUS" "$TMP/ss-absent"  >"$TMP/ss-absent.out"  2>"$TMP/ss-absent.err"  || :
[ -s "$TMP/ss-corrupt.out" ] || die_unmeasured "the status report printed nothing for the unparseable result; there is no reported line to read"
[ -s "$TMP/ss-absent.out" ]  || die_unmeasured "the status report printed nothing for the absent result; there is no reported line to read"

# --------------------------------------------------------------------------
# assert
# --------------------------------------------------------------------------
cat > "$TMP/assert.py" <<'PY'
"""Twelve assertions over what four tools PRINTED, named and counted one by one.

Nothing here reads a result file: that is R26's evidence, and R25 is the claim
about the human-readable line. Nothing here reproduces a tool's stderr either -
it names temporary directories, and this output is tailed into a committed file.

stdout: one indented line per assertion. Exit 0 all held, 1 one did not, 2 the
evidence could not be read or a premise did not hold - neither of which is ever
reported as a pass.
"""
import io
import re
import sys

TMP, spec_n, spec_x_n, hy_locked_rc, hy_clean_rc = sys.argv[1:6]
spec_n = int(spec_n)
spec_x_n = int(spec_x_n)
hy_locked_rc = int(hy_locked_rc)
hy_clean_rc = int(hy_clean_rc)

out = sys.stdout
EVALUATED = 0
UPHELD = 0
FAILED = []


def say(name, held, text):
    """UPHELD IS COUNTED, NOT DERIVED. A total computed from one ok flag reports
    nothing upheld the moment one assertion fails, which contradicts the `held:`
    lines printed directly above it."""
    global EVALUATED, UPHELD
    EVALUATED += 1
    if held:
        UPHELD += 1
        out.write("  held:    %-6s %s\n" % (name, text))
    else:
        FAILED.append(name)
        out.write("  FINDING: %-6s did not hold - %s\n" % (name, text))


def premise_failed(text):
    out.write("  PREMISE did not hold - %s\n" % text)
    out.write("  Nothing was exercised. Unmeasured, not a pass.\n")
    sys.exit(2)


def read(name):
    try:
        with io.open("%s/%s" % (TMP, name), encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except (IOError, OSError) as exc:
        premise_failed("the evidence file %s could not be read: %s"
                       % (name, exc.__class__.__name__))


# --------------------------------------------------------------------------
# R11 - every figure on a regenerated view is read from a file in the repo
# --------------------------------------------------------------------------
# The four renderings the page has, told apart by the class the tile carries and
# by the glyph it draws. A digit is a measurement; the other three are not, and
# the whole requirement is that an unmeasurable figure never comes out as the
# first kind.
TILE_RE = re.compile(
    r'<span class="stat-l">(.*?)</span>'
    r'<span class="stat-n([^"]*)"[^>]*>(.*?)</span>')


def tiles(name):
    page = read(name)
    found = {}
    for m in TILE_RE.finditer(page):
        found[m.group(1)] = (m.group(2).strip(), m.group(3).strip())
    return found


def rendering(pair):
    """-> one of number / n-a / never-run / unreadable / other."""
    if pair is None:
        return "other"
    _cls, glyph = pair
    if re.match(r'^-?[0-9][0-9,]*$', glyph):
        return "number"
    if glyph == "n/a":
        return "n-a"
    if glyph == "—":
        return "never-run"
    if glyph == "?":
        return "unreadable"
    return "other"


LIVING = "Living spec"
CHECKS = "Checks, last run"

t3 = tiles("v-three.html")
t5 = tiles("v-five.html")
tl = tiles("v-locked.html")
tc = tiles("v-corrupt.html")

for label, tbl, where in ((LIVING, t3, "v-three"), (LIVING, t5, "v-five"),
                          (LIVING, tl, "v-locked"), (CHECKS, tc, "v-corrupt"),
                          (CHECKS, t3, "v-three")):
    if label not in tbl:
        premise_failed("the page built from %s carries no `%s` tile in the markup this "
                       "check reads, so no figure was examined" % (where, label))

out.write("  what the four builds rendered, per tile:\n")
for where, tbl in (("readable spec, 3 requirements", t3),
                   ("readable spec, 5 requirements", t5),
                   ("spec unreadable by permission", tl),
                   ("result present and unparseable", tc)):
    out.write("    %-32s %-16s %-10s %-16s %s\n"
              % (where, LIVING, rendering(tbl.get(LIVING)), CHECKS,
                 rendering(tbl.get(CHECKS))))

g3 = t3[LIVING][1]
g5 = t5[LIVING][1]
say("R11.1",
    g3 == str(spec_n) and g5 == str(spec_x_n) and g3 != g5,
    "a figure moves with its file: the spec holding %d requirements renders %r and the "
    "spec holding %d renders %r" % (spec_n, g3, spec_x_n, g5))

rl = rendering(tl.get(LIVING))
say("R11.2",
    rl in ("never-run", "unreadable", "n-a") and tl[LIVING][1] != "0",
    "an unreadable source renders an unmeasured marker, not a digit: `%s` reads %r (%s)"
    % (LIVING, tl[LIVING][1], rl))

rc = rendering(tc.get(CHECKS))
say("R11.3",
    rc == "unreadable",
    "a source that is present and will not parse renders the read-and-not-understood "
    "marker: `%s` reads %r (%s)" % (CHECKS, tc[CHECKS][1], rc))

say("R11.4",
    rendering(t3.get(LIVING)) == "number" and rendering(t3.get(CHECKS)) == "other"
    and t3[CHECKS][1] not in ("", "0"),
    "the honest inverse: with every source readable the same two tiles report measured "
    "values (%r and %r), so the markers above are a response to the source and not the "
    "page's normal state" % (t3[LIVING][1], t3[CHECKS][1]))

# --------------------------------------------------------------------------
# R20 - a survey with too little evidence refuses to draft
# --------------------------------------------------------------------------
REFUSAL = "NOT ENOUGH EVIDENCE TO DRAFT A SPEC."
TIER = "DRAFT TIER:"

barren = read("barren.report")
evidenced = read("evidenced.report")

say("R20.1",
    REFUSAL in barren and TIER not in barren,
    "a repository with essentially nothing in it reaches the refusing verdict: the report "
    "says %r and names no draft tier" % REFUSAL)

# The tally the verdict printed for itself, so the refusal can be checked against
# its own stated reason rather than taken on the word of one headline.
TALLY_RE = re.compile(r'^\s*(strong|weak)\s+[—-]\s+[^:]*:\s*(\d+) lines \(floor (\d+)\)',
                      re.M)
tally = {m.group(1): (int(m.group(2)), int(m.group(3))) for m in TALLY_RE.finditer(barren)}
if set(tally) != {"strong", "weak"}:
    premise_failed("the barren report printed no per-tier tally, so the refusal could not be "
                   "checked against the reason the survey gave for it")
out.write("  the barren survey's own tally: strong %d (floor %d), weak %d (floor %d)\n"
          % (tally["strong"][0], tally["strong"][1], tally["weak"][0], tally["weak"][1]))
say("R20.2",
    tally["strong"][0] < tally["strong"][1] and tally["weak"][0] < tally["weak"][1],
    "the refusal is grounded in the tally it printed, not unconditional: both tiers came "
    "back under the floors the report named beside them")

say("R20.3",
    TIER in evidenced and REFUSAL not in evidenced,
    "the other direction: a repository that does state its behaviour reaches a draft tier "
    "and does not refuse")

# --------------------------------------------------------------------------
# R25 - a value that could not be measured is REPORTED as unmeasured
# --------------------------------------------------------------------------
# Read from the printed streams only. Matched text is quoted back as the marker,
# never as the line: those lines carry temporary absolute paths.
rc_un = read("rc-unmeasured.err")
rc_me = read("rc-measured.err")

RUNNER_MARK = "spec coverage: UNMEASURED"
RUNNER_MEASURED = re.compile(r'^spec coverage: \d+ active requirement\(s\)', re.M)

say("R25.1",
    RUNNER_MARK in rc_un,
    "the runner reports a denominator it could not derive on the printed line, in words: "
    "%r" % RUNNER_MARK)

say("R25.2",
    RUNNER_MARK not in rc_me and RUNNER_MEASURED.search(rc_me) is not None,
    "the runner's inverse: with a derivable denominator the same line reports the measured "
    "count and does not say UNMEASURED")

hy_locked = read("hy-locked.err")
hy_locked_out = read("hy-locked.out")
hy_clean = read("hy-clean.err")

HY_MARK = "Unmeasured, not clean"
say("R25.3",
    HY_MARK in hy_locked and hy_locked_rc == 2 and hy_locked_out.strip() == "",
    "the hygiene check reports a file it could not open as %r, exits %d rather than 0, and "
    "counts it as nothing examined" % (HY_MARK, hy_locked_rc))

say("R25.4",
    HY_MARK not in hy_clean and hy_clean_rc == 0,
    "the hygiene check's inverse: a readable, clean file exits %d and says nothing about "
    "being unmeasured, so the marker above is a response to the file" % hy_clean_rc)

ss_corrupt = read("ss-corrupt.out")
ss_absent = read("ss-absent.out")
STAGE5_RE = re.compile(r'^\s*5\s+\S+\s+(\S+(?: \S+)?)\s{2,}', re.M)


def stage5(text):
    m = STAGE5_RE.search(text)
    return m.group(1).strip() if m else None


s_corrupt = stage5(ss_corrupt)
s_absent = stage5(ss_absent)
if s_corrupt is None or s_absent is None:
    premise_failed("the status report printed no stage 5 row this check could read, so the "
                   "word it uses for an unreadable result was never examined")
out.write("  the status report's stage 5: unparseable result -> %r, absent result -> %r\n"
          % (s_corrupt, s_absent))
say("R25.5",
    s_corrupt == "unknown" and s_absent == "not run" and s_corrupt != s_absent,
    "the status report keeps two words for two facts: a result present and unparseable is "
    "reported %r, one never written is reported %r, and neither is a number"
    % (s_corrupt, s_absent))

out.write("  assertions evaluated: %d, upheld: %d\n" % (EVALUATED, UPHELD))
if FAILED:
    out.write("  did not hold: %s\n" % ", ".join(FAILED))
    sys.exit(1)
sys.exit(0)
PY

ARC=0
python3 "$TMP/assert.py" "$TMP" "$SPEC_N" "$SPEC_X_N" "$HY_LOCKED_RC" "$HY_CLEAN_RC" || ARC=$?

case "$ARC" in
  0) printf '  R11, R20 and R25 satisfied: a figure that could not be measured is drawn as a marker and never as a number, a survey with nothing to draft from refuses, and each tool says the word on the line a person reads.\n'
     exit 0 ;;
  1) printf '  Not satisfied: see the findings above, each named for the requirement it belongs to. A value nobody could measure has been reported as though somebody had.\n'
     exit 1 ;;
  *) die_unmeasured "the assertions could not be evaluated; unmeasured, not a pass" ;;
esac
