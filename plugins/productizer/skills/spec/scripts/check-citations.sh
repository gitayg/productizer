#!/usr/bin/env bash
# check-citations.sh --base REF [--head REF] [--root DIR]
#                    [--version] [--help] [--selftest]
#
# A CITATION ADDED BY THIS CHANGE THAT RESOLVES TO NOTHING.
#
# Requirement ids are permanent, so a citation of one is meant to resolve for
# the life of the product. Nothing checked that a NEW citation resolves at the
# moment it is written. A plan, a check's coverage claim, a commit trailer or a
# comment can name an id the spec does not hold - mistyped, invented, or copied
# from another product's spec - and it reads exactly like provenance. This
# reads the lines a change ADDS and resolves every requirement id on them
# against the spec the change ends at.
#
# Adapted from the DANGLING_REF rule of the AI Unified Process (Apache-2.0, by
# Simon Martinelli), whose spec linter refuses a reference to a requirement
# that is not in its requirements file. The idea is theirs; this code is not.
# What is added here is the split below, the diff scope, and the
# superseded-chain note.
#
# WHY DIFF-SCOPED, AND NOT THE WHOLE TREE. `drift-reverse.sh` already walks the
# whole tree and reports every dead or unknown citation as a candidate for a
# person to judge. That is the right shape for a scheduled pass and the wrong
# shape for a check on a change: on this repository it reports every example
# id ever written in a reference doc, every run, and a check that repeats the
# same rows on every change is one people stop reading. A citation that is
# already in the tree at the base is that pass's business. A citation THIS
# change writes is this check's.
#
# THE SPLIT, ON THE SPEC'S OWN `Next requirement id` COUNTER.
#
#   CITATION_NEVER_ALLOCATED   the id is at or above the counter. It was never
#                              handed out here: a typo, an invention, an id
#                              from someone else's spec, or an example.
#   CITATION_ALLOCATED_MISSING the id is below the counter and the spec does
#                              not define it. It WAS handed out and its row is
#                              gone, which this spec forbids - a deletion, or a
#                              requirement that lives in a split spec file this
#                              check does not read.
#
#   Two different repairs, so two different codes. drift-reverse.sh draws the
#   same line (its signals B and D) for the same reason.
#
#   The counter alone cannot place two ids, because ids start at R1 and carry
#   no leading zero, so neither is ever handed out whatever the counter says:
#     - `R0` is the reserved example id. The plugin's own templates and guide
#       write `Superseded by R0.` precisely because no spec can allocate it.
#       Unless the spec defines it, it is printed as an EXAMPLE line, like an
#       id inside an EXAMPLE block and counted with them in the summary, and
#       is not a finding. 1.0 read it as 0, below every counter, and so as
#       CITATION_ALLOCATED_MISSING.
#     - `R0` followed by more digits - a leading zero - is
#       CITATION_NEVER_ALLOCATED. 1.0 read the digits as a number below the
#       counter and called it allocated-but-missing, which sends the writer
#       looking for a deleted row that never existed.
#
#   CITATION_SUPERSEDED is a NOTE, not a finding. The id resolves - a
#   superseded requirement keeps its sentence forever - but a NEW citation of
#   it is usually a citation of the wrong agreement. The note follows the
#   `Superseded by` chain to its end and names the requirement that stands
#   now. A withdrawn id, or a chain that ends anywhere but an active
#   requirement, is a note that says where it ended.
#
# COMMIT TRAILERS. Every commit in BASE..HEAD is handed to
# `req-trailer.sh --validate --rev <sha>` with the spec at HEAD. An id it
# reports as absent from the spec is TRAILER_UNKNOWN_ID; a token that is not an
# id at all is TRAILER_MALFORMED_ID. A commit with no trailer is counted and is
# not a finding - an untraced commit is `req-trailer.sh --orphans`' business.
# The trailer is validated by req-trailer.sh itself rather than re-parsed here:
# two readers of one trailer format disagree the day one of them is edited.
#
# WHAT IS READ, AND WHAT IS NOT.
#
#   Read: lines ADDED in `git diff --unified=0 MERGE-BASE HEAD`, which is
#   `git diff BASE...HEAD`, over tracked files. A citation added and removed
#   again inside the range is not in the net diff and is not reported.
#
#   Not read:
#     - any path with a `fixtures/` or `evals/` component. They hold their own
#       example specs with their own numbering; an `R3` in a fixture spec is a
#       different requirement wearing the same name. check-suspect-links.sh
#       measured this: 81 tracked files matched one id, 19 of them outside
#       those trees.
#     - `.claude/productizer/spec.md` and `constitution.md`. validate-spec.py
#       owns citations inside them, section-aware; a second reader here would
#       report the same defect twice under two names.
#
#   `.claude/productizer/backlog.md` IS read, since 1.2 (B127). 1.1 excluded
#   it by name on the claim above, and the claim was false for it: measured
#   2026-10-12, validate-spec.py run over this repository's spec and a backlog
#   with a row citing an id above the counter reported 0 errors and 0
#   warnings. A typo like R5 for R50 in a backlog row is a dangling citation
#   like any other, and the filename was the only thing letting it through.
#   Only the lines a change ADDS are read, as everywhere else, so a row is
#   re-read when it is rewritten (a status flipped to `done`) and the rows
#   already there are not. An EXAMPLE block cannot sit inside a markdown table
#   without ending it, so a backlog row that needs an illustrative id writes
#   `R0`, which is never a finding.
#     - lines inside an EXAMPLE block, in the file as it stands at HEAD: from
#       a line that STARTS with `<!-- EXAMPLE:BEGIN` to the next line that
#       starts with `<!-- EXAMPLE:END` or `EXAMPLE:END`. Leading whitespace
#       and a `#` or `//` comment leader are allowed before either. The
#       marker is format-spec.md section 6's, which validate-spec.py and
#       scaffold.sh already honour. An example id is not a citation, and this
#       is the one place a writer can say so. Each skipped id is still
#       printed, as an EXAMPLE line, so the marker is visible rather than
#       silent. A BEGIN with no END after it skips NOTHING: a malformed
#       marker fails toward reporting, never toward silence.
#       Anchored at the line start, unlike validate-spec.py's substring test,
#       and measured into that: on the commit that lands this file, the
#       substring rule made 31 lines of this file's own self-test an example
#       block, because code that BUILDS a marker mentions it mid-line.
#     - `.claude/productizer/requirement-index.md`. It is generated from the
#       spec, and `build-requirement-index.sh --check` already fails the run
#       when it is not what the spec generates, so it cannot hold an id the
#       spec lacks without that check going red first. It lists every
#       superseded id by design: measured on this repository over the five
#       commits before v4.65.1, all 6 notes this check printed were its rows,
#       and none was a citation anybody wrote.
#     - binary files. Named, never folded into the read count.
#
# THE SPEC IS READ AT HEAD, through `spec-requirements.sh`, the one parser
# the other spec checks read it through. The counter is read with the same
# field read drift-reverse.sh uses: the `Next requirement id` line, then the
# first `R<n>` on the `:` line after it.
#
# KNOWN LIMITATIONS, written down rather than discovered later:
#   - A citation is a TOKEN: `R` and digits, with no letter, digit or
#     underscore either side. `R9.1` cites R9. An `R` and digits that mean
#     something else - git's rename score, a storage product, a register - is
#     indistinguishable from a citation, and so is an example id outside an
#     EXAMPLE block.
#   - One spec path. A spec split across files, or moved by
#     `.claude/productizer/config.json`, reads as missing requirements.
#   - req-trailer.sh reads the spec through its own matcher, not
#     spec-requirements.sh, so the two halves of this check can disagree about
#     an id that is bold outside the `## Requirements` section.
#   - A renamed file's unchanged lines are not added lines (`--find-renames`
#     is passed explicitly, so a user's diff.renames setting cannot change
#     the answer). A copy is not detected as one, so a copied file's lines
#     are all read.
#   - In a shallow clone the commit list of the range can be cut short with
#     no error from git. The run names the clone as shallow when it is one.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  read, and every citation this change added resolves, and every trailer
#      in the range names ids the spec holds. Notes do not change this.
#   1  findings - at least one FINDING line.
#   2  refused, and the reason is named: bad usage, no --base, the base or
#      head does not resolve, a shallow clone that lacks the base or the merge
#      base, no spec at HEAD, a spec with no requirement definitions, a spec
#      with no readable `Next requirement id`, or req-trailer.sh answering in
#      a way this check cannot read. Never 0.
#
# Under --selftest the same three mean: every
# case produced the exit code and the sentence it declares (0), at least one
# did not (1), and the corpus could not be built (2).
set -euo pipefail

