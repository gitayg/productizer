#!/usr/bin/env python3
"""argv-classify.py [--walk ARG...] [--selftest] [--version] [--help]

THE ONE READING OF A CHECK'S ARGV that both run-checks.sh and stage-advance.sh
use: which positions of a declared argv may name code the repository chose,
and which operands may name a repository path. run-checks.sh refuses such a
command unless the configuration opts in to repository-declared check tools
(R102, R22); stage-advance.sh protects every such path from an unattended
change (R126). The two scripts used to carry a copy each, the copies drifted
twice (B136 review, 2026-10-13), and each drift was a file that ran while the
other script said it could not. So the reading lives here, once, and each
script loads this file by its path - never by import, so no bytecode cache
beside it is ever read.

WHAT IT CLASSIFIES. walk(argv) returns (index, role, value) for:
  program   argv[0], as written
  script    after an element that names an interpreter, its first operand
            that does not begin with `-` (a placeholder there too, and a
            placeholder in the value of an option the interpreter takes
            before its script: `-m{file}`, `--require={file}`)
  after     when an interpreter's options come BEFORE its first operand, every
            later operand - an option may have taken the first one as its
            value (`python3 -W ignore x.py`, `node --require ./a.js b.js`),
            and which operand is the script cannot be told from the argv. A
            placeholder there is the change choosing what runs, unless `-m`
            already named the module and the rest are its arguments
  module    after `-m NAME` or `-mNAME`: NAME's top package, its single-file
            form and NAME as a file path (`pkg`, `pkg.py`, `pkg/mod.py`)
  operand   for every element but argv[0]: the element itself, the value of
            `--opt=VALUE`, or the value glued to a short option
            (`-Itools/lib`), because a tool reads a program of its own
            through an option (`sed -f x.sed`, `perl -Itools/lib`)
An interpreter is matched by its STEM, whatever version or suffix it carries:
python3.9, pypy3, ruby3.2, /usr/bin/python3 and node.exe are interpreters.

WHAT EACH CALLER DECIDES ITSELF, on purpose. Whether a classified value names
a path in ITS repository: stage-advance.sh asks of the base tree, and of any
path a change could add (path_like: no whitespace, and a slash or a script
extension); run-checks.sh asks of the work tree the tools will run in, where a
path that is not there names nothing. The roles, the interpreter stems and the
script extensions are this file's alone.

WHAT IT DOES NOT SEE. A file a tool runs that no operand names: a test runner
discovering tests, a config file the tool finds by itself, a git alias.

--walk prints one line per classified position, `INDEX<TAB>ROLE<TAB>VALUE`.

Exit codes:
  0  printed what was asked
  1  the self-test found a case that did not hold
  2  bad usage
--selftest pins the classification table below, case by case.
"""

import os
import posixpath
import re
import subprocess
import sys

VERSION = "argv-classify 1.0"

PROGRAM, SCRIPT, AFTER, MODULE, OPERAND = "program", "script", "after", "module", "operand"

# How each role reads in a sentence. stage-advance.sh writes these into its
# refusals, and its self-test asserts them.
DESCRIBE = {
    PROGRAM: "the program",
    SCRIPT: "the script an interpreter is handed",
    MODULE: "the script an interpreter is handed",
    AFTER: "an operand of an interpreter whose options precede its script",
    OPERAND: "a repository path named",
}

INTERPRETER_STEMS = {"python", "pypy", "jython", "perl", "ruby", "jruby", "node", "nodejs",
                     "deno", "bun", "php", "lua", "luajit", "tclsh", "wish", "expect", "rscript",
                     "osascript", "swift", "ghc", "runghc", "runhaskell", "groovy", "jshell",
                     "scala", "java", "kotlin", "julia", "elixir", "escript", "erl", "raku",
                     "pwsh", "powershell", "ts-node", "tsx"}

# What an interpreter reads as a script, and what a tool reads as a program
# of its own (sed -f, jq -f, a jar).
SCRIPT_EXT = re.compile(r"\.(py|pyw|sh|bash|zsh|pl|pm|rb|js|mjs|cjs|ts|mts|cts|lua|php|r|scpt|tcl|"
                        r"exp|ps1|awk|sed|jq|jar|class|groovy|kt|kts|scala|swift|hs|ex|exs|jl|raku)$",
                        re.IGNORECASE)


def is_interpreter(x):
    b = posixpath.basename(x).lower()
    if b.endswith(".exe"):
        b = b[:-4]
    return re.sub(r"[0-9][0-9._-]*$", "", b) in INTERPRETER_STEMS


