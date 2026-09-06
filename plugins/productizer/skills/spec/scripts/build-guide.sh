#!/usr/bin/env bash
# build-guide.sh [--root DIR] [--spec FILE] [--guide FILE] [--check]
#                [--selftest|--self-test] [--version] [--help]
#
# R9 - when a release is prepared, the lifecycle shall regenerate the user
# guide from the active requirements. This is that regeneration, and it is
# deliberately narrow.
#
# WHAT IT GENERATES, AND WHAT IT REFUSES TO TOUCH.
#
# GUIDE.md is written prose, and it is good BECAUSE it is written prose. A
# guide regenerated wholesale out of EARS sentences would be accurate,
# unreadable, and therefore unread - a worse failure than a stale one, and a
# quieter one. So this writes exactly ONE section, the active requirement set,
# between two markers. Every byte outside them is left as its author left it.
#
# MARKERS ABSENT IS A REFUSAL, NOT A BEST GUESS. A generator that picks a
# plausible spot overwrites a paragraph somebody wrote, and prose does not come
# back the way a regenerated section does. It exits 2 and prints the two lines
# to paste where the section belongs.
#
# SUPERSEDED AND WITHDRAWN REQUIREMENTS ARE NOT RENDERED. This section says
# what the product does now. A replaced requirement stays in the spec forever -
# that is R3 - but nothing in the sentence itself tells a reader it stopped
# being true, so a reader who acts on one from the guide acts on behaviour that
# was withdrawn.
#
# NO CLOCK IS WRITTEN. No generation date, no "last updated". A wall clock in
# the output makes two runs against an unchanged spec differ, and --check would
# then go red every day for a reason that has nothing to do with the
# requirements. The section is a function of the spec's content and of nothing
# else, which is the whole reason its staleness is worth acting on. Anywhere a
# date is ever needed it is taken UTC.
#
# --ROOT DEFAULTS TO THE WORK TREE, NEVER THE WORKING DIRECTORY. Defaulting to
# `.` writes a GUIDE.md into whatever directory the release happened to be run
# from, and the real one stays stale while a run reports success.
#
# --CHECK REGENERATES INTO MEMORY AND WRITES NOTHING, so a release can be gated
# on the guide being current. It names the ids that drifted, because "GUIDE.md
# is stale" is not actionable and "R29 is in the spec and not in the guide" is.
#
# ==========================================================================
# WHAT IS ASSERTED ABOUT THE OTHER 615 LINES, AND WHAT IS NOT.
# ==========================================================================
#
# The generated section is about 85 lines of a 700-line file. Until 1.1 it was
# the only thing asserted, and an audit proved what that costs: prose inserted
# immediately AFTER the closing marker, flatly contradicting two active
# requirements, passed clean. Everything outside the markers could disagree
# with the spec and stay green.
#
# THE OBVIOUS FIX IS THE WRONG ONE. A guide is prose. Demanding that it repeat
# the spec's sentences would go red on every correct guide ever written, and a
# check that reddens on correct input gets switched off - after which nothing
# is checked at all. So this asserts only what can be TRUE of prose:
#
#   R9.a  the marker-delimited section is byte-identical to a fresh render
#   R9.b  every active requirement's row in the committed guide is the row the
#         spec produces today - counted per id, not as one flag
#   R9.c  every requirement id written as BARE PROSE outside the section names
#         a requirement the spec defines
#   R9.d  no sentence outside the section pairs a defined id with a status
#         word the spec denies - an active requirement called `withdrawn`, a
#         superseded one called `still active`
#
# THE CLOSED VOCABULARY IS PRINTED ON EVERY RUN, and so is every id mentioned
# outside the section with its file line and its status, so a reader who
# disagrees argues with the LIST rather than with a verdict whose rule is
# invisible. The vocabulary was measured against the committed GUIDE.md before
# it was chosen: one sentence matched, `Superseded by R58.`, and R58 names no
# requirement so it is not examined. A wider net - `never`, `optional`,
# `only`, `just` - matched ordinary prose in five places and was dropped.
#
# WHAT IS DELIBERATELY NOT ASSERTED, because none of it can be decided without
# reading English:
#
#   - a statement that contradicts a requirement WITHOUT naming its id. The
#     largest remaining hole. 1.2 tried to close it, MEASURED THE ATTEMPT AND
#     ABANDONED IT; the numbers are below so nobody rebuilds the same rule.
#   - any semantic disagreement between the guide's prose and a requirement's
#     wording. `R17 blocks deploys` against `R17 blocks publishes` reads the
#     same to this check.
#   - a BARE PROSE id that names a superseded requirement with no status word
#     beside it. Prose legitimately narrates history - "R7 was narrowed" - and
#     failing that is the cry-wolf case above.
#   - an id inside a code span that happens to name a real requirement.
#     `R1`...`R6` in the committed guide are placeholder shapes, not citations.
#     R9.d still examines them; R9.c does not.
#   - everything in the guide that is not about requirements at all: install
#     steps, the stage narrative, the command list.
#
# ==========================================================================
# 1.2 - WHY THE REMAINING HOLE IS NOT CLOSED, WITH THE MEASUREMENTS.
# ==========================================================================
#
# The obvious narrowing is a TRACEABILITY rule: any paragraph outside the
# section that speaks in the spec's own requirement vocabulary must be
# traceable to a requirement. Three widths of that rule were run against the
# committed GUIDE.md with one deliberate contradiction of R17 planted
# immediately after the end marker - `Deploys and publishes run straight
# through. Nobody has to sign off on one first, and the gate never holds a
# command back waiting for a person.` - across the 86 prose paragraphs that
# then sit outside the section:
#
#   RULE                                   FIRES  PLANT  FALSE  PRECISION
#   `shall` or `the lifecycle`                 5      0      5       0.00
#   `<subject> shall <verb>`                   0      0      0    0 examined
#   any spec subject noun (`the gate`, ...)   17      1     16       0.06
#
# The first is red on a correct guide five times over and catches nothing -
# the cry-wolf failure that gets a check switched off. The second fires on
# NOTHING, and an assertion nothing exercises is exit 2 forever under this
# repo's own premise rule, not a pass. The third looks like a catch and is
# not, which is the decisive measurement: negate the planted sentence into
# one that AGREES with R17 - `the gate holds a command back waiting for a
# person` - and every rule above, plus R9.c and R9.d already in this file,
# returns the identical verdict on both. The two sentences differ by `never`,
# `do not` and `Nobody`, and `never` as a trigger word was already measured
# against ordinary prose here and dropped.
#
# So the hole is not narrow-able by matching: separating a sentence from its
# own negation is reading, not matching. Closing it needs a model in the check
# path, and Stage 5 forbids exactly that - `models.checks` in config.json is
# `model: none, effort: none, enforced: true`, whose stated reason is that a
# model deciding whether a check passed is the failure the stage exists to
# prevent. R9 therefore stays PARTIAL on purpose, and a weak rule that made it
# read Covered would be worse than the hole.
#
# WHAT 1.2 DOES INSTEAD IS MEASURE THE HOLE AND PRINT ITS SIZE on every run:
# how many prose paragraphs sit outside the generated section, how many of
# those any assertion here could reach, and how many were examined by nothing
# at all. It adds NO assertion. A gap with a number on it can be argued about
# and watched; `the rest of the file is not checked` cannot.
#
# A FINDING OUTSIDE THE MARKERS IS A FINDING IN WRITE MODE TOO. Regenerating
# the section cannot fix a sentence somebody wrote outside it, so the write
# succeeds and the exit code is still 1. That is the contract's meaning of 1 -
# findings - not a failed write.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  written, or already current, and nothing outside the markers disagrees
#   1  findings: the committed section is out of date with the spec (--check),
#      or text outside it names an id the spec does not define or claims a
#      status the spec denies (either mode)
#   2  cannot run - bad usage, no repository root, an unreadable guide, or a
#      guide carrying no markers to write between
#   3  COULD NOT READ THE SPEC. Never reported as "0 active requirements": a
#      spec nobody could open is not a product with nothing agreed about it.
#
# --SELFTEST DRIVES ALL FOUR. R39 - every check tool carries a self-test that
# reaches each exit code it can return - and this file returns four, so all
# four are built as cases in a temporary directory below. Under --selftest the
# exit code means: every case produced the code this contract declares for it
# (0), at least one did not (1), the corpus could not be built at all (2).
# `--self-test` is accepted as an alias, because this repository spells the
# flag both ways and a tool that answers only one spelling has a self-test the
# next caller cannot find.
set -euo pipefail

