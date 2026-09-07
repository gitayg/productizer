#!/usr/bin/env bash
# check-classification-provenance.sh [--version] [--help] [--root DIR]
#                                    [--spec-path PATH] [--store DIR]
#                                    [--backlog PATH] [--selftest|--self-test]
#
# Validates the provenance records `record-classification.sh` writes. Two
# acceptance rows share this one mechanism, and this is the half that refuses.
#
#   R6  When an intent arrives, the lifecycle shall classify it against the
#       WHOLE living spec as exactly one of extend, refine, duplicate or
#       contradict.
#
#   R19 If the spec home is unreachable, then the lifecycle shall stop rather
#       than classify against a remembered copy.
#
# WHAT IT ASSERTS, per record:
#
#   1. THE CLASSIFICATION IS EXACTLY ONE OF THE FOUR. Not zero - a record with
#      no Classification line, or a blank one, records nothing. Not two - a
#      second Classification line makes which value is authoritative undefined.
#      Not a fifth value, which nothing downstream knows how to act on.
#
#   2. EXACTLY ONE RECORD PER INTENT. The writer holds this at the filename;
#      this holds it at the content, because a second file under a different
#      name declaring the same intent walks straight past the filename.
#
#   3. THE HASH MATCHES THE SPEC AT THE RECORDED COMMIT. The spec is refetched
#      with `git show <commit>:<path>` and rehashed. This is the R19 assertion:
#      a classification made from a remembered copy either carries no hash - in
#      which case it is refused by 4 - or carries a hash of the remembered copy,
#      which does not match the spec at the commit it stamped.
#
#   4. NO RECORD WITHOUT A HASH. A blank, absent or placeholder `Spec hash` or
#      `Spec commit` is a finding, and so is an em dash. This is the ONE place
#      in this lifecycle where an em dash is refused rather than required: an
#      unmeasured value is normally reported honestly as unknown, but here the
#      correct response to an unreachable spec home is to write NO RECORD, so a
#      record that writes the gap in is a record that should not exist.
#
#   5. EVERY REQUIREMENT ACTIVE IN THAT SPEC WAS IN SCOPE. The active ids are
#      recomputed from the refetched spec and compared with the record's list.
#      A missing id is the truncation case: a classifier that saw part of the
#      spec can be right by luck, and a graded eval scoring 16/16 on outcomes
#      cannot tell that apart from one that saw all of it. An id in the list
#      that the spec does not have active is the same failure inverted.
#
# and once for the store as a whole:
#
#   6. THE STORE IS NOT EMPTY IN A REPO THAT DEMONSTRABLY CLASSIFIED. See the
#      section below; this is the assertion 2.0 adds, and the reason for it is
#      that the five above had never once been evaluated.
#
#   7. EVERY CORROBORATED CLASSIFICATION HAS A RECORD OF ITS OWN. This is
#      3.0's, and it fills the hole 2.0's own summary was blind to. Assertion 6
#      asks only whether the store is EMPTY. A store holding three records and
#      a backlog corroborating five classifications satisfied it completely,
#      and the difference was printed as a NOTE - so a classification that left
#      a backlog line and no record walked past every assertion in 2.0. It was
#      not hypothetical: adding one such line to this repo's backlog left 2.0
#      exiting 0.
#
#      THE JOIN IS THE INTENT IDENTIFIER. Records are named and keyed by it,
#      and a backlog line recording a classification cites the intent as an
#      issue link. A line naming exactly one intent is joinable and asserted; a
#      line naming none, or several, is NOT asserted and says so by location.
#      You cannot demand a record for an intent nothing named, and inferring
#      one from the surrounding text would be this check guessing. On this
#      repository that leaves one line unasserted, and it is printed.
#
#   8. ADVISORY - EVERY MERGED INTENT CITED IN THE CHANGE LOG HAS A RECORD.
#      Assertion 7 still cannot see a classification that left NO backlog line
#      at all. The change log can: a row that CITES AN ISSUE is a row about an
#      arriving intent whose merge changed the spec, and an intent whose
#      classification changed the spec was certainly classified. The rejection
#      of the change log below is a rejection of it as THE corroborator, and
#      none of its three reasons reaches a row that names an issue.
#
#      IT IS ADVISORY BECAUSE IT STARTS RED, and that is measured: on this
#      repository one merged intent has a row and no record. That is a real
#      gap, it is named by location, and the remedy is a record only the writer
#      can make - so the failing count is printed, kept out of every `upheld`
#      total, and does not touch the exit code. This repo's own convention for
#      a new assertion that starts red is advisory first. Promoting it to
#      blocking is a one-line change and belongs with the store being complete.
#
# ASSERTIONS ARE COUNTED SEPARATELY, NOT ROLLED INTO ONE FLAG. The summary
# names each assertion and how many records upheld it, how many failed it, and
# how many did not assert it at all - a record whose commit could not be
# resolved asserts nothing about its hash, and is counted in neither column.
# One `ok` boolean, divided at the end, is how a check comes to report a
# denominator it never measured. Assertions 1, 4 and 5 share one counter and
# say so: they are raised inside `classification-record.py`, the parser the
# writer and this check deliberately share, and it does not label which of the
# three a finding came from.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   A record made against an OLDER spec is not a finding. The normal intake
#   flow is classify, then merge the delta - so the spec moves immediately
#   after almost every correct record. Anchoring the comparison to the commit
#   the record cites is what stops this check going red on every historical
#   record the first time a requirement is added. Currency is reported per
#   record as a note, and a note is not a verdict.
#
#   It does not observe the classification being MADE. Nothing in a file can.
#   It observes the record, which is why the writer refuses to emit one it
#   cannot stand behind.
#
# NO FILE MEANS NO COUNT, NOT ZERO
#
#   no classifications/ directory   this repo has recorded none. Reported as a
#                                   note, never as "0 classifications are
#                                   fine": the two are different sentences.
#   a directory it cannot list      UNKNOWN. Exit 2. A directory nobody can
#                                   open is exactly where a truncated
#                                   classification hides.
#   a directory holding no records  a measured zero, and said so.
#
# An unmatched glob reaches a command as its own literal text in bash, so the
# cases are told apart by an explicit directory test and never by a count.
#
# AN EMPTY STORE IS NOT A PASS - AND IS NOT AUTOMATICALLY A FAILURE EITHER
#
#   Through 1.0 this check exited 0 over an empty store, saying in its own pass
#   line that it had asserted nothing. The sentence was true and the exit code
#   was not: a clean exit from a blocking check is read as "R6 holds here", and
#   this one had swept an empty set every run since the day it was written,
#   because Stage 2 intake never invoked `record-classification.sh`. The
#   mechanism was written and never wired, and nothing said so out loud.
#
#   Failing outright is the other wrong answer. A repo scaffolded this morning
#   has classified nothing and has violated nothing, and a check that cries
#   wolf there teaches everybody to ignore it.
#
#   So an empty store is not judged on its own. It is judged against evidence
#   held OUTSIDE the store about whether this repo classified anything at all:
#
#     empty store, evidence classification happened   FINDING       exit 1
#     empty store, no such evidence                   UNMEASURED    exit 2
#
#   Never 0, and never the same sentence twice: the first says records are
#   missing, the second says nothing was measured. Collapsing them would be the
#   1.0 defect again in a different costume.
#
# THE CORROBORATING SOURCE IS THE BACKLOG, AND HERE IS WHY IT AND NOT THE REST
#
#   `.claude/productizer/backlog.md`, scanned for the classification word
#   itself - the backticked `extend`, `refine`, `duplicate` or `contradict`
#   following the word `classified`. Stage 1 already writes that line onto an
#   item when it goes through intake, so the evidence is committed in the repo,
#   readable offline, in a file the lifecycle maintains for its own reasons. It
#   names the classification rather than an effect of one, and it is written
#   for all four outcomes.
#
#   The spec's `## Change log` was considered and REJECTED. It records MERGES,
#   not classifications. Two of the four outcomes - duplicate and contradict -
#   merge nothing by definition, so a lifecycle classifying correctly and
#   refusing what it should refuse leaves an empty change log. Evidence that
#   vanishes exactly when the requirement is working hardest is not evidence.
#   Its rows also cover spec edits that were never an arriving intent at all -
#   this repo's own row cites no issue, because it records a split made under a
#   decision record - so counting a row as "an intent was classified" would
#   assert something the row does not say.
#
#   Tracker labels were considered and REJECTED. They live in a service, behind
#   a network and a token: a check that reads them reports unmeasured every time
#   it runs offline, and they leave with the tracker at the next migration. That
#   is the same reason this lifecycle commits its records beside the spec
#   instead of in issue comments.
#
#   THE BACKTICKED-SPELLING LIMITATION 2.0 WROTE DOWN IS FIXED IN 3.0, AND THE
#   FIX WAS MEASURED BOTH WAYS. The pattern now also matches the past-tense
#   prose spellings and the ruling form `Closed <date> as a duplicate of R23`.
#   On this repo's backlog: 3 lines matched by the backticked pattern alone, 4
#   by the widened one. The line it gains is a real duplicate ruling the old
#   pattern could never see.
#
#   It is still PAST TENSE ONLY, and that half is measured too: running an
#   unbackticked, tense-free pattern over the same file also matches this
#   repo's own sentence `Intake will classify it a duplicate`, which is prose
#   about what intake WILL do and a record of nothing. 2.0's header predicted
#   that false positive; 3.0 confirmed it by running the wider pattern rather
#   than reasoning about it, which is why the widening keeps `classified` and
#   never `classify`, and requires `of R<n>` on the ruling form.
#
#   The backlog is read on every run, not only when the store is empty, so the
#   set of files this check declares as examined does not depend on the verdict
#   it is about to reach. When both counts are non-zero their difference is
#   printed as a note and never as a verdict: a backlog line and a store record
#   are not in one-to-one correspondence, and lines written before the store
#   existed can never have one.
#
# UNRESOLVABLE IS NOT WRONG. A record citing a commit this clone does not hold
# - a shallow clone, a rewritten history - cannot be checked. That is exit 2,
# refused, and it is never folded into a pass. The one ordering rule is
# check-spec-home's: findings already in hand are a definite answer, so they
# exit 1 even when another record was unresolvable. Unresolvability only
# refuses when it could still change the verdict.
#
# REPORTED BY LOCATION, NEVER BY QUOTING CONTENT. File, line, and the class of
# problem. A record names an intent a stranger can write, and this output
# reaches a committed results file and a model's context. The only value ever
# echoed is a classification word, checked against a closed set of four first -
# and that rule governs the backlog scan too: a corroborated line is reported
# as a line number and a classification word, never as the item's text.
# Paths are printed RELATIVE to the root, because an absolute one names
# somebody's home directory and this output is committed.
#
# ONE LINE PER FILE EXAMINED, on stdout, unindented - the spec, the backlog
# when it could be read, then every record read. The runner treats a check that
# exits clean having examined less than it declared as HOLLOW, which is a
# failure. A check that looks at nothing must not look like a pass.
#
# KNOWN LIMITATIONS, written down rather than discovered later:
#   - The active-id rules are build-view.sh's, reproduced in
#     classification-record.py. A spec written in a shape that parser does not
#     recognise yields a smaller active set, and a record matching it passes.
#     The mitigation is that both halves use the one parser, so the writer and
#     the check are wrong together and visibly - never in disagreement.
#   - A record can be hand-written to cite an ancient commit whose spec was
#     genuinely small, and it will pass. What the record proves is that its
#     scope list matches the spec it names; that the commit named is the right
#     one is what the writer, not this check, establishes.
#   - Running as a user who can read anything (root) defeats the unreadable-
#     directory test, as it defeats every such test.
#
# PORTABILITY. Developed on macOS/BSD. No GNU-only behaviour: no mapfile, no
# `grep -P`, no `date -d`, no in-place sed. Nothing suppresses stderr.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  clean - and never over an empty store
#   1  findings, including an empty store in a repo that classified
#   2  could not run - no work tree, no spec, an unreadable store or record, a
#      SHALLOW CLONE (which holds none of the commits the records cite, so
#      every one of them would look unresolvable for a reason about the clone),
#      a recorded commit this clone cannot resolve, or an empty store with
#      nothing corroborating that any classification was ever made. Never
#      confused with 0.
#
# ASSERTION 8 SETS NO EXIT CODE. Its failures are printed as ADVISORY lines by
# location and are added to no `upheld` total. An advisory that quietly moved
# the exit code would be a blocking assertion wearing a softer word.
#
# --SELFTEST BUILDS A REPOSITORY AND CLASSIFIES IN IT. R39 - every check tool
# carries a self-test that reaches each exit code it can return - and all three
# of this file's are reached below, over throwaway git repositories built in a
# temporary directory. The clean case is written by `record-classification.sh`,
# the writer this check exists to validate, so the pair is proven to agree
# rather than each agreeing with a fixture somebody typed. Every failing case
# is that same repository with exactly one thing changed. Under --selftest the
# three codes mean: every case produced the code this contract declares for it
# (0), at least one did not (1), the corpus could not be built at all (2).
# `--self-test` is accepted as an alias, because this repository spells the
# flag both ways and a tool that answers only one spelling has a self-test the
# next caller cannot find.
set -euo pipefail

