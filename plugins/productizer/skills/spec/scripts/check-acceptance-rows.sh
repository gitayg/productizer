#!/usr/bin/env bash
# check-acceptance-rows.sh [--version] [--help] [--root PATH] [--spec PATH]
#                          [--checks PATH] [--selftest] [--fixtures DIR]
#
# Asserts R36: WHEN A REQUIREMENT IS ADDED, THE LIFECYCLE SHALL RECORD IT IN
# THE ACCEPTANCE CRITERIA TABLE. R35 - allocating the next unused id - is
# `validate-spec.py` and this check does not repeat it. That script already
# refuses a reused id (ID_REUSED), an id at or above the declared counter
# (ID_AT_OR_ABOVE_COUNTER), an id that arrived out of order (ID_OUT_OF_ORDER)
# and a citation naming an id the spec does not define (CITATION_UNKNOWN).
#
# The failure it catches is quiet. A requirement lands, is cited by a plan, a
# branch name and a PR title, and never acquires a row saying what would prove
# it. Nothing goes red; the requirement simply becomes one nobody can tell the
# difference between "verified" and "never looked at" for. R27 and R28 in this
# repo's own spec were in that state for a day, inherited from a superseded
# requirement that had carried no row either.
#
# ==========================================================================
# 1.1 - A ROW THAT EXISTS IS NOT YET A ROW THAT IS TRUE.
# ==========================================================================
#
# Until 1.1 this check asserted that a row EXISTS and nothing else. A row is
# free text, so a row could name a check that does not exist, a check that is
# switched off, a check that asserts a DIFFERENT requirement, or a script that
# was deleted - and every one of those passed clean. That is not hypothetical
# here: R18's row named `run-checks.sh argv[0] validation`, which is the
# implementation rather than the obligation, and so could never go red.
#
# So 1.1 asserts that what a row NAMES IS REAL. Rows are prose, and the point
# is not to make prose machine-readable; it is that three shapes inside prose
# are checkable, and where one of them appears it is now checked:
#
#   SHAPE                       WHAT IS ASSERTED
#   `<id>` followed by the      that <id> is a check declared in checks.yaml,
#   word "check"                that it is not `enabled: false`, and - across
#                               all such citations on the row - that at least
#                               one of them carries a `coverage.spec_units`
#                               claim for THIS requirement
#   a backticked path, i.e. a   that the file or directory exists, resolved
#   token holding `/` and       against the work tree and against the skill
#   ending in an extension      directory this script lives in
#   or a `/`
#   a backticked `NAME.sh` or   that a file of that name exists somewhere in
#   `NAME.py` with no `/`       the work tree
#
# WHAT IS NOT ASSERTED, AND IS PRINTED RATHER THAN PASSED SILENTLY:
#
#   - whether the named check actually PROVES the requirement. It asserts the
#     check claims it; what stands behind the claim is that check's own
#     falsification, not this one.
#   - any row naming a corpus, a config key, a document section or a promise
#     ("Nothing yet", "reviewed at intake", "not yet verified"). Prose
#     legitimately says those, and failing them would redden a correct table -
#     after which the check gets switched off and nothing is checked at all.
#     Every active row that named nothing this check could verify is LISTED BY
#     ID on every run, under `NOT VERIFIED`, so the unchecked set is visible
#     rather than absorbed into the pass.
#   - a bare `NAME.json` / `NAME.md` with no directory. `config.json` names a
#     file that exists at four paths here and none of them is what the row
#     meant; only `.sh` and `.py` basenames are resolved.
#   - a row for a SUPERSEDED, WITHDRAWN or INFERRED requirement. Those are
#     frozen records of what was once proven; re-checking them against today's
#     checks.yaml would redden the archive for being the archive.
#
# WHAT COUNTS AS NEEDING A ROW, AND WHAT DOES NOT.
#
#   active                       a row is REQUIRED
#   `Superseded by R<n>.`        no row - the requirement is a frozen record
#   `Withdrawn.`                 no row - the behaviour no longer exists
#   `Inferred ... Unconfirmed.`  no row - references/import.md, property 3:
#                                an inferred requirement is not counted as
#                                verified, and a row for one would inflate
#                                the very comparison this check performs
#
# Demanding a row for a dead or unratified requirement is not a stricter
# check, it is a WRONG one: it goes permanently red against a correct spec,
# and a check that is red for a correct spec gets switched off. This repo's
# spec holds five superseded requirements with no row, correctly.
#
# ADVISORY-CAPABLE, AND THE COUNTS ARE PRINTED ON EVERY RUN. Every number
# below is printed whether it is zero or not, so a clean run is readable and a
# dirty one can be watched shrinking. The script itself always exits 1 when
# any of them is above zero; whether that blocks is `severity:` in
# checks.yaml, the same route `stderr-suppression` took.
#
# UPHELD IS COUNTED PER ASSERTION, one increment per item that held, never
# from a single ok flag.
#
# WHAT IT PRINTS. One BARE PATH per line for every file examined - the
# runner reads those as coverage. Everything else is INDENTED. Findings name
# the ID, THE LINE and the offending TOKEN and nothing else: the requirement
# text is never echoed, because this output lands in a committed result file.
#
# A NUMBER THAT COULD NOT BE MEASURED IS PRINTED AS AN EM DASH, NEVER AS
# ZERO. A spec that cannot be read, that has no `## Requirements` section, no
# `## Acceptance criteria` section, an acceptance table whose rows do not have
# the column count its own header declares, a checks.yaml that cannot be
# parsed or that declares no checks, or a table in which NOT ONE row named
# anything in any of the three checkable shapes, is exit 2 - refused. That
# last one is the premise guard: "0 rows name something unreal" is a claim
# about rows somebody actually resolved, and a table that named nothing
# resolvable exercised none of the three new assertions.
#
# --SELFTEST DRIVES A COMMITTED CORPUS, and it exists because the eight
# assertions above are only worth what their falsification is worth. Each
# directory under `fixtures/acceptance-rows/` is a spec.md and a checks.yaml
# differing from the clean case in exactly one way, plus an `expect` file
# holding the exit code that case must produce and the reason in one line.
# One of them is the case this check was built for: a row naming a real,
# enabled check whose `spec_units` claim a DIFFERENT requirement.
#
# The corpus GUARDS ITS OWN PREMISE. If the clean case does not exit 0, every
# other case's exit 1 proves nothing - they would all be red for whatever is
# wrong with the clean one - so a clean case that is not clean is exit 2 for
# the whole selftest, never a pass on the seven that followed.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every active requirement has a row, and everything those rows name
#      resolves
#   1  at least one does not - reported by id and line
#   2  COULD NOT MEASURE - bad usage, a spec that could not be parsed, a
#      checks.yaml that could not be parsed, or a table exercising none of
#      the three resolution assertions
#
# Under --selftest the same three mean: every case produced the exit code it
# declares (0), at least one did not (1), and the corpus could not be driven
# at all - no fixture directory, a case with no `expect`, or a clean case that
# was not clean (2).
set -euo pipefail

