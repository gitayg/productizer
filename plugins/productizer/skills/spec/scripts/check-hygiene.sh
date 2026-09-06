#!/usr/bin/env bash
# check-hygiene.sh [--version] [--help] [--patterns FILE] [--print-patterns]
#                  [--selftest|--self-test] <file>...
#
# Refuses content that must not reach a public repo: personal filesystem
# paths, machine hostnames, private key material, and anything shaped like a
# credential.
#
# TWO PATTERN SOURCES, UNIONED.
#
#   1. The BUILT-IN generic list below. It names no person, no company and no
#      project, on purpose. This file ships to everyone who installs the
#      plugin, and a deny list that spells out the private names tells every
#      stranger who clones it exactly which names are worth looking for.
#
#   2. An optional LOCAL list, one extended regular expression per line, `#`
#      comments and blank lines ignored. Resolution order:
#
#          --patterns FILE
#          $PRODUCTIZER_HYGIENE_PATTERNS
#          .claude/productizer/hygiene-local.txt under the git work tree
#
#      This is where a maintainer keeps the names they cannot publish - an
#      <employer>, a private project - in a file that is not committed. A
#      local list that was NAMED and cannot be read is exit 2, never a quiet
#      fall back to generic-only: someone who configured a private list and
#      then saw a clean run would believe those names had been checked.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every file examined, nothing found
#   1  findings, reported by location
#   2  could not run - bad usage, an unreadable file, an unreadable local list
#
# Under --selftest the same three mean: every case produced the exit code it
# declares (0), at least one did not (1), and the corpus could not be built at
# all (2). `--self-test` is accepted as an alias, because this repository
# spells the flag both ways and a tool that answers only one spelling is a
# tool whose self-test the next caller cannot find.
#
# WHAT IT PRINTS.
#
#   One BARE PATH per line for every file EXAMINED. The runner parses those as
#   coverage and treats a check that exits 0 having examined less than it
#   declared as hollow, which is a failure and not a pass.
#
#   Findings are INDENTED, and name the file, the line and the CLASS of the
#   finding. THE MATCHED TEXT IS NEVER PRINTED. Printing the offending line
#   once copied a leaked path into the committed checks-result.json, so
#   finding a leak created one, and the next run found its own report.
#
#   A file that was NOT examined - missing, a directory, or binary - is named
#   on an indented line. It is visible, and it is not counted as covered.
#
# WHAT THIS FIXES IN THE 1.0 CHECK. Every one of these was found by a security
# scan of the 1.0 script; none of them may come back.
#
#   - The `PATTERNS=` BYPASS. 1.0 dropped its own definition line by piping
#     the results through `grep -v '^[0-9]*:PATTERNS='`, which exempted any
#     line beginning with that word in ANY scanned file - a real, reproduced
#     bypass. Here the exclusion is by FILE AND LINE NUMBER: exactly the one
#     line of THIS file that defines the list, located by reading this file,
#     and nothing else anywhere. No content-based exemption exists.
#   - FAILING OPEN. 1.0 wrapped grep in `|| true`, which swallowed grep's
#     exit 2. An unreadable file came out as exit 0 AND was reported as
#     covered. Here grep's status is inspected and anything other than
#     match/no-match is exit 2.
#   - `-I` HID BINARIES. A file holding one NUL byte was skipped in silence
#     while still counted as examined. Binaries are named and not counted.
#   - MISSING PATHS VANISHED. 1.0 did `[ -f "$f" ] || continue`. They are
#     named now.
#   - CASE. 1.0 matched case-sensitively against a lower-case list, so a
#     CamelCase spelling walked straight past a rule that named it, into a
#     public commit. Matching is case-insensitive.
#
# PORTABILITY. Developed on macOS/BSD. No GNU-only behaviour: no mapfile, no
# `grep -P`, no `date -d`, no in-place sed. Nothing suppresses stderr.
set -euo pipefail

VERSION="check-hygiene 2.0"

