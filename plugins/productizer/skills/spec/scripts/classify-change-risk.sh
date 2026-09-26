#!/usr/bin/env bash
# classify-change-risk.sh [--policy FILE] [--root DIR]
#                         [--base REF | --path P... | --paths-from FILE]
#                         [--calibrate [--commits N]]
#                         [--version] [--help] [--selftest]
#
# Classifies a change set by the paths it touches and reports the RISK TIER with
# the policy rule that decided each path. It GATES NOTHING. Reporting first is
# the point: a policy earns the right to block by being measured, and this is the
# instrument that measures it.
#
# THE POLICY IS A FILE, NOT AN OPINION IN HERE. `.claude/productizer/risk-tiers.yaml`
# declares the tiers and an ORDERED rule list; the first matching rule wins and
# its index and glob are printed beside every path, so every answer is
# attributable to one line of a committed file. This script contains no path
# knowledge of its own and no default tier.
#
# THE TIER LIST'S ORDER IS THE RANKING, highest risk first. That is how a change
# set touching several tiers gets one answer, and it is a property of the policy
# file rather than of this script - which is why this script cannot check it. A
# policy that listed its tiers low-to-high would produce confident backwards
# answers, and nothing here would notice.
#
# GREY IS NOT A TIER. A path no rule covers is UNCLASSIFIED and exits 1.
# Unclassified means nobody has decided about that path - it does NOT mean low
# risk, and this script will not print it as the bottom tier. That is R26's rule
# about numbers applied to words: an unmeasured thing rendered as a reassuring
# value is a fabrication whichever type it has.
#
# RISK AND COMPLEXITY ARE SEPARATE AXES, AND ONLY ONE OF THEM IS DECLARED.
#
#   RISK        printed, from the policy. A property of what was touched.
#   SIZE        printed, measured - files touched, lines added and removed.
#               Available only with --base, because it needs a diff.
#   COMPLEXITY  printed as `unmeasured`, ALWAYS. How much planning a change
#               needs is not a property of its paths. Deriving it from the tier
#               would print the tier twice under two names, and the case this
#               whole mechanism exists for - a one-line change to a contract -
#               is precisely where risk is maximal and complexity is minimal.
#
# THE CHANGE SET COMES FROM ONE OF THREE PLACES, and exactly one:
#
#   --base REF      the paths git reports changed between REF and the work tree.
#                   `--no-renames`, so a renamed file yields BOTH paths: the old
#                   path is what the policy may have a rule for, and collapsing
#                   the pair loses it.
#   --path P        named on the command line, repeatable. Bare arguments with no
#                   leading dash are paths too, which is the shape the check
#                   runner produces when it substitutes `{files}`. No diff, so no
#                   size.
#   --paths-from F  one path per line, `-` for stdin. No diff, so no size.
#
# --calibrate IS THE OTHER HALF, and it is a report, not a verdict. It walks the
# commits reachable from HEAD, classifies every path each one touched, and prints
# the tier distribution, the most frequently changed paths with their tiers, and
# the grey residue. It exits 0 when it measured, because "this history contains
# grey paths" is an observation about a repository, not a failure of one.
#
# WHAT IT PRINTS. One BARE PATH per line for every path examined, before
# anything else, so the runner's `stdout_paths` coverage can see what was
# actually looked at. Everything after that is indented.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  classified - every path in the change set matched a rule, and the tier
#      and the deciding rule are printed for each
#   1  at least one path matched no rule. Reported as `unclassified`, never as a
#      tier, and never as a pass. Also --calibrate's code when the range yielded
#      no commit at all, because a distribution over nothing is not a
#      distribution of zeros
#   2  could not run - bad usage, two change-set sources at once, no policy file,
#      a policy that is not readable, no python3, no yaml module, no git work
#      tree when one was needed, a shallow clone under --calibrate, or a change
#      set with no paths in it at all
#   3  the policy itself is unusable - a rule naming a tier the `tiers` block
#      does not declare, a rule with no glob or no reason, a duplicate glob, a
#      missing `unclassified` block, or an `unclassified` block claiming to be a
#      tier. Separate from 2 because a malformed policy and an absent one are
#      different repairs, and a policy read as empty would classify everything
#      grey while looking like it worked
#
# Under --selftest the same four mean: every case produced the code it declares
# (0), at least one did not (1), the corpus could not be built (2), and 3 is not
# produced by the self-test itself.
#
# WHAT THIS DOES NOT DO.
#
#   It does not read the CONTENT of any changed file. A one-character typo fix
#   and an inversion of a requirement's sentence in the same file are one
#   measurement here. `check-suspect-links.sh` is the instrument for the second.
#
#   It does not know about deletions beyond the path: a deleted red file is
#   classified red, which is right, but nothing here says the deletion is worse
#   than an edit.
#
#   It assigns the change set the HIGHEST tier any of its paths reached. A
#   commit touching one red path and forty blue ones is red, and the count of
#   each tier is printed so a reader can see the shape rather than only the
#   verdict.
set -euo pipefail

