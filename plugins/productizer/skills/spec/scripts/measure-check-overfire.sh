#!/usr/bin/env bash
# measure-check-overfire.sh [--config FILE] [--root DIR]
#                          (--list | --check ID)
#                          [--commits N | --since REF] [--per-run-timeout SECS]
#                          [--history empty|clone]
#                          [--version] [--help] [--selftest]
#
# --commits defaults to 30, the window the proposed block-earning rule uses.
#
# Answers one question about one check: HOW OFTEN WOULD IT HAVE FIRED, AND ON
# WHAT. It replays the check against commits that are already on this branch,
# each against the tree as it stood at that commit, and reports the count.
#
# WHY THIS EXISTS. `severity: advise` has been available here from the start and
# three checks use it, so the advisory mode is not the gap. The gap is that no
# check in this repository has ever been measured for firing on the wrong things
# before being made blocking. A blocking check that fires on correct work is
# routed around, and a routed-around gate measures nothing - so the severity was
# always an argument rather than a number.
#
# WHAT THE NUMBER IS, AND WHAT IT IS NOT. Every commit replayed here is ALREADY
# ON THE BRANCH. It was merged. So a fire is one of two things and this tool
# cannot tell them apart:
#
#   a genuine defect that merged anyway, or
#   a false positive.
#
# The figure is therefore reported as a FIRE RATE and described as an UPPER BOUND
# on over-fire, never as an over-fire rate. Calling it an over-fire rate would
# assert that every historical fire was wrong, which is exactly the flattering
# direction. Separating the two needs a person to rule on each fire, and the
# fires are printed with their commits so that ruling is possible.
#
# A SECOND LIMIT, AND IT IS STRUCTURAL. Some fires are anachronisms rather than
# either of the above: a check written today, replayed against a tree from before
# the requirement it asserts existed, fires correctly and measures nothing about
# over-firing. The count is printed per commit so an anachronism is visible as a
# run of consecutive early fires, and the rate is not adjusted for it, because
# adjusting it would need the very human ruling this tool does not do.
#
# --list IS THE OTHER HALF OF THE HONESTY. It walks every check in the config and
# says, computed rather than asserted, whether it can be replayed at all and why
# not when it cannot. Four reasons a check is unmeasurable here:
#
#   DISABLED               a shut guard measures nothing; the rate is n/a
#   NO COMMAND             nothing to run
#   READS GIT HISTORY      the tree is extracted with `git archive`, which
#                          carries no `.git`. A check declaring `git`, or passing
#                          `--base`, is comparing against a history that is not
#                          there, so its result at that commit would be the
#                          extraction's artefact and not the check's answer
#   TOOL ABSENT            the declared tool is not on this machine; the rate is
#                          ?, which is what unreadable means here
#
# HOW A TREE IS OBTAINED. `git archive <commit>` piped into an extraction under a
# temporary directory. NOT `git checkout`, and not `git worktree`: this repository
# is routinely worked on by several agents at once, and a measurement that moves
# the work tree or writes into `.git` would corrupt whatever else is running.
# Nothing here writes inside the repository.
#
# --history clone IS THE SECOND WAY, AND IT IS OPT-IN. The default (`empty`)
# gives the extracted tree an empty repository, so a check that reads history
# refuses, and --list calls every check declaring `git` unmeasurable. That is the
# conservative answer and it cost nine checks their rates. It also hid one: a
# check that reads history WITHOUT declaring git - `import-marking` walks
# `git log` for one of its four sources - gets no history, carries on with three,
# and passes; its 0/30 was taken with a source dark. `--history clone` builds,
# per commit, a repository whose object store BORROWS this one's through
# `objects/info/alternates` (read-only; nothing is written into this `.git`),
# with one branch `main` at that commit and the work tree checked out there. So
# the check sees the REAL history up to that commit, as CI's full-depth checkout
# does, and nothing after it: no remote-tracking refs and no tags are carried,
# because the tip of this branch is the future at every commit replayed. A check
# reading tags or `origin/*` therefore sees none, which the output says.
#
# EVERY CHILD'S TEMPORARY DIRECTORY IS OURS. Each replay runs with TMPDIR
# pointed inside this tool's own scratch directory. A replay killed on timeout is
# killed with SIGKILL, which runs no trap, so whatever the check had made under
# TMPDIR used to stay in the system temp directory for good. Now it stays under
# a directory this tool removes on exit.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  measured - the check triggered on at least one commit in the range, and a
#      fire rate over that count is printed
#   2  could not run - bad usage, --list and --check together, --commits and
#      --since together, no config, an unparseable config, no python3, no yaml
#      module, not a git work tree, a shallow clone, or a --check id the config
#      does not declare
#   3  this check CANNOT be measured over history - disabled, no command, it
#      reads git history the extracted tree does not carry, or its tool is absent
#      on this machine. The rate prints as n/a or ?, never as 0%
#   4  measured nothing - either the check triggered on no commit in the range,
#      or it triggered and returned a VERDICT on none of them because every
#      replay refused, timed out or found no tool. The rate prints as n/a in both
#      cases, because a rate over zero examined commits is not a rate of zero
#
# Progress goes to stderr, one line per commit, as the replay runs. A 30-commit
# replay of `unmeasured-report` was abandoned after minutes "without producing one
# figure"; measured later, one commit costs about 16s, so the whole replay was
# eight minutes of silence, not a hang - and nothing on the screen could say which.
#
# Under --selftest the same four mean: every case produced the code it declares
# (0), at least one did not (1 - which is therefore reachable under --selftest
# and nowhere else), the corpus could not be built (2), and 3 and 4 are driven as
# cases.
#
# WHAT THIS DOES NOT DO.
#
#   It does not measure UNDER-firing. A check that never fires scores a perfect
#   0% here and may be proving nothing at all. R39's falsification requirement is
#   the instrument for that, and this one is deliberately blind to it.
#
#   It replays a check's CURRENT version against an OLD tree. That is the right
#   way round for the question - would this check, as it stands, have fired - and
#   it is not a reconstruction of what CI did at the time.
#
#   It reads only the check's exit code, mapped through its declared
#   `exit_codes`. An exit the config does not declare is counted in its own
#   bucket and is never folded into `pass`.
#
#   A `mode: per_file` check is invoked once per triggering file and the results
#   are folded WORST FIRST - undeclared, then refused, then fired, then passed -
#   so a commit where one file of ten failed is a commit the check fired on. It
#   is one commit in the count either way; this tool counts COMMITS, not files.
set -euo pipefail

