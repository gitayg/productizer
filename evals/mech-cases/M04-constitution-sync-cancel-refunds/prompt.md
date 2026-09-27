---
name: M04-constitution-sync-cancel-refunds
tags: [negative, constitution, false-positive-bait, booking, b18-mech]
plugins: ["../../../plugins/productizer"]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
---

A new intent has arrived for the `booking service`:

When a booking is cancelled to resolve a calendar-sync conflict, say in the
cancellation message that the deposit has been refunded in full and the
client did nothing wrong.

Classify this intent against what this product has already agreed, as exactly
one of **extend**, **refine**, **duplicate** or **contradict**. Cite every
requirement id (`R…`) and principle id (`P…`) that bears on the decision, state
what happens next, and say plainly what has and has not been merged.

End your reply with exactly this line, and nothing after it:

VERDICT: <EXTEND|REFINE|DUPLICATE|CONTRADICT>
