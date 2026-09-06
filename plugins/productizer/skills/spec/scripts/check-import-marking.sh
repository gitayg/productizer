#!/usr/bin/env bash
# check-import-marking.sh [--version] [--help] [--root PATH] [--spec PATH]
#                         [--backlog PATH] [--max-commits N] [--selftest]
#                         [--fixtures DIR]
#
# Asserts R10: WHEN A REPOSITORY WITH HISTORY IS IMPORTED, THE LIFECYCLE SHALL
# MARK EVERY DRAFTED REQUIREMENT INFERRED AND UNCONFIRMED.
#
# `build-view.sh` RENDERS the inferred status and nothing asserted it was ever
# applied. A forgotten marker therefore produces a requirement that reads as
# agreed - which that file's own comment calls the precise failure the
# inferred status exists to prevent. Three things follow from an unmarked
# import, all silent: the audit trail records a decision nobody made, the
# Stage 2 contradiction halt starts defending an imported accident with the
# authority of a ratification, and every plan, test and PR title citing the id
# inherits that confidence without re-checking it.
#
# ==========================================================================
# WHAT CHANGED IN 1.1, AND WHY IT HAD TO.
# ==========================================================================
#
# 1.0 answered ONE question - "is every requirement attributed to an import
# marked?" - and answered it by finding the cohort FROM THE MARKINGS. Every
# cohort anchored on a requirement that already wore the marker, so the
# complete violation was invisible by construction: an import that marked NONE
# of its requirements and named no stage left nothing to anchor on, printed
# `requirements attributed to an import: 0`, and EXITED 0. An audit reproduced
# exactly that and the run came back clean. The check printed a note saying so,
# which was honest, and was still a pass.
#
# That is the vacuous-assertion failure, not a missing feature. An assertion
# with no positive case to fire on holds forever and measures nothing, and a
# green tick is the worst possible way to say "not measured".
#
# 1.1 SPLITS THE QUESTION IN TWO, and answers them in order:
#
#   1  DID AN IMPORT EVER RUN HERE?  Four sources are read. If NOT ONE of them
#      records an import, R10 is an event-driven obligation whose event did not
#      occur here: that is exit 0, printed as `NO IMPORT ON THE RECORD`, and it
#      is a measurement of the premise rather than a refusal to look. What is
#      exit 2 is the state one step further in - an import IS on the record and
#      no requirement can be attributed to it, so something happened and this
#      check cannot say what.
#
#   2  ARE THE REQUIREMENTS THAT IMPORT DRAFTED MARKED?  Only asked once (1)
#      says yes. A cohort of which NOT ONE member is marked is a FINDING, exit
#      1, and it prints under its own heading - it is a different fact from a
#      cohort where one marker was forgotten, and reading the same is how the
#      complete failure hid inside the partial one.
#
# The states print differently and exit differently:
#
#   no import on the record          exit 0   the premise, measured and absent
#   an import, cohort unresolved     exit 2   UNMEASURED
#   an import, nothing marked        exit 1   findings, under its own heading
#   an import, some marker missing   exit 1   findings, per id
#   an import, all settled           exit 0
#
# MEASURED 2026-09-06 AND CORRECTED HERE. Until this date the two paragraphs
# above and the contract below said `no import on the record` was exit 2,
# UNMEASURED, never 0. The committed suite measures it as 0: `never-imported`
# and `silent-import` both declare 0 and both hold, and `--selftest` exits 0
# over all 8 cases. The exit-2 row above is the state the suite actually
# declares as 2 - `stage-in-the-backlog`, `IMPORT ON THE RECORD, COHORT
# UNRESOLVED`. No behaviour was changed by this correction; only the prose,
# which described an earlier draft's intent.
#
# ==========================================================================
# HOW AN IMPORT IS DETECTED. READ THIS BEFORE TRUSTING ANY RUN.
# ==========================================================================
#
# STAGE 0C WRITES NO ARTIFACT OF ITS OWN. `import-survey.sh` deliberately never
# writes to the repo it surveys, the draft is a hand edit, and promotion is
# another one. Nothing in the config or the filesystem says "an import ran
# here". Everything below is therefore inference from what the process DOES
# leave behind, and the evidence tally is printed on every run so a reader can
# disagree with the list rather than with the verdict.
#
# FOUR SOURCES, TWO OF THEM MARKER-FREE:
#
#   A  CHANGE-LOG COHORT (marker-anchored). `references/import.md` step 8
#      records the import as one change-log row. A row whose `Added` column
#      names a marked requirement is an import row, and every other id in that
#      same `Added` cell belongs to the same import. The column is located by
#      the table's OWN HEADER, never by position, and ranges are expanded.
#
#   B  COMMIT COHORT (marker-anchored). The commit that INTRODUCED a marked
#      requirement's bullet introduced the rest of that batch too. Oldest
#      introduction wins, so a later reformat that re-adds every bullet in the
#      diff is not mistaken for the import. Survives someone trimming the
#      change log afterwards.
#
#   C  A DECLARED STAGE (MARKER-FREE). `Stage 0c` named in a change-log row, a
#      commit message, anywhere else in the spec, or in the backlog. This is
#      the ONE piece of prose used, because it is a stage identifier rather
#      than an English word - `import` is a substring of `important` and a
#      topic half this repo's requirements are about; `stage 0c` is neither.
#      C is what makes an import that marked NOTHING visible, and it is why
#      the backlog is now read: step 5 of the procedure writes the import's
#      refusals down as backlog items, and those survive a spec nobody marked.
#
#   D  A DECISION-RECORD PROMOTION (marker-free in effect). Promotion DELETES
#      the marker line, so a ratified requirement is bare BY DESIGN. A row
#      that reads as a confirmation AND says the id came from an import is
#      evidence of an import and satisfies the obligation for that id.
#
# TWO SIGNALS WERE BUILT, MEASURED, AND REJECTED. Both are named here because
# the next person will think of them:
#
#   - THE WORD `import` IN A SUMMARY OR A COMMIT MESSAGE. Measured against a
#     fixture: it attributed six requirements to an import in a spec where
#     four were agreed one at a time, because one commit message carried the
#     word. On a lifecycle tool WITH an import stage that is not hypothetical.
#
#   - A BATCH: "one commit that introduced N or more requirements is
#     import-shaped". Measured against this repository's own history on
#     2026-09-01 before it was written: the FOUNDING commit introduced 22
#     requirement bullets in one commit, hand-authored, no import anywhere
#     near it. Any threshold low enough to catch a real import (import.md
#     drafts up to thirty, in batches of about ten) fires on that commit and
#     reports 22 hand-agreed requirements as an unmarked import. A check that
#     reddens on a correct spec gets switched off, and then nothing is checked
#     at all. REJECTED ON THE MEASUREMENT, not on taste.
#
# WHAT SATISFIES THE OBLIGATION for an id attributed to an import:
#
#   `Inferred ... Unconfirmed.`              the marking itself
#   `Withdrawn. Rejected at import: ...`     refused at ratification, id spent
#   a decision-record row naming the id and reading as a confirmation of an
#   imported requirement - because promotion deletes the marker, and reporting
#   a ratified requirement as never-marked would make the check red for the
#   one outcome the stage is aiming at
#
# THE HOLES, NAMED, BECAUSE THEY ARE STILL HOLES:
#
#   - AN IMPORT THAT MARKED NOTHING *AND* NAMED NO STAGE ANYWHERE - not in the
#     change log, not in a commit message, not in the spec, not in the backlog
#     - is still not attributable. It is reported as NO IMPORT ON THE RECORD,
#     exit 0, because from the outside it is byte-identical to a repository
#     that never imported - measured 2026-09-06 as the suite's `silent-import`
#     case, which declares 0 and holds. This paragraph previously said exit 2,
#     UNMEASURED. Either way THAT IS THE HONEST LIMIT, NOT A CLOSED GAP, and
#     the reported state is the one the evidence supports rather than the one
#     the hole deserves. The fix is upstream and it is one line of process: have
#     Stage 0c write a machine record of its own id range, and read that here
#     instead of inferring.
#   - A SHALLOW CLONE removes evidence from B without removing it from the
#     repository, and B silently sees fewer introductions. Exit 2.
#   - AN IMPORT SPLIT ACROSS SEVERAL CHANGE-LOG ROWS only pulls in the rows
#     that name a marked id or the stage; a row where every marker was
#     forgotten and the stage went unnamed is a row this check never reaches.
#
# EVERY ASSERTION IS COUNTED SEPARATELY, examined and upheld, from the items
# THAT ASSERTION ACTUALLY LOOKED AT. Never from one `ok` flag: a check in this
# repo once printed `upheld: 0` above six lines saying `held:`.
#
# GIT IS PART OF THE INPUT, SO GIT BEING UNREADABLE IS NOT A CLEAN RUN. A root
# that is not a git work tree, or a history that cannot be walked, is exit 2
# with cohort B printed as an em dash - never as 0 commits. The one ordering
# rule: findings already found are a definite answer, so they exit 1 even when
# B could not be read.
#
# WHAT IT PRINTS. One BARE PATH per line for every file examined; everything
# else INDENTED. Findings name the ID AND THE LINE. No requirement text is
# ever echoed - this output lands in a committed result file.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  an import is on the record and every requirement it drafted is marked,
#      refused at import, or promoted out of it - OR no import is on the
#      record at all, which is the premise measured and found absent
#   1  at least one is not - reported by id, line, and the source that
#      attributed it
#   2  COULD NOT MEASURE - bad usage, a spec that could not be parsed, a git
#      history that could not be walked, or an import on the record that no
#      requirement could be attributed to
#
# ONE LINE OF THAT CONTRACT WAS STALE UNTIL 2026-09-06 AND IS NOW CORRECTED
# ABOVE RATHER THAN LEFT WITH A NOTE UNDER IT. `no import on the record at all`
# used to be listed under 2; the committed suite measures it as 0 - the
# `never-imported` and `silent-import` cases both declare exit 0, and both
# hold. The suite's own comment gives the reason and it is the better argument:
# R10 is event-driven, four sources were read and none records an import, and
# that is a measurement of the premise rather than a refusal to look. Nothing
# in this file's behaviour changed with the correction. NOTE, NOT FIXED HERE:
# `fixtures/import-marking/selftest.sh`'s own header block still describes
# cases 1 and 5 as `exit 2, UNMEASURED` while its `run_case` lines declare 0.
# That file is the suite, not this check, and it is left for whoever owns it.
#
# --SELFTEST RUNS THE COMMITTED FALSIFICATION SUITE, `fixtures/import-marking/
# selftest.sh`, against THIS file. That suite already existed and already
# builds a throwaway git repository per case from the spec versions in
# `fixtures/import-marking/spec/`; what it did not have was a way in. R39 asks
# every check tool to CARRY a self-test, and a suite that only a person who
# knows the path can run is not one the tool carries. The flag is that way in
# and it adds no second copy of the cases.
#
# The suite drives all three of this check's exit codes: 0 on four cases
# (never imported, every requirement marked, all of them promoted, an import
# that left no trace at all), 1 on three (nothing marked, a marker forgotten,
# the stage named only in a commit message) and 2 on one (the stage named in
# the backlog and nowhere else, so an import is on the record and its cohort
# cannot be resolved).
#
# Under --selftest the three codes mean: every case produced the verdict it
# declares (0), at least one did not (1), and the suite could not be run at
# all (2). `--self-test` is accepted as an alias because the repo spells it
# both ways.
set -euo pipefail

