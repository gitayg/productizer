#!/usr/bin/env bash
# check-spec-home.sh [--version] [--config PATH] [--repo SLUG=PATH]... [--remote]
#                    [--selftest]
#
# Asserts R1: THE LIFECYCLE SHALL HOLD EXACTLY ONE LIVING SPEC PER PRODUCT.
#
# Until this existed, nothing did. `product.spec_home` was declared in
# config.json and never read back, so a product could grow a second
# `.claude/productizer/spec.md` in a second repo and nothing would say so -
# two allocators both handing out R42, two specs both believed, and the
# divergence discovered later by whoever trusted the wrong one.
#
# WHAT IT MEASURES. Every repo in `product.repos`, asked one question: does it
# hold the spec file named by `spec.path`? Then:
#
#   exactly one, and it is the declared home        pass
#   exactly one, but not the declared home          fail - the home is a lie
#   two or more                                     fail - R1 is broken now
#   none, and every repo was reachable              fail - no living spec
#   any repo could not be reached                   REFUSED, see below
#
# UNREACHABLE IS NOT ABSENT, AND THIS IS THE WHOLE POINT.
#
# A repo this check cannot open is not a repo with no spec in it. Counting it
# as "no spec there" is how a two-spec product reports as a one-spec product:
# the second spec is in the repo nobody could reach. So an unreachable repo is
# reported by name, with the reason it could not be reached, and the run exits
# 2 - refused, distinct from both pass and fail, and never folded into the
# "specs found" count in either direction.
#
# The one ordering rule: two specs already found is a definite answer, so it
# fails (1) even when a third repo was unreachable. Unreachability only
# refuses when it could still change the verdict.
#
# HOW A REPO IS REACHED, in order:
#
#   1. --repo SLUG=PATH, given on the command line. Explicit wins.
#   2. `github.repo` in the config matches the slug - this is the repo the
#      check is running in, so the working directory is used.
#   3. The working directory's own basename matches the slug's.
#   4. A sibling checkout: ../<basename> holding a .git or a .claude.
#   5. --remote, and `gh` on PATH: the GitHub contents API. OFF BY DEFAULT,
#      because a check that reaches the network is not deterministic and a
#      rate limit would read as an outage rather than a verdict.
#
# Nothing matched means UNREACHABLE. It never means absent.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  exactly one living spec, in the declared home
#   1  R1 is violated - too many, none, or not where the config says
#   2  COULD NOT MEASURE - a repo out of reach, or a config that cannot be
#      read or does not declare what this check needs
#
# Under --selftest (--self-test is accepted too) the same three mean: every
# case produced the exit code it declares and said what it was supposed to say
# (0), at least one did not (1), and the corpus could not be driven at all (2).
set -euo pipefail

VERSION="check-spec-home 1.0"
CONFIG=".claude/productizer/config.json"
REMOTE=""
MODE="measure"
MAP_SLUG=()
MAP_PATH=()

die_unmeasured() { printf 'check-spec-home: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --config) [ "$#" -ge 2 ] || die_unmeasured "--config needs a path"; CONFIG="$2"; shift 2 ;;
    --remote) REMOTE=1; shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --repo)
      [ "$#" -ge 2 ] || die_unmeasured "--repo needs SLUG=PATH"
      case "$2" in
        *=*) MAP_SLUG+=("${2%%=*}"); MAP_PATH+=("${2#*=}") ;;
        *) die_unmeasured "--repo $2 is not SLUG=PATH" ;;
      esac
      shift 2
      ;;
    *) die_unmeasured "unknown argument: $1" ;;
  esac
done

