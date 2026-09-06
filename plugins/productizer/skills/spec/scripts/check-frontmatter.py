#!/usr/bin/env python3
# check-frontmatter.py — validate the YAML frontmatter of this skill's agent templates.
#
# Usage: check-frontmatter.py [--help] [--] [template ...]   (see usage() below, which is what
# `--help` actually prints — this comment is not the help text and cannot drift out of it)
#
# Why this exists. `tools:` in subagent frontmatter is an ALLOWLIST: what is not listed does
# not exist for that agent. references/delegation.md leans on exactly that — it is why the
# verifier and the reviewer cannot write files, and it says so in prose: "the tool list, not
# the prose, carries the restriction." Nothing read that list. The declared checks cover all
# files (hygiene), `**/*.sh` (shell-lint) and the solver corpus; a typo in `tools:` — `Bash,
# Reed` — is a security property silently deleted, in a file no check opens.
#
# Stdlib only, on purpose. This runs in whatever Python a contributor happens to have, before
# anyone has installed anything. A check that needs `pip install PyYAML` to run is a check
# that does not run. The parser below is therefore a deliberately small YAML SUBSET, and it
# REFUSES what it cannot read rather than guessing — see can_not_parse below.
import io
import os
import subprocess
import re
import sys

SELF = "check-frontmatter"

# The documented subagent frontmatter fields, verified against
# https://code.claude.com/docs/en/sub-agents.md (fetched 2026-08-29), "Supported frontmatter
# fields". Two are required; the rest are optional.
#
# READ THIS BEFORE ADDING A KEY. This set is the whole value of the check, and its failure
# mode is asymmetric. A key wrongly ABSENT from this set makes the check report a working
# template as broken — noisy, but self-correcting, because someone investigates. A key
# wrongly PRESENT blesses a field the runtime ignores, which is the failure this check was
# written to catch. So a key is added here only with a docs citation, never because it looks
# plausible or because a template already uses it.
REQUIRED_KEYS = ("name", "description")
OPTIONAL_KEYS = (
    "tools",
    "disallowedTools",
    "model",
    "permissionMode",
    "maxTurns",
    "skills",
    "mcpServers",
    "hooks",
    "memory",
    "background",
    "effort",
    "isolation",
    "color",
    "initialPrompt",
    "experimental",
)
KNOWN_KEYS = set(REQUIRED_KEYS) | set(OPTIONAL_KEYS)

# Tool names a subagent's `tools:` may name, same source, "Available tools".
KNOWN_TOOLS = {
    "Read", "Grep", "Glob", "Bash", "PowerShell", "Edit", "Write", "NotebookEdit",
    "WebFetch", "WebSearch", "TodoWrite", "Skill", "ToolSearch", "EnterWorktree",
    "ExitWorktree", "Monitor", "TaskStop", "SendMessage", "Artifact", "Agent", "ListAgents",
}

# Named, and reported separately from an unknown name, because these are a DIFFERENT defect.
# An unknown name is a typo. One of these is spelled correctly, is a real tool, and is still
# removed from every subagent — so listing it reads to a maintainer as a granted capability
# that was never granted. Inert, not wrong, and the reader cannot tell by looking.
ALWAYS_REMOVED_TOOLS = {
    "AskUserQuestion", "EndConversation", "EnterPlanMode", "ExitPlanMode",
    "ScheduleWakeup", "TaskOutput", "WaitForMcpServers", "Workflow",
}

# Enumerated values, from the same table. A key whose value is outside its enum is as inert as
# an unknown key, and fails just as quietly.
ENUMS = {
    "model": None,  # sonnet|opus|haiku|fable|<full model id>|inherit — open, so not enumerated
    "effort": {"low", "medium", "high", "xhigh", "max"},
    "permissionMode": {
        "default", "acceptEdits", "auto", "dontAsk", "bypassPermissions", "plan", "manual",
    },
    "memory": {"user", "project", "local"},
    "isolation": {"worktree"},
    "color": {"red", "blue", "green", "yellow", "purple", "orange", "pink", "cyan"},
}

# `name` must be lowercase letters and hyphens, and may not contain `:` — that is reserved for
# plugin-scoped identifiers, and Claude Code declines to load such a file at all.
NAME_RE = re.compile(r"^[a-z][a-z-]*$")