VERSION="check-citations 1.2"
ROOT=""
BASE=""
HEAD_REF="HEAD"
MODE="measure"

usage() {
  printf 'usage: check-citations.sh --base REF [--head REF] [--root DIR]\n'
  printf '                          [--version] [--help] [--selftest]\n'
  printf '  --base REF  required. The change is git diff BASE...HEAD: the lines\n'
  printf '              added since the merge base of REF and HEAD.\n'
  printf '  --head REF  the commit the change ends at. Default HEAD. The spec\n'
  printf '              is read at this commit, not from the work tree.\n'
  printf '  --root DIR  the repo work tree. Defaults to the git top level,\n'
  printf '              never to the working directory.\n'
  printf '  --selftest  drive the built-in corpus instead of a repository.\n'
  printf 'Exit: 0 every added citation resolves, 1 findings, 2 refused.\n'
}

die_unmeasured() { printf 'check-citations: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)
      [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --base)
      [ "$#" -ge 2 ] || die_unmeasured "--base needs a ref"
      BASE="$2"; shift 2 ;;
    --base=*) BASE="${1#--base=}"; shift ;;
    --head)
      [ "$#" -ge 2 ] || die_unmeasured "--head needs a ref"
      HEAD_REF="$2"; shift 2 ;;
    --head=*) HEAD_REF="${1#--head=}"; shift ;;
    --selftest) MODE="selftest"; shift ;;
    -*) printf 'check-citations: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'check-citations: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

SELFDIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# --selftest. R39: every exit code this tool can return is driven by a case,
# each case is a real git history built in a sandbox, and each asserts a
# sentence of output as well as its code.
#
# THE IDS THAT MUST NOT RESOLVE ARE BUILT, NOT WRITTEN. This file is itself a
# tracked file in a repository this check reads, and a never-allocated id
# written literally below would be reported on the commit that adds it - the
# same reason req-trailer.sh spells out no coverage id in its header. Ids that
# DO resolve here (R1 to R4) are written as they are.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SELF="$SELFDIR/$(basename "$0")"
  command -v git >/dev/null ||
    die_unmeasured "git is not on PATH, so no history could be built and no case was driven"
  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-citations-selftest.XXXXXX")" ||
    die_unmeasured "could not create a sandbox, so no case was driven"
  SB="$(cd "$SB" && pwd -P)"
  trap 'rm -rf "$SB"' EXIT HUP INT TERM
  # No global or system git config reaches a fixture: a user's hooks path or
  # signing setting would otherwise decide whether a case can even commit.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

  NEVER="R$((4 + 3))"     # at or above the fixture counter R5
  UNKNOWN="R$((4 + 5))"   # in a trailer, and in no spec
  LEADING="R0$((1 + 2))"  # a leading zero: the digits read 3, an allocated id

  g() { git -c user.email=selftest@example.invalid -c user.name=selftest \
          -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }
  commit_all() { g -C "$1" add -A; g -C "$1" commit -q -m "$2"; }

  # The fixture spec: R1 superseded by R2, R2 superseded by R4, R4 active, and
  # R3 allocated below the counter with no row - the missing case.
  fixture_spec() {
    mkdir -p "$1/.claude/productizer"
    {
      # shellcheck disable=SC2016  # the backticks are the spec's literal counter syntax
      printf '# Living spec - selftest\n\nNext requirement id\n: `R5` - allocate from here.\n\n'
      printf '## Requirements\n\n'
      printf -- '- **R1** \342\200\224 The lifecycle shall hold one spec.\n  Superseded by R2. Narrowed.\n'
      printf -- '- **R2** \342\200\224 The lifecycle shall hold one spec per product.\n  Superseded by R4. Narrowed again.\n'
      printf -- '- **R4** \342\200\224 The lifecycle shall hold one spec per product in its home.\n'
    } > "$1/.claude/productizer/spec.md"
  }
  # The base: the spec, and notes.md whose line 2 ALREADY cites a never
  # allocated id. Every case below must leave it unreported: it is not added.
  base_repo() {
    g init -q "$SB/$1"
    fixture_spec "$SB/$1"
    printf 'notes\nalready here before the change: %s\n' "$NEVER" > "$SB/$1/notes.md"
    commit_all "$SB/$1" "base"
  }
  # One commit that appends $2 to notes.md, with message $3.
  add_line() {
    printf '%b\n' "$2" >> "$SB/$1/notes.md"
    commit_all "$SB/$1" "$3"
  }

  FAILED=0
  DRIVEN=0
  CODES=""
  drive() {
    # $1 case, $2 expected exit, $3 expected sentence (a grep BRE), $4.. argv
    local name="$1" want="$2" marker="$3"
    shift 3
    local rc=0 script="${DRIVE_SCRIPT:-$SELF}"
    if [ "$#" -eq 0 ]; then set -- --root "$SB/$name" --base HEAD~1; fi
    bash "$script" "$@" > "$SB/$name.out" 2> "$SB/$name.err" || rc=$?
    DRIVEN=$((DRIVEN + 1))
    CODES="$CODES$rc
"
    local why=""
    [ "$rc" -eq "$want" ] || why="exit $rc, expected $want"
    if ! grep -q -- "$marker" "$SB/$name.out" "$SB/$name.err"; then
      [ -n "$why" ] && why="$why; "
      why="${why}its output does not say what it was supposed to say"
    fi
    if [ -z "$why" ]; then
      printf '  held: case %-22s exit %d, and said so - %s\n' "$name" "$rc" "$marker"
      return 0
    fi
    printf '  FINDING: case %-22s %s - expected: %s\n' "$name" "$why" "$marker"
    sed 's/^/      | /' "$SB/$name.out" "$SB/$name.err"
    FAILED=$((FAILED + 1))
    return 0
  }

  # clean: one resolving citation, two id-shaped tokens that are not
  # citations, and a valid trailer. The pre-existing line stays unreported.
  base_repo clean
  add_line clean 'cites R4; PR77 and R4x are not citations' "$(printf 'cite R4\n\nProductizer-Req: R4')"

  base_repo never
  add_line never "cites $NEVER" "cite a never allocated id"

  base_repo missing
  add_line missing 'cites R3' "cite an allocated id with no row"

  # reserved-r0: the reserved example id, below every counter and never
  # allocated. leading-zero: an id whose digits read as allocated R3, which no
  # spec can allocate in that spelling.
  base_repo reserved-r0
  add_line reserved-r0 'cites R0, the example id' "cite the reserved example id"

  base_repo leading-zero
  add_line leading-zero "cites $LEADING" "cite an id with a leading zero"

  # utf8-neighbour: an id followed by a multibyte character, read under a UTF-8
  # locale. The BSD awk refused it (exit 2) before every awk here read bytes.
  base_repo utf8-neighbour
  add_line utf8-neighbour 'spans R4–R4 · done' "cite an id beside an en dash"

  base_repo superseded
  add_line superseded 'cites R1' "cite the start of a supersede chain"

  # plusplus: an added line whose text begins `++` prints as `+++`, the same
  # three characters as a file header. It must still be read as a line.
  base_repo plusplus
  add_line plusplus "++ cites $NEVER" "a line that looks like a header"

  base_repo trailer-unknown
  add_line trailer-unknown 'cites R4' "$(printf 'cite R4\n\nProductizer-Req: R4,%s' "$UNKNOWN")"

  base_repo trailer-malformed
  add_line trailer-malformed 'cites R4' "$(printf 'cite R4\n\nProductizer-Req: R4,nonsense')"

  # excluded: the same never-allocated id, in every path this check leaves to
  # another reader.
  base_repo excluded
  mkdir -p "$SB/excluded/fixtures" "$SB/excluded/sub/evals"
  printf 'cites %s\n' "$NEVER" > "$SB/excluded/fixtures/a.md"
  printf 'cites %s\n' "$NEVER" > "$SB/excluded/sub/evals/b.md"
  printf 'cites %s\n' "$NEVER" > "$SB/excluded/.claude/productizer/constitution.md"
  commit_all "$SB/excluded" "cite it where other readers own the citation"

  # backlog: a row appended to the backlog cites a never-allocated id. No
  # other reader checks it, so this one does. backlog-rewritten: an existing
  # row that already cited it is rewritten (its status flipped), so the
  # rewritten line is an added line and is read again; the row beside it,
  # untouched, is not. backlog-r0: the reserved example id in a backlog row is
  # an EXAMPLE line, the one way a table row can illustrate an id.
  base_repo backlog
  printf '| B1 | a row | todo | cites R4 |\n' > "$SB/backlog/.claude/productizer/backlog.md"
  commit_all "$SB/backlog" "a backlog that cites a real requirement"
  printf '| B2 | a typo | todo | cites %s |\n' "$NEVER" >> "$SB/backlog/.claude/productizer/backlog.md"
  commit_all "$SB/backlog" "append a backlog row"

  base_repo backlog-rewritten
  printf '| B1 | old | todo | cites %s |\n| B2 | old | todo | cites R3 |\n' "$NEVER" \
    > "$SB/backlog-rewritten/.claude/productizer/backlog.md"
  commit_all "$SB/backlog-rewritten" "a backlog with two old rows"
  printf '| B1 | old | done | cites %s |\n| B2 | old | todo | cites R3 |\n' "$NEVER" \
    > "$SB/backlog-rewritten/.claude/productizer/backlog.md"
  commit_all "$SB/backlog-rewritten" "close B1"

  base_repo backlog-r0
  printf '| B1 | an illustration | todo | writes R0 for the example |\n' > "$SB/backlog-r0/.claude/productizer/backlog.md"
  commit_all "$SB/backlog-r0" "a backlog row that illustrates an id"

  base_repo example
  add_line example "<!-- EXAMPLE:BEGIN -->\nan example: $NEVER\n<!-- EXAMPLE:END -->" "an example block"

  # example-unclosed: a BEGIN with no END after it skips nothing.
  base_repo example-unclosed
  add_line example-unclosed "<!-- EXAMPLE:BEGIN -->\nan example: $NEVER" "an unclosed example block"

  # example-mention: a marker named mid-line is a mention, not a marker, so
  # the id on the next line is still read.
  base_repo example-mention
  add_line example-mention "the marker is written <!-- EXAMPLE:BEGIN -->\ncites $NEVER\n<!-- EXAMPLE:END -->" "a mention of the marker"

  # added-then-removed: the net diff of the range holds no added citation.
  # head-option: the same history, ending at the commit that added it.
  base_repo added-then-removed
  add_line added-then-removed "cites $NEVER" "add it"
  printf 'notes\nalready here before the change: %s\n' "$NEVER" > "$SB/added-then-removed/notes.md"
  commit_all "$SB/added-then-removed" "remove it again"

  # shallow: the base was never fetched.
  git clone -q --depth 1 "file://$SB/never" "$SB/shallow" ||
    die_unmeasured "could not build a shallow clone, so the case that names a shallow clone was never driven"

  base_repo no-spec
  g -C "$SB/no-spec" rm -q .claude/productizer/spec.md
  commit_all "$SB/no-spec" "remove the spec"

  base_repo no-requirements
  # shellcheck disable=SC2016  # the backticks are the spec's literal counter syntax
  printf '# Living spec - selftest\n\nNext requirement id\n: `R5`\n\n## Design\n\nProse only.\n' \
    > "$SB/no-requirements/.claude/productizer/spec.md"
  commit_all "$SB/no-requirements" "a spec with no requirement definitions"

  base_repo no-counter
  sed 's/^Next requirement id$/Next id, spelled otherwise/' "$SB/no-counter/.claude/productizer/spec.md" \
    > "$SB/no-counter/spec.tmp"
  mv "$SB/no-counter/spec.tmp" "$SB/no-counter/.claude/productizer/spec.md"
  commit_all "$SB/no-counter" "the counter field renamed out of reach"

  mkdir -p "$SB/not-a-work-tree"

  # The req-trailer.sh contract, driven through a copy of this script beside a
  # stub that answers 3 in a sentence this check does not know, and one that
  # answers 2. Either way the trailers are unvalidated, and that is a refusal.
  for stub in stub3 stub2; do
    mkdir -p "$SB/$stub-bin"
    cp "$SELF" "$SB/$stub-bin/check-citations.sh"
    cp "$SELFDIR/spec-requirements.sh" "$SB/$stub-bin/spec-requirements.sh"
  done
  printf '#!/usr/bin/env bash\necho "req-trailer: something new" >&2\nexit 3\n' > "$SB/stub3-bin/req-trailer.sh"
  printf '#!/usr/bin/env bash\necho "req-trailer: a refusal" >&2\nexit 2\n' > "$SB/stub2-bin/req-trailer.sh"

  drive clean              0 'summary: lines read 1, citations 1, findings 0, notes 0'
  drive superseded         0 'NOTE CITATION_SUPERSEDED notes.md:3 R1 -> R4'
  drive excluded           0 '0 file(s) with added lines read, 3 excluded'
  drive backlog-r0         0 'EXAMPLE .claude/productizer/backlog.md:1 R0 (the reserved example id'
  drive backlog            1 "FINDING CITATION_NEVER_ALLOCATED .claude/productizer/backlog.md:2 $NEVER\$"
  drive backlog-rewritten  1 'summary: lines read 1, citations 1, findings 1'
  drive reserved-r0        0 'EXAMPLE notes.md:3 R0 (the reserved example id: ids start at R1'
  drive example            0 "EXAMPLE notes.md:4 $NEVER (inside an EXAMPLE block"
  drive added-then-removed 0 'summary: lines read 0, citations 0'
  drive empty-range        0 '^range: 0 commit(s)' --root "$SB/clean" --base HEAD
  drive never              1 "FINDING CITATION_NEVER_ALLOCATED notes.md:3 $NEVER\$"
  drive missing            1 'FINDING CITATION_ALLOCATED_MISSING notes.md:3 R3$'
  drive leading-zero       1 "FINDING CITATION_NEVER_ALLOCATED notes.md:3 $LEADING\$"
  LC_ALL=C.UTF-8 drive utf8-neighbour 0 'summary: lines read 1, citations 1, findings 0'
  drive plusplus           1 "FINDING CITATION_NEVER_ALLOCATED notes.md:3 $NEVER\$"
  drive trailer-unknown    1 "FINDING TRAILER_UNKNOWN_ID [0-9a-f]\{40\} $UNKNOWN\$"
  drive trailer-malformed  1 'FINDING TRAILER_MALFORMED_ID [0-9a-f]\{40\} nonsense$'
  drive example-unclosed   1 "FINDING CITATION_NEVER_ALLOCATED notes.md:4 $NEVER\$"
  drive example-mention    1 "FINDING CITATION_NEVER_ALLOCATED notes.md:4 $NEVER\$"
  drive head-option        1 "FINDING CITATION_NEVER_ALLOCATED notes.md:3 $NEVER\$" \
    --root "$SB/added-then-removed" --base HEAD~2 --head HEAD~1
  drive no-base            2 '--base is required' --root "$SB/clean"
  drive base-unresolvable  2 'does not resolve to a commit' --root "$SB/clean" --base no-such-ref
  drive head-unresolvable  2 'the head ref no-such-ref does not resolve' --root "$SB/clean" --base HEAD --head no-such-ref
  drive shallow            2 'the clone is SHALLOW' --root "$SB/shallow" --base HEAD~1
  drive no-spec            2 'no .claude/productizer/spec.md at'
  drive no-requirements    2 'holds no requirement definitions'
  drive no-counter         2 "states no readable 'Next requirement id'"
  drive not-a-work-tree    2 'is not inside a git work tree' --root "$SB/not-a-work-tree" --base HEAD
  drive unknown-option     2 'unknown option --nonsense' --nonsense
  DRIVE_SCRIPT="$SB/stub3-bin/check-citations.sh" \
    drive trailer-unreadable 2 'named no id this check can read' --root "$SB/clean" --base HEAD~1
  DRIVE_SCRIPT="$SB/stub2-bin/check-citations.sh" \
    drive trailer-refused    2 'req-trailer.sh exited 2 validating' --root "$SB/clean" --base HEAD~1

  printf '  cases driven: %d. Cases that did not hold: %d\n' "$DRIVEN" "$FAILED"
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    grep -qx "$want" <<<"$CODES" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  printf '    NOT ASSERTED: a withdrawn citation (CITATION_WITHDRAWN) and a supersede chain that ends anywhere but an active requirement; a spec that itself defines R0, which then resolves like any other id; a binary file in the range; a merge commit in the range; the refusal for a base and head with no merge base, which needs two unrelated histories; a shallow clone that holds the base but not the merge base; and whether a citation MEANS the requirement - every case asserts a token resolved, never that the sentence around it is about that requirement.\n'
  if [ "$FAILED" -ne 0 ]; then
    printf 'FAIL: %d selftest case(s) did not produce the exit code and the sentence they declare.\n' "$FAILED" >&2
    exit 1
  fi
  if [ -n "$MISSING" ]; then
    printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  printf '  PASS: every case produced the exit code and the sentence it declares.\n'
  exit 0
