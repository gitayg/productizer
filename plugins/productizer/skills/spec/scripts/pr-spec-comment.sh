#!/usr/bin/env bash
# pr-spec-comment.sh [repo-root] [--base REF] [--checks PATH]
#                    [--selftest] [--version] [--help]
#
# Renders what a change did to the living spec, as markdown, for a human to
# paste onto a pull request.
#
# IT RENDERS TO STDOUT AND POSTS NOTHING. That is not a missing feature; it is
# the design. Posting to a pull request is a PUBLISH, and this repository routes
# every publish through `.claude/hooks/publish-gate.sh`, which demands a written
# checklist naming the exact command and a person who decided to run it. A
# script that posted this by itself would be a publish routed around the
# product's own central mechanism, inside the repository that ships it. So
# `--post` is REFUSED with a sentence rather than left unimplemented, and the
# footer of every report names the command a person may choose to run.
#
# WHAT IT DOES NOT COMPUTE ITSELF. The spec delta comes from `spec-diff.sh`,
# which already resolves the base ref, reads both files at both ends, caps an
# oversized diff instead of truncating it, and separates "unchanged" from "no
# baseline" from "the ref does not resolve". Re-deriving any of that here would
# give this repository two answers to one question. This reads spec-diff.sh's
# output, and the base commit spec-diff.sh reports is the base EVERY other
# section is measured against, so one resolution of one ref anchors the whole
# report.
#
# NOTHING UNMEASURED IS RENDERED AS ZERO. "The change adds no requirement",
# "the base ref does not resolve", "the diff was over the cap so it was not
# read" and "the spec is not readable" all end in an empty id list, and they are
# four different facts. Each gets its own sentence; the ones that are an absence
# of measurement rather than a measured absence are marked NOT MEASURED and
# change the exit code, so a caller can tell the report is partial without
# reading it.
#
# Exit: 0 rendered, every section measured
#       2 usage, or a refused publish
#       3 not a git work tree, no such directory, spec-diff.sh unusable, or no evals/solver-probe.py
#       5 rendered, but at least one section could NOT be measured and says so
#
# THE PROBE IS REQUIRED (maintainer ruling 2026-10-12, B129). A repository with
# no readable evals/solver-probe.py is exit 3 before anything is rendered, not a
# partial report: the CI build template renders this report as every pull
# request's body, and an adopter without a probe would read "This report is
# partial" on every one. A probe that exists but fails or prints no counts is
# still a section marked NOT MEASURED, and exit 5.
#
# --selftest builds real repositories under mktemp -d, with the real sibling
# spec-diff.sh, and exits 0 when every case held and 1 when one did not.
set -euo pipefail

VERSION="pr-spec-comment 1.2"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HERE/$(basename -- "${BASH_SOURCE[0]}")"
SPEC_DIFF="$HERE/spec-diff.sh"

SPEC_REL=".claude/productizer/spec.md"
CLASS_REL=".claude/productizer/classifications"
PROBE_REL="evals/solver-probe.py"
CHECKS_REL=".claude/productizer/checks-result.json"

ROOT=""
BASE=""
CHECKS=""
SELFTEST=0

usage() {
  echo "usage: pr-spec-comment.sh [repo-root] [--base REF] [--checks PATH]"
  echo "       pr-spec-comment.sh --selftest | --version | --help"
  echo "Renders markdown to stdout. It posts nothing, by design - see the file header."
}

while [ $# -gt 0 ]; do
  case "$1" in
    --base)     BASE="${2:-}"; [ -n "$BASE" ] || { echo "pr-spec-comment: --base needs a ref" >&2; exit 2; }; shift 2 ;;
    --base=*)   BASE="${1#--base=}"; [ -n "$BASE" ] || { echo "pr-spec-comment: --base needs a ref" >&2; exit 2; }; shift ;;
    --checks)   CHECKS="${2:-}"; [ -n "$CHECKS" ] || { echo "pr-spec-comment: --checks needs a path" >&2; exit 2; }; shift 2 ;;
    --checks=*) CHECKS="${1#--checks=}"; [ -n "$CHECKS" ] || { echo "pr-spec-comment: --checks needs a path" >&2; exit 2; }; shift ;;
    --version)  echo "$VERSION"; exit 0 ;;
    --selftest|--self-test) SELFTEST=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    # Named explicitly, because somebody will try it and deserves the reason
    # rather than "unknown option".
    --post|--comment|--publish|--gh|--pr)
      echo "pr-spec-comment: $1 is REFUSED, and deliberately not implemented." >&2
      echo "Posting to a pull request is a publish. This repository puts every publish behind" >&2
      echo ".claude/hooks/publish-gate.sh, which requires a written checklist naming the exact" >&2
      echo "command and a person who decided to run it. Auto-posting from here would route" >&2
      echo "around that gate inside the repository that ships it." >&2
      echo "The markdown goes to stdout; the report's footer names the command." >&2
      exit 2 ;;
    -*)         echo "pr-spec-comment: unknown option: $1" >&2; exit 2 ;;
    *)          [ -z "$ROOT" ] || { echo "pr-spec-comment: only one repo-root" >&2; exit 2; }; ROOT="$1"; shift ;;
  esac
