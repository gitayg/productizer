#!/usr/bin/env bash
# check-spec-home-stop.sh [--version] [--help] [--root DIR] [--fixture DIR]
#                         [--tree DIR] [--selftest]
#
# Asserts R19: IF THE SPEC HOME IS UNREACHABLE, THEN THE LIFECYCLE SHALL STOP
# RATHER THAN CLASSIFY AGAINST A REMEMBERED COPY.
#
# WHY THIS EXISTS, MEASURED RATHER THAN ARGUED. `check-spec-home.sh` was the
# only check the acceptance table pointed at for this, and its own header says
# it asserts R1 - one living spec per product. An audit made the spec home
# unreachable in two otherwise identical trees, one where nothing had been
# classified (R19 obeyed) and one where a classification had been recorded from
# a remembered copy (R19 violated), and that check produced byte-identical
# output and the same exit code in both. Its verdict is independent of whether
# R19 was obeyed, so it is not evidence about R19.
#
# `check-classification-provenance.sh` owns the other half of the mechanism and
# cannot own this one either: its first act is to read the spec, and it exits 2
# - unmeasured - the moment the spec home is unreachable. The one situation R19
# is about is the one situation it refuses to render a verdict in.
#
# WHAT R19 IS ABOUT. An agent cannot reach the authoritative spec, so it
# classifies an intent against a copy it remembers. A classification made
# against a remembered spec can miss a contradiction the real spec would have
# caught. The obligation is to STOP, not to proceed on stale information.
#
# WHAT MAKES THE VIOLATION OBSERVABLE. `record-classification.sh` writes the
# spec commit and content hash every classification was made against. So
# "classified from a remembered copy" is a fact on disk rather than a mood:
#
#   a record in a tree whose spec home cannot be read was made against
#   something other than the live spec, because the live spec was not there
#   to be read;
#
#   a record whose `Spec commit` is absent, blank, a placeholder or not
#   commit-shaped cannot name the spec it was made against at all.
#
# WHAT IT ASSERTS, SEPARATELY, EACH NAMED IN THE OUTPUT. Every one is driven by
# a constructed case under `fixtures/spec-home-stop/`, and every case declares
# both the construction and the verdict the detector must reach.
#
#   A1  unreachable spec home + nothing classified   -> CLEAN. The lifecycle
#       stopped. This is the honest inverse; without it the check only ever
#       proves it can say no.
#   A2  unreachable spec home + a classification recorded anyway -> FINDING.
#       This is the violation and the point of the check. A1 and A2 are
#       constructed as the same tree differing in exactly one thing: whether a
#       record is present. That is the audit's two-tree experiment, committed.
#   A3  a record whose `Spec commit` is absent, blank, a placeholder or not
#       commit-shaped -> FINDING. A record that cannot say which spec it was
#       made against cannot show it was made against the live one.
#   A4  reachable spec home + a well-formed record -> CLEAN. The negative
#       control: without it, a detector that fired on the mere existence of a
#       record would pass A2 and A3 and be worthless.
#
# A1 TO A4 READ A TREE'S STATE, AND A STATE HAS NO CLOCK IN IT. That was 1.0's
# defect and it is the reason for the next two: in an unreachable-home tree
# 1.0 called EVERY record a violation, so a record written on Tuesday while
# the home worked and a record written on Thursday after it broke produced the
# same finding. Only the second was classified against a remembered copy.
#
#   A5  a record committed BEFORE the commit that broke the home -> NOT a
#       finding. Git knows when both happened, and `merge-base --is-ancestor`
#       reads ANCESTRY rather than dates, which is what "before" has to mean
#       in a history where committer clocks disagree and a rebase rewrites
#       them. A record written IN the breaking commit is NOT before it: a
#       commit is its own ancestor, and the first build of this said `before`
#       for exactly that record until the constructed history caught it.
#   A6  a record committed AFTER it -> a finding. A5's inverse, and mandatory:
#       a timeline that only ever spares records is a detector switched off.
#
# A5 AND A6 NEED A HISTORY RATHER THAN A TREE, so they are BUILT at run time
# in the temporary directory this run already owns, not committed under
# `fixtures/` - a case directory there cannot carry a git history of its own
# inside this repository. One construction exercises both: commit one has a
# reachable home and a record, commit two deletes the spec and adds a second
# record. The two records differ in exactly one thing, which side of the
# deletion they were written on. That is the two-tree experiment moved onto
# the time axis.
#
# EVERY WAY THE TIMELINE CANNOT BE READ LEAVES THE FINDING STANDING, and says
# which way it was: not a work tree, no commit ever deleted the spec path, the
# record untracked. Downgrading a finding on an unreadable timeline would turn
# every untracked tree into an alibi. A SHALLOW CLONE IS REFUSED, not passed:
# it holds neither commit, so every record would look undateable for a reason
# about the clone and not about the record.
#
#   A7  THIS REPOSITORY. Every assertion above is about a fixture or a
#       construction, so through 1.0 the check examined its own test data and
#       the question of whether THIS repository stopped was asserted by
#       nothing. A7 runs the same detector over `--root`.
#
#       A7 IS CONDITIONAL AND SAYS SO WHEN IT DOES NOT FIRE. R19's trigger is
#       an unreachable spec home; this repository's is reachable, so the
#       requirement is not in force here and A7 renders NO verdict on the
#       stop. It prints that it did not fire, the summary prints NOT ASSERTED,
#       and the PASS line says in as many words that it is not a statement
#       about this repository. Printing `A7 held` there would be a vacuous
#       hold, which is the defect this whole file exists to stop repeating.
#       What A7 does assert unconditionally is A3's half: a record HERE that
#       cannot name the spec it was made against is a finding whatever the
#       home is doing. And a root with no `.claude/productizer` at all asserts
#       nothing rather than holding - it has nothing to stop.
#
# THE PREMISE IS GUARDED BOTH WAYS, AND A FAILED PREMISE IS NEVER A PASS.
#
#   a case declared unreachable whose spec turns out readable   exit 2
#   a case declared reachable whose spec cannot be read         exit 2
#   a case declaring records whose store holds none             exit 2, and it
#       says which assertion was therefore never exercised. This repo has
#       already shipped an assertion that swept an empty set from the day it
#       was written; the second one does not get to happen quietly.
#   an assertion no case exercises                              exit 2
#   no cases at all, or a case with no `case.txt`               exit 2
#
# `--tree DIR` runs the detector on ONE tree and reports its verdict directly -
# 0 clean, 1 findings - with no declared expectation to compare against. That
# is the mode the two-tree experiment is run in, and it is also how this check
# is pointed at a real repository.
#
# NO NETWORK, EVER. Reachability is decided from local state: the spec named by
# `spec.path` in the tree's own `.claude/productizer/config.json`, read or not
# read. A check that asked the network would render one verdict on a train and
# another in the office, and CI would hang on the difference.
#
# WHAT IT DELIBERATELY DOES NOT DO. It does not resolve a well-formed commit
# against an object store. That is `check-classification-provenance.sh`'s job,
# it needs a repository the record's tree may not be, and duplicating it here
# would go red on every shallow clone. Unresolvable here means unresolvable as
# a commit identity: no field, no value, a placeholder, or not a sha.
#
# It observes RECORDS, not the act of classifying. Nothing in a file can
# observe an act. The writer's refusal path is the other half, and the two are
# deliberately separate: this check would still fire on a record written by
# hand, by a model, or by a future writer that forgot to refuse.
#
# REPORTED BY LOCATION, NEVER BY QUOTING CONTENT. A record names an intent a
# stranger can write, and this output is tailed into a committed results file
# and read back into a model's context. The value of a field is never echoed -
# only the field, the line and the class of problem.
#
# WHAT IT PRINTS. One BARE repo-relative path per line for every file examined,
# unindented, which the runner parses as coverage. Everything else is indented
# or is a multi-word line. No absolute path is ever printed: an absolute path
# in a committed result names whoever ran it.
#
# PORTABILITY. Developed on macOS/BSD. No GNU-only behaviour: no mapfile, no
# `grep -P`, no `date -d`, no in-place sed. Nothing suppresses stderr. Nothing
# is written into the repository under examination; the only scratch is a
# temporary directory removed on exit.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  clean - every assertion held, or (--tree) the tree holds no finding
#   1  findings - an assertion did not hold, or (--tree) the tree holds one
#   2  could not run - bad usage, no fixture, no python3, a case whose premise
#      did not hold, an assertion no case exercised, a shallow clone under a
#      tree whose timeline had to be read, or a constructed history that did
#      not come out as constructed. Never confused with 0.
#
# Under --selftest (--self-test is accepted too) the same three mean: every
# case produced the exit code it declares and said what it was supposed to say
# (0), at least one did not (1), and the corpus could not be driven at all (2).
set -euo pipefail