VERSION="build-guide 1.2"

usage() {
  printf 'usage: build-guide.sh [--root DIR] [--spec FILE] [--guide FILE] [--check] [--selftest] [--version] [--help]\n'
}

ROOT=""; SPEC=""; GUIDE=""; MODE="write"

need_value() {
  [ -n "${2:-}" ] || { printf 'build-guide: %s needs a value\n' "$1" >&2; usage >&2; exit 2; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root)    need_value "$1" "${2:-}"; ROOT="$2";  shift 2 ;;
    --spec)    need_value "$1" "${2:-}"; SPEC="$2";  shift 2 ;;
    --guide)   need_value "$1" "${2:-}"; GUIDE="$2"; shift 2 ;;
    --check)   MODE="check"; shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *)         printf 'build-guide: unknown argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done


# --------------------------------------------------------------- --selftest
#
# A GENERATOR IS TESTED BY GENERATING. Every case below is a spec and a guide
# written into a temporary directory, this script run against them, and the
# exit code read off the child. Nothing is written into the repository this
# file lives in - which matters more here than in a check, because write mode
# REWRITES GUIDE.md, and a self-test that pointed at the real one would edit
# the tree it was meant to be measuring.
#
# THE CLEAN CASE IS A ROUND TRIP, not a comparison against a stored expectation.
# Write the section, then --check it: no golden file to drift, and the pair
# proves the two modes agree with each other rather than each agreeing with a
# copy somebody committed once.
if [ "$MODE" = "selftest" ]; then
  SELF_TMP="$(mktemp -d)" || {
    printf 'build-guide: cannot create a temporary directory to build the self-test corpus in. Unmeasured, not a pass.\n' >&2
    exit 2; }
  trap 'rm -rf "$SELF_TMP"' EXIT HUP INT TERM

  command -v python3 >/dev/null 2>&1 || {
    printf 'build-guide: python3 is not installed, so no case could be driven. Unmeasured, not a pass.\n' >&2
    exit 2; }

  CASE_ROOT="$SELF_TMP/repo"
  mkdir -p "$CASE_ROOT/.claude/productizer"

  # Two requirements under two headings, so the renderer groups something
  # rather than taking its every-group-empty path.
  cat > "$CASE_ROOT/.claude/productizer/spec.md" <<'FIXTURE_SPEC'
