#!/usr/bin/env bash
# record-classification.sh [--version] [--help] [--selftest]
#                          --intent ID --classification VALUE
#                          [--root DIR] [--spec-path PATH] [--store DIR]
#
# Writes the provenance record for one intake classification: the spec commit
# and content hash it was made against, every active requirement id that was in
# scope, the intent's identifier, and the single classification value.
#
# WHY A RECORD AT ALL. Two acceptance rows share this one mechanism.
#
#   R6  When an intent arrives, the lifecycle shall classify it against the
#       WHOLE living spec as exactly one of extend, refine, duplicate or
#       contradict.
#
#       A graded eval scored 16/16 on outcomes, which is equally consistent
#       with a classifier that saw half the spec and got lucky on a small one.
#       Outcomes cannot tell those apart; the ids that were in front of it can.
#
#   R19 If the spec home is unreachable, then the lifecycle shall stop rather
#       than classify against a remembered copy.
#
#       Made mechanical here rather than written as a rule: an unreachable spec
#       home yields no hash, this script refuses to emit a record without one,
#       and the check refuses a record that has none. Classifying from a
#       remembered copy stops being forbidden and starts being impossible to
#       RECORD, which is the only half a script can enforce.
#
# THE REFUSAL PATH IS THE POINT. Every reason the spec home might not be
# readable ends the same way - exit 2, nothing written, no partial file:
#
#   the spec file is missing, or cannot be read
#   the work tree is not a git repository, so there is no commit to cite
#   the spec is not tracked at HEAD, so `git show` has nothing to hash
#   the spec in the work tree differs from the spec at HEAD
#
# THE LAST ONE DESERVES ITS SENTENCE. A record cites a commit, and the check
# rehashes the spec AT that commit. A classification made against uncommitted
# edits could never be verified against anything, so the record would be
# unfalsifiable - which is the same as no record. Commit the spec, then
# classify against it.
#
# The record is built in a temporary directory and moved into place in one
# step, so an interrupted run leaves the store exactly as it found it.
#
# EXACTLY ONE CLASSIFICATION PER INTENT is enforced at the filename: the record
# is named for the intent, so a second classification of the same intent is a
# collision this script refuses rather than a second file nobody notices.
#
# THE INTENT'S ID, NEVER ITS WORDS. An intent is text a stranger can write - on
# a public repo anyone can open an issue - and this store is committed and read
# back into a model's context. The identifier is checked against a closed shape
# before it is written, and nothing else from the intent is recorded here.
#
# PORTABILITY. Developed on macOS/BSD. No GNU-only behaviour: no mapfile, no
# `grep -P`, no `date -d`, no in-place sed. Nothing suppresses stderr - an
# error and a genuine no-match look identical once it is discarded, and this
# script's whole job is telling those two apart.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  the record was written; its path is the last line of stdout
#   1  refused - a record for this intent already exists. The store already
#      holds exactly one classification for it, and that is the invariant
#      holding, not a crash.
#   2  could not run - bad usage, or NO HASH: an unreachable spec home, an
#      untracked spec, a work tree that disagrees with HEAD. Never a record
#      with a blank or placeholder hash.
set -euo pipefail

# Byte-identical output across runs and machines: collation, number formatting
# and case folding all follow the locale otherwise.
export LC_ALL=C

VERSION="record-classification 1.1"

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/classification-record.py"

ROOT=""
SPEC_REL=".claude/productizer/spec.md"
STORE_REL=".claude/productizer/classifications"
INTENT=""
CLASSIFICATION=""
SELFTEST=""

usage() {
  printf 'usage: record-classification.sh --intent ID --classification VALUE\n'
  printf '                                [--root DIR] [--spec-path PATH] [--store DIR]\n'
  printf '       record-classification.sh --selftest\n'
  printf '  --intent ID          the tracker key or identifier of the intent (#123, PROJ-123)\n'
  printf '  --classification V   exactly one of extend, refine, duplicate, contradict\n'
  printf '  --root DIR           the repo work tree. Defaults to the git top level,\n'
  printf '                       never to the working directory.\n'
  printf '  --spec-path PATH     spec location relative to the root, NOT to the working\n'
  printf '                       directory (default .claude/productizer/spec.md). An\n'
  printf '                       absolute path must lie inside the root.\n'
  printf '  --store DIR          record store relative to the root, NOT to the working\n'
  printf '                       directory (default .claude/productizer/classifications).\n'
  printf '                       An absolute path is used as given.\n'
  printf '  --selftest           run the cases in throwaway repositories and exit\n'
}

