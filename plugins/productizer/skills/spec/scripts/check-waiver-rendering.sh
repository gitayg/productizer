#!/usr/bin/env bash
# check-waiver-rendering.sh [--root DIR] [--fixture DIR] [--version] [--help]
#
# Asserts R37 and R38, the two halves of a person overriding a failing check:
#
#   R37  WHEN A PERSON OVERRIDES A FAILING CHECK, THE LIFECYCLE SHALL RECORD
#        THE OVERRIDE IN A FILE NAMING THE CHECK, THE AUTHORITY AND THE REASON.
#   R38  WHILE A FAILING CHECK IS OVERRIDDEN, THE LIFECYCLE SHALL RENDER IT AS
#        FAILED AND WAIVED, AND NEVER AS PASSED.
#
# THE DEFECT THIS EXISTS FOR IS A GREEN LINE OVER A RED MEASUREMENT. P1 says a
# value that was not measured is never recorded as a measurement, and intake's
# own words on this item are the design: an overridden check WAS measured, so
# P1 does not forbid recording the override - but a failure rendered green
# because somebody said so is a judgment wearing a measurement's clothes. So
# the waived check's `status` must still read `fail`, its line must still say
# FAIL, and only the BLOCKING must change. A refactor that implemented waivers
# as "set status to pass" would satisfy every casual reading of R38 and produce
# exactly the hollow green this repository keeps having. That is the standing
# case here, and it is asserted in both directions.
#
# WHAT IT DOES. It copies `fixtures/waiver-rendering/` into a temporary
# directory and runs the REAL run-checks.sh against that copy, once per case.
# The temporary copy is not a convenience: the runner writes a result file
# inside the repository it is checking, so pointing it at this repository would
# make a test of the runner a writer to the tree under test.
#
# TEN CASES, TEN RUNS, TEN VERDICTS. Never one run holding ten checks: a
# single run refuses if ANY check refuses, so a regressed case would ride a
# neighbour's refusal straight to a green assertion. Each case gets its own
# config, its own waiver directory, its own run and its own reported tally.
#
#   waived        a failing check with a valid waiver -> FAIL, waived, exit 0
#   unwaived      THE P4 CASE. The same failing check and the same waiver file
#                 still on disk, minus the `policy.waivers` line -> exit 3
#   expired       a waiver past its expiry -> EXPIRED, the check blocks again
#   no-check      a waiver recording no `Check`      -> MALFORMED, blocks
#   no-authority  a waiver recording no `Authority`  -> MALFORMED, blocks
#   no-reason     a waiver recording no `Reason`     -> MALFORMED, blocks
#   no-expires    a waiver recording no `Expires`    -> MALFORMED, blocks
#   unknown       a waiver naming a check nothing declares -> UNKNOWN_CHECK
#   passing       a waiver aimed at a check that PASSED -> NOT_APPLICABLE
#   duplicate     two waivers over one check -> DUPLICATE on both, neither
#                 honoured, and the check blocks
#
# BOTH DIRECTIONS, AND THE PAIR IS THE POINT. `waived` and `unwaived` are the
# same failing check over the same file with the same waiver file present. One
# line of config separates them. A check that only ever asserted the waived
# direction would stay green against a runner that honoured every waiver it
# found, which is the P4 failure; one that only asserted the unwaived direction
# would stay green against a runner that had stopped honouring waivers at all.
#
# P4 - A REPOSITORY BEING EXAMINED NEVER CHOOSES WHAT RUNS. Waiver files live
# in the repository under examination, so a cloned repo able to waive its own
# blocking checks would arrive with them disarmed. The runner's answer, which
# `unwaived` is the standing case for, is that `policy.waivers` is ABSENT BY
# DEFAULT: with no such key the directory is never opened, and enabling it is
# one reviewed line in the committed `checks.yaml` - the same shape and the
# same reasoning as `policy.allow_repo_local_tools`. Three further bounds are
# asserted by the cases above: a waiver selects no executable and grants
# nothing when its `Check` matches no declared id (`unknown`); it expires
# (`expired`); and it can only ever move an already-measured FAILURE, never a
# pass and never an absence (`passing`).
#
# EIGHT ASSERTIONS PER CASE, COUNTED ONE BY ONE. `upheld` is incremented per
# assertion that held and is never derived from one ok flag - a check in this
# repository once printed `upheld: 0` directly above six lines that each said
# `held:`. Tallies are reported PER CASE and never summed: `expired: 8/8`
# beside `waived: 3/8` says which behaviour regressed, and a total does not.
#
# THE PREMISE IS CHECKED FIRST, and a premise that does not hold is exit 2 -
# unmeasured, never a pass. `grep` must be installed, or every case reports
# `missing_tool` and no case is the case it was written to be. The needle must
# really be absent from the file the failing check scans, and present in the
# other. The valid waiver's expiry must still be in the future and the expired
# one's must be in the past, or the fixture has rotted into testing a different
# thing while still exiting 0.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every assertion held, in every case
#   1  an assertion failed - on at least one case the runner no longer treats a
#      waiver the way R37 and R38 require
#   2  could not run - bad usage, no fixture, no runner, no python3, no grep,
#      or a premise that did not hold
#
# WHAT IT PRINTS. One BARE repo-relative PATH per line for every file examined,
# which the runner parses as coverage. Assertions are INDENTED and tagged with
# the case they belong to.
#
# REPORTED BY LOCATION, NEVER BY QUOTING CONTENT. A waiver's `Reason` is text a
# stranger can write, and this output is tailed into a committed result file.
# Findings name the waiver's PATH and its state; they never echo its reason.
# The authority is a fixture-authored label and appears only where R38's
# rendering is the thing being asserted. The runner's own stderr is likewise
# never reproduced wholesale: it names the temporary directory it ran in, and
# an absolute path in a committed file is somebody's home directory published
# to everyone who clones the repo.
#
# PORTABILITY. Developed on macOS/BSD. No GNU-only behaviour: no mapfile, no
# `grep -P`, no `date -d`, no in-place sed, no `stat` format string. Dates are
# compared in python3, which is already required to read the result. Nothing
# suppresses stderr.
set -euo pipefail

