---
type: regex
pattern: 'Next requirement id\s*\n:\s*`R43`'
match: contains
target: {source: file, path: .claude/productizer/spec.md}
arm: both
weight: 1
---

Run validity, not an outcome. Passes when the run's working directory holds the
living spec the scaffold copies in, read from disk after the run. A run where
this fails never had a spec to find, and says nothing about finding one: it is
excluded and counted, never scored as a pass or a fail of the halt decision.
`arm: both` because the bare arm needs the same proof.
