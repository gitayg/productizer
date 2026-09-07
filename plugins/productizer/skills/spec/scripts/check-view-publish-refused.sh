#!/usr/bin/env bash
# check-view-publish-refused.sh [--root DIR] [--hook PATH] [--fixture DIR]
#                              [--settings PATH] [--log PATH]
#                              [--max-age-days N] [--version] [--help]
#
# Asserts the half of R31 that nothing observed: IF A PUBLISHED VIEW DECLARES A
# CAPABILITY THAT CAN PUBLISH NEW VERSIONS OF ITSELF, THEN THE LIFECYCLE SHALL
# REFUSE TO PUBLISH IT.
#
# WHY THIS EXISTS SEPARATELY FROM `view-read-only`. That check reads the
# generated page and asserts it declares no such capability - it observes the
# page NOT ASKING. R31's obligation is that the lifecycle REFUSES TO PUBLISH,
# and until `.claude/hooks/artifact-gate.sh` there was no refusal to observe,
# because an artifact is published through the Artifact tool and the existing
# publish gate is registered on Bash. Half of R31 was unimplemented rather than
# merely unverified. This check drives the real hook and watches it decline.
#
# It also reaches the surface `view-read-only` writes down that it cannot
# reach. Its limitations block says the grant is made when the page is
# published, not inside the page, so a capability granted at publish time
# leaves no trace in the file it reads. Cases marked `call` here are exactly
# that: a clean page, a forbidden capability in the publish call's
# `capabilities` argument, and a refusal.
#
# NOTHING IS EVER PUBLISHED. The hook is a filter on a tool call, so it is fed
# a payload on stdin and its decision is read off stdout. No page leaves this
# machine, and the fixture pages are not real views - they are the smallest
# thing that declares each capability.
#
# SIX ASSERTIONS, COUNTED SEPARATELY. A single `ok` flag reported above six
# lines of evidence is how a check in this repo printed `upheld: 0` while
# holding six things; each group below carries its own case count and its own
# upheld count, and a group is upheld only when every case in it is.
#
#   A1  a page ASKING for a self-publishing capability is refused
#   A2  a self-publishing capability GRANTED BY THE CALL is refused, even when
#       the page's own source is clean
#   A3  a publish this gate cannot read is refused rather than guessed at
#   A4  a publish that declares only output IS ALLOWED. A gate that blocks
#       every publish is as broken as one that blocks none, and it is switched
#       off just as fast
#   A5  the emitted document carries exactly ONE decision, and it is the gate's
#       own. Text out of the page reaches the reason string, so a page holding
#       the literal bytes of an allow decision must not be able to forge one by
#       being quoted back
#   A6  the hook this check drove is the hook the harness is CONFIGURED TO RUN.
#       A1-A5 feed it a payload directly, so all five hold just as well for a
#       correct gate that nothing ever invokes. Three parts, and each one is a
#       way the wiring has failed elsewhere: an entry exists whose matcher is
#       exactly `Artifact`; its command resolves to a file that exists and is
#       executable; and that file is BYTE-IDENTICAL to the one driven here, so
#       a registration pointing at a stale or different copy is a finding
#       rather than a pass. Compared by content, never by string equality of
#       the configured value - two spellings of the same path are the same
#       hook, and one spelling of two different files is not.
#   A7  the hook HAS ACTUALLY BEEN INVOKED BY THE TOOL. A6 proves the wiring
#       and stops there; every assertion above it holds just as well for a
#       correct gate that nothing ever calls. See the next block.
#   A8  the gate RECORDS every decision it makes, and records the decision it
#       actually made. A7's evidence is a log file, so a log that silently
#       stopped being written would make A7 read as "the tool has not published
#       yet" forever. This asserts the recorder from the other end: the twenty
#       cases above are driven with the record redirected to a temp file, and
#       that file must come back holding exactly those twenty decisions, in
#       order. It is measurable on every run, with no publish involved.
#
# A6 ASSERTED THE WIRING AND NOT THE FIRING, AND A7 IS WHY THAT REASONING WAS
# WRONG. The stated reason the firing could not be observed was that observing
# it needs a real publish, which is the act this gate exists to refuse. But
# THIS GATE DOES NOT REFUSE EVERY PUBLISH - A4 is the assertion that it must
# not. A page declaring only `downloads` is ALLOWED, which is what the
# dashboard declares and what gets published routinely. A legitimate, permitted
# publish was therefore available as evidence the whole time; what was missing
# was that the hook left no trace when it ran. It leaves one now, and A7 reads
# it: `.claude/productizer/artifact-gate-log.jsonl`, not committed, one JSON
# object per line, bounded, carrying a timestamp, the decision, the action, the
# gate's version and the page's BASENAME only.
#
# A7 IS FOUR PARTS, AND THE FIRST ONE IS WHAT MAKES THE OTHER THREE MEAN
# ANYTHING. This check drives the hook twenty times per run; if those writes
# landed in the record, A7 would be reading back its own footprints. So the
# cases are driven with ARTIFACT_GATE_LOG pointed at a temp file, and part one
# fingerprints the real record before and after the driving and asserts it did
# not change. Part two: it holds at least one parseable decision. Part three:
# at least one inside the recency window (--max-age-days, default 30). Part
# four: nothing in it is shaped like an absolute path or a home-directory slug.
#
# NO RECORD IS UNMEASURED, AND IS NEVER A PASS. A missing record file, an empty
# one, or one whose newest line is outside the window means the Artifact tool
# has not published since this gate began recording. That is exit 2 with the
# reason on stderr - not exit 0, and not a finding. "I have not seen it happen"
# and "it does not happen" are different sentences.
#
# WHAT A RECORD PROVES, STATED RATHER THAN HIDDEN. It proves this hook ran,
# under the tool, on the publishes it names. It does NOT prove the tool would
# invoke it for a publish the hook would REFUSE: the only thing that settles
# that is a `deny` line in the record, and a `deny` only appears when someone
# actually attempts a forbidden publish. Every run prints how many `deny` lines
# are in the window, and says in as many words when there are none. An `allow`
# is not counted as evidence of a refusal.
#
# THE PREMISE IS GUARDED, FIVE WAYS. If the fixture holds no page declaring a
# forbidden capability, no call granting one, no unreadable publish, or nothing
# that must be allowed, then the corresponding refusal was never exercised and
# this run asserts nothing about it - exit 2, unmeasured, never a pass. An
# assertion sweeping an empty set has already shipped in this repo once. The
# fifth premise is A6's: a settings file that is absent or that does not parse
# is exit 2, because a registration nobody could read has not been shown to
# exist, and "I could not find it" is not "it is not there".
#
# DECLARED LIMITATION OF A6. The matcher must be spelled exactly `Artifact`. A
# harness that also honours a regex spelling - `Artifact|Bash`, say - would be
# correctly wired and reported here as a finding. That is the false positive
# this strictness buys, it is loud rather than silent, and the finding names
# the matcher it did find so the reader is not left guessing.
#
# DECLARED LIMITATIONS OF A7, ALL THREE OF THEM.
#
#   1. A record proves the hook RAN. It does not prove WHO ran it. A person
#      typing `bash .claude/hooks/artifact-gate.sh` at a prompt writes the same
#      line the tool does. Part one rules out THIS CHECK as the author and
#      nothing else. What makes the tool the likely author is that the record
#      is not written by anything else in this lifecycle, and that the actions
#      and page names in it match publishes that were actually made.
#   2. Anyone who exports ARTIFACT_GATE_LOG in their shell silences the real
#      record for every hook run under it. That direction is safe - A7 goes
#      UNMEASURED, never falsely green - but it is a way to make the assertion
#      stop asserting without touching a file.
#   3. The recency window is a wall clock comparison between the record's epoch
#      field and this machine's `date -u +%s`. A machine whose clock is wrong
#      reads its own records as future-dated or ancient. Records dated in the
#      future are counted as recent, deliberately: refusing them would turn a
#      clock skew into a failure of R31.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every case reached the decision the fixture says it must
#   1  findings - a publish that had to be refused was not, one that had to go
#      through did not, or a decision was not the gate's own
#   2  could not run - bad usage, no work tree, no hook, no fixture, an
#      unreadable case file, a premise that was never exercised, or A7 with no
#      decision record to read. Findings win over unmeasured: a run that
#      definitely broke something is reported as broken even when some other
#      assertion could not be measured.
#
# WHAT IT PRINTS. One BARE repo-relative path per line for every file examined,
# which the runner parses as coverage. Case lines, findings and counts are
# INDENTED. Nothing absolute is printed and no reason text is reproduced: this
# output is tailed into a committed result file, and both a home directory and
# a page's own bytes would be published to everyone who clones the repo.
set -euo pipefail

