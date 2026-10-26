# Which model runs a stage, in full

Read this before saying which model or effort a stage runs on. The settings
themselves, and their recommended defaults, are in `references/models.md`.

## The nine stages

Each stage names a model and an effort in `.claude/productizer/config.json` under `models`,
shipped with recommended defaults you can change (`references/models.md`). The
block has two halves and they are not interchangeable: a stage beginning a
**fresh context** carries the setting in subagent frontmatter and it is
enforced; a stage running **in your session** inherits your session's model
whatever the file says, so the skill's job there is to say which stage it is
entering and let you choose. **Do not claim a stage runs on a model it does
not** — a preference nothing enforces is documentation, and documentation that
reads like a control gets budgeted against and trusted.

Stage 5 takes **no model at all**. It runs declared scripts and compares
coverage arithmetically; a model asked *did this check pass* believes the green
summary line, which is the failure the stage exists to prevent.