VERSION="1.1"

CONFIG_REL=""
ROOT=""
CHECK_ID=""
COMMITS=""
SINCE=""
PER_RUN_TIMEOUT="120"
HISTORY="empty"
MODE=""

die_unmeasured() {
  printf 'measure-check-overfire: %s\n' "$1" >&2
  exit 2
}

usage() {
  sed -n '2,/^set -euo pipefail$/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf 'measure-check-overfire.sh %s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --list) [ -z "$MODE" ] || die_unmeasured "--list and --check ask different questions; give one"; MODE="list"; shift ;;
    --check)
      [ "$#" -ge 2 ] || die_unmeasured "--check needs a check id"
      [ -z "$MODE" ] || die_unmeasured "--list and --check ask different questions; give one"
      MODE="measure"; CHECK_ID="$2"; shift 2 ;;
    --config) [ "$#" -ge 2 ] || die_unmeasured "--config needs a value"; CONFIG_REL="$2"; shift 2 ;;
    --root) [ "$#" -ge 2 ] || die_unmeasured "--root needs a value"; ROOT="$2"; shift 2 ;;
    --commits) [ "$#" -ge 2 ] || die_unmeasured "--commits needs a value"; COMMITS="$2"; shift 2 ;;
    --since) [ "$#" -ge 2 ] || die_unmeasured "--since needs a value"; SINCE="$2"; shift 2 ;;
    --per-run-timeout) [ "$#" -ge 2 ] || die_unmeasured "--per-run-timeout needs a value"; PER_RUN_TIMEOUT="$2"; shift 2 ;;
    --history)
      [ "$#" -ge 2 ] || die_unmeasured "--history needs empty or clone"
      case "$2" in empty|clone) HISTORY="$2" ;; *) die_unmeasured "--history is empty or clone, not $2" ;; esac
      shift 2 ;;
    *) die_unmeasured "unknown option: $1" ;;
  esac
done

# ---------------------------------------------------------------------------
# The engine. One python program for both modes so the measurability rules that
# --list reports and the measurability rules --check enforces are the same code.
# Timeouts come from subprocess's own, rather than from a poll loop, because a
# poll loop charges its own interval to every invocation.
# ---------------------------------------------------------------------------
ENGINE='
import os, re, signal, subprocess, sys, tarfile, shutil, time

mode     = sys.argv[1]
cfg_fp   = sys.argv[2]
root     = sys.argv[3]
check_id = sys.argv[4]
n_commits= sys.argv[5]
since    = sys.argv[6]
per_run  = float(sys.argv[7])
work_root= sys.argv[8]
history  = sys.argv[9]

def refuse(msg, code=2):
    sys.stderr.write("measure-check-overfire: " + msg + "\n")
    raise SystemExit(code)

try:
    import yaml
except ImportError:
    refuse("python3 has no yaml module, so checks.yaml cannot be read")

try:
    with open(cfg_fp, "r", encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh)
except OSError as exc:
    refuse("the config could not be read: %s" % exc)
except yaml.YAMLError as exc:
    refuse("the config is not parseable YAML: %s" % exc)

if not isinstance(cfg, dict) or not isinstance(cfg.get("checks"), list):
    refuse("the config declares no checks list")

defaults = cfg.get("defaults") or {}

def git(*args, capture=True):
    return subprocess.run(["git", "-C", root] + list(args),
                          stdout=subprocess.PIPE if capture else None,
                          stderr=None, text=True)

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

def tool_present(entry):
    if entry.startswith("./") or entry.startswith("/"):
        cand = entry if entry.startswith("/") else os.path.join(root, entry[2:])
        return os.path.isfile(cand) and os.access(cand, os.X_OK)
    return shutil.which(entry) is not None

def measurability(chk):
    """Returns (measurable, reason, rate_placeholder)."""
    if chk.get("enabled") is False:
        return False, "disabled - a shut guard fires on nothing and proves nothing", "n/a"
    cmd = chk.get("command")
    if not isinstance(cmd, list) or not cmd:
        return False, "no command to run", "n/a"
    requires = chk.get("requires") or []
    if "git" in requires and history != "clone":
        return (False,
                "reads git history, and an extracted tree carries no .git - its "
                "answer there would be an artefact of the extraction "
                "(--history clone gives it the real history)", "n/a")
    if any(isinstance(a, str) and a == "--base" for a in cmd):
        return (False,
                "the command passes --base, so it compares against a history the "
                "extracted tree does not have", "n/a")
    absent = [r for r in requires if not tool_present(r)]
    if absent:
        return False, "tool absent on this machine: " + ", ".join(absent), "?"
    return True, "%s, %s" % (
        chk.get("mode", defaults.get("mode", "batch")),
        "no file placeholder - runs against the whole extracted tree"
        if not any("{file" in str(a) for a in cmd) else "file placeholder"), None

def history_line():
    if history == "clone":
        return ("history: CLONE - each commit gets the real history up to it, "
                "borrowed read-only; no tags, no remotes, nothing after it")
    return ("history: EMPTY - each tree gets an empty repository, so a check "
            "reading history refuses rather than answers")

if mode == "list":
    print("    " + history_line())
    print("    every check in this config, and whether it can be replayed")
    print("      %-28s %-11s %s" % ("check", "measurable", "why"))
    yes = no = 0
    for chk in cfg["checks"]:
        cid = chk.get("id") or "(no id)"
        ok, why, _ph = measurability(chk)
        if ok:
            yes += 1
        else:
            no += 1
        print("      %-28s %-11s %s" % (cid[:28], "yes" if ok else "NO", why))
    print("    measurable: %d of %d   unmeasurable: %d" % (yes, yes + no, no))
    print("    An unmeasurable check is NOT a check with a 0% fire rate. Its rate")
    print("    is n/a for a shut guard and ? for a tool this machine does not")
    print("    have, and neither of those is a number.")
    raise SystemExit(0)

# ---- measure one check -----------------------------------------------------
chosen = [c for c in cfg["checks"] if c.get("id") == check_id]
if not chosen:
    refuse("the config declares no check with id %r" % check_id)
chk = chosen[0]