die_unmeasured() { printf 'record-classification: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --selftest|--self-test) SELFTEST=1; shift ;;
    --intent) [ "$#" -ge 2 ] || die_unmeasured "--intent needs an identifier"; INTENT="$2"; shift 2 ;;
    --intent=*) INTENT="${1#--intent=}"; shift ;;
    --classification) [ "$#" -ge 2 ] || die_unmeasured "--classification needs a value"; CLASSIFICATION="$2"; shift 2 ;;
    --classification=*) CLASSIFICATION="${1#--classification=}"; shift ;;
    --root) [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"; ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --spec-path) [ "$#" -ge 2 ] || die_unmeasured "--spec-path needs a path"; SPEC_REL="$2"; shift 2 ;;
    --spec-path=*) SPEC_REL="${1#--spec-path=}"; shift ;;
    --store) [ "$#" -ge 2 ] || die_unmeasured "--store needs a path"; STORE_REL="$2"; shift 2 ;;
    --store=*) STORE_REL="${1#--store=}"; shift ;;
    -*) printf 'record-classification: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'record-classification: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# --------------------------------------------------------------- --selftest
#
# Every case is a throwaway repository under one temporary directory, removed
# on every exit path. The writer is run from a working directory OUTSIDE the
# repository it is pointed at, because that is the layout B132 was measured in:
# a record printed as the clone's and written into whatever repository the
# caller stood in. A case run from inside the root cannot tell a path joined to
# the root from one resolved against the working directory - they are the same
# directory there.
if [ -n "$SELFTEST" ]; then
  command -v git >/dev/null ||
    die_unmeasured "git is not on PATH, and every case in this self-test is a git repository"
  SELF="$HERE/$(basename "$0")"
  T="$(mktemp -d "${TMPDIR:-/tmp}/record-classification-selftest.XXXXXX")" ||
    die_unmeasured "cannot create a temporary directory to build the self-test corpus in"
  trap 'rm -rf "$T"' EXIT HUP INT TERM
  G() { git -c user.email=selftest@example.invalid -c user.name=selftest "$@"; }

  # fixture <dir> - a committed repository with a two-requirement spec.
  fixture() {
    mkdir -p "$1/.claude/productizer"
    printf '# Fixture spec\n\n## Requirements\n\n- **R1** - the lifecycle shall do the first thing.\n- **R2** - the lifecycle shall do the second thing.\n' \
      > "$1/.claude/productizer/spec.md"
    G init -q "$1"
    G -C "$1" add -A
    G -C "$1" commit -q -m "fixture spec"
  }

  CASES=0; FAILED=0; CODES=""
  # check <name> <expected exit> <observed exit> <file holding the sentence> <sentence> <what>
  check() {
    CASES=$((CASES + 1))
    CODES="$CODES$3
"
    if [ "$3" = "$2" ] && grep -qF -- "$5" "$4"; then
      verdict="held"
    else
      verdict="NOT HELD"; FAILED=$((FAILED + 1))
    fi
    printf '    %-28s expected %s  got %s  %-8s %s\n' "$1" "$2" "$3" "$verdict" "$6"
  }
  # absent <name> <path> <what> - a path that must NOT exist after a case.
  absent() {
    CASES=$((CASES + 1))
    if [ -e "$2" ]; then
      verdict="NOT HELD"; FAILED=$((FAILED + 1))
    else
      verdict="held"
    fi
    printf '    %-28s %-28s %-8s %s\n' "$1" "absent" "$verdict" "$3"
  }

  printf '  selftest: %s\n' "$VERSION"
  REPO="$T/clone"; fixture "$REPO"
  OUT="$T/elsewhere"; mkdir -p "$OUT"
  STORE_DEF=".claude/productizer/classifications"

  # 1. B132: run from outside the root. The record lands in the root's store.
  got=0
  ( cd "$OUT" && bash "$SELF" --root "$REPO" --intent 1 --classification extend ) \
    > "$T/c1.out" 2> "$T/c1.err" || got=$?
  : > "$T/c1.where"
  [ -f "$REPO/$STORE_DEF/1.md" ] && printf 'written under the root\n' >> "$T/c1.where"
  [ "$(tail -n 1 "$T/c1.out")" = "$STORE_DEF/1.md" ] && printf 'printed exactly the path written\n' >> "$T/c1.where"
  check outside-root-default-store 0 "$got" "$T/c1.where" "written under the root" \
    "run from outside --root, the record is written in the root's store"
  check outside-root-prints-path 0 "$got" "$T/c1.where" "printed exactly the path written" \
    "and its last line of stdout is that path, repo-relative"
  absent outside-root-cwd-untouched "$OUT/.claude" \
    "and nothing is written relative to the working directory"

  # 2. A decoy store in the working directory holds the same intent. The
  # one-per-intent guard must read the root's store, not the decoy.
  REPO2="$T/clone2"; fixture "$REPO2"
  DECOY="$T/decoy"; mkdir -p "$DECOY/$STORE_DEF"
  printf 'Intent: 1\n' > "$DECOY/$STORE_DEF/1.md"
  got=0
  ( cd "$DECOY" && bash "$SELF" --root "$REPO2" --intent 1 --classification refine ) \
    > "$T/c2.out" 2> "$T/c2.err" || got=$?
  check guard-reads-root-store 0 "$got" "$REPO2/$STORE_DEF/1.md" "Classification: refine" \
    "a record of the same intent in the working directory is not this root's record"

  # 3. The same intent again, against the root - exactly one per intent.
  got=0
  ( cd "$OUT" && bash "$SELF" --root "$REPO" --intent 1 --classification refine ) \
    > "$T/c3.out" 2> "$T/c3.err" || got=$?
  check same-intent-refused 1 "$got" "$T/c3.err" "REFUSED: this intent is already classified" \
    "a second classification of the same intent is refused"

  # 4. A relative --store is joined to the root, not the working directory.
  got=0
  ( cd "$OUT" && bash "$SELF" --root "$REPO" --store "alt-store" --intent 2 --classification extend ) \
    > "$T/c4.out" 2> "$T/c4.err" || got=$?
  [ -f "$REPO/alt-store/2.md" ] && printf 'relative store under the root\n' >> "$T/c4.out"
  check relative-store-under-root 0 "$got" "$T/c4.out" "relative store under the root" \
    "--store alt-store from outside the root writes ROOT/alt-store"
  absent relative-store-cwd-untouched "$OUT/alt-store" \
    "and not ./alt-store"

  # 5. An absolute --store is used as given, and printed as written.
  got=0
  ( cd "$OUT" && bash "$SELF" --root "$REPO" --store "$T/abs-store" --intent 3 --classification extend ) \
    > "$T/c5.out" 2> "$T/c5.err" || got=$?
  check absolute-store-honoured 0 "$got" "$T/c5.out" "$T/abs-store/3.md" \
    "an absolute --store is written and printed as that absolute path"

  # 6. A relative --root from a sibling directory.
  got=0
  ( cd "$OUT" && bash "$SELF" --root "../clone" --intent 4 --classification duplicate ) \
    > "$T/c6.out" 2> "$T/c6.err" || got=$?
  check relative-root 0 "$got" "$REPO/$STORE_DEF/4.md" "Classification: duplicate" \
    "a relative --root resolves against the working directory once, and the store under it"

  # 7. An absolute --spec-path inside the root is the same spec, recorded by
  # its repo-relative path - the one the check rehashes at the cited commit.
  got=0
  ( cd "$OUT" && bash "$SELF" --root "$REPO" --spec-path "$REPO/.claude/productizer/spec.md" \
      --intent 5 --classification extend ) > "$T/c7.out" 2> "$T/c7.err" || got=$?
  check absolute-spec-inside-root 0 "$got" "$REPO/$STORE_DEF/5.md" "Spec path: .claude/productizer/spec.md" \
    "an absolute --spec-path inside the root is recorded repo-relative"

  # 8. An absolute --spec-path outside the root has no commit to cite.
  cp "$REPO/.claude/productizer/spec.md" "$T/loose-spec.md"
  got=0
  ( cd "$OUT" && bash "$SELF" --root "$REPO" --spec-path "$T/loose-spec.md" \
      --intent 6 --classification extend ) > "$T/c8.out" 2> "$T/c8.err" || got=$?
  check absolute-spec-outside-root 2 "$got" "$T/c8.err" "is outside the root" \
    "a spec outside the repository is refused - no commit of this root can be cited for it"

  # 9. A relative --spec-path that exists only relative to the working
  # directory is NOT found: it is joined to the root.
  mkdir -p "$OUT/specs"; cp "$REPO/.claude/productizer/spec.md" "$OUT/specs/spec.md"
  got=0
  ( cd "$OUT" && bash "$SELF" --root "$REPO" --spec-path "specs/spec.md" \
      --intent 7 --classification extend ) > "$T/c9.out" 2> "$T/c9.err" || got=$?
  check relative-spec-under-root 2 "$got" "$T/c9.err" "specs/spec.md does not exist under the given root" \
    "a relative --spec-path is read under the root, never the working directory"

  # 10. Uncommitted edits to the spec: no hash a check could ever verify.
  REPO3="$T/clone3"; fixture "$REPO3"
  printf -- '- **R3** - an uncommitted line.\n' >> "$REPO3/.claude/productizer/spec.md"
  got=0
  ( cd "$OUT" && bash "$SELF" --root "$REPO3" --intent 8 --classification extend ) \
    > "$T/c10.out" 2> "$T/c10.err" || got=$?
  check spec-differs-from-head 2 "$got" "$T/c10.err" "differs from the spec at HEAD" \
    "a classification against uncommitted edits is refused"
  absent spec-differs-wrote-nothing "$REPO3/$STORE_DEF" "and nothing was written"

  # 11. Bad usage.
  got=0
  bash "$SELF" --not-a-real-option > "$T/c11.out" 2> "$T/c11.err" || got=$?
  check unknown-option 2 "$got" "$T/c11.err" "unknown option --not-a-real-option" \
    "bad usage is refused, never answered"

  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  DOCUMENTED="$(awk '/^# EXIT CODES/ { on = 1; next } on && /^[^#]/ { exit } on && /^#   [0-9]  / { print $2 }' "$SELF" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  printf '    exit codes reached: %s   documented: %s\n' "$REACHED" "$DOCUMENTED"
  printf '    NOT ASSERTED: an unreadable spec or store file (needs a non-root user to make a file unreadable), a repository with no HEAD, two intent ids that slug to one filename, python3 absent, and an interrupted run leaving the store untouched.\n'
  if [ "$FAILED" -ne 0 ]; then
    printf 'FAIL: %d of %d selftest case(s) did not produce the exit code and the sentence they declare.\n' "$FAILED" "$CASES" >&2
    exit 1
  fi
  if [ "$REACHED" != "$DOCUMENTED" ]; then
    printf 'FAIL: exit codes reached (%s) differ from those documented in the header (%s).\n' "$REACHED" "$DOCUMENTED" >&2
    exit 1
  fi
  printf '  selftest: %d of %d case(s) held\n' "$CASES" "$CASES"
  exit 0
