#!/usr/bin/env python3
"""Replay CI's `checks` job against a clean clone of one commit, before you push.

WHY. Four CI failures reached `main` in v4.61.0-v4.62.0 behind a green local
suite, and every one was a gap between a working tree and a fresh runner
checkout: a check CI runs that no declared check ran, untracked files outside
the change set, a tool present only through one machine's npx cache, and a
committed file a scanner allowlists by path. The last one was caught only by
replaying CI's own steps in a clean clone at the commit. This is that replay.

WHAT IT DOES.
  1. Clones the repository into a temporary directory and checks out the exact
     commit, so nothing uncommitted can leak in. It asserts 0 local changes.
  2. Reads .github/workflows/checks.yml FROM THAT COMMIT, takes the `checks`
     job's steps in order, and runs each `run:` block verbatim with
     `bash --noprofile --norc -e -o pipefail -c`, in the clone, with
     RUNNER_TEMP, GITHUB_ENV, GITHUB_PATH and GITHUB_WORKSPACE pointed into the
     temporary directory. What a step writes to GITHUB_ENV and GITHUB_PATH is
     carried into every later step, as the runner does. A step's `env:` is
     applied with `${{ github.event.before }}` replaced by the push base and
     `${{ github.event.pull_request.base.sha }}` by empty - a push to main.
  3. Skips `uses:` steps and steps that only INSTALL a tool (semgrep, gitleaks,
     a global npm install such as the Claude Code CLI), naming each skip and
     the copy of the tool this machine will use instead.
  4. Prints one line per step with its exit code, and the tail of each failing
     step's log.

Every step runs, even after one fails. A step CI would skip after a failure
(no `if: !cancelled()`) is marked so; its result is still reported, because a
second failure hidden behind the first is the one you push next.

THE ONE REFUSAL IT FORGIVES, AND HOW. Measured on a Mac: the PyYAML install
step fails because Homebrew's Python refuses a system-wide pip install
(PEP 668, `externally-managed-environment`), while CI's setup-python
interpreter accepts it. That is not a pass - the pinned version was never
installed - and it is not a defect in the commit either. It is reported as
HOST-REFUSED, and only under all three of these conditions:
  - the step is listed in HOST_REFUSALS below, by name;
  - its log carries that list's marker (for pip, PEP 668's error name);
  - the step the list names as its verifier (the Guard, which asserts python3
    can import yaml) runs LATER and passes.
If the verifier fails, is absent, or never runs, the refused step counts as a
FAILURE. A HOST-REFUSED step is never counted as passed: the summary names it
separately, with the pin that was not installed. Any other failure of that
step, without the marker, is an ordinary FAIL.

THE SOURCE REPOSITORY IS NEVER WRITTEN. It is read with `git rev-parse`,
`git --no-optional-locks status` and a `git fetch` run FROM the clone. A
snapshot - status, refs, and a hash of every file in the working tree - is
taken before and after and both digests are printed. A difference is reported
with the paths that changed; the replay writes only under its temporary
directory, so a difference means another process edited the tree meanwhile.
--selftest asserts it on a dirty fixture repository.

Usage:
    replay-ci.py [--commit SHA] [--base SHA] [--keep] [--repo DIR]
    replay-ci.py --selftest

    --commit SHA   the commit to replay (default HEAD)
    --base SHA     the push base, standing in for github.event.before
                   (default: this repository's refs/remotes/origin/main tip, as
                   last fetched - the `before` a push to main would carry now)
    --keep         keep the temporary directory and print where it is
    --repo DIR     the repository to replay (default: the one holding the
                   current directory)

Exit: 0 every step that ran passed (a HOST-REFUSED step whose postcondition a
        later step verified is allowed, and named)
      1 a step failed
      2 could not run: bad usage, no git, not a git work tree, the workflow
        is missing or unparseable, or the commit (or base) was not found
"""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import signal
import time

WORKFLOW = ".github/workflows/checks.yml"
JOB = "checks"
TAIL = 25

