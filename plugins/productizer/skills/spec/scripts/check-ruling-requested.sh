#!/usr/bin/env bash
# check-ruling-requested.sh [--version] [--help] [--root DIR] [--selftest]
#
# Asserts R34: IF AN INTENT CONTRADICTS AN ACTIVE REQUIREMENT, THEN THE
# LIFECYCLE SHALL ASK WHICH WINS. R34 is the ASK half of the old R23, split out
# under B31; R33 carries the stop and is asserted by the solver corpus.
#
# The stop is already asserted elsewhere. Nothing asserted the ask, and that is
# backlog item B11: on a contradiction the lifecycle correctly stops, nobody is
# prompted for the decision, and work stops and stays stopped. A stop that asks
# nobody is indistinguishable from a stop that was never resolved.
#
# So this check does not re-observe the stop. It observes the artefact of the
# ask: a ruling file a human can actually act on, reachable from the spec.
#
# WHAT IT ASSERTS
#
#   1. EVERY OPEN CONCERN CITES A RULING THAT EXISTS. For each row in the
#      spec's *Areas of concern* whose status is `open: D<n>`, the file
#      `rulings/D<n>-*.md` must be there. A concern raised with no ruling file
#      is B11 exactly: halted, nothing written, nobody asked. A row whose
#      status is open and cites no ruling at all is the same failure one step
#      earlier - a question with nowhere to be answered.
#
#   2. EVERY PENDING RULING HAS ITS CONCERN ROW. For each `D<n>` whose header
#      status is `pending`, some `C<m>` row must cite it. Otherwise the ask is
#      invisible to everyone who reads the spec rather than the directory, and
#      the spec is where intake looks.
#
#   3. A PENDING RULING IS A REAL ASK, NOT A STUB. In a file whose status is
#      `pending`: `## The conflict`, `## The question` and both columns of the
#      `## What each side costs` table must be present and filled. Unfilled
#      means empty, or still carrying an angle-bracket placeholder copied out
#      of templates/ruling.md. A ruling still wearing the template is a file,
#      not a question.
#
#   4. THE HEADER BLOCK IS MACHINE-READABLE. `Status:` carries exactly one of
#      `pending`, `ruled`, `lapsed`, `superseded` and nothing else on the
#      line; every header field is present; an unset field is an em dash and
#      never blank. A blank value and a missing line are indistinguishable to
#      anything counting these files, and a counter that cannot tell them
#      apart reports a pending ruling as ruled - which is the count reading
#      clean while a contradiction is live.
#
#   5. EVERY INTENT RECORDED AS `contradict` HAS A RULING NAMING IT. This is
#      the one that reaches the stop nothing else here can see.
#
#      Assertions 1 to 4 all start from the spec or from the rulings directory,
#      so a contradiction stopped IN CONVERSATION - no concern row, no ruling
#      file, nothing written anywhere - presents them with an empty repository
#      and they call it clean. That is B11, and splitting R23 into R33 and R34
#      did not touch it.
#
#      The evidence such a stop DOES leave is the classification record.
#      `record-classification.sh` writes one per intent, naming exactly one of
#      extend, refine, duplicate, contradict, and it writes it BEFORE anything
#      else happens. `references/rulings.md` then fixes the order that follows
#      a `contradict`: allocate the ids, write the ruling file, add the concern
#      row, commit, and only THEN ask - "Writing the file first is the whole
#      mechanism." So a record saying `contradict` with no ruling file naming
#      the same intent is exactly a stop that ended in a session.
#
#      The join is the `Intent:` field, present in both files, reduced to one
#      spelling by the same rule `classification-record.py --slug` uses. Every
#      ruling counts, whatever its status: a `ruled` ruling asked its question
#      just as much as a pending one did.
#
#      WHAT IT STILL CANNOT SEE, said plainly rather than discovered later: an
#      intent that was never classified at all leaves no record either, and
#      nothing in a repository lists the intents that arrived. Closing THAT is
#      not a check's job - it needs Stage 1 to record the classification before
#      it asks, which `record-classification.sh` already supports and nothing
#      currently forces.
#
# THE SELF-ASSERTION, AND WHY IT IS NOT OPTIONAL
#
# In a repository with no rulings and no contradiction on record, all five
# sweeps above are over empty sets and the run exits clean having asserted
# nothing. A check that sweeps an empty set and prints PASS has already shipped
# here and sat green for weeks. So before it looks at the real repository, this
# script replays a committed fixture -
# `fixtures/ruling-scope/r34-conversational-stop/` - into a temporary root and
# runs ITSELF against it, twice:
#
#   1. `stopped/`: an intent classified `contradict`, with no concern row and
#      no rulings directory at all. Must be REFUSED.
#   2. `asked/`: the same contradiction written up as rulings.md requires.
#      Must be CLEAN - otherwise assertion 1 would also pass for a check that
#      refuses every contradict record it sees, which would make raising a
#      ruling properly indistinguishable from not raising one.
#
# Both must hold; a run that could not set the fixture up is exit 2, never a
# pass. Everything is copied into a temporary directory; nothing is written
# into the repository being checked. The nested run is marked by an environment
# variable so it does not recurse.
#
# WHAT IT DELIBERATELY NEVER LOOKS AT
#
# Everything from `## Ruling` downward. Those sections are the human's, and a
# pending ruling is SUPPOSED to still carry their template guidance. Flagging
# them would demand that the agent pre-write the decision, which is the exact
# harm the whole design exists to prevent. The three sections above are named
# one by one rather than scanned as "everything before Ruling", so a file that
# is missing its `## Ruling` heading still cannot drag Reasoning, Not decided
# or Consequences into scope.
#
# NO FILE MEANS NO COUNT, NOT ZERO
#
#   no rulings/ directory        this repo has never raised a contradiction.
#                                Clean IF no concern row is open citing one -
#                                and a finding for every row that is, because
#                                that is precisely the halted-and-silent case.
#   a directory it cannot read   UNKNOWN. Exit 2. Never folded into "none
#                                pending": a directory nobody could open is
#                                where the unasked question hides.
#
# An unmatched glob reaches the command as a literal path in bash, so the two
# are distinguished by an explicit directory test, never by trusting a count.
#
# `grep -x -F`-equivalent matching, never a substring. `Status: pending`
# appears in the template's own prose and in any ruling that discusses being
# pending; an unanchored match reports questions that do not exist. The status
# is read from the header block only, so the string in a body paragraph is
# not a status.
#
# REPORTED BY LOCATION, NEVER BY QUOTING THE MATCH. File, line, and the class
# of problem. A checker in this repo that printed the offending line put the
# leaked content into a committed result file, so finding a leak created one.
# A ruling also quotes an incoming intent, which is text a stranger can write.
#
# Paths are printed RELATIVE to the root for the same reason: an absolute path
# names somebody's home directory, and this output is committed.
#
# ONE LINE PER FILE EXAMINED, on stdout, unindented - the spec, then every
# ruling file read. The runner asserts that a check examined what it declared
# and calls a clean exit with nothing examined HOLLOW, which is a failure. A
# check that looks at nothing must not look like a pass.
#
# KNOWN LIMITATIONS, written down rather than discovered later:
#   - A literal angle-bracket pair in quoted requirement text inside one of the
#     three scanned sections reads as a template placeholder. Backtick it -
#     inline code spans are stripped before the scan, which is how the repo
#     already writes `D<n>`.
#   - The cost table's second pipe line is assumed to be the column separator.
#     A table written without one loses its first data row from the scan.
#   - Running as a user who can read anything (root) defeats the unreadable-
#     directory test, as it defeats every such test.
#   - Assertion 5 sees only intents that were CLASSIFIED. A contradiction that
#     arrived, was argued and was dropped without a classification record
#     leaves nothing anywhere, and no check can find it. The upstream fix is
#     the writer's, named above.
#   - The classification store is read at its default path. A repository that
#     moved it with `record-classification.sh --store` gets an absent-store
#     note rather than a search, and the note says the count is missing rather
#     than zero.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  clean, and both self-assertions upheld
#   1  findings
#   2  could not run - no work tree, no spec, a rulings or classifications
#      directory or file that could not be read, or a fixture that could not be
#      set up. Never confused with 0.
#
# Under --selftest (--self-test is accepted too) the same three mean: every
# case produced the exit code it declares and said what it was supposed to say
# (0), at least one did not (1), and the corpus could not be driven at all (2).
# The self-assertion above and that corpus answer different questions and are
# not interchangeable; the block that implements it says which is which.
set -euo pipefail