export LC_ALL=C

VERSION="check-spec-home-stop 2.0"

MODE="cases"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$HERE")"

ROOT=""
FIXTURE="$SKILL/fixtures/spec-home-stop"
TREE=""

# Coverage lines are bare only for trees that ARE this repository. Set to 0
# around a constructed history in a temporary directory.
EMIT_PATHS=1

# The store's location inside a tree. The detector holds the same constant;
# they are the one contract `record-classification.sh` writes to.
STORE_IN_TREE=".claude/productizer/classifications"
# The spec path the tree itself declares, filled in per tree by the detector.
SPEC_IN_TREE=""

die_unmeasured() { printf 'check-spec-home-stop: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)      [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)    ROOT="${1#--root=}";       shift ;;
    --fixture)   [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2"; shift 2 ;;
    --fixture=*) FIXTURE="${1#--fixture=}"; shift ;;
    --tree)      [ "$#" -ge 2 ] || die_unmeasured "--tree needs a path";    TREE="$2";    shift 2 ;;
    --tree=*)    TREE="${1#--tree=}";       shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1" ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1"

# stderr-ok: `command -v` on a missing name writes nothing useful and this is
# a pure presence probe - the refusal below carries the whole diagnosis.
command -v python3 >/dev/null 2>&1 ||
  die_unmeasured "python3 is not on PATH, so no tree can be read. Refusing rather than reporting an unexamined fixture as clean."

