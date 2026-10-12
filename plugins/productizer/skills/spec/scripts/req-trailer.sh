#!/usr/bin/env bash
# req-trailer.sh — the join between a permanent requirement id and the commits
#                  that implement it, and between a requirement and its tests.
#
# The spec already owns the hard half: ids that are never reused and never
# renumbered. What was missing is the other direction. Given R14, nothing could
# answer "which commits built this", and given a commit, nothing recorded which
# agreement it served. The join is one git trailer:
#
#     Productizer-Req: R14,R22
#
# A trailer is the cheapest provenance mechanism there is. It is part of the
# commit message, so it survives clone, fetch, rebase, cherry-pick, format-patch
# and mirroring with no infrastructure at all, and it is queryable with
# `git log --grep` on a machine that has never heard of this repo's tooling.
# There is no database to keep in step, nothing to migrate, and nothing that
# rots when the tool that wrote it is uninstalled.
#
# THE OTHER HALF: COVERAGE IDS.
#
#   A commit says a requirement was built. It does not say it is tested. A
#   coverage id says that, and it is deliberately NOT a second id authority:
#
#     COV_<requirement-id>_<slug>
#
#   For R14 that is COV_ followed by R14 followed by _halts_on_contradiction.
#   This file does not spell a whole one out on purpose. --coverage scans every
#   tracked file in the repository it is pointed at, and this script gets
#   vendored INTO those repositories — a literal example in this header would
#   be read as genuine coverage of a genuine requirement, which is the exact
#   false positive the mode exists to expose. references/traceability.md does
#   spell them out, and says so.
#
#   The requirement id is quoted verbatim inside the coverage id, so a coverage
#   id cannot exist without naming a requirement, cannot be renumbered
#   independently, and stops resolving the moment the requirement it names stops
#   existing. That is the point: it makes an orphan mechanically detectable in
#   both directions — a requirement nothing covers, and a coverage id pointing
#   at a requirement that is gone or superseded.
#
#   Full convention: references/traceability.md.
#
# WHO DID THE WORK: `Assisted-by:`.
#
#   The requirement trailer says WHICH agreement a commit served. It says
#   nothing about who or what wrote it, and on this repository that is not a
#   detail — most of these commits were written by a model.
#
#   The Linux kernel is the only major project that has written the rule down,
#   so this follows it verbatim rather than inventing a house style
#   (Documentation/process/coding-assistants.rst, quoted):
#
#     "AI agents MUST NOT add Signed-off-by tags. Only humans can legally
#      certify the Developer Certificate of Origin (DCO)."
#
#     "Contributions should include an Assisted-by tag in the following
#      format::  Assisted-by: LLM [TOOL1] [TOOL2]"
#
#     "Basic development tools (git, gcc, make, editors) should not be listed."
#
#   Source: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/Documentation/process/coding-assistants.rst
#
#   THREE TRAILERS, AND ONLY ONE OF THEM IS OURS TO WRITE.
#
#     Signed-off-by   a legal certification of the DCO. A model cannot hold
#                     one, so this script never writes one and never offers to.
#     Co-authored-by  git and every forge resolve it to a PERSON: it takes a
#                     name and an address, it appears in contributor lists, and
#                     it makes a person-shaped claim about the commit. Putting
#                     a model in it is the same false claim as Signed-off-by
#                     wearing a friendlier word, so this script refuses it too.
#     Assisted-by     what is actually true, and the only one written here.
#
#   `--assisted-by` writes the kernel's exact form, `Assisted-by: LLM`, and
#   `--tools` appends the specialised analysis tools the kernel's format allows.
#   The word LLM is the whole identity on purpose: the kernel names no vendor
#   and no model, and a trailer naming a version that will be retired is a
#   provenance record with a shelf life.
#
#   `--authorship` reads the OTHER direction: given a message, it reports what
#   the message claims about who wrote it, and refuses two things — a DCO
#   certification or a co-authorship credit whose identity looks like an agent
#   rather than a person, and an `Assisted-by` that is not in the kernel's form.
#   What it CANNOT do is tell whether a commit carrying no authorship trailer
#   at all was assisted. That is unknowable from the message, so it is exit 4,
#   never a clean bill of health.
#
# MODES.
#
#   --add <ids> --file <msg>   merge the trailer into a commit-message file.
#                              Idempotent: run twice, and the file is unchanged.
#     [--assisted-by [--tools "<t1> <t2>"]]
#                              also merge `Assisted-by: LLM [tools]`.
#   --authorship [--file <msg> | --rev <rev>]
#                              what the message claims about who wrote it.
#   --validate [--file <msg> | --rev <rev>]
#                              every id in the trailer must exist in the spec.
#                              An unknown id is an error that names it.
#   --query <id>               the commits carrying that id.
#   --orphans                  active requirements no commit claims.
#   --coverage                 active requirements no COV_ id covers, plus
#                              COV_ ids naming a requirement that is gone or
#                              superseded.
#
# HOW IT REFUSES TO REPORT A ZERO IT DID NOT MEASURE.
#
#   "0 orphans" reads as a clean bill of health, and four different situations
#   can produce it. They are kept apart and none of them is printed as a zero:
#
#     no living spec                     -> exit 2. Nothing to trace.
#     not a git repository, or git broke -> exit 4. Nothing to trace against.
#     a repository with no commits yet   -> exit 4. No history to search.
#     commits, but not one carries a
#     trailer                            -> exit 4. The mechanism is not in use
#                                          here; coverage is UNKNOWN, not zero.
#
#   Only the fifth case — commits exist and some of them carry trailers — is a
#   measurement, and its report prints the counts it was measured from.
#   The same discipline applies to --coverage: no file could be listed, or not
#   one file carries a COV_ id, are both "cannot determine", not "0 uncovered".
#
# WHAT IT SEARCHES, AND WHAT IT THEREFORE CANNOT SEE.
#
#   --query and --orphans read `git log HEAD` — the full ancestry of HEAD, every
#   parent of every merge included, and nothing outside it. A commit that exists
#   only on another branch, or only on a remote that has not been fetched, is
#   invisible, and its requirement therefore looks orphaned. A shallow
#   clone is worse: it looks like a short history rather than a truncated one.
#   The report always names how many commits it actually walked, so a suspicious
#   answer can be recognised as one. KNOWN_LIMITATIONS.md has the rest.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  ran, and there is nothing to report. Backed by printed counts.
#   1  crashed before reaching a report. Read as undetermined, never as clean.
#   2  bad usage, or no spec / no requirement ids in it — nothing was compared.
#   3  a finding: an unknown id, an orphaned requirement, a dangling coverage
#      id. The run succeeded; what it found did not.
#   4  CANNOT DETERMINE. Not a pass, and not a zero.
#
# `--version` prints the version string. `--selftest` drives every code above
# in a sandbox and exits 0 when every case held, 3 when one did not, and 4 when
# the corpus could not be built.
#
# It never suppresses stderr. An error and a genuine no-match look identical
# once hidden, and telling those two apart is the whole job.
#
# Every date it prints is pinned to UTC. A traceability record whose timestamps
# depend on the reader's laptop is not a record.
set -euo pipefail
export LC_ALL=C

TMP=""
on_exit() {
  status=$?
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then rm -rf "$TMP"; fi
  case "$status" in
    0 | 2 | 3 | 4) exit "$status" ;;
    *)
      printf 'req-trailer: exited %s before reaching a report. Undetermined, not clean.\n' "$status" >&2
      exit 1
      ;;
  esac
}
trap on_exit EXIT