# ---------------------------------------------------------------------------
# --selftest. R39: one case per exit code this tool can return, each built in
# a sandbox so nothing here reads or writes a real repository.
#
# EVERY CASE ASSERTS ITS OWN SENTENCE, NOT ONLY ITS EXIT CODE. Four different
# things exit 1 here - two specs, no spec, a spec outside the declared home,
# and a home that is not one of the product's repos - and five different
# things exit 2. A corpus reading exit codes alone cannot tell them apart, so
# a change that turned "no spec anywhere" into "the home is a lie" would stay
# green through it.
#
# THE ORDERING RULE IS DRIVEN TOO. Two specs already found is a definite
# answer and fails (1) even when a third repo was unreachable; unreachability
# only refuses when it could still change the verdict. That precedence is a
# sentence in the header above, and `two-beats-unreachable` is the case that
# makes it a measurement.
#
# Every repo is reached by an explicit --repo mapping, never by the working
# directory or a sibling checkout, so a case is unreachable because the corpus
# left it unmapped and not because of where this happened to be invoked from.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  [ -f "$SELF" ] ||
    die_unmeasured "cannot re-invoke this script for the self-test, so no case was driven"

  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-spec-home-selftest.XXXXXX")" ||
    die_unmeasured "could not create a sandbox, so no case was driven"
  trap 'rm -rf "$SB"' EXIT HUP INT TERM

  SPEC_IN_REPO=".claude/productizer/spec.md"

  mk_case() {
    # $1 case name, $2.. the repo basenames that HOLD a spec
    local d="$SB/$1"
    shift
    mkdir -p "$d/repos/home-repo/.claude/productizer" \
             "$d/repos/other-repo/.claude/productizer"
    local holder
    for holder in "$@"; do
      printf '# Living spec — sandbox\n\n## Requirements\n\n- **R1** — The lifecycle shall hold exactly one living spec per product.\n' \
        > "$d/repos/$holder/$SPEC_IN_REPO"
    done
    cat > "$d/config.json" <<'CFG'
{
  "product": {
    "repos": ["acme/home-repo", "acme/other-repo"],
    "spec_home": "acme/home-repo"
  },
  "spec": {
    "path": ".claude/productizer/spec.md"
  }
}
CFG
  }

  FAILED=0
  DRIVEN=0

  drive() {
    # $1 case name, $2 expected exit, $3 expected sentence, $4.. argv
    local case_name="$1" want="$2" marker="$3"
    shift 3
    local rc=0
    ( cd "$SB/$case_name" && bash "$SELF" "$@" ) \
      > "$SB/$case_name.out" 2> "$SB/$case_name.err" || rc=$?
    DRIVEN=$((DRIVEN + 1))
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
      printf '  held: case %-22s exit %d, and said so - %s\n' "$case_name" "$rc" "$marker"
      return 0
    fi
    printf '  FINDING: case %-22s %s - expected: %s\n' "$case_name" "$why" "$marker"
    FAILED=$((FAILED + 1))
    return 0
  }

  BOTH_MAPPED=(--repo acme/home-repo=repos/home-repo --repo acme/other-repo=repos/other-repo)

  mk_case clean home-repo
  mk_case two-specs home-repo other-repo
  mk_case no-spec
  mk_case wrong-home other-repo
  mk_case home-not-listed home-repo
  mk_case unreachable home-repo
  mk_case two-beats-unreachable home-repo other-repo
  mk_case bad-json home-repo
  mk_case no-repos home-repo
  mk_case no-home home-repo
  mk_case absent-config home-repo
  mk_case bad-mapping home-repo

  # `spec_home` names a repo the product does not list. The filesystem is
  # fine; the declaration is not, and that is its own finding.
  cat > "$SB/home-not-listed/config.json" <<'CFG'
{
  "product": {
    "repos": ["acme/home-repo", "acme/other-repo"],
    "spec_home": "acme/somewhere-else"
  },
  "spec": { "path": ".claude/productizer/spec.md" }
}
CFG
  printf 'this file is not JSON at all: { "product": \n' > "$SB/bad-json/config.json"
  cat > "$SB/no-repos/config.json" <<'CFG'
{ "product": { "repos": [], "spec_home": "acme/home-repo" },
  "spec": { "path": ".claude/productizer/spec.md" } }
CFG
  cat > "$SB/no-home/config.json" <<'CFG'
{ "product": { "repos": ["acme/home-repo"] },
  "spec": { "path": ".claude/productizer/spec.md" } }