fi

[ -n "$INTENT" ] || die_unmeasured "--intent is required. A record with no intent belongs to nothing."
[ -n "$CLASSIFICATION" ] || die_unmeasured "--classification is required, and must be one of extend, refine, duplicate, contradict."

case "$CLASSIFICATION" in
  extend|refine|duplicate|contradict) ;;
  *) die_unmeasured "'$CLASSIFICATION' is not one of the four classifications the lifecycle allows: extend, refine, duplicate, contradict." ;;
esac

command -v python3 >/dev/null ||
  die_unmeasured "python3 is not on PATH, so the spec cannot be hashed or parsed. Refusing rather than writing a record whose provenance nobody computed."
[ -f "$LIB" ] && [ -r "$LIB" ] ||
  die_unmeasured "cannot read classification-record.py beside this script. The active-id rules and the hash live there; guessing them here is how two parsers come to disagree."

# Defaulting to the working directory has caused four separate silent-wrong-
# answer bugs in this repo: the script reads a directory that is not the repo
# and reports a confident result about it. git names the work tree or nothing does.
if [ -z "$ROOT" ]; then
  if ! ROOT="$(git rev-parse --show-toplevel)"; then
    die_unmeasured "no git work tree here, and --root was not given. Without a repository there is no commit to record, and a classification with no commit is the remembered copy R19 forbids."
  fi
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"