VERSION="req-trailer 1.0"
TRAILER_KEY="Productizer-Req"
ASSIST_KEY="Assisted-by"
SPEC_REL=".claude/productizer/spec.md"

# The kernel's own exclusion, quoted above: "Basic development tools (git, gcc,
# make, editors) should not be listed." Named here so a refusal can say which
# rule it is enforcing and where the rule came from. `clang` is on the list and
# `clang-tidy` is deliberately NOT, because the kernel names clang-tidy as an
# example of a tool that SHOULD be listed.
BASIC_TOOLS="git gcc g++ cc clang make cmake ninja ld as vi vim emacs nano ed sed awk bash sh zsh"

# Identities that must never appear in a Signed-off-by or a Co-authored-by.
# THIS IS A WORD LIST OVER FREE TEXT, and it is wrong in both directions: a
# vendor it does not name walks past it, and a person legitimately called
# `Roberta Botticelli` would be flagged by a substring rule, which is why every
# entry is matched on a word boundary. A clean --authorship run therefore does
# NOT prove a human signed; it proves no NAMED agent did. Said out loud in the
# report rather than left for the reader to discover.
AGENT_WORDS="claude anthropic gpt openai copilot cursor codeium codex gemini llm bot devin aider windsurf"

die_usage() { printf 'req-trailer: %s\n' "$1" >&2; exit 2; }
undetermined() { printf 'req-trailer: CANNOT DETERMINE — %s\n' "$1" >&2; exit 4; }

usage() {
  cat <<'USAGE'
req-trailer.sh — requirement-id traceability, both directions.

  req-trailer.sh --add R14,R22 --file .git/COMMIT_EDITMSG
        [--assisted-by [--tools "coccinelle sparse"]]
  req-trailer.sh --validate [--file <msg> | --rev <rev>]
  req-trailer.sh --authorship [--file <msg> | --rev <rev>]
  req-trailer.sh --query R14 [--limit N]
  req-trailer.sh --orphans
  req-trailer.sh --coverage [--include-ignored]

Authorship options (--add):
  --assisted-by    also write `Assisted-by: LLM`, the Linux kernel's form.
                   Signed-off-by and Co-authored-by are never written: only a
                   human can certify the DCO, and Co-authored-by credits a
                   person. See the header for the quoted rule.
  --tools "<list>" specialised analysis tools to append, space separated.
                   Requires --assisted-by. Basic development tools are refused.

Common options:
  --repo <dir>     repository root (default: current directory)
  --spec <path>    living spec (default: <repo>/.claude/productizer/spec.md)
  --limit <n>      most rows to print per section (default 50)
  -h, --help       this text
  --version        print the version and exit
  --selftest       drive every exit code in a sandbox; reads no repository

Exit: 0 nothing to report · 1 crashed · 2 usage/no spec · 3 a finding
      4 cannot determine (never printed as a zero)
USAGE
}

MODE=""
IDS_ARG=""
ASSISTED=0
TOOLS_ARG=""
FILE=""
REV=""
QUERY_ID=""
ROOT=""
SPEC=""
LIMIT=50
INCLUDE_IGNORED=0
SELFTEST=0

set_mode() {
  [ -z "$MODE" ] || die_usage "--$1 and --$MODE are two different jobs; run one at a time"
  MODE="$1"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --add)        set_mode add; [ "$#" -ge 2 ] || die_usage "--add needs one or more ids, e.g. --add R14,R22"; IDS_ARG="$2"; shift 2 ;;
    --add=*)      set_mode add; IDS_ARG="${1#--add=}"; shift ;;
    --validate)   set_mode validate; shift ;;
    --authorship) set_mode authorship; shift ;;
    --query)      set_mode query; [ "$#" -ge 2 ] || die_usage "--query needs a requirement id, e.g. --query R14"; QUERY_ID="$2"; shift 2 ;;
    --query=*)    set_mode query; QUERY_ID="${1#--query=}"; shift ;;
    --orphans)    set_mode orphans; shift ;;
    --coverage)   set_mode coverage; shift ;;
    --file)       [ "$#" -ge 2 ] || die_usage "--file needs a path"; FILE="$2"; shift 2 ;;
    --file=*)     FILE="${1#--file=}"; shift ;;
    --rev)        [ "$#" -ge 2 ] || die_usage "--rev needs a revision"; REV="$2"; shift 2 ;;
    --rev=*)      REV="${1#--rev=}"; shift ;;
    --repo)       [ "$#" -ge 2 ] || die_usage "--repo needs a directory"; ROOT="$2"; shift 2 ;;
    --repo=*)     ROOT="${1#--repo=}"; shift ;;
    --spec)       [ "$#" -ge 2 ] || die_usage "--spec needs a path"; SPEC="$2"; shift 2 ;;
    --spec=*)     SPEC="${1#--spec=}"; shift ;;
    --limit)      [ "$#" -ge 2 ] || die_usage "--limit needs a number"; LIMIT="$2"; shift 2 ;;
    --limit=*)    LIMIT="${1#--limit=}"; shift ;;
    --include-ignored) INCLUDE_IGNORED=1; shift ;;
    --assisted-by) ASSISTED=1; shift ;;
    --tools)      [ "$#" -ge 2 ] || die_usage "--tools needs a space-separated list, e.g. --tools \"coccinelle sparse\""; TOOLS_ARG="$2"; shift 2 ;;
    --tools=*)    TOOLS_ARG="${1#--tools=}"; shift ;;
    -h | --help)  usage; exit 0 ;;
    --version)    printf '%s\n' "$VERSION"; exit 0 ;;
    --selftest)   SELFTEST=1; shift ;;
    -*)           die_usage "unknown option: $1" ;;
    *)            die_usage "unexpected argument '$1'. Paths go after --file, revisions after --rev." ;;
  esac
done