# An MCP server pattern is a legitimate entry that is not a built-in tool name.
MCP_RE = re.compile(r"^mcp__[A-Za-z0-9_-]+(__(\*|[A-Za-z0-9_-]+))?$")

DEFAULT_TEMPLATES = ("agent-verifier.md", "agent-reviewer.md")


def usage():
    sys.stdout.write("""\
check-frontmatter.py — validate the YAML frontmatter of this skill's agent templates.

Usage:
  check-frontmatter.py                  check the default agent templates (see below)
  check-frontmatter.py <file> [file...] check exactly these files
  check-frontmatter.py -- <file>        same, for a path that begins with a dash
  check-frontmatter.py --help | -h      print this and exit 0
  check-frontmatter.py --version        print the version and exit 0
  check-frontmatter.py --selftest       drive this file's own contract and exit 0/1
                                        (--self-test is accepted as an alias)

There are no other options. There are no tunables: the key set, the tool set and the
enumerated values are fixed in the script, so two runs over the same tree agree.

Default templates, resolved next to this script in ../templates/:
  agent-verifier.md
  agent-reviewer.md

These are the AGENT templates. templates/SKILL-secure-api-review.md and
templates/spec-command.md also carry frontmatter, but a Skill and a slash command are
different dialects with different key sets; checking them against the subagent set would
report correct files as broken. They are out of scope here and are not checked.

What it checks:
  1. The frontmatter parses at all — a `---` block at the very top of the file, closed.
  2. Required keys are present: name, description. And `tools`, which the subagent docs
     make optional but references/delegation.md requires: an agent that omits it inherits
     every tool, so a delegated agent always declares the list.
  3. `tools:` names only real tools. An unknown name is a typo that silently deletes a
     capability; a correctly-spelled but always-removed tool is reported separately,
     because it reads as a granted capability that was never granted.
  4. Every key is a documented subagent frontmatter key, and enumerated values are in
     range. An unknown key is REPORTED, never ignored — a field the runtime drops looks
     exactly like a field it honours, and the file cannot tell you which it got.

Three outcomes are kept distinct and are never collapsed into one:
  the file is ABSENT          exit 3. The check did not run. Never reported as a pass.
  the frontmatter CANNOT PARSE  a finding. Reported as unreadable, never as "no keys".
  it parsed and found NOTHING   exit 0. A real, measured pass.

Exit status:
  0  every file checked, no findings
  1  findings — at least one file has something wrong with it
  2  a bad invocation: an unknown option
  3  the check could not run: a file was absent or unreadable

Under --selftest: 0 every case produced the exit code this contract declares for
it, 1 at least one did not, 2 the corpus could not be built at all. All four
codes above are driven, each by a fixture written into a temporary directory
that is removed afterwards. Nothing is written into the repository.
""")


def die_usage(msg):
    sys.stderr.write("%s: %s\n\n" % (SELF, msg))
    sys.stderr.write(usage_text())
    sys.exit(2)


def usage_text():
    buf = io.StringIO()
    real, sys.stdout = sys.stdout, buf
    try:
        usage()
    finally:
        sys.stdout = real
    return buf.getvalue()


def parse_args(argv):
    """No options but --help; the rest are paths. `--` ends option parsing."""
    paths = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--version":
            # The check runner records the version of every tool it ran, so a
            # result can be read back later against the tool that produced it.
            # A check with no --version is a check the runner cannot declare.
            print("check-frontmatter 1.0")
            raise SystemExit(0)
        if a in ("-h", "--help"):
            usage()
            sys.exit(0)
        # R39: the self-test is dispatched here, ahead of the unknown-option
        # refusal below, and answers to either spelling. This repository writes
        # the flag both ways, and a tool that answers only one spelling has a
        # self-test the next caller cannot find.
        if a == "--selftest" or a == "--self-test":
            raise SystemExit(selftest())
        if a == "--":
            paths.extend(argv[i + 1:])
            break
        if a.startswith("-") and a != "-":
            die_usage("unknown option: %s" % a)
        paths.append(a)
        i += 1
    return paths


class CannotParse(Exception):
    """The frontmatter could not be read. Distinct from 'it read as empty'."""