VERSION="check-acceptance-rows 1.1"
ROOT=""
SPEC=".claude/productizer/spec.md"
CHECKS=".claude/productizer/checks.yaml"
MODE="measure"
FIXTURES=""

die_unmeasured() { printf 'check-acceptance-rows: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root) [ "$#" -ge 2 ] || die_unmeasured "--root needs a path"; ROOT="$2"; shift 2 ;;
    --spec) [ "$#" -ge 2 ] || die_unmeasured "--spec needs a path"; SPEC="$2"; shift 2 ;;
    --checks) [ "$#" -ge 2 ] || die_unmeasured "--checks needs a path"; CHECKS="$2"; shift 2 ;;
    --selftest) MODE="selftest"; shift ;;
    --fixtures) [ "$#" -ge 2 ] || die_unmeasured "--fixtures needs a path"; FIXTURES="$2"; shift 2 ;;
    *) die_unmeasured "unknown argument: $1" ;;
  esac
done

# The working directory is NEVER the default. A check rooted at wherever it
# happened to be invoked from reads a different spec depending on the caller,
# and answers confidently either way.
if [ -z "$ROOT" ]; then
  ROOT=$(git rev-parse --show-toplevel) \
    || die_unmeasured "no --root given and this is not a git work tree"
fi
[ -d "$ROOT" ] || die_unmeasured "--root is not a directory: $ROOT"
# Normalised to an absolute physical path. `--root .` otherwise makes every
# comparison against the work tree a string comparison against a single dot,
# which reports files that ARE inside it as sitting outside. `pwd -P` is POSIX
# and behaves the same on BSD and GNU, which `readlink -f` does not.
ROOT=$(cd -P "$ROOT" && pwd -P) \
  || die_unmeasured "cannot resolve --root to an absolute path: $ROOT"