# ===========================================================================
# --selftest
#
# R39: every exit code in the contract above is driven by a case, each case
# asserts a sentence as well as a code, and every repository is built in a
# sandbox under mktemp, so nothing here reads or writes the repository this
# script is vendored into.
#
# Two kinds of token are BUILT, never written, for the reason the header gives
# for coverage ids: this file is scanned. A coverage id spelled out below would
# be read by --coverage as real coverage of a real requirement, and an id the
# spec does not hold would be read by check-citations.sh as a dangling
# citation on the commit that adds it.
#
# Its own exit codes: 0 every case held, 3 at least one did not (a finding
# about this script), 4 the corpus could not be built (cannot determine).
# ===========================================================================
selftest() {
  local self SB
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  SB="$(mktemp -d "${TMPDIR:-/tmp}/req-trailer-selftest.XXXXXX")" ||
    undetermined "could not create a sandbox, so no case was driven"
  SB="$(cd "$SB" && pwd -P)"
  # on_exit removes $TMP, so the sandbox is cleaned the same way a run's is.
  TMP="$SB"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

  local unk cov
  unk="R$((4 + 5))"
  cov="$(printf 'COV_%s_%s' R1 holds_one_spec)"

  st_git() { git -c user.email=selftest@example.invalid -c user.name=selftest \
               -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }
  st_spec() {
    mkdir -p "$1/.claude/productizer"
    {
      printf '# Living spec - selftest\n\nNext requirement id\n: R4\n\n## Requirements\n\n'
      printf -- '- **R1** \342\200\224 The lifecycle shall hold one spec.\n'
      printf -- '- **R2** \342\200\224 The lifecycle shall hold two specs.\n  Superseded by R3. Narrowed.\n'
      printf -- '- **R3** \342\200\224 The lifecycle shall hold one spec per product.\n'
    } > "$1/.claude/productizer/spec.md"
  }
  st_commit() { st_git -C "$1" add -A; st_git -C "$1" commit -q -m "$2"; }

  # repo: a base commit with no trailer, then one claiming R1 with an
  # Assisted-by, and one tracked file carrying a coverage id for R1 and one
  # for an id the spec never had.
  st_git init -q "$SB/repo" || undetermined "git init failed, so no case was driven"
  st_spec "$SB/repo"
  printf 'base\n' > "$SB/repo/README"
  st_commit "$SB/repo" "base"
  printf 'test %s\ntest %s\n' "$cov" "$(printf 'COV_%s_%s' "$unk" ghost)" > "$SB/repo/t.sh"
  st_commit "$SB/repo" "$(printf 'build R1\n\nProductizer-Req: R1\nAssisted-by: LLM')"

  # untrailed: commits, and not one carries a trailer. Also no coverage id.
  st_git init -q "$SB/untrailed"
  st_spec "$SB/untrailed"
  st_commit "$SB/untrailed" "base"

  mkdir -p "$SB/no-spec" "$SB/not-git"
  st_spec "$SB/not-git"

  printf 'subject\n\nbody\n' > "$SB/msg-plain"
  cp "$SB/msg-plain" "$SB/msg-add"
  cp "$SB/msg-plain" "$SB/msg-assist"
  printf 'subject\n\nProductizer-Req: R1,%s\n' "$unk" > "$SB/msg-unknown"
  printf 'subject\n\nProductizer-Req: R2\n' > "$SB/msg-superseded"
  printf 'subject\n\nCo-authored-by: Claude <noreply@example.invalid>\n' > "$SB/msg-agent"

  local failed=0 driven=0 codes=""
  st_case() {
    # st_case <name> <want-exit> <sentence (grep -F)> <args...>
    local name="$1" want="$2" say="$3" rc=0
    shift 3
    bash "$self" "$@" > "$SB/$name.out" 2> "$SB/$name.err" || rc=$?
    driven=$((driven + 1))
    codes="$codes$rc
"
    local why=""
    [ "$rc" -eq "$want" ] || why="exit $rc, expected $want"
    if ! grep -qF -- "$say" "$SB/$name.out" "$SB/$name.err"; then
      [ -n "$why" ] && why="$why; "
      why="${why}its output does not say what it was supposed to say"
    fi
    if [ -z "$why" ]; then
      printf '  held: case %-20s exit %d, and said so - %s\n' "$name" "$rc" "$say"
    else
      failed=$((failed + 1))
      printf '  FINDING: case %-20s %s - expected: %s\n' "$name" "$why" "$say"
      sed 's/^/      | /' "$SB/$name.out" "$SB/$name.err"
    fi
  }

  local -a R=(--repo "$SB/repo")
  {
    st_case add                 0 'Productizer-Req: R1'                        --add R1 --file "$SB/msg-add" "${R[@]}"
    st_case add-again           0 'already present and unchanged'              --add R1 --file "$SB/msg-add" "${R[@]}"
    st_case add-assisted        0 'Assisted-by: LLM'                           --add R1 --assisted-by --file "$SB/msg-assist" "${R[@]}"
    st_case validate-rev        0 '1 cited id(s) all exist'                    --validate --rev HEAD "${R[@]}"
    st_case validate-superseded 0 'is superseded in the spec'                  --validate --file "$SB/msg-superseded" "${R[@]}"
    st_case authorship          0 '1 Assisted-by trailer(s)'                   --authorship --rev HEAD "${R[@]}"
    st_case query               0 '1 commit(s) carry this id'                  --query R1 "${R[@]}"
    st_case add-unknown         3 'refusing to write a trailer naming an id'   --add "$unk" --file "$SB/msg-plain" "${R[@]}"
    st_case validate-unknown    3 "$unk is cited by"                           --validate --file "$SB/msg-unknown" "${R[@]}"
    st_case authorship-agent    3 'carries a Co-authored-by naming claude'     --authorship --file "$SB/msg-agent" "${R[@]}"
    st_case query-unclaimed     3 "No commit in HEAD's history claims R3"      --query R3 "${R[@]}"
    st_case orphans             3 'ORPHANED'                                   --orphans "${R[@]}"
    st_case coverage            3 'DANGLING'                                   --coverage "${R[@]}"
    st_case tools-basic         2 'is a basic development tool'                --add R1 --assisted-by --tools git --file "$SB/msg-plain" "${R[@]}"
    st_case no-mode             2 'pick one of'                                "${R[@]}"
    st_case no-spec             2 'no living spec'                             --validate --file "$SB/msg-plain" --repo "$SB/no-spec"
    st_case validate-none       4 "carries no 'Productizer-Req:' trailer"      --validate --file "$SB/msg-plain" "${R[@]}"
    st_case authorship-none     4 'makes NO claim'                             --authorship --file "$SB/msg-plain" "${R[@]}"
    st_case orphans-untrailed   4 'not one carries'                            --orphans --repo "$SB/untrailed"
    st_case coverage-none       4 'found no COV_R'                             --coverage --repo "$SB/untrailed"
    st_case not-git             4 'is not a git repository'                    --orphans --repo "$SB/not-git"
  }
  # Exit 1 is what a crash becomes, so a case has to crash it: a temporary
  # directory that cannot be made fails under `set -e` before any report.
  local rc=0
  TMPDIR="$SB/no-such-dir" bash "$self" --validate --file "$SB/msg-plain" --repo "$SB/repo" \
    > "$SB/crash.out" 2> "$SB/crash.err" || rc=$?
  driven=$((driven + 1))
  codes="$codes$rc
"
  if [ "$rc" -eq 1 ] && grep -qF 'before reaching a report. Undetermined, not clean.' "$SB/crash.err"; then
    printf '  held: case %-20s exit %d, and said so - %s\n' crash "$rc" 'Undetermined, not clean.'
  else
    failed=$((failed + 1))
    printf '  FINDING: case %-20s exit %d, expected 1 and "Undetermined, not clean."\n' crash "$rc"
  fi

  # The add case must have written exactly one trailer, and the second run
  # must have left the file byte-identical: idempotence is the claim.
  if [ "$(grep -c '^Productizer-Req: R1$' "$SB/msg-add")" -ne 1 ]; then
    failed=$((failed + 1))
    printf '  FINDING: case %-20s the message does not hold exactly one Productizer-Req: R1 line\n' add-again
  fi

  printf '  cases driven: %d. Cases that did not hold: %d\n' "$driven" "$failed"
  local reached missing="" want
  reached="$(printf '%s' "$codes" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  for want in 0 1 2 3 4; do
    grep -qx "$want" <<<"$codes" || missing="$missing $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2 3 4\n' "$reached"
  printf '    NOT ASSERTED: a squash-merged or indented trailer; --limit truncation; --include-ignored; --tools with a specialised tool name; a Signed-off-by naming an agent (the Co-authored-by path is driven, the Signed-off-by path is the same word list); a repository with no commits; and whether any commit actually implements the requirement its trailer claims, which nothing in this script can see.\n'
  if [ "$failed" -ne 0 ] || [ -n "$missing" ]; then
    [ -z "$missing" ] || printf 'FAIL: documented exit code(s) no case reached:%s\n' "$missing" >&2
    printf 'FAIL: %d case(s) did not produce the exit code and the sentence they declare.\n' "$failed" >&2
    exit 3
  fi
  printf '  PASS: every case produced the exit code and the sentence it declares.\n'
  exit 0
}