def split_frontmatter(text, path):
    """Return the raw frontmatter body. Raises CannotParse with a reason a human can act on."""
    if text.startswith("﻿"):
        raise CannotParse("file begins with a UTF-8 BOM, so the `---` opener is not at "
                          "byte 0 and the frontmatter will not be recognised")
    lines = text.split("\n")
    if not lines or lines[0].rstrip("\r") != "---":
        first = lines[0][:40] if lines else ""
        raise CannotParse("no frontmatter: line 1 is %r, expected `---`" % first)
    for n in range(1, len(lines)):
        if lines[n].rstrip("\r") == "---":
            return lines[1:n], n + 1
    raise CannotParse("frontmatter opened with `---` at line 1 but is never closed; "
                      "searched all %d lines" % len(lines))


def parse_block(body, path):
    """A deliberately small YAML subset: `key: value`, block sequences, and inline `[a, b]`.

    It refuses everything else. Silently returning a partial mapping is the one behaviour a
    validator must not have — the keys it failed to read would be reported as absent, and a
    missing required key is precisely what this check exists to catch.
    """
    data = {}
    order = []
    key = None
    for idx, raw in enumerate(body):
        lineno = idx + 2  # body starts at file line 2
        line = raw.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue

        if re.match(r"^\s*-\s", line):
            if key is None:
                raise CannotParse("line %d: list item before any key: %r" % (lineno, line.strip()))
            item = line.lstrip()[1:].strip()
            if not isinstance(data[key], list):
                if data[key] != "":
                    raise CannotParse("line %d: key %r has both an inline value and a list"
                                      % (lineno, key))
                data[key] = []
            data[key].append(strip_quotes(item))
            continue

        if line[:1] in (" ", "\t"):
            raise CannotParse("line %d: indented line that is not a list item: %r — this "
                              "parser reads flat keys and block sequences only, and will "
                              "not guess at nested structure" % (lineno, line.strip()))

        m = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s?(.*)$", line)
        if not m:
            raise CannotParse("line %d: not a `key: value` line: %r" % (lineno, line.strip()))
        key, val = m.group(1), m.group(2).strip()
        if key in data:
            raise CannotParse("line %d: duplicate key %r" % (lineno, key))
        order.append(key)
        data[key] = parse_scalar(val)
    return data, order


def strip_quotes(s):
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        return s[1:-1]
    return s


def parse_scalar(val):
    if val.startswith("[") and val.endswith("]"):
        inner = val[1:-1].strip()
        if not inner:
            return []
        return [strip_quotes(p.strip()) for p in inner.split(",")]
    return strip_quotes(val)


def as_tool_list(val):
    """`tools:` is written either as a block/inline list or as one comma-separated string."""
    if isinstance(val, list):
        return [v for v in (x.strip() for x in val) if v]
    return [v for v in (x.strip() for x in str(val).split(",")) if v]


