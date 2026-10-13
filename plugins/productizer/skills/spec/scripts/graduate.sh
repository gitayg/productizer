#!/usr/bin/env bash
# scripts/graduate.sh — harvest repeated corrections, cluster them, promote them.
#
# A correction is a human telling the agent it got something wrong. Corrections
# are the cheapest signal a repo produces and the one it throws away fastest:
# they live in a transcript nobody reads again. This walks them up a ladder.
#
#   graduate.sh lexicon                  print the two lexicons and the thresholds
#   graduate.sh harvest  [opts]          scan sources, write corrections.jsonl
#   graduate.sh present  [opts]          cluster, threshold, draft ops, print cards
#   graduate.sh excerpts --id TAG        the raw messages behind one cluster
#   graduate.sh apply    --id TAG --decide accept
#   graduate.sh undo     --id TAG
#   graduate.sh --selftest               drive every exit code in a throwaway root
#
#   --version          print the version and exit 0
#   --help             print this header and exit 0
#   --selftest         build a throwaway root under mktemp, drive each exit
#                      code below and the path rules, and exit 0 if every case
#                      held, 1 if one did not, 2 if the cases could not be
#                      built. `--self-test` is an alias.
#   --root DIR         repo the guidance is promoted into. Default: the git
#                      work tree holding the working directory - NOT the
#                      working directory itself. Defaulting to the CWD has
#                      produced four separate silent wrong answers here, each
#                      of which looked like a clean run from a subdirectory.
#                      Outside a work tree there is no default: --root is
#                      required, because guessing is what caused those four.
#   --work DIR         where harvest/draft/journal state lives.
#                      Default <root>/.claude/productizer/graduation
#   --transcripts DIR  root of Claude Code project transcripts.
#                      Default $CLAUDE_TRANSCRIPTS, else ~/.claude/projects
#   --source LIST      comma list of transcripts,pr. Default transcripts
#   --refresh-context  re-run detect-context.sh instead of using the cached probe
#
#   A relative --work or --transcripts is read under the ROOT, NOT the working
#   directory, and a relative --work is created there; an absolute one is used
#   as given. A relative --root is read from the working directory, once. The
#   transcripts default ($CLAUDE_TRANSCRIPTS, else ~/.claude/projects) is not a
#   path option and is used as it reads. Through 1.1 a relative --work was
#   created under the working directory and a relative --transcripts read from
#   it (B141, ruled "converge on repo root").
#
# THE HUMAN DECIDES. There is no auto-apply flag, defaulted on or otherwise.
# `present` writes nothing outside --work. `apply` refuses without an explicit
# `--decide accept` naming one cluster.
#
# Counting is by DISTINCT CONVERSATION, not by message. Ten repeats in one
# session is one lesson badly received; three across three sessions is a rule.
# The promotion threshold is 3 distinct conversations. That number is here, in
# THRESHOLD_CONVERSATIONS, and nowhere else.
#
# The ladder is prose -> skill -> hook -> ci-gate. Instructions are advisory and
# decay as the context window fills; checks are deterministic and never tire. A
# cluster climbs as high as its evidence justifies and no higher — the rung is
# recommended, printed, and never silently taken.
#
# EACH RUNG ASSERTS A DIFFERENT PROPERTY. Not the same check three times with
# the volume turned up — that is one check, and calling it three is how a ladder
# reports progress that did not happen.
#
#   prose    a line in CLAUDE.md. Asserts nothing. It is read, or it is not.
#   skill    a file under .claude/productizer/graduated/. Asserts nothing
#            either, and says so in its own body; it buys detail and a place to
#            put the evidence, not enforcement.
#   hook     ONE PROPOSED ACTION, judged from the tool payload BEFORE it runs.
#            Reaches text that never becomes a file — a Bash command line is
#            judged here and by nothing else. It never opens a file in the
#            repository and has no denominator.
#   ci-gate  EVERY TRIGGERING FILE IN THE TREE, after the fact, with a declared
#            coverage denominator. Sees the violation the hook never could: one
#            already on disk, edited outside the agent, arriving in a merge, or
#            made by a tool the hook is not registered on. A run that failed to
#            open a file it should have read is a refusal, not a pass — which
#            is the verdict a hook cannot express.
#
# A RUNG IS ONLY OFFERED IF A RULE FOR IT IS WRITTEN. See RULES below. A cluster
# with no rule caps at skill; a cluster whose rule has no `gate` caps at hook.
# The previous version of this file emitted a hook whose body was `exit 0` and a
# checks.yaml entry whose command was the empty string, which is the same defect
# as recording an unmeasured value as a zero.
#
# Clustering is a lexicon, not a model. Every grouping decision is a named
# regex you can read in `graduate.sh lexicon`. A correction that matches no
# topic tag is not guessed at and not dropped: it lands in UNDECIDED and is
# escalated to the human as its own card.
#
# Apply is all-or-nothing and precondition-checked. A create must not already
# exist; an update or remove must match the target file exactly as it was when
# the suggestion was drafted. On any mismatch nothing is written at all and the
# suggestion is flagged, rather than silently clobbering your work. Undo
# restores prior contents, and only if the file still matches what was written.
#
# What this cannot do: it extends a lexicon from corrections people actually
# made. It trains nothing, and it produces precision data only — the corrections
# that WERE voiced. It has no view of the ones nobody bothered to voice, so it
# cannot close a recall gap. See references/graduation.md.
#
# Exit: 0  did the thing
#       2  usage
#       3  no source was available at all — nothing was scanned
#       4  sources were present but nothing in them would parse
#       5  sources parsed, and zero messages were corrections (a measured zero)
#       6  corrections found, none reached the conversation threshold
#       7  apply refused: a precondition failed. NOTHING was written.
#       8  undo refused: a file no longer matches what apply wrote.
set -euo pipefail

export TZ=UTC
export LC_ALL=C

VERSION="graduate 1.2"

THRESHOLD_CONVERSATIONS=3
RUNG_SCORE_SKILL=12
RUNG_SCORE_HOOK=36
RUNG_SCORE_GATE=72

die_usage() { printf 'graduate: %s\n' "$1" >&2; exit 2; }

# The header IS the help, and it used to be printed as a hard-coded line range.
# A range goes stale the first time anyone edits the header, and it did. Print
# from line 2 to the line before `set -euo pipefail` instead, so the two cannot
# drift apart.
show_help() { sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d'; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$HERE/detect-context.sh"
# The rung templates ship with this script, not with the repo being examined.
# P4: a repository under examination never chooses what runs, and it does not
# choose what gets written into it either.
TMPL_DIR="$HERE/../templates/graduate"

[ $# -gt 0 ] || die_usage "no subcommand. One of: lexicon, harvest, present, excerpts, apply, undo."

CMD=""
case "$1" in
  lexicon|harvest|present|excerpts|apply|undo) CMD="$1"; shift ;;
  -h|--help) show_help; exit 0 ;;
  --version) printf '%s\n' "$VERSION"; exit 0 ;;
  --selftest|--self-test) CMD="selftest"; shift ;;
  -*) die_usage "unknown option before the subcommand: $1" ;;
  *)  die_usage "unknown subcommand: $1" ;;
esac