VERSION="check-import-marking 1.1"
ROOT=""
SPEC=".claude/productizer/spec.md"
BACKLOG=".claude/productizer/backlog.md"
MAX_COMMITS="500"
MODE="measure"
FIXTURES=""

die_unmeasured() { printf 'check-import-marking: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root) [ "$#" -ge 2 ] || die_unmeasured "--root needs a path"; ROOT="$2"; shift 2 ;;
    --spec) [ "$#" -ge 2 ] || die_unmeasured "--spec needs a path"; SPEC="$2"; shift 2 ;;
    --backlog)
      [ "$#" -ge 2 ] || die_unmeasured "--backlog needs a path"
      BACKLOG="$2"; shift 2
      ;;
    --max-commits)
      [ "$#" -ge 2 ] || die_unmeasured "--max-commits needs a number"
      case "$2" in
        ''|*[!0-9]*) die_unmeasured "--max-commits is not a number: $2" ;;
      esac
      MAX_COMMITS="$2"; shift 2
      ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --fixtures)
      [ "$#" -ge 2 ] || die_unmeasured "--fixtures needs a path"
      FIXTURES="$2"; shift 2
      ;;
    *) die_unmeasured "unknown argument: $1" ;;
  esac
done

# ---------------------------------------------------------------------------
# --selftest: hand the committed suite this file and read its verdict. The
# cases live in the fixture, not here, so there is exactly one copy of them.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  # Derived from where THIS script lives rather than from the working
  # directory: an installed plugin is not a repository, and the fixture is
  # beside the script wherever it was installed.
  SELF_DIR="$(cd -P "$(dirname "$0")" && pwd -P)" \
    || die_unmeasured "cannot resolve the directory this script lives in, so the committed suite could not be located"
  SELF_SKILL="$(dirname "$SELF_DIR")"
  [ -n "$FIXTURES" ] || FIXTURES="$SELF_SKILL/fixtures/import-marking"
  SUITE="$FIXTURES/selftest.sh"
  [ -f "$SUITE" ] && [ -r "$SUITE" ] \
    || die_unmeasured "no committed suite at ${FIXTURES##*/}/selftest.sh; the cases this self-test reads its expectations from are not there, which is unmeasured rather than eight cases that all held"

  WORK="$(mktemp -d)" \
    || die_unmeasured "cannot create a temporary directory to capture the suite's output in"
  # Removed on every exit path, signal included.
  trap 'rm -rf "$WORK"' EXIT HUP INT TERM

  # `|| SRC=$?` on the same line as the command. A `$(...)` in an argument list
  # and a pipeline both RESET `$?`, and reading the status one line later is
  # how a self-test comes to report a pass it never observed.
  SRC=0
  bash "$SUITE" --check "$0" > "$WORK/suite.out" 2> "$WORK/suite.err" || SRC=$?

  CASES="$(awk '/^(ok|FAIL)[ \t]/ { n++ } END { print n + 0 }' "$WORK/suite.out")"
  UPHELD="$(awk '/^ok[ \t]/ { n++ } END { print n + 0 }' "$WORK/suite.out")"

  printf '    selftest cases driven: %s\n' "$CASES"
  # The suite's own per-case lines, indented into this check's output. Its
  # stderr goes with them: a reason nobody prints is a reason nobody has.
  sed 's/^/      /' < "$WORK/suite.out"
  if [ -s "$WORK/suite.err" ]; then
    sed 's/^/      /' < "$WORK/suite.err" >&2
  fi

  if [ "$SRC" = 2 ]; then
    die_unmeasured "the committed suite could not run (exit 2). Its reason was printed above. Nothing was asserted about R10"
  fi
  if [ "$CASES" = 0 ]; then
    die_unmeasured "the committed suite drove no case at all, so this self-test asserted nothing. Unmeasured, not a pass"
  fi

  # The exit codes THIS CHECK produced, taken from the suite's own lines: `ok
  # <name> exit N` when a case held, `got exit N` when it did not. Read from
  # the observed side on purpose - a code the check never actually returned is
  # not a code the self-test reached, whatever the case declared.
  REACHED="$(awk '
    /^ok[ \t]/        { for (i = 1; i <= NF; i++) if ($i == "exit") seen[$(i + 1)] = 1 }
    /got exit [0-9]/  { for (i = 1; i <= NF; i++) if ($i == "exit") seen[$(i + 1)] = 1 }
    END { out = ""; for (c = 0; c <= 2; c++) if (c in seen) out = out " " c
          print (out == "" ? " none" : out) }' "$WORK/suite.out")"

  if [ "$CASES" = "$UPHELD" ]; then SELF_VERDICT="held"; else SELF_VERDICT="NOT HELD"; fi
  printf '    R39.s  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$CASES" "$UPHELD" "$SELF_VERDICT" \
    "each committed case produces the verdict it declares"
  printf '    exit codes this self-test reached:%s. The contract declares 0, 1 and 2; a code missing here is a code nothing drove\n' \
    "$REACHED"
  printf '    NOT ASSERTED: the suite compares the exit code and ONE load-bearing line, never the whole finding, so a case red for a second reason on top of the right one is invisible here\n'
  [ "$CASES" = "$UPHELD" ] || exit 1
  exit 0
