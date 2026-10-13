#!/usr/bin/env python3
"""argv-classify.py [--tokens ARG...] [--data-only ARG...] [--selftest] [--version] [--help]

THE STRICT READING OF A CHECK'S ARGV that run-checks.sh and stage-advance.sh
share (maintainer ruling 2026-10-13). It recognises no interpreter. Any
program counts the same; what is read is which values a literal argument can
name, and which programs may be handed the files under check. run-checks.sh
refuses a command that names a path in the work tree without the opt-in to
repository-declared check tools (R102, R22); stage-advance.sh protects every
such path from an unattended change (R126). Each script loads this file by
its path - never by import, so no bytecode cache beside it is ever read - and
decides for itself whether a value names a path in ITS tree.

WHAT A LITERAL ARGUMENT CAN NAME. values(token) returns (value, shaped):
  the whole token        shaped unless it begins with `-`
  --opt=VALUE            the value after the first `=` (shaped), and after
                         each later `=` (judged by existence only)
  -XVALUE                the value glued to a short option (shaped), and
                         every later suffix (`-nfprog.sed`), judged by
                         existence only, since a cluster of short options can
                         hide where the value starts
"shaped" means the caller may count the value as a path by its shape alone
(path_shaped: no whitespace, and a slash or a script extension), the way
stage-advance.sh must for a path a change could add. A value that is not
shaped counts only when the tree holds it.

normalise(value, root) is the shared path test: the value as a path relative
to the root, after `./`, `//`, `..` and a trailing `/` are folded, or None
when it is the root itself, outside it, a placeholder or a URL.

THE DATA-ONLY LIST. A placeholder (`{file}`, `{files}`) is the change under
check choosing an argument. Without the opt-in it may be handed only to a
program on DATA_ONLY: a tool that reads its file operands as data and runs
none of them. The list lives here, in the plugin, and never in the examined
repository's config. An entry names, beside its reason, the options that make
the tool run code or load what it runs; any of those in the argv, spelled
whole, as `--opt=VALUE` or as an abbreviation a parser would accept, voids the
entry for that argv. The program must be named bare: a path in argv[0] is not
the tool the entry describes.

is_interpreter() serves only run-checks.sh's R18 refusal of an interpreter
handed an inline program (`python3 -c`). It decides nothing under R102 or R126.

WHAT IT DOES NOT SEE. A file a tool runs that no argument names: a test
runner discovering tests, a config the tool finds by itself, a git alias.

--tokens prints one line per value, `INDEX<TAB>shaped|exists<TAB>VALUE`.
--data-only prints `data-only` or the reason the argv is not, and exits 0.

Exit codes:
  0  printed what was asked
  1  the self-test found a case that did not hold
  2  bad usage
--selftest pins the tables below, case by case.
"""

import os
import posixpath
import re
import subprocess
import sys

VERSION = "argv-classify 2.0"

# The placeholders the runner expands into repository paths. `{base}` is not
# one: it becomes a commit id, and run-checks.sh judges the id it becomes.
PLACEHOLDERS = ("{file}", "{files}")

# THE DATA-ONLY LIST. Started from the tools templates/checks.yaml runs with a
# placeholder (measured 2026-10-13: shellcheck in shell-lint, semgrep in sast,
# sast-auth and secure-coding-controls; gitleaks takes `.`, not a
# placeholder, and actionlint is not in the template), plus grep, which the
# runner's own self-test drives. Each entry: the options that make it run
# code, and why it is otherwise data-only. The option lists were read off
# the installed tools' --help on 2026-10-13 (shellcheck 0.11.0, semgrep
# 1.171.0, BSD grep 2.6.0, GNU grep 3.x); an option a later release adds is
# not on them.
DATA_ONLY = {
    "shellcheck": ((), "parses each file operand as shell source and never runs it; "
                       "--rcfile, -P and -x only choose more files to parse"),
    "semgrep": (("--allow-local-builds", "--allow-untrusted-validators"),
                "matches rules against each target as text; a rules file is YAML with no "
                "code. --allow-local-builds builds (runs) the scanned project and "
                "--allow-untrusted-validators runs validators from rules of any origin, "
                "so either voids the entry"),
    "grep": (("--filter", "--pager", "--view", "--config", "---", "--save-config",
              "--format-open", "--pre", "--pre-glob"),
             "reads each operand as text and matches patterns in it; GNU and BSD grep have "
             "no option that runs a command. The voiding options are ugrep's and ripgrep's, "
             "for a `grep` on PATH that is one of them: --filter, --pager, --view and --pre "
             "run a command, --config, --- and --save-config load or write a config file"),
}

