#!/usr/bin/env bash
# measure-check-underfire.sh [--config FILE] [--root DIR] [--plants FILE]
#                           (--list | --check ID)
#                           [--commits N | --since REF] [--per-run-timeout SECS]
#                           [--version] [--help] [--selftest]
#
# --commits defaults to 10. Each commit costs two replays per plant.
#
# Answers the question measure-check-overfire.sh is blind to by construction:
# WHEN THE DEFECT A CHECK EXISTS FOR IS ACTUALLY THERE, DOES THE CHECK FIRE?
#
# WHY THIS EXISTS. An over-fire rate cannot see a check that fires at nothing.
# Fourteen checks here read `0/30 = 0.0%` over merged history, and that figure
# is equally consistent with a check that correctly never fired and with a check
# that cannot fire at all. Only a defect that is KNOWN to be present can tell
# those apart, and merged history does not come with one. So this tool PLANTS
# one: it takes the tree of a real merged commit, writes into it a defect of
# exactly the kind the check's `why:` names, replays the check, and records
# whether it fired. The figure is RECALL - caught over planted - per kind of
# defect and per check.
#
# EVERY PLANT HAS A CONTROL, AND THE CONTROL IS WHAT MAKES A CATCH MEAN
# SOMETHING. A plant is a pair of edits of the same shape: the CONTROL (the same
# file, the same place, a neutral line) and the DEFECT (the line the check
# exists to catch). Both are applied to fresh copies of the same tree and both
# are replayed. A catch counts only when the control PASSED and the defect
# FIRED - otherwise a check that was already firing on that tree for some other
# reason would score a catch it did nothing to earn.
#
# WHAT IS COUNTED, AND WHAT IS EXCLUDED - NEVER COUNTED AS A MISS.
#
#   planted     a defect that was applied, VERIFIED to be in the tree by reading
#               it back, whose control passed, and whose replay returned a
#               verdict. This is the denominator.
#   caught      of those, the check fired
#   missed      of those, the check passed
#
#   out of scope     the defect lies outside the check's `when:`, so the runner
#                    would never have run the check on it. Not a miss: a check
#                    cannot be blamed for a path it was never handed. It is a
#                    SCOPE finding, and it is printed as one.
#   plant failed     the edit could not be applied or did not read back as
#                    written - an anchor absent at that commit, a file that did
#                    not exist yet, a bit that was never set. A miss here would
#                    be indistinguishable from a plant that never happened, so
#                    it is its own figure.
#   control fired    the neutral edit already fired, so a fire on the defect is
#                    not attributable to the defect
#   control no verdict / planted no verdict
#                    refused, timed out, an undeclared exit, or the tool absent
#                    at that commit. Nothing was examined.
#
# A recall over zero planted is n/a, never 0% and never 100%.
#
# PLANTS NEVER TOUCH THE REPOSITORY. Every tree is an extraction or a borrowed-
# history clone under this tool's own temporary directory, which it refuses to
# create inside the repository and removes on exit. Planted credentials are
# FAKE: random characters in the shape a scanner knows, generated at run time,
# written only into those trees, and never printed. The defect texts that a
# check of THIS repository would catch - a stderr redirection, a home-directory
# path, a credential shape - are assembled at run time from pieces, so this file
# does not carry them.
#
# HISTORY. A plant says which history its tree gets.
#
#   empty    `git archive` into a directory with an empty repository - the same
#            tree measure-check-overfire.sh replays by default. A check that
#            declares `git` cannot be planted this way; its plant is reported
#            unmeasurable rather than replayed against an absent history.
#   clone    a repository borrowing this one's objects read-only, with one
#            branch `main` at the commit and nothing after it. With it, a plant
#            also says its STAGE: `worktree` leaves the defect uncommitted (what
#            a pre-commit run sees), `committed` amends it into the commit with
#            the commit's own message (what CI sees). The same defect at the two
#            stages is two kinds, because a check can see one and not the other.
#
# THE CATALOGUE. The plants for this repository's checks are written below, in
# the engine, each with the reason it is in scope. --plants FILE replaces the
# catalogue with a JSON one of the same shape, which is how --selftest drives
# the tool against fixtures. A check the catalogue does not plant for is listed
# by --list with the reason, or as NO PLANT AND NO REASON when nobody has looked.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  measured - at least one plant reached a verdict under a passing control,
#      and recall over that count is printed, whatever its value. A recall of
#      0.0% is exit 0: it is a measurement, and the worst one this tool makes.
#      --list also exits 0.
#   2  could not run - bad usage, --list and --check together, --commits and
#      --since together, no config, an unparseable config, an unreadable or
#      malformed plants file, no python3, no yaml module, not a git work tree, a
#      shallow clone, a --check id the config does not declare, or a temporary
#      directory that would sit inside the repository
#   3  this check CANNOT be measured here - disabled, no command, its command
#      passes --base, its tool is absent on this machine, no plant is written
#      for it (with the reason when one is recorded), or every plant written for
#      it needs a history its tree would not have. Recall prints n/a or ?.
#   4  measured nothing - every plant was out of scope, failed to apply, or got
#      no verdict under a passing control. Recall prints n/a.
#
# Under --selftest: every case produced the code it declares (0), at least one
# did not (1 - reachable under --selftest and nowhere else), the fixture could
# not be built (2); 3 and 4 are driven as cases.
#
# WHAT THIS DOES NOT DO.
#
#   A recall on planted defects says NOTHING about defects of a kind nobody
#   planted. It measures the check against the catalogue, and the catalogue is
#   one person's guess at what the defect looks like. A check with 100% recall
#   here can still miss every real defect that is shaped differently.
#
#   It replays the check's exit code only, as measure-check-overfire.sh does.
#   The runner's COVERAGE layer - which can turn a passing exit into `hollow` -
#   is not replayed, so a defect the runner would have caught through coverage
#   and the check itself missed reads as a miss here.
#
#   A {files} or {file} check is handed only the planted paths, not the rest of
#   the commit's change set. That is what makes a catch attributable, and it is
#   narrower than what the runner hands it.
set -euo pipefail

VERSION="1.0"

CONFIG_REL=""
ROOT=""
CHECK_ID=""
COMMITS=""
SINCE=""
PER_RUN_TIMEOUT=""
PLANTS=""
MODE=""

die_unmeasured() {
  printf 'measure-check-underfire: %s\n' "$1" >&2
  exit 2
}

usage() {
  sed -n '2,/^set -euo pipefail$/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf 'measure-check-underfire.sh %s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --list) [ -z "$MODE" ] || die_unmeasured "--list and --check ask different questions; give one"; MODE="list"; shift ;;
    --check)
      [ "$#" -ge 2 ] || die_unmeasured "--check needs a check id"
      [ -z "$MODE" ] || die_unmeasured "--list and --check ask different questions; give one"
      MODE="measure"; CHECK_ID="$2"; shift 2 ;;
    --config) [ "$#" -ge 2 ] || die_unmeasured "--config needs a value"; CONFIG_REL="$2"; shift 2 ;;
    --root) [ "$#" -ge 2 ] || die_unmeasured "--root needs a value"; ROOT="$2"; shift 2 ;;
    --plants) [ "$#" -ge 2 ] || die_unmeasured "--plants needs a value"; PLANTS="$2"; shift 2 ;;
    --commits) [ "$#" -ge 2 ] || die_unmeasured "--commits needs a value"; COMMITS="$2"; shift 2 ;;
    --since) [ "$#" -ge 2 ] || die_unmeasured "--since needs a value"; SINCE="$2"; shift 2 ;;
    --per-run-timeout) [ "$#" -ge 2 ] || die_unmeasured "--per-run-timeout needs a value"; PER_RUN_TIMEOUT="$2"; shift 2 ;;
    *) die_unmeasured "unknown option: $1" ;;
  esac
done

# ---------------------------------------------------------------------------
# The engine. Written with double quotes only, because it sits inside a single-
# quoted shell string; a literal apostrophe is written \x27.
# ---------------------------------------------------------------------------
ENGINE='
import json, os, random, re, shutil, signal, stat, string, subprocess, sys, tarfile, time

mode, cfg_fp, root, check_id, n_commits, since, per_run_arg, work_root, plants_fp = sys.argv[1:10]

def refuse(msg, code=2):
    sys.stderr.write("measure-check-underfire: " + msg + "\n")
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

# The scratch directory must not be inside the repository: a plant written there
# would be a defect - a fake credential, a stderr redirection - in the work tree
# other people commit from.
real_root = os.path.realpath(root)
real_work = os.path.realpath(work_root)
if real_work == real_root or real_work.startswith(real_root.rstrip(os.sep) + os.sep):
    refuse("the temporary directory %s is inside the repository %s, and a plant written "
           "there would be a defect in the work tree. Point TMPDIR elsewhere." % (real_work, real_root))

# ---- the defect texts, assembled from pieces --------------------------------
# Each is built at run time so this file never carries the thing a check of this
# repository exists to catch. Credentials are random every run: FAKE, in the
# shape the scanner knows, and never printed.
R = random.SystemRandom()
ALNUM = string.ascii_letters + string.digits

def rs(n, alphabet=ALNUM):
    return "".join(R.choice(alphabet) for _ in range(n))

def pem():
    body = "".join(R.choice(ALNUM + "+/") for _ in range(64 * 12))
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    head = "-----BEGIN " + "RSA PRIV" + "ATE KEY-----"
    tail = "-----END " + "RSA PRIV" + "ATE KEY-----"
    return "\n".join([head] + lines + [tail])