export LC_ALL=C

VERSION="check-classification-provenance 3.0"

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/classification-record.py"

ROOT=""
SPEC_REL=".claude/productizer/spec.md"
STORE_REL=".claude/productizer/classifications"
BACKLOG_REL=".claude/productizer/backlog.md"
SELFTEST=""

# The corroborating pattern, WIDENED IN 3.0 AND MEASURED BEFORE IT WAS.
#
#   backticked spelling alone (2.0)  3 lines of this repo's backlog
#   the alternation below (3.0)      4 lines
#
# The line it adds is a duplicate ruling written as `Closed <date> as a
# duplicate of R23` - a real classification, of a kind 2.0 could never see,
# because the four words never appear in backticks on it.
#
# IT IS STILL PAST TENSE ONLY, and that is the measurement too: an
# unbackticked, tense-free pattern also matches this repo's own line reading
# `Intake will classify it a duplicate`, which is prose about what intake WILL
# do and a record of nothing. 2.0's header predicted that false positive; it
# was then confirmed by running the wider pattern over the file, so the
# widening keeps `classified`, never `classify`, and requires `of R<n>` on the
# ruling form so a bare mention of the word cannot corroborate anything.
EVIDENCE_RE='classified (as )?(an? )?(\*\*)?`?(extend|refine|duplicate|contradict)`?(\*\*)?|([Cc]losed|[Rr]esolved|[Mm]erged) [^|]{0,40}as an? (duplicate|contradiction) of R[0-9]+'

