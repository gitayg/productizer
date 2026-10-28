## What changed
<one paragraph, citing the requirement ids this change serves>

## How it was tested
<the commands run and what they printed: the test names, the pass counts, the
checks result. A test never seen failing is not evidence>

## How to revert
<the commit to revert, any data, migration or configuration to restore, and
what stops working meanwhile>

## Spec delta
<templates/spec-delta.md, when the change moved the spec>

---

The body of a pull request, for a person to fill in or an agent to draft. An
agent may draft *How it was tested* and *How to revert*; the author who opens
the pull request is responsible for both. A body missing either is a finding at
review (`REVIEW.md`), and `scripts/check-plan-record.py --kind pr-body` reads a
body saved to a file for both sections. Nothing in the lifecycle posts a body:
opening the pull request is the author's act.