fi

[ -n "$BASE" ] ||
  die_unmeasured "--base is required. This check reads only the lines a change adds, and with no base there is no change to read. Nothing was measured."

if [ -z "$ROOT" ]; then
  if ! ROOT="$(git rev-parse --show-toplevel)"; then
    die_unmeasured "no git work tree here, and --root was not given. Refusing rather than reading the working directory."
  fi
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
TOP="$(git -C "$ROOT" rev-parse --show-toplevel)" ||
  die_unmeasured "--root $ROOT is not inside a git work tree. The lines a change added are only answerable from git."

PARSER="$SELFDIR/spec-requirements.sh"
TRAILER="$SELFDIR/req-trailer.sh"
[ -f "$PARSER" ] ||
  die_unmeasured "spec-requirements.sh is not beside this script. The spec is read through that one parser on purpose, so no requirement was resolved."
[ -f "$TRAILER" ] ||
  die_unmeasured "req-trailer.sh is not beside this script, so no commit trailer could be validated."

SPECREL=".claude/productizer/spec.md"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-citations.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# --- the range ----------------------------------------------------------------
SHALLOW="$(git -C "$TOP" rev-parse --is-shallow-repository)"
HEAD_SHA="$(git -C "$TOP" rev-parse --verify --quiet "$HEAD_REF^{commit}")" || HEAD_SHA=""
[ -n "$HEAD_SHA" ] ||
  die_unmeasured "the head ref $HEAD_REF does not resolve to a commit, so there is no change to read."