# Byte-identical behaviour across machines and locales: character ranges,
# case folding and sort order all follow the locale otherwise, and this
# script's comparisons are all made out of them. `record-classification.sh`
# sets this for the same reason.
export LC_ALL=C

VERSION="check-ruling-requested 1.1"
ROOT=""
MODE="measure"

usage() {
  printf 'usage: check-ruling-requested.sh [--version] [--help] [--root DIR] [--selftest]\n'
  printf '  --root DIR  the repo work tree to examine. Defaults to the git\n'
  printf '              top level, never to the working directory.\n'
  printf '  --selftest  drive the built-in corpus instead of a repository.\n'
}

die_unmeasured() { printf 'check-ruling-requested: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)
      [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    -*) printf 'check-ruling-requested: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'check-ruling-requested: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# --selftest. R39: one case per exit code this tool can return, each built in
# a sandbox so nothing here reads or writes a real repository.
#
# THIS IS NOT THE SELF-ASSERTION BELOW, AND THE TWO ARE NOT INTERCHANGEABLE.
# The self-assertion runs on EVERY ordinary invocation and answers one
# question: in a repository where all four sweeps are over empty sets, did
# this check assert anything at all. It drives two cases. The corpus here
# answers R39's question instead - does every exit code this tool can return
# have a case that reaches it - and it drives the argument parser, the premise
# guards and the refusal paths, none of which the self-assertion touches.
#
# EVERY CASE ASSERTS ITS OWN SENTENCE, NOT ONLY ITS EXIT CODE. Nine different
# things exit 1 here and five exit 2, so a corpus reading exit codes alone
# could not tell a stub ruling from a missing header field, and a change that
# turned one into the other would stay green.
#
# THE NEGATIVE CONTROL IS MANDATORY. `contradict-answered` records the same
# contradiction as `contradict-silent` and writes the ruling and the concern
# row that answer it. Without it, a check that refused every contradict record
# it saw would pass every red case here and make raising a ruling properly
# indistinguishable from not raising one.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  [ -f "$SELF" ] ||
    die_unmeasured "cannot re-invoke this script for the self-test, so no case was driven"

  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-ruling-requested-selftest.XXXXXX")" ||
    die_unmeasured "could not create a sandbox, so no case was driven"
  SB="$(cd "$SB" && pwd -P)"
  # chmod back before removing: one case makes a directory unlistable, and a
  # sandbox that cannot be cleaned up is litter in somebody's temp directory.
  trap 'chmod -R u+rwx "$SB" || :; rm -rf "$SB"' EXIT HUP INT TERM

  mk_case() { mkdir -p "$SB/$1/.claude/productizer"; }
  P_DIR() { printf '%s/.claude/productizer' "$SB/$1"; }

  plain_spec() {
    cat > "$(P_DIR "$1")/spec.md" <<'SPEC'
# Sandbox spec

## Requirements

- **R1** — If an intent contradicts an active requirement, then the lifecycle shall ask which wins.
SPEC
  }

  spec_with_concern() {
    # $1 case, $2 the Status cell exactly as it should read
    plain_spec "$1"
    cat >> "$(P_DIR "$1")/spec.md" <<SPEC

## Areas of concern

| # | Concern | Requirements | Policy / owner | Raised by | Status |
|---|---|---|---|---|---|
| C1 | A sandbox concern | R1 | — | — | $2 |
SPEC
  }

  # A pending ruling with nothing missing: every header field present and
  # non-blank, all three scanned sections filled, no template placeholder.
  good_ruling() {
    # $1 case, $2 file name, $3 the Intent value
    mkdir -p "$(P_DIR "$1")/rulings"
    cat > "$(P_DIR "$1")/rulings/$2" <<RULING
# D1 — whether the sandbox merges the uncontested part

Status: pending
Raised: 2026-09-01
Concern: C1
Intent: $3
Ruled: —
Ruled by: —
Supersedes: —
Superseded by: —

## The conflict

R1 forbids the whole delta and the incoming sentence merges part of it, so the
two cannot both hold for a delta with one contested requirement in it.

## The question

Does a delta with one contested requirement merge in part, or not at all?

## What each side costs

| If R1 governs | If the incoming behaviour governs |
|---|---|
| Nine uncontested requirements wait behind one question nobody has answered | The contested requirement is ruled on against a spec that has already moved |

## Ruling

<Which side governs, stated as the behaviour that now holds.>
RULING
  }

  class_record() {
    # $1 case, $2 intent, $3 classification
    mkdir -p "$(P_DIR "$1")/classifications"
    cat > "$(P_DIR "$1")/classifications/sandbox-1.md" <<REC
# Classification — $2

Intent: $2
Classification: $3
Recorded: 2026-09-01
Spec path: .claude/productizer/spec.md
Spec commit: 0000000000000000000000000000000000000000
Spec hash: sha256:0000000000000000000000000000000000000000000000000000000000000000
In scope count: 1

## Requirement ids in scope

R1
REC
  }

  FAILED=0
  DRIVEN=0
  SKIPPED=""
  # R39.b: the reached half of the declaration below is ACCUMULATED here, one
  # entry per case as it ran. A literal list would satisfy the reader and prove
  # nothing.
  CODES=""

  drive() {
    # $1 case name, $2 expected exit, $3 expected sentence, $4.. argv override
    local case_name="$1" want="$2" marker="$3"
    shift 3
    local rc=0
    if [ "$#" -eq 0 ]; then set -- --root "$SB/$case_name"; fi
    bash "$SELF" "$@" > "$SB/$case_name.out" 2> "$SB/$case_name.err" || rc=$?
    DRIVEN=$((DRIVEN + 1))
    CODES="$CODES$rc
"
    local why=""
    [ "$rc" -eq "$want" ] || why="exit $rc, expected $want"
    # Both files handed to grep directly, never piped into it: under
    # `set -o pipefail` a `cat a b | grep -q` reports 141 whenever grep matches
    # early enough to SIGPIPE the cat, and `if !` reads that as no match.
    if ! grep -q -- "$marker" "$SB/$case_name.out" "$SB/$case_name.err"; then
      [ -n "$why" ] && why="$why; "
      why="${why}its output does not say what it was supposed to say"
    fi
    if [ -z "$why" ]; then
      printf '  held: case %-24s exit %d, and said so - %s\n' "$case_name" "$rc" "$marker"
      return 0
    fi
    printf '  FINDING: case %-24s %s - expected: %s\n' "$case_name" "$why" "$marker"
    FAILED=$((FAILED + 1))
    return 0
  }

  # --- clean: nothing open, nothing pending, nothing classified ------------
  mk_case clean;              plain_spec clean

  # --- the negative control: the same contradiction, written down ----------
  mk_case contradict-answered
  spec_with_concern contradict-answered 'open: D1'
  good_ruling contradict-answered D1-sandbox.md sandbox-9
  class_record contradict-answered sandbox-9 contradict

  # --- exit 1 --------------------------------------------------------------
  mk_case open-no-ruling;     spec_with_concern open-no-ruling 'open: D1'
  mk_case open-no-cite;       spec_with_concern open-no-cite 'open'
  mk_case pending-uncited;    plain_spec pending-uncited
  good_ruling pending-uncited D1-sandbox.md sandbox-9

  mk_case ruling-stub;        spec_with_concern ruling-stub 'open: D1'
  good_ruling ruling-stub D1-sandbox.md sandbox-9
  # Delete the question and leave everything else intact.
  awk '/^## The question$/ { skip = 1; next } /^## What each side costs$/ { skip = 0 } skip != 1' \
    "$(P_DIR ruling-stub)/rulings/D1-sandbox.md" > "$SB/ruling-stub.tmp"
  mv "$SB/ruling-stub.tmp" "$(P_DIR ruling-stub)/rulings/D1-sandbox.md"

  mk_case ruling-placeholder; spec_with_concern ruling-placeholder 'open: D1'
  good_ruling ruling-placeholder D1-sandbox.md sandbox-9
  sed 's/^Does a delta with one contested requirement merge in part, or not at all?$/<State the question here.>/' \
    "$(P_DIR ruling-placeholder)/rulings/D1-sandbox.md" > "$SB/rp.tmp"
  mv "$SB/rp.tmp" "$(P_DIR ruling-placeholder)/rulings/D1-sandbox.md"

  mk_case ruling-bad-status;  spec_with_concern ruling-bad-status 'open: D1'
  good_ruling ruling-bad-status D1-sandbox.md sandbox-9
  sed 's/^Status: pending$/Status: probably pending/' \
    "$(P_DIR ruling-bad-status)/rulings/D1-sandbox.md" > "$SB/rb.tmp"
  mv "$SB/rb.tmp" "$(P_DIR ruling-bad-status)/rulings/D1-sandbox.md"

  mk_case ruling-blank-field; spec_with_concern ruling-blank-field 'open: D1'
  good_ruling ruling-blank-field D1-sandbox.md sandbox-9
  sed 's/^Ruled: —$/Ruled:/' \
    "$(P_DIR ruling-blank-field)/rulings/D1-sandbox.md" > "$SB/rf.tmp"
  mv "$SB/rf.tmp" "$(P_DIR ruling-blank-field)/rulings/D1-sandbox.md"

  mk_case ruling-empty;       plain_spec ruling-empty
  mkdir -p "$(P_DIR ruling-empty)/rulings"
  : > "$(P_DIR ruling-empty)/rulings/D1-sandbox.md"

  mk_case ruling-bad-name;    plain_spec ruling-bad-name
  mkdir -p "$(P_DIR ruling-bad-name)/rulings"
  printf 'Status: ruled\n' > "$(P_DIR ruling-bad-name)/rulings/Dx-not-a-number.md"

  mk_case contradict-silent;  plain_spec contradict-silent
  class_record contradict-silent sandbox-9 contradict

  mk_case contradict-unnamed; plain_spec contradict-unnamed
  mkdir -p "$(P_DIR contradict-unnamed)/classifications"
  printf '# Classification\n\nClassification: contradict\nRecorded: 2026-09-01\n' \
    > "$(P_DIR contradict-unnamed)/classifications/sandbox-1.md"

  # --- exit 2 --------------------------------------------------------------
  mk_case no-spec
  mk_case rulings-not-a-dir;  plain_spec rulings-not-a-dir
  printf 'a file where the directory should be\n' > "$(P_DIR rulings-not-a-dir)/rulings"
  mk_case class-not-a-dir;    plain_spec class-not-a-dir
  printf 'a file where the directory should be\n' > "$(P_DIR class-not-a-dir)/classifications"
  mk_case rulings-unreadable; plain_spec rulings-unreadable
  mkdir -p "$(P_DIR rulings-unreadable)/rulings"
  printf 'Status: ruled\n' > "$(P_DIR rulings-unreadable)/rulings/D1-sandbox.md"
  chmod 000 "$(P_DIR rulings-unreadable)/rulings"
  printf 'not a directory\n' > "$SB/a-file"

  # THE CLEAN CASE GUARDS THE OTHERS' PREMISE. If a tree with nothing open,
  # nothing pending and nothing classified does not exit 0 and say so, every
  # red case below would be red for that reason instead of its own.
  CLEAN_RC=0
  bash "$SELF" --root "$SB/clean" > "$SB/clean.out" 2> "$SB/clean.err" || CLEAN_RC=$?
  if [ "$CLEAN_RC" -ne 0 ] || ! grep -q 'PASS: every open concern cites a ruling that exists' "$SB/clean.out"; then
    printf '  the clean case exited %d and did not report the ask holding.\n' "$CLEAN_RC"
    die_unmeasured "the corpus premise did not hold; unmeasured, not a pass"
  fi
  printf '  held: case %-24s exit 0, and said so - %s\n' "clean" "PASS: every open concern cites a ruling that exists"
  CODES="$CODES$CLEAN_RC
"

  drive contradict-answered  0 'contradict classifications checked for a ruling: 1, upheld 1'

  drive open-no-ruling       1 'no .claude/productizer/rulings directory at all. The lifecycle stopped and nobody was asked'
  drive open-no-cite         1 'is open but cites no ruling id'
  drive pending-uncited      1 'no C row in the spec'
  drive ruling-stub          1 "has no '## The question' section"
  drive ruling-placeholder   1 'still carries a template placeholder'
  drive ruling-bad-status    1 'carries something other than exactly one of'
  drive ruling-blank-field   1 "header field 'Ruled' is blank"
  drive ruling-empty         1 'the ruling file is empty'
  drive ruling-bad-name      1 'filename is not D<n>'
  drive contradict-silent    1 'The lifecycle stopped in conversation and wrote nothing'
  drive contradict-unnamed   1 'names no intent, so no ruling can be joined to it'

  drive no-spec              2 'cannot read .claude/productizer/spec.md'
  drive rulings-not-a-dir    2 'rulings exists but is not a directory'
  drive class-not-a-dir      2 'exists and is not a directory'
  drive root-not-a-dir       2 'is not a directory' --root "$SB/a-file"

  # An unlistable directory is not unlistable to a user who can read anything,
  # and the header already records that. The case is DECLARED SKIPPED rather
  # than driven and silently held: a case that cannot fire is not a case.
  if [ "$(id -u)" = "0" ]; then
    SKIPPED="rulings-unreadable"
    printf '  SKIPPED: case %-22s this is running as uid 0, which can list a mode-000 directory. The refusal cannot fire, so it is not claimed as driven.\n' "rulings-unreadable"
  else
    drive rulings-unreadable 2 'cannot be listed'
  fi

  printf '  cases driven: %d. Cases that did not hold: %d\n' \
    "$((DRIVEN + 1))" "$FAILED"

  # The R39.b declaration. The reached half is computed from the cases above;
  # the documented half is the contract in this file's header.
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  if [ "$FAILED" -ne 0 ]; then
    printf 'FAIL: %d selftest case(s) did not produce the exit code and the sentence they declare.\n' "$FAILED" >&2
    exit 1
  fi
  if [ -n "$MISSING" ]; then
    printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  printf '  R39 for this tool: the self-test exists, reaches 0, 1 and 2, and every case asserts which finding it produced as well as which code.\n'
  if [ -n "$SKIPPED" ]; then
    printf '  NOT ASSERTED: case %s did not run here.\n' "$SKIPPED"
  fi
  printf '  NOT ASSERTED: an intent that was never classified at all. It leaves no record and nothing in a repository lists the intents that arrived, so no corpus can build the case - the header says the same, and the fix is the writer'"'"'s.\n'
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

SPEC="$ROOT/.claude/productizer/spec.md"
RULINGS="$ROOT/.claude/productizer/rulings"

[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unmeasured "cannot read .claude/productizer/spec.md under the given root. Without the spec there is no list of open concerns, so nothing can be said about whether anyone was asked."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-ruling-requested.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

rel() { printf '%s' "${1#"$ROOT"/}"; }

found=0
finding() { printf '    %s\n' "$1"; found=1; }

# The join key between a classification record and a ruling. Both write the
# intent's identifier as the human typed it - `#123` in one file and `123` in
# the other, or `PROJ-123` against `proj-123` - so the two are reduced to one
# spelling before they are compared. The reduction is `classification-record.py
# --slug`'s, deliberately: a second, subtly different normalisation is how two
# files come to disagree about whether they name the same intent.
intent_key() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' |
    sed -e 's/[^a-z0-9._-][^a-z0-9._-]*/-/g' -e 's/^[-.]*//' -e 's/[-.]*$//'
}

# COUNTED PER ASSERTION, never from one flag. A single `ok` at the end cannot
# tell "every unit held" apart from "no unit was examined", and this check runs
# in a repository where three of its four sweeps are over empty sets.
open_checked=0;       open_upheld=0
cited_checked=0;      cited_upheld=0
contradict_checked=0; contradict_upheld=0
class_seen=0
selftest_upheld=0
selftest_total=2

verdict() {
  if [ "${PRODUCTIZER_RULING_REQUESTED_SELFTEST:-}" = "$ROOT" ]; then
    printf 'self-assertions: not run - this is the nested pass over the fixture\n'
  else
    printf 'self-assertions upheld: %d of %d\n' "$selftest_upheld" "$selftest_total"
  fi
  if [ "$found" -ne 0 ]; then
    printf 'FAIL: a contradiction was stopped without a question anyone can answer. R34 asks which wins; these findings are the ask that never landed.\n' >&2
    exit 1
  fi
  if [ "${PRODUCTIZER_RULING_REQUESTED_SELFTEST:-}" != "$ROOT" ] && [ "$selftest_upheld" -ne "$selftest_total" ]; then
    printf 'UNMEASURED: %d of %d self-assertions ran. In a repository with no rulings and no contradiction on record every sweep above is over an empty set, so a pass that rested only on them would assert nothing.\n' "$selftest_upheld" "$selftest_total" >&2
    exit 2
  fi
  printf 'PASS: every open concern cites a ruling that exists, every pending ruling is cited back and is filled in enough to answer, and every intent recorded as a contradiction has a ruling naming it.\n'
  exit 0
}

# ---------------------------------------------------------------------------
# THE SELF-ASSERTION. Runs first, and always. See the header.
# ---------------------------------------------------------------------------
# THE MARKER NAMES THE ROOT IT SUPPRESSES, and is honoured only for that root.
# A bare on/off variable is a premise guard anything in the environment can
# switch off in silence - one stray export in CI and every run here prints PASS
# having asserted nothing, which is the exact failure this block exists to
# close. Naming the temporary fixture root means a value that arrived from
# anywhere else does not match, and the self-assertion runs anyway.
if [ "${PRODUCTIZER_RULING_REQUESTED_SELFTEST:-}" != "$ROOT" ]; then
  SELFDIR="$(cd "$(dirname "$0")" && pwd)"
  FIXREL="plugins/productizer/skills/spec/fixtures/ruling-scope/r34-conversational-stop"
  FIXDIR="$SELFDIR/../fixtures/ruling-scope/r34-conversational-stop"
  [ -d "$FIXDIR" ] ||
    die_unmeasured "the self-assertion fixture is not at $FIXREL beside this script. Without it, a repository with no rulings and no recorded contradiction gives every sweep below an empty set, and a pass would assert nothing."
  FIXDIR="$(cd "$FIXDIR" && pwd)"

  # Coverage is claimed for the fixture only when the fixture is really inside
  # the tree being checked. Pointed elsewhere with --root, it is not one of
  # that tree's files and claiming it would misstate what was read.
  fixcov() {
    case "$FIXDIR/" in
      "$ROOT"/*) printf '%s/%s\n' "${FIXDIR#"$ROOT"/}" "$1" ;;
      # The path is NOT printed: outside the checked tree it is an absolute
      # path naming somebody's home directory, and this output is committed.
      *) printf '  fixture file read from outside the tree being checked: %s\n' "$1" ;;
    esac
  }

  for fx in stopped/spec.md stopped/classifications/fixture-9.md \
            asked/spec.md asked/classifications/fixture-9.md \
            asked/rulings/D1-uncontested-part.md; do
    { [ -f "$FIXDIR/$fx" ] && [ -r "$FIXDIR/$fx" ]; } ||
      die_unmeasured "the self-assertion fixture is missing or unreadable: $FIXREL/$fx"
    fixcov "$fx"
  done

  # PREMISE GUARDS. Each names a way the fixture could stop testing what it
  # claims while still going green.
  for fx in stopped asked; do
    grep -qxF 'Classification: contradict' "$FIXDIR/$fx/classifications/fixture-9.md" ||
      die_unmeasured "$FIXREL/$fx/classifications/fixture-9.md is not classified contradict, so neither assertion below is about a contradiction."
  done
  [ ! -e "$FIXDIR/stopped/rulings" ] ||
    die_unmeasured "$FIXREL/stopped/ has a rulings directory. The whole point of that half is a contradiction with NO ruling written, so with one present it asserts nothing."
  FIXINTENT="$(awk '/^Intent:/ { sub(/^Intent:[ \t]*/, ""); print; exit }' "$FIXDIR/asked/classifications/fixture-9.md")"
  FIXRULED="$(awk '/^Intent:/ { sub(/^Intent:[ \t]*/, ""); print; exit }' "$FIXDIR/asked/rulings/D1-uncontested-part.md")"
  [ -n "$FIXINTENT" ] && [ "$(intent_key "$FIXINTENT")" = "$(intent_key "$FIXRULED")" ] ||
    die_unmeasured "$FIXREL/asked/ does not name one intent in both its record and its ruling, so the clean half of the assertion would pass for the wrong reason."

  SELF="$SELFDIR/${0##*/}"
  [ -x "$SELF" ] ||
    die_unmeasured "cannot re-invoke this script as $SELF for the self-assertion."

  run_fixture() {
    rm -rf "$WORK/fixroot"
    mkdir -p "$WORK/fixroot/.claude/productizer"
    cp -R "$FIXDIR/$1/." "$WORK/fixroot/.claude/productizer/"
    FIXRC=0
    PRODUCTIZER_RULING_REQUESTED_SELFTEST="$WORK/fixroot" "$SELF" --root "$WORK/fixroot" \
      > "$WORK/fix.out" 2> "$WORK/fix.err" || FIXRC=$?
    # The nested run's stdout is held back - its coverage lines name a
    # temporary directory. Its stderr is not: that is where the reason is, and
    # a reason nobody prints is a reason nobody has. A FAIL line from the
    # `stopped` pass is the expected result.
    if [ -s "$WORK/fix.err" ]; then
      printf 'self-assertion, nested run over %s/ - its own stderr follows:\n' "$1" >&2
      sed 's/^/  /' < "$WORK/fix.err" >&2
    fi
  }

  # 1. THE CONVERSATIONAL STOP. Classified contradict, nothing written.
  run_fixture stopped
  if [ "$FIXRC" = "2" ]; then
    die_unmeasured "the self-assertion's nested run over $FIXREL/stopped/ could not measure it (exit 2); its reason is on stderr just above."
  fi
  if [ "$FIXRC" = "1" ] && grep -q 'classified as contradict' "$WORK/fix.out"; then
    selftest_upheld=$((selftest_upheld + 1))
    printf '  self-assertion 1 upheld: a contradiction classified and then stopped in conversation, with nothing written to the spec, is refused.\n'
  else
    finding "$FIXREL/stopped/spec.md:1: a contradiction recorded as classified, with no concern row and no ruling file anywhere, was NOT refused (nested run exited $FIXRC). That is B11 exactly, and it is the gap R34 inherited from R23."
  fi

  # 2. THE SAME CONTRADICTION WRITTEN DOWN. Without this half, assertion 1
  #    would also pass for a check that refuses every contradict record it
  #    sees, which would make raising a ruling properly indistinguishable from
  #    not raising one.
  run_fixture asked
  if [ "$FIXRC" = "2" ]; then
    die_unmeasured "the self-assertion's nested run over $FIXREL/asked/ could not measure it (exit 2); its reason is on stderr just above."
  fi
  if [ "$FIXRC" = "0" ]; then
    selftest_upheld=$((selftest_upheld + 1))
    printf '  self-assertion 2 upheld: the same contradiction, written up with its concern row and its ruling, is clean.\n'
  else
    finding "$FIXREL/asked/spec.md:1: a contradiction written up exactly as rulings.md requires was refused anyway (nested run exited $FIXRC). A check that cannot tell a raised ruling from an unraised one is not asserting the ask."
  fi