VERSION="check-waiver-rendering 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$HERE")"

ROOT=""
MODE="measure"
FIXTURE="$SKILL/fixtures/waiver-rendering"
NEEDLE="WAIVER-FIXTURE-NEEDLE"

die_unmeasured() { printf 'check-waiver-rendering: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    # `--self-test` is an alias, not a second flag: this repository spells the
    # same obligation both ways and a tool that answers only one spelling reads
    # as carrying no self-test to whichever scanner is looking for the other.
    --selftest|--self-test) MODE="selftest"; shift ;;
    --root)      [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)    ROOT="${1#--root=}";        shift ;;
    --fixture)   [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2"; shift 2 ;;
    --fixture=*) FIXTURE="${1#--fixture=}";  shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1" ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1"

# The work tree, never the working directory. --root does not decide what is
# tested - the fixture and the runner are found beside this script - it decides
# what the printed paths are relative to, so nothing absolute reaches the
# committed result.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" || ROOT=""
fi
if [ -n "$ROOT" ] && [ -d "$ROOT" ]; then
  ROOT="$(cd "$ROOT" && pwd -P)"
else
  # No work tree: an installed plugin is not a repository. Paths are then
  # printed relative to the skill directory, which is still not absolute.
  ROOT="$SKILL"
fi

