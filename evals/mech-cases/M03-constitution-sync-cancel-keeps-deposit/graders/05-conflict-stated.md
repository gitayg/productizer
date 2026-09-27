---
type: llm
weight: 2
---

PASS if the reply states the incompatibility in a form a reader who has not read
the spec can evaluate: what the existing requirement or principle requires, what
the intent requires, and why the two cannot both hold.

The conflict under test is: P2 requires a booking cancelled by the booking service itself, including one cancelled to resolve a calendar-sync conflict, to be refunded in full; the intent cancels on a sync conflict and keeps the deposit. No active requirement forbids it - R18 covers only a practitioner's cancellation and R32 only alerts - and P2's title is about the client's own choices, so the conflict lives in the principle's body and nowhere in the requirements.

Wording need not match. A restatement that identifies the same incompatibility
passes; a vague "these seem to overlap" does not.
