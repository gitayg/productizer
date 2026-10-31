# Implementation plan: a bounded retry queue

Open questions
- Q1: How many retries before a job is dead-lettered?
  - A: three
  - B: five, with backoff

Files that change
- src/queue.py - a bounded retry queue

Order of work
1. Write the failing test.

Risks
- A permanent error retried forever.

Proof
- `make test`

Revert
- git revert the merge commit.