# --------------------------------------------------------------- --selftest
#
# R39: every exit code this file documents - 0 2 3 4 5 6 7 8 - is reached by
# a case below, each driving THIS script as a child in a throwaway root under
# mktemp, and each asserting a sentence of its output as well as its code. The
# path rules are cases too: a relative --work and --transcripts are given from
# a working directory holding a decoy of the same name, and must resolve under
# the root.
#
# NO NETWORK. harvest runs detect-context.sh, which asks gh about the account,
# only when its cached probe is missing - so every work directory is seeded
# with a probe first. Nothing is written outside the temporary directory.
if [ "$CMD" = "selftest" ]; then
  [ $# -eq 0 ] || die_usage "--selftest takes no further arguments; got: $1"
  command -v python3 >/dev/null ||
    die_usage "python3 is not on PATH, so no case could be driven"
  SELF_ABS="$HERE/${BASH_SOURCE[0]##*/}"
  T="$(mktemp -d)" || die_usage "cannot create a temporary directory for the self-test"
  trap 'rm -rf "$T"' EXIT HUP INT TERM
  R="$T/root"
  mkdir -p "$R/tx" "$R/tx-low" "$R/tx-zero" "$R/tx-bad" "$R/w" "$R/w-low" \
           "$R/w-zero" "$R/w-bad" "$R/w-none" "$T/decoy/tx" "$T/decoy/w" ||
    die_usage "could not lay out the self-test root"
  for d in w w-low w-zero w-bad w-none; do
    printf '{"detect_context":"selftest"}\n' > "$R/$d/context.json"
  done
  printf '{"detect_context":"selftest"}\n' > "$T/decoy/w/context.json"
  # A session is the task, the agent's reply, then the person's correction.
  session() { # <session id> <correction text>
    printf '{"type":"user","sessionId":"%s","message":{"content":"write a page"}}\n' "$1"
    printf '{"type":"assistant","sessionId":"%s","message":{"content":"done"}}\n' "$1"
    printf '{"type":"user","sessionId":"%s","message":{"content":"%s"}}\n' "$1" "$2"
  }
  for i in 1 2 3; do session "s$i" "do not use emoji again" > "$R/tx/s$i.jsonl"; done
  session s1 "do not use emoji again" > "$R/tx-low/s1.jsonl"
  session s1 "thank you, that looks right" > "$R/tx-zero/s1.jsonl"
  printf 'this is not json\n' > "$R/tx-bad/s1.jsonl"

  CASES=0; UPHELD=0; CODES=""
  # case <name> <want> <sentence> <what> -- <args...>. DRIVE_CWD, when set, is
  # the working directory the child runs from.
  DRIVE_CWD=""
  self_case() {
    local name="$1" want="$2" says="$3" what="$4" got=0 v="held"
    shift 5
    ( cd "${DRIVE_CWD:-$T}" && bash "$SELF_ABS" "$@" ) > "$T/$name.out" 2> "$T/$name.err" || got=$?
    CASES=$((CASES + 1))
    CODES="$CODES$got
"
    if [ "$got" != "$want" ]; then
      v="NOT HELD"
    elif ! grep -qF -- "$says" "$T/$name.out" "$T/$name.err"; then
      v="NOT HELD (right code, missing: $says)"
    fi
    [ "$v" != "held" ] || UPHELD=$((UPHELD + 1))
    printf '      %-28s expected %s  got %s  %s  %s\n' "$name" "$want" "$got" "$v" "$what"
  }
  # An assertion about the filesystem after a case, counted as its own case.
  self_fact() { # <name> <what> <command...>
    local name="$1" what="$2" v="held"
    shift 2
    CASES=$((CASES + 1))
    if "$@"; then UPHELD=$((UPHELD + 1)); else v="NOT HELD"; fi
    printf '      %-28s %-28s %s  %s\n' "$name" "(a file-system fact)" "$v" "$what"
  }

  printf '    selftest: %s\n' "$VERSION"
  self_case lexicon 0 "promotion threshold: 3 distinct conversations" \
    "the lexicons and thresholds print" -- lexicon --root "$R" --work "$R/w"
  self_case bad-usage 2 "unknown option: --frobnicate" \
    "an option this script does not take" -- harvest --root "$R" --frobnicate
  self_case no-source 3 "NO SOURCE WAS AVAILABLE" \
    "a transcripts directory that is not there - a scan that did not happen" \
    -- harvest --root "$R" --work "$R/w-none" --transcripts "$R/nowhere"
  self_case unparseable 4 "NOTHING PARSEABLE" \
    "a transcript that is not JSON lines - no count, because none was measured" \
    -- harvest --root "$R" --work "$R/w-bad" --transcripts "$R/tx-bad"
  self_case measured-zero 5 "A MEASURED ZERO" \
    "read, and no message is a correction - a real zero" \
    -- harvest --root "$R" --work "$R/w-zero" --transcripts "$R/tx-zero"
  self_case harvest-low 0 "harvested  1 correction(s)" \
    "one correction, in one conversation" \
    -- harvest --root "$R" --work "$R/w-low" --transcripts "$R/tx-low"
  self_case below-threshold 6 "NOTHING REACHED THE THRESHOLD" \
    "one conversation is below the three the threshold needs" \
    -- present --root "$R" --work "$R/w-low"

  # B141: the path rules. The decoy working directory holds an EMPTY tx/ (exit
  # 3 if read) and its own w/; both relative options must resolve under the
  # root. Through 1.1 both resolved here, in the decoy.
  DRIVE_CWD="$T/decoy"
  self_case relative-paths 0 "harvested  3 correction(s)" \
    "a relative --transcripts and --work are read under the root, never the working directory" \
    -- harvest --root "$R" --work w --transcripts tx
  DRIVE_CWD=""
  landed_under_root() { [ -f "$R/w/corrections.jsonl" ] && [ ! -e "$T/decoy/w/corrections.jsonl" ]; }
  self_fact relative-work-under-root "the harvest landed in <root>/w, and nothing in the decoy w/" \
    landed_under_root

  self_case present 0 "1 cluster(s) reached the threshold" \
    "three conversations reach the threshold, and nothing is written outside --work" \
    -- present --root "$R" --work "$R/w"
  printf 'somebody wrote this first\n' > "$R/CLAUDE.md"
  self_case apply-refused 7 "PRECONDITION FAILED - NOTHING WAS WRITTEN" \
    "the file the draft would create already exists" \
    -- apply --root "$R" --work "$R/w" --id no-emoji --decide accept
  rm -f "$R/CLAUDE.md"
  self_case apply 0 "applied 1 operation(s)" \
    "accepted by name, written under the root" \
    -- apply --root "$R" --work "$R/w" --id no-emoji --decide accept
  cp "$R/CLAUDE.md" "$T/as-applied.md"
  printf 'an edit made after apply\n' >> "$R/CLAUDE.md"
  self_case undo-refused 8 "UNDO REFUSED - NOTHING WAS RESTORED" \
    "a file edited after apply is not restored over" \
    -- undo --root "$R" --work "$R/w" --id no-emoji
  cp "$T/as-applied.md" "$R/CLAUDE.md"
  self_case undo 0 "removed  CLAUDE.md" \
    "the file apply created is removed again" \
    -- undo --root "$R" --work "$R/w" --id no-emoji

  if [ "$CASES" = "$UPHELD" ]; then V="held"; else V="NOT HELD"; fi
  printf '    R39  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$CASES" "$UPHELD" "$V" \
    "each case exits with the code this file's contract declares for it, for the reason it names"
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 2 3 4 5 6 7 8; do
    grep -qx "$want" <<<"$CODES" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 2 3 4 5 6 7 8\n' "$REACHED"
  printf '    NOT ASSERTED: the pr source, the hook and ci-gate rungs, excerpts, prune, and the content of a drafted rung; detect-context.sh is never run, so what harvest records about the repository is not exercised.\n'
  [ "$CASES" = "$UPHELD" ] || exit 1
  if [ -n "$MISSING" ]; then
    printf 'graduate: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  exit 0
fi

ROOT=""
WORK=""
TRANSCRIPTS=""
SOURCES="transcripts"
ID=""
DECIDE=""
REFRESH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root)         [ $# -ge 2 ] || die_usage "--root needs a directory";       ROOT="$2"; shift 2 ;;
    --root=*)       ROOT="${1#--root=}"; shift ;;
    --work)         [ $# -ge 2 ] || die_usage "--work needs a directory";       WORK="$2"; shift 2 ;;
    --work=*)       WORK="${1#--work=}"; shift ;;
    --transcripts)  [ $# -ge 2 ] || die_usage "--transcripts needs a directory"; TRANSCRIPTS="$2"; shift 2 ;;
    --transcripts=*) TRANSCRIPTS="${1#--transcripts=}"; shift ;;
    --source)       [ $# -ge 2 ] || die_usage "--source needs a list";          SOURCES="$2"; shift 2 ;;
    --source=*)     SOURCES="${1#--source=}"; shift ;;
    --id)           [ $# -ge 2 ] || die_usage "--id needs a cluster id";        ID="$2"; shift 2 ;;
    --id=*)         ID="${1#--id=}"; shift ;;
    --decide)       [ $# -ge 2 ] || die_usage "--decide needs a decision";      DECIDE="$2"; shift 2 ;;
    --decide=*)     DECIDE="${1#--decide=}"; shift ;;
    --refresh-context) REFRESH=1; shift ;;
    -h|--help)      show_help; exit 0 ;;
    --version)      printf '%s\n' "$VERSION"; exit 0 ;;
    -*)             die_usage "unknown option: $1" ;;
    *)              die_usage "unexpected argument: $1" ;;
  esac
