#!/usr/bin/env bash
# upgrade-drift.sh [--repo DIR] [--plugin DIR] [--scaffolded-version X]
#                  [--diff] [--version] [--help] [--selftest]
#
# A REPO THAT INSTALLED THIS PLUGIN AT VERSION X AND NOW RUNS VERSION Y IS
# TOLD NOTHING.
#
# `scaffold.sh` never overwrites, deliberately - "scaffolding never replaces
# work" is its own sentence and it is the right rule. The consequence nobody
# wrote down is that once a repo has `.claude/productizer/`, no later plugin
# upgrade touches it again. Ever. The repo keeps the seeds, the hooks and the
# check list it received on the day it was scaffolded, and the plugin moves.
#
# `check-installed-copies.sh` names this hazard in its own header and then
# scopes itself to THIS repository:
#
#     the dangerous direction is the other one - this repo hardening its own
#     gate while every repo installing the plugin keeps the weaker copy
#
# That is the case it cannot see and this script is pointed at: some OTHER
# repo, scaffolded at some earlier version, holding copies nobody compared.
#
# WHAT IS MEASURED. Five dimensions, reported separately because they fail
# separately and a person will want to act on them separately.
#
#   1. VERSION PROVENANCE - which plugin version is installed here, against
#      which version scaffolded the repo.
#   2. INSTALLED EXECUTABLES - hooks that landed from a template and no longer
#      are that template. Byte-compared, the technique
#      `check-installed-copies.sh` established.
#   3. SCHEMA VERSIONS - the repo's `config.json` and `checks.yaml` carry their
#      OWN schema versions, independent of the plugin's. A repo can be two
#      schema revisions behind while every file looks fine.
#   4. CHECKS SHIPPED BUT NEVER DECLARED - check ids the plugin's checks.yaml
#      template now carries that the repo's checks.yaml has never named. An
#      undeclared check does not run, and a suite that never ran a check is
#      not a suite that passed it.
#   5. TEMPLATES THAT GAINED CONTENT - lines a template has that the repo's
#      copy does not. A seed is meant to be edited, so a difference is not by
#      itself a defect; content the template GAINED is the part a person may
#      want and cannot currently see.
#
#      THE TEMPLATE IS COMPARED IN ITS SCAFFOLDED FORM, NOT ITS SHIPPED ONE.
#      `scaffold.sh` strips every fenced `EXAMPLE:BEGIN..EXAMPLE:END` block on
#      the way in, because the worked examples are numbered - R1..R6, P1..P5 -
#      and copying them verbatim seeds a repo with requirements nobody agreed
#      to. Diffing the shipped template instead reported those blocks as
#      content every scaffolded repo is missing, forever: measured here on a
#      real repo, 77 lines each on spec.md and constitution.md, all of it the
#      examples doing exactly what they exist to do. The same strip is applied
#      before comparing, so what is left is content the template really gained.
#
# NOTHING IS EVER WRITTEN. Not one path outside this script's own `mktemp -d`
# under `--selftest` is opened for writing on any code path. The report ends
# at a person, who applies, dismisses or defers each finding themselves. This
# is P2 - nothing reaches an audience without a person deciding - and it is the
# same shape as reporting a suspect link rather than rewriting it.
#
# THE REPOSITORY BEING EXAMINED NEVER CHOOSES WHAT RUNS. This is P4, it is the
# sharpest constraint here, and it is worth being explicit about how it is
# honoured, because "we only read files" is not on its own enough:
#
#   * NOTHING FROM THE REPO IS EXECUTED. No `bash`, no `source`, no `eval`, no
#     command substitution over repo content. The hooks under examination are
#     compared as bytes and are never run - not even with `--help`.
#   * THE COMPARISON SET COMES FROM THE PLUGIN SIDE ONLY. Every filename this
#     script iterates is a `basename` taken from the plugin's own templates
#     directory or from the fixed table below. The repo-side path is then
#     built as `<repo>/<fixed relative path>`. A repo cannot name a file, add
#     a glob, or point this script at anything it did not already intend to
#     look at.
#   * THE REPO'S CONFIG IS NEVER A SOURCE OF PATHS. `config.json` has a
#     `spec.path` key. Following it would let a committed file in a foreign
#     repo choose what gets read and then printed. It is not read. The spec is
#     looked for at the scaffolded location and nowhere else, and a repo that
#     relocated its spec is reported as UNMEASURED rather than followed. That
#     is a real loss of coverage, taken deliberately.
#   * ONLY TWO VALUES ARE EVER PARSED OUT OF REPO CONTENT, both through an
#     anchored pattern with a fixed character class: an integer schema version,
#     and check ids matching `[a-z0-9][a-z0-9-]*`. Neither is used as a path,
#     a command, or an argument to one.
#   * A SYMLINK ON THE REPO SIDE IS A FINDING, NOT SOMETHING TO FOLLOW. A repo
#     can replace its scaffolded `config.json` with a link to anything the
#     invoking user can read. Following it would put that file's content into
#     a report. Symlinked entries are refused and counted UNMEASURED.
#
# A VIEW NEVER BECOMES AN INPUT (P3). This report is output. This script reads
# no report, its own or any other, and nothing it prints is fed back to it.
#
# UNKNOWN IS A REAL ANSWER AND RENDERS AS ITSELF (P1). Nothing in a scaffolded
# repo records which plugin version scaffolded it - measured, not assumed; see
# the recommendation in `references/upgrade.md`. So version provenance is
# `unknown` on every repo scaffolded before that changes, and `unknown` is
# NOT rendered as `up to date` and does not exit 0. A person who knows the
# answer can supply it with `--scaffolded-version`, and the report then says
# the value was ASSERTED BY AN OPERATOR rather than measured.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every dimension was measured, and the repo matches the installed plugin
#   1  drift reported. Every dimension was measured and at least one differs.
#      NOTHING WAS CHANGED - the findings are for a person to apply, dismiss
#      or defer.
#   2  could not run - bad usage, no plugin manifest, no templates directory,
#      or the repo has no productizer scaffold to be out of date at all
#   3  at least one dimension COULD NOT BE MEASURED, so the drift list has a
#      hole in it. Outranks 1 deliberately: an incomplete list of differences
#      presented as the list of differences is the failure this repo keeps
#      finding, and "we did not look there" must not read as "nothing there".
#
# --SELFTEST DRIVES EVERY ONE OF THOSE FOUR, and the reached half of the R39.b
# declaration is accumulated from the cases as they run.
#
# WHAT IT PRINTS. One BARE repo-relative path per file examined. Findings,
# counts and notes are INDENTED. Content is printed only under `--diff`, which
# is off by default, so the default report is safe to keep and carries no
# bytes out of the repo being examined.
set -euo pipefail