def operand_of(x):
    """The element itself, the value of --opt=VALUE, or a short option's glued value."""
    if x.startswith("--"):
        return x.split("=", 1)[1] if "=" in x else None
    if x.startswith("-"):
        return x[2:].lstrip("=") if len(x) > 2 else None
    return x


def module_paths(m):
    """`-m pkg.mod` runs pkg/__init__.py and pkg/mod.py."""
    if "/" in m or "{" in m or not m:
        return []
    top = m.split(".")[0]
    return list(dict.fromkeys([top, top + ".py", m.replace(".", "/") + ".py"]))


def path_like(c, in_tree):
    """A repository path: one in_tree(normalised) holds, or one with no
    whitespace and a slash or a script extension. A placeholder or a URL is
    not one, and neither is prose with a slash in it."""
    if not c or "{" in c or "://" in c:
        return False
    rel = posixpath.normpath(c)
    if rel not in (".", "..") and in_tree(rel):
        return True
    return not re.search(r"\s", c) and ("/" in c or bool(SCRIPT_EXT.search(c)))


def walk(v):
    out = [(0, PROGRAM, v[0])]
    for j, x in enumerate(v):
        if not is_interpreter(x):
            continue
        opts_first = seen = ended = moduled = False
        for k in range(j + 1, len(v)):
            y = v[k]
            if not ended and y == "--":
                ended = True
                continue
            if not ended and y.startswith("-") and y != "-":
                if not seen:
                    opts_first = True
                    c = operand_of(y)
                    if c is not None and "{" in c:
                        out.append((k, SCRIPT, c))
                    elif y.startswith("-m") and not y.startswith("--") and len(y) > 2:
                        # `-mNAME` fills the script's place: what follows is
                        # the module's arguments.
                        out.extend((k, MODULE, p) for p in module_paths(y[2:]))
                        moduled = seen = True
                continue
            if "{" in y and seen and moduled:
                continue
            out.append((k, AFTER if seen else SCRIPT, y))
            if k > j + 1 and v[k - 1] == "-m":
                out.extend((k, MODULE, p) for p in module_paths(y))
                moduled = True
            if not seen and not opts_first:
                break
            seen = True
    for k in range(1, len(v)):
        c = operand_of(v[k])
        if c is not None:
            out.append((k, OPERAND, c))
    return out


# THE TABLE. Each argv, and the classified positions other than `operand`,
# which every element but argv[0] yields. stage-advance.sh and run-checks.sh
# each drive a case of their own through the real script that pins one row.
TABLE = [
    (["python3", "-W", "ignore", "tools/a.py"],
     [(0, PROGRAM, "python3"), (2, SCRIPT, "ignore"), (3, AFTER, "tools/a.py")]),
    (["python3.9", "tools/a.py"], [(0, PROGRAM, "python3.9"), (1, SCRIPT, "tools/a.py")]),
    (["python3.12", "lint.py", "--strict", "x.py"],
     [(0, PROGRAM, "python3.12"), (1, SCRIPT, "lint.py")]),
    (["/usr/bin/pypy3", "-X", "dev", "-m", "modpkg.main"],
     [(0, PROGRAM, "/usr/bin/pypy3"), (2, SCRIPT, "dev"), (4, AFTER, "modpkg.main"),
      (4, MODULE, "modpkg"), (4, MODULE, "modpkg.py"), (4, MODULE, "modpkg/main.py")]),
    (["python3", "-mpkg", "{files}", "tests"],
     [(0, PROGRAM, "python3"), (1, MODULE, "pkg"), (1, MODULE, "pkg.py"), (3, AFTER, "tests")]),
    (["python3", "-m", "pytest", "{files}"],
     [(0, PROGRAM, "python3"), (2, SCRIPT, "pytest"), (2, MODULE, "pytest"),
      (2, MODULE, "pytest.py")]),
    (["python3", "-m", "{file}"], [(0, PROGRAM, "python3"), (2, SCRIPT, "{file}")]),
    (["python3", "-W", "ignore", "{file}"],
     [(0, PROGRAM, "python3"), (2, SCRIPT, "ignore"), (3, AFTER, "{file}")]),
    (["node", "--require", "./a.js", "b.js"],
     [(0, PROGRAM, "node"), (2, SCRIPT, "./a.js"), (3, AFTER, "b.js")]),
    (["node.exe", "--require={file}", "b.js"],
     [(0, PROGRAM, "node.exe"), (1, SCRIPT, "{file}"), (2, SCRIPT, "b.js")]),
    (["perl", "-Itools/lib", "-MMark", "/dev/null"],
     [(0, PROGRAM, "perl"), (3, SCRIPT, "/dev/null")]),
    (["sed", "-n", "-f", "tools/prog.sed", "docs/in.txt"], [(0, PROGRAM, "sed")]),
    (["python3", "{file}"], [(0, PROGRAM, "python3"), (1, SCRIPT, "{file}")]),
    (["python3", "--", "-x.py"], [(0, PROGRAM, "python3"), (2, SCRIPT, "-x.py")]),
    (["shellcheck", "--severity=warning", "{file}"], [(0, PROGRAM, "shellcheck")]),
    (["grep", "-q", "needle", "{file}"], [(0, PROGRAM, "grep")]),
]
# Interpreter by stem, and the operand reading.
STEMS = [("python3.12", True), ("pypy3", True), ("node.exe", True), ("/usr/bin/python3", True),
         ("ruby3.2", True), ("Rscript", True), ("pythonista", False), ("grep", False),
         ("nodemon", False), ("shellcheck", False)]
