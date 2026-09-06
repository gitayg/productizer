#!/usr/bin/env bash
# retrieval-budget.sh [repo-root] [--record] [--band PCT] [--prompts PATH] [--baseline PATH]
# retrieval-budget.sh --selftest | --version | --help
#
# The regression eval for spec retrieval: fixed prompts, each naming the one
# requirement it must reach, and a measurement of how much of the spec has to be
# read to reach it. Record a baseline once; every later run compares against it
# and fails when the figure leaves the band.
#
# There is no judge here and no golden dataset. Both were tried elsewhere and
# both rot: a judge drifts with the model behind it, and a golden dataset is a
# second spec nobody maintains. What is left is a number that either moved or
# did not.
#
# WHAT IS MEASURED, AND WHAT IT IS NOT
#
# The unit is CHARACTERS (bytes, LC_ALL=C), and it is a PROXY for a token
# budget, not a token count. A real token count needs the tokeniser of the model
# doing the retrieval, which means a request out of the process, which is not
# something a regression check may depend on - and a proxy printed under the
# word "tokens" is a fabricated measurement. So the figure is named for what it
# is, everywhere it appears.
#
# CALIBRATED, 2026-09-05. The proxy is no longer only honest, it is measured.
# `evals/token-calibration.sh` reads EXACT counts from the tokeniser itself, via
# `/v1/messages/count_tokens`, which bills nothing, so the calibration is
# repeatable whenever this spec's content changes. Model
# `claude-sonnet-4-5-20250929`; per-request overhead measured at 7 tokens and
# subtracted from every figure below:
#
#   the candidate runs this check reports   3.79 - 4.31   (5 prompts)
#   narrative prose                         4.27          (2227 B /  521 tok)
#   EARS requirement lines                  4.21          (4531 B / 1075 tok)
#   the whole living spec                   3.89          (25592 B / 6582 tok)
#   YAML, this repo's check configuration   3.84          (99799 B / 25978 tok)
#   markdown table rows                     3.74          (14322 B / 3829 tok)
#   shell source, comments and all          3.35          (96636 B / 28807 tok)
#   Python source                           3.12          (6661 B / 2135 tok)
#   shell source, comments stripped         2.33          (2000 B /  859 tok)
#
# HOW TO READ THAT. Within the candidate runs the check actually reports, the
# rate is narrow - 3.79 to 4.31, a spread of 14% - so a budget of N characters
# on the spec as it stands today is about N/4 tokens. Across content types it is
# not narrow at all: 2.33 to 4.31, a spread of 85%. NO CONVERSION FACTOR IS
# PRINTED HERE AND THE WORD "tokens" IS STILL NOT USED FOR THE BUDGET, because a
# factor good to 14% on today's spec is good to nothing on a spec whose content
# mix moves - and the check cannot see that move.
#
# THE BLIND SPOT, MEASURED RATHER THAN ASSERTED. 2000 bytes of this repo's
# requirement prose is 471 tokens. 2000 bytes of shell source with its comments
# stripped is 859. The SAME character count, 82% more tokens. A spec that starts
# quoting interfaces in fenced blocks moves its real retrieval cost by about that
# much while the number this check prints does not move at all.
#
# So a MIX figure is reported beside every budget: the percentage of the
# candidate bytes sitting on a markup or code line - a line that begins with a
# table pipe, begins with a fence, is indented four spaces or a tab, or carries
# a backtick anywhere. It is a byte-only heuristic, it is NOT a token count, and
# it is deliberately NOT banded and NOT a pass or a fail: nothing here has
# measured what a healthy mix is. It exists so that a content shift under a flat
# character budget is visible instead of silent.
#
# The proxy models retrieval as the two steps an agent actually takes:
#
#   1. Search the spec for the prompt's terms. A line is a CANDIDATE when it
#      contains at least one term, case-insensitively, as a substring.
#   2. Read the candidates in file order until the target requirement's
#      definition line - the line carrying `**R<n>**` - is reached.
#
# The budget is the total size of the candidate lines read, up to and including
# the target line. It rises when the target moves down the file, when the terms
# start matching more of the spec, or when the spec grows around it - which are
# the three ways spec retrieval actually degrades.
#
# When the target line is not itself a candidate, the search never surfaces it
# and the agent falls back to reading the whole file. That is reported as
# `full-scan` with the full file size, and it fails regardless of the band: the
# retrieval step did not work, and a full scan that happens to sit inside a wide
# band is not a pass.
#
# HOUSE RULE: a value that could not be measured is never rendered as zero. No
# baseline, a target that does not exist, an unreadable spec - each has its own
# word, its own exit code, and none of them prints a number.
#
# Deterministic: no wall clock is read, so nothing here varies with TZ, and two
# runs over the same bytes produce the same bytes.
#
# Prompt set - `.claude/productizer/retrieval-prompts.tsv`, tab separated:
#
#   # id     target  terms (space separated)
#   login    R4      login session expiry
#
# Baseline - `.claude/productizer/retrieval-baseline.tsv`, written by --record.
# The third field is the mix percentage; it is recorded so a later run can be
# read against it by eye, and a baseline written before this field existed still
# reads correctly, because only the second field is ever compared:
#
#   # id     chars   mix
#   login    412     31
#
# Exit: 0 every prompt in band
#       2 usage, or a malformed prompt set
#       3 no such directory, or no spec to read
#       4 out of band, target missing, or full scan - the check is RED
#       5 no baseline recorded - not a pass, and not a zero
#       6 no prompt set - nothing to measure
#
# --selftest drives every one of those six codes over fixtures built under
# `mktemp -d`, and asserts both that each case exits the code it declares and
# that the set of codes reached is the whole documented set. `--self-test` is
# an alias. Nothing in the repository is read or written by it - in particular
# not the committed prompt set or baseline. Its own exits: 0 every case held,
# 1 one did not or a documented code was never reached, 2 it could not run.
set -euo pipefail