done

# ===========================================================================
# SELF-TEST. Real repositories under mktemp -d, the real spec-diff.sh beside
# this file, a stub solver probe, no network. Every case asserts an exit code
# AND a sentence of the report.
# ===========================================================================
selftest() {
  # Global, not local: the EXIT trap runs after this function has returned.
  ST="$(mktemp -d)" || { echo "pr-spec-comment: cannot create a temporary directory for the self-test" >&2; exit 2; }
  trap 'rm -rf "$ST"' EXIT
  export GIT_CEILING_DIRECTORIES="$ST"
  local CASES=0 HELD=0 CODES=""

  G() { git -C "$1" -c user.email=selftest@example.invalid -c user.name=selftest \
          -c commit.gpgsign=false "${@:2}"; }
  # newrepo <name> [bare|noconst|noprobe]: a spec holding R1, tagged `base`, and
  # a solver probe. Unless `bare`, also a classification store and a Stage 5
  # result, so that every section of the report is measurable. `noconst` leaves
  # out the constitution and nothing else; `noprobe` the probe and nothing else.
  newrepo() {
    local R="$ST/$1"
    mkdir -p "$R/.claude/productizer"
    G "$R" init --quiet --initial-branch=main
    printf '# Spec\n\n## Requirements\n\n- **R1** \342\200\224 The tool shall greet.\n' \
      > "$R/.claude/productizer/spec.md"
    # The constitution too: spec-diff.sh reads both files, and a missing one
    # turns its exit into 5 for the whole run.
    [ "${2:-}" = noconst ] || printf '# Constitution\n\n1. Small steps.\n' > "$R/.claude/productizer/constitution.md"
    if [ "${2:-}" != bare ]; then
      mkdir -p "$R/.claude/productizer/classifications"
      printf 'Intent: seed\nClassification: extend\n' > "$R/.claude/productizer/classifications/0-seed.md"
      cat > "$R/.claude/productizer/checks-result.json" <<'JSON'
{"verdict": "PASS", "exit_code": 0,
 "counts": {"declared": 2, "triggered": 2, "passed": 2, "blocking_failures": 0, "waived": 0,
            "advisory_failures": 0, "not_triggered": 0, "spec_units_unsatisfied": 0},
 "checks": [{"id": "lint", "status": "pass"}], "change": {"files": ["src/a.sh"]}}
JSON
    fi
    if [ "${2:-}" != noprobe ]; then
      mkdir -p "$R/evals"
      printf 'print("  true positives   3")\nprint("  false negatives  0")\nprint("  precision 1.00")\n' \
        > "$R/evals/solver-probe.py"
    fi
    G "$R" add -A
    G "$R" commit --quiet -m base
    G "$R" tag base
  }
  commit() { G "$1" add -A; G "$1" commit --quiet -m change; }

  drive() { # drive <name> <want> <text> <dir> [args...]
    local name="$1" want="$2" text="$3" D="$4"; shift 4
    local got=0
    ( cd "$D" && bash "$SELF" "$@" ) >"$ST/$name.out" 2>"$ST/$name.err" || got=$?
    CASES=$((CASES + 1)); CODES="$CODES $got"
    if [ "$got" = "$want" ] && grep -qF -- "$text" "$ST/$name.out" "$ST/$name.err"; then
      HELD=$((HELD + 1)); printf '  ok    %-40s exit %s\n' "$name" "$got"
    else
      printf '  FAIL  %-40s exit %s (wanted %s and the text: %s)\n' "$name" "$got" "$want" "$text"
      head -n 12 "$ST/$name.out" | sed 's/^/          stdout: /'
      head -n 8 "$ST/$name.err" | sed 's/^/          stderr: /'
    fi
  }

  lacks() { # lacks <case> <text>: the named case's stdout must NOT carry the text
    # grep's three answers kept apart: 1 is the absence asserted, and 2 (no
    # such case output) must not read as one.
    local g=0
    CASES=$((CASES + 1))
    grep -qF -- "$2" "$ST/$1.out" || g=$?
    case "$g" in
      1) HELD=$((HELD + 1)); printf '  ok    %-40s does not carry: %s\n' "$1 (lacks)" "$2" ;;
      0) printf '  FAIL  %-40s carries: %s\n' "$1 (lacks)" "$2" ;;
      *) printf '  FAIL  %-40s no output to read (grep exit %s)\n' "$1 (lacks)" "$g" ;;
    esac
  }

  printf 'pr-spec-comment self-test\n\n'
  local R

  newrepo added; R="$ST/added"
  printf -- '- **R2** \342\200\224 The tool shall wave.\n' >> "$R/.claude/productizer/spec.md"
  commit "$R"
  # shellcheck disable=SC2016  # the backticks are literal markdown in the expected sentence
  drive requirement-added 0 '| Added | `R2` |' "$R" --base base
  drive every-section-measured 0 "The store was read" "$R" --base base

  # A json.py planted in the working directory the renderer runs in. The Stage 5
  # result is read by a python3 heredoc read from stdin; without isolation that
  # heredoc's `import json` would load this file instead of the standard library
  # and the verdict would be whatever the plant returns, not what the result
  # file says. The renderer runs in trees an agent may have written, so the
  # verdict must still come from the real json. Asserting the true verdict PASS
  # proves the standard library parsed the result; a hijack renders NOT MEASURED.
  newrepo jsonhijack; R="$ST/jsonhijack"
  cat > "$R/json.py" <<'PLANT'
