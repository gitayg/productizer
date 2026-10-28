# Stage 0 in full: bind, scaffold, import, schedule

Read this before Stage 0 runs, and before the first stage that touches Jira or
GitHub, scaffolds a file, imports an existing repo or installs a scheduled task.
SKILL.md keeps the rules of this stage; this is the stage as a whole, with the
reasons.

## Stage 0 · Bind, scaffold, schedule

Before the first stage touching Jira or GitHub, run
`~/.claude/skills/spec/scripts/detect-context.sh` and resolve every setting
first hit wins: **detected → `.claude/productizer/config.json` → ask → environment → fail
loudly.** Read `references/integrations.md` before the first external write.

- **One spec per product, not per repo.** A product is one or more repos
  (`.claude/productizer/config.json` → `product`); exactly one is the **spec home** and the
  rest point at it, so there is one id space and one allocator. Two allocators
  both hand out `R42`, and contradiction detection needs the whole agreed set —
  split it and a front end and its API can agree opposite behaviour unnoticed.
  **If the spec home is unreachable, intake cannot run**: stop and say so.
- **Ask once per repo**, in one `AskUserQuestion` call, on the first stage
  touching an external system. Detection prefills but never replaces the
  question, and every question needs an escape hatch: a half-answered config is
  still finished. Answers go to `.claude/productizer/config.json`
  (`templates/config.json`); name the path.
- **Never ask where nobody is present.** Gate on the detected `interactive`
  flag, not the stage number: nightly evals (4) and the band check (9) run as
  scheduled tasks with no memory of any conversation, so they read
  `.claude/productizer/config.json` and, if it is missing, report what they need and stop
  rather than prompting.
- **A `rejected` check runner is a finding, not a shrug** — say what it rejected
  and why. A repo setting `SDLC_CHECK_RUNNER` is choosing what runs on the
  cloner's machine, so the probe validates before executing.
- **Secrets never enter the config file**, which is committed: `JIRA_API_TOKEN`
  comes from the environment. Never ask for a token in chat, never write one to
  disk.

### Scaffold
Once, right after binding, and **never overwrite a file that exists**. Repo
templates in `.claude/productizer/templates/` win over this skill's; **say when an
override is in play**, or a spec not matching the documented shape reads as a
bug.

**Scaffold with `scripts/scaffold.sh <template> <destination>`, not `cp`.** The
templates carry worked examples — `R1`…`R6` in the spec, `P1`…`P5` in the
constitution — so a human can see the shape. Copying them verbatim seeds a repo
with requirements and principles nobody agreed to, which is the one thing this
lifecycle cannot tolerate. The script strips the fenced example block, refuses
to overwrite, and refuses a gitignored destination.

| File | Written as |
|---|---|
| `.claude/productizer/spec.md` | `scripts/scaffold.sh templates/spec.md …` — empty, system named, next id `R1` |
| `.claude/productizer/constitution.md` | same, and left with **no principles**: the first ones are ratified, never scaffolded |
| `REVIEW.md` | `templates/REVIEW.md` as-is, at the repo root |
| `CLAUDE.md` | only if absent, cut to what is true of this repo |

Nothing else: bands, evals and hooks wait for something real to watch or gate.
**An empty spec is the correct starting state** — a seeded `R1` is a requirement
nobody agreed to, and gets cited before anyone notices.

**Check the spec path is committable before writing it** — `.claude/` is
routinely gitignored, so the **bare** `git check-ignore .claude/productizer/spec.md`
must exit non-zero. Do not take the verdict from `-v`: it exits 0 whenever *any*
rule matches, **including a negation**, so a repo that correctly re-included the
path with `!.claude/productizer/**` reads as ignored and gets refused. Use `-v`
only to name the offending rule once the bare form has already said no. Exit 128
means git could not tell, which is a third answer and not a pass. A scaffold
reporting success while the spec stays untracked leaves an audit trail that
looks present and is not. Report what you wrote, what you skipped and any
gitignore edit.

### Import an existing repo (0c)
A repo with history and no spec starts from evidence, not memory. Run
`scripts/import-survey.sh <repo>` — read-only, one pass — and draft at most 30
requirements from what it found (`templates/import.md`). **Every imported
requirement lands `inferred` and unconfirmed**, carrying the file, line or test
it came from; only a human promoting one makes it active, and that promotion is
a commit. Inferred requirements cannot trigger the Stage 2 halt, or the
lifecycle starts defending whatever the code happened to do on import day, bugs
included (`references/import.md`).

### Schedule
Install once per repo, after `.claude/productizer/config.json` exists
(`references/running-it.md`): `sdlc-evals-<slug>` from
`templates/scheduled-evals.md` once `evals/` holds an eval, and
`sdlc-bands-<slug>` from `templates/scheduled-bands.md` once `ops/bands.yaml`
does, and one `sdlc-bands-<slug>-<metric>` from
`templates/scheduled-band-metric.md` for each band bound under `band_bindings`.

- **Always `list_scheduled_tasks` before creating**, and update rather than
  recreate: a second task under a new id silently doubles the nightly run.
- **Refuse to install an eval task with no evals.** An empty suite reports green
  every night, manufacturing evidence that nothing regressed. Say so, and offer
  to build the first from real tasks.
- **A SessionStart hook makes the state resident** — which stage, which ids are
  open, what is unruled — so a new session reads it instead of re-deriving it
  (`templates/session-start.sh`, `templates/hooks-settings.json`,
  `references/session-start.md`). It must stay fast and fail open: a hook that
  errors on a repo with no spec blocks every session in it.
- Warn once: **tasks only run while the desktop app is open**, so an hourly band
  check has holes on days it stays shut; gap-intolerant metrics need CI.
