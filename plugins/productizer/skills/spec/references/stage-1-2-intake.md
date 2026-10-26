# Stages 1 and 2 in full: capture the intent, intake, merge the delta

Read this before Stage 1 captures an intent and again before Stage 2 classifies
one. SKILL.md keeps the rules of both stages; this is both stages as a whole,
with the reasons.

### 1 · Plan — capture the intent
Wanted-but-not-yet-agreed waits in `.claude/productizer/backlog.md`
(`templates/backlog.md`, `references/backlog.md`). It is the queue **in front
of** the lifecycle: `B`-numbered, ordered by priority with no priority field —
the order *is* the ranking — and nothing in it is binding, so an item can be
picked up and still refused at intake. Where an item names a Jira key, **Jira
owns its status** and nothing is ever written back.

An intent arrives as a **tracker item**, **text** or a **file**. Brainstorm with
the originator until it is concrete (`templates/intake.md`); one too vague to
classify is not ready, and you do not decide what they meant. Then open the
issue if it did not arrive as one: **that is the durable record**, and a file
nobody queries is not one.

### 2 · Design — intake, then merge the delta
Read the intent, then `.claude/productizer/spec.md` in full. **Check it against the
constitution first** (`.claude/productizer/constitution.md`, `templates/constitution.md`):
`P`-numbered principles bind every requirement, including the ones nobody has
written yet, and asking *is this permitted at all* is a prior question to the
four below. A requirement crossing a principle is **automatically critical** —
it gives way, or the principle is amended as its own act by its ratifying
authority, never inside the change that needed it relaxed
(`references/constitution.md`). Then classify the intent as exactly one of four
things (`templates/intake.md`):

| | Meaning | Action |
|---|---|---|
| **Extend** | not covered yet | allocate new ids, write them in EARS |
| **Refine** | right but imprecise | same id, changed text, recorded |
| **Duplicate** | already specified | cite the id and **stop** |
| **Contradict** | the spec forbids what this requires | **stop and ask** |

**Record the classification the moment you settle on it**, before the delta,
before the ruling, before anything else - `scripts/record-classification.sh
--intent <id> --classification <one of the four>`
(`references/classification-provenance.md`). It writes the spec commit and hash
you classified against and every active id that was in scope; an unreachable
spec home yields no hash, so it refuses to write rather than record a guess,
which is the only half of R19 a script can hold. **This is a step of the stage,
not a nicety at the end of it** - a classification with no record is one nothing
can ever check, and `check-classification-provenance.sh` reports an empty store
in a repo that classified as a finding rather than a pass. The same file also
holds R6's one-per-intent rule at the filename, so classifying an intent twice
is a collision the writer refuses.

**A contradiction is a stop, not a merge.** Quote both requirement ids, state
the conflict in one sentence, ask which wins, and say plainly nothing was
merged.

**Write the ruling before you ask.** Run `scripts/request-ruling.sh` at the
moment you classify contradict - it allocates the `D` and `C` ids, drafts the
file from `templates/ruling.md` with both sides and both columns of costs, and
prints the path to name in your message. Asking first and writing after is the
failure this is for: the session can end before anything is written, the halt
leaves no trace, and the work stops and stays stopped with nobody holding a
question. A stop that nobody was asked to answer is indistinguishable from a
stop that was abandoned. Never supersede silently, and never prefer a requirement for being newer
— that changes agreed behaviour with nobody approving it, leaving a spec that is
confidently wrong rather than obviously incomplete.

State the change for review as a **spec delta** in the PR body
(`templates/spec-delta.md`) — every id that moved, quoted, with its constitution
check. It is never committed as a file, because a per-change copy of the spec
drifts the first time someone edits one and not the other. A contradiction a
human decides is recorded as a **ruling** (`templates/ruling.md`,
`references/rulings.md`), so the decision outlives the conversation that made it.

`scripts/contradiction-check.py` is a deterministic **second opinion** on
numeric bounds and mutually exclusive responses (`references/solver.md`). It may
halt on its own, but **its `CONSISTENT` means *not decided*, never *cleared***:
wiring it to let the model skip a pair reintroduces the silent miss with a
solver's authority attached.

Merging is a spec edit: new requirements take the next ids, replaced ones are
marked superseded with a pointer and never deleted, and each active one keeps a
row in the acceptance criteria table. **Ids are never reused and never
renumbered** — plans, tests, findings and PR titles cite them, and a reused id
silently redirects all of them.

**Requirements are written in EARS** (`references/ears.md`): one per sentence,
one `shall` each, response observable from outside. Unquantified adjectives are
arguments deferred to review, and a spec with no `If <trigger>, then …`
requirements has not considered failure — a gap the tests inherit. Apply policy
skills **while writing**, not afterwards; name conflicts and both owners. Only
the **delta** goes to build.