CFG
  rm -f "$SB/absent-config/config.json"

  # THE CLEAN CASE GUARDS THE OTHERS' PREMISE. If one spec in the declared
  # home does not exit 0 and say so, every red case below would be red for
  # that reason instead of its own and nothing would have been measured.
  CLEAN_RC=0
  ( cd "$SB/clean" && bash "$SELF" --config config.json "${BOTH_MAPPED[@]}" ) \
    > "$SB/clean.out" 2> "$SB/clean.err" || CLEAN_RC=$?
  if [ "$CLEAN_RC" -ne 0 ] || ! grep -q 'PASS: exactly one living spec' "$SB/clean.out"; then
    printf '  the clean case exited %d and did not report one living spec in the declared home.\n' "$CLEAN_RC"
    die_unmeasured "the corpus premise did not hold; unmeasured, not a pass"
  fi
  printf '  held: case %-22s exit 0, and said so - %s\n' "clean" "PASS: exactly one living spec"

  drive two-specs        1 'R1 broken'                          --config config.json "${BOTH_MAPPED[@]}"
  drive no-spec          1 'this is a measured zero'            --config config.json "${BOTH_MAPPED[@]}"
  drive wrong-home       1 'the config declares the home as'    --config config.json "${BOTH_MAPPED[@]}"
  drive home-not-listed  1 'is not one of the repos in product.repos' --config config.json "${BOTH_MAPPED[@]}"

  # Two specs is a definite answer, so it fails even with a repo out of reach.
  drive two-beats-unreachable 1 'R1 broken'                     --config config.json \
        --repo acme/home-repo=repos/home-repo --repo acme/other-repo=repos/other-repo \
        --repo acme/third-repo=repos/nowhere

  drive unreachable      2 'could not be reached'               --config config.json \
        --repo acme/home-repo=repos/home-repo
  drive absent-config    2 'cannot read config.json'            --config config.json
  drive bad-json         2 'could not be parsed'                --config config.json
  drive no-repos         2 'declares no non-empty'              --config config.json
  drive no-home          2 'names no home repo'                 --config config.json
  drive bad-mapping      2 'is not SLUG=PATH'                   --config config.json --repo no-equals-here

  printf '  cases driven: %d, exit codes reached: 0, 1, 2. Cases that did not hold: %d\n' \
    "$((DRIVEN + 1))" "$FAILED"
  if [ "$FAILED" -ne 0 ]; then
    printf 'FAIL: %d selftest case(s) did not produce the exit code and the sentence they declare.\n' "$FAILED" >&2
    exit 1
  fi
  printf '  R39 for this tool: the self-test exists, reaches 0, 1 and 2, and every case asserts which verdict it produced as well as which code.\n'
  printf '  NOT ASSERTED: --remote is never driven. It reaches the GitHub contents API, and a corpus that asks the network renders one verdict on a train and another in the office.\n'
  exit 0
fi

[ -f "$CONFIG" ] && [ -r "$CONFIG" ] ||
  die_unmeasured "cannot read $CONFIG. A config nobody could open says nothing about how many specs exist; it is not a product with zero repos."
command -v python3 >/dev/null ||
  die_unmeasured "python3 is not on PATH, so the config cannot be parsed. Refusing rather than guessing what was declared."

# The config is read, never sourced. Output is one TAB-separated record per
# line so the shell below never has to parse JSON.
DECL="$(python3 - "$CONFIG" <<'PY'
import json, sys

path = sys.argv[1]
try:
    with open(path) as fh:
        cfg = json.load(fh)
except (OSError, ValueError) as exc:
    sys.stderr.write("check-spec-home: %s could not be parsed: %s\n" % (path, exc))
    sys.exit(2)
if not isinstance(cfg, dict):
    sys.stderr.write("check-spec-home: %s is not a JSON object\n" % path)
    sys.exit(2)

out = []
product = cfg.get("product")
if not isinstance(product, dict):
    sys.stderr.write("check-spec-home: %s declares no `product` object. Unmeasured.\n" % path)
    sys.exit(2)

repos = product.get("repos")
if not isinstance(repos, list) or not repos or not all(isinstance(r, str) and r.strip() for r in repos):
    sys.stderr.write("check-spec-home: %s declares no non-empty `product.repos` list. A product with no "
                     "repos named is a product nobody can count the specs of - unmeasured, not zero.\n" % path)
    sys.exit(2)

spec = cfg.get("spec") if isinstance(cfg.get("spec"), dict) else {}
spec_path = spec.get("path")
if not isinstance(spec_path, str) or not spec_path.strip():
    spec_path = ".claude/productizer/spec.md"
    out.append(("note", "`spec.path` is not declared; falling back to .claude/productizer/spec.md"))

