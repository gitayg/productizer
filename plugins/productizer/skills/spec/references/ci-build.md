# Building from the spec in CI — an optional, copyable workflow

> **EXPERIMENTAL — this workflow has never run on a real GitHub runner. Its main
> protection, that the AI gets no shell, was measured only with a local CLI. Do
> not adopt it yet.** The runner measurements it waits on are backlog items B113
> (whether the action honours the committed permission settings) and B121 (the
> no-shell template measured end to end on GitHub).

`templates/build-from-spec.yml` turns a merged spec change into a **draft**
pull request, with no person at the keyboard while the model works. It is a
file you copy into your own repository, in the same way as
`templates/agent-evals.yml`. Productizer runs nothing itself: CI mechanics are
outside the spec's scope, and this is a template the repository owner chooses
to adopt.

Adapted from the AI Unified Process generate workflow (Apache-2.0, Simon
Martinelli), `.github/workflows/aiup-generate.yml`. Four ideas came from it: a
dispatched run whose only output is a pull request, the spec's diff travelling
with the prompt, git denied to the agent, and the run's id written into the
pull request. No code was copied. Two choices go the other way on purpose. It is
a copied file, not a reusable workflow called through a moving tag, because a
moving tag changes the code that runs in every adopting repository without
anyone reviewing it there. And it takes no free-text skill or model input.

## The rule it follows

Nothing reaches an audience without a person deciding. In this workflow the
decision is the person who dispatches the run:

- **`workflow_dispatch` is the only trigger.** No push, schedule, comment or
  label starts it.
- **It runs only from the default branch.** The first step refuses any other
  `github.ref`, and both scripts refuse a `HEAD` that is not the tip of the
  default branch.
- **It never writes to the default branch.** It pushes only
  `productizer/<mode>-<issue>-<run id>`, using an explicit refspec.
- **The pull request is always a draft.** Merging still needs a person, and
  branch protection is what makes that true (see below).

## What runs

| Job | Token | What it does |
|---|---|---|
| `prepare` | `contents: read`, checkout keeps no credentials | `build-dispatch.sh prepare`: decides whether there is anything to do, then writes the agent's data as files, and renders the pull request body (`--body-out`) - the one step that runs the repository's own code, here with no write token and before the agent runs - as a separate artifact the agent's job never fetches. **No model is called.** |
| `generate` | `contents: read`, checkout keeps no credentials, Bash denied, `.git` moved out before the agent runs | `anthropics/claude-code-action` with a fixed prompt, then `build-dispatch.sh capture` turns the working tree into a patch against the stashed git-dir |
| `deliver` | `contents: write`, `pull-requests: write` | the pinned productizer scripts are checked to be the pinned commit and copied out of the workspace; then `build-dispatch.sh deliver`: `stage-advance.sh` decides on the patch, then a new branch and a commit, then `stage-advance.sh` decides again on that commit, then a push and `gh pr create --draft` with prepare's body as text. **No model runs here, and no code from the repository being written to** (R71). |

A write token never sits beside the model. The agent job's only token is its
own read-only `GITHUB_TOKEN`, and that token is passed to the action
explicitly. Without it the action requests an OIDC token and exchanges it for
an app token that has `contents`, `pull_requests` and `issues` write. That was
read in the action's `src/github/token.ts` at the pinned commit. The agent job
does not grant `id-token: write`, so the exchange could not happen anyway.
Passing the token explicitly makes the intent visible rather than incidental.

**Never a shell in CI (maintainer ruling, 2026-10-11).** An earlier, unpushed
draft of this template tried to protect the runner's own artifact and cache
tokens - `ACTIONS_RUNTIME_TOKEN`, `ACTIONS_RESULTS_URL`, `ACTIONS_CACHE_URL` -
by blanking them in the agent step's `env:`. **That blank was ineffective and
has been removed.** Read in actions/runner at the pinned behaviour:
`NodeScriptActionHandler.cs` copies the step env first and THEN sets those
tokens (its `ScriptHandler.cs` sets only the id-token request vars, and only
when `id-token` is granted). So a step-level blank cannot override the runner's
own token for a Node step, and in any case the agent's OWN process never held
those tokens - the action passes the agent `{ ...process.env }` minus only the
two OIDC request vars (`base-action/src/parse-sdk-options.ts` at the pinned
commit), and the runner never put the artifact/cache tokens in the step
process's env to begin with. A blank that protects nothing is a false
assurance, so it is gone.

