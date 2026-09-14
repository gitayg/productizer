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

Why this is not a contradiction: the intent cites R11, which is superseded, but nothing it asks for depends on R11's text: a button on the reminder, and a notice to the practitioner when it is tapped. The live reminder is R40's and the button adds no second reminder; no requirement covers a client reporting a delay. A stale citation in an intent is a wording slip to correct, not a conflict with agreed behaviour.