# `spec.home` is a dotted pointer at the key that names the home repo. Follow
# it when it resolves; say so out loud when it dangles, because a pointer at a
# key that does not exist is exactly how `spec_home` came to be declared and
# never read.
home = None
home_source = None
pointer = spec.get("home")
if isinstance(pointer, str) and pointer.strip():
    node = cfg
    for part in pointer.split("."):
        node = node.get(part) if isinstance(node, dict) else None
    if isinstance(node, str) and node.strip():
        home, home_source = node.strip(), "spec.home -> %s" % pointer
    else:
        out.append(("note", "`spec.home` points at `%s`, which the config does not define. "
                            "Falling back to product.spec_home / product.spec_repo." % pointer))
if home is None:
    for key in ("spec_home", "spec_repo"):
        value = product.get(key)
        if isinstance(value, str) and value.strip():
            home, home_source = value.strip(), "product.%s" % key
            break
if home is None:
    sys.stderr.write("check-spec-home: %s names no home repo (`spec.home`, `product.spec_home` or "
                     "`product.spec_repo`). Unmeasured.\n" % path)
    sys.exit(2)

gh = cfg.get("github") if isinstance(cfg.get("github"), dict) else {}
here = gh.get("repo") if isinstance(gh.get("repo"), str) else ""

out.append(("specpath", spec_path.strip()))
out.append(("home", home))
out.append(("homesource", home_source))
out.append(("here", here.strip()))
for r in repos:
    out.append(("repo", r.strip()))
sys.stdout.write("".join("%s\t%s\n" % kv for kv in out))
PY
)" || exit 2

SPECPATH=""; HOME_SLUG=""; HOME_SRC=""; HERE_SLUG=""
REPOS=()
NOTES=()
while IFS=$'\t' read -r key value; do
  case "$key" in
    specpath)   SPECPATH="$value" ;;
    home)       HOME_SLUG="$value" ;;
    homesource) HOME_SRC="$value" ;;
    here)       HERE_SLUG="$value" ;;
    repo)       REPOS+=("$value") ;;
    note)       NOTES+=("$value") ;;
  esac
done <<< "$DECL"

CWD="$(pwd)"
PARENT="$(dirname "$CWD")"

# Paths printed here reach run-checks' `output_tail`, which is committed inside
# checks-result.json. An absolute path therefore writes whoever ran the check
# into a public file - the same leak that shipped in v4.2.0 and was removed in
# v4.3.0. Report relative to the work tree when the target is inside it. A path
# outside the tree stays absolute: shortening it would misname where the file is,
# and a wrong path is worse than a long one.
REL_ROOT="$(git rev-parse --show-toplevel 2>&1)" || REL_ROOT="$CWD"
case "$REL_ROOT" in /*) ;; *) REL_ROOT="$CWD" ;; esac

rel_to_root() {
  case "$1" in
    "$REL_ROOT"/*) printf '%s' "${1#"$REL_ROOT"/}" ;;
    "$REL_ROOT")   printf '.' ;;
    *)              printf '%s' "$1" ;;
  esac
}

# Echoes "<state>\t<where>". States: present, absent, unreachable.
locate() {
  slug="$1"
  base="${slug##*/}"
  dir=""
  how=""

  i=0
  while [ "$i" -lt "${#MAP_SLUG[@]}" ]; do
    if [ "${MAP_SLUG[$i]}" = "$slug" ]; then
      dir="${MAP_PATH[$i]}"
      how="--repo mapping"
      if [ ! -d "$dir" ]; then
        printf 'unreachable\t--repo %s=%s is not a directory\n' "$slug" "$dir"
        return 0
      fi
      break
    fi
    i=$((i + 1))
  done

  if [ -z "$dir" ] && [ -n "$HERE_SLUG" ] && [ "$HERE_SLUG" = "$slug" ]; then
    dir="$CWD"; how="github.repo names it, so it is the repo this check runs in"
  fi
  if [ -z "$dir" ] && [ "${CWD##*/}" = "$base" ]; then
    dir="$CWD"; how="the working directory basename matches"
  fi
  if [ -z "$dir" ] && { [ -d "$PARENT/$base/.git" ] || [ -d "$PARENT/$base/.claude" ]; }; then
    dir="$PARENT/$base"; how="sibling checkout"
  fi

  if [ -z "$dir" ]; then
    if [ -n "$REMOTE" ] && command -v gh >/dev/null; then
      err="$(mktemp "${TMPDIR:-/tmp}/check-spec-home.XXXXXX")"
      if gh api "repos/$slug/contents/$SPECPATH" --jq '.name' > /dev/null 2> "$err"; then
        rm -f "$err"
        printf 'present\tGitHub contents API\n'
        return 0
      fi
      # A 404 is an ANSWER - the file is not there. Anything else is the API
      # declining to answer, which is not the same sentence.
      if grep -q '404' "$err"; then
        rm -f "$err"
        printf 'absent\tGitHub contents API\n'
        return 0
      fi
      why="$(tr '\n' ' ' < "$err")"
      rm -f "$err"
      printf 'unreachable\tgh api failed: %s\n' "${why:-no message on stderr}"
      return 0
    fi
    if [ -n "$REMOTE" ]; then
      printf 'unreachable\tno local checkout found and gh is not on PATH\n'
    else
      printf 'unreachable\tno local checkout found; pass --repo %s=PATH, or --remote to ask GitHub\n' "$slug"
    fi
    return 0
  fi

  target="$dir/$SPECPATH"
  if [ -e "$target" ] && [ ! -r "$target" ]; then
    printf 'unreachable\t%s exists but cannot be read (%s)\n' "$(rel_to_root "$target")" "$how"
    return 0
  fi
  if [ -f "$target" ]; then
    printf 'present\t%s (%s)\n' "$(rel_to_root "$target")" "$how"
  else
    printf 'absent\t%s (%s)\n' "$(rel_to_root "$dir")" "$how"
  fi
}