# (label, pattern over the step's `run:` block, the binary later steps use)
INSTALL_ONLY = [
    ("semgrep", re.compile(r"pip install [^\n]*'semgrep=="), "semgrep", ["--version", "--disable-version-check"]),
    ("gitleaks", re.compile(r"releases/download/[^\n]*gitleaks"), "gitleaks", ["version"]),
    ("a global npm install", re.compile(r"\bnpm (install|i) (-g|--global)\b"), "claude", ["--version"]),
]

# (install step name, log marker of a host refusal, verifier step name, why)
HOST_REFUSALS = [
    (re.compile(r"^PyYAML\b"), "externally-managed-environment", re.compile(r"^Guard\b"),
     "PEP 668: this machine's python3 refuses a system-wide pip install; CI's setup-python accepts it"),
]

EXPRESSIONS = {
    "github.event.before": None,  # the push base, filled in at run time
    "github.event.pull_request.base.sha": "",
}
EXPR = re.compile(r"\$\{\{\s*([^}]*?)\s*\}\}")
IF_ALWAYS = {"!cancelled()", "always()"}
STEP_KEYS = {"name", "id", "uses", "with", "run", "env", "if"}


class CannotRun(Exception):
    pass


def git(args, cwd):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        raise CannotRun(f"`git {' '.join(args)}` exited {r.returncode}: {r.stderr.strip()}")
    say_stderr(args, r.stderr)
    return r.stdout


def git_ok(args, cwd):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if r.returncode == 0:
        say_stderr(args, r.stderr)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def say_stderr(args, err):
    """A git call that succeeded but wrote to stderr is shown, never dropped."""
    for line in err.strip().splitlines():
        print(f"replay-ci: git {args[0]} said on stderr: {line}")


def snapshot(top):
    """Status, refs and a digest of every file under the work tree but .git."""
    status = git(["--no-optional-locks", "status", "--porcelain=v1", "-uall", "--ignored"], top)
    refs = git(["for-each-ref", "--format=%(objectname) %(refname)"], top)
    rc, head, err = git_ok(["rev-parse", "HEAD"], top)
    head = head if rc == 0 else "no HEAD: " + err
    files = {}
    for root, dirs, names in os.walk(top):
        if root == top and ".git" in dirs:
            dirs.remove(".git")
        dirs.sort()
        for n in sorted(names):
            p = os.path.join(root, n)
            rel = os.path.relpath(p, top)
            if os.path.islink(p):
                files[rel] = "link:" + os.readlink(p)
            else:
                with open(p, "rb") as fh:
                    files[rel] = hashlib.sha256(fh.read()).hexdigest()
    h = hashlib.sha256()
    for part in (status, refs, head):
        h.update(part.encode() + b"\0")
    for rel, d in sorted(files.items()):
        h.update(f"{rel}\0{d}\0".encode())
    return h.hexdigest(), files


def load_steps(ws):
    try:
        import yaml
    except ImportError:
        raise CannotRun("workflow unparseable: python3 has no yaml module (PyYAML) to read it with")
    path = os.path.join(ws, WORKFLOW)
    if not os.path.isfile(path):
        raise CannotRun(f"workflow unparseable: {WORKFLOW} does not exist at this commit")
    try:
        with open(path, encoding="utf-8") as fh:
            doc = yaml.safe_load(fh)
    except yaml.YAMLError as e:
        raise CannotRun(f"workflow unparseable: {WORKFLOW}: {e}")
    try:
        steps = doc["jobs"][JOB]["steps"]
    except (TypeError, KeyError):
        raise CannotRun(f"workflow unparseable: {WORKFLOW} has no jobs.{JOB}.steps")
    if not isinstance(steps, list) or not steps:
        raise CannotRun(f"workflow unparseable: jobs.{JOB}.steps is not a non-empty list")
    for i, s in enumerate(steps, 1):
        if not isinstance(s, dict) or ("run" in s) == ("uses" in s):
            raise CannotRun(f"workflow unparseable: step {i} is not exactly one of `run:` or `uses:`")
        extra = set(s) - STEP_KEYS
        if extra:
            raise CannotRun(f"workflow unparseable: step {i} uses {sorted(extra)}, which this replay "
                            f"does not implement - refusing rather than ignoring it")
        cond = str(s.get("if", "")).strip()
        m = EXPR.fullmatch(cond)
        if cond and (m.group(1) if m else cond) not in IF_ALWAYS:
            raise CannotRun(f"workflow unparseable: step {i} has `if: {cond}`, which this replay cannot evaluate")
        if "run" in s and "${{" in str(s["run"]):
            raise CannotRun(f"workflow unparseable: step {i}'s run: block holds a `${{{{ }}}}` expression")
        for k, v in (s.get("env") or {}).items():
            for expr in EXPR.findall(str(v)):
                if expr not in EXPRESSIONS:
                    raise CannotRun(f"workflow unparseable: step {i} env {k} uses `${{{{ {expr} }}}}`, "
                                    f"which this replay cannot evaluate")
    return steps