# ---------------------------------------------------------------------------
# --selftest. R39: one case per exit code this tool can return, in BOTH of the
# modes it has, because they are two different programs sharing a detector.
#
#   --tree      one tree, its own verdict, nothing declared to compare against
#   the default the declared cases, the built histories, and A7
#
# A corpus that only drove --tree would leave the case loop, the premise
# guards and the unexercised-assertion refusal untested, and those are where
# this file's own defects have been.
#
# THE HISTORIES ARE BUILT AT RUN TIME, for the reason the header already
# gives: a case directory under `fixtures/` cannot carry a git history of its
# own inside this repository. `build_timeline_repo` above builds two of them
# for A5 and A6; the sandbox below builds its own for the shallow refusal and
# for the --tree timeline path, which A5 and A6 do not reach.
#
# EVERY CASE ASSERTS ITS OWN SENTENCE, NOT ONLY ITS EXIT CODE. Six things exit
# 2 here and each is a different refusal - a tree that is not a directory, a
# config that is not JSON, a store that is not a directory, a missing fixture,
# an empty fixture, a case whose premise did not hold, and a shallow clone.
# Reading exit codes alone could not tell a broken premise from a missing
# fixture, and this file has already shipped one assertion that swept an empty
# set; the second one does not get to happen quietly.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SELF="$HERE/${0##*/}"
  [ -f "$SELF" ] ||
    die_unmeasured "cannot re-invoke this script for the self-test, so no case was driven"
  command -v git >/dev/null ||
    die_unmeasured "git is not on PATH, so no history could be built and no case was driven"

  # `pwd -P` because the temporary directory is reached through a symlink on
  # macOS and git resolves every path it prints.
  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-spec-home-stop-selftest.XXXXXX")" ||
    die_unmeasured "could not create a sandbox, so no case was driven"
  SB="$(cd "$SB" && pwd -P)"
  trap 'rm -rf "$SB"' EXIT HUP INT TERM

  ST=".claude/productizer"

  mk_tree() { mkdir -p "$SB/$1/$ST"; }

  put_config() {
    cat > "$SB/$1/$ST/config.json" <<'JSON'
{"product": {"spec_home": "example/home-repo"}, "spec": {"path": ".claude/productizer/spec.md"}}
JSON
  }
  put_spec() {
    printf '# Living spec — sandbox\n\n## Requirements\n\n- **R1** — The lifecycle shall stop.\n' \
      > "$SB/$1/$ST/spec.md"
  }
  put_record() {
    # $1 tree, $2 name, $3 the Spec commit value
    mkdir -p "$SB/$1/$ST/classifications"
    cat > "$SB/$1/$ST/classifications/$2.md" <<REC
Intent: $2
Classification: extend
Recorded: 2026-01-01
Spec path: .claude/productizer/spec.md
Spec commit: $3
Spec hash: sha256:0000000000000000000000000000000000000000000000000000000000000000
In scope count: 1

## Requirement ids in scope

R1
REC
  }

  GOOD_SHA="0123456789abcdef0123456789abcdef01234567"

  FAILED=0
  DRIVEN=0
  # R39.b: the reached half of the declaration below is ACCUMULATED here, one
  # entry per case as it ran. A literal list would satisfy the reader and prove
  # nothing.
  CODES=""

  drive() {
    # $1 case name, $2 expected exit, $3 expected sentence, $4.. argv
    local case_name="$1" want="$2" marker="$3"
    shift 3
    local rc=0
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

  # --- trees for --tree ----------------------------------------------------
  mk_tree stopped;        put_config stopped
  mk_tree reachable;      put_config reachable; put_spec reachable
  put_record reachable rec "$GOOD_SHA"
  mk_tree classified;     put_config classified
  put_record classified rec "$GOOD_SHA"
  mk_tree placeholder;    put_config placeholder; put_spec placeholder
  put_record placeholder rec "—"
  mk_tree bad-config;     printf 'this is not JSON {\n' > "$SB/bad-config/$ST/config.json"
  mk_tree store-not-dir;  put_config store-not-dir; put_spec store-not-dir
  printf 'a file where the store should be\n' > "$SB/store-not-dir/$ST/classifications"
  printf 'not a directory\n' > "$SB/a-file"

  # A history where the record was written BEFORE the home broke. `--tree`
  # reaches the timeline through its own path, which A5 and A6 do not drive.
  mk_tree spared; put_config spared; put_spec spared
  put_record spared rec "$GOOD_SHA"
  git -c init.defaultBranch=main init -q "$SB/spared"
  git -C "$SB/spared" config user.email "fixture@example.invalid"
  git -C "$SB/spared" config user.name "check-spec-home-stop selftest"
  git -C "$SB/spared" add -A
  git -C "$SB/spared" -c commit.gpgsign=false commit -q -m "the home is reachable and one classification is recorded"
  rm -f "$SB/spared/$ST/spec.md"
  git -C "$SB/spared" add -A
  git -C "$SB/spared" -c commit.gpgsign=false commit -q -m "the spec home breaks afterwards"

  # The same history, cloned shallow. Neither commit is reachable, so a record
  # cannot be dated at all - UNKNOWN, and never innocent.
  git clone -q --depth 1 "file://$SB/spared" "$SB/shallow" ||
    die_unmeasured "could not build a shallow clone, so the refusal that separates an undateable record from an innocent one was never driven"

  # --- constructed fixtures for the default mode ---------------------------
  mk_fixture_case() {
    # $1 fixture dir, $2 case name, $3 case.txt body written by the caller
    mkdir -p "$SB/$1/$2/$ST"
  }
  FIX_BAD="$SB/fixture-premise"
  mkdir -p "$FIX_BAD/a1/$ST"
  printf '# Living spec — sandbox\n\n## Requirements\n\n- **R1** — The lifecycle shall stop.\n' \
    > "$FIX_BAD/a1/$ST/spec.md"
  cat > "$FIX_BAD/a1/case.txt" <<'DECL'
Case: declares an unreachable home over a spec that is right there
Asserts: A1
Home: unreachable
Records: 0
Expect: clean
Findings: 0
DECL

  FIX_FAIL="$SB/fixture-verdict"
  mkdir -p "$FIX_FAIL/a1/$ST/classifications"
  cat > "$FIX_FAIL/a1/$ST/classifications/rec.md" <<REC
Intent: rec
Classification: extend
Recorded: 2026-01-01
Spec path: .claude/productizer/spec.md
Spec commit: 0123456789abcdef0123456789abcdef01234567
Spec hash: sha256:0000000000000000000000000000000000000000000000000000000000000000
In scope count: 1
REC
  cat > "$FIX_FAIL/a1/case.txt" <<'DECL'
Case: an unreachable home with a classification recorded, declared clean anyway
Asserts: A1
Home: unreachable
Records: 1
Expect: clean
Findings: 0
DECL

  FIX_EMPTYSTORE="$SB/fixture-emptystore"
  mkdir -p "$FIX_EMPTYSTORE/a2/$ST"
  cat > "$FIX_EMPTYSTORE/a2/case.txt" <<'DECL'
Case: declares a record its store does not hold
Asserts: A2
Home: unreachable
Records: 1
Expect: finding
Findings: 1
DECL

  mkdir -p "$SB/fixture-empty"

  # A root that does not run this lifecycle, so A7 is NOT APPLICABLE and the
  # default-mode cases are the only thing the verdict rests on.
  mkdir -p "$SB/no-lifecycle"

  # THE CLEAN CASE GUARDS THE OTHERS' PREMISE, and it is the tool's own
  # committed corpus: the four declared cases, the two built histories, and A7
  # rendering no verdict over a root with no lifecycle in it. If that does not
  # exit 0, every red case below would be red for that reason instead of its
  # own.
  CLEAN_RC=0
  bash "$SELF" --root "$SB/no-lifecycle" > "$SB/clean.out" 2> "$SB/clean.err" || CLEAN_RC=$?
  if [ "$CLEAN_RC" -ne 0 ] || ! grep -q 'PASS: 4 constructed cases and one built history' "$SB/clean.out"; then
    printf '  the clean case exited %d and did not report the declared cases holding.\n' "$CLEAN_RC"
    die_unmeasured "the corpus premise did not hold; unmeasured, not a pass"
  fi
  printf '  held: case %-24s exit 0, and said so - %s\n' "declared-cases" "PASS: 4 constructed cases and one built history"
  CODES="$CODES$CLEAN_RC
"

  drive tree-stopped        0 'R19 obeyed'                      --tree "$SB/stopped"
  drive tree-reachable      0 'the spec home is reachable, so R19 was not in force' --tree "$SB/reachable"
  drive tree-spared         0 'committed BEFORE the commit that made the spec home unreachable' --tree "$SB/spared"

  drive tree-classified     1 'R19 is violated in this tree'    --tree "$SB/classified"
  drive tree-placeholder    1 'carries a placeholder'           --tree "$SB/placeholder"
  drive fixture-verdict     1 'did not reach the verdict R19 requires' --root "$SB/no-lifecycle" --fixture "$FIX_FAIL"

  drive tree-not-a-dir      2 'names something that is not a directory' --tree "$SB/a-file"
  drive tree-bad-config     2 'could not be read as JSON'       --tree "$SB/bad-config"
  drive tree-store-not-dir  2 'is UNKNOWN, not zero'            --tree "$SB/store-not-dir"
  drive tree-shallow        2 'SHALLOW clone'                   --tree "$SB/shallow"
  drive fixture-missing     2 'no fixture directory at'         --root "$SB/no-lifecycle" --fixture "$SB/no-such-fixture"
  drive fixture-empty       2 'holds no case directory'         --root "$SB/no-lifecycle" --fixture "$SB/fixture-empty"
  drive fixture-premise     2 'The case was never tested'       --root "$SB/no-lifecycle" --fixture "$FIX_BAD"
  drive fixture-emptystore  2 'swept an empty set'              --root "$SB/no-lifecycle" --fixture "$FIX_EMPTYSTORE"
  drive bad-option          2 'unknown option'                  --no-such-option

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
  printf '  R39 for this tool: the self-test exists, reaches 0, 1 and 2 in BOTH modes, and every case asserts which refusal or which verdict it produced as well as which code.\n'
  printf '  NOT ASSERTED: the REFUSED path for an assertion no case exercises. Reaching it needs a fixture whose cases cover some of A1 to A6 and not others, and A5 and A6 are built unconditionally by this script rather than declared, so no fixture can leave them unexercised.\n'
  exit 0
fi

# The work tree, never the working directory. --root does not decide WHAT is
# examined - the fixture is found beside this script, so the case set is the
# same wherever this is invoked from - it decides what the printed paths are
# relative to, so nothing absolute reaches the committed result.
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-spec-home-stop.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# ---------------------------------------------------------------------------
# The detector. One tree in, TSV out. It reads and never writes.
#
#   PATH    <printable path>                     a file actually examined
#   INFO    home=reachable|unreachable  <why>    the premise, measured
#   INFO    records=<n>                          how many records the store holds
#   FINDING <class>  <path:line>  <sentence>     a violation, by location
#
# Exit 0 having reported, or 2 having refused. Never 0 on a tree it could not
# read: a store nobody could list is not a store with nothing in it.
# ---------------------------------------------------------------------------
cat > "$WORK/detect.py" <<'PY'
"""Decide, from local state only, whether one tree stopped or classified anyway."""
import json
import os
import posixpath
import re
import sys

tree, prefix = sys.argv[1], sys.argv[2]

CONFIG_REL = ".claude/productizer/config.json"
DEFAULT_SPEC = ".claude/productizer/spec.md"
STORE_REL = ".claude/productizer/classifications"

# The writer's own list, so a value it would refuse to write is a value this
# refuses to believe. A record whose provenance is a placeholder is a record
# that should not exist: an unreachable home yields no commit, and the answer
# to that is no record, not a record with the gap written into it.
PLACEHOLDERS = {
    "—", "–", "--", "-", "?", "??", "n/a", "na", "none", "null",
    "nil", "unknown", "unset", "tbd", "todo", "pending", "placeholder", "0",
}

RE_COMMIT = re.compile(r"^[0-9a-f]{40}$")

WHY_A3 = ("A record that cannot name the spec it was made against cannot show "
          "it was made against the live one.")


def die(message):
    sys.stderr.write("check-spec-home-stop: %s\n" % message)
    raise SystemExit(2)


def out(*fields):
    sys.stdout.write("\t".join(fields) + "\n")


def show(path):
    """Repo-relative, canonical, never absolute and never carrying a `..`
    segment - the runner matches these against the change set by exact text."""
    rel = posixpath.normpath(os.path.relpath(path, tree).replace(os.sep, "/"))
    if prefix:
        rel = posixpath.normpath(prefix + "/" + rel)
    if rel.startswith("..") or rel.startswith("/"):
        die("a path escaped the tree being examined. Refusing to print it: an "
            "unanchored path is one the runner cannot match and one that may "
            "name somebody's home directory.")
    return rel


if not os.path.isdir(tree):
    die("the tree to examine is not a directory. Unmeasured, not clean.")

# --- what the tree declares about its own spec home ------------------------
spec_rel = DEFAULT_SPEC
home = "(not declared)"
config_path = os.path.join(tree, CONFIG_REL)
if os.path.exists(config_path):
    try:
        with open(config_path, encoding="utf-8") as fh:
            cfg = json.load(fh)
    except (OSError, ValueError, UnicodeDecodeError) as exc:
        die("%s could not be read as JSON (%s). A config nobody can parse does "
            "not say where the spec home is - unmeasured, not reachable."
            % (show(config_path), exc.__class__.__name__))
    if not isinstance(cfg, dict):
        die("%s is not a JSON object, so it declares no spec home. Unmeasured."
            % show(config_path))
    out("PATH", show(config_path))
    spec = cfg.get("spec") if isinstance(cfg.get("spec"), dict) else {}
    declared = spec.get("path")
    if isinstance(declared, str) and declared.strip():
        spec_rel = declared.strip()
    product = cfg.get("product") if isinstance(cfg.get("product"), dict) else {}
    for key in ("spec_home", "spec_repo"):
        value = product.get(key)
        if isinstance(value, str) and value.strip():
            home = value.strip()
            break

if spec_rel.startswith("/") or ".." in spec_rel.split("/"):
    die("the declared `spec.path` leaves the tree. Refusing rather than "
        "reading a file the declaration does not actually name.")

out("INFO", "declared home=%s" % home, spec_rel)

# --- reachable, or not, decided locally ------------------------------------
spec_path = os.path.join(tree, spec_rel)
reachable = False
why = ""
if os.path.islink(spec_path) and not os.path.exists(spec_path):
    why = "a link at %s whose target is not there" % show(spec_path)
elif not os.path.exists(spec_path):
    why = "no file at %s" % show(spec_path)
elif not os.path.isfile(spec_path):
    why = "%s is not a regular file" % show(spec_path)
else:
    try:
        with open(spec_path, "rb") as fh:
            fh.read(1)
        reachable = True
    except OSError as exc:
        why = ("%s exists but cannot be read (%s)"
               % (show(spec_path), exc.strerror or exc.__class__.__name__))

if reachable:
    out("PATH", show(spec_path))
    out("INFO", "home=reachable", show(spec_path))
else:
    out("INFO", "home=unreachable", why)

# --- the store. Absent, unlistable and empty are three different answers ----
store = os.path.join(tree, STORE_REL)
records = []
if os.path.exists(store):
    if not os.path.isdir(store):
        die("%s exists and is not a directory, so how many classifications "
            "were recorded is UNKNOWN, not zero." % show(store))
    try:
        names = sorted(os.listdir(store))
    except OSError as exc:
        die("%s cannot be listed (%s). How many classifications were recorded "
            "is UNKNOWN, not zero - a directory nobody can open is exactly "
            "where the one made from a remembered copy hides."
            % (show(store), exc.strerror or exc.__class__.__name__))
    records = [n for n in names if n.endswith(".md")]

out("INFO", "records=%d" % len(records))

for name in records:
    path = os.path.join(store, name)
    out("PATH", show(path))
    # The caller needs to name this record to git without an absolute path
    # ever being printed, so the basename travels and the caller rebuilds the
    # path from the store it already knows.
    out("RECORD", name, show(path))
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        die("cannot read %s (%s). A record nobody could open is not a record "
            "that is fine." % (show(path), exc.__class__.__name__))

    # A2: the tree could not reach its own spec, and a classification exists.
    if not reachable:
        out("FINDING", "A2", "%s:1" % show(path),
            "a classification was recorded while the spec home was unreachable "
            "(%s). R19 says stop. A record made with no live spec to read was "
            "made against a remembered copy, and a classification made from a "
            "remembered copy can miss a contradiction the real spec would have "
            "caught." % why)

    # A3: the record cannot name the spec it was made against.
    hits = []
    for i, line in enumerate(text.split("\n")):
        if line.startswith("Spec commit:"):
            hits.append((i + 1, line.split(":", 1)[1].strip()))

    if not hits:
        out("FINDING", "A3", "%s:1" % show(path),
            "the record carries no `Spec commit` line at all, so it names no "
            "spec. " + WHY_A3)
        continue
    if len(hits) > 1:
        out("FINDING", "A3", "%s:%d" % (show(path), hits[1][0]),
            "the record carries %d `Spec commit` lines, so which spec it names "
            "is undefined. %s" % (len(hits), WHY_A3))
        continue

    lineno, value = hits[0]
    if not value:
        out("FINDING", "A3", "%s:%d" % (show(path), lineno),
            "the record's `Spec commit` is blank. " + WHY_A3)
    elif value.lower() in PLACEHOLDERS:
        out("FINDING", "A3", "%s:%d" % (show(path), lineno),
            "the record's `Spec commit` carries a placeholder rather than a "
            "measurement. An unreachable spec home yields no commit, and the "
            "answer to that is no record - not a record with the gap written "
            "in. " + WHY_A3)
    elif not RE_COMMIT.match(value):
        out("FINDING", "A3", "%s:%d" % (show(path), lineno),
            "the record's `Spec commit` is not a 40-character lowercase hex "
            "commit sha, so it resolves to no commit. " + WHY_A3)
PY

# ---------------------------------------------------------------------------
# Running the detector once, and reading back what it said.
# ---------------------------------------------------------------------------
D_HOME=""; D_WHY=""; D_RECORDS=""; D_TOTAL=0; D_A2=0; D_A3=0

# ---------------------------------------------------------------------------
# THE TIMELINE. 1.0 read a tree's STATE, and a state has no clock in it.
#
# In a tree whose spec home is unreachable, 1.0 called EVERY record a
# violation. But a record written on Tuesday, when the home worked, and a
# record written on Thursday, after it broke, are not the same event: only the
# second was classified against a remembered copy. A check that cannot tell
# them apart calls a correct lifecycle guilty for a breakage that happened
# afterwards, and a check that cries wolf gets switched off.
#
# Git knows both dates, and they are not read as dates. `merge-base
# --is-ancestor` is ancestry, and ancestry is what "before" means in a history
# where committer clocks disagree and a rebase rewrites them.
#
#   the commit that DELETED the spec path   the breakage
#   the OLDEST commit touching the record   when the record was written
#
# If the record's commit is an ancestor of the breakage, the record predates
# it: reported as a note, never as a finding.
#
# EVERY WAY THE TIMELINE CANNOT BE READ LEAVES THE FINDING STANDING, and says
# so. Not a work tree, the spec path never deleted in this history, the record
# untracked: each of those means the timeline was NOT APPLIED, and a finding
# this check cannot date is a finding it still holds. Downgrading on an
# unreadable timeline would turn every untracked tree into an alibi.
#
# A SHALLOW CLONE IS REFUSED, NOT PASSED. It holds neither commit, so every
# record would look undateable for a reason about the clone.
# ---------------------------------------------------------------------------
git_top() { # <dir> -> the work tree top, or nothing
  # stderr-ok: git's own diagnosis when this is not a work tree IS the answer
  # to "can the timeline be read here"; hiding it would make "no history" and
  # "a git that failed" the same empty string.
  local top
  if top="$(git -C "$1" rev-parse --show-toplevel)"; then
    printf '%s' "$top"
  fi
}

apply_timeline() { # <tree>
  local tree top shallow del rec rc name shown line cls loc text kept
  tree="$1"
  if [ -z "$SPEC_IN_TREE" ]; then
    D_TIMELINE="not applied - the tree declared no spec path, so there is no path whose deletion could be the breakage"
    return 0
  fi
  top="$(git_top "$tree")"
  if [ -z "$top" ]; then
    D_TIMELINE="not applied - this tree is not inside a git work tree, so nothing here dates a record against the breakage"
    return 0
  fi

  shallow="unknown"
  if shallow="$(git -C "$top" rev-parse --is-shallow-repository)"; then :; fi
  [ "$shallow" != "true" ] ||
    die_unmeasured "the tree being examined sits in a SHALLOW clone. Neither the commit that broke the spec home nor the commit that wrote a record is reachable, so a record cannot be dated against the breakage at all - UNKNOWN, not innocent and not guilty. Fetch full history (fetch-depth: 0) and re-run."

  # The commit that removed the spec path. `git log` exits 0 and prints
  # nothing when the path was never deleted, so an empty result is an answer
  # and is read as one.
  del="$(git -C "$top" log --diff-filter=D --format=%H -1 -- "$tree/$SPEC_IN_TREE")"
  if [ -z "$del" ]; then
    D_TIMELINE="not applied - this history holds no commit that deleted the spec path, so there is no breakage to date a record against. Every record's finding stands."
    return 0
  fi

  kept="$WORK/findings.kept"
  : > "$kept"
  while IFS="$(printf '\t')" read -r cls loc text; do
    [ -n "$cls" ] || continue
    if [ "$cls" != "A2" ]; then
      printf '%s\t%s\t%s\n' "$cls" "$loc" "$text" >> "$kept"
      continue
    fi
    name=""
    while IFS="$(printf '\t')" read -r rec shown; do
      [ -n "$rec" ] || continue
      case "$loc" in "$shown":*) name="$rec" ;; esac
    done < "$WORK/records.txt"
    if [ -z "$name" ]; then
      printf '%s\t%s\t%s\n' "$cls" "$loc" "$text" >> "$kept"
      continue
    fi
    # The OLDEST commit touching this record is when it was written.
    line="$(git -C "$top" log --format=%H -- "$tree/$STORE_IN_TREE/$name" | tail -1)"
    if [ -z "$line" ]; then
      printf '%s\t%s\t%s\n' "$cls" "$loc" "$text" >> "$kept"
      continue
    fi
    rc=0
    if [ "$line" = "$del" ]; then
      # A record written IN the very commit that broke the home is not a
      # record that predates the breakage - `--is-ancestor` calls a commit its
      # own ancestor, which would make the worst case look like the innocent
      # one. Measured, not reasoned: the first build of this said `before` for
      # a record added in the deletion commit, and the constructed history
      # caught it.
      rc=1
    else
      # A non-zero exit here is the ANSWER - "not an ancestor" - and not a
      # failure, so it is taken as a value rather than allowed to end the run.
      git -C "$top" merge-base --is-ancestor "$line" "$del" || rc=$?
    fi
    case "$rc" in
      0)
        D_PREDATE=$((D_PREDATE + 1))
        D_A2=$((D_A2 - 1))
        D_TOTAL=$((D_TOTAL - 1))
        printf '  timeline %s: this record was committed BEFORE the commit that made the spec home unreachable, so it was not classified against a remembered copy. Not a finding.\n' "$loc"
        ;;
      1)
        printf '%s\t%s\t%s\n' "$cls" "$loc" "$text" >> "$kept"
        ;;
      *)
        die_unmeasured "git merge-base --is-ancestor exited $rc while dating a record against the breakage, so whether that record predates it is UNKNOWN - not before, and not after."
        ;;
    esac
  done < "$WORK/findings.txt"
  mv "$kept" "$WORK/findings.txt"
  D_TIMELINE="applied - $D_PREDATE record(s) predate the breakage and are not findings"
}

