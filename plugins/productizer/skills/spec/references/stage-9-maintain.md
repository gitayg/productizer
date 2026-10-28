# Stage 9 in full: maintain, and the drift loop

Read this before Stage 9 handles a band finding or a spec-versus-code drift
finding. SKILL.md keeps the rules; this is the stage as a whole.

### 9 · Maintain — close the loop
Detection is deterministic — no model in that path — tiers in version-controlled
config (`templates/bands.yaml`): 1σ log, 2σ diagnose read-only, 3σ act via PR or
pre-approved runbook. A finding is **opened as an issue**, the same door Stage 1
uses, carrying the anomaly, the evidence, the proposed outcome and the open
questions, and goes through intake like any other intent, which stops a
production signal silently contradicting the spec. Dismissals tune the bands;
when a fix ships, add the eval. A human triages it.

**More than one band: one file, one binding, one task each** (B171, v4.75.0).
The first band is `ops/bands.yaml`, bound by `bands` in
`.claude/productizer/config.json` and run by the task from
`templates/scheduled-bands.md`; nothing about it changes when a band is added.
Each added band gets its own bands file, its own binding under `band_bindings`
and its own task from `templates/scheduled-band-metric.md`, which reads only
that binding and runs its command only when it matches the literal frozen into
that task. Two ship: **revert rate** (`templates/bands-revert-rate.yaml`,
`scripts/band-revert-rate.py`) - commits carrying a `This reverts commit` line
over changes merged, first-parent, in the last 30 days - and **review rounds
per change** (`templates/bands-review-rounds.yaml`,
`scripts/band-review-rounds.py`) - the mean rounds of the review records last
changed in those 30 days. Each prints its value, its baseline over the six
windows before and a `tier:` line the task acts on, and exits 3, not measured,
when there is nothing to measure or no baseline. Human effort per change is
cut only while the revert rate holds: the two bands are read together.

**Drift is the other loop** (`references/drift.md`, `templates/converge.md`):
the code and the spec disagree, and the answer is not automatically to update
the spec to match the code — that ratifies whatever shipped. A finding names
which side is wrong and opens a NEW work item that starts at intent, as a
Stage 9 finding does. It never moves an existing item back: stage moves are
forward-only (R55), so re-entering an item at Stage 1 is refused. Where a
spec lives when a product spans several repos, and what breaks when it is
split: `references/spec-stores.md`.