# Kept for run-checks.sh's R18 inline-program refusal only.
INTERPRETER_STEMS = {"python", "pypy", "jython", "perl", "ruby", "jruby", "node", "nodejs",
                     "deno", "bun", "php", "lua", "luajit", "tclsh", "wish", "expect", "rscript",
                     "osascript", "swift", "ghc", "runghc", "runhaskell", "groovy", "jshell",
                     "scala", "java", "kotlin", "julia", "elixir", "escript", "erl", "raku",
                     "pwsh", "powershell", "ts-node", "tsx"}

# What a program reads as code of its own, by extension: a path that carries
# one is path-shaped even with no slash in it.
SCRIPT_EXT = re.compile(r"\.(py|pyw|sh|bash|zsh|pl|pm|rb|js|mjs|cjs|ts|mts|cts|lua|php|r|scpt|tcl|"
                        r"exp|ps1|awk|sed|jq|jar|class|groovy|kt|kts|scala|swift|hs|ex|exs|jl|raku)$",
                        re.IGNORECASE)

DOTTED = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$")


def is_interpreter(x):
    b = posixpath.basename(x).lower()
    if b.endswith(".exe"):
        b = b[:-4]
    return re.sub(r"[0-9][0-9._-]*$", "", b) in INTERPRETER_STEMS


def has_placeholder(tok):
    return any(p in tok for p in PLACEHOLDERS)


def values(tok):
    """Every value a literal argument can name, as (value, shaped)."""
    if not tok.startswith("-") or tok == "-":
        return [(tok, True)]
    out = [(tok, False)]
    if tok.startswith("--"):
        parts = tok.split("=")
        for i in range(1, len(parts)):
            out.append(("=".join(parts[i:]), i == 1))
    else:
        for k in range(2, len(tok)):
            out.append((tok[k:], k == 2 or (k == 3 and tok[2] == "=")))
    return [(v, s) for v, s in out if v]


def path_shaped(v):
    """A path by its shape alone: no whitespace, and a slash or a script
    extension. A placeholder or a URL is not one."""
    if not v or "{" in v or "://" in v or re.search(r"\s", v):
        return False
    return "/" in v or bool(SCRIPT_EXT.search(v))


def module_paths(v):
    """A dotted name a program may resolve as a module (`pkg.mod`): its top
    package, the single-file form and the file path. No interpreter is
    recognised; any dotted identifier is read this way."""
    if not DOTTED.match(v):
        return []
    top = v.split(".")[0]
    return list(dict.fromkeys([top, top + ".py", v.replace(".", "/") + ".py"]))


def normalise(value, root, fold=False):
    """The value as a path relative to root, or None: the root itself, a path
    outside it, a placeholder, a URL, or an empty value."""
    if not value or "{" in value or "://" in value or "\x00" in value:
        return None
    if value.startswith("/"):
        lex = posixpath.normpath(value)
        r = posixpath.normpath(root)
        a, b = (lex.lower(), r.lower()) if fold else (lex, r)
        if a.startswith(b.rstrip("/") + "/"):
            return lex[len(r.rstrip("/")) + 1:]
        return None
    rel = posixpath.normpath(value)
    if rel in (".", "..") or rel.startswith("../"):
        return None
    return rel


def denied_option(tok, denied):
    """Is tok one of the denied options, whole, with a value, or abbreviated?"""
    for d in denied:
        if d == "---":
            if tok.startswith("---"):
                return d
            continue
        if not tok.startswith("--") or tok.startswith("---"):
            continue
        name = tok.split("=", 1)[0]
        if len(name) > 2 and (name == d or d.startswith(name)):
            return d
    return None