import os
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "JSON_HIJACK_MARKER"), "w").write("x")
def load(*a, **k): return {}
def loads(*a, **k): return {}
PLANT
  commit "$R"
  drive planted-json-not-imported 0 "Verdict | **PASS**" "$R" --base base
  CASES=$((CASES + 1)); CODES="$CODES 0"
  if [ ! -e "$R/JSON_HIJACK_MARKER" ]; then
    HELD=$((HELD + 1)); printf '  ok    %-40s %s\n' "planted-json-side-effect-blocked" "the plant never executed"
  else
    printf '  FAIL  %-40s %s\n' "planted-json-side-effect-blocked" "the planted json.py executed in the renderer"
  fi

  newrepo refined; R="$ST/refined"
  printf '# Spec\n\n## Requirements\n\n- **R1** \342\200\224 The tool shall greet by name.\n' \
    > "$R/.claude/productizer/spec.md"
  commit "$R"
  # shellcheck disable=SC2016  # the backticks are literal markdown in the expected sentence
  drive requirement-refined 0 '| Refined (id kept, sentence changed) | `R1` |' "$R" --base base

  newrepo contradict; R="$ST/contradict"
  printf 'Intent: 7\nClassification: contradict\n' > "$R/.claude/productizer/classifications/7-x.md"
  commit "$R"
  drive contradiction-on-top 0 "**YES — 1 of 1 classification record(s)" "$R" --base base

  newrepo unchanged; R="$ST/unchanged"
  printf 'x\n' > "$R/other.txt"
  commit "$R"
  drive nothing-moved 0 "**No requirement moved.**" "$R" --base base

  newrepo partial bare; R="$ST/partial"
  printf -- '- **R2** \342\200\224 The tool shall wave.\n' >> "$R/.claude/productizer/spec.md"
  commit "$R"
  drive no-store-is-partial 5 "> **This report is partial.**" "$R" --base base
  drive no-checks-result-not-measured 5 "Checks that were never run" "$R" --base base
  drive base-does-not-resolve 5 "**NOT MEASURED — the base ref does not resolve.**" "$R" --base no-such-ref

  drive post-refused 2 "--post is REFUSED, and deliberately not implemented" "$R" --post
  drive unknown-option 2 "unknown option: --frobnicate" "$R" --frobnicate
  mkdir -p "$ST/plain"
  drive not-a-repository 3 "not a git repository" "$ST" "$ST/plain"
  drive version 0 "pr-spec-comment 1." "$ST" --version

  # B103. No constitution and an unchanged spec: spec-diff.sh exits 5 for the
  # run because of the constitution alone. The spec was measured, and every
  # other section is too, so the report is whole and names the real cause.
  newrepo noconst noconst; R="$ST/noconst"
  printf 'x\n' > "$R/other.txt"
  commit "$R"
  drive no-constitution-named-not-spec 0 "it is the constitution's absence, not the spec's" "$R" --base base
  drive no-constitution-spec-still-measured 0 "**No requirement moved.**" "$R" --base base
  lacks no-constitution-named-not-spec "does not exist at"

  # B104. The body is rendered in an adopter's repository. Nothing in it may
  # name this repository's own artifacts; what it says about the probe and the
  # publish gate is read from the tree it runs in.
  newrepo adopter; R="$ST/adopter"
  printf 'x\n' > "$R/other.txt"
  commit "$R"
  drive adopter-corpus-size-derived 0 "Over 3 case(s): the sum of the rows above" "$R" --base base
  lacks adopter-corpus-size-derived "26-case"
  lacks no-store-is-partial "26-case"
  lacks adopter-corpus-size-derived "publish-checklist.md"
  lacks adopter-corpus-size-derived "checks.yml"
  mkdir -p "$R/.claude/hooks"
  # shellcheck disable=SC2016  # the hook line is literal shell, read by sed
  printf '#!/bin/sh\nGATE_CHECKLIST="${GATE_CHECKLIST:-ops/release-list.md}"\n' > "$R/.claude/hooks/publish-gate.sh"
  commit "$R"
  # shellcheck disable=SC2016  # the backticks are literal markdown in the expected sentence
  drive adopter-gate-path-from-hook 0 'write `ops/release-list.md` with `Command: gh pr comment' "$R" --base base

  # B129. The probe is required: with no evals/solver-probe.py the report is
  # refused (exit 3) before a line is rendered, not rendered as partial.
  newrepo noprobe noprobe; R="$ST/noprobe"
  printf -- '- **R2** \342\200\224 The tool shall wave.\n' >> "$R/.claude/productizer/spec.md"
  commit "$R"
  drive no-probe-refused 3 "there is no readable evals/solver-probe.py in this tree" "$R" --base base
  lacks no-probe-refused "## What this change did to the spec"

  printf '\n%s of %s cases held\n' "$HELD" "$CASES"
  local reached documented
  reached="$(printf '%s' "$CODES" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  documented="$(awk '/^# Exit:/ { f = 1; sub(/^# Exit:/, "#      ") } f && /^#[[:space:]]+[0-9] / { printf "%s ", $2; next } f { exit }' "$SELF" | sed 's/  *$//')"
  printf '    exit codes reached: %s   documented: %s\n' "$reached" "$documented"
  printf '    NOT ASSERTED: an id that VANISHED; a Superseded or Withdrawn annotation; an unreadable classification record; a malformed checks-result.json; a probe that exits non-zero or prints no counts; the change-set cap of five paths; exit 3 for an unusable spec-diff.sh; a constitution new in the range; a spec absent at both ends; a probe row whose last field is not a count; a workflow under .github/workflows naming the probe; a publish-gate.sh with no readable checklist line.\n'
  [ "$reached" = "$documented" ] || { printf 'FAIL: reached and documented exit codes differ\n'; return 1; }
  [ "$HELD" -eq "$CASES" ] || return 1
  return 0
}