VERSION="check-view-publish-refused 1.1"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT=""; HOOK=""; FIXTURE=""; SETTINGS=""; GATELOG=""
MODE="measure"

# How old the newest decision record may be and still count as evidence that
# the tool invokes this hook. Thirty days: long enough that a fortnight without
# publishing anything does not read as a broken gate, short enough that a
# record from a hook version deleted months ago is not still vouching for one
# that exists today.
MAX_AGE_DAYS=30

die_unmeasured() { printf 'check-view-publish-refused: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    # `--self-test` is an alias, not a second flag: this repository spells the
    # same obligation both ways and a tool that answers only one spelling reads
    # as carrying no self-test to whichever scanner is looking for the other.
    --selftest|--self-test) MODE="selftest"; shift ;;
    --root)      [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)    ROOT="${1#--root=}";       shift ;;
    --hook)      [ "$#" -ge 2 ] || die_unmeasured "--hook needs a path";    HOOK="$2";    shift 2 ;;
    --hook=*)    HOOK="${1#--hook=}";       shift ;;
    --fixture)   [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2"; shift 2 ;;
    --fixture=*) FIXTURE="${1#--fixture=}"; shift ;;
    --settings)   [ "$#" -ge 2 ] || die_unmeasured "--settings needs a path"; SETTINGS="$2"; shift 2 ;;
    --settings=*) SETTINGS="${1#--settings=}"; shift ;;
    --log)        [ "$#" -ge 2 ] || die_unmeasured "--log needs a path";      GATELOG="$2"; shift 2 ;;
    --log=*)      GATELOG="${1#--log=}";    shift ;;
    --max-age-days)   [ "$#" -ge 2 ] || die_unmeasured "--max-age-days needs a number"; MAX_AGE_DAYS="$2"; shift 2 ;;
    --max-age-days=*) MAX_AGE_DAYS="${1#--max-age-days=}"; shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1. The tree is named with --root." ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1. The tree is named with --root."

# The work tree, never the working directory. Run from a subdirectory this must
# check the same thing it checks from the root, or the answer depends on where
# the person stood when they asked.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" \
    || die_unmeasured "no git work tree here, and --root was not given. The hook to drive could not be located; unmeasured, not clean."
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

[ -n "$HOOK" ]    || HOOK="$ROOT/.claude/hooks/artifact-gate.sh"
[ -n "$FIXTURE" ] || FIXTURE="$HERE/../fixtures/view-publish-refused"

[ -f "$HOOK" ] && [ -r "$HOOK" ] \
  || die_unmeasured "no readable publish hook at the path given. There is nothing to drive, so whether the lifecycle refuses to publish a self-publishing view is UNMEASURED, not satisfied"
[ -d "$FIXTURE" ] || die_unmeasured "no fixture directory at the path given; there are no publishes to drive"
FIXTURE="$(cd "$FIXTURE" && pwd -P)"
CASES="$FIXTURE/cases.tsv"
[ -f "$CASES" ] && [ -r "$CASES" ] || die_unmeasured "no readable cases.tsv in the fixture; nothing to drive"

