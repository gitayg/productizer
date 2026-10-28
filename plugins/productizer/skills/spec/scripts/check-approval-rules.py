#!/usr/bin/env python3
"""check-approval-rules.py [ROOT] [--selftest] [--version] [--help]

Does the repository's CODEOWNERS give every file under `.claude/productizer/`
and `.github/workflows/` a human owner? ROOT defaults to the git top level of
the working directory.

WHY THIS EXISTS (B172). A change an agent authored reaches the files that judge
it - the spec, the checks, the workflows - through a pull request, and branch
protection's "Require review from Code Owners" makes a person approve such a
change only for a path CODEOWNERS gives an owner. An entry with no owner, or a
later pattern that takes a file away from its owner, leaves those files
approvable by anyone with write access. The file is in the tree, so its effect
is checked on the tree.

WHAT IT READS, as GitHub does (GitHub's documentation, "About code owners"): the first
of `.github/CODEOWNERS`, `CODEOWNERS` and `docs/CODEOWNERS` that exists; "the
last matching pattern takes the most precedence"; a pattern with no owners
leaves its files without one; paths are case sensitive; `!` and `[ ]` do not
work, so a line using either is reported. A pattern is matched as gitignore
does: one holding a `/` before its end is anchored to the root, one without
matches at any depth, a trailing `/` matches what is under a directory, `*` and
`?` stay within one path component and `**` crosses them. A pattern naming a
directory owns what is under it, but one whose last component holds a `*` owns
only what it names: GitHub's own example reads "`docs/*` ... will match files
like `docs/getting-started.md` but not further nested files".

WHAT IT ASSERTS, each a separate finding:
  codeowners     a CODEOWNERS file exists in one of the three places, and no
                 line uses `!` or `[`
  human-owner    every probed path's last matching pattern names at least one
                 owner that is not a bot: an `@user`, an `@org/team` or an
                 email, where an owner ending in `[bot]` is a bot
The probed paths are every tracked file under the two directories, and one
file name in each that no repository holds, standing for a file a change adds.

WHAT IT DOES NOT. It reads a file. Whether branch protection requires code
owner review, dismisses stale approvals when a commit is pushed, requires the
most recent push to be approved by someone else, or lets GitHub Actions approve
pull requests are repository settings it cannot see, and every run says so. A
plain user name is counted human whether a person or a machine holds it, and a
team is counted human whatever its members are.

Exit codes:
  0  both assertions held
  1  at least one finding, each printed with its assertion
  2  could not run: bad usage, ROOT not a git work tree, or CODEOWNERS unreadable
--selftest runs its cases in temporary repositories, and exits 0 when every
case held, 1 otherwise.
"""
import os
import re
import subprocess
import sys
import tempfile

VERSION = "check-approval-rules 1.0"
ASSERTIONS = ("codeowners", "human-owner")
LOCATIONS = (".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS")
PROTECTED = (".claude/productizer/", ".github/workflows/")
PROBE = "approval-rules-probe-added-file"
OWNER_RE = re.compile(r"^(@[A-Za-z0-9][A-Za-z0-9-]*(?:\[bot\])?(?:/[A-Za-z0-9._-]+)?|[^@\s]+@[^@\s]+\.[^@\s]+)$")
NOT_MEASURED = ("NOT MEASURED: branch protection's code owner review, stale-approval dismissal and most-recent-push "
                "approval, and whether GitHub Actions may approve pull requests - repository settings, not files")
HERE = os.path.dirname(os.path.abspath(__file__))
USAGE = "usage: check-approval-rules.py [ROOT] [--selftest] [--version] [--help]\n"


def to_regex(pat):
    anchored = pat.startswith("/") or "/" in pat.rstrip("/")
    dir_only = pat.endswith("/")
    body = pat.strip("/")
    out, i = [], 0
    while i < len(body):
        if body.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif body.startswith("**", i):
            out.append(".*")
            i += 2
        elif body[i] == "*":
            out.append("[^/]*")
            i += 1
        elif body[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(body[i]))
            i += 1
    head = "^" if anchored else "^(?:.*/)?"
    last = body.rsplit("/", 1)[-1]
    tail = "/.+$" if dir_only else "$" if "*" in last and last != "**" else "(?:/.+)?$"
    return re.compile(head + "".join(out) + tail)


def parse(text):
    """[(line number, pattern, owners)] and the lines GitHub would not read as written."""
    rules, bad = [], []
    for n, line in enumerate(text.split("\n"), 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        parts = s.split()
        if "!" in parts[0] or "[" in parts[0]:
            bad.append("line %d: %s uses `!` or `[ ]`, which CODEOWNERS does not support" % (n, parts[0]))
            continue
        rules.append((n, parts[0], parts[1:], to_regex(parts[0])))
    return rules, bad


def human(owner):
    return bool(OWNER_RE.match(owner)) and not owner.endswith("[bot]")


def git(root, *args):
    return subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True, check=False)