fi

# The working directory is NEVER the default. A check rooted at wherever it
# happened to be invoked from reads a different spec and a different history
# depending on the caller, and answers confidently either way.
if [ -z "$ROOT" ]; then
  ROOT=$(git rev-parse --show-toplevel) \
    || die_unmeasured "no --root given and this is not a git work tree"
fi
[ -d "$ROOT" ] || die_unmeasured "--root is not a directory: $ROOT"

python3 - "$ROOT" "$SPEC" "$BACKLOG" "$MAX_COMMITS" <<'PY'
import os
import re
import subprocess
import sys

root, spec_rel, backlog_rel = sys.argv[1], sys.argv[2], sys.argv[3]
max_commits = int(sys.argv[4])
spec_path = spec_rel if os.path.isabs(spec_rel) else os.path.join(root, spec_rel)
backlog_path = (backlog_rel if os.path.isabs(backlog_rel)
                else os.path.join(root, backlog_rel))
shown = os.path.relpath(spec_path, root)
shown_backlog = os.path.relpath(backlog_path, root)

RE_REQ = re.compile(r'^(?:[-*]\s+)?\*\*(R[0-9]+)\*\*')
RE_ADDED_REQ = re.compile(r'^\+(?:[-*]\s+)?\*\*(R[0-9]+)\*\*')
RE_INFER = re.compile(r'^Inferred(\s*\([^)]*\))?\s+from\b')
RE_REJIMP = re.compile(r'^Withdrawn\.\s*Rejected at import\b', re.I)
RE_RID = re.compile(r'\bR[0-9]+\b')
RE_RANGE = re.compile(r'\bR([0-9]+)\s*[–—-]\s*R?([0-9]+)\b')
RE_SEP = re.compile(r'^[\s:|-]+$')