if [ "$SELFTEST" -eq 1 ]; then
  ST_RC=0
  selftest || ST_RC=$?
  exit "$ST_RC"
fi

[ -n "$ROOT" ] || ROOT="."
cd "$ROOT" || { echo "pr-spec-comment: no such directory: $ROOT" >&2; exit 3; }
git rev-parse --is-inside-work-tree >/dev/null || { echo "pr-spec-comment: not a git repository: $ROOT" >&2; exit 3; }
cd "$(git rev-parse --show-toplevel)"
[ -n "$CHECKS" ] || CHECKS="$CHECKS_REL"

[ -x "$SPEC_DIFF" ] || {
  echo "pr-spec-comment: spec-diff.sh is not executable at $SPEC_DIFF." >&2
  echo "The delta is computed there and nowhere else. Refusing rather than reimplementing it." >&2
  exit 3; }

# THE PROBE IS REQUIRED (maintainer ruling 2026-10-12, B129). The report carries
# the repository's solver probe, and the CI build template renders this report
# as every pull request's body; a repository without one would read "This report
# is partial" on every pull request. So its absence is a refusal, checked before
# a line is rendered, and the caller decides what to do without a body.
[ -f "$PROBE_REL" ] && [ -r "$PROBE_REL" ] || {
  echo "pr-spec-comment: there is no readable $PROBE_REL in this tree, and the report requires the repository's solver probe." >&2
  echo "The CI build template requires an adopter to provide $PROBE_REL (references/ci-build.md, \"Adopting it\"). Nothing was rendered." >&2
  exit 3; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SD_OUT="$WORK/spec-diff.txt"

say() { printf '%s\n' "$*"; }

# Set only by an absence of MEASUREMENT. A measured empty set never sets it.
UNMEASURED=0

# --- the delta -------------------------------------------------------------
# spec-diff.sh's stderr is neither captured nor discarded: it reprints git's own
# errors there, and an error nobody was shown is the silent empty diff both
# scripts exist to prevent.
SD_ARGS=()
[ -z "$BASE" ] || SD_ARGS=(--base "$BASE")
SD_RC=0
"$SPEC_DIFF" . ${SD_ARGS[@]+"${SD_ARGS[@]}"} >"$SD_OUT" || SD_RC=$?

case "$SD_RC" in
  0|4|5|7) ;;
  6) UNMEASURED=1 ;;
  2|3) echo "pr-spec-comment: spec-diff.sh exited $SD_RC - see its message above." >&2; exit 3 ;;
  *)   echo "pr-spec-comment: spec-diff.sh exited $SD_RC, which this script cannot read." >&2; exit 3 ;;
esac

HEAD_SHA="$(git rev-parse --verify 'HEAD^{commit}')"
# One resolution of the base, lifted from spec-diff.sh's own header, so every
# section below is measured against the ref the delta was measured against.
BASE_SHA="$(sed -n 's/^Base: .* at \([0-9a-f]\{7,\}\),.*/\1/p' "$SD_OUT")"; BASE_SHA="$(head -n 1 <<<"$BASE_SHA")"
# shellcheck disable=SC2016  # the backticks are literal, in a sed regex matching spec-diff.sh's markdown; single quotes are what keeps them literal
BASE_LABEL="$(sed -n 's/^Base: `\([^`]*\)`.*/\1/p' "$SD_OUT")"; BASE_LABEL="$(head -n 1 <<<"$BASE_LABEL")"
[ -n "$BASE_LABEL" ] || BASE_LABEL="did not resolve"