VERSION="upgrade-drift 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO=""; PLUGIN=""; ASSERTED=""; SHOW_DIFF=0; MODE="measure"

die_unmeasured() { printf 'upgrade-drift: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --repo)     [ "$#" -ge 2 ] || die_unmeasured "--repo needs a path";   REPO="$2";   shift 2 ;;
    --repo=*)   REPO="${1#--repo=}";     shift ;;
    --plugin)   [ "$#" -ge 2 ] || die_unmeasured "--plugin needs a path"; PLUGIN="$2"; shift 2 ;;
    --plugin=*) PLUGIN="${1#--plugin=}"; shift ;;
    --scaffolded-version)   [ "$#" -ge 2 ] || die_unmeasured "--scaffolded-version needs a value"; ASSERTED="$2"; shift 2 ;;
    --scaffolded-version=*) ASSERTED="${1#--scaffolded-version=}"; shift ;;
    --diff) SHOW_DIFF=1; shift ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1." ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1."

# ---------------------------------------------------------------------------
# --selftest. Each case builds a little plugin and a little repo under
# `mktemp -d`, differing from the clean pair in exactly one way, drives THIS
# script against them, and compares the exit code with the one it declares.
# Nothing is written into any real repository on any exit path, signal
# included.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  WORK="$(mktemp -d)" \
    || die_unmeasured "cannot create a temporary directory to build the cases in; nothing was driven"
  trap 'rm -rf "$WORK"' EXIT HUP INT TERM

  CASES=0; UPHELD=0; REPORT=""
  # A SECOND assertion, counted separately: does the case's report actually
  # NAME the dimension it was built to exercise? This is not belt and braces.
  # Breaking dimension 4 on purpose left `undeclared-check` still exiting 1 -
  # section 5 fired on the same fixture and carried the code - so the exit code
  # alone certified a detection that had been deleted. The exit-code accounting
  # is kept pure and this runs beside it.
  ASSERTS=0; ASSERTS_UPHELD=0; AREPORT=""
  # R39.b: ACCUMULATED, one entry per case as it ran. A literal list would
  # satisfy a reader and prove nothing.
  CODES=""

  # A clean pair: a plugin at 9.9.9 with two templates and a hook, and a repo
  # whose scaffold matches it and which records the version that scaffolded it.
  build() {
    B="$WORK/$1"
    mkdir -p "$B/plugin/.claude-plugin" "$B/plugin/skills/spec/templates" \
             "$B/repo/.claude/productizer" "$B/repo/.claude/hooks" \
      || die_unmeasured "could not lay out the case directory for $1"
    printf '{ "name": "productizer", "version": "9.9.9" }\n' > "$B/plugin/.claude-plugin/plugin.json"
    printf '#!/usr/bin/env bash\n# a gate\nexit 0\n' > "$B/plugin/skills/spec/templates/publish-gate.sh"
    printf '{\n  "version": 2\n}\n' > "$B/plugin/skills/spec/templates/config.json"
    printf 'version: 1\nchecks:\n  - id: secret-scan\n  - id: shell-lint\n' \
      > "$B/plugin/skills/spec/templates/checks.yaml"
    cp "$B/plugin/skills/spec/templates/publish-gate.sh" "$B/repo/.claude/hooks/publish-gate.sh"
    chmod +x "$B/repo/.claude/hooks/publish-gate.sh"
    cp "$B/plugin/skills/spec/templates/config.json"  "$B/repo/.claude/productizer/config.json"
    cp "$B/plugin/skills/spec/templates/checks.yaml"  "$B/repo/.claude/productizer/checks.yaml"
    printf '{ "plugin_version": "9.9.9" }\n' > "$B/repo/.claude/productizer/installed.json"
  }

  # `|| GOT=$?` on the SAME LINE as the command. A `$(...)` in an argument list
  # and a pipeline both reset `$?`, and reading the status one line later is how
  # a self-test reports a pass it never observed.
  drive() {
    NAME="$1"; WANT="$2"; WHY="$3"; shift 3
    GOT=0
    bash "$0" "$@" > "$WORK/$NAME.out" 2> "$WORK/$NAME.err" || GOT=$?
    CASES=$((CASES + 1))
    if [ "$GOT" = "$WANT" ]; then UPHELD=$((UPHELD + 1)); V="held"; else V="NOT HELD"; fi
    CODES="$CODES$GOT
"
    REPORT="$REPORT      $NAME  expected $WANT  got $GOT  $V  $WHY
"
  }

  # <case> <substring the report must contain> <why that substring is the proof>
  expect_in() {
    ASSERTS=$((ASSERTS + 1))
    if grep -qF -- "$2" "$WORK/$1.out"; then
      ASSERTS_UPHELD=$((ASSERTS_UPHELD + 1)); AV="held"
    else
      AV="NOT HELD"
    fi
    AREPORT="$AREPORT      $1  $AV  report must name: $3
"
  }

  # 0 - the clean pair. Without it every red case below proves only that
  # something is red, not that this script is what makes it red.
  build clean
  drive clean 0 "a repo whose scaffold matches the installed plugin and which records the version that scaffolded it" \
    --repo "$WORK/clean/repo" --plugin "$WORK/clean/plugin"
  expect_in clean "Every dimension was measured, and this repo matches the plugin it has installed" "a measured pass, not an unmeasured one"

  # 1 - dimension 1, the version itself.
  build older-version
  printf '{ "plugin_version": "9.9.8" }\n' > "$WORK/older-version/repo/.claude/productizer/installed.json"
  drive older-version 1 "the repo was scaffolded by an older plugin version than the one installed" \
    --repo "$WORK/older-version/repo" --plugin "$WORK/older-version/plugin"
  expect_in older-version "scaffolded by 9.9.8, installed 9.9.9" "dimension 1, the version itself"

  # 1 - dimension 2, the installed executable. The dangerous direction.
  build drifted-hook
  printf 'exit 1\n' >> "$WORK/drifted-hook/repo/.claude/hooks/publish-gate.sh"
  drive drifted-hook 1 "an installed hook that is no longer the template it came from" \
    --repo "$WORK/drifted-hook/repo" --plugin "$WORK/drifted-hook/plugin"
  expect_in drifted-hook "publish-gate.sh is no longer the template it came from" "dimension 2, the installed executable"

  # 1 - dimension 3, the schema version, which moves independently of the
  # plugin version and of the file's own content.
  build schema-behind
  printf '{\n  "version": 1\n}\n' > "$WORK/schema-behind/repo/.claude/productizer/config.json"
  drive schema-behind 1 "the repo's config.json declares an older schema version than the template" \
    --repo "$WORK/schema-behind/repo" --plugin "$WORK/schema-behind/plugin"
  expect_in schema-behind "declares schema version 1; the installed plugin expects 2" "dimension 3, the schema version"

  # 1 - dimension 4, a check the plugin ships and the repo never declared. An
  # undeclared check does not run, and never running it is not passing it.
  build undeclared-check
  printf 'version: 1\nchecks:\n  - id: secret-scan\n' \
    > "$WORK/undeclared-check/repo/.claude/productizer/checks.yaml"
  drive undeclared-check 1 "the plugin ships a check id the repo's checks.yaml has never named" \
    --repo "$WORK/undeclared-check/repo" --plugin "$WORK/undeclared-check/plugin"
  expect_in undeclared-check "check id(s) the plugin ships are not declared" "dimension 4, the undeclared check"

  # 1 - dimension 5, content the template gained after the repo was scaffolded.
  build template-gained
  printf '  - id: dependency-audit\n' >> "$WORK/template-gained/plugin/skills/spec/templates/checks.yaml"
  cp "$WORK/template-gained/plugin/skills/spec/templates/checks.yaml" \
     "$WORK/template-gained/repo/.claude/productizer/checks.yaml"
  printf '{\n  "version": 2,\n  "note": "a key the template gained"\n}\n' \
    > "$WORK/template-gained/plugin/skills/spec/templates/config.json"
  drive template-gained 1 "a template gained lines the repo's copy does not have" \
    --repo "$WORK/template-gained/repo" --plugin "$WORK/template-gained/plugin"
  expect_in template-gained "config.json - the template has" "dimension 5, content the template gained"

  # 0 - the example blocks, which scaffold.sh strips on the way in. Diffing the
  # SHIPPED template instead reports them as content every scaffolded repo is
  # missing, forever - a finding that can never be actioned and never goes away.
  build example-blocks
  printf 'header\n<!-- EXAMPLE:BEGIN\nR1 a worked example nobody agreed to\nEXAMPLE:END -->\ntail\n' \
    > "$WORK/example-blocks/plugin/skills/spec/templates/backlog.md"
  printf 'header\ntail\n' > "$WORK/example-blocks/repo/.claude/productizer/backlog.md"
  drive example-blocks 0 "a template whose only difference from the repo copy is the example blocks scaffold.sh strips" \
    --repo "$WORK/example-blocks/repo" --plugin "$WORK/example-blocks/plugin"

  # 1 - the same template, with one real line gained on top of those blocks.
  # Without this pair the strip above could be silently over-stripping.
  build example-blocks-plus
  printf 'header\n<!-- EXAMPLE:BEGIN\nR1 a worked example nobody agreed to\nEXAMPLE:END -->\na line the template really gained\ntail\n' \
    > "$WORK/example-blocks-plus/plugin/skills/spec/templates/backlog.md"
  printf 'header\ntail\n' > "$WORK/example-blocks-plus/repo/.claude/productizer/backlog.md"
  drive example-blocks-plus 1 "the same template with one real gained line beside the stripped example block" \
    --repo "$WORK/example-blocks-plus/repo" --plugin "$WORK/example-blocks-plus/plugin"

  # 3 - nothing records which version scaffolded the repo. UNKNOWN is not
  # up-to-date, and it is not drift either.
  build unknown-version
  rm -f "$WORK/unknown-version/repo/.claude/productizer/installed.json"
  drive unknown-version 3 "no file records which plugin version scaffolded this repo, so the answer is unknown rather than current" \
    --repo "$WORK/unknown-version/repo" --plugin "$WORK/unknown-version/plugin"
  expect_in unknown-version "UNKNOWN: nothing in this repo records which plugin version scaffolded it" "unknown rendered as unknown, never as up to date"

  # 0 - the same repo with the answer supplied by a person. P1: an asserted
  # value is reported as asserted, and it is still an answer.
  build asserted-version
  rm -f "$WORK/asserted-version/repo/.claude/productizer/installed.json"
  drive asserted-version 0 "an operator supplied the scaffolding version the repo does not record" \
    --repo "$WORK/asserted-version/repo" --plugin "$WORK/asserted-version/plugin" \
    --scaffolded-version 9.9.9

  # 3 - a repo-side entry replaced by a symlink. P4: the repo does not get to
  # choose what this script reads, so the link is refused rather than followed,
  # and the dimension is unmeasured rather than clean.
  build symlinked
  rm -f "$WORK/symlinked/repo/.claude/productizer/config.json"
  ln -s /dev/null "$WORK/symlinked/repo/.claude/productizer/config.json"
  drive symlinked 3 "a scaffolded file replaced by a symlink, which is refused rather than followed" \
    --repo "$WORK/symlinked/repo" --plugin "$WORK/symlinked/plugin"
  expect_in symlinked "a symlink is refused rather than followed" "P4, the repo not choosing what is read"

  # 2 - no scaffold at all. There is nothing installed here to be out of date,
  # which is a different fact from "installed and current".
  build no-scaffold
  rm -rf "$WORK/no-scaffold/repo/.claude/productizer"
  drive no-scaffold 2 "a repo with no productizer scaffold, so there is nothing installed to be out of date" \
    --repo "$WORK/no-scaffold/repo" --plugin "$WORK/no-scaffold/plugin"

  # 2 - no plugin manifest. Without it the version being compared AGAINST is
  # unknown, and every dimension below is measured against nothing.
  build no-manifest
  rm -f "$WORK/no-manifest/plugin/.claude-plugin/plugin.json"
  drive no-manifest 2 "no plugin manifest, so there is no installed version to compare against" \
    --repo "$WORK/no-manifest/repo" --plugin "$WORK/no-manifest/plugin"

  # 2 - bad usage, which reaches could-not-run through the argument parser
  # rather than through the premise guards.
  build bad-usage
  drive bad-usage 2 "an option this script does not take" \
    --repo "$WORK/bad-usage/repo" --frobnicate

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"
  if [ "$CASES" = "$UPHELD" ]; then SELF_VERDICT="held"; else SELF_VERDICT="NOT HELD"; fi
  printf '    R39.s  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$CASES" "$UPHELD" "$SELF_VERDICT" \
    "each case exits with the code it declares"
  printf '%s' "$AREPORT"
  if [ "$ASSERTS" = "$ASSERTS_UPHELD" ]; then A_VERDICT="held"; else A_VERDICT="NOT HELD"; fi
  printf '    R39.s  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "case-report-names-its-own-dimension" "$ASSERTS" "$ASSERTS_UPHELD" "$A_VERDICT" \
    "each case reports the dimension it was built to exercise"
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2 3; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2 3\n' "$REACHED"
  printf '    NOT ASSERTED: the eight cases above pair their exit code with a required phrase, so a case going red for another dimension is caught; the four could-not-run and example-block cases are still asserted on the CODE ALONE and a wrong reason there is invisible\n'
  printf '    NOT ASSERTED: the fixtures are built by this file, so they prove the script reacts to a difference; they do not prove the fixed table below names every file a real scaffold writes\n'
  [ "$CASES" = "$UPHELD" ] || exit 1
  [ "$ASSERTS" = "$ASSERTS_UPHELD" ] || exit 1
  if [ -n "$MISSING" ]; then
    printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Premises. Everything below is read-only.