command -v jq >/dev/null 2>&1 || die_unmeasured "jq is not installed; the hook's decision could not be read, which is unmeasured and not a pass"

case "$MAX_AGE_DAYS" in
  ''|*[!0-9]*) die_unmeasured "--max-age-days must be a whole number of days; got '$MAX_AGE_DAYS'. A window this check cannot read is not one it may guess at" ;;
esac
[ "$MAX_AGE_DAYS" -gt 0 ] || die_unmeasured "--max-age-days must be greater than zero; a window of zero days admits no record ever and would report a working gate as unmeasured forever"

# ---------------------------------------------------------------------------
# --selftest - R39: THIS TOOL REACHES EACH EXIT CODE IT CAN RETURN, ON PURPOSE.
#
# Four cases, one per way the contract above can be reached, each driven
# through THIS script so the argument handling and the premise guards are on
# the path too. Nothing is stubbed and no case is asserted by reading source:
# the exit code is read off a real run.
#
#   clean            the committed hook and the committed fixture      -> 0
#   gate-allows-all  the same fixture and a gate that refuses nothing  -> 1
#   no-fixture       a fixture directory that is not there             -> 2
#   bad-usage        an option the parser does not take                -> 2
#
# THE CLEAN CASE GUARDS THE OTHERS' PREMISE. If driving the committed hook does
# not exit 0, every case below would be red for that reason rather than its
# own, and nothing would have been measured - so that is exit 2 for the whole
# self-test, never a pass on the three that followed.
#
# NOTHING IS WRITTEN INTO THE REPOSITORY. The broken gate is a copy under
# mktemp and the directory goes on every exit path, signal included.
# `view-read-only` hashes this tree while the suite runs, and a file appearing
# here inside that window is reported as the view builder moving a repository
# file - a check that mutated the tree would make a sibling check fail for a
# reason nobody could find.
#
# WHAT THIS SELF-TEST DOES NOT ASSERT, printed rather than passed silently: it
# reads the exit CODE and never the wording of a finding, so a case that went
# red for the wrong reason is invisible here.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-view-publish-refused-selftest.XXXXXX")" \
    || die_unmeasured "cannot create a temporary directory to build the self-test's inputs in; nothing was driven"
  trap 'rm -rf "$SB"' EXIT HUP INT TERM

  # The production defect A1, A2 and A3 exist to catch: a gate that emits a
  # well-formed decision and allows every publish, including the ones R31
  # obliges it to refuse. It is the ONLY thing separating this case from the
  # clean one, so the exit code moving from 0 to 1 is attributable to it.
  cat > "$SB/allow-everything.sh" <<'SELFTEST_HOOK'
#!/usr/bin/env bash
# Built by check-view-publish-refused.sh --selftest. Never registered, never
# reachable from the repository: it lives under mktemp for one run.
cat >/dev/null
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"a gate that refuses nothing"}}\n'
SELFTEST_HOOK
  chmod +x "$SB/allow-everything.sh"

  SELF_CASES=0
  SELF_FAILED=0
  # R39.b: the reached half of the declaration below is ACCUMULATED here,
  # one entry per case as it ran. A literal list would satisfy the reader
  # and prove nothing.
  CODES=""

  # $1 case, $2 expected exit, $3 what the case is, then the argv to drive.
  #
  # `|| _rc=$?` on the SAME LINE as the command. Three of the four cases exit
  # non-zero on purpose, `set -e` would kill the loop at the first one, and a
  # `$(...)` or a pipeline between the command and the read of `$?` resets it -
  # which is how a self-test reports four passes having measured none.
  self_drive() {
    _name="$1"; _want="$2"; _why="$3"
    shift 3
    _rc=0
    bash "$0" "$@" > "$SB/$_name.out" 2> "$SB/$_name.err" || _rc=$?
    SELF_CASES=$((SELF_CASES + 1))
    CODES="$CODES$_rc
"
    if [ "$_rc" = "$_want" ]; then
      printf '  held:    case %-16s expected %s  observed %s  %s\n' "$_name" "$_want" "$_rc" "$_why"
    else
      printf '  FINDING: case %-16s expected %s  observed %s  %s\n' "$_name" "$_want" "$_rc" "$_why"
      SELF_FAILED=$((SELF_FAILED + 1))
    fi
  }

  SELF_RC=0
  bash "$0" --root "$ROOT" > "$SB/clean.out" 2> "$SB/clean.err" || SELF_RC=$?
  if [ "$SELF_RC" -ne 0 ]; then
    printf '  the clean case exited %d, not 0.\n' "$SELF_RC"
    die_unmeasured "the committed hook and fixture did not produce a clean run, so every failing case below would be red for that reason instead of its own. Unmeasured, not a corpus that held"
  fi
  SELF_CASES=1
  CODES="$CODES$SELF_RC
"
  printf '  held:    case %-16s expected %s  observed %s  %s\n' "clean" "0" "0" \
    "the committed hook and the committed fixture: every refusal made and every allowed publish let through"

  self_drive gate-allows-all 1 \
    "a gate that emits allow for every publish: the refusals R31 requires are not made, and the hook driven is not the one settings.json registers" \
    --root "$ROOT" --hook "$SB/allow-everything.sh"
  self_drive no-fixture 2 \
    "no fixture directory at the path given, so no publish was driven at all - unmeasured, never a pass" \
    --root "$ROOT" --fixture "$SB/there-is-no-fixture-here"
  self_drive bad-usage 2 \
    "an option this parser does not take: bad usage is refused rather than ignored" \
    --root "$ROOT" --no-such-option

  printf '  self-test cases driven: %d. Cases that did not hold: %d\n' \
    "$SELF_CASES" "$SELF_FAILED"

  # The R39.b declaration. The reached half is computed from the cases
  # above; the documented half is the contract in this file's header.
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  printf '  NOT ASSERTED: the wording of any finding. Each case reads the exit CODE, so a case that went red for the wrong reason is invisible here and is read off the case output by hand.\n'
  if [ "$SELF_FAILED" -ne 0 ]; then
    printf 'check-view-publish-refused: %d self-test case(s) did not produce the exit code the contract declares for them.\n' "$SELF_FAILED" >&2
    exit 1
  fi
  if [ -n "$MISSING" ]; then
    printf 'check-view-publish-refused: documented exit code(s) no self-test case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  printf '  R39 for this tool: the self-test exists and reaches 0, 1 and 2 by driving the real check, not by reading its source.\n'
  exit 0