print("    check: %s" % check_id)
print("    " + history_line())

# The history comes FIRST. Whether a check is replayable over history is not a
# question that has an answer when there is no history, and answering it anyway
# would report a repository problem as a property of the check.
if git("rev-parse", "--git-dir").returncode != 0:
    refuse("not a git work tree, so no tree at any commit could be obtained")
if git("rev-parse", "--is-shallow-repository").stdout.strip() == "true":
    refuse("this clone is shallow; a rate over a truncated history is not a rate "
           "over this branch")

ok, why, placeholder = measurability(chk)
if not ok:
    print("    measurable: NO - %s" % why)
    print("    fire rate: %s" % placeholder)
    print("    NOT MEASURED. This is not a fire rate of zero, and it must not be")
    print("    read as evidence that the check is quiet.")
    raise SystemExit(3)
print("    measurable: yes - %s" % why)

if since:
    rl = git("rev-list", "--no-merges", since + "..HEAD")
else:
    rl = git("rev-list", "--no-merges", "-n", n_commits, "HEAD")
if rl.returncode != 0:
    refuse("the commit range could not be resolved")
commits = [c for c in rl.stdout.split() if c]
if not commits:
    refuse("the range names no commit, so nothing could be replayed")

cmd_tpl = chk["command"]
codes   = chk.get("exit_codes") or {}
pass_c  = set(codes.get("pass") or [])
fail_c  = set(codes.get("fail") or [])
ref_c   = set(codes.get("refused") or [])
when    = chk.get("when") or {}
always  = bool(when.get("always"))
globs   = [glob_to_regex(g) for g in (when.get("paths") or [])]

tally = dict(triggered=0, not_triggered=0, passed=0, fired=0, refused=0,
             undeclared=0, tool_absent=0, timed_out=0)
fired_on = []
per_commit = []

# The work root is HANDED IN, not made here, so a single trap in the calling
# shell owns the cleanup. An earlier version called mkdtemp itself, and five
# SIGKILLed runs left 5.8MB each behind in the system temp directory - the same
# litter B64 records for run-checks.sh. A SIGKILL still cannot be cleaned up by
# anybody; INT and TERM now can.
work = os.path.join(work_root, "trees")
os.makedirs(work, exist_ok=True)

# TERM and INT handled HERE as well as in the calling shell, because bash defers
# a trap until the foreground command returns: a signal sent to the shell alone
# does not reach this program, and a signal sent to the group reaches this program
# first. Raising SystemExit lets the `finally` below do the removal, so there is
# one cleanup path and not two.
def _bail(signum, _frame):
    raise SystemExit(143 if signum == signal.SIGTERM else 130)

signal.signal(signal.SIGTERM, _bail)
signal.signal(signal.SIGINT, _bail)

common = git("rev-parse", "--git-common-dir").stdout.strip()
objects_dir = os.path.join(root if not os.path.isabs(common) else "", common, "objects")

def quiet(argv):
    return subprocess.run(argv, stdout=subprocess.DEVNULL, stderr=None).returncode

def clone_at(sha, tree):
    """A repository at `tree` whose history is this one up to `sha` and no further.
    Returns None on success, or the step that failed."""
    if quiet(["git", "init", "--quiet", tree]) != 0:
        return "git init"
    with open(os.path.join(tree, ".git", "objects", "info", "alternates"), "w") as fh:
        fh.write(os.path.abspath(objects_dir) + "\n")
    for argv, what in (
            (["git", "-C", tree, "config", "gc.auto", "0"], "config"),
            (["git", "-C", tree, "update-ref", "refs/heads/main", sha], "update-ref"),
            (["git", "-C", tree, "symbolic-ref", "HEAD", "refs/heads/main"], "symbolic-ref"),
            (["git", "-C", tree, "reset", "--hard", "--quiet"], "checkout")):
        if quiet(argv) != 0:
            return what
    return None

child_tmp_root = os.path.join(work_root, "child-tmp")
os.makedirs(child_tmp_root, exist_ok=True)
t_start = time.time()

