#!/usr/bin/env bash
# scripts/run-checks.sh — run the declared checks stage against one change.
#
# The checks stage sits between build and deploy. It reads
# `.claude/productizer/checks.yaml` (see `templates/checks.yaml`), works out which
# declared checks this particular change attracts, runs them, and writes a
# machine-readable result the review stage consumes. It decides nothing itself:
# every check, every trigger and every threshold comes out of the config.
#
#   run-checks.sh --config .claude/productizer/checks.yaml \
#                 --changed changed-files.txt \
#                 --tags auth,pii \
#                 --out .claude/productizer/checks-result.json
#
#   --config PATH    the declaration, honoured exactly as typed: absolute, or
#                    relative to the working directory. Default, when omitted:
#                    `.claude/productizer/checks.yaml` under the git work tree
#                    holding the working directory, then under the one holding
#                    this script. The DEFAULT is deliberately not resolved
#                    against the working directory - that made the runner
#                    startable only from the repository root, and every root
#                    resolution below is downstream of this lookup.
#   --changed PATH   file of changed paths, one per line ("-" reads stdin).
#                    Looked for relative to the working directory first, which
#                    is what someone typing a path means, then under the
#                    repository root. A miss names both places searched.
#                    Its CONTENTS are read as a change set and are checked
#                    for being one: a line that is not there AND could never
#                    have been a path - whitespace in it, a leading `#`, a
#                    shell metacharacter - refuses the run and is quoted back.
#   --base REF       derive the changed paths from git diff against REF.
#                    The result records `change.base_ref` (REF as typed) and
#                    `change.base` (the full id of the merge base the diff was
#                    taken from). Under --changed both are null.
#   --tags LIST      comma-separated requirement tags carried by this change
#   --root DIR       repo root the checks run in, and what every relative path
#                    inside the config resolves against. Default: the git work
#                    tree holding the config — NOT the config's own directory,
#                    which for the default `.claude/productizer/checks.yaml`
#                    is two levels down and makes every relative tool path
#                    miss. Falls back to the config's directory only when
#                    there is no work tree. The root chosen, and how, is
#                    printed and recorded in the result.
#   --out PATH       where the result JSON lands ("-" for stdout).
#                    Default: policy.output from the config
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every blocking check passed and covered what it declared
#   3  REFUSED — a deliberate no. A blocking check failed, was hollow, timed
#      out, hit an exit code the config does not describe, or its tool is not
#      installed. Also: nothing triggered, under `policy.empty_run: refuse`
#   2  bad usage — missing arguments, or a config that cannot be parsed or
#      does not validate
#   1  crashed — this script could not reach a verdict
#
# 3 and 1 stay distinct because a gate that exits the same way when it says no
# as when it falls over is unreadable in a log, and the wrong thing gets fixed.
# Read a 1 as unverified, never as a pass.
#
# HOW IT FAILS CLOSED.
#
#   - An unparseable or invalid config is exit 2. It is never partially
#     honoured, because a half-read config silently drops checks.
#   - A declared tool that is not installed FAILS its check. It is never
#     skipped. Skipping is how a repo ends up with a green stage and no
#     scanner.
#   - An exit code the config does not map is a failure, not a pass. Vendors
#     add exit codes between releases; an unrecognised one means this file no
#     longer understands the tool.
#   - A check that examined nothing FAILS, whatever it printed and whatever it
#     returned. This is the point of the whole script; see the coverage
#     section of `references/checks.md`.
#   - A change set that is not a list of paths is exit 2, with the offending
#     line quoted. `--changed` handed a script was accepted and the script's
#     own source lines became the change under test; the result read like a
#     real run and the dashboard published it. Absence is NOT what is refused
#     - a file this change deleted is legitimately absent - only a line that
#     could never have been a path.
#   - The coverage denominator is derived from the spec, not from the check.
#     A check that shrinks what it claims does not shrink what it is measured
#     against: every active requirement in `policy.spec` gets a row, and a row
#     nothing covers is `Missing`, which refuses.
#   - A spec that cannot be read, or that holds no requirements, is reported
#     as UNMEASURED and refuses. It is never rendered as "0 units, all
#     covered": a denominator nobody could compute is not a denominator of 0.
#   - A configuration in which every check is `enabled: false` is exit 2. A
#     configuration with no active verification refuses to load rather than
#     exit 0 having verified nothing.
#   - Team-level settings — anything deciding what is examined or whether the
#     run blocks — are honoured only from the committed config. A
#     `<config>.local.<ext>` copy supplying one is ignored with a named
#     warning on stderr; only `timeout_seconds` is locally overridable.
#   - A check that could not run blocks whatever its severity. `advise`
#     softens a check's findings, never its absence.
#   - Every check's tool version is recorded in the result. A scanner that
#     silently stops working usually changes version first, and a version that
#     cannot be obtained fails the check.
#
# WAIVERS - A PERSON OVERRIDING A FAILING CHECK.
#
# `policy.waivers: <dir>` names a directory of waiver files (see
# `templates/waiver.md`). Each one records ONE failing check, the authority who
# overrode it, the reason, and the date it expires.
#
#   A WAIVER NEVER CHANGES THE MEASUREMENT. The check's `status` stays `fail`,
#   its findings stay in the result, and its coverage claims stay voided. What
#   a waiver changes is whether the run BLOCKS and how the line READS:
#   `FAIL - WAIVED BY <authority>`, never `PASS`. P1 is the whole reason: an
#   overridden check WAS measured, so recording the override is legitimate -
#   but a failure rendered green because somebody said so is a judgment
#   wearing a measurement's clothes.
#
#   ONLY A `fail` IS WAIVABLE. `missing_tool`, `timeout`, `no_version`,
#   `refused`, `unmapped_exit` and `hollow` are ABSENCES of measurement, and a
#   person cannot decide an absence away. A waiver naming one of those - or a
#   check that passed, or a disabled one, or one this change did not trigger -
#   is reported `not_applicable` and softens nothing.
#
#   P4 - A REPOSITORY BEING EXAMINED NEVER CHOOSES WHAT RUNS. Waiver files live
#   in the repository under examination, so a cloned repo that could waive its
#   own blocking checks would arrive with them already disarmed. Four bounds,
#   and the first is the load-bearing one:
#
#     1. OFF BY DEFAULT. With no `policy.waivers` key the directory is never
#        read, so a clone carrying `waivers/` waives nothing. Turning it on is
#        one reviewed line in `checks.yaml` - the same shape and the same
#        reasoning as `policy.allow_repo_local_tools`, and like every other
#        `policy` key it is honoured only from the committed config, never from
#        a `checks.local.yaml`.
#     2. IT SELECTS NOTHING. A waiver names no executable, no path and no argv.
#        Its `Check:` value is only ever compared against the ids the committed
#        config declares; one that matches nothing grants nothing and is
#        reported `unknown_check`. A waiver cannot widen what runs, only narrow
#        what blocks - by exactly one already-measured failure.
#     3. IT EXPIRES. `Expires:` is required. An unbounded waiver is a permanent
#        hole that outlives the person who wrote it and the finding it was
#        written for; an expired one stops softening and the check blocks again.
#     4. THE AUTHORITY IS A LABEL, NOT A CREDENTIAL. It is untrusted text a
#        stranger can write: it is collapsed to one printable line, truncated,
#        and rendered - never executed, never resolved as a path, never treated
#        as an instruction. It names WHO TO ASK. What actually authorises the
#        override is the reviewed commit that added the file, which is why the
#        result reports the waiver's LOCATION. The `Reason:` text is never
#        echoed anywhere: only whether one is recorded.
#
#   The residue is stated rather than hidden: someone who can land a commit in
#   a repo that has already opted in can waive that repo's own failing check
#   for the life of the expiry. That is the same power as editing `checks.yaml`
#   itself, it is visible in the diff, in the run's own output and in the
#   result file, and it is bounded by a date.
#
# WHAT IT DOES NOT DO.
#
#   - It does not judge whether the declared checks are the right ones. A
#     config declaring one weak check passes cleanly. Coverage assertions
#     police each check; only a human polices the list.
#   - It does not sandbox the tools it runs. Everything in `checks.yaml`
#     executes with this script's privileges, which is why the config is
#     argv-only and reviewed like code.
#   - A waiver does not restore what a failure voided. The waived check is
#     still `fail`, so every `spec_units` claim it made is still voided and the
#     requirement goes back to `Missing`. Under `policy.spec_coverage: require`
#     the run therefore still refuses - on the DENOMINATOR, not on the check.
#     That is deliberate: a waiver is a decision about one finding, not a
#     statement that the requirement is verified.
#   - Killing a check on timeout kills its process group. A tool that daemonises
#     out of that group survives.

set -euo pipefail
set -m   # own process group per background job, so a timeout kills the tree

VERSION_TIMEOUT=60

# 2 means "the caller or the config is wrong", and only argument parsing and
# the config parser are entitled to say it. Once PARSED is set, a 2 can only
# have come from a failing command inside this script, so it is rewritten to 1
# — a crash reported as bad usage sends someone to edit a config that was fine.
PARSED=""

# `measure` runs the checks stage. `selftest` drives THIS script as a subject
# and asserts the exit codes it produced; see the --selftest block below.
MODE="measure"

on_exit() {
  status=$?
  # --selftest does not run the stage at all, so the rewriting below does not
  # apply to it: its 1 means "a case did not produce the code it declares", and
  # relabelling that as "crashed before reaching a verdict" would report the
  # self-test's own finding as a fault in the runner.
  [ "$MODE" = measure ] || return
  case "$status" in
    0 | 3) ;;
    2) [ -z "$PARSED" ] || { printf 'run-checks: crashed with status 2 after the config was accepted. Unverified, not a pass.\n' >&2; exit 1; } ;;
    *)
      printf 'run-checks: exited %s before reaching a verdict. Treat this as unverified, not as a pass.\n' "$status" >&2
      exit 1
      ;;
  esac
}
trap on_exit EXIT

die_usage() { printf 'run-checks: %s\n' "$1" >&2; exit 2; }

# Echoes the git work tree containing $1, or nothing. git's own explanation is
# kept in GIT_WHY rather than discarded: a fallback that cannot say why it fell
# back is a fallback nobody can debug.
GIT_WHY=""
git_toplevel() {
  GIT_WHY=""
  if ! command -v git >/dev/null 2>&1; then
    GIT_WHY="git is not on PATH"
    return 1
  fi
  if [ ! -d "$1" ]; then
    GIT_WHY="$1 is not a directory"
    return 1
  fi
  _gt_err="$(mktemp "${TMPDIR:-/tmp}/run-checks-git.XXXXXX")"
  if _gt_top="$(git -C "$1" rev-parse --show-toplevel 2>"$_gt_err")" && [ -n "$_gt_top" ]; then
    rm -f "$_gt_err"
    printf '%s\n' "$_gt_top"
    return 0
  fi
  GIT_WHY="$(tr '\n' ' ' < "$_gt_err")"
  [ -n "$GIT_WHY" ] || GIT_WHY="git could not name a work tree"
  rm -f "$_gt_err"
  return 1
}

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

CONFIG=""
CHANGED=""
BASE=""
TAGS=""
ROOT=""
OUT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)  [ "$#" -ge 2 ] || die_usage "--config needs a path";  CONFIG="$2"; shift 2 ;;
    --changed) [ "$#" -ge 2 ] || die_usage "--changed needs a path"; CHANGED="$2"; shift 2 ;;
    --base)    [ "$#" -ge 2 ] || die_usage "--base needs a ref";     BASE="$2";    shift 2 ;;
    --tags)    [ "$#" -ge 2 ] || die_usage "--tags needs a list";    TAGS="$2";    shift 2 ;;
    --root)    [ "$#" -ge 2 ] || die_usage "--root needs a path";    ROOT="$2";    shift 2 ;;
    --out)     [ "$#" -ge 2 ] || die_usage "--out needs a path";     OUT="$2";     shift 2 ;;
    # Print the header block, however long it grows. A hardcoded line range
    # goes stale the first time someone adds a paragraph to it, and then the
    # help text stops mid-sentence and nobody notices.
    -h | --help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    # `--self-test` is an alias, not a second flag: this repository spells the
    # same obligation both ways and a tool that answers only one spelling reads
    # as carrying no self-test to whichever scanner is looking for the other.
    --selftest | --self-test) MODE="selftest"; shift ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

# ---------------------------------------------------------------------------
# --selftest - R39: THIS TOOL REACHES EACH EXIT CODE IT CAN RETURN, ON PURPOSE.
#
# Twelve cases: six of them one per way the contract at the top of this file
# can be reached, and six for the change set the runner is handed - the one
# shape that must be refused, and five for a path in it that is not in the
# tree. Eighteen assertions read the RESULT FILE rather than the exit code,
# because the last four cases are about a mechanism they share an exit code
# with: two of them exit 3, and so does `refused`; two exit 0, and so does
# `clean`.
# Each is driven through
# THIS script, so the argument handling, the change-set check, the config
# parser, the executor and the on_exit rewriting are all on the path. No case
# is asserted by reading source: the exit code is read off a real run.
#
#   clean         a config whose one check passes                      -> 0
#   refused       the same shape, whose one blocking check fails       -> 3
#   all-disabled  a config in which every check is `enabled: false`    -> 2
#   no-config     --config naming a file that is not there             -> 2
#   both-sources  --changed and --base given together                  -> 2
#   crashed       a result path under a directory this process is not
#                 allowed to create, which fails AFTER the config was
#                 accepted - the case on_exit rewrites to 1            -> 1
#   not-a-list    --changed handed a file whose lines are a shebang, a
#                 comment and a sentence rather than paths             -> 2
#   deleted       a change set naming a path that is NOT there because
#                 this change deleted it, which is legitimate and must
#                 still run                                            -> 0
#   deleted-in-scope
#                 the same, with the absent path INSIDE a per_file
#                 check's scope, so a tool would have been handed it   -> 0
#   deleted-under-base
#                 the same scope in a real git repository built here,
#                 a path committed then deleted, run under --base: the
#                 drop is labelled `deleted` by git's D list           -> 0
#   all-scope-gone
#                 every path in the one check's scope is gone: no
#                 scan at all, which is not a pass                     -> 3
#   all-gone-and-no-tool
#                 the same, with the tool absent too: the absent
#                 tool is the fact that must be reported               -> 3
#
# IT NEVER RUNS THE DECLARED SUITE OVER THIS REPOSITORY. That takes minutes and
# writes over `policy.output`, so a self-test that did it would be slower than
# the thing it tests and would rewrite a committed file every time anyone
# probed it. The corpus is a handful of files, five configs and one two-commit
# git repository, all built under mktemp, and the only tool any config names is
# grep (or one that is deliberately not installed).
#
# THE CLEAN CASE GUARDS THE OTHERS' PREMISE. If a config whose one check passes
# does not exit 0, every case below would be red for that reason rather than
# its own - exit 2 for the whole self-test, never a pass on the five that
# followed.
#
# THE `crashed` CASE HAS A PREMISE OF ITS OWN, and it is the one that fails
# quietly: root creates a directory inside a mode-500 parent without complaint,
# and the case would then exit 0 and be reported as not holding rather than as
# never having been exercised. So the sandbox is probed by TRYING THE WRITE,
# not by reading the mode bits, and a probe that succeeds is exit 2.
#
# NOTHING IS WRITTEN INTO THE REPOSITORY. Every config, every scanned file and
# every result lands under mktemp, and the directory goes on every exit path,
# signal included.
#
# WHAT THIS SELF-TEST DOES NOT ASSERT, printed rather than passed silently: it
# reads the exit CODE and never the content of the result file, so a run that
# reached the right code by the wrong route is invisible here.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  self_unmeasured() { printf 'run-checks: --selftest: %s\n' "$1" >&2; exit 2; }

  command -v python3 >/dev/null 2>&1 || self_unmeasured "python3 is not on PATH, so no case could be driven at all"  # stderr-ok: a presence probe whose EXIT STATUS is the whole answer, and the absence is reported in words by the self_unmeasured on this same line
  command -v grep >/dev/null 2>&1 || self_unmeasured "grep is not on PATH, and every fixture check is a grep - every case would report missing_tool and none would be the case it was written to be"  # stderr-ok: same probe, same reason, and the absence is reported in words on this same line

  SB="$(mktemp -d "${TMPDIR:-/tmp}/run-checks-selftest.XXXXXX")" \
    || self_unmeasured "cannot create a temporary directory to build the corpus in; nothing was driven"
  # The mode-500 directory is put back to writable first: `rm -rf` over a tree
  # holding one is fine here and is not on every platform, and a trap that
  # depends on that leaves a directory behind where it is not.
  trap 'chmod -R u+rwX "$SB" 2>/dev/null || :; rm -rf "$SB"' EXIT HUP INT TERM  # stderr-ok: a best-effort mode reset on the way out, whose failure is already handled by the `|| :` beside it; its stderr would name a temporary path in a committed log

  mkdir -p "$SB/fixture"
  printf 'this file does not hold the needle\n'  > "$SB/fixture/finding.txt"
  printf 'RUN-CHECKS-SELFTEST-NEEDLE\n'          > "$SB/fixture/clean.txt"
  printf 'fixture/clean.txt\n'                   > "$SB/changed-clean.txt"
  printf 'fixture/finding.txt\n'                 > "$SB/changed-finding.txt"
  # NOT a change set: the first three lines of a shell script. This is the
  # shape that was accepted, recorded and published - see the change-set block
  # further down - so the corpus holds it verbatim rather than a tidied stand-in.
  printf '#!/usr/bin/env bash\n# a comment, not a path\nthis is not a file at all\n' \
    > "$SB/changed-not-a-list.txt"
  # A change set with a DELETION in it. The second path is created and then
  # removed, so it is absent for the same reason a deleted file is absent, and
  # the run must still reach a verdict over the file that is there.
  printf 'fixture/clean.txt\nfixture/deleted-by-this-change.txt\n' > "$SB/changed-deleted.txt"
  printf 'gone\n' > "$SB/fixture/deleted-by-this-change.txt"
  rm -f "$SB/fixture/deleted-by-this-change.txt"
  # A deleted path INSIDE A CHECK'S SCOPE, which is the case the `deleted`
  # case above states it does not reach: its absent path matches no check's
  # `paths`, so no tool was ever asked to open it and the run could not tell a
  # dropped path from one nobody wanted. These two files are both matched by
  # one glob, one of them is removed, and the check is per_file - so without
  # the drop the tool IS handed the absent path and refuses, which is the
  # whole defect. Measured on this repository before the fix: `shell-lint`
  # and `stderr-suppression` both came back REFUSED against a change set
  # spanning the root commit, and a refused check catches no regression.
  mkdir -p "$SB/fixture/scope"
  printf 'RUN-CHECKS-SELFTEST-NEEDLE\n' > "$SB/fixture/scope/kept.txt"
  printf 'RUN-CHECKS-SELFTEST-NEEDLE\n' > "$SB/fixture/scope/gone.txt"
  rm -f "$SB/fixture/scope/gone.txt"
  printf 'fixture/scope/kept.txt\nfixture/scope/gone.txt\n' > "$SB/changed-scope.txt"
  # EVERY path in the one check's scope is gone. An empty list is not a small
  # scan, it is no scan, and the run must not read as a pass.
  printf 'fixture/scope/gone.txt\n' > "$SB/changed-scope-all-gone.txt"

  # PREMISE. The scanned files must really differ in the needle, or `clean` and
  # `refused` are the same case twice and one of them is reported as a
  # regression the first time somebody edits the fixture above.
  if grep -q RUN-CHECKS-SELFTEST-NEEDLE "$SB/fixture/finding.txt"; then
    self_unmeasured "the fixture's finding file holds the needle, so its check would pass and there would be no refusal to observe. Unmeasured, not a pass"
  fi
  if grep -q RUN-CHECKS-SELFTEST-NEEDLE "$SB/fixture/clean.txt"; then :; else
    self_unmeasured "the fixture's clean file does not hold the needle, so its check would fail and the clean case would stop being clean. Unmeasured, not a pass"
  fi
  # PREMISE for the `deleted` case. If the removal did not take, the case is a
  # change set of two files that are both there - the clean case a second time
  # - and it would pass without ever asking about an absent path.
  if [ -e "$SB/fixture/deleted-by-this-change.txt" ]; then
    self_unmeasured "the path the deleted case names is still there, so nothing absent was ever handed to the runner. Unmeasured, not a pass"
  fi
  # PREMISE for the two in-scope cases. If the removal did not take, the scope
  # holds two present files and the drop is never exercised; if the surviving
  # file lost the needle, its check fails and the case goes red for a reason
  # that is not the one it was written to observe.
  if [ -e "$SB/fixture/scope/gone.txt" ]; then
    self_unmeasured "the in-scope path that must be absent is still there, so no tool was ever at risk of being handed one. Unmeasured, not a pass"
  fi
  if grep -q RUN-CHECKS-SELFTEST-NEEDLE "$SB/fixture/scope/kept.txt"; then :; else
    self_unmeasured "the surviving in-scope file does not hold the needle, so its check would fail on its content and the case would stop being about the absent path. Unmeasured, not a pass"
  fi

  # One check, one file, one tool, `spec_coverage` off so no spec has to exist
  # beside it and `allow_repo_local_tools` left at its default so nothing
  # repo-local is selected by a config this script wrote.
  cat > "$SB/checks-pass.yaml" <<'SELFTEST_CFG_PASS'