# The skill directory, derived from where THIS script lives rather than
# hardcoded: a row citing `references/ears.md` means the copy shipped beside
# this script, wherever the plugin was installed. `cd -P` resolves the symlink
# an installed copy may be reached through; `pwd -P` is POSIX and behaves the
# same on BSD and GNU, which `readlink -f` does not.
SCRIPT_DIR=$(cd -P "$(dirname "$0")" && pwd -P) \
  || die_unmeasured "cannot resolve the directory this script lives in"
SKILL_DIR=$(dirname "$SCRIPT_DIR")

# The existence test's only stderr is noise about a question the exit status
# already answers; check-stderr.sh exempts this shape structurally.
command -v python3 >/dev/null 2>&1 \
  || die_unmeasured "python3 is not installed, so the spec was never parsed"

# ---------------------------------------------------------------------------
# --selftest: drive the committed corpus and read the exit code off each case.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  [ -n "$FIXTURES" ] || FIXTURES="$SKILL_DIR/fixtures/acceptance-rows"
  [ -d "$FIXTURES" ] \
    || die_unmeasured "no fixture directory at ${FIXTURES##*/}; the corpus this selftest reads its expectations from is not there, which is unmeasured rather than eight cases that all held"

  # Printed relative to the work tree. An absolute path carries somebody's
  # home directory, and this output is captured into a committed result file.
  rel_to_root() {
    case "$1" in
      "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;;
      *) OUTSIDE=$((OUTSIDE + 1)) ;;
    esac
  }

  # NOTHING IS WRITTEN INTO THE TREE BEING CHECKED. The fixture directories
  # are committed files; a case's captured output goes to a temporary
  # directory that is removed on every exit path, signal included.
  SCRATCH=$(mktemp -d) \
    || die_unmeasured "cannot create a temporary directory to capture each case's output in"
  trap 'rm -rf "$SCRATCH"' EXIT HUP INT TERM

  OUTSIDE=0
  CASES=0
  UPHELD=0
  # R39.b: the reached half of the declaration below is ACCUMULATED here, one
  # entry per case as it ran. A literal list would satisfy the reader and prove
  # nothing.
  CODES=""
  CLEAN_SEEN=0
  CLEAN_HELD=0
  REPORT=""

  for CASE in "$FIXTURES"/*/; do
    [ -d "$CASE" ] || continue
    # The glob leaves a trailing slash, and `$CASE/spec.md` would then print a
    # doubled separator into the coverage lines the runner parses.
    CASE="${CASE%/}"
    NAME=$(basename "$CASE")
    [ -f "$CASE/expect" ]     || die_unmeasured "the case $NAME has no expect file, so there is no declared exit code to compare against"
    [ -f "$CASE/spec.md" ]    || die_unmeasured "the case $NAME has no spec.md"
    [ -f "$CASE/checks.yaml" ] || die_unmeasured "the case $NAME has no checks.yaml"
    EXPECTED=$(awk 'NR==1{print $1}' "$CASE/expect")
    REASON=$(awk 'NR==1{$1=""; sub(/^ +/, ""); print}' "$CASE/expect")
    case "$EXPECTED" in
      0|1|2) : ;;
      *) die_unmeasured "the case $NAME declares an exit code of '$EXPECTED', and the contract has only 0, 1 and 2" ;;
    esac

    rel_to_root "$CASE/spec.md"
    rel_to_root "$CASE/checks.yaml"

    # The case is driven through THIS script, not through the python below, so
    # the argument handling and the premise guards are on the path too.
    # `|| GOT=$?` because the interesting cases exit non-zero on purpose and
    # `set -e` would otherwise kill the loop at the first one - right exit
    # code, no reason printed.
    GOT=0
    bash "$0" --root "$CASE" --spec spec.md --checks checks.yaml \
      > "$SCRATCH/$NAME.out" 2> "$SCRATCH/$NAME.err" || GOT=$?

    CASES=$((CASES + 1))
    CODES="$CODES$GOT
"
    if [ "$GOT" = "$EXPECTED" ]; then
      UPHELD=$((UPHELD + 1))
      VERDICT="held"
    else
      VERDICT="NOT HELD"
    fi
    if [ "$EXPECTED" = 0 ]; then
      CLEAN_SEEN=$((CLEAN_SEEN + 1))
      [ "$VERDICT" = "held" ] && CLEAN_HELD=$((CLEAN_HELD + 1))
      # `|| :` - the test above is a question, and a false answer is an
      # answer, not a failure that should end the run.
      :
    fi
    REPORT="$REPORT      $NAME  expected $EXPECTED  got $GOT  $VERDICT  $REASON
"
  done

  [ "$CASES" -gt 0 ] \
    || die_unmeasured "the fixture directory holds no case directory, so nothing was driven"
  [ "$CLEAN_SEEN" -gt 0 ] \
    || die_unmeasured "no case in the corpus declares an expected exit of 0. Without a clean case the seven failing ones prove only that something is red, not that this check is what makes them red"
  [ "$CLEAN_HELD" = "$CLEAN_SEEN" ] \
    || die_unmeasured "the clean case did not exit 0. Every other case's failure is then unattributable - they would be red for whatever is wrong with the clean one - so this is unmeasured, not a corpus that held"

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"
  [ "$OUTSIDE" -eq 0 ] \
    || printf '    %d fixture file(s) sit outside the work tree and are not printed as coverage; an absolute path in this output would carry a home directory\n' "$OUTSIDE"
  if [ "$CASES" = "$UPHELD" ]; then SELF_VERDICT="held"; else SELF_VERDICT="NOT HELD"; fi
  printf '    R36.f  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$CASES" "$UPHELD" "$SELF_VERDICT" \
    "each fixture case exits with the code its expect file declares"

  # The R39.b declaration. The reached half is computed from the cases above;
  # the documented half is the contract in this file's header.
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  printf '    NOT ASSERTED: the corpus drives the exit CODE, never the wording of a finding; a case that went red for the wrong reason is invisible here and is read off the case output by hand\n'
  [ "$CASES" = "$UPHELD" ] || exit 1
  if [ -n "$MISSING" ]; then
    printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  exit 0
fi

python3 - "$ROOT" "$SPEC" "$CHECKS" "$SKILL_DIR" <<'PY'
import os
import re
import sys

root, spec_rel, checks_rel, skill_dir = sys.argv[1:5]


def under(rel):
    return rel if os.path.isabs(rel) else os.path.join(root, rel)


spec_path = under(spec_rel)
checks_path = under(checks_rel)
spec_shown = os.path.relpath(spec_path, root)
checks_shown = os.path.relpath(checks_path, root)

# `- **R14** — ...`, the one shape templates/spec.md writes requirements in.
RE_REQ = re.compile(r'^(?:[-*]\s+)?\*\*(R[0-9]+)\*\*')
RE_SUPER = re.compile(r'^Superseded by\s+R[0-9]+')
RE_WITHDRW = re.compile(r'^Withdrawn\.')
RE_INFER = re.compile(r'^Inferred(\s*\([^)]*\))?\s+from\b')
RE_ACROW = re.compile(r'^\|\s*`?(R[0-9]+)`?\s*(?<!\\)\|')
RE_SEP = re.compile(r'^[\s:|-]+$')

# A markdown cell may hold a pipe by escaping it as `\|`. Splitting on a bare
# pipe tears such a row into an extra cell and silently shifts every column
# after it - the mistake build-view.sh already shipped once, which rendered a
# real note as a single stray backtick. Split on UNESCAPED pipes only, then
# put the real character back.
RE_MD_PIPE = re.compile(r'(?<!\\)\|')

# --- the three checkable shapes ---------------------------------------------
# A backticked span. Only what is INSIDE backticks is ever resolved: a row is
# prose, and an unquoted word in prose is a word, not a citation.
RE_SPAN = re.compile(r'`([^`]+)`')
# A bare identifier - the shape a checks.yaml `id:` takes.
RE_ID_SHAPE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*$')
# The word that turns such an identifier into a CHECK citation. Without it,
# `awk`, `make` and `downloads` would each be read as a check that does not
# exist, which is the cry-wolf failure this check must not have.
RE_IS_CHECK = re.compile(r'^\s*checks?\b', re.I)
# A path: it holds a directory separator AND either ends in one or carries a
# file extension. `n/a` holds a separator and is not a path; without the
# second half of this rule R27's row reports a missing file called `n/a`.
RE_PATH_SHAPE = re.compile(r'^[^\s]*/[^\s]*$')
RE_HAS_EXT = re.compile(r'/[^/]*\.[A-Za-z0-9]{1,6}$')
# A script named by basename alone. Restricted to .sh and .py on purpose:
# `config.json` and `spec.md` exist at several paths here and a basename
# search would resolve them to whichever it found first, which proves nothing.
RE_SCRIPT_SHAPE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*\.(?:sh|py)$')
# `references/import.md:70` cites a line. The line number is not part of the
# path, and leaving it on turns a correct citation into a missing file.
RE_LINE_SUFFIX = re.compile(r':[0-9]+$')