**The real vector is a shell.** Code the agent can run during the generate
job - or git the template makes run - can tamper with a file that a LATER Node
step in the same job executes, and that step (the action's own internals, its
setup-bun post step, the checkout post step, upload-artifact) holds the
runtime/cache token. Because this workflow is dispatched on the default branch,
a cache written there is readable by every branch's workflows: cross-workflow
cache poisoning. The template closes this by **denying the agent a shell
outright**: `build-dispatch.sh prepare` adds `--disallowedTools Bash` in every
`permissions` option, the agent step's `claude_args` carries it too, and the
"Read the flags" step - `build-dispatch.sh agent-args`, self-tested since B118 -
refuses to run the agent if the prepared flags do not deny Bash.
`check-ci-template.py` asserts the agent step declares the standalone deny
(`deny-bash`) and that the "Read the flags" step calls `agent-args` (`guards`). Measured 2026-10-11 against local `claude -p` 2.1.295:
denying Bash removes the built-in command tool, and the removal is honoured in
sub-agents too, so a `Task` cannot reach a shell either. Running the
repository's tests in CI is given up for this rule.

What the file and the checker cannot prove is that the CLI inside the action
really removes the Bash tool at run time; that is measured only against local
`claude -p`, not on a runner (B113).

**Git runs after the agent, so the capture uses a git the agent could not have
configured.** The post-agent steps run `git` in the same working tree. A
`filter.*.clean`, `core.fsmonitor`, `diff.*.textconv` or `core.hooksPath` entry
the agent could write into `.git/config`, `.git/hooks/*` or `.git/info/attributes`
would make the template's own `git diff` execute agent-chosen code - the shell
vector above, reached with no Bash. Measured 2026-10-11: under `acceptEdits`
with Bash denied the CLI refuses a `.git/**` write as a sensitive file and
refuses every write outside the working directory, so the agent cannot plant
such config in the first place. On top of that guard the template takes a
structural measure: `build-dispatch.sh stash-git` moves `.git` OUT of the
agent's working directory before the agent runs, to a path under `RUNNER_TEMP`
the CLI's edit tools cannot reach, and `build-dispatch.sh capture` computes the
patch against that stashed git-dir with the system and global config out of
reach (`GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`), attributes
neutralised (`GIT_ATTR_NOSYSTEM=1`, `GIT_ATTR_SOURCE` at the empty tree),
`core.fsmonitor` and `core.hooksPath` pinned off, and `--no-ext-diff
--no-textconv`. It refuses (exit 8) if a `.git` reappears in the working tree.
git itself never stages a nested `.git` and never emits a `.git` path in a
diff, so a replanted `.git` is caught by that existence check. Worktree
`.gitattributes` with config out of reach can still request `eol`, `ident` or
`working-tree-encoding`; measured 2026-10-11 these are content normalisations
that execute nothing, and `GIT_ATTR_SOURCE` at the empty tree neutralises them
anyway so the delivered bytes are verbatim. A `filter`/`textconv` driver needs
a config entry the relocation puts out of reach. The relocation and the capture
logic live in `build-dispatch.sh` (`stash-git`, `capture`), self-tested, not as
shell in the YAML.

**Nothing an unattended run executes after the agent comes from a place the
agent could have written** (R69, R70, added v4.67.2). The capture step is the
one post-agent `run:` in the agent's own job; it pins `BASH_ENV` and `ENV`
empty, so a shell reading the tree the agent edited sources no startup file an
agent-influenced environment could name, and it runs the copy of
`build-dispatch.sh` made under `RUNNER_TEMP` before the agent ran, never the
checkout the agent could edit. In `deliver`, `gh pr create` runs from the
repository root - the checkout at the default-branch tip - not from the worktree
the patch was applied into; the branch is already on origin and `--base`/`--head`
name it, so `gh` needs nothing from the applied tree. The git that does run
there uses `--git-dir`/`-C` against the committed configuration the worktree
shares, which the patch cannot write, and `stage-advance.sh` refuses a patch
carrying `.gitattributes` or anything under `.github` before `git apply`. And
`pr-spec-comment.sh`, which renders the body, reads the Stage 5 result with an
isolated interpreter (`python3 -I` and a `sys.path` scrub) so a `json.py`
planted beside the result cannot be imported in place of the standard library -
measured defense in depth, since the body is rendered from the default-branch
tip, not the agent's tree - and since v4.67.3 in `prepare`, not `deliver`. `check-ci-template.py` asserts the `BASH_ENV` pin
(`post-agent-env`) and `build-dispatch.sh` self-tests the `gh` working directory
(`gh-ran-at-repo-root-not-the-worktree`); that a real runner honours the pin is
unmeasured (B121).