run_detector() { # <tree> <printable prefix>
  local rc=0
  python3 "$WORK/detect.py" "$1" "$2" > "$WORK/detect.tsv" || rc=$?
  [ "$rc" -eq 0 ] ||
    die_unmeasured "the tree could not be examined (see the reason above). Unmeasured, and never a pass."

  D_HOME=""; D_WHY=""; D_RECORDS=""; D_TOTAL=0; D_A2=0; D_A3=0
  D_PREDATE=0; D_TIMELINE="not applied"; SPEC_IN_TREE=""
  : > "$WORK/findings.txt"
  : > "$WORK/records.txt"
  local kind a b c
  while IFS="$(printf '\t')" read -r kind a b c; do
    case "$kind" in
      PATH)
        # Coverage lines name files IN THIS REPOSITORY. A constructed
        # history lives in a temporary directory, and printing its paths
        # bare would declare coverage for files the runner cannot match
        # and that nobody can open after the run.
        if [ "$EMIT_PATHS" -eq 1 ]; then printf '%s\n' "$a"; else printf '    constructed: %s\n' "$a"; fi ;;
      RECORD) printf '%s\t%s\n' "$a" "$b" >> "$WORK/records.txt" ;;
      INFO)
        case "$a" in
          home=*)    D_HOME="${a#home=}"; D_WHY="$b" ;;
          records=*) D_RECORDS="${a#records=}" ;;
          "declared home="*)
            SPEC_IN_TREE="$b"
            printf '  declared home: %s, spec path %s\n' "${a#declared home=}" "$b" ;;
        esac
        ;;
      FINDING)
        D_TOTAL=$((D_TOTAL + 1))
        case "$a" in
          A2) D_A2=$((D_A2 + 1)) ;;
          A3) D_A3=$((D_A3 + 1)) ;;
        esac
        printf '%s\t%s\t%s\n' "$a" "$b" "$c" >> "$WORK/findings.txt"
        ;;
    esac
  done < "$WORK/detect.tsv"

  [ -n "$D_HOME" ] && [ -n "$D_RECORDS" ] ||
    die_unmeasured "the detector reported no home state or no record count for this tree. Unmeasured."

  if [ "$D_HOME" = "unreachable" ] && [ "$D_A2" -gt 0 ]; then
    apply_timeline "$1"
  fi
}