def check_file(path):
    """Return (findings, ran). ran=False means the check could not run on this file."""
    f = []
    if not os.path.exists(path):
        return (["ABSENT: no file at %s" % path], False)
    if os.path.isdir(path):
        return (["ABSENT: %s is a directory, not a template" % path], False)
    try:
        text = io.open(path, encoding="utf-8").read()
    except (IOError, OSError) as e:
        return (["UNREADABLE: %s: %s" % (_rel(path), e.strerror or e)], False)
    except UnicodeDecodeError as e:
        return (["UNREADABLE: %s is not valid UTF-8: %s" % (_rel(path), e)], False)

    try:
        body, _ = split_frontmatter(text, path)
        data, order = parse_block(body, path)
    except CannotParse as e:
        # A finding, not a crash, and never reported as "found no keys": the file exists and
        # its frontmatter is unreadable, which is a defect in the file.
        return (["CANNOT PARSE: %s" % e], True)

    if not order:
        f.append("frontmatter block is empty — no keys at all")

    for k in REQUIRED_KEYS:
        if k not in data:
            f.append("missing required key: %s" % k)
        elif not str(data[k]).strip():
            f.append("required key %s is present but empty" % k)

    # delegation.md: "An agent that inherits the default gets everything, so a delegated agent
    # always declares the list." Omitting `tools` is legal frontmatter and a real defect here.
    if "tools" not in data:
        f.append("missing key: tools — an agent that omits it INHERITS EVERY TOOL, "
                 "including Edit and Write (references/delegation.md)")

    if "name" in data:
        name = str(data["name"]).strip()
        if name and not NAME_RE.match(name):
            if ":" in name:
                f.append("name %r contains ':', which is reserved for plugin-scoped ids; "
                         "Claude Code will not load this file" % name)
            else:
                f.append("name %r is not lowercase letters and hyphens" % name)

    if "tools" in data:
        tools = as_tool_list(data["tools"])
        if not tools:
            f.append("tools: is present but names no tools — an agent that resolves to zero "
                     "tools fails to launch")
        for t in tools:
            if t in KNOWN_TOOLS or MCP_RE.match(t):
                continue
            if t in ALWAYS_REMOVED_TOOLS:
                f.append("tools: lists %r, which is ALWAYS removed from subagents — it is "
                         "inert here and reads as a capability that was never granted" % t)
            else:
                f.append("tools: unknown tool %r — not a documented tool name. A name that "
                         "does not resolve is a capability silently deleted" % t)

    for k in order:
        if k not in KNOWN_KEYS:
            f.append("unknown key %r — not a documented subagent frontmatter field, so the "
                     "runtime ignores it. Reported rather than assumed harmless: a dropped "
                     "field looks exactly like an honoured one" % k)
            continue
        allowed = ENUMS.get(k)
        if allowed:
            v = data[k]
            for one in (v if isinstance(v, list) else [v]):
                if str(one).strip() and str(one).strip() not in allowed:
                    f.append("key %s has value %r, which is outside its documented range "
                             "(%s)" % (k, one, ", ".join(sorted(allowed))))
    return (f, True)


def _rel(path):
    """Repo-relative, because this output is captured.

    The check runner stores each check's output tail inside checks-result.json,
    which is committed. An absolute path therefore writes whoever ran the check
    into a public file - the same leak that shipped once already. A path outside
    the work tree stays absolute: shortening it would misname where the file is,
    and a wrong path is worse than a long one.
    """
    try:
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        root = top.stdout.decode("utf-8", "replace").strip()
    except OSError:
        return path
    if not root or not os.path.isabs(root):
        return path
    ap = os.path.abspath(path)
    if ap == root:
        return "."
    if ap.startswith(root + os.sep):
        return ap[len(root) + 1:]
    return path



# --------------------------------------------------------------- --selftest
#
# R39 — every check tool carries a self-test that reaches each exit code it can
# return. This file returns four and all four are driven below, each by a
# template written into a temporary directory and this script re-invoked on it.
# Nothing is written into the repository, and the corpus is removed on every
# exit path.
#
# THE CASES ARE RUN AS A SUBPROCESS, not by calling main() in-process, so the
# argument parser and the three-way exit are on the measured path too. A
# self-test that calls check_file() directly would leave the exits — the part
# of the contract everything downstream reads — untested.

SELFTEST_CLEAN = """---
name: fixture-agent
description: a template that exists only to be the clean case of this self-test
tools: Read, Grep
---

Body text. Nothing below the frontmatter is examined.
"""

SELFTEST_CASES = (
    # (name, filename, contents, expected exit, what the case is)
    ("clean-template", "clean.md", SELFTEST_CLEAN, 0,
     "required keys present, tools declared, every name real"),
    ("unknown-tool", "typo.md",
     SELFTEST_CLEAN.replace("tools: Read, Grep", "tools: Read, Reed"), 1,
     "a misspelled tool name is a capability silently deleted"),
    ("always-removed-tool", "inert.md",
     SELFTEST_CLEAN.replace("tools: Read, Grep", "tools: Read, ExitPlanMode"), 1,
     "a real but always-removed tool reads as a capability never granted"),
    ("missing-tools-key", "notools.md",
     SELFTEST_CLEAN.replace("tools: Read, Grep\n", ""), 1,
     "an agent that omits tools inherits every tool"),
    ("missing-required-key", "noname.md",
     SELFTEST_CLEAN.replace("name: fixture-agent\n", ""), 1,
     "a required key is absent"),
    ("unknown-key", "straykey.md",
     SELFTEST_CLEAN.replace("tools: Read, Grep", "tools: Read, Grep\ncolour: red"), 1,
     "a key the runtime drops looks exactly like one it honours"),
    ("enum-out-of-range", "badenum.md",
     SELFTEST_CLEAN.replace("tools: Read, Grep", "tools: Read, Grep\neffort: enormous"), 1,
     "a value outside its documented range is as inert as an unknown key"),
    ("cannot-parse", "noblock.md",
     "no frontmatter here at all\n", 1,
     "unreadable frontmatter is a finding, never reported as `no keys`"),
)


