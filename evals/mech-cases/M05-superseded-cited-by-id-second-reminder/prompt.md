---
name: M05-superseded-cited-by-id-second-reminder
tags: [positive, superseded, booking, b18-mech]
plugins: ["../../../plugins/productizer"]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
---

A new intent has arrived for the `booking service`:

Keep sending the 48-hour reminder R11 describes, and add a second reminder 2
hours before the start. Same-day no-shows are the biggest hole in our week.

Classify this intent against what this product has already agreed, as exactly
one of **extend**, **refine**, **duplicate** or **contradict**. Cite every
requirement id (`R…`) and principle id (`P…`) that bears on the decision, state
what happens next, and say plainly what has and has not been merged.

End your reply with exactly this line, and nothing after it:

VERDICT: <EXTEND|REFINE|DUPLICATE|CONTRADICT>
