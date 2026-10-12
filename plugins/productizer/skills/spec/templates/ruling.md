# D<n> — <the conflict in a few words>

Status: pending
Raised: <YYYY-MM-DD>
Concern: C<n>
Intent: <#123 / PROJ-123>
Ruled: —
Ruled by: —
Supersedes: —
Superseded by: —

That block is read by machine as well as by people. One `Key: value` per line,
no blank line inside the block, and `Status:` carries exactly one of `pending`,
`ruled`, `lapsed` or `superseded` — nothing else on the line. An unset field is
an em dash, never blank: a blank value and a missing line are indistinguishable
to anything counting these files, and a counter that cannot tell them apart
reports a pending ruling as ruled.

## The conflict

**R14** — <the active requirement, verbatim, EARS text unchanged>

**Incoming** — <the behaviour the intent requires, written in EARS, no id
allocated — allocating one here would merge the losing side by accident>

<Why these cannot both hold, in one sentence. State it; do not argue it. The
argument belongs under Reasoning, after someone has ruled.>

## The question

<One question with a decidable answer, naming the two outcomes. "Thoughts?" is
not a question — it returns a discussion, and a discussion does not close a
stop.>

## What each side costs

| If R14 governs | If the incoming behaviour governs |
|---|---|
| <who stays blocked, what is not built> | <what is given up, which tests change, who is affected> |

Fill both columns even when one looks obvious. A ruler handed one side's costs
is being steered, and a steered ruling is the agent's decision wearing a human
name.

## Ruling

<Which side governs, stated as the behaviour that now holds. One sentence.>

Ruled by <name>, <YYYY-MM-DD>.

A named person, never a role and never "the team" — an unattributed ruling
cannot be questioned later, because nobody knows who to ask. The agent drafts
every section above this one and none from here down.

## Reasoning

<Why this side won: the evidence, constraint or cost that decided it. Not a
restatement of the ruling. The next person to raise the same question reads
this instead of re-arguing it, so a reason of "we decided to" teaches nothing
and buys the argument again.>

## Not decided

<What this ruling deliberately leaves open, and the scope it does not reach.
Omit this and the ruling gets read as wider than it was, and a later intent is
refused on a question nobody actually ruled on.>

## Consequences

| Change | Applied |
|---|---|
| Allocated | R<new> |
| Superseded | R<old> → R<new> |
| Withdrawn | — |
| Acceptance criteria | R<old> row removed, R<new> row added |
| Concern row | C4 → `resolved: D7, <YYYY-MM-DD>` |
| Decision record | row dated <YYYY-MM-DD> citing D7 |
| Change log | row dated <YYYY-MM-DD>, issue <#123> |

Every row lands in the same commit as this file. A ruling recorded in one commit
and applied in another leaves a window where the spec and the record disagree,
and a reader inside that window cannot tell which of the two is stale.
