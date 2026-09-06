#!/usr/bin/env bash
# check-nothing-merged.sh [--root DIR] [--fixture DIR] [--merge-command PROGRAM]
#                        [--version] [--help] [--selftest]
#
# Asserts R24: IF AN INTENT CONTRADICTS AN ACTIVE REQUIREMENT, THEN THE
# LIFECYCLE SHALL MERGE NOTHING.
#
# R23 - the STOP - is asserted twice already: `contradiction-check.py
# --selftest` proves the conflict is detected, and the `ruling-requested` check
# proves a question reaches a human. Neither of them looks at the spec
# afterwards. R24's acceptance row said so in as many words: "not yet verified
# - R14's checks asserted the stop; no check yet observes that nothing was
# merged." A stop that halts loudly and merges quietly passes both existing
# checks. This is the standing case that would go red.
#
# HOW IT ANSWERS THE QUESTION. Not by reading the code and reasoning about what
# it would do - a structural claim goes stale the first time somebody refactors
# it. It TRIGGERS THE CONDITION and observes that nothing moved: a fixture
# repository holding a small spec with one active requirement, an intent that
# contradicts it, the contradiction path actually run against a copy of it, and
# the spec compared byte for byte with what it was.
#
# WHAT IT ASSERTS, AND WHY EACH ONE IS SEPARATE. A single boolean says a merge
# happened and not which half of the file moved, so each is measured on its own
# and reported by name.
#
#   1  THE SPEC IS BYTE-IDENTICAL, outside the one table the stop is required
#      to write. sha256 of the whole file with the *Areas of concern* section
#      excised, before against after. That table is excised because recording
#      the conflict there is step 3 of references/rulings.md and
#      check-ruling-requested.sh fails when it is missing - demanding byte
#      identity of the whole file would fail the correct behaviour. Every other
#      byte of the spec must be exactly what it was.
#
#   2  NO REQUIREMENT ID WAS ALLOCATED. Four measures, because an id can be
#      taken four ways: the `Next requirement id` counter still reads what it
#      read; the list of requirement definitions under `## Requirements` is
#      unchanged text for text; the set of distinct `R<n>` ids OUTSIDE the
#      excised table has gained nothing; and every `R<n>` INSIDE that table
#      names a requirement that already existed, since the one region
#      assertion 1 cannot see is the one region an id could otherwise be taken
#      in unobserved. That fourth measure exists because the first three were
#      falsified and did not go red: an id written into the concern table was
#      invisible, and the counter's own `R2` masked it from a whole-file id
#      set. references/rulings.md is the authority: "Do not allocate a
#      requirement id for the incoming behaviour. An id in the spec is a merge,
#      whatever the surrounding prose says." A contradiction that quietly took
#      the next id has merged the losing side even though no sentence changed.
#
#   3  THE CHANGE LOG GAINED NO ROW. Its data rows, in order, unchanged. R7
#      puts every classification in this table, so a contradict classification
#      writing itself a row here is the merge arriving through the log.
#
#   4  THE ACCEPTANCE CRITERIA TABLE GAINED NO ROW. Same measure. R8 says a new
#      requirement is recorded here, so a row here is an id that landed.
#
# 3 and 4 are largely implied by 1 and are still measured separately, because
# "the spec changed" and "the change log gained a row" send a reader to
# different places.
#
# THE PREMISE IS CHECKED FIRST, AND IT IS NOT AN ASSERTION. If the fixture's
# intent does not actually contradict the fixture's requirement, the condition
# R24 speaks about never occurred and the run proves nothing about it. That is
# exit 2 - unmeasured - and never a pass. The premise is settled by
# `contradiction-check.py --pair`, arithmetically, not by this file's opinion.
# The path that would merge must also have run to completion; a refusal leaves
# the spec untouched for the wrong reason, which would be a pass earned by an
# error.
#
# THE FIXTURE IS COPIED, NEVER RUN IN PLACE. The contradiction path WRITES: it
# creates a ruling file and appends a concern row. Pointing it at this
# repository would make a test of the lifecycle a writer to the tree under
# test, and pointing it at the fixture directory would leave the fixture
# altered after the first run, so the second run would measure something else.
#
# --merge-command NAMES THE PATH THAT WOULD MERGE. It defaults to
# `request-ruling.sh` beside this script, which is what the lifecycle actually
# runs at the moment an intent is classified contradict, and which is the only
# script in the skill that writes the spec at all. The option exists for two
# reasons: a repo whose contradiction path is some other program can point this
# at it, and every assertion above can be OBSERVED FAILING by pointing it at a
# program that merges. An assertion never seen red asserts nothing. The value
# is a program path run with three arguments - the sandbox root, the intent
# file inside it, the contradicted requirement id - and never a shell string,
# so nothing here evaluates a command line.
#
# NEITHER THE SPEC NOR THE INTENT IS EVER QUOTED. Both are text a stranger can
# write, and this output is tailed into a committed result file. Findings name
# a LOCATION and a class of problem: which measure moved, in which section.
# The premise reports the verdict word and not the sentences it compared, for
# the same reason.
#
# PATHS ARE PRINTED RELATIVE to the root, so no absolute path - which is
# somebody's home directory - reaches a committed file.
#
# ONE LINE PER FILE EXAMINED, on stdout, unindented; assertions are INDENTED.
# The runner parses the unindented lines as coverage and calls a clean exit
# having examined nothing HOLLOW, which is a failure.
#
# KNOWN LIMITATIONS, written down rather than discovered later:
#   - Assertion 1 cannot see a change made INSIDE the *Areas of concern*
#     section, which it excises. An id taken in that table is caught by
#     assertion 2's fourth measure; prose written into it is not caught at all,
#     which is the price of not failing the row the stop is required to write.
#   - The fixture proves the contradiction path merges nothing. It cannot prove
#     that no other program in the repo merges, because no other program in the
#     repo writes the spec; if one is added, this check will not know.
#   - A `## ` heading inside a fenced code block in the spec would confuse the
#     section split. No spec in this repo has one.
#
# PORTABILITY. macOS/BSD bash. No mapfile, no `grep -P`, no `date -d`, no
# GNU in-place sed. The fixture names no absolute path, so a fresh clone on
# another machine runs the same case.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every assertion held - the contradiction path merged nothing
#   1  an assertion failed - something merged on a contradiction
#   2  could not run - bad usage, no fixture, no contradiction checker, no
#      python3, a premise that did not hold, or a merge path that never ran.
#      Never confused with 0.
#
# --SELFTEST DRIVES ALL THREE, AND IT USES THE HOOK THE HEADER ALREADY NAMED.
# `--merge-command` was written so that "every assertion above can be OBSERVED
# FAILING by pointing it at a program that merges", and until now nothing
# committed did the pointing - the hook existed and the falsification lived in
# somebody's terminal history. Five cases run under `mktemp -d`: the default
# contradiction path, which must merge nothing; a program written on the spot
# that DOES merge, which must be caught; a merge path that errors, which is
# not a spec the lifecycle declined to merge; an intent that does not
# contradict, so R24's condition never occurred; and bad usage. Each runs THIS
# script and its exit code is compared with the one the case declares.
#
# The spec that gets merged into is a COPY under the temporary directory. The
# committed fixture is read and never written, so the second run measures the
# same case as the first.
#
# Under --selftest the three codes mean: every case produced the code it
# declares (0), at least one did not (1), and the cases could not be built or
# driven at all (2). `--self-test` is accepted as an alias because the repo
# spells it both ways. Note that the `--selftest` named at the top of this
# header belongs to `contradiction-check.py` and always did; it is a
# cross-reference to another tool's self-test, not a claim about this one.
set -euo pipefail