# The one piece of prose this check trusts, and it is a stage identifier
# rather than an English word. `import` matches `important` and matches half
# the requirements of a product whose subject IS importing; `stage 0c` does
# neither.
RE_STAGE0C = re.compile(r'\bstage\s*0c\b', re.I)
# Promotion is recorded in the decision record, and only a row that reads as a
# confirmation AND says the id came from the import counts as one. The same
# pair build-view.sh uses, so the two files agree about what a promotion is.
RE_RATIFY = re.compile(r'confirm|promot|ratif', re.I)
RE_FROMIMP = re.compile(r'import|inferred', re.I)

RE_MD_PIPE = re.compile(r'(?<!\\)\|')

out = sys.stdout


def cells(row):
    return [c.strip().replace('\\|', '|') for c in RE_MD_PIPE.split(row)]


def refuse(message):
    # The em dashes are load-bearing: R26 forbids recording an unmeasured
    # value as zero, and `0` here would read as "an import was found and came
    # back clean".
    out.write('    requirements attributed to an import: —\n')
    out.write('    attributed requirements with no inferred marking: —\n')
    sys.stderr.write('check-import-marking: %s\n' % message)
    raise SystemExit(2)


def ids_in(field):
    found = set(RE_RID.findall(field))
    for low, high in RE_RANGE.findall(field):
        low, high = int(low), int(high)
        if low <= high and high - low <= 999:
            found.update('R%d' % n for n in range(low, high + 1))
    return found