# Byte semantics for awk's length() and for every comparison below. Without it
# the same spec measures differently under two locales, which is the one thing
# a regression eval may not do.
export LC_ALL=C

# Resolved before anything cds anywhere, because the self-test drives its
# cases through this same file and `$0` is relative for most callers.
SELF="$(cd -P "$(dirname "$0")" && pwd -P)/$(basename "$0")"

# A blocking check records the version of the tool that produced its verdict,
# so a silent regression in this file is visible as a diff rather than as an
# unchanged green.
VERSION="retrieval-budget 1.0"

ROOT=""
RECORD=0
SELFTEST=0
BAND=20
PROMPTS=""
BASELINE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --record)     RECORD=1; shift ;;
    --band)       BAND="${2:-}"; [ -n "$BAND" ] || { echo "retrieval-budget: --band needs a percentage" >&2; exit 2; }; shift 2 ;;
    --band=*)     BAND="${1#--band=}"; shift ;;
    --prompts)    PROMPTS="${2:-}"; [ -n "$PROMPTS" ] || { echo "retrieval-budget: --prompts needs a path" >&2; exit 2; }; shift 2 ;;
    --prompts=*)  PROMPTS="${1#--prompts=}"; shift ;;
    --baseline)   BASELINE="${2:-}"; [ -n "$BASELINE" ] || { echo "retrieval-budget: --baseline needs a path" >&2; exit 2; }; shift 2 ;;
    --baseline=*) BASELINE="${1#--baseline=}"; shift ;;
    --selftest|--self-test) SELFTEST=1; shift ;;
    --version)    printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help)    echo "usage: retrieval-budget.sh [repo-root] [--record] [--band PCT] [--prompts PATH] [--baseline PATH]"; exit 0 ;;
    -*)           echo "retrieval-budget: unknown option: $1" >&2; exit 2 ;;
    *)            [ -z "$ROOT" ] || { echo "retrieval-budget: only one repo-root" >&2; exit 2; }; ROOT="$1"; shift ;;
  esac
done