version: 1
policy:
  empty_run: refuse
  spec_coverage: "off"
defaults:
  timeout_seconds: 30
  mode: per_file
  severity: block
checks:
  - id: clean
    why: the file it scans holds the needle, so this check passes and the run reaches a verdict
    when:
      paths: ["fixture/clean.txt"]
    severity: block
    requires: [grep]
    version_command: [grep, --version]
    mode: per_file
    command: [grep, -q, RUN-CHECKS-SELFTEST-NEEDLE, "{file}"]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
    coverage:
      from: per_file_exit
      examined_when_exit_in: [0, 1]
      must_cover: all_triggering
      min_covered: 1
SELFTEST_CFG_PASS

  cat > "$SB/checks-fail.yaml" <<'SELFTEST_CFG_FAIL'
version: 1
policy:
  empty_run: refuse
  spec_coverage: "off"
defaults:
  timeout_seconds: 30
  mode: per_file
  severity: block
checks:
  - id: finding
    why: the file it scans does not hold the needle, so this blocking check reports a real measured finding and the run must refuse
    when:
      paths: ["fixture/finding.txt"]
    severity: block
    requires: [grep]
    version_command: [grep, --version]
    mode: per_file
    command: [grep, -q, RUN-CHECKS-SELFTEST-NEEDLE, "{file}"]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
    coverage:
      from: per_file_exit
      examined_when_exit_in: [0, 1]
      must_cover: all_triggering
      min_covered: 1
SELFTEST_CFG_FAIL

  cat > "$SB/checks-off.yaml" <<'SELFTEST_CFG_OFF'
version: 1
policy:
  empty_run: refuse
  spec_coverage: "off"
defaults:
  timeout_seconds: 30
  mode: per_file
  severity: block
checks:
  - id: clean
    enabled: false
    why: every check in this configuration is switched off, which is a load error and not a clean pass
    when:
      paths: ["fixture/clean.txt"]
    severity: block
    requires: [grep]
    version_command: [grep, --version]
    mode: per_file
    command: [grep, -q, RUN-CHECKS-SELFTEST-NEEDLE, "{file}"]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
    coverage:
      from: per_file_exit
      examined_when_exit_in: [0, 1]
      must_cover: all_triggering
      min_covered: 1
SELFTEST_CFG_OFF

  # One check whose `paths` glob matches BOTH in-scope files, so the absent one
  # is inside the scope rather than beside it. per_file, so the executor would
  # substitute that path straight into argv.
  cat > "$SB/checks-scope.yaml" <<'SELFTEST_CFG_SCOPE'
version: 1
policy:
  empty_run: refuse
  spec_coverage: "off"
defaults:
  timeout_seconds: 30
  mode: per_file
  severity: block
checks:
  - id: scoped
    why: its paths glob matches a file that is there and one that is not, so the absent path is inside this check's scope and would be handed to the tool unless the runner drops it
    when:
      paths: ["fixture/scope/*.txt"]
    severity: block
    requires: [grep]
    version_command: [grep, --version]
    mode: per_file
    command: [grep, -q, RUN-CHECKS-SELFTEST-NEEDLE, "{file}"]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
    coverage:
      from: per_file_exit
      examined_when_exit_in: [0, 1]
      must_cover: all_triggering
      min_covered: 1
SELFTEST_CFG_SCOPE

  # BOTH CONCLUSIONS AT ONCE: the tool is absent AND every path in the scope is
  # gone. They compete, and `missing_tool` must win - it is the earlier and
  # larger fact, true whatever the file list holds, and R13 is stated over it.
  # This case exists because the first version of the drop wrote its status
  # before the executor looked for the tool, and `fixtures/missing-tool` and
  # `fixtures/fabricated-zero` - whose one changed path is never created - both
  # came back as the drop instead, taking R13's check red. The self-test could
  # not see that; now it can.
  cat > "$SB/checks-gone-no-tool.yaml" <<'SELFTEST_CFG_GONE_NO_TOOL'
version: 1
policy:
  empty_run: refuse
  spec_coverage: "off"
defaults:
  timeout_seconds: 30
  mode: per_file
  severity: block
checks:
  - id: scoped
    why: its tool is absent on every machine and every path in its scope is gone, so both conclusions are available at once and the absent tool is the one that must be reported
    when:
      paths: ["fixture/scope/*.txt"]
    severity: block
    requires: [definitely-not-a-real-tool]
    version_command: [definitely-not-a-real-tool, --version]
    mode: per_file
    command: [definitely-not-a-real-tool, "{file}"]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
    coverage:
      from: per_file_exit
      examined_when_exit_in: [0, 1]
      must_cover: all_triggering
      min_covered: 1
SELFTEST_CFG_GONE_NO_TOOL

  # PREMISE. If somebody has installed a tool by this name the case stops being
  # about an absent one and quietly becomes a second copy of `all-scope-gone`.
  if command -v definitely-not-a-real-tool >/dev/null 2>&1; then  # stderr-ok: a presence probe whose EXIT STATUS is the whole answer, and the finding is reported in words on the next line
    self_unmeasured "a tool named definitely-not-a-real-tool is installed on this machine, so the case that must report an absent tool has a present one. Unmeasured, not a pass"
  fi

  mkdir -p "$SB/locked"
  chmod 500 "$SB/locked"
  # PREMISE, PROBED BY TRYING IT. Root makes a directory inside a mode-500
  # parent and never says a word, and the crashed case would then exit 0.
  if mkdir "$SB/locked/probe" 2>/dev/null; then  # stderr-ok: the probe ASKS whether the sandbox is really unwritable and the permission error IS the expected answer; the failure to be unwritable is reported in words on the next line
    rmdir "$SB/locked/probe"
    chmod -R u+rwX "$SB"
    self_unmeasured "a directory this self-test made unwritable can still be written to - running as root will do that - so the crash after the config was accepted was never reached. Unmeasured, not a pass"
  fi

  # A REAL GIT REPOSITORY, for the one case that runs under --base. Commit 1
  # holds `gone.txt`; commit 2 deletes it and adds `kept.txt`. Against HEAD~1
  # the diff is one addition and one deletion, both inside `fixture/scope/*.txt`.
  # The fixture's own git commands run with the user's and the system's git
  # config switched off, so a signing requirement or a hook on this machine
  # cannot make the corpus different from the one written here; the RUNNER is
  # not isolated that way, because it is the thing under test.
  command -v git >/dev/null 2>&1 || self_unmeasured "git is not on PATH, so the --base case that drives the deleted label cannot be built"  # stderr-ok: a presence probe whose EXIT STATUS is the whole answer, and the absence is reported in words on this same line
  fixture_git() {
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
      git -C "$SB/repo" -c user.name=selftest -c user.email=selftest@example.invalid \
      -c commit.gpgsign=false -c init.defaultBranch=main "$@" >> "$SB/repo-build.log" 2>&1
  }
  # THE TWO FILES MUST NOT LOOK ALIKE TO GIT. Measured: with identical content,
  # git's default rename detection reports commit 2 as `gone.txt -> kept.txt`,
  # `--name-only` lists only `kept.txt`, `--diff-filter=D` lists nothing, and
  # the case silently stops being about a deletion. So `gone.txt` holds text
  # that shares no line with `kept.txt`, and `files_in_scope 2` below turns a
  # rename collapse into a finding rather than a pass.
  mkdir -p "$SB/repo/fixture/scope"
  { fixture_git init -q &&
    printf 'this file is committed once and deleted in the next commit\nit shares no line with the file that survives\n' > "$SB/repo/fixture/scope/gone.txt" &&
    fixture_git add fixture/scope/gone.txt &&
    fixture_git commit -q -m one &&
    printf 'RUN-CHECKS-SELFTEST-NEEDLE\n' > "$SB/repo/fixture/scope/kept.txt" &&
    fixture_git add fixture/scope/kept.txt &&
    fixture_git rm -q fixture/scope/gone.txt &&
    fixture_git commit -q -m two; } ||
    self_unmeasured "the fixture git repository could not be built, so the --base case was never driven. Unmeasured, not a pass"
  GIT_BASE_REF="HEAD~1"
  GIT_BASE_SHA="$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$SB/repo" rev-parse --verify "$GIT_BASE_REF^{commit}")" ||
    self_unmeasured "the fixture repository has no $GIT_BASE_REF, so there is no base to diff against. Unmeasured, not a pass"
  # PREMISE, read off the TREES and not off `--diff-filter=D`, which is the
  # query under test: the path is in the base commit, not in HEAD, and not on
  # disk. Any one of those false and the case stops being about a deletion.
  if GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$SB/repo" cat-file -e "$GIT_BASE_REF:fixture/scope/gone.txt" >> "$SB/repo-build.log" 2>&1 &&
     ! GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$SB/repo" cat-file -e "HEAD:fixture/scope/gone.txt" >> "$SB/repo-build.log" 2>&1 &&
     [ ! -e "$SB/repo/fixture/scope/gone.txt" ]; then :; else
    self_unmeasured "the fixture repository does not hold gone.txt at the base and lack it at HEAD, so nothing was deleted in the range. Unmeasured, not a pass"
  fi

  SELF_CASES=0
  SELF_FAILED=0
  # Assertions read off a RESULT FILE rather than off an exit code. Counted
  # apart from the driven cases because they drive nothing and reach no exit
  # code of their own - a run that reached the right code by the wrong route is
  # invisible to a case and visible to one of these. They fail the self-test
  # through the same SELF_FAILED the cases use, so no new exit code appears.
  SELF_ASSERTS=0
  # R39.b: the reached half of the declaration below is ACCUMULATED here, one
  # entry per case as it ran - including the clean case, which is driven
  # outside self_drive because it guards the others' premise. A literal list
  # would satisfy the reader and prove nothing.
  CODES=""

  # $1 case, $2 expected exit, $3 what the case is, then the argv to drive.
  #
  # `|| _rc=$?` on the SAME LINE as the command. Five of the six cases exit
  # non-zero on purpose, `set -e` would end the run at the first one, and a
  # `$(...)` or a pipeline between the command and the read of `$?` resets it -
  # which is how a self-test reports six passes having measured none.
  self_drive() {
    _name="$1"; _want="$2"; _why="$3"
    shift 3
    _rc=0
    bash "$0" "$@" > "$SB/$_name.out" 2> "$SB/$_name.err" || _rc=$?
    SELF_CASES=$((SELF_CASES + 1))
    CODES="$CODES$_rc
"
    if [ "$_rc" = "$_want" ]; then
      printf '  held:    case %-13s expected %s  observed %s  %s\n' "$_name" "$_want" "$_rc" "$_why"
    else
      printf '  FINDING: case %-13s expected %s  observed %s  %s\n' "$_name" "$_want" "$_rc" "$_why"
      SELF_FAILED=$((SELF_FAILED + 1))
    fi
  }

  # $1 result file, $2 key on the first check row, $3 the value it must hold
  # rendered as JSON, $4 what that asserts. The comparison is a `==` between
  # two parsed JSON values and NOTHING IS EVALUATED - no expression string is
  # handed to python, because a check in this repository's own suite exists to
  # stop a config choosing what this runner executes, and a self-test that
  # eval()s a string would be the same shape one file over.
  self_assert() {
    _file="$1"; _key="$2"; _want="$3"; _what="$4"
    SELF_ASSERTS=$((SELF_ASSERTS + 1))
    _got="$(python3 - "$_file" "$_key" "$_want" <<'SELFTEST_ASSERT'
import json, sys
path, key, want = sys.argv[1:4]
try:
    doc = json.load(open(path))
except (OSError, ValueError) as exc:
    print("the result file could not be read: %s" % exc)
    raise SystemExit(0)
rows = doc.get("checks") or []
if not rows:
    print("the result holds no check rows at all")
    raise SystemExit(0)
row = rows[0]
if key not in row:
    print("the row has no `%s` key; it holds %s" % (key, ", ".join(sorted(row))))
    raise SystemExit(0)
print("held" if row[key] == json.loads(want)
      else "%s is %s, not %s" % (key, json.dumps(row[key]), want))
SELFTEST_ASSERT
)"
    if [ "$_got" = "held" ]; then
      printf '  held:    assert %-20s %s\n' "$_key" "$_what"
    else
      printf '  FINDING: assert %-20s %s - %s\n' "$_key" "$_what" "$_got"
      SELF_FAILED=$((SELF_FAILED + 1))
    fi
  }

  # The same, for a key in the result's `change` object rather than on a check
  # row. Same rules: two parsed JSON values compared with `==`, nothing
  # evaluated. A missing key is a finding and never read as null, because
  # "the runner did not write it" and "the runner wrote null" are the two
  # things `change.base` exists to tell apart.
  self_assert_change() {
    _file="$1"; _key="$2"; _want="$3"; _what="$4"
    SELF_ASSERTS=$((SELF_ASSERTS + 1))
    _got="$(python3 - "$_file" "$_key" "$_want" <<'SELFTEST_ASSERT_CHANGE'
import json, sys
path, key, want = sys.argv[1:4]
try:
    doc = json.load(open(path))
except (OSError, ValueError) as exc:
    print("the result file could not be read: %s" % exc)
    raise SystemExit(0)
change = doc.get("change")
if not isinstance(change, dict):
    print("the result holds no `change` object")
    raise SystemExit(0)
if key not in change:
    print("`change` has no `%s` key; it holds %s" % (key, ", ".join(sorted(change))))
    raise SystemExit(0)
print("held" if change[key] == json.loads(want)
      else "change.%s is %s, not %s" % (key, json.dumps(change[key]), want))
SELFTEST_ASSERT_CHANGE
)"
    if [ "$_got" = "held" ]; then
      printf '  held:    assert %-20s %s\n' "change.$_key" "$_what"
    else
      printf '  FINDING: assert %-20s %s - %s\n' "change.$_key" "$_what" "$_got"
      SELF_FAILED=$((SELF_FAILED + 1))
    fi
  }

  SELF_RC=0
  bash "$0" --config "$SB/checks-pass.yaml" --root "$SB" \
    --changed "$SB/changed-clean.txt" --out "$SB/clean.json" \
    > "$SB/clean.out" 2> "$SB/clean.err" || SELF_RC=$?
  if [ "$SELF_RC" -ne 0 ]; then
    printf '  the clean case exited %d, not 0.\n' "$SELF_RC"
    self_unmeasured "a configuration whose one check passes did not produce a clean run, so every case below would be red for that reason instead of its own. Unmeasured, not a corpus that held"
  fi
  SELF_CASES=1
  CODES="$CODES$SELF_RC