usage() {
  printf 'usage: check-classification-provenance.sh [--version] [--help] [--root DIR]\n'
  printf '                                          [--spec-path PATH] [--store DIR]\n'
  printf '                                          [--backlog PATH]\n'
  printf '  --root DIR        the repo work tree to examine. Defaults to the git\n'
  printf '                    top level, never to the working directory.\n'
  printf '  --spec-path PATH  spec location relative to the root\n'
  printf '  --store DIR       record store relative to the root\n'
  printf '  --selftest        build throwaway repositories in a temporary directory\n'
  printf '                    and drive every exit code this check can return.\n'
  printf '  --backlog PATH    the file corroborating that classification happened,\n'
  printf '                    relative to the root. An empty store is a FINDING when\n'
  printf '                    this file records a classification and UNMEASURED when\n'
  printf '                    it does not - it is never a pass either way.\n'
}

die_unmeasured() { printf 'check-classification-provenance: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root) [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"; ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --spec-path) [ "$#" -ge 2 ] || die_unmeasured "--spec-path needs a path"; SPEC_REL="$2"; shift 2 ;;
    --spec-path=*) SPEC_REL="${1#--spec-path=}"; shift ;;
    --store) [ "$#" -ge 2 ] || die_unmeasured "--store needs a path"; STORE_REL="$2"; shift 2 ;;
    --store=*) STORE_REL="${1#--store=}"; shift ;;
    --backlog) [ "$#" -ge 2 ] || die_unmeasured "--backlog needs a path"; BACKLOG_REL="$2"; shift 2 ;;
    --backlog=*) BACKLOG_REL="${1#--backlog=}"; shift ;;
    --selftest|--self-test) SELFTEST=1; shift ;;
    -*) printf 'check-classification-provenance: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'check-classification-provenance: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null ||
  die_unmeasured "python3 is not on PATH, so no record can be parsed or rehashed. Refusing rather than reporting unparsed records as clean."
[ -f "$LIB" ] && [ -r "$LIB" ] ||
  die_unmeasured "cannot read classification-record.py beside this script. The active-id rules live there, and a second copy of them here is how two parsers come to disagree."


# --------------------------------------------------------------- --selftest
#
# Placed after the python3 and library guards above, so a machine that cannot
# run this check at all says so once rather than through nine identical cases.
#
# THE CLEAN CASE IS WRITTEN BY THE WRITER. `record-classification.sh` is run
# inside the throwaway repository and produces the record this check then
# validates - so the case proves the two halves of the mechanism agree, which
# a hand-typed fixture cannot. Every other case is that repository copied and
# changed in exactly one way.
#
# Nothing is written into the repository this file lives in. The corpus is
# removed on every exit path, signal included.
if [ -n "$SELFTEST" ]; then
  command -v git >/dev/null ||
    die_unmeasured "git is not on PATH, and every case in this self-test is a git repository"
  WRITER="$HERE/record-classification.sh"
  [ -f "$WRITER" ] && [ -r "$WRITER" ] ||
    die_unmeasured "record-classification.sh is not beside this script, so the clean case cannot be written by the writer this check validates. Unmeasured, not a pass."

  SELF_TMP="$(mktemp -d)" ||
    die_unmeasured "cannot create a temporary directory to build the self-test corpus in"
  trap 'rm -rf "$SELF_TMP"' EXIT HUP INT TERM

  BASE="$SELF_TMP/clean"
  mkdir -p "$BASE/.claude/productizer"

  # Two active requirements and NO `## Change log` section: assertion 8 reads
  # the change log for cited intents, and a fixture that gave it one would tie
  # every case to a second, unrelated assertion.
  cat > "$BASE/.claude/productizer/spec.md" <<'FIXTURE_SPEC'