try:
    for idx, sha in enumerate(commits):
        t_commit = time.time()
        def progress(verdict):
            sys.stderr.write("measure-check-overfire: [%d/%d] %s %s (%.1fs, %.0fs so far)\n"
                             % (idx + 1, len(commits), sha[:12], verdict,
                                time.time() - t_commit, time.time() - t_start))
            sys.stderr.flush()
        show = git("show", "--pretty=format:", "--name-only", "--no-renames",
                   "--diff-filter=ACMR", sha)
        files = [f for f in show.stdout.splitlines() if f.strip()]
        if always:
            triggering = files
        else:
            triggering = [f for f in files if any(rx.match(f) for rx in globs)]
            if not triggering:
                tally["not_triggered"] += 1
                per_commit.append((sha, "not-triggered"))
                progress("not-triggered")
                continue
        tally["triggered"] += 1

        tree = os.path.join(work, sha[:12])
        if history == "clone":
            failed_step = clone_at(sha, tree)
            if failed_step is not None:
                tally["tool_absent"] += 1
                per_commit.append((sha, "tree-unavailable (%s)" % failed_step))
                progress("tree-unavailable")
                shutil.rmtree(tree, ignore_errors=True)
                continue
        else:
            os.makedirs(tree, exist_ok=True)
            tar_fp = os.path.join(work, sha[:12] + ".tar")
            with open(tar_fp, "wb") as th:
                arc = subprocess.run(["git", "-C", root, "archive", "--format=tar", sha],
                                     stdout=th, stderr=None)
            if arc.returncode != 0:
                tally["tool_absent"] += 1
                per_commit.append((sha, "tree-unavailable"))
                progress("tree-unavailable")
                continue
            with tarfile.open(tar_fp) as tf:
                try:
                    tf.extractall(tree, filter="data")
                except TypeError:
                    tf.extractall(tree)
            os.unlink(tar_fp)

        # AN EMPTY GIT REPOSITORY IN THE EXTRACTED TREE, DELIBERATELY. Measured
        # first, not assumed: without this, 20 of 20 replays of acceptance-rows
        # came back REFUSED with `not a git work tree`, because almost every
        # check here locates its own root with `git rev-parse --show-toplevel`.
        # A rate over 20 refusals is not a rate.
        #
        # `init` and NOTHING ELSE - no commit. That is the asymmetry that keeps
        # this honest: a check needing only the ROOT now works, and a check
        # reading HISTORY finds no HEAD and REFUSES, which is counted as a
        # refusal and never as a pass. Committing the tree would have given
        # those checks a one-commit history that is not this repository, and
        # they would have answered confidently about it.
        if history != "clone":
            subprocess.run(["git", "init", "--quiet", tree],
                           stdout=subprocess.DEVNULL, stderr=None, check=False)

        exe = cmd_tpl[0]
        exe_fp = os.path.join(tree, exe[2:]) if exe.startswith("./") else None
        if exe_fp is not None and not os.path.isfile(exe_fp):
            tally["tool_absent"] += 1
            per_commit.append((sha, "tool-absent-at-that-commit"))
            progress("tool-absent-at-that-commit")
            shutil.rmtree(tree, ignore_errors=True)
            continue

        # A `{file}` template is invoked ONCE PER TRIGGERING FILE and the
        # invocations are folded worst-first, exactly as the runner does it.
        # Running only the first file would under-count every per_file check -
        # a commit touching ten scripts would be judged on one of them - and an
        # under-count here reads as a low fire rate, which is the flattering
        # direction.
        per_file_mode = any(str(a) == "{file}" for a in cmd_tpl)
        invocations = triggering if per_file_mode else [None]
        rcs, broke = [], None
        for one in invocations:
            argv = []
            for arg in cmd_tpl:
                a = str(arg)
                if a == "{files}":
                    argv.extend(triggering)
                elif a == "{file}":
                    argv.append(one)
                else:
                    argv.append(a)
            # THE WHOLE PROCESS GROUP, NOT JUST THE CHILD. subprocess.run(timeout=)
            # kills only the direct child; a check that spawns the runner leaves
            # grandchildren holding the pipes open, and the read blocks forever
            # after the timeout has already fired. Measured, not reasoned: a
            # replay of selftest-coverage with a 25s per-run limit was still alive
            # after twenty minutes. So the child gets its own session and the
            # timeout kills the group.
            child_tmp = os.path.join(child_tmp_root, "%s-%d" % (sha[:12], len(rcs)))
            os.makedirs(child_tmp, exist_ok=True)
            child_env = dict(os.environ, TMPDIR=child_tmp)
            try:
                proc = subprocess.Popen(argv, cwd=tree, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, text=True,
                                        start_new_session=True, env=child_env)
            except OSError as exc:
                broke = ("tool_absent", "not-executable: %s" % exc.strerror)
                break
            try:
                proc.communicate(timeout=per_run)
                rcs.append(proc.returncode)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    proc.kill()
                try:
                    proc.communicate(timeout=10)
                except subprocess.TimeoutExpired:
                    pass
                broke = ("timed_out", "timed-out")
                break
        if broke is not None:
            tally[broke[0]] += 1
            per_commit.append((sha, broke[1]))
            progress(broke[1])
            shutil.rmtree(tree, ignore_errors=True)
            continue
        if not rcs:
            tally["tool_absent"] += 1
            per_commit.append((sha, "no invocation was made"))
            progress("no invocation was made")
            shutil.rmtree(tree, ignore_errors=True)
            continue
        # Worst first: an undeclared code outranks a refusal, a refusal outranks
        # a fire, and a fire outranks a pass. A commit where one file failed is a
        # commit the check fired on, whatever its other files did.
        undeclared = [c for c in rcs if c not in pass_c and c not in fail_c and c not in ref_c]
        if undeclared:
            rc = undeclared[0]
        elif any(c in ref_c for c in rcs):
            rc = [c for c in rcs if c in ref_c][0]
        elif any(c in fail_c for c in rcs):
            rc = [c for c in rcs if c in fail_c][0]
        else:
            rc = rcs[0]

        if rc in fail_c:
            tally["fired"] += 1
            subj = git("show", "-s", "--pretty=format:%s", sha).stdout.strip()
            fired_on.append((sha, subj))
            per_commit.append((sha, "FIRED"))
        elif rc in pass_c:
            tally["passed"] += 1
            per_commit.append((sha, "pass"))
        elif rc in ref_c:
            tally["refused"] += 1
            per_commit.append((sha, "refused"))
        else:
            tally["undeclared"] += 1
            per_commit.append((sha, "undeclared exit %d" % rc))
        progress(per_commit[-1][1])
        shutil.rmtree(tree, ignore_errors=True)
finally:
    shutil.rmtree(work, ignore_errors=True)

print("    commits in range:            %5d" % len(commits))
print("    triggered:                   %5d" % tally["triggered"])
print("    not triggered:               %5d" % tally["not_triggered"])
print("    outcome over the triggered commits")
print("      pass                       %5d" % tally["passed"])
print("      FIRED (a declared fail)    %5d" % tally["fired"])
print("      refused                    %5d" % tally["refused"])
print("      undeclared exit            %5d" % tally["undeclared"])
print("      tool absent at that commit %5d" % tally["tool_absent"])
print("      timed out                  %5d" % tally["timed_out"])

if tally["triggered"] == 0:
    print("    fire rate: n/a - the check triggered on no commit in this range.")
    print("    A rate over zero triggering commits is not a rate of zero, and")
    print("    this range says nothing about whether the check over-fires.")
    raise SystemExit(4)

# THE DENOMINATOR IS VERDICTS, NOT TRIGGERS. A replay that refused, timed out or
# found no tool did not examine the commit, and putting it under the line would
# quietly shrink the rate towards zero - the more often a check cannot run, the
# cleaner it would look. This is the fabricated-zero failure with a division in
# front of it.
verdicts = tally["passed"] + tally["fired"]
if verdicts == 0:
    print("    fire rate: n/a - the check triggered %d time(s) and returned a"
          % tally["triggered"])
    print("    verdict on none of them: %d refused, %d timed out, %d had no tool"
          % (tally["refused"], tally["timed_out"], tally["tool_absent"]))
    print("    at that commit. Nothing was examined, so there is no rate. This is")
    print("    NOT a rate of zero and must not be read as a quiet check.")
    raise SystemExit(4)
print("    verdicts (pass or fail):     %5d   <- the denominator" % verdicts)
print("    fire rate over merged history: %d/%d = %.1f%%"
      % (tally["fired"], verdicts, 100.0 * tally["fired"] / verdicts))
