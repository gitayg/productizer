# Rulings — the record of a contradiction and how it ended

Intake stops when an incoming intent contradicts an active requirement. The stop
is the point of this lifecycle: every comparable tool detects the conflict,
notes it and merges anyway, which produces a spec that is confidently wrong.

A stop that ends in a chat message is only half of that. The decision gets made
in a session, the session ends, and the reasoning is gone — while the spec keeps
the outcome and loses the argument. Six months later nobody can say why R14 lost,
so the same intent arrives again and is argued from nothing. A decision made in
conversation and never written down is the exact failure this tool exists to
prevent, one layer up.

So the stop writes a file, and it writes it **before** it asks the question.

## Where rulings live

```
.claude/productizer/rulings/D<n>-<slug>.md
```

One file per contradiction, committed to the repo beside the spec. Shape:
`templates/ruling.md`.

- **Committed, not ticketed.** A ruling that lives only in an issue comment
  leaves the repo when the tracker is migrated, and the audit trail then depends
  on a vendor nobody in the room controls. The spec diff and the ruling are
  reviewed by the same people through the same gate.
- **Beside the spec, not inside it.** The spec records what is agreed now; a
  ruling records an argument. At fifty rulings, inlining them buries the
  requirements they exist to protect.
- **The spec keeps the pointers.** The *Areas of concern* row cites the ruling
  id, and the *Decision record* table gains one row per ruling. Intake already
  reads the whole spec, so it meets every past decision without opening the
  directory.
- **`.claude/` is routinely gitignored.** Run `git check-ignore -v` on the first
  ruling path; it must exit non-zero. A ruling directory that cannot be committed
  is a local notes folder that looks like an audit trail.
- **Cite `D7`, never the path.** The slug is decoration for humans scanning
  `ls`; the id is the handle. Citing paths means a tidy-up rename breaks every
  reference in every issue comment, silently.

## Ids: `D`, its own space

**Keyed by the issue that raised it** is the cheaper design. Every intent already
has a tracker item, the join to the branch and the PR is already made by issue
number, and there is no second counter to keep monotonic — one counter is one
thing to get wrong. Against it: one intent routinely contradicts two
requirements and needs two rulings, so the key is not unique without a suffix
nobody agrees on; tracker keys are renumbered wholesale on a GitHub-to-Jira
migration; and a repo bound as `linkage` has two trackers and therefore two
keyspaces claiming the same authority.

**Its own space** costs an allocator and buys permanence. The criterion is
whether a citation to a ruling must last as long as a citation to a requirement,
and it must: a superseded requirement carries a forward pointer and one line on
why, and that line names the ruling. It is read whenever anyone asks why the
spec says what it says — the same lifetime as `R14` itself, which outlives the
tracker that raised it by design.

**Rulings get `D1`, `D2`, …** Issue keys are recorded as a field inside the
ruling, so the join to the tracker survives without being load-bearing.

The prefix is free: `R` is requirements, `P` is principles, `C` is the *Areas of
concern* rows in the spec — which the session-start hook already matches as
`C[0-9]+`. No `D<n>` id exists anywhere else in this lifecycle. Jira keys carry
a dash (`PROJ-123`), so they cannot be confused with a bare `D7` either.

`C` and `D` are deliberately not merged. A concern is an open question; a ruling
is an answer. `Superseded by C7` would read as a decision replaced by a
question, and concerns cover contested ground that never reaches a ruling at all.
Allocate the pair in one commit: a `C` row with no `D` file is a question with
nowhere to be answered, and a `D` file with no `C` row is invisible to anyone
reading the spec. If you find one side missing, write the other — never renumber
to close the gap.

Everything the spec's id discipline says applies here unchanged. Ids are
monotonic and the counter never rewinds; a removed ruling does not free its
number. Ids are never reused and never renumbered — a reused `D7` silently
redirects every supersession line citing it, and nothing errors. A ruling is
never deleted and never edited after it is ruled; it changes status.

| Status | Meaning |
|---|---|
| `pending` | Written, nobody has ruled. The contradicting delta is not merged. |
| `ruled` | Decided and applied. The consequences table matches the spec. |
| `superseded` | Reversed by a later ruling, which is named in `Superseded by:`. |
| `lapsed` | Nobody ruled and the intent went away. Nothing was merged. |

## Raising one

At the moment intake classifies an intent as **contradict**, before the question
is asked out loud:

1. Allocate the next `D<n>` and the next `C<n>`.
2. Write the ruling file from `templates/ruling.md`: both requirements verbatim,
   the conflict in one sentence, one decidable question, both columns of costs.
3. Add the `C<n>` row to *Areas of concern* with status `open: D<n>`.
4. Commit both.
5. Then ask, and name the ruling path in the message.

Writing the file first is the whole mechanism. Ask first and the session may end
before anything is written, which returns you to the failure at the top of this
page — and leaves the session-start count reading clean while a contradiction is
live.

Do not allocate a requirement id for the incoming behaviour. An id in the spec
is a merge, whatever the surrounding prose says.

**A pending ruling blocks its own delta and nothing else.** Unrelated intents
keep flowing. A halt that stops all work in the repo teaches people to route
around intake, and an intake nobody runs detects no contradictions at all.

## Surfacing what is pending

The state is a directory of files with a fixed header, so anything can count it
without parsing the spec: one glob, one fixed-string match, no network.

