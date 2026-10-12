# Session start — announcing lifecycle state without being asked

Everything else in this lifecycle waits to be asked. The spec, the intake
classification, the stage — a person has to think of the question before any of
it surfaces. That is the failure this hook exists to prevent: a session opening
in a repo with a contradiction sitting unresolved in the spec, and nobody
learning about it until they happen to ask.

`templates/session-start.sh` runs on the `SessionStart` event, which fires "when
a session begins or resumes", and announces the state of the bound repo in one
line before the first prompt.

## What it shows

```
acme-billing · 2 open intents · 1 CONTRADICTION waiting on your ruling · spec R1–R<n>, 3 superseded
Open in Areas of concern: C1. Nothing merges into the spec until it is ruled on.
```

| Field | Read from | Rule |
|---|---|---|
| product | `product.name` in `.claude/productizer/config.json` | stripped to letters, digits, `. _ -` and space, truncated to 40 characters |
| open intents | `gh issue list --label sdlc:intent --state open`, cached | rendered `open intents unknown` when it cannot be read, never `0` |
| contradictions | rows of the *Areas of concern* table in the spec | a status naming `resolved` is not open; the count is uppercased because it is the only line here that needs a human |
| spec range | the `- **R<n>**` requirement bullets | lowest and highest id, not a count of rows |
| superseded | `Superseded by R<n>` as a status marker on its own line | prose and index rows mentioning supersession are not counted, or every superseded requirement counts three times |

The second line appears only when a contradiction is open. A quiet repo gets one
line; a repo needing a ruling gets two, and the second one says what is blocked.

The hook returns JSON on stdout and fills two fields with the same sentence:
`hookSpecificOutput.additionalContext`, which is "Text added to Claude's
context", and `systemMessage` — "To surface a message to the user on any
platform, return `systemMessage` in JSON output". One reaches the model, the
other reaches the human. Filling only the first means the state is known and
never said out loud.

## What it costs

Measured on macOS, median of 100 runs each:

| Case | Per run |
|---|---|
| repo with no `.claude/productizer/config.json` | 3.9 ms |
| bound repo, 60-line spec, intent count cached | 16.9 ms |
| bound repo, 4,576-line spec (4,000 requirements) | 26.2 ms |
| bound repo, intent count stale, `gh` reachable | one `gh issue list`, hard-capped at 1.5 s, once per 15 minutes |
| bound repo, `gh` hung or unauthenticated | 1.5 s once, then 50 ms for 5 minutes |

An unbound repo exits on a single `test -f`, before it opens the spec or looks
for `gh`. That matters because most repos on a machine are not bound and must
not pay for a feature they do not use.

The intent count is the only network call, and it is the only number with no
file to read: the shipped binding sets `intent.persist` to false, so intents
live in the tracker and a folder scan would count something else. It is bounded
three ways — a 15 minute cache, a watchdog that kills `gh` after 1.5 s, and a
5 minute negative cache so an unauthenticated `gh` does not charge every session
the full wait. Set `SDLC_HOOK_NO_NETWORK=1` to drop it entirely; the rest of the
line still renders.

## Installing it

```bash
mkdir -p .claude/hooks
cp ~/.claude/skills/spec/templates/session-start.sh .claude/hooks/session-start.sh
chmod +x .claude/hooks/session-start.sh
echo '.claude/productizer/.session-start-intents' >> .gitignore
```

Then merge `templates/hooks-settings.json` into `.claude/settings.json`. Commit
both — a hook that is not version controlled is not a governance control, it is
one engineer's local convenience.

Notes on the registration, which the JSON cannot carry itself:

- **`timeout: 5`, not the default.** The `command` default is 600 seconds. A
  session-start hook that can stall for ten minutes is a session-start hook that
  will, one day, on a bad network.
- **The matcher covers `startup|resume|clear|compact`.** `compact` is included
  because a compaction discards the announcement from context, and state nobody
  can see is state nobody acts on. `fork` is excluded: a fork inherits the
  parent's context and would hear it twice.
- **`${CLAUDE_PROJECT_DIR}`, not a relative path.** Hooks "run in the current
  directory", which is not necessarily the repo root when a session opens in a
  subdirectory.

## Turning it off

Delete the `SessionStart` block from `.claude/settings.json`. The script can
stay on disk; nothing else invokes it. To keep the announcement but stop the
tracker query, export `SDLC_HOOK_NO_NETWORK=1` — the intent count then reads
`open intents unknown`, which is honest, where a `0` would read as "nothing in
flight" and be believed.

## What it cannot tell you

- **It reflects committed state only.** Uncommitted spec edits in your working
  tree are read as if they were agreed. Work happening in another session,
  another clone or another branch is invisible.
- **A contradiction it never sees is a contradiction it never reports.** The
  count comes from the *Areas of concern* table. An intake that stopped at a
  contradiction without recording a row produces a clean-looking line.
- **The intent count can be 15 minutes stale**, and reflects one repo — the
  labelled issues on the current repo, not the product's other repos. The fleet
  view is still the answer to what is in flight across repos.
- **It does not name the stage.** Stage is determined by the issue and the
  branch, not by file presence, and reconstructing that costs more than a
  session-start hook may spend. The line reports state, not a next action.
- **A spec at a path other than `.claude/productizer/spec.md` is not read.** The hook
  does not honour `spec.path` from the binding; a repo that moves its spec gets
  silence rather than a wrong number.
- **It never blocks and never errors.** Missing binding, unreadable spec,
  malformed JSON, corrupt cache: every one exits 0 with no output. `SessionStart`
  cannot block a session, and a hook writing to stderr renders in the transcript
  as a hook error, so the script sends its own stderr to `/dev/null`. The cost
  of that choice is that a broken hook is silent in exactly the way a correctly
  quiet one is — if you expect a line and get none, run the script by hand.

## Why it counts instead of quoting

A spec, a binding and an issue title all arrive with a clone and can be written
by anyone who can open a pull request. Text from any of them is placed straight
into the model's context on the first turn of a session, before a human has read
a word of it. So the hook emits counts, requirement ids and concern ids, and one
product name reduced to a conservative character set — nothing that can carry an
instruction. The same rule makes the output safe to build by string
concatenation: no quote or backslash survives sanitisation, so no field can be
broken open to inject a second one.
