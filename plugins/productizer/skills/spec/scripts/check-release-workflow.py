#!/usr/bin/env python3
"""check-release-workflow.py [PATH] [--selftest] [--version] [--help]

Static assertions over this repository's own CI workflow,
.github/workflows/checks.yml by default (read from the current directory, which
is the repository root when the check suite runs it), or the workflow at PATH.

WHY THIS EXISTS. A version tag runs two jobs (B128). `release-prep`, whose
token can only read, runs this repository's code: it makes the release title,
the evidence notes and a copy of the CI build template pinned to the tag's
commit. `release-draft`, the only job whose token can write, checks out nothing
and runs no repository code: it reads those files as text, creates a draft and
attaches the pinned copy. That split is R71's discipline applied to releases,
and it is a property of the YAML - one edit (a checkout "to read a file", a
`python3` "to validate the notes") removes it while every script stays green.
So it is checked on the file itself (B142).

WHAT IT ASSERTS, each a separate finding:
  write-job-no-checkout
                 a job holding any write scope has no actions/checkout step,
                 and no run: clones, fetches or checks out a repository (git
                 clone/fetch/pull/checkout/switch/worktree/sparse-checkout, gh
                 repo clone). A job's scopes are its own permissions:, else the
                 workflow's, else - neither declared - the repository's default
                 token, which can write and is treated as a write scope
  write-job-no-repo-code
                 a job holding any write scope runs no code from the repository,
                 by check-ci-template.py's lexical rule, loaded from that file:
                 no local action (`uses: ./...`); no run: names an interpreter
                 or package runner (python, python3, node, bun, deno, ruby,
                 perl, php, npm, npx, yarn, pnpm, make), sources a file, or runs
                 a `./` path. Stricter than that rule in one place: here a
                 `bash`/`sh` invocation of ANY file is a finding, $RUNNER_TEMP
                 included, because what sits there in a release job is what
                 release-prep handed over - repository output, never code to
                 run. LIMITS: it reads the run: text, so a command spelled
                 through a variable or an alias, or an interpreter a system
                 tool starts, is not seen; git and gh are allowed, and what
                 they could run - hooks, aliases, extensions - is not this
                 rule's; a `uses:` action from another repository is pinned
                 code, not this repository's, and is not refused
  prep-read-only the job named release-prep holds no write scope
  draft-needs-prep
                 the job named release-draft lists release-prep in needs:
  handover       every actions/download-artifact step in a write job names an
                 artifact (with: name:) that a job it needs, holding no write
                 scope, uploads with actions/upload-artifact under that name. A
                 download with no name takes every artifact of the run, so it
                 is a finding
  attach-pinned  the lines that make the attached copy the tag's are present,
                 in order, as the workflow ships them. In release-prep: the
                 refusal of a tag naming a commit other than GITHUB_SHA, and
                 check-ci-template.py run on the pinned copy with a note
                 refused. In release-draft: the refusal of a copy whose
                 PRODUCTIZER_SHA is not GITHUB_SHA, `gh release create` with
                 --draft, then `gh release upload` of the copy. LIMITS: lines
                 are matched in order with whitespace and comments ignored,
                 the way check-ci-template.py's guards are, not as control
                 flow, so a line made unreachable by an earlier exit is not seen
  pinned         every `uses:` in the workflow is pinned to a full 40-character
                 commit id
  yaml-hash-pinned
                 every pip install in any job's run: that names PyYAML passes
                 --require-hashes and --only-binary :all: (B148) as arguments
                 of that same command, and no --no-binary or other
                 --only-binary value (B177), by check-ci-template.py's rule,
                 loaded from that file; it reads the run: text, not whether
                 the hashes are PyPI's
  run-injection  no `${{` expression of any context inside any run: in the
                 workflow; values reach a shell through env:

WHAT IT DOES NOT. It reads one file and runs nothing. It cannot tell whether
GitHub enforces the permissions the file declares, whether a pinned commit is
the release its comment names, or whether the jobs ever ran. A workflow with
no release-draft or no release-prep job is not called clean: the assertions
about them could not run, and that is exit 2.

PyYAML is required. On a machine where it lives only in the user site, run
this with `python3`, not `python3 -I`, which hides the user site.

Exit codes:
  0  every assertion held
  1  at least one finding, each printed with its assertion and location
  2  could not run: bad usage, an unreadable or unparseable file, PyYAML
     missing, check-ci-template.py not loadable, or no release-prep or
     release-draft job
--selftest runs over fixtures/release-workflow/ and exits 0 when every case
held, 1 when one did not.
"""