# EVERY PATH OPTION IS READ UNDER THE ROOT, never under the working directory.
# A relative --spec-path is joined to the root below. An absolute one is
# honoured only if it lies inside the root, and is then rewritten to its
# repo-relative spelling: the record's `Spec path:` line and `git show
# COMMIT:PATH` both need that spelling, and a spec outside the repository has
# no commit of this root that could be cited for it. It used to be joined to
# the root unconditionally, so a real, readable absolute path was refused as
# "does not exist" - a refusal whose stated reason was false.
case "$SPEC_REL" in
  /*)
    ROOT_ABS="$(cd "$ROOT" && pwd -P)"
    spec_dir="$(dirname "$SPEC_REL")"
    spec_abs="$SPEC_REL"
    if [ -d "$spec_dir" ]; then
      spec_abs="$(cd "$spec_dir" && pwd -P)/$(basename "$SPEC_REL")"
    fi
    case "$spec_abs" in
      "$ROOT_ABS"/*) SPEC_REL="${spec_abs#"$ROOT_ABS"/}" ;;
      *) die_unmeasured "--spec-path $SPEC_REL is outside the root $ROOT. A record cites a commit of the root and the check rehashes the spec at that commit, so a spec outside it could never be verified. Nothing was written." ;;
    esac
    ;;
esac

SPEC="$ROOT/$SPEC_REL"
# AN ABSOLUTE --store IS HONOURED AS ABSOLUTE, and the path printed is the path
# written. This used to be an unconditional `$ROOT/$STORE_REL`, so an absolute
# argument was joined to the root and the record landed INSIDE the repository
# under a directory shaped like the caller's scratch path. Measured, not
# argued: a run given an absolute store printed that absolute path and wrote to
# a repo-relative one, and the next run refused with `already classified` while
# the named store was visibly empty - the guard was reading a copy the caller
# could not see.
#
# Two defects in one, and the second is the worse: the message named one path
# and the write went to another. A tool that reports a location it did not use
# cannot be checked by reading its output, which is the only thing anyone reads.
#
# It also matters for R4's neighbourhood - a recorder that writes into the
# repository it is recording ABOUT can move the very tree a later check hashes.
case "$STORE_REL" in
  /*) STORE="$STORE_REL" ;;
  *)  STORE="$ROOT/$STORE_REL" ;;
esac

# What gets PRINTED is the path that was written, shortened to repo-relative
# when it is inside the repo. Both halves matter: printing a path other than the
# one used is the defect above, and printing an absolute one puts somebody's
# home directory into output that gets pasted into files this project commits.
# So: same path, shortest honest spelling.
show_path() {
  case "$1" in
    "$ROOT"/*) printf '%s' "${1#"$ROOT"/}" ;;
    *)         printf '%s' "$1" ;;
  esac
}

# --- the spec home, or nothing --------------------------------------------
[ -e "$SPEC" ] ||
  die_unmeasured "the spec home is unreachable: $SPEC_REL does not exist under the given root. R19 - stop, rather than classify against a remembered copy. Nothing was written."
[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unmeasured "the spec home is unreachable: $SPEC_REL exists but cannot be read. Unreachable is not empty, and neither is a reason to classify from memory. Nothing was written."

if ! COMMIT="$(git -C "$ROOT" rev-parse HEAD)"; then
  die_unmeasured "the repository has no HEAD commit, so there is nothing to record the spec against. Nothing was written."
fi
case "$COMMIT" in
  [0-9a-f]*) ;;
  *) die_unmeasured "git named HEAD as something that is not a commit sha. Refusing." ;;
esac

WORK="$(mktemp -d "${TMPDIR:-/tmp}/record-classification.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# `git show` writes its reason to stderr, and that reason is the answer to
# "why is the spec home unreachable". It is captured and printed, never binned.
if ! git -C "$ROOT" show "$COMMIT:$SPEC_REL" > "$WORK/at-head" 2> "$WORK/git-err"; then
  printf 'record-classification: git could not read %s at %s:\n' "$SPEC_REL" "$COMMIT" >&2
  sed 's/^/  /' < "$WORK/git-err" >&2
  die_unmeasured "the spec is not tracked at HEAD, so no commit can be cited for it. A classification with no commit is the remembered copy R19 forbids. Nothing was written."
fi

SPEC_HASH="$(python3 "$LIB" --sha256 "$SPEC")"
HEAD_HASH="$(python3 "$LIB" --sha256 "$WORK/at-head")"

if [ "$SPEC_HASH" != "$HEAD_HASH" ]; then
  die_unmeasured "the spec in the work tree differs from the spec at HEAD. A record cites a commit and the check rehashes the spec AT that commit, so a classification made against uncommitted edits could never be verified against anything. Commit the spec, then classify against it. Nothing was written."
fi

case "$SPEC_HASH" in
  sha256:????????????????????????????????????????????????????????????????) ;;
  *) die_unmeasured "the spec hash did not come out in the expected shape. Refusing rather than writing a record whose hash nobody can check." ;;
esac

SLUG="$(python3 "$LIB" --slug "$INTENT")"
RECORDED="$(python3 "$LIB" --today)"

# The intent identifier is written into a committed file, so its shape is
# checked before it is written and not after. Everything else about the intent
# stays out of this store.
python3 "$LIB" --active-ids "$SPEC" > "$WORK/ids"
ID_COUNT="$(awk 'END { print NR }' "$WORK/ids")"

# THE PATH WRITTEN IS `$STORE/$SLUG.md`, and show_path is used only to PRINT
# it. B132: this used to be `DEST="$(show_path ...)"`, so a store under the
# root was shortened to a repo-relative path and then resolved against the
# WORKING DIRECTORY by the existence test and the `mv` below. Measured: run
# from one repository with --root a clean clone, it hashed the clone's spec,
# printed the clone's store path, and wrote the record into the repository the
# caller stood in - the clone's store stayed empty, and the one-per-intent
# guard read the wrong store too. Run from a directory with no such store it
# failed in `mv` with exit 1, the code this contract reserves for "already
# classified".
DEST="$STORE/$SLUG.md"

# --- exactly one classification per intent --------------------------------
if [ -e "$DEST" ]; then
  [ -r "$DEST" ] ||
    die_unmeasured "$(show_path "$STORE/$SLUG.md") exists but cannot be read, so whether this intent is already classified is UNKNOWN, not no. Nothing was written."
  EXISTING="$(awk '/^Intent:/ { sub(/^Intent:[ \t]*/, ""); print; exit }' "$DEST")"
  if [ "$EXISTING" = "$INTENT" ]; then
    printf '%s\n' "$(show_path "$STORE/$SLUG.md")"
    printf 'REFUSED: this intent is already classified. Exactly one classification per intent is the R6 invariant, and it is held here by the filename. Nothing was written.\n' >&2
    exit 1
  fi
  die_unmeasured "$(show_path "$STORE/$SLUG.md") already holds a record for a different intent identifier - two identifiers reduced to one filename. Pick a distinguishable id; do not overwrite. Nothing was written."