BASE_SHA="$(git -C "$TOP" rev-parse --verify --quiet "$BASE^{commit}")" || BASE_SHA=""
if [ -z "$BASE_SHA" ]; then
  if [ "$SHALLOW" = "true" ]; then
    die_unmeasured "the base ref $BASE does not resolve in this clone, and the clone is SHALLOW. The commit the change is measured against was never fetched, so which lines it added is UNKNOWN. Fetch full history (fetch-depth: 0) and re-run. This is not a clean result."
  fi
  die_unmeasured "the base ref $BASE does not resolve to a commit. A wrong base makes every line below the wrong line, so nothing was read."
fi
if ! MB="$(git -C "$TOP" merge-base "$BASE_SHA" "$HEAD_SHA")"; then
  if [ "$SHALLOW" = "true" ]; then
    die_unmeasured "$BASE and $HEAD_REF have no merge base in this clone, and the clone is SHALLOW: the history that joins them was never fetched. Fetch full history and re-run. This is not a clean result."
  fi
  die_unmeasured "$BASE and $HEAD_REF have no merge base, so there is no change between them to read."
fi
HEAD_SHORT="$(git -C "$TOP" rev-parse --short "$HEAD_SHA")"
MB_SHORT="$(git -C "$TOP" rev-parse --short "$MB")"