def data_only(argv):
    """(True, reason) when argv[0] is on DATA_ONLY and no denied option is in
    the argv; (False, why) otherwise."""
    prog = argv[0]
    if prog not in DATA_ONLY:
        return False, "the program is not on the data-only list"
    denied, reason = DATA_ONLY[prog]
    for tok in argv[1:]:
        d = denied_option(tok, denied)
        if d:
            return False, "the program is on the data-only list, but %s in the argv makes it run code" % d
    return True, reason


# THE TABLES the self-test pins.
VALUES = [
    ("tools/a.py", [("tools/a.py", True)]),
    ("-", [("-", True)]),
    ("--require=./a.js", [("--require=./a.js", False), ("./a.js", True)]),
    ("--define=k=tools/x", [("--define=k=tools/x", False), ("k=tools/x", True), ("tools/x", False)]),
    ("-Itools/lib", [("-Itools/lib", False), ("tools/lib", True), ("ools/lib", False),
                     ("ols/lib", False), ("ls/lib", False), ("s/lib", False), ("/lib", False),
                     ("lib", False), ("ib", False), ("b", False)]),
    ("-I=x", [("-I=x", False), ("=x", True), ("x", True)]),
    ("-W", [("-W", False)]),
    ("--json", [("--json", False)]),
]
SHAPED = [("tools/x.sh", True), ("x.py", True), ("ignore", False), ("README", False),
          ("a reason / with a slash", False), ("https://e.invalid/x", False), ("{file}", False),
          ("/usr/bin/x", True), ("p/default", True)]
NORMALISE = [("./x", "x"), ("x//y", "x/y"), ("x/../y", "y"), ("docs/", "docs"), (".", None),
             ("..", None), ("../x", None), ("/r/x", "x"), ("/r", None), ("/rx/y", None),
             ("/R/X", None), ("{file}", None), ("https://e.invalid/x", None)]
MODULES = [("modpkg.main", ["modpkg", "modpkg.py", "modpkg/main.py"]), ("pytest", []),
           ("docs/in.txt", []), ("1.2", [])]
DATA = [(["shellcheck", "--severity=warning", "{file}"], True),
        (["semgrep", "--config", "p/default", "{files}"], True),
        (["semgrep", "--allow-local-builds", "{files}"], False),
        (["semgrep", "--allow-local", "{files}"], False),
        (["semgrep", "--allow-untrusted-validators=true", "{files}"], False),
        (["grep", "-c", "x", "{files}"], True),
        (["grep", "--filter=sh", "x", "{files}"], False),
        (["grep", "---", "x", "{files}"], False),
        (["/usr/bin/grep", "x", "{files}"], False),
        (["python3", "{file}"], False),
        (["cat", "{file}"], False),
        (["{file}"], False)]
STEMS = [("python3.12", True), ("pypy3", True), ("node.exe", True), ("/usr/bin/python3", True),
         ("pythonista", False), ("grep", False), ("shellcheck", False)]


def documented_codes():
    block = __doc__.split("Exit codes:", 1)[1].split("--selftest", 1)[0]
    return sorted(set(re.findall(r"^\s{2}(\d)\s", block, re.M)))