VERSION="1.0"

POLICY_REL=""
ROOT=""
BASE=""
PATHS_FROM=""
COMMITS=""
MODE="classify"
CLI_PATHS=()

die_unmeasured() {
  printf 'classify-change-risk: %s\n' "$1" >&2
  exit 2
}

usage() {
  sed -n '2,/^set -euo pipefail$/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf 'classify-change-risk.sh %s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --calibrate) MODE="calibrate"; shift ;;
    --policy) [ "$#" -ge 2 ] || die_unmeasured "--policy needs a value"; POLICY_REL="$2"; shift 2 ;;
    --root) [ "$#" -ge 2 ] || die_unmeasured "--root needs a value"; ROOT="$2"; shift 2 ;;
    --base) [ "$#" -ge 2 ] || die_unmeasured "--base needs a value"; BASE="$2"; shift 2 ;;
    --path) [ "$#" -ge 2 ] || die_unmeasured "--path needs a value"; CLI_PATHS+=("$2"); shift 2 ;;
    --paths-from) [ "$#" -ge 2 ] || die_unmeasured "--paths-from needs a value"; PATHS_FROM="$2"; shift 2 ;;
    --commits) [ "$#" -ge 2 ] || die_unmeasured "--commits needs a value"; COMMITS="$2"; shift 2 ;;
    # A leading dash is an option this script does not take, and that is an
    # error rather than a path: a mistyped flag silently read as a filename
    # would be classified grey and reported as a finding about the policy.
    -*) die_unmeasured "unknown option: $1" ;;
    # Anything else is a path. This is the shape the check runner produces - it
    # substitutes `{files}` as plain arguments and offers no way to hand a list
    # on stdin - so a declared check reads `[classify-change-risk.sh, "{files}"]`.
    *) CLI_PATHS+=("$1"); shift ;;
  esac
done

# ---------------------------------------------------------------------------
# The matcher and the reporter. One python program, two modes, so the glob
# semantics that decide one change set's tier and the glob semantics that
# aggregate a history cannot drift apart.
# ---------------------------------------------------------------------------
MATCHER='
import re, sys, collections

mode      = sys.argv[1]
policy_fp = sys.argv[2]
paths_fp  = sys.argv[3]
size_line = sys.argv[4]

def refuse(msg, code=2):
    sys.stderr.write("classify-change-risk: " + msg + "\n")
    raise SystemExit(code)

try:
    import yaml
except ImportError:
    refuse("python3 has no yaml module, so the risk policy cannot be read. "
           "Nothing was classified; that is not the same as everything being low risk.")

