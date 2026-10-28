# Review policy

## Who reviews
The review is dispatched to a subagent with a clean context. The session that
wrote the code never reviews it.

This is a rule, not a preference. A writing session is anchored to its own
reasoning: asked to review, it re-derives the conclusions that produced the
code and calls them confirmation. A fresh context reads the diff as evidence
rather than as a memory. A self-review by the authoring session is not a
review pass and does not satisfy this policy.

## Precondition: resolve the base
Every pass below compares the diff against a base. Resolve it and state it
before any pass runs.

1. Name the base ref and say how it was resolved — the remote branch if it
   exists, otherwise a local branch, otherwise a fallback. Say which of those
   it was.
2. Diff against the merge base of that ref and HEAD, not the branch tip.
3. If the base looks wrong, fix that before believing any other result. A
   wrong base makes every finding confidently wrong at once.
4. Treat an empty diff as a base failure until proven otherwise. An empty diff
   is far more often a base-resolution problem than a change that genuinely
   did nothing.

State the resolved base at the top of the review. A review that does not name
its base is not readable as evidence.

## Passes
- Bugs: logic errors, edge cases, regressions.
- Security: injection, auth gaps, PII in logs.
- Compliance: does the diff satisfy the requirement ids this change cites, as
  they read in the living spec, plus plan.md and our design principles? A diff
  that implements behaviour no requirement asked for is scope, not compliance.
- Revert: does the PR body say how the change was tested and how to revert
  it (`templates/pull-request.md`), and does `plan.md` say how to revert it?
  A missing revert path is an Important finding.

## Important, Nit, Pre-existing
- Important: breaks behaviour, leaks data, or breaches policy.
- Nit: style, naming, preference.
- Pre-existing: a bug this change did not introduce. Report it, labelled, so it
  is not charged to the change; it never blocks the change.

## Every finding
- Names a file and line, `path:line`. A finding nobody can locate cannot be
  checked or fixed.
- Names the whole bug class, not the one instance, so the author fixes every
  instance and the next round does not find the second one.
- Is not one already reported in an earlier round.

## Say the count
State how many findings the round produced. When there are none, say
`no issues` — never leave it blank. A summary with no count cannot be told
from a review nobody wrote.

## Cap the nits
Report at most 5 nits. Summarise the rest as a count.

## Cap the rounds
Each round reviews only the diff since the commit the last round reviewed.
After three rounds the author stops patching and rethinks the approach; a
fourth round needs the record's `Rethink:` line to name the new approach.

## Record and answer
Each round's findings go into the change's review record
(`templates/review-record.md`, beside its `plan.md`). Every finding is answered
fixed, rejected, intentional or irrelevant, with a reason; for fixed, the
commit. **An Important finding left open fails the `review-record` check and
blocks the stage.** The way out is a waiver of that check
(`templates/waiver.md`), signed by a named person, with an expiry.

## Do not report
Generated files. Anything CI already enforces.

## Ignored paths
Not reviewed, and a finding located under one fails the review record. One
glob per line; a `*` crosses `/`.
- `dist/**`
- `*.lock`
