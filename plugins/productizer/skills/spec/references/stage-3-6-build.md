# Stages 3 to 6 in full: build, test, check, deploy

Read this before Stage 3 plans a change, and before Stages 4-6 when they run
here rather than in a delegated check runner (`references/delegation.md`).
SKILL.md keeps the rules of these stages; this is them as a whole.

### 3 · Build — plan first, knowledge as files
- **Plan mode is not optional.** Read-only first, then `plan.md`
  (`templates/plan.md`) naming files, order of work, risks and proof,
  interrogated until an unfamiliar engineer could build from it. Commit it, then
  build.
- **`CLAUDE.md`** holds day-one knowledge under one page: when a mistake happens
  twice, the correction lands here. **Skills** carry inconsistently enforced
  policy; **hooks** what must be deterministic.
- **Parallel work** splits along files; tasks sharing one stay sequential, each
  in its own worktree.

### 4 · Test — verify before a human looks
- One command runs all checks, listed in `CLAUDE.md` with healthy example output
  and a quantifiable target (`templates/verification-section.md`).
- Bug fix: **write the failing test first and commit it before the fix.** A hook
  blocks test-file edits during the fix — the test is not the thing to fix.
- **Never report a task done without running the checks and pasting the
  output.**
- Agent config is regression-tested nightly, and every production incident earns
  a permanent eval. A schedule reports, it does not block — gating a merge needs
  CI (`templates/agent-evals.yml`).
- Keep refusal and crash distinguishable in the exit code, or a gate saying no
  reads like one that fell over and the wrong thing gets fixed.

### 5 · Check — the checks are declared, not built in

Declared in `templates/checks.yaml` and `references/checks.md`. Each names an id, an **argv** command — never a shell
string, since the file is committed and a string would let anyone landing a
commit choose what runs on the puller's machine — a `when` trigger of `always`,
path globs or **requirement tags**, `block` or `advise`, mapped exit codes, and
a mandatory **coverage** assertion. Tags are what makes scrutiny per-item: an
auth requirement earns the auth ruleset, a copy edit does not.
`scripts/run-checks.sh` runs them and fails closed seven ways — bad config,
missing tool, timeout, unmapped exit code, nothing triggered, and **hollow**: a
check that exited clean having examined less than it declared. That last one is
the point. A scanner reporting *Grade A (100/100)* after opening one file of
forty-eight is not a pass, and without a coverage assertion it is indent-for-
indent identical to one.

### 6 · Deploy — review both ways, gate hard
- Review policy is written down (`templates/REVIEW.md`) and **dispatched to a
  subagent with a clean context** (`templates/agent-reviewer.md`): the session
  that wrote the code never reviews it, because asked to it re-derives its own
  reasoning and calls that confirmation.
- **Resolve the diff base before any pass runs**, and state it: a wrong base
  makes every finding confidently wrong.
- **The agent never approves its own code.** Output arrives as a PR through
  branch protection; there is no route to push main. **Production is a hook, not
  a convention** (`templates/production-gate.sh`), and in regulated environments
  the non-negotiables live in `templates/managed-settings.json`, which engineers
  cannot override.
- **Secret checks go pre-push, not in CI.** A required check runs after the
  push, by which time the secret is on the remote and must be rotated: blocking
  a merge is the whole remedy for a bad base, and none at all for a secret.
