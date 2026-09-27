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

Conflict under test: R14 offers a freed slot only to the first client on that practitioner's waitlist for 30 minutes; the intent hands the slot to anyone in public search the moment the appointment is cancelled. A cancellation is how a slot is freed, but R14 sits under Waitlist rather than Search and shares no word with the intent's trigger, so the collision is found only by reading all 38 active requirements, not the section the intent is about.