def clone(src, commit, base, ws):
    git(["-c", "init.defaultBranch=main", "init", "-q", ws], src)
    git(["fetch", "-q", "--no-tags", src,
         "+refs/remotes/origin/*:refs/remotes/origin/*",
         "+refs/tags/*:refs/tags/*",
         "+refs/heads/*:refs/replay-src/heads/*",
         "+HEAD:refs/replay-src/HEAD"], ws)
    for sha, what in ((commit, "commit"), (base, "base")):
        rc, _, err = git_ok(["cat-file", "-e", sha + "^{commit}"], ws)
        if rc != 0:
            raise CannotRun(f"{what} not found: {sha} is not reachable from any ref of the source repository ({err})")
    git(["-c", "advice.detachedHead=false", "checkout", "-q", "-B", "main", commit], ws)
    for ref in git(["for-each-ref", "--format=%(refname)", "refs/replay-src/"], ws).split():
        git(["update-ref", "-d", ref], ws)
    head = git(["rev-parse", "HEAD"], ws).strip()
    dirty = git(["status", "--porcelain", "-uall"], ws)
    if head != commit or dirty:
        raise CannotRun(f"the clone is not clean at {commit}: HEAD {head}, {len(dirty.splitlines())} local change(s)")


def read_env_file(path):
    out = {}
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        if not line.strip():
            continue
        if "<<" in line and ("=" not in line or line.index("<<") < line.index("=")):
            name, delim = line.split("<<", 1)
            body = []
            while i < len(lines) and lines[i] != delim:
                body.append(lines[i])
                i += 1
            if i >= len(lines):
                raise ValueError(f"GITHUB_ENV: `{name}<<{delim}` is never closed")
            i += 1
            out[name] = "\n".join(body)
        elif "=" in line:
            name, value = line.split("=", 1)
            out[name] = value
        else:
            raise ValueError(f"GITHUB_ENV: line is neither NAME=value nor NAME<<DELIM: {line!r}")
    return out


def tail(path, n=TAIL):
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    return lines[-n:]


def step_name(s):
    return str(s.get("name") or ("uses: " + str(s.get("uses"))) or "(unnamed)")


def replay(src, commit, base, base_why, keep):
    top = os.path.realpath(tempfile.mkdtemp(prefix="replay-ci-"))
    ws = os.path.join(top, "ws")
    rt = os.path.join(top, "runner-temp")
    logs = os.path.join(top, "logs")
    os.makedirs(rt)
    os.makedirs(logs)
    print(f"replay-ci: workspace {top}", flush=True)
    try:
        clone(src, commit, base, ws)
        subject = git(["log", "-1", "--format=%s", commit], ws).strip()
        print(f"replay-ci: commit {commit}  {subject}")
        print(f"replay-ci: base   {base}  ({base_why})")
        if base == commit:
            print("replay-ci: base equals the commit - the change set is EMPTY, so change-set-driven checks "
                  "measure nothing here; pass --base to replay a real push")
        print(f"replay-ci: clean clone, HEAD {commit}, 0 local changes")
        steps = load_steps(ws)
        print(f"replay-ci: {len(steps)} steps in jobs.{JOB} of {WORKFLOW} at that commit", flush=True)
        return run_steps(steps, ws, rt, logs, base)
    finally:
        if keep:
            print(f"replay-ci: kept {top}")
        else:
            shutil.rmtree(top, ignore_errors=False)