# ONE ALTERNATIVE PER PATTERN, AND NO `|` INSIDE AN ALTERNATIVE. The single
# line is deliberate: other tools read the list as data without executing this
# THE SLUG FORM IS NOT REDUNDANT. Tooling that turns a working directory into a
# cache or scratch key replaces every separator with a hyphen, so a home-
# directory path becomes a single hyphenated run carrying the same username.
# The separator-anchored patterns cannot see it. Measured, not anticipated: a
# scratch path in that form reached a committed result file in this repository
# and the gate passed it clean, while the identical path in ordinary form was
# caught.
#
# ONLY THE CAPITALISED USER-DIRECTORY FORM IS LISTED, AND THE OMISSION IS
# DELIBERATE. The lowercase counterpart was tried and withdrawn: it fires on
# ordinary hyphenated prose, and the first run flagged a check's own name as a
# personal path. A rule that cries wolf on a word is a rule somebody switches
# off, which costs more than the case it would have caught. The capitalised form
# carries a capital letter in the middle of a hyphenated run, which prose does
# not produce. A Linux scratch path in slug form is therefore NOT caught, and
# that is a known hole rather than an oversight.
#
# Nothing in this comment spells either pattern out, deliberately: this file is
# scanned by its own rules, and an example would be a finding.
#
# script. It is also split on `|` at run time for reporting, and
# PATTERN_CLASSES names each alternative in the same order - a length mismatch
# refuses the run rather than mislabelling a finding.
PATTERNS='/Users/[A-Za-z][A-Za-z0-9._-]*|/home/[A-Za-z][A-Za-z0-9._-]*|C:\\Users\\[A-Za-z][A-Za-z0-9._-]*|-Users-[A-Za-z][A-Za-z0-9._-]*|[A-Za-z0-9][A-Za-z0-9-]*\.local[^A-Za-z0-9_.-]|[A-Za-z0-9][A-Za-z0-9-]*\.local$|-----BEGIN [A-Z ]*PRIVATE KEY|gh[opsur]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|A[KS]IA[0-9A-Z]{16}|sk-ant-[A-Za-z0-9_-]{16,}|sk-proj-[A-Za-z0-9_-]{16,}|^sk-[A-Za-z0-9]{20,}|[^A-Za-z0-9]sk-[A-Za-z0-9]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|[sr]k_live_[A-Za-z0-9]{10,}|AIza[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{20,}|eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}'
PATTERN_CLASSES='personal filesystem path|personal filesystem path|personal filesystem path|personal filesystem path, slug form|machine hostname|machine hostname|private key material|GitHub token|GitHub personal access token|AWS access key id|Anthropic API key|OpenAI project API key|OpenAI API key|OpenAI API key|Slack token|Stripe live key|Google API key|npm token|JSON Web Token'

usage() {
  printf 'usage: check-hygiene.sh [--version] [--help] [--patterns FILE] [--print-patterns] [--selftest] <file>...\n'
}

# ---------------------------------------------------------------- arguments

PATTERNS_FILE=""
SELFTEST=""
PATTERNS_SOURCE=""
PRINT_ONLY=""
FILES=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --print-patterns) PRINT_ONLY=1; shift ;;
    --selftest|--self-test) SELFTEST=1; shift ;;
    --patterns)
      if [ "$#" -lt 2 ]; then
        printf 'check-hygiene: --patterns needs a FILE\n' >&2
        exit 2
      fi
      PATTERNS_FILE="$2"; PATTERNS_SOURCE="--patterns"; shift 2 ;;
    --patterns=*)
      PATTERNS_FILE="${1#--patterns=}"; PATTERNS_SOURCE="--patterns"; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do FILES+=("$1"); shift; done ;;
    -*)
      printf 'check-hygiene: unknown option %s\n' "$1" >&2
      usage >&2
      exit 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