done

# No 2>&1 here. This repo greps its own shell for a suppressed stderr, and a
# `command -v` that hides its own errors is the pattern the grep is looking
# for. Binning stdout alone says nothing about errors.
command -v python3 >/dev/null ||
  die_usage "python3 is not on PATH. Refusing rather than half-parsing transcripts with awk."

# NOT the working directory. `.` made every answer depend on which directory the
# operator happened to be standing in, and a wrong root here writes guidance
# into the wrong repo. git speaks for itself on stderr when there is no work
# tree, so nothing here needs to paraphrase it.
if [ -z "$ROOT" ]; then
  if ! ROOT="$(git rev-parse --show-toplevel)"; then
    die_usage "no --root given and this is not a git work tree, so there is no root to default to. Pass --root DIR."
  fi
fi
[ -d "$ROOT" ] || die_usage "no such directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"

# A path option is read under the root when relative and used as given when
# absolute. Through 1.1 a relative --work was created under the working
# directory - guidance state for one repo written into whatever directory the
# operator stood in.
under_root() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *)  printf '%s' "$ROOT/$1" ;;
  esac
}
WORK="$(under_root "${WORK:-.claude/productizer/graduation}")"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"

if [ -n "$TRANSCRIPTS" ]; then
  TRANSCRIPTS="$(under_root "$TRANSCRIPTS")"
else
  TRANSCRIPTS="${CLAUDE_TRANSCRIPTS:-$HOME/.claude/projects}"
fi

# --- the lexicons ------------------------------------------------------------
# Both are data, printed by `graduate.sh lexicon`, and every clustering decision
# this script makes is traceable to one line of them. That is the whole point:
# an opaque similarity score would group better and be unarguable, which is the
# wrong trade for a tool whose output a human has to rule on.
#
# CUE decides whether a message is a correction at all.
# TOPIC decides which cluster it joins, and whether that cluster is the kind of
# thing a deterministic check could ever assert.
LEXICON_PY='
CUES = [
    ("negation",     r"^\s*(no|nope|not quite|wrong)\b|\b(that\x27s|thats|this is) (not|wrong)\b"),
    ("prohibition",  r"\b(don\x27t|do not|never|stop)\b"),
    ("repetition",   r"\b(again|as i said|i said|i already|i told you|like i told you)\b"),
    ("wrongness",    r"\b(wrong|incorrect|broken|you broke|that\x27s a bug)\b"),
    ("undo",         r"\b(revert|undo|roll it back|roll back|back out)\b"),
    ("redirection",  r"\b(instead|actually|rather than|should have|was supposed to)\b"),
    ("omission",     r"\b(you forgot|you missed|you didn\x27t|you did not|still missing|you skipped)\b"),
]

# A cluster is CHECKABLE if and only if RULES below carries a rule for it, and
# it reaches ci-gate only if that rule carries a `gate`. The flag used to be a
# hand-set boolean: eight clusters claimed it while this file could write zero
# checks, so every promotion to hook or ci-gate produced a stub that asserted
# nothing. A claim nothing can fill is the same defect as an unmeasured zero.
TOPICS = [
    ("run-tests",             r"\brun (the )?(unit |integration )?tests?\b|\btest suite\b|\bwithout running the tests\b",
     "asked agents to run the tests before saying a change was ready"),
    ("no-stderr-suppression", r"2>\s*/dev/null|\bsuppress(ing|ed)? stderr\b|\bswallow(ing|ed)? (the )?errors?\b",
     "told agents not to suppress stderr"),
    ("absolute-paths",        r"\babsolute paths?\b|\brelative path\b",
     "asked for absolute paths"),
    ("no-blind-staging",      r"\bgit add -A\b|\bgit add \.\b|\bstage (the )?(specific )?files by name\b",
     "told agents to stage files by name instead of staging everything"),
    ("version-bump",          r"\bbump (the )?version\b|\bversion (number|bump)\b|\bforgot to bump\b",
     "asked for the version to be bumped before the commit"),
    ("update-docs",           r"\breadme\b|\bchangelog\b|\bupdate (the )?docs?\b|\bdocumentation\b",
     "asked for the docs to be updated in the same change"),
    ("no-emoji",              r"\bemoji(s)?\b",
     "asked agents not to use emoji"),
    ("file-ownership",        r"\bdon\x27t touch\b|\boff.limits\b|\bnever (modify|edit|touch)\b|\byou own only\b",
     "told agents to stay inside the files they own"),
    ("verify-before-claiming", r"\bsee it fail\b|\bprove it\b|\bverbatim\b|\bdon\x27t (just )?(claim|assume)\b|\bevidence\b",
     "asked agents to show evidence instead of asserting a result"),
    ("scope-discipline",      r"\bout of scope\b|\bdidn\x27t ask\b|\bdid not ask\b|\bonly what (i|we) asked\b|\bstop adding\b",
     "asked agents not to go beyond what was asked"),
]