# ---------------------------------------------------------------------------
# --selftest - R39: THIS TOOL REACHES EACH EXIT CODE IT CAN RETURN, ON PURPOSE.
#
# Four cases, one per way the contract above can be reached, each driven
# through THIS script so the argument handling and the premises are on the path
# too. No case is asserted by reading source: the exit code is read off a real
# run of the real runner.
#
#   clean            a byte copy of the committed fixture              -> 0
#   waiver-honoured  the same copy with the `unknown` waiver's `Check`
#                    pointed at the check that really is declared, so
#                    the runner honours a waiver the `unknown` case
#                    says it must report as naming nothing             -> 1
#   no-fixture       a fixture directory that is not there             -> 2
#   bad-usage        an option the parser does not take                -> 2
#
# THE CLEAN CASE IS DRIVEN AGAINST THE COPY, NOT AGAINST THE COMMITTED FIXTURE,
# and that is deliberate. The two runs then differ in ONE FIELD OF ONE WAIVER,
# so the exit code moving from 0 to 1 is attributable to that field and to
# nothing else.
#
# THE CLEAN CASE GUARDS THE OTHER THREE. If the copy does not exit 0, the
# waiver-honoured case would be red for whatever is wrong with the copy - exit
# 2 for the whole self-test, never a pass on the cases that followed.
#
# THE TWO HEAVY CASES RUN CONCURRENTLY, AND THAT IS NOT AN OPTIMISATION. Each
# one starts the real runner ten times, once per waiver case, and the runner
# polls a running check once a second - so a drive costs about twenty seconds
# of wall clock whatever the machine. Run one after the other the pair would
# exceed the budget check-selftest-coverage.sh allows a single self-test, and a
# self-test that times out is reported `?` - unreadable - which REFUSES that
# check rather than answering it. The two drives share nothing but a read-only
# copy of the fixture and their own temporary directories, so running them at
# once changes no verdict.
#
# NOTHING IS WRITTEN INTO THE REPOSITORY. Both fixtures are copies under
# mktemp, the runner writes its result inside them, and the directory goes on
# every exit path, signal included. `view-read-only` hashes this tree while the
# suite runs and a file appearing in it inside that window is reported as the
# view builder moving a repository file.
#
# WHAT THIS SELF-TEST DOES NOT ASSERT, printed rather than passed silently: it
# reads the exit CODE and never which of the eighty assertions moved, so a case
# that went red for the wrong reason is invisible here.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-waiver-rendering-selftest.XXXXXX")" \
    || die_unmeasured "cannot create a temporary directory to build the self-test's fixtures in; nothing was driven"
  trap 'rm -rf "$SB"' EXIT HUP INT TERM

  [ -d "$FIXTURE" ] \
    || die_unmeasured "no fixture directory to copy, so neither drive had a corpus. Unmeasured, not a pass"
  cp -R "$FIXTURE" "$SB/intact" \
    || die_unmeasured "the fixture could not be copied, so neither drive had a corpus. Unmeasured, not a pass"
  cp -R "$FIXTURE" "$SB/honoured" \
    || die_unmeasured "the second copy could not be made, so the case that must go red was never built. Unmeasured, not a pass"

  # ONE FIELD OF ONE WAIVER. The `unknown` case exists to assert that a waiver
  # whose `Check:` matches no declared id grants nothing and is reported
  # `unknown_check`. Pointing that field at `finding` - the id the fixture's
  # config really does declare - turns it into a waiver the runner honours, so
  # the case's expected state, its expected blocking count and its expected
  # exit code all move at once. That is the difference between the two drives
  # and it is the only one.
  #
  # awk writes a new file rather than editing in place: `sed -i` takes an
  # argument on BSD and none on GNU, and this repository has shipped that
  # difference as a CI-only failure before.
  for _w in "$SB/honoured"/waivers/unknown/*.md; do
    awk '/^Check:/ { print "Check: finding"; next } { print }' "$_w" > "$_w.rewritten" \
      || die_unmeasured "the waiver copy could not be rewritten, so the case that must go red was never built. Unmeasured, not a pass"
    mv "$_w.rewritten" "$_w"
  done
  if diff -r "$SB/intact" "$SB/honoured" > /dev/null; then
    die_unmeasured "the two fixture copies are identical, so the waiver-honoured case is the clean case run twice and would prove nothing. Unmeasured, not a pass"
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
      printf '  held:    case %-16s expected %s  observed %s  %s\n' "$1" "$2" "$_rc" "$3"
    else
      printf '  FINDING: case %-16s expected %s  observed %s  %s\n' "$1" "$2" "$_rc" "$3"
      SELF_FAILED=$((SELF_FAILED + 1))
    fi
  }

  self_bg clean --root "$ROOT" --fixture "$SB/intact"
  self_bg waiver-honoured --root "$ROOT" --fixture "$SB/honoured"
  self_bg no-fixture --root "$ROOT" --fixture "$SB/there-is-no-fixture-here"
  self_bg bad-usage --root "$ROOT" --no-such-option
  wait

  CLEAN_RC="$(cat "$SB/clean.rc")"
  if [ "$CLEAN_RC" != 0 ]; then
    printf '  the clean case exited %s, not 0.\n' "$CLEAN_RC"
    die_unmeasured "a byte copy of the committed fixture did not produce a clean run, so the waiver-honoured case below would be red for that reason instead of its own. Unmeasured, not a corpus that held"
  fi

  self_report clean 0 \
    "a byte copy of the committed fixture: eighty assertions over ten waiver cases, all upheld"
  self_report waiver-honoured 1 \
    "the same copy with the unknown waiver aimed at the check that IS declared, so the runner honours it and the unknown case's state, blocking count and exit code all move"
  self_report no-fixture 2 \
    "no fixture directory at the path given, so the standing case is missing - unmeasured, never a pass"
  self_report bad-usage 2 \
    "an option this parser does not take: bad usage is refused rather than ignored"

  printf '  self-test cases driven: %d, exit codes reached: 0, 1, 2. Cases that did not hold: %d\n' \
    "$SELF_CASES" "$SELF_FAILED"
  printf '  NOT ASSERTED: which of the eighty assertions moved. Each case reads the exit CODE, so a case that went red for the wrong reason is invisible here and is read off the case output by hand.\n'
  if [ "$SELF_FAILED" -ne 0 ]; then
    printf 'check-waiver-rendering: %d self-test case(s) did not produce the exit code the contract declares for them.\n' "$SELF_FAILED" >&2
    exit 1
  fi
  printf '  R39 for this tool: the self-test exists and reaches 0, 1 and 2 by driving the real check against a real runner, not by reading its source.\n'
  exit 0
fi

# label : config : the check id in it : the waiver directory it declares
# ("-" for the P4 case, which declares none).
CASES="waived:checks-waived.yaml:finding:waivers/valid
unwaived:checks-unwaived.yaml:finding:-
expired:checks-expired.yaml:finding:waivers/expired
no-check:checks-no-check.yaml:finding:waivers/no-check
no-authority:checks-no-authority.yaml:finding:waivers/no-authority
no-reason:checks-no-reason.yaml:finding:waivers/no-reason
no-expires:checks-no-expires.yaml:finding:waivers/no-expires
unknown:checks-unknown.yaml:finding:waivers/unknown
passing:checks-passing.yaml:clean:waivers/passing
duplicate:checks-duplicate.yaml:finding:waivers/duplicate"

field() { printf '%s\n' "$1" | cut -d: -f"$2"; }

RUNNER="$HERE/run-checks.sh"
[ -f "$RUNNER" ] || die_unmeasured "no run-checks.sh beside this script; there is nothing to test"
[ -d "$FIXTURE" ] || die_unmeasured "no fixture directory; the standing case is missing, which is unmeasured and not a pass"
[ -f "$FIXTURE/changed.txt" ] || die_unmeasured "the fixture has no changed.txt"
# stderr-ok: `command -v` on a name that is not installed writes nothing worth
# reading, and its EXIT STATUS is the whole answer this premise probe wants; the
# absence itself is reported by the die_unmeasured on the same line.
command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the result could not be read"
# stderr-ok: same probe, same reason - the exit status is the answer, and an
# absent grep is reported in words by the die_unmeasured on this line.
command -v grep >/dev/null 2>&1 || die_unmeasured "grep is not installed, so every fixture check would report missing_tool and no case would be the case it was written to be; unmeasured, not a pass"

for spec in $CASES; do
  cfg="$(field "$spec" 2)"
  [ -f "$FIXTURE/$cfg" ] || die_unmeasured "the fixture has no $cfg, so the $(field "$spec" 1) case was never run. A case that is absent is unmeasured, not a pass"
done
[ -f "$FIXTURE/fixture/finding.txt" ] || die_unmeasured "the fixture has no fixture/finding.txt; there is no failure to waive"
[ -f "$FIXTURE/fixture/clean.txt" ]   || die_unmeasured "the fixture has no fixture/clean.txt; there is no passing check to aim a waiver at"

# PREMISE - the failing check really fails and the passing one really passes.
# Both greps are EXPECTED to answer, one way each, so the status is inspected
# rather than allowed to end the script: under `set -e` a `grep -q` that finds
# nothing exits 1 and kills the run mid-premise, printing an exit code and no
# reason.
if grep -q "$NEEDLE" "$FIXTURE/fixture/finding.txt"; then
  die_unmeasured "fixture/finding.txt holds the needle, so the check that scans it would PASS and there would be no failure to waive. The premise failed; unmeasured, not a pass"
fi
if grep -q "$NEEDLE" "$FIXTURE/fixture/clean.txt"; then :; else
  die_unmeasured "fixture/clean.txt does not hold the needle, so the check that scans it would FAIL and the `passing` case would stop being about a passing check. The premise failed; unmeasured, not a pass"
fi

# PREMISE - each case declares the waiver directory it was written for, read
# from the config rather than assumed here. A config edited to point somewhere
# else would otherwise keep this check green while testing nothing.
for spec in $CASES; do
  label="$(field "$spec" 1)"; cfg="$(field "$spec" 2)"; want="$(field "$spec" 4)"
  got="$(sed -n 's/^  waivers: *//p' "$FIXTURE/$cfg" | sed -n '1p')"
  if [ "$want" = "-" ]; then
    [ -z "$got" ] || die_unmeasured "$label: $cfg declares a \`policy.waivers\` key, so it is no longer the case where waivers are switched off. The premise failed; unmeasured, not a pass"
  else
    [ "$got" = "$want" ] || die_unmeasured "$label: $cfg declares waivers dir '$got', not the '$want' this case was written for. The premise failed; unmeasured, not a pass"
    [ -d "$FIXTURE/$want" ] || die_unmeasured "$label: the fixture has no $want directory, so the waiver this case is about does not exist. Unmeasured, not a pass"
  fi