if tally["refused"] or tally["timed_out"] or tally["tool_absent"]:
    print("    %d triggering commit(s) produced NO verdict and are excluded from"
          % (tally["refused"] + tally["timed_out"] + tally["tool_absent"]))
    print("    the denominator, never counted as a pass.")
print("    UPPER BOUND ON OVER-FIRE, NOT AN OVER-FIRE RATE. Every commit here is")
print("    already on the branch, so each fire is either a defect that merged or")
print("    a false positive, and nothing in this tool can tell those apart. A")
print("    person rules on each fire; the fires are named below so that is")
print("    possible. Fires clustered at the oldest commits are the anachronism")
print("    case - a check replayed against a tree from before the requirement it")
print("    asserts - and the rate is NOT adjusted for it.")
if fired_on:
    print("    fired on")
    for sha, subj in fired_on:
        print("      %s  %s" % (sha[:12], subj[:70]))
print("    per commit, newest first")
for sha, verdict in per_commit:
    print("      %s  %s" % (sha[:12], verdict))
raise SystemExit(0)
'

# ---------------------------------------------------------------------------
# --selftest
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  command -v python3 >/dev/null 2>&1 || { echo "selftest: no python3" >&2; exit 2; }
  python3 -c 'import yaml' || { echo "selftest: python3 has no yaml module" >&2; exit 2; }
  command -v git >/dev/null 2>&1 || { echo "selftest: no git" >&2; exit 2; }

  WORK="$(mktemp -d)" || { echo "selftest: could not make a work directory" >&2; exit 2; }
  trap 'rm -rf "$WORK"' EXIT

  REPO="$WORK/repo"
  mkdir -p "$REPO/tools" "$REPO/src"

  # A three-commit history with a tool committed INSIDE it, so the extracted
  # tree at each commit carries the check that is replayed against it. The tool
  # fires - exit 1 - exactly when `src/bad.txt` exists, which makes the fire
  # rate a property of the fixture's history and not of the machine.
  cat > "$REPO/tools/fires-on-bad.sh" <<'FIXTURE_TOOL'
#!/usr/bin/env bash
set -euo pipefail
for f in "$@"; do printf '%s\n' "$f"; done
if [ -f src/bad.txt ]; then
  echo "  found src/bad.txt" >&2
  exit 1
fi
exit 0
FIXTURE_TOOL
  chmod +x "$REPO/tools/fires-on-bad.sh"

  # A tool that always REFUSES. It drives the second leg of exit 4: a check that
  # triggers and returns a verdict on nothing. Without this case the refusal leg
  # is only read, and it is the leg that matters - the first real run of this
  # script hit exactly it, 20 refusals out of 20, and a triggers-based
  # denominator would have printed that as a 0.0% fire rate.
  cat > "$REPO/tools/always-refuses.sh" <<'FIXTURE_REFUSER'
#!/usr/bin/env bash
set -euo pipefail
echo "this tool cannot run here" >&2
exit 2
FIXTURE_REFUSER
  chmod +x "$REPO/tools/always-refuses.sh"

  # A tool that LOCATES ITS OWN ROOT WITH GIT and declares no dependency on git,
  # which is how almost every check in this repository is written. It exists
  # because removing the `git init` on the extracted tree left this self-test
  # GREEN - a finding about the test, not about the tool - and this case is what
  # closes that. With the empty repository present it returns a verdict; without
  # it, every replay refuses and the run ends at exit 4 with no rate.
  cat > "$REPO/tools/needs-root.sh" <<'FIXTURE_ROOT'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)" || {
  echo "needs-root: not a git work tree, so the root is unknown" >&2; exit 2; }
printf '%s\n' "$ROOT" > /dev/null
exit 0
FIXTURE_ROOT
  chmod +x "$REPO/tools/needs-root.sh"

  # A per_file tool that fires on exactly one path. The commit below touches three
  # src files and that path sorts LAST, so a harness that invoked only the first
  # file would report a pass. This is the case that keeps the per_file fold
  # honest: an under-count there reads as a low fire rate.
  cat > "$REPO/tools/fires-on-trip.sh" <<'FIXTURE_TRIP'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1"
if [ "$1" = "src/trip.txt" ]; then
  echo "  this is the file it fires on" >&2
  exit 1
fi
exit 0
FIXTURE_TRIP
  chmod +x "$REPO/tools/fires-on-trip.sh"

  # A tool that OUTLIVES ITS OWN CHILD PROCESS. Its grandchild sleeps 30s and
  # carries a token unique to this self-test, so a kill that reached only the
  # direct child leaves a process the case below finds by name. 30s outlasts the
  # 10s the engine waits after a kill, so the survivor is still alive when it is
  # looked for; and the case still ENDS with the group kill removed, because that
  # wait is bounded - a case that hung would hang the suite instead of failing.
  GC_TOKEN="ofgrandchild-$$-$RANDOM"
  cat > "$REPO/tools/hangs.sh" <<FIXTURE_HANG
#!/usr/bin/env bash
set -euo pipefail
sh -c 'sleep 30; : $GC_TOKEN' &
wait
FIXTURE_HANG
  chmod +x "$REPO/tools/hangs.sh"

  # A tool that READS HISTORY and says so in `requires`: it fires when the LAST
  # COMMIT added or modified src/bad.txt. Under the default it is unmeasurable (a
  # tree with an empty repository has no last commit); under --history clone it
  # must fire on exactly the commit that added the file. A synthetic history that
  # handed every tree a one-commit past would fire on every commit carrying it.
  cat > "$REPO/tools/reads-last-commit.sh" <<'FIXTURE_LAST'
#!/usr/bin/env bash
set -euo pipefail
names="$(git show --name-only --diff-filter=AM --pretty=format: HEAD)" || {
  echo "reads-last-commit: no last commit to read" >&2; exit 2; }
case "$names" in *src/bad.txt*) echo "  the last commit touched src/bad.txt" >&2; exit 1 ;; esac
exit 0
FIXTURE_LAST
  chmod +x "$REPO/tools/reads-last-commit.sh"

  # A tool that fires when the repository it is handed can see a commit its HEAD
  # cannot reach - the future, from the point of view of the commit replayed. A
  # clone carrying this branch's tip as a remote-tracking ref fails it on every
  # commit but the newest.
  cat > "$REPO/tools/sees-no-future.sh" <<'FIXTURE_FUTURE'