# Fixture spec

Next requirement id: R3

## Requirements

### Ubiquitous requirements

- **R1** - the lifecycle shall do the first thing.

### Event-driven requirements

- **R2** - when a thing arrives, the lifecycle shall do the second thing.

## Change log

Nothing. This fixture exists to be regenerated from, not to be read.
FIXTURE_SPEC

  # An empty section between the markers, and prose on both sides of it that
  # names no requirement id - so R9.c and R9.d have nothing to fire on and the
  # clean case is clean for the reason it says it is.
  cat > "$CASE_ROOT/GUIDE.md" <<'FIXTURE_GUIDE'
# Fixture guide

Opening prose that names no requirement at all.

<!-- productizer:requirements:begin -->
<!-- productizer:requirements:end -->

Closing prose that names no requirement either.
FIXTURE_GUIDE

  SELF_CASES=0
  SELF_UPHELD=0

  # The exit code is captured into a variable on the SAME LINE as the command.
  # A command substitution in an argument list resets $?, so reading the status
  # inside the call below would report the status of the call.
  record() { # <case> <expected> <observed> <what the case is>
    SELF_CASES=$((SELF_CASES + 1))
    if [ "$3" = "$2" ]; then
      SELF_UPHELD=$((SELF_UPHELD + 1)); verdict="held"
    else
      verdict="NOT HELD"
    fi
    printf '      %-26s expected %s  got %s  %s  %s\n' "$1" "$2" "$3" "$verdict" "$4"
  }

  printf '    selftest: %s\n' "$VERSION"

  got=0
  bash "$0" --root "$CASE_ROOT" > "$SELF_TMP/write.out" 2> "$SELF_TMP/write.err" || got=$?
  record write-into-markers 0 "$got" "the section is generated between the two markers and nothing else is touched"

  got=0
  bash "$0" --root "$CASE_ROOT" --check > "$SELF_TMP/check.out" 2> "$SELF_TMP/check.err" || got=$?
  record check-current 0 "$got" "the section just written is what the spec produces today"

  # The R9.c case is built from the guide AFTER the write, so its section is
  # current and the only thing that can go red is the prose outside it.
  cp "$CASE_ROOT/GUIDE.md" "$SELF_TMP/prose-guide.md"
  printf '\nThe guide also mentions R99 in running prose outside the section.\n' \
    >> "$SELF_TMP/prose-guide.md"
  got=0
  bash "$0" --root "$CASE_ROOT" --guide "$SELF_TMP/prose-guide.md" --check \
    > "$SELF_TMP/prose.out" 2> "$SELF_TMP/prose.err" || got=$?
  record undefined-id-in-prose 1 "$got" "R9.c: prose outside the section names an id the spec does not define"

  # One requirement added to the spec and nothing done to the guide.
  cp -R "$CASE_ROOT" "$SELF_TMP/stale"
  python3 - "$SELF_TMP/stale/.claude/productizer/spec.md" <<'ADD_ONE_REQUIREMENT'
import io
import sys

path = sys.argv[1]
with io.open(path, encoding="utf-8") as fh:
    text = fh.read()
with io.open(path, "w", encoding="utf-8") as fh:
    fh.write(text.replace(
        "## Change log",
        "- **R3** - the lifecycle shall do a third thing.\n\n## Change log", 1))
ADD_ONE_REQUIREMENT
  got=0
  bash "$0" --root "$SELF_TMP/stale" --check \
    > "$SELF_TMP/stale.out" 2> "$SELF_TMP/stale.err" || got=$?
  record check-stale 1 "$got" "a requirement is in the spec and absent from the guide"

  # The same drift in WRITE mode succeeds and exits 0: regenerating IS the fix
  # for a stale section, and only a finding outside the markers survives it.
  got=0
  bash "$0" --root "$SELF_TMP/stale" > "$SELF_TMP/rewrite.out" 2> "$SELF_TMP/rewrite.err" || got=$?
  record write-fixes-drift 0 "$got" "regenerating fixes the section a --check just called stale"

  # A guide with the markers stripped out.
  python3 - "$CASE_ROOT/GUIDE.md" "$SELF_TMP/no-markers.md" <<'STRIP_MARKERS'
import io
import sys

src, dst = sys.argv[1:3]
with io.open(src, encoding="utf-8") as fh:
    text = fh.read()
for marker in ("<!-- productizer:requirements:begin -->",
               "<!-- productizer:requirements:end -->"):
    text = text.replace(marker, "")
with io.open(dst, "w", encoding="utf-8") as fh:
    fh.write(text)