**The job that can write runs no code from the repository it writes to** (R71,
added v4.67.3). The pull request body is the one artifact that needed the
repository's own code: `pr-spec-comment.sh` runs the repository's solver probe.
It is rendered in `prepare` (`--body-out`), which holds no write token and runs
before the agent, from HEAD and the spec delta - nothing the agent produces is
an input - and travels to `deliver` as its own artifact, `productizer-body`,
which the agent's job never downloads. `deliver` treats it as text: it refuses
a body whose recorded HEAD is not the HEAD it is delivering onto or that is over
60000 bytes (both exit 7, nothing pushed), appends the run's trailer line, and
passes it to `gh pr create --body-file`. What `deliver` then runs while holding
the write token is: `actions/checkout` and `actions/download-artifact` (pinned
by commit); `git` against the repository's committed configuration, with
`core.hooksPath=/dev/null` and `--no-verify` wherever a hook could fire
(`worktree add`, `commit`, `push`); `gh pr create`, from the repository root;
`python3 -I` heredocs that are the scripts' own code reading `config.json` as
data; and productizer's own scripts - `build-dispatch.sh`, `stage-advance.sh`,
`spec-requirements.sh`, `req-trailer.sh` - which are not the adopter's code:
they come from `PRODUCTIZER_SHA`, are checked at run time to be exactly that
commit with nothing added or changed, and are copied to `$RUNNER_TEMP` before
they run, so a `.productizer-tools` directory in the repository being written to
cannot stand in for them. `check-ci-template.py` holds the YAML half of that
(`write-job-no-repo-code`) and `build-dispatch.sh`'s self-test the script half
(`deliver-ran-no-repository-code`: a probe that leaves a mark ran in prepare and
in no deliver case). Unmeasured on a runner: that GitHub artifacts cannot be
replaced by a later job (B121).

### Inputs

| Input | Type | Meaning |
|---|---|---|
| `mode` | choice: `plan`, `build` | `plan` writes the issue's `plan.md`; `build` implements a committed plan |
| `issue` | number | the issue the run serves. It names the branch and the plan path. Its text is **not** read, so it never reaches the prompt |
| `spec_base` | optional string | a full 40-character commit id to diff the spec against. `build-dispatch.sh` checks the format |
| `permissions` | choice: `repo-settings` (default), `edits-only` | how much of the repository's committed Claude Code settings the agent gets. It can only narrow them. See [Permissions](#permissions) |

There is no free-text skill or model input. The model and effort come from
`models.build` in `.claude/productizer/config.json`, for both modes:
config.json has no plan key, and `plan.md` is Stage 3 work
(`references/models.md`, row "3 build"). `inherit` passes no flag, so the
action's default model runs. `cheap` is refused, because no model is named
`cheap` in CI.

### The base the spec is diffed against

`spec_base` when it is given. Otherwise the base is the first parent of the
newest commit in the default branch's first-parent history that changed
`spec.md` or `constitution.md`. That is the state of the branch just before the
spec change was merged. When a later, unrelated spec change has been merged
since, pass `spec_base` explicitly. The diff then reaches the agent exactly as
`references/build-diff.md` describes it.

### The plan path

The plan path is `artifacts.path` from config.json with `<slug>` replaced by
`issue-<N>`, followed by `/plan.md`. With the default, that is
`docs/sdlc/issue-<N>/plan.md`. Plan mode writes the plan there, and build mode
refuses (exit 5) unless the plan is committed there.

### What `deliver` asks `stage-advance.sh`

| Mode | Asked | Evidence it needs | What it forbids |
|---|---|---|---|
| `plan` | `design -> build --mode plan` | a `plan.md` under `artifacts.path` | every path except the plan |
| `build` | `build -> test --mode build` | a path outside `artifacts.path` (a plan alone is not a build), and never the backlog | the spec, plus the forbidden set below |

**The forbidden set, every mode.** It is written once, in `forbidden_any_mode()`
in `stage-advance.sh`, and matched on the folded key described below it:

- `.github/**`: every workflow, composite action, `CODEOWNERS` and
  `dependabot.yml`, all of it.