```bash
# how many are waiting - only when the directory exists, since none is not 0
[ -d .claude/productizer/rulings ] \
  && find .claude/productizer/rulings -maxdepth 1 -type f -name 'D*.md' \
       -exec grep -lxF 'Status: pending' {} + | wc -l

# which ones, ids only
find .claude/productizer/rulings -maxdepth 1 -type f -name 'D*.md' \
    -exec grep -lxF 'Status: pending' {} + \
  | sed -n 's#^.*/\(D[0-9][0-9]*\)[-.].*#\1#p' | head -5 | paste -sd, -
```

Contract for anything reading these files — the session-start hook included:

- **`-x` and `-F`, not a substring match.** `Status: pending` appears in the
  template's own prose and will appear in a ruling that discusses being pending.
  An unanchored match counts those and reports questions that do not exist.
- **Emit ids, never text.** A ruling quotes an incoming intent, which is text a
  stranger can write, and a session-start announcement lands in the model's
  context before a human has read a word of it. `D7` cannot carry a sentence.
  This is the rule the hook already applies to the spec, for the same reason.
- **No file means no count, not zero.** A repo with no `rulings/` directory has
  never raised one; a directory that cannot be read is unknown. Reporting either
  as `0 pending` states "nothing is waiting" as a fact, which is the one wrong
  answer that looks healthy. In `bash`, an unmatched glob reaches `grep` as a
  literal path, and hiding the error that follows hides an unreadable directory
  with it; so the examples above use `find`, never suppress stderr, and
  distinguish the cases with a directory test rather than by trusting the count.
- **Staleness is derived, never stored.** Age comes from the `Raised:` line. A
  stored `stalled` flag has to be updated by someone, and nobody will.
- **The count is only as good as step 2 above.** A contradiction stopped in
  conversation without a file is a contradiction nothing can see.

**Three or more pending in one repo means intake is running ahead of the person
who has to rule.** Stop taking intents in that area until the queue drains;
questions arriving faster than answers get answered in bulk, and a bulk ruling
is a rubber stamp.

## Recording the ruling

A human rules. Not the agent, not the intent's author by implication, not
whoever committed last.

The agent drafts the conflict, the question, the costs and the consequences
table. It does not fill `Ruling`, `Ruled by` or `Reasoning`. A stop that
resolves itself is not a stop.

Then, in one commit:

- The ruling file: status `ruled`, `Ruled` and `Ruled by` filled, the reasoning
  written as the constraint that decided it rather than a restatement, the
  consequences table completed.
- The spec: losing requirement marked `Superseded by R<n>.` with one line on why
  that names the ruling; winning requirement allocated a new id; acceptance
  criteria rows added and removed to match; the `C<n>` row moved to
  `resolved: D<n>, <date>`; one *Decision record* row; one *Change log* row.

One commit, because a spec that has been changed and a ruling that has not yet
been written are two files disagreeing about what was agreed, and the reader in
between cannot tell which is ahead.

Where the ruling is "the existing requirement stands", there is still a file,
still a `ruled` status and still a *Decision record* row. Recording only the
rulings that changed something leaves the rejected intents looking unconsidered,
and they arrive again.

## When nobody rules

A pending ruling never expires into a decision. Not after a week, not after a
quarter. Default-on-timeout is precisely the silent merge the stop exists to
prevent, and it would be worse than merging immediately because it would carry
the appearance of process.

What escalates is the noise, not the outcome:

| Age | What happens |
|---|---|
| Every session | The session-start line names the count and the ids. |
| 7 days | Re-post the stop on the tracker item, naming the person asked and the date they were asked. |
| 30 days | Close the **intent** as not-ruled. Set the ruling to `lapsed` with one line naming what was never decided. |

Lapsing expires the question, never the conflict. The active requirement still
governs, because it was never superseded — the safe default is that nothing
changed. The `C<n>` row stays open, since the ground is still contested.

If the intent comes back, raise a new `D<m>` citing the lapsed one. Do not
reopen `D<n>`: its dates record when nobody answered, and that is part of the
record. A question that lapsed twice is telling you the requirement has no
owner, which is the finding.

## When a later intent contradicts a ruling

Most reversals surface as an ordinary contradiction, because a ruling usually
leaves a requirement behind and the new intent collides with it. The dangerous
case is the ruling that left nothing to collide with — a withdrawal, or a
decision about what the system will never do. The spec has no active requirement
covering it, intake classifies the intent as **extend**, and a ruled decision is
reversed by an agent with nobody approving it.

The guard is the *Decision record* table. Intake reads the spec in full, so
after classifying an intent as extend or refine, check it against the decisions
listed there. A hit is a contradiction and stops the same way.

The stop is the same shape with one substitution: the ruling under challenge
stands where the requirement usually stands, quoted from its `Ruling` and `Not
decided` sections rather than paraphrased. Check `Not decided` first — a ruling
read wider than it was written refuses work nobody ever ruled on.

Reopening has a bar: **the new ruling must name what changed** — evidence, a
constraint, a cost, a regulation. A different person asking is not a change. Say
so in the new ruling's Reasoning, and say it whichever way the ruling goes.
Without that bar a settled question is re-argued until someone gives a different
answer, and the record shows one clean decision instead of the four attempts it
took to get it.

Two outcomes, both recorded:

- **Upheld.** `D<m>` is `ruled`; `D<n>` is untouched and still `ruled`. The new
  file is short and names what was argued and why it did not move the decision.
  Recording an upheld ruling is what stops the third attempt arriving with no
  memory of the second.
- **Reversed.** `D<n>` gains `Superseded by: D<m>` in its header and its status
  becomes `superseded`. Nothing else in it is edited — the reasoning was true
  when it was written, and rewriting it destroys the only evidence of how the
  decision looked at the time. `D<m>` gains `Supersedes: D<n>` and carries the
  spec consequences.

A ruling is never withdrawn. It happened.