"
  printf '  held:    case %-13s expected %s  observed %s  %s\n' "clean" "0" "0" \
    "one blocking check, it passes, and it covered the file it was given"

  self_drive refused 3 \
    "one blocking check and it fails: a deliberate no, which is 3 and never 1" \
    --config "$SB/checks-fail.yaml" --root "$SB" \
    --changed "$SB/changed-finding.txt" --out "$SB/refused.json"
  self_drive all-disabled 2 \
    "every declared check is switched off: a load error, because the run would otherwise exit 0 having verified nothing" \
    --config "$SB/checks-off.yaml" --root "$SB" \
    --changed "$SB/changed-clean.txt" --out "$SB/off.json"
  self_drive no-config 2 \
    "--config names a file that is not there: the stage is declared in a file and there is no built-in list to fall back on" \
    --config "$SB/there-is-no-config-here.yaml" --root "$SB" \
    --changed "$SB/changed-clean.txt"
  self_drive both-sources 2 \
    "--changed and --base together: two sources for one change set disagree silently, so neither is honoured" \
    --config "$SB/checks-pass.yaml" --root "$SB" \
    --changed "$SB/changed-clean.txt" --base HEAD
  self_drive crashed 1 \
    "the result cannot be written, which fails after the config was accepted: unverified, and reported as 1 rather than as the 2 that would send a reader to edit a config that was fine" \
    --config "$SB/checks-pass.yaml" --root "$SB" \
    --changed "$SB/changed-clean.txt" --out "$SB/locked/sub/result.json"

  self_drive not-a-list 2 \
    "--changed handed a file that is not a list of paths: a shebang, a comment and a sentence. Believing it makes every line a changed file and writes a result that reads like a real run" \
    --config "$SB/checks-pass.yaml" --root "$SB" \
    --changed "$SB/changed-not-a-list.txt" --out "$SB/not-a-list.json"
  self_drive deleted 0 \
    "a change set naming a path this change deleted: absent, path-shaped and legitimate, so the run still reaches a verdict over what is there" \
    --config "$SB/checks-pass.yaml" --root "$SB" \
    --changed "$SB/changed-deleted.txt" --out "$SB/deleted.json"

  # THE CASE THE `deleted` CASE ABOVE SAYS IT DOES NOT REACH. Here the absent
  # path is INSIDE the one check's scope, the check is per_file, and without
  # the drop the executor substitutes that path into argv and grep exits 2 -
  # refused, blocking, exit 3. The assertions under it read the result file, so
  # the case pins the MECHANISM and not only the code: what was handed over,
  # what was dropped, and under which label.
  self_drive deleted-in-scope 0 \
    "a deleted path inside a check's scope, in per_file mode: dropped before argv, so the check runs over what survives instead of being handed a path no tool can open" \
    --config "$SB/checks-scope.yaml" --root "$SB" \
    --changed "$SB/changed-scope.txt" --out "$SB/scope.json"
  self_assert "$SB/scope.json" status '"pass"' \
    "the check RAN over the surviving file - it is not refused, which is what being handed the absent path produced"
  self_assert "$SB/scope.json" files_in_scope 2 \
    "the declared scope is still both files: the drop shrinks what is handed over, never what is demanded"
  self_assert "$SB/scope.json" files_handed_over 1 \
    "exactly one path reached a command line"
  self_assert "$SB/scope.json" files_dropped_absent '["fixture/scope/gone.txt"]' \
    "the dropped path is NAMED, and labelled absent rather than deleted, because --changed has no second source that could corroborate a deletion"
  self_assert "$SB/scope.json" files_dropped_deleted '[]' \
    "nothing is called deleted on a run that cannot know that it was"
  self_assert_change "$SB/scope.json" base 'null' \
    "a --changed run records no base: the list was diffed against nothing this runner can name, and HEAD would be invented"
  self_assert_change "$SB/scope.json" base_ref 'null' \
    "and no ref either"

  # THE `deleted` LABEL, DRIVEN. The same scope and the same per_file check,
  # but in a real git repository and under --base, which is the only mode with
  # a second source. The in-scope path was COMMITTED and then DELETED in a
  # later commit, so `git diff --diff-filter=D` against the first commit names
  # it - and the drop must be labelled `deleted`, with `dropped_source` naming
  # git, where the --changed case above labels the same shape `absent`.
  self_drive deleted-under-base 0 \
    "a path committed and then deleted in a real repository, run under --base: dropped before argv, and corroborated by git as deleted rather than merely absent" \
    --config "$SB/checks-scope.yaml" --root "$SB/repo" \
    --base "$GIT_BASE_REF" --out "$SB/git-deleted.json"
  self_assert "$SB/git-deleted.json" status '"pass"' \
    "the check RAN over the surviving file"
  self_assert "$SB/git-deleted.json" files_in_scope 2 \
    "git's diff named both paths - a rename collapse would have made this 1 and hidden the deletion"
  self_assert "$SB/git-deleted.json" files_handed_over 1 \
    "exactly one path reached a command line"
  self_assert "$SB/git-deleted.json" files_dropped_deleted '["fixture/scope/gone.txt"]' \
    "the dropped path is labelled DELETED, because git named it removed in the range"
  self_assert "$SB/git-deleted.json" files_dropped_absent '[]' \
    "and it is not also called absent"
  self_assert "$SB/git-deleted.json" dropped_source "\"git diff --diff-filter=D against $GIT_BASE_REF\"" \
    "the label says git is where it came from, and against which ref"
  self_assert_change "$SB/git-deleted.json" base "\"$GIT_BASE_SHA\"" \
    "change.base is the full commit id the diff was taken from, read back from the fixture repository by rev-parse"
  self_assert_change "$SB/git-deleted.json" base_ref "\"$GIT_BASE_REF\"" \
    "change.base_ref is the ref exactly as typed"

  # EVERY path in scope gone. Without the guard the drop leaves an empty list,
  # per_file iterates zero times, and the executor's `worst` stays at its
  # initial 0 - a PASS over a set nothing opened.
  self_drive all-scope-gone 3 \
    "every path in the check's scope is gone: an empty list is no scan, so the check is recorded as unable to run and blocks, rather than passing over nothing" \
    --config "$SB/checks-scope.yaml" --root "$SB" \
    --changed "$SB/changed-scope-all-gone.txt" --out "$SB/all-gone.json"
  self_assert "$SB/all-gone.json" status '"nothing_to_examine"' \
    "the row says why it could not run, and is neither a pass nor a refusal - nothing refused anything, because no tool was invoked"
  self_assert "$SB/all-gone.json" files_handed_over 0 \
    "no path reached a command line"

  self_drive all-gone-and-no-tool 3 \
    "the tool is absent AND every path in scope is gone: the absent tool is the earlier and larger fact, so that is what is reported" \
    --config "$SB/checks-gone-no-tool.yaml" --root "$SB" \
    --changed "$SB/changed-scope-all-gone.txt" --out "$SB/gone-no-tool.json"
  self_assert "$SB/gone-no-tool.json" status '"missing_tool"' \
    "an absent tool outranks an empty file list - R13 is stated over the tool, and a drop that reported itself first took R13 red once already"

  printf '  self-test cases driven: %d, result-file assertions: %d. Cases and assertions that did not hold: %d\n' \
    "$SELF_CASES" "$SELF_ASSERTS" "$SELF_FAILED"

  # The R39.b declaration. The reached half is computed from the cases above;
  # the documented half is the four-code contract at the top of this file.
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2 3; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '  exit codes reached: %s   documented: 0 1 2 3\n' "$REACHED"
  printf '  NOT ASSERTED for the first eight cases: the content of the result file. Each of those reads the exit CODE only, so a run that reached the right code by the wrong route is invisible and is read off the case output by hand. The last four cases are the exception - eighteen assertions read their result files, because `all-scope-gone` and `all-gone-and-no-tool` share exit 3 with `refused` and with each other, `deleted-in-scope` and `deleted-under-base` share exit 0 with `clean` and with each other, and the code alone cannot tell any of them apart.\n'
  printf '  NOW ASSERTED, and this line used to say it was not: the `deleted` case alone proves only that an absent path was ACCEPTED, because the path it names falls outside the one check scope and no tool was asked to open it. `deleted-in-scope` puts an absent path INSIDE a per_file check scope, where the executor would have substituted it into argv, and five assertions read off the result file: the check ran, the scope is still 2, one path was handed over, the dropped one is named, and it is labelled absent and not deleted.\n'
  printf '  NOW ASSERTED, and this line used to say it was not: the `deleted` LABEL, and the git query that produces it. `deleted-under-base` builds a two-commit git repository, deletes an in-scope path in the second commit and runs under --base HEAD~1; assertions read off the result file that git named both paths, one was handed over, the drop is labelled deleted and not absent, dropped_source names git and the ref, and change.base / change.base_ref record the commit and the ref. The --changed case asserts both are null.\n'
  printf '  NOT ASSERTED: a --base whose ref is NOT an ancestor of HEAD, where change.base (the merge base) and `git rev-parse <ref>` differ; and a deletion git reports as a RENAME, where --name-only and --diff-filter=D both omit the old path, so it is neither handed over nor dropped nor labelled.\n'
  if [ "$SELF_FAILED" -ne 0 ]; then
    printf 'run-checks: %d self-test case(s) did not produce the exit code the contract declares for them.\n' "$SELF_FAILED" >&2
    exit 1
  fi
  if [ -n "$MISSING" ]; then
    printf 'run-checks: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  printf '  R39 for this tool: the self-test exists and reaches 0, 1, 2 and 3 by driving the real runner over a corpus built for it, not by reading its source and not by running the declared suite.\n'
  exit 0
fi

# WHERE THE DEFAULT CONFIG IS LOOKED FOR.
#
# `.claude/productizer/checks.yaml` is a path relative to the REPOSITORY, not
# to wherever the caller happens to be standing. Resolving it against the
# working directory meant the runner could only ever be started from the repo
# root: from a subdirectory it reported "no config" and stopped - and every
# root resolution below is downstream of this lookup, so a fix there was never
# reached. An explicit --config is a different thing: someone typed it, so it
# is honoured exactly as typed.
DEFAULT_CONFIG_REL=".claude/productizer/checks.yaml"
CONFIG_WHY=""
if [ -n "$CONFIG" ]; then
  CONFIG_SOURCE="--config, given on the command line"
elif TOP="$(git_toplevel "$PWD")" && [ -f "$TOP/$DEFAULT_CONFIG_REL" ]; then
  CONFIG="$TOP/$DEFAULT_CONFIG_REL"
  CONFIG_SOURCE="the default, under the git work tree holding the working directory"
elif TOP="$(git_toplevel "$SELF_DIR")" && [ -f "$TOP/$DEFAULT_CONFIG_REL" ]; then
  CONFIG="$TOP/$DEFAULT_CONFIG_REL"
  CONFIG_SOURCE="the default, under the git work tree holding this script"
else
  CONFIG="$DEFAULT_CONFIG_REL"
  CONFIG_SOURCE="the default, relative to the working directory"
  CONFIG_WHY=" No git work tree holding the working directory or this script has one: ${GIT_WHY}"
fi
[ -f "$CONFIG" ] || die_usage "no config at $CONFIG ($CONFIG_SOURCE).${CONFIG_WHY} The checks stage is declared in a file; there is no built-in list to fall back on."

command -v python3 >/dev/null 2>&1 ||
  die_usage "python3 is not on PATH, so the config cannot be read. Refusing rather than guessing what was declared."

CONFIG_ABS="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"

# WHERE EVERY RELATIVE PATH IN THE CONFIG RESOLVES FROM.
#
# The config's own directory is NOT the repository root, and treating it as one
# was a real bug. The default config lives at `.claude/productizer/checks.yaml`,
# so `dirname` yields `.claude/productizer`; every relative path in the file
# then resolved against that. `./scripts/check-hygiene.sh` in `requires`
# reported `missing_tool` for a tool that was present and executable,
# the shell linter could not open the files it was handed, `policy.output` wrote
# `.claude/productizer/.claude/productizer/checks-result.json` — a nested
# shadow of the config directory, outside anything anyone intended.
#
# A manufactured `missing_tool` is a false absence, which is the one thing this
# whole stage exists to refuse; and it is worse now that a check which cannot
# run blocks whatever its severity. So anchor to the work tree, and say out
# loud which anchor was used: a runner that quietly picks a different root than
# the reader assumes makes every path below it confidently wrong at once.
ROOT_SOURCE="--root, given on the command line"
if [ -z "$ROOT" ]; then
  if ROOT="$(git_toplevel "$(dirname "$CONFIG_ABS")")"; then
    ROOT_SOURCE="the git work tree holding the config"
  else
    ROOT="$(dirname "$CONFIG_ABS")"
    ROOT_SOURCE="the config's own directory, because there is no git work tree: ${GIT_WHY%% }"
  fi
fi
[ -d "$ROOT" ] || die_usage "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/run-checks.XXXXXX")"
cleanup() { [ -n "${KEEP_WORK:-}" ] || rm -rf "$WORK"; }
trap 'cleanup' HUP INT TERM

# --- the change under test ------------------------------------------------

if [ -n "$CHANGED" ] && [ -n "$BASE" ]; then
  die_usage "--changed and --base both given. Pick one source for the change; two disagree silently."
fi

if [ -n "$CHANGED" ]; then
  if [ "$CHANGED" = "-" ]; then
    cat > "$WORK/changed.txt"
  else
    # Someone typing a relative path means it relative to where they are
    # standing, so that is tried first. But the documented invocation names a
    # file that lives in the repository, and from a subdirectory that used to
    # be reported as "does not exist" while the file sat at the root. Fall back
    # to ROOT, and when neither holds it, name both places searched - a
    # not-found that will not say where it looked sends people to recreate a
    # file they already have.
    if [ -f "$CHANGED" ]; then
      CHANGED_SRC="$CHANGED"
    elif [ -f "$ROOT/$CHANGED" ]; then
      CHANGED_SRC="$ROOT/$CHANGED"
    else
      die_usage "--changed $CHANGED does not exist. Looked in the working directory ($PWD) and under the repository root ($ROOT)."
    fi
    cp "$CHANGED_SRC" "$WORK/changed.txt"
  fi
  # WHY A PATH IN THE CHANGE SET IS ABSENT: this mode cannot say. The caller
  # handed over a list and nothing here knows where it came from, so the empty
  # file below is a real answer - no second source - and never a claim that
  # nothing was deleted. The runner still drops absent paths from what it hands
  # a tool, because that question is about the TREE and the tree answers it in
  # both modes; only the LABEL on the drop differs, and it says which it is.
  : > "$WORK/deleted.txt"
  DELETED_SOURCE="none: --changed hands over a list, and nothing here can say why a path in it is absent"
  # NO BASE, AND NONE IS INVENTED. `change.base` and `change.base_ref` are
  # written null for this mode: a caller-supplied list was diffed against
  # nothing this runner can name, and recording HEAD here would be a
  # measurement nobody took.
  BASE_SHA=""
  BASE_REF=""
elif [ -n "$BASE" ]; then
  command -v git >/dev/null 2>&1 || die_usage "--base needs git on PATH"
  merge_base="$(cd "$ROOT" && git merge-base "$BASE" HEAD 2>/dev/null)" ||
    die_usage "cannot resolve a merge base against $BASE. A wrong base makes every result below confidently wrong at once."
  # WHAT THE DIFF WAS COMPUTED AGAINST, recorded as two different facts.
  # `base_ref` is the ref exactly as typed. `base` is the commit the diff below
  # is actually taken from - the MERGE BASE, not `git rev-parse $BASE`. The two
  # are the same commit whenever REF is an ancestor of HEAD (HEAD~1, a
  # root commit, a branch not moved since); they differ when REF has moved on
  # past the fork point, and then `rev-parse` would name a commit this diff was
  # never taken against. `--verify` makes it a full 40-hex id or a refusal.
  BASE_SHA="$(cd "$ROOT" && git rev-parse --verify "${merge_base}^{commit}")" ||
    die_usage "the merge base against $BASE did not resolve to a commit. A wrong base makes every result below confidently wrong at once."
  BASE_REF="$BASE"
  (cd "$ROOT" && git diff --name-only "$merge_base" HEAD) > "$WORK/changed.txt"
  if [ ! -s "$WORK/changed.txt" ]; then
    die_usage "the diff against $BASE is empty. An empty diff is far more often a base problem than a change that did nothing; resolve the base before believing a green run."
  fi
  # THE SECOND SOURCE THIS MODE HAS AND THE OTHER DOES NOT. It does not decide
  # what is handed to a tool - the tree decides that, in both modes - it
  # decides what the drop is CALLED in the report. A path this range removed is
  # named `deleted`; one absent for some other reason is named `absent`, which
  # is what a typo or a path that was never in this repository looks like from
  # here. Both are dropped and both are printed; only a reader can tell the
  # third case from the second, and this is what gives them the chance.
  (cd "$ROOT" && git diff --name-only --diff-filter=D "$merge_base" HEAD) > "$WORK/deleted.txt"
  DELETED_SOURCE="git diff --diff-filter=D against $BASE"
else
  die_usage "no change given. Pass --changed <file> or --base <ref>."
fi