# ---------------------------------------------------------------------------
# --selftest: drive the whole exit-code contract over throwaway fixtures.
#
# R39 obliges a check tool to carry a self-test that REACHES EACH EXIT CODE it
# can return, and this tool documents six: 0, 2, 3, 4, 5 and 6. So the cases
# below are organised by exit code rather than by feature, and the run asserts
# two separate things - that every case exited the code its line declares, AND
# that the set of codes actually reached is the whole documented set. The
# second assertion is the one that catches a contract growing a seventh code
# nobody drove.
#
# NOTHING IN THE REPOSITORY IS READ OR WRITTEN. Every fixture is a spec, a
# prompt set and a baseline built under `mktemp -d` and removed on every exit
# path, signal included. The committed prompt set and the committed baseline
# are never opened here: a self-test that re-records the baseline it is meant
# to be protecting would launder a regression into a new normal.
#
# EXIT CODES OF THE SELF-TEST ITSELF: 0 every case held, 1 at least one did
# not or a documented code was never reached, 2 the self-test could not run -
# no temporary directory. That last one is a guard and is NOT driven by any
# case below, which is said again in the NOT ASSERTED line the run prints.
# ---------------------------------------------------------------------------
if [ "$SELFTEST" -eq 1 ]; then
  SCRATCH="$(mktemp -d)" || { echo "retrieval-budget: cannot create a temporary directory, so no case was driven" >&2; exit 2; }
  trap 'rm -rf "$SCRATCH"' EXIT HUP INT TERM

  # A fixture spec. The `pad` candidate lines sit ABOVE the target, so a budget
  # can be made to rise or fall without touching the prompt set - which is how
  # both out-of-band directions are driven without retuning a single term.
  write_spec() { # write_spec <dir> <pad-lines>
    mkdir -p "$1/.claude/productizer"
    {
      echo '# fixture spec'
      echo
      j=0
      while [ "$j" -lt "$2" ]; do
        echo "- Note $j about the login session, here to widen the candidate scan."
        j=$((j + 1))
      done
      echo
      echo '- **R1** - When a session ends, the lifecycle shall expire the login session.'
      echo
      echo '- **R2** - The lifecycle shall report an absent tool as missing.'
    } > "$1/.claude/productizer/spec.md"
  }

  write_prompt() { # write_prompt <dir> <id> <target> <terms>
    mkdir -p "$1/.claude/productizer"
    { printf '# id\ttarget\tterms\n'; printf '%s\t%s\t%s\n' "$2" "$3" "$4"; } \
      > "$1/.claude/productizer/retrieval-prompts.tsv"
  }

  CASES=0
  UPHELD=0
  REPORT=""
  CODES=""

  # Each case is driven through THIS file, so the argument handling and the
  # guards ahead of the measurement are on the path too. `|| got=$?` because
  # most of these exit non-zero on purpose and `set -e` would otherwise end the
  # run at the first one - right exit code, nothing reported.
  drive() { # drive <name> <expected> <reason> [argv...]
    name="$1"; expected="$2"; reason="$3"; shift 3
    got=0
    bash "$SELF" "$@" > "$SCRATCH/$name.out" 2> "$SCRATCH/$name.err" || got=$?
    CASES=$((CASES + 1))
    if [ "$got" = "$expected" ]; then
      UPHELD=$((UPHELD + 1)); verdict="held"
    else
      verdict="NOT HELD"
    fi
    CODES="$CODES$got
"
    REPORT="$REPORT      $name  expected $expected  got $got  $verdict  $reason
"
  }

  # --- 0: usage, a recorded baseline, and a spec inside its own band --------
  drive help 0 "--help prints the usage line and exits 0" --help
  drive version 0 "--version states which build produced a verdict, and exits 0" --version

  OK_DIR="$SCRATCH/in-band"
  write_spec "$OK_DIR" 2
  write_prompt "$OK_DIR" login R1 "login session expiry"
  drive no-baseline 5 "budgets measured and nothing compared - not a pass, and not a zero" "$OK_DIR"
  drive record 0 "--record writes a baseline for every prompt that reached its target" "$OK_DIR" --record
  drive in-band 0 "the same spec read against its own baseline is in band" "$OK_DIR"

  ALT_DIR="$SCRATCH/alt-paths"
  write_spec "$ALT_DIR" 2
  mkdir -p "$ALT_DIR/evals"
  { printf '# id\ttarget\tterms\n'; printf 'login\tR1\tlogin session expiry\n'; } > "$ALT_DIR/evals/p.tsv"
  drive record-alt 0 "premise for alt-paths: the = forms record to the paths they name" \
    "$ALT_DIR" --record --prompts=evals/p.tsv --baseline=evals/b.tsv
  drive alt-paths 0 "--prompts=, --baseline= and --band= read and band the files they name" \
    "$ALT_DIR" --prompts=evals/p.tsv --baseline=evals/b.tsv --band=25

  # --- 4: out of band both ways, a missing target, a full scan, a refusal ---
  HIGH_DIR="$SCRATCH/out-high"
  write_spec "$HIGH_DIR" 2
  write_prompt "$HIGH_DIR" login R1 "login session expiry"
  drive record-high 0 "premise for out-of-band-high: a baseline taken on the narrow spec" "$HIGH_DIR" --record
  write_spec "$HIGH_DIR" 40
  drive out-of-band-high 4 "forty more candidate lines above the target puts the budget over +20%" "$HIGH_DIR"

  LOW_DIR="$SCRATCH/out-low"
  write_spec "$LOW_DIR" 40
  write_prompt "$LOW_DIR" login R1 "login session expiry"
  drive record-low 0 "premise for out-of-band-low: a baseline taken on the wide spec" "$LOW_DIR" --record
  write_spec "$LOW_DIR" 0
  drive out-of-band-low 4 "the same candidate lines removed puts the budget under -20%" "$LOW_DIR"

  GONE_DIR="$SCRATCH/target-missing"
  write_spec "$GONE_DIR" 2
  write_prompt "$GONE_DIR" ghost R9 "login session expiry"
  drive target-missing 4 "a target that is not in the spec is red and prints a word, never a number" "$GONE_DIR"
  drive record-refused 4 "--record over a prompt that cannot retrieve refuses, rather than making the failure the norm" "$GONE_DIR" --record

  SCAN_DIR="$SCRATCH/full-scan"
  write_spec "$SCAN_DIR" 2
  write_prompt "$SCAN_DIR" scan R2 "login session expiry"
  drive full-scan 4 "a target line matching no term is a fallback to reading the whole file, and fails whatever the band" "$SCAN_DIR"

  # --- 6: nothing to measure ------------------------------------------------
  NOPROMPT_DIR="$SCRATCH/no-prompts"
  write_spec "$NOPROMPT_DIR" 2
  drive no-prompt-set 6 "a spec with no prompt set beside it measured nothing, which is not a pass" "$NOPROMPT_DIR"

  BLANK_DIR="$SCRATCH/blank-prompts"
  write_spec "$BLANK_DIR" 2
  printf '# only a comment\n\n' > "$BLANK_DIR/.claude/productizer/retrieval-prompts.tsv"
  drive empty-prompt-set 6 "a prompt set of blanks and comments holds no prompt to measure" "$BLANK_DIR"

  # --- 3: no spec to retrieve from ------------------------------------------
  NOSPEC_DIR="$SCRATCH/no-spec"
  mkdir -p "$NOSPEC_DIR"
  drive no-spec 3 "a directory with no spec is nothing to retrieve from, not a budget of zero" "$NOSPEC_DIR"
  drive no-such-directory 3 "a root that cannot be entered is refused before anything is measured" "$SCRATCH/absent-root"

  # --- 2: usage, and a prompt set that is not the declared shape ------------
  drive band-not-a-number 2 "--band takes a whole percentage" "$OK_DIR" --band abc
  drive band-over-100 2 "a band above 100 leaves no lower bound at all" "$OK_DIR" --band 150
  drive band-without-value 2 "--band with nothing after it is a usage error, never a silent default" "$OK_DIR" --band
  drive prompts-without-value 2 "--prompts with nothing after it is a usage error" "$OK_DIR" --prompts
  drive baseline-without-value 2 "--baseline with nothing after it is a usage error" "$OK_DIR" --baseline
  drive unknown-option 2 "an option this tool does not know is refused rather than ignored" "$OK_DIR" --nope
  drive two-roots 2 "two repo roots is a usage error - the second would silently win" "$OK_DIR" "$OK_DIR"

  BADLINE_DIR="$SCRATCH/bad-line"
  write_spec "$BADLINE_DIR" 2
  printf 'login R1 login session expiry\n' > "$BADLINE_DIR/.claude/productizer/retrieval-prompts.tsv"
  drive malformed-prompt-line 2 "a line that is not id TAB target TAB terms is refused by line number" "$BADLINE_DIR"

  BADTARGET_DIR="$SCRATCH/bad-target"
  write_spec "$BADTARGET_DIR" 2
  write_prompt "$BADTARGET_DIR" login X1 "login session expiry"
  drive target-not-an-r-id 2 "a target that is not an R-id is refused before any measurement" "$BADTARGET_DIR"

  # --- the two assertions ---------------------------------------------------
  [ "$CASES" -gt 0 ] || { echo "retrieval-budget: no case was driven, so nothing was measured" >&2; exit 2; }

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"

  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/ *$//')"
  MISSING=""
  for want in 0 2 3 4 5 6; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 2 3 4 5 6\n' "$REACHED"

  if [ "$CASES" = "$UPHELD" ]; then SELF_VERDICT="held"; else SELF_VERDICT="NOT HELD"; fi
  printf '    R39.a  %-40s examined %3d  upheld %3d  %s: %s\n' \
    "each-case-exits-the-declared-code" "$CASES" "$UPHELD" "$SELF_VERDICT" \
    "every case exits with the code its line declares"
  if [ -n "$MISSING" ]; then CODE_VERDICT="NOT HELD"; else CODE_VERDICT="held"; fi
  printf '    R39.b  %-40s examined %3d  upheld %3d  %s: %s\n' \
    "every-documented-exit-code-reached" 6 "$((6 - $(printf '%s' "$MISSING" | wc -w | tr -d ' ')))" "$CODE_VERDICT" \
    "the codes the header documents are the codes the cases drove"
  [ -z "$MISSING" ] || echo "retrieval-budget: documented exit code(s) never reached by any case:$MISSING" >&2

  printf '    NOT ASSERTED: the cases drive the exit CODE, never the wording of a finding, so a case red for the wrong reason is invisible here. The self-test own exit 2 - no temporary directory - is a guard no case drives. The band figures are fixture figures; nothing here reads or rewrites the committed prompt set or baseline.\n'

  [ "$CASES" = "$UPHELD" ] || exit 1
  [ -z "$MISSING" ] || exit 1
  exit 0
