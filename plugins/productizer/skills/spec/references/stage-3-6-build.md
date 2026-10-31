# Stages 3 to 6 in full: build, test, check, deploy

Read this before Stage 3 plans a change, and before Stages 4-6 when they run
here rather than in a delegated check runner (`references/delegation.md`).
SKILL.md keeps the rules of these stages; this is them as a whole.

### 3 · Build — plan first, knowledge as files
- **Plan mode is not optional.** Read-only first, then `plan.md`
  (`templates/plan.md`) naming files, order of work, risks, proof and how to
  revert it, interrogated until an unfamiliar engineer could build from it.
  Commit it, then build. `scripts/check-plan-record.py` fails a plan whose
  `Proof` or `Revert` is missing or still the placeholder, and with
  `--kind pr-body` a pull request body (`templates/pull-request.md`) missing
  *How it was tested*, *Proof it works* or *How to revert*. An agent may draft
  all three; the author answers for them.
- **Proof against the request, not the tests.** *Proof it works* is what a
  person sees when using the change the way a user would meet it: one list
  item per `R<n>`, `B<n>` or `#<n>` answered, each saying what it shows and
  carrying a screenshot, a recording, a fenced log or a link to a run's
  artifact. A change nobody using it can observe says `**n/a** - <reason>`
  alone. The reviewer reads it before the diff (`REVIEW.md`). The checker reads
  text; it cannot tell a real screenshot from a wrong one, and nothing in the
  lifecycle takes or uploads one.
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
  a permanent eval. **A revert or an incident becomes a reviewer case**
  (`templates/reviewer-case.md`, under `evals/reviewer/`): the change, the
  confirmed bug's `path:line`, the fix. `templates/agent-evals.yml` runs the
  reviewer on each case whenever its prompt, tools or model or `REVIEW.md`
  changes, and `scripts/score-reviewer-case.py` scores the record it prints
  with no model. A revert landing without a case fails the `revert-cases`
  check (`scripts/check-revert-cases.py`). A schedule reports, it does not
  block — gating a merge needs CI (`templates/agent-evals.yml`).
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
- **Every round is recorded and every finding answered.** The caller writes
  each round's findings into the change's review record
  (`templates/review-record.md`, beside `plan.md`): a `path:line`, a severity
  of Important, Nit or Pre-existing, the whole bug class, and a status of open,
  fixed, rejected, intentional or irrelevant with a reason. The `review-record`
  check (`scripts/check-review-record.py`) fails a record with an Important
  finding still open, so it blocks the stage; a waiver of that check is the
  only way past, and it still reads failed and waived. The tally of how
  findings were answered is the measure of the reviewer's noise.
- **Cap the rounds between an agent author and an agent reviewer.** A later
  round reviews only the diff since the last round's head and never re-reports
  a finding at the same location and class. After three rounds the author
  rethinks the approach instead of patching: a fourth round fails the record
  until its `Rethink:` line names the new approach. The cap holds the loop in a
  session; the CI build template runs no reviewer, so it has no loop to cap.
- **The agent never approves its own code.** Output arrives as a PR through
  branch protection; there is no route to push main. **Production is a hook, not
  a convention** (`templates/production-gate.sh`), and in regulated environments
  the non-negotiables live in `templates/managed-settings.json`, which engineers
  cannot override.
- **Secret checks go pre-push, not in CI.** A required check runs after the
  push, by which time the secret is on the remote and must be rotated: blocking
  a merge is the whole remedy for a bad base, and none at all for a secret.

### Approval rules for an agent-authored change
A setup step in the adopter's repository, not runner code: the lifecycle ships
the template and a check, and a person with admin rights sets the rules. On the
default branch, in branch protection or a ruleset:

- **Require a pull request review, and "Require review from Code Owners".**
  GitHub: a pull request "that affects code with a code owner must be approved
  by that code owner". Commit `templates/CODEOWNERS` as `.github/CODEOWNERS`,
  owning `.claude/productizer/` and `.github/workflows/` by a person or a team
  of people. `scripts/check-approval-rules.py` (the `approval-rules` check)
  fails a CODEOWNERS that leaves a file under either directory, or a file a
  change adds there, with no owner or only a bot.
- **Dismiss stale pull request approvals when new commits are pushed**, and
  **require approval of the most recent reviewable push**, so a new commit
  dismisses earlier approvals and the person who pushed last cannot approve it.
- **Do not let a bot approval stand for a person.** Keep "Allow GitHub Actions
  to create and approve pull requests" off where nothing needs it. The CI build
  template opens its draft with `GITHUB_TOKEN`, which needs that setting on,
  and the one setting covers both creating and approving; whether an approval
  by `GITHUB_TOKEN` counts toward required reviews is not stated in GitHub's
  documentation and was not measured here.
- **Do not allow bypassing the above settings**, administrators included.

None of these settings is in the tree, so `approval-rules` cannot see them and
says so on every run. Whether the person who dispatched an agent run counts as
a required reviewer of its pull request is an open question (B173).

**Productizer's own repository** commits `.github/CODEOWNERS`, owning both
directories to `@gitayg`, and runs `approval-rules` on itself (B178, v4.75.0).
The settings above are not changed by any release: turning on "Require review
from Code Owners" for its `main`, with the rest of the list, is a step the
maintainer takes on GitHub. Until then the file names an owner nobody is
required to hear from.