# ------------------------------------------------------------- --selftest
#
# R39 - EVERY CHECK TOOL SHALL CARRY A SELF-TEST THAT REACHES EACH EXIT CODE IT
# CAN RETURN. All three of this file's are reachable and all three are driven
# below. Each case is a fixture built in a temporary directory and this script
# re-invoked on it; nothing is written into the tree being checked and the
# corpus is removed on every exit path, signal included.
#
# THE TRIGGER STRINGS ARE ASSEMBLED AT RUN TIME AND NEVER WRITTEN OUT. This
# file is scanned by its own rules - that is the positive control the header
# names - so a literal personal path or a literal key shape written here would
# be a real finding in this script, and the gate would report itself. Every
# offending string below is therefore built from pieces that match nothing
# where they are typed.
#
# THE CHILD RUNS ARE PINNED TO AN EMPTY LOCAL LIST. Without `--patterns` the
# resolution order ends at `.claude/productizer/hygiene-local.txt`, which is
# not committed - so the same case would be clean on one machine and a finding
# on another, and a self-test whose verdict depends on an uncommitted file is
# not evidence. The unreadable-list case below drives the other half of that
# path deliberately.
if [ -n "$SELFTEST" ]; then
  SCRATCH="$(mktemp -d)" || {
    printf 'check-hygiene: cannot create a temporary directory to build the self-test corpus in. Unmeasured, not a pass.\n' >&2
    exit 2; }
  trap 'rm -rf "$SCRATCH"' EXIT HUP INT TERM

  : > "$SCRATCH/no-local-patterns.txt"

  printf 'nothing here but ordinary prose and a relative path, docs/guide.md\n' \
    > "$SCRATCH/clean.txt"

  # A home-directory path. Written as two pieces so this line is not itself one.
  printf 'config lives at %s%s\n' '/Us' 'ers/nobody/.config/app' > "$SCRATCH/personal-path.txt"

  # An AWS access key id shape. Same construction, same reason.
  printf 'aws_access_key_id = %s%s\n' 'AK' 'IA0123456789ABCDEF' > "$SCRATCH/credential.txt"

  # A NUL byte makes it binary: named, and NOT counted as examined.
  printf 'text\000more text\n' > "$SCRATCH/binary.bin"

  mkdir -p "$SCRATCH/a-directory"

  SELF_CASES=0
  SELF_UPHELD=0

  # `record` is called with the exit code ALREADY IN A VARIABLE. A command
  # substitution in an argument list resets $?, so reading the status inside
  # the call would report the status of the call.
  record() { # <case> <expected> <observed> <what the case is>
    SELF_CASES=$((SELF_CASES + 1))
    if [ "$3" = "$2" ]; then
      SELF_UPHELD=$((SELF_UPHELD + 1))
      verdict="held"
    else
      verdict="NOT HELD"
    fi
    printf '      %-26s expected %s  got %s  %s  %s\n' "$1" "$2" "$3" "$verdict" "$4"
  }

  printf '    selftest: %s\n' "$VERSION"

  got=0
  bash "$0" --patterns "$SCRATCH/no-local-patterns.txt" "$SCRATCH/clean.txt" \
    > "$SCRATCH/clean.out" 2> "$SCRATCH/clean.err" || got=$?
  record clean-file 0 "$got" "a file holding no forbidden shape is examined and reported clean"

  got=0
  bash "$0" --patterns "$SCRATCH/no-local-patterns.txt" "$SCRATCH/personal-path.txt" \
    > "$SCRATCH/pp.out" 2> "$SCRATCH/pp.err" || got=$?
  record personal-path 1 "$got" "a home-directory path is a finding"

  got=0
  bash "$0" --patterns "$SCRATCH/no-local-patterns.txt" "$SCRATCH/credential.txt" \
    > "$SCRATCH/cred.out" 2> "$SCRATCH/cred.err" || got=$?
  record credential-shape 1 "$got" "a key-shaped string is a finding"

  # The match itself must never reach the report. This is the one assertion
  # here that is about OUTPUT rather than an exit code, and it is the defect
  # the header records as having shipped once: a leak reported by quoting it.
  leak=0
  grep -qF 'IA0123456789ABCDEF' "$SCRATCH/cred.out" "$SCRATCH/cred.err" || leak=$?
  record match-not-printed 1 "$leak" "the offending text is absent from the finding (grep found nothing, which is exit 1)"

  # Binary alongside a clean file: the binary is named, not counted, and the
  # run is still clean because something WAS examined.
  got=0
  bash "$0" --patterns "$SCRATCH/no-local-patterns.txt" "$SCRATCH/binary.bin" "$SCRATCH/clean.txt" \
    > "$SCRATCH/bin.out" 2> "$SCRATCH/bin.err" || got=$?
  record binary-named-not-scanned 0 "$got" "a NUL-bearing file is named and skipped while the clean file still counts"

  got=0
  bash "$0" --patterns "$SCRATCH/no-local-patterns.txt" \
    > "$SCRATCH/nofiles.out" 2> "$SCRATCH/nofiles.err" || got=$?
  record no-files-given 2 "$got" "nothing scanned is not a clean scan"

  got=0
  bash "$0" --not-a-real-option "$SCRATCH/clean.txt" \
    > "$SCRATCH/badopt.out" 2> "$SCRATCH/badopt.err" || got=$?
  record unknown-option 2 "$got" "bad usage is refused, never answered"

  got=0
  bash "$0" --patterns "$SCRATCH/no-such-list.txt" "$SCRATCH/clean.txt" \
    > "$SCRATCH/nolist.out" 2> "$SCRATCH/nolist.err" || got=$?
  record named-list-unreadable 2 "$got" "a configured local list that could not be read refuses rather than falling back to generic-only"

  got=0
  bash "$0" --patterns "$SCRATCH/no-local-patterns.txt" "$SCRATCH/a-directory" "$SCRATCH/absent.txt" \
    > "$SCRATCH/none.out" 2> "$SCRATCH/none.err" || got=$?
  record nothing-examinable 2 "$got" "every path given was a directory or missing, so the run has no evidence in it"

  if [ "$SELF_CASES" = "$SELF_UPHELD" ]; then self_verdict="held"; else self_verdict="NOT HELD"; fi
  printf '    R39  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$SELF_CASES" "$SELF_UPHELD" "$self_verdict" \
    "each case exits with the code this file's contract declares for it"
  printf '    exit codes reached: 0, 1 and 2 - the whole contract.\n'
  printf '    NOT ASSERTED: the default local-list resolution ($PRODUCTIZER_HYGIENE_PATTERNS and .claude/productizer/hygiene-local.txt) is pinned out of every case above, because that file is not committed and a case whose verdict depends on it is not evidence. Only the --patterns arm of that path is driven.\n'
  [ "$SELF_CASES" = "$SELF_UPHELD" ] || exit 1
  exit 0