STRIP_MARKERS
  got=0
  bash "$0" --root "$CASE_ROOT" --guide "$SELF_TMP/no-markers.md" \
    > "$SELF_TMP/nomark.out" 2> "$SELF_TMP/nomark.err" || got=$?
  record no-markers 2 "$got" "guessing where the section belongs would overwrite prose somebody wrote"

  got=0
  bash "$0" --root "$SELF_TMP/no-such-root" --check \
    > "$SELF_TMP/noroot.out" 2> "$SELF_TMP/noroot.err" || got=$?
  record root-does-not-exist 2 "$got" "a root that is not a directory is refused, never defaulted around"

  got=0
  bash "$0" --not-a-real-option > "$SELF_TMP/badopt.out" 2> "$SELF_TMP/badopt.err" || got=$?
  record unknown-argument 2 "$got" "bad usage is refused, never answered"

  got=0
  bash "$0" --root > "$SELF_TMP/noval.out" 2> "$SELF_TMP/noval.err" || got=$?
  record option-without-value 2 "$got" "an option missing its argument is refused"

  got=0
  bash "$0" --root "$CASE_ROOT" --spec "$SELF_TMP/no-such-spec.md" --check \
    > "$SELF_TMP/nospec.out" 2> "$SELF_TMP/nospec.err" || got=$?
  record spec-unreadable 3 "$got" "a spec nobody could open is not a product with nothing agreed about it"

  printf 'a file with no requirements section\n' > "$SELF_TMP/empty-spec.md"
  got=0
  bash "$0" --root "$CASE_ROOT" --spec "$SELF_TMP/empty-spec.md" --check \
    > "$SELF_TMP/emptyspec.out" 2> "$SELF_TMP/emptyspec.err" || got=$?
  record spec-has-no-section 3 "$got" "no requirement was read, which is unmeasured and not a spec with none"

  if [ "$SELF_CASES" = "$SELF_UPHELD" ]; then self_verdict="held"; else self_verdict="NOT HELD"; fi
  printf '    R39  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$SELF_CASES" "$SELF_UPHELD" "$self_verdict" \
    "each case exits with the code this file's contract declares for it"
  printf '    exit codes reached: 0, 1, 2 and 3 - the whole contract.\n'
  printf '    NOT ASSERTED: the CONTENT of the generated section. The corpus drives the exit code, so a renderer producing different but self-consistent prose in both modes would pass every case above; what the section says is asserted by R9.a against the committed guide, and read by a person.\n'
  [ "$SELF_CASES" = "$SELF_UPHELD" ] || exit 1
  exit 0
fi

if [ -z "$ROOT" ]; then
  # Not `.`. A release run from a subdirectory would otherwise regenerate a
  # guide nobody reads and leave the real one stale, reporting success both
  # times. git's own fatal goes to the terminal on purpose.
  ROOT="$(git rev-parse --show-toplevel)" || {
    printf 'build-guide: --root was not given and this is not a git work tree, so there is no repository root to default to. Pass --root DIR.\n' >&2
    exit 2
  }
fi
[ -d "$ROOT" ] || { printf 'build-guide: no such directory: %s\n' "$ROOT" >&2; exit 2; }

[ -n "$SPEC" ]  || SPEC="$ROOT/.claude/productizer/spec.md"
[ -n "$GUIDE" ] || GUIDE="$ROOT/GUIDE.md"

command -v python3 >/dev/null 2>&1 || {
  printf 'build-guide: python3 is not installed, so the spec was never parsed. Missing, not clean.\n' >&2
  exit 2
}

python3 - "$SPEC" "$GUIDE" "$MODE" "$ROOT" <<'PY'
import os
import re
import sys
import tempfile
import textwrap

BEGIN = "<!-- productizer:requirements:begin -->"
END = "<!-- productizer:requirements:end -->"

SPEC_PATH, GUIDE_PATH, MODE, ROOT = sys.argv[1:5]


# Paths are printed RELATIVE to the work tree. An absolute one carries
# somebody's home directory, and this output is captured verbatim into
# checks-result.json, which is committed. That exact leak shipped once from
# build-view.sh; it does not get to ship twice.
def disp(path):
    try:
        rel = os.path.relpath(os.path.abspath(path), os.path.abspath(ROOT))
    except ValueError:
        return path
    return path if rel.startswith("..") else rel


# GUIDE.md is wrapped prose and the generated section has to be wrapped prose
# too, or the diff of a one-word spec edit is a whole rewritten paragraph and
# the section announces itself as machine output on sight. 78 columns, the
# width the rest of the file already uses. Hyphens and long tokens are never
# broken - `read-only` split across two lines is not the same word.
WIDTH = 78


def para(text):
    return textwrap.fill(text, width=WIDTH, break_on_hyphens=False,
                         break_long_words=False)


def bullet(text):
    return textwrap.fill(text, width=WIDTH, initial_indent="- ",
                         subsequent_indent="  ", break_on_hyphens=False,
                         break_long_words=False)


def die(code, msg):
    sys.stderr.write("build-guide: " + msg + "\n")
    raise SystemExit(code)


ONES = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
        "sixteen", "seventeen", "eighteen", "nineteen"]
TENS = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy",
        "eighty", "ninety"]


def words(n):
    if n < 20:
        return ONES[n]
    if n < 100:
        t, r = divmod(n, 10)
        return TENS[t] + ("-" + ONES[r] if r else "")
    return str(n)


def Words(n):
    w = words(n)
    return w[0].upper() + w[1:]