# THE RULE TABLE. One entry is one property a machine can decide, written out
# here where it can be read and argued with, exactly as the lexicons are.
#
#   what         the violation, in a phrase the blocked agent reads.
#   matchers     the PreToolUse tool names whose payload the hook can read. A
#                payload from any other tool is REFUSED, never approved: a hook
#                registered on the wrong matcher would be reading a shape it
#                does not understand and passing everything.
#   hook_re      a Python regex, applied per line to the text the proposed
#                action would introduce.
#   skip_shell_comments  a comment cannot run anything, so for shell-shaped
#                rules a commented line is skipped, the same way the repo-wide
#                stderr check skips one.
#   gate         present only when the SAME property is expressible as one
#                POSIX ERE over file bytes. It has to be: the ci-gate rung must
#                be argv-only and must never run anything out of the repository
#                it is gating (P4), which leaves grep and nothing else. A
#                property that needs a program is a hook property and stops
#                there. That cap is real and stated, not papered over.
#
# The gate ERE demands a non-comment first character on the line, and it
# deliberately does not match the way it is spelled here - a bracket follows
# every redirection instead of a slash - so this file does not flag itself.
RULES = {
    "no-stderr-suppression": {
        "what": "stderr thrown away, which makes an error and a genuine no-match identical",
        "matchers": ["Bash", "Write", "Edit", "MultiEdit", "NotebookEdit"],
        "hook_re": r"2[ \t]*>>?[ \t]*/dev/null|2[ \t]*>&[ \t]*-|&>>?[ \t]*/dev/null|>&[ \t]*/dev/null|1?>>?[ \t]*/dev/null[ \t]+2[ \t]*>&[ \t]*1",
        "skip_shell_comments": True,
        "gate": {
            "paths": ["**/*.sh", "**/*.bash"],
            "ere": r"^[[:space:]]*[^#[:space:]].*(2[[:space:]]*>>?[[:space:]]*/dev/null|2[[:space:]]*>&[[:space:]]*-|&>>?[[:space:]]*/dev/null|>&[[:space:]]*/dev/null|1?>>?[[:space:]]*/dev/null[[:space:]]+2[[:space:]]*>&[[:space:]]*1)",
            "why": "a script that bins stderr reports an error and a real no-match identically, so the run is green either way and the wrong thing gets fixed",
        },
    },
    "no-blind-staging": {
        "what": "a blanket git add, which commits whatever else happened to be in the tree",
        "matchers": ["Bash"],
        "hook_re": r"\bgit[ \t]+([^ \t]+[ \t]+)*add[ \t]+([-]A\b|[-][-]all\b|\.([ \t]|$))",
        "skip_shell_comments": True,
        # No gate: staging leaves no residue in the tree to grep for. The
        # evidence is the command, and the command is only ever in front of the
        # hook. Reported as a cap rather than invented as a check.
        "gate": None,
    },
    "no-emoji": {
        "what": "an emoji, which this repo asked agents to keep out of its files",
        "matchers": ["Bash", "Write", "Edit", "MultiEdit", "NotebookEdit"],
        "hook_re": r"[\U0001F000-\U0001FAFF\u2600-\u27BF\u2B00-\u2BFF\uFE0F\U0001F1E6-\U0001F1FF]",
        "skip_shell_comments": False,
        # No gate: the ranges are multibyte, and a POSIX ERE handed to grep
        # under an unknown locale cannot be relied on to mean codepoints. An
        # ERE that matches on one machine and not the next is not a gate.
        "gate": None,
    },
}

'

# --- shared python preamble --------------------------------------------------
COMMON_PY='
import hashlib, json, os, re, sys

def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()

def load_jsonl(path):
    out = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            out.append(json.loads(line))
    return out
'

case "$CMD" in

lexicon)
  python3 -c "$LEXICON_PY"'
print("promotion threshold: %d distinct conversations" % '"$THRESHOLD_CONVERSATIONS"')
print("rung bands by score (signals x conversations x pain):")
print("  score <  %d          prose" % '"$RUNG_SCORE_SKILL"')
print("  score <  %d          skill" % '"$RUNG_SCORE_HOOK"')
print("  score <  %d          hook      (clusters with a hook rule only)" % '"$RUNG_SCORE_GATE"')
print("  score >= %d          ci-gate   (clusters with a gate rule only)" % '"$RUNG_SCORE_GATE"')
print("  a cluster is capped at the highest rung RULES can actually fill, whatever")
print("  its score. An offered rung nothing can fill is a stub, and a stub asserts")
print("  nothing while reporting that the ladder was climbed.")
print("")
print("CUE lexicon - decides whether a message is a correction")
# The lexicon is only inspectable if it prints as the pattern it is, so the
# apostrophe escape the shell needed is undone for display.
def show(rx):
    return rx.replace(chr(92) + "x27", chr(39))
for name, rx in CUES:
    print("  %-16s %s" % (name, show(rx)))
print("")
print("TOPIC lexicon - decides which cluster it joins")
def ceiling(tag):
    rule = RULES.get(tag)
    if rule is None:
        return "skill", "no rule is written for it"
    if not rule.get("gate"):
        return "hook", "hook rule only; its property is not one POSIX ERE over file bytes"
    return "ci-gate", "hook rule and gate rule"

for tag, rx, summary in TOPICS:
    cap, why = ceiling(tag)
    print("  %-24s highest rung: %-8s %s" % (tag, cap, show(rx)))
    print("  %-24s summary: you %s" % ("", summary))
    print("  %-24s cap: %s" % ("", why))
print("")
print("RULE table - what each checkable cluster actually asserts")
for tag in sorted(RULES):
    rule = RULES[tag]
    print("  %s" % tag)
    print("    refuses      %s" % rule["what"])
    print("    hook on      %s" % ", ".join(rule["matchers"]))
    print("    hook regex   %s" % rule["hook_re"])
    gate = rule.get("gate")
    if gate:
        print("    gate paths   %s" % ", ".join(gate["paths"]))
        print("    gate ere     %s" % gate["ere"])
    else:
        print("    gate         none. Capped at hook, and that cap is the honest answer.")
'
  ;;

harvest)
  # detect-context.sh already probes this repo for git, gh and config. Re-deriving
  # any of that here would be a second copy that disagrees with the first the day
  # someone edits one of them.
  CTX="$WORK/context.json"
  if [ ! -f "$CTX" ] || [ "$REFRESH" -eq 1 ]; then
    if [ -x "$DETECT" ] || [ -f "$DETECT" ]; then
      ( cd "$ROOT" && bash "$DETECT" ) > "$CTX.tmp"
      mv "$CTX.tmp" "$CTX"
    else
      printf 'graduate: detect-context.sh not found at %s\n' "$DETECT" >&2
      printf 'graduate: the harvest will not know what this repo is bound to.\n' >&2
      printf '{"detect_context":"missing"}\n' > "$CTX"
    fi
  fi

  python3 -c "$COMMON_PY$LEXICON_PY"'
transcripts_root = sys.argv[1]
sources         = [s for s in sys.argv[2].split(",") if s]
work            = sys.argv[3]
ctx_path        = sys.argv[4]

try:
    ctx = json.load(open(ctx_path))
except Exception:
    ctx = {"detect_context": "unparseable"}

cue_res   = [(n, re.compile(rx, re.I)) for n, rx in CUES]
topic_res = [(t, re.compile(rx, re.I), s) for t, rx, s in TOPICS]

# A brief is not a correction. The cap is a length, stated, not a judgement:
# a 4000-character message that happens to contain "don\x27t" is a task
# description, and letting it in poisons every cluster it touches.
MAX_CORRECTION_CHARS = 1200

report = {"sources": {}, "files_seen": 0, "files_unparseable": 0,
          "conversations_seen": 0, "messages_seen": 0, "corrections": 0}
records = []