try:
    with open(policy_fp, "r", encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
except OSError as exc:
    refuse("the risk policy could not be read: %s" % exc)
except yaml.YAMLError as exc:
    refuse("the risk policy is not parseable YAML: %s" % exc)

if not isinstance(doc, dict):
    refuse("the risk policy did not parse to a mapping", 3)

if doc.get("version") != 1:
    refuse("the risk policy declares version %r; this tool reads version 1"
           % (doc.get("version"),), 3)

tiers = doc.get("tiers")
if not isinstance(tiers, list) or not tiers:
    refuse("the risk policy declares no tiers", 3)

order = []
for entry in tiers:
    if not isinstance(entry, dict):
        refuse("a tiers entry is not a mapping", 3)
    for field in ("id", "means", "review"):
        if not entry.get(field):
            refuse("tier %r has no %s" % (entry.get("id"), field), 3)
    if entry["id"] in order:
        refuse("tier %r is declared twice" % entry["id"], 3)
    order.append(entry["id"])

unc = doc.get("unclassified")
if not isinstance(unc, dict):
    refuse("the risk policy has no `unclassified` block, so a path no rule "
           "covers would have nowhere to land but a tier", 3)
if unc.get("is_a_tier") is not False:
    refuse("the `unclassified` block does not declare `is_a_tier: false`; "
           "unclassified is the absence of a decision and must not rank", 3)
unc_id = unc.get("id") or "grey"
if unc_id in order:
    refuse("%r is both a tier and the unclassified id" % unc_id, 3)

rules = doc.get("rules")
if not isinstance(rules, list) or not rules:
    refuse("the risk policy declares no rules", 3)

def glob_to_regex(g):
    out, i = ["^"], 0
    while i < len(g):
        if g.startswith("**/", i):
            out.append("(?:[^/]+/)*"); i += 3
        elif g.startswith("/**", i) and i + 3 == len(g):
            out.append("(?:/.*)?"); i += 3
        elif g.startswith("**", i):
            out.append(".*"); i += 2
        elif g[i] == "*":
            out.append("[^/]*"); i += 1
        elif g[i] == "?":
            out.append("[^/]"); i += 1
        else:
            out.append(re.escape(g[i])); i += 1
    out.append("$")
    return re.compile("".join(out))

compiled, seen = [], {}
for idx, rule in enumerate(rules, start=1):
    if not isinstance(rule, dict):
        refuse("rule %d is not a mapping" % idx, 3)
    glob = rule.get("glob")
    tier = rule.get("tier")
    why  = rule.get("why")
    if not glob:
        refuse("rule %d has no glob" % idx, 3)
    if tier not in order:
        refuse("rule %d (%s) names tier %r, which the tiers block does not declare"
               % (idx, glob, tier), 3)
    if not why:
        refuse("rule %d (%s) carries no reason. A tier nobody wrote a reason for "
               "is one nobody can argue with" % (idx, glob), 3)
    if glob in seen:
        refuse("glob %s appears in rule %d and rule %d; first match wins, so the "
               "second can never decide anything and one of them is a mistake"
               % (glob, seen[glob], idx), 3)
    seen[glob] = idx
    compiled.append((idx, tier, glob, glob_to_regex(glob)))

rank = {t: i for i, t in enumerate(order)}

def shown(path, width):
    """The TAIL of a long path, marked as elided. A silently left-truncated path
    reads like a path that exists, and a reader cannot tell the two apart."""
    return path if len(path) <= width else "..." + path[-(width - 3):]

def classify(path):
    for idx, tier, glob, rx in compiled:
        if rx.match(path):
            return idx, tier, glob
    return None, unc_id, None

try:
    with open(paths_fp, "r", encoding="utf-8") as fh:
        raw = [ln.rstrip("\n") for ln in fh]
except OSError as exc:
    refuse("the path list could not be read: %s" % exc)

# ---- calibrate: aggregate over history ------------------------------------
if mode == "calibrate":
    NO_PATHS = "(no path reported)"
    per_tier    = collections.Counter()
    per_path    = collections.Counter()
    path_tier   = {}
    commit_tier = {}
    for ln in raw:
        if "\t" not in ln:
            continue
        sha, path = ln.split("\t", 1)
        if not sha:
            continue
        commit_tier.setdefault(sha, None)
        path = path.strip()
        if not path:
            continue
        idx, tier, glob = classify(path)
        per_tier[tier] += 1
        per_path[path] += 1
        path_tier[path] = tier
        cur = commit_tier[sha]
        if tier == unc_id:
            if cur is None:
                commit_tier[sha] = unc_id
        elif cur is None or cur == unc_id or rank[tier] < rank[cur]:
            commit_tier[sha] = tier
    if not commit_tier:
        refuse("no commit in the range was read, so nothing was classified. A "
               "distribution over zero commits is not a distribution of zeros", 1)
    total = sum(per_tier.values())
    if total == 0:
        refuse("every commit in the range reported no path, so no path-change "
               "was classified", 1)
    print("    calibration over the whole history of this repository")
    print("      commits read:       %6d" % len(commit_tier))
    print("      path-changes:       %6d" % total)
    for tier in order + [unc_id]:
        n = per_tier[tier]
        label = tier if tier != unc_id else unc_id + " (unclassified)"
        print("      %-24s %6d  %5.1f%%" % (label, n, 100.0 * n / total))
    print("      distinct paths:     %6d" % len(per_path))
    print("    commits by their highest tier")
    cbt = collections.Counter(
        NO_PATHS if v is None else v for v in commit_tier.values())
    for tier in order + [unc_id, NO_PATHS]:
        n = cbt[tier]
        label = tier if tier != unc_id else unc_id + " (every path unclassified)"
        print("      %-34s %5d  %5.1f%%" % (label, n, 100.0 * n / len(commit_tier)))
    print("    the paths that actually change here, most first")
    for path, n in per_path.most_common(20):
        print("      %-68s %-6s %4d" % (shown(path, 68), path_tier[path], n))
    grey = [(p, n) for p, n in per_path.most_common() if path_tier[p] == unc_id]
    if grey:
        print("    grey residue - paths no rule covers, most first")
        for path, n in grey[:20]:
            print("      %-68s %4d" % (shown(path, 68), n))
        print("      distinct grey paths: %d of %d" % (len(grey), len(per_path)))
    else:
        print("    grey residue: none - every path in this history matched a rule")
    print("    NOT A VERDICT. This is a distribution, and a distribution cannot")
    print("    say a tier is set correctly. What it CAN say is when a tier has")
    print("    stopped discriminating: a tier reached by most commits is not")
    print("    telling a reader anything they did not already know.")
    raise SystemExit(0)

# ---- classify: one change set ---------------------------------------------
paths = [p.strip() for p in raw]
paths = [p for p in paths if p]
if not paths:
    refuse("the change set contains no paths, so no tier was computed. An empty "
           "change set is not a low-risk change set; the tier is - (never run)")

rows, counts = [], collections.Counter()
for path in sorted(set(paths)):
    idx, tier, glob = classify(path)
    rows.append((path, tier, idx, glob))
    counts[tier] += 1

for path, _t, _i, _g in rows:
    print(path)

ranked = [t for _p, t, _i, _g in rows if t != unc_id]
highest = min(ranked, key=lambda t: rank[t]) if ranked else None

if highest is None:
    print("    risk tier: %s (unclassified) - every path in this change set is "
          "uncovered, so no tier was reached" % unc_id)
else:
    print("    risk tier: %s" % highest)
print("    decided by")
for path, tier, idx, glob in rows:
    if idx is None:
        print("      %-60s %-6s  no rule" % (shown(path, 60), tier))
    else:
        print("      %-60s %-6s  rule %-3d %s" % (shown(path, 60), tier, idx, glob))
print("    tiers present: " + "  ".join("%s %d" % (t, counts[t]) for t in order)
      + "   %s (unclassified) %d" % (unc_id, counts[unc_id]))
print("    size: %s" % size_line)
print("    complexity: unmeasured - no path predicts how much planning a change")
print("    needs, and this policy declares risk only. A one-line edit to the")
print("    living spec is maximum risk and minimum complexity at once.")

if counts[unc_id]:
    print("    UNCLASSIFIED: %d path(s) matched no rule. Unclassified is not the"
          % counts[unc_id])
    print("    bottom tier - it is the absence of a decision, and it is reported")
    print("    as a finding so that the decision gets made.")
    raise SystemExit(1)
raise SystemExit(0)
'

# ---------------------------------------------------------------------------
# --selftest
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  command -v python3 >/dev/null 2>&1 || { echo "selftest: no python3" >&2; exit 2; }
  python3 -c 'import yaml' || { echo "selftest: python3 has no yaml module" >&2; exit 2; }

  WORK="$(mktemp -d)" || { echo "selftest: could not make a work directory" >&2; exit 2; }
  trap 'rm -rf "$WORK"' EXIT

  CASES=0; UPHELD=0; REPORT=""; CODES=""

  # A minimal but STRUCTURALLY COMPLETE policy. It is deliberately NOT this
  # repository's policy: a self-test reading the live policy would change its
  # answers whenever the policy changed, which tests the repository rather than
  # the tool.
  cat > "$WORK/good.yaml" <<'GOOD_POLICY'
version: 1
tiers:
  - id: red
    means: structural
    review: a person decides
  - id: blue
    means: autonomous-safe
    review: an agent may land it
unclassified:
  id: grey
  is_a_tier: false
  means: no rule covers this path
rules:
  - tier: red
    glob: "contract.md"
    why: the agreement
  - tier: blue
    glob: "docs/**"
    why: prose
  - tier: blue
    glob: "plugins/*/skills/*/references/**"
    why: prose, reached across segments
GOOD_POLICY

  printf 'contract.md\ndocs/a.md\n' > "$WORK/list-ok"
  : > "$WORK/list-empty"

  sed 's/^  - tier: red$/  - tier: crimson/' "$WORK/good.yaml" > "$WORK/undeclared-tier.yaml"
  sed 's/^  is_a_tier: false$/  is_a_tier: true/' "$WORK/good.yaml" > "$WORK/grey-ranks.yaml"
  grep -v -e '^unclassified:$' -e '^  id: grey$' -e '^  is_a_tier: false$' \
          -e '^  means: no rule covers this path$' \
          "$WORK/good.yaml" > "$WORK/no-unc.yaml"

  cat > "$WORK/no-why.yaml" <<'NO_WHY_POLICY'
version: 1
tiers:
  - id: red
    means: structural
    review: a person decides
unclassified:
  id: grey
  is_a_tier: false
  means: no rule covers this path
rules:
  - tier: red
    glob: "contract.md"
NO_WHY_POLICY

  cat > "$WORK/dup-glob.yaml" <<'DUP_POLICY'
version: 1
tiers:
  - id: red
    means: structural
    review: a person decides
  - id: blue
    means: autonomous-safe
    review: an agent may land it
unclassified:
  id: grey
  is_a_tier: false
  means: no rule covers this path
rules:
  - tier: red
    glob: "contract.md"
    why: the agreement
  - tier: blue
    glob: "contract.md"
    why: and now it is prose, which cannot both be true
DUP_POLICY

  printf 'this is not yaml at all: [\n' > "$WORK/broken.yaml"

  # `|| GOT=$?` on the SAME line as the command. A pipeline or a command
  # substitution in an argument list resets $?, and reading the status one line
  # later is how a self-test reports a pass it never observed.
  drive() {
    NAME="$1"; WANT="$2"; WHY="$3"; shift 3
    GOT=0
    bash "$0" --root "$WORK" "$@" > "$WORK/$NAME.out" 2> "$WORK/$NAME.err" || GOT=$?
    CASES=$((CASES + 1))
    if [ "$GOT" = "$WANT" ]; then UPHELD=$((UPHELD + 1)); V="held"; else V="NOT HELD"; fi
    CODES="$CODES$GOT
"
    REPORT="$REPORT      $NAME  expected $WANT  got $GOT  $V  $WHY
"
  }

  # --- 0: classified, every path covered -----------------------------------
  drive all-red 0 "one path, and the red rule decides it" \
    --policy "$WORK/good.yaml" --path contract.md
  drive mixed 0 "a red path and a blue path; the set takes the higher tier" \
    --policy "$WORK/good.yaml" --path contract.md --path docs/readme.md
  drive deep-glob 0 "** reaches across segments, so a nested reference path matches" \
    --policy "$WORK/good.yaml" --path plugins/p/skills/s/references/a/b/c.md
  drive from-file 0 "the change set arrives as a file, one path per line" \
    --policy "$WORK/good.yaml" --paths-from "$WORK/list-ok"
  drive positional 0 "bare arguments are paths - the shape the runner produces for {files}" \
    --policy "$WORK/good.yaml" contract.md docs/a.md

  # --- 1: a path no rule covers --------------------------------------------
  drive grey-only 1 "a path no rule covers is unclassified, not the bottom tier" \
    --policy "$WORK/good.yaml" --path src/new-thing.ts
  drive grey-beside-blue 1 "one grey path among covered ones still exits 1" \
    --policy "$WORK/good.yaml" --path docs/readme.md --path src/new-thing.ts
  drive star-does-not-cross 1 "a single * must not reach across a path separator" \
    --policy "$WORK/good.yaml" --path plugins/p/extra/skills/s/references/x.md

  # --- 2: could not run ----------------------------------------------------
  drive no-policy 2 "the named policy file is not there" \
    --policy "$WORK/there-is-no-policy-here.yaml" --path contract.md
  drive empty-set 2 "a change set with no paths in it - not a low-risk change set" \
    --policy "$WORK/good.yaml" --paths-from "$WORK/list-empty"
  drive bad-usage 2 "an option this script does not take" \
    --policy "$WORK/good.yaml" --frobnicate
  drive two-sources 2 "a change set cannot come from two places at once" \
    --policy "$WORK/good.yaml" --path contract.md --paths-from "$WORK/list-ok"
  drive unparseable 2 "a policy that is not YAML - read as empty it would grey everything" \
    --policy "$WORK/broken.yaml" --path contract.md

  # --- 3: the policy itself is unusable ------------------------------------
  drive undeclared-tier 3 "a rule names a tier the tiers block does not declare" \
    --policy "$WORK/undeclared-tier.yaml" --path contract.md
  drive no-why 3 "a rule with no reason beside it" \
    --policy "$WORK/no-why.yaml" --path contract.md
  drive dup-glob 3 "the same glob twice, so the second can never decide anything" \
    --policy "$WORK/dup-glob.yaml" --path contract.md
  drive grey-ranks 3 "unclassified declaring itself a tier" \
    --policy "$WORK/grey-ranks.yaml" --path contract.md
  drive no-unc 3 "no unclassified block, so an uncovered path has nowhere to land" \
    --policy "$WORK/no-unc.yaml" --path contract.md

  # Sentences, not only codes. A case that exits right for the wrong reason is
  # the failure a code-only assertion cannot see, so the rows carrying this
  # tool's central claims assert their WORDING too.
  WORDED=0; WORDED_OK=0
  assert_says() {
    WORDED=$((WORDED + 1))
    if grep -q "$2" "$WORK/$1.out"; then
      WORDED_OK=$((WORDED_OK + 1)); W="held"
    else
      W="NOT HELD"
    fi
    REPORT="$REPORT      wording:$1  $W  $3
"
  }
  assert_says grey-only 'Unclassified is not the' \
    "the grey finding says unclassified is not the bottom tier"
  assert_says mixed 'complexity: unmeasured' \
    "complexity is never derived from the tier"
  assert_says mixed 'risk tier: red' \
    "the set takes the highest tier any of its paths reached"
  assert_says positional 'risk tier: red' \
    "a bare argument reaches the same classification as --path"
  assert_says all-red 'size: unmeasured' \
    "with no diff, size is unmeasured and never 0 files"

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"
  if [ "$CASES" = "$UPHELD" ] && [ "$WORDED" = "$WORDED_OK" ]; then
    SELF_VERDICT="held"
  else
    SELF_VERDICT="NOT HELD"
  fi
  printf '    R39.s  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$CASES" "$UPHELD" "$SELF_VERDICT" \
    "each case exits the code it declares, and five rows also assert the sentence"
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2 3; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2 3\n' "$REACHED"
  printf '    NOT ASSERTED: --calibrate and --base are not driven here, so neither the history aggregation nor the SIZE measurement is covered by a case - only the `size: unmeasured` wording for a change set with no diff is. Both need a real git history, and a self-test that built one would be measuring the fixture it had just written. Their figures in references/risk-and-calibration.md come from runs against this repository, including the verified fact that --no-renames yields BOTH paths of a move.\n'
  [ "$CASES" = "$UPHELD" ] || exit 1
  [ "$WORDED" = "$WORDED_OK" ] || exit 1
  if [ -n "$MISSING" ]; then
    printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run.
# ---------------------------------------------------------------------------
command -v python3 >/dev/null 2>&1 \
  || die_unmeasured "python3 is not installed, so the risk policy could not be read"

SOURCES=0
[ -n "$BASE" ] && SOURCES=$((SOURCES + 1))
[ -n "$PATHS_FROM" ] && SOURCES=$((SOURCES + 1))
[ "${#CLI_PATHS[@]}" -gt 0 ] && SOURCES=$((SOURCES + 1))
if [ "$MODE" = "classify" ] && [ "$SOURCES" -gt 1 ]; then
  die_unmeasured "--base, --path and --paths-from are three ways to name ONE change set; give one. Two sources silently classify a set nobody asked about."
fi

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" \
    || die_unmeasured "no git work tree here and --root was not given; the policy could not be located"
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

[ -n "$POLICY_REL" ] || POLICY_REL=".claude/productizer/risk-tiers.yaml"
case "$POLICY_REL" in
  /*) POLICY="$POLICY_REL" ;;
  *)  POLICY="$ROOT/$POLICY_REL" ;;
esac
[ -r "$POLICY" ] \
  || die_unmeasured "no readable risk policy at $POLICY. Nothing was classified, which is not the same as nothing being risky."

TMP="$(mktemp -d)" || die_unmeasured "could not make a temporary directory"
trap 'rm -rf "$TMP"' EXIT
LIST="$TMP/paths"
: > "$LIST"
SIZE_LINE="unmeasured - no diff was taken, so files and lines are unknown. Not zero."

if [ "$MODE" = "calibrate" ]; then
  git -C "$ROOT" rev-parse --git-dir > /dev/null \
    || die_unmeasured "--calibrate reads history and this is not a git work tree"
  if [ "$(git -C "$ROOT" rev-parse --is-shallow-repository)" = "true" ]; then
    die_unmeasured "--calibrate reads history and this clone is shallow; a distribution over a truncated history is not this repository's distribution"
  fi
  LOG_ARGS=(log --no-renames --pretty=format:#SHA#%H --name-only)
  [ -n "$COMMITS" ] && LOG_ARGS+=("-n" "$COMMITS")
  # `<sha>\t<path>` per line, with a marked sha line carried forward by awk so a
  # commit that touched nothing is still counted as read rather than vanishing.
  git -C "$ROOT" "${LOG_ARGS[@]}" \
    | awk 'BEGIN{sha=""}
           index($0, "#SHA#") == 1 { sha = substr($0, 6); print sha "\t"; next }
           NF { print sha "\t" $0 }' > "$LIST"
  set +e
  python3 -c "$MATCHER" calibrate "$POLICY" "$LIST" "$SIZE_LINE"
  RC=$?
  set -e
  exit "$RC"
fi

if [ -n "$BASE" ]; then
  git -C "$ROOT" rev-parse --git-dir > /dev/null \
    || die_unmeasured "--base needs a git work tree"
  git -C "$ROOT" rev-parse --verify --quiet "$BASE" > /dev/null \
    || die_unmeasured "--base $BASE does not resolve to a commit here"
  # --no-renames deliberately: git's rename detection reports one path for a
  # move, and the OLD path is the one the policy may have a rule for.
  git -C "$ROOT" diff --name-only --no-renames "$BASE" -- > "$LIST" \
    || die_unmeasured "git diff against $BASE failed"
  FILES="$(grep -c . "$LIST" || true)"
  ADDREM="$(git -C "$ROOT" diff --numstat --no-renames "$BASE" -- \
    | awk '{a+=$1; d+=$2} END{printf "+%d/-%d", a, d}')"
  SIZE_LINE="$FILES files  $ADDREM lines  (a direct measurement of SIZE, which is not complexity)"
elif [ -n "$PATHS_FROM" ]; then
  if [ "$PATHS_FROM" = "-" ]; then
    cat > "$LIST"
  else
    [ -r "$PATHS_FROM" ] || die_unmeasured "--paths-from $PATHS_FROM is not readable"
    cat "$PATHS_FROM" > "$LIST"
  fi
elif [ "${#CLI_PATHS[@]}" -gt 0 ]; then
  printf '%s\n' "${CLI_PATHS[@]}" > "$LIST"
else
  die_unmeasured "no change set: give --base, --path or --paths-from. Classifying nothing would print a tier nobody measured."
fi

set +e
python3 -c "$MATCHER" classify "$POLICY" "$LIST" "$SIZE_LINE"
RC=$?
set -e
exit "$RC"