print_findings() { # <label>
  local cls loc text
  while IFS="$(printf '\t')" read -r cls loc text; do
    [ -n "$cls" ] || continue
    printf '  %s %s: %s: %s\n' "$1" "$cls" "$loc" "$text"
  done < "$WORK/findings.txt"
}

# ---------------------------------------------------------------------------
# --tree: one tree, its own verdict, nothing declared to compare against.
# ---------------------------------------------------------------------------
if [ -n "$TREE" ]; then
  # The basename only: this message can reach a committed result file, and a
  # path typed on the command line is somebody's home directory more often
  # than not.
  [ -d "$TREE" ] || die_unmeasured "--tree names something that is not a directory: ${TREE##*/}"
  run_detector "$TREE" ""
  printf '  spec home: %s%s\n' "$D_HOME" "$([ -n "$D_WHY" ] && printf ' — %s' "$D_WHY")"
  printf '  classification records: %s\n' "$D_RECORDS"
  printf '  timeline: %s\n' "$D_TIMELINE"
  print_findings "detected"
  printf '  findings: %d (A2 %d, A3 %d)\n' "$D_TOTAL" "$D_A2" "$D_A3"
  if [ "$D_TOTAL" -gt 0 ]; then
    printf 'FAIL: R19 is violated in this tree - a classification exists that cannot be shown to have been made against the live spec.\n' >&2
    exit 1
  fi
  if [ "$D_HOME" = "unreachable" ]; then
    printf '  R19 obeyed: the spec home is unreachable and nothing was classified. The lifecycle stopped.\n'
  else
    printf '  the spec home is reachable, so R19 was not in force here; every record present names a spec it could have been made against.\n'
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# The declared cases.
# ---------------------------------------------------------------------------
[ -d "$FIXTURE" ] ||
  die_unmeasured "no fixture directory at ${FIXTURE##*/}; the constructed cases are missing, which is unmeasured and not a pass"