# Each file's own outcome, from the heading spec-diff.sh gives it. Its EXIT is
# the strongest outcome over the spec AND the constitution, so a run whose exit
# is 5 may be one where only the constitution has no baseline. Reading the exit
# as the spec's state blamed the spec for a missing constitution (B103).
file_state() { # file_state <path> -> absent | new, no baseline | unchanged | diff too large | changed against `X`
  awk -v want="$1" '
    index($0, "### `" want "` - ") == 1 { print substr($0, length("### `" want "` - ") + 1); exit }
  ' "$SD_OUT"
}
CONST_REL=".claude/productizer/constitution.md"
SPEC_STATE="$(file_state "$SPEC_REL")"
CONST_STATE="$(file_state "$CONST_REL")"

# --- requirement ids, out of the fenced diff -------------------------------
# The spec's section only. spec-diff.sh emits the constitution too, and a
# principle carries no requirement id.
spec_section() {
  awk -v want="$SPEC_REL" '
    index($0, "### `") == 1 { insec = (index($0, "`" want "`") > 0); next }
    insec { print }
  ' "$SD_OUT"
}

ADDED=""; DROPPED=""; SUPERSEDED=""; WITHDRAWN=""
if [ "${SPEC_STATE#changed against}" != "$SPEC_STATE" ] && [ -n "$(spec_section)" ]; then
  # awk walks the body in order, so a `Superseded by` or `Withdrawn.` line is
  # attributed to the id above it - which is where the spec puts it. The id line
  # may arrive as context, as a removal or as an addition; all three move the
  # cursor, because the annotation belongs to whichever one it was.
  spec_section | awk '
    /^(\+\+\+|---) / { next }
    { body = substr($0, 2) }
    body ~ /^- \*\*R[0-9]+\*\*/ {
      id = body; sub(/^- \*\*/, "", id); sub(/\*\*.*$/, "", id); cur = id
      if (substr($0, 1, 1) == "+") add[id] = 1
      if (substr($0, 1, 1) == "-") drop[id] = 1
      next
    }
    substr($0, 1, 1) == "+" && body ~ /Superseded by R[0-9]+\./ && cur != "" { sup[cur] = 1; next }
    substr($0, 1, 1) == "+" && body ~ /^[[:space:]]*Withdrawn\./ && cur != "" { wd[cur] = 1; next }
    END {
      for (i in add)  printf "ADDED %s\n", i
      for (i in drop) printf "DROPPED %s\n", i
      for (i in sup)  printf "SUPERSEDED %s\n", i
      for (i in wd)   printf "WITHDRAWN %s\n", i
    }
  ' >"$WORK/ids.txt"
  ADDED="$(awk '$1=="ADDED"{print $2}' "$WORK/ids.txt" | sort -uV)"
  DROPPED="$(awk '$1=="DROPPED"{print $2}' "$WORK/ids.txt" | sort -uV)"
  SUPERSEDED="$(awk '$1=="SUPERSEDED"{print $2}' "$WORK/ids.txt" | sort -uV)"
  WITHDRAWN="$(awk '$1=="WITHDRAWN"{print $2}' "$WORK/ids.txt" | sort -uV)"
fi

# An id on both sides kept its id and changed its sentence: a refinement. On the
# added side only, it is new. On the dropped side only it VANISHED - and R2 says
# an id is permanent, so that is a finding and not a bullet.
set_op() { # set_op -12|-23 <a> <b>
  comm "$1" <(printf '%s\n' "$2" | grep -v '^$' | sort -u) \
            <(printf '%s\n' "$3" | grep -v '^$' | sort -u) | sort -V
}
REFINED="$(set_op -12 "$ADDED" "$DROPPED")"
NEW="$(set_op -23 "$ADDED" "$DROPPED")"
VANISHED="$(set_op -23 "$DROPPED" "$ADDED")"

# One awk, not a pipeline: `set -o pipefail` is on, and a `grep` that matches
# nothing exits 1, which would kill the run on the ordinary case of an empty id
# set. It did, on the first run of this script.
fmt_ids() { printf '%s\n' "$1" | awk 'NF { a = (a == "" ? "`" $0 "`" : a ", `" $0 "`") } END { print a }'; }
row() { # row <label> <ids> <what a measured empty set means here>
  local ids; ids="$(fmt_ids "$2")"
  if [ -n "$ids" ]; then say "| $1 | $ids |"
  else say "| $1 | none — $3 |"; fi
}