def run_steps(steps, ws, rt, logs, base):
    carried_env = {}
    prepend = []
    base_path = os.environ.get("PATH", "")
    results = []  # (index, name, status, rc)
    refused = {}  # step index -> (verifier regex, why, pin)
    failed_so_far = False
    for i, s in enumerate(steps, 1):
        name = step_name(s)
        tag = f"  #{i:<2}"
        if "uses" in s:
            print(f"{tag} SKIP          `uses:` action, not replayed ({s['uses']})", flush=True)
            results.append((i, name, "SKIP", None))
            continue
        run = str(s["run"])
        hit = next((x for x in INSTALL_ONLY if x[1].search(run)), None)
        if hit:
            label, _, binary, vargs = hit
            found = shutil.which(binary, path=os.pathsep.join(prepend + [base_path]))
            if found:
                r = subprocess.run([found, *vargs], capture_output=True, text=True)
                ver = (r.stdout.strip() + "\n" + r.stderr.strip()).strip().splitlines()[:1]
                using = f"this machine's {found} ({ver[0] if ver else 'no version output'}; not compared to the pin)"
            else:
                using = f"`{binary}` is NOT on this machine's PATH - a later step that needs it will fail"
            print(f"{tag} SKIP          install-only step ({label}): {name} - using {using}", flush=True)
            results.append((i, name, "SKIP", None))
            continue
        cond = str(s.get("if", "")).strip()
        m = EXPR.fullmatch(cond)
        ci_would_skip = failed_so_far and not (cond and (m.group(1) if m else cond) in IF_ALWAYS)
        env_file = os.path.join(rt, f"github-env-{i}")
        path_file = os.path.join(rt, f"github-path-{i}")
        open(env_file, "w").close()
        open(path_file, "w").close()
        env = dict(os.environ)
        env.update(carried_env)
        for k, v in (s.get("env") or {}).items():
            env[str(k)] = EXPR.sub(lambda mm: base if mm.group(1) == "github.event.before"
                                   else EXPRESSIONS[mm.group(1)], str(v))
        env.update(RUNNER_TEMP=rt, GITHUB_ENV=env_file, GITHUB_PATH=path_file, GITHUB_WORKSPACE=ws,
                   PATH=os.pathsep.join(prepend + [base_path]))
        log = os.path.join(logs, f"step-{i:02d}.log")
        t0 = time.time()
        with open(log, "w") as fh:
            r = subprocess.run(["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", run],
                               cwd=ws, env=env, stdin=subprocess.DEVNULL, stdout=fh, stderr=subprocess.STDOUT)
        secs = time.time() - t0
        rc = r.returncode
        note = ""
        if rc == 0:
            try:
                carried_env.update(read_env_file(env_file))
            except ValueError as e:
                rc, note = 1, f" [{e}]"
            with open(path_file, encoding="utf-8") as fh:
                for p in fh.read().splitlines():
                    if p.strip():
                        if p in prepend:
                            prepend.remove(p)
                        prepend.insert(0, p)
        status = "PASS" if rc == 0 else "FAIL"
        if rc != 0:
            with open(log, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            for inst, marker, verifier, why in HOST_REFUSALS:
                if inst.search(name) and marker in text:
                    status = "HOST-REFUSED"
                    pins = re.findall(r"'([A-Za-z0-9_.-]+==[^']+)'", run)
                    refused[i] = (verifier, why, pins)
                    note = f" [{why}; postcondition pending a later step matching /{verifier.pattern}/]"
                    break
        if ci_would_skip:
            note += " (CI would skip this step: an earlier step failed and it has no `if: !cancelled()`)"
        print(f"{tag} {status:<13} exit {rc:<3} {secs:6.1f}s  {name}{note}", flush=True)
        if status != "PASS":
            print(f"        --- last {TAIL} lines of its log ---")
            for line in tail(log):
                print(f"        | {line}")
        if status == "PASS":
            for j, (verifier, why, pins) in list(refused.items()):
                if verifier.search(name):
                    print(f"        -> #{j}'s postcondition verified by this step. #{j} is HOST-REFUSED, NOT "
                          f"passed: {', '.join(pins) or 'its pin'} was never installed here, so later steps "
                          f"ran against this machine's own copy")
                    results[j - 1] = (j, results[j - 1][1], "HOST-REFUSED-VERIFIED", results[j - 1][3])
                    del refused[j]
        if status == "FAIL":
            failed_so_far = True
        results.append((i, name, status, rc))
    for j, (verifier, why, pins) in refused.items():
        print(f"  #{j:<2} postcondition NOT verified: no later step matching /{verifier.pattern}/ passed, "
              f"so this HOST-REFUSED step counts as a FAILURE")
        results[j - 1] = (j, results[j - 1][1], "FAIL", results[j - 1][3])
    return results


def summarize(results, commit, base):
    failed = [r for r in results if r[2] == "FAIL"]
    passed = [r for r in results if r[2] == "PASS"]
    skipped = [r for r in results if r[2] == "SKIP"]
    host = [r for r in results if r[2] == "HOST-REFUSED-VERIFIED"]
    where = f"commit {commit[:12]}, base {base[:12]}"
    if failed:
        names = "; ".join(f"#{i} {n}" for i, n, _, _ in failed)
        print(f"replay-ci: FAIL - {len(failed)} step(s) failed of {len(results) - len(skipped)} that ran: "
              f"{names}. ({where})")
        return 1
    extra = ""
    if host:
        extra = (f", {len(host)} HOST-REFUSED with the postcondition verified by a later step - not counted as "
                 f"passed ({'; '.join(f'#{i} {n}' for i, n, _, _ in host)})")
    print(f"replay-ci: PASS - every step that ran passed: {len(passed)} passed, {len(skipped)} skipped "
          f"(named above){extra}. ({where})")
    return 0


def parse(argv):
    opts = {"commit": "HEAD", "base": None, "keep": False, "repo": os.getcwd()}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--keep":
            opts["keep"] = True
            i += 1
        elif a in ("--commit", "--base", "--repo") and i + 1 < len(argv):
            opts[a[2:]] = argv[i + 1]
            i += 2
        else:
            raise CannotRun(f"bad usage: unknown or incomplete argument {a!r}; see the file header")
    return opts


def main(argv):
    try:
        # Written as a comparison against the string, not the list ["--selftest"]:
        # check-selftest-coverage.sh recognises a self-test by the line that
        # dispatches on its flag, and a list literal hid this one from it.
        if len(argv) == 1 and argv[0] == "--selftest":
            return selftest()
        opts = parse(argv)
        if shutil.which("git") is None:
            raise CannotRun("git not found on PATH")
        rc, top, err = git_ok(["rev-parse", "--show-toplevel"], opts["repo"])
        if rc != 0:
            raise CannotRun(f"not a git work tree: {opts['repo']} ({err})")
        rc, commit, err = git_ok(["rev-parse", "--verify", opts["commit"] + "^{commit}"], top)
        if rc != 0:
            raise CannotRun(f"commit not found: {opts['commit']} ({err})")
        if opts["base"] is not None:
            rc, base, err = git_ok(["rev-parse", "--verify", opts["base"] + "^{commit}"], top)
            if rc != 0:
                raise CannotRun(f"base not found: {opts['base']} ({err})")
            why = "from --base"
        else:
            rc, base, err = git_ok(["rev-parse", "--verify", "refs/remotes/origin/main^{commit}"], top)
            if rc != 0:
                raise CannotRun(f"base not found: this repository has no origin/main to stand in for "
                                f"github.event.before; pass --base ({err})")
            why = ("the origin/main tip as this repository last fetched it - the `before` a push to main "
                   "would carry now; `git fetch` first if it may be stale")
        before, files_before = snapshot(top)
        print(f"replay-ci: source {top}  snapshot before {before[:16]}")
        results = replay(top, commit, base, why, opts["keep"])
        after, files_after = snapshot(top)
        if after == before:
            print(f"replay-ci: source repository untouched: snapshot after {after[:16]} equals before")
        else:
            changed = sorted(p for p in set(files_before) | set(files_after)
                             if files_before.get(p) != files_after.get(p))
            print(f"replay-ci: source repository CHANGED during the replay: snapshot after {after[:16]} "
                  f"!= before. The replay writes only under its temporary directory; paths that differ: "
                  f"{', '.join(changed) or '(status or refs only)'}")
        return summarize(results, commit, base)
    except CannotRun as e:
        print(f"replay-ci: could not run: {e}")
        return 2


# --------------------------------------------------------------------- selftest

FIXTURE_STEPS = {
    "checkout": """\
      - uses: actions/checkout@0000000000000000000000000000000000000000
""",
    "pyyaml": """\
      - name: PyYAML, which the runner refuses to work without
        run: |
          echo "python3 -m pip install 'FixturePkg==1.0'"
          echo "error: externally-managed-environment" >&2
          exit 1
""",
    "pyyaml-other": """\
      - name: PyYAML, which the runner refuses to work without
        run: |
          echo "error: no network" >&2
          exit 1
""",
    "gitleaks": """\
      - name: gitleaks, which the declared secret-scan check runs
        run: |
          # https://github.com/gitleaks/gitleaks/releases/download/v0.0.0/gitleaks.tar.gz
          echo "this install-only step RAN; it must be skipped" >&2
          exit 1
""",
    "tool": """\
      - name: Tool - puts a tool on PATH and variables in the env
        run: |
          set -euo pipefail
          mkdir -p "$RUNNER_TEMP/tools-bin"
          printf '#!/bin/sh\\necho fixture-tool-ran\\n' > "$RUNNER_TEMP/tools-bin/fixture-tool"
          chmod 0755 "$RUNNER_TEMP/tools-bin/fixture-tool"
          echo "$RUNNER_TEMP/tools-bin" >> "$GITHUB_PATH"
          echo "CARRIED=from-an-earlier-step" >> "$GITHUB_ENV"
          { echo 'MULTI<<EOF'; echo 'line one'; echo 'line two'; echo 'EOF'; } >> "$GITHUB_ENV"
""",
    "guard": """\
      - name: Guard - the refused install's postcondition holds
        run: echo "postcondition holds"
""",
    "guard-fails": """\
      - name: Guard - the refused install's postcondition holds
        run: |
          echo "postcondition does NOT hold"
          exit 1
""",
    "carry": """\
      - name: Carry - GITHUB_ENV and GITHUB_PATH reach a later step
        if: ${{ !cancelled() }}
        run: |
          set -euo pipefail
          test "${CARRIED:-}" = from-an-earlier-step
          test "${MULTI:-}" = "$(printf 'line one\\nline two')"
          fixture-tool
""",
    "clean": """\
      - name: Clean - the commit, never the working tree
        run: |
          set -euo pipefail
          test "$(cat marker.txt)" = committed
          test ! -e untracked.txt
          test -z "$(git status --porcelain -uall)"
          test "$PWD" = "$GITHUB_WORKSPACE"
          echo built > build-output.txt
""",
    "event": """\
      - name: Event - env mapping with the push base substituted
        env:
          PUSH_BEFORE: ${{ github.event.before }}
          PR_BASE_SHA: ${{ github.event.pull_request.base.sha }}
        run: |
          set -euo pipefail
          test "$PUSH_BEFORE" = "$FIXTURE_EXPECT_BASE"
          test -z "$PR_BASE_SHA"
""",
    "broken": """\
      - name: Broken - fails on purpose
        run: |
          echo "boom-marker-7f3a"
          exit 3
""",
    "secret": """\
      - name: Secret - an expression the replay cannot evaluate
        env:
          TOKEN: ${{ secrets.TOKEN }}
        run: echo "$TOKEN"
""",
}

PRISTINE = ["checkout", "pyyaml", "gitleaks", "tool", "guard", "carry", "clean", "event"]


def _workflow(parts):
    return ("name: checks\non:\n  push:\n    branches: [main]\njobs:\n  checks:\n    runs-on: ubuntu-latest\n"
            "    steps:\n" + "".join(FIXTURE_STEPS[p] for p in parts))


def _fixture(top, workflow_text, origin=True):
    """A two-commit repository whose working tree is dirty and holds an untracked file."""
    src = os.path.join(top, "src")
    g = ["-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false"]
    git(["-c", "init.defaultBranch=main", "init", "-q", src], top)
    with open(os.path.join(src, "marker.txt"), "w") as fh:
        fh.write("committed\n")
    git(["add", "marker.txt"], src)
    git([*g, "commit", "-q", "-m", "A: marker"], src)
    a = git(["rev-parse", "HEAD"], src).strip()
    os.makedirs(os.path.join(src, ".github", "workflows"))
    with open(os.path.join(src, WORKFLOW), "w") as fh:
        fh.write(workflow_text)
    git(["add", WORKFLOW], src)
    git([*g, "commit", "-q", "-m", "B: workflow"], src)
    b = git(["rev-parse", "HEAD"], src).strip()
    if origin:
        git(["update-ref", "refs/remotes/origin/main", a], src)
    with open(os.path.join(src, "marker.txt"), "w") as fh:
        fh.write("dirty\n")
    with open(os.path.join(src, "untracked.txt"), "w") as fh:
        fh.write("never committed\n")
    return src, a, b


def _cases():
    # (label, workflow parts or raw text, argv builder, env builder, origin?, want rc, [sentences])
    P = PRISTINE
    return [
        ("pristine fixture: every step passes, the refusal is forgiven only with its verifier, skips named",
         P, lambda s, a, b: [], lambda a, b: {"FIXTURE_EXPECT_BASE": a}, True, 0,
         ["every step that ran passed", "HOST-REFUSED", "postcondition verified by this step",
          "FixturePkg==1.0 was never installed", "not counted as passed", "install-only step (gitleaks)",
          "`uses:` action, not replayed", "the origin/main tip", "source repository untouched"]),
        ("--base given: the push base is that commit, and the output says it came from --base",
         P, lambda s, a, b: ["--base", b], lambda a, b: {"FIXTURE_EXPECT_BASE": b}, True, 0,
         ["every step that ran passed", "(from --base)", "change set is EMPTY"]),
        ("--keep: the temporary directory survives and is named",
         P, lambda s, a, b: ["--keep"], lambda a, b: {"FIXTURE_EXPECT_BASE": a}, True, 0,
         ["every step that ran passed", "replay-ci: kept "]),
        ("a step fails: exit 1, named, with the tail of its log",
         P + ["broken"], lambda s, a, b: [], lambda a, b: {"FIXTURE_EXPECT_BASE": a}, True, 1,
         ["1 step(s) failed", "#9 Broken - fails on purpose", "| boom-marker-7f3a"]),
        ("the refused install's verifier fails: the refusal is a FAILURE, not forgiven",
         [p if p != "guard" else "guard-fails" for p in P], lambda s, a, b: [],
         lambda a, b: {"FIXTURE_EXPECT_BASE": a}, True, 1,
         ["postcondition NOT verified", "2 step(s) failed", "#2 PyYAML"]),
        ("the refused install has no verifier step at all: a FAILURE",
         [p for p in P if p != "guard"], lambda s, a, b: [], lambda a, b: {"FIXTURE_EXPECT_BASE": a}, True, 1,
         ["postcondition NOT verified", "1 step(s) failed", "#2 PyYAML"]),
        ("the install step fails WITHOUT the host-refusal marker: an ordinary FAIL",
         [p if p != "pyyaml" else "pyyaml-other" for p in P], lambda s, a, b: [],
         lambda a, b: {"FIXTURE_EXPECT_BASE": a}, True, 1, ["1 step(s) failed", "#2 PyYAML"]),
        ("an expression the replay cannot evaluate: could not run",
         P + ["secret"], lambda s, a, b: [], lambda a, b: {}, True, 2,
         ["could not run: workflow unparseable", "secrets.TOKEN"]),
        ("the workflow is not YAML: could not run",
         "jobs: [unclosed\n  - : :\n", lambda s, a, b: [], lambda a, b: {}, True, 2,
         ["could not run: workflow unparseable"]),
        ("the workflow has no checks job: could not run",
         "name: x\njobs:\n  other:\n    steps:\n      - run: true\n", lambda s, a, b: [], lambda a, b: {}, True, 2,
         ["could not run: workflow unparseable", "no jobs.checks.steps"]),
        ("--commit names no commit: could not run",
         P, lambda s, a, b: ["--commit", "0" * 40], lambda a, b: {}, True, 2, ["could not run: commit not found"]),
        ("no origin/main and no --base: could not run",
         P, lambda s, a, b: [], lambda a, b: {}, False, 2, ["could not run: base not found", "pass --base"]),
        ("--repo is not a git work tree: could not run",
         P, lambda s, a, b: ["--repo", os.path.dirname(s)], lambda a, b: {}, True, 2,
         ["could not run: not a git work tree"]),
        ("git is not on PATH: could not run",
         P, lambda s, a, b: [], lambda a, b: {"PATH": ""}, True, 2, ["could not run: git not found"]),
        ("an unknown argument: could not run",
         P, lambda s, a, b: ["--bogus"], lambda a, b: {}, True, 2, ["could not run: bad usage"]),
        ("--commit with no value: could not run",
         P, lambda s, a, b: ["--commit"], lambda a, b: {}, True, 2, ["could not run: bad usage"]),
    ]


def selftest():
    reached = []
    fails = 0
    cases = _cases()
    for label, wf, argv_of, env_of, origin, want_rc, want in cases:
        top = tempfile.mkdtemp(prefix="replay-ci-selftest-")
        try:
            text = wf if isinstance(wf, str) else _workflow(wf)
            src, a, b = _fixture(top, text, origin)
            before, _ = snapshot(src)
            env = dict(os.environ)
            env.update(env_of(a, b))
            argv = [sys.executable, os.path.abspath(__file__), *(["--repo", src] if "--repo" not in argv_of(src, a, b)
                                                                  else []), *argv_of(src, a, b)]
            r = subprocess.run(argv, cwd=top, env=env, capture_output=True, text=True)
            out = r.stdout + r.stderr
            after, _ = snapshot(src)
            problems = [f"missing sentence: {w!r}" for w in want if w not in out]
            if r.returncode != want_rc:
                problems.insert(0, f"exit {r.returncode}, want {want_rc}")
            if after != before or os.path.exists(os.path.join(src, "build-output.txt")):
                problems.append("the fixture's source repository changed")
            ws = re.search(r"^replay-ci: workspace (\S+)", out, re.M)
            if ws:
                if "--keep" in argv and not os.path.isdir(os.path.join(ws.group(1), "ws")):
                    problems.append("--keep given but the workspace is gone")
                if "--keep" not in argv and os.path.exists(ws.group(1)):
                    problems.append("the workspace was not removed")
                if "--keep" in argv:
                    shutil.rmtree(ws.group(1))
            reached.append(r.returncode)
        finally:
            shutil.rmtree(top)
        ok = not problems
        fails += 0 if ok else 1
        print(f"  {'ok  ' if ok else 'FAIL'}  exit {r.returncode} (want {want_rc})  {label}")
        summary = next((ln for ln in out.splitlines() if ln.startswith(("replay-ci: PASS", "replay-ci: FAIL",
                                                                          "replay-ci: could not run"))), "")
        if summary:
            print(f"        {summary[:200]}")
        for p in problems:
            print(f"        red: {p}")
        if problems:
            print("        --- its output ---")
            for ln in out.splitlines()[-40:]:
                print(f"        | {ln}")
    print(f"\n{len(cases) - fails} of {len(cases)} cases held")
    codes = sorted(set(reached))
    print(f"    exit codes reached: {' '.join(str(c) for c in codes)}   documented: 0 1 2")
    print("    NOT ASSERTED: that the real workflow replays the same way on this machine - it is never run here, "
          "it takes minutes; that a skipped install's local tool matches CI's pinned version; that a `uses:` "
          "action's effect (setup-node, setup-python) is matched by this machine's own runtimes.")
    missing = {0, 1, 2} - set(codes)
    if missing:
        sys.stdout.flush()
        print(f"FAIL: documented code(s) {sorted(missing)} never driven by any case", file=sys.stderr)
        fails += 1
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    # SIGTERM raises SystemExit, so the `finally` that removes the temporary
    # directory runs. Measured: killed without this, a run left its clone behind.
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(143))
    sys.exit(main(sys.argv[1:]))
