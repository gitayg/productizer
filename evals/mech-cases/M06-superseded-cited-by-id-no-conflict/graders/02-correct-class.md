---
type: regex
pattern: '^\s*\*{0,2}VERDICT\*{0,2}:\s*\*{0,2}EXTEND'
flags: 'mi'
match: contains
target: last_message
weight: 4
---

The reply must end with `VERDICT: EXTEND`.

Not halting is necessary but not sufficient — classifying a duplicate as an
extend allocates a second id for behaviour that already has one, and the spec
grows two answers to the same question.