# --- the spec at HEAD, through the one parser --------------------------------
if [ -z "$(git -C "$TOP" ls-tree "$HEAD_SHA" -- "$SPECREL")" ]; then
  die_unmeasured "no $SPECREL at $HEAD_SHORT. With no spec there is nothing to resolve a citation against, so nothing was resolved."
fi
git -C "$TOP" show "$HEAD_SHA:$SPECREL" > "$WORK/spec.md" ||
  die_unmeasured "cannot read $SPECREL at $HEAD_SHORT, which git lists as holding it"
bash "$PARSER" "$WORK/spec.md" > "$WORK/reqs.tsv" ||
  die_unmeasured "spec-requirements.sh refused $SPECREL at $HEAD_SHORT, so no requirement was resolved"
[ -s "$WORK/reqs.tsv" ] ||
  die_unmeasured "$SPECREL at $HEAD_SHORT holds no requirement definitions. Every citation would read as dangling, which says nothing about the citations. Nothing was resolved; that is not a pass."

# The same field read drift-reverse.sh uses, copied deliberately.
NEXT_ID="$(awk '
  /^[Nn]ext requirement id/ { want = 1; next }
  want && /^:/ { if (match($0, /R[0-9]+/)) { print substr($0, RSTART + 1, RLENGTH - 1); exit } want = 0 }
' "$WORK/spec.md")"
case "$NEXT_ID" in
  '' | *[!0-9]*)
    die_unmeasured "$SPECREL at $HEAD_SHORT states no readable 'Next requirement id', so an id that was never allocated cannot be told from one whose requirement is gone. The two have different repairs; nothing was guessed." ;;
esac

N_REQ="$(awk 'END { print NR }' "$WORK/reqs.tsv")"
count_status() { awk -F'\t' -v s="$1" '$3 == s { n++ } END { print n + 0 }' "$WORK/reqs.tsv"; }
printf 'base: %s, merge base %s; head: %s -> %s\n' "$BASE" "$MB_SHORT" "$HEAD_REF" "$HEAD_SHORT"
printf 'spec: %s at %s - %s active, %s superseded, %s withdrawn, %s malformed; next requirement id R%s\n' \
  "$SPECREL" "$HEAD_SHORT" "$(count_status active)" "$(count_status superseded)" \
  "$(count_status withdrawn)" "$(count_status malformed)" "$NEXT_ID"
printf 'requirements resolved against: %s\n' "$N_REQ"
if [ "$SHALLOW" = "true" ]; then
  printf 'clone: SHALLOW - the commit list below can be cut short with no error from git\n'
fi

# --- the lines the change added -----------------------------------------------
#
# The hunk header's own counts decide where a hunk ends, never the first
# character alone: under --unified=0 an added line whose text begins `++`
# prints as `+++`, the same three characters as a file header.
git -C "$TOP" -c core.quotePath=false diff --unified=0 --no-color --no-ext-diff \
    --no-textconv --find-renames --src-prefix=a/ --dst-prefix=b/ \
    "$MB" "$HEAD_SHA" -- > "$WORK/diff.txt" ||
  die_unmeasured "git diff $MB_SHORT $HEAD_SHORT failed, so the lines this change added are unknown"