rel_to_root() {
  case "$1" in
    "$ROOT"/*) printf '%s' "${1#"$ROOT"/}" ;;
    *)         printf '%s' "$(basename "$(dirname "$1")")/$(basename "$1")" ;;
  esac
}

field() { # <key> <file>
  awk -v k="$1" 'index($0, k ": ") == 1 { sub(/^[^:]*:[ \t]*/, ""); print; exit }' "$2"
}

A1_EX=0; A1_UP=0
A2_EX=0; A2_UP=0
A3_EX=0; A3_UP=0
A4_EX=0; A4_UP=0

bump() { # <class> <ex|up>
  case "$1:$2" in
    A1:ex) A1_EX=$((A1_EX + 1)) ;; A1:up) A1_UP=$((A1_UP + 1)) ;;
    A2:ex) A2_EX=$((A2_EX + 1)) ;; A2:up) A2_UP=$((A2_UP + 1)) ;;
    A3:ex) A3_EX=$((A3_EX + 1)) ;; A3:up) A3_UP=$((A3_UP + 1)) ;;
    A4:ex) A4_EX=$((A4_EX + 1)) ;; A4:up) A4_UP=$((A4_UP + 1)) ;;
    *) die_unmeasured "a case declares assertion '$1', which this check does not implement. Unmeasured." ;;
  esac
}

cases=0
failed=0

for CASE_DIR in "$FIXTURE"/*/; do
  # An unmatched glob arrives as its own literal text, so test the path.
  [ -d "$CASE_DIR" ] || continue
  CASE_DIR="${CASE_DIR%/}"
  DECL="$CASE_DIR/case.txt"
  [ -f "$DECL" ] && [ -r "$DECL" ] ||
    die_unmeasured "$(rel_to_root "$CASE_DIR") has no readable case.txt. A case that does not declare what it constructs cannot have its premise checked, and an unchecked premise is how a case comes to test nothing."

  cases=$((cases + 1))
  CASE_REL="$(rel_to_root "$CASE_DIR")"
  printf '%s\n' "$(rel_to_root "$DECL")"

  NAME="$(field Case "$DECL")"
  ASSERTS="$(field Asserts "$DECL")"
  WANT_HOME="$(field Home "$DECL")"
  WANT_RECORDS="$(field Records "$DECL")"
  EXPECT="$(field Expect "$DECL")"
  WANT_FINDINGS="$(field Findings "$DECL")"

  printf '  case %s: %s\n' "${CASE_DIR##*/}" "$NAME"

  case "$WANT_HOME" in unreachable|reachable) ;; *) die_unmeasured "$CASE_REL/case.txt declares Home: '$WANT_HOME', which is neither reachable nor unreachable." ;; esac
  case "$EXPECT" in clean|finding) ;; *) die_unmeasured "$CASE_REL/case.txt declares Expect: '$EXPECT', which is neither clean nor finding." ;; esac
  case "$WANT_RECORDS" in ''|*[!0-9]*) die_unmeasured "$CASE_REL/case.txt declares Records: '$WANT_RECORDS', which is not a whole number." ;; esac
  case "$WANT_FINDINGS" in ''|*[!0-9]*) die_unmeasured "$CASE_REL/case.txt declares Findings: '$WANT_FINDINGS', which is not a whole number." ;; esac
  case "$ASSERTS" in A1|A2|A3|A4) ;; *) die_unmeasured "$CASE_REL/case.txt declares Asserts: '$ASSERTS', which is not one of A1 A2 A3 A4." ;; esac

  run_detector "$CASE_DIR" "$CASE_REL"

  # --- the premise, measured against what the case says it constructed -----
  if [ "$D_HOME" != "$WANT_HOME" ]; then
    die_unmeasured "$CASE_REL declares its spec home $WANT_HOME and it measures as $D_HOME (${D_WHY:-no reason given}). The case was never tested, so assertion $ASSERTS was never exercised. Unmeasured, not a pass."
  fi
  if [ "$D_RECORDS" != "$WANT_RECORDS" ]; then
    if [ "$WANT_RECORDS" != "0" ] && [ "$D_RECORDS" = "0" ]; then
      die_unmeasured "$CASE_REL declares $WANT_RECORDS classification record(s) and its store holds none, so assertion $ASSERTS swept an empty set. An assertion with no positive case to fire on holds vacuously forever. Unmeasured, not a pass."
    fi
    die_unmeasured "$CASE_REL declares $WANT_RECORDS classification record(s) and its store holds $D_RECORDS. The case is not the case it says it is; what was exercised is unknown."
  fi

  bump "$ASSERTS" ex

  printf '  spec home: %s%s\n' "$D_HOME" "$([ -n "$D_WHY" ] && printf ' — %s' "$D_WHY")"
  printf '  classification records: %s\n' "$D_RECORDS"
  printf '  timeline: %s\n' "$D_TIMELINE"
  print_findings "detected"

  # --- the verdict the detector actually reached ---------------------------
  observed_class=0
  case "$ASSERTS" in
    A2) observed_class="$D_A2" ;;
    A3) observed_class="$D_A3" ;;
    *)  observed_class="$D_TOTAL" ;;
  esac

  held=1
  if [ "$D_TOTAL" -ne "$WANT_FINDINGS" ]; then held=0; fi
  if [ "$EXPECT" = "finding" ] && [ "$D_TOTAL" -eq 0 ]; then held=0; fi
  if [ "$EXPECT" = "clean" ] && [ "$D_TOTAL" -ne 0 ]; then held=0; fi
  if [ "$EXPECT" = "finding" ] && [ "$observed_class" -ne "$WANT_FINDINGS" ]; then held=0; fi

  if [ "$EXPECT" = "finding" ]; then
    WANTED="$WANT_FINDINGS finding(s), all of class $ASSERTS"
  else
    WANTED="clean - no finding of any class"
  fi

  if [ "$held" -eq 1 ]; then
    bump "$ASSERTS" up
    printf '  held: %s — expected %s; observed %d finding(s) (A2 %d, A3 %d)\n' \
      "$ASSERTS" "$WANTED" "$D_TOTAL" "$D_A2" "$D_A3"
  else
    failed=$((failed + 1))
    printf '  FINDING: did not hold - %s expected %s; observed %d finding(s) (A2 %d, A3 %d)\n' \
      "$ASSERTS" "$WANTED" "$D_TOTAL" "$D_A2" "$D_A3"
  fi
