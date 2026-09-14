---
name: help
description: "List every Productizer command with what it does and when to reach for it, read from the installed plugin rather than from memory. Use when asked what productizer can do, what the commands are, how to use it, where to start, or which command to use for something."
disable-model-invocation: true
allowed-tools: Bash Read
---

# Productizer — what you can type

!`D="${CLAUDE_PLUGIN_ROOT}"; [ -n "$D" ] && [ -d "$D" ] || D="$(git rev-parse --show-toplevel 2>/dev/null)/plugins/productizer"; S="$D/skills/help/scripts/list-commands.sh"; if [ ! -f "$S" ]; then echo "cannot find list-commands.sh under the plugin - this list would be from memory, and memory is what it exists to avoid."; exit 0; fi; rc=0; bash "$S" --plugin "$D" || rc=$?; [ "$rc" -eq 0 ] || echo "  (list-commands.sh exited $rc - 3: no skills/ or commands/ found, 4: an entry could not be read)"`

## Reading that

The first column says where a row came from: `skill` is
`skills/<name>/SKILL.md`, `command` is `commands/<name>.md`. Both are read at
run time from their own frontmatter, and both are typed the same way.

`[auto]` means Claude may invoke it on its own from what you are doing.
Everything else you type, deliberately — those either publish something, run
every declared tool in the repo, edit the queue, or start asking you questions,
and none of that should happen because a sentence sounded like a request.

**The bare form works too** — `/dashboard`, `/check` — unless another plugin has
claimed the name.

## Where to start

- **A repo that has never used this** → `import`. It surveys read-only and
  refuses to draft from a repo that cannot evidence its own behaviour.
- **A repo already under a spec** → `answer` for what is waiting on a person,
  `dashboard` to see the whole state, `check` before you commit.
- **Something you want built** → `backlog` to queue it, or just describe it and
  the lifecycle skill picks it up.

## What this list is not

It is read from the **installed** plugin at run time, so it cannot list a
command that does not exist or miss one that does. It can still be behind the
source checkout: installing copies a snapshot, and edits there do not reach it
until `claude plugin update productizer`.

A skill or command whose file cannot be read is listed as unreadable rather than skipped.
A command missing from a list is indistinguishable from one that was never
installed, and only one of those is worth knowing about.