VERSION="check-nothing-merged 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$HERE")"

ROOT=""
FIXTURE="$SKILL/fixtures/nothing-merged"
MERGE_COMMAND=""
MODE="measure"

usage() {
  printf 'usage: check-nothing-merged.sh [--version] [--help] [--root DIR] [--fixture DIR] [--merge-command PROGRAM] [--selftest]\n'
  printf '  --root DIR             what printed paths are relative to. Defaults to the\n'
  printf '                         git top level, never to the working directory.\n'
  printf '  --fixture DIR          the standing case. Defaults to fixtures/nothing-merged\n'
  printf '                         beside this script.\n'
  printf '  --merge-command PROG   the path that would merge, run as\n'
  printf '                         PROG <sandbox-root> <intent-file> <requirement-id>.\n'
  printf '                         Defaults to request-ruling.sh beside this script.\n'
  printf '  --selftest             drive this check against five built cases and read\n'
  printf '                         the exit code off each. --self-test is an alias.\n'
  printf 'exit: 0 nothing merged - 1 something merged - 2 could not run\n'
}

die_unmeasured() { printf 'check-nothing-merged: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)          [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";            ROOT="$2";          shift 2 ;;
    --root=*)        ROOT="${1#--root=}";                   shift ;;
    --fixture)       [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path";         FIXTURE="$2";       shift 2 ;;
    --fixture=*)     FIXTURE="${1#--fixture=}";             shift ;;
    --merge-command) [ "$#" -ge 2 ] || die_unmeasured "--merge-command needs a program"; MERGE_COMMAND="$2"; shift 2 ;;
    --merge-command=*) MERGE_COMMAND="${1#--merge-command=}"; shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --) shift; break ;;
    -*) printf 'check-nothing-merged: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *)  printf 'check-nothing-merged: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1"