def selftest():
    print("argv-classify self-test\n")
    held = total = 0
    reached = set()

    def case(name, ok, detail=""):
        nonlocal held, total
        total += 1
        if ok:
            held += 1
            print("  ok    %s" % name)
        else:
            print("  FAIL  %s %s" % (name, detail))

    for tok, want in VALUES:
        got = values(tok)
        case("values %s" % tok, got == want, "-> %r" % (got,))
    for v, want in SHAPED:
        case("path_shaped %r is %s" % (v, want), path_shaped(v) is want)
    for v, want in NORMALISE:
        got = normalise(v, "/r")
        case("normalise %r under /r is %r" % (v, want), got == want, "-> %r" % (got,))
    case("normalise '/R/X' under /r folded is 'X'", normalise("/R/X", "/r", fold=True) == "X")
    for v, want in MODULES:
        case("module_paths %r" % v, module_paths(v) == want, "-> %r" % (module_paths(v),))
    for argv, want in DATA:
        got = data_only(argv)[0]
        case("data_only %s is %s" % (" ".join(argv), want), got is want, "-> %r" % (data_only(argv),))
    for name, want in STEMS:
        case("interpreter %s is %s (R18 only)" % (name, want), is_interpreter(name) is want)
    me = os.path.abspath(__file__)
    for name, args, want, text in (
            ("cli-tokens", ["--tokens", "x", "--opt=tools/a.py"], 0, "1\tshaped\ttools/a.py"),
            ("cli-data-only", ["--data-only", "cat", "{file}"], 0, "the program is not on the data-only list"),
            ("cli-version", ["--version"], 0, "argv-classify 2."),
            ("cli-help", ["--help"], 0, "Exit codes:"),
            ("cli-usage", ["--bogus"], 2, "usage: argv-classify.py"),
            ("cli-tokens-empty", ["--tokens"], 2, "usage: argv-classify.py")):
        proc = subprocess.run([sys.executable, "-I", me] + args, capture_output=True, text=True,
                              timeout=60)
        reached.add(str(proc.returncode))
        case("%s exit %d" % (name, proc.returncode),
             proc.returncode == want and text in proc.stdout + proc.stderr,
             "(wanted %d and: %s)" % (want, text))
    # Exit 1, driven: a copy of this file whose table pins one row wrongly.
    # The copy is told it is the inner run, so it does not make a copy itself.
    if os.environ.get("ARGV_CLASSIFY_INNER") == "1":
        return finish(held, total, reached, inner=True)
    import shutil
    import tempfile
    sandbox = tempfile.mkdtemp()
    try:
        bad = os.path.join(sandbox, os.path.basename(me))
        with open(me, encoding="utf-8") as fh:
            src = fh.read()
        wrong = src.replace('(["cat", "{file}"], False),', '(["cat", "{file}"], True),', 1)
        with open(bad, "w", encoding="utf-8") as fh:
            fh.write(wrong)
        proc = subprocess.run([sys.executable, "-I", bad, "--selftest"], capture_output=True,
                              text=True, timeout=120, env=dict(os.environ, ARGV_CLASSIFY_INNER="1"))
        reached.add(str(proc.returncode))
        case("cli-selftest-wrong-row exit %d" % proc.returncode,
             wrong != src and proc.returncode == 1 and "FAIL  data_only cat {file} is True" in proc.stdout,
             "(wanted 1 and the row named)")
    finally:
        shutil.rmtree(sandbox)
    return finish(held, total, reached)


def finish(held, total, reached, inner=False):
    print("\n%d of %d cases held" % (held, total))
    got, doc = " ".join(sorted(reached)), " ".join(documented_codes())
    print("    exit codes reached: %s   documented: %s" % (got, doc))
    print("    NOT ASSERTED: whether a value names a path in a real tree (run-checks.sh and "
          "stage-advance.sh each drive that through a fixture of their own); that each "
          "DATA_ONLY tool really runs nothing it reads - the entries rest on the tools' "
          "--help read on 2026-10-13, and an option a later release adds is not on them; a "
          "file a tool runs that no argument names - a test runner discovering tests, a "
          "config the tool finds by itself, a git alias; a value inside a comma-separated "
          "list (`--x=a,b`), which is one value here.")
    if got != doc and not inner:
        print("FAIL: reached and documented exit codes differ")
        return 1
    return 0 if held == total else 1


def die(msg):
    sys.stderr.write("argv-classify: %s\n" % msg)
    sys.exit(2)


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
    if len(args) >= 2 and args[0] == "--tokens":
        for k, tok in enumerate(args[1:]):
            for v, shaped in values(tok):
                print("%d\t%s\t%s" % (k, "shaped" if shaped else "exists", v))
        return 0
    if len(args) >= 2 and args[0] == "--data-only":
        ok, why = data_only(args[1:])
        print("data-only" if ok else why)
        return 0
    die("usage: argv-classify.py --tokens ARG... | --data-only ARG... | --selftest | --version | --help")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