def cells(row):
    return [c.strip().replace('\\|', '|') for c in RE_MD_PIPE.split(row)]


UNMEASURED = [
    'requirements read: —',
    'active requirements examined: —',
    'requirements missing an acceptance row: —',
    'rows naming something that does not resolve: —',
]


def refuse(message):
    for line in UNMEASURED:
        sys.stdout.write('    %s\n' % line)
    sys.stderr.write('check-acceptance-rows: %s\n' % message)
    raise SystemExit(2)


try:
    with open(spec_path, encoding='utf-8') as handle:
        text = handle.read()
except OSError as exc:
    refuse('cannot read %s: %s' % (spec_shown, exc.strerror or exc))

# --- the declared checks ----------------------------------------------------
# Read BEFORE the spec path is printed as coverage: a run that could not read
# checks.yaml resolved nothing, and must not be able to claim it examined the
# spec either.
try:
    import yaml
except ImportError as exc:
    refuse('python3 has no yaml module (%s), so checks.yaml was never parsed. '
           'Unmeasured, not a table whose citations all resolve' % exc)

try:
    with open(checks_path, encoding='utf-8') as handle:
        config = yaml.safe_load(handle)
except OSError as exc:
    refuse('cannot read %s: %s' % (checks_shown, exc.strerror or exc))