# Fixture spec

Next requirement id: R3

## Requirements

- **R1** - the lifecycle shall do the first thing.
- **R2** - when a thing arrives, the lifecycle shall do the second thing.
FIXTURE_SPEC

  # One line naming exactly one intent, in the past tense, with the
  # classification word backticked - the shape the corroborating pattern reads.
  cat > "$BASE/.claude/productizer/backlog.md" <<'FIXTURE_BACKLOG'
# Fixture backlog

- [#1](https://example.invalid/issues/1) classified as `extend`.
FIXTURE_BACKLOG

  git -c init.defaultBranch=main init -q "$BASE"
  git -C "$BASE" config user.email "fixture@example.invalid"
  git -C "$BASE" config user.name "provenance fixture"
  git -C "$BASE" add -A
  git -C "$BASE" commit -q -m "fixture spec and backlog"

  # The writer resolves its own root from the working directory, so it is run
  # from inside the repository rather than pointed at it.
  ( cd "$BASE" && bash "$WRITER" --intent 1 --classification extend ) \
    > "$SELF_TMP/writer.out" 2> "$SELF_TMP/writer.err" ||
    die_unmeasured "record-classification.sh refused to write the clean case, so there is no valid record to vary from. Unmeasured, not a pass."

  SELF_CASES=0
  SELF_UPHELD=0
  # R39.b: the reached half of the declaration below is ACCUMULATED here, one
  # entry per case as `record_case` sees it. A literal list would satisfy the
  # reader and prove nothing.
  CODES=""

  # The exit code is captured into a variable on the SAME LINE as the command.
  # A command substitution in an argument list resets $?, so reading the status
  # inside the call below would report the status of the call.
  record_case() { # <case> <expected> <observed> <what the case is>
    SELF_CASES=$((SELF_CASES + 1))
    CODES="$CODES$3
"
    if [ "$3" = "$2" ]; then
      SELF_UPHELD=$((SELF_UPHELD + 1)); verdict="held"
    else
      verdict="NOT HELD"
    fi
    printf '      %-26s expected %s  got %s  %s  %s\n' "$1" "$2" "$3" "$verdict" "$4"
  }

  # variant <name> - a copy of the clean repository to break in one way.
  variant() {
    cp -R "$BASE" "$SELF_TMP/$1"
    printf '%s\n' "$SELF_TMP/$1"
  }

  printf '    selftest: %s\n' "$VERSION"

  got=0
  bash "$0" --root "$BASE" > "$SELF_TMP/clean.out" 2> "$SELF_TMP/clean.err" || got=$?
  record_case clean-record 0 "$got" "a record written by the writer, against the spec at the commit it names"

  V="$(variant badhash)"
  python3 - "$V/.claude/productizer/classifications/1.md" <<'BREAK_THE_HASH'
import io
import re
import sys

path = sys.argv[1]
with io.open(path, encoding="utf-8") as fh:
    text = fh.read()
with io.open(path, "w", encoding="utf-8") as fh:
    fh.write(re.sub(r"Spec hash: sha256:[0-9a-f]{64}",
                    "Spec hash: sha256:" + "0" * 64, text, count=1))
BREAK_THE_HASH
  got=0
  bash "$0" --root "$V" > "$SELF_TMP/badhash.out" 2> "$SELF_TMP/badhash.err" || got=$?
  record_case hash-does-not-match 1 "$got" "the record stamps one spec and hashed another - what a remembered copy looks like written down"

  V="$(variant twice)"
  cp "$V/.claude/productizer/classifications/1.md" \
     "$V/.claude/productizer/classifications/1-again.md"
  got=0
  bash "$0" --root "$V" > "$SELF_TMP/twice.out" 2> "$SELF_TMP/twice.err" || got=$?
  record_case same-intent-twice 1 "$got" "a second file declaring the same intent walks straight past the filename guarantee"

  V="$(variant norecord)"
  rm -rf "$V/.claude/productizer/classifications"
  got=0
  bash "$0" --root "$V" > "$SELF_TMP/norecord.out" 2> "$SELF_TMP/norecord.err" || got=$?
  record_case corroborated-no-record 1 "$got" "the backlog records a classification and the store holds no provenance for it"

  V="$(variant nothing)"
  rm -rf "$V/.claude/productizer/classifications"
  printf 'nothing in this file corroborates a classification\n' \
    > "$V/.claude/productizer/backlog.md"
  got=0
  bash "$0" --root "$V" > "$SELF_TMP/nothing.out" 2> "$SELF_TMP/nothing.err" || got=$?
  record_case empty-store-no-evidence 2 "$got" "no record was examined and nothing says one should exist - unmeasured, never a clean exit over an empty set"

  V="$(variant badcommit)"
  python3 - "$V/.claude/productizer/classifications/1.md" <<'BREAK_THE_COMMIT'
import io
import re
import sys

path = sys.argv[1]
with io.open(path, encoding="utf-8") as fh:
    text = fh.read()
with io.open(path, "w", encoding="utf-8") as fh:
    fh.write(re.sub(r"Spec commit: [0-9a-f]{40}",
                    "Spec commit: " + "a" * 40, text, count=1))
BREAK_THE_COMMIT
  got=0
  bash "$0" --root "$V" > "$SELF_TMP/badcommit.out" 2> "$SELF_TMP/badcommit.err" || got=$?
  record_case commit-unresolvable 2 "$got" "whether the record was made against the whole spec is UNKNOWN - not yes, and not no"

  # A shallow clone holds none of the commits the records cite, so every one of
  # them would look unresolvable for a reason about the clone. Refused once,
  # up front, rather than discovered per record.
  git clone --quiet --depth 1 "file://$BASE" "$SELF_TMP/shallow"
  got=0
  bash "$0" --root "$SELF_TMP/shallow" \
    > "$SELF_TMP/shallow.out" 2> "$SELF_TMP/shallow.err" || got=$?
  record_case shallow-clone 2 "$got" "a clone that cannot reach the cited commits is refused, not passed"

  got=0
  bash "$0" --root "$BASE" --spec-path "no-such-spec.md" \
    > "$SELF_TMP/nospec.out" 2> "$SELF_TMP/nospec.err" || got=$?
  record_case spec-unreadable 2 "$got" "with no spec there is no active set to compare a record against"

  got=0
  bash "$0" --not-a-real-option > "$SELF_TMP/badopt.out" 2> "$SELF_TMP/badopt.err" || got=$?
  record_case unknown-option 2 "$got" "bad usage is refused, never answered"

  if [ "$SELF_CASES" = "$SELF_UPHELD" ]; then self_verdict="held"; else self_verdict="NOT HELD"; fi
  printf '    R39  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$SELF_CASES" "$SELF_UPHELD" "$self_verdict" \
    "each case exits with the code this file's contract declares for it"
  # The R39.b declaration. The reached half is computed from the cases above;
  # the documented half is the contract in this file's header.
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  printf '    NOT ASSERTED: assertion 8, which reads the change log for cited intents. The fixture spec deliberately carries no change log, so no case above exercises it; and the corpus drives the exit code, never the wording of a finding.\n'
  [ "$SELF_CASES" = "$SELF_UPHELD" ] || exit 1
  if [ -n "$MISSING" ]; then
    printf 'check-classification-provenance: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  exit 0
fi

if [ -z "$ROOT" ]; then
  if ! ROOT="$(git rev-parse --show-toplevel)"; then
    die_unmeasured "no git work tree here, and --root was not given. Refusing rather than reading the working directory, which is not the repo often enough to matter."
  fi
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"

# A SHALLOW CLONE IS REFUSED, NOT PASSED. Assertion 3 refetches the spec at the
# commit each record cites; a shallow clone holds none of them, so every record
# would report as unresolvable for a reason that is about the clone and not
# about the record. Said once, here, rather than discovered per record.
# stderr-ok: git's own diagnosis when --root is not a work tree IS the answer
# to "can this history be read", and suppressing it would leave an empty string
# indistinguishable from a repository that is genuinely not shallow.
SHALLOW="unknown"
if SHALLOW_OUT="$(git -C "$ROOT" rev-parse --is-shallow-repository)"; then
  SHALLOW="$SHALLOW_OUT"
fi
[ "$SHALLOW" != "true" ] ||
  die_unmeasured "this is a SHALLOW clone. The commit every record cites is unreachable here, so whether any classification was made against the whole spec is UNKNOWN - not yes, and not no. Fetch full history (fetch-depth: 0) and re-run."

SPEC="$ROOT/$SPEC_REL"
STORE="$ROOT/$STORE_REL"
BACKLOG="$ROOT/$BACKLOG_REL"

[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unmeasured "cannot read $SPEC_REL under the given root. Without the spec there is no active set to compare a record against, and a check that cannot compare must not report a pass."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-classification-provenance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

found=0
unresolved=0
finding() { printf '    %s\n' "$1"; found=1; }

# Every assertion carries its OWN pair of counters. Nothing here is derived by
# subtracting one number from another at the end.
a_hash_up=0;  a_hash_bad=0;  a_hash_none=0
a_name_up=0;  a_name_bad=0
a_uniq_up=0;  a_uniq_bad=0
a_body_up=0;  a_body_bad=0
a_store_up=0; a_store_bad=0; a_store_none=0
a_per_up=0;   a_per_bad=0;   a_per_none=0
a_log_up=0;   a_log_bad=0;   a_log_none=0

printf '%s\n' "$SPEC_REL"          # coverage: one line per file examined

# ---------------------------------------------------------------------------
# The store. Absent, unreadable and empty are three different answers.
# ---------------------------------------------------------------------------
DIRSTATE="absent"
if [ -e "$STORE" ]; then
  [ -d "$STORE" ] ||
    die_unmeasured "$STORE_REL exists but is not a directory. A path that is not the directory the contract names says nothing about how many classifications were recorded - unmeasured, not zero."
  if [ -r "$STORE" ] && [ -x "$STORE" ]; then
    DIRSTATE="present"
  else
    die_unmeasured "$STORE_REL exists but cannot be listed. How many classifications were recorded is UNKNOWN, not zero - a directory nobody can open is exactly where a truncated classification hides."
  fi
fi

records=0
: > "$WORK/intents.tsv"

if [ "$DIRSTATE" = "present" ]; then
  for f in "$STORE"/*.md; do
    # An unmatched glob arrives as its own literal text, so test the path.
    [ -e "$f" ] || continue
    base="${f##*/}"
    rel="$STORE_REL/$base"
    printf '%s\n' "$rel"           # coverage: one line per file examined
    records=$((records + 1))

    [ -f "$f" ] && [ -r "$f" ] ||
      die_unmeasured "cannot read $rel. A record nobody could open is not a record that is fine."

    # --- pass one: header fields, without the spec ------------------------
    python3 "$LIB" --validate "$f" "-" > "$WORK/pass1.tsv"

    rec_commit=""; rec_hash=""; rec_specpath=""; rec_intent=""; rec_class=""
    while IFS="$(printf '\t')" read -r kind kline detail; do
      [ "${kind:-}" = "VALUE" ] || continue
      case "$detail" in
        "Spec commit="*) rec_commit="${detail#Spec commit=}" ;;
        "Spec hash="*)   rec_hash="${detail#Spec hash=}" ;;
        "Spec path="*)   rec_specpath="${detail#Spec path=}" ;;
        Intent=*)        rec_intent="${detail#Intent=}" ;;
        Classification=*) rec_class="${detail#Classification=}" ;;
      esac
      : "$kline"
    done < "$WORK/pass1.tsv"

    # --- refetch the spec at the recorded commit and rehash it ------------
    # ASSERTION 3, counted on its own. A record with no commit or no hash at
    # all is assertion 4's to refuse, and asserts NOTHING here.
    SPECSRC="-"
    if [ -n "$rec_commit" ] && [ -n "$rec_hash" ] && [ -n "$rec_specpath" ]; then
      if git -C "$ROOT" show "$rec_commit:$rec_specpath" > "$WORK/at-commit" 2> "$WORK/git-err"; then
        got="$(python3 "$LIB" --sha256 "$WORK/at-commit")"
        if [ "$got" = "$rec_hash" ]; then
          SPECSRC="$WORK/at-commit"
          a_hash_up=$((a_hash_up + 1))
        else
          a_hash_bad=$((a_hash_bad + 1))
          finding "$rel:1: the recorded Spec hash does not match the spec at the recorded Spec commit. The record stamps one spec and hashed another, which is what classifying from a remembered copy looks like once it is written down. The in-scope list was NOT compared - what this record read is unknown, not empty."
        fi
      else
        printf '    %s:1: the recorded Spec commit cannot be resolved in this clone. git said:\n' "$rel"
        sed 's/^/      /' < "$WORK/git-err"
        unresolved=$((unresolved + 1))
        a_hash_none=$((a_hash_none + 1))
      fi
    else
      a_hash_none=$((a_hash_none + 1))
    fi

    # --- pass two: everything, now that the spec is in hand ---------------
    # ASSERTIONS 1, 4 and 5, in one counter, because the shared parser does
    # not label which of the three a finding belongs to and a second copy of
    # its rules here is how two parsers come to disagree.
    python3 "$LIB" --validate "$f" "$SPECSRC" > "$WORK/pass2.tsv"

    body_bad=0
    active_at="—"
    while IFS="$(printf '\t')" read -r kind kline detail; do
      case "${kind:-}" in
        FINDING) finding "$rel:$kline: $detail"; body_bad=1 ;;
        VALUE)
          case "$detail" in
            "Active at commit="*) active_at="${detail#Active at commit=}" ;;
          esac
          ;;
      esac
    done < "$WORK/pass2.tsv"
    if [ "$body_bad" -eq 0 ]; then
      a_body_up=$((a_body_up + 1))
    else
      a_body_bad=$((a_body_bad + 1))
    fi

    # --- ASSERTION 2a: the filename is the writer's uniqueness guarantee --
    if [ -n "$rec_intent" ]; then
      want="$(python3 "$LIB" --slug "$rec_intent")"
      if [ "$base" != "$want.md" ]; then
        a_name_bad=$((a_name_bad + 1))
        finding "$rel:1: the filename does not match the intent this record declares. The store holds one record per intent BY NAME, so a record filed under any other name is a second classification the filename can never catch."
      else
        a_name_up=$((a_name_up + 1))
      fi
      printf '%s\t%s\n' "$rec_intent" "$rel" >> "$WORK/intents.tsv"
    fi

    printf '  %s classification: %s, ids in scope claimed against %s active at that commit\n' \
      "$base" "${rec_class:-—}" "$active_at"

    if [ -n "$rec_hash" ] && [ "$rec_hash" != "$(python3 "$LIB" --sha256 "$SPEC")" ]; then
      printf '  %s note: the spec has moved since this record was written. Historical, not a finding - the normal intake flow is classify, then merge the delta.\n' "$base"
    fi
  done