if [ "$SELFTEST" = 1 ]; then
  [ -z "$MODE" ] || die_usage "--selftest builds its own repositories; it takes no mode"
  selftest
fi

[ -n "$MODE" ] || { usage >&2; die_usage "pick one of --add, --validate, --authorship, --query, --orphans, --coverage"; }

# --tools without --assisted-by would silently write nothing, which is the one
# outcome a provenance tool must never produce quietly.
if [ -n "$TOOLS_ARG" ] && [ "$ASSISTED" = 0 ]; then
  die_usage "--tools names the tools that assisted; it needs --assisted-by to have something to attach them to. Nothing was written."
fi
if [ "$ASSISTED" = 1 ] && [ "$MODE" != add ]; then
  die_usage "--assisted-by writes a trailer, so it only means anything with --add. To READ what a message claims, use --authorship."
fi
case "$LIMIT" in '' | *[!0-9]*) die_usage "--limit must be a whole number, not '$LIMIT'" ;; esac
[ "$LIMIT" -gt 0 ] || die_usage "--limit must be at least 1"

[ -n "$ROOT" ] || ROOT="."
[ -d "$ROOT" ] || die_usage "no such directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"
[ -n "$SPEC" ] || SPEC="$ROOT/$SPEC_REL"

command -v git >/dev/null || die_usage "git is not on PATH. Every mode here is a git operation."

TMP="$(mktemp -d "${TMPDIR:-/tmp}/req-trailer.XXXXXX")"

SOH=$'\001'
STX=$'\002'

# --- the ids the spec actually holds ---------------------------------------
#
# Matches the requirement pattern stage-status.sh, build-view.sh and
# drift-reverse.sh already count on: a list item whose first bold run is the
# id, with the status marker on the line after it. Four readers of one shape
# disagree the moment one of them is edited, so the pattern is copied
# deliberately and said out loud in each place.
read_spec() {
  [ -f "$SPEC" ] || die_usage "no living spec at ${SPEC#"$ROOT"/}. There is nothing to trace ids against, so nothing was traced."
  awk '
    /^([-*][ \t]+)?\*\*R[0-9]+\*\*/ {
      if (match($0, /R[0-9]+/)) {
        cur = substr($0, RSTART, RLENGTH)
        st[cur] = "active"
        if (!(cur in seen)) { seen[cur] = 1; order[++n] = cur }
      }
      next
    }
    cur != "" {
      t = $0; sub(/^[ \t]+/, "", t)
      if (t ~ /^Superseded by/) { st[cur] = "superseded"; cur = ""; next }
      if (t ~ /^Withdrawn\./)   { st[cur] = "withdrawn";  cur = ""; next }
      cur = ""
    }
    END { for (i = 1; i <= n; i++) printf "%s\t%s\n", order[i], st[order[i]] }
  ' "$SPEC" >"$TMP/ids.tsv"

  N_IDS=$(awk 'END { print NR + 0 }' "$TMP/ids.tsv")
  if [ "$N_IDS" -eq 0 ]; then
    die_usage "${SPEC#"$ROOT"/} holds no ids matching '**R<n>**'. Nothing to trace against; this is not a clean tree."
  fi
  awk -F'\t' '$2 == "active"     { print $1 }' "$TMP/ids.tsv" | sort -u >"$TMP/active"
  awk -F'\t' '$2 == "superseded" { print $1 }' "$TMP/ids.tsv" | sort -u >"$TMP/superseded"
  awk -F'\t' '$2 == "withdrawn"  { print $1 }' "$TMP/ids.tsv" | sort -u >"$TMP/withdrawn"
  sort -u "$TMP/ids.tsv" | cut -f1 | sort -u >"$TMP/known"
  N_ACTIVE=$(awk 'END { print NR + 0 }' "$TMP/active")
  N_SUPER=$(awk 'END { print NR + 0 }' "$TMP/superseded")
  N_WITHDRAWN=$(awk 'END { print NR + 0 }' "$TMP/withdrawn")
}

# --- ids handed to us on the command line ----------------------------------
#
# Refuses rather than guesses. 'r14' and 'R-14' are not this repo's id format,
# and quietly repairing them would put a shape into commit history that the
# spec's own readers do not match.
normalise_ids() {
  printf '%s' "$1" | tr ',;' '  ' | tr -s '[:space:]' '\n' | awk '
    NF {
      if ($1 !~ /^R[0-9]+$/) {
        printf "req-trailer: '\''%s'\'' is not a requirement id. This spec numbers requirements R<n> — R14, R22 — and ids are never reused or renumbered.\n", $1 > "/dev/stderr"
        bad = 1
        next
      }
      print $1
    }
    END { if (bad) exit 2 }
  ' | sort -u -V
}

# --- what the history says --------------------------------------------------
N_COMMITS=0
N_TRAILED=0

scan_history() {
  if ! git -C "$ROOT" rev-parse --git-dir >"$TMP/gitdir" 2>"$TMP/git.err"; then
    undetermined "$ROOT is not a git repository, or git failed: $(tr '\n' ' ' <"$TMP/git.err")
No history means no commits to trace ids to. This is not zero orphans."
  fi
  if ! git -C "$ROOT" rev-parse --verify HEAD >"$TMP/head" 2>"$TMP/head.err"; then
    undetermined "this repository has no commits yet (no HEAD).
There is no history to search, so no requirement can be shown as traced or as orphaned. This is not zero orphans."
  fi

  TZ=UTC git -C "$ROOT" log \
    --date=format-local:'%Y-%m-%d %H:%M:%S' \
    --format="${SOH}%H${STX}%ad${STX}%s%n%B" >"$TMP/log" 2>"$TMP/log.err" \
    || die_usage "git log failed: $(tr '\n' ' ' <"$TMP/log.err")"

  awk -v SOH="$SOH" -v STX="$STX" -v PAIRS="$TMP/pairs.tsv" -v BAD="$TMP/badtok" -v COUNTS="$TMP/counts" '
    BEGIN { ncommit = 0; ntrail = 0; sha = ""; date = ""; subj = "" }
    substr($0, 1, 1) == SOH {
      ncommit++
      n = split(substr($0, 2), f, STX)
      sha = f[1]; date = (n >= 2 ? f[2] : ""); subj = (n >= 3 ? f[3] : "")
      has = 0
      next
    }
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (tolower(substr(line, 1, 16)) != "productizer-req:") next
      val = substr(line, 17)
      gsub(/[,;]/, " ", val)
      m = split(val, ids, /[ \t]+/)
      for (i = 1; i <= m; i++) {
        if (ids[i] == "") continue
        if (ids[i] ~ /^R[0-9]+$/) { s = ids[i] "\t" sha "\t" date "\t" subj; print s > PAIRS }
        else                      { s = ids[i] "\t" sha;                     print s > BAD }
      }
      if (!has) { has = 1; ntrail++ }
    }
    END { s = ncommit "\t" ntrail; print s > COUNTS }
  ' "$TMP/log"

  [ -f "$TMP/pairs.tsv" ] || : >"$TMP/pairs.tsv"
  [ -f "$TMP/badtok" ]    || : >"$TMP/badtok"
  N_COMMITS=$(cut -f1 "$TMP/counts")
  N_TRAILED=$(cut -f2 "$TMP/counts")

  if [ "$N_TRAILED" -eq 0 ]; then
    undetermined "walked $N_COMMITS commit(s) of HEAD's history and not one carries a '${TRAILER_KEY}:' trailer.