OPERANDS = [("-Itools/lib", "tools/lib"), ("--require=./a.js", "./a.js"), ("--require", None),
            ("-W", None), ("-Wignore", "ignore"), ("-I=x", "x"), ("plain", "plain")]
PATHS = [("tools/x.sh", True), ("x.py", True), ("ignore", False), ("README", True),
         ("a reason / with a slash", False), ("https://e.invalid/x", False), ("{file}", False),
         (".", False), ("/usr/bin/x", True)]


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

    for argv, want in TABLE:
        got = [t for t in walk(argv) if t[1] != OPERAND]
        case("walk %s" % " ".join(argv), got == want, "-> %r" % (got,))
    for name, want in STEMS:
        case("interpreter %s is %s" % (name, want), is_interpreter(name) is want)
    for elem, want in OPERANDS:
        case("operand of %s is %r" % (elem, want), operand_of(elem) == want)
    for c, want in PATHS:
        case("path_like %r is %s" % (c, want), path_like(c, lambda r: r == "README") is want)
    me = os.path.abspath(__file__)
    for name, args, want, text in (
            ("cli-walk", ["--walk", "python3", "-W", "ignore", "x.py"], 0, "3\tafter\tx.py"),
            ("cli-version", ["--version"], 0, "argv-classify 1."),
            ("cli-help", ["--help"], 0, "Exit codes:"),
            ("cli-usage", ["--bogus"], 2, "usage: argv-classify.py"),
            ("cli-walk-empty", ["--walk"], 2, "usage: argv-classify.py")):
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
        wrong = src.replace('(3, AFTER, "tools/a.py")]),', '(3, SCRIPT, "tools/a.py")]),', 1)
        with open(bad, "w", encoding="utf-8") as fh:
            fh.write(wrong)
        proc = subprocess.run([sys.executable, "-I", bad, "--selftest"], capture_output=True,
                              text=True, timeout=120, env=dict(os.environ, ARGV_CLASSIFY_INNER="1"))
        reached.add(str(proc.returncode))
        case("cli-selftest-wrong-row exit %d" % proc.returncode,
             wrong != src and proc.returncode == 1 and "FAIL  walk python3 -W ignore tools/a.py" in proc.stdout,
             "(wanted 1 and the row named)")
    finally:
        shutil.rmtree(sandbox)
    return finish(held, total, reached)


def finish(held, total, reached, inner=False):
    print("\n%d of %d cases held" % (held, total))
    got, doc = " ".join(sorted(reached)), " ".join(documented_codes())
    print("    exit codes reached: %s   documented: %s" % (got, doc))
    print("    NOT ASSERTED: that a real interpreter treats each option the way the table "
          "assumes (run-checks.sh and stage-advance.sh measure that with a marker file); "
          "a file a tool runs that no operand names - a test runner discovering tests, a "
          "config the tool finds by itself, a git alias; an interpreter whose stem is not "
          "in the list; a placeholder in an option value of a tool that is not an "
          "interpreter (`--config={file}` is data here).")
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
    if len(args) >= 2 and args[0] == "--walk":
        for k, role, value in walk(args[1:]):
            print("%d\t%s\t%s" % (k, role, value))
        return 0
    die("usage: argv-classify.py --walk ARG... | --selftest | --version | --help")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