except yaml.YAMLError as exc:
    refuse('cannot parse %s as yaml: %s' % (checks_shown, exc))

if not isinstance(config, dict) or not isinstance(config.get('checks'), list):
    refuse('%s has no `checks:` list, so there is no set of declared checks to '
           'resolve a row against. That is unmeasured, not a table whose '
           'citations are all real' % checks_shown)

declared = {}
for entry in config['checks']:
    if not isinstance(entry, dict):
        continue
    cid = entry.get('id')
    if not isinstance(cid, str):
        continue
    units = set()
    coverage = entry.get('coverage')
    if isinstance(coverage, dict):
        for unit in coverage.get('spec_units') or []:
            if isinstance(unit, dict) and isinstance(unit.get('id'), str):
                units.add(unit['id'])
    declared[cid] = {'enabled': entry.get('enabled', True) is not False,
                     'units': units}

if not declared:
    refuse('%s declares no check with an `id:`, so every check citation in the '
           'table would report as unreal for the same single reason'
           % checks_shown)

# The paths are printed only once both files have actually been read. A path
# printed before the read would be counted as coverage for a file nobody
# opened.
sys.stdout.write('%s\n' % spec_shown)
sys.stdout.write('%s\n' % checks_shown)
lines = text.split('\n')


def section_bounds(title):
    start = None
    for index, line in enumerate(lines):
        if re.match(r'^##\s+%s\s*$' % re.escape(title), line):
            start = index + 1
            break
    if start is None:
        return None
    for index in range(start, len(lines)):
        if re.match(r'^##\s', lines[index]):
            return (start, index)
    return (start, len(lines))


req_bounds = section_bounds('Requirements')
if req_bounds is None:
    refuse('%s has no `## Requirements` section, so there is no set of '
           'requirements to compare the acceptance table against' % spec_shown)