try:
    with open(spec_path, encoding='utf-8') as handle:
        text = handle.read()
except OSError as exc:
    refuse('cannot read %s: %s' % (shown, exc.strerror or exc))

out.write('%s\n' % shown)
lines = text.split('\n')

# The backlog is READ, not required. Step 5 of the import procedure writes the
# survey's refusals down as backlog items, and those survive a spec where the
# marker was never applied - which is the one case cohorts A and B cannot see.
# A repository with no backlog is normal; a backlog that exists and cannot be
# opened is not, and it is not quietly treated as empty either.
backlog_lines = []
backlog_read = False
backlog_note = None
if os.path.exists(backlog_path):
    try:
        with open(backlog_path, encoding='utf-8') as handle:
            backlog_lines = handle.read().split('\n')
        backlog_read = True
        out.write('%s\n' % shown_backlog)
    except OSError as exc:
        refuse('%s exists and cannot be read: %s. An unreadable evidence '
               'source is not an absent one'
               % (shown_backlog, exc.strerror or exc))
else:
    backlog_note = ('%s does not exist, so the backlog was not searched for a '
                    'declared stage' % shown_backlog)


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
    refuse('%s has no `## Requirements` section, so there is nothing an '
           'import could have drafted into it' % shown)

# --- every requirement, with whatever marker sits under it ------------------
requirements = {}
first, last = req_bounds
for index in range(first, last):
    match = RE_REQ.match(lines[index])
    if not match:
        continue
    # The entry runs to the first blank line or the next requirement, not a
    # fixed window: a marker under a sentence that wrapped over four lines is
    # still found. A marker this check fails to see is a requirement it
    # reports as never having been marked.
    entry = []
    for follow in lines[index + 1:last]:
        if not follow.strip() or RE_REQ.match(follow):
            break
        entry.append(follow.strip())
    requirements[match.group(1)] = {
        'line': index + 1,
        'inferred': any(RE_INFER.match(e) for e in entry),
        'rejected': any(RE_REJIMP.match(e) for e in entry),
    }

if not requirements:
    refuse('%s has a `## Requirements` section holding no `- **R<n>**` '
           'requirement' % shown)

