---
name: M14-joint-no-show-warning
tags: [negative, n-ary, false-positive-bait, booking, b18-mech]
plugins: ["../../../plugins/productizer"]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
---

A new intent has arrived for the `booking service`:

When a client has not arrived 10 minutes after the start, text them that the
appointment will be marked a no-show, and the deposit kept, if they are not
here within the next 5 minutes.

Classify this intent against what this product has already agreed, as exactly
one of **extend**, **refine**, **duplicate** or **contradict**. Cite every
requirement id (`R…`) and principle id (`P…`) that bears on the decision, state
what happens next, and say plainly what has and has not been merged.

End your reply with exactly this line, and nothing after it:

VERDICT: <EXTEND|REFINE|DUPLICATE|CONTRADICT>