fi

# ---------------------------------------------------------------------------
# ASSERTION 2b: exactly one record per intent, checked at the content and not
# the filename. Counted per record, so the number below is a count of records
# that held it and never a count of intents.
# ---------------------------------------------------------------------------
if [ -s "$WORK/intents.tsv" ]; then
  sort "$WORK/intents.tsv" > "$WORK/intents-sorted.tsv"
  cut -f1 "$WORK/intents-sorted.tsv" | uniq -d > "$WORK/dupes"
  while IFS="$(printf '\t')" read -r who where; do
    dup=0
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      if [ "$d" = "$who" ]; then dup=1; fi
    done < "$WORK/dupes"
    if [ "$dup" -eq 1 ]; then
      a_uniq_bad=$((a_uniq_bad + 1))
      finding "$where:1: this intent is classified more than once in the store. R6 says exactly one of the four, and two records for one intent is two answers with nothing choosing between them."
    else
      a_uniq_up=$((a_uniq_up + 1))
    fi
  done < "$WORK/intents-sorted.tsv"
fi

# ---------------------------------------------------------------------------
# ASSERTION 6: the store is not an empty one in a repo that classified.
#
# Read on EVERY run, not only when the store is empty, so the set of files
# this check declares as examined does not depend on the verdict it reaches.
# ---------------------------------------------------------------------------
corroborated=0
BACKSTATE="absent"
: > "$WORK/evidence"