fi

case "$BAND" in
  ''|*[!0-9]*) echo "retrieval-budget: --band must be a whole percentage, not: $BAND" >&2; exit 2 ;;
esac
[ "$BAND" -le 100 ] || { echo "retrieval-budget: --band above 100 leaves no lower bound: $BAND" >&2; exit 2; }

[ -n "$ROOT" ] || ROOT="."
cd "$ROOT" || { echo "retrieval-budget: no such directory: $ROOT" >&2; exit 3; }

SPEC=".claude/productizer/spec.md"
[ -n "$PROMPTS" ]  || PROMPTS=".claude/productizer/retrieval-prompts.tsv"
[ -n "$BASELINE" ] || BASELINE=".claude/productizer/retrieval-baseline.tsv"

[ -f "$SPEC" ] || {
  echo "retrieval-budget: no spec at $SPEC" >&2
  echo "  Nothing to retrieve from. This is not a budget of zero." >&2
  exit 3
}
[ -r "$SPEC" ] || { echo "retrieval-budget: cannot read $SPEC" >&2; exit 3; }

if [ ! -f "$PROMPTS" ]; then
  echo "retrieval-budget: no prompt set at $PROMPTS" >&2
  echo "  outcome: no-prompt-set. Nothing was measured, and that is not a pass." >&2
  echo "  Write one line per prompt: <id>TAB<target R-id>TAB<terms>" >&2
  exit 6