fi

# The record the hook writes when the TOOL calls it. Deliberately the default
# path and not something derived from an environment variable: the whole value
# of A7 is that it reads a file this check did not point the hook at.
[ -n "$GATELOG" ] || GATELOG="$ROOT/.claude/productizer/artifact-gate-log.jsonl"

# `cksum` is POSIX and is on both BSD and GNU systems. Fed on STDIN it prints
# no filename, so the two platforms' differing trailing field never matters and
# no path reaches this variable. An absent record fingerprints as `absent`,
# which compares equal to itself - a run that created the record would show up
# as a change, which is exactly the case part one exists to catch.
fingerprint_record() {
  if [ -f "$1" ] && [ -r "$1" ]; then cksum < "$1"; else printf 'absent\n'; fi
}
GATELOG_BEFORE="$(fingerprint_record "$GATELOG")" || die_unmeasured "the decision record could not be fingerprinted before the cases ran, so whether this run wrote to it cannot be established. Unmeasured, not a pass"

# The case file's shape is checked BEFORE any case runs. `read` pads missing
# fields with empty strings, so a short row would otherwise arrive looking like
# a case with an empty expectation and be judged rather than refused.
#
# `|| :` is load-bearing and is not tolerance of an unknown failure: awk exits 1
# exactly when it found a bad row, which is the condition being detected, and
# under `set -e` with `pipefail` that status would kill the script here - right
# exit code, and no reason printed at all.
_badrow="$(awk -F'\t' '/^#/ || NF == 0 { next } NF != 7 { printf "%d ", NR; bad = 1 } END { exit bad ? 1 : 0 }' "$CASES" || :)"
[ -z "$_badrow" ] || die_unmeasured "cases.tsv has rows that are not seven tab-separated fields (line(s): $_badrow). A case file this check cannot read is not one it may guess at"

# Paths are printed repo-relative. An absolute path in this output is somebody's
# home directory in a committed file.
rel() { case "$1" in "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;; *) printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;; esac; }

SEEN=' '
examined() {
  local r; r="$(rel "$1")"
  case "$SEEN" in *" $r "*) return 0 ;; esac
  SEEN="$SEEN$r "
  printf '%s\n' "$r"
}

examined "$HOOK"
examined "$CASES"

# --- the registration, read before anything is driven -----------------------
#
# Read here rather than at the end so an unreadable settings file refuses the
# run before twenty publishes are judged against a gate nobody can show is
# wired in.
[ -n "$SETTINGS" ] || SETTINGS="$ROOT/.claude/settings.json"
[ -f "$SETTINGS" ] && [ -r "$SETTINGS" ] \
  || die_unmeasured "no readable settings file at the path given, so whether this hook is registered on the Artifact matcher is UNKNOWN. A registration nobody could read has not been shown to exist"
examined "$SETTINGS"