if [ -e "$BACKLOG" ]; then
  if [ -f "$BACKLOG" ] && [ -r "$BACKLOG" ]; then
    BACKSTATE="read"
    printf '%s\n' "$BACKLOG_REL"   # coverage: one line per file examined
    set +e
    grep -n -E "$EVIDENCE_RE" "$BACKLOG" > "$WORK/evidence"
    grc=$?
    set -e
    case "$grc" in
      0) corroborated="$(wc -l < "$WORK/evidence" | tr -d ' ')" ;;
      1) corroborated=0 ;;          # a genuine no-match, which is an answer
      *) die_unmeasured "grep exited $grc reading $BACKLOG_REL, so whether this repo ever classified anything is UNKNOWN. An empty store is only innocent once that question has an answer." ;;
    esac
  else
    BACKSTATE="unreadable"
  fi
fi

if [ "$records" -gt 0 ]; then
  a_store_up=1
elif [ "$corroborated" -gt 0 ]; then
  a_store_bad=1
else
  a_store_none=1
fi

# ---------------------------------------------------------------------------
# ASSERTION 7: EVERY CORROBORATED CLASSIFICATION HAS A RECORD OF ITS OWN.
#
# This is 3.0's assertion, and the hole it fills is the one 2.0's own summary
# was blind to. Assertion 6 asks whether the store is EMPTY. A store holding
# three records and a backlog corroborating five classifications satisfied it
# completely: the two extra classifications were invisible to both halves of
# the mechanism, and the difference was printed as a NOTE. So a classification
# that left a backlog line and no record walked past every assertion in 2.0.
#
# The join is the INTENT IDENTIFIER. Records are named and keyed by it, and a
# backlog line that records a classification cites the intent as an issue
# link. A line naming exactly one intent is joinable and is asserted. A line
# naming none, or more than one, is NOT asserted and says so by location: you
# cannot demand a record for an intent nothing named, and inventing one from
# the surrounding text would be this check guessing.
# ---------------------------------------------------------------------------
: > "$WORK/record-intents"
if [ -s "$WORK/intents.tsv" ]; then
  cut -f1 "$WORK/intents.tsv" | sort -u > "$WORK/record-intents"