# --- source D: promotions, from the decision record -------------------------
promoted = set()
d_rows = 0
dr_bounds = section_bounds('Decision record')
if dr_bounds is not None:
    first, last = dr_bounds
    for index in range(first, last):
        row = lines[index]
        if not row.lstrip().startswith('|'):
            continue
        if RE_RATIFY.search(row) and RE_FROMIMP.search(row):
            hits = set(r for r in RE_RID.findall(row) if r in requirements)
            if hits:
                d_rows += 1
                promoted.update(hits)

# An id is EVIDENCE OF AN IMPORT when it still wears the marking, when it was
# refused at ratification, or when the decision record says a person promoted
# it out of an import. All three are outcomes of the same stage.
marked = set(r for r, v in requirements.items()
             if v['inferred'] or v['rejected']) | promoted

# --- source C, marker-free: a declared stage in the spec or the backlog -----
# Read BEFORE the change log so a stage named in a row is counted once, as
# cohort C, wherever else it also matches.
attributed = {}
c_spec = 0
c_backlog = 0
changelog_rows = set()

cl_bounds = section_bounds('Change log')
if cl_bounds is not None:
    changelog_rows = set(range(cl_bounds[0], cl_bounds[1]))

for index, line in enumerate(lines):
    if index in changelog_rows:
        continue          # counted under the change-log pass below
    if not RE_STAGE0C.search(line):
        continue
    c_spec += 1
    for rid in ids_in(line):
        attributed.setdefault(rid, set()).add('%s:%d names `Stage 0c`'
                                              % (shown, index + 1))

for index, line in enumerate(backlog_lines):
    if not RE_STAGE0C.search(line):
        continue
    c_backlog += 1
    for rid in ids_in(line):
        attributed.setdefault(rid, set()).add('%s:%d names `Stage 0c`'
                                              % (shown_backlog, index + 1))

# --- source A: change-log rows, and C where the row names the stage ---------
a_rows = 0
c_changelog = 0
if cl_bounds is not None:
    first, last = cl_bounds
    header = None
    added_col = None
    rows = []
    for index in range(first, last):
        raw = lines[index]
        if not raw.lstrip().startswith('|'):
            continue
        row = cells(raw)
        if header is None:
            header = row
            # The column is located by the table's own header. Reading it by
            # position is how a table that gained a column starts reporting a
            # different column's contents as requirement ids.
            for position, name in enumerate(row):
                if name.strip().lower() == 'added':
                    added_col = position
            continue
        if RE_SEP.match(raw):
            continue
        if len(row) != len(header):
            refuse('%s:%d - the change log row has %d cells where its own '
                   'header declares %d; a row this check cannot line up with '
                   'its columns is a row whose `Added` ids it cannot read'
                   % (shown, index + 1, len(row), len(header)))
        rows.append((index + 1, raw, row))
    if rows and added_col is None:
        refuse('%s - the change log table declares no `Added` column, so the '
               'ids an import row added cannot be read out of it' % shown)
    for lineno, raw, row in rows:
        found = ids_in(row[added_col])
        by_marker = bool(found & marked)
        by_stage = bool(RE_STAGE0C.search(raw))
        if not (by_marker or by_stage):
            continue
        if by_marker:
            a_rows += 1
        if by_stage:
            c_changelog += 1
            # A row naming the stage attributes every id it names, not only
            # the ids in `Added`: an import row that recorded its range in the
            # summary is still that import's row.
            found = found | ids_in(raw)
        for rid in found:
            attributed.setdefault(rid, set()).add(
                'change log %s:%d' % (shown, lineno))

# --- source B: the commit that introduced a marked requirement --------------
# Plus C again, where a commit message names the stage.
b_commits = None
c_commits = 0
walked = None
git_note = None


def git(*args):
    return subprocess.run(('git', '-C', root) + args, capture_output=True,
                          text=True)


probe = git('rev-parse', '--is-inside-work-tree')
if probe.returncode != 0:
    git_note = (probe.stderr.strip().split('\n')[-1]
                if probe.stderr.strip() else 'git rev-parse failed')