fi

# ---------------------------------------------------------------------------
# The spec's Areas of concern rows. One record per cited ruling id:
#   line <TAB> open|other|open-nocite <TAB> C<n> <TAB> D<n>
# Rows inside an HTML comment are example scaffolding, not live concerns.
# ---------------------------------------------------------------------------
AWK_CONCERNS='
BEGIN { ins = 0; incomment = 0 }
/^## / { ins = ($0 ~ /^##[ \t]+Areas of concern[ \t]*$/) ? 1 : 0; next }
ins == 0 { next }
incomment == 1 { if ($0 ~ /-->/) incomment = 0; next }
/<!--/ { if ($0 !~ /-->/) incomment = 1; next }
$0 !~ /^[ \t]*\|/ { next }
{
  line = $0
  sub(/^[ \t]*\|/, "", line)
  sub(/\|[ \t]*$/, "", line)
  nf = split(line, f, "|")
  for (i = 1; i <= nf; i++) gsub(/^[ \t]+|[ \t]+$/, "", f[i])
  if (nf < 2) next
  if (f[1] !~ /^C[0-9]+$/) next
  status = f[nf]
  isopen = (status ~ /^open([ \t]*:|[ \t]*$)/) ? 1 : 0
  cited = 0
  rest = status
  while (match(rest, /D[0-9]+/)) {
    printf "%d\t%s\t%s\t%s\n", FNR, (isopen ? "open" : "other"), f[1], substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
    cited = 1
  }
  if (isopen == 1 && cited == 0)
    printf "%d\topen-nocite\t%s\t-\n", FNR, f[1]
}'