fi

# The digest is recorded so a baseline can be tied to the spec it was taken
# from. Where no hasher exists the word `unavailable` is printed - a digest that
# could not be computed is not a digest of nothing.
digest() {
  if command -v shasum >/dev/null; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    printf 'unavailable\n'
  fi
}

SPEC_BYTES="$(wc -c < "$SPEC" | tr -d ' ')"
SPEC_DIGEST="$(digest "$SPEC")"

# --- the measurement -------------------------------------------------------
# Prints: <state> <chars> <mix>   where state is found | full-scan |
# target-missing, and mix is the percentage of the counted bytes on a markup or
# code line - see THE BLIND SPOT above for why it is here and what it is not.
#
# `full-scan` and `target-missing` still print a number only where one was
# genuinely measured: the full file size is a real cost; a missing target has no
# cost at all and prints -1, which the caller renders as a word, never as 0. Mix
# prints -1 in both, because the scan stopped before it had counted the bytes a
# percentage would be taken over.
budget_for() { # budget_for <terms> <target-id>
  awk -v terms="$1" -v marker="**$2**" -v fullsize="$SPEC_BYTES" '
    BEGIN { n = split(terms, t, " "); for (i = 1; i <= n; i++) low[i] = tolower(t[i]) }
    {
      line = tolower($0); cand = 0
      for (i = 1; i <= n; i++) if (index(line, low[i]) > 0) { cand = 1; break }
      if (cand) {
        budget += length($0) + 1
        if ($0 ~ /^\|/ || $0 ~ /^```/ || $0 ~ /^(    |\t)/ || index($0, "`") > 0)
          markup += length($0) + 1
      }
      if (index($0, marker) > 0) {
        if (cand) printf "found %d %d\n", budget, (budget > 0 ? int(markup * 100 / budget + 0.5) : 0)
        else      printf "full-scan %d -1\n", fullsize
        seen = 1
        exit
      }
    }
    END { if (!seen) print "target-missing -1 -1" }
  ' "$SPEC"
}

# --- read the prompt set ---------------------------------------------------
IDS=""; TARGETS=""; STATES=""; CHARS=""; MIXES=""
NPROMPTS=0
LINENO_=0
while IFS= read -r raw || [ -n "$raw" ]; do
  LINENO_=$((LINENO_ + 1))
  case "$raw" in ''|'#'*) continue ;; esac
  id="$(printf '%s' "$raw" | cut -f1)"
  target="$(printf '%s' "$raw" | cut -f2)"
  terms="$(printf '%s' "$raw" | cut -f3-)"
  if [ -z "$id" ] || [ -z "$target" ] || [ -z "$terms" ] || [ "$id" = "$target" ]; then
    echo "retrieval-budget: $PROMPTS line $LINENO_ is not <id>TAB<target>TAB<terms>" >&2
    exit 2
  fi
  case "$target" in
    R[0-9]*) ;;
    *) echo "retrieval-budget: $PROMPTS line $LINENO_ - target must be an R-id, not: $target" >&2; exit 2 ;;
  esac
  read -r state chars mix <<EOF
