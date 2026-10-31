## What changed
<one paragraph, citing the requirement ids this change serves>

## How it was tested
<the commands run and what they printed: the test names, the pass counts, the
checks result. A test never seen failing is not evidence>

## Proof it works
<what a person sees when they use the change the way a user would meet it,
measured against the original request - not the tests, which go above. One
list item per requirement id, backlog id or issue it answers, each saying what
it shows and carrying the evidence: a screenshot, a recording, a log in a
fenced block, or a link to a run's artifact. For a change nobody using it can
observe, replace all of this with the one line: **n/a** - then the reason>

## How to revert
<the commit to revert, any data, migration or configuration to restore, and
what stops working meanwhile>

## Spec delta
<templates/spec-delta.md, when the change moved the spec>

---

The body of a pull request, for a person to fill in or an agent to draft. An
agent may draft *How it was tested*, *Proof it works* and *How to revert*; the
author who opens the pull request is responsible for all three. *Proof it
works* is what the reviewer reads before the diff: evidence that the change
does what was asked, where *How it was tested* is evidence that its tests
pass. A body missing any of the three is a finding at review (`REVIEW.md`), and
`scripts/check-plan-record.py --kind pr-body` reads a body saved to a file for
all three, and fails a proof item that names no `R<n>`, `B<n>` or `#<n>` or
carries no link, image or fenced log. It reads text: it cannot tell a real
screenshot from a wrong one. Nothing in the lifecycle takes a screenshot,
uploads one or posts a body: opening the pull request is the author's act.