The mechanism is not in use in this repository, so requirement coverage here is UNKNOWN. Reporting it as '0 traced' or '$N_ACTIVE orphans' would both be inventions.
Install templates/prepare-commit-msg.sh, or add the trailer by hand, and this becomes measurable."
  fi
  cut -f1 "$TMP/pairs.tsv" | sort -u >"$TMP/traced"
}

# ===========================================================================
# --add
# ===========================================================================
if [ "$MODE" = add ]; then
  [ -n "$FILE" ] || die_usage "--add needs --file <commit-message-file>. It edits a message; it does not edit history."
  [ -f "$FILE" ] || die_usage "no such commit-message file: $FILE"
  [ -w "$FILE" ] || die_usage "commit-message file is not writable: $FILE"

  normalise_ids "$IDS_ARG" >"$TMP/want" || exit 3
  [ -s "$TMP/want" ] || die_usage "--add was given no usable requirement id"
  # EVERY refusal happens before the first byte is written. An earlier version
  # validated the tool list after the requirement trailer had already gone into
  # the file, so a refusal said "Nothing was written" over a message it had
  # just edited. Measured on --tools "git smatch", not reasoned about.
  : >"$TMP/tools.want"
  if [ "$ASSISTED" = 1 ] && [ -n "$TOOLS_ARG" ]; then
    printf '%s' "$TOOLS_ARG" | tr ',;' '  ' | tr -s '[:space:]' '\n' | awk 'NF' >"$TMP/tools.raw"
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      case "$t" in
        *:* | *[!A-Za-z0-9._+-]*)
          die_usage "'$t' is not a tool name. A tool token in an ${ASSIST_KEY} trailer is a bare name — coccinelle, sparse, smatch, clang-tidy. Nothing was written." ;;
      esac
      lower="$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')"
      for b in $BASIC_TOOLS; do
        if [ "$lower" = "$b" ]; then
          die_usage "'$t' is a basic development tool. The rule this trailer follows says: \"Basic development tools (git, gcc, make, editors) should not be listed.\" List the specialised analysis tools only. Nothing was written."
        fi
      done
      printf '%s\n' "$t" >>"$TMP/tools.want"
    done <"$TMP/tools.raw"
  fi


  # If the spec is reachable, an id that is not in it never reaches history.
  # A trailer naming an id nobody can resolve is worse than no trailer: it
  # reads as provenance and is not.
  if [ -f "$SPEC" ]; then
    read_spec
    comm -23 "$TMP/want" "$TMP/known" >"$TMP/unknown"
    if [ -s "$TMP/unknown" ]; then
      printf 'req-trailer: refusing to write a trailer naming %s that %s does not contain:\n' \
        "$(awk 'END { print (NR == 1 ? "an id" : "ids") }' "$TMP/unknown")" "${SPEC#"$ROOT"/}" >&2
      while IFS= read -r bad; do printf '  %s — not in the spec\n' "$bad" >&2; done <"$TMP/unknown"
      printf 'The commit message was NOT modified.\n' >&2
      exit 3
    fi
  fi

  # Existing value, if any. Merging rather than replacing is what makes a
  # second run a no-op AND makes two separate --add calls additive.
  awk '
    { line = $0; sub(/^[ \t]+/, "", line) }
    tolower(substr(line, 1, 16)) == "productizer-req:" { print substr(line, 17) }
  ' "$FILE" >"$TMP/existing.raw"

  if [ -s "$TMP/existing.raw" ]; then
    tr ',;' '  ' <"$TMP/existing.raw" | tr -s '[:space:]' '\n' \
      | awk '$1 ~ /^R[0-9]+$/ { print }' | sort -u -V >"$TMP/have"
  else
    : >"$TMP/have"
  fi

  sort -u -V "$TMP/want" "$TMP/have" >"$TMP/merged"
  MERGED_VALUE="$(paste -sd, - <"$TMP/merged")"

  # git interpret-trailers is the only correct placer of a trailer: it knows
  # where the trailer block ends, that '#' comment lines and a scissors line
  # are not part of the message, and that a subject-only message needs a blank
  # line first. Hand-rolled appending gets all three wrong.
  git interpret-trailers \
      --if-exists replace --if-missing add \
      --trailer "${TRAILER_KEY}: ${MERGED_VALUE}" \
      "$FILE" >"$TMP/msg.new" 2>"$TMP/it.err" \
    || die_usage "git interpret-trailers failed: $(tr '\n' ' ' <"$TMP/it.err")"

  if cmp -s "$FILE" "$TMP/msg.new"; then
    printf '%s: %s already present and unchanged (%s)\n' "$TRAILER_KEY" "$MERGED_VALUE" "$FILE"
  else
    cat "$TMP/msg.new" >"$FILE"
    printf '%s: %s\n' "$TRAILER_KEY" "$MERGED_VALUE"
  fi

  # --- Assisted-by ---------------------------------------------------------
  #
  # Written second and separately, because the two trailers answer different
  # questions and one being unavailable must not cost the other. A commit can
  # carry a requirement id and no assistance claim, or the reverse.
  if [ "$ASSISTED" = 1 ]; then
    # Merge with whatever the message already claims, the same way the ids are
    # merged: two runs are additive, and a second identical run changes nothing.
    awk '
      { line = $0; sub(/^[ \t]+/, "", line) }
      tolower(substr(line, 1, 12)) == "assisted-by:" { print substr(line, 13) }
    ' "$FILE" >"$TMP/assist.raw"

    : >"$TMP/tools.have"
    if [ -s "$TMP/assist.raw" ]; then
      tr -s '[:space:]' '\n' <"$TMP/assist.raw" \
        | awk 'NF && toupper($1) != "LLM" { print }' >"$TMP/tools.have"
    fi

    sort -u "$TMP/tools.want" "$TMP/tools.have" >"$TMP/tools.merged"
    ASSIST_VALUE="LLM"
    if [ -s "$TMP/tools.merged" ]; then
      ASSIST_VALUE="LLM $(paste -sd' ' - <"$TMP/tools.merged")"
    fi

    git interpret-trailers \
        --if-exists replace --if-missing add \
        --trailer "${ASSIST_KEY}: ${ASSIST_VALUE}" \
        "$FILE" >"$TMP/msg.assist" 2>"$TMP/ita.err" \
      || die_usage "git interpret-trailers failed writing ${ASSIST_KEY}: $(tr '\n' ' ' <"$TMP/ita.err")"

    if cmp -s "$FILE" "$TMP/msg.assist"; then
      printf '%s: %s already present and unchanged (%s)\n' "$ASSIST_KEY" "$ASSIST_VALUE" "$FILE"
    else
      cat "$TMP/msg.assist" >"$FILE"
      printf '%s: %s\n' "$ASSIST_KEY" "$ASSIST_VALUE"
    fi
    printf 'No Signed-off-by and no Co-authored-by was written, and neither ever is: only a human can certify the DCO, and Co-authored-by credits a person.\n'
  fi
  exit 0
fi