# ---------------------------------------------------------------------------
if [ -z "$PLUGIN" ]; then
  # Resolved from THIS script's location, never from anything the repo says.
  PLUGIN="$HERE/../../.."
fi
[ -d "$PLUGIN" ] || die_unmeasured "--plugin $PLUGIN is not a directory"
PLUGIN="$(cd "$PLUGIN" && pwd -P)"

MANIFEST="$PLUGIN/.claude-plugin/plugin.json"
TEMPLATES="$PLUGIN/skills/spec/templates"
[ -f "$MANIFEST" ] \
  || die_unmeasured "no plugin manifest at $MANIFEST, so the version being compared against is unknown and every comparison below would be against nothing"
[ -d "$TEMPLATES" ] \
  || die_unmeasured "no templates directory at $TEMPLATES, so there is nothing to compare the repo's copies against"

PLUGIN_VERSION="$(python3 -c '
import io, json, sys
try:
    d = json.load(io.open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
v = d.get("version")
print(v if isinstance(v, str) and v else "")
' "$MANIFEST")" || die_unmeasured "the plugin manifest at $MANIFEST would not parse as JSON, so the installed version could not be read"
[ -n "$PLUGIN_VERSION" ] \
  || die_unmeasured "the plugin manifest at $MANIFEST carries no version string; there is nothing to compare against"

if [ -z "$REPO" ]; then
  REPO="$(git rev-parse --show-toplevel)" \
    || die_unmeasured "no git work tree here, and --repo was not given; the repo to examine could not be located"
fi
[ -d "$REPO" ] || die_unmeasured "--repo $REPO is not a directory"
REPO="$(cd "$REPO" && pwd -P)"

SCAFFOLD="$REPO/.claude/productizer"
[ -d "$SCAFFOLD" ] \
  || die_unmeasured "no .claude/productizer in $REPO, so nothing was ever installed here and there is nothing to be out of date. That is a different fact from installed-and-current, and it is not reported as one"

DRIFT=0
UNMEASURED=0
EXAMINED=0

# One BARE repo-relative path per file examined; the runner convention in this
# skill parses those as coverage. Findings are indented.
seen() { EXAMINED=$((EXAMINED + 1)); printf '%s\n' "$1"; }

# P4. Every repo-side path passes through here. A symlink is refused rather
# than followed: a committed link in a foreign repo would otherwise choose what
# this script reads and then reports.
#   0 usable regular file · 1 absent · 2 present but not a usable regular file
repo_file_state() {
  if [ -L "$1" ]; then return 2; fi
  if [ ! -e "$1" ]; then return 1; fi
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then return 2; fi
  return 0
}

# The template as scaffold.sh would have written it: the same fenced example
# blocks stripped, by the same pattern. Written to this script's OWN temporary
# directory - never into the repo being examined, which is not written to on
# any path. TMPDIR is created lazily so a run that needs no strip creates
# nothing at all.
STRIPDIR=""
STRIPPED=""
# Sets the GLOBAL $STRIPPED rather than printing the path. That is not style:
# a `$(scaffolded_form ...)` runs in a SUBSHELL, so the `mktemp -d` and the
# `trap ... EXIT` both belonged to that subshell and the directory was removed
# the instant the substitution closed. The caller then diffed against a path
# that no longer existed, `diff` failed into /dev/null, and the count came back
# 0 - a clean verdict for a file nobody compared. This script's own --selftest
# caught it: the case with a real gained line beside a stripped example block
# went 0 where it declares 1.
scaffolded_form() { # <template path> ; sets $STRIPPED
  if [ -z "$STRIPDIR" ]; then
    STRIPDIR="$(mktemp -d)" || die_unmeasured "cannot create a temporary directory to strip the example blocks in"
    trap 'rm -rf "$STRIPDIR"' EXIT HUP INT TERM
  fi
  STRIPPED="$STRIPDIR/$(basename "$1")"
  python3 -c '
import io, re, sys
s = io.open(sys.argv[1], encoding="utf-8", errors="replace").read()
out, _ = re.subn(r"<!-- EXAMPLE:BEGIN.*?EXAMPLE:END -->\n", "", s, flags=re.S)
io.open(sys.argv[2], "w", encoding="utf-8").write(out)
' "$1" "$STRIPPED" || die_unmeasured "could not strip the example blocks from $1, so what the template gained is UNKNOWN"
}

show_diff() { # <repo copy> <template>
  [ "$SHOW_DIFF" -eq 1 ] || return 0
  printf '    --- diff: what the template has that this copy does not (+ = template) ---\n'
  # -L twice, so the two `---`/`+++` header lines carry ROLES and not the
  # absolute paths of the machine this ran on. The diff is for a person to
  # read and may end up pasted somewhere; the filesystem layout of whoever
  # ran it is not part of the finding.
  diff -u -L "installed copy" -L "template as the plugin ships it" -- "$1" "$2" | sed 's/^/    /' || true
  printf '    --- end diff ---\n'
}

printf 'plugin version installed: %s\n' "$PLUGIN_VERSION"
printf 'repo examined: %s\n' "$REPO"
printf '\n'

# ---------------------------------------------------------------------------
# 1. VERSION PROVENANCE. P1: unknown is an answer and renders as itself.
# ---------------------------------------------------------------------------
printf '1. VERSION PROVENANCE\n'
SCAFFOLDED=""
SCAFFOLDED_HOW=""
if [ -n "$ASSERTED" ]; then
  SCAFFOLDED="$ASSERTED"
  SCAFFOLDED_HOW="ASSERTED BY AN OPERATOR on the command line, not measured from the repo"
else
  PROV="$SCAFFOLD/installed.json"
  if repo_file_state "$PROV"; then
    seen ".claude/productizer/installed.json"
    SCAFFOLDED="$(python3 -c '
import io, json, sys
try:
    d = json.load(io.open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
v = d.get("plugin_version")
print(v if isinstance(v, str) else "")
' "$PROV" || true)"
    [ -n "$SCAFFOLDED" ] && SCAFFOLDED_HOW="read from .claude/productizer/installed.json"
  fi
fi

if [ -z "$SCAFFOLDED" ]; then
  UNMEASURED=$((UNMEASURED + 1))
  printf '  UNKNOWN: nothing in this repo records which plugin version scaffolded it.\n'
  printf '           This is not "up to date" and it is not drift. It is unmeasured.\n'
  printf '           No file written by scaffold.sh or init.sh carries the plugin version,\n'
  printf '           so no repo scaffolded before that changes can answer this. A person who\n'
  printf '           knows the answer can supply it with --scaffolded-version, and it will be\n'
  printf '           reported as asserted rather than measured.\n'
elif [ "$SCAFFOLDED" = "$PLUGIN_VERSION" ]; then
  printf '  held: scaffolded by %s, installed %s - the same (%s)\n' \
    "$SCAFFOLDED" "$PLUGIN_VERSION" "$SCAFFOLDED_HOW"
else
  DRIFT=$((DRIFT + 1))
  printf '  FINDING: scaffolded by %s, installed %s (%s).\n' \
    "$SCAFFOLDED" "$PLUGIN_VERSION" "$SCAFFOLDED_HOW"
  printf '           Everything below was written by %s and no upgrade has touched it since.\n' "$SCAFFOLDED"
fi
printf '\n'

# ---------------------------------------------------------------------------
# 2. INSTALLED EXECUTABLES. Byte-compared, never run.
# ---------------------------------------------------------------------------
printf '2. INSTALLED EXECUTABLES\n'
HOOKS="$REPO/.claude/hooks"
hook_pairs=0
if [ -d "$HOOKS" ] && [ ! -L "$HOOKS" ]; then
  # The loop is over the PLUGIN's templates. The repo contributes no name.
  for tpl in "$TEMPLATES"/*.sh; do
    [ -f "$tpl" ] || continue
    base="$(basename "$tpl")"
    inst="$HOOKS/$base"
    if repo_file_state "$inst"; then :; else
      case "$?" in
        1) continue ;;
        *) UNMEASURED=$((UNMEASURED + 1))
           seen ".claude/hooks/$base"
           printf '  UNMEASURED: .claude/hooks/%s is present but is not a readable regular file (a symlink is refused rather than followed). Whether it drifted is UNKNOWN.\n' "$base"
           continue ;;
      esac
    fi
    hook_pairs=$((hook_pairs + 1))
    seen ".claude/hooks/$base"
    if cmp -s "$tpl" "$inst"; then
      printf '  held: %s is byte-for-byte the template it came from\n' "$base"
    else
      DRIFT=$((DRIFT + 1))
      _ts="$(wc -c < "$tpl" | tr -d ' ')"
      _is="$(wc -c < "$inst" | tr -d ' ')"
      printf '  FINDING: .claude/hooks/%s is no longer the template it came from (template %s bytes, installed %s bytes). This repo is running different gate code from the plugin it installed.\n' \
        "$base" "$_ts" "$_is"
      show_diff "$inst" "$tpl"
    fi
    if [ ! -x "$inst" ]; then
      DRIFT=$((DRIFT + 1))
      printf '  FINDING: .claude/hooks/%s is not executable, so it never runs. A gate that cannot run is absent, quietly.\n' "$base"
    fi
  done
  [ "$hook_pairs" -gt 0 ] || printf '  no template executable has a counterpart under .claude/hooks, so no installed executable was compared\n'
else
  printf '  no .claude/hooks directory to examine. This repo installed no hooks, so none of them can have drifted.\n'
fi
printf '\n'

# ---------------------------------------------------------------------------
# 3. SCHEMA VERSIONS. These move independently of the plugin version.
# ---------------------------------------------------------------------------
printf '3. SCHEMA VERSIONS\n'

json_schema_version() { # <path> -> integer or empty
  python3 -c '
import io, json, sys
try:
    d = json.load(io.open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
v = d.get("version")
print(v if isinstance(v, int) else "")
' "$1" || true
}

yaml_schema_version() { # <path> -> integer or empty. Anchored, fixed class.
  sed -n 's/^version:[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p' "$1" | head -1
}

compare_schema() { # <relative path> <template name> <json|yaml>
  local relp="$1" tplname="$2" kind="$3"
  local tpl="$TEMPLATES/$tplname" inst="$REPO/$relp"
  [ -f "$tpl" ] || { printf '  UNMEASURED: the plugin ships no %s template, so the expected schema version is unknown\n' "$tplname"; UNMEASURED=$((UNMEASURED + 1)); return; }
  if repo_file_state "$inst"; then :; else
    case "$?" in
      1) printf '  UNMEASURED: %s is not present in this repo, so its schema version is unknown (a repo that relocated it is not followed - see P4 in the header)\n' "$relp"
         UNMEASURED=$((UNMEASURED + 1)); return ;;
      *) seen "$relp"
         printf '  UNMEASURED: %s is present but is not a readable regular file (a symlink is refused rather than followed)\n' "$relp"
         UNMEASURED=$((UNMEASURED + 1)); return ;;
    esac
  fi
  seen "$relp"
  local want have
  if [ "$kind" = json ]; then
    want="$(json_schema_version "$tpl")"; have="$(json_schema_version "$inst")"
  else
    want="$(yaml_schema_version "$tpl")"; have="$(yaml_schema_version "$inst")"
  fi
  if [ -z "$want" ] || [ -z "$have" ]; then
    UNMEASURED=$((UNMEASURED + 1))
    printf '  UNMEASURED: %s - schema version could not be read on %s side (template %s, repo %s)\n' \
      "$relp" "$([ -z "$want" ] && printf 'the template' || printf 'the repo')" "${want:-none}" "${have:-none}"
    return
  fi
  if [ "$have" -eq "$want" ]; then
    printf '  held: %s declares schema version %s, which is what the plugin expects\n' "$relp" "$have"
  elif [ "$have" -lt "$want" ]; then
    DRIFT=$((DRIFT + 1))
    printf '  FINDING: %s declares schema version %s; the installed plugin expects %s. The file looks fine and is a revision behind.\n' \
      "$relp" "$have" "$want"
    show_diff "$inst" "$tpl"
  else
    DRIFT=$((DRIFT + 1))
    printf '  FINDING: %s declares schema version %s, AHEAD of the %s this plugin expects. The repo is running a newer schema than the tool reading it.\n' \
      "$relp" "$have" "$want"
  fi
}

compare_schema ".claude/productizer/config.json" config.json json
compare_schema ".claude/productizer/checks.yaml" checks.yaml yaml
printf '\n'

# ---------------------------------------------------------------------------
# 4. CHECKS SHIPPED BUT NEVER DECLARED.
# ---------------------------------------------------------------------------
printf '4. CHECKS THE PLUGIN SHIPS THAT THIS REPO HAS NEVER DECLARED\n'
check_ids() { # <path> -> ids, one per line. Anchored, fixed character class,
              # so nothing a repo can write becomes a path or an argument.
  sed -n 's/^[[:space:]]*-[[:space:]]*id:[[:space:]]*\([a-z0-9][a-z0-9-]*\)[[:space:]]*$/\1/p' "$1" | sort -u
}
TPL_CHECKS="$TEMPLATES/checks.yaml"
REPO_CHECKS="$SCAFFOLD/checks.yaml"
if [ ! -f "$TPL_CHECKS" ]; then
  UNMEASURED=$((UNMEASURED + 1))
  printf '  UNMEASURED: the plugin ships no checks.yaml template, so the shipped check set is unknown\n'
elif repo_file_state "$REPO_CHECKS"; then
  missing="$(comm -23 <(check_ids "$TPL_CHECKS") <(check_ids "$REPO_CHECKS") || true)"
  if [ -z "$missing" ]; then
    printf '  held: every check id the plugin ships is declared in this repo\n'
  else
    n="$(printf '%s\n' "$missing" | wc -l | tr -d ' ')"
    DRIFT=$((DRIFT + 1))
    printf '  FINDING: %s check id(s) the plugin ships are not declared in this repo. An undeclared check does not run, and never running a check is not passing it:\n' "$n"
    printf '%s\n' "$missing" | sed 's/^/      /'
  fi
else
  UNMEASURED=$((UNMEASURED + 1))
  printf '  UNMEASURED: this repo has no readable .claude/productizer/checks.yaml, so which checks it declares is unknown\n'
fi
printf '\n'

# ---------------------------------------------------------------------------
# 5. TEMPLATES THAT GAINED CONTENT.
#
# The table is FIXED and lives on the plugin side. A seed is meant to be
# edited, so a bare difference is not a defect; what is reported is the count
# of lines the TEMPLATE has that the repo's copy does not - content the
# template gained, which is the part a person may want and cannot see today.
# ---------------------------------------------------------------------------
printf '5. TEMPLATES THAT GAINED CONTENT SINCE THIS REPO WAS SCAFFOLDED\n'
printf '  A seed is meant to be edited. What is counted is lines the TEMPLATE has and this\n'
printf '  copy does not, never the other way round, so local edits are not reported as drift.\n'
printf '  The template is compared in the form scaffold.sh would have written it, with the\n'
printf '  fenced example blocks stripped; otherwise every scaffolded repo is missing them forever.\n'
gained_any=0
for entry in \
  "spec.md|.claude/productizer/spec.md" \
  "constitution.md|.claude/productizer/constitution.md" \
  "backlog.md|.claude/productizer/backlog.md" \
  "config.json|.claude/productizer/config.json" \
  "checks.yaml|.claude/productizer/checks.yaml" \
  "bands.yaml|.claude/productizer/bands.yaml" \
  "compliance-map.yaml|.claude/productizer/compliance-map.yaml" \
  "REVIEW.md|REVIEW.md" \
  "CLAUDE.md|CLAUDE.md" \
; do
  tplname="${entry%%|*}"; relp="${entry#*|}"
  tpl="$TEMPLATES/$tplname"; inst="$REPO/$relp"
  [ -f "$tpl" ] || continue
  if repo_file_state "$inst"; then :; else
    case "$?" in
      1) continue ;;
      *) UNMEASURED=$((UNMEASURED + 1))
         printf '  UNMEASURED: %s is present but is not a readable regular file (a symlink is refused rather than followed)\n' "$relp"
         continue ;;
    esac
  fi
  # `|| true` because diff exits 1 whenever the files differ, which is the
  # case being counted, and `set -o pipefail` would otherwise kill the run
  # having printed nothing.
  cmpto="$tpl"
  # `if`, not `grep ... && cmpto=...`: under `set -e` a bare `a && b` whose `a`
  # is false fails the whole run, and every template without an example block
  # takes that branch.
  if grep -q 'EXAMPLE:BEGIN' "$tpl"; then scaffolded_form "$tpl"; cmpto="$STRIPPED"; fi
  # stderr is NOT suppressed here, deliberately. `$cmpto` is `$STRIPPED` for
  # every template carrying an example block, and that is a temporary file this
  # script made - a shape that has already failed once, when `scaffolded_form`
  # returned through `$(...)` and its `mktemp -d` died with the subshell, so the
  # diff compared against a path that was gone. With stderr hidden that reads as
  # `gained=0`, which renders as NO DRIFT: a measurement nobody took, reported
  # as a clean result. So the file is checked before the diff and a missing one
  # is UNMEASURED, not zero.
  if [ ! -f "$cmpto" ] || [ ! -r "$cmpto" ]; then
    UNMEASURED=$((UNMEASURED + 1))
    printf '  UNMEASURED: %s could not be compared - the form to compare against (%s) is not a readable file. Not a finding of no drift.\n' \
      "$relp" "$cmpto"
    continue
  fi
  gained="$(diff -u -- "$inst" "$cmpto" | grep -c '^+[^+]' || true)"
  gained="${gained:-0}"
  [ "$gained" -gt 0 ] || continue
  gained_any=1
  DRIFT=$((DRIFT + 1))
  printf '  FINDING: %s - the template has %s line(s) this copy does not.\n' "$relp" "$gained"
  show_diff "$inst" "$cmpto"
done
[ "$gained_any" -eq 1 ] || printf '  held: no template carries content this repo'"'"'s copy is missing\n'
printf '\n'

# ---------------------------------------------------------------------------
# The verdict. Nothing was written, on any path above.
# ---------------------------------------------------------------------------
printf '  files examined: %d\n' "$EXAMINED"
printf '  findings: %d   dimensions unmeasured: %d\n' "$DRIFT" "$UNMEASURED"
printf '  NOTHING WAS CHANGED. Every finding above is for a person to apply, dismiss or defer.\n'

if [ "$UNMEASURED" -gt 0 ]; then
  printf '  At least one dimension could not be measured, so this list of differences is not the list of differences. Unknown is not absence.\n'
  exit 3
fi
if [ "$DRIFT" -gt 0 ]; then
  printf '  This repo is not running what the installed plugin ships.\n'
  exit 1
fi
printf '  Every dimension was measured, and this repo matches the plugin it has installed.\n'
exit 0