# The prose around each group is written here rather than in the spec, because
# the spec states obligations and a guide has to read like something a person
# wrote. Fixed text, so the output stays a pure function of the spec.
FRAMING = {
    "ubiquitous": ("Always, with no trigger.",
                   "One requirement holds whatever else is happening:",
                   "{N} requirements hold whatever else is happening:"),
    "event": ("When something arrives.",
              "One thing happens on a discrete trigger:",
              "{N} things happen on a discrete trigger:"),
    "state": ("For as long as a state lasts.",
              "One requirement is true for the duration of a state, not at a moment inside it:",
              "{N} requirements are true for the duration of a state, not at a moment inside it:"),
    "unwanted": ("When something goes wrong.",
                 "One defence, written as `If \u2026 then` because a designed path and a defended one are not the same thing:",
                 "{N} defences, written as `If \u2026 then` because a designed path and a defended one are not the same thing:"),
    "optional": ("Only where the feature is present.",
                 "One requirement applies only to a build that includes the feature:",
                 "{N} requirements apply only to a build that includes the feature:"),
    "complex": ("While a state lasts, and then a trigger fires.",
                "One requirement stacks a state and a trigger, in that order:",
                "{N} requirements stack a state and a trigger, in that order:"),
    "other": ("The rest of the agreed set.",
              "One requirement sits under a heading this generator does not recognise, and is listed unchanged:",
              "{N} requirements sit under a heading this generator does not recognise, and are listed unchanged:"),
}
ORDER = ["ubiquitous", "event", "state", "unwanted", "optional", "complex", "other"]


def group_of(heading):
    h = heading.lower()
    if "ubiquit" in h:
        return "ubiquitous"
    if "complex" in h:
        return "complex"
    if "unwanted" in h:
        return "unwanted"
    if "event" in h:
        return "event"
    if "state" in h:
        return "state"
    if "optional" in h:
        return "optional"
    return "other"


def escape_pipes(s):
    # Tables downstream are split on unescaped pipes. Nothing here emits a
    # table today, but a requirement that ever contains one must not be able
    # to become a column boundary somewhere else.
    return re.sub(r"(?<!\\)\|", r"\\|", s)


# --- read the spec -----------------------------------------------------------
try:
    with open(SPEC_PATH, encoding="utf-8") as fh:
        spec = fh.read()
except OSError as exc:
    die(3, "cannot read the spec at %s (%s). Unmeasured, not empty - a guide "
           "generated from a spec nobody could open would describe a product "
           "nobody agreed to." % (disp(SPEC_PATH), exc.strerror))

lines = spec.split("\n")
start = None
for i, ln in enumerate(lines):
    if re.match(r"^##[ \t]+Requirements[ \t]*$", ln):
        start = i + 1
        break
if start is None:
    die(3, "the spec at %s has no `## Requirements` section, so no requirement "
           "was read. That is unmeasured, not a spec with none." % disp(SPEC_PATH))

stop = len(lines)
for j in range(start, len(lines)):
    if re.match(r"^##[^#]", lines[j]):
        stop = j
        break

BULLET = re.compile(r"^-[ \t]+\*\*(R\d+)\*\*[ \t]*[—–-][ \t]*(.*)$")
SUPERSEDED = re.compile(r"^Superseded by R\d+\.")
WITHDRAWN = re.compile(r"^Withdrawn\.")

reqs = []          # (id, group, text, status)
group = "other"
k = start
while k < stop:
    ln = lines[k]
    if ln.startswith("###"):
        group = group_of(ln.lstrip("#").strip())
        k += 1
        continue
    m = BULLET.match(ln)
    if not m:
        k += 1
        continue
    rid, text = m.group(1), m.group(2).strip()
    status = "active"
    k += 1
    while k < stop:
        nxt = lines[k]
        if not nxt.strip() or BULLET.match(nxt) or nxt.startswith("#"):
            break
        if not (nxt.startswith(" ") or nxt.startswith("\t")):
            break
        cont = nxt.strip()
        if SUPERSEDED.match(cont):
            status = "superseded"
        elif WITHDRAWN.match(cont):
            status = "withdrawn"
        else:
            text = (text + " " + cont).strip()
        k += 1
    reqs.append((rid, group, text, status))

if not reqs:
    die(3, "the spec at %s holds no requirements. Unmeasured, not zero - a "
           "requirements section with nothing in it is a spec that could not "
           "be read, not a product with nothing agreed about it." % disp(SPEC_PATH))

active = [r for r in reqs if r[3] == "active"]
n_active = len(active)
n_sup = sum(1 for r in reqs if r[3] == "superseded")
n_wd = sum(1 for r in reqs if r[3] == "withdrawn")

# --- render ------------------------------------------------------------------
out = [BEGIN,
       "<!-- Generated from `.claude/productizer/spec.md` by",
       "     plugins/productizer/skills/spec/scripts/build-guide.sh. Everything between",
       "     these two markers is rewritten on every release - edit the spec, not this. -->",
       ""]

out.append(para("**%s requirement%s %s active**, and they are the whole of "
                "what has been agreed."
                % (Words(n_active), "" if n_active == 1 else "s",
                   "is" if n_active == 1 else "are")))
out.append("")

if n_sup or n_wd:
    if n_sup and n_wd:
        tail = ("%s more %s superseded and %s withdrawn"
                % (Words(n_sup), "is" if n_sup == 1 else "are", words(n_wd)))
    elif n_sup:
        tail = ("%s more %s superseded and none withdrawn"
                % (Words(n_sup), "is" if n_sup == 1 else "are"))
    else:
        tail = ("None %s superseded and %s withdrawn"
                % ("is", words(n_wd)))
    out.append(para("%s, and neither kind is listed here. The spec keeps both "
                    "forever with their text intact, so a citation written two "
                    "years ago still leads somewhere \u2014 but a guide is read "
                    "by someone deciding what to do next, and a superseded "
                    "sentence gives them no sign it stopped being true." % tail))
    out.append("")