import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile

VERSION = "check-release-workflow 1.2"
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PATH = os.path.join(".github", "workflows", "checks.yml")
FIXTURES = os.path.join(HERE, "..", "fixtures", "release-workflow")
CI_TEMPLATE = os.path.join(HERE, "check-ci-template.py")
SHARED = ("write_perms", "walk_uses", "walk_runs", "first_missing", "REPO_CODE_RX",
          "SOURCE_RX", "DOT_SLASH_RX", "PIN_RX", "INJECT_RX", "unhashed_yaml_install")
PREP, DRAFT = "release-prep", "release-draft"

CHECKOUT_RUN_RX = re.compile(
    r"(?<![\w./-])(?:git(?:\s+-[-\w]+(?:[ =]\S+)?)*\s+"
    r"(clone|fetch|pull|checkout|switch|worktree|sparse-checkout)"
    r"|gh\s+repo\s+(clone))(?![\w-])")
ANY_SHELL_FILE_RX = re.compile(r"(?<![\w./-])(?:bash|sh)((?:\s+-[-\w]+)*)\s+(\S+)")
# The lines that make the attached copy the tag's, as the workflow ships them.
PREP_LINES = (
    'if [ "$sha" != "$GITHUB_SHA" ]; then', "exit 1",
    'if ! python3 -I plugins/productizer/skills/spec/scripts/check-ci-template.py '
    '"$pinned" > "$check_log"; then', "exit 1",
    "if grep -q '^check-ci-template: note:' \"$check_log\"; then", "exit 1")
DRAFT_LINES = (
    'if ! grep -q -x -F "  PRODUCTIZER_SHA: \\"$GITHUB_SHA\\"" "$pinned"; then', "exit 1",
    'gh release create "$TAG" --draft --verify-tag --title "$title" --notes-file "$notes"',
    'gh release upload "$TAG" "$pinned"')
# Matched the way check-ci-template.py's guards are: whitespace collapsed.
PREP_LINES = tuple(" ".join(l.split()) for l in PREP_LINES)
DRAFT_LINES = tuple(" ".join(l.split()) for l in DRAFT_LINES)

ASSERTIONS = ("write-job-no-checkout", "write-job-no-repo-code", "prep-read-only",
              "draft-needs-prep", "handover", "attach-pinned", "pinned", "yaml-hash-pinned",
              "run-injection")


def die(msg):
    sys.stderr.write("check-release-workflow: %s\n" % msg)
    raise SystemExit(2)


def ci_rules():
    """check-ci-template.py, loaded by path, so both checkers read write jobs by
    one lexical rule."""
    try:
        spec = importlib.util.spec_from_file_location("check_ci_template", CI_TEMPLATE)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except (OSError, SyntaxError, AttributeError) as exc:
        die("could not load the shared rule from %s: %s. Nothing was checked."
            % (CI_TEMPLATE, exc))
    gone = [n for n in SHARED if not hasattr(mod, n)]
    if gone:
        die("%s no longer defines %s, so the shared rule could not be read. Nothing was "
            "checked." % (CI_TEMPLATE, ", ".join(gone)))
    return mod


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


def steps_of(job):
    return [s for s in (job.get("steps") or []) if isinstance(s, dict)]


def action(step):
    return str(step.get("uses", "")).split("@")[0]


def needs_of(job):
    n = job.get("needs")
    if isinstance(n, str):
        return [n]
    if isinstance(n, list):
        return [str(x) for x in n]
    return []