TOKENS = {
    "@@DROP@@":      lambda: "2>" + "/dev/" + "null",
    "@@DEVNULL@@":   lambda: "/dev/" + "null",
    "@@HOMEMAC@@":   lambda: "/" + "Us" + "ers/" + "alice-planted/projects",
    "@@HOMELINUX@@": lambda: "/" + "ho" + "me/" + "alice-planted/projects",
    "@@HOMEWIN@@":   lambda: "C:" + "\\" + "Us" + "ers" + "\\" + "alice-planted",
    "@@LOCALHOST@@": lambda: "build-box-planted" + "." + "local" + " ",
    "@@PEM@@":       pem,
    "@@GHP@@":       lambda: "gh" + "p_" + rs(36),
    "@@AKIA@@":      lambda: "AK" + "IA" + rs(16, "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"),
    "@@GLPAT@@":     lambda: "gl" + "pat-" + rs(20),
    "@@SENDGRID@@":  lambda: "S" + "G." + rs(22) + "." + rs(43),
    "@@GENERIC@@":   lambda: rs(32, string.ascii_lowercase + string.digits),
    "@@SLACK@@":     lambda: "xo" + "xb-" + rs(12, string.digits) + "-" + rs(13, string.digits) + "-" + rs(24),
    "@@STRIPE@@":    lambda: "s" + "k_" + "live_" + rs(24),
    "@@NPMTOKEN@@":  lambda: "np" + "m_" + rs(36),
}

def expand(text):
    for tok, make in TOKENS.items():
        while tok in text:
            text = text.replace(tok, make(), 1)
    return text

# ---- the catalogue ------------------------------------------------------------
SCR = "plugins/productizer/skills/spec/scripts"
TPL = "plugins/productizer/skills/spec/templates"
SH_HEAD = "#!/usr/bin/env bash\nset -euo pipefail\n"
PLANTED_MD = "PLANTED-NOTES.md"

def new_file(path, control, defect, exe=False):
    return ([{"op": "create", "path": path, "text": control, "exec": exe}],
            [{"op": "create", "path": path, "text": defect, "exec": exe}])

def line_in(path, control, defect, line=1):
    return ([{"op": "insert", "path": path, "line": line, "text": control}],
            [{"op": "insert", "path": path, "line": line, "text": defect}])

def plant(check, kind, pair, history="empty", stage=None, why=""):
    return {"check": check, "kind": kind, "control": pair[0], "defect": pair[1],
            "history": history, "stage": stage, "why": why}

CRED_KINDS = [
    ("github token", "token: @@GHP@@\n"),
    ("aws access key", "aws_access_key_id = @@AKIA@@\n"),
    ("private key block", "@@PEM@@\n"),
    ("gitlab token", "GITLAB_TOKEN=@@GLPAT@@\n"),
    ("sendgrid key", "SENDGRID_API_KEY=@@SENDGRID@@\n"),
    ("generic assigned secret", "client_secret = \"@@GENERIC@@\"\n"),
    ("slack bot token", "SLACK_TOKEN=@@SLACK@@\n"),
    ("stripe live key", "STRIPE_KEY=@@STRIPE@@\n"),
    ("npm token", "//registry.npmjs.org/:_authToken=@@NPMTOKEN@@\n"),
]
CRED_CONTROL = "token: read it from the vault at run time\n"

DEFAULT = {"plants": [], "unplantable": {}}
P = DEFAULT["plants"]

# stderr-suppression - its why: an error and a genuine no-match look identical
# once stderr is discarded. Literal forms, one indirect form, and one form in a
# path its `when:` does not cover.
P.append(plant("stderr-suppression", "literal redirection, new script",
    new_file(SCR + "/zz-planted.sh", SH_HEAD + "ls /nonexistent-planted || true\n",
             SH_HEAD + "ls /nonexistent-planted @@DROP@@ || true\n", exe=True)))
P.append(plant("stderr-suppression", "literal redirection, inside run-checks.sh",
    line_in(SCR + "/run-checks.sh", "ls /nonexistent-planted || true",
            "ls /nonexistent-planted @@DROP@@ || true")))
P.append(plant("stderr-suppression", "exec redirection of the whole script",
    new_file(SCR + "/zz-planted.sh", SH_HEAD + "exec 2>&2\n",
             SH_HEAD + "exec @@DROP@@\n", exe=True)))
P.append(plant("stderr-suppression", "indirect: the sink held in a variable",
    new_file(SCR + "/zz-planted.sh", SH_HEAD + "sink=/dev/stderr\nls /nonexistent-planted 2>\"$sink\" || true\n",
             SH_HEAD + "sink=@@DEVNULL@@\nls /nonexistent-planted 2>\"$sink\" || true\n", exe=True)))
P.append(plant("stderr-suppression", "indirect: python stderr discarded inside a shell script",
    new_file(SCR + "/zz-planted.sh",
             SH_HEAD + "python3 -c \"import subprocess; subprocess.run([\x27ls\x27, \x27/x\x27])\"\n",
             SH_HEAD + "python3 -c \"import subprocess; subprocess.run([\x27ls\x27, \x27/x\x27], stderr=subprocess.DEVNULL)\"\n",
             exe=True)))
P.append(plant("stderr-suppression", "literal redirection in a workflow run: block",
    line_in(".github/workflows/checks.yml", "# planted: ls /nonexistent-planted || true",
            "# planted: ls /nonexistent-planted @@DROP@@ || true"),
    why="out of scope by construction: when: is **/*.sh and **/*.bash"))

# shell-lint - its why names an unquoted expansion. At --severity=warning
# shellcheck reports an unquoted COMMAND substitution (SC2046) but an unquoted
# VARIABLE (SC2086) is severity info, below the line this check draws. SC2164
# (cd with no failure branch) is not planted: under `set -e`, which every script
# here starts with, shellcheck correctly does not raise it - measured.
P.append(plant("shell-lint", "unquoted command substitution (SC2046, warning)",
    new_file(SCR + "/zz-planted.sh", SH_HEAD + "rm -f -- \"$(ls \"${1:-.}\")\"\n",
             SH_HEAD + "rm -f -- $(ls \"${1:-.}\")\n", exe=True)))
P.append(plant("shell-lint", "a declaration masking a failed substitution (SC2155, warning)",
    new_file(SCR + "/zz-planted.sh", SH_HEAD + "f() { local v; v=\"$(false)\"; echo \"$v\"; }\nf\n",
             SH_HEAD + "f() { local v=\"$(false)\"; echo \"$v\"; }\nf\n", exe=True)))
P.append(plant("shell-lint", "unused variable inside run-checks.sh (SC2034, warning)",
    line_in(SCR + "/run-checks.sh", "true", "planted_unused_var=1")))
P.append(plant("shell-lint", "unquoted expansion, the kind its why names (SC2086, info)",
    new_file(SCR + "/zz-planted.sh", SH_HEAD + "cp -- \"$1\" \"$2\"\n",
             SH_HEAD + "cp -- $1 $2\n", exe=True)))

# hygiene - personal paths, hostnames and credential shapes in a public repo.
for kind, text in [("home path, macOS", "notes: @@HOMEMAC@@/thing\n"),
                   ("home path, linux", "notes: @@HOMELINUX@@/thing\n"),
                   ("home path, windows", "notes: @@HOMEWIN@@\\thing\n"),
                   ("machine hostname", "built on @@LOCALHOST@@yesterday\n")] + CRED_KINDS:
    P.append(plant("hygiene", kind, new_file(PLANTED_MD, "notes: nothing personal here\n", text)))

# secret-scan - gitleaks over the whole tree.
for kind, text in CRED_KINDS:
    P.append(plant("secret-scan", kind, new_file(PLANTED_MD, CRED_CONTROL, text)))

# sast - injection and unsafe evaluation in shipped Python and JavaScript.
PY = "import subprocess, sys\n"
for kind, ctl, bad in [
        ("python subprocess shell=True", PY + "def run(u):\n    subprocess.call([\"ls\", u])\nrun(sys.argv[1])\n",
                                         PY + "def run(u):\n    subprocess.call(\"ls \" + u, shell=True)\nrun(sys.argv[1])\n"),
        ("python eval of an argument", PY + "def run(u):\n    return int(u)\nrun(sys.argv[1])\n",
                                       PY + "def run(u):\n    return eval(u)\nrun(sys.argv[1])\n"),
        ("python os.system of an argument", "import os, sys\ndef run(u):\n    os.execvp(\"ls\", [\"ls\", u])\nrun(sys.argv[1])\n",
                                            "import os, sys\ndef run(u):\n    os.system(\"ls \" + u)\nrun(sys.argv[1])\n"),
        ("python pickle of untrusted input", "import json, sys\nobj = json.loads(sys.stdin.read())\n",
                                             "import pickle, sys\nobj = pickle.loads(sys.stdin.buffer.read())\n"),
        ("python tarfile extractall", "import tarfile, sys\nwith tarfile.open(sys.argv[1]) as tf:\n    tf.extractall(sys.argv[2], filter=\"data\")\n",
                                      "import tarfile, sys\nwith tarfile.open(sys.argv[1]) as tf:\n    tf.extractall(sys.argv[2])\n")]:
    P.append(plant("sast", kind, new_file(SCR + "/zz_planted.py", ctl, bad)))
P.append(plant("sast", "javascript child_process.exec of request input",
    new_file(SCR + "/zz-planted.js",
             "const cp = require(\"child_process\");\nfunction run(req) { cp.execFile(\"ls\", [req.query.dir]); }\nmodule.exports = run;\n",
             "const cp = require(\"child_process\");\nfunction run(req) { cp.exec(\"ls \" + req.query.dir); }\nmodule.exports = run;\n")))