# --- report ----------------------------------------------------------------
say "## What this change did to the spec"
say ""
say "| | |"
say "|---|---|"
say "| Base | \`$BASE_LABEL\`${BASE_SHA:+ at \`$BASE_SHA\`} |"
say "| Head | \`${HEAD_SHA:0:12}\` |"
say "| Spec | \`$SPEC_REL\` |"
say ""

say "### Requirements"
say ""
SPEC_CASE="$SPEC_STATE"
[ "$SD_RC" != 6 ] || SPEC_CASE="no base"
case "$SPEC_CASE" in
  "changed against"*)
    say "| Movement | Ids |"
    say "|---|---|"
    row "Added" "$NEW" "the diff was read end to end and defines no id that was not there before"
    row "Refined (id kept, sentence changed)" "$REFINED" "no requirement kept its id and changed its wording"
    row "Superseded" "$SUPERSEDED" "nothing gained a \`Superseded by R<n>.\` line"
    row "Withdrawn" "$WITHDRAWN" "nothing gained a \`Withdrawn.\` line"
    say ""
    if [ -n "$(fmt_ids "$VANISHED")" ]; then
      say "> **An id left the file.** $(fmt_ids "$VANISHED") is defined at the base and not at HEAD."
      say "> Requirement ids in the living spec are permanent, and a replaced requirement keeps its"
      say "> original text in place, so this is not a supersession — a superseded requirement keeps"
      say "> its line. Check the diff."
      say ""
    fi
    ;;
  unchanged)
    say "**No requirement moved.** \`$SPEC_REL\` is byte-identical at \`$BASE_LABEL\` and at HEAD."
    say "This is a measured absence of change: both ends were read and compared."
    say ""
    ;;
  "new, no baseline")
    say "**NOT MEASURED — no baseline.** \`$SPEC_REL\` does not exist at \`$BASE_LABEL\`, so it has no"
    say "history to diff against and every line of it is an addition. An empty movement table here"
    say "would read as \"nothing changed\", which is a different and untrue answer."
    say ""
    UNMEASURED=1
    ;;
  absent)
    say "**NOT MEASURED — there is no spec.** \`$SPEC_REL\` is tracked at neither \`$BASE_LABEL\` nor"
    say "HEAD, so there is nothing to diff. That is not a spec that did not change."
    say ""
    UNMEASURED=1
    ;;
  "no base")
    say "**NOT MEASURED — the base ref does not resolve.** \`spec-diff.sh\` refused to fall back to an"
    say "empty diff, and so does this. Pass \`--base REF\` with a ref this clone actually carries;"
    say "a shallow clone is the usual cause."
    say ""
    ;;
  "diff too large")
    say "**NOT MEASURED — the diff is over \`spec-diff.sh\`'s cap and was left out whole.** It was not"
    say "truncated: a cut-off diff reads as a complete one. The movement table cannot be derived"
    say "from a diff that was not emitted, so it is absent rather than empty."
    say ""
    UNMEASURED=1
    ;;
  *)
    say "**NOT MEASURED.** \`spec-diff.sh\` exited $SD_RC and its output names no outcome for"
    say "\`$SPEC_REL\`, so this report cannot say what happened to it."
    say ""
    UNMEASURED=1
    ;;
esac

# The constitution carries no requirement id, so its outcome never decides the
# table above. When it has no baseline, say so under its own name: that is the
# cause of spec-diff.sh's exit 5 in a repository that has no constitution.
case "$CONST_STATE" in
  absent)
    say "\`$CONST_REL\` is tracked at neither end. That is why \`spec-diff.sh\` reports no baseline"
    say "for this run; it is the constitution's absence, not the spec's, and it moves no requirement."
    say "" ;;
  "new, no baseline")
    say "\`$CONST_REL\` is new in this range and has no baseline at \`$BASE_LABEL\`. It carries no"
    say "requirement id, so it moves no requirement."
    say "" ;;
esac

# --- contradiction ---------------------------------------------------------
# R33: an intent that contradicts an active requirement STOPS the pipeline, and
# R12 says nothing depending on it merges. A pull request carrying a classified
# contradiction is the single fact a reviewer most needs on the page.
say "### Classified \`contradict\`?"
say ""
if [ ! -d "$CLASS_REL" ]; then
  say "**NOT MEASURED.** There is no classification store at \`$CLASS_REL\`. That is not the same as"
  say "\"no contradiction was recorded\", and it is not reported as one."
  say ""
  UNMEASURED=1
elif [ -z "$BASE_SHA" ]; then
  say "**NOT MEASURED.** The base did not resolve above, so there is no range to read the store over."
  say ""