- `.claude/**`, default-deny: settings, hooks, agents, commands, skills, and
  every rule under `.claude/productizer/` (`checks.yaml`, `calibration.yaml`,
  `constitution.md`, `config.json`, and whatever is added later). The
  exceptions are the lifecycle's bookkeeping, `.claude/productizer/backlog.md`,
  and the spec outside build mode. A nested `*/.claude/**` has no exceptions.
- At any depth: `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `.mcp.json`,
  `.gitattributes`, `.gitmodules`.
- At the root: `.git/**`, `.husky/**`, `.githooks/**`,
  `.pre-commit-config.yaml`, `lefthook.yml`, `.lefthook.yml`,
  `lefthook-local.yml`, `.lefthook-local.yml`, `CODEOWNERS`,
  `docs/CODEOWNERS`, `REVIEW.md`, `.productizer-run/**`,
  `.productizer-tools/**`.

Names are matched on a folded key (format characters removed, NFKC, Unicode
case folding), so a variant a case- or normalisation-insensitive checkout folds
onto a rule file is refused; exceptions are granted on the exact bytes only. A
symbolic link created or retargeted, and a gitlink added, repointed or removed,
is refused at any path. In build mode the backlog may gain an item but not lose
or change one.

These decide what CI runs, what an agent is told and may do, how git treats a
path, and what the run is judged by. Because the set is checked first, an
`artifacts.path` under `.claude/` or `.github/` cannot hold a plan an
unattended run may write.

**Bookkeeping may be added, never erased.** The lifecycle's own bookkeeping -
`.claude/productizer/snapshots/**`, `.claude/productizer/classifications/**`,
`.claude/productizer/checks-result.json` - is "nothing" when it is ADDED, so a
run that produced only bookkeeping produced nothing to advance on. A DELETION
of one of those records is a different act: a classification, a snapshot or the
checks result is an audit record the governance checks read, and a run that
erases one can flip a check from a finding to clean. So a deletion of a
bookkeeping path is refusal 3 in every mode, exactly as editing a rule file is;
a stage run is the wrong actor to erase the record it is judged by. A snapshot or
a classification MODIFIED is refused too: their writers never overwrite one. The
checks result is rewritten by every `run-checks.sh` run, so its modification
stays 'nothing'.

**The patch text is never parsed.** `stage-advance.sh --patch` has git apply
the patch to a scratch index read from `HEAD`, in a temporary object
directory, and judges git's own `diff-tree` of the result. The paths judged
are the paths `git apply --index` writes. A header reader misses some of
those paths. `stage-advance 1.0` read the headers, and each of these shapes was
measured passing it while git wrote a workflow or `checks.yaml`:

- `diff --git` names whose a/ and b/ sides differ, with no rename lines
- hunk headers that name a different file from the `diff --git` line
- a traditional `---`/`+++` section after a git section
- a CRLF header
- a tab-suffixed name

`deliver` then asks a second time, with
`--base HEAD --head <the commit it made>`, so the decision that gates the push
is made on what was actually committed. A patch git cannot apply to `HEAD` is
exit 4, and a path holding a control character (newline, tab, carriage return)
is exit 4. `deliver` relays either as exit 6.

`intent -> design` was rejected for plan mode. Design's evidence is a
requirement record that moved, and plan mode is forbidden to touch the spec,
so that question could only ever be answered "produced nothing".

## Permissions

**The ruling (maintainer, 2026-10-10).** The agent's permissions are "what is
defined in the UI", which means two things:

- **By default, the repository's own Claude Code settings apply.** The agent
  gets the permission rules the owner committed: the allow and deny lists in
  `.claude/settings.json` (and in `.claude/settings.local.json` if one is
  committed), and their `permissions.defaultMode`. The template hardcodes no
  bypass.
- **The Run-workflow form can only narrow those settings.** The person who
  dispatches the run picks a `permissions` choice, and no choice widens what
  the settings grant.

| Option | What reaches the agent | What it allows |
|---|---|---|
| `repo-settings` (default) | the committed settings. When they set **no** `defaultMode`, `--permission-mode acceptEdits` is added. When they set one, no mode flag is passed. **Always `--disallowedTools Bash`** (maintainer ruling 2026-10-11, never a shell in CI) | file edits in the checkout; any non-shell tool the committed allow list grants (but see the trust caveat below); nothing the deny lists name; **no shell** |
| `edits-only` | now **identical** to `repo-settings` and kept only as an alias: the shell denial that once distinguished it is unconditional | the same: file edits, no shell |

**Why `acceptEdits` is added, and only when no `defaultMode` is committed.**
A headless run with no permission mode denied the one file write it was asked
to make (measurement m1 below). This stage's whole output is file edits, so
without a mode it would produce nothing, every time. `acceptEdits` grants file
edits and nothing else: the Bash calls in m8 and m9 still went through the
deny lists. When the owner commits a `defaultMode`, that is their decision
about edits, and no flag overrides it.

**`read-only` was dropped.** It was meant as "no edits except the plan file".
That cannot be written as a narrowing permission rule, because a deny beats an
allow. With `--disallowedTools Write --allowedTools "Write(plan.md)"`, the
agent reported the Write tool disabled for the session, and `plan.md` was not
created (m10). Plan mode is already confined to the plan file after the fact:
`stage-advance.sh` refuses any other path in plan mode.

**If the owner commits `defaultMode: bypassPermissions`,** that is the
owner's choice, and it is passed through unchanged. `build-dispatch.sh` prints
a WARNING and never produces the value itself. `check-ci-template.py` fails any
template that contains it. But since v4.67.1 **a committed bypass no longer
grants a shell**: the unconditional `--disallowedTools Bash` is a flag deny,
and a flag deny beats a committed mode (measured in m8, m9). Understand what it
still means before choosing it:

- the agent runs any non-shell tool the deny lists do not name
- it has the API key in its environment
- it reads the spec diff, and text your committers wrote is text the model
  will treat as instructions

A prompt injection in the spec, or in any file the agent reads, can then do
whatever the agent's remaining tools allow. The job's token cannot write to the
repository, and the agent has no shell, but the key can still be read and, if a
committed MCP server or an allowed tool can reach the network, sent anywhere.

The shell is denied in every option, a committed bypass included, so the
`edits-only` alias no longer narrows anything further.

### What was measured, and what was read

**Read in the action's source** at the pinned commit `1d6de8cb…`:
- `base-action/src/parse-sdk-options.ts` sets `settingSources` to
  `["user", "project", "local"]` unless `--setting-sources` is passed. It
  passes `--permission-mode` through to the CLI. It accumulates every
  `--disallowedTools` occurrence into one list.
- The SDK `query()` call in `run-claude-sdk.ts` sets no `cwd`, so the CLI runs
  in the step's working directory, which is the checkout.
- `setup-claude-code-settings.ts` writes only the user file
  `~/.claude/settings.json`. It adds `enableAllProjectMcpServers: true` and the
  action's `settings` input; this template passes no `settings` input.
- `run.ts` restores `.claude/` from the base branch only for pull-request
  events. Its comment says ".claude/ and .mcp.json in the checkout are
  attacker-controlled". This workflow is `workflow_dispatch` on the default
  branch, so the checkout's own `.claude/` is what the CLI reads.
- The action installs Claude Code `2.1.296`.

**Measured locally** on 2026-10-10. These ran `claude -p` 2.1.295 with haiku
and `--setting-sources project,local` (to mirror a runner, whose user settings
hold nothing), in fresh temporary repositories, reading `permission_denials`
and the files left behind:

| # | Committed settings | Flags | Result |
|---|---|---|---|
| m1 | none | none | Write **denied**, no file |
| m2 | `allow: ["Write"]` | none | Write **denied**. The CLI printed "Ignoring 1 permissions.allow entry from .claude/settings.json: this workspace has not been trusted" |
| m2b | `allow: ["Write"]` | none, with `CI=true GITHUB_ACTIONS=true CLAUDE_CODE_ACTION=1` | the same: allow ignored, Write denied |
| m3 | none | `--permission-mode acceptEdits` | file written |
| m4 | `deny: ["Write"]` | `--permission-mode acceptEdits` | Write unavailable, no file: the committed deny beat the flag |
| m5 | `defaultMode: acceptEdits` | none | file written: the committed mode was honoured |
| m6 | `defaultMode: bypassPermissions` | none | Write **denied**: the committed bypass was **not** honoured in an untrusted workspace |
| m7 | `defaultMode: default` | none | Write denied |
| m8 | `deny: ["Bash(echo:*)"]` | `--permission-mode bypassPermissions --disallowedTools "Bash(git:*)"` | `echo` and `git status` denied, `ls` ran: the committed deny and the flag's deny **combine** |
| m9 | none | `--permission-mode bypassPermissions --disallowedTools "Bash(git:*)" --disallowedTools Bash` | every Bash call refused, because the tool was removed |
| m10 | none | `--permission-mode acceptEdits --disallowedTools Write --allowedTools "Write(plan.md)"` | Write disabled, no `plan.md`: no carve-out |

**What this means, stated plainly:**
- **Allow lists are ignored on a runner.** In these measurements a committed
  allow list was ignored, because a fresh checkout is a workspace nobody has
  trusted. The committed deny lists and a committed `defaultMode: acceptEdits`
  were honoured. So under `repo-settings` the agent can edit files but, unless
  something else grants it, it cannot run your tests. That is narrower than
  the settings say. It never errs wider.
- **The action's own path was not measured.** It runs the CLI through the
  Agent SDK, not `claude -p`, on 2.1.296, not 2.1.295. Whether the SDK path
  applies the same trust gate is unknown. If it does not, the committed allow
  list and a committed bypass would both take effect. That is still exactly
  what the owner committed.
- **No workaround is shipped.** The template does not mark the workspace
  trusted. Doing so would widen the run beyond what was measured, and it would
  also switch on the repository's hooks and MCP servers.

## `build-dispatch.sh`

```
build-dispatch.sh prepare [repo-root] --mode plan|build --issue N
                          --default-branch NAME --out DIR [--spec-base SHA]
                          [--permissions repo-settings|edits-only]
                          [--body-out DIR]
build-dispatch.sh agent-args [repo-root] --out FILE
build-dispatch.sh stash-git [repo-root] --git-dir DIR
build-dispatch.sh capture [repo-root] --git-dir DIR --out FILE
build-dispatch.sh deliver [repo-root] --mode plan|build --issue N
                          --patch FILE --body DIR --run-id ID
                          --default-branch NAME [--spec-base SHA] [--dry-run]
```

`agent-args` is the last check on the flags the agent runs with, in the
`generate` job before the agent step. It re-reads `.productizer-run/claude-args`
(prepare's output, fetched as an artifact) and refuses it - exit 3 - unless
every line is one of the fixed shapes prepare writes (`--model <id>`,
`--effort <level>`, `--permission-mode acceptEdits`, `--disallowedTools Bash`),
no flag repeats, and the Bash deny is present. Only then does it append the
lines it checked, not the file as it stands, to `$GITHUB_OUTPUT` as
`claude_args` under a random heredoc delimiter. Until B118 this was shell inside
the template's YAML, which no self-test ran, and a last line with no newline
was never read by its loop yet still emitted: measured against the v4.67.4
step, a file ending in an unterminated `--permission-mode bypassPermissions`
passed the check and reached the step output. The self-test drives every
`claude-args` its own `prepare` cases wrote through `agent-args`, so the two
sets of shapes cannot drift apart.

`stash-git` moves the working tree's `.git` out to `DIR` (which must be outside
the tree) before the agent runs; `capture` computes the patch against that
stashed git-dir with the agent's version-control settings out of reach. Both
run in the `generate` job around the agent step.

| Exit | Meaning |
|---|---|
| 0 | ok, or the dry run printed what it would have pushed and opened |
| 2 | usage, including a `--spec-base` that is not 40 lower-case hex digits or does not resolve, and a `--permissions` value outside `repo-settings` and `edits-only` |
| 3 | the repository cannot be read as needed: not a work tree, a shallow clone, an unreadable `config.json` or Claude Code settings file, `HEAD` is not the default-branch tip, (`stash-git`/`capture`) the git-dir could not be moved or read, or (`agent-args`) the prepared `claude-args` are missing, hold a line outside the fixed shapes or a repeated flag, or lack the Bash deny |
| 4 | the spec is unchanged against the base. The run stops before any model call |
| 5 | build mode, and no plan is committed at the plan path |
| 6 | refused by `stage-advance.sh`, on the patch or on the commit made from it, whose reason is relayed verbatim. The branch is deleted and nothing is pushed |
| 7 | delivery failed after the decision. The step is named: the body (missing, rendered for another HEAD, or over the 60000-byte cap), the branch, the commit, the push or `gh` |
| 8 | `capture` refused: a `.git` reappeared in the working tree after `stash-git` moved the real one out |

`spec-diff.sh` exits 5 (no baseline) and 7 (over the cap) do not stop the run.
The line it printed goes to the agent as written, as `build-diff.md`
prescribes. Its exit 6, a base that does not resolve, is a usage error here.

`prepare --body-out` renders the pull request body, before the agent runs and
in a job with no write token: the renderer, `pr-spec-comment.sh`, runs the
repository's own solver probe when one exists. `deliver` renders nothing; it
reads that body as text (see "The job that can write runs no code from the
repository it writes to" above). The body is that report, followed by the
sentence saying the pull request is a proposal to be reviewed, and the line
`Productizer-Run: <run id>`.

The commit carries `Productizer-Req:` with the requirement ids whose records
differ between the spec at the base and the spec at `HEAD`, as read by
`spec-requirements.sh`. **The ids never come from the model.** It also carries
`Assisted-by: LLM` (via `req-trailer.sh`) and `Productizer-Run:`. When the
delta names no requirement id, the commit carries no `Productizer-Req:` line
and the log says so.

`--selftest` runs everything under `mktemp -d` against a local bare
"origin", with a stub `gh` first on `PATH`. It covers both a dry run and a
real push-and-open. It never touches the network.

## `check-ci-template.py`

`check-ci-template.py` makes static assertions over the template, or over any
workflow given as a path:

- the only trigger is `workflow_dispatch`, and there is no `pull_request_target`
- the top-level permissions are exactly `contents: read`
- write permissions appear only in `deliver`
- the agent job holds no write, and its checkouts set `persist-credentials: false`
- the step that runs the agent action denies the agent a shell: its
  `claude_args` carries a standalone `--disallowedTools Bash` (`deny-bash`)
- every `run:` step after the agent action, in the agent's own job, pins
  `BASH_ENV` to the empty string, so a post-agent shell reading the tree the
  agent edited sources no file an agent-influenced environment could name
  (`post-agent-env`)
- a job holding any write permission runs no code from the repository it writes
  to: no local action, no run: naming an interpreter or package runner (python,
  python3, node, bun, deno, ruby, perl, php, npm, npx, yarn, pnpm, make) or
  `pr-spec-comment.sh`, no sourced file or `./` path, and every `bash`/`sh`
  runs a script staged under `$RUNNER_TEMP` (`write-job-no-repo-code`). It reads
  the run: text, so an interpreter a staged script itself starts, or a command
  spelled through a variable, is not seen
- every `uses:` is pinned to a full 40-character commit id
- no `${{` expression of any context inside a `run:` (`run-injection`):
  `github.event` and `inputs`, and since B119 also `steps`, `needs`, `env`,
  `matrix`, `github.head_ref` and the rest, any of which can carry
  attacker-influenced text into the shell. Every value reaches a `run:` through
  `env:`. The template's own `${{ steps.args.outputs.claude_args }}` reaches
  the action's `claude_args:` input, not a `run:`, so it is not caught
- no `continue-on-error`, `|| true` or `2>/dev/null`
- neither `bypassPermissions` nor `--dangerously-skip-permissions` appears
  anywhere outside a comment
- a `permissions` input of type choice, default `repo-settings`, with options
  drawn only from `repo-settings` and `edits-only`
- `PRODUCTIZER_SHA` in the top-level `env` is a quoted string of 40 lower-case
  hex digits - the all-zero placeholder or a full commit id - and every
  checkout of the productizer tools uses `ref: ${{ env.PRODUCTIZER_SHA }}`
  (`tools-pin`, B107). An unquoted all-digit value is a YAML number and is
  refused. When the value is the placeholder, the checker prints a note saying
  the workflow will refuse to run and how to pin it
- the runtime guards are in place, as the exact lines the template ships
  (`guards`, B118): prepare's first step refuses a dispatch off the default
  branch and an unpinned `PRODUCTIZER_SHA`; in the agent's job a step with id
  `args` calls `build-dispatch.sh agent-args` before the agent, the agent's
  `claude_args` reads its output, a step between them copies
  `build-dispatch.sh` to `$RUNNER_TEMP` and stash-gits `.git` there, and a step
  after the agent removes the run data and captures from that copy with the
  same git-dir; in every write job, the step that checks the tools checkout is
  `PRODUCTIZER_SHA` with nothing changed and stages it under `$RUNNER_TEMP`
  comes before any step that runs the staged copy. Lines are matched in order,
  with whitespace and comments ignored, not as control flow: a guard line made
  unreachable by an earlier `exit 0` is not seen. The tools-verification step
  stays YAML on purpose - it decides whether the productizer scripts may run,
  so it cannot be one of them

Exit 0 means every assertion held, 1 means a finding, and 2 means it could not
run. It returns 2, not 0, when no job runs the agent at all: an assertion
nobody could evaluate is unmeasured, not clean. `--selftest` runs over
`fixtures/ci-template/`, which holds one good workflow and one copy per
violation, each differing from the good one by a single change. Re-run it on
your copy after every edit.

## Adopting it

1. **Copy** `templates/build-from-spec.yml` to
   `.github/workflows/build-from-spec.yml`.
2. **Pin the scripts.** Set `PRODUCTIZER_SHA` to the full commit id of the
   productizer release you reviewed. The shipped placeholder, forty zeros, is
   refused by the first step, which says why and how to pin. A template cannot
   carry its own commit id, so this value is the one thing you fill in. For
   release `vX.Y.Z`:

   ```
   git ls-remote https://github.com/gitayg/productizer 'refs/tags/vX.Y.Z^{}'
   ```

   prints the commit id to use. Keep the `^{}`: release tags are annotated,
   and without it `git ls-remote` prints the id of the tag object, not of the
   commit it names (measured on `v4.65.1`: `refs/tags/v4.65.1` is the tag
   object `d669edc…`, `refs/tags/v4.65.1^{}` the commit `d9573c0…`). Keep the
   value quoted. Then run `check-ci-template.py` on your copy: its `tools-pin`
   assertion refuses anything but 40 lower-case hex digits.
3. **Set the secret.** Add `ANTHROPIC_API_KEY` as a repository secret.
4. **Protect the default branch.** Require a pull request review before
   merging, and require your status checks. The draft pull request is a
   proposal. Branch protection is what stops a proposal from merging without a
   person.
5. **Review your committed Claude Code settings.** `.claude/settings.json`
   is what the agent gets: its deny lists and its `defaultMode`. Add denies
   for anything an unattended agent must never run. See
   [Permissions](#permissions).
6. **Dispatch it** from the Actions tab or with
   `gh workflow run build-from-spec.yml -f mode=plan -f issue=<N>`, from the
   default branch. The shell is denied in every run; `-f
   permissions=edits-only` is accepted as an alias of `repo-settings`.

## Known limitations, stated plainly

- **Your checks will not run on its pull request by themselves.** A pull
  request opened with the workflow's `GITHUB_TOKEN` does not trigger
  `pull_request` workflows. That is GitHub's rule against recursive runs. The
  adopter's checks therefore do not start until a person pushes to the
  branch, unless `deliver` authenticates as a GitHub App instead. With branch protection that requires
  those checks, the pull request cannot merge until they have run.
- **The whole Bash tool is denied, not just git.** Since v4.67.1 the agent
  gets `--disallowedTools Bash` in every option (maintainer ruling, never a
  shell in CI). Measured 2026-10-11 against local `claude -p`: the tool is
  removed, in sub-agents too, so the `sh -c` escape that defeated the old
  `Bash(git:*)` deny has no shell to reach. A command-executing MCP tool from a
  committed `.mcp.json` is the residual (R67 is `Partial`): the action sets
  `enableAllProjectMcpServers`, so an adopter who commits such a server gives
  the agent that path. The token is still a boundary too: the agent job cannot
  write, and `deliver` judges the commit git made, not the patch text.
- **Build mode needs evidence outside the plan, not proof of code.** Since
  `stage-advance.sh` 1.2, `build -> test` refuses a run that changed nothing
  outside `artifacts.path` or changed only the backlog, so a run that rewrote
  only `plan.md` no longer opens a pull request. Any other path still counts,
  so a run that edited only a README does.
- **The agent cannot run your tests, by design.** The no-shell rule removes the
  Bash tool, so build mode edits code without running it. Your checks on the
  pull request are what verify it, and they run only once a person pushes
  (first item). This is a deliberate trade for keeping a shell out of CI.
- **Whatever permissions apply, the model reads text your committers wrote.**
  It has the API key in its environment and reads the spec diff. Treat the
  spec as instructions the model will see.
- **A moved default branch stops delivery.** If the default branch gained a
  commit after the run was dispatched, `deliver` exits 3 rather than push a
  change made against an older tree. Dispatch the run again.
- **It has never run end to end here.** This repository is public, holds no
  model secrets, and a run costs model spend. What is measured is the
  template's static properties (`check-ci-template.py`, 14 of 14, actionlint
  1.7.12 clean), and all of `build-dispatch.sh` - `prepare`, `stash-git`,
  `capture`, `deliver` - against local repositories with a stub `gh`. The
  action's real behaviour inside GitHub Actions, that it tolerates its `.git`
  being moved out before it runs, its setup-bun post step writing no cache, the
  CLI removing the Bash tool, the artifact hand-offs and a real `gh pr create`
  are not measured (B121).