# ---------------------------------------------------------------------------
# --selftest: build the cases, drive THIS script against each, read the exit
# code off it. The committed fixture is READ by these cases and never written.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-nothing-merged-selftest.XXXXXX")" \
    || die_unmeasured "cannot create a temporary directory to build the cases in; nothing was driven"
  # Removed on every exit path, signal included. Nothing is written into the
  # repository this script lives in, nor into the committed fixture.
  trap 'rm -rf "$WORK"' EXIT HUP INT TERM

  CASES=0; UPHELD=0; REPORT=""
  REACHED_0=0; REACHED_1=0; REACHED_2=0

  # `|| GOT=$?` on the same line as the command. A `$(...)` in an argument list
  # and a pipeline both RESET `$?`, and reading the status one line later is
  # how a self-test comes to report a pass it never observed.
  drive() {
    NAME="$1"; WANT="$2"; WHY="$3"; shift 3
    GOT=0
    bash "$0" "$@" > "$WORK/$NAME.out" 2> "$WORK/$NAME.err" || GOT=$?
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

  # A program that MERGES. This is the falsification the header promised and
  # never committed: it takes the incoming behaviour's id, writes it into the
  # spec under `## Requirements`, gives it a change-log row and advances the
  # counter - three of the four ways R24 can be violated, in one run. It exits
  # 0, because a merge path that errors is a different case, below.
  cat > "$WORK/merger.sh" <<'MERGER'
#!/usr/bin/env bash
# $1 sandbox root · $2 intent file · $3 the contradicted requirement id
set -euo pipefail
SPEC="$1/.claude/productizer/spec.md"
awk '
  /^- \*\*R1\*\*/ {
    print
    print "- **R2** — If a request body fails schema validation, then the service shall accept it anyway."
    next
  }
  /^\| 2026-08-31 \|/ {
    print
    print "| 2026-09-01 | — | — | R2 | — | — | the losing side of a contradiction, merged. |"
    next
  }
  { print }
' "$SPEC" > "$SPEC.merged"
sed -e 's/`R2` — allocate from here/`R3` — allocate from here/' "$SPEC.merged" > "$SPEC"
rm -f "$SPEC.merged"
MERGER

  # A merge path that ERRORS. A spec left untouched because the program died
  # is not a spec the lifecycle declined to merge, and reading the two the same
  # way is a pass earned by an error.
  printf '#!/usr/bin/env bash\nexit 3\n' > "$WORK/broken.sh"

  # An intent that AGREES. R24's condition never occurs, so nothing about R24
  # was tested and the run has to say so rather than pass.
  mkdir -p "$WORK/agreeing-fixture" \
    || die_unmeasured "could not lay out the agreeing-intent case"
  cp "$FIXTURE/spec.md" "$WORK/agreeing-fixture/spec.md" \
    || die_unmeasured "the committed fixture's spec.md could not be copied, so the premise case could not be built"
  printf 'The incoming intent, restating the requirement rather than contradicting it.\n\nIf a request body fails schema validation, then the service shall reject it with 400.\n' \
    > "$WORK/agreeing-fixture/intent.md"

  # 0 - the default contradiction path, which is the thing under test. Without
  # it every failing case below proves only that something is red.
  drive nothing-merged 0 "the default contradiction path against the committed fixture" \
    --root "$WORK"

  # 1 - a path that merges. This is the case that decides whether the four
  # assertions are worth anything at all.
  drive a-merger 1 "a merge path that allocates R2, logs it and advances the counter" \
    --root "$WORK" --merge-command "$WORK/merger.sh"

  # 2 - the merge path never ran to completion.
  drive merge-path-errors 2 "a merge path that exits 3, so the spec is untouched for the wrong reason" \
    --root "$WORK" --merge-command "$WORK/broken.sh"

  # 2 - the premise. An intent that does not contradict never entered the state
  # R24 speaks about.
  drive premise-not-met 2 "an intent that restates the requirement instead of contradicting it" \
    --root "$WORK" --fixture "$WORK/agreeing-fixture"

  # 2 - bad usage, reaching the same code through the argument parser.
  drive bad-usage 2 "an option this script does not take" \
    --root "$WORK" --frobnicate

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
  printf '    NOT ASSERTED: the merger case proves the four assertions can go red together; it does NOT prove each one goes red on its own, which is read off the a-merger case output by hand\n'
  [ "$CASES" = "$UPHELD" ] || exit 1
  exit 0
fi

# The work tree, never the working directory. Defaulting to the working
# directory has caused several silent wrong answers here: the script reads a
# directory that is not the repo and reports a confident clean result. --root
# does not decide WHAT is tested - the fixture and the merge path are found
# beside this script - only what the printed paths are relative to.
GIVEN_ROOT=0
if [ -n "$ROOT" ]; then
  GIVEN_ROOT=1
else
  ROOT="$(git rev-parse --show-toplevel)" || ROOT=""
fi
if [ -n "$ROOT" ] && [ -d "$ROOT" ] && [ -x "$ROOT" ]; then
  ROOT="$(cd "$ROOT" && pwd -P)" || die_unmeasured "--root could not be entered, so printed paths cannot be made relative to it"
elif [ "$GIVEN_ROOT" -eq 1 ]; then
  # A root that was ASKED for and cannot be used is an error, not a cue to
  # quietly measure against a different one.
  die_unmeasured "--root $ROOT is not a directory this process can enter"
else
  # An installed plugin is not a repository. Paths are then relative to the
  # skill directory, which is still not absolute.
  ROOT="$SKILL"
fi

DEFAULT_MERGE="$HERE/request-ruling.sh"
CONTRA="$HERE/contradiction-check.py"
USING_DEFAULT=1
if [ -n "$MERGE_COMMAND" ]; then
  USING_DEFAULT=0
else
  MERGE_COMMAND="$DEFAULT_MERGE"
fi

command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the spec could not be compared"
[ -f "$CONTRA" ] || die_unmeasured "no contradiction-check.py beside this script, so the fixture's premise cannot be settled. Unmeasured, not a pass"
[ -d "$FIXTURE" ] || die_unmeasured "no fixture directory; the standing case is missing, which is unmeasured and not a pass"
# A directory that cannot be entered is UNKNOWN, and unknown is exit 2. Left to
# `set -e` the failing `cd` below exits 1, which the runner reads as a finding -
# a check that could not run reporting as a check that ran and found something.
{ [ -r "$FIXTURE" ] && [ -x "$FIXTURE" ]; } || die_unmeasured "the fixture directory cannot be listed, so the standing case could not be read. Unmeasured, not a pass"
FIXTURE="$(cd "$FIXTURE" && pwd -P)" || die_unmeasured "the fixture directory could not be entered. Unmeasured, not a pass"
FIX_SPEC="$FIXTURE/spec.md"
FIX_INTENT="$FIXTURE/intent.md"
[ -f "$FIX_SPEC" ] && [ -r "$FIX_SPEC" ] || die_unmeasured "the fixture has no readable spec.md; there is no active requirement to contradict"
[ -f "$FIX_INTENT" ] && [ -r "$FIX_INTENT" ] || die_unmeasured "the fixture has no readable intent.md; there is no incoming intent"
[ -f "$MERGE_COMMAND" ] && [ -r "$MERGE_COMMAND" ] || die_unmeasured "the merge path $(basename "$MERGE_COMMAND") is not a readable file, so the path that would merge was never taken"

rel() {
  case "$1" in
    "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;;
    *)         printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;;
  esac
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-nothing-merged.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

# --------------------------------------------------------------------------
# The premise. Not an assertion: if these two do not conflict, R24's condition
# never occurred and nothing about R24 was tested.
# --------------------------------------------------------------------------
# The first ACTIVE requirement definition in the fixture spec: a top-level list
# item under `## Requirements` whose following line is not a status marker.
REQ_ID="$(awk '
  /^## / { inreq = ($0 ~ /^##[ \t]+Requirements[ \t]*$/) ? 1 : 0; next }
  !inreq { next }
  match($0, /^[ \t]*[-*][ \t]+\*\*R[0-9]+\*\*/) {
    line = substr($0, RSTART, RLENGTH)
    sub(/^[^R]*/, "", line); sub(/\*\*$/, "", line)
    print line; exit
  }' "$FIX_SPEC")"
[ -n "$REQ_ID" ] || die_unmeasured "the fixture spec defines no requirement under ## Requirements, so there is nothing for an intent to contradict. Unmeasured, not a pass"

REQ_TEXT="$(awk -v id="$REQ_ID" '
  /^## / { inreq = ($0 ~ /^##[ \t]+Requirements[ \t]*$/) ? 1 : 0; next }
  !inreq { next }
  $0 ~ ("^[ \t]*[-*][ \t]+\\*\\*" id "\\*\\*") {
    line = $0
    sub(/^[ \t]*[-*][ \t]+\*\*R[0-9]+\*\*[ \t]*/, "", line)
    sub(/^[^A-Za-z]+/, "", line)
    print line; exit
  }' "$FIX_SPEC")"
[ -n "$REQ_TEXT" ] || die_unmeasured "$REQ_ID has no sentence after its id. Unmeasured, not a pass"

# The intent's statement is its last non-empty line; everything above it is the
# fixture's own commentary.
INTENT_TEXT="$(awk 'NF { last = $0 } END { print last }' "$FIX_INTENT")"
[ -n "$INTENT_TEXT" ] || die_unmeasured "the fixture's intent.md is empty. Unmeasured, not a pass"

PRC=0
python3 "$CONTRA" --pair "$REQ_TEXT" "$INTENT_TEXT" > "$TMP/premise.out" 2> "$TMP/premise.err" || PRC=$?
VERDICT="$(sed -n '1s/:.*//p' "$TMP/premise.out")"
if [ "$PRC" -ne 1 ] || [ "$VERDICT" != "CONTRADICTION" ]; then
  die_unmeasured "the fixture's intent does not contradict $REQ_ID - the checker returned ${VERDICT:-no verdict} (exit $PRC). R24's condition never occurred, so this run says nothing about whether a contradiction merges. Unmeasured, not a pass"
fi

# --------------------------------------------------------------------------
# Run the path that would merge, against a COPY.
# --------------------------------------------------------------------------
SANDBOX="$TMP/repo"
mkdir -p "$SANDBOX/.claude/productizer"
cp "$FIX_SPEC" "$SANDBOX/.claude/productizer/spec.md"
cp "$FIX_INTENT" "$SANDBOX/intent.md"
cp "$SANDBOX/.claude/productizer/spec.md" "$TMP/before.md"

rel "$FIX_SPEC"
rel "$FIX_INTENT"
rel "$CONTRA"
if [ "$USING_DEFAULT" -eq 1 ]; then
  rel "$MERGE_COMMAND"
fi

MRC=0
if [ "$USING_DEFAULT" -eq 1 ]; then
  bash "$MERGE_COMMAND" --root "$SANDBOX" --against "$REQ_ID" \
    --intent-file "$SANDBOX/intent.md" > "$TMP/merge.out" 2> "$TMP/merge.err" || MRC=$?
else
  bash "$MERGE_COMMAND" "$SANDBOX" "$SANDBOX/intent.md" "$REQ_ID" \
    > "$TMP/merge.out" 2> "$TMP/merge.err" || MRC=$?
fi
if [ "$MRC" -ne 0 ]; then
  die_unmeasured "the path that would merge exited $MRC, so it never ran to completion. A spec left untouched by an error is not a spec the lifecycle declined to merge. Unmeasured, not a pass"
fi
cp "$SANDBOX/.claude/productizer/spec.md" "$TMP/after.md"

if [ "$USING_DEFAULT" -eq 0 ]; then
  printf '  note: the merge path was overridden on the command line, so the default contradiction path was not the thing exercised.\n'
fi
printf '  premise: the intent contradicts %s, and the path that would merge ran to completion.\n' "$REQ_ID"

cat > "$TMP/assert.py" <<'PY'
"""Compare the fixture spec before and after the contradiction path ran.

stdout: one indented line per assertion. Exit 0 all held, 1 one did not,
2 the comparison could not be made at all - which is never a pass, because a
spec nobody could parse is not a spec that was observed unchanged.
"""
import hashlib
import re
import sys

before_path, after_path = sys.argv[1:3]
out = sys.stdout
ok = True

HEADING = re.compile(r"^##[ \t]+(.*?)[ \t]*$")
DEFN = re.compile(r"^[ \t]*[-*][ \t]+\*\*(R\d+)\*\*")
RID = re.compile(r"\bR\d+\b")
SEP = re.compile(r"^[ \t]*\|[ \t:|-]+\|[ \t]*$")


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def lines_of(text):
    return text.split("\n")


def sections(text):
    """name -> (start, end) line indices, end exclusive. Bare `## ` only."""
    ls = lines_of(text)
    marks = []
    for i, ln in enumerate(ls):
        m = HEADING.match(ln)
        if m:
            marks.append((i, m.group(1)))
    found = {}
    for j, (i, name) in enumerate(marks):
        end = marks[j + 1][0] if j + 1 < len(marks) else len(ls)
        found.setdefault(name, (i, end))
    return ls, found


def excise(text, name):
    ls, secs = sections(text)
    if name not in secs:
        return None
    s, e = secs[name]
    return "\n".join(ls[:s] + ls[e:])


def table_rows(text, name):
    ls, secs = sections(text)
    if name not in secs:
        return None
    s, e = secs[name]
    rows = []
    for ln in ls[s:e]:
        if not ln.lstrip().startswith("|"):
            continue
        if SEP.match(ln):
            continue
        rows.append(ln.strip())
    return rows[1:] if rows else rows          # drop the header row


def definitions(text):
    ls, secs = sections(text)
    if "Requirements" not in secs:
        return None
    s, e = secs["Requirements"]
    return [ln.strip() for ln in ls[s:e] if DEFN.match(ln)]


def counter(text):
    ls = lines_of(text)
    for i, ln in enumerate(ls):
        if ln.strip() == "Next requirement id":
            for nxt in ls[i + 1:]:
                if not nxt.strip():
                    break
                m = RID.search(nxt)
                if m:
                    return m.group(0)
            return None
    return None


def ids_outside_concerns(text):
    """Distinct R ids everywhere except the table the stop writes to."""
    trimmed = excise(text, "Areas of concern")
    return sorted(set(RID.findall(text if trimmed is None else trimmed)))


def ids_inside_concerns(text):
    ls, secs = sections(text)
    if "Areas of concern" not in secs:
        return []
    s, e = secs["Areas of concern"]
    return sorted(set(RID.findall("\n".join(ls[s:e]))))


def defined_ids(text):
    d = definitions(text)
    return [] if d is None else [DEFN.match(ln).group(1) for ln in d]


before, after = read(before_path), read(after_path)

# Everything below needs these to exist in the BEFORE file. A fixture that
# carries none of them was never a spec, and comparing it says nothing.
missing = [n for n in ("Requirements", "Areas of concern", "Acceptance criteria",
                       "Change log") if n not in sections(before)[1]]
if missing:
    out.write("  the fixture spec has no %s section, so nothing could be "
              "compared\n" % ", ".join("`## %s`" % m for m in missing))
    out.write("  assertions evaluated: 0 of 4. Unmeasured, not a pass.\n")
    sys.exit(2)
if counter(before) is None:
    out.write("  the fixture spec carries no `Next requirement id` line, so an "
              "allocated id could not be detected\n")
    out.write("  assertions evaluated: 0 of 4. Unmeasured, not a pass.\n")
    sys.exit(2)


UPHELD = 0


def say(held, text):
    global ok, UPHELD
    if held:
        UPHELD += 1
    else:
        ok = False
    out.write("  %s %s\n" % ("held:" if held else "FINDING: did not hold -", text))


def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# 1 - byte-identical outside the one table the stop is required to write.
b_ex, a_ex = excise(before, "Areas of concern"), excise(after, "Areas of concern")
if a_ex is None:
    say(False, "1 spec byte-identical outside `## Areas of concern`: that "
               "section is gone from the spec after the run, so the comparison "
               "the assertion makes no longer has a subject")
else:
    say(digest(b_ex) == digest(a_ex),
        "1 spec byte-identical outside `## Areas of concern` (sha256 "
        "%s..%s before, %s..%s after)"
        % (digest(b_ex)[:8], digest(b_ex)[-4:], digest(a_ex)[:8], digest(a_ex)[-4:]))

# 2 - no requirement id was allocated. Three ways to take one, three measures.
b_c, a_c = counter(before), counter(after)
b_d, a_d = definitions(before), definitions(after)
b_i, a_i = ids_outside_concerns(before), ids_outside_concerns(after)
why = []
if b_c != a_c:
    why.append("the `Next requirement id` counter moved")
if a_d is None:
    why.append("`## Requirements` is gone from the spec")
elif b_d != a_d:
    why.append("the requirement definitions under `## Requirements` changed "
               "(%d before, %d after)" % (len(b_d), len(a_d)))
new_ids = [i for i in a_i if i not in b_i]
if new_ids:
    why.append("%d id(s) appear outside `## Areas of concern` that were not "
               "there before" % len(new_ids))
# The excised table is the one place assertion 1 cannot see, so an id taken
# there would otherwise be invisible. A concern row may cite a requirement
# that already existed; an id that was never defined is an allocation.
known = defined_ids(before)
smuggled = [i for i in ids_inside_concerns(after) if i not in known]
if smuggled:
    why.append("%d id(s) inside `## Areas of concern` name no requirement that "
               "existed before the run" % len(smuggled))
say(not why,
    "2 no requirement id was allocated%s" % ("" if not why else ": " + "; ".join(why)))

# 3 - the change log gained no row.
b_cl, a_cl = table_rows(before, "Change log"), table_rows(after, "Change log")
if a_cl is None:
    say(False, "3 the change log gained no row: `## Change log` is gone from "
               "the spec after the run")
else:
    say(b_cl == a_cl,
        "3 the change log gained no row (%d data rows before, %d after)"
        % (len(b_cl), len(a_cl)))

# 4 - the acceptance criteria table gained no row.
b_ac, a_ac = table_rows(before, "Acceptance criteria"), table_rows(after, "Acceptance criteria")
if a_ac is None:
    say(False, "4 the acceptance criteria table gained no row: `## Acceptance "
               "criteria` is gone from the spec after the run")
else:
    say(b_ac == a_ac,
        "4 the acceptance criteria table gained no row (%d data rows before, "
        "%d after)" % (len(b_ac), len(a_ac)))

# Informational, not an assertion: the stop's own row. Unknown is an em dash,
# never a zero - a table that could not be read has no count.
b_oc, a_oc = table_rows(before, "Areas of concern"), table_rows(after, "Areas of concern")
if a_oc is None or b_oc is None:
    added = "—"
else:
    added = str(len(a_oc) - len(b_oc))
out.write("  concern rows the stop added: %s\n" % added)
out.write("  assertions evaluated: 4, upheld: %d\n" % UPHELD)
sys.exit(0 if ok else 1)
PY

ARC=0
python3 "$TMP/assert.py" "$TMP/before.md" "$TMP/after.md" || ARC=$?

case "$ARC" in
  0) printf '  R24 satisfied: an intent that contradicts an active requirement merged nothing.\n'; exit 0 ;;
  1) printf 'FAIL: a contradicting intent merged something. R24 says the lifecycle shall merge nothing; the findings above name what moved.\n' >&2; exit 1 ;;
  *) die_unmeasured "the assertions could not be evaluated; unmeasured, not a pass" ;;
esac