#!/usr/bin/env bash
set -euo pipefail
all="$(git rev-list --all --count)"
mine="$(git rev-list --count HEAD)"
if [ "$all" != "$mine" ]; then
  echo "  this repository holds $all commits and HEAD reaches $mine" >&2
  exit 1
fi
exit 0
FIXTURE_FUTURE
  chmod +x "$REPO/tools/sees-no-future.sh"

  # A tool that makes a directory under TMPDIR and then outlives the timeout. It
  # is killed with SIGKILL, so its own cleanup never runs; the directory must end
  # up inside this tool's scratch directory and not in the caller's TMPDIR.
  cat > "$REPO/tools/leaks-tmp.sh" <<'FIXTURE_LEAK'
#!/usr/bin/env bash
set -euo pipefail
mktemp -d "${TMPDIR:-/tmp}/leak.XXXXXX" > /dev/null
sleep 5 &
wait
FIXTURE_LEAK
  chmod +x "$REPO/tools/leaks-tmp.sh"

  GIT=(git -C "$REPO" -c user.email=selftest@example.invalid -c user.name=selftest -c commit.gpgsign=false)
  git init --quiet "$REPO" > /dev/null
  printf 'one\n' > "$REPO/src/a.txt"
  "${GIT[@]}" add tools/fires-on-bad.sh tools/always-refuses.sh tools/needs-root.sh tools/fires-on-trip.sh tools/hangs.sh \
    tools/reads-last-commit.sh tools/sees-no-future.sh tools/leaks-tmp.sh src/a.txt > /dev/null
  "${GIT[@]}" commit --quiet -m "first: a clean tree" > /dev/null
  printf 'bad\n' > "$REPO/src/bad.txt"
  "${GIT[@]}" add src/bad.txt > /dev/null
  "${GIT[@]}" commit --quiet -m "second: adds the file the tool fires on" > /dev/null
  "${GIT[@]}" rm --quiet src/bad.txt > /dev/null
  "${GIT[@]}" commit --quiet -m "third: removes it again" > /dev/null
  # A TOOL THAT ARRIVES LATE. The two oldest commits do not carry it, so replaying
  # a check that names it must land in `tool absent at that commit` and must NOT
  # be counted as a pass. Without this case, rewiring that branch to `passed` left
  # the self-test green - a finding about the test.
  cat > "$REPO/tools/late-arrival.sh" <<'FIXTURE_LATE'