def user_texts(obj):
    m = obj.get("message") or {}
    c = m.get("content")
    if isinstance(c, str):
        return [c]
    out = []
    if isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get("type") == "text":
                out.append(b.get("text") or "")
    return out

if "transcripts" in sources:
    if not os.path.isdir(transcripts_root):
        report["sources"]["transcripts"] = {"state": "absent",
            "detail": "no such directory: %s" % transcripts_root}
    else:
        files = []
        for dirpath, dirnames, filenames in os.walk(transcripts_root):
            dirnames.sort()
            for fn in sorted(filenames):
                if fn.endswith(".jsonl"):
                    files.append(os.path.join(dirpath, fn))
        files.sort()
        if not files:
            report["sources"]["transcripts"] = {"state": "empty",
                "detail": "directory exists, contains no .jsonl transcripts"}
        else:
            convs = set()
            parsed_any = False
            for path in files:
                report["files_seen"] += 1
                try:
                    objs = load_jsonl(path)
                except Exception as e:
                    report["files_unparseable"] += 1
                    continue
                parsed_any = True
                seen_assistant = False
                for lineno, obj in enumerate(objs, 1):
                    if not isinstance(obj, dict):
                        continue
                    conv = obj.get("sessionId") or path
                    convs.add(conv)
                    if obj.get("type") == "assistant":
                        seen_assistant = True
                        continue
                    if obj.get("type") != "user":
                        continue
                    for text in user_texts(obj):
                        report["messages_seen"] += 1
                        # A correction is a reply to something the agent did.
                        # The first message of a session is the task.
                        if not seen_assistant:
                            continue
                        if not text or len(text) > MAX_CORRECTION_CHARS:
                            continue
                        if "<system-reminder>" in text or "<command-name>" in text:
                            continue
                        cues = sorted(n for n, rx in cue_res if rx.search(text))
                        if not cues:
                            continue
                        tags = sorted(t for t, rx, s in topic_res if rx.search(text))
                        report["corrections"] += 1
                        records.append({
                            "conversation": conv,
                            "source": "transcripts",
                            "ts": obj.get("timestamp") or "",
                            "cues": cues,
                            "tags": tags or ["UNDECIDED"],
                            "excerpt": " ".join(text.split())[:300],
                            "file": path,
                            "line": lineno,
                        })
            report["conversations_seen"] = len(convs)
            report["sources"]["transcripts"] = {
                "state": "read" if parsed_any else "unparseable",
                "detail": "%d file(s), %d unparseable" % (report["files_seen"], report["files_unparseable"]),
                "root": transcripts_root}

if "pr" in sources:
    # Never faked. gh state comes from detect-context.sh, not from a second probe.
    gh = (ctx.get("github_cli") or {}).get("state", "unknown")
    report["sources"]["pr"] = {"state": "unavailable",
        "detail": "detect-context.sh reports gh state=%s; PR review comments were NOT read" % gh}

records.sort(key=lambda r: (r["file"], r["line"]))
with open(os.path.join(work, "corrections.jsonl"), "w", encoding="utf-8") as fh:
    for r in records:
        fh.write(json.dumps(r, sort_keys=True) + "\n")
with open(os.path.join(work, "harvest.json"), "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2, sort_keys=True)

for name, s in sorted(report["sources"].items()):
    print("source %-12s %-12s %s" % (name, s["state"], s.get("detail", "")))

states = [s["state"] for s in report["sources"].values()]
# Four different nothings, and they lead to four different actions. Collapsing
# any of them into "0 corrections found" reads as "nothing to learn", which is a
# claim about the repo rather than a report about the scan.
if not states or all(st == "absent" for st in states):
    print("")
    print("NO SOURCE WAS AVAILABLE. Nothing was scanned, so nothing is known about")
    print("this repo\x27s corrections. Not a zero - a scan that did not happen.")
    sys.exit(3)
if all(st in ("absent", "empty") for st in states):
    print("")
    print("NO TRANSCRIPTS. The source directory exists and holds no transcript, so")
    print("there was nothing to read. Not a zero - an empty shelf.")
    sys.exit(3)
if all(st in ("absent", "empty", "unparseable") for st in states):
    print("")
    print("NOTHING PARSEABLE. %d file(s) seen, %d would not parse. No correction"
          % (report["files_seen"], report["files_unparseable"]))
    print("count is reported, because none was measured.")
    sys.exit(4)

print("")
print("scanned    %d message(s) across %d conversation(s) in %d file(s)"
      % (report["messages_seen"], report["conversations_seen"], report["files_seen"]))
print("harvested  %d correction(s)" % report["corrections"])
if report["corrections"] == 0:
    print("")
    print("A MEASURED ZERO. The sources were read and no message matched the cue")
    print("lexicon. That is a real answer about these transcripts, not a missing one.")
    sys.exit(5)
' "$TRANSCRIPTS" "$SOURCES" "$WORK" "$WORK/context.json"
  ;;

present)
  [ -f "$WORK/corrections.jsonl" ] || die_usage "no harvest in $WORK. Run: graduate.sh harvest --work $WORK"

  python3 -c "$COMMON_PY$LEXICON_PY"'
import difflib, datetime
work      = sys.argv[1]
root      = sys.argv[2]
threshold = int(sys.argv[3])
b_skill   = int(sys.argv[4])
b_hook    = int(sys.argv[5])
b_gate    = int(sys.argv[6])
tmpl_dir  = sys.argv[7]

recs = load_jsonl(os.path.join(work, "corrections.jsonl"))
meta = {t: s for t, rx, s in TOPICS}

# The rung a cluster is ALLOWED to reach, which is the highest rung RULES can
# fill for it. Everything above that is a stub, and a stub reports a climb that
# did not happen.
RUNG_ORDER = ["prose", "skill", "hook", "ci-gate"]

def ceiling(tag):
    rule = RULES.get(tag)
    if rule is None:
        return "skill", ("no mechanical rule is written for this cluster, so nothing "
                         "above skill could assert anything")
    if not rule.get("gate"):
        return "hook", ("hook rule only - this property is not expressible as one POSIX "
                        "ERE over file bytes, which is all a gate is allowed to be")
    return "ci-gate", None

clusters = {}
for r in recs:
    for tag in r["tags"]:
        cl = clusters.setdefault(tag, {"tag": tag, "recs": []})
        cl["recs"].append(r)

rows = []
for tag, cl in clusters.items():
    per_conv = {}
    cues = set()
    for r in cl["recs"]:
        per_conv[r["conversation"]] = per_conv.get(r["conversation"], 0) + 1
        cues.update(r["cues"])
    conversations = len(per_conv)
    occurrences = len(cl["recs"])
    # Pain is how many times one person had to say it inside a single
    # conversation. Repeating yourself is the friction; it is not evidence of
    # breadth, which is what conversations counts, so the two never merge.
    pain = min(3, max(per_conv.values()))
    signals = len(cues)
    score = signals * conversations * pain
    summary = meta.get(tag)
    if score < b_skill:      rung = "prose"
    elif score < b_hook:     rung = "skill"
    elif score < b_gate:     rung = "hook"
    else:                    rung = "ci-gate"
    cap_rung, cap_reason = ceiling(tag)
    if RUNG_ORDER.index(rung) > RUNG_ORDER.index(cap_rung):
        rung = cap_rung
        capped = True
    else:
        capped = False
        cap_reason = None
    rows.append({"tag": tag, "conversations": conversations, "occurrences": occurrences,
                 "pain": pain, "signals": signals, "score": score, "rung": rung,
                 "capped": capped, "cap_reason": cap_reason,
                 "checkable": tag in RULES, "summary": summary,
                 "cues": sorted(cues), "per_conv": per_conv})