printf '%s\n' "$(rel "$SPEC")"        # coverage: one line per file examined
awk "$AWK_CONCERNS" "$SPEC" > "$WORK/concerns.tsv"

OPEN_IDS=""     # ids an open concern row points at
CITED_IDS=""    # ids any concern row points at, open or not
while IFS="$(printf '\t')" read -r cline cstate cid did; do
  [ -n "${cline:-}" ] || continue
  case "$cstate" in
    open)
      OPEN_IDS="$OPEN_IDS$did"$'\n'
      CITED_IDS="$CITED_IDS$did"$'\n'
      printf '%s\n' "$cline	$cid	$did" >> "$WORK/open.tsv"
      ;;
    other) CITED_IDS="$CITED_IDS$did"$'\n' ;;
    open-nocite)
      finding "$(rel "$SPEC"):$cline: concern $cid is open but cites no ruling id. An open concern with nowhere to be answered is a stop that asked nobody - allocate a D id and write the ruling file."
      ;;
  esac
done < "$WORK/concerns.tsv"

in_list() { printf '%s' "$2" | grep -qxF -- "$1"; }
# ---------------------------------------------------------------------------
# The rulings directory. Absent and unreadable are different sentences.
# ---------------------------------------------------------------------------
DIRSTATE="absent"
if [ -e "$RULINGS" ]; then
  [ -d "$RULINGS" ] ||
    die_unmeasured ".claude/productizer/rulings exists but is not a directory. Unmeasured - a path that is not the directory the contract names says nothing about how many rulings there are."
  if [ -r "$RULINGS" ] && [ -x "$RULINGS" ]; then
    DIRSTATE="present"
  else
    die_unmeasured ".claude/productizer/rulings exists but cannot be listed. The number of pending rulings is UNKNOWN, not zero - a directory nobody can open is exactly where an unasked question hides."
  fi