P.append(plant("sast", "python eval inside a shell heredoc",
    new_file(SCR + "/zz-planted.sh", SH_HEAD + "python3 - \"$1\" <<\x27EOF\x27\nimport sys\nprint(int(sys.argv[1]))\nEOF\n",
             SH_HEAD + "python3 - \"$1\" <<\x27EOF\x27\nimport sys\nprint(eval(sys.argv[1]))\nEOF\n", exe=True),
    why="out of scope by construction: when: is .py/.js/.ts/.go, and most Python this plugin runs lives in shell heredocs"))

# dependency-audit - npm audit on a root manifest. Needs the npm registry.
def npm_pair(ver, lock):
    man = "{\"name\":\"planted\",\"version\":\"1.0.0\",\"dependencies\":{\"minimist\":\"%s\"}}\n" % ver
    edits = [{"op": "create", "path": "package.json", "text": man}]
    if lock:
        edits.append({"op": "create", "path": "package-lock.json", "text":
            ("{\"name\":\"planted\",\"version\":\"1.0.0\",\"lockfileVersion\":3,\"requires\":true,\"packages\":"
             "{\"\":{\"name\":\"planted\",\"version\":\"1.0.0\",\"dependencies\":{\"minimist\":\"%s\"}},"
             "\"node_modules/minimist\":{\"version\":\"%s\",\"resolved\":"
             "\"https://registry.npmjs.org/minimist/-/minimist-%s.tgz\"}}}\n") % (ver, ver, ver)})
    return edits
P.append(plant("dependency-audit", "critical advisory in a locked dependency",
    (npm_pair("1.2.8", True), npm_pair("0.0.8", True))))
P.append(plant("dependency-audit", "critical advisory, manifest with no lockfile",
    (npm_pair("1.2.8", False), npm_pair("0.0.8", False))))

# risk-tier-classified - a path no rule covers. Needs git only to find its root.
P.append(plant("risk-tier-classified", "a path under a directory no rule covers",
    ([{"op": "create", "path": "evals/zz-planted.md", "text": "planted\n"}],
     [{"op": "create", "path": "zz-planted-dir/new-file.txt", "text": "planted\n"}]),
    history="clone", stage="worktree"))

# template-frontmatter - a mistyped key falls back to a default silently.
AV = TPL + "/agent-verifier.md"
P.append(plant("template-frontmatter", "an undocumented key",
    ([{"op": "replace", "path": AV, "old": "tools: Bash, Read\n", "new": "tools: Bash, Read\ncolor: blue\n"}],
     [{"op": "replace", "path": AV, "old": "tools: Bash, Read\n", "new": "tools: Bash, Read\ncolour: blue\n"}])))
P.append(plant("template-frontmatter", "the tools allowlist key misspelled",
    ([{"op": "replace", "path": AV, "old": "tools: Bash, Read\n", "new": "tools: Read, Bash\n"}],
     [{"op": "replace", "path": AV, "old": "tools: Bash, Read\n", "new": "tool: Bash, Read\n"}])))

# guide-current - a hand edit inside the generated requirements section.
END = "<!-- productizer:requirements:end -->"
P.append(plant("guide-current", "a hand edit inside the generated section",
    ([{"op": "replace", "path": "GUIDE.md", "old": END, "new": END + "\nA planted hand edit."}],
     [{"op": "replace", "path": "GUIDE.md", "old": END, "new": "A planted hand edit.\n" + END}])))
P.append(plant("guide-current", "prose outside the section naming a requirement the spec lacks",
    ([{"op": "replace", "path": "GUIDE.md", "old": END, "new": END + "\nA planted note about the spec."}],
     [{"op": "replace", "path": "GUIDE.md", "old": END, "new": END + "\nA planted note about R999."}])))

# installed-copies - a hook that drifted from its template, or lost its bit.
HOOK, GATE = ".claude/hooks/publish-gate.sh", TPL + "/publish-gate.sh"
P.append(plant("installed-copies", "the installed hook drifted from its template",
    ([{"op": "append", "path": HOOK, "text": "# planted note\n"}, {"op": "append", "path": GATE, "text": "# planted note\n"}],
     [{"op": "append", "path": HOOK, "text": "# planted note\n"}])))
P.append(plant("installed-copies", "the installed hook lost its executable bit",
    ([{"op": "chmod_on", "path": HOOK}], [{"op": "chmod_off", "path": HOOK}])))

# the publish gate disarmed in BOTH copies, so installed-copies has nothing to
# say and the checks that drive the gate are the only ones that can notice.
DISARM = ([{"op": "insert", "path": GATE, "line": 1, "text": ":"}, {"op": "insert", "path": HOOK, "line": 1, "text": ":"}],
          [{"op": "insert", "path": GATE, "line": 1, "text": "exit 0"}, {"op": "insert", "path": HOOK, "line": 1, "text": "exit 0"}])
P.append(plant("publish-gate-decides", "the publish gate allows everything, both copies", DISARM))
P.append(plant("untrusted-execution", "the publish gate allows everything, both copies", DISARM))
AHOOK, AGATE = ".claude/hooks/artifact-gate.sh", TPL + "/artifact-gate.sh"
P.append(plant("view-publish-refused", "the artifact gate allows everything, both copies",
    ([{"op": "insert", "path": AGATE, "line": 1, "text": ":"}, {"op": "insert", "path": AHOOK, "line": 1, "text": ":"}],
     [{"op": "insert", "path": AGATE, "line": 1, "text": "exit 0"}, {"op": "insert", "path": AHOOK, "line": 1, "text": "exit 0"}])))

# the runner records a missing tool as a pass - R13 and R26 exist for this.
RC = SCR + "/run-checks.sh"
MISSING = ([{"op": "replace", "path": RC, "old": "row[\"status\"] = \"missing_tool\"\n",
             "new": "row[\"status\"] = \"missing_tool\"  # planted note\n"}],
           [{"op": "replace", "path": RC, "old": "row[\"status\"] = \"missing_tool\"\n",
             "new": "row[\"status\"] = \"pass\"\n"}])
for chk in ("missing-tool-reported", "no-fabricated-zero"):
    P.append(plant(chk, "the runner records a missing tool as a pass", MISSING))
KEEPCOV = ([{"op": "replace", "path": RC, "after": "    if row[\"status\"] in CANNOT_RUN:\n",
             "old": "        del row[\"coverage\"]\n", "new": "        del row[\"coverage\"]  # planted note\n"}],
           [{"op": "replace", "path": RC, "after": "    if row[\"status\"] in CANNOT_RUN:\n",
             "old": "        del row[\"coverage\"]\n", "new": "        pass\n"}])
for chk in ("cannot-run-coverage", "no-fabricated-zero"):
    P.append(plant(chk, "a row that reached no verdict keeps its coverage count", KEEPCOV))

# acceptance-rows - a requirement with no row, and a row naming a check that is not there.
SPEC = ".claude/productizer/spec.md"
REQ = [{"op": "replace", "path": SPEC, "old": "\n\n### Event-driven",
        "new": "\n- **R999** — The lifecycle shall keep a planted requirement.\n\n### Event-driven"}]
ROW_OK = {"op": "replace", "path": SPEC, "old": "\n\n## Change log", "new": "\n| R999 | Nothing yet. |\n\n## Change log"}
ROW_GHOST = {"op": "replace", "path": SPEC, "old": "\n\n## Change log",
             "new": "\n| R999 | `ghost-planted` check over `check-ghost-planted.sh` |\n\n## Change log"}
P.append(plant("acceptance-rows", "a requirement with no acceptance row", (REQ + [ROW_OK], REQ)))
P.append(plant("acceptance-rows", "a row naming a check and a script that do not exist", (REQ + [ROW_OK], REQ + [ROW_GHOST])))

# spec-home - the declared home is not the repository holding the spec.
CONF = ".claude/productizer/config.json"
P.append(plant("spec-home", "the declared home names a repository outside the product",
    ([{"op": "replace", "path": CONF, "old": "\"name\": \"productizer\"", "new": "\"name\": \"productizer-planted\""}],
     [{"op": "replace", "path": CONF, "old": "\"spec_home\": \"gitayg/productizer\"", "new": "\"spec_home\": \"gitayg/elsewhere\""}])))

# retrieval-budget - its cost is the candidate lines read, in file order, up to
# the target. So the plant is twelve lines carrying a prompt\x27s terms, placed
# BEFORE that prompt\x27s target; the control is twelve lines carrying none.
# Growth AFTER the target is not planted as a defect: it does not change the
# cost this check measures (measured - the spec grew 39696 to 71297 bytes at its
# end and the check stayed green, which is the check measuring what it says).
def spec_lines(sentence):
    return "".join("- **R%d** — %s\n" % (900 + i, sentence) for i in range(12))
P.append(plant("retrieval-budget", "prompt-matching lines ahead of the target (unmeasured-zero, R26)",
    ([{"op": "replace", "path": SPEC, "old": "\n- **R25** — ",
       "new": "\n" + spec_lines("The lifecycle shall keep a planted line beside it.") + "- **R25** — "}],
     [{"op": "replace", "path": SPEC, "old": "\n- **R25** — ",
       "new": "\n" + spec_lines("If a planted value is measured, then the lifecycle shall keep a zero beside it.") + "- **R25** — "}])))

# view-rendered - the prefers-contrast block no longer applies.
VIEW = TPL + "/view.html"
P.append(plant("view-rendered", "the prefers-contrast block no longer matches",
    ([{"op": "replace", "path": VIEW, "old": "@media (prefers-contrast: more){", "new": "@media (prefers-contrast: more){ /* planted note */"}],
     [{"op": "replace", "path": VIEW, "old": "@media (prefers-contrast: more){", "new": "@media (prefers-contrast: planted-never){"}])))