else
  git diff --name-only "$BASE_SHA" "$HEAD_SHA" -- "$CLASS_REL" >"$WORK/class.txt"
  # Two passes on purpose. The heading asks a yes/no question, and a list of
  # records the reader has to scan for the word `contradict` is not an answer.
  # So the rows are rendered into a buffer first, the verdict is printed, and
  # the buffer follows it.
  : >"$WORK/class.md"
  CHANGED=0
  CONTRADICTS=0
  UNREADABLE=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    CHANGED=$((CHANGED + 1))
    if [ ! -r "$f" ]; then
      # Deleted at HEAD, or unreadable. Either way its classification cannot be
      # read, and "not read" is not "not a contradiction".
      say "- \`$f\` — **NOT MEASURED**: changed in this range and not readable at HEAD." >>"$WORK/class.md"
      UNREADABLE=1
      continue
    fi
    verdict="$(sed -n 's/^Classification:[[:space:]]*//p' "$f")"; verdict="$(head -n 1 <<<"$verdict")"
    intent="$(sed -n 's/^Intent:[[:space:]]*//p' "$f")"; intent="$(head -n 1 <<<"$intent")"
    case "$verdict" in
      contradict)
        CONTRADICTS=$((CONTRADICTS + 1))
        say "- **\`$f\` — \`contradict\`** (intent \`${intent:-unstated}\`). A contradiction stops the pipeline here," >>"$WORK/class.md"
        say "  and nothing that depends on it merges until somebody rules. This needs a ruling, not a review." >>"$WORK/class.md" ;;
      "")
        UNREADABLE=1
        say "- \`$f\` — **NOT MEASURED**: the record carries no \`Classification:\` line." >>"$WORK/class.md" ;;
      *)
        say "- \`$f\` — \`$verdict\` (intent \`${intent:-unstated}\`)" >>"$WORK/class.md" ;;
    esac
  done <"$WORK/class.txt"

  if [ "$CONTRADICTS" -gt 0 ]; then
    say "**YES — $CONTRADICTS of $CHANGED classification record(s) that changed in this range say \`contradict\`.**"
  elif [ "$UNREADABLE" = 1 ]; then
    say "**NOT MEASURED for at least one record.** $CHANGED record(s) changed in this range and at"
    say "least one could not be read. An unread classification is not a cleared one."
    UNMEASURED=1
  elif [ "$CHANGED" -gt 0 ]; then
    say "**No.** $CHANGED classification record(s) changed in this range; every one was read and none"
    say "says \`contradict\`."
  else
    say "**No.** No file under \`$CLASS_REL\` changed between \`$BASE_SHA\` and HEAD. The store was read"
    say "over the range and is unchanged — a measured absence, not an unread one."
  fi
  if [ -s "$WORK/class.md" ]; then
    say ""
    cat "$WORK/class.md"
  fi
  say ""
fi

# --- check verdicts --------------------------------------------------------
say "### Check verdicts"
say ""
if ! command -v python3 >/dev/null; then
  say "**NOT MEASURED.** \`python3\` is not on PATH, and the result file is JSON."
  say ""
  UNMEASURED=1
elif [ ! -r "$CHECKS" ]; then
  say "**NOT MEASURED.** No readable Stage 5 result at \`$CHECKS\`. Checks that were never run"
  say "are not checks that passed. Run \`run-checks.sh --base <ref> --out $CHECKS\` first."
  say ""
  UNMEASURED=1
elif ! python3 -I - "$CHECKS" >"$WORK/checks.md" <<'PY'
# -I isolates the interpreter; on Python >= 3.11 it also implies -P, which keeps
# the current directory off sys.path. On older runners -I does NOT imply -P, so
# a `json.py` planted in the working directory would be imported in place of the
# standard library before this script's first `import json`. sys is a builtin
# and is never loaded from a file, so scrub the directory entries it carries
# BEFORE importing anything else. The Stage 5 result this reads may sit in a
# tree an agent has edited, so this is a trust boundary, not a nicety.
import sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import json

with open(sys.argv[1], encoding="utf-8") as fh:
    r = json.load(fh)

c = r.get("counts", {})
say = print
say("| | |")
say("|---|---|")
say("| Verdict | **%s** (exit %s) |" % (r.get("verdict", "NOT MEASURED"),
                                        r.get("exit_code", "NOT MEASURED")))
for label, key in (("Declared", "declared"), ("Triggered", "triggered"),
                   ("Passed", "passed"), ("Blocking failures", "blocking_failures"),
                   ("Waived", "waived"), ("Advisory failures", "advisory_failures"),
                   ("Not triggered", "not_triggered"),
                   ("Spec units unsatisfied", "spec_units_unsatisfied")):
    say("| %s | %s |" % (label, c.get(key, "NOT MEASURED")))
say("")

bad = [ch for ch in r.get("checks", []) if ch.get("status") not in (None, "pass")]
if bad:
    say("Not passing:")
    say("")
    for ch in bad:
        say("- `%s` — **%s** (%s, exit %s) — %s"
            % (ch.get("id", "?"), ch.get("status", "NOT MEASURED"),
               ch.get("severity", "?"), ch.get("exit_code", "NOT MEASURED"),
               ch.get("why", "")))
    say("")