else:
    log = git('log', '--max-count=%d' % max_commits, '--reverse',
              '--format=%H%x1f%B%x1e', '--', spec_rel)
    if log.returncode != 0:
        git_note = (log.stderr.strip().split('\n')[-1]
                    if log.stderr.strip() else 'git log failed')
    else:
        commits = []
        for record in log.stdout.split('\x1e'):
            record = record.strip('\n')
            if record and '\x1f' in record:
                commits.append(record.split('\x1f', 1))
        walked = len(commits)
        introduced = {}
        stage_commits = []
        failed = None
        for sha, message in commits:
            show = git('show', '--unified=0', '--format=', sha, '--', spec_rel)
            if show.returncode != 0:
                failed = (show.stderr.strip().split('\n')[-1]
                          if show.stderr.strip()
                          else 'git show %s failed' % sha[:12])
                break
            hits = set()
            for line in show.stdout.split('\n'):
                match = RE_ADDED_REQ.match(line)
                if match:
                    hits.add(match.group(1))
            # Oldest wins: `--reverse` means the first commit seen holding a
            # bullet is the one that introduced it, so a later reformat that
            # re-adds every bullet in its diff is not read as the import.
            for rid in hits:
                introduced.setdefault(rid, sha)
            if RE_STAGE0C.search(message) and hits:
                stage_commits.append((sha, hits))
        if failed is not None:
            git_note = failed
        else:
            by_commit = {}
            for rid, sha in introduced.items():
                by_commit.setdefault(sha, set()).add(rid)
            b_commits = 0
            for sha, batch in by_commit.items():
                if not (batch & marked):
                    continue
                b_commits += 1
                for rid in batch:
                    attributed.setdefault(rid, set()).add('commit %s' % sha[:12])
            for sha, hits in stage_commits:
                c_commits += 1
                for rid in hits:
                    attributed.setdefault(rid, set()).add(
                        'commit %s names `Stage 0c`' % sha[:12])

# --- the cohort -------------------------------------------------------------
known = sorted((r for r in attributed if r in requirements),
               key=lambda r: int(r[1:]))
unknown = sorted((r for r in attributed if r not in requirements),
                 key=lambda r: int(r[1:]))
settled = [r for r in known
           if requirements[r]['inferred'] or requirements[r]['rejected']
           or r in promoted]
findings = [r for r in known if r not in settled]

c_total = c_spec + c_backlog + c_changelog + c_commits
# The premise, and it is deliberately NOT `known`. A marked requirement, a
# promotion row, an import row or a declared stage each say an import ran here
# even when no id can be pinned to it - and "an import ran and I cannot say
# which requirements it drafted" is a different, louder fact than "no import
# ran".
premise = bool(marked or a_rows or c_total or d_rows or (b_commits or 0))

# --- the coverage number the runner reads -----------------------------------
# Every requirement the check parsed out of the file - never the attribution
# count, which is legitimately 0 on a repo that was never imported and would
# read as a hollow run.
out.write('    requirements read: %d\n' % len(requirements))
out.write('    requirements still wearing the marking, refused at '
          'import, or promoted from one: %d\n' % len(marked))
out.write('    source A - change log rows naming one of them: %d\n' % a_rows)
if b_commits is None:
    out.write('    source B - commits introducing one of them: — (git could '
              'not be walked: %s)\n' % (git_note or 'unknown reason'))
else:
    out.write('    source B - commits introducing one of them: %d, of %d '
              'touching the spec\n' % (b_commits, walked))
out.write('    source C - `Stage 0c` named, marker-free: %d total — change '
          'log %d, commit messages %s, elsewhere in %s %d, %s %s\n'
          % (c_total, c_changelog,
             '—' if b_commits is None else str(c_commits),
             shown, c_spec, shown_backlog,
             str(c_backlog) if backlog_read else '— (not present)'))
out.write('    source D - decision record rows promoting an imported '
          'requirement: %d\n' % d_rows)
if backlog_note:
    out.write('    note: %s\n' % backlog_note)
out.write('    requirements attributed to an import: %d\n' % len(known))
out.write('    of those, already marked, refused or promoted: %d\n'
          % len(settled))
out.write('    attributed requirements with no inferred marking: %d\n'
          % len(findings))

# --- assertions, counted one at a time --------------------------------------
# `upheld` is incremented per item that held. It is NEVER derived from an `ok`
# flag: this repo once printed `upheld: 0` above six lines saying `held:`.
ASSERTIONS = []


def assertion(key, name, examined, upheld, held, note=None):
    ASSERTIONS.append({'key': key, 'name': name, 'examined': examined,
                       'upheld': upheld, 'held': held, 'note': note})


assertion('R10.1', 'an-import-is-on-the-record', 1, 1 if premise else 0,
          'some source above records that a Stage 0c import ran in this '
          'repository',
          None if premise else 'nothing does, so R10 has no premise here and '
                               'nothing below was measured')

assertion('R10.2', 'the-import-yields-a-cohort', 1 if premise else 0,
          1 if (premise and known) else 0,
          'the recorded import can be resolved to the requirement ids it '
          'drafted',
          None if premise else 'not evaluated: no import is on the record')