fi

FILE_IDS=""
RULED_INTENTS=""
pending_count=0
ruling_count=0

if [ "$DIRSTATE" = "present" ]; then
  for f in "$RULINGS"/D*.md; do
    # An unmatched glob arrives as its own literal text, so test the path.
    [ -e "$f" ] || continue
    base="${f##*/}"
    printf '%s\n' "$(rel "$f")"       # coverage: one line per file examined
    ruling_count=$((ruling_count + 1))

    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
      die_unmeasured "cannot read $(rel "$f"). A ruling nobody could open is not a ruling that is fine."
    fi

    case "$base" in
      D[0-9]*) ;;
      *) finding "$(rel "$f"):1: filename is not D<n>[-<slug>].md, so no counter can key it to a concern row"; continue ;;
    esac
    id="${base%.md}"
    id="${id%%-*}"
    case "$id" in
      D[0-9]*)
        rest="${id#D}"
        case "$rest" in
          *[!0-9]*) finding "$(rel "$f"):1: filename is not D<n>[-<slug>].md, so no counter can key it to a concern row"; continue ;;
        esac
        ;;
      *) finding "$(rel "$f"):1: filename is not D<n>[-<slug>].md, so no counter can key it to a concern row"; continue ;;
    esac
    FILE_IDS="$FILE_IDS$id"$'\n'

    awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function strip_code(s) { gsub(/`[^`]*`/, "", s); return s }
    function sect_start(name,   i) {
      for (i = 1; i <= TOP; i++)
        if (L[i] ~ ("^##[ \t]+" name "[ \t]*$")) return i
      return 0
    }
    function sect_end(s,   i) {
      for (i = s + 1; i <= TOP; i++)
        if (L[i] ~ /^## /) return i - 1
      return TOP
    }
    # Empty, or still wearing an angle-bracket placeholder from the template.
    # The placeholder scan carries state across lines because the templates
    # own placeholders wrap: the opening bracket and the closing one are on
    # different lines, and a per-line match sees neither.
    function check_prose(name,   s, e, i, j, nb, line, ch, isopen, oline) {
      s = sect_start(name)
      if (s == 0) { printf "SECTMISSING\t1\t%s\n", name; return }
      e = sect_end(s)
      nb = 0
      for (i = s + 1; i <= e; i++) if (L[i] !~ /^[ \t]*$/) nb++
      if (nb == 0) { printf "SECTEMPTY\t%d\t%s\n", s, name; return }
      isopen = 0; oline = 0
      for (i = s + 1; i <= e; i++) {
        line = strip_code(L[i])
        for (j = 1; j <= length(line); j++) {
          ch = substr(line, j, 1)
          if (isopen == 0) { if (ch == "<") { isopen = 1; oline = i } }
          else if (ch == ">") { printf "SECTPLACEHOLDER\t%d\t%s\n", oline, name; return }
          else if (ch == "<") oline = i
        }
      }
    }
    function check_costs(   name, s, e, i, c, m, P, row, nf, cells, cell) {
      name = "What each side costs"
      s = sect_start(name)
      if (s == 0) { printf "SECTMISSING\t1\t%s\n", name; return }
      e = sect_end(s)
      m = 0
      for (i = s + 1; i <= e; i++) if (L[i] ~ /^[ \t]*\|/) { m++; P[m] = i }
      if (m < 3) { printf "COSTNOTABLE\t%d\t%s\n", s, name; return }
      for (i = 3; i <= m; i++) {
        row = L[P[i]]
        sub(/^[ \t]*\|/, "", row)
        sub(/\|[ \t]*$/, "", row)
        nf = split(row, cells, "|")
        if (nf < 2) { printf "COSTSHORTROW\t%d\t%s\n", P[i], name; continue }
        for (c = 1; c <= 2; c++) {
          cell = trim(strip_code(cells[c]))
          if (cell == "") printf "COSTBLANK\t%d\t%d\n", P[i], c
          else if (cell ~ /<[^<>]*>/) printf "COSTPLACEHOLDER\t%d\t%d\n", P[i], c
        }
      }
    }
    { L[NR] = $0 }
    END {
      N = NR
      if (N == 0) { printf "EMPTYFILE\t1\t\n"; exit }

      firsth = 0
      for (i = 1; i <= N; i++) if (L[i] ~ /^## /) { firsth = i; break }
      lim = (firsth ? firsth - 1 : N)

      # The header block is the run of Key: value lines around the Status
      # line, above the first section heading. Scoping it this way is what
      # makes a Status: pending inside a body paragraph not a status.
      sidx = 0
      for (i = 1; i <= lim; i++) if (L[i] ~ /^Status:/) { sidx = i; break }
      if (sidx == 0) printf "NOSTATUS\t1\t\n"
      else {
        hs = sidx; while (hs > 1 && L[hs-1] !~ /^[ \t]*$/) hs--
        he = sidx; while (he < lim && L[he+1] !~ /^[ \t]*$/) he++
        for (i = hs; i <= he; i++)
          if (match(L[i], /^[A-Za-z][A-Za-z ]*:/)) {
            k = substr(L[i], 1, RLENGTH - 1)
            cnt[k]++; ln[k] = i; val[k] = trim(substr(L[i], RLENGTH + 1))
          }
      }

      nreq = split("Status,Raised,Concern,Intent,Ruled,Ruled by,Supersedes,Superseded by", REQ, ",")
      for (i = 1; i <= nreq; i++) {
        k = REQ[i]
        if (cnt[k] == 0) {
          if (k != "Status" || sidx > 0) printf "MISSINGFIELD\t%d\t%s\n", (sidx ? sidx : 1), k
        } else if (cnt[k] > 1) printf "DUPFIELD\t%d\t%s\n", ln[k], k
        else if (val[k] == "") printf "BLANKFIELD\t%d\t%s\n", ln[k], k
      }

      st = ""
      if (cnt["Status"] == 1) {
        s = L[ln["Status"]]
        if (s == "Status: pending") st = "pending"
        else if (s == "Status: ruled") st = "ruled"
        else if (s == "Status: lapsed") st = "lapsed"
        else if (s == "Status: superseded") st = "superseded"
        else printf "BADSTATUS\t%d\t\n", ln["Status"]
      }
      printf "STATUS\t%d\t%s\n", (cnt["Status"] == 1 ? ln["Status"] : 0), st

      # The intent this ruling was raised for, emitted for EVERY status. A
      # ruling that has already been ruled asked its question just as much as a
      # pending one did, so it discharges the classification record all the
      # same. Emitted before the pending-only exit below for that reason.
      if (cnt["Intent"] == 1 && val["Intent"] != "") printf "INTENTVAL\t%d\t%s\n", ln["Intent"], val["Intent"]

      if (st != "pending") exit

      # Everything from ## Ruling down belongs to the human and MUST still
      # carry its template guidance in a pending ruling. The three sections
      # below are named explicitly, so a file with no ## Ruling heading still
      # cannot pull Reasoning or Consequences into scope.
      rl = 0
      for (i = 1; i <= N; i++) if (L[i] ~ /^##[ \t]+Ruling[ \t]*$/) { rl = i; break }
      TOP = (rl ? rl - 1 : N)

      check_prose("The conflict")
      check_prose("The question")
      check_costs()
    }' "$f" > "$WORK/r.tsv"

    status=""
    while IFS="$(printf '\t')" read -r kind kline detail; do
      [ -n "${kind:-}" ] || continue
      loc="$(rel "$f"):$kline"
      case "$kind" in
        STATUS) status="$detail" ;;
        INTENTVAL) RULED_INTENTS="$RULED_INTENTS$(intent_key "$detail")"$'\n' ;;
        EMPTYFILE) finding "$loc: the ruling file is empty. An empty file is not an ask." ;;
        NOSTATUS) finding "$loc: no Status: line in the header block. Nothing can count this ruling, so a live contradiction reads as none." ;;
        BADSTATUS) finding "$loc: Status: carries something other than exactly one of pending, ruled, lapsed, superseded with nothing else on the line." ;;
        MISSINGFIELD) finding "$loc: header field '$detail' is missing. A missing line and a blank value are indistinguishable to a counter, and the counter then reports a pending ruling as ruled." ;;
        DUPFIELD) finding "$loc: header field '$detail' appears more than once, so which value is authoritative is undefined." ;;
        BLANKFIELD) finding "$loc: header field '$detail' is blank. An unset field is an em dash, never blank." ;;
        SECTMISSING) finding "$loc: pending ruling has no '## $detail' section. Without it there is no question for a human to answer." ;;
        SECTEMPTY) finding "$loc: pending ruling's '## $detail' section is empty. A stop that states no question asked nobody." ;;
        SECTPLACEHOLDER) finding "$loc: pending ruling's '## $detail' section still carries a template placeholder. A ruling wearing the template is a file, not an ask." ;;
        COSTNOTABLE) finding "$loc: pending ruling's '## $detail' section has no filled cost table. A ruler handed no costs is being asked to guess." ;;
        COSTSHORTROW) finding "$loc: cost table row has fewer than two columns." ;;
        COSTBLANK) finding "$loc: column $detail of the cost table is blank. A ruler handed one side's costs is being steered, and a steered ruling is the agent's decision wearing a human name." ;;
        COSTPLACEHOLDER) finding "$loc: column $detail of the cost table still carries a template placeholder." ;;
      esac
    done < "$WORK/r.tsv"

    if [ "$status" = "pending" ]; then
      pending_count=$((pending_count + 1))
      cited_checked=$((cited_checked + 1))
      if ! in_list "$id" "$CITED_IDS"; then
        finding "$(rel "$f"):1: $id is pending but no C row in the spec's Areas of concern cites it. The ask is invisible to anyone reading the spec, which is where intake looks."
      else
        cited_upheld=$((cited_upheld + 1))
      fi
    fi
  done
fi

# ---------------------------------------------------------------------------
# B11 itself: an open concern whose ruling file was never written.
# ---------------------------------------------------------------------------
if [ -f "$WORK/open.tsv" ]; then
  while IFS="$(printf '\t')" read -r oline ocid odid; do
    [ -n "${oline:-}" ] || continue
    open_checked=$((open_checked + 1))
    if ! in_list "$odid" "$FILE_IDS"; then
      if [ "$DIRSTATE" = "absent" ]; then
        finding "$(rel "$SPEC"):$oline: concern $ocid is open citing $odid, and there is no .claude/productizer/rulings directory at all. The lifecycle stopped and nobody was asked."
      else
        finding "$(rel "$SPEC"):$oline: concern $ocid is open citing $odid, but no rulings/$odid-*.md exists. The lifecycle stopped and nobody was asked."
      fi
    else
      open_upheld=$((open_upheld + 1))
    fi
  done < "$WORK/open.tsv"
fi

# ---------------------------------------------------------------------------
# THE STOP THAT WROTE NOTHING TO THE SPEC.
#
# Everything above starts from the spec or from the rulings directory, so a
# contradiction stopped in conversation - no concern row, no ruling file - is
# invisible to it. That is the original B11 failure and it survived the R23
# split into R33 and R34 untouched.
#
# The evidence such a stop DOES leave is the classification record.
# `record-classification.sh` writes one per intent before anything else
# happens, naming exactly one of extend, refine, duplicate, contradict; and
# `references/rulings.md` is explicit about the order that follows a
# `contradict`: allocate the ids, write the ruling file, add the concern row,
# COMMIT, and only THEN ask. So a record saying `contradict` with no ruling
# file naming the same intent is precisely a stop that asked in a session and
# wrote nothing - detectable, by location, with nothing quoted.
#
# WHAT THIS STILL CANNOT SEE, and it is worth stating plainly: an intent that
# was never classified at all leaves no record either, and nothing in this
# repository lists the intents that arrived. Closing that needs Stage 1 to
# record the classification before it asks, which is a writer-side obligation
# no check can substitute for.
# ---------------------------------------------------------------------------
CLASSREL=".claude/productizer/classifications"
CLASS="$ROOT/$CLASSREL"
CLASSSTATE="absent"
if [ -e "$CLASS" ]; then
  [ -d "$CLASS" ] ||
    die_unmeasured "$CLASSREL exists and is not a directory. A path that is not the store the contract names says nothing about what was classified."
  { [ -r "$CLASS" ] && [ -x "$CLASS" ]; } ||
    die_unmeasured "$CLASSREL exists and cannot be listed. Whether a contradiction was classified and then left unwritten is UNKNOWN, not no."
  CLASSSTATE="present"
  for c in "$CLASS"/*.md; do
    [ -e "$c" ] || continue
    printf '%s\n' "$(rel "$c")"         # coverage: one line per file examined
    class_seen=$((class_seen + 1))
    { [ -f "$c" ] && [ -r "$c" ]; } ||
      die_unmeasured "cannot read $(rel "$c"). A classification nobody could open is not a classification that is fine."
    # Read whole-line, the same way the rulings' Status is read: `contradict`
    # appears in the four-value list inside these records' own prose, and a
    # substring match would classify every record as a contradiction.
    cval="$(awk '/^Classification:/ { sub(/^Classification:[ \t]*/, ""); print; exit }' "$c")"
    [ "$cval" = "contradict" ] || continue
    contradict_checked=$((contradict_checked + 1))
    cintent="$(awk '/^Intent:/ { sub(/^Intent:[ \t]*/, ""); print; exit }' "$c")"
    if [ -z "$cintent" ]; then
      finding "$(rel "$c"):1: this record classifies an intent as contradict and names no intent, so no ruling can be joined to it. Nothing can tell whether anyone was asked."
      continue
    fi
    if in_list "$(intent_key "$cintent")" "$RULED_INTENTS"; then
      contradict_upheld=$((contradict_upheld + 1))
    elif [ "$DIRSTATE" = "absent" ]; then
      finding "$(rel "$c"):1: this intent was classified as contradict and there is no .claude/productizer/rulings directory at all. The lifecycle stopped in conversation and wrote nothing - the ask has nowhere to land and nobody is holding the question."
    else
      finding "$(rel "$c"):1: this intent was classified as contradict and no ruling file names it in its Intent field. rulings.md writes the file BEFORE the question is asked, so a contradiction with a record and no ruling is a stop that ended in a session."
    fi
  done
fi

printf 'rulings examined: %d\n' "$ruling_count"
printf 'pending rulings: %d\n' "$pending_count"
printf 'classification records examined: %d\n' "$class_seen"
printf 'open concerns checked for a ruling that exists: %d, upheld %d\n' "$open_checked" "$open_upheld"
printf 'pending rulings checked for a concern row: %d, upheld %d\n' "$cited_checked" "$cited_upheld"
printf 'contradict classifications checked for a ruling: %d, upheld %d\n' "$contradict_checked" "$contradict_upheld"
if [ "$DIRSTATE" = "absent" ]; then
  printf 'note: no .claude/productizer/rulings directory - this repo has never raised a contradiction. That is no count, not a measured zero.\n'
fi
if [ "$CLASSSTATE" = "absent" ]; then
  printf 'note: no %s directory - nothing here has recorded a classification. That is no count, not a measured zero, and it is the one state in which a conversational stop stays invisible.\n' "$CLASSREL"
fi

verdict