done

# PREMISE - the P4 case is only a P4 case while the waiver it would have
# honoured is still sitting on disk. Without that file, `unwaived` blocking
# proves nothing about the default being off; it proves only that there was
# nothing to honour.
[ -f "$FIXTURE/waivers/valid/W1-finding.md" ] || die_unmeasured "the fixture has no waivers/valid/W1-finding.md, so the unwaived case has no unread waiver beside it and cannot show that the default is off rather than empty. Unmeasured, not a pass"

# PREMISE - the fixture has not rotted. A `valid` waiver whose expiry has
# quietly passed would turn the honoured case into a second expired case, and
# an `expired` one dated in the future would stop testing expiry at all. Dates
# are compared in python3: `date -d` is GNU-only and `date -j` is BSD-only.
python3 - "$FIXTURE/waivers/valid/W1-finding.md" "$FIXTURE/waivers/expired/W2-finding.md" <<'PY' || die_unmeasured "the fixture's waiver expiries no longer bracket today, so the honoured and expired cases are not the cases they were written to be. Unmeasured, not a pass"
import datetime, re, sys

today = datetime.date.today().isoformat()


def expires(path):
    with open(path, errors="replace") as fh:
        for ln in fh:
            m = re.match(r"^Expires:[ \t]*(\d{4}-\d{2}-\d{2})[ \t]*$", ln.rstrip("\n"))
            if m:
                return m.group(1)
    return None