rows.sort(key=lambda r: (-r["score"], r["tag"]))
promoted = [r for r in rows if r["conversations"] >= threshold and r["tag"] != "UNDECIDED"]
held     = [r for r in rows if r["conversations"] <  threshold and r["tag"] != "UNDECIDED"]
undecided = [r for r in rows if r["tag"] == "UNDECIDED"]

# --- draft the operations ----------------------------------------------------
def read_bytes(p):
    with open(p, "rb") as fh:
        return fh.read()

GUIDE_DIR = ".claude/productizer/graduated"

# --- filling a rung ----------------------------------------------------------
# The rung bodies are templates that ship with this script, under
# templates/graduate/. They are NOT read out of the repository being examined:
# a repo under examination never chooses what runs (P4), and it does not choose
# what gets written into itself either.
def read_template(name):
    path = os.path.join(tmpl_dir, name)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read()
    except OSError as exc:
        print("graduate: cannot read the rung template %s (%s)." % (path, exc), file=sys.stderr)
        print("graduate: refusing to draft a rung it cannot fill. Emitting a body that",
              file=sys.stderr)
        print("asserts nothing is the defect this rung was rewritten to remove.", file=sys.stderr)
        sys.exit(2)

def fill(text, subs, where):
    for k, v in subs.items():
        text = text.replace("@@%s@@" % k, v)
    left = sorted(set(re.findall(r"@@[A-Z_]+@@", text)))
    if left:
        print("graduate: the %s template left %s unfilled. Refusing: a rung with a hole"
              % (where, ", ".join(left)), file=sys.stderr)
        print("in it is a stub wearing a template.", file=sys.stderr)
        sys.exit(2)
    return text

def commented(prefix, text):
    out = []
    for line in text.split("\n"):
        out.append((prefix + " " + line).rstrip() if line else prefix)
    return "\n".join(out)

HOOK_ASSERTS = """WHAT THIS RUNG ASSERTS THAT THE RUNG BELOW IT DOES NOT

The rung below is `skill`: a markdown file under .claude/productizer/graduated/.
It asserts nothing at all. It is advice, it competes for a context window, and
it is followed or it is not - which is the whole reason the ladder exists.

This rung asserts a property of ONE PROPOSED ACTION, read out of the tool
payload BEFORE the action runs, and refuses the action when the property fails.
It therefore also reaches text that never becomes a file: a Bash command line is
judged here and by no other rung."""

GATE_ASSERTS = """WHAT THIS RUNG ASSERTS THAT THE HOOK RUNG BELOW IT DOES NOT

The hook is handed one payload and answers about that payload. It has no
denominator and no memory. A violation already on disk - written before the hook
was installed, edited by a human outside the agent, arriving in a merge, or made
by a tool the hook is not registered on - is invisible to it.

This rung asserts the property over EVERY TRIGGERING FILE IN THE TREE, and it
declares a coverage denominator, so a run that failed to open a file it should
have read is a refusal rather than a pass. `covered 0/1 files` is a verdict
about the check itself, and it is the one thing a hook can never say."""

GUIDE_DIR = ".claude/productizer/graduated"

def ops_for(row):
    tag = row["tag"]
    sentence = "In %d conversation%s, you %s." % (
        row["conversations"], "" if row["conversations"] == 1 else "s", row["summary"])
    evidence = ("Evidence: %d conversations, %d occurrences, %d cue type(s), pain %d, score %d."
                % (row["conversations"], row["occurrences"], row["signals"], row["pain"], row["score"]))
    ops = []
    if row["rung"] == "prose":
        block = ("\n## Graduated corrections\n\n- **%s** - %s (evidence: %d conversations, rung prose)\n"
                 % (tag, row["summary"], row["conversations"]))
        # The marker makes the append idempotent. Applying twice used to write
        # the same bullet twice, and a file that repeats itself is one nobody
        # rereads.
        ops.append(("update-or-create", "CLAUDE.md", block, "append", None,
                    "- **%s** -" % tag))
    elif row["rung"] == "skill":
        body = ("# %s\n\n%s\n\n%s\nRung: skill. Promoted by scripts/graduate.sh.\n\n"
                "THIS FILE ASSERTS NOTHING, AND THAT IS THE RUNG, NOT AN OMISSION. It is\n"
                "read when it happens to be in context and ignored when it is not. The rung\n"
                "above it, `hook`, refuses the action instead of describing it; the rung\n"
                "above that, `ci-gate`, refuses the whole tree. Both need a rule written in\n"
                "the RULES table of scripts/graduate.sh, and this cluster\n%s.\n"
                % (tag, sentence, evidence,
                   "has one but has not earned the score for it"
                   if tag in RULES else
                   "has none, which is why the ladder stops here for it"))
        ops.append(("update-or-create", "%s/%s.md" % (GUIDE_DIR, tag), body, "whole", None, None))
    else:
        rule = RULES[tag]
        hook_body = fill(read_template("hook.sh"), {
            "TAG": tag,
            "CONVERSATIONS": str(row["conversations"]),
            "SENTENCE": sentence,
            "WHAT": rule["what"],
            "ASSERTS": commented("#", HOOK_ASSERTS),
            "MATCHER_RE": "|".join(rule["matchers"]),
            "MATCHERS": json.dumps(rule["matchers"]),
            "PATTERN": rule["hook_re"],
            "SKIP_COMMENTS": "True" if rule["skip_shell_comments"] else "False",
        }, "hook")
        ops.append(("update-or-create", ".claude/hooks/graduated-%s.sh" % tag,
                    hook_body, "whole", None, None))
        if row["rung"] == "ci-gate":
            gate = rule["gate"]
            block = fill(read_template("ci-gate.yaml"), {
                "TAG": tag,
                "CONVERSATIONS": str(row["conversations"]),
                "SENTENCE": sentence,
                "ASSERTS": commented("  #", GATE_ASSERTS),
                "WHY": gate["why"],
                "PATHS": "\n".join("        - \"%s\"" % g for g in gate["paths"]),
                "ERE": gate["ere"],
            }, "ci-gate")
            # The hook is emitted alongside the gate, not replaced by it. They
            # assert different properties, so a repo at ci-gate that dropped the
            # hook would stop seeing every violation that never reaches a file.
            ops.append(("update-or-create", ".claude/productizer/checks.yaml",
                        block, "append", read_template("ci-gate-header.yaml") + block,
                        "  - id: graduated-%s\n" % tag))
    return sentence, ops

def resolve(op, path, payload, mode, create_payload=None, marker=None):
    ap = os.path.join(root, path)
    exists = os.path.exists(ap)
    if op == "update-or-create":
        op = "update" if exists else "create"
    before = read_bytes(ap) if exists else b""
    noop = False
    if op == "create":
        # A fragment appended to a file that does not exist is not a file. A
        # checks.yaml consisting of one check entry and no `version:` refuses to
        # parse, and a gate that refuses to load is a gate that never ran.
        after = (payload if create_payload is None else create_payload).encode("utf-8")
    elif op == "remove":
        after = b""
    elif mode == "append":
        if marker is not None and marker.encode("utf-8") in before:
            after = before
            noop = True
        else:
            after = before + payload.encode("utf-8")
    else:
        after = payload.encode("utf-8")
    return {"op": op, "path": path, "exists": exists, "noop": noop,
            # A hook that is not executable is a hook Claude Code cannot run,
            # and an unrunnable hook allows everything.
            "exec": path.startswith(".claude/hooks/"),
            "before_sha256": sha256_bytes(before) if exists else None,
            "after_sha256": sha256_bytes(after) if op != "remove" else None,
            "after_b64": None if op == "remove" else __import__("base64").b64encode(after).decode(),
            "before_preview": before.decode("utf-8", "replace"),
            "after_preview": "" if op == "remove" else after.decode("utf-8", "replace")}