if n_active == 0:
    out.append(para("Nothing is active. Every requirement the spec has ever "
                    "held has since been superseded or withdrawn, so there is "
                    "nothing here to describe."))
    out.append("")
else:
    for g in ORDER:
        members = [r for r in active if r[1] == g]
        bold, sing, plur = FRAMING[g]
        if not members:
            if g == "unwanted":
                out.append(para("**%s** Nothing. A spec with no `If` "
                                "requirements has not considered failure, and "
                                "the tests will inherit that gap." % bold))
                out.append("")
            continue
        n = len(members)
        sentence = sing if n == 1 else plur.replace("{N}", Words(n))
        out.append(para("**%s** %s" % (bold, sentence)))
        out.append("")
        for rid, _g, text, _s in members:
            out.append(bullet("**%s** \u2014 %s" % (rid, escape_pipes(text))))
        out.append("")

out.append(para("Every id above is permanent. A plan, a test or a PR title "
                "naming `%s` will still mean this sentence in two years, which "
                "is why ids are never reused and never renumbered. The whole "
                "spec \u2014 the superseded text included, with the acceptance "
                "criteria and the change log \u2014 is at "
                "`.claude/productizer/spec.md`."
                % (active[0][0] if active else "R1")))
out.append(END)

block = "\n".join(out)

# --- splice it in ------------------------------------------------------------
try:
    with open(GUIDE_PATH, encoding="utf-8") as fh:
        guide = fh.read()
except OSError as exc:
    die(2, "cannot read the guide at %s (%s)." % (disp(GUIDE_PATH), exc.strerror))

n_begin, n_end = guide.count(BEGIN), guide.count(END)
if n_begin != 1 or n_end != 1:
    if n_begin == 0 and n_end == 0:
        why = "it carries no generated-requirements markers"
    else:
        why = ("it carries %d begin marker(s) and %d end marker(s), and exactly "
               "one of each is needed to know what to replace" % (n_begin, n_end))
    die(2, "refusing to touch %s: %s. Guessing where the section belongs would "
           "overwrite prose somebody wrote, and prose does not come back the way "
           "a regenerated section does.\n"
           "  Put these two lines in %s where the requirements should appear, "
           "then run again:\n"
           "    %s\n"
           "    %s" % (disp(GUIDE_PATH), why, os.path.basename(GUIDE_PATH), BEGIN, END))

b = guide.index(BEGIN)
e = guide.index(END)
if e < b:
    die(2, "refusing to touch %s: the end marker comes before the begin marker, "
           "so there is no section between them to replace." % disp(GUIDE_PATH))

old_block = guide[b:e + len(END)]
new_guide = guide[:b] + block + guide[e + len(END):]

# Bullets are wrapped, so the rows are unwrapped again before they are
# compared. Comparing wrapped lines would call a requirement "changed" because
# a word moved across a line break.
ROW_HEAD = re.compile(r"^- \*\*(R\d+)\*\* — (.*)$")


def rows(text):
    found = {}
    rid = None
    for ln in text.split("\n"):
        m = ROW_HEAD.match(ln)
        if m:
            rid = m.group(1)
            found[rid] = m.group(2).strip()
        elif rid and ln.startswith("  ") and ln.strip():
            found[rid] = (found[rid] + " " + ln.strip()).strip()
        else:
            rid = None
    return found


print(disp(SPEC_PATH))
print(disp(GUIDE_PATH))
print("2 file(s) read, %d active requirement(s) rendered" % n_active)

# =============================================================================
# THE REST OF THE FILE. Everything above regenerates ~85 lines of a ~700-line
# guide; what follows is the only thing asserted about the other ~615, and it
# is deliberately small enough to be true.
# =============================================================================
FENCE = re.compile(r"^\s*(```|~~~)")
RE_ID = re.compile(r"\bR[0-9]+\b")

# The closed vocabulary. It is printed in --help and quoted in the header for
# one reason: a reader who disagrees should be able to argue with THIS LIST
# rather than with a verdict whose rule is invisible. Measured against the
# committed GUIDE.md before it was chosen - one sentence matched, the
# `Superseded by R58.` example, and R58 names no requirement so it is not
# examined. A wider net (`never`, `optional`, `only`) matched ordinary prose
# and was dropped: a check that reddens on a correct guide gets switched off.
DENIES = re.compile(
    r"superseded|withdrawn|retired|obsolete|deprecated|no longer"
    r"|does not apply|not active|was dropped|has been removed"
    r"|shall not|need not|is advisory|not enforced", re.I)
AFFIRMS = re.compile(
    r"is active|still active|still holds|remains active|remains in force", re.I)
# `Superseded by R32` names R32 as the SUCCESSOR, which is active and correct.
# Without this the sentence that documents the supersede convention is a
# finding, and the check would be red on a guide that is right.
SUCCESSOR = re.compile(r"(?:superseded|replaced|split)\s+(?:by|into)\s+"
                       r"(?:and\s+|,\s*|R[0-9]+\s*)*$", re.I)

status_by_id = {}
for _rid, _g, _t, _st in reqs:
    status_by_id[_rid] = _st

begin_line = end_line = None
for i, ln in enumerate(guide.split("\n")):
    if BEGIN in ln:
        begin_line = i
    if END in ln:
        end_line = i