def check(path):
    rules = ci_rules()
    doc = load(path)
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        die("%s has no jobs mapping" % path)
    for name in (PREP, DRAFT):
        if not isinstance(jobs.get(name), dict):
            die("%s has no job named %s, so the release assertions could not run. "
                "Unmeasured, not clean." % (path, name))

    findings = []

    def find(kind, where, what):
        findings.append("%s %s: %s" % (kind, where, what))

    def writes(job):
        if "permissions" in job:
            return rules.write_perms(job["permissions"])
        if "permissions" in doc:
            return rules.write_perms(doc["permissions"])
        return ["the repository's default token (no permissions declared)"]

    for jname, job in jobs.items():
        if not isinstance(job, dict):
            continue
        w = writes(job)
        if not w:
            continue
        held = "a job holding write on %s" % ", ".join(w)
        for i, s in enumerate(steps_of(job)):
            where = "jobs.%s.steps[%d]" % (jname, i)
            if action(s) == "actions/checkout":
                find("write-job-no-checkout", where, "%s checks out the repository "
                     "with actions/checkout; it must check out nothing" % held)
            if str(s.get("uses", "")).startswith("./"):
                find("write-job-no-repo-code", where, "%s runs a local action, which is "
                     "code from the repository: %s" % (held, s.get("uses")))
            if action(s) == "actions/download-artifact":
                art = (s.get("with") or {}).get("name")
                if not art:
                    find("handover", where, "%s downloads every artifact of the run (no "
                         "with: name:); it must name the one a read-only job made" % held)
                else:
                    makers = [n for n in needs_of(job)
                              if isinstance(jobs.get(n), dict) and not writes(jobs[n])
                              and any(action(u) == "actions/upload-artifact"
                                      and (u.get("with") or {}).get("name") == art
                                      for u in steps_of(jobs[n]))]
                    if not makers:
                        find("handover", where, "%s downloads the artifact %r, which no "
                             "read-only job it needs uploads" % (held, art))
            if "run" not in s:
                continue
            run = str(s["run"])
            m = CHECKOUT_RUN_RX.search(run)
            if m:
                find("write-job-no-checkout", where, "%s runs %s in a run:; it must "
                     "check out nothing" % (held, m.group(0)))
            m = rules.REPO_CODE_RX.search(run)
            if m:
                find("write-job-no-repo-code", where, "%s names %s in a run:; it must "
                     "execute no code from the repository" % (held, m.group(1)))
            if rules.SOURCE_RX.search(run) or rules.DOT_SLASH_RX.search(run):
                find("write-job-no-repo-code", where, "%s sources a file or runs a ./ "
                     "path" % held)
            for sm in ANY_SHELL_FILE_RX.finditer(run):
                find("write-job-no-repo-code", where, "%s runs a shell on %s; nothing a "
                     "release job holds is code to run" % (held, sm.group(2)))

    w = writes(jobs[PREP])
    if w:
        find("prep-read-only", "jobs.%s.permissions" % PREP, "holds write on %s; the job "
             "that runs the repository's code must hold none" % ", ".join(w))
    if PREP not in needs_of(jobs[DRAFT]):
        find("draft-needs-prep", "jobs.%s.needs" % DRAFT, "does not list %s; found %s"
             % (PREP, ", ".join(needs_of(jobs[DRAFT])) or "none"))

    for jname, lines in ((PREP, PREP_LINES), (DRAFT, DRAFT_LINES)):
        runs = [str(s["run"]) for s in steps_of(jobs[jname]) if "run" in s]
        misses = [rules.first_missing(r, lines) for r in runs]
        if not runs or all(misses):
            # The run: that got furthest names the line that is missing.
            first = max(misses, key=lines.index) if runs else lines[0]
            find("attach-pinned", "jobs.%s" % jname, "no run: carries, in order, the line: %s"
                 % first)

    for where, uses in rules.walk_uses(doc):
        if not rules.PIN_RX.match(uses):
            find("pinned", where, "not pinned to a full commit id: %s" % uses)
    for where, run in rules.walk_runs(doc):
        m = rules.INJECT_RX.search(run)
        if m:
            find("run-injection", where, "an expression is interpolated into the script: %s"
                 % m.group(0).strip())
        line = rules.unhashed_yaml_install(run)
        if line:
            find("yaml-hash-pinned", where, "installs PyYAML without --require-hashes and "
                 "--only-binary :all: as arguments of the same pip install, or with "
                 "--no-binary or another --only-binary value, so a file re-published at "
                 "that version would be installed: %s" % line)
    return findings