done


# ---------------------------------------------------------------------------
# A5 AND A6: THE TIMELINE, ON A HISTORY BUILT FOR THE PURPOSE.
#
# 1.0 read a tree's STATE. In an unreachable-home tree every record was a
# finding, and a record written before the home broke was indistinguishable
# from one written after. These two assertions are the difference, and they
# need a HISTORY rather than a tree, so they are built rather than committed:
# a case directory under `fixtures/` cannot carry a git history of its own
# inside this repository.
#
#   A5  a record committed BEFORE the breakage -> NOT a finding
#   A6  a record committed AFTER the breakage  -> a finding
#
# ONE HISTORY EXERCISES BOTH, and it is the same construction twice over:
# commit one has a reachable home and a record; commit two deletes the spec
# and adds a second record. The two records differ in exactly one thing -
# which side of the deletion they were written on - which is the two-tree
# experiment moved onto the time axis.
#
# Nothing is written into the repository under examination: the history is
# built in the temporary directory this run already owns and removed with it.
# ---------------------------------------------------------------------------
A5_EX=0; A5_UP=0
A6_EX=0; A6_UP=0

# Both records are WELL FORMED on purpose - a valid 40-hex commit and a hash -
# so A3 cannot fire on either and the only thing separating the two histories
# is which side of the deletion the record was written on.
write_record() { # <dir> <name>
  cat > "$1/$STORE_IN_TREE/$2.md" <<REC
Intent: $2
Classification: extend
Recorded: 2026-01-01
Spec path: .claude/productizer/spec.md
Spec commit: 0123456789abcdef0123456789abcdef01234567
Spec hash: sha256:0000000000000000000000000000000000000000000000000000000000000000
In scope count: 1

## Requirement ids in scope

R1
REC
}

# build_timeline_repo <dir> <before|after>
#
# TWO histories, not one, and that is the point. On a single history holding
# both records, "one was spared" and "one was not" are two readings of one
# number, so any break moves both and neither can be falsified alone. One
# record per history separates them: the never-spare break reddens A5 only,
# the always-spare break reddens A6 only.
build_timeline_repo() {
  local dir side
  dir="$1"; side="$2"
  mkdir -p "$dir/$STORE_IN_TREE"
  cat > "$dir/.claude/productizer/config.json" <<'JSON'
{"product": {"spec_home": "example/home-repo"}, "spec": {"path": ".claude/productizer/spec.md"}}
JSON
  printf '# Living spec — timeline case\n\n## Requirements\n\n- **R1** — The lifecycle shall stop.\n' \
    > "$dir/.claude/productizer/spec.md"
  git -c init.defaultBranch=main init -q "$dir"
  git -C "$dir" config user.email "fixture@example.invalid"
  git -C "$dir" config user.name "spec-home-stop timeline"
  if [ "$side" = "before" ]; then
    write_record "$dir" rec
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "the home is reachable and one classification is recorded"
    rm -f "$dir/.claude/productizer/spec.md"
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "the spec home breaks, and nothing is classified afterwards"
  else
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "the home is reachable and nothing is classified"
    rm -f "$dir/.claude/productizer/spec.md"
    write_record "$dir" rec
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "the spec home breaks, and a classification is recorded anyway"
  fi
}

# run_timeline_case <label> <before|after> - guards the construction, then
# reports what the detector made of it. A construction that did not come out
# as constructed exercised nothing, which is exit 2 and never a pass.
run_timeline_case() {
  local label side dir
  label="$1"; side="$2"
  dir="$WORK/timeline-$side"
  build_timeline_repo "$dir" "$side"
  printf 'constructed history: %s\n' "$label"
  EMIT_PATHS=0
  run_detector "$dir" ""
  EMIT_PATHS=1
  printf '  spec home: %s%s\n' "$D_HOME" "$([ -n "$D_WHY" ] && printf ' — %s' "$D_WHY")"
  printf '  classification records: %s\n' "$D_RECORDS"
  printf '  timeline: %s\n' "$D_TIMELINE"
  print_findings "detected"

  [ "$D_HOME" = "unreachable" ] ||
    die_unmeasured "the constructed history '$side' measures its spec home as $D_HOME after the deletion commit, so the assertion it carries was never exercised. Unmeasured, not a pass."
  [ "$D_RECORDS" = "1" ] ||
    die_unmeasured "the constructed history '$side' holds $D_RECORDS record(s) and not the 1 it was built with, so what was exercised is unknown."
  case "$D_TIMELINE" in
    applied*) ;;
    *) die_unmeasured "the timeline was NOT APPLIED to the constructed history '$side' ($D_TIMELINE), so the assertion it carries swept an empty set. An assertion with nothing to fire on holds vacuously forever." ;;
  esac
}

# --- A5: the record was written before the home broke ------------------------
run_timeline_case "one record, committed BEFORE the spec home broke" before
A5_EX=$((A5_EX + 1))
if [ "$D_PREDATE" -eq 1 ] && [ "$D_TOTAL" -eq 0 ]; then
  A5_UP=$((A5_UP + 1))
  printf '  held: A5 — expected the record to be spared and no finding to remain; 1 spared, 0 findings\n'
else
  failed=$((failed + 1))
  printf '  FINDING: did not hold - A5 expected 1 record spared and 0 findings; observed %d spared, %d finding(s) (A2 %d, A3 %d)\n' \
    "$D_PREDATE" "$D_TOTAL" "$D_A2" "$D_A3"