# --- IS THIS A CHANGE SET AT ALL, OR IS IT A FILE SOMEBODY HANDED OVER? ----
#
# The contents of `--changed` used to be believed, whatever they were. A file
# holding `#!/usr/bin/env bash`, a comment line and an English sentence was
# accepted without a word: those three lines became the change under test, they
# were recorded verbatim in `change.files`, coverage was computed against them,
# and a result was written that reads exactly like a real run. That is not a
# hypothetical shape. `checks-result.json` in this repository once held 2611
# entries of which 9 existed - the other 2602 were a script's own source lines,
# put there by a run that was handed the script instead of its change set.
#
# THE DAMAGE TRAVELS. `change.files` is rendered into the published dashboard,
# so what is accepted here decides what a published page SAYS. A defect in what
# this runner takes IN does not stay inside the runner.
#
# ABSENCE IS NOT THE TEST, and that is the part that has to be got right. A
# file DELETED by the change under test is legitimately absent - the verdict
# script below already counts those separately instead of demanding coverage
# for them - and this repository's own check fixtures hand the runner paths
# that were never created at all. Refusing on absence would break both. So the
# question asked here is the narrower one absence cannot answer: COULD THIS
# LINE EVER HAVE BEEN A PATH? Whitespace in it, a leading `#`, a shell
# metacharacter - those are a line of a script or a sentence of prose, and no
# change set holds one. An entry that IS there is never asked.
#
# IT REFUSES, IT DOES NOT FILTER. Dropping the unusable lines and running on
# what survived would measure a scope nobody declared - the same failure with
# tidier output - and the run would still report itself as covering a change.
#
# EXIT 2, NOT 3, and the contract at the top of this file decides that. 3 is a
# deliberate no ABOUT THE CHANGE: a blocking check that ran and failed. Nothing
# here has run. `--changed` named the wrong kind of file, which is the same
# fault as `--changed` naming no file at all - already a 2, a few lines up.
#
# WHAT IT DOES NOT CATCH, said here rather than left to be discovered. A line
# that is not a path but is SHAPED like one - `fi`, `esac`, a bare word -
# cannot be told apart from a path this change deleted, and is accepted. The
# hole is real and it is bounded: in every instance observed the same file also
# held lines that could not be paths, and one of those refuses the whole run.
# The cost in the other direction is stated too - a DELETED path with a space
# in its name is refused, because nothing here can confirm it ever existed.
cs_line=0
cs_raw=""
while IFS= read -r cs_raw || [ -n "$cs_raw" ]; do
  cs_line=$((cs_line + 1))
  # Same reading the plan below takes: surrounding whitespace is trimmed and a
  # blank line is nothing. A rule that judged a different string than the one
  # that becomes a changed path would refuse and record two different things.
  cs_entry="${cs_raw#"${cs_raw%%[![:space:]]*}"}"
  cs_entry="${cs_entry%"${cs_entry##*[![:space:]]}"}"
  if [ -z "$cs_entry" ]; then continue; fi

  cs_probe="${cs_entry#./}"
  case "$cs_probe" in
    /*) ;;
    *) cs_probe="$ROOT/$cs_probe" ;;
  esac
  # It is there. Nothing else is anyone's business - not its shape, not its
  # name. This is the same question the verdict script asks about a path a
  # check did not cover, asked earlier and of the whole set.
  if [ -e "$cs_probe" ]; then continue; fi

  # `git diff --name-only` renders a path holding a non-ASCII or a control
  # character in C-quoted form - "sm\303\266rg\303\245s.txt" - so a change set
  # derived from git and handed over as a file arrives that way. git named it,
  # which is the one thing this rule is trying to establish.
  case "$cs_entry" in
    '"'*'"') continue ;;
  esac

  cs_why=""
  case "$cs_entry" in
    "#"*) cs_why="it opens with \`#\`, which is a comment or a shebang line" ;;
  esac
  if [ -z "$cs_why" ]; then
    case "$cs_entry" in
      *[[:space:]]*) cs_why="it holds whitespace, so it is a line of text and not one path" ;;
    esac
  fi
  if [ -z "$cs_why" ]; then
    case "$cs_entry" in
      *[\"\'\`\$\&\;\|\<\>\(\)\{\}\\]*) cs_why="it holds shell metacharacters" ;;
    esac
  fi
  if [ -n "$cs_why" ]; then
    # Quoted, because the whole point is that the reader sees what arrived
    # instead of a file list - and collapsed to one short printable run first,
    # because it is a line out of a file a stranger may have written.
    cs_shown="$(printf '%s' "$cs_entry" | tr -c '[:print:]' ' ' | cut -c1-100)"
    die_usage "the change set is not a list of paths. Line $cs_line of it reads \"$cs_shown\", and $cs_why. It is not under the repository root ($ROOT) either, so it is not a path this change deleted - it was never a path. This is what handing the runner a script, a diff or a log instead of its change set looks like: every line becomes a changed file, the coverage denominator is computed against them, and the result reads like a real run. Refusing rather than dropping the line: a run over a scope nobody declared is the same hollow green. Pass a file holding one path per line, or use --base <ref>."
  fi
done < "$WORK/changed.txt"

# --- plan: parse, validate, decide what this change attracts ---------------

cat > "$WORK/plan.py" <<'PY'
import json, os, re, sys

CONFIG, WORK, CHANGED, TAGS, ROOT, ROOT_SOURCE, CONFIG_SOURCE, DELETED, DELETED_SOURCE, BASE_SHA, BASE_REF = sys.argv[1:12]

def bad(msg):
    sys.stderr.write("run-checks: %s: %s\n" % (os.path.basename(CONFIG), msg))
    sys.exit(2)

try:
    import yaml
except ImportError:
    sys.stderr.write("run-checks: python3 has no yaml module, so the config cannot be read. "
                     "Install PyYAML. Refusing rather than guessing what was declared.\n")
    sys.exit(2)

try:
    with open(CONFIG) as fh:
        doc = yaml.safe_load(fh)
except yaml.YAMLError as exc:
    bad("not valid YAML, so nothing was run. %s" % str(exc).replace("\n", " "))
except OSError as exc:
    bad("cannot be read: %s" % exc)

if not isinstance(doc, dict):
    bad("the top level must be a mapping with `version` and `checks` keys")
if doc.get("version") != 1:
    bad("unsupported `version: %r`. This runner reads version 1 only; a config it half-understands drops checks silently."
        % doc.get("version"))

# --- committed config vs local override -----------------------------------
# A setting that decides what a check examines, or whether the run blocks,
# decides what everyone downstream reads in checks-result.json. That is a team
# decision and it is honoured only from the committed config, where it is in
# the diff someone approved. A `<config>.local.<ext>` file may still say how
# long this particular machine is allowed to take, because a slow laptop is
# nobody else's business.
#
# Ignored, never silently: a dropped override that nobody is told about looks
# exactly like an honoured one to the developer who wrote it.

LOCAL_CHECK_KEYS = ("timeout_seconds",)
LOCAL_DEFAULT_KEYS = ("timeout_seconds",)

_base, _ext = os.path.splitext(CONFIG)
LOCAL = _base + ".local" + _ext
LOCAL_NAME = os.path.basename(LOCAL)
ignored_local, local_defaults, local_checks = [], {}, {}

if os.path.exists(LOCAL):
    try:
        with open(LOCAL) as fh:
            loc = yaml.safe_load(fh)
    except yaml.YAMLError as exc:
        bad("its local override %s is not valid YAML, so nothing was run. %s"
            % (LOCAL_NAME, str(exc).replace("\n", " ")))
    except OSError as exc:
        bad("its local override %s cannot be read: %s" % (LOCAL_NAME, exc))
    if loc is None:
        loc = {}
    if not isinstance(loc, dict):
        bad("its local override %s must be a mapping" % LOCAL_NAME)

    lp = loc.get("policy") or {}
    if not isinstance(lp, dict):
        bad("`policy` in %s must be a mapping" % LOCAL_NAME)
    # Every policy key is team-level. There is no policy setting that changes
    # only this machine.
    ignored_local.extend("policy.%s" % k for k in sorted(lp))

    ld = loc.get("defaults") or {}
    if not isinstance(ld, dict):
        bad("`defaults` in %s must be a mapping" % LOCAL_NAME)
    for k in sorted(ld):
        if k in LOCAL_DEFAULT_KEYS:
            local_defaults[k] = ld[k]
        else:
            ignored_local.append("defaults.%s" % k)

    lc = loc.get("checks")
    if lc is None:
        lc = []
    if not isinstance(lc, list):
        bad("`checks` in %s must be a list" % LOCAL_NAME)
    for i, entry in enumerate(lc):
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str) or not entry["id"]:
            bad("checks[%d] in %s must be a mapping naming an existing check by `id`" % (i, LOCAL_NAME))
        eid = entry["id"]
        for k in sorted(entry):
            if k == "id":
                continue
            if k in LOCAL_CHECK_KEYS:
                local_checks.setdefault(eid, {})[k] = entry[k]
            else:
                ignored_local.append("checks[%s].%s" % (eid, k))

    for k in sorted(loc):
        if k not in ("version", "policy", "defaults", "checks"):
            ignored_local.append(k)

for _name in ignored_local:
    sys.stderr.write(
        "run-checks: WARNING: ignoring `%s` from %s. It is a team-level setting: it decides what "
        "gets examined or whether this run blocks, so it is honoured only from the committed %s "
        "where everyone who reads this repo's results can see it. Locally overridable: %s.\n"
        % (_name, LOCAL_NAME, os.path.basename(CONFIG), ", ".join(LOCAL_CHECK_KEYS)))

policy = doc.get("policy") or {}
if not isinstance(policy, dict):
    bad("`policy` must be a mapping")
empty_run = policy.get("empty_run", "refuse")
if empty_run not in ("refuse", "pass"):
    bad("`policy.empty_run` must be `refuse` or `pass`, not %r" % empty_run)

defaults = doc.get("defaults") or {}
if not isinstance(defaults, dict):
    bad("`defaults` must be a mapping")
defaults = dict(defaults)
defaults.update(local_defaults)

# policy.output was checked by nothing: not type, not absoluteness, not whether
# it lands inside the repo. A committed YAML value truncated a file outside the
# work tree and the run still exited 0/PASS.
# Off by default: a check tool living inside the repo under test is only safe
# when someone has decided that repo is trusted, and that decision belongs in
# the file where a reviewer will see it.
ALLOW_REPO_LOCAL = policy.get("allow_repo_local_tools", False)
if not isinstance(ALLOW_REPO_LOCAL, bool):
    bad("policy.allow_repo_local_tools must be true or false, not %r" % (ALLOW_REPO_LOCAL,))

OUTPUT = policy.get("output")
if OUTPUT is not None:
    if not isinstance(OUTPUT, str) or not OUTPUT.strip():
        bad("policy.output must be a non-empty string, not %r" % (OUTPUT,))
    if os.path.isabs(OUTPUT):
        bad("policy.output %r is absolute. It is written relative to the repository "
            "being checked; an absolute path lets a committed file choose what gets "
            "overwritten on the machine that cloned it." % OUTPUT)
    _res = os.path.realpath(os.path.join(ROOT, OUTPUT))
    _root = os.path.realpath(ROOT)
    if _res != _root and not _res.startswith(_root + os.sep):
        bad("policy.output %r resolves to %s, outside the repository at %s. This "
            "stage writes one result file, inside the repo it is checking."
            % (OUTPUT, _res, _root))

# WHERE A PERSON'S OVERRIDE OF A FAILING CHECK IS RECORDED.
#
# Absent by default, and that default is the P4 bound: with no key here the
# directory is never opened, so a cloned repository that ships its own
# `waivers/` waives nothing on the machine that cloned it. Enabling it is one
# line in the committed config, in the diff someone approved - and, like every
# `policy` key, it cannot be turned on from a `checks.local.yaml`.
WAIVER_DIR = policy.get("waivers")
if WAIVER_DIR is not None:
    if not isinstance(WAIVER_DIR, str) or not WAIVER_DIR.strip():
        bad("policy.waivers must be a non-empty string naming a directory inside the "
            "repository, not %r" % (WAIVER_DIR,))
    if os.path.isabs(WAIVER_DIR):
        bad("policy.waivers %r is absolute. Waivers are read relative to the repository "
            "being checked; an absolute path lets a committed file choose which directory "
            "on the puller's machine gets to switch this repo's gates off." % WAIVER_DIR)
    _wres = os.path.realpath(os.path.join(ROOT, WAIVER_DIR))
    _wroot = os.path.realpath(ROOT)
    if _wres != _wroot and not _wres.startswith(_wroot + os.sep):
        bad("policy.waivers %r resolves to %s, outside the repository at %s. An override of "
            "this repo's checks is recorded inside this repo, where it is reviewed with it."
            % (WAIVER_DIR, _wres, _wroot))

# The spec is the denominator. `require` always measures against it; `auto`
# measures as soon as any check names a requirement, so a repo that has not
# adopted this yet is not made to fail for it; `off` is the committed, visible
# opt-out.
SPEC_MODE = policy.get("spec_coverage", "auto")
if SPEC_MODE is False:
    # YAML 1.1 reads a bare `off` as the boolean false. Reading it as the word
    # the author wrote is better than making them learn that; the alternative
    # is an author who typed `off` and got a config error they cannot explain.
    SPEC_MODE = "off"
if SPEC_MODE not in ("require", "auto", "report", "off"):
    bad("`policy.spec_coverage` must be `require`, `auto`, `report` or `off`, not %r. YAML reads "
        "a bare `on`/`yes`/`true` as a boolean; quote the word." % (SPEC_MODE,))
SPEC_PATH = policy.get("spec", ".claude/productizer/spec.md")
if not isinstance(SPEC_PATH, str) or not SPEC_PATH.strip():
    bad("policy.spec must be a non-empty string, not %r" % (SPEC_PATH,))
if os.path.isabs(SPEC_PATH):
    bad("policy.spec %r is absolute. It is read relative to the repository being checked; an "
        "absolute path lets a committed file choose which file on the puller's machine becomes "
        "the denominator." % SPEC_PATH)

checks = doc.get("checks")
if not isinstance(checks, list) or not checks:
    bad("`checks` must be a non-empty list. A config declaring no checks is not a passing stage; delete the file or fill it in.")

# --- the denominator, derived from the spec -------------------------------
#
# The check author does not get to state what the check is measured against. A
# check that declares less than the spec holds is the hole this closes: the
# unit list comes from `policy.spec` and from nothing the check said.
#
# Units are the ACTIVE requirement bullets — `- **R7** — ...`. A requirement
# whose following line marks it superseded or withdrawn is out of the
# denominator, because the spec says the behaviour is no longer agreed.
#
# An unreadable spec, or one holding no requirements, comes back UNMEASURED
# and never as an empty set. "0 units, all covered" is the same hollow green
# this whole script exists to refuse.

REQ_RE = re.compile(r"^\s*[-*]\s+\*\*(R\d+)\*\*\s*[\u2014\u2013-]\s*(.+?)\s*$")
STATUS_RE = re.compile(r"^(Superseded by R\d+|Withdrawn)\b")
UNIT_ID_RE = re.compile(r"^R\d+$")


def enumerate_spec(path, shown):
    """-> (status, detail, active_units). active_units is None when unmeasured.

    `shown` is the configured, repo-relative path. Messages quote that and never
    the absolute one: this text lands in a committed result file, and an
    absolute path there differs on every machine that runs the stage.
    """
    if not os.path.exists(path):
        return ("unreadable",
                "no spec at %s, so the coverage denominator could not be derived. Unmeasured, "
                "not zero." % shown, None)
    try:
        with open(path, errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError as exc:
        return ("unreadable",
                "cannot read %s: %s. The coverage denominator could not be derived. Unmeasured, "
                "not zero." % (shown, exc), None)

    units, order, current, since = {}, [], None, 0
    for ln in lines:
        m = REQ_RE.match(ln)
        if m:
            rid, text = m.group(1), m.group(2)
            if rid in units:
                return ("unreadable",
                        "%s declares %s twice. Ids are permanent and unique, so a duplicate means "
                        "the denominator cannot be trusted. Unmeasured, not zero." % (shown, rid), None)
            units[rid] = {"id": rid, "text": text, "status": "active"}
            order.append(rid)
            current, since = rid, 0
            continue
        if current is not None:
            # The marker sits on the line after the requirement. Two lines of
            # slack, then the requirement is taken as active: a marker further
            # down belongs to prose, not to this id.
            since += 1
            if since > 2 or ln.strip().startswith("#"):
                current = None
            else:
                s = STATUS_RE.match(ln.strip(" \t>*-"))
                if s:
                    units[current]["status"] = ("superseded" if s.group(1)[0] == "S" else "withdrawn")
                    current = None

    if not order:
        return ("no_requirements",
                "%s holds no `- **R<n>** - ...` requirement lines, so the coverage denominator "
                "could not be derived. Unmeasured, not zero." % shown, None)
    active = [units[r] for r in order if units[r]["status"] == "active"]
    if not active:
        return ("no_requirements",
                "%s holds %d requirements and none of them active, so there is nothing to measure "
                "coverage against. Unmeasured, not zero." % (shown, len(order)), None)
    return "measured", None, active


if SPEC_MODE == "off":
    SPEC_STATUS, SPEC_DETAIL, SPEC_UNITS = "off", (
        "policy.spec_coverage: off - no requirement was measured. This is a committed opt-out, "
        "not a measurement."), None
else:
    SPEC_STATUS, SPEC_DETAIL, SPEC_UNITS = enumerate_spec(os.path.join(ROOT, SPEC_PATH), SPEC_PATH)
SPEC_IDS = {u["id"] for u in SPEC_UNITS} if SPEC_UNITS else set()
SPEC_CLAIMS = {}

# --- glob matching --------------------------------------------------------
# Deliberately small: `**` crosses directory separators, `*` and `?` do not.
# fnmatch is not used because its `*` crosses `/`, which makes `scripts/*.sh`
# quietly match `scripts/a/b/c.sh` and a reader mis-scope every check.

def glob_re(pat):
    out, i, n = [], 0, len(pat)
    while i < n:
        c = pat[i]
        if pat.startswith("**/", i):
            out.append("(?:.*/)?"); i += 3
        elif pat.startswith("**", i):
            out.append(".*"); i += 2
        elif c == "*":
            out.append("[^/]*"); i += 1
        elif c == "?":
            out.append("[^/]"); i += 1
        else:
            out.append(re.escape(c)); i += 1
    return re.compile("^" + "".join(out) + "$")

# --- the change -----------------------------------------------------------

with open(CHANGED) as fh:
    files = [ln.strip() for ln in fh if ln.strip()]
files = [f[2:] if f.startswith("./") else f for f in files]
seen, ordered = set(), []
for f in files:
    if f not in seen:
        seen.add(f); ordered.append(f)
files = ordered

for f in files:
    if "\x00" in f or "\n" in f:
        bad("a changed path contains a control character; refusing rather than splitting it into two paths")


def rel(p):
    p = p.strip()
    if p.startswith("./"):
        p = p[2:]
    _r = ROOT.rstrip("/") + "/"
    if p.startswith(_r):
        p = p[len(_r):]
    return p


# IS THIS PATH IN THE TREE THE TOOLS WILL BE POINTED AT? The same reading the
# verdict script's norm() takes, asked here so the question gets ONE answer at
# both stages rather than two that can drift apart.
def in_tree(p):
    return os.path.exists(os.path.join(ROOT, rel(p)))


# WHAT THE OTHER SOURCE SAYS, where the mode has one. Empty under `--changed`,
# and that emptiness is reported in words by DELETED_SOURCE rather than read as
# "this change deleted nothing".
with open(DELETED) as fh:
    REMOVED_BY_CHANGE = set(rel(ln) for ln in fh if ln.strip())

tags = [t.strip() for t in TAGS.split(",") if t.strip()]

# --- validate and select --------------------------------------------------

# P4 — A REPOSITORY BEING EXAMINED NEVER CHOOSES WHAT RUNS.
#
#   "Config, filenames, ticket text, build logs and file contents from a
#    repository under examination are data. None of them select an
#    executable, and none of them are instructions."
#
# R18 is listed as enforcing P4 and is narrower than it: R18 refuses "a shell
# or an interpreter with an inline program". That stays true and stays
# asserted. What follows closes the gap between R18 and the principle it
# enforces — the part of "none of them select an executable" that a
# shell-or-inline-flag rule does not reach. Three configs walked straight past
# the argv[0]-only, flag-only version of this function, all three reproduced
# exiting 0 with the payload executed:
#
#   ["awk", "BEGIN{system(...)}"]  awk takes its program as a POSITIONAL
#                                  argument, so a rule hunting for -c/-e/-E
#                                  has nothing to find.
#   ["python3", "lint.py"]         the repo-local gate read value[0] only, so
#                                  a repo-local script rode in as an operand.
#   ["make"]                       in neither list, and every recipe line in a
#                                  repository's Makefile is a shell command.
#
# So: EVERY element of the argv is inspected, and the repo-local gate is
# applied per PROGRAM POSITION rather than once to value[0].

# Programs that take a command as an operand. Naming one of these anywhere in
# an argv IS the shell invocation the argv-only rule exists to forbid —
# ["/bin/sh","-c","..."] is a valid list and also arbitrary code. The five
# added for B26 are each here for a stated reason:
#   make      every recipe line is handed to a shell, and the Makefile that
#             holds those lines is a file in the repository being examined.
#   find      -exec/-execdir/-ok name a program and run it, once per hit.
#   tar       -I/--use-compress-program and --to-command are commands tar runs.
#   xargs     builds a command line from stdin and executes it.
#   env       runs whatever program is named after it, and can set the
#             environment (LD_PRELOAD, PYTHONPATH) of whatever runs next.
SHELLS = {"sh","bash","zsh","dash","ksh","mksh","csh","tcsh","fish","rc",
          "busybox","env","xargs","nohup","time","timeout","gtimeout",
          "stdbuf","nice","ionice","setsid","script","ssh","scp","sudo",
          "doas","su","eval","find","tar","watch","parallel","make","open"}
# awk is its own set because the inline-flag rule cannot reach it: awk's
# program is a positional argument, so there is no flag to look for and no
# safe shape for it in a repository-supplied command.
AWKS = {"awk","gawk","nawk","mawk","busybox-awk"}
INTERPRETERS = {"python","python2","python3","perl","ruby","node","deno","bun",
                "php","lua","luajit","tclsh","expect","Rscript","osascript",
                "swift","ghc","runghc","groovy","jshell","scala"}
INLINE_FLAGS = {"-c","-e","-E","-Xc","--command","--eval","--exec"}
SCRIPT_EXT = re.compile(
    r"\.(py|sh|bash|zsh|pl|rb|js|mjs|cjs|ts|lua|php|r|scpt|tcl|exp|ps1|awk)$",
    re.IGNORECASE)
ROOT_REAL = os.path.realpath(ROOT)

def program_ref(where, elem, role):
    """A position that SELECTS AN EXECUTABLE, gated by allow_repo_local_tools.

    Only these positions are gated. A path sitting in an ordinary operand is
    data, which is what P4 already says it is; gating those would refuse
    `--config pyproject.toml` and teach people to switch the gate off."""
    if os.path.isabs(elem):
        real = os.path.realpath(elem)
        inside = real == ROOT_REAL or real.startswith(ROOT_REAL + os.sep)
    else:
        # Checks run with the work tree as their working directory (`cd
        # "$ROOT"` below), so a relative program reference resolves inside it:
        # as a path when it looks like one, and as a plain name when an
        # interpreter is the thing opening it — `python3 lint.py` reads
        # ./lint.py with no slash anywhere in the argv.
        inside = ("/" in elem or elem.startswith(".")
                  or SCRIPT_EXT.search(elem) is not None
                  or os.path.exists(os.path.join(ROOT, elem))
                  # `python3 -m pkg.mod` puts the work tree on sys.path, so a
                  # module name that resolves to a file in it is a repo-local
                  # program wearing a name with no slash in it.
                  or os.path.exists(os.path.join(ROOT, elem.replace(".", os.sep) + ".py")))
    # A repo-local check script is both the attack and a legitimate pattern -
    # a cloned repo choosing what runs on your machine, and your own repo
    # declaring its own linter, are the same bytes in the same place. The
    # filesystem cannot tell them apart, so the config must: default deny,
    # and an explicit opt-in that a reviewer can see in the diff.
    if inside and not ALLOW_REPO_LOCAL:
        # Reported by POSITION, never by quoting the value. checks.yaml is a
        # file a stranger writes and this text lands in a committed result.
        bad("%s (%s) is a path inside the repository being checked. A cloned "
            "repo would be choosing what executes on the machine that cloned it. "
            "If this is your own repo's script, set `policy.allow_repo_local_tools: "
            "true` - it is off by default so that trusting the repo is a decision "
            "someone made, not one nobody noticed." % (where, role))

def argv_of(where, value):
    if isinstance(value, str):
        bad("%s is a string. Commands are argv lists, never strings: a string is handed to a shell, "
            "and this file is committed, so that would let anyone who lands a commit choose what runs "
            "on the machine of whoever pulls it." % where)
    if not isinstance(value, list) or not value or not all(isinstance(x, str) and x for x in value):
        bad("%s must be a non-empty list of non-empty strings" % where)

    # EVERY element, not just value[0]. A value[0]-only rule is a live bypass:
    # the interposer is only ever one argument further along.
    for i, elem in enumerate(value):
        at = "%s[%d]" % (where, i)
        base = os.path.basename(elem)
        if base in AWKS:
            bad("%s names awk, which is refused in every position. awk takes its program as a "
                "POSITIONAL argument, so a rule that looks for -c/-e/-E never sees it, and there "
                "is no shape of awk that a repository can safely choose." % at)
        if base in SHELLS:
            bad("%s names a program that takes a command as an operand. That is the shell "
                "invocation argv-only exists to prevent, and the list form does not make it safe; "
                "it is refused in any position, not only the first. Name the tool you actually "
                "want to run." % at)
        if base in INTERPRETERS:
            for j in range(i + 1, len(value)):
                if value[j] in INLINE_FLAGS:
                    bad("%s[%d] hands an interpreter an inline program. Put the program in a file "
                        "the repo can review, and name that file here." % (where, j))
            for j in range(i + 1, len(value)):
                if value[j].startswith("-"):
                    continue
                program_ref("%s[%d]" % (where, j), value[j],
                            "the first operand of an interpreter")
                break
    program_ref("%s[0]" % where, value[0], "the program")
    return list(value)

def int_list(where, value):
    if not isinstance(value, list) or not all(isinstance(x, int) and not isinstance(x, bool) for x in value):
        bad("%s must be a list of integers" % where)
    return list(value)

ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
plan, ids = [], set()

for idx, chk in enumerate(checks):
    if not isinstance(chk, dict):
        bad("checks[%d] must be a mapping" % idx)
    cid = chk.get("id")
    if not isinstance(cid, str) or not ID_RE.match(cid):
        bad("checks[%d].id must be lower-case and match [a-z0-9][a-z0-9._-]*, got %r" % (idx, cid))
    if cid in ids:
        bad("duplicate check id %r. Two checks with one id collapse into one row in the result and one of them stops being read." % cid)
    ids.add(cid)
    w = "check %r" % cid

    if cid in local_checks:
        chk = dict(chk)
        chk.update(local_checks[cid])

    # A disabled check is a check that covers nothing. It is not a quiet pass:
    # its rows still appear, marked `disabled`, and every requirement it
    # claimed goes back to Missing.
    enabled = chk.get("enabled", True)
    if not isinstance(enabled, bool):
        bad("%s.enabled must be true or false, not %r" % (w, enabled))

    sev = chk.get("severity", defaults.get("severity", "block"))
    if sev not in ("block", "advise"):
        bad("%s.severity must be `block` or `advise`, not %r" % (w, sev))

    mode = chk.get("mode", defaults.get("mode", "batch"))
    if mode not in ("batch", "per_file"):
        bad("%s.mode must be `batch` or `per_file`, not %r" % (w, mode))

    timeout = chk.get("timeout_seconds", defaults.get("timeout_seconds", 120))
    if not isinstance(timeout, int) or isinstance(timeout, bool) or timeout <= 0:
        bad("%s.timeout_seconds must be a positive integer, not %r" % (w, timeout))

    cmd = argv_of("%s.command" % w, chk.get("command"))
    if mode == "per_file":
        if sum(a.count("{file}") for a in cmd) != 1:
            bad("%s runs per file, so its command must contain {file} exactly once" % w)
        if any("{files}" in a for a in cmd):
            bad("%s runs per file and must not contain {files}" % w)
    else:
        if any("{file}" in a and "{files}" not in a for a in cmd):
            bad("%s runs in batch mode; use {files}, not {file}" % w)

    when = chk.get("when")
    if not isinstance(when, dict) or not any(k in when for k in ("always", "paths", "tags")):
        bad("%s.when must declare at least one of `always`, `paths` or `tags`. "
            "A check nothing triggers never runs and is never noticed." % w)
    w_paths = when.get("paths") or []
    w_tags = when.get("tags") or []
    if not isinstance(w_paths, list) or not all(isinstance(p, str) and p for p in w_paths):
        bad("%s.when.paths must be a list of glob strings" % w)
    if not isinstance(w_tags, list) or not all(isinstance(t, str) and t for t in w_tags):
        bad("%s.when.tags must be a list of tag strings" % w)

    ec = chk.get("exit_codes")
    if not isinstance(ec, dict) or "pass" not in ec:
        bad("%s.exit_codes must be a mapping declaring at least `pass`. "
            "Without it every exit code is unrecognised and the check can never pass." % w)
    ec_pass = int_list("%s.exit_codes.pass" % w, ec.get("pass"))
    ec_fail = int_list("%s.exit_codes.fail" % w, ec.get("fail", []))
    ec_ref = int_list("%s.exit_codes.refused" % w, ec.get("refused", []))
    for a, b, an, bn in ((ec_pass, ec_fail, "pass", "fail"),
                         (ec_pass, ec_ref, "pass", "refused"),
                         (ec_fail, ec_ref, "fail", "refused")):
        overlap = sorted(set(a) & set(b))
        if overlap:
            bad("%s.exit_codes lists %s in both `%s` and `%s`" % (w, overlap, an, bn))

    cov = chk.get("coverage")
    if not isinstance(cov, dict):
        bad("%s declares no `coverage`. Every check states what it must have examined; "
            "without that, a scanner that opened nothing reports the same green as one that read every file." % w)
    frm = cov.get("from")
    if frm not in ("per_file_exit", "stdout_paths", "stdout_count", "command"):
        bad("%s.coverage.from must be one of per_file_exit, stdout_paths, stdout_count, command — got %r" % (w, frm))
    if frm == "per_file_exit" and mode != "per_file":
        bad("%s.coverage.from is per_file_exit but the check runs in batch mode; "
            "batch mode has no per-file result to read" % w)
    if frm in ("stdout_paths", "stdout_count"):
        if not isinstance(cov.get("pattern"), str) or not cov["pattern"]:
            bad("%s.coverage.from is %s, so it needs a `pattern` with one capture group" % (w, frm))
        try:
            rx = re.compile(cov["pattern"], re.MULTILINE)
        except re.error as exc:
            bad("%s.coverage.pattern is not a valid regular expression: %s" % (w, exc))
        if rx.groups < 1:
            bad("%s.coverage.pattern has no capture group; the first group is the item it captures" % w)
    cov_cmd = argv_of("%s.coverage.command" % w, cov.get("command")) if frm == "command" else None
    must = cov.get("must_cover", "none")
    if must not in ("all_triggering", "none"):
        bad("%s.coverage.must_cover must be `all_triggering` or `none`, not %r" % (w, must))
    if must == "all_triggering" and frm == "stdout_count":
        bad("%s.coverage.must_cover is all_triggering but `stdout_count` yields a number, not a set of paths" % w)
    min_cov = cov.get("min_covered", 1)
    if not isinstance(min_cov, int) or isinstance(min_cov, bool) or min_cov < 0:
        bad("%s.coverage.min_covered must be a non-negative integer" % w)
    min_rules = cov.get("min_rules", 0)
    if not isinstance(min_rules, int) or isinstance(min_rules, bool) or min_rules < 0:
        bad("%s.coverage.min_rules must be a non-negative integer" % w)
    rules_cmd = argv_of("%s.coverage.rules_command" % w, cov["rules_command"]) if cov.get("rules_command") else None
    rules_pat = cov.get("rules_pattern")
    if min_rules > 0:
        if not rules_pat or not rules_cmd:
            bad("%s.coverage.min_rules is set, so it needs both `rules_command` and `rules_pattern`. "
                "A ruleset that failed to load is an empty ruleset, and an empty ruleset passes everything." % w)
        try:
            re.compile(rules_pat)
        except re.error as exc:
            bad("%s.coverage.rules_pattern is not a valid regular expression: %s" % (w, exc))

    # --- what this check claims to cover, from the spec's own unit list ---
    # A claim is a claim, not coverage. It is bound to this check's result
    # below: a check that is disabled, that could not run, or that failed
    # covers nothing, whatever it declared here.
    su = cov.get("spec_units")
    if su is None:
        su = []
    if not isinstance(su, list):
        bad("%s.coverage.spec_units must be a list of claims" % w)
    seen_units = set()
    for j, cl in enumerate(su):
        cw = "%s.coverage.spec_units[%d]" % (w, j)
        if not isinstance(cl, dict):
            bad("%s must be a mapping with `id` and `verdict`" % cw)
        uid = cl.get("id")
        if not isinstance(uid, str) or not UNIT_ID_RE.match(uid):
            bad("%s.id must be a requirement id like R7, got %r" % (cw, uid))
        if uid in seen_units:
            bad("%s claims %s twice; two verdicts on one unit is not a verdict" % (cw, uid))
        seen_units.add(uid)
        vd = cl.get("verdict")
        if vd not in ("Covered", "Partial", "n/a"):
            bad("%s.verdict must be `Covered`, `Partial` or `n/a`, not %r. `Missing` is not "
                "claimable - it is what the runner concludes about a unit nothing covered." % (cw, vd))
        reason = cl.get("reason")
        if vd == "n/a":
            if not isinstance(reason, str) or not reason.strip():
                bad("%s claims `n/a` with no `reason`. An n/a removes a requirement from the "
                    "denominator, so it states why in a line a reviewer can disagree with. "
                    "\"Hard to test\" is not n/a." % cw)
        elif vd == "Partial":
            # A PARTIAL MUST SAY WHAT IT DOES NOT PROVE, and this is not a style
            # rule. Under `require`, a Partial is ACCEPTED - the run does not
            # refuse on it - and the entire basis for accepting it is that the
            # gap is written down where a reader can see it. A Partial with no
            # reason is not a declared gap; it is an undeclared one wearing a
            # verdict, which is exactly what `require` exists to stop.
            if not isinstance(reason, str) or not reason.strip():
                bad("%s claims `Partial` with no `reason`. Under `policy.spec_coverage: require` a "
                    "Partial does not refuse the run, and what earns it that is the sentence saying "
                    "which part is unasserted. Without one it is an undeclared gap with a verdict "
                    "on it. Say what this check does NOT prove." % cw)
        elif reason is not None and (not isinstance(reason, str) or not reason.strip()):
            bad("%s.reason must be a non-empty string when given" % cw)
        evidence = cl.get("evidence")
        if evidence is not None and (not isinstance(evidence, str) or not evidence.strip()):
            bad("%s.evidence must be a non-empty string when given" % cw)
        if SPEC_STATUS == "measured" and uid not in SPEC_IDS:
            bad("%s claims %s, which %s does not list as an active requirement. A claim against "
                "an id nobody can find is not coverage." % (cw, uid, SPEC_PATH))
        SPEC_CLAIMS.setdefault(uid, []).append(
            {"check": cid, "verdict": vd,
             "reason": reason if isinstance(reason, str) else None,
             "evidence": evidence})

    ver = chk.get("version_command")
    if ver is None:
        if sev == "block":
            bad("%s blocks but declares no `version_command`. A blocking check records the version of the tool "
                "that produced its verdict, or a scanner can silently regress and nothing notices." % w)
        ver_argv = None
    else:
        ver_argv = argv_of("%s.version_command" % w, ver)

    req = chk.get("requires")
    req = argv_of("%s.requires" % w, req) if req is not None else [cmd[0]]

    # --- does this change attract it -------------------------------------
    reasons, matched = [], []
    if when.get("always") is True:
        reasons.append("always")
    for pat in w_paths:
        rx = glob_re(pat)
        hits = [f for f in files if rx.match(f)]
        if hits:
            reasons.append("path:%s" % pat)
            matched.extend(hits)
    hit_tags = [t for t in w_tags if t in tags]
    if hit_tags:
        reasons.append("tag:%s" % ",".join(hit_tags))

    # A tag or an `always` says something about the whole change, so the whole
    # change is the file set. Path triggers scope to what they matched.
    if "always" in reasons or hit_tags:
        file_set = list(files)
    else:
        seen, file_set = set(), []
        for f in matched:
            if f not in seen:
                seen.add(f); file_set.append(f)

    # --- WHAT CAN ACTUALLY BE HANDED TO THE TOOL -------------------------
    #
    # THE SAME RULE THE COVERAGE STAGE ALREADY APPLIES, ONE STAGE EARLIER.
    # Down there a path DELETED by this change is dropped from what coverage
    # DEMANDS, because no tool can open it and demanding coverage for it
    # manufactures a gap. Every word of that applies to INVOCATION: handing a
    # tool a path that is gone from the tree manufactures a REFUSAL the same
    # way. Measured 2026-09-07 on this repository: the root-commit-to-HEAD
    # change set names 14 deleted paths, two of them `.sh`, and `shell-lint`
    # and `stderr-suppression` both exited 2 - correctly, since check-stderr
    # cannot read a file that is not there - so both were REFUSED. A refused
    # check catches no regression, which is why v4.55.0 passed every local
    # check and went red in CI on `stderr-suppression`: CI diffs against a
    # real base where nothing is deleted, so it actually ran the check.
    #
    # DROPPED AND COUNTED, NEVER DROPPED QUIETLY. `files` stays the whole
    # declared scope - it is still the coverage denominator and still what
    # `files_in_scope` reports - and `files_deleted` is carried into the
    # result and rendered per check. A rule that silently shrinks what it
    # hands over is the same failure as a check that silently shrinks what it
    # examined.
    #
    # ONE QUESTION, ONE ANSWER, IN BOTH MODES. `--base <ref>` could ask git
    # (`--diff-filter=D`) and `--changed <file>` could not, and that would be
    # two answers to one question. It is not done, and not merely because one
    # mode cannot: the question the runner needs answered is "can a tool open
    # this path", and only the TREE answers that. git answers a different one
    # - "did this range remove it" - and the two come apart in both directions
    # against a working tree, which is what the tools are actually pointed at:
    # a path deleted in the range and re-created uncommitted is openable and
    # git still calls it D, and a path untouched by the range but removed from
    # the working tree is unopenable and git does not call it D at all. So
    # `os.path.exists` is not the mode-agnostic compromise, it is the more
    # correct of the two everywhere. Measured on this repository's
    # root-commit-to-HEAD range: git's D list and the absent-from-tree set are
    # the same 14 paths, no disagreement either way, so nothing is lost by
    # asking the tree.
    #
    # THE LINE THIS DOES NOT CROSS. A path absent for ANY OTHER REASON - a
    # typo, a path that was never in this repository - is absent too, and
    # `os.path.exists` alone cannot tell it from a deletion. So the drop is
    # LABELLED from whatever second source the mode has: under `--base`,
    # git's own `--diff-filter=D` list for the same range, and under
    # `--changed` there is no second source and the label says so. Both are
    # dropped either way, because what a tool can open is a fact about the
    # tree - but a reader sees `absent` beside a path git never removed, which
    # is what a typo looks like from here, and sees it named.
    #
    # Nothing is dropped quietly, and that is the whole safeguard: the
    # change-set check above already REFUSES an entry that could never have
    # been a path, and every drop below is counted and printed under its own
    # name in the run's output and in checks-result.json. THIS REPOSITORY'S
    # OWN FIXTURES DEPEND ON THE DROP BEING ALLOWED: `fixtures/missing-tool`
    # and `fixtures/fabricated-zero` hand the runner
    # `fixture/one-changed-file.txt`, which is never created anywhere, so a
    # rule that handed absent-for-another-reason paths to the tool anyway
    # would be a rule this repository violates on purpose in two committed
    # places.
    files_present, files_deleted, files_absent = [], [], []
    for f in file_set:
        if in_tree(f):
            files_present.append(f)
        elif rel(f) in REMOVED_BY_CHANGE:
            files_deleted.append(f)
        else:
            files_absent.append(f)

    # DOES THIS CHECK EVEN READ THE LIST? A batch command with no `{files}` in
    # it is handed no paths at all, so nothing was dropped from its invocation
    # and saying so would be noise. `per_file` reads the list by construction:
    # the executor iterates it.
    consumes_files = (mode == "per_file") or any("{files}" in a for a in cmd)

    plan.append({
        "index": idx, "id": cid, "severity": sev, "mode": mode,
        "timeout_seconds": timeout, "command": cmd, "requires": req,
        "version_command": ver_argv, "why": chk.get("why", ""),
        "exit_codes": {"pass": ec_pass, "fail": ec_fail, "refused": ec_ref},
        "coverage": {"from": frm, "pattern": cov.get("pattern"), "command": cov_cmd,
                     "examined_when_exit_in": int_list("%s.coverage.examined_when_exit_in" % w,
                                                       cov.get("examined_when_exit_in", [0]))
                                              if frm == "per_file_exit" else None,
                     "must_cover": must, "min_covered": min_cov,
                     "min_rules": min_rules, "rules_command": rules_cmd,
                     "rules_pattern": rules_pat},
        "enabled": enabled,
        # A check scoped `always` that did not run is broken. A check scoped by
        # paths or tags that did not match is simply not applicable to this
        # change. Collapsing the two makes every commit that touches no shell
        # script look like a gap, which is how an amber signal stops meaning
        # anything. The reader of the result cannot tell them apart without this.
        "trigger_scope": "always" if when.get("always") is True else "scoped",
        "triggered": enabled and bool(reasons), "triggered_by": reasons, "files": file_set,
        # `files` is the declared scope and the coverage denominator.
        # `files_present` is what the executor is allowed to substitute into
        # argv, and `files_deleted` is the difference, kept so it can be
        # counted rather than inferred from a subtraction downstream.
        "files_present": files_present, "files_deleted": files_deleted,
        "files_absent": files_absent, "consumes_files": consumes_files,
    })

for _eid in sorted(local_checks):
    if _eid not in ids:
        sys.stderr.write("run-checks: WARNING: %s overrides check %r, which %s does not declare. "
                         "Nothing was applied.\n" % (LOCAL_NAME, _eid, os.path.basename(CONFIG)))

# A configuration with no active verification refuses to load. Exiting 0 over
# a file that switched every check off is the largest hollow pass available,
# and it is one line of YAML away in every repo that has this file.
if not any(c["enabled"] for c in plan):
    bad("every one of the %d declared checks is `enabled: false`. A configuration with no active "
        "verification is a load error, not a clean pass: it would exit 0 having verified nothing. "
        "Delete the file if the stage is not wanted." % len(plan))

# `auto` measures the moment anyone declares a claim, and says so plainly when
# nobody has. Silence is reported as not-declared, never as covered.
_claim_count = sum(len(v) for v in SPEC_CLAIMS.values())
# `report` MEASURES AND NEVER REFUSES, and it exists because `auto` has no
# middle. Under `auto` the FIRST claim anybody declares turns enforcement on for
# the whole spec, so a repo adopting this incrementally goes from green to
# refusing every run the moment it records its first honest piece of coverage -
# which punishes exactly the act it is trying to encourage. The alternatives
# were both worse: delete the claims to get green, which destroys a real record
# to dodge a verdict, or narrow the denominator to what checks happen to claim,
# which is the hollow pass this whole file exists to prevent.
#
# `report` changes the VERDICT and never the MEASUREMENT. The denominator still
# comes from the spec, every uncovered requirement is still named, and the line
# says "declared but not enforced" so nobody reads the run as clean coverage. It
# is a visible, committed statement that the mapping is unfinished - not a way
# to stop counting.
SPEC_ENFORCED = SPEC_MODE == "require" or (SPEC_MODE == "auto" and _claim_count > 0)
if SPEC_MODE == "auto" and _claim_count == 0:
    SPEC_STATUS, SPEC_DETAIL, SPEC_UNITS = "not_declared", (
        "no check names a requirement from %s, so no requirement was measured. Unmeasured, not "
        "covered. Declare `coverage.spec_units` on the checks that verify something, or set "
        "`policy.spec_coverage: off` if this repo deliberately does not." % SPEC_PATH), None

# --- waivers: read, classified, and honoured by nothing yet ----------------
#
# Everything decidable without a run is decided here: whether the file records
# the four things R37 requires, whether the date is a date and still in the
# future, whether the id names a check this config declares, and whether two
# waivers claim the same check. Whether the named check actually FAILED is not
# knowable until it has run, so `candidate` is as far as this gets; the verdict
# script turns a candidate into `honoured` or `not_applicable`.
#
# NOTHING HERE IS QUOTED BACK. The location is reported; `Reason:` is recorded
# only as present or absent; a `Check:` that matches no declared id is not
# echoed, because a value nobody recognises is a stranger's text. `Authority:`
# is rendered, because R38 says the line names it - collapsed to one printable
# line and truncated first.

WAIVER_FIELD_RE = re.compile(r"^([A-Za-z][A-Za-z-]*):[ \t]*(.*)$")
WAIVER_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
WAIVER_REQUIRED = ("Check", "Authority", "Reason", "Expires")
# `templates/ruling.md` already writes an unset field as an em dash, and this
# block is read by the same kind of reader. A dash is unset, not a value: a
# waiver whose authority is "-" names nobody.
WAIVER_UNSET = ("\u2014", "\u2013", "-", "?", "TBD", "tbd")


def waiver_label(v):
    """One line of untrusted repository text, safe to render and nothing else."""
    v = "".join(ch if ch.isprintable() else " " for ch in v)
    return " ".join(v.split())[:60]


import datetime
WAIVER_TODAY = datetime.date.today().isoformat()

waivers = []
if WAIVER_DIR is not None:
    _wabs = os.path.join(ROOT, WAIVER_DIR)
    _names = []
    try:
        _names = sorted(n for n in os.listdir(_wabs) if n.endswith(".md"))
    except OSError as exc:
        # An absent or unreadable directory is NOT an error and NOT zero
        # waivers silently: it is said, on stderr, so a misspelt policy.waivers
        # does not read as "nobody has waived anything".
        sys.stderr.write("run-checks: WARNING: policy.waivers names %s, which could not be listed "
                         "(%s). No waiver was read; nothing is waived.\n"
                         % (WAIVER_DIR, exc.strerror or exc))
    for _n in _names:
        loc = "%s/%s" % (WAIVER_DIR.rstrip("/"), _n)
        rec = {"file": loc, "check": None, "authority": None, "expires": None,
               "reason_recorded": False, "state": None, "detail": None}
        fields = {}
        try:
            with open(os.path.join(_wabs, _n), errors="replace") as fh:
                for ln in fh:
                    m = WAIVER_FIELD_RE.match(ln.rstrip("\n"))
                    # First occurrence wins. A second `Authority:` further down
                    # the file would otherwise silently replace the one a
                    # reviewer read at the top.
                    if m and m.group(1) in WAIVER_REQUIRED and m.group(1) not in fields:
                        fields[m.group(1)] = m.group(2).strip()
        except OSError as exc:
            rec["state"] = "unreadable"
            rec["detail"] = ("could not be read (%s). A waiver nobody could read is not a waiver; "
                             "nothing was softened by it." % (exc.strerror or exc))
            waivers.append(rec)
            continue

        absent = [k for k in WAIVER_REQUIRED
                  if not fields.get(k) or fields[k] in WAIVER_UNSET]
        rec["reason_recorded"] = "Reason" not in absent
        rec["authority"] = waiver_label(fields.get("Authority", "")) if "Authority" not in absent else None
        if absent:
            rec["state"] = "malformed"
            rec["detail"] = ("records no %s. R37 requires a waiver to name the check, the authority "
                             "and the reason, and this runner also requires an expiry; a waiver "
                             "missing any of them is not honoured."
                             % ", ".join("`%s`" % k for k in absent))
            waivers.append(rec)
            continue
        if not WAIVER_DATE_RE.match(fields["Expires"]):
            rec["state"] = "malformed"
            rec["detail"] = ("its `Expires` field is not a YYYY-MM-DD date, so the bound on this "
                             "waiver could not be read. Not honoured.")
            waivers.append(rec)
            continue
        rec["expires"] = fields["Expires"]
        if fields["Check"] not in ids:
            rec["state"] = "unknown_check"
            rec["detail"] = ("names a check this configuration does not declare. Reported by "
                             "location rather than by quoting the name: it is text from the "
                             "repository, and it matched nothing, so it waives nothing.")
            waivers.append(rec)
            continue
        rec["check"] = fields["Check"]
        if rec["expires"] < WAIVER_TODAY:
            rec["state"] = "expired"
            rec["detail"] = ("expired on %s (today is %s), so it no longer softens anything and "
                             "`%s` blocks again if it fails. A waiver is bounded on purpose."
                             % (rec["expires"], WAIVER_TODAY, rec["check"]))
            waivers.append(rec)
            continue
        rec["state"] = "candidate"
        waivers.append(rec)

    # TWO WAIVERS FOR ONE CHECK IS NOT AN OVERRIDE, it is two people each
    # believing they were the one who decided. Neither is honoured.
    _per_check = {}
    for _w in waivers:
        if _w["state"] == "candidate":
            _per_check.setdefault(_w["check"], []).append(_w)
    for _cid, _group in _per_check.items():
        if len(_group) > 1:
            for _w in _group:
                _w["state"] = "duplicate"
                _w["detail"] = ("one of %d waivers naming `%s`. Two authorities over one check is "
                                "not an override; none of them is honoured."
                                % (len(_group), _cid))

os.makedirs(os.path.join(WORK, "run"), exist_ok=True)
with open(os.path.join(WORK, "plan.json"), "w") as fh:
    json.dump({"config": CONFIG, "config_source": CONFIG_SOURCE,
               "root": ROOT, "root_source": ROOT_SOURCE,
               "policy": {"empty_run": empty_run,
               "output": OUTPUT}, "files": files, "tags": tags,
               # WHERE THE REASON FOR A DROP CAME FROM, in words, so a result
               # file says whether the `absent` label meant "git looked and did
               # not name it" or "nothing looked at all".
               "deleted_source": DELETED_SOURCE,
               # Empty string on the shell side means "this mode has no base";
               # it becomes null here and never the empty string on disk.
               "base": BASE_SHA or None, "base_ref": BASE_REF or None,
               "local_overrides_ignored": ignored_local,
               "waivers": {"declared": WAIVER_DIR is not None, "dir": WAIVER_DIR,
                           "today": WAIVER_TODAY, "entries": waivers},
               "spec_coverage": {"mode": SPEC_MODE, "spec": SPEC_PATH, "status": SPEC_STATUS,
                                 "detail": SPEC_DETAIL, "enforced": SPEC_ENFORCED,
                                 "units": SPEC_UNITS, "claims": SPEC_CLAIMS},
               "checks": plan}, fh, indent=2)

for c in plan:
    if not c["triggered"]:
        continue
    d = os.path.join(WORK, "run", str(c["index"]))
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "meta"), "w") as fh:
        fh.write("mode=%s\ntimeout=%d\n" % (c["mode"], c["timeout_seconds"]))
    with open(os.path.join(d, "argv"), "wb") as fh:
        fh.write(b"".join(a.encode() + b"\x00" for a in c["command"]))
    with open(os.path.join(d, "version_argv"), "wb") as fh:
        if c["version_command"]:
            fh.write(b"".join(a.encode() + b"\x00" for a in c["version_command"]))
    with open(os.path.join(d, "rules_argv"), "wb") as fh:
        rc = c["coverage"]["rules_command"]
        if rc and c["coverage"]["min_rules"] > 0:
            fh.write(b"".join(a.encode() + b"\x00" for a in rc))
    with open(os.path.join(d, "cov_argv"), "wb") as fh:
        cc = c["coverage"]["command"]
        if cc:
            fh.write(b"".join(a.encode() + b"\x00" for a in cc))
    with open(os.path.join(d, "requires"), "w") as fh:
        fh.write("".join(r + "\n" for r in c["requires"]))
    # WHAT THE EXECUTOR MAY SUBSTITUTE INTO ARGV: the present ones only. The
    # deleted ones stay in the plan, in `files` and in `files_deleted`, and
    # never reach a command line.
    with open(os.path.join(d, "files"), "w") as fh:
        fh.write("".join(f + "\n" for f in c["files_present"]))
    # EVERY PATH IN SCOPE IS GONE. Dropping them all leaves an empty list, and
    # an empty list is not a small scan - it is no scan. `per_file` would
    # iterate zero times and the executor's `worst` would stay at its initial
    # 0, which the map reads as PASS; a batch `{files}` would invoke the tool
    # with no paths and get whatever that tool does with none. Either way a
    # check whose entire scope vanished would read as a clean bill of health
    # over a set nothing opened. check-hygiene reached the same conclusion
    # about its own arguments - "Nothing was scanned, so nothing is clean.
    # Unmeasured, not a pass" - and exits 2. The runner does not delegate that
    # to the tool: it invokes none and records a status that cannot run.
    #
    # A MARKER, NOT THE STATUS ITSELF, and the difference is a defect this
    # already caused. Written as `status_override` it short-circuited the
    # executor before the requires check, and `fixtures/missing-tool` - whose
    # one path is never created and whose tool is deliberately absent - came
    # back as this instead of `missing_tool`, taking R13's check red. An
    # absent TOOL is the earlier and larger fact: it is true whatever the file
    # list holds. So the executor decides the order, after it has looked.
    if c["consumes_files"] and not c["files_present"]:
        with open(os.path.join(d, "nothing_to_examine"), "w") as fh:
            fh.write("%d\n" % (len(c["files_deleted"]) + len(c["files_absent"])))
    # The check's OWN verdict map, written where per_file aggregation can read
    # it. Without this the shell has only the numbers, and a number cannot say
    # which outcome it means: a check declaring `pass: [1]` and `fail: [0]` is
    # not a broken check, it is grep.
    with open(os.path.join(d, "exit_map"), "w") as fh:
        for kind in ("pass", "fail", "refused"):
            for code in c["exit_codes"].get(kind, []):
                fh.write("%s %s\n" % (kind, code))