$(budget_for "$terms" "$target")
EOF
  IDS="$IDS$id
"
  TARGETS="$TARGETS$target
"
  STATES="$STATES$state
"
  CHARS="$CHARS$chars
"
  MIXES="$MIXES$mix
"
  NPROMPTS=$((NPROMPTS + 1))
done < "$PROMPTS"

if [ "$NPROMPTS" -eq 0 ]; then
  echo "retrieval-budget: $PROMPTS holds no prompts (only blanks and comments)" >&2
  echo "  outcome: no-prompt-set. Nothing was measured, and that is not a pass." >&2
  exit 6
fi

field() { printf '%s' "$1" | sed -n "${2}p"; }

# --- record ----------------------------------------------------------------
if [ "$RECORD" -eq 1 ]; then
  bad=0
  i=1
  while [ "$i" -le "$NPROMPTS" ]; do
    st="$(field "$STATES" "$i")"
    if [ "$st" != "found" ]; then
      echo "retrieval-budget: prompt $(field "$IDS" "$i") -> $(field "$TARGETS" "$i") is $st" >&2
      bad=$((bad + 1))
    fi
    i=$((i + 1))
  done
  if [ "$bad" -gt 0 ]; then
    echo "retrieval-budget: refusing to record a baseline - $bad prompt(s) cannot retrieve their target." >&2
    echo "  A baseline taken from a spec that already fails the eval makes the failure the norm." >&2
    exit 4
  fi
  mkdir -p "$(dirname "$BASELINE")"
  {
    echo "# retrieval-budget baseline"
    echo "# unit: candidate-scan characters (bytes) - a PROXY for a token budget, not a token count"
    echo "# calibration: 3.79-4.31 bytes/token on candidate runs, 2026-09-05, evals/token-calibration.sh"
    echo "# fields: id, characters (compared against the band), mix percent (recorded, never compared)"
    echo "# spec: $SPEC"
    echo "# spec-bytes: $SPEC_BYTES"
    echo "# spec-sha256: $SPEC_DIGEST"
    i=1
    while [ "$i" -le "$NPROMPTS" ]; do
      printf '%s\t%s\t%s\n' "$(field "$IDS" "$i")" "$(field "$CHARS" "$i")" "$(field "$MIXES" "$i")"
      i=$((i + 1))
    done | sort
  } > "$BASELINE"
  echo "retrieval-budget: recorded $NPROMPTS prompt(s) to $BASELINE"
  exit 0
fi

# --- compare ---------------------------------------------------------------
HAVE_BASELINE=1
[ -f "$BASELINE" ] || HAVE_BASELINE=0