#!/usr/bin/env bash
set -euo pipefail
for f in "$@"; do printf '%s\n' "$f"; done
exit 0
FIXTURE_LATE
  chmod +x "$REPO/tools/late-arrival.sh"
  printf 'one, edited\n' > "$REPO/src/a.txt"
  "${GIT[@]}" add tools/late-arrival.sh src/a.txt > /dev/null
  "${GIT[@]}" commit --quiet -m "fourth: a late tool and a touched src path" > /dev/null
  printf 'ok\n' > "$REPO/src/ok1.txt"
  printf 'ok\n' > "$REPO/src/ok2.txt"
  printf 'trip\n' > "$REPO/src/trip.txt"
  "${GIT[@]}" add src/ok1.txt src/ok2.txt src/trip.txt > /dev/null
  "${GIT[@]}" commit --quiet -m "fifth: three src files, the tripping one sorting last" > /dev/null

  write_cfg() {
    cat > "$WORK/$1" <<CFG
version: 1
defaults:
  mode: batch
  severity: block
checks:
  - id: measurable-one
    why: fires when src/bad.txt is present
    when:
      paths: ["src/**"]
    requires: [./tools/fires-on-bad.sh]
    mode: batch
    command: [./tools/fires-on-bad.sh, "{files}"]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
  - id: never-triggers
    why: its trigger paths do not exist in this history
    when:
      paths: ["nowhere/**"]
    requires: [./tools/fires-on-bad.sh]
    mode: batch
    command: [./tools/fires-on-bad.sh, "{files}"]
    exit_codes:
      pass: [0]
      fail: [1]
  - id: switched-off
    enabled: false
    why: a shut guard
    when:
      always: true
    requires: [./tools/fires-on-bad.sh]
    mode: batch
    command: [./tools/fires-on-bad.sh]
    exit_codes:
      pass: [0]
      fail: [1]
  - id: needs-history
    why: declares git, so an extracted tree cannot answer for it
    when:
      always: true
    requires: [./tools/fires-on-bad.sh, git]
    mode: batch
    command: [./tools/fires-on-bad.sh]
    exit_codes:
      pass: [0]
      fail: [1]
  - id: tool-not-here
    why: names a tool this machine does not have
    when:
      always: true
    requires: [a-tool-that-is-not-installed-anywhere]
    mode: batch
    command: [a-tool-that-is-not-installed-anywhere]
    exit_codes:
      pass: [0]
      fail: [1]
  - id: outlives-its-child
    why: it backgrounds a sleep and waits, so a child-only kill leaves the pipe held
    when:
      paths: ["src/**"]
    requires: [./tools/hangs.sh]
    mode: batch
    command: [./tools/hangs.sh, "{files}"]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
  - id: per-file-fold
    why: per_file, and its tool fires on one path that sorts last
    when:
      paths: ["src/**"]
    requires: [./tools/fires-on-trip.sh]
    mode: per_file
    command: [./tools/fires-on-trip.sh, "{file}"]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
  - id: late-tool
    why: its tool exists only at the newest commit
    when:
      paths: ["src/**"]
    requires: [./tools/late-arrival.sh]
    mode: batch
    command: [./tools/late-arrival.sh, "{files}"]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
  - id: locates-its-own-root
    why: it calls git rev-parse --show-toplevel and declares no dependency on git
    when:
      paths: ["src/**"]
    requires: [./tools/needs-root.sh]
    mode: batch
    command: [./tools/needs-root.sh, "{files}"]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
  - id: always-refuses
    why: its tool exits 2 on every commit, so nothing is ever examined
    when:
      paths: ["src/**"]
    requires: [./tools/always-refuses.sh]
    mode: batch
    command: [./tools/always-refuses.sh, "{files}"]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
  - id: reads-last-commit
    why: declares git and reads the last commit, so only a real history can answer for it
    when:
      always: true
    requires: [./tools/reads-last-commit.sh, git]
    mode: batch
    command: [./tools/reads-last-commit.sh]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
  - id: sees-no-future
    why: fires when the repository it is handed holds a commit HEAD cannot reach
    when:
      always: true
    requires: [./tools/sees-no-future.sh, git]
    mode: batch
    command: [./tools/sees-no-future.sh]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
  - id: leaks-tmp
    why: makes a directory under TMPDIR and is then killed on timeout
    when:
      paths: ["src/**"]
    requires: [./tools/leaks-tmp.sh]
    mode: batch
    command: [./tools/leaks-tmp.sh, "{files}"]
    exit_codes:
      pass: [0]
      fail: [1]
      refused: [2]
  - id: no-command-at-all
    why: nothing to run
    when:
      always: true
    requires: [./tools/fires-on-bad.sh]
    mode: batch
    exit_codes:
      pass: [0]
      fail: [1]
CFG
  }
  write_cfg checks.yaml
  printf 'this is not yaml at all: [\n' > "$WORK/broken.yaml"

  CASES=0; UPHELD=0; REPORT=""; CODES=""

  # `|| GOT=$?` on the SAME line as the command, because a pipeline or a command
  # substitution in an argument list resets $? and reading it a line later is how
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

  # --- 0: measured ---------------------------------------------------------
  drive measured 0 "a replayable check over three commits yields a rate" \
    --root "$REPO" --config "$WORK/checks.yaml" --check measurable-one
  drive listed 0 "--list reports measurability for every check in the config" \
    --root "$REPO" --config "$WORK/checks.yaml" --list
  drive measured-since 0 "the range given as --since rather than --commits" \
    --root "$REPO" --config "$WORK/checks.yaml" --check measurable-one --since HEAD~2

  # --- 2: could not run ----------------------------------------------------
  drive unknown-check 2 "a check id the config does not declare" \
    --root "$REPO" --config "$WORK/checks.yaml" --check no-such-check
  drive no-config 2 "the named config is not there" \
    --root "$REPO" --config "$WORK/there-is-no-config.yaml" --check measurable-one
  drive unparseable 2 "a config that is not YAML" \
    --root "$REPO" --config "$WORK/broken.yaml" --check measurable-one
  drive bad-usage 2 "an option this script does not take" \
    --root "$REPO" --config "$WORK/checks.yaml" --frobnicate
  drive both-modes 2 "--list and --check ask different questions" \
    --root "$REPO" --config "$WORK/checks.yaml" --list --check measurable-one
  drive not-a-repo 2 "a root that is not a git work tree" \
    --root "$WORK" --config "$WORK/checks.yaml" --check measurable-one

  # --- 3: cannot be measured over history ----------------------------------
  drive disabled 3 "a disabled check - a shut guard, rate n/a and not 0%" \
    --root "$REPO" --config "$WORK/checks.yaml" --check switched-off
  drive needs-history 3 "a check declaring git, which an extracted tree cannot answer for" \
    --root "$REPO" --config "$WORK/checks.yaml" --check needs-history
  drive tool-absent 3 "a check whose tool is not on this machine - rate ?, not 0%" \
    --root "$REPO" --config "$WORK/checks.yaml" --check tool-not-here
  drive no-command 3 "a check with no command to run" \
    --root "$REPO" --config "$WORK/checks.yaml" --check no-command-at-all

  # --- 4: measured nothing -------------------------------------------------
  drive never-triggers 4 "the check triggered on no commit, so the rate is n/a" \
    --root "$REPO" --config "$WORK/checks.yaml" --check never-triggers
  drive no-verdict 4 "it triggered and refused every time, so there is no denominator" \
    --root "$REPO" --config "$WORK/checks.yaml" --check always-refuses
  drive locates-root 0 "a tool that finds its own root with git gets a verdict, because the extracted tree is given an empty repository" \
    --root "$REPO" --config "$WORK/checks.yaml" --check locates-its-own-root
  drive late-tool 0 "a tool absent from the older trees lands in its own bucket, never in pass" \
    --root "$REPO" --config "$WORK/checks.yaml" --check late-tool
  drive per-file-fold 0 "a per_file check is invoked for every triggering file, not only the first" \
    --root "$REPO" --config "$WORK/checks.yaml" --check per-file-fold
  drive timed-out 4 "every replay outran the limit, so nothing was examined and there is no rate" \
    --root "$REPO" --config "$WORK/checks.yaml" --check outlives-its-child --per-run-timeout 1
  CASES=$((CASES + 1))
  ALIVE="$(pgrep -f "$GC_TOKEN" | wc -l | tr -d ' ')" || ALIVE=0
  pkill -f "$GC_TOKEN" || :
  if [ "$ALIVE" = "0" ]; then UPHELD=$((UPHELD + 1)); V="held"; else V="NOT HELD"; fi
  REPORT="$REPORT      group-kill  expected 0 alive  got $ALIVE alive  $V  the timeout killed the whole process group: no grandchild of a timed-out replay is still running
"

  # --- --history clone ----------------------------------------------------
  drive empty-history-refuses 3 "a check reading the last commit is unmeasurable without --history clone" \
    --root "$REPO" --config "$WORK/checks.yaml" --check reads-last-commit
  drive clone-reads-history 0 "with --history clone the same check reads the real last commit of each tree" \
    --root "$REPO" --config "$WORK/checks.yaml" --check reads-last-commit --history clone
  drive clone-no-future 0 "a cloned tree holds nothing its HEAD cannot reach" \
    --root "$REPO" --config "$WORK/checks.yaml" --check sees-no-future --history clone
  drive listed-clone 0 "--list under --history clone counts the git-declaring checks as replayable" \
    --root "$REPO" --config "$WORK/checks.yaml" --list --history clone
  drive bad-history 2 "--history takes empty or clone and nothing else" \
    --root "$REPO" --config "$WORK/checks.yaml" --check measurable-one --history sideways

  # --- a SIGKILLed child leaves nothing in the caller's TMPDIR ----------------
  mkdir -p "$WORK/outer-tmp"
  NAME="tmp-contained"; GOT=0
  TMPDIR="$WORK/outer-tmp" bash "$0" --root "$REPO" --config "$WORK/checks.yaml" \
    --check leaks-tmp --per-run-timeout 1 > "$WORK/$NAME.out" 2> "$WORK/$NAME.err" || GOT=$?
  CASES=$((CASES + 1))
  LEFT="$(find "$WORK/outer-tmp" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
  if [ "$GOT" = "4" ] && [ "$LEFT" = "0" ]; then UPHELD=$((UPHELD + 1)); V="held"; else V="NOT HELD"; fi
  CODES="$CODES$GOT
