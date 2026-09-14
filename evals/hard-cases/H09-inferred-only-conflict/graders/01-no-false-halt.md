---
type: regex
pattern: '^\s*\*{0,2}VERDICT\*{0,2}:\s*\*{0,2}CONTRADICT'
flags: 'mi'
match: not_contains
target: last_message
weight: 6
---

The reply must NOT end with `VERDICT: CONTRADICT`.

This is the precision criterion. It carries 6 of the 14 scored weight points
here — 43 percent of this case's score — against the 16 of 25 that detection and
halting carry together in a must-halt case, which is 64 percent. That asymmetry
is the whole design: recall is bought at the cost of precision deliberately, and
the exchange rate is written in the weights rather than implied. Without these
cases a classifier that halted on every intent would score perfectly.

Why this is not a contradiction: the only requirement the intent collides with is R36, which is inferred and unconfirmed: nobody has agreed to it, and the spec says an inferred requirement becomes active only when a human confirms it. No active requirement or principle covers blocking a client over no-shows - R22 governs the deposit, not access - so this extends the spec and raises R36's confirmation question rather than halting.