lookup() { # lookup <id> -> baseline chars, or empty
  [ "$HAVE_BASELINE" -eq 1 ] || return 0
  awk -F'\t' -v want="$1" '$1 == want { print $2; found = 1; exit } END { if (!found) exit 0 }' "$BASELINE"
}

lookup_mix() { # lookup_mix <id> -> baseline mix percent, or empty for an older baseline
  [ "$HAVE_BASELINE" -eq 1 ] || return 0
  awk -F'\t' -v want="$1" '$1 == want { print $3; found = 1; exit } END { if (!found) exit 0 }' "$BASELINE"
}

echo "retrieval budget"
echo "  metric   candidate-scan characters (bytes) - a PROXY for a token budget, not a token count"
echo "  rate     3.79-4.31 bytes/token measured on candidate runs 2026-09-05; 2.33-4.31 across content types"
echo "           No factor is applied. Recalibrate with evals/token-calibration.sh when the content mix moves."
echo "  spec     $SPEC ($SPEC_BYTES bytes, sha256 $SPEC_DIGEST)"
echo "  prompts  $PROMPTS ($NPROMPTS)"
if [ "$HAVE_BASELINE" -eq 1 ]; then
  echo "  baseline $BASELINE"
else
  echo "  baseline $BASELINE - ABSENT"
fi
echo "  band     +/-${BAND}%   mix is reported, never banded"
echo
printf '%-16s %-8s %-12s %-12s %-17s %-16s %s\n' "prompt" "target" "budget" "baseline" "band" "mix" "outcome"

RED=0; NOBASE=0; OK=0
i=1
while [ "$i" -le "$NPROMPTS" ]; do
  id="$(field "$IDS" "$i")"
  target="$(field "$TARGETS" "$i")"
  state="$(field "$STATES" "$i")"
  chars="$(field "$CHARS" "$i")"
  mix="$(field "$MIXES" "$i")"
  base="$(lookup "$id")"
  base_mix="$(lookup_mix "$id")"

  budget_s="$chars"; base_s="$base"; band_s="none"; outcome=""

  # A mix that could not be measured is a word, and a baseline written before
  # the field existed leaves the comparison off rather than inventing a zero.
  if [ "$mix" = "-1" ]; then
    mix_s="unmeasured"
  elif [ -n "$base_mix" ]; then
    mix_s="${mix}% (was ${base_mix}%)"
  else
    mix_s="${mix}%"
  fi

  if [ "$state" = "target-missing" ]; then
    budget_s="unmeasured"
    outcome="target-missing"
    RED=$((RED + 1))
  elif [ "$state" = "full-scan" ]; then
    outcome="full-scan"
    RED=$((RED + 1))
  fi

  if [ -z "$base" ]; then
    base_s="none"
    [ -n "$outcome" ] || { outcome="no-baseline"; NOBASE=$((NOBASE + 1)); }
  else
    lo=$(( base * (100 - BAND) / 100 ))
    hi=$(( base * (100 + BAND) / 100 ))
    band_s="${lo}..${hi}"
    if [ -z "$outcome" ]; then
      if [ "$chars" -lt "$lo" ]; then
        outcome="out-of-band-low"; RED=$((RED + 1))
      elif [ "$chars" -gt "$hi" ]; then
        outcome="out-of-band-high"; RED=$((RED + 1))
      else
        outcome="in-band"; OK=$((OK + 1))
      fi
    fi
  fi

  printf '%-16s %-8s %-12s %-12s %-17s %-16s %s\n' "$id" "$target" "$budget_s" "$base_s" "$band_s" "$mix_s" "$outcome"
  i=$((i + 1))
done

echo
echo "in-band $OK   red $RED   no-baseline $NOBASE   of $NPROMPTS"

if [ "$RED" -gt 0 ]; then
  echo "retrieval-budget: RED - $RED prompt(s) outside the band, missing their target, or falling back to a full scan." >&2
  exit 4
fi
if [ "$NOBASE" -gt 0 ]; then
  if [ "$HAVE_BASELINE" -eq 0 ]; then
    echo "retrieval-budget: no baseline at $BASELINE. Record one with --record." >&2
  else
    echo "retrieval-budget: $NOBASE prompt(s) have no baseline entry. Record one with --record." >&2
  fi
  echo "  outcome: no-baseline. The figures above were measured; nothing was compared. This is not a pass." >&2
  exit 5
fi
echo "retrieval-budget: green - $OK prompt(s) in band."