guide_lines = guide.split("\n")
outside = [(i + 1, guide_lines[i]) for i in range(len(guide_lines))
           if i < begin_line or i > end_line]


def code_flags(line):
    # True where a character sits inside an inline code span. An UNCLOSED
    # backtick marks nothing: guessing that the rest of the line is code is
    # how a real citation gets silently exempted.
    flags = [False] * len(line)
    i = 0
    while i < len(line):
        if line[i] == "`":
            j = line.find("`", i + 1)
            if j == -1:
                break
            for k in range(i, j + 1):
                flags[k] = True
            i = j + 1
        else:
            i += 1
    return flags


mentions = []          # (lineno, rid, in_code)
prose_lines = []       # fenced blocks dropped: a fence is code, not prose
in_fence = False
for lineno, line in outside:
    if FENCE.match(line):
        in_fence = not in_fence
        continue
    flags = [True] * len(line) if in_fence else code_flags(line)
    if not in_fence:
        prose_lines.append((lineno, line))
    for m in RE_ID.finditer(line):
        mentions.append((lineno, m.group(0),
                         any(flags[m.start():m.end()])))

# Paragraphs, then sentences. GUIDE.md is wrapped at 78 columns, so a claim
# about a requirement routinely spans two lines; a line-scoped rule would miss
# every one that happened to wrap.
paragraphs = []
current = []
for lineno, line in prose_lines:
    if not line.strip():
        if current:
            paragraphs.append(current)
            current = []
    else:
        current.append((lineno, line))
if current:
    paragraphs.append(current)

ASSERTIONS = []


def assertion(key, name, examined, upheld, held, note=None):
    ASSERTIONS.append({"key": key, "name": name, "examined": examined,
                       "upheld": upheld, "held": held, "note": note})


FINDINGS = []

# --- R9.a the generated section is byte-identical to a fresh render ----------
current_section = (new_guide == guide)
assertion("R9.a", "generated-section-is-current", 1, 1 if current_section else 0,
          "the marker-delimited section is byte-identical to a fresh render "
          "of the spec")

# --- R9.b every active requirement is rendered, with the spec's wording ------
committed_rows = rows(old_block)
fresh_rows = rows(block)
per_id = 0
for _rid, _g, _t, _st in reqs:
    if _st != "active":
        continue
    if committed_rows.get(_rid) == fresh_rows.get(_rid):
        per_id += 1
assertion("R9.b", "every-active-requirement-rendered-unchanged", n_active, per_id,
          "the row in the committed guide is the row the spec produces today")

# --- R9.c prose outside the markers cites only ids the spec defines ----------
bare = [m for m in mentions if not m[2]]
bare_ok = 0
for lineno, rid, _ in bare:
    if rid in status_by_id:
        bare_ok += 1
    else:
        FINDINGS.append("R9.c  %s:%d  prose names %s, and %s defines no such "
                        "requirement" % (disp(GUIDE_PATH), lineno, rid,
                                         disp(SPEC_PATH)))
assertion("R9.c", "prose-ids-outside-name-a-defined-requirement", len(bare),
          bare_ok,
          "an id written as running prose outside the section resolves in the "
          "spec",
          None if bare else "no id is written as bare prose outside the "
                            "section, so this assertion did not fire")

# --- R9.d no status claim outside the markers that the spec denies -----------
defined_mentions = [m for m in mentions if m[1] in status_by_id]
claims_examined = 0
claims_upheld = 0
for para in paragraphs:
    offsets = []
    pieces = []
    at = 0
    for lineno, line in para:
        offsets.append((at, lineno))
        pieces.append(line)
        at += len(line) + 1
    text = " ".join(pieces)

    def line_of(pos):
        found = offsets[0][1]
        for start, lineno in offsets:
            if start <= pos:
                found = lineno
        return found

    at = 0
    for sentence in re.split(r"(?<=[.!?])\s+", text):
        base = text.find(sentence, at)
        if base < 0:
            base = at
        at = base + len(sentence)
        denies = DENIES.search(sentence)
        affirms = AFFIRMS.search(sentence)
        if not (denies or affirms):
            continue
        for m in RE_ID.finditer(sentence):
            rid = m.group(0)
            if rid not in status_by_id:
                continue
            if SUCCESSOR.search(sentence[:m.start()]):
                continue
            claims_examined += 1
            state = status_by_id[rid]
            lineno = line_of(base + m.start())
            if denies and state == "active":
                FINDINGS.append(
                    "R9.d  %s:%d  %s is active in the spec, and the text "
                    "outside the generated section says `%s` of it"
                    % (disp(GUIDE_PATH), lineno, rid, denies.group(0)))
            elif affirms and state != "active":
                FINDINGS.append(
                    "R9.d  %s:%d  %s is %s in the spec, and the text outside "
                    "the generated section says `%s` of it"
                    % (disp(GUIDE_PATH), lineno, rid, state, affirms.group(0)))
            else:
                claims_upheld += 1
assertion("R9.d", "status-claims-outside-agree-with-the-spec", claims_examined,
          claims_upheld,
          "a sentence outside the section carrying one of the status words "
          "below agrees with that requirement's status in the spec",
          None if claims_examined else "no sentence outside the section pairs "
                                       "a defined id with a status word, so "
                                       "this assertion did not fire")