def selftest():
    import shutil
    import tempfile

    try:
        work = tempfile.mkdtemp(prefix="check-frontmatter-selftest.")
    except OSError as exc:
        sys.stderr.write("%s: cannot create a temporary directory to build the "
                         "self-test corpus in (%s). Unmeasured, not a pass.\n"
                         % (SELF, exc.__class__.__name__))
        return 2

    cases = 0
    upheld = 0

    def run(name, argv, expected, what):
        """Drive one case and read the exit code off the child."""
        nonlocal cases, upheld
        proc = subprocess.run([sys.executable, os.path.abspath(__file__)] + argv,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        got = proc.returncode
        cases += 1
        if got == expected:
            upheld += 1
            verdict = "held"
        else:
            verdict = "NOT HELD"
        sys.stdout.write("      %-26s expected %d  got %d  %s  %s\n"
                         % (name, expected, got, verdict, what))

    try:
        sys.stdout.write("    selftest: check-frontmatter 1.0\n")
        for name, filename, body, expected, what in SELFTEST_CASES:
            path = os.path.join(work, filename)
            with io.open(path, "w", encoding="utf-8") as fh:
                fh.write(body)
            run(name, [path], expected, what)

        run("unknown-option", ["--not-a-real-option"], 2,
            "a bad invocation is refused, never answered")
        run("absent-file", [os.path.join(work, "no-such-template.md")], 3,
            "a file nobody opened is not a file that passed")
        run("directory-not-a-file", [work], 3,
            "a directory is reported as absent, never parsed as empty")
        run("absent-outranks-findings",
            [os.path.join(work, "typo.md"), os.path.join(work, "no-such-template.md")], 3,
            "could-not-run outranks findings, so the run cannot be read as a verdict")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    verdict = "held" if cases == upheld else "NOT HELD"
    sys.stdout.write("    R39  %-38s examined %3d  upheld %3d  %s: %s\n"
                     % ("selftest-cases-produce-declared-exit", cases, upheld,
                        verdict, "each case exits with the code this file's "
                        "contract declares for it"))
    sys.stdout.write("    exit codes reached: 0, 1, 2 and 3 - the whole contract.\n")
    sys.stdout.write("    NOT ASSERTED: the WORDING of any finding. The corpus drives the "
                     "exit code, so a case that went red for the wrong reason is "
                     "invisible here and is read off the case output by hand.\n")
    return 0 if cases == upheld else 1


def main(argv):
    paths = parse_args(argv)
    if not paths:
        here = os.path.dirname(os.path.abspath(__file__))
        tdir = os.path.join(os.path.dirname(here), "templates")
        paths = [os.path.join(tdir, n) for n in DEFAULT_TEMPLATES]

    findings = 0
    could_not_run = 0
    for p in paths:
        f, ran = check_file(p)
        if not ran:
            could_not_run += 1
            for line in f:
                sys.stdout.write("%s: %s\n" % (SELF, line))
            continue
        if f:
            findings += 1
            sys.stdout.write("FAIL %s\n" % _rel(p))
            for line in f:
                sys.stdout.write("  - %s\n" % line)
        else:
            sys.stdout.write("ok   %s\n" % _rel(p))

    # Three outcomes, three exits. "Could not run" outranks "found nothing wrong", because a
    # file nobody opened is not a file that passed.
    if could_not_run:
        sys.stdout.write("%s: %d file(s) could not be checked. This is NOT a pass.\n"
                         % (SELF, could_not_run))
        return 3
    if findings:
        sys.stdout.write("%s: %d of %d file(s) have findings.\n" % (SELF, findings, len(paths)))
        return 1
    sys.stdout.write("%s: %d file(s) checked, no findings.\n" % (SELF, len(paths)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
