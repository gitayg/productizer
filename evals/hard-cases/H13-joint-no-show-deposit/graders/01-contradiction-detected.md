---
type: regex
pattern: '^\s*\*{0,2}VERDICT\*{0,2}:\s*\*{0,2}CONTRADICT'
flags: 'mi'
match: contains
target: last_message
weight: 10
---

The reply must end with `VERDICT: CONTRADICT`.

This is the recall criterion. It carries 10 of the 25 scored weight points in
this case, and together with the halt criterion beside it 16 of 25 — 64 percent
of the score, against the 43 percent the mirror-image criterion carries in a
must-not-halt case. A run that
explains the conflict beautifully and then classifies the intent as an extend
has shipped a conflicting requirement, which is the failure this corpus exists
to measure. Missing critical information is worse than including extra
information: an over-cautious halt costs a human a minute, a missed
contradiction costs a spec that is confidently wrong.

Conflict under test: no single requirement conflicts with the intent. R24 marks an appointment a no-show while the client has not arrived by 15 minutes after the start, and R22 retains the deposit of a no-show. Together they retain the deposit of a client who arrives between 15 and 20 minutes after the start, which is exactly the client the intent says must never lose it.