fi

classification_word() { # <backlog line, as grep -n printed it>
  local w
  w="$(printf '%s\n' "$1" | sed -n -E 's/.*classified (as )?(an? )?\**`?(extend|refine|duplicate|contradict)`?\**.*/\3/p' | head -1)"
  if [ -z "$w" ]; then
    w="$(printf '%s\n' "$1" | sed -n -E 's/.*as an? (duplicate|contradiction) of R[0-9]+.*/\1/p' | head -1)"
    [ "$w" != "contradiction" ] || w="contradict"
  fi
  # Only ever a word from the closed set of four reaches stdout. A record
  # names an intent a stranger can write, and this output is committed.
  case "$w" in extend|refine|duplicate|contradict) printf '%s' "$w" ;; *) printf '%s' "—" ;; esac
}

while IFS= read -r line; do
  [ -n "$line" ] || continue
  lno="${line%%:*}"
  word="$(classification_word "$line")"

  # The intent identifiers this line names, deduplicated. grep -o exits 1 on a
  # genuine no-match, which is an ANSWER here and not a failure, so it is taken
  # as a value rather than allowed to kill the run under `set -e`.
  ids=""
  ids="$(printf '%s\n' "$line" | grep -o -E '\[#[0-9]+\]\(' | sed -E 's/^\[#([0-9]+)\]\($/\1/' | sort -u)" || :
  count=0
  for one in $ids; do count=$((count + 1)); : "$one"; done

  if [ "$count" -ne 1 ]; then
    a_per_none=$((a_per_none + 1))
    printf '  %s:%s note: a classification of `%s` is recorded here and the line names %d intent identifier(s), so no record can be looked for. NOT asserted - not a pass and not a finding.\n' \
      "$BACKLOG_REL" "$lno" "$word" "$count"
    continue
  fi

  have=0
  while IFS= read -r known; do
    [ -n "$known" ] || continue
    if [ "$known" = "$ids" ]; then have=1; fi
  done < "$WORK/record-intents"

  if [ "$have" -eq 1 ]; then
    a_per_up=$((a_per_up + 1))
  else
    a_per_bad=$((a_per_bad + 1))
    finding "$BACKLOG_REL:$lno: an intake classification of \`$word\` is recorded here and the store holds no provenance record for the intent this line names. R6 needs the ids that were in scope and R19 needs the hash of what was read; neither exists for this classification, so neither can ever be checked. The store cannot fill itself: Stage 2 intake has to call record-classification.sh at the moment it settles on one of the four."
  fi
done < "$WORK/evidence"

# ---------------------------------------------------------------------------
# ASSERTION 8, ADVISORY: A MERGED SPEC CHANGE THAT CITES AN INTENT IS ITSELF
# EVIDENCE THAT THE INTENT WAS CLASSIFIED.
#
# 2.0's header REJECTED the change log as THE corroborator and was right to:
# it records merges, duplicate and contradict merge nothing by definition, and
# some of its rows record spec edits that were never an arriving intent. None
# of that argues against using it as AN ADDITIONAL one. A row that CITES AN
# ISSUE is a row about an arriving intent - the objection does not reach it -
# and an intent whose classification changed the spec was certainly
# classified. This closes the case assertion 7 cannot see: a classification
# that left NO backlog line at all, and would otherwise be invisible to both
# halves.
#
# IT IS ADVISORY, and the reason is measured rather than tactful. On this
# repository it fires: one merged intent has a row and no record. That is a
# real gap and it is named by location below, but it is a gap in the STORE
# rather than in this check, and the remedy is a record only the writer can
# make. This repo's own convention for a new assertion that starts red is to
# declare it advisory first (`R8 asserts every added requirement has a row,
# advisory first because it starts red`), and promoting it to blocking is a
# one-line change once the store is complete. An advisory count is NEVER added
# into `upheld` and never changes the exit code.
# ---------------------------------------------------------------------------
python3 - "$SPEC" <<'PY' > "$WORK/log-intents"
"""Intent identifiers cited by the spec's `## Change log` rows.

Emits `<line>\t<intent>` per cited issue. Columns are located by HEADER NAME,
never by position, and a row whose first cell is a `<placeholder>` is not a
record of anything.
"""
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    lines = handle.read().split("\n")

start = None
for index, line in enumerate(lines):
    if re.match(r'^##\s+Change log\s*$', line):
        start = index + 1
        break
if start is None:
    raise SystemExit(0)                 # no table: assertion 8 asserts nothing
end = len(lines)
for index in range(start, len(lines)):
    if re.match(r'^##\s', lines[index]):
        end = index
        break

columns = None
for index in range(start, end):
    line = lines[index]
    if not line.lstrip().startswith("|"):
        continue
    parts = line.strip().split("|")
    if parts and parts[0].strip() == "":
        parts = parts[1:]
    if parts and parts[-1].strip() == "":
        parts = parts[:-1]
    row = [part.strip() for part in parts]
    if not row or all(re.match(r'^:?-{2,}:?$', cell) for cell in row):
        continue
    if columns is None:
        lowered = [cell.lower() for cell in row]
        if "issue" in lowered:
            columns = lowered.index("issue")
        continue
    if re.match(r'^<[^>]*>$', row[0]):
        continue
    if columns >= len(row):
        continue
    for found in re.finditer(r'\[#([0-9]+)\]\(', row[columns]):
        sys.stdout.write("%d\t%s\n" % (index + 1, found.group(1)))
PY