# ===========================================================================
# --validate
# ===========================================================================
if [ "$MODE" = validate ]; then
  [ -z "$FILE" ] || [ -z "$REV" ] || die_usage "--validate reads one message: --file or --rev, not both"
  read_spec

  if [ -n "$FILE" ]; then
    [ -f "$FILE" ] || die_usage "no such commit-message file: $FILE"
    SOURCE="$FILE"
    cp "$FILE" "$TMP/msg"
  else
    [ -n "$REV" ] || REV=HEAD
    SOURCE="commit $REV"
    git -C "$ROOT" log -1 --format=%B "$REV" >"$TMP/msg" 2>"$TMP/rev.err" \
      || die_usage "cannot read $REV: $(tr '\n' ' ' <"$TMP/rev.err")"
  fi

  awk '
    { line = $0; sub(/^[ \t]+/, "", line) }
    tolower(substr(line, 1, 16)) == "productizer-req:" { print substr(line, 17) }
  ' "$TMP/msg" >"$TMP/val.raw"

  if [ ! -s "$TMP/val.raw" ]; then
    undetermined "$SOURCE carries no '${TRAILER_KEY}:' trailer.
There is nothing to validate. An absent trailer is not a valid one — it is an untraced change."
  fi

  tr ',;' '  ' <"$TMP/val.raw" | tr -s '[:space:]' '\n' | awk 'NF' >"$TMP/tokens"
  awk '$1 !~ /^R[0-9]+$/' "$TMP/tokens" | sort -u >"$TMP/malformed"
  awk '$1 ~ /^R[0-9]+$/'  "$TMP/tokens" | sort -u >"$TMP/cited"

  comm -23 "$TMP/cited" "$TMP/known" >"$TMP/unknown"
  comm -12 "$TMP/cited" "$TMP/superseded" >"$TMP/cited.super"
  comm -12 "$TMP/cited" "$TMP/withdrawn"  >"$TMP/cited.withdrawn"

  N_CITED=$(awk 'END { print NR + 0 }' "$TMP/cited")
  fail=0

  if [ -s "$TMP/malformed" ]; then
    fail=1
    while IFS= read -r t; do
      printf "req-trailer: '%s' in the trailer of %s is not a requirement id. Ids are R<n>.\n" "$t" "$SOURCE" >&2
    done <"$TMP/malformed"
  fi
  if [ -s "$TMP/unknown" ]; then
    fail=1
    while IFS= read -r t; do
      printf 'req-trailer: %s is cited by %s but does not exist in %s. Either the id was mistyped, or it was invented, or the spec it was written against is not the spec here.\n' \
        "$t" "$SOURCE" "${SPEC#"$ROOT"/}" >&2
    done <"$TMP/unknown"
  fi

  # Superseded and withdrawn are NOT errors. An id keeps its sentence forever,
  # and a commit that touched a requirement before it was replaced is telling
  # the truth about the history it belongs to. It is worth saying out loud.
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    printf 'req-trailer: note — %s is cited by %s and is superseded in the spec. Correct for a commit made before the replacement; worth a look on a new one.\n' "$t" "$SOURCE" >&2
  done <"$TMP/cited.super"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    printf 'req-trailer: note — %s is cited by %s and is withdrawn in the spec.\n' "$t" "$SOURCE" >&2
  done <"$TMP/cited.withdrawn"

  if [ "$fail" = 1 ]; then
    printf 'req-trailer: %s did not validate.\n' "$SOURCE" >&2
    exit 3
  fi
  printf 'req-trailer: %s — %s cited id(s) all exist in %s (%s active, %s superseded, %s withdrawn on file).\n' \
    "$SOURCE" "$N_CITED" "${SPEC#"$ROOT"/}" "$N_ACTIVE" "$N_SUPER" "$N_WITHDRAWN"
  exit 0
fi

# ===========================================================================
# --authorship
#
# The other direction from --add: given a message, what does it CLAIM about
# who wrote it, and is any of that claim one a model cannot hold?
# ===========================================================================
if [ "$MODE" = authorship ]; then
  [ -z "$FILE" ] || [ -z "$REV" ] || die_usage "--authorship reads one message: --file or --rev, not both"

  if [ -n "$FILE" ]; then
    [ -f "$FILE" ] || die_usage "no such commit-message file: $FILE"
    SOURCE="$FILE"
    cp "$FILE" "$TMP/msg"
  else
    [ -n "$REV" ] || REV=HEAD
    SOURCE="commit $REV"
    git -C "$ROOT" log -1 --format=%B "$REV" >"$TMP/msg" 2>"$TMP/rev.err" \
      || die_usage "cannot read $REV: $(tr '\n' ' ' <"$TMP/rev.err")"
  fi

  awk '
    { line = $0; sub(/^[ \t]+/, "", line) }
    tolower(substr(line, 1,  12)) == "assisted-by:"    { print substr(line, 13)  > A }
    tolower(substr(line, 1,  14)) == "signed-off-by:"  { print substr(line, 15)  > S }
    tolower(substr(line, 1,  15)) == "co-authored-by:" { print substr(line, 16)  > C }
  ' A="$TMP/a.raw" S="$TMP/s.raw" C="$TMP/c.raw" "$TMP/msg"
  for f in a s c; do [ -f "$TMP/$f.raw" ] || : >"$TMP/$f.raw"; done

  N_ASSIST=$(awk 'END { print NR + 0 }' "$TMP/a.raw")
  N_SOB=$(awk 'END { print NR + 0 }' "$TMP/s.raw")
  N_COA=$(awk 'END { print NR + 0 }' "$TMP/c.raw")

  if [ "$N_ASSIST" -eq 0 ] && [ "$N_SOB" -eq 0 ] && [ "$N_COA" -eq 0 ]; then
    undetermined "$SOURCE carries no ${ASSIST_KEY}, Signed-off-by or Co-authored-by trailer.
