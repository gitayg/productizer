#!/usr/bin/env python3
"""check-ci-template.py [PATH] [--selftest] [--version] [--help]

Static assertions over the copyable unattended-run workflow,
templates/build-from-spec.yml by default, or the workflow at PATH.

WHY THIS EXISTS. The template is copied into other people's repositories and
runs a model there with their secrets. Its guarantees - a person dispatches,
no write token sits beside the model, nothing is interpolated into a shell -
are properties of the YAML, and one careless edit removes any of them while
every script it calls stays green. So the properties are checked on the file
itself, not argued in its comments.

WHAT IT ASSERTS, each a separate finding:
  trigger        the only trigger is workflow_dispatch, and pull_request_target
                 appears nowhere
  top-perms      the top-level permissions are exactly contents: read
  write-scope    a write permission appears only in the job named deliver
  agent-job      the job that runs anthropics/claude-code-action has no write
                 permission, and every checkout in it sets
                 persist-credentials: false
  deny-bash      the step that runs the agent action denies the agent a shell:
                 its `claude_args` carries a standalone `--disallowedTools Bash`
                 (the whole Bash tool, not just `Bash(git:*)`). A shell is the
                 vector by which a prompt-injected agent in this read-only job
                 could tamper with a file a later token-holding step runs; the
                 maintainer ruled on 2026-10-11 that CI never gives it one
  post-agent-env every run: step that follows the agent action inside the
                 agent's own job pins BASH_ENV to the empty string, so no
                 startup file an agent-influenced environment could name is
                 sourced by a post-agent shell that reads the edited tree
  write-job-no-repo-code
                 a job holding any write permission runs no code from the
                 repository it writes to, by a rule read off the YAML: it has
                 no local action (`uses: ./...`); no run: names an interpreter
                 or package runner (python, python3, node, bun, deno, ruby,
                 perl, php, npm, npx, yarn, pnpm, make) or pr-spec-comment.sh,
                 sources a file, or runs a `./` path; and every `bash`/`sh`
                 invocation runs a script under $RUNNER_TEMP, where the template
                 stages the pinned productizer scripts after verifying their
                 commit. LIMITS: it reads the run: text, so an interpreter a
                 staged script itself starts is not seen (the staged scripts are
                 productizer's own, pinned by commit); a command spelled through
                 a variable or an alias is not seen; git and gh are allowed, and
                 what they run - hooks, filters, extensions - is the scripts'
                 hardening, not this rule's
  pinned         every `uses:` is pinned to a full 40-character commit id
  run-injection  no `${{` expression of any context inside a run: - not only
                 github.event and inputs, but steps, needs, env, matrix,
                 github.head_ref and the rest, any of which can carry
                 attacker-influenced text into the shell. Every value reaches a
                 run: through env:, where it is data, not script text
  swallow        no continue-on-error, and no `|| true` or `2>/dev/null` in a
                 run:
  no-bypass      neither `bypassPermissions` nor `--dangerously-skip-permissions`
                 appears anywhere in the workflow outside its comments. A
                 repository's own committed defaultMode is its owner's choice;
                 the template never produces one (maintainer ruling 2026-10-10)
  perms-input    workflow_dispatch has a `permissions` input of type choice,
                 default `repo-settings`, whose options are drawn only from
                 repo-settings and edits-only - each of which can only narrow
                 the repository's committed Claude Code settings
  tools-pin      the top-level env PRODUCTIZER_SHA is a quoted string of 40
                 lower-case hex digits: the all-zero placeholder the first step
                 refuses, or a full commit id. An unquoted all-digit value is a
                 YAML number, so it is refused too. Every checkout of
                 ${{ env.PRODUCTIZER_REPO }} uses ref: ${{ env.PRODUCTIZER_SHA }}
  guards         the runtime guards are present, in place, as the exact lines
                 the template ships (B118). In prepare's first step: the
                 default-branch refusal and both PRODUCTIZER_SHA refusals. In
                 the agent's job: a step with id `args`, before the agent, that
                 calls `build-dispatch.sh agent-args . --out "$GITHUB_OUTPUT"`
                 (the self-tested check of the agent's flags), and the agent's
                 claude_args reading `steps.args.outputs.claude_args`; then a
                 step between them that copies build-dispatch.sh to
                 $RUNNER_TEMP, stash-gits .git there and removes the tools
                 checkout; and after the agent a step that removes the run data
                 and captures from the $RUNNER_TEMP copy with the same git-dir.
                 In every write job: the step that checks the tools checkout IS
                 PRODUCTIZER_SHA with nothing changed, then stages it under
                 $RUNNER_TEMP, before any step that runs the staged copy.
                 LIMITS: lines are matched in order with whitespace and
                 comments ignored, not as one block, so a guard line made
                 unreachable (after an earlier exit 0, say) is not seen

WHAT IT DOES NOT. It reads one file and runs nothing. It cannot tell whether a
pinned commit is the release its comment names, whether the scripts the
workflow calls behave, or whether GitHub enforces what the file declares. A
job with no agent step is not called safe: the agent job could not be found,
so its assertions could not run, and that is exit 2.

PyYAML reads `on:` as the boolean True (YAML 1.1). Both spellings are read.

Exit codes:
  0  every assertion held
  1  at least one finding, each printed with its assertion and location
  2  could not run: bad usage, an unreadable or unparseable file, PyYAML
     missing, or no job running the agent
--selftest runs over fixtures/ci-template/ and exits 0 when every case held,
1 when one did not.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

VERSION = "check-ci-template 1.0"
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PATH = os.path.join(HERE, "..", "templates", "build-from-spec.yml")
FIXTURES = os.path.join(HERE, "..", "fixtures", "ci-template")

AGENT_ACTION = "anthropics/claude-code-action"
# A standalone denial of the whole Bash tool. `Bash` must not be followed by a
# `(`, so `--disallowedTools "Bash(git:*)"` - a denial of only git through Bash
# - does not satisfy it; the whole shell must be gone.
DENY_BASH_RX = re.compile(r"--disallowedTools\s+[\"']?Bash(?![\w(])")
BYPASS_WORDS = ("bypassPermissions", "dangerously-skip-permissions")
PERMS_OPTIONS = ("repo-settings", "edits-only")
PIN_RX = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}$")
REPO_CODE_WORDS = ("python", "python3", "node", "bun", "deno", "ruby", "perl", "php",
                   "npm", "npx", "yarn", "pnpm", "make")
REPO_CODE_RX = re.compile(r"(?<![\w./$-])(%s)(?![\w.-])" % "|".join(REPO_CODE_WORDS))
SHELL_SCRIPT_RX = re.compile(r"(?<![\w./-])(?:bash|sh)((?:\s+-[-\w]+)*)\s+(\S+)")
SOURCE_RX = re.compile(r"(?:^|[\s;&|(])source\s+\S")
DOT_SLASH_RX = re.compile(r"(?:^|[\s;&|(])\./\S")
TEMP_PREFIXES = ('"$RUNNER_TEMP/', "$RUNNER_TEMP/", '"${RUNNER_TEMP}/', "${RUNNER_TEMP}/")
INJECT_RX = re.compile(r"\$\{\{[^\n]*?(?:\}\}|$)", re.M)
SHA_RX = re.compile(r"[0-9a-f]{40}")
ZERO_SHA = "0" * 40
TOOLS_REF = "${{ env.PRODUCTIZER_SHA }}"
ARGS_REF = "${{ steps.args.outputs.claude_args }}"
# The runtime guards, as the exact lines the template ships (whitespace
# collapsed). Each tuple is matched in order inside one step's run:.
PIN_GUARD = ('if [ "$REF" != "refs/heads/$DEFAULT_BRANCH" ]; then', "exit 1",
             'if [ "$PRODUCTIZER_SHA" = "%s" ]; then' % ZERO_SHA, "exit 1",
             'if ! [[ "$PRODUCTIZER_SHA" =~ ^[0-9a-f]{40}$ ]]; then', "exit 1")
ARGS_GUARD = ('bash "$TOOLS/build-dispatch.sh" agent-args . --out "$GITHUB_OUTPUT"',)
STASH_GUARD = ('cp "$TOOLS/build-dispatch.sh" "$RUNNER_TEMP/build-dispatch.sh"',
               'bash "$RUNNER_TEMP/build-dispatch.sh" stash-git . --git-dir "$RUNNER_TEMP/productizer-gitdir"',
               "rm -rf .productizer-tools")
CAPTURE_GUARD = ("rm -rf .productizer-run",
                 'bash --noprofile --norc "$RUNNER_TEMP/build-dispatch.sh" capture . '
                 '--git-dir "$RUNNER_TEMP/productizer-gitdir" --out "$RUNNER_TEMP/productizer.patch"')
VERIFY_GIT = "git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C .productizer-tools"
VERIFY_GUARD = ('got="$(%s rev-parse HEAD)"' % VERIFY_GIT,
                'if [ "$got" != "$PRODUCTIZER_SHA" ]; then', "exit 1",
                'dirty="$(%s status --porcelain --untracked-files=all)"' % VERIFY_GIT,
                'if [ -n "$dirty" ]; then', "exit 1",
                'cp -R "$TOOLS" "$RUNNER_TEMP/productizer-tools"',
                "rm -rf .productizer-tools")
STAGED_TOOLS = "$RUNNER_TEMP/productizer-tools"
SWALLOW = (("|| true", re.compile(r"\|\|\s*true\b")),
           ("2>/dev/null", re.compile(r"2>\s*/dev/null")))


def die(msg):
    sys.stderr.write("check-ci-template: %s\n" % msg)
    raise SystemExit(2)


def load(path):
    try:
        import yaml
    except ImportError:
        die("PyYAML is not importable, so %s was not read. Nothing was checked." % path)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            doc = yaml.safe_load(fh)
    except OSError as exc:
        die("could not read %s: %s. Nothing was checked." % (path, exc.strerror))
    except yaml.YAMLError as exc:
        die("%s is not parseable YAML: %s" % (path, str(exc).replace("\n", " ")))
    if not isinstance(doc, dict):
        die("%s is not a workflow: its top level is not a mapping" % path)
    return doc


def triggers(doc):
    on = doc["on"] if "on" in doc else doc.get(True)
    if isinstance(on, str):
        return [on]
    if isinstance(on, list):
        return [str(t) for t in on]
    if isinstance(on, dict):
        return [str(t) for t in on]
    return []


def write_perms(perms):
    """The permission names a `permissions:` value grants write on."""
    if perms is None:
        return []
    if isinstance(perms, str):
        return ["write-all"] if perms.strip() == "write-all" else []
    if isinstance(perms, dict):
        return sorted(str(k) for k, v in perms.items() if str(v).strip() == "write")
    return ["unreadable permissions value"]


def walk_uses(doc):
    """(location, uses) for every job-level and step-level uses:."""
    for jname, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        if "uses" in job:
            yield "jobs.%s.uses" % jname, str(job["uses"])
        for i, step in enumerate(job.get("steps") or []):
            if isinstance(step, dict) and "uses" in step:
                yield "jobs.%s.steps[%d]" % (jname, i), str(step["uses"])


def walk_runs(doc):
    for jname, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        for i, step in enumerate(job.get("steps") or []):
            if isinstance(step, dict) and "run" in step:
                yield "jobs.%s.steps[%d]" % (jname, i), str(step["run"])


def strings(node):
    """Every key and scalar in the parsed workflow. Comments never reach here."""
    if isinstance(node, dict):
        for k, v in node.items():
            yield str(k)
            for x in strings(v):
                yield x
    elif isinstance(node, list):
        for v in node:
            for x in strings(v):
                yield x
    elif node is not None:
        yield str(node)


def has_key(node, key):
    if isinstance(node, dict):
        return any(k == key or has_key(v, key) for k, v in node.items())
    if isinstance(node, list):
        return any(has_key(v, key) for v in node)
    return False


def guard_lines(run):
    """A run: as guards read it: continuations joined, whitespace collapsed,
    blank and comment-only lines dropped."""
    out = []
    for line in re.sub(r"\\\n\s*", " ", run).splitlines():
        line = " ".join(line.split())
        if line and not line.startswith("#"):
            out.append(line)
    return out


def first_missing(run, required):
    """The first required line not found, in order, in run; None when all are."""
    lines, i = guard_lines(run), 0
    for req in required:
        while i < len(lines) and lines[i] != req:
            i += 1
        if i == len(lines):
            return req
        i += 1
    return None


def is_agent(step):
    return str(step.get("uses", "")).split("@")[0] == AGENT_ACTION


def guard_step(steps, lo, hi, marker, required, where, what, find):
    """The first step in steps[lo:hi] whose run: names marker must hold the
    required lines; no such step, or a line missing, is a finding."""
    for i in range(max(lo, 0), min(hi, len(steps))):
        run = steps[i].get("run")
        if run is not None and marker in " ".join(str(run).split()):
            miss = first_missing(str(run), required)
            if miss:
                find("guards", "%s.steps[%d]" % (where, i),
                     "the %s step is missing the line: %s" % (what, miss))
            return
    find("guards", where, "no %s step: a run: calling %s must be there" % (what, marker))


def check_guards(jobs, find):
    def steps_of(job):
        return [s for s in (job.get("steps") or []) if isinstance(s, dict)]

    prep = jobs.get("prepare")
    psteps = steps_of(prep) if isinstance(prep, dict) else []
    if not psteps or "run" not in psteps[0]:
        find("guards", "jobs.prepare.steps[0]", "prepare's first step must be the run: that "
             "refuses a dispatch off the default branch and an unpinned PRODUCTIZER_SHA, "
             "before anything is checked out")
    else:
        miss = first_missing(str(psteps[0]["run"]), PIN_GUARD)
        if miss:
            find("guards", "jobs.prepare.steps[0]",
                 "the refusal step is missing the line: %s" % miss)

    for jname, job in jobs.items():
        if not isinstance(job, dict):
            continue
        steps, where = steps_of(job), "jobs.%s" % jname
        agent_idx = next((i for i, s in enumerate(steps) if is_agent(s)), None)
        if agent_idx is not None:
            args_idx = next((i for i, s in enumerate(steps) if s.get("id") == "args"), None)
            if args_idx is None or args_idx > agent_idx or "run" not in steps[args_idx]:
                find("guards", where, "no run: step with id args before the agent action: "
                     "the agent's flags must pass build-dispatch.sh agent-args first")
                args_idx = -1
            else:
                miss = first_missing(str(steps[args_idx]["run"]), ARGS_GUARD)
                if miss:
                    find("guards", "%s.steps[%d]" % (where, args_idx),
                         "the args step is missing the line: %s" % miss)
            cargs = " ".join(str((steps[agent_idx].get("with") or {}).get("claude_args")
                                 or "").split())
            if ARGS_REF not in cargs:
                find("guards", "%s.steps[%d].with.claude_args" % (where, agent_idx),
                     "the agent's claude_args must read %s, the flags agent-args checked"
                     % ARGS_REF)
            guard_step(steps, args_idx + 1, agent_idx, "stash-git", STASH_GUARD,
                       where, "stash-git (between the args step and the agent)", find)
            guard_step(steps, agent_idx + 1, len(steps), " capture ", CAPTURE_GUARD,
                       where, "capture (after the agent)", find)
        if write_perms(job.get("permissions")):
            users = [i for i, s in enumerate(steps) if STAGED_TOOLS in str(s.get("run", ""))]
            vidx = next((i for i, s in enumerate(steps)
                         if VERIFY_GIT + " rev-parse HEAD" in " ".join(str(s.get("run", "")).split())),
                        None)
            if vidx is None:
                if users:
                    find("guards", where, "a write job runs the staged productizer scripts, "
                         "but no step first checks the tools checkout is PRODUCTIZER_SHA")
                continue
            miss = first_missing(str(steps[vidx]["run"]), VERIFY_GUARD)
            if miss:
                find("guards", "%s.steps[%d]" % (where, vidx),
                     "the tools-verification step is missing the line: %s" % miss)
            early = [i for i in users if i < vidx]
            if early:
                find("guards", "%s.steps[%d]" % (where, early[0]), "runs the staged "
                     "productizer scripts before the step that verifies them")


def check_tools_pin(doc, find):
    env = doc.get("env")
    env = env if isinstance(env, dict) else {}
    sha, repo = env.get("PRODUCTIZER_SHA"), env.get("PRODUCTIZER_REPO", "<owner>/productizer")
    if not isinstance(sha, str) or not SHA_RX.fullmatch(sha):
        find("tools-pin", "env.PRODUCTIZER_SHA", "must be a quoted string of 40 lower-case "
             "hex digits - the all-zero placeholder, refused at run time, or the full commit "
             "id of the productizer release you reviewed (git ls-remote https://github.com/%s "
             "'refs/tags/vX.Y.Z^{}'); found %r" % (repo, sha))
    for jname, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        for i, s in enumerate(job.get("steps") or []):
            if not isinstance(s, dict) or str(s.get("uses", "")).split("@")[0] != "actions/checkout":
                continue
            w = s.get("with") or {}
            if "PRODUCTIZER_REPO" in str(w.get("repository", "")) and \
                    " ".join(str(w.get("ref", "")).split()) != TOOLS_REF:
                find("tools-pin", "jobs.%s.steps[%d].with.ref" % (jname, i),
                     "the productizer tools checkout must use ref: %s; found %r"
                     % (TOOLS_REF, w.get("ref")))
    return isinstance(sha, str) and sha == ZERO_SHA


def check(path):
    doc = load(path)
    findings = []

    def find(kind, where, what):
        findings.append("%-13s %s: %s" % (kind, where, what))

    trig = triggers(doc)
    if trig != ["workflow_dispatch"]:
        find("trigger", "on", "the only trigger must be workflow_dispatch; found %s"
             % (", ".join(trig) or "none"))
    with open(path, "r", encoding="utf-8") as fh:
        if "pull_request_target" in fh.read():
            find("trigger", "file", "pull_request_target appears in the workflow")

    top = doc.get("permissions")
    if top != {"contents": "read"}:
        find("top-perms", "permissions", "must be exactly contents: read; found %r" % (top,))

    jobs = doc.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        die("%s has no jobs mapping" % path)

    agent_jobs = []
    for jname, job in jobs.items():
        if not isinstance(job, dict):
            continue
        writes = write_perms(job.get("permissions"))
        if writes and jname != "deliver":
            find("write-scope", "jobs.%s.permissions" % jname,
                 "write on %s outside the deliver job" % ", ".join(writes))
        steps = [s for s in (job.get("steps") or []) if isinstance(s, dict)]
        if any(str(s.get("uses", "")).split("@")[0] == AGENT_ACTION for s in steps):
            agent_jobs.append(jname)
            if writes:
                find("agent-job", "jobs.%s.permissions" % jname,
                     "the agent job holds write on %s" % ", ".join(writes))
            if "permissions" not in job:
                find("agent-job", "jobs.%s" % jname,
                     "the agent job declares no permissions of its own")
            # Every run: step AFTER the agent action, in the agent's own job,
            # reads a tree the agent edited. Such a shell must not source a
            # startup file named by an environment the agent could have
            # influenced, so BASH_ENV is pinned empty. ENV is pinned beside it
            # in the template for POSIX sh; only BASH_ENV is required here,
            # because the steps run bash.
            agent_idx = next((i for i, s in enumerate(steps)
                              if str(s.get("uses", "")).split("@")[0] == AGENT_ACTION), None)
            if agent_idx is not None:
                for i in range(agent_idx + 1, len(steps)):
                    s = steps[i]
                    if "run" not in s:
                        continue
                    env = s.get("env")
                    be = env.get("BASH_ENV") if isinstance(env, dict) else None
                    if str(be) != "":
                        find("post-agent-env", "jobs.%s.steps[%d]" % (jname, i),
                             "a run: step after the agent action must pin BASH_ENV to the "
                             "empty string; a post-agent shell in the agent's job reads the "
                             "tree the agent edited and must source no agent-named startup file")
            for i, s in enumerate(steps):
                if str(s.get("uses", "")).split("@")[0] == "actions/checkout":
                    pc = (s.get("with") or {}).get("persist-credentials")
                    if str(pc).strip().lower() != "false":
                        find("agent-job", "jobs.%s.steps[%d]" % (jname, i),
                             "checkout in the agent job must set persist-credentials: false")
                if str(s.get("uses", "")).split("@")[0] == AGENT_ACTION:
                    cargs = str((s.get("with") or {}).get("claude_args") or "")
                    if not DENY_BASH_RX.search(cargs):
                        find("deny-bash", "jobs.%s.steps[%d].with.claude_args" % (jname, i),
                             "the agent action step must deny the agent a shell with a "
                             "standalone --disallowedTools Bash (never a shell in CI); a "
                             "Bash(git:*) deny alone does not satisfy it")
    for jname, job in jobs.items():
        if not isinstance(job, dict) or not write_perms(job.get("permissions")):
            continue
        for i, s in enumerate(job.get("steps") or []):
            if not isinstance(s, dict):
                continue
            where = "jobs.%s.steps[%d]" % (jname, i)
            if str(s.get("uses", "")).startswith("./"):
                find("write-job-no-repo-code", where, "a job holding a write token runs a "
                     "local action, which is code from the repository it writes to: %s"
                     % s.get("uses"))
            if "run" not in s:
                continue
            run = str(s["run"])
            m = REPO_CODE_RX.search(run)
            if m:
                find("write-job-no-repo-code", where, "a job holding a write token names "
                     "%s in a run:; it must execute no code from the repository it writes to"
                     % m.group(1))
            if "pr-spec-comment.sh" in run:
                find("write-job-no-repo-code", where, "a job holding a write token runs "
                     "pr-spec-comment.sh, which runs the repository's solver probe; render "
                     "the body in a job with no write token")
            if SOURCE_RX.search(run) or DOT_SLASH_RX.search(run):
                find("write-job-no-repo-code", where, "a job holding a write token sources "
                     "a file or runs a ./ path from the workspace")
            for sm in SHELL_SCRIPT_RX.finditer(run):
                target = sm.group(2)
                if not target.startswith(TEMP_PREFIXES):
                    find("write-job-no-repo-code", where, "a job holding a write token runs "
                         "a shell script that is not staged under $RUNNER_TEMP: %s" % target)
    if not agent_jobs:
        die("no job in %s runs %s, so the agent job's assertions could not run. "
            "Unmeasured, not clean." % (path, AGENT_ACTION))

    for where, uses in walk_uses(doc):
        if not PIN_RX.match(uses):
            find("pinned", where, "not pinned to a full commit id: %s" % uses)

    for where, run in walk_runs(doc):
        m = INJECT_RX.search(run)
        if m:
            find("run-injection", where, "an expression is interpolated into the script: %s"
                 % m.group(0).strip())
        for label, rx in SWALLOW:
            if rx.search(run):
                find("swallow", where, "%s hides a failure" % label)

    if has_key(doc, "continue-on-error"):
        find("swallow", "file", "continue-on-error turns a failed step green")

    check_guards(jobs, find)
    placeholder = check_tools_pin(doc, find)

    for word in BYPASS_WORDS:
        if any(word in x for x in strings(doc)):
            find("no-bypass", "file", "%s appears outside a comment; the template never "
                 "produces a permission bypass" % word)

    on = doc["on"] if "on" in doc else doc.get(True)
    wd = on.get("workflow_dispatch") if isinstance(on, dict) else None
    inputs = (wd or {}).get("inputs") if isinstance(wd, dict) else None
    perm = inputs.get("permissions") if isinstance(inputs, dict) else None
    if not isinstance(perm, dict):
        find("perms-input", "on.workflow_dispatch.inputs", "no permissions input; the "
             "dispatching person has no way to narrow the agent's permissions")
    else:
        if perm.get("type") != "choice":
            find("perms-input", "inputs.permissions", "must be type choice, not %r: free "
                 "text must not reach the agent's arguments" % (perm.get("type"),))
        if perm.get("default") != "repo-settings":
            find("perms-input", "inputs.permissions", "default must be repo-settings; "
                 "found %r" % (perm.get("default"),))
        opts = perm.get("options") or []
        extra = [str(o) for o in opts if str(o) not in PERMS_OPTIONS]
        if extra or "repo-settings" not in [str(o) for o in opts]:
            find("perms-input", "inputs.permissions", "options must include repo-settings "
                 "and be drawn only from %s; found %s"
                 % (", ".join(PERMS_OPTIONS), ", ".join(str(o) for o in opts) or "none"))

    return findings, placeholder


ASSERTIONS = ("trigger", "top-perms", "write-scope", "agent-job", "deny-bash",
              "post-agent-env", "write-job-no-repo-code", "pinned", "run-injection", "swallow", "no-bypass",
              "perms-input", "tools-pin", "guards")


def report(path):
    findings, placeholder = check(path)
    if placeholder:
        print("check-ci-template: note: PRODUCTIZER_SHA is the all-zero placeholder, which the "
              "workflow refuses at run time. Pin it before the first dispatch: git ls-remote "
              "https://github.com/<PRODUCTIZER_REPO> 'refs/tags/vX.Y.Z^{}' prints the commit id "
              "of release vX.Y.Z.")
    failed = set(f.split()[0] for f in findings)
    held = len(ASSERTIONS) - len(failed)
    if findings:
        print("check-ci-template: %d finding(s) in %s" % (len(findings), path))
        for f in findings:
            print("  " + f)
        print("check-ci-template: %d of %d assertions held" % (held, len(ASSERTIONS)))
        return 1
    print("check-ci-template: every assertion held in %s (%s)" % (path, ", ".join(ASSERTIONS)))
    print("check-ci-template: %d of %d assertions held" % (held, len(ASSERTIONS)))
    return 0


def documented_codes():
    block = __doc__.split("Exit codes:", 1)[1].split("--selftest", 1)[0]
    return sorted(set(re.findall(r"^\s{2}(\d)\s", block, re.M)))


def selftest():
    cases_file = os.path.join(FIXTURES, "cases.tsv")
    try:
        with open(cases_file, "r", encoding="utf-8") as fh:
            rows = [l.rstrip("\n").split("\t") for l in fh
                    if l.strip() and not l.startswith("#")]
    except OSError as exc:
        die("no readable cases.tsv at %s: %s" % (cases_file, exc.strerror))
    bad = [r for r in rows if len(r) != 3]
    if bad or not rows:
        die("cases.tsv rows must be three tab-separated fields: file, exit, sentence")

    print("check-ci-template self-test\n")
    held, reached = 0, set()
    sandbox = tempfile.mkdtemp()
    try:
        extra = [
            ("not-yaml", 2, "is not parseable YAML", "on: [\n  : :\n"),
            ("no-agent-job", 2, "Unmeasured, not clean",
             "on: workflow_dispatch\npermissions:\n  contents: read\njobs:\n  a:\n"
             "    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n"),
        ]
        targets = [(f, int(code), text, os.path.join(FIXTURES, f)) for f, code, text in rows]
        for name, code, text, body in extra:
            p = os.path.join(sandbox, name + ".yml")
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(body)
            targets.append((name, code, text, p))
        targets.append(("missing-file", 2, "could not read",
                        os.path.join(sandbox, "absent.yml")))
        targets.append(("version", 0, "check-ci-template 1.", "--version"))
        targets.append(("shipped-template", 0, "every assertion held",
                        os.path.abspath(DEFAULT_PATH)))
        for name, want, text, arg in targets:
            proc = subprocess.run([sys.executable, os.path.abspath(__file__), arg],
                                  capture_output=True, text=True, timeout=60)
            out = proc.stdout + proc.stderr
            reached.add(str(proc.returncode))
            if proc.returncode == want and text in out:
                held += 1
                print("  ok    %-34s exit %d" % (name, proc.returncode))
            else:
                print("  FAIL  %-34s exit %d (wanted %d and the text: %s)"
                      % (name, proc.returncode, want, text))
                for line in out.splitlines()[:8]:
                    print("          " + line)
        total = len(targets)
    finally:
        shutil.rmtree(sandbox)

    print("\n%d of %d cases held" % (held, total))
    got, doc = " ".join(sorted(reached)), " ".join(documented_codes())
    print("    exit codes reached: %s   documented: %s" % (got, doc))
    print("    NOT ASSERTED: that a pinned commit is the release its comment names; a "
          "write permission granted through a reusable workflow's own file; an "
          "expression smuggled into a run: through env indirection that is itself "
          "untrusted; YAML anchors and merge keys; any behaviour of GitHub itself; that "
          "the CLI inside the action really removes the Bash tool when deny-bash is "
          "declared (deny-bash checks the workflow declares it, not that the CLI honours "
          "it - measured against local claude -p, references/ci-build.md); that a "
          "permissions option really narrows - what each one adds to the agent's "
          "arguments is build-dispatch.sh's, asserted in its own self-test; that a "
          "write job runs no repository code beyond what its run: text names - an "
          "interpreter a staged script starts, or a command spelled through a variable, "
          "is not seen by write-job-no-repo-code; that the $RUNNER_TEMP copy really is "
          "the pinned commit (the template verifies that at run time, not this checker); "
          "that PRODUCTIZER_SHA names a productizer release (tools-pin checks its shape, "
          "not what it points at); that a guard line is reachable - guards match the "
          "template's lines in order, not its control flow, so a line after an earlier "
          "exit 0 still counts; that GitHub runs the guards as written or parses the "
          "claude_args heredoc agent-args appends (build-dispatch.sh self-tests "
          "agent-args itself); an expression interpolated into a script that is not a "
          "run: - an actions/github-script `script:`, say - which run-injection does not "
          "read.")
    if got != doc:
        print("FAIL: reached and documented exit codes differ")
        return 1
    return 0 if held == total else 1


def main(argv):
    args = argv[1:]
    if args in (["--version"],):
        print(VERSION)
        return 0
    if args in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    if args in (["--selftest"], ["--self-test"]):
        return selftest()
    if len(args) > 1 or (args and args[0].startswith("-")):
        die("usage: check-ci-template.py [PATH] | --selftest | --version | --help")
    return report(args[0] if args else os.path.abspath(DEFAULT_PATH))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
