# Spec delta — <issue> <short title>

The reviewable statement of one change to the living spec. It names every
requirement id that moved, quotes the text, and says which of the four intake
classifications produced it. A reviewer reads this instead of reconstructing
prose from a diff, which is the only way a spec change reviews like code.

**This goes in the PR body, not into the repo.** The spec is the artifact and
`git log -p .claude/productizer/spec.md` is the audit trail; a committed delta file
per change is the per-change copy of the spec that the spec header rules out,
and it starts drifting from the spec the first time someone edits one and not
the other. Paste this into the PR that carries the spec commit.

**Nothing here deletes anything.** There is no removed section, because a
requirement never leaves the spec — it changes status. Supersede replaces a
behaviour and points forward; withdraw ends a behaviour and says why. Both keep
the original sentence in place in the spec, and both keep the id resolvable for
every plan, test, review finding and PR title that already cites it.

**Every section is keyed by permanent id, never by title.** Two requirements
can be retitled into each other; two ids cannot. A delta keyed by title
silently reattaches to a different requirement the moment someone rewords a
heading.

---

## What drove it

Issue
: <#123 / PROJ-123> — <one line: what customers cannot do today, in their words>

Branch / PR
: `<branch>` / <pr>

Spec commit
: `<sha>` — the commit this delta describes.

Classification
: extend (R41, R42, R43) · refine (R12) · duplicate (R9, no change) ·
contradict (R7, ruled — see C4). Those four are intake's classes
(`templates/intake.md`); supersede and withdraw are what a ruling produces, not
classes of their own.

Allocator
: `R41` before this change, `R44` after. The highest id ever used, not a count
of rows. Ids are never reused and never renumbered.

## Constitution check

Run before any requirement was written, against every active principle in
`.claude/productizer/constitution.md`. Record the result even when it passes — a check
with no record is indistinguishable from a check nobody ran.

| Principle | Bearing on this change | Result |
|---|---|---|
| P1 | R42 writes settlement rows to an export sink | pass — sink is inside the tenant boundary, asserted by `test_export_sink_tenant_scoped` |
| P2 | R41 hands unverified callbacks to a queue consumer | pass — the consumer resolves a principal before it does work |
| P3 | R41 queues a callback the service cannot yet verify instead of rejecting it | pass — queueing defers the decision, it does not make it; the settlement is not applied until verification succeeds, and one that never succeeds expires unapplied |
| P4 | none — no published contract changes | not engaged |

State `no violations` or name the principle and stop. A requirement that
contradicts a principle is automatically critical: it does not get merged and
then argued about, and it is not routed to a human to pick a winner. Either the
requirement changes, or the principle is amended as its own act in its own
commit by its ratifying authority (`references/constitution.md`).

## Added requirements

New behaviour the spec did not cover. New ids, allocated from the header's
allocator, written in EARS (`references/ears.md`).

**R41** — When a payment provider posts a settlement callback the billing
service cannot yet verify, the billing service shall queue it for retry.
Pattern: event-driven. Replaces R7 — see *Superseded*.
Failure cases: input n/a because a callback that fails verification is what R41 queues · caller n/a because the consumer resolves a principal before it works (P2 above) · repeat R43 · dependency <the If requirement for a queue that refuses the write>
Verified by: `test_unverified_callback_is_queued`.

**R42** — When an operator requests a settlement export, the billing service
shall write a CSV containing one row per settlement in the requested period.
Pattern: event-driven.
Failure cases: n/a because an export reads settlements and changes none
Verified by: `test_settlement_export_row_per_settlement`.

**R43** — If a settlement callback arrives with a provider reference already
recorded, then the billing service shall record no second settlement.
Pattern: unwanted behaviour.
Verified by: `test_duplicate_settlement_callback_records_once`.

A change that adds no unwanted-behaviour requirement has not considered
failure, and the tests will inherit that gap. Say so explicitly if the change
genuinely has no failure path, rather than leaving the reviewer to notice.

**Every added `When` requirement answers four questions** — invalid input, a
wrong caller or tenant, a repeat or concurrent action, a failing dependency —
each with an `If` requirement id or `n/a because <reason>`, or once with
`n/a because <reason>` when it changes no state. Quote the `Failure cases`
line here as it stands in the spec, where it is one unindented line, last in
the requirement's item (`references/ears.md` rule 6).
`validate-spec.py --repo . --failure-cases` refuses the change without it.