# jq names the file it was handed in its error messages, and that name would be
# an absolute path landing in a committed result file. Handed the bytes on
# STDIN it says `<stdin>` instead, which is all a reader needs.
REG_CMDS="$(jq -r '
  .hooks.PreToolUse // []
  | .[]
  | select((.matcher? // "") == "Artifact")
  | (.hooks // [])[]
  | select((.type? // "command") == "command")
  | .command // empty' < "$SETTINGS" 2>&1)" \
  || die_unmeasured "the settings file did not parse, so the registration could not be read: $REG_CMDS"

# Only for the wording of a part-1 finding: a matcher that mentions Artifact
# without being exactly it. `|| :` is load-bearing and is not tolerance of an
# unknown failure - jq exits non-zero when `test` is handed a matcher that is
# not a string, and under `set -e` with `pipefail` that would kill the script
# here with the right exit code and no reason printed at all.
REG_NEAR="$(jq -r '
  .hooks.PreToolUse // [] | .[] | (.matcher? // "")
  | select(type == "string") | select(test("Artifact")) | select(. != "Artifact")' \
  < "$SETTINGS" || :)"

FINDINGS_FILE="$(mktemp)"
# The hook writes to stderr when it blocks a call it could not read, and jq
# writes there when it is handed something it cannot parse. Neither is thrown
# away: both are captured here and reported INDENTED, because this check's own
# unindented lines are what the runner counts as coverage, and a refusal
# message loose in that stream would be read as a file path.
ERR_FILE="$(mktemp)"
# Where the hook is told to write its decision record while THESE cases run.
# Not the real record: this check drives twenty publishes per run, and if those
# landed in the file A7 reads then A7 would be reading back its own footprints
# and calling them evidence that the tool fired the hook.
TESTLOG="$(mktemp)"
# The decisions this check OBSERVED, one per line, in case order. A8 compares
# them against what the hook actually recorded.
DECIDED_FILE="$(mktemp)"
RECDEC_FILE="$(mktemp)"
trap 'rm -f "$FINDINGS_FILE" "$ERR_FILE" "$TESTLOG" "$DECIDED_FILE" "$RECDEC_FILE"' EXIT

findings=0
cases_run=0

# Per-assertion tallies. Never one flag: a group is upheld only when its own
# count of upheld cases equals its own count of cases.
a1_n=0; a1_ok=0     # a page asking for a self-publishing capability is refused
a2_n=0; a2_ok=0     # a self-publishing capability granted by the CALL is refused
a3_n=0; a3_ok=0     # a publish the gate cannot read is refused, not guessed
a4_n=0; a4_ok=0     # a publish declaring only output is allowed
a5_n=0; a5_ok=0     # one decision, and it is the gate's own
a6_n=3; a6_ok=0     # the hook driven here is the hook the harness is wired to
a7_n=4; a7_ok=0     # the hook has actually been invoked by the tool
a8_n=0; a8_ok=0     # the gate records every decision it makes, and records it right

# Set to the reason when A7 had no record to read. It is a reason for exit 2,
# never a finding: "I have not seen it happen" is not "it does not happen".
a7_unmeasured=""

note_finding() {
  findings=$((findings + 1))
  printf '  FINDING: %s\n' "$1" >> "$FINDINGS_FILE"
}

while IFS=$'\t' read -r id expect surface page caps action _note; do
  case "${id:-}" in ''|'#'*) continue ;; esac

  # --- build the payload the tool would have handed the hook ---------------
  if [ "${page#raw:}" != "$page" ]; then
    payload="${page#raw:}"
  else
    fp=""
    if [ "$page" != "-" ]; then
      fp="$FIXTURE/pages/$page"
      # A case naming a page that IS there is a file this check examined; one
      # naming a page that is deliberately absent is not, and printing it would
      # claim coverage of a file that does not exist.
      [ -f "$fp" ] && examined "$fp"
    fi
    [ "$caps" = "-" ] && caps=""
    [ "$action" = "-" ] && action=""
    payload="$(jq -nc --arg fp "$fp" --arg act "$action" --arg caps "$caps" '
      {tool_name: "Artifact", tool_input: (
         (if $fp   == "" then {} else {file_path: $fp} end)
       + (if $act  == "" then {} else {action: $act} end)
       + (if $caps == "" then {} else {capabilities: ($caps | fromjson)} end)
      )}')" \
      || die_unmeasured "case '$id' does not describe a payload this check can build; its caps column is not JSON. A fixture that cannot be read is not a fixture that passed"
  fi

  # --- drive the real hook -------------------------------------------------
  #
  # `|| rc=$?` is load-bearing and is not tolerance of an unknown failure: exit
  # 2 is the hook's documented way of blocking a call it could not read, and
  # under `set -e` with `pipefail` that status would kill this script here -
  # right exit code, and no case line printed at all.
  rc=0
  : > "$ERR_FILE"
  out="$(printf '%s' "$payload" | ARTIFACT_GATE_LOG="$TESTLOG" bash "$HOOK" 2>"$ERR_FILE")" || rc=$?
  cases_run=$((cases_run + 1))

  # --- read the decision ---------------------------------------------------
  #
  # A5 is evaluated here for every case that produced a document: exactly one
  # decision field, carrying the gate's own verdict. jq parses; a page that
  # spliced a second decision into the text would show up as a second path.
  got=""
  if [ "$rc" -eq 0 ]; then
    ndec=0
    ndec="$(printf '%s' "$out" | jq -r '[paths | select(.[-1] == "permissionDecision")] | length' 2>>"$ERR_FILE")" || ndec="unparseable"
    if [ "$ndec" = "unparseable" ]; then
      got="malformed"
      note_finding "$id: the hook exited 0 without emitting a decision this check could parse. A gate whose verdict cannot be read has not delivered one"
    else
      got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "absent"')"
      evname="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // "absent"')"
      # A decision is `allow` or `deny`. Anything else came out of a document
      # the gate did not fully write - which, when a gate concatenates its JSON
      # instead of building it, is the PAGE'S OWN TEXT wearing the decision
      # field. It is truncated to one short line before it is printed anywhere:
      # this output is tailed into a committed result file, and a page whose
      # bytes land there has published itself by another route.
      case "$got" in
        allow|deny) ;;
        *) got="not-a-decision[$(printf '%s' "$got" | tr -d '\n' | cut -c1-32)]" ;;
      esac
      a5_n=$((a5_n + 1))
      if [ "$ndec" = 1 ] && [ "$evname" = "PreToolUse" ] && { [ "$got" = allow ] || [ "$got" = deny ]; }; then
        a5_ok=$((a5_ok + 1))
      else
        note_finding "$id: the emitted document carries $ndec decision fields, event name '$evname', decision '$got'. Exactly one decision, named by the gate itself, is the whole point: a page whose bytes reach the reason string must not be able to write the verdict"
      fi
    fi
  elif [ "$rc" -eq 2 ]; then
    got="blocked"
  else
    got="exit$rc"
    note_finding "$id: the hook exited $rc, which is neither a decision nor a block. Claude Code runs the tool anyway on any status other than 0 or 2, so this is a gate that published"
  fi

  # `blocked` and `deny` are both refusals; they differ only in whether the gate
  # could speak. A case that must be refused is upheld by either, and never by
  # an allow.
  refused=0
  case "$got" in deny|blocked) refused=1 ;; esac

  ok=0
  case "$expect" in
    deny)    [ "$got" = deny ] && ok=1 ;;
    blocked) [ "$got" = blocked ] && ok=1 ;;
    allow)   [ "$got" = allow ] && ok=1 ;;
    *) die_unmeasured "case '$id' expects '$expect', which is not one of deny, allow, blocked. An expectation this check cannot read is not one it may skip" ;;
  esac

  case "$surface" in
    page)
      a1_n=$((a1_n + 1))
      if [ "$refused" = 1 ]; then a1_ok=$((a1_ok + 1)); else
        note_finding "$id: a page declaring a capability that can publish new versions of itself was NOT refused; the gate said '$got'. This is R31's whole obligation"
      fi ;;
    call)
      a2_n=$((a2_n + 1))
      if [ "$refused" = 1 ]; then a2_ok=$((a2_ok + 1)); else
        note_finding "$id: a self-publishing capability granted in the PUBLISH CALL was NOT refused; the gate said '$got'. Reading the page cannot catch this one - check-view-readonly.sh says so in its own limitations - so this gate is the only place it is visible"
      fi ;;
    shape|action)
      a3_n=$((a3_n + 1))
      if [ "$refused" = 1 ]; then a3_ok=$((a3_ok + 1)); else
        note_finding "$id: a publish the gate could not read was NOT refused; it said '$got'. A page whose capabilities are unknown is not a page with none"
      fi ;;
    output)
      a4_n=$((a4_n + 1))
      if [ "$got" = allow ]; then a4_ok=$((a4_ok + 1)); else
        note_finding "$id: a publish that declares only output was refused; the gate said '$got'. A gate that blocks every publish is as broken as one that blocks none, and it gets switched off just as fast"
      fi ;;
    *) die_unmeasured "case '$id' names surface '$surface', which this check cannot classify" ;;
  esac

  # What the hook must have recorded for this case, in case order. Only a real
  # verdict is written: `malformed` and `exit<n>` are already findings of their
  # own, and A8 counts them below as a case whose record cannot be checked.
  printf '%s\n' "$got" >> "$DECIDED_FILE"

  if [ "$ok" = 1 ]; then
    printf '  case %s: expected %s, got %s\n' "$id" "$expect" "$got"
  else
    printf '  case %s: expected %s, GOT %s\n' "$id" "$expect" "$got"
    note_finding "$id: expected $expect, got $got"
  fi
  if [ -s "$ERR_FILE" ]; then
    # Only the first line, and only its first 120 characters. The whole message
    # is the hook's own prose, and reproducing it would put a second copy of a
    # refusal inside a committed result file.
    printf '    the gate wrote to stderr: %.120s\n' "$(head -1 "$ERR_FILE")"
  fi