live, dead = expires(sys.argv[1]), expires(sys.argv[2])
ok = live is not None and dead is not None and live >= today and dead < today
if not ok:
    sys.stderr.write("check-waiver-rendering: valid waiver expires %r, expired waiver expires %r, "
                     "today is %s.\n" % (live, dead, today))
sys.exit(0 if ok else 1)
PY

rel() {
  case "$1" in
    "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;;
    *)         printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;;
  esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SANDBOX="$TMP/repo"
mkdir -p "$SANDBOX"
cp -R "$FIXTURE"/. "$SANDBOX/"

# Every file this check opened, one bare path per line. The waiver files are
# named because they ARE the subject: R37 is about what a file records.
rel "$RUNNER"
rel "$FIXTURE/changed.txt"
rel "$FIXTURE/fixture/finding.txt"
rel "$FIXTURE/fixture/clean.txt"
for spec in $CASES; do
  rel "$FIXTURE/$(field "$spec" 2)"
done
for w in "$FIXTURE"/waivers/*/*.md; do
  rel "$w"
done

cat > "$TMP/assert.py" <<'PY'
"""Read what one run reported and say whether R37 and R38 still hold for it.

stdout: one indented, case-tagged line per assertion. Exit 0 all held, 1 one
did not, 2 the result could not be read at all - which is never reported as a
pass, because a result nobody could read is not a result that rendered
anything.

`upheld` is COUNTED, one increment per assertion that held, never derived from
a single ok flag.
"""
import json
import re
import sys

(result_path, err_path, rc_txt, label, check_id, waiver_dir,
 want_rc, want_status, want_blocking, want_waived, want_state, want_entries,
 tally_path) = sys.argv[1:14]

want_rc = int(want_rc)
want_entries = int(want_entries)
want_blocking = int(want_blocking)
want_waived = int(want_waived)
out = sys.stdout
TOTAL = 8
upheld = 0
WAIVED_MARK = "FAIL · WAIVED BY "


def say(held, text):
    global upheld
    if held:
        upheld += 1
    out.write("  [%s] %s %s\n" % (label, "held:" if held else "FINDING: did not hold -", text))


def finish(code):
    with open(tally_path, "w") as fh:
        fh.write("%d/%d\n" % (upheld, TOTAL))
    out.write("  [%s] assertions evaluated: %d, upheld: %d\n" % (label, TOTAL, upheld))
    sys.exit(code)


try:
    with open(result_path, errors="replace") as fh:
        doc = json.load(fh)
except (OSError, ValueError) as exc:
    with open(tally_path, "w") as fh:
        fh.write("0/%d unreadable\n" % TOTAL)
    out.write("  [%s] the runner's result could not be read: %s\n" % (label, exc.__class__.__name__))
    out.write("  [%s] assertions evaluated: 0 of %d. Unmeasured, not a pass.\n" % (label, TOTAL))
    sys.exit(2)

try:
    with open(err_path, errors="replace") as fh:
        err = fh.read()
except OSError:
    err = ""

rows = {c.get("id"): c for c in doc.get("checks") or []}
row = rows.get(check_id) or {}
if check_id not in rows:
    out.write("  [%s] note: the result records no row for `%s` at all; the assertions below "
              "fail for that reason.\n" % (label, check_id))
counts = doc.get("counts") or {}
wv = doc.get("waivers") or {}
entries = wv.get("entries") or []
entry = entries[0] if entries else {}

# 1 - the exit code. A waived failure must not block; an unwaived, expired,
# malformed or unknown one must.
say(rc_txt == str(want_rc), "the run exits %d; it exited %s" % (want_rc, rc_txt))

# 2 - R38's core. THE MEASUREMENT DOES NOT MOVE.
# The `and not pass` half is the property a waiver-implemented-as-a-status-
# rewrite would break, and it is only meaningful where the check really did
# fail. The `passing` case is the one where `pass` is the right answer.
say(row.get("status") == want_status
    and (want_status == "pass" or row.get("status") != "pass"),
    "the check's recorded status is `%s`%s; it is %r"
    % (want_status, "" if want_status == "pass" else " and is not `pass`",
       row.get("status")))

# 3 - whether it BLOCKED, which is the only thing a waiver is allowed to change.
say(counts.get("blocking_failures") == want_blocking
    and doc.get("verdict") == ("refused" if want_blocking else "pass"),
    "it counts %d blocking failure(s) and the verdict is `%s`; it counts %r and %r"
    % (want_blocking, "refused" if want_blocking else "pass",
       counts.get("blocking_failures"), doc.get("verdict")))

# 4 - the waived tally is its own number. A failure moved out of the blocking
# count and into nothing at all is a failure that has gone quiet.
say(counts.get("waived") == want_waived,
    "it counts %d waived failure(s); it counts %r" % (want_waived, counts.get("waived")))

# 5 - what the runner made of the waiver file itself, one state per case. This
# is the assertion that tells the four malformed cases apart from each other's
# and from `expired`, `unknown_check` and `not_applicable`.
if want_state == "-":
    say(wv.get("declared") is False and not entries,
        "no waiver directory was declared, so nothing was read: `waivers.declared` is %r with "
        "%d entr(ies)" % (wv.get("declared"), len(entries)))
else:
    say(wv.get("declared") is True and len(entries) == want_entries
        and all(w.get("state") == want_state for w in entries),
        "all %d waiver(s) read from %s are recorded `%s`; %d entr(ies), states %r"
        % (want_entries, waiver_dir, want_state, len(entries),
           [w.get("state") for w in entries]))

# 6 - R38's RENDERING. The reported line, not the whole stream: the stream
# names the temporary directory the run happened in.
line = ""
for ln in err.splitlines():
    if re.search(r"\s%s\s+(block|advise)\s" % re.escape(check_id), ln):
        line = ln
        break
if want_state == "honoured":
    say(line.lstrip().startswith(WAIVED_MARK) and "PASS" not in line,
        "the stage line for `%s` reads `FAIL · WAIVED BY <authority>` and never PASS"
        % check_id)
elif want_status == "fail":
    say(line.lstrip().startswith("FAIL") and WAIVED_MARK not in line,
        "the stage line for `%s` reads FAIL and is NOT rendered as waived" % check_id)
else:
    say(line.lstrip().startswith("PASS") and WAIVED_MARK not in line,
        "the stage line for `%s` reads PASS and is not rendered as waived" % check_id)

# 7 - the waiver sits BESIDE the failure in the machine-readable result, or is
# absent from it. A rendering nobody downstream can read is half the obligation.
w = row.get("waiver")
if want_state == "honoured":
    say(isinstance(w, dict) and w.get("file") == entry.get("file") and bool(w.get("authority"))
        and bool(w.get("expires")),
        "the check's own row carries the waiver, naming its location and the authority; it "
        "carries %r" % (w,))
else:
    say(w is None, "the check's own row carries no waiver; it carries %r" % (w,))

# 8 - the case-specific reason, in words a reader can act on, and by LOCATION.
detail = (entry.get("detail") or "") if want_state != "-" else ""
if want_state == "malformed":
    missing = {"no-check": "Check", "no-authority": "Authority",
               "no-reason": "Reason", "no-expires": "Expires"}[label]
    say("`%s`" % missing in detail and entry.get("file", "").startswith(waiver_dir),
        "the malformed waiver is reported by LOCATION under %s and its report names the "
        "absent `%s` field" % (waiver_dir, missing))
elif want_state == "expired":
    say("expired on" in detail and entry.get("expires") is not None,
        "the report says the waiver expired and gives the date it expired on")
elif want_state == "unknown_check":
    # The unknown id is repository text that matched nothing. It is reported by
    # location and must NOT be echoed.
    say("does not declare" in detail and "no-such-check-is-declared" not in detail
        and entry.get("check") is None,
        "the unknown check is reported by location, and the unrecognised id is not quoted back")
elif want_state == "duplicate":
    say(all("not an override" in (w.get("detail") or "") for w in entries)
        and all(w.get("file", "").startswith(waiver_dir) for w in entries),
        "both waivers are reported by LOCATION under %s and each says two authorities over one "
        "check is not an override" % waiver_dir)
elif want_state == "not_applicable":
    say("`pass`" in detail and "never the absence" in detail,
        "the report says the named check passed and that only a failure can be waived")
elif want_state == "honoured":
    summary = [ln for ln in err.splitlines() if ln.startswith("PASS: ")]
    summary = summary[0] if summary else ""
    say("waived by a person" in summary and "FAILED" in summary,
        "the run's own summary says a blocking check FAILED and was waived by a person, rather "
        "than reporting a clean run")
else:  # the P4 case: nothing was read, and the unread waiver is still there
    say("REFUSED: " in err and check_id in err.split("REFUSED: ")[-1],
        "the run names `%s` in its REFUSED line, with the waiver file that would have "
        "honoured it sitting unread on disk" % check_id)

finish(0 if upheld == TOTAL else 1)
PY

# label : expected rc : expected status : expected blocking count : expected
# waived count : expected waiver state : expected number of waiver files read
EXPECT="waived:0:fail:0:1:honoured:1
unwaived:3:fail:1:0:-:0
expired:3:fail:1:0:expired:1
no-check:3:fail:1:0:malformed:1
no-authority:3:fail:1:0:malformed:1
no-reason:3:fail:1:0:malformed:1
no-expires:3:fail:1:0:malformed:1
unknown:3:fail:1:0:unknown_check:1
passing:0:pass:0:0:not_applicable:1
duplicate:3:fail:1:0:duplicate:2"

FAILED=0
SUMMARY=""

for spec in $CASES; do
  label="$(field "$spec" 1)"
  cfg="$(field "$spec" 2)"
  cid="$(field "$spec" 3)"
  wdir="$(field "$spec" 4)"

  exp=""
  for e in $EXPECT; do
    case "$e" in "$label":*) exp="$e"; break ;; esac
  done
  [ -n "$exp" ] || die_unmeasured "$label: no expectation declared for this case"

  RC=0
  # A refused run exits 3 and that is the expected outcome for seven of the
  # nine cases, so the status is captured rather than allowed to kill the
  # script: under `set -e` an uncaught 3 would end the run mid-case, printing
  # an exit code and no reason, with the remaining cases never attempted.
  bash "$RUNNER" --config "$SANDBOX/$cfg" --root "$SANDBOX" \
    --changed "$SANDBOX/changed.txt" --out "$TMP/$label.json" \
    > "$TMP/$label.out" 2> "$TMP/$label.err" || RC=$?

  ARC=0
  # Same reason: 1 means an assertion did not hold, which is a result to
  # report, not a reason to abandon the other cases.
  python3 "$TMP/assert.py" "$TMP/$label.json" "$TMP/$label.err" "$RC" \
    "$label" "$cid" "$wdir" \
    "$(field "$exp" 2)" "$(field "$exp" 3)" "$(field "$exp" 4)" \
    "$(field "$exp" 5)" "$(field "$exp" 6)" "$(field "$exp" 7)" \
    "$TMP/$label.tally" || ARC=$?

  tally="$(cat "$TMP/$label.tally")"
  SUMMARY="$SUMMARY | $label: $tally upheld"

  case "$ARC" in
    0) : ;;
    1) FAILED=$((FAILED + 1)) ;;
    *) die_unmeasured "$label: the assertions could not be evaluated; unmeasured, not a pass" ;;
  esac
done

printf '  per case:%s\n' "${SUMMARY# |}"

if [ "$FAILED" -eq 0 ]; then
  printf '  R37 and R38 satisfied: a waiver records the check, one authority and the reason or it is not honoured; a waived failing check is rendered FAIL and waived, keeps its `fail` status, and stops blocking; and the same check without a `policy.waivers` line still blocks with its waiver file unread on disk.\n'
  exit 0
fi
printf '  R37 and R38 not satisfied on %d of the cases above: see the findings, which name the case. A waiver is no longer treated the way the spec requires.\n' "$FAILED"
exit 1