# BYTES, NOT CHARACTERS, in every awk that reads a changed file's text. Ids are
# ASCII, and the BSD awk on macOS under a UTF-8 locale (LANG=en_US.UTF-8, the
# Terminal default, or C.UTF-8) takes a one-character substr after an id and
# then refuses the byte it got: an added line reading `R1–R5` made the whole run
# exit 2 with `towc: multibyte conversion failure`. Measured 2026-10-12; case
# `utf8-neighbour`. gawk and mawk do not fail, so CI on Linux did not see it.
LC_ALL=C awk -v ADDED="$WORK/added.tsv" -v BIN="$WORK/binary.txt" -v FILES="$WORK/files.txt" '
  BEGIN { inh = 0; f = "" }
  inh && /^-/ { ro--; if (ro <= 0 && rn <= 0) inh = 0; next }
  inh && /^\+/ {
    print f "\t" ln "\t" substr($0, 2) > ADDED
    ln++; rn--; if (ro <= 0 && rn <= 0) inh = 0; next
  }
  inh && /^\\/ { next }
  /^diff --git / { inh = 0; f = ""; next }
  /^\+\+\+ / {
    f = substr($0, 5)
    if (f == "/dev/null") f = ""
    else { sub(/^b\//, "", f); print f > FILES }
    next
  }
  /^Binary files / { print $0 > BIN; next }
  /^@@ / {
    o = $2; n = $3
    sub(/^-/, "", o); split(o, po, ",")
    sub(/^\+/, "", n); split(n, pn, ",")
    ro = (2 in po) ? po[2] + 0 : 1
    rn = (2 in pn) ? pn[2] + 0 : 1
    ln = pn[1] + 0
    inh = (ro > 0 || rn > 0) ? 1 : 0
    next
  }
' "$WORK/diff.txt"
for f in added.tsv binary.txt files.txt; do [ -f "$WORK/$f" ] || : > "$WORK/$f"; done

# Exclusions, by path. See the header for why each one.
excluded() {
  case "$1" in
    .claude/productizer/spec.md|.claude/productizer/constitution.md) return 0 ;;
    .claude/productizer/requirement-index.md) return 0 ;;
  esac
  grep -Eq '(^|/)(fixtures|evals)/' <<<"$1"
}
: > "$WORK/read.txt"
: > "$WORK/excluded.txt"
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  if excluded "$rel"; then printf '%s\n' "$rel" >> "$WORK/excluded.txt"
  else printf '%s\n' "$rel" >> "$WORK/read.txt"; fi
done < "$WORK/files.txt"

N_COMMITS="$(git -C "$TOP" rev-list --count "$BASE_SHA..$HEAD_SHA")"
printf 'range: %s commit(s); %s file(s) with added lines read, %s excluded (fixtures/, evals/, spec, constitution, requirement index), %s binary not read\n' \
  "$N_COMMITS" "$(awk 'END { print NR }' "$WORK/read.txt")" \
  "$(awk 'END { print NR }' "$WORK/excluded.txt")" "$(awk 'END { print NR }' "$WORK/binary.txt")"
while IFS= read -r b; do
  [ -n "$b" ] || continue
  printf '  not read, binary: %s\n' "$b"
done < "$WORK/binary.txt"

