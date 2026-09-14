---
type: llm
weight: 2
---

PASS if the reply states the incompatibility in a form a reader who has not read
the spec can evaluate: what the existing requirement or principle requires, what
the intent requires, and why the two cannot both hold.

The conflict under test is: R5's 'roughly 800 ms' reads as unquantified, but its acceptance criterion fixes the agreed bound at p95 below 800 ms. The intent, framed as making R5 measurable, sets p95 under 900 ms: a search at p95 850 ms fails the agreed test and passes the new wording, so behaviour previously forbidden becomes permitted. That is a loosening however close 900 looks to 'roughly 800'.

Wording need not match. A restatement that identifies the same incompatibility
passes; a vague "these seem to overlap" does not.