ac_bounds = section_bounds('Acceptance criteria')
if ac_bounds is None:
    refuse('%s has no `## Acceptance criteria` section; the table this check '
           'compares against does not exist, which is not the same fact as '
           'every requirement being missing a row' % spec_shown)

# --- the requirements, with the status marker that sits under each ----------
requirements = []
first, last = req_bounds
for index in range(first, last):
    match = RE_REQ.match(lines[index])
    if not match:
        continue
    # The entry runs to the first blank line or the next requirement, not a
    # fixed window: a marker sitting under a sentence that wrapped over four
    # lines is still found. A marker this check fails to see is a dead
    # requirement it reports as a gap.
    entry = []
    for follow in lines[index + 1:last]:
        if not follow.strip() or RE_REQ.match(follow):
            break
        entry.append(follow.strip())
    status = 'active'
    for line in entry:
        if RE_SUPER.match(line):
            status = 'superseded'
            break
        if RE_WITHDRW.match(line):
            status = 'withdrawn'
            break
        if RE_INFER.match(line):
            status = 'inferred'
            break
    requirements.append({'id': match.group(1), 'line': index + 1,
                         'status': status})

# --- the acceptance criteria table ------------------------------------------
ac_ids = set()
ac_rows = 0
header_width = None
rows_by_id = {}
first, last = ac_bounds
for index in range(first, last):
    raw = lines[index]
    if not raw.lstrip().startswith('|'):
        continue
    parts = cells(raw)
    width = len(parts)
    if header_width is None:
        header_width = width
        continue
    if RE_SEP.match(raw):
        continue
    if width != header_width:
        refuse('%s:%d - the acceptance table row has %d cells where its own '
               'header declares %d; a row this check cannot line up with its '
               'columns is a row it cannot read an id out of'
               % (spec_shown, index + 1, width, header_width))
    match = RE_ACROW.match(raw)
    if match:
        ac_rows += 1
        rid = match.group(1)
        ac_ids.add(rid)
        # Everything after the id cell is the evidence the row names. Joined,
        # because a row may spread its evidence over more than one column.
        evidence = ' '.join(parts[2:]).strip()
        rows_by_id.setdefault(rid, {'line': index + 1, 'evidence': evidence})

if header_width is None:
    refuse('%s has an `## Acceptance criteria` section holding no table' % spec_shown)

tally = {'active': 0, 'superseded': 0, 'withdrawn': 0, 'inferred': 0}
for requirement in requirements:
    tally[requirement['status']] += 1
if not requirements:
    refuse('%s has a `## Requirements` section holding no `- **R<n>**` '
           'requirement' % spec_shown)

missing = [r for r in requirements
           if r['status'] == 'active' and r['id'] not in ac_ids]

# --- resolving what the rows name -------------------------------------------
# A basename index of the work tree, built once. `.git` is skipped: a packed
# object is not a script, and walking it is the difference between a check
# that runs in a second and one that does not.
basenames = set()
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d != '.git']
    for name in filenames:
        basenames.add(name)


def resolves(token):
    """True where a path token names something on disk. Two bases: the work
    tree, and the skill directory this script lives in - a row citing
    `references/ears.md` means the copy shipped beside the scripts."""
    for base in (root, skill_dir):
        if os.path.exists(os.path.join(base, token)):
            return True
    return False


def citations(evidence):
    """The checkable shapes inside one row's prose, in order."""
    found = []
    for span in RE_SPAN.finditer(evidence):
        inner = span.group(1).strip()
        if not inner:
            continue
        token = inner.split()[0]
        token = RE_LINE_SUFFIX.sub('', token).rstrip(',;')
        if not token:
            continue
        after = evidence[span.end():]
        if RE_ID_SHAPE.match(token) and RE_IS_CHECK.match(after):
            found.append(('check', token))
        elif RE_PATH_SHAPE.match(token) and (token.endswith('/')
                                             or RE_HAS_EXT.search(token)):
            found.append(('path', token))
        elif RE_SCRIPT_SHAPE.match(token):
            found.append(('script', token))
    return found


ASSERTIONS = []


def assertion(key, name, examined, upheld, held, note=None):
    ASSERTIONS.append({'key': key, 'name': name, 'examined': examined,
                       'upheld': upheld, 'held': held, 'note': note})


FINDINGS = []