fi

# --- A6: the record was written after it -------------------------------------
# A5's inverse, and mandatory: a timeline that only ever spares records is a
# detector switched off, and it would pass A5 on its own.
run_timeline_case "one record, committed AFTER the spec home broke" after
A6_EX=$((A6_EX + 1))
if [ "$D_A2" -eq 1 ] && [ "$D_PREDATE" -eq 0 ] && [ "$D_A3" -eq 0 ]; then
  A6_UP=$((A6_UP + 1))
  printf '  held: A6 — expected 1 finding of class A2 and nothing spared; observed A2 %d, spared %d\n' "$D_A2" "$D_PREDATE"
else
  failed=$((failed + 1))
  printf '  FINDING: did not hold - A6 expected exactly 1 A2 finding, 0 spared and no A3; observed A2 %d, spared %d, A3 %d\n' \
    "$D_A2" "$D_PREDATE" "$D_A3"
fi

# ---------------------------------------------------------------------------
# A7: THIS REPOSITORY.
#
# Every assertion above this line is about a fixture or a construction. Whether
# THIS repository stopped was asserted by nothing, which is a check measuring
# its own test data and calling the result compliance.
#
# A7 IS CONDITIONAL, AND SAYS SO OUT LOUD WHEN IT DOES NOT FIRE. R19's trigger
# is an unreachable spec home. This repository's home is reachable, so the
# requirement is not in force here and A7 renders NO verdict on the stop - it
# reports that it did not fire. Printing `A7 held` there would be a vacuous
# hold, which is the exact defect this file was written to stop repeating.
#
# What it DOES assert unconditionally is the other half: a record in this
# repository that cannot name the spec it was made against is a finding here
# as much as in a fixture, whatever the home is doing.
# ---------------------------------------------------------------------------
A7_INFORCE=0; A7_UP=0
printf 'this repository\n'
# The premise A7 needs before anything: a root that actually runs this
# lifecycle. A directory with no `.claude/productizer` has not failed to
# stop - it has nothing to stop - and reporting a hold there would be a
# vacuous hold wearing this repository'"'"'s name.
if [ ! -d "$ROOT/.claude/productizer" ]; then
  printf '  A7 NOT APPLICABLE: this root holds no .claude/productizer, so it does not run this lifecycle and there is nothing here to stop. Nothing asserted.\n'
else
run_detector "$ROOT" ""
printf '  spec home: %s%s\n' "$D_HOME" "$([ -n "$D_WHY" ] && printf ' — %s' "$D_WHY")"
printf '  classification records: %s\n' "$D_RECORDS"
printf '  timeline: %s\n' "$D_TIMELINE"
print_findings "detected"

if [ "$D_HOME" = "unreachable" ]; then
  A7_INFORCE=1
  if [ "$D_A2" -eq 0 ]; then
    A7_UP=1
    printf '  held: A7 — this repository'"'"'s spec home is unreachable and no classification was recorded against a remembered copy\n'
  else
    failed=$((failed + 1))
    printf '  FINDING: did not hold - A7: this repository'"'"'s spec home is unreachable and %d classification(s) were recorded anyway\n' "$D_A2"
  fi
else
  printf '  A7 DID NOT FIRE: this repository'"'"'s spec home is reachable, so R19'"'"'s trigger never came about and this run renders NO verdict on whether this repository would stop. Not a pass - nothing was asserted.\n'
fi

if [ "$D_A3" -gt 0 ]; then
  failed=$((failed + 1))
  printf '  FINDING: %d record(s) in this repository cannot name the spec they were made against. That is a finding whatever the home is doing.\n' "$D_A3"
else
  printf '  A3 over this repository: %s record(s) examined, none unable to name its spec commit\n' "$D_RECORDS"
fi
fi


[ "$cases" -gt 0 ] ||
  die_unmeasured "the fixture holds no case directory, so nothing about R19 was exercised. An empty case set is unmeasured, not clean."

printf 'cases examined: %d\n' "$cases"
printf 'assertion A1 (unreachable home, nothing classified -> clean): exercised %d, upheld %d\n' "$A1_EX" "$A1_UP"
printf 'assertion A2 (unreachable home, a classification recorded anyway -> finding): exercised %d, upheld %d\n' "$A2_EX" "$A2_UP"
printf 'assertion A3 (a record that cannot name its spec commit -> finding): exercised %d, upheld %d\n' "$A3_EX" "$A3_UP"
printf 'assertion A4 (reachable home, a well-formed record -> clean): exercised %d, upheld %d\n' "$A4_EX" "$A4_UP"
printf 'assertion A5 (a record committed BEFORE the breakage -> not a finding): exercised %d, upheld %d\n' "$A5_EX" "$A5_UP"
printf 'assertion A6 (a record committed AFTER the breakage -> a finding): exercised %d, upheld %d\n' "$A6_EX" "$A6_UP"
if [ "$A7_INFORCE" -eq 1 ]; then
  printf 'assertion A7 (THIS repository stopped): in force - its spec home is unreachable; upheld %d\n' "$A7_UP"
else
  printf 'assertion A7 (THIS repository stopped): NOT IN FORCE and therefore NOT ASSERTED - its spec home is reachable, so R19 never triggered here. This run says nothing about whether this repository would stop, and does not pretend otherwise.\n'
fi

if [ "$failed" -gt 0 ]; then
  printf 'FAIL: %d case(s) did not reach the verdict R19 requires. An unreachable spec home no longer stops a classification, or the detector fires where it must not.\n' "$failed" >&2
  exit 1
fi

# An assertion nothing exercised held vacuously, and a vacuous hold reported as
# a pass is the failure this file was written to avoid repeating.
unexercised=""
[ "$A1_EX" -gt 0 ] || unexercised="$unexercised A1"
[ "$A2_EX" -gt 0 ] || unexercised="$unexercised A2"
[ "$A3_EX" -gt 0 ] || unexercised="$unexercised A3"
[ "$A4_EX" -gt 0 ] || unexercised="$unexercised A4"
[ "$A5_EX" -gt 0 ] || unexercised="$unexercised A5"
[ "$A6_EX" -gt 0 ] || unexercised="$unexercised A6"
if [ -n "$unexercised" ]; then
  printf 'REFUSED: no case exercised%s. An assertion with nothing to fire on holds vacuously, and this run asserts nothing about it - unmeasured, not clean.\n' "$unexercised" >&2
  exit 2
fi

if [ "$A7_INFORCE" -eq 1 ]; then
  SAYS_REPO="this repository's own spec home is unreachable and it stopped (A7)"
else
  SAYS_REPO="this repository's spec home is reachable, so A7 rendered NO verdict on it - the pass below is about the constructed cases and NOT a statement that this repository would stop"
fi
printf 'PASS: %d constructed cases and one built history. An unreachable spec home with nothing classified is clean (A1); the same tree with one classification recorded is a finding (A2); a record that cannot name its spec commit is a finding (A3); a reachable home with a well-formed record stays clean (A4); a record committed before the home broke is spared (A5) and one committed after it is not (A6). %s.\n' "$cases" "$SAYS_REPO"