if [ -s "$WORK/log-intents" ]; then
  while IFS="$(printf '\t')" read -r lno intent; do
    [ -n "$intent" ] || continue
    have=0
    while IFS= read -r known; do
      [ -n "$known" ] || continue
      if [ "$known" = "$intent" ]; then have=1; fi
    done < "$WORK/record-intents"
    if [ "$have" -eq 1 ]; then
      a_log_up=$((a_log_up + 1))
    else
      a_log_bad=$((a_log_bad + 1))
      # PROMOTED TO BLOCKING once the store was complete, which is the condition
      # this assertion was written to wait for. It began advisory because it
      # started red - the change log cited an intent (#3) whose merge changed
      # the spec and which had left no record at all, and a check that is red on
      # arrival for a gap only the writer can close teaches people to ignore it.
      # That record now exists, the assertion holds 3 of 3, and an advisory that
      # has gone green is an assertion nobody is enforcing.
      finding "$SPEC_REL:$lno: this change-log row cites an arriving intent whose merge changed the spec, and the store holds no provenance record for it. A classification that changed the spec certainly happened; which ids were in scope and which spec was read are unrecorded and can never be checked."
    fi
  done < "$WORK/log-intents"
else
  a_log_none=1
fi

# ---------------------------------------------------------------------------
# The summary. Every number below was counted where it was measured.
# ---------------------------------------------------------------------------
printf 'records examined: %d\n' "$records"
if [ "$DIRSTATE" = "absent" ]; then
  printf 'note: no %s directory - this repo has recorded no classification. That is no count, not a measured zero.\n' "$STORE_REL"
elif [ "$records" -eq 0 ]; then
  printf 'note: %s exists and holds no records. This one IS a measured zero.\n' "$STORE_REL"
fi
printf 'unresolvable commits: %d\n' "$unresolved"

case "$BACKSTATE" in
  read)
    printf 'classifications corroborated in %s: %d\n' "$BACKLOG_REL" "$corroborated"
    ;;
  absent)
    printf 'note: no %s - nothing in this repo corroborates a classification either way. Absent is not the same sentence as none happened.\n' "$BACKLOG_REL"
    ;;
  unreadable)
    printf 'note: %s exists and cannot be read. Whether this repo ever classified anything is UNKNOWN, not none.\n' "$BACKLOG_REL"
    ;;
esac

if [ "$records" -gt 0 ] && [ "$corroborated" -gt "$records" ]; then
  printf 'note: %d corroborated classification(s) against %d record(s). Reported, never judged - the two are not in one-to-one correspondence, and a backlog line written before the store existed can never have a record.\n' \
    "$corroborated" "$records"
fi

printf 'assertions, each counted where it was measured:\n'
printf '  3 hash matches the spec at the recorded commit: %d upheld, %d failed, %d not asserted\n' \
  "$a_hash_up" "$a_hash_bad" "$a_hash_none"
printf '  1+4+5 classification value, hash present, scope list complete: %d upheld, %d failed\n' \
  "$a_body_up" "$a_body_bad"
printf '  2a filename matches the intent the record declares: %d upheld, %d failed\n' \
  "$a_name_up" "$a_name_bad"
printf '  2b exactly one record per intent, at the content: %d upheld, %d failed\n' \
  "$a_uniq_up" "$a_uniq_bad"
printf '  6 the store is not empty in a repo that classified: %d upheld, %d failed, %d not asserted\n' \
  "$a_store_up" "$a_store_bad" "$a_store_none"
printf '  7 every corroborated classification has a record of its own: %d upheld, %d failed, %d not asserted\n' \
  "$a_per_up" "$a_per_bad" "$a_per_none"
printf '  8 every merged intent cited in the change log has a record: %d upheld, %d failed, %d not asserted\n' \
  "$a_log_up" "$a_log_bad" "$a_log_none"
printf '  note: assertion 8 was advisory until the store was complete, because it started red on a gap only the writer could close and a check that is red on arrival teaches people to ignore it. The store is complete, so it now sets the exit code like the rest. An advisory that has gone green is an assertion nobody is enforcing.\n'

if [ "$found" -ne 0 ]; then
  if [ "$records" -eq 0 ]; then
    printf 'FAIL: this repo records %d classification(s) and holds provenance for none of them. An empty store here is not nothing to check - it is R6 and R19 unrecorded, and the store cannot fill itself: Stage 2 intake has to call record-classification.sh at the moment it settles on one of the four.\n' "$corroborated" >&2
  else
    printf 'FAIL: a classification record does not stand up. R6 needs the whole active set to have been in scope; R19 needs a hash that matches the spec at the commit it names.\n' >&2
  fi
  exit 1
fi

if [ "$unresolved" -gt 0 ]; then
  printf 'REFUSED: %d record(s) cite a commit this clone cannot resolve, so whether they were classified against the whole spec is UNKNOWN - not yes, and not no.\n' "$unresolved" >&2
  exit 2
fi

# The verdict line says what was actually asserted. A run with no records has
# asserted nothing about records, and through 1.0 that run exited 0 - which is
# the green summary line this whole stage exists to distrust.
if [ "$records" -eq 0 ]; then
  # The reason differs and is said differently. "Nothing corroborates it" is a
  # measured answer; "the corroborator could not be read" is not one, and
  # printing the first sentence over the second would be this check inventing
  # the measurement it just failed to take.
  case "$BACKSTATE" in
    read)   why="nothing in $BACKLOG_REL corroborates that this repo has ever classified an intent" ;;
    absent) why="there is no $BACKLOG_REL to corroborate that this repo has ever classified an intent" ;;
    *)      why="$BACKLOG_REL could not be read, so whether this repo has ever classified an intent is UNKNOWN - not no" ;;
  esac
  printf 'UNMEASURED: no classification record was examined, and %s. R6 and R19 are NOT asserted by this run. Refusing rather than passing: a clean exit over an empty set is read as the requirement holding, and it is the one wrong answer that looks healthy.\n' "$why" >&2
  exit 2
fi

printf 'PASS: all %d record(s) carry a hash that matches the spec at the commit they name, exactly one classification from the four, and every requirement active in that spec in scope.\n' "$records"