fi

# ------------------------------------------------------- the built-in list

BUILTIN=()
CLASSES=()
IFS='|' read -r -a BUILTIN <<< "$PATTERNS"
IFS='|' read -r -a CLASSES <<< "$PATTERN_CLASSES"
if [ "${#BUILTIN[@]}" -ne "${#CLASSES[@]}" ]; then
  printf 'check-hygiene: %d built-in patterns but %d class labels. A finding would be mislabelled, so the run is refused.\n' \
    "${#BUILTIN[@]}" "${#CLASSES[@]}" >&2
  exit 2
fi

# --------------------------------------------------------- the local list

# The work tree is found by walking up for a `.git`, rather than by asking
# git, so that running outside a repository is silent instead of writing a
# fatal line to stderr. Nothing here may suppress stderr to tidy that up.
find_work_tree() {
  local d
  d="$PWD"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -e "$d/.git" ]; then
      printf '%s\n' "$d"
      return 0
    fi
    d="$(dirname -- "$d")"
  done
  if [ -e "/.git" ]; then
    printf '/\n'
  fi
  return 0
}

if [ -z "$PATTERNS_FILE" ] && [ -n "${PRODUCTIZER_HYGIENE_PATTERNS:-}" ]; then
  PATTERNS_FILE="$PRODUCTIZER_HYGIENE_PATTERNS"
  PATTERNS_SOURCE="\$PRODUCTIZER_HYGIENE_PATTERNS"
fi

if [ -z "$PATTERNS_FILE" ]; then
  WORK_TREE="$(find_work_tree)"
  if [ -n "$WORK_TREE" ] && [ -e "$WORK_TREE/.claude/productizer/hygiene-local.txt" ]; then
    PATTERNS_FILE="$WORK_TREE/.claude/productizer/hygiene-local.txt"
    PATTERNS_SOURCE="the default local list"
  fi
fi

LOCAL_PATTERNS=()
if [ -n "$PATTERNS_FILE" ]; then
  if [ ! -f "$PATTERNS_FILE" ] || [ ! -r "$PATTERNS_FILE" ]; then
    printf 'check-hygiene: cannot read the local pattern list %s (named by %s). A configured list that was not read is unmeasured, not clean - refusing rather than checking the generic patterns alone.\n' \
      "$PATTERNS_FILE" "$PATTERNS_SOURCE" >&2
    exit 2
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    leading="${line%%[![:space:]]*}"
    trimmed="${line#"$leading"}"
    case "$trimmed" in
      ''|'#'*) continue ;;
    esac
    LOCAL_PATTERNS+=("$trimmed")
  done < "$PATTERNS_FILE"
fi

if [ -n "$PRINT_ONLY" ]; then
  for p in "${BUILTIN[@]}"; do printf '%s\n' "$p"; done
  if [ "${#LOCAL_PATTERNS[@]}" -gt 0 ]; then
    for p in "${LOCAL_PATTERNS[@]}"; do printf '%s\n' "$p"; done
  fi
  exit 0
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  printf 'check-hygiene: no files given. Nothing scanned is not a clean scan.\n' >&2
  usage >&2
  exit 2
fi

# ------------------------------------------------------------- the scan

GREP_ARGS=(-e "$PATTERNS")
if [ "${#LOCAL_PATTERNS[@]}" -gt 0 ]; then
  for p in "${LOCAL_PATTERNS[@]}"; do GREP_ARGS+=(-e "$p"); done
fi