checks_examined = checks_upheld = 0
claim_examined = claim_upheld = 0
paths_examined = paths_upheld = 0
scripts_examined = scripts_upheld = 0
unverified = []
printed = []

for requirement in sorted([r for r in requirements if r['status'] == 'active'],
                          key=lambda r: int(r['id'][1:])):
    rid = requirement['id']
    row = rows_by_id.get(rid)
    if row is None:
        continue
    cited = citations(row['evidence'])
    if not cited:
        unverified.append((rid, row['line']))
        continue

    real_checks = []
    for kind, token in cited:
        if kind == 'check':
            checks_examined += 1
            known = declared.get(token)
            if known is None:
                FINDINGS.append(
                    'R36.b  %s  %s:%d  names `%s` as a check, and %s declares '
                    'no check with that id'
                    % (rid, spec_shown, row['line'], token, checks_shown))
                printed.append((rid, 'check ', token, 'NOT DECLARED'))
            elif not known['enabled']:
                FINDINGS.append(
                    'R36.b  %s  %s:%d  names the check `%s`, which is '
                    '`enabled: false` in %s and therefore never runs'
                    % (rid, spec_shown, row['line'], token, checks_shown))
                printed.append((rid, 'check ', token, 'DISABLED'))
            else:
                checks_upheld += 1
                real_checks.append(token)
                printed.append((rid, 'check ', token,
                                'claims ' + rid if rid in known['units']
                                else 'declared, does NOT claim ' + rid))
        elif kind == 'path':
            paths_examined += 1
            if resolves(token):
                paths_upheld += 1
                printed.append((rid, 'path  ', token, 'exists'))
            else:
                FINDINGS.append(
                    'R36.d  %s  %s:%d  names `%s`, and no such file or '
                    'directory exists under the work tree or the skill '
                    'directory' % (rid, spec_shown, row['line'], token))
                printed.append((rid, 'path  ', token, 'MISSING'))
        else:
            scripts_examined += 1
            if token in basenames:
                scripts_upheld += 1
                printed.append((rid, 'script', token, 'exists'))
            else:
                FINDINGS.append(
                    'R36.e  %s  %s:%d  names the script `%s`, and no file of '
                    'that name exists anywhere in the work tree'
                    % (rid, spec_shown, row['line'], token))
                printed.append((rid, 'script', token, 'MISSING'))

    # The claim assertion is scoped to rows that named a check which EXISTS.
    # A row citing only a deleted check is already a finding above; counting
    # it again here would report one defect as two.
    if real_checks:
        claim_examined += 1
        if any(rid in declared[name]['units'] for name in real_checks):
            claim_upheld += 1
        else:
            FINDINGS.append(
                'R36.c  %s  %s:%d  names the check%s %s as its evidence, and '
                'not one of them declares a `coverage.spec_units` claim for '
                '%s in %s'
                % (rid, spec_shown, row['line'], '' if len(real_checks) == 1
                   else 's', ', '.join('`%s`' % c for c in real_checks),
                   rid, checks_shown))

# --- the premise -------------------------------------------------------------
# Not one row named anything in any of the three shapes. The three resolution
# assertions were exercised by nothing, and a run that resolved nothing must
# not be able to report that everything resolved.
if checks_examined + paths_examined + scripts_examined == 0:
    refuse('not one row in the acceptance table of %s named a check, a path or '
           'a script this check can resolve, so nothing was resolved. "Every '
           'citation is real" is a claim about citations somebody looked up'
           % spec_shown)

assertion('R36.a', 'every-active-requirement-has-a-row', tally['active'],
          tally['active'] - len(missing),
          'the acceptance criteria table holds a row naming this requirement')
assertion('R36.b', 'cited-check-exists-and-is-enabled', checks_examined,
          checks_upheld,
          'a `<id>` check named by a row is declared in checks.yaml and is not '
          'switched off',
          None if checks_examined else 'no active row names a check, so this '
                                       'assertion did not fire')
assertion('R36.c', 'cited-check-claims-this-requirement', claim_examined,
          claim_upheld,
          'at least one check the row names carries a `coverage.spec_units` '
          'claim for that requirement',
          None if claim_examined else 'no active row names a check that '
                                      'exists, so this assertion did not fire')