def report(path):
    findings = check(path)
    failed = set(f.split()[0] for f in findings)
    held = len(ASSERTIONS) - len(failed)
    if findings:
        print("check-release-workflow: %d finding(s) in %s" % (len(findings), path))
        for f in findings:
            print("  " + f)
        print("check-release-workflow: %d of %d assertions held" % (held, len(ASSERTIONS)))
        return 1
    print("check-release-workflow: every assertion held in %s (%s)" % (path, ", ".join(ASSERTIONS)))
    print("check-release-workflow: %d of %d assertions held" % (held, len(ASSERTIONS)))
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
    if not rows or any(len(r) != 3 for r in rows):
        die("cases.tsv rows must be three tab-separated fields: file, exit, sentence")

    print("check-release-workflow self-test\n")
    held, reached = 0, set()
    sandbox = tempfile.mkdtemp()
    try:
        extra = [
            ("not-yaml", 2, "is not parseable YAML", "on: [\n  : :\n"),
            ("no-release-draft", 2, "no job named release-draft",
             "on: push\npermissions:\n  contents: read\njobs:\n  release-prep:\n"
             "    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n"),
        ]
        targets = [(f, int(code), text, [os.path.join(FIXTURES, f)]) for f, code, text in rows]
        for name, code, text, body in extra:
            p = os.path.join(sandbox, name + ".yml")
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(body)
            targets.append((name, code, text, [p]))
        # A copy of this script beside a check-ci-template.py that defines none
        # of the shared rule: refused, never a traceback that reads as exit 1.
        lone = os.path.join(sandbox, "lone")
        os.mkdir(lone)
        shutil.copy(os.path.abspath(__file__), lone)
        with open(os.path.join(lone, "check-ci-template.py"), "w", encoding="utf-8") as fh:
            fh.write("VERSION = 'a stub with no rule'\n")
        targets.append(("shared-rule-gone", 2, "no longer defines write_perms",
                        [os.path.join(FIXTURES, "good.yml")],
                        os.path.join(lone, os.path.basename(__file__))))
        targets.append(("missing-file", 2, "could not read",
                        [os.path.join(sandbox, "absent.yml")]))
        targets.append(("usage", 2, "usage: check-release-workflow.py", ["a", "b"]))
        targets.append(("version", 0, "check-release-workflow 1.", ["--version"]))
        for t in targets:
            name, want, text, args = t[:4]
            script = t[4] if len(t) > 4 else os.path.abspath(__file__)
            proc = subprocess.run([sys.executable, script] + args,
                                  capture_output=True, text=True, timeout=60, cwd=sandbox)
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
    print("    NOT ASSERTED: that GitHub enforces the declared permissions or runs the jobs "
          "as written - nothing here runs a workflow, and the release jobs are proven only "
          "by a real tag push; the real .github/workflows/checks.yml (that is the declared "
          "check's run, not a self-test case); a command spelled through a variable or an "
          "alias, or code a system tool or an action from another repository runs; what "
          "git or gh may run - hooks, aliases, extensions; a write scope granted through a "
          "reusable workflow's own file; YAML anchors and merge keys; that an attach-pinned "
          "line is reachable - lines are matched in order, not as control flow; an "
          "expression in a script that is not a run:, such as actions/github-script's "
          "script:; that the hashes a PyYAML install names are PyPI's, or that pip on a "
          "runner accepts them.")
    if got != doc:
        print("FAIL: reached and documented exit codes differ")
        return 1
    return 0 if held == total else 1


def main(argv):
    args = argv[1:]
    if args == ["--version"]:
        print(VERSION)
        return 0
    if args in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    if args in (["--selftest"], ["--self-test"]):
        return selftest()
    if len(args) > 1 or (args and args[0].startswith("-")):
        die("usage: check-release-workflow.py [PATH] | --selftest | --version | --help")
    return report(args[0] if args else DEFAULT_PATH)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