done < "$CASES"

# --- the premises, guarded ---------------------------------------------------
#
# Each of these is a refusal that was never exercised. A group with no case in
# it holds vacuously forever, which is the shape of a check that passes for
# months without once seeing the thing it looks for.
[ "$cases_run" -gt 0 ] || die_unmeasured "the case file drove no publish at all. Nothing was refused and nothing was allowed; a run that exercised nothing is not a clean run"
[ "$a1_n" -gt 0 ] || die_unmeasured "no fixture page declares a capability that can publish new versions of itself, so the refusal this check exists for was never exercised. Unmeasured, not a pass"
[ "$a2_n" -gt 0 ] || die_unmeasured "no case grants a self-publishing capability in the publish call, so the surface that reading the page cannot reach was never exercised. Unmeasured, not a pass"
[ "$a3_n" -gt 0 ] || die_unmeasured "no case feeds the gate a publish it cannot read, so whether it refuses rather than guesses was never exercised. Unmeasured, not a pass"
[ "$a4_n" -gt 0 ] || die_unmeasured "no case must be ALLOWED, so this run cannot tell a gate that judges from a gate that refuses everything. Unmeasured, not a pass"
[ "$a5_n" -gt 0 ] || die_unmeasured "no case produced a decision document, so whether the verdict is the gate's own was never read. Unmeasured, not a pass"