assertion('R36.d', 'cited-path-exists', paths_examined, paths_upheld,
          'a backticked path named by a row resolves under the work tree or '
          'the skill directory',
          None if paths_examined else 'no active row names a path, so this '
                                      'assertion did not fire')
assertion('R36.e', 'cited-script-exists', scripts_examined, scripts_upheld,
          'a backticked `NAME.sh` or `NAME.py` named by a row exists in the '
          'work tree',
          None if scripts_examined else 'no active row names a script by '
                                        'basename, so this assertion did not '
                                        'fire')

# The coverage number the runner reads. It is every requirement the check
# actually parsed out of the file, not the subset that produced findings -
# a check that opened the spec and understood none of it must not be able
# to report a pass.
sys.stdout.write('    requirements read: %d\n' % len(requirements))
sys.stdout.write('    active requirements examined: %d\n' % tally['active'])
sys.stdout.write('    no row required: %d superseded, %d withdrawn, '
                 '%d inferred\n'
                 % (tally['superseded'], tally['withdrawn'], tally['inferred']))
sys.stdout.write('    acceptance criteria rows read: %d, naming %d distinct '
                 'ids\n' % (ac_rows, len(ac_ids)))
sys.stdout.write('    checks declared in %s: %d\n'
                 % (checks_shown, len(declared)))
sys.stdout.write('    requirements missing an acceptance row: %d\n'
                 % len(missing))
sys.stdout.write('    rows naming something that does not resolve: %d\n'
                 % sum(1 for f in FINDINGS if not f.startswith('R36.a')))

for requirement in sorted(missing, key=lambda r: int(r['id'][1:])):
    sys.stdout.write('    MISSING  %s  %s:%d  active, and the acceptance '
                     'criteria table has no row for it\n'
                     % (requirement['id'], spec_shown, requirement['line']))

# Every citation, with what it resolved to. A reader who disagrees with a
# verdict argues with THIS LIST rather than with a rule they cannot see.
sys.stdout.write('    what the active rows name, and what it resolved to: %d '
                 'citation(s)\n' % len(printed))
for rid, kind, token, verdict in printed:
    sys.stdout.write('      %-5s %s %-46s %s\n' % (rid, kind, token, verdict))

sys.stdout.write('    NOT VERIFIED: %d active row(s) named nothing in a '
                 'checkable shape - a corpus, a config key, a document '
                 'section or a promise. Listed, never counted as verified:\n'
                 % len(unverified))
for rid, line in unverified:
    sys.stdout.write('      %-5s %s:%d\n' % (rid, spec_shown, line))

# An assertion nothing exercised is not a pass. `examined 0, upheld 0` would
# otherwise print `held` and count towards the total, so a table that named
# no path would read exactly like one whose every path resolved. The three
# resolution assertions being ALL zero is exit 2 above, guarded as a premise;
# one of them alone being zero is a correct state of a correct table, so it is
# reported as DID NOT FIRE and counted as neither.
for entry in ASSERTIONS:
    if entry['examined'] == 0:
        verdict = 'DID NOT FIRE'
    else:
        verdict = 'held' if entry['upheld'] == entry['examined'] else 'NOT HELD'
    sys.stdout.write('    %-6s %-38s examined %3d  upheld %3d  %s: %s\n'
                     % (entry['key'], entry['name'], entry['examined'],
                        entry['upheld'], verdict, entry['held']))
    if entry['note']:
        sys.stdout.write('           note: %s\n' % entry['note'])
fired = [e for e in ASSERTIONS if e['examined']]
sys.stdout.write('    assertions upheld: %d of the %d that fired; %d did not '
                 'fire and are counted as neither\n'
                 % (sum(1 for e in fired if e['upheld'] == e['examined']),
                    len(fired), len(ASSERTIONS) - len(fired)))
sys.stdout.write('    NOT ASSERTED: that a named check PROVES the requirement '
                 '- only that it claims it; any row naming a corpus, a config '
                 'key or a promise; a bare NAME.json or NAME.md with no '
                 'directory; rows for superseded, withdrawn or inferred '
                 'requirements\n')

for line in FINDINGS:
    if not line.startswith('R36.a'):
        sys.stdout.write('    UNREAL   %s\n' % line)

raise SystemExit(1 if (missing or FINDINGS) else 0)
PY