upheld = 0
for rid in attributed:
    if rid in requirements:
        upheld += 1
assertion('R10.3', 'every-attributed-id-is-defined-in-the-spec',
          len(attributed), upheld,
          'an id a source attributed to the import names a requirement %s '
          'actually defines' % shown,
          None if attributed else 'nothing was attributed, so this assertion '
                                  'did not fire')

upheld = 0
for rid in known:
    if rid in settled:
        upheld += 1
assertion('R10.4', 'every-attributed-requirement-carries-the-marking',
          len(known), upheld,
          'the requirement is marked `Inferred ... Unconfirmed.`, was refused '
          'at import, or was promoted out of one',
          None if known else 'no requirement was attributed to an import, so '
                             'this assertion did not fire')

for entry in ASSERTIONS:
    if entry['examined'] == 0:
        verdict = 'NOT EXERCISED'
    elif entry['upheld'] == entry['examined']:
        verdict = 'held'
    else:
        verdict = 'NOT HELD'
    out.write('    %-6s %-48s examined %3d  upheld %3d  %s: %s\n'
              % (entry['key'], entry['name'], entry['examined'],
                 entry['upheld'], verdict, entry['held']))
    if entry['note']:
        out.write('           note: %s\n' % entry['note'])
out.write('    assertions upheld: %d of %d\n'
          % (sum(1 for e in ASSERTIONS
                 if e['examined'] > 0 and e['upheld'] == e['examined']),
             len(ASSERTIONS)))

for rid in unknown:
    out.write('    NOT CHECKED  %s  named by %s, but %s defines no such '
              'requirement\n'
              % (rid, sorted(attributed[rid])[0], shown))

# --- the verdict, and the three states print differently --------------------
if findings and not settled:
    out.write('    IMPORT MARKED NOTHING.  %d requirement(s) are attributed '
              'to an import and NOT ONE of them carries the marking. This is '
              'not a forgotten marker; it is the convention never having been '
              'applied.\n' % len(findings))
elif findings:
    out.write('    MARKERS MISSING.  %d of %d requirement(s) attributed to an '
              'import carry no marking; the rest do, so the convention was '
              'applied and then dropped.\n' % (len(findings), len(known)))

for rid in findings:
    out.write('    UNMARKED  %s  %s:%d  attributed to an import by %s, '
              'and carries no `Inferred ... Unconfirmed.` marking\n'
              % (rid, shown, requirements[rid]['line'],
                 ', '.join(sorted(attributed[rid]))))

# Findings already found are a definite answer, so they exit 1 even when git
# could not be read.
if findings:
    raise SystemExit(1)

if not premise:
    # NO IMPORT ON THE RECORD IS A MEASUREMENT, NOT A REFUSAL - and getting this
    # wrong once is why the wording below is so careful.
    #
    # R10 is event-driven: "WHEN a repository with history is IMPORTED". Where
    # no import has happened, the obligation never arose, and that is the same
    # shape as `jira-unbound`, which measures that its guard is shut and claims
    # `n/a` rather than refusing. This check briefly exited 2 here on the theory
    # that nothing was measured. Something WAS measured: that four independent
    # sources record no import. That is a fact about the repository, re-read on
    # every run, and it stops being true the moment an import leaves a trace.
    #
    # The distinction that matters: "did the import mark everything?" is
    # unanswerable without an import, and "is R10 in force here?" is answerable
    # and answered No. This reports the second. The coverage claim is `n/a` and
    # it expires by itself - record an import and the premise holds, the other
    # assertions run, and an unmarked cohort becomes a finding.
    out.write('    NO IMPORT ON THE RECORD.  Nothing in %s, %s or this '
              'repository\'s history says a Stage 0c import ran here. R10 is '
              'event-driven, so where no import has happened the obligation '
              'never arose - this is not a claim that imports are marked '
              'correctly, and it is not a refusal to look. Four sources were '
              'read and none records an import; that is re-measured every run '
              'and stops holding the moment one leaves a trace.\n'
              % (shown, shown_backlog))
    raise SystemExit(0)

if not known:
    out.write('    IMPORT ON THE RECORD, COHORT UNRESOLVED.  An import is '
              'recorded, and no requirement id could be attributed to it, so '
              'there was nothing to assert the marking of.\n')
    sys.stderr.write('check-import-marking: an import is on the record and no '
                     'requirement could be attributed to it. Unmeasured, not '
                     'clean.\n')
    raise SystemExit(2)

if b_commits is None:
    raise SystemExit(2)
raise SystemExit(0)
PY
