# Building from the spec in CI — an optional, copyable workflow

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
| `prepare` | `contents: read`, checkout keeps no credentials | `build-dispatch.sh prepare`: decides whether there is anything to do, then writes the agent's data as files. **No model is called.** |
| `generate` | `contents: read`, checkout keeps no credentials | `anthropics/claude-code-action` with a fixed prompt, then `git add -N .` and `git diff --binary` into a patch |
| `deliver` | `contents: write`, `pull-requests: write` | `build-dispatch.sh deliver`: `stage-advance.sh` decides on the patch, then a new branch and a commit, then `stage-advance.sh` decides again on that commit, then a push and `gh pr create --draft`. **No model runs here.** |

A write token never sits beside the model. The agent job's only token is its
own read-only `GITHUB_TOKEN`, and that token is passed to the action
explicitly. Without it the action requests an OIDC token and exchanges it for
an app token that has `contents`, `pull_requests` and `issues` write. That was
read in the action's `src/github/token.ts` at the pinned commit. The agent job
does not grant `id-token: write`, so the exchange could not happen anyway.
Passing the token explicitly makes the intent visible rather than incidental.

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
| `build` | `build -> test --mode build` | any path outside the lifecycle's bookkeeping | the spec, plus the forbidden set below |

**The forbidden set, every mode.** It is written once, in `forbidden_any_mode()`
in `stage-advance.sh`, and matched on the path lower-cased, so a case variant
that a case-insensitive checkout would fold onto a rule file is refused too:

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

These decide what CI runs, what an agent is told and may do, how git treats a
path, and what the run is judged by. Because the set is checked first, an
`artifacts.path` under `.claude/` or `.github/` cannot hold a plan an
unattended run may write.

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
| `repo-settings` (default) | the committed settings. When they set **no** `defaultMode`, `--permission-mode acceptEdits` is added. When they set one, no mode flag is passed. Always `--disallowedTools "Bash(git:*)"` | file edits in the checkout; any tool the committed allow list grants (but see the trust caveat below); nothing the deny lists name |
| `edits-only` | the same, plus `--disallowedTools Bash` | file edits only. The Bash tool is removed outright, so the agent cannot run your tests |

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
template that contains it. Understand what it means before choosing it:

- the agent runs any tool the deny lists do not name
- it has the API key in its environment
- it reads the spec diff, and text your committers wrote is text the model
  will treat as instructions

A prompt injection in the spec, or in any file the agent reads, can then do
whatever a shell on the runner can do. The job's token cannot write to the
repository, but the key can still be read and sent anywhere.

`edits-only` narrows even an owner's bypass: the deny lists were honoured
under bypass mode in m8, and removing Bash took it away in m9.

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
build-dispatch.sh deliver [repo-root] --mode plan|build --issue N
                          --patch FILE --run-id ID --default-branch NAME
                          [--spec-base SHA] [--dry-run]
```

| Exit | Meaning |
|---|---|
| 0 | ok, or the dry run printed what it would have pushed and opened |
| 2 | usage, including a `--spec-base` that is not 40 lower-case hex digits or does not resolve, and a `--permissions` value outside `repo-settings` and `edits-only` |
| 3 | the repository cannot be read as needed: not a work tree, a shallow clone, an unreadable `config.json` or Claude Code settings file, or `HEAD` is not the default-branch tip |
| 4 | the spec is unchanged against the base. The run stops before any model call |
| 5 | build mode, and no plan is committed at the plan path |
| 6 | refused by `stage-advance.sh`, on the patch or on the commit made from it, whose reason is relayed verbatim. The branch is deleted and nothing is pushed |
| 7 | delivery failed after the decision. The step is named: the body, the branch, the commit, the push or `gh` |

`spec-diff.sh` exits 5 (no baseline) and 7 (over the cap) do not stop the run.
The line it printed goes to the agent as written, as `build-diff.md`
prescribes. Its exit 6, a base that does not resolve, is a usage error here.

Deliver renders the pull request body **before** the patch is applied anywhere.
The renderer, `pr-spec-comment.sh`, runs the repository's own solver probe when
one exists, and code the model wrote must never execute in the job that holds
a write token. The body is that report, followed by the sentence saying the
pull request is a proposal to be reviewed, and the line
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
- every `uses:` is pinned to a full 40-character commit id
- no `${{ github.event.` and no `${{ inputs.` inside a `run:`
- no `continue-on-error`, `|| true` or `2>/dev/null`
- neither `bypassPermissions` nor `--dangerously-skip-permissions` appears
  anywhere outside a comment
- a `permissions` input of type choice, default `repo-settings`, with options
  drawn only from `repo-settings` and `edits-only`

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
   refused by the first step, which says why. A template cannot carry its own
   commit id, so this value is the one thing you fill in.
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
   default branch. Add `-f permissions=edits-only` to take the shell away for
   that run.

## Known limitations, stated plainly

- **Your checks will not run on its pull request by themselves.** A pull
  request opened with the workflow's `GITHUB_TOKEN` does not trigger
  `pull_request` workflows. That is GitHub's rule against recursive runs. The
  adopter's checks therefore do not start until a person pushes to the
  branch, unless `deliver` authenticates as a GitHub App instead. With branch protection that requires
  those checks, the pull request cannot merge until they have run.
- **`Bash(git:*)` is a guard rail, not a boundary.** The deny rule matches
  commands that begin with `git`. Measured locally on 2026-10-10 with
  `claude -p --permission-mode bypassPermissions --disallowedTools "Bash(git:*)"`:
  the `git status` call was denied and recorded in `permission_denials`. A
  command that reaches git another way, such as `sh -c`, is not matched. The
  boundary is the token: the agent job cannot write, and `deliver` refuses a
  commit that touches what the stage may not. It judges the commit git made,
  not the patch text, so whatever text arrives as the patch, only what git
  applies is delivered.
- **Build mode accepts a patch that edits only the plan.** `build -> test`
  counts any non-bookkeeping path as evidence, so a run that rewrote only
  `plan.md` opens a pull request containing just that change. The reviewer
  sees it. Nothing refuses it.
- **The agent may be unable to run your tests.** On a runner the committed
  allow list was measured as ignored (see [Permissions](#permissions)), so
  build mode edits code without running it unless your settings say
  otherwise. Your checks on the pull request are what verify it, and they run
  only once a person pushes (first item).
- **Whatever permissions apply, the model reads text your committers wrote.**
  It has the API key in its environment and reads the spec diff. Treat the
  spec as instructions the model will see.
- **A moved default branch stops delivery.** If the default branch gained a
  commit after the run was dispatched, `deliver` exits 3 rather than push a
  change made against an older tree. Dispatch the run again.
- **It has never run end to end here.** This repository is public, holds no
  model secrets, and a run costs model spend. What is measured is the
  template's static properties (`check-ci-template.py`, actionlint 1.7.12
  clean), and both ends of `build-dispatch.sh` against local repositories with
  a stub `gh`. The action's real behaviour inside GitHub Actions, the artifact
  hand-offs and a real `gh pr create` are not measured.
