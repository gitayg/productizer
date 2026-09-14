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

Why this is not a contradiction: D3 is scoped to booking for another adult, and its own Why column says bookings made by a parent or guardian for a child under 16 were not part of the decision. No active requirement or principle covers it, so the intent extends the spec. Halting on D3 reads the ruling wider than it was written.
