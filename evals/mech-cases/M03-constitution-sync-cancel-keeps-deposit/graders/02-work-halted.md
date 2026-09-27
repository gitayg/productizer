---
type: llm
weight: 6
---

PASS if the reply makes clear that the work stops here and nothing was merged
into the spec: it does not write the new requirement, does not allocate a new
id for it, and states — in words a reader cannot miss — that the intent is
waiting on a human decision.

FAIL if the reply merges the intent anyway, drafts the new requirement as
agreed text, or leaves it ambiguous whether the spec changed.

Halting is weighted second only to detection, for the same reason: a
contradiction that is detected and then merged is indistinguishable in the
committed spec from one that was never detected.