# The ONE self-exemption, and it is a coordinate, not a rule about content:
# the single line of THIS file that defines the pattern list. Everything else
# in this file is scanned like anything else - run it on itself, that is the
# positive control.
SELF="${BASH_SOURCE[0]}"
SELF_DEF_LINE="$(awk '/^PATTERNS=/{print NR; exit}' "$SELF")"
SELF_ID=""
if [ -r "$SELF" ]; then
  SELF_ID="$(ls -diL -- "$SELF" | awk '{print $1}')"
fi

# A file is binary if it holds a NUL byte anywhere. Deciding this here, rather
# than letting `grep -I` decide it silently, is what makes a skipped binary
# something the reader sees.
is_binary() {
  local total kept
  total="$(wc -c < "$1")"
  kept="$(LC_ALL=C tr -d '\000' < "$1" | wc -c)"
  [ "$total" -ne "$kept" ]
}

# Name the CLASS by re-testing the line against each pattern with the same
# engine that matched it. The line is held in a variable and never printed.
classify() {
  local content="$1" out="" lab i n
  n="${#BUILTIN[@]}"
  for ((i = 0; i < n; i++)); do
    if LC_ALL=C grep -Eqi -e "${BUILTIN[$i]}" <<< "$content"; then
      lab="${CLASSES[$i]}"
      case ", $out, " in
        *", $lab, "*) ;;
        *) out="${out:+$out, }$lab" ;;
      esac
    fi
  done
  n="${#LOCAL_PATTERNS[@]}"
  for ((i = 0; i < n; i++)); do
    if LC_ALL=C grep -Eqi -e "${LOCAL_PATTERNS[$i]}" <<< "$content"; then
      lab="local list entry $((i + 1))"
      case ", $out, " in
        *", $lab, "*) ;;
        *) out="${out:+$out, }$lab" ;;
      esac
    fi
  done
  if [ -z "$out" ]; then
    out="forbidden pattern"
  fi
  printf '%s\n' "$out"
}

found=0
examined=0
for f in "${FILES[@]}"; do
  if [ ! -e "$f" ]; then
    printf '    %s: does not exist (deleted in this change?) - NOT examined\n' "$f"
    continue
  fi
  if [ -d "$f" ]; then
    printf '    %s: is a directory - NOT examined\n' "$f"
    continue
  fi
  if [ ! -r "$f" ]; then
    printf 'check-hygiene: cannot read %s. Unmeasured, not clean - a file nobody could open is not a clean file.\n' "$f" >&2
    exit 2
  fi
  if is_binary "$f"; then
    printf '    %s: binary (holds a NUL byte) - NOT examined, and NOT counted as clean\n' "$f"
    continue
  fi

  printf '%s\n' "$f"          # coverage: one bare path per file examined
  examined=$((examined + 1))

  skip_line=""
  if [ -n "$SELF_ID" ] && [ -n "$SELF_DEF_LINE" ]; then
    if [ "$(ls -diL -- "$f" | awk '{print $1}')" = "$SELF_ID" ]; then
      skip_line="$SELF_DEF_LINE"
    fi
  fi

  set +e
  hits="$(LC_ALL=C grep -Eni "${GREP_ARGS[@]}" -- "$f")"
  grc=$?
  set -e
  case "$grc" in
    0) ;;
    1) hits="" ;;
    *)
      printf 'check-hygiene: grep exited %s on %s. Unmeasured, not clean.\n' "$grc" "$f" >&2
      exit 2 ;;
  esac

  if [ -n "$hits" ]; then
    while IFS= read -r hit; do
      ln="${hit%%:*}"
      content="${hit#*:}"
      if [ "$ln" = "$skip_line" ]; then
        continue
      fi
      printf '    %s:%s: %s - open the file at that line; the match is deliberately not printed\n' \
        "$f" "$ln" "$(classify "$content")"
      found=1
    done <<< "$hits"
  fi
done

# NOTHING EXAMINED IS NOT A CLEAN SCAN, and this file already said so - for
# zero ARGUMENTS. It did not say so for arguments that all turned out to be
# unexaminable: two paths that do not exist scanned nothing and exited 0, which
# is a clean bill of health over a set the tool never opened. Measured, not
# argued - it is how a caller that mangles its file list gets a green.
#
# Missing files are individually fine: a change set legitimately names a file it
# deleted. What is not fine is EVERY one of them being unexaminable, because
# then the run has no evidence in it at all.
if [ "$examined" -eq 0 ]; then
  printf 'check-hygiene: %d path(s) given and none could be examined - all missing, directories, or binary. Nothing was scanned, so nothing is clean. Unmeasured, not a pass.\n' "${#FILES[@]}" >&2
  exit 2
fi

printf '    files examined: %d of %d given\n' "$examined" "${#FILES[@]}"
exit "$found"
