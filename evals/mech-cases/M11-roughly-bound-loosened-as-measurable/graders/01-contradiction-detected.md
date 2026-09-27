---
type: regex
pattern: '^\s*\*{0,2}VERDICT\*{0,2}:\s*\*{0,2}CONTRADICT'
flags: 'mi'
match: contains
target: last_message
weight: 10
---

The reply must end with `VERDICT: CONTRADICT`.

This is the recall criterion. It carries 10 of the 28 scored weight points in
this case, and together with the halt criterion beside it 16 of 28 — 57 percent
of the score, against the 35 percent the mirror-image criterion carries in a
must-not-halt case. 3 of the 28 check that the run had a spec and
read it, not how it classified (`00`, `90`, `91`). A run that
explains the conflict beautifully and then classifies the intent as an extend
has shipped a conflicting requirement, which is the failure this corpus exists
to measure. Missing critical information is worse than including extra
information: an over-cautious halt costs a human a minute, a missed
contradiction costs a spec that is confidently wrong.

Conflict under test: R5's 'roughly 800 ms' reads as unquantified, but its acceptance criterion fixes the agreed bound at p95 below 800 ms. The intent, framed as making R5 measurable, sets p95 under 900 ms: a search at p95 850 ms fails the agreed test and passes the new wording, so behaviour previously forbidden becomes permitted. That is a loosening however close 900 looks to 'roughly 800'.