printf 'config: %s\n' "$CONFIG"
printf 'spec path: %s\n' "$SPECPATH"
printf 'declared home: %s (from %s)\n' "$HOME_SLUG" "$HOME_SRC"
if [ "${#NOTES[@]}" -gt 0 ]; then
  for n in "${NOTES[@]}"; do
    printf 'note: %s\n' "$n"
  done
fi

present=0; absent=0; unreachable=0
HOLDERS=()
for slug in "${REPOS[@]}"; do
  IFS=$'\t' read -r state where <<< "$(locate "$slug")"
  printf '  %-40s %-12s %s\n' "$slug" "$state" "$where"
  case "$state" in
    present)     present=$((present + 1)); HOLDERS+=("$slug") ;;
    absent)      absent=$((absent + 1)) ;;
    unreachable) unreachable=$((unreachable + 1)) ;;
  esac
done

printf 'repos declared: %d\n' "${#REPOS[@]}"
printf 'repos reachable: %d\n' "$((present + absent))"
printf 'repos unreachable: %d\n' "$unreachable"
printf 'specs found: %d\n' "$present"

home_listed=0
for slug in "${REPOS[@]}"; do
  [ "$slug" = "$HOME_SLUG" ] && home_listed=1
done

if [ "$present" -ge 2 ]; then
  printf 'FAIL: R1 broken - %d repos hold a living spec (%s). One product, one spec: pick the home and supersede the other.\n' \
    "$present" "$(IFS=', '; printf '%s' "${HOLDERS[*]}")" >&2
  exit 1
fi

if [ "$unreachable" -gt 0 ]; then
  printf 'REFUSED: %d of %d repos could not be reached, so the number of living specs is UNKNOWN - not zero, and not one. A repo nobody could open is where a second spec hides.\n' \
    "$unreachable" "${#REPOS[@]}" >&2
  exit 2
fi

if [ "$present" -eq 0 ]; then
  printf 'FAIL: no repo in this product holds %s. Every repo was reached and none has one, so this is a measured zero, not an unmeasured one.\n' \
    "$SPECPATH" >&2
  exit 1
fi

if [ "$home_listed" -eq 0 ]; then
  printf 'FAIL: the declared home %s is not one of the repos in product.repos. A home outside the product is a home nothing checks.\n' \
    "$HOME_SLUG" >&2
  exit 1
fi

if [ "${HOLDERS[0]}" != "$HOME_SLUG" ]; then
  printf 'FAIL: the one living spec is in %s, but the config declares the home as %s. The declaration and the filesystem disagree, and downstream tooling believes the declaration.\n' \
    "${HOLDERS[0]}" "$HOME_SLUG" >&2
  exit 1
fi

printf 'PASS: exactly one living spec, in the declared home %s.\n' "$HOME_SLUG"