# --- EXAMPLE blocks, from each read file as it stands at HEAD -------------------
#
# A marker counts only at the START of a line, after optional whitespace and an
# optional `#` or `//` comment leader. Anywhere else it is a mention, and
# opens nothing. Well-formed only: a BEGIN opens a block only if an END
# follows it, and a line carrying BEGIN and END together is an example line
# on its own.
: > "$WORK/example.tsv"
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  git -C "$TOP" show "$HEAD_SHA:$rel" > "$WORK/blob" ||
    die_unmeasured "cannot read $rel at $HEAD_SHORT, so whether its added lines sit in an EXAMPLE block is unknown"
  LC_ALL=C awk -v F="$rel" '
    function isb(l) { return l ~ /^[ \t]*((#|\/\/)[ \t]*)?<!-- EXAMPLE:BEGIN/ }
    function ise(l) { return l ~ /^[ \t]*((#|\/\/)[ \t]*)?(<!-- )?EXAMPLE:END/ }
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (!isb(line[i])) continue
        if (index(line[i], "EXAMPLE:END")) { print F "\t" i; continue }
        for (j = i + 1; j <= NR; j++) if (ise(line[j])) break
        if (j <= NR) { for (k = i; k <= j; k++) print F "\t" k; i = j }
      }
    }
  ' "$WORK/blob" >> "$WORK/example.tsv"
done < "$WORK/read.txt"

# --- resolve every citation on every added line --------------------------------
LC_ALL=C awk -F'\t' -v REQS="$WORK/reqs.tsv" -v EXAMPLES="$WORK/example.tsv" \
    -v READ="$WORK/read.txt" -v NEXT="$NEXT_ID" -v COUNTS="$WORK/counts" '
  BEGIN {
    while ((getline r < REQS) > 0) {
      split(r, p, "\t"); st[p[1]] = p[3]; tg[p[1]] = p[4]
    }
    while ((getline r < EXAMPLES) > 0) ex[r] = 1
    while ((getline r < READ) > 0) rd[r] = 1
    lines = 0; cites = 0; finds = 0; notes = 0; exs = 0
  }
  function final(id,   cur, hops) {
    cur = id; hops = 0
    while (st[cur] == "superseded" && hops < 100) {
      if (!(tg[cur] in st)) return tg[cur] " (not in the spec)"
      cur = tg[cur]; hops++
    }
    if (hops >= 100) return "a cycle"
    if (st[cur] == "active") return cur
    return cur " (" st[cur] ")"
  }
  !($1 in rd) { next }
  {
    lines++
    s = $3; seen = ""
    while (match(s, /R[0-9]+/)) {
      bc = (RSTART == 1) ? "" : substr(s, RSTART - 1, 1)
      ac = substr(s, RSTART + RLENGTH, 1)
      id = substr(s, RSTART, RLENGTH)
      s = substr(s, RSTART + RLENGTH)
      if (bc ~ /[A-Za-z0-9_]/ || ac ~ /[A-Za-z0-9_]/) continue
      if (index(seen, " " id " ")) continue
      seen = seen " " id " "
      cites++
      where = $1 ":" $2
      if (($1 "\t" $2) in ex) { exs++; printf "EXAMPLE %s %s (inside an EXAMPLE block, not resolved)\n", where, id; continue }
      if (id in st) {
        if (st[id] == "superseded") { notes++; printf "NOTE CITATION_SUPERSEDED %s %s -> %s\n", where, id, final(id) }
        else if (st[id] == "withdrawn") { notes++; printf "NOTE CITATION_WITHDRAWN %s %s\n", where, id }
        continue
      }
      if (id == "R0") { exs++; printf "EXAMPLE %s %s (the reserved example id: ids start at R1, so it is never allocated and is not resolved)\n", where, id; continue }
      if (id ~ /^R0/) { finds++; printf "FINDING CITATION_NEVER_ALLOCATED %s %s\n", where, id; continue }
      if (substr(id, 2) + 0 >= NEXT + 0) { finds++; printf "FINDING CITATION_NEVER_ALLOCATED %s %s\n", where, id }
      else { finds++; printf "FINDING CITATION_ALLOCATED_MISSING %s %s\n", where, id }
    }
  }
  END { print lines "\t" cites "\t" finds "\t" notes "\t" exs > COUNTS }
' "$WORK/added.tsv"

IFS="$(printf '\t')" read -r N_LINES N_CITES N_FIND N_NOTES N_EX < "$WORK/counts"

# --- the trailers of every commit in the range ---------------------------------
git -C "$TOP" rev-list --reverse "$BASE_SHA..$HEAD_SHA" > "$WORK/commits.txt" ||
  die_unmeasured "git rev-list $BASE..$HEAD_REF failed, so which commits to validate is unknown"
n_valid=0
n_untrailed=0
n_bad=0
while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  trc=0
  bash "$TRAILER" --validate --rev "$sha" --repo "$TOP" --spec "$WORK/spec.md" \
    > "$WORK/t.out" 2> "$WORK/t.err" || trc=$?
  case "$trc" in
    0) n_valid=$((n_valid + 1)) ;;
    4) n_untrailed=$((n_untrailed + 1)) ;;
    3)
      n_bad=$((n_bad + 1))
      # Two sentences req-trailer.sh writes for a 3, matched on their fixed
      # text. The quote is passed in rather than escaped inside a regex, where
      # mawk and the BSD awk do not agree on octal escapes.
      awk -v sha="$sha" -v q="'" '
        /^req-trailer: R[0-9]+ is cited by commit / { print "FINDING TRAILER_UNKNOWN_ID " sha " " $2; next }
        index($0, "req-trailer: " q) == 1 && index($0, q " in the trailer of commit ") {
          t = substr($0, length("req-trailer: " q) + 1)
          t = substr(t, 1, index(t, q " in the trailer of commit ") - 1)
          print "FINDING TRAILER_MALFORMED_ID " sha " " t
        }
      ' "$WORK/t.err" > "$WORK/t.find"
      [ -s "$WORK/t.find" ] ||
        die_unmeasured "req-trailer.sh exited 3 for $sha and named no id this check can read: $(tr '\n' ' ' < "$WORK/t.err"). Its output format moved; nothing below it was counted."
      cat "$WORK/t.find"
      N_FIND=$((N_FIND + $(awk 'END { print NR }' "$WORK/t.find")))
      ;;
    *)
      die_unmeasured "req-trailer.sh exited $trc validating $sha: $(tr '\n' ' ' < "$WORK/t.err"). The trailers of this range are unvalidated, so this is not a pass." ;;
  esac
done < "$WORK/commits.txt"

printf 'trailers: %s commit(s) validated, %s carry no trailer (not a finding here), %s named an id the spec does not hold or a token that is no id\n' \
  "$n_valid" "$n_untrailed" "$n_bad"
printf 'summary: lines read %s, citations %s, findings %s, notes %s, inside EXAMPLE blocks %s\n' \
  "$N_LINES" "$N_CITES" "$N_FIND" "$N_NOTES" "$N_EX"
printf 'NOT READ: lines that already existed at the merge base, and any id not written as R and digits.\n'

if [ "$N_FIND" -gt 0 ]; then
  printf 'FAIL: this change adds %s citation(s) or trailer id(s) that resolve to no requirement in %s at %s.\n' \
    "$N_FIND" "$SPECREL" "$HEAD_SHORT" >&2
  exit 1
fi
printf 'PASS: every citation this change added resolves in %s at %s.\n' "$SPECREL" "$HEAD_SHORT"
