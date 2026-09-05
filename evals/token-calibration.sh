#!/usr/bin/env bash
# token-calibration.sh [repo-root] [--keep DIR] [--model ID]
#
# Calibrates the character proxy in `retrieval-budget.sh` against a real token
# count, so the proxy's exchange rate is a measured figure and not an
# assumption.
#
# WHY THIS EXISTS. `retrieval-budget.sh` counts CHARACTERS and says, in its own
# header and in every line it prints, that characters are a proxy for a token
# budget and not a token count. That honesty is worth nothing until somebody
# measures how far the proxy is from the thing it stands for. This script is
# that measurement.
#
# THE INSTRUMENT. Anthropic's `/v1/messages/count_tokens` endpoint returns the
# exact token count the model would see, from the model's own tokeniser. It is
# free and it bills nothing, so this calibration costs $0.00 and can be re-run
# whenever the spec's content mix changes. It is NOT a sampled estimate and it
# is NOT this session's usage accounting: it is the tokeniser.
#
# The endpoint counts a whole request, so every count carries a fixed
# per-request overhead of a few tokens. The overhead is measured here rather
# than assumed - see `overhead` below - and subtracted from every figure.
#
# WHAT IS MEASURED. Two families, and the difference between them is the point:
#
#   candidates/*  the exact byte runs `retrieval-budget.sh` reports - the
#                 candidate lines of the living spec, up to and including the
#                 target requirement, for a realistic prompt. This is the
#                 quantity under calibration, not a stand-in for it.
#   mix/*         single-content-type slices - EARS requirement lines, markdown
#                 table rows, narrative prose, YAML, Python, shell. These
#                 establish the SPREAD, which is the finding: bytes per token
#                 is a property of the content, not of the file, so no single
#                 conversion factor can be printed honestly.
#
# HOUSE RULE, INHERITED. A value that could not be measured is never rendered
# as zero. A slice that comes out empty is named and skipped; a request that
# fails prints the status and stops the run.
#
# AUTH. `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` in the environment.
# Neither is ever printed, logged or written to a file.
#
# Exit: 0 measured
#       2 usage
#       3 no repo, no spec, or no credential
#       4 the token counter refused or could not be reached
set -euo pipefail
export LC_ALL=C

ROOT=""
KEEP=""
MODEL="claude-sonnet-4-5-20250929"
while [ $# -gt 0 ]; do
  case "$1" in
    --keep)    KEEP="${2:-}"; [ -n "$KEEP" ]  || { echo "token-calibration: --keep needs a directory" >&2; exit 2; }; shift 2 ;;
    --model)   MODEL="${2:-}"; [ -n "$MODEL" ] || { echo "token-calibration: --model needs an id" >&2; exit 2; }; shift 2 ;;
    -h|--help) echo "usage: token-calibration.sh [repo-root] [--keep DIR] [--model ID]"; exit 0 ;;
    -*)        echo "token-calibration: unknown option: $1" >&2; exit 2 ;;
    *)         [ -z "$ROOT" ] || { echo "token-calibration: only one repo-root" >&2; exit 2; }; ROOT="$1"; shift ;;
  esac
done
[ -n "$ROOT" ] || ROOT="."
cd "$ROOT" || { echo "token-calibration: no such directory: $ROOT" >&2; exit 3; }

SPEC=".claude/productizer/spec.md"
[ -r "$SPEC" ] || { echo "token-calibration: no readable spec at $SPEC" >&2; exit 3; }

TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-}"
AUTH_HEADER=""
if [ -n "$TOKEN" ]; then
  AUTH_HEADER="Authorization: Bearer $TOKEN"
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  AUTH_HEADER="x-api-key: $ANTHROPIC_API_KEY"
else
  echo "token-calibration: no CLAUDE_CODE_OAUTH_TOKEN and no ANTHROPIC_API_KEY" >&2
  echo "  Nothing was measured. This is not a calibration of zero." >&2
  exit 3
fi

WORK="$KEEP"
if [ -z "$WORK" ]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
fi
mkdir -p "$WORK/candidates" "$WORK/mix"

# --- slices ----------------------------------------------------------------