The message makes NO claim about who wrote this change, so who wrote it is UNKNOWN. It is not evidence that a human wrote it, and it is not evidence that a model did.
Nothing in a commit message can settle this after the fact — the record has to be written at the time. \`req-trailer.sh --add --assisted-by\` writes it."
  fi

  # Does a value name an agent? Word-boundaried, so `Roberta` is not `bot`.
  names_agent() {
    local v="$1" w
    for w in $AGENT_WORDS; do
      if LC_ALL=C grep -Eqi -e "(^|[^A-Za-z0-9])${w}([^A-Za-z0-9]|\$)" <<<"$v"; then
        printf '%s\n' "$w"
        return 0
      fi
    done
    return 1
  }

  fail=0

  # 1. A DCO certification, or a co-authorship credit, naming an agent.
  #    "AI agents MUST NOT add Signed-off-by tags. Only humans can legally
  #     certify the Developer Certificate of Origin (DCO)."
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    if w="$(names_agent "$v")"; then
      fail=1
      printf 'req-trailer: %s carries a Signed-off-by naming %s, which reads as an agent. Only a human can certify the Developer Certificate of Origin, so this line claims something no model can hold. Use %s instead.\n' \
        "$SOURCE" "$w" "$ASSIST_KEY" >&2
    fi
  done <"$TMP/s.raw"

  while IFS= read -r v; do
    [ -n "$v" ] || continue
    if w="$(names_agent "$v")"; then
      fail=1
      printf 'req-trailer: %s carries a Co-authored-by naming %s, which reads as an agent. Co-authored-by takes a name and an address and is resolved to a PERSON by git and by every forge, so it makes a person-shaped claim a model cannot hold. Use %s instead.\n' \
        "$SOURCE" "$w" "$ASSIST_KEY" >&2
    fi
  done <"$TMP/c.raw"

  # 2. The form of the Assisted-by value itself.
  while IFS= read -r v; do
    trimmed="$(printf '%s' "$v" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')"
    if [ -z "$trimmed" ]; then
      fail=1
      printf 'req-trailer: %s carries an empty %s trailer. A trailer with no value records nothing while looking like a record.\n' "$SOURCE" "$ASSIST_KEY" >&2
      continue
    fi
    first="${trimmed%% *}"
    if [ "$(printf '%s' "$first" | tr '[:lower:]' '[:upper:]')" != "LLM" ]; then
      fail=1
      printf "req-trailer: %s has '%s: %s'. The form is 'LLM [TOOL1] [TOOL2]' — the first token is the literal word LLM, and the rest are specialised analysis tools.\n" \
        "$SOURCE" "$ASSIST_KEY" "$trimmed" >&2
      continue
    fi
    rest="${trimmed#"$first"}"
    for t in $rest; do
      lower="$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')"
      for b in $BASIC_TOOLS; do
        if [ "$lower" = "$b" ]; then
          fail=1
          printf 'req-trailer: %s lists %s in its %s trailer. Basic development tools (git, gcc, make, editors) should not be listed; the tag is for the specialised analysis tools.\n' \
            "$SOURCE" "$t" "$ASSIST_KEY" >&2
        fi
      done
    done
  done <"$TMP/a.raw"

  printf 'Authorship claimed by %s: %s %s trailer(s), %s Signed-off-by, %s Co-authored-by.\n' \
    "$SOURCE" "$N_ASSIST" "$ASSIST_KEY" "$N_SOB" "$N_COA"
  printf 'The rule: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/Documentation/process/coding-assistants.rst\n'
  printf 'WHAT THIS DID NOT MEASURE. The agent check is a word list over free text — %s names. A vendor it does not name walks straight past it, so a clean run shows that no NAMED agent signed off, never that a human did. And a message with no %s trailer is not a message written without assistance; it is a message that did not say.\n' \
    "$(printf '%s' "$AGENT_WORDS" | wc -w | tr -d ' ')" "$ASSIST_KEY"

  [ "$fail" = 0 ] || exit 3
  exit 0
fi

# ===========================================================================
# --query
# ===========================================================================
if [ "$MODE" = query ]; then
  normalise_ids "$QUERY_ID" >"$TMP/q" || exit 3
  [ "$(awk 'END { print NR + 0 }' "$TMP/q")" -eq 1 ] || die_usage "--query takes exactly one id"
  QID="$(cat "$TMP/q")"

  read_spec
  scan_history

  STATUS="$(awk -F'\t' -v id="$QID" '$1 == id { print $2 }' "$TMP/ids.tsv")"
  [ -n "$STATUS" ] || STATUS="NOT IN THE SPEC"

  # `git log --grep` is the coarse filter — the thing anyone can run without
  # this script, which is the point of using a trailer at all. It is a regex
  # over the message, so R1 would also match the R14 line; the exact
  # membership test happens after, on the parsed ids.
  #
  # The pattern is deliberately NOT anchored with ^. A squash merge indents
  # every line of the messages it swallows, so `--grep='^Productizer-Req:'`
  # silently misses squashed commits — measured, on `git merge --squash`. The
  # unanchored form finds them, at the cost of also matching the words in a
  # commit message that talks about the trailer.
  TZ=UTC git -C "$ROOT" log --grep="${TRAILER_KEY}:" \
    --date=format-local:'%Y-%m-%d %H:%M:%S' --format='%H' >"$TMP/grepped" 2>"$TMP/grep.err" \
    || die_usage "git log --grep failed: $(tr '\n' ' ' <"$TMP/grep.err")"
  N_GREPPED=$(awk 'END { print NR + 0 }' "$TMP/grepped")

  awk -F'\t' -v id="$QID" '$1 == id { print $2 "\t" $3 "\t" $4 }' "$TMP/pairs.tsv" >"$TMP/hits"
  N_HITS=$(awk 'END { print NR + 0 }' "$TMP/hits")

  printf '%s — %s\n' "$QID" "$STATUS"
  printf '%s commit(s) carry this id. Walked %s commit(s); %s carry a %s trailer; git log --grep matched %s.\n\n' \
    "$N_HITS" "$N_COMMITS" "$N_TRAILED" "$TRAILER_KEY" "$N_GREPPED"
  if [ "$N_HITS" -gt 0 ]; then
    awk -F'\t' -v lim="$LIMIT" 'NR <= lim { printf "  %s  %s UTC  %s\n", substr($1, 1, 12), $2, $3 }' "$TMP/hits"
    if [ "$N_HITS" -gt "$LIMIT" ]; then
      printf '  ... and %s more (raise --limit)\n' "$(( N_HITS - LIMIT ))"
    fi
    printf '\nThe same query on any machine, without this script — a regex, so it over-matches\n(%s also matches %s4, %s7...); the exact membership test above is this script'"'"'s only addition.\nNo ^ anchor: a squash merge indents the trailer and an anchored pattern misses it.\n  TZ=UTC git log --grep='"'"'%s:.*%s'"'"'\n' \
      "$QID" "$QID" "$QID" "$TRAILER_KEY" "$QID"
    exit 0
  fi
  printf 'No commit in HEAD'"'"'s history claims %s. It may be unbuilt, built without a trailer, or built on a branch not merged here.\n' "$QID" >&2
  exit 3
fi

# ===========================================================================
# --orphans
# ===========================================================================
if [ "$MODE" = orphans ]; then
  read_spec
  scan_history

  comm -23 "$TMP/active" "$TMP/traced" >"$TMP/orphans"
  comm -13 "$TMP/known"  "$TMP/traced" >"$TMP/ghosts"
  N_ORPHANS=$(awk 'END { print NR + 0 }' "$TMP/orphans")
  N_GHOSTS=$(awk 'END { print NR + 0 }' "$TMP/ghosts")
  N_TRACED=$(awk 'END { print NR + 0 }' "$TMP/traced")

  printf 'Requirement -> commit traceability, %s\n' "$ROOT"
  printf 'Spec: %s — %s active, %s superseded, %s withdrawn.\n' \
    "${SPEC#"$ROOT"/}" "$N_ACTIVE" "$N_SUPER" "$N_WITHDRAWN"
  printf 'History: walked %s commit(s) of HEAD; %s carry a %s trailer; %s distinct id(s) claimed.\n\n' \
    "$N_COMMITS" "$N_TRAILED" "$TRAILER_KEY" "$N_TRACED"

  if [ "$N_ORPHANS" -gt 0 ]; then
    printf 'ORPHANED — active, and no commit claims it (%s):\n' "$N_ORPHANS"
    awk -v lim="$LIMIT" 'NR <= lim { printf "  %s\n", $0 }' "$TMP/orphans"
    [ "$N_ORPHANS" -le "$LIMIT" ] || printf '  ... and %s more (raise --limit)\n' "$(( N_ORPHANS - LIMIT ))"
    printf '\n'
  fi
  if [ "$N_GHOSTS" -gt 0 ]; then
    printf 'CLAIMED BUT UNKNOWN — a commit cites an id the spec does not contain (%s):\n' "$N_GHOSTS"
    awk -v lim="$LIMIT" 'NR <= lim { printf "  %s\n", $0 }' "$TMP/ghosts"
    [ "$N_GHOSTS" -le "$LIMIT" ] || printf '  ... and %s more (raise --limit)\n' "$(( N_GHOSTS - LIMIT ))"
    printf '\n'
  fi

  if [ "$N_ORPHANS" -eq 0 ] && [ "$N_GHOSTS" -eq 0 ]; then
    printf 'Every active requirement is claimed by at least one commit, and every claimed id exists. Measured from the counts above.\n'
    exit 0
  fi
  exit 3
fi

# ===========================================================================
# --coverage
# ===========================================================================
if [ "$MODE" = coverage ]; then
  read_spec

  FILE_SRC=""
  if [ "$INCLUDE_IGNORED" = 1 ]; then
    FILE_SRC="find (gitignored files included)"
    ( cd "$ROOT" && find . -name .git -prune -o -type f -print0 ) >"$TMP/files.z" 2>"$TMP/find.err" \
      || undetermined "could not walk $ROOT: $(tr '\n' ' ' <"$TMP/find.err")"
  elif git -C "$ROOT" rev-parse --git-dir >"$TMP/gitdir" 2>"$TMP/git.err"; then
    FILE_SRC="git ls-files (gitignored files NOT scanned)"
    git -C "$ROOT" ls-files -z >"$TMP/files.z" 2>"$TMP/ls.err" \
      || undetermined "git ls-files failed: $(tr '\n' ' ' <"$TMP/ls.err")"
  else
    FILE_SRC="find (not a git repository)"
    ( cd "$ROOT" && find . -name .git -prune -o -type f -print0 ) >"$TMP/files.z" 2>"$TMP/find.err" \
      || undetermined "could not walk $ROOT: $(tr '\n' ' ' <"$TMP/find.err")"
  fi

  N_FILES=$(tr -dc '\0' <"$TMP/files.z" | wc -c | tr -d ' ')
  if [ "$N_FILES" -eq 0 ]; then
    undetermined "no file could be listed in $ROOT via $FILE_SRC.
Nothing was scanned, so no requirement can be shown as covered or uncovered. This is not zero uncovered."
  fi

  # xargs exits 123 when any grep in the batch found nothing, which is the
  # normal case for most batches. 124-127 are real failures.
  xrc=0
  ( cd "$ROOT" && xargs -0 grep -oIHE 'COV_R[0-9]+[A-Za-z0-9_]*' ) \
    <"$TMP/files.z" >"$TMP/cov.raw" 2>"$TMP/grep.err" || xrc=$?
  case "$xrc" in
    0 | 1 | 123) ;;
    *) undetermined "the coverage scan failed (xargs/grep exit $xrc): $(tr '\n' ' ' <"$TMP/grep.err")" ;;
  esac

  awk '
    {
      p = match($0, /COV_R[0-9]+[A-Za-z0-9_]*$/)
      if (!p) next
      tok = substr($0, p)
      file = (p >= 3 ? substr($0, 1, p - 2) : "?")
      q = match(tok, /R[0-9]+/)
      id = substr(tok, q, RLENGTH)
      print id "\t" tok "\t" file
    }
  ' "$TMP/cov.raw" | sort -u >"$TMP/cov.tsv"

  N_COV=$(awk 'END { print NR + 0 }' "$TMP/cov.tsv")
  if [ "$N_COV" -eq 0 ]; then
    undetermined "scanned $N_FILES file(s) via $FILE_SRC and found no COV_R<n> identifier.
The coverage convention is not in use in this repository, so test coverage of requirements here is UNKNOWN. Reporting '$N_ACTIVE uncovered' would state as a finding something that was never measured.
references/traceability.md has the convention."
  fi

  cut -f1 "$TMP/cov.tsv" | sort -u >"$TMP/covered"
  comm -23 "$TMP/active" "$TMP/covered" >"$TMP/uncovered"
  N_UNCOVERED=$(awk 'END { print NR + 0 }' "$TMP/uncovered")

  # A coverage id naming an id the spec never had: invented, mistyped, or
  # written against a different spec.
  awk -F'\t' 'NR == FNR { k[$1] = 1; next } !($1 in k)' "$TMP/known" "$TMP/cov.tsv" >"$TMP/dangling"
  # A coverage id naming a requirement that no longer stands. The id resolves,
  # the agreement behind it does not — drift-reverse.sh signal A, seen from the
  # test side instead of the code side.
  awk -F'\t' 'NR == FNR { k[$1] = 1; next } ($1 in k)' "$TMP/superseded" "$TMP/cov.tsv" >"$TMP/stale"
  awk -F'\t' 'NR == FNR { k[$1] = 1; next } ($1 in k)' "$TMP/withdrawn"  "$TMP/cov.tsv" >>"$TMP/stale"
  N_DANGLING=$(awk 'END { print NR + 0 }' "$TMP/dangling")
  N_STALE=$(awk 'END { print NR + 0 }' "$TMP/stale")
  N_COVERED=$(awk 'END { print NR + 0 }' "$TMP/covered")

  printf 'Requirement -> coverage traceability, %s\n' "$ROOT"
  printf 'Spec: %s — %s active, %s superseded, %s withdrawn.\n' \
    "${SPEC#"$ROOT"/}" "$N_ACTIVE" "$N_SUPER" "$N_WITHDRAWN"
  printf 'Scan: %s file(s) via %s; %s COV_ identifier(s) naming %s distinct id(s).\n\n' \
    "$N_FILES" "$FILE_SRC" "$N_COV" "$N_COVERED"

  if [ "$N_UNCOVERED" -gt 0 ]; then
    printf 'UNCOVERED — active, and no COV_ identifier names it (%s):\n' "$N_UNCOVERED"
    awk -v lim="$LIMIT" 'NR <= lim { printf "  %s\n", $0 }' "$TMP/uncovered"
    [ "$N_UNCOVERED" -le "$LIMIT" ] || printf '  ... and %s more (raise --limit)\n' "$(( N_UNCOVERED - LIMIT ))"
    printf '\n'
  fi
  if [ "$N_DANGLING" -gt 0 ]; then
    printf 'DANGLING — a COV_ identifier names an id the spec does not contain (%s):\n' "$N_DANGLING"
    awk -F'\t' -v lim="$LIMIT" 'NR <= lim { printf "  %-34s %s  (no such requirement)\n", $2, $3 }' "$TMP/dangling"
    [ "$N_DANGLING" -le "$LIMIT" ] || printf '  ... and %s more (raise --limit)\n' "$(( N_DANGLING - LIMIT ))"
    printf '\n'
  fi
  if [ "$N_STALE" -gt 0 ]; then
    printf 'STALE — a COV_ identifier names a requirement that no longer stands (%s):\n' "$N_STALE"
    awk -F'\t' -v lim="$LIMIT" 'NR <= lim { printf "  %-34s %s  (%s is superseded or withdrawn)\n", $2, $3, $1 }' "$TMP/stale"
    [ "$N_STALE" -le "$LIMIT" ] || printf '  ... and %s more (raise --limit)\n' "$(( N_STALE - LIMIT ))"
    printf '\n'
  fi

  if [ "$N_UNCOVERED" -eq 0 ] && [ "$N_DANGLING" -eq 0 ] && [ "$N_STALE" -eq 0 ]; then
    printf 'Every active requirement is named by at least one COV_ identifier, and every COV_ identifier names a standing requirement. Measured from the counts above.\n'
    exit 0
  fi
  exit 3
fi

die_usage "unreachable: mode '$MODE' has no implementation"