fi

# --- build it whole, then move it in one step ------------------------------
{
  printf '# Classification — %s\n\n' "$INTENT"
  printf 'Intent: %s\n' "$INTENT"
  printf 'Classification: %s\n' "$CLASSIFICATION"
  printf 'Recorded: %s\n' "$RECORDED"
  printf 'Spec path: %s\n' "$SPEC_REL"
  printf 'Spec commit: %s\n' "$COMMIT"
  printf 'Spec hash: %s\n' "$SPEC_HASH"
  printf 'In scope count: %s\n' "$ID_COUNT"
  printf '\n'
  printf 'The spec commit and hash above are what make this record falsifiable:\n'
  printf 'the spec at that commit is rehashed and its active requirement ids are\n'
  printf 'recomputed, then compared with the list below. A record whose hash is\n'
  printf 'blank, absent or a placeholder is refused rather than believed.\n'
  printf '\n'
  printf '%s\n\n' "## Requirement ids in scope"
  cat "$WORK/ids"
} > "$WORK/record.md"

mkdir -p "$STORE"
mv "$WORK/record.md" "$DEST"

printf '%s\n' "$SPEC_REL"
printf 'spec commit: %s\n' "$COMMIT"
printf 'spec hash: %s\n' "$SPEC_HASH"
printf 'active requirement ids in scope: %s\n' "$ID_COUNT"
printf 'classification: %s\n' "$CLASSIFICATION"
printf '%s\n' "$(show_path "$STORE/$SLUG.md")"