# --- report -----------------------------------------------------------------
# `upheld` is counted per assertion, one increment per item that held. It is
# never derived from a single flag: this repo once printed `upheld: 0` above
# six lines saying `held:`.
print("    ids mentioned outside the generated section: %d (%d as bare prose, "
      "%d inside a code span)"
      % (len(mentions), len(bare), len(mentions) - len(bare)))
for lineno, rid, in_code in mentions:
    print("      %s:%d  %s  %s  %s"
          % (disp(GUIDE_PATH), lineno, rid,
             "code-span" if in_code else "prose    ",
             status_by_id.get(rid, "NOT IN THE SPEC")))
print("    status words this check will act on: %s" % DENIES.pattern.replace("|", ", "))
print("    status words read as an active claim: %s" % AFFIRMS.pattern.replace("|", ", "))
# AN ASSERTION NOTHING EXERCISED IS NOT A PASS. `examined 0, upheld 0` used to
# print `held` and count towards the total, so a run in which nothing outside
# the section was looked at read identically to one in which everything was.
# It is now DID NOT FIRE and is counted as neither. It is not exit 2: zero
# bare-prose ids outside the section is the CORRECT state of a correct guide,
# and refusing every such run is the cry-wolf failure this file already warns
# about twice.
for entry in ASSERTIONS:
    if entry["examined"] == 0:
        verdict = "DID NOT FIRE"
    else:
        verdict = "held" if entry["upheld"] == entry["examined"] else "NOT HELD"
    print("    %-6s %-46s examined %3d  upheld %3d  %s: %s"
          % (entry["key"], entry["name"], entry["examined"], entry["upheld"],
             verdict, entry["held"]))
    if entry["note"]:
        print("           note: %s" % entry["note"])
fired = [e for e in ASSERTIONS if e["examined"]]
print("    assertions upheld: %d of the %d that fired; %d did not fire and "
      "are counted as neither"
      % (sum(1 for e in fired if e["upheld"] == e["examined"]), len(fired),
         len(ASSERTIONS) - len(fired)))
# --- the size of the hole, measured, asserted by nothing ---------------------
# Every assertion above needs an id to work from: R9.c and R9.d both start
# from `\bR[0-9]+\b`. A paragraph carrying no id is therefore reachable by
# NOTHING here, and that count is the R9 gap stated as a number rather than as
# a sentence. It changes no verdict - deliberately. See the 1.2 block in the
# header for the three rules that were measured and rejected.
lines_with_ids = set(lineno for lineno, _rid, _c in mentions)
reachable = 0
for para in paragraphs:
    if any(lineno in lines_with_ids for lineno, _line in para):
        reachable += 1
print("    prose paragraphs outside the generated section: %d" % len(paragraphs))
print("    of those, reachable by R9.c or R9.d because they name an id: %d"
      % reachable)
print("    of those, examined by NOTHING in this check: %d"
      % (len(paragraphs) - reachable))
print("    NOT ASSERTED: any statement outside the generated section that "
      "contradicts a requirement WITHOUT naming its id - the %d paragraphs "
      "counted immediately above; any semantic disagreement between the "
      "guide's prose and a requirement's wording; everything in the guide "
      "that is not about requirements at all"
      % (len(paragraphs) - reachable))
print("    Three narrower rules were measured against this guide with a "
      "planted contradiction and all three were rejected - precision 0.00, "
      "0 examined, and 0.06 whose one catch fires identically on the "
      "sentence's own negation. Closing this needs a model in the check "
      "path, which `models.checks` forbids. See the header.")

for line in FINDINGS:
    print("    OUTSIDE  %s" % line)


def by_id(ids):
    return sorted(ids, key=lambda s: int(s[1:]))


# --- the verdict -------------------------------------------------------------
if current_section:
    if MODE == "check":
        print("    %s requirements section is up to date with the spec."
              % disp(GUIDE_PATH))
    else:
        print("    %s requirements section is already up to date; nothing "
              "written." % disp(GUIDE_PATH))
    raise SystemExit(1 if FINDINGS else 0)

was = committed_rows
now = fresh_rows
added = [i for i in now if i not in was]
gone = [i for i in was if i not in now]
changed = [i for i in now if i in was and was[i] != now[i]]

if MODE == "check":
    print("    %s is OUT OF DATE with %s." % (disp(GUIDE_PATH), disp(SPEC_PATH)))
    for i in by_id(added):
        print("    added in the spec, absent from the guide:   %s — %s" % (i, now[i]))
    for i in by_id(gone):
        print("    in the guide, no longer active in the spec: %s" % i)
    for i in by_id(changed):
        print("    wording differs:                            %s" % i)
    if not (added or gone or changed):
        print("    the requirement ids match; the framing or the counts around "
              "them differ.")
    print("    Regenerate with: build-guide.sh --root <repo>")
    raise SystemExit(1)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(GUIDE_PATH)),
                           prefix=".build-guide.")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(new_guide)
    os.replace(tmp, GUIDE_PATH)
except Exception:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise

print("    wrote the requirements section of %s" % disp(GUIDE_PATH))
for i in by_id(added):
    print("    added:   %s — %s" % (i, now[i]))
for i in by_id(gone):
    print("    removed: %s" % i)
for i in by_id(changed):
    print("    changed: %s" % i)
# The write fixed the section. It cannot fix a sentence somebody wrote outside
# it, so a finding out there survives the regeneration and is still a finding.
raise SystemExit(1 if FINDINGS else 0)
PY