## Refined requirements

Same id, changed text. A refinement makes a requirement stricter, more specific
or more measurable **without changing what is agreed**: everything satisfying
the new text satisfied the old one. If that is not true, it is a supersession
and belongs in the next section — a contradiction under a smaller word is still
a contradiction, and it changes agreed behaviour with nobody approving it.

**R12** — quote both sides, so the reviewer judges the claim rather than
trusting it.

Before
: While under 100 concurrent requests, the billing service shall return p95
latency under 200 ms.

After
: While under 100 concurrent requests, the billing service shall return p95
latency under 100 ms.

Why
: Tightened from 200 ms to 100 ms. Strictly narrower, so R12 keeps its id and
every citation of it stays correct.

## Superseded requirements

The behaviour is replaced. The old requirement keeps its sentence in the spec,
gains `Superseded by R<n>.` on the line beneath it, and loses its acceptance
criteria row.

**R7 → R41**

Was
: When a payment provider posts a settlement callback the billing service
cannot verify, the billing service shall reject it with 400.

Now
: R41 — the callback is queued for retry instead.

Why
: The provider treats 400 as permanent and drops the settlement, so a
verification lag lost money that never arrived again. Behaviour R7 required —
rejecting — is now forbidden, which makes this a supersession and not a
refinement, however similar the two sentences read.

Ruled by
: <name>, <date> — required only where the supersession came out of a
contradiction. A supersession the originator and the requirement's owner both
agree on needs no ruling; one that resolves a conflict needs the ruling
recorded here and in the spec's decision record, before either requirement is
written.

## Withdrawn requirements

The behaviour no longer exists at all — not replaced, ended. The requirement
keeps its sentence in the spec and gains `Withdrawn.` with the reason, so the
next person to propose it finds out it was considered and dropped.

None in this change. When there are any, use the same shape:

**R19** — withdrawn.
Was
: While a settlement is pending, the billing service shall display an estimated
clearing date.

Why
: The provider stopped publishing clearing estimates; the field has no source.

## Duplicates found

Requirements in the intent that the spec already covers. Cite the id, add
nothing. A near-identical requirement under a new id splits one behaviour's
citations across two ids, and the tests follow only one of them.

- The intent's "callbacks must be authenticated" is already **R9**. No change.

## Contradictions raised

Every conflict this intent hit, whether or not it has been ruled on. An open row
here means the spec change is **not complete** and the PR is not mergeable —
nothing downstream of an unruled contradiction is safe to build.

| # | Conflict, in one sentence | Requirements | Status |
|---|---|---|---|
| C4 | The intent requires queueing unverifiable callbacks; R7 requires rejecting them with 400 | R7, R41 | resolved: R7 superseded by R41, ruled by <name> on <date> |

## Acceptance criteria

Every active requirement holds a row in the spec's criteria table. Show the
rows this change adds and removes, so "do the tests assert the criteria" is
answered here rather than deferred to Stage 4.

| Requirement | Row | Verified by |
|---|---|---|
| R41 | added | `test_unverified_callback_is_queued` |
| R42 | added | `test_settlement_export_row_per_settlement` |
| R43 | added | `test_duplicate_settlement_callback_records_once` |
| R7 | removed | superseded — no row for a non-active requirement |

List any added requirement you could not map to a check as unmapped, with the
reason. Omitting the row instead makes an unverified requirement look verified.

## Reviewer checklist

Each line is a question the delta above should already answer. A `no` is a
change request, not a comment.

- [ ] Every id here appears in the spec diff, and every id in the spec diff
      appears here.
- [ ] No id was reused, and no id was renumbered.
- [ ] The allocator moved to one past the highest id ever used.
- [ ] Every refinement is genuinely narrower than the text it replaces.
- [ ] Nothing was deleted from the spec — superseded and withdrawn requirements
      keep their sentences and gained their markers.
- [ ] The constitution check names every active principle, and none is violated.
- [ ] No contradiction row is still open.
- [ ] Every added requirement is EARS, one `shall`, observable response, no
      unquantified adjectives.
- [ ] The change log row in the spec matches the ids in this delta.