# governance - loosening a declared check, seen before the commit and after it.
CY = ".claude/productizer/checks.yaml"
def cy(after, old, new):
    return {"op": "replace", "path": CY, "after": after, "until": "\n  - id: ", "old": old, "new": new}
WHY_EDIT = cy("  - id: hygiene\n", "    why: ", "    why: planted note - ")
for stage in ("worktree", "committed"):
    P.append(plant("governance-weakening", "a blocking check lowered to advise, %s" % stage,
        ([WHY_EDIT], [cy("  - id: hygiene\n", "    severity: block\n", "    severity: advise\n")]),
        history="clone", stage=stage))
    P.append(plant("governance-weakening", "a check switched off, %s" % stage,
        ([WHY_EDIT], [cy("  - id: hygiene\n", "    why: ", "    enabled: false\n    why: ")]),
        history="clone", stage=stage))
    P.append(plant("governance-self-footing", "the sweep switched off, %s" % stage,
        ([WHY_EDIT], [cy("  - id: governance-weakening\n", "    why: ", "    enabled: false\n    why: ")]),
        history="clone", stage=stage))

# diff-paths-named - a path swept into a commit whose message does not name it.
P.append(plant("diff-paths-named", "a file swept into the commit, unnamed",
    ([{"op": "create", "path": "evals/zz-swept-planted.md", "text": "swept\n"},
      {"op": "message", "text": "Also adds evals/zz-swept-planted.md."}],
     [{"op": "create", "path": "evals/zz-swept-planted.md", "text": "swept\n"}]),
    history="clone", stage="committed"))

U = DEFAULT["unplantable"]
U["solver-corpus"] = ("it runs the solver against its own labelled corpus; the defect is a wrong DECISION inside "
                      "contradiction-check.py, and a plant would be a mutation of the solver chosen to break a "
                      "case the corpus already holds - a test of the corpus, not a recall figure")
U["ruling-requested"] = "its defect is a halted contradiction with no drafted ruling; planting one means fabricating a halt record whose shape this tool would be guessing"
U["view-read-only"] = "its defect is a view build that writes into the repository; planting one means a build-view.sh mutation that writes, and none was written"
U["import-marking"] = "its defect exists only after a Stage 0c import; with no import on the record the obligation never arises, and fabricating an import is guessing its shape"
U["classification-provenance"] = "its defect is a classification record citing a partial spec; the records cite commits, so a plant needs a fabricated classification run"
U["jira-unbound"] = "its defect is a Jira n/a that should have expired; a plant needs a fabricated binding state across two files"
U["nothing-merged"] = "its defect is a halted contradiction that merged anyway; a plant needs a fabricated halt plus a merge"
U["spec-home-stop"] = "it drives fixtures of an unreachable spec home; the defect is a regression in the stop, a mutation nobody wrote"
U["declared-scope"] = "it drives the runner over a fixture of a check that examined less than it declared; the defect is a runner mutation nobody wrote"
U["unmeasured-report"] = "it drives four view builds and a survey over fixtures; the defect is a mutation of build-view.sh or import-survey.sh nobody wrote, at about 16s per replay"
U["waiver-rendering"] = "it drives the runner over waiver fixtures; the defect is a mutation of waiver handling nobody wrote"
U["selftest-coverage"] = "a plant is a new tool with no self-test, and its replay probes every self-test in the tree - 13 of 30 over-fire replays timed out at 25s"
U["superseded-text"] = "its defect is a superseded sentence rewritten after the fact; a plant needs a rewrite committed on top of the real supersede, in history"
U["pending-ruling-scope"] = "its defect is a pending ruling that blocks the wrong set; a plant needs a fabricated pending ruling"
U["spec-integrity"] = "its defect is an id that changed meaning across history; a plant needs a rewritten requirement committed on top of the real one"
U["changelog-row"] = "its defect is a requirement that moved with no change-log row; a plant needs a requirement move committed on top of the real history"
U["suspect-links"] = "advisory, and its defect is a rewritten sentence with stale citations across a base range; not planted"
U["sast-auth"] = "disabled"
U["secure-coding-controls"] = "disabled"
U["pii-log-scan"] = "disabled"

# ---- load the catalogue in use ------------------------------------------------
if plants_fp:
    try:
        with open(plants_fp, "r", encoding="utf-8") as fh:
            catalogue = json.load(fh)
    except OSError as exc:
        refuse("the plants file could not be read: %s" % exc)
    except ValueError as exc:
        refuse("the plants file is not JSON: %s" % exc)
else:
    catalogue = DEFAULT

OPS = {"create", "insert", "append", "replace", "chmod_off", "chmod_on", "message"}
if not isinstance(catalogue, dict) or not isinstance(catalogue.get("plants"), list):
    refuse("the plants file declares no plants list")
for pl in catalogue["plants"]:
    for side in ("control", "defect"):
        edits = pl.get(side)
        if not isinstance(edits, list):
            refuse("plant %r has no %s edit list" % (pl.get("kind"), side))
        for e in edits:
            if not isinstance(e, dict) or e.get("op") not in OPS:
                refuse("plant %r carries an edit with an unknown op: %r" % (pl.get("kind"), e))
            if e["op"] == "message" and pl.get("stage") != "committed":
                refuse("plant %r edits the commit message but is not committed" % pl.get("kind"))
    if pl.get("history", "empty") not in ("empty", "clone"):
        refuse("plant %r names a history that is neither empty nor clone" % pl.get("kind"))
    if pl.get("history") == "clone" and pl.get("stage") not in ("worktree", "committed"):
        refuse("plant %r has a clone history and no stage" % pl.get("kind"))
unplantable = catalogue.get("unplantable") or {}

