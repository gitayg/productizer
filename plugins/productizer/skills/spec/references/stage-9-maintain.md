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

**Drift is the other loop** (`references/drift.md`, `templates/converge.md`):
the code and the spec disagree, and the answer is not automatically to update
the spec to match the code — that ratifies whatever shipped. A finding names
which side is wrong and opens a NEW work item that starts at intent, as a
Stage 9 finding does. It never moves an existing item back: stage moves are
forward-only (R55), so re-entering an item at Stage 1 is refused. Where a
spec lives when a product spans several repos, and what breaks when it is
split: `references/spec-stores.md`.