# The change set is named but CAPPED. One real result file here carried a
# `files` list 150 kB long, and a pull-request comment that long is a comment
# nobody reads. The count is the measurement; the sample is a courtesy, and the
# line says when it is a sample so the reader is never shown a short list that
# looks complete.
files = r.get("change", {}).get("files", [])
LIMIT = 5
shown = ", ".join("`%s`" % f for f in files[:LIMIT]) or "_none listed_"
more = "" if len(files) <= LIMIT else " (first %d of %d shown)" % (LIMIT, len(files))
say("Read from the recorded run over %d changed path(s): %s%s. That run is whatever last "
    "wrote this file — if it is not the run for this pull request, these verdicts are "
    "about a different change."
    % (len(files), shown, more))
PY
then
  say "**NOT MEASURED.** \`$CHECKS\` exists but is not readable as a Stage 5 result — see the error above."
  say ""
  UNMEASURED=1
else
  cat "$WORK/checks.md"
  say ""
fi

# --- the solver probe ------------------------------------------------------
# Everything said here is read from the tree the report runs in. This renders
# the body of a pull request in an adopter's repository too, so a sentence about
# this repository's own corpus, workflow or publish checklist would be a
# reference to nothing there (B104). Absent a workflow naming the probe, that
# sentence is omitted. The probe itself was required above (B129).
say "### Solver probe"
say ""
if ! command -v python3 >/dev/null; then
  say "**NOT MEASURED.** \`python3\` is not on PATH."
  say ""
  UNMEASURED=1
elif ! python3 "$PROBE_REL" >"$WORK/probe.txt"; then
  say "**NOT MEASURED.** \`$PROBE_REL\` did not complete — see the error above. A probe that did not"
  say "finish has no score, and none is rendered."
  say ""
  UNMEASURED=1
else
  PROBE_ROWS="$(grep -E '^  (true|false) (positives|negatives)|^  undecided' "$WORK/probe.txt" || true)"
  if [ -z "$PROBE_ROWS" ]; then
    say "**NOT MEASURED.** The probe ran and exited 0 but printed no counts. An empty score is not a"
    say "perfect one and is not rendered as one."
    say ""
    UNMEASURED=1
  else
    say '```'
    printf '%s\n' "$PROBE_ROWS"
    grep -E '^  (precision|recall)' "$WORK/probe.txt" || true
    say '```'
    say ""
    # The corpus size is the probe's own: every case lands in exactly one of
    # the rows above, so their sum is the number of cases it ran. A row whose
    # last field is not a count makes the sum unknowable, and then no size is
    # stated rather than a wrong one.
    PROBE_N="$(printf '%s\n' "$PROBE_ROWS" | awk '$NF !~ /^[0-9]+$/ { bad = 1 } { n += $NF } END { if (!bad) print n }')"
    if [ -n "$PROBE_N" ]; then
      say "Over $PROBE_N case(s): the sum of the rows above, as \`$PROBE_REL\` printed them."
      say ""
    fi
    PROBE_GATES=""
    for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
      [ -f "$wf" ] || continue
      if grep -qF -- "$PROBE_REL" "$wf"; then PROBE_GATES="$PROBE_GATES$wf"$'\n'; fi
    done
    if [ -n "$PROBE_GATES" ]; then
      say "This repository's workflow $(fmt_ids "$PROBE_GATES") runs this probe. Any bounds"
      say "it holds the probe to live there and are deliberately not restated here — two copies of one"
      say "measurement drift apart."
      say ""
    fi
  fi
fi

# --- footer ----------------------------------------------------------------
# The publish gate is named only where it is installed, and its checklist path
# is read from the hook itself rather than assumed.
GATE_HOOK=".claude/hooks/publish-gate.sh"
say "---"
say ""
say "Rendered by \`pr-spec-comment.sh\` ($VERSION) to stdout. **It posted nothing.**"
say "Posting it is a separate step for a person to take, for example by piping this output into"
say "\`gh pr comment <n> --body-file -\`."
if [ -r "$GATE_HOOK" ]; then
  # shellcheck disable=SC2016  # the hook's own line is matched literally; nothing here should expand
  GATE_LIST="$(sed -n 's/^GATE_CHECKLIST="\${GATE_CHECKLIST:-\([^}]*\)}"$/\1/p' "$GATE_HOOK")"; GATE_LIST="$(head -n 1 <<<"$GATE_LIST")"
  if [ -n "$GATE_LIST" ]; then
    say "This repository's \`$GATE_HOOK\` holds a publish until a checklist names the command:"
    say "write \`$GATE_LIST\` with \`Command: gh pr comment <n> --body-file -\` as its first line, then"
    say "pipe this output into that command yourself."
  else
    say "This repository has \`$GATE_HOOK\`, which may hold that command until a person has decided to run it."
  fi
fi
if [ "$UNMEASURED" = 1 ]; then
  say ""
  say "> **This report is partial.** At least one section above is marked NOT MEASURED."
fi

[ "$UNMEASURED" = 0 ] || exit 5