# The candidate scan, byte for byte the same rule as retrieval-budget.sh: a
# line is a candidate when it contains any term case-insensitively, and the run
# ends at the line carrying the target marker.
candidates() { # candidates <terms> <target-id>
  awk -v terms="$1" -v marker="**$2**" '
    BEGIN { n = split(terms, t, " "); for (i = 1; i <= n; i++) low[i] = tolower(t[i]) }
    {
      line = tolower($0); cand = 0
      for (i = 1; i <= n; i++) if (index(line, low[i]) > 0) { cand = 1; break }
      if (cand) print
      if (index($0, marker) > 0) exit
    }
  ' "$SPEC"
}

# One realistic prompt per line, in the prompt-set format retrieval-budget.sh
# reads: <id> <target> <terms>. These are the repo's own vocabulary, so the
# candidate runs are the runs the check would actually report here.
while read -r cid ctarget cterms; do
  [ -n "$cid" ] || continue
  candidates "$cterms" "$ctarget" > "$WORK/candidates/$cid"
done <<'PROMPTS'
override R37 override waive failing check authority
contradiction R14 contradict stop ask wins merge
unmeasured R16 unmeasured measured zero report
jira R21 jira backlog key status write
view R31 view publish capability read-only
PROMPTS

# Single-content-type slices. Each is real content from this repository; none is
# synthesised, because a synthetic sample calibrates a synthetic proxy.
# grep's exit 1 is a genuine empty slice and is handled by the empty-file branch
# in the loop below; anything above 1 is a real failure and stops the run. The
# status is inspected rather than swallowed by `|| true`, which would make an
# unreadable spec look like a spec with no requirements in it.
slice() { # slice <name> <extended-regexp>
  local st=0
  grep -E "$2" "$SPEC" > "$WORK/mix/$1" || st=$?
  [ "$st" -le 1 ] || { echo "token-calibration: grep failed ($st) building slice $1" >&2; exit 3; }
}
slice ears-requirements '^- \*\*R[0-9]+\*\*'
slice markdown-table-rows '^\|'
slice narrative-prose '^[A-Za-z(][^|]*$'

copy_if() { # copy_if <source> <slice-name>
  if [ -r "$1" ]; then cp "$1" "$WORK/mix/$2"; fi
}
copy_if "$SPEC" spec-whole-file
copy_if .claude/productizer/checks.yaml yaml-checks
copy_if evals/check-corpus.py python-source
# NOT retrieval-budget.sh. That was the first choice and it was a feedback loop:
# the calibration's own result is written into that file's header, which changes
# its byte count, which changes the next calibration. The shell slice has to be
# a script this measurement does not touch.
copy_if plugins/productizer/skills/spec/scripts/run-checks.sh shell-source
copy_if evals/fixtures/billing-spec.md fixture-spec