suggestions = {}
for row in promoted:
    sentence, raw = ops_for(row)
    resolved = []
    bad = None
    for op, path, payload, mode, create_payload, marker in raw:
        r = resolve(op, path, payload, mode, create_payload, marker)
        if r["op"] == "create" and r["exists"]:
            bad = "create target already exists: %s" % path
        resolved.append(r)
    suggestions[row["tag"]] = {"tag": row["tag"], "rung": row["rung"], "sentence": sentence,
                               "evidence": {k: row[k] for k in
                                            ("conversations", "occurrences", "pain", "signals", "score",
                                             "checkable", "capped", "cues")},
                               "ops": resolved, "blocked": bad}

# --- prune -------------------------------------------------------------------
# A guidance file whose cluster no longer appears in the window is a candidate
# for removal. It is a candidate and nothing more: absence in this window is not
# proof the lesson stopped mattering, so it is presented, never auto-removed.
prune_ops = []
gd = os.path.join(root, GUIDE_DIR)
live = {r["tag"] for r in rows}
if os.path.isdir(gd):
    for fn in sorted(os.listdir(gd)):
        if not fn.endswith(".md"):
            continue
        tag = fn[:-3]
        if tag not in live:
            prune_ops.append(resolve("remove", "%s/%s" % (GUIDE_DIR, fn), "", "whole", None, None))
if prune_ops:
    suggestions["prune"] = {"tag": "prune", "rung": "n/a",
        "sentence": "%d graduated guidance file(s) had no correction in this window." % len(prune_ops),
        "evidence": {"conversations": 0, "occurrences": 0, "pain": 0, "signals": 0,
                     "score": 0, "checkable": False, "capped": False, "cues": []},
        "ops": prune_ops, "blocked": None}

with open(os.path.join(work, "suggestions.json"), "w", encoding="utf-8") as fh:
    json.dump({"drafted_utc": datetime.datetime.now(datetime.timezone.utc)
                                 .strftime("%Y-%m-%dT%H:%M:%SZ"),
               "root": root, "threshold_conversations": threshold,
               "suggestions": suggestions}, fh, indent=2, sort_keys=True)

# --- present -----------------------------------------------------------------
MARK = {"create": "+", "update": "~", "remove": "−"}

def card(row, sug):
    print("")
    print("=" * 74)
    print("  %s   [%d conversations]" % (row["tag"], row["conversations"]))
    print("=" * 74)
    print("  %s" % sug["sentence"])
    print("")
    print("  evidence  %d conversations / %d occurrences / %d cue type(s) / pain %d"
          % (row["conversations"], row["occurrences"], row["signals"], row["pain"]))
    print("            score = signals x conversations x pain = %d x %d x %d = %d"
          % (row["signals"], row["conversations"], row["pain"], row["score"]))
    print("            cues: %s" % ", ".join(row["cues"]))
    print("  rung      %s" % row["rung"])
    if row["capped"]:
        print("            CAPPED at %s: %s." % (row["rung"], row["cap_reason"]))
        print("            The score justified a higher rung; nothing could fill it, and an")
        print("            unfillable rung is a stub that reports a climb that did not happen.")
    print("  ladder    prose -> skill -> hook -> ci-gate   (recommended, not taken)")
    print("            each rung asserts a different property: see graduate.sh --help")
    print("")
    for r in sug["ops"]:
        print("  %s %s%s%s" % (MARK[r["op"]], r["path"],
                               "   (executable)" if r.get("exec") else "",
                               "   (already present - this append is a no-op)" if r.get("noop") else ""))
    for r in sug["ops"]:
        print("")
        d = list(difflib.unified_diff(
            r["before_preview"].splitlines(True), r["after_preview"].splitlines(True),
            fromfile="a/" + r["path"], tofile="b/" + r["path"], n=2))
        for line in d[:60]:
            print("    " + line.rstrip("\n"))
        if len(d) > 60:
            print("    ... %d more diff line(s)" % (len(d) - 60))
    if sug["blocked"]:
        print("")
        print("  BLOCKED: %s" % sug["blocked"])
    print("")
    print("  excerpts  scripts/graduate.sh excerpts --id %s" % row["tag"])
    print("  accept    scripts/graduate.sh apply --id %s --decide accept" % row["tag"])

print("Corrections harvested: %d. Threshold: %d distinct conversations."
      % (len(recs), threshold))
print("")
print("  %-24s %5s %5s %5s %5s  %s" % ("cluster", "conv", "occ", "pain", "score", "rung"))
for r in rows:
    state = "" if r["conversations"] >= threshold else "  (below threshold)"
    print("  %-24s %5d %5d %5d %5d  %s%s"
          % (r["tag"], r["conversations"], r["occurrences"], r["pain"], r["score"],
             r["rung"] if r["conversations"] >= threshold else "-", state))

for row in promoted:
    card(row, suggestions[row["tag"]])

if "prune" in suggestions:
    s = suggestions["prune"]
    print("")
    print("=" * 74)
    print("  prune   [no evidence in this window]")
    print("=" * 74)
    print("  %s" % s["sentence"])
    print("  Absence in one window is not proof the lesson stopped mattering.")
    for r in s["ops"]:
        print("  %s %s" % (MARK[r["op"]], r["path"]))
    print("  accept    scripts/graduate.sh apply --id prune --decide accept")

if undecided:
    u = undecided[0]
    print("")
    print("=" * 74)
    print("  UNDECIDED   [%d conversations, %d message(s)]" % (u["conversations"], u["occurrences"]))
    print("=" * 74)
    print("  These read as corrections and matched no topic in the lexicon. They are")
    print("  not guessed at and not dropped. Either they belong to a cluster the")
    print("  lexicon does not have yet, or they are not corrections and the cue")
    print("  lexicon is too wide. Only you can say which.")
    print("  excerpts  scripts/graduate.sh excerpts --id UNDECIDED")

print("")
if not promoted:
    print("NOTHING REACHED THE THRESHOLD. %d cluster(s) exist; none appeared in %d or"
          % (len(held), threshold))
    print("more distinct conversations. Repeats inside one conversation do not count.")
    sys.exit(6)
print("%d cluster(s) reached the threshold. Nothing has been written outside %s."
      % (len(promoted), work))
print("Apply requires you to name one and decide: --id TAG --decide accept")
' "$WORK" "$ROOT" "$THRESHOLD_CONVERSATIONS" "$RUNG_SCORE_SKILL" "$RUNG_SCORE_HOOK" "$RUNG_SCORE_GATE" "$TMPL_DIR"
  ;;

excerpts)
  [ -n "$ID" ] || die_usage "excerpts needs --id TAG"
  [ -f "$WORK/corrections.jsonl" ] || die_usage "no harvest in $WORK"
  python3 -c "$COMMON_PY"'