def check(root):
    """Return (exit code, lines to print)."""
    top = git(root, "rev-parse", "--show-toplevel")
    if top.returncode != 0:
        return 2, ["check-approval-rules: %s is not a git work tree" % root]
    root = top.stdout.strip()
    found = next((loc for loc in LOCATIONS if os.path.isfile(os.path.join(root, loc))), None)
    findings = {a: [] for a in ASSERTIONS}
    out = ["check-approval-rules: root %s" % root]
    rules = []
    if found is None:
        findings["codeowners"].append("no CODEOWNERS in %s" % ", ".join(LOCATIONS))
    else:
        try:
            with open(os.path.join(root, found), "rb") as fh:
                text = fh.read().decode("utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            return 2, out + ["check-approval-rules: cannot read %s: %s" % (found, exc)]
        rules, bad = parse(text)
        findings["codeowners"].extend("%s %s" % (found, b) for b in bad)
        out.append("read %s: %d rule(s)" % (found, len(rules)))
    listed = git(root, "ls-files", "-z", "--", *PROTECTED)
    if listed.returncode != 0:
        return 2, out + ["check-approval-rules: git ls-files failed: %s" % listed.stderr.strip()]
    probes = sorted(set(p for p in listed.stdout.split("\0") if p) | set(d + PROBE for d in PROTECTED))
    if found is None:
        findings["human-owner"].append("none of the %d probed path(s) has an owner, since there is no CODEOWNERS" % len(probes))
        probes_judged = []
    else:
        probes_judged = probes
    for path in probes_judged:
        last = None
        for rule in rules:
            if rule[3].match(path):
                last = rule
        if last is None:
            findings["human-owner"].append("%s matches no pattern, so it has no owner" % path)
        elif not any(human(o) for o in last[2]):
            why = "names no owner" if not last[2] else "names no human owner (%s)" % " ".join(last[2])
            findings["human-owner"].append("%s: its last matching pattern, %s on line %d, %s" % (path, last[1], last[0], why))
    out.append("probed %d path(s)" % len(probes))
    held = 0
    for a in ASSERTIONS:
        if findings[a]:
            out.extend("FINDING %s: %s" % (a, f) for f in findings[a])
        else:
            held += 1
    out.append(NOT_MEASURED)
    out.append("%d of %d assertions held" % (held, len(ASSERTIONS)))
    return (0 if held == len(ASSERTIONS) else 1), out


def documented_codes():
    block = __doc__.split("Exit codes:", 1)[1]
    return [int(m.group(1)) for m in re.finditer(r"^  (\d) ", block, re.M)]


def repo(tmp, name, codeowners, where=".github/CODEOWNERS", files=(".claude/productizer/spec.md", ".github/workflows/ci.yml", "src/a.py")):
    root = os.path.join(tmp, name)
    os.makedirs(root)
    subprocess.run(["git", "init", "-q", root], check=True)
    for f in files:
        os.makedirs(os.path.dirname(os.path.join(root, f)) or root, exist_ok=True)
        with open(os.path.join(root, f), "w", encoding="utf-8") as fh:
            fh.write("x\n")
    if codeowners is not None:
        os.makedirs(os.path.dirname(os.path.join(root, where)) or root, exist_ok=True)
        with open(os.path.join(root, where), "w", encoding="utf-8") as fh:
            fh.write(codeowners)
    subprocess.run(["git", "-C", root, "add", "-A"], check=True)
    return root


GOOD = "# owners\n* @dev-team\n/.claude/productizer/ @maint\n/.github/workflows/ @acme/release\n"


def selftest():
    held = total = 0
    codes = set()
    with tempfile.TemporaryDirectory() as tmp:
        cases = [
            ("good", repo(tmp, "good", GOOD), 0, "2 of 2 assertions held"),
            ("good-root-file", repo(tmp, "root", GOOD, where="CODEOWNERS"), 0, "read CODEOWNERS:"),
            ("good-docs-file", repo(tmp, "docs", GOOD, where="docs/CODEOWNERS"), 0, "read docs/CODEOWNERS:"),
            ("no-codeowners", repo(tmp, "none", None), 1, "FINDING codeowners: no CODEOWNERS"),
            ("unowned-later-pattern", repo(tmp, "unowned", GOOD + ".github/workflows/\n"), 1,
             "FINDING human-owner: .github/workflows/ci.yml: its last matching pattern, .github/workflows/ on line 5, names no owner"),
            ("bot-owner", repo(tmp, "bot", GOOD.replace("@maint", "@release-helper[bot]")), 1,
             "names no human owner (@release-helper[bot])"),
            ("bot-and-human", repo(tmp, "both", GOOD.replace("@maint", "@release-helper[bot] maint@example.com")), 0,
             "2 of 2 assertions held"),
            ("later-glob-takes-file", repo(tmp, "glob", GOOD + "*.yml @ci-helper[bot]\n"), 1, "ci.yml: its last matching pattern, *.yml"),
            ("only-one-dir-owned", repo(tmp, "onedir", "/.claude/productizer/ @maint\n"), 1,
             ".github/workflows/ci.yml matches no pattern"),
            ("added-file-probe", repo(tmp, "probe", "/.claude/productizer/spec.md @maint\n/.github/ @maint\n"), 1,
             ".claude/productizer/%s matches no pattern" % PROBE),
            ("single-star-stays-in-dir", repo(tmp, "star", "/.claude/* @maint\n/.github/ @maint\n"), 1,
             ".claude/productizer/spec.md matches no pattern"),
            ("double-star-crosses", repo(tmp, "dstar", "/.claude/** @maint\n/.github/ @maint\n"), 0, "2 of 2 assertions held"),
            ("unanchored-name", repo(tmp, "unanch", "productizer/ @maint\nworkflows/ @maint\n"), 0, "2 of 2 assertions held"),
            ("case-sensitive", repo(tmp, "case", "/.Claude/productizer/ @maint\n/.github/workflows/ @maint\n"), 1,
             ".claude/productizer/spec.md matches no pattern"),
            ("negation-refused", repo(tmp, "neg", GOOD + "!/.github/workflows/ci.yml\n"), 1, "uses `!` or `[ ]`"),
            ("not-an-owner", repo(tmp, "notowner", GOOD.replace("@maint", "maint")), 1, "names no human owner (maint)"),
            ("not-a-repo", os.path.join(tmp, "plain"), 2, "is not a git work tree"),
        ]
        os.makedirs(os.path.join(tmp, "plain"))
        first = repo(tmp, "first", "* @nobody[bot]\n", where="CODEOWNERS")
        with open(os.path.join(first, ".github", "CODEOWNERS"), "w", encoding="utf-8") as fh:
            fh.write(GOOD)
        cases.append(("github-dir-wins", first, 0, "read .github/CODEOWNERS:"))
        with open(os.path.join(os.path.dirname(HERE), "templates", "CODEOWNERS"), encoding="utf-8") as fh:
            cases.append(("shipped-template-holds", repo(tmp, "tpl", fh.read()), 0, "2 of 2 assertions held"))
        unreadable = repo(tmp, "unread", None)
        with open(os.path.join(unreadable, ".github", "CODEOWNERS"), "wb") as fh:
            fh.write(b"\xff\xfe* @maint\n")
        cases.append(("unreadable", unreadable, 2, "cannot read .github/CODEOWNERS"))
        for name, root, want_rc, want_text in cases:
            total += 1
            rc, out = check(root)
            codes.add(rc)
            text = "\n".join(out)
            if rc == want_rc and want_text in text:
                held += 1
                print("  ok   %s (exit %d)" % (name, rc))
            else:
                print("  FAIL %s: exit %d, wanted %d with %r\n%s" % (name, rc, want_rc, want_text, text))
        total += 1
        proc = subprocess.run([sys.executable, os.path.abspath(__file__), "a", "b"], capture_output=True, text=True, check=False)
        codes.add(proc.returncode)
        if proc.returncode == 2 and "usage" in proc.stderr:
            held += 1
            print("  ok   bad-usage (exit 2)")
        else:
            print("  FAIL bad-usage: exit %d, stderr %r" % (proc.returncode, proc.stderr))
    documented = documented_codes()
    print("    exit codes reached: %s   documented: %s" % (" ".join(str(c) for c in sorted(codes)), " ".join(str(c) for c in documented)))
    print("    NOT ASSERTED: the repository settings named in the header, or that a user name belongs to a person")
    print("check-approval-rules selftest: %d of %d cases held" % (held, total))
    return 0 if held == total and codes == set(documented) else 1


def main(argv):
    args = argv[1:]
    if args == ["--version"]:
        print(VERSION)
        return 0
    if args in (["--help"], ["-h"]):
        print(__doc__)
        return 0
    if args in (["--selftest"], ["--self-test"]):
        return selftest()
    if len(args) > 1 or (args and args[0].startswith("-")):
        sys.stderr.write(USAGE)
        return 2
    rc, out = check(args[0] if args else os.getcwd())
    stream = sys.stderr if rc == 2 else sys.stdout
    for line in out:
        stream.write(line + "\n")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