# ---- shared machinery -----------------------------------------------------------
def git(*args):
    return subprocess.run(["git", "-C", root] + list(args), stdout=subprocess.PIPE,
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

def check_gate(chk):
    """(measurable, reason, placeholder) before any plant is looked at."""
    if chk.get("enabled") is False:
        return False, "disabled - a shut guard fires on nothing", "n/a"
    cmd = chk.get("command")
    if not isinstance(cmd, list) or not cmd:
        return False, "no command to run", "n/a"
    if any(isinstance(a, str) and a == "--base" for a in cmd):
        return False, "the command passes --base, which no planted tree can honour", "n/a"
    absent = [r for r in (chk.get("requires") or []) if r != "git" and not tool_present(r)]
    if absent:
        return False, "tool absent on this machine: " + ", ".join(absent), "?"
    return True, "", None

def plant_gate(chk, pl):
    """None when this plant can be replayed for this check, else why not."""
    if "git" in (chk.get("requires") or []) and pl.get("history", "empty") != "clone":
        return ("the check declares git and this plant gives its tree an empty history, "
                "so the replay would answer about the extraction")
    return None

def in_scope(chk, pl):
    when = chk.get("when") or {}
    if when.get("always"):
        return True
    globs = [glob_to_regex(g) for g in (when.get("paths") or [])]
    paths = [e["path"] for e in pl["defect"] if "path" in e]
    return any(any(rx.match(p) for rx in globs) for p in paths)

def handed(chk, edits):
    when = chk.get("when") or {}
    paths = []
    for e in edits:
        if "path" in e and e["path"] not in paths:
            paths.append(e["path"])
    if when.get("always"):
        return paths
    globs = [glob_to_regex(g) for g in (when.get("paths") or [])]
    return [p for p in paths if any(rx.match(p) for rx in globs)]

by_id = {c.get("id"): c for c in cfg["checks"]}

if mode == "list":
    print("    every check in this config, and what the plant catalogue holds for it")
    print("      %-26s %-7s %s" % ("check", "plants", "kinds, or why there are none"))
    counted = named = silent = 0
    for chk in cfg["checks"]:
        cid = chk.get("id") or "(no id)"
        mine = [pl for pl in catalogue["plants"] if pl.get("check") == cid]
        if mine:
            counted += 1
            kinds = "; ".join(pl["kind"] for pl in mine)
            print("      %-26s %-7d %s" % (cid[:26], len(mine), kinds[:150]))
        elif cid in unplantable:
            named += 1
            print("      %-26s %-7s NONE - %s" % (cid[:26], "-", unplantable[cid][:150]))
        else:
            silent += 1
            print("      %-26s %-7s NO PLANT AND NO REASON - nobody has looked" % (cid[:26], "-"))
    print("    checks with plants: %d   without, reason recorded: %d   without, no reason: %d   of %d"
          % (counted, named, silent, len(cfg["checks"])))
    print("    A check without a plant has NO recall figure. That is not 100% and not 0%.")
    raise SystemExit(0)

# ---- measure one check --------------------------------------------------------
if check_id not in by_id:
    refuse("the config declares no check with id %r" % check_id)
chk = by_id[check_id]
print("    check: %s" % check_id)
print("    catches, by its own why: %s" % " ".join(str(chk.get("why", "(no why)")).split())[:300])

if git("rev-parse", "--git-dir").returncode != 0:
    refuse("not a git work tree, so no tree at any commit could be obtained")
if git("rev-parse", "--is-shallow-repository").stdout.strip() == "true":
    refuse("this clone is shallow; the trees planted into would not be this branch")

ok, why, placeholder = check_gate(chk)
if not ok:
    print("    measurable: NO - %s" % why)
    print("    recall: %s" % placeholder)
    print("    NOT MEASURED. This is not a recall of 0% or of 100%.")
    raise SystemExit(3)

mine = [pl for pl in catalogue["plants"] if pl.get("check") == check_id]
if not mine:
    reason = unplantable.get(check_id)
    print("    measurable: NO - no plant is written for this check")
    print("    reason: %s" % (reason if reason else "none recorded - nobody has looked"))
    print("    recall: n/a")
    print("    NOT MEASURED. A check nobody planted for has no recall figure.")
    raise SystemExit(3)
usable = [pl for pl in mine if plant_gate(chk, pl) is None]
if not usable:
    print("    measurable: NO - %s" % plant_gate(chk, mine[0]))
    print("    recall: n/a")
    raise SystemExit(3)

if since:
    rl = git("rev-list", "--no-merges", since + "..HEAD")
else:
    rl = git("rev-list", "--no-merges", "-n", n_commits, "HEAD")
if rl.returncode != 0:
    refuse("the commit range could not be resolved")
commits = [c for c in rl.stdout.split() if c]
if not commits:
    refuse("the range names no commit, so nothing could be planted into")

per_run = float(per_run_arg) if per_run_arg else float(
    chk.get("timeout_seconds") or defaults.get("timeout_seconds") or 180)
codes = chk.get("exit_codes") or {}
pass_c = set(codes.get("pass") or [])
fail_c = set(codes.get("fail") or [])
ref_c = set(codes.get("refused") or [])
cmd_tpl = chk["command"]
print("    measurable: yes - %d plant kind(s) over %d commit(s), %.0fs per replay"
      % (len(mine), len(commits), per_run))

common = git("rev-parse", "--git-common-dir").stdout.strip()
objects_dir = os.path.abspath(os.path.join(root, common, "objects"))
work = os.path.join(work_root, "trees")
tars = os.path.join(work_root, "tars")
child_tmp_root = os.path.join(work_root, "child-tmp")
for d in (work, tars, child_tmp_root):
    os.makedirs(d, exist_ok=True)

def _bail(signum, _frame):
    raise SystemExit(143 if signum == signal.SIGTERM else 130)
signal.signal(signal.SIGTERM, _bail)
signal.signal(signal.SIGINT, _bail)

def quiet(argv, cwd=None):
    return subprocess.run(argv, cwd=cwd, stdout=subprocess.DEVNULL, stderr=None).returncode

GITC = ["-c", "user.email=plant@example.invalid", "-c", "user.name=plant",
        "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/nonexistent-hooks"]

def provision(sha, history, tree):
    if history == "clone":
        if quiet(["git", "init", "--quiet", tree]) != 0:
            return "git init failed"
        with open(os.path.join(tree, ".git", "objects", "info", "alternates"), "w") as fh:
            fh.write(objects_dir + "\n")
        for argv in (["git", "-C", tree, "config", "gc.auto", "0"],
                     ["git", "-C", tree, "update-ref", "refs/heads/main", sha],
                     ["git", "-C", tree, "symbolic-ref", "HEAD", "refs/heads/main"],
                     ["git", "-C", tree, "reset", "--hard", "--quiet"]):
            if quiet(argv) != 0:
                return "could not build the clone: " + argv[3]
        return None
    tar_fp = os.path.join(tars, sha + ".tar")
    if not os.path.exists(tar_fp):
        with open(tar_fp, "wb") as th:
            if subprocess.run(["git", "-C", root, "archive", "--format=tar", sha],
                              stdout=th, stderr=None).returncode != 0:
                os.unlink(tar_fp)
                return "git archive failed"
    os.makedirs(tree, exist_ok=True)
    with tarfile.open(tar_fp) as tf:
        try:
            tf.extractall(tree, filter="data")
        except TypeError:
            tf.extractall(tree)
    quiet(["git", "init", "--quiet", tree])
    return None

def read_text(fp):
    with open(fp, "rb") as fh:
        return fh.read().decode("utf-8", "surrogateescape")

def write_text(fp, text):
    with open(fp, "wb") as fh:
        fh.write(text.encode("utf-8", "surrogateescape"))

def apply_edits(tree, edits):
    """Apply and VERIFY each edit. Returns (None, touched, expected) or (reason, ...)."""
    touched, expected = [], {}
    for e in edits:
        op = e["op"]
        if op == "message":
            continue
        fp = os.path.join(tree, e["path"])
        if op == "create":
            if os.path.lexists(fp):
                return "%s already exists at this commit" % e["path"], touched, expected
            os.makedirs(os.path.dirname(fp) or tree, exist_ok=True)
            text = expand(e["text"])
            write_text(fp, text)
            if e.get("exec"):
                os.chmod(fp, 0o755)
            expected[e["path"]] = text
        elif op in ("insert", "append", "replace"):
            if not os.path.isfile(fp):
                return "%s is absent at this commit" % e["path"], touched, expected
            orig = read_text(fp)
            if op == "insert":
                lines = orig.split("\n")
                n = int(e.get("line", 1))
                if len(lines) < n:
                    return "%s has fewer than %d lines" % (e["path"], n), touched, expected
                new = "\n".join(lines[:n] + [expand(e["text"])] + lines[n:])
            elif op == "append":
                new = orig + ("" if orig.endswith("\n") or not orig else "\n") + expand(e["text"])
            else:
                start, end = 0, len(orig)
                if e.get("after"):
                    i = orig.find(e["after"])
                    if i < 0:
                        return "anchor %r absent from %s" % (e["after"][:40], e["path"]), touched, expected
                    start = i + len(e["after"])
                    if e.get("until"):
                        j = orig.find(e["until"], start)
                        if j >= 0:
                            end = j
                k = orig.find(e["old"], start, end)
                if k < 0:
                    return "text %r absent from %s where the plant goes" % (e["old"][:40], e["path"]), touched, expected
                new = orig[:k] + expand(e["new"]) + orig[k + len(e["old"]):]
            if new == orig:
                return "the edit to %s changed nothing" % e["path"], touched, expected
            mode_before = os.stat(fp).st_mode
            write_text(fp, new)
            os.chmod(fp, stat.S_IMODE(mode_before))
            expected[e["path"]] = new
        elif op in ("chmod_off", "chmod_on"):
            if not os.path.isfile(fp):
                return "%s is absent at this commit" % e["path"], touched, expected
            m = stat.S_IMODE(os.stat(fp).st_mode)
            if op == "chmod_off":
                if not m & 0o111:
                    return "%s was never executable, so losing the bit cannot land" % e["path"], touched, expected
                os.chmod(fp, m & ~0o111)
            else:
                os.chmod(fp, m | 0o755)
        if e["path"] not in touched:
            touched.append(e["path"])
    # VERIFY: read every edited path back. An edit that did not land is a plant
    # that did not happen, and replaying it would score a miss nobody earned.
    for e in edits:
        if e["op"] == "message":
            continue
        fp = os.path.join(tree, e["path"])
        if e["op"] in ("chmod_off", "chmod_on"):
            execy = bool(stat.S_IMODE(os.stat(fp).st_mode) & 0o111)
            if execy != (e["op"] == "chmod_on"):
                return "the mode of %s did not read back as set" % e["path"], touched, expected
        elif not os.path.isfile(fp) or read_text(fp) != expected.get(e["path"]):
            return "%s did not read back as written" % e["path"], touched, expected
    return None, touched, expected

def commit_plant(tree, edits, touched, expected):
    """Amend the plant into HEAD, keeping the commit message, then verify it is there."""
    msg = subprocess.run(["git", "-C", tree, "log", "-1", "--format=%B"], stdout=subprocess.PIPE,
                         stderr=None, text=True).stdout.rstrip("\n")
    extra = [expand(e["text"]) for e in edits if e["op"] == "message"]
    if extra:
        msg = msg + "\n\n" + "\n".join(extra)
    if touched and quiet(["git", "-C", tree] + GITC + ["add", "-A", "-f", "--"] + touched) != 0:
        return "git add of the plant failed"
    if quiet(["git", "-C", tree] + GITC + ["commit", "--quiet", "--amend", "--no-verify",
                                        "--allow-empty", "-m", msg]) != 0:
        return "amending the plant into the commit failed"
    st = subprocess.run(["git", "-C", tree, "status", "--porcelain", "--"] + (touched or ["."]),
                        stdout=subprocess.PIPE, stderr=None, text=True).stdout.strip()
    if st:
        return "the plant is still uncommitted after the amend"
    for path, text in expected.items():
        shown = subprocess.run(["git", "-C", tree, "show", "HEAD:" + path], stdout=subprocess.PIPE,
                               stderr=None).stdout.decode("utf-8", "surrogateescape")
        if shown != text:
            return "%s in the amended commit is not what was planted" % path
    if extra:
        body = subprocess.run(["git", "-C", tree, "log", "-1", "--format=%B"], stdout=subprocess.PIPE,
                              stderr=None, text=True).stdout
        if not all(x in body for x in extra):
            return "the commit message did not take the planted line"
    return None

def worktree_dirty(tree, touched):
    st = subprocess.run(["git", "-C", tree, "status", "--porcelain", "--untracked-files=all", "--"] + touched,
                        stdout=subprocess.PIPE, stderr=None, text=True).stdout.strip()
    return bool(st)

def replay(tree, files, sha, label):
    """Run the check. Returns pass | fired | refused | undeclared | timed_out | tool_absent."""
    exe = str(cmd_tpl[0])
    if exe.startswith("./") and not os.path.isfile(os.path.join(tree, exe[2:])):
        return "tool_absent"
    per_file = any(str(a) == "{file}" for a in cmd_tpl)
    uses_files = per_file or any(str(a) == "{files}" for a in cmd_tpl)
    if uses_files and not files:
        return "tool_absent"
    rcs = []
    for one in (files if per_file else [None]):
        argv = []
        for a in cmd_tpl:
            a = str(a)
            if a == "{files}":
                argv.extend(files)
            elif a == "{file}":
                argv.append(one)
            else:
                argv.append(a)
        child_tmp = os.path.join(child_tmp_root, "%s-%s-%d" % (sha[:12], label, len(rcs)))
        os.makedirs(child_tmp, exist_ok=True)
        try:
            proc = subprocess.Popen(argv, cwd=tree, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    text=True, start_new_session=True,
                                    env=dict(os.environ, TMPDIR=child_tmp))
        except OSError:
            return "tool_absent"
        try:
            proc.communicate(timeout=per_run)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                proc.kill()
            try:
                proc.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                pass
            return "timed_out"
        rcs.append(proc.returncode)
    und = [c for c in rcs if c not in pass_c and c not in fail_c and c not in ref_c]
    if und:
        return "undeclared"
    if any(c in ref_c for c in rcs):
        return "refused"
    if any(c in fail_c for c in rcs):
        return "fired"
    return "pass"

BUCKETS = ("out_of_scope", "unmeasurable", "plant_failed", "control_fired", "control_none",
           "planted_none", "caught", "missed")
rows = []
for pl in mine:
    rows.append(dict(plant=pl, missed_at=[], failed_why={}, none_why={}, **{b: 0 for b in BUCKETS}))

t0 = time.time()
seq = 0
try:
    for ci, sha in enumerate(commits):
        for row in rows:
            pl = row["plant"]
            if not in_scope(chk, pl):
                row["out_of_scope"] += 1
                continue
            if plant_gate(chk, pl) is not None:
                row["unmeasurable"] += 1
                continue
            history = pl.get("history", "empty")
            outcome = {}
            for side in ("control", "defect"):
                seq += 1
                tree = os.path.join(work, "%s-%d" % (sha[:12], seq))
                err = provision(sha, history, tree)
                if err is None:
                    err, touched, expected = apply_edits(tree, pl[side])
                if err is None and history == "clone":
                    if pl["stage"] == "committed":
                        err = commit_plant(tree, pl[side], touched, expected)
                    elif touched and not worktree_dirty(tree, touched):
                        err = "the plant does not show as a change against HEAD"
                if err is not None:
                    outcome[side] = ("plant_failed", err)
                    shutil.rmtree(tree, ignore_errors=True)
                    break
                outcome[side] = (replay(tree, handed(chk, pl[side]), sha, side), None)
                shutil.rmtree(tree, ignore_errors=True)
                if side == "control" and outcome[side][0] != "pass":
                    break
            ctl = outcome.get("control")
            dfc = outcome.get("defect")
            if ctl[0] == "plant_failed" or (dfc and dfc[0] == "plant_failed"):
                why = (dfc if dfc and dfc[0] == "plant_failed" else ctl)[1]
                row["plant_failed"] += 1
                row["failed_why"][why] = row["failed_why"].get(why, 0) + 1
                verdict = "plant failed: " + why
            elif ctl[0] == "fired":
                row["control_fired"] += 1
                verdict = "control fired"
            elif ctl[0] != "pass":
                row["control_none"] += 1
                verdict = "control " + ctl[0]
                row["none_why"][verdict] = row["none_why"].get(verdict, 0) + 1
            elif dfc[0] == "fired":
                row["caught"] += 1
                verdict = "CAUGHT"
            elif dfc[0] == "pass":
                row["missed"] += 1
                row["missed_at"].append(sha[:12])
                verdict = "MISSED"
            else:
                row["planted_none"] += 1
                verdict = "planted " + dfc[0]
                row["none_why"][verdict] = row["none_why"].get(verdict, 0) + 1
            sys.stderr.write("measure-check-underfire: [%d/%d] %s %s: %s (%.0fs so far)\n"
                             % (ci + 1, len(commits), sha[:12], pl["kind"][:60], verdict, time.time() - t0))
            sys.stderr.flush()
finally:
    shutil.rmtree(work, ignore_errors=True)
    shutil.rmtree(tars, ignore_errors=True)

def pct(a, b):
    return "%d/%d = %.1f%%" % (a, b, 100.0 * a / b) if b else "n/a"

print("    window: %d commit(s), newest %s, oldest %s" % (len(commits), commits[0][:12], commits[-1][:12]))
print("    per kind   (planted = caught + missed: verified, in scope, control passed, verdict returned)")
print("      %-58s %6s %6s %6s %6s  %s" % ("kind", "plant", "caught", "missed", "excl", "recall"))
tot = {b: 0 for b in BUCKETS}
for row in rows:
    for b in BUCKETS:
        tot[b] += row[b]
    planted = row["caught"] + row["missed"]
    excl = sum(row[b] for b in BUCKETS if b not in ("caught", "missed"))
    label = row["plant"]["kind"]
    if row["plant"].get("history") == "clone":
        label += " [clone]"
    print("      %-58s %6d %6d %6d %6d  %s" % (label[:58], planted, row["caught"], row["missed"], excl,
                                            pct(row["caught"], planted)))
planted = tot["caught"] + tot["missed"]
print("    planted (the denominator):         %5d" % planted)
print("      caught                           %5d" % tot["caught"])
print("      missed                           %5d" % tot["missed"])
print("    excluded, and never counted as missed")
print("      out of scope (outside when:)     %5d" % tot["out_of_scope"])
print("      unmeasurable plant (history)     %5d" % tot["unmeasurable"])
print("      plant failed to apply or verify  %5d" % tot["plant_failed"])
print("      control fired (not attributable) %5d" % tot["control_fired"])
print("      control returned no verdict      %5d" % tot["control_none"])
print("      planted run returned no verdict  %5d" % tot["planted_none"])
for row in rows:
    for why, n in sorted(row["failed_why"].items()):
        print("        failed x%d  %s: %s" % (n, row["plant"]["kind"][:40], why[:100]))
for row in rows:
    for why, n in sorted(row["none_why"].items()):
        print("        no verdict x%d  %s: %s" % (n, row["plant"]["kind"][:40], why))
    if any(k == "planted refused" for k in row["none_why"]):
        print("        (a blocking check that REFUSES stops the runner, so that defect would not")
        print("        have merged - but a refusal names no defect and is not a catch)")
for row in rows:
    if row["plant"].get("why") and row["out_of_scope"]:
        print("    SCOPE: %s - %s" % (row["plant"]["kind"], row["plant"]["why"]))
if planted == 0:
    print("    recall: n/a - no plant reached a verdict under a passing control.")
    print("    This is NOT a recall of 0% or of 100%; nothing was measured.")
    raise SystemExit(4)
print("    recall over planted defects: %s" % pct(tot["caught"], planted))
for row in rows:
    if row["missed_at"]:
        print("    MISSED  %s  at %s" % (row["plant"]["kind"][:60], " ".join(row["missed_at"][:12])))
print("    A RECALL ON PLANTED DEFECTS SAYS NOTHING ABOUT DEFECTS OF A KIND NOBODY")
print("    PLANTED. It is this check against this catalogue, one guess at what the")
print("    defect looks like. The runner\x27s coverage layer is not replayed.")
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
  mkdir -p "$REPO/tools" "$REPO/src" "$REPO/docs"

  # finds-marker fires when any file it is handed holds PLANTED-DEFECT, and
  # refuses on a file that is not there. It is the check that works.
  cat > "$REPO/tools/finds-marker.sh" <<'FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
for f in "$@"; do
  [ -f "$f" ] || { echo "no such file: $f" >&2; exit 2; }
  if grep -q "PLANTED""-DEFECT" "$f"; then echo "  found it in $f" >&2; exit 1; fi
done
exit 0
FIXTURE
  # blind is the check this whole tool exists for: it reads nothing and passes.
  # Over merged history it scores 0% fire like a good check does.
  cat > "$REPO/tools/blind.sh" <<'FIXTURE'
#!/usr/bin/env bash
exit 0
FIXTURE
  cat > "$REPO/tools/always-refuses.sh" <<'FIXTURE'
#!/usr/bin/env bash
echo "cannot run here" >&2
exit 2
FIXTURE
  cat > "$REPO/tools/fires-always.sh" <<'FIXTURE'
#!/usr/bin/env bash
exit 1
FIXTURE
  # makes a directory under TMPDIR and outlives the timeout, so it is killed
  # with SIGKILL and its own cleanup never runs. Its GRANDCHILD sleeps 30s and
  # carries a token unique to this self-test, so a kill that reached only the
  # direct child leaves a process this self-test can find by name. 30s outlasts
  # the 10s the engine waits after a kill, so the survivor is still there when
  # it is looked for - and the case still ends, because that wait is bounded.
  GC_TOKEN="ufgrandchild-$$-$RANDOM"
  cat > "$REPO/tools/hangs.sh" <<FIXTURE
#!/usr/bin/env bash
set -euo pipefail
mktemp -d "\${TMPDIR:-/tmp}/leak.XXXXXX" > /dev/null
sh -c 'sleep 30; : $GC_TOKEN' &
wait
FIXTURE
  # reads-head fires when the LAST COMMIT carries the marker. It cannot see an
  # uncommitted plant, which is what the worktree-versus-committed pair shows.
  cat > "$REPO/tools/reads-head.sh" <<'FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
diff="$(git show --pretty=format: HEAD)" || { echo "no HEAD" >&2; exit 2; }
case "$diff" in *PLANTED"-DEFECT"*) exit 1 ;; esac
exit 0
FIXTURE
  # finds-token fires on a github-token shape, so the run-time expansion of a
  # fake credential is exercised end to end.
  cat > "$REPO/tools/finds-token.sh" <<'FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