# The mix-shift demonstration. Two slices cut to the SAME byte count from two
# kinds of content a spec can plausibly hold: narrative requirement prose, and
# the fenced source a spec grows when it starts quoting interfaces. The check
# under calibration cannot tell these apart - it counts bytes - so the gap
# between their token counts is exactly the error it is blind to.
SHIFT_BYTES=2000
mkdir -p "$WORK/shift"
head -c "$SHIFT_BYTES" "$WORK/mix/narrative-prose" > "$WORK/shift/prose-${SHIFT_BYTES}B"
# The comment header of a shell script is prose, so it is stripped before the
# code slice is cut. Leaving it in measured prose twice and called one of them
# code, which understated the gap this pair exists to show.
gst=0
grep -vE '^[[:space:]]*(#|$)' "$WORK/mix/shell-source" > "$WORK/.code-only" || gst=$?
[ "$gst" -le 1 ] || { echo "token-calibration: grep failed ($gst) stripping shell comments" >&2; exit 3; }
head -c "$SHIFT_BYTES" "$WORK/.code-only" > "$WORK/shift/code-${SHIFT_BYTES}B"
for s in "$WORK/shift"/*; do
  if [ "$(wc -c < "$s" | tr -d ' ')" -ne "$SHIFT_BYTES" ]; then
    echo "token-calibration: $(basename "$s") is short of $SHIFT_BYTES bytes - the mix-shift pair is not byte-equal" >&2
    rm -f "$WORK/shift"/*
    break
  fi
done

# --- the counter -----------------------------------------------------------

# Prints the exact token count of a file's bytes as message content, or exits 4.
# Python builds the JSON so that quotes, backslashes and newlines in the sample
# survive intact - a shell-quoted payload silently changes the bytes being
# measured, which would calibrate the wrong string.
raw_count() { # raw_count <path>
  python3 -c 'import json,sys; sys.stdout.write(json.dumps({"model":sys.argv[1],"messages":[{"role":"user","content":open(sys.argv[2],encoding="utf-8",errors="replace").read()}]}))' \
    "$MODEL" "$1" > "$WORK/.payload"
  local status body
  status="$(curl -sS -o "$WORK/.reply" -w '%{http_code}' \
    https://api.anthropic.com/v1/messages/count_tokens \
    -H "$AUTH_HEADER" \
    -H 'anthropic-version: 2023-06-01' \
    -H 'anthropic-beta: oauth-2025-04-20' \
    -H 'content-type: application/json' \
    --data-binary @"$WORK/.payload")"
  if [ "$status" != "200" ]; then
    echo "token-calibration: count_tokens returned HTTP $status for $1" >&2
    head -c 400 "$WORK/.reply" >&2; echo >&2
    exit 4
  fi
  body="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["input_tokens"])' "$WORK/.reply")"
  printf '%s\n' "$body"
}

# The per-request overhead, measured rather than assumed. The probe is ten
# common English words, each of which is exactly one token, and the same ten
# words twice. Doubling a list of whole-word tokens adds exactly as many tokens
# as it adds words, so twice the short count minus the long count is everything
# in the request that is not content.
#
# The first probe tried here was a single `x` against `xx`, and it was WRONG by
# one token: `xx` is a single token, not two, so the doubling identity did not
# hold and the overhead came out one too high. The self-check below is the fix -
# the run stops rather than subtract an overhead whose own probe misbehaved.
PROBE_WORDS="one two three four five six seven eight nine ten"
printf '%s' "$PROBE_WORDS"           > "$WORK/.probe1"
printf '%s %s' "$PROBE_WORDS" "$PROBE_WORDS" > "$WORK/.probe2"
p1="$(raw_count "$WORK/.probe1")"
p2="$(raw_count "$WORK/.probe2")"
PROBE_WORD_COUNT="$(printf '%s' "$PROBE_WORDS" | wc -w | tr -d ' ')"
if [ $(( p2 - p1 )) -ne "$PROBE_WORD_COUNT" ]; then
  echo "token-calibration: overhead probe is not one token per word ($p1 then $p2)" >&2
  echo "  outcome: overhead unmeasured. No bytes-per-token figure is printed." >&2
  exit 4
fi
OVERHEAD=$(( 2 * p1 - p2 ))

echo "token calibration"
echo "  counter   /v1/messages/count_tokens (exact, free) - model $MODEL"
echo "  overhead  $OVERHEAD token(s) per request, measured and subtracted"
echo "  spec      $SPEC"
echo

printf '%-24s %10s %10s %12s\n' "slice" "bytes" "tokens" "bytes/token"
TOTB=0; TOTT=0
for group in candidates mix shift; do
  for f in "$WORK/$group"/*; do
    [ -f "$f" ] || continue
    b="$(wc -c < "$f" | tr -d ' ')"
    name="$group/$(basename "$f")"
    if [ "$b" -eq 0 ]; then
      printf '%-24s %10s %10s %12s\n' "$name" "0" "empty" "unmeasured"
      continue
    fi
    t=$(( $(raw_count "$f") - OVERHEAD ))
    printf '%-24s %10d %10d %12s\n' "$name" "$b" "$t" "$(python3 -c 'import sys;print("%.2f"%(int(sys.argv[1])/int(sys.argv[2])))' "$b" "$t")"
    TOTB=$(( TOTB + b )); TOTT=$(( TOTT + t ))
  done
done

echo
echo "corpus $TOTB bytes, $TOTT tokens"
echo "A single conversion factor is NOT printed here on purpose. The spread"
echo "across the slices above is the result: bytes per token is a property of"
echo "the content, and a spec whose content mix shifts moves the exchange rate"
echo "while the character count stands still."