"
  REPORT="$REPORT      $NAME  expected 4 and 0 entries left  got $GOT and $LEFT  $V  a replay killed on timeout made a directory under TMPDIR, and none of it is left in the caller's TMPDIR
"

  # Sentences, not only codes, on the rows carrying this tool's central claims.
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
  assert_says measured 'fire rate over merged history: 1/4 = 25.0%' \
    "one fire over the four commits that triggered - the commit that only DELETES src/bad.txt does not trigger, because a deleted path is not handed to a check"
  assert_says measured 'UPPER BOUND ON OVER-FIRE, NOT AN OVER-FIRE RATE' \
    "the figure is never called an over-fire rate"
  assert_says never-triggers 'fire rate: n/a' \
    "no triggering commit prints n/a, never 0%"
  assert_says disabled 'fire rate: n/a' \
    "a shut guard prints n/a, never 0%"
  assert_says tool-absent 'fire rate: ?' \
    "an absent tool prints ?, never 0%"
  assert_says locates-root 'fire rate over merged history: 0/4 = 0.0%' \
    "without the empty git repository in the extracted tree this tool refuses on every commit and no rate exists"
  assert_says late-tool 'tool absent at that commit     2' \
    "the two oldest trees do not carry the tool, and neither is counted as a pass"
  assert_says per-file-fold 'fire rate over merged history: 1/4 = 25.0%' \
    "the fire is on the LAST of three triggering files, so only visiting them all finds it"
  assert_says timed-out 'timed out                      4' \
    "all four triggering commits outran the limit, and a timeout is never a pass"
  assert_says no-verdict 'verdict on none of them' \
    "every replay refused, so no rate is printed rather than a 0.0% one"
  assert_says measured 'the denominator' \
    "the denominator is named in the output, because which commits are under the line is the whole argument"
  assert_says clone-reads-history 'fire rate over merged history: 1/5 = 20.0%' \
    "one fire over five commits: only the commit that ADDED src/bad.txt has it in its last commit, which only a real per-commit history shows"
  assert_says clone-reads-history 'history: CLONE' \
    "the history mode is printed, so a rate taken over a clone is never read as one taken over an empty repository"
  assert_says clone-no-future 'fire rate over merged history: 0/5 = 0.0%' \
    "no replayed repository can see a commit after the one it was built at"
  assert_says listed-clone 'measurable: 11 of 14' \
    "the three checks declaring git are replayable once the history is real"
  assert_says listed 'measurable: 8 of 14' \
    "without --history clone the same three are not"
  WORDED=$((WORDED + 1))
  if grep -q 'measure-check-overfire: \[1/5\] ' "$WORK/measured.err"; then
    WORDED_OK=$((WORDED_OK + 1)); W="held"
  else
    W="NOT HELD"
  fi
  REPORT="$REPORT      wording:progress  $W  a progress line per commit goes to stderr, so a long replay is never silent
"

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"
  if [ "$CASES" = "$UPHELD" ] && [ "$WORDED" = "$WORDED_OK" ]; then
    SELF_VERDICT="held"
  else
    SELF_VERDICT="NOT HELD"
  fi
  printf '    R39.s  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$CASES" "$UPHELD" "$SELF_VERDICT" \
    "each case exits the code it declares, and twenty rows also assert the sentence"
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 2 3 4; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 2 3 4\n' "$REACHED"
  printf '    NOT ASSERTED: the undeclared-exit bucket is not driven - every fixture tool returns a code its own config declares. The group kill on timeout IS asserted (group-kill): until 1.1 it was exercised but not asserted, because its fixture grandchild exited by itself after 5s.\n'
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
[ -n "$MODE" ] || die_unmeasured "give --list or --check ID. Measuring nothing would print a rate nobody took."
command -v python3 >/dev/null 2>&1 \
  || die_unmeasured "python3 is not installed, so checks.yaml could not be read"
command -v git >/dev/null 2>&1 \
  || die_unmeasured "git is not installed, so no tree could be obtained"
[ -z "$COMMITS" ] || [ -z "$SINCE" ] \
  || die_unmeasured "--commits and --since name the range two ways; give one"
# 30 by default, which is the window the rule in references/risk-and-calibration.md
# proposes a check must clear to earn `block`. A default that disagreed with the
# rule would make the common invocation answer a question nobody asked.
[ -n "$COMMITS" ] || COMMITS="30"

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" \
    || die_unmeasured "no git work tree here and --root was not given"
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

[ -n "$CONFIG_REL" ] || CONFIG_REL=".claude/productizer/checks.yaml"
case "$CONFIG_REL" in
  /*) CONFIG="$CONFIG_REL" ;;
  *)  CONFIG="$ROOT/$CONFIG_REL" ;;
esac
[ -r "$CONFIG" ] \
  || die_unmeasured "no readable config at $CONFIG. Nothing was measured, which is not a fire rate of zero."

# mktemp IS GIVEN AN EXPLICIT TEMPLATE UNDER $TMPDIR. Measured on this
# machine: macOS /usr/bin/mktemp -d with no template IGNORES TMPDIR and writes
# to the per-user temp directory whatever TMPDIR says. So a bare `mktemp -d`
# cannot be redirected, and neither the scratch-directory guard nor the
# containment of a killed child could be tested through it.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/measure-check-overfire.XXXXXX")" \
  || die_unmeasured "could not make a temporary directory"
# EXIT covers the ordinary path; INT and TERM are trapped separately because a
# fatal signal terminates the shell without running the EXIT trap, and that is
# how five interrupted runs each left several megabytes of extracted tree behind.
trap 'rm -rf "$TMP"' EXIT
trap 'rm -rf "$TMP"; exit 130' INT
trap 'rm -rf "$TMP"; exit 143' TERM

set +e
python3 -c "$ENGINE" "$MODE" "$CONFIG" "$ROOT" "$CHECK_ID" "$COMMITS" "$SINCE" "$PER_RUN_TIMEOUT" "$TMP" "$HISTORY"
RC=$?
set -e
exit "$RC"