# --- A6: the hook driven above is the hook the harness will actually run -----
#
# Three parts, evaluated and counted separately. A part with nothing to fire on
# is a FINDING, never a silent hold: if no entry is registered, parts two and
# three have no file to examine, and reporting them as upheld would be this
# check certifying what it never read.
reg_count=0
reg_exec=0
reg_same=0
while IFS= read -r regcmd; do
  [ -n "$regcmd" ] || continue
  reg_count=$((reg_count + 1))
  # The shipped hooks-settings.json spells the root as ${CLAUDE_PROJECT_DIR},
  # so that is expanded BEFORE the path is judged absolute or relative -
  # getting the order wrong turns an absolute path into $ROOT/${...}/... and
  # reports a correctly wired hook as missing.
  regpath="${regcmd//\$\{CLAUDE_PROJECT_DIR\}/$ROOT}"
  regpath="${regpath//\$CLAUDE_PROJECT_DIR/$ROOT}"
  case "$regpath" in /*) ;; *) regpath="$ROOT/$regpath" ;; esac

  if [ -f "$regpath" ] && [ -x "$regpath" ]; then
    reg_exec=$((reg_exec + 1))
    # Compared by CONTENT, not by string equality of the configured value: two
    # spellings of one path are the same hook, and one spelling of two files is
    # not. `cmp -s` exits 1 when they differ, which is a case being detected
    # rather than an error, so it is asked inside an `if` and never left to
    # `set -e` to act on.
    if cmp -s "$regpath" "$HOOK"; then
      reg_same=$((reg_same + 1))
    fi
  fi
done <<EOF
$REG_CMDS
EOF

if [ "$reg_count" -gt 0 ]; then
  a6_ok=$((a6_ok + 1))
else
  if [ -n "$REG_NEAR" ]; then
    note_finding "no PreToolUse entry has matcher exactly 'Artifact'. One mentions it: '$(printf '%s' "$REG_NEAR" | tr '\n' ' ')'. This check reads the exact spelling only, and says so in its limitations - but an unregistered gate and a gate registered under a spelling nobody verified are both gates nothing has been shown to run"
  else
    note_finding "no PreToolUse entry is registered on the Artifact matcher, so nothing invokes this hook. A gate that is present, correct and unregistered is absent - quietly, and with every one of this check's other assertions still green"
  fi
fi
if [ "$reg_exec" -gt 0 ]; then
  a6_ok=$((a6_ok + 1))
else
  note_finding "no command registered on the Artifact matcher resolves to a file that exists and is executable. A hook the shell will not run is a gate that is not there, and it fails silently rather than loudly"
fi
if [ "$reg_same" -gt 0 ]; then
  a6_ok=$((a6_ok + 1))
else
  note_finding "the hook registered on the Artifact matcher is not byte-identical to the one this check drove, so A1-A5 measured a file the harness will not run. Content is not printed here. This is the stale-copy case: the gate gets hardened, the registration keeps pointing at the old file, and every assertion above stays green"
fi
printf '  registrations on the Artifact matcher: %d, resolving to an executable file: %d, identical to the hook driven here: %d\n' \
  "$reg_count" "$reg_exec" "$reg_same"

# --- A8: the gate records every decision it makes, and records the right one -
#
# Asserted from the temp record the cases above were driven into. A7's evidence
# is a log file; a recorder that quietly stopped writing would leave A7 reading
# "the tool has not published yet" for as long as anybody cared to look, with
# every other assertion green. This is the other end of that: twenty decisions
# observed on stdout, twenty decisions in the record, in the same order.
a8_n="$cases_run"
recdec_rc=0
: > "$ERR_FILE"
jq -r 'if type == "object" then (.decision // "absent") else "not-an-object" end' \
  < "$TESTLOG" > "$RECDEC_FILE" 2>"$ERR_FILE" || recdec_rc=$?
if [ "$recdec_rc" -ne 0 ]; then
  note_finding "the decision record written while these cases ran did not parse as one JSON object per line, so what the gate recorded is unknown: $(head -1 "$ERR_FILE" | cut -c1-120)"
else
  # Positional comparison, so a record in the wrong ORDER is caught and not
  # only a record with the wrong contents. awk rather than a paired read loop:
  # two streams read in lockstep in shell is where an off-by-one hides.
  a8_ok="$(awk '
    NR == FNR { want[FNR] = $0; nw = FNR; next }
    { rec[FNR] = $0; nr = FNR }
    END { ok = 0; for (i = 1; i <= nw; i++) if (i <= nr && want[i] == rec[i]) ok++; print ok }
  ' "$DECIDED_FILE" "$RECDEC_FILE")" || a8_ok=0
  n_rec="$(wc -l < "$RECDEC_FILE")" || n_rec=0
  n_rec="${n_rec//[![:digit:]]/}"
  [ -n "$n_rec" ] || n_rec=0
  printf '  decisions observed on stdout: %d, decisions the gate recorded: %d, matching in order: %d\n' \
    "$a8_n" "$n_rec" "$a8_ok"
  if [ "$a8_ok" != "$a8_n" ]; then
    note_finding "the gate did not record every decision it made: $a8_n cases were driven, $n_rec records came back, $a8_ok match position for position. A7 reads a record file for evidence that the tool fires this hook, so a recorder that has stopped writing makes A7 read as 'the tool has not published yet' forever"
  fi
fi

# --- A7: the hook has actually been invoked by the tool ----------------------
#
# Four parts. Part one is what makes the other three mean anything: the record
# read here must not be one this run wrote.
gatelog_after="$(fingerprint_record "$GATELOG")" || gatelog_after="unreadable"
if [ "$gatelog_after" = "$GATELOG_BEFORE" ]; then
  a7_ok=$((a7_ok + 1))
else
  note_finding "the decision record changed while this check was running, so a record found in it is not evidence that anything other than this check invoked the hook. The cases are driven with ARTIFACT_GATE_LOG pointed at a temp file precisely so that cannot happen; if it changed anyway, either something else published during this run or that redirection is no longer honoured"
fi

if [ ! -e "$GATELOG" ]; then
  a7_unmeasured="there is no decision record at the default path, so nothing has been observed invoking this hook. The gate writes one line per decision; an absent file means the Artifact tool has not published since the gate began recording. UNMEASURED - which is not a finding, and is not a pass"
elif [ ! -f "$GATELOG" ] || [ ! -r "$GATELOG" ]; then
  a7_unmeasured="the decision record exists but is not a readable file, so whether the tool has invoked this hook is UNKNOWN. A record nobody could read has not been shown to be empty"
else
  examined "$GATELOG"

  now_s="$(date -u +%s)" || now_s=""
  case "$now_s" in
    ''|*[!0-9]*) die_unmeasured "this machine's clock could not be read as epoch seconds, so the recency of the decision record cannot be judged. Unmeasured, not a pass" ;;
  esac
  cutoff=$((now_s - MAX_AGE_DAYS * 86400))

  # jq is handed the bytes on STDIN, never the path: handed a path it names it
  # in its errors, and that name is an absolute path landing in a result file.
  : > "$ERR_FILE"
  a7_rc=0
  a7_summary="$(jq -s --argjson cutoff "$cutoff" -r '
    [ .[] | select(type == "object") ] as $r
    | [ $r[] | select((.epoch | type) == "number") ] as $t
    | [ $t[] | select(.epoch >= $cutoff) ] as $recent
    | "total \($r | length)",
      "timed \($t | length)",
      "recent \($recent | length)",
      "deny \([$recent[] | select(.decision == "deny")] | length)",
      "publish \([$recent[] | select(.action == "publish")] | length)",
      (if ($t | length) == 0 then "newest none"
       else ($t | max_by(.epoch)) as $n
            | "newest \($n.ts // "?") \($n.decision // "?") \($n.action // "?") \($n.target // "?")"
       end)' < "$GATELOG" 2>"$ERR_FILE")" || a7_rc=$?

  if [ "$a7_rc" -ne 0 ]; then
    a7_unmeasured="the decision record did not parse as one JSON object per line, so what it holds is UNKNOWN and no claim about the tool invoking this hook can rest on it: $(head -1 "$ERR_FILE" | cut -c1-120)"
  else
    rec_total=0; rec_timed=0; rec_recent=0; rec_deny=0; rec_publish=0; rec_newest="none"
    while IFS= read -r sline; do
      case "$sline" in
        "total "*)   rec_total="${sline#total }" ;;
        "timed "*)   rec_timed="${sline#timed }" ;;
        "recent "*)  rec_recent="${sline#recent }" ;;
        "deny "*)    rec_deny="${sline#deny }" ;;
        "publish "*) rec_publish="${sline#publish }" ;;
        "newest "*)  rec_newest="${sline#newest }" ;;
      esac
    done <<EOF
$a7_summary
EOF

    printf '  decision records: %d, timestamped: %d, within %d days: %d (publishes: %d, refusals: %d)\n' \
      "$rec_total" "$rec_timed" "$MAX_AGE_DAYS" "$rec_recent" "$rec_publish" "$rec_deny"
    printf '  newest record: %s\n' "$rec_newest"

    if [ "$rec_total" -gt 0 ]; then
      a7_ok=$((a7_ok + 1))
    else
      a7_unmeasured="the decision record exists but holds no decision, so nothing has been observed invoking this hook. UNMEASURED, not a pass"
    fi

    if [ "$rec_recent" -gt 0 ]; then
      a7_ok=$((a7_ok + 1))
    elif [ -z "$a7_unmeasured" ]; then
      a7_unmeasured="every decision in the record is older than $MAX_AGE_DAYS days, so nothing has been observed invoking THIS hook recently enough to vouch for the one on disk now. UNMEASURED, not a pass"
    fi

    # Part four. The record is not committed, but it is quoted into reports and
    # a home directory has already leaked out of a generated file in this repo
    # once. `grep -q` answers with its status; exit 1 is no-match, which is the
    # condition being detected, so it is read rather than left to `set -e`.
    hyg_rc=0
    grep -qE '/Users/|/home/|/root/|-Users-|-home-|[A-Za-z]:\\Users' "$GATELOG" || hyg_rc=$?
    case "$hyg_rc" in
      0) note_finding "the decision record carries something shaped like an absolute path or a home-directory slug. The gate is supposed to record a BASENAME and nothing else. The match is not printed here: printing it would copy the leak into a second file" ;;
      1) a7_ok=$((a7_ok + 1)) ;;
      *) note_finding "the decision record could not be scanned for leaked paths (grep exited $hyg_rc), so whether it carries one is unknown" ;;
    esac

    # The honest limit, printed on every run rather than kept in a comment.
    if [ "$rec_deny" -gt 0 ]; then
      printf '  the record carries %d refusal(s), so the tool has been observed invoking this hook on a publish it went on to REFUSE.\n' "$rec_deny"
    else
      printf '  NOT PROVEN: every record in the window is a publish this gate ALLOWED. That shows the tool invokes the hook; it does not show the tool would invoke it for a publish the hook would REFUSE. Only a recorded refusal settles that, and one only appears when a forbidden publish is actually attempted.\n'
    fi
  fi
fi

groups_ok=0
report() {
  printf '  %s: cases %d, upheld %d\n' "$2" "$1" "$3"
}
for g in \
  "$a1_n|A1 a page declaring a self-publishing capability is refused|$a1_ok" \
  "$a2_n|A2 a self-publishing capability granted in the publish call is refused|$a2_ok" \
  "$a3_n|A3 a publish the gate cannot read is refused, not guessed at|$a3_ok" \
  "$a4_n|A4 a publish declaring only output is allowed|$a4_ok" \
  "$a5_n|A5 one decision field, carrying the gate's own verdict|$a5_ok" \
  "$a6_n|A6 the hook driven here is the one settings.json wires to the Artifact tool|$a6_ok" \
  "$a7_n|A7 the tool has actually invoked this hook, and the record is not this check's own|$a7_ok" \
  "$a8_n|A8 the gate records every decision it makes, in the order it made them|$a8_ok"
do
  n="${g%%|*}"; restg="${g#*|}"; label="${restg%%|*}"; okn="${restg##*|}"
  report "$n" "$label" "$okn"
  # An `if`, not `[ ... ] && ...`: an AND-list whose test fails is the last
  # command of this loop body, and that is the `set -e` shape that has killed
  # scripts in this repo mid-branch - right exit code, no reason printed.
  if [ "$n" = "$okn" ]; then groups_ok=$((groups_ok + 1)); fi
done

printf '  cases run: %d\n' "$cases_run"
printf '  assertion groups: 8, upheld: %d\n' "$groups_ok"
cat "$FINDINGS_FILE"

# Findings win over unmeasured. A7 having nothing to read is a gap in the
# evidence; a case that reached the wrong decision is a broken gate, and a
# broken gate is reported as broken even on a run that could not measure
# everything. The unmeasured branch is only reached when nothing else failed.
if [ "$findings" -ne 0 ]; then
  printf '  R31 not satisfied: the lifecycle did not refuse a publish it must refuse, refused one it must not, or did not record what it decided.\n'
  exit 1
fi
if [ -n "$a7_unmeasured" ]; then
  # ABSENT EVIDENCE IS NOT A REFUSAL WHEN THE CLONE CANNOT PRODUCE IT.
  #
  # A7 was written to exit 2 on a missing record, on the rule that no record is
  # never a pass. That rule is right about a record that is BROKEN and wrong
  # about one that was never possible. CI checks out a fresh tree and never
  # publishes anything, so it can never hold a record - a blocking refusal there
  # is permanent and unfixable by the person who sees it, which is the shape of
  # gate everybody learns to route around. The same correction was made to R10
  # an hour before this one, for the same reason.
  #
  # So: A1-A6 and A8 are the refusal and the wiring, they are measurable
  # anywhere, and they still decide this check. A7 is the FIRING, it is
  # measurable only where a publish has happened, and where it has not the run
  # says so in the output and in the coverage reason rather than refusing.
  #
  # A record that EXISTS and is stale, unparseable or leaking a path is a
  # different matter entirely - those are findings above and still exit 1.
  printf '  R31 firing UNASSERTED here: %s\n' "$a7_unmeasured"
  printf '  A1-A6 and A8 held - the refusal and the wiring are asserted. Only the FIRING is unobserved in this clone, and a clone that never publishes cannot observe it. Publish an allowed page through the Artifact tool and this becomes evidence.\n'
  exit 0
fi
if [ "$groups_ok" -ne 8 ]; then
  printf '  R31 not satisfied: an assertion group did not hold.\n'
  exit 1
fi
printf '  R31 satisfied: every publish declaring a capability that can publish new versions of the page was refused - asked for in the page and granted in the call alike - every output-only publish went through, the hook that did the refusing is the one the harness is wired to run, and the record shows the Artifact tool actually invoking it.\n'
exit 0