sys.stdout.write("\n".join(str(c["index"]) for c in plan if c["triggered"]) + "\n")
PY

TRIGGERED="$(python3 "$WORK/plan.py" "$CONFIG_ABS" "$WORK" "$WORK/changed.txt" "$TAGS" "$ROOT" "$ROOT_SOURCE" "$CONFIG_SOURCE" "$WORK/deleted.txt" "$DELETED_SOURCE" "$BASE_SHA" "$BASE_REF")" || {
  rc=$?
  cleanup
  exit "$rc"
}

PARSED=1

# --- execute ---------------------------------------------------------------

# Runs argv with a wall-clock limit, appending combined output to $2.
# Returns the child's status, or 124 when the limit was reached.
run_limited() {
  limit="$1"; outfile="$2"; shift 2
  "$@" >>"$outfile" 2>&1 &
  pid=$!
  waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$limit" ]; then
      kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      sleep 2
      kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  rc=0
  wait "$pid" || rc=$?
  return "$rc"
}

# Reads a NUL-separated argv file into the global array ARGV.
read_argv() {
  ARGV=()
  [ -s "$1" ] || return 0
  while IFS= read -r -d '' item; do
    ARGV+=("$item")
  done < "$1"
}

cd "$ROOT"

for idx in $TRIGGERED; do
  [ -n "$idx" ] || continue
  D="$WORK/run/$idx"
  # Read, never sourced. `meta` is derived from a committed config, and
  # sourcing it would turn that data into code in this shell — the exact
  # mistake the argv-only rule in checks.yaml exists to prevent.
  mode="$(sed -n 's/^mode=//p' "$D/meta")"
  timeout="$(sed -n 's/^timeout=//p' "$D/meta")"

  # Every declared tool must be present. Missing is a failure, never a skip:
  # skipping is how a repo ends up with a green stage and no scanner.
  MISSING=""
  while IFS= read -r req; do
    [ -n "$req" ] || continue
    case "$req" in
      */*) [ -x "$req" ] || MISSING="$MISSING $req" ;;
      *)   command -v "$req" >/dev/null 2>&1 || MISSING="$MISSING $req" ;;
    esac
  done < "$D/requires"
  if [ -n "$MISSING" ]; then
    printf '%s\n' "${MISSING# }" > "$D/missing"
    printf 'missing_tool\n' > "$D/status_override"
    continue
  fi

  # AFTER the tool check, on purpose. Every path this check would have been
  # pointed at is gone from the tree, so there is nothing to open; running it
  # anyway means running it over an empty list, which is the hollow pass the
  # plan wrote this marker to refuse. An absent TOOL outranks it - that is
  # true whatever the file list holds - so this is asked second.
  if [ -e "$D/nothing_to_examine" ]; then
    printf 'nothing_to_examine\n' > "$D/status_override"
    continue
  fi

  # The tool's own version, recorded in the result. A scanner that silently
  # stops working usually changes version first.
  if [ -s "$D/version_argv" ]; then
    read_argv "$D/version_argv"
    vrc=0
    run_limited "$VERSION_TIMEOUT" "$D/version_out" "${ARGV[@]}" || vrc=$?
    printf '%s\n' "$vrc" > "$D/version_exit"
  fi

  # Rules the check loaded, where it declares a way to enumerate them. An
  # empty ruleset passes everything.
  if [ -s "$D/rules_argv" ]; then
    read_argv "$D/rules_argv"
    rrc=0
    run_limited "$timeout" "$D/rules_out" "${ARGV[@]}" || rrc=$?
    printf '%s\n' "$rrc" > "$D/rules_exit"
  fi

  : > "$D/output"
  started="$(date +%s)"

  if [ "$mode" = "per_file" ]; then
    : > "$D/file_exits"
    # AGGREGATE BY DECLARED OUTCOME, NOT BY NUMERIC SIZE.
    #
    # This used to be `worst = max(exit code)`, which assumes a larger number is
    # a worse result. That is a convention, not a fact, and every check here
    # DECLARES what its codes mean. A check with inverted semantics - grep,
    # where 0 means the forbidden thing was FOUND - has `pass: [1]` and
    # `fail: [0]`, so max() picked 1 over 0 and the stage reported PASS over a
    # tree that violated. Measured on a fixture, not argued.
    #
    # Order is refused > fail > pass > unmapped-becomes-refused. The first file
    # reaching the worst outcome donates its exit code, so whatever maps it
    # downstream sees a code the check itself declared rather than one this
    # loop invented.
    rank_of() {  # 3 refused · 2 fail · 1 pass · 0 not declared
      _r=0
      while read -r _kind _code; do
        [ "$_code" = "$1" ] || continue
        case "$_kind" in refused) _r=3 ;; fail) [ "$_r" -lt 2 ] && _r=2 ;; pass) [ "$_r" -lt 1 ] && _r=1 ;; esac
      done < "$D/exit_map"
      printf '%s' "$_r"
    }
    worst=0
    worst_rank=-1
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      read_argv "$D/argv"
      CMD=()
      for a in "${ARGV[@]}"; do
        CMD+=("${a//\{file\}/$f}")
      done
      printf '\n===== %s\n' "$f" >> "$D/output"
      frc=0
      run_limited "$timeout" "$D/output" "${CMD[@]}" || frc=$?
      printf '%s\t%s\n' "$frc" "$f" >> "$D/file_exits"
      r="$(rank_of "$frc")"
      # An UNDECLARED code outranks everything. A check that returned something
      # its own map does not cover has not passed - nobody knows what it did,
      # and unknown is refused, never clean.
      [ "$r" -eq 0 ] && r=4
      if [ "$r" -gt "$worst_rank" ]; then worst_rank="$r"; worst="$frc"; fi
    done < "$D/files"
    printf '%s\n' "$worst" > "$D/exit"
  else
    read_argv "$D/argv"
    CMD=()
    for a in "${ARGV[@]}"; do
      if [ "$a" = "{files}" ]; then
        while IFS= read -r f; do
          [ -n "$f" ] || continue
          CMD+=("$f")
        done < "$D/files"
      else
        CMD+=("$a")
      fi
    done
    brc=0
    run_limited "$timeout" "$D/output" "${CMD[@]}" || brc=$?
    printf '%s\n' "$brc" > "$D/exit"
  fi

  printf '%s\n' "$(( $(date +%s) - started ))" > "$D/duration"

  if [ -s "$D/cov_argv" ]; then
    read_argv "$D/cov_argv"
    crc=0
    run_limited "$timeout" "$D/cov_out" "${ARGV[@]}" || crc=$?
    printf '%s\n' "$crc" > "$D/cov_exit"
  fi
done

# --- verdict ---------------------------------------------------------------

cat > "$WORK/verdict.py" <<'PY'
import json, os, re, sys

WORK, OUT = sys.argv[1], sys.argv[2]
plan = json.load(open(os.path.join(WORK, "plan.json")))

def read(d, name, default=""):
    p = os.path.join(d, name)
    if not os.path.exists(p):
        return default
    with open(p, errors="replace") as fh:
        return fh.read()

def norm(p):
    p = p.strip()
    if p.startswith("./"):
        p = p[2:]
    root = plan["root"].rstrip("/") + "/"
    if p.startswith(root):
        p = p[len(root):]
    return p

results, blocking_failures, advisory_failures, triggered = [], [], [], 0

# A check that could not run reached no verdict, and no verdict is not a soft
# finding. `advise` means "argue with this check's findings"; it never means
# "it is acceptable for this check to be absent". So these statuses block
# whatever the severity says.
#
# `nothing_to_examine` is here for the same reason as the rest: every path in
# the check's scope is gone from the tree, so no tool was invoked and no
# verdict exists. It is not a pass, and it is not `refused` either - nothing
# refused anything, because nothing was asked.
CANNOT_RUN = {"missing_tool", "timeout", "no_version", "refused", "unmapped_exit",
              "nothing_to_examine"}


def record_failure(row):
    if row["blocking"] or row["status"] in CANNOT_RUN:
        if not row["blocking"]:
            row["detail"] = (row.get("detail", "") + " Declared `advise`, but blocking anyway: a "
                             "check that could not run has no findings to soften.").strip()
        blocking_failures.append(row)
    else:
        advisory_failures.append(row)


for c in plan["checks"]:
    row = {"id": c["id"], "why": c["why"], "severity": c["severity"],
           "blocking": c["severity"] == "block", "mode": c["mode"],
           "command": c["command"], "trigger_scope": c.get("trigger_scope", "scoped"),
           "triggered": c["triggered"],
           "triggered_by": c["triggered_by"], "files_in_scope": len(c["files"]),
           "enabled": c["enabled"]}
    if not c["enabled"]:
        # Reported, not omitted. A check switched off in a config that still
        # lists it is a decision someone should see in the same place they see
        # the passes, and every requirement it claimed goes back to Missing.
        row["status"] = "disabled"
        row["detail"] = "`enabled: false`. A disabled check covers nothing."
        results.append(row)
        continue
    if not c["triggered"]:
        row["status"] = "not_triggered"
        results.append(row)
        continue
    triggered += 1
    d = os.path.join(WORK, "run", str(c["index"]))

    # WHAT WAS NOT HANDED OVER, on every triggered row, counted rather than
    # left to be worked out from a subtraction. `files_in_scope` above is the
    # declared scope; these say how much of it reached a command line, and the
    # two lists say what happened to the rest - `deleted` where the mode had a
    # second source that named it removed, `absent` where nothing corroborated
    # it and a typo would look identical.
    row["files_handed_over"] = len(c["files_present"])
    row["files_dropped_deleted"] = c["files_deleted"][:200]
    row["files_dropped_absent"] = c["files_absent"][:200]
    row["file_list_consumed"] = c["consumes_files"]
    row["dropped_source"] = plan["deleted_source"]

    override = read(d, "status_override").strip()
    if override == "nothing_to_examine":
        _nd, _na = len(c["files_deleted"]), len(c["files_absent"])
        row["status"] = "nothing_to_examine"
        row["detail"] = ("every one of the %d path(s) in scope is gone from the tree (%d deleted by "
                         "this change, %d absent with nothing to say why), so nothing survives for a "
                         "tool to open and none was invoked. Not a pass: a check whose entire scope "
                         "vanished examined nothing." % (_nd + _na, _nd, _na))
        row["tool"] = {"version": None}
        results.append(row)
        record_failure(row)
        continue
    if override == "missing_tool":
        row["status"] = "missing_tool"
        row["detail"] = ("declared tool not installed: %s. Not skipped — a check whose tool is absent "
                         "is a check that did not run." % read(d, "missing").strip())
        row["tool"] = {"version": None}
        results.append(row)
        record_failure(row)
        continue

    ver_exit = read(d, "version_exit").strip()
    # Whatever the tool printed, collapsed to one line. Not parsed into a
    # semver: the value only has to change when the tool changes, so that a
    # scanner which silently regressed can be told apart from one that did not.
    ver_txt = " ".join(read(d, "version_out").split())[:200]
    row["tool"] = {"command": c["version_command"],
                   "version": ver_txt or None if ver_exit == "0" else None,
                   "exit_code": int(ver_exit) if ver_exit else None}

    exit_code = int(read(d, "exit", "1").strip() or 1)
    duration = int(read(d, "duration", "0").strip() or 0)
    output = read(d, "output")
    row["exit_code"] = exit_code
    row["duration_seconds"] = duration

    # --- coverage ---------------------------------------------------------
    cov = c["coverage"]
    covered, covered_list, timed_out, count_note = 0, [], False, None
    if cov["from"] == "per_file_exit":
        ok = set(cov["examined_when_exit_in"] or [0])
        for line in read(d, "file_exits").splitlines():
            if "\t" not in line:
                continue
            code, path = line.split("\t", 1)
            code = int(code)
            if code == 124:
                timed_out = True
            if code in ok:
                covered_list.append(path)
        covered = len(covered_list)
    elif cov["from"] == "stdout_paths":
        # MULTILINE so ^ and $ mean "a line of the tool's output", which is what
        # anyone writing one of these patterns against a line-oriented scanner
        # assumes. Without it the pattern silently matches nothing and the check
        # reads as hollow when the tool was fine.
        rx = re.compile(cov["pattern"], re.MULTILINE)
        seen = set()
        for m in rx.finditer(output):
            p = norm(m.group(1))
            if p and p not in seen:
                seen.add(p); covered_list.append(p)
        covered = len(covered_list)
    elif cov["from"] == "stdout_count":
        # No match means the tool never printed the number it was supposed to,
        # which is a coverage failure and not a reason to crash the run.
        m = re.search(cov["pattern"], output, re.MULTILINE)
        try:
            covered = int(m.group(1)) if m else 0
        except (TypeError, ValueError):
            covered = 0
            count_note = "the coverage pattern captured %r, which is not a number" % m.group(1)
    elif cov["from"] == "command":
        cov_exit = read(d, "cov_exit").strip()
        if cov_exit == "0":
            seen = set()
            for line in read(d, "cov_out").splitlines():
                p = norm(line)
                if p and p not in seen:
                    seen.add(p); covered_list.append(p)
            covered = len(covered_list)

    if exit_code == 124:
        timed_out = True

    rules, rules_detail = None, None
    if cov["min_rules"] > 0:
        r_exit = read(d, "rules_exit").strip()
        if r_exit == "0":
            rules = len(set(re.findall(cov["rules_pattern"], read(d, "rules_out"), re.MULTILINE)))
        else:
            rules = 0
            rules_detail = "the rule enumeration exited %s, so no ruleset was confirmed loaded" % (r_exit or "?")

    missing_files = []
    deleted_files = []
    if cov["must_cover"] == "all_triggering":
        have = set(covered_list)
        # Both sides must be normalised. `have` holds norm()ed paths from the
        # tool; c["files"] is whatever the caller passed in. An absolute changed
        # list against a relative-normalised covered set never matches, and every
        # check reports hollow however much it examined.
        #
        # A path DELETED in this change is a separate case from one skipped. It
        # is in the diff and gone from the tree, so no tool can open it, and
        # demanding coverage for it makes every deletion a hollow pass - an
        # accusation manufactured by the runner rather than a gap found in the
        # check. It is dropped from the requirement and COUNTED, never dropped
        # quietly: a rule that silently shrinks what it demands is the same
        # failure as a check that silently shrinks what it examined.
        #
        # THE PLAN ALREADY ASKED. It partitioned this check's scope before the
        # executor ran, dropped the absent side from what was handed to the
        # tool, and recorded it. This used to ask `os.path.exists` a second
        # time, here, after the run - two answers to one question, from two
        # readings of a tree that can move in between. It reads the one answer
        # now, so what coverage stops demanding is exactly what invocation
        # stopped handing over, by construction rather than by coincidence.
        #
        # BOTH LABELS, and that is not a shortcut. The labels split WHY a path
        # is not in the tree; what coverage can demand turns on WHETHER it is,
        # because a path nothing can open cannot be examined whatever the
        # reason. Forgiving only the corroborated half would demand coverage
        # for a path that was never handed to the tool - reporting `hollow`
        # over the runner's own decision, which is the manufactured accusation
        # this whole block exists to refuse. Measured: with only the `deleted`
        # half here the `deleted-in-scope` self-test case came back `hollow`.
        gone = set(norm(f) for f in c["files_deleted"] + c["files_absent"])
        for f in c["files"]:
            if norm(f) in have:
                continue
            if norm(f) in gone:
                deleted_files.append(norm(f))
            else:
                missing_files.append(f)

    reasons = []
    if covered < cov["min_covered"]:
        reasons.append("examined %d, which is below the declared minimum of %d%s"
                       % (covered, cov["min_covered"], "; " + count_note if count_note else ""))
    if missing_files:
        reasons.append("did not examine %d of the %d files in scope (%s%s)"
                       % (len(missing_files), len(c["files"]), ", ".join(missing_files[:5]),
                          ", ..." if len(missing_files) > 5 else ""))
    if rules is not None and rules < cov["min_rules"]:
        reasons.append("loaded %d rules, below the declared minimum of %d%s"
                       % (rules, cov["min_rules"], "; " + rules_detail if rules_detail else ""))

    row["coverage"] = {
        "from": cov["from"], "required": {"min_covered": cov["min_covered"],
                                          "must_cover": cov["must_cover"],
                                          "min_rules": cov["min_rules"]},
        "observed": {"covered": covered, "covered_items": covered_list[:200],
                     "rules_loaded": rules, "files_in_scope": len(c["files"]),
                     "not_examined": missing_files[:200],
                     "deleted_not_required": deleted_files[:200]},
        "satisfied": not reasons, "reasons": reasons,
    }
    row["timed_out"] = timed_out
    row["output_tail"] = output[-2000:]

    ec = c["exit_codes"]
    if timed_out:
        row["status"] = "timeout"
        row["detail"] = "hit the %ds limit. A killed scanner has no verdict; it is not a pass." % c["timeout_seconds"]
    elif row["tool"]["exit_code"] is not None and row["tool"]["exit_code"] != 0:
        row["status"] = "no_version"
        row["detail"] = ("the tool could not state its version (exit %s), so a silent regression in it "
                         "would be undetectable." % row["tool"]["exit_code"])
    elif exit_code in ec["refused"]:
        row["status"] = "refused"
        row["detail"] = "the tool refused to run this input (exit %d)." % exit_code
    elif exit_code not in ec["pass"] and exit_code not in ec["fail"]:
        row["status"] = "unmapped_exit"
        row["detail"] = ("exit %d is not described in `exit_codes`. An exit code the config does not "
                         "recognise is treated as a failure: tools add codes between releases." % exit_code)
    elif exit_code in ec["fail"]:
        row["status"] = "fail"
        row["detail"] = "the check reported findings."
        if reasons:
            # A findings-shaped exit can also be a coverage hole — a scanner
            # that read one file, found something in it, and never opened the
            # rest. Fixing the finding would then turn this red into a hollow
            # green, so say both now rather than after the next run.
            row["detail"] += (" It also failed its coverage assertion: %s. Fixing the finding alone "
                              "would turn this into a hollow pass." % "; ".join(reasons))
    elif not row["coverage"]["satisfied"]:
        row["status"] = "hollow"
        row["detail"] = ("exited %d but %s. A check that examined nothing is a failure, not a pass."
                         % (exit_code, "; ".join(reasons)))
    else:
        row["status"] = "pass"

    # A CHECK THAT REACHED NO VERDICT MEASURED NOTHING, so it records no count.
    #
    # `covered` is initialised to 0 above and the coverage block is assembled
    # before the status is known, which is fine for every status that is a
    # verdict: a `fail`, a `hollow` and a `pass` all ran, and their 0 is a
    # tally of what was really observed. For the CANNOT_RUN statuses it is
    # not. A `stdout_count` check killed at its limit never printed the number
    # it was going to print, so the 0 recorded for it was produced by this
    # line and by nothing else - and a month later it reads exactly like a
    # real zero. P1: an absent measurement is never a measurement of zero.
    #
    # DELETED, NOT NULLED, because absence is already this file's convention
    # for a row that could not run - the `missing_tool` row above reaches
    # `continue` before this block exists at all, and a reader who can tell
    # `missing_tool` from `timeout` should not have to tell absent from null
    # as well. The spec denominator further down keeps `units_total` and
    # `counts` null instead, because those keys sit in an object that is
    # always present and has no absence to express.
    #
    # This changes nothing about the verdict. A CANNOT_RUN status is decided
    # by the kill, the version, the exit code or the map - never by coverage -
    # and it already blocks whatever the severity says.
    if row["status"] in CANNOT_RUN:
        del row["coverage"]

    if row["status"] != "pass":
        record_failure(row)
    elif not row["coverage"]["satisfied"]:
        row["detail"] = "passed, but the coverage assertion was not met."

    results.append(row)

# --- waivers: a person overriding a failing check -------------------------
#
# R38: WHILE A FAILING CHECK IS OVERRIDDEN, RENDER IT AS FAILED AND WAIVED, AND
# NEVER AS PASSED. So nothing here touches `status`, `exit_code`, `coverage` or
# `output_tail`. The waiver is attached BESIDE the unchanged failure and the row
# is moved out of the blocking set - that is the entire effect.
#
# ONLY A `fail` THAT WAS ACTUALLY BLOCKING IS WAIVABLE. Every other status is an
# absence of measurement (`timeout`, `missing_tool`, `hollow`, ...) or a verdict
# with nothing to override (`pass`, `disabled`, `not_triggered`), and an
# `advise` check's findings already do not block. Each of those is reported
# `not_applicable`, naming the status, so a waiver that has quietly stopped
# applying is visible instead of decorative.

wv = plan.get("waivers") or {"declared": False, "dir": None, "today": None, "entries": []}
rows_by_id = {r["id"]: r for r in results}
waived = []

for w in wv["entries"]:
    if w["state"] != "candidate":
        continue
    row = rows_by_id[w["check"]]
    if row["status"] == "fail" and row in blocking_failures:
        blocking_failures.remove(row)
        waived.append(row)
        w["state"] = "honoured"
        w["detail"] = ("`%s` failed and this waiver moves it out of the blocking set until %s. "
                       "The measurement did not move: the check is still recorded `fail`."
                       % (w["check"], w["expires"]))
        # Beside the failure, never on top of it. `authority` is repository text
        # rendered as a label; `file` is what a reader opens to see who decided
        # and why, and the reason is deliberately not copied here.
        row["waiver"] = {"file": w["file"], "authority": w["authority"],
                         "expires": w["expires"], "reason_recorded": w["reason_recorded"]}
        row["detail"] = (row.get("detail", "")
                         + " WAIVED BY %s until %s (%s): this check does not block, and it did not "
                           "pass - it is still `fail`, and its findings above are unchanged."
                         % (w["authority"], w["expires"], w["file"])).strip()
    else:
        w["state"] = "not_applicable"
        w["detail"] = ("names `%s`, whose status is `%s`. Only a blocking check that ran and "
                       "FAILED can be waived: a person can override a finding, never the absence "
                       "of one." % (w["check"], row["status"]))

# --- spec coverage: the denominator the check did not choose --------------
#
# Every active requirement gets a row, the covered ones included, because a
# report that lists only the failures leaves the reader supplying their own
# denominator - which is the whole failure this file exists to prevent.

sc = plan["spec_coverage"]
by_id = {r["id"]: r for r in results}
# A Covered or Partial claim is a measurement, and a check that could not reach
# a verdict measured nothing. A disabled check is out of force entirely, n/a
# included: a claim from something switched off covers nothing.
VOID_RUN = {"missing_tool", "timeout", "no_version", "refused", "unmapped_exit", "fail", "hollow",
            "nothing_to_examine"}

spec_report = {"mode": sc["mode"], "spec": sc["spec"], "status": sc["status"],
               "detail": sc["detail"], "enforced": sc["enforced"],
               "units_total": None, "counts": None, "units": None, "satisfied": None}
spec_unsatisfied = []

if sc["status"] == "measured":
    unit_rows = []
    for u in sc["units"]:
        claims = []
        for cl in sc["claims"].get(u["id"], []):
            st = by_id.get(cl["check"], {}).get("status", "unknown")
            if st == "disabled":
                void = "the check is disabled, and a disabled, skipped or todo check covers nothing"
            elif cl["verdict"] in ("Covered", "Partial") and st in VOID_RUN:
                void = "the check came back %s, so it measured nothing here" % st
            else:
                void = None
            claims.append({"check": cl["check"], "claimed": cl["verdict"], "reason": cl["reason"],
                           "evidence": cl["evidence"], "check_status": st, "voided": void})
        live = [c for c in claims if not c["voided"]]
        if any(c["claimed"] == "Covered" for c in live):
            uv = "Covered"
        elif any(c["claimed"] == "Partial" for c in live):
            uv = "Partial"
        elif any(c["claimed"] == "n/a" for c in live):
            uv = "n/a"
        else:
            uv = "Missing"
        if uv == "Missing":
            note = ("; ".join("%s claimed %s but %s" % (c["check"], c["claimed"], c["voided"])
                              for c in claims if c["voided"])
                    or "no check in this config names this requirement")
        elif uv == "n/a":
            note = "; ".join("%s: %s" % (c["check"], c["reason"])
                             for c in live if c["claimed"] == "n/a")
        elif uv == "Partial":
            note = "; ".join("%s: %s" % (c["check"], c["reason"] or c["evidence"] or "part only")
                             for c in live if c["claimed"] == "Partial")
        else:
            note = None
        unit_rows.append({"id": u["id"], "text": u["text"], "verdict": uv, "note": note,
                          "exercised": any(by_id.get(c["check"], {}).get("status") == "pass"
                                           for c in live),
                          "claims": claims})
    counts = {"Covered": 0, "Partial": 0, "Missing": 0, "n/a": 0}
    for r in unit_rows:
        counts[r["verdict"]] += 1
    # WHAT `require` REFUSES ON, AND WHY IT IS NOT "EVERYTHING SHORT OF COVERED".
    #
    # This used to be `Partial or Missing`, which made the setting unreachable
    # rather than strict. Some obligations cannot be fully proven from inside a
    # repository at all: one needs a model in the check path, which
    # `models.checks` forbids; one is a fact about the publishing service; one
    # names a situation this repository has never been in. Demanding Covered for
    # those is demanding a proof that does not exist, and a gate that can never
    # be satisfied is a gate somebody switches off.
    #
    # So the bar is: NOTHING MAY BE SILENTLY UNPROVEN. `Missing` refuses - no
    # check names the requirement at all. A `Partial` is accepted only because
    # the config loader above refuses to load one without a `reason`, so every
    # Partial has already stated which part is unasserted, in the run's own
    # output where a reader can disagree with it.
    #
    # The failure this actually guards against is the one that has bitten this
    # repository repeatedly: a check quietly claiming more than it proves, or
    # disappearing entirely. Both land as `Missing` or as a claim voided by a
    # check that did not run, and both still refuse.
    spec_unsatisfied = [r for r in unit_rows if r["verdict"] == "Missing"]
    spec_report.update({"units_total": len(unit_rows), "counts": counts, "units": unit_rows,
                        "satisfied": not spec_unsatisfied})

# An unmeasured denominator refuses when it is being enforced. `units_total`
# and `counts` stay null rather than 0 - a number nobody could compute is not
# the number zero, and rendering it as zero is how "all covered" gets printed
# over a spec that was never read.
spec_refused = bool(sc["enforced"] and (sc["status"] != "measured" or spec_unsatisfied))

empty = triggered == 0
refuse_empty = empty and plan["policy"]["empty_run"] == "refuse"

verdict = "pass"
code = 0
if blocking_failures or refuse_empty or spec_refused:
    verdict = "refused"
    code = 3

# This file is committed. An absolute path in it publishes the maintainer's
# home directory to everyone who clones the repo -- exactly what check-hygiene
# refuses, leaked by the tool that reports on hygiene. Emit repo-relative:
# `root` is where this file lives, so "." says everything true about it, and
# the absolute values stay in memory for path resolution and never on disk.
def _rel(p, root):
    r = root.rstrip("/") + "/"
    return p[len(r):] if p.startswith(r) else os.path.basename(p)

# WHY THE SCHEMA ID STAYS `/1` WITH `change.base` AND `change.base_ref` ADDED.
# The change is additive: no field is renamed, removed or re-typed, and every
# reader measured reads `change` by key with a default (`build-view.sh` already
# reads `change.get('base')` and gets null; `pr-spec-comment.sh` reads only
# `files`). A bump would break the one reader that pins the id exactly -
# `emit-attestation.sh` refuses anything but `/1` - to announce two keys no
# reader has to understand. `/2` is for the day a field a reader relies on
# changes meaning. A reader that must know whether a null base means "no base
# in this mode" or "an older runner that never recorded one" tells them apart
# by the KEY: present-and-null is the former, absent is the latter.
doc = {
    "schema": "productizer.checks.result/1",
    "config": _rel(plan["config"], plan["root"]),
    "root": ".",
    "config_source": plan["config_source"],
    "root_source": plan["root_source"],
    "change": {"files": plan["files"], "file_count": len(plan["files"]), "tags": plan["tags"],
               "base": plan["base"], "base_ref": plan["base_ref"]},
    "verdict": verdict,
    "exit_code": code,
    "counts": {"declared": len(plan["checks"]), "triggered": triggered,
               "passed": sum(1 for r in results if r["status"] == "pass"),
               "blocking_failures": len(blocking_failures),
               # What blocked, and what would have. A waived row is out of
               # `blocking_failures` because it no longer decides the verdict,
               # and it is counted here so it is not out of sight as well.
               "waived": len(waived),
               "advisory_failures": len(advisory_failures),
               "disabled": sum(1 for r in results if r["status"] == "disabled"),
               "not_triggered": sum(1 for r in results if r["status"] == "not_triggered"),
               "spec_units_unsatisfied": (len(spec_unsatisfied)
                                          if sc["status"] == "measured" else None)},
    "spec_coverage": spec_report,
    # Every waiver read, honoured or not. A waiver that stopped applying is the
    # one worth seeing: it is the difference between "nobody waived this" and
    # "somebody meant to and it expired".
    "waivers": wv,
    "local_overrides_ignored": plan["local_overrides_ignored"],
    "checks": results,
}

payload = json.dumps(doc, indent=2)
if OUT == "-":
    sys.stdout.write(payload + "\n")
else:
    os.makedirs(os.path.dirname(os.path.abspath(OUT)) or ".", exist_ok=True)
    with open(OUT, "w") as fh:
        fh.write(payload + "\n")

e = sys.stderr
e.write("checks stage: %d declared, %d triggered by %d changed files%s\n"
        % (len(plan["checks"]), triggered, len(plan["files"]),
           " and tags [%s]" % ", ".join(plan["tags"]) if plan["tags"] else ""))
for r in results:
    if r["status"] == "not_triggered":
        continue
    cv = r.get("coverage")
    cov_txt = ""
    if cv:
        cov_txt = "  covered %d" % cv["observed"]["covered"]
        if cv["required"]["must_cover"] == "all_triggering":
            cov_txt += "/%d files" % cv["observed"]["files_in_scope"]
            _gone = len(cv["observed"].get("deleted_not_required", []))
            if _gone:
                # "gone from the tree", not "deleted by this change". The set
                # behind this number is every path coverage stopped demanding,
                # and that turns on whether a tool could open it, not on why -
                # so calling all of them deleted would assert a cause on the
                # absent-for-another-reason half. The line under this row
                # splits them, and names them.
                cov_txt += " (%d gone from the tree, not required)" % _gone
        if cv["observed"]["rules_loaded"] is not None:
            cov_txt += ", %d rules" % cv["observed"]["rules_loaded"]
    # R38 - RENDERED AS FAILED AND WAIVED, NEVER AS PASSED. The word FAIL stays
    # in the status column and the authority is appended to it, so the line
    # cannot be skimmed as a pass and cannot be read without seeing who decided.
    # It overflows the column on purpose: a waiver is not a quiet state.
    _label = r["status"].upper()
    if r.get("waiver"):
        _label = "FAIL \u00b7 WAIVED BY %s" % r["waiver"]["authority"]
    e.write("  %-9s %-18s %-6s exit %-4s %s%s\n"
            % (_label, r["id"], r["severity"],
               r.get("exit_code", "-"),
               ((r.get("tool") or {}).get("version") or "version unknown")[:44], cov_txt))
    # WHAT THE RUNNER DID NOT HAND OVER. Printed only where the check reads the
    # file list at all - for a batch command with no `{files}` in it nothing was
    # handed over in the first place and the number would say nothing. Printed
    # whatever the status, including a pass: a run that quietly narrowed what it
    # pointed the tools at is the thing this line exists to make visible.
    _del = r.get("files_dropped_deleted") or []
    _abs = r.get("files_dropped_absent") or []
    if r.get("file_list_consumed") and (_del or _abs):
        _parts = []
        if _del:
            _parts.append("%d deleted by this change (%s%s)"
                          % (len(_del), ", ".join(_del[:4]), ", ..." if len(_del) > 4 else ""))
        if _abs:
            _parts.append("%d absent, and this run has no second source to say why - a typo or a "
                          "path that was never here looks the same (%s%s)"
                          % (len(_abs), ", ".join(_abs[:4]), ", ..." if len(_abs) > 4 else ""))
        e.write("             -> %d of %d path(s) in scope not handed over, %d handed over: %s. "
                "Reason source: %s.\n"
                % (len(_del) + len(_abs), r["files_in_scope"], r["files_handed_over"],
                   "; ".join(_parts), r.get("dropped_source")))
    if r.get("detail"):
        e.write("             -> %s\n" % r["detail"])

if sc["status"] == "measured":
    e.write("spec coverage: %d active requirement(s) derived from %s - %d Covered, %d Partial, "
            "%d Missing, %d n/a%s\n"
            % (spec_report["units_total"], sc["spec"], spec_report["counts"]["Covered"],
               spec_report["counts"]["Partial"], spec_report["counts"]["Missing"],
               spec_report["counts"]["n/a"],
               "" if sc["enforced"] else " (declared but not enforced)"))
    for r in spec_report["units"]:
        e.write("  %-8s %-5s %s\n" % (r["verdict"].upper(), r["id"], r["text"][:78]))
        if r["note"]:
            e.write("             -> %s\n" % r["note"])
else:
    e.write("spec coverage: UNMEASURED (%s). %s\n" % (sc["status"], sc["detail"]))

# Said whenever the policy is on, including when it read nothing: "0 waivers"
# from a directory that was opened is a measurement, and it is not the same
# statement as a repo that never opted in.
if wv["declared"]:
    _honoured = [w for w in wv["entries"] if w["state"] == "honoured"]
    e.write("waivers: %d file(s) read from %s, %d honoured (today is %s)\n"
            % (len(wv["entries"]), wv["dir"], len(_honoured), wv["today"]))
    for w in wv["entries"]:
        e.write("  %-14s %s\n" % (w["state"].upper(), w["file"]))
        if w["detail"]:
            e.write("             -> %s\n" % w["detail"])

if plan["local_overrides_ignored"]:
    e.write("ignored %d local override(s) of team-level settings: %s. Team-level settings are "
            "honoured only from the committed config.\n"
            % (len(plan["local_overrides_ignored"]), ", ".join(plan["local_overrides_ignored"])))

if spec_refused:
    if sc["status"] != "measured":
        e.write("REFUSED: %s A stage that cannot say what it was measured against does not get "
                "to report a pass.\n" % sc["detail"])
    else:
        e.write("REFUSED: %d of %d requirement(s) in %s are not covered: %s. The denominator is "
                "derived from the spec, not from what a check declared about itself.\n"
                % (len(spec_unsatisfied), spec_report["units_total"], sc["spec"],
                   ", ".join("%s (%s)" % (r["id"], r["verdict"]) for r in spec_unsatisfied[:8])))

if refuse_empty:
    e.write("REFUSED: no declared check was triggered by this change. "
            "That is a gap in the config, not a clean change. Set `policy.empty_run: pass` "
            "only if you mean it.\n")
if advisory_failures:
    e.write("advisory (does not block): %s\n"
            % ", ".join("%s (%s)" % (r["id"], r["status"]) for r in advisory_failures))
if blocking_failures:
    e.write("REFUSED: %s\n" % ", ".join("%s (%s)" % (r["id"], r["status"]) for r in blocking_failures))
elif not refuse_empty and not spec_refused:
    # Say what actually passed. "PASS" over a run that examined nothing, or one
    # with an unread advisory failure in it, is the same hollow green this
    # whole stage exists to make visible.
    if empty:
        e.write("PASS: no declared check was triggered, so nothing was examined. "
                "`policy.empty_run: pass` is what made that acceptable.\n")
    elif waived:
        # NOT "every blocking check passed". Something failed and a person let
        # it through; a summary line that does not say so is the hollow green
        # this whole stage exists to refuse.
        e.write("PASS: %d blocking check(s) FAILED and are waived by a person, not by a "
                "measurement - each is still recorded `fail` above%s. Everything else ran and "
                "covered what it declared.\n"
                % (len(waived),
                   ", and %d advisory check(s) did not pass" % len(advisory_failures)
                   if advisory_failures else ""))
    elif advisory_failures:
        e.write("PASS: every blocking check ran and covered what it declared. "
                "%d advisory check(s) did not — read them above.\n" % len(advisory_failures))
    else:
        e.write("PASS: every blocking check ran, covered what it declared, and found nothing.\n")
# Every relative path in the config resolved against this directory, and the
# result file landed under it. Naming it is what makes a wrong one visible.
e.write("config: %s (%s)\n" % (plan["config"], plan["config_source"]))
e.write("root: %s (%s)\n" % (plan["root"], plan["root_source"]))
e.write("result: %s\n" % ("stdout" if OUT == "-" else os.path.abspath(OUT)))
sys.exit(code)
PY

if [ -z "$OUT" ]; then
  OUT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["policy"]["output"] or "-")' "$WORK/plan.json")"
fi

rc=0
PARSED=""   # the verdict script owns 2 and 3 again from here
python3 "$WORK/verdict.py" "$WORK" "$OUT" || rc=$?
cleanup
exit "$rc"