for f in "$@"; do
  if grep -Eq 'gh[p]_[A-Za-z0-9]{36}' "$f"; then exit 1; fi
done
exit 0
FIXTURE
  chmod +x "$REPO"/tools/*.sh
  printf 'one\n' > "$REPO/src/a.txt"
  printf 'docs\n' > "$REPO/docs/readme.md"

  GIT=(git -C "$REPO" -c user.email=selftest@example.invalid -c user.name=selftest -c commit.gpgsign=false)
  git init --quiet "$REPO" > /dev/null
  "${GIT[@]}" add tools src docs > /dev/null
  "${GIT[@]}" commit --quiet -m "first" > /dev/null
  printf 'two\n' > "$REPO/src/b.txt"
  "${GIT[@]}" add src/b.txt > /dev/null
  "${GIT[@]}" commit --quiet -m "second" > /dev/null
  # A TOOL THAT ARRIVES LATE: the two older trees do not carry it.
  cat > "$REPO/tools/late.sh" <<'FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
for f in "$@"; do
  if grep -q "PLANTED""-DEFECT" "$f"; then exit 1; fi
done
exit 0
FIXTURE
  chmod +x "$REPO/tools/late.sh"
  printf 'three\n' > "$REPO/src/c.txt"
  "${GIT[@]}" add tools/late.sh src/c.txt > /dev/null
  "${GIT[@]}" commit --quiet -m "third" > /dev/null

  cat > "$WORK/checks.yaml" <<'CFG'
version: 1
defaults:
  mode: batch
  severity: block
  timeout_seconds: 30
checks:
  - id: catches-marker
    why: fires on the marker
    when: {paths: ["src/**"]}
    requires: [./tools/finds-marker.sh]
    command: [./tools/finds-marker.sh, "{files}"]
    exit_codes: {pass: [0], fail: [1], refused: [2]}
  - id: blind
    why: reads nothing
    when: {paths: ["src/**"]}
    requires: [./tools/blind.sh]
    command: [./tools/blind.sh, "{files}"]
    exit_codes: {pass: [0], fail: [1], refused: [2]}
  - id: refuses
    why: refuses everything
    when: {paths: ["src/**"]}
    requires: [./tools/always-refuses.sh]
    command: [./tools/always-refuses.sh]
    exit_codes: {pass: [0], fail: [1], refused: [2]}
  - id: fires-always
    why: fires on anything
    when: {paths: ["src/**"]}
    requires: [./tools/fires-always.sh]
    command: [./tools/fires-always.sh]
    exit_codes: {pass: [0], fail: [1], refused: [2]}
  - id: hangs
    why: outlives its timeout
    when: {paths: ["src/**"]}
    requires: [./tools/hangs.sh]
    command: [./tools/hangs.sh]
    timeout_seconds: 1
    exit_codes: {pass: [0], fail: [1], refused: [2]}
  - id: reads-head
    why: reads the last commit
    when: {always: true}
    requires: [./tools/reads-head.sh, git]
    command: [./tools/reads-head.sh]
    exit_codes: {pass: [0], fail: [1], refused: [2]}
  - id: reads-head-empty-only
    why: declares git, and its only plant gives it no history
    when: {always: true}
    requires: [./tools/reads-head.sh, git]
    command: [./tools/reads-head.sh]
    exit_codes: {pass: [0], fail: [1], refused: [2]}
  - id: per-file
    why: per_file, fires on the marker
    mode: per_file
    when: {paths: ["src/**"]}
    requires: [./tools/finds-marker.sh]
    command: [./tools/finds-marker.sh, "{file}"]
    exit_codes: {pass: [0], fail: [1], refused: [2]}
  - id: finds-token
    why: fires on a token shape
    when: {always: true}
    requires: [./tools/finds-token.sh]
    command: [./tools/finds-token.sh, "{files}"]
    exit_codes: {pass: [0], fail: [1], refused: [2]}
  - id: late
    why: its tool exists at the newest commit only
    when: {paths: ["src/**"]}
    requires: [./tools/late.sh]
    command: [./tools/late.sh, "{files}"]
    exit_codes: {pass: [0], fail: [1], refused: [2]}
  - id: switched-off
    enabled: false
    why: a shut guard
    when: {always: true}
    requires: [./tools/blind.sh]
    command: [./tools/blind.sh]
    exit_codes: {pass: [0], fail: [1]}
  - id: nobody-looked
    why: no plant and no reason
    when: {always: true}
    requires: [./tools/blind.sh]
    command: [./tools/blind.sh]
    exit_codes: {pass: [0], fail: [1]}
  - id: reason-given
    why: no plant, with a reason
    when: {always: true}
    requires: [./tools/blind.sh]
    command: [./tools/blind.sh]
    exit_codes: {pass: [0], fail: [1]}
  - id: tool-not-here
    why: its tool is not installed
    when: {always: true}
    requires: [a-tool-that-is-not-installed-anywhere]
    command: [a-tool-that-is-not-installed-anywhere]
    exit_codes: {pass: [0], fail: [1]}
CFG
  printf 'this is not yaml at all: [\n' > "$WORK/broken.yaml"

  cat > "$WORK/plants.json" <<'PLANTS'
{"plants": [
 {"check": "catches-marker", "kind": "marker in a new file",
  "control": [{"op": "create", "path": "src/planted.txt", "text": "benign\n"}],
  "defect":  [{"op": "create", "path": "src/planted.txt", "text": "PLANTED-DEFECT\n"}]},
 {"check": "catches-marker", "kind": "anchor absent at every commit",
  "control": [{"op": "replace", "path": "src/a.txt", "old": "NO-SUCH-ANCHOR", "new": "benign"}],
  "defect":  [{"op": "replace", "path": "src/a.txt", "old": "NO-SUCH-ANCHOR", "new": "PLANTED-DEFECT"}]},
 {"check": "catches-marker", "kind": "exec bit that was never set",
  "control": [{"op": "chmod_on", "path": "src/a.txt"}],
  "defect":  [{"op": "chmod_off", "path": "src/a.txt"}]},
 {"check": "catches-marker", "kind": "marker outside when",
  "control": [{"op": "create", "path": "docs/planted.md", "text": "benign\n"}],
  "defect":  [{"op": "create", "path": "docs/planted.md", "text": "PLANTED-DEFECT\n"}]},
 {"check": "blind", "kind": "marker in a new file",
  "control": [{"op": "create", "path": "src/planted.txt", "text": "benign\n"}],
  "defect":  [{"op": "create", "path": "src/planted.txt", "text": "PLANTED-DEFECT\n"}]},
 {"check": "refuses", "kind": "marker in a new file",
  "control": [{"op": "create", "path": "src/planted.txt", "text": "benign\n"}],
  "defect":  [{"op": "create", "path": "src/planted.txt", "text": "PLANTED-DEFECT\n"}]},
 {"check": "fires-always", "kind": "marker in a new file",
  "control": [{"op": "create", "path": "src/planted.txt", "text": "benign\n"}],
  "defect":  [{"op": "create", "path": "src/planted.txt", "text": "PLANTED-DEFECT\n"}]},
 {"check": "hangs", "kind": "marker in a new file",
  "control": [{"op": "create", "path": "src/planted.txt", "text": "benign\n"}],
  "defect":  [{"op": "create", "path": "src/planted.txt", "text": "PLANTED-DEFECT\n"}]},
 {"check": "reads-head", "kind": "marker committed", "history": "clone", "stage": "committed",
  "control": [{"op": "create", "path": "src/planted.txt", "text": "benign\n"}, {"op": "message", "text": "names src/planted.txt"}],
  "defect":  [{"op": "create", "path": "src/planted.txt", "text": "PLANTED-DEFECT\n"}]},
 {"check": "reads-head", "kind": "marker left in the work tree", "history": "clone", "stage": "worktree",
  "control": [{"op": "create", "path": "src/planted.txt", "text": "benign\n"}],
  "defect":  [{"op": "create", "path": "src/planted.txt", "text": "PLANTED-DEFECT\n"}]},
 {"check": "reads-head-empty-only", "kind": "marker with no history",
  "control": [{"op": "create", "path": "src/planted.txt", "text": "benign\n"}],
  "defect":  [{"op": "create", "path": "src/planted.txt", "text": "PLANTED-DEFECT\n"}]},
 {"check": "per-file", "kind": "marker in the last of two files",
  "control": [{"op": "create", "path": "src/p1.txt", "text": "benign\n"}, {"op": "create", "path": "src/p2.txt", "text": "benign\n"}],
  "defect":  [{"op": "create", "path": "src/p1.txt", "text": "benign\n"}, {"op": "create", "path": "src/p2.txt", "text": "PLANTED-DEFECT\n"}]},
 {"check": "finds-token", "kind": "a fake github token",
  "control": [{"op": "create", "path": "notes.md", "text": "token: from the vault\n"}],
  "defect":  [{"op": "create", "path": "notes.md", "text": "token: @@GHP@@\n"}]},
 {"check": "late", "kind": "marker in a new file",
  "control": [{"op": "create", "path": "src/planted.txt", "text": "benign\n"}],
  "defect":  [{"op": "create", "path": "src/planted.txt", "text": "PLANTED-DEFECT\n"}]}
],
 "unplantable": {"reason-given": "a reason written down for the fixture"}}
PLANTS
  printf '{"plants": [' > "$WORK/malformed.json"
  printf '{"plants": [{"check": "blind", "kind": "k", "control": [{"op": "teleport"}], "defect": []}]}\n' > "$WORK/badop.json"

  CASES=0; UPHELD=0; REPORT=""; CODES=""
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
  C=(--root "$REPO" --config "$WORK/checks.yaml" --plants "$WORK/plants.json" --commits 3)

  # --- 0: measured ---------------------------------------------------------
  drive catches 0 "a check that sees the defect is measured at full recall" "${C[@]}" --check catches-marker
  drive blind 0 "a check that fires at nothing is MEASURED, at 0% recall - the case this tool exists for" "${C[@]}" --check blind
  drive clone-stages 0 "one defect, committed and uncommitted, measured as two kinds" "${C[@]}" --check reads-head
  drive per-file 0 "a per_file check is handed every planted file" "${C[@]}" --check per-file
  drive token 0 "a fake credential is generated at run time and planted" "${C[@]}" --check finds-token
  drive late 0 "a tool absent from older trees is excluded, never missed" "${C[@]}" --check late
  drive listed 0 "--list names every check's plants, or why there are none" "${C[@]}" --list

  # --- 2: could not run ----------------------------------------------------
  drive unknown-check 2 "a check id the config does not declare" "${C[@]}" --check no-such-check
  drive no-config 2 "the named config is not there" --root "$REPO" --config "$WORK/none.yaml" --plants "$WORK/plants.json" --check blind
  drive unparseable 2 "a config that is not YAML" --root "$REPO" --config "$WORK/broken.yaml" --plants "$WORK/plants.json" --check blind
  drive bad-usage 2 "an option this script does not take" "${C[@]}" --frobnicate
  drive both-modes 2 "--list and --check ask different questions" "${C[@]}" --list --check blind
  drive not-a-repo 2 "a root that is not a git work tree" --root "$WORK" --config "$WORK/checks.yaml" --plants "$WORK/plants.json" --check blind
  drive malformed-plants 2 "a plants file that is not JSON" --root "$REPO" --config "$WORK/checks.yaml" --plants "$WORK/malformed.json" --check blind
  drive bad-op 2 "a plant with an op this tool does not know" --root "$REPO" --config "$WORK/checks.yaml" --plants "$WORK/badop.json" --check blind
  mkdir -p "$REPO/scratch-inside"
  NAME="tmp-inside-repo"; GOT=0
  TMPDIR="$REPO/scratch-inside" bash "$0" "${C[@]}" --check blind > "$WORK/$NAME.out" 2> "$WORK/$NAME.err" || GOT=$?
  CASES=$((CASES + 1))
  if [ "$GOT" = "2" ]; then UPHELD=$((UPHELD + 1)); V="held"; else V="NOT HELD"; fi
  CODES="$CODES$GOT
"
  REPORT="$REPORT      $NAME  expected 2  got $GOT  $V  a temporary directory inside the repository is refused, so no plant can land in the work tree
"
  rmdir "$REPO/scratch-inside"

  # --- 3: cannot be measured -----------------------------------------------
  drive disabled 3 "a disabled check - recall n/a" "${C[@]}" --check switched-off
  drive nobody-looked 3 "no plant and no reason - n/a, and it says nobody looked" "${C[@]}" --check nobody-looked
  drive reason-given 3 "no plant, the recorded reason printed" "${C[@]}" --check reason-given
  drive tool-absent 3 "the tool is not on this machine - recall ?" "${C[@]}" --check tool-not-here
  drive empty-history 3 "a check declaring git with only an empty-history plant is not replayed" "${C[@]}" --check reads-head-empty-only

  # --- 4: measured nothing -------------------------------------------------
  drive refuses 4 "every control refused, so no plant reached a verdict" "${C[@]}" --check refuses
  drive control-fires 4 "every control fired, so no catch is attributable" "${C[@]}" --check fires-always
  mkdir -p "$WORK/outer-tmp"
  NAME="hangs"; GOT=0
  TMPDIR="$WORK/outer-tmp" bash "$0" "${C[@]}" --check hangs > "$WORK/$NAME.out" 2> "$WORK/$NAME.err" || GOT=$?
  CASES=$((CASES + 1))
  LEFT="$(find "$WORK/outer-tmp" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
  ALIVE="$(pgrep -f "$GC_TOKEN" | wc -l | tr -d ' ')" || ALIVE=0
  pkill -f "$GC_TOKEN" || :
  if [ "$GOT" = "4" ] && [ "$LEFT" = "0" ] && [ "$ALIVE" = "0" ]; then UPHELD=$((UPHELD + 1)); V="held"; else V="NOT HELD"; fi
  CODES="$CODES$GOT
"
  REPORT="$REPORT      $NAME  expected 4, 0 left, 0 alive  got $GOT, $LEFT left, $ALIVE alive  $V  every control timed out at the declared 1s; what the killed child made under TMPDIR is not left in the caller's, and the kill reached its grandchild
"

  WORDED=0; WORDED_OK=0
  assert_says() {
    WORDED=$((WORDED + 1))
    if grep -qF -- "$2" "$WORK/$1.out"; then WORDED_OK=$((WORDED_OK + 1)); W="held"; else W="NOT HELD"; fi
    REPORT="$REPORT      wording:$1  $W  $3
"
  }
  assert_says catches 'recall over planted defects: 3/3 = 100.0%' \
    "three verified plants, three catches; the failed and out-of-scope plants are not under the line"
  assert_says catches 'missed                               0' \
    "a plant that failed to apply, and one outside when:, are never counted as missed"
  assert_says catches 'plant failed to apply or verify      6' \
    "an absent anchor (3) and a bit that was never set (3) are counted as failed plants, on their own line"
  assert_says catches 'out of scope (outside when:)         3' \
    "a defect outside the check's paths is counted as out of scope"
  assert_says blind 'recall over planted defects: 0/3 = 0.0%' \
    "the check that fires at nothing is caught by this tool - its over-fire rate would read 0% and look perfect"
  assert_says clone-stages 'recall over planted defects: 3/6 = 50.0%' \
    "the committed plant is caught three times and the uncommitted one missed three times"
  assert_says per-file 'recall over planted defects: 3/3 = 100.0%' \
    "the marker is in the LAST planted file, so only handing it every file finds it"
  assert_says token 'recall over planted defects: 3/3 = 100.0%' \
    "the token is expanded at run time into the github shape and the fixture tool finds it"
  assert_says late 'recall over planted defects: 1/1 = 100.0%' \
    "two trees without the tool are excluded, one tree with it catches"
  assert_says late 'control returned no verdict          2' \
    "the tool-absent trees land in the no-verdict bucket"
  assert_says refuses 'recall: n/a' "no verdict under a passing control is n/a, never 0%"
  assert_says control-fires 'control fired (not attributable)     3' \
    "a control that fires is excluded rather than scored as a catch"
  assert_says nobody-looked 'nobody has looked' "a check nobody planted for is named as such"
  assert_says reason-given 'a reason written down for the fixture' "the recorded reason is printed"
  assert_says listed 'NO PLANT AND NO REASON' "--list names the checks nobody has looked at"

  # No plant ever reaches the repository's own work tree.
  CASES=$((CASES + 1))
  if [ -z "$(git -C "$REPO" status --porcelain)" ] && ! grep -rEq 'gh[p]_[A-Za-z0-9]{36}' "$REPO/src" "$REPO/docs" "$REPO/tools"; then
    UPHELD=$((UPHELD + 1)); V="held"
  else
    V="NOT HELD"
  fi
  REPORT="$REPORT      repo-untouched  expected a clean work tree  $V  after every case above, the fixture repository has no change and no token in it
"

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"
  if [ "$CASES" = "$UPHELD" ] && [ "$WORDED" = "$WORDED_OK" ]; then SELF_VERDICT="held"; else SELF_VERDICT="NOT HELD"; fi
  printf '    R39.s  %-38s examined %3d  upheld %3d  %s: %s\n' \
    "selftest-cases-produce-declared-exit" "$CASES" "$UPHELD" "$SELF_VERDICT" \
    "each case exits the code it declares, and fifteen rows also assert the sentence"
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 2 3 4; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 2 3 4\n' "$REACHED"
  printf '    NOT ASSERTED: the default catalogue. Every case above runs the fixture catalogue; whether a plant for a real check is the defect that check exists for is a judgement made in the catalogue, and its figures come from real runs. The undeclared-exit bucket is not driven.\n'
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
[ -n "$MODE" ] || die_unmeasured "give --list or --check ID. Measuring nothing would print a recall nobody took."
command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed, so checks.yaml could not be read"
command -v git >/dev/null 2>&1 || die_unmeasured "git is not installed, so no tree could be obtained"
[ -z "$COMMITS" ] || [ -z "$SINCE" ] || die_unmeasured "--commits and --since name the range two ways; give one"
[ -n "$COMMITS" ] || COMMITS="10"

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" || die_unmeasured "no git work tree here and --root was not given"
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

[ -n "$CONFIG_REL" ] || CONFIG_REL=".claude/productizer/checks.yaml"
case "$CONFIG_REL" in
  /*) CONFIG="$CONFIG_REL" ;;
  *)  CONFIG="$ROOT/$CONFIG_REL" ;;
esac
[ -r "$CONFIG" ] || die_unmeasured "no readable config at $CONFIG. Nothing was measured, which is not a recall of zero."

# mktemp IS GIVEN AN EXPLICIT TEMPLATE UNDER $TMPDIR. Measured on this
# machine: macOS /usr/bin/mktemp -d with no template IGNORES TMPDIR and writes
# to the per-user temp directory whatever TMPDIR says. So a bare `mktemp -d`
# cannot be redirected, and neither the scratch-directory guard nor the
# containment of a killed child could be tested through it.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/measure-check-underfire.XXXXXX")" \
  || die_unmeasured "could not make a temporary directory"
trap 'rm -rf "$TMP"' EXIT
trap 'rm -rf "$TMP"; exit 130' INT
trap 'rm -rf "$TMP"; exit 143' TERM

set +e
python3 -c "$ENGINE" "$MODE" "$CONFIG" "$ROOT" "$CHECK_ID" "$COMMITS" "$SINCE" "$PER_RUN_TIMEOUT" "$TMP" "$PLANTS"
RC=$?
set -e
exit "$RC"