work = sys.argv[1]; tag = sys.argv[2]
recs = [r for r in load_jsonl(os.path.join(work, "corrections.jsonl")) if tag in r["tags"]]
if not recs:
    print("No harvested correction carries the tag %s." % tag)
    print("That is a measured absence in this harvest, not a claim the tag is wrong.")
    sys.exit(0)
by_conv = {}
for r in recs:
    by_conv.setdefault(r["conversation"], []).append(r)
print("%s - %d message(s) across %d conversation(s)" % (tag, len(recs), len(by_conv)))
for conv in sorted(by_conv):
    print("")
    print("  conversation %s   (%d message(s))" % (conv, len(by_conv[conv])))
    for r in sorted(by_conv[conv], key=lambda x: (x["file"], x["line"])):
        print("    %s:%d  [%s]" % (r["file"], r["line"], ",".join(r["cues"])))
        print("      %s" % r["excerpt"])
' "$WORK" "$ID"
  ;;

apply)
  [ -n "$ID" ] || die_usage "apply needs --id TAG naming one cluster"
  [ "$DECIDE" = "accept" ] || die_usage \
    "apply needs --decide accept. This script never applies a change on its own; there is no auto-apply flag."
  [ -f "$WORK/suggestions.json" ] || die_usage "no draft in $WORK. Run: graduate.sh present --work $WORK"
  mkdir -p "$WORK/undo"

  python3 -c "$COMMON_PY"'
import base64, datetime, shutil
work = sys.argv[1]; root = sys.argv[2]; tag = sys.argv[3]

draft = json.load(open(os.path.join(work, "suggestions.json")))
sug = draft["suggestions"].get(tag)
if sug is None:
    print("graduate: no drafted suggestion with id %s. Known: %s"
          % (tag, ", ".join(sorted(draft["suggestions"]))), file=sys.stderr)
    sys.exit(2)

# --- preconditions, ALL of them, before ANY write ----------------------------
# The suggestion was drafted against a snapshot of these files. If any of them
# moved since, the diff a human approved is not the diff that would land. So the
# whole suggestion is refused and flagged rather than silently clobbering work.
failures = []
for r in sug["ops"]:
    ap = os.path.join(root, r["path"])
    exists = os.path.exists(ap)
    if r["op"] == "create":
        if exists:
            failures.append("%s: create target already exists" % r["path"])
    else:
        if not exists:
            failures.append("%s: target is gone since the suggestion was drafted" % r["path"])
            continue
        now = sha256_of(ap)
        if now != r["before_sha256"]:
            failures.append("%s: modified since the suggestion was drafted "
                            "(drafted %s..., now %s...)" % (r["path"], r["before_sha256"][:12], now[:12]))

if failures:
    draft["suggestions"][tag]["flagged"] = {
        "at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "reasons": failures}
    with open(os.path.join(work, "suggestions.json"), "w", encoding="utf-8") as fh:
        json.dump(draft, fh, indent=2, sort_keys=True)
    print("PRECONDITION FAILED - NOTHING WAS WRITTEN.", file=sys.stderr)
    for f in failures:
        print("  %s" % f, file=sys.stderr)
    print("", file=sys.stderr)
    print("The suggestion is flagged in %s. Re-run `present` to redraft it against"
          % os.path.join(work, "suggestions.json"), file=sys.stderr)
    print("the files as they are now, then review the new diff.", file=sys.stderr)
    sys.exit(7)

# --- write -------------------------------------------------------------------
undo_dir = os.path.join(work, "undo", tag)
if os.path.isdir(undo_dir):
    shutil.rmtree(undo_dir)
os.makedirs(undo_dir)

journal = {"tag": tag, "root": root,
           "at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "ops": []}
for i, r in enumerate(sug["ops"]):
    ap = os.path.join(root, r["path"])
    if os.path.exists(ap):
        shutil.copyfile(ap, os.path.join(undo_dir, "%d.bak" % i))
        prior = "file"
    else:
        prior = "absent"
    if r["op"] == "remove":
        os.remove(ap)
        after_sha = None
    else:
        data = base64.b64decode(r["after_b64"])
        os.makedirs(os.path.dirname(ap) or ".", exist_ok=True)
        tmp = ap + ".graduate.tmp"
        with open(tmp, "wb") as fh:
            fh.write(data)
        if r.get("exec"):
            # Claude Code runs a `type: command` hook through a shell, so a hook
            # written 0644 fails to execute - and a hook that cannot run allows
            # every action it was installed to refuse.
            os.chmod(tmp, 0o755)
        os.replace(tmp, ap)
        after_sha = sha256_bytes(data)
    journal["ops"].append({"i": i, "op": r["op"], "path": r["path"],
                           "prior": prior, "after_sha256": after_sha})
    print("%s %s" % ({"create": "+", "update": "~", "remove": "-"}[r["op"]], r["path"]))

with open(os.path.join(work, "journal-%s.json" % tag), "w", encoding="utf-8") as fh:
    json.dump(journal, fh, indent=2, sort_keys=True)
print("")
print("applied %d operation(s). Undo: scripts/graduate.sh undo --id %s" % (len(sug["ops"]), tag))
' "$WORK" "$ROOT" "$ID"
  ;;

undo)
  [ -n "$ID" ] || die_usage "undo needs --id TAG"
  [ -f "$WORK/journal-$ID.json" ] || die_usage "nothing applied for $ID from $WORK"

  python3 -c "$COMMON_PY"'
import shutil
work = sys.argv[1]; root = sys.argv[2]; tag = sys.argv[3]
journal = json.load(open(os.path.join(work, "journal-%s.json" % tag)))
undo_dir = os.path.join(work, "undo", tag)

# Undo restores what apply wrote over. If the file no longer matches what apply
# wrote, someone edited it afterwards, and restoring would destroy that edit -
# which is the same clobber the apply preconditions exist to prevent.
failures = []
for o in journal["ops"]:
    ap = os.path.join(root, o["path"])
    if o["op"] == "remove":
        if os.path.exists(ap):
            failures.append("%s: reappeared since it was removed" % o["path"])
        continue
    if not os.path.exists(ap):
        failures.append("%s: gone since it was written" % o["path"])
        continue
    now = sha256_of(ap)
    if now != o["after_sha256"]:
        failures.append("%s: changed since it was written (wrote %s..., now %s...)"
                        % (o["path"], o["after_sha256"][:12], now[:12]))

if failures:
    print("UNDO REFUSED - NOTHING WAS RESTORED.", file=sys.stderr)
    for f in failures:
        print("  %s" % f, file=sys.stderr)
    print("", file=sys.stderr)
    print("Undo only reverses its own write. A file edited after apply holds work this",
          file=sys.stderr)
    print("journal knows nothing about, and restoring the backup would destroy it.",
          file=sys.stderr)
    sys.exit(8)

for o in journal["ops"]:
    ap = os.path.join(root, o["path"])
    bak = os.path.join(undo_dir, "%d.bak" % o["i"])
    if o["prior"] == "file":
        shutil.copyfile(bak, ap)
        print("restored %s" % o["path"])
    else:
        if os.path.exists(ap):
            os.remove(ap)
        print("removed  %s  (it did not exist before apply)" % o["path"])
os.remove(os.path.join(work, "journal-%s.json" % tag))
print("")
print("undone %d operation(s)." % len(journal["ops"]))
' "$WORK" "$ROOT" "$ID"
  ;;
esac
