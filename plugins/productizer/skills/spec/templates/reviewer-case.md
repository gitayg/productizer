# Reviewer case — <what broke, in a few words>

Source: <revert <commit>, or incident <issue or report>>
Change: <the commit that shipped the bug>
Base: <the commit the change was made on, or —>
Bug: <path:line of the confirmed bug, as the change left it>
Class: <the bug class, not the one instance>
Fix: <the commit or pull request that fixed it>

---

One file per revert or incident, under `evals/reviewer/`, named for what broke
(`evals/reviewer/retry-on-permanent-error.md`). A revert or an incident is the
one place a reviewer's miss is confirmed rather than guessed, so each becomes a
case the reviewer is scored on from then on.

**Change** is the commit the reviewer is handed: the one a revert names on its
`This reverts commit` line, or the one an incident was traced to. **Bug** is
where the confirmed bug sits in that commit's tree, `path:line` or
`path:line-line` relative to the repository root. **Fix** is what fixed it: the
revert itself, or the later commit or pull request. **Base**, when given, is
the commit the review diffs from; leave it `—` and the score checks only that
the review was of the change.

**A revert that lands without a case fails the `revert-cases` check**
(`scripts/check-revert-cases.py`): every commit in a change carrying a
`This reverts commit <id>` line needs a case here whose `Change:` is that id.
Add the case in the same change as the revert. An incident has no commit to
find it by, so its case is added by whoever traced it; nothing checks for one.

**Scoring takes no model.** `templates/agent-evals.yml` runs the reviewer on the
change and saves what it prints as a review record
(`templates/review-record.md`); `scripts/score-reviewer-case.py` reads that
record against this file. The reviewer caught the case when round 1 reviewed
this change and an Important finding names the bug's path and a line range
that overlaps it. Every other round-1 finding is counted as noise. The suite
re-runs when the reviewer's prompt, its tools, its model or `REVIEW.md`
changes.
