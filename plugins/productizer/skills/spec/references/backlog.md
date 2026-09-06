# The backlog — the queue in front of the lifecycle

Stage 1 assumes an intent exists. In practice the intent arrives weeks after
somebody first wanted the thing, and in between it lives in a head, a Slack
thread or a ticket nobody has read since. The backlog is where that waiting
happens on purpose.

Template: `templates/backlog.md`. Lives at `.claude/productizer/backlog.md`.

## It is not the spec, and the distinction is the whole point

The spec holds what the product has **agreed** to do. The backlog holds what
somebody **wants**. Nothing in it has been classified, so nothing in it is
binding, and an item can be refused at intake for contradicting a requirement
agreed two years ago.

That refusal is the system working. A backlog whose items are treated as
commitments is a second spec written by whoever shouts loudest, and it will
contradict the first one silently — which is precisely the failure the
contradiction halt exists to prevent, arriving through the back door.

So: **`B` ids never merge into `R` ids.** An item that becomes a requirement
keeps its `B` id in the intent and the requirement takes a fresh `R`. The two
spaces stay separate because they answer different questions — "who wanted
this, when" against "what does the system do".

## Order is the priority, and there is no priority field

The file's order is the ranking. No `priority: high` column, no P1/P2/P3.

Two representations of one ordering disagree the first time someone edits one
and not the other, and then nobody can say which is the real queue. A single
ordered list cannot drift from itself.

This also makes reordering cheap, which matters more than it sounds: a priority
scheme with ceremony around it does not get updated, and a backlog nobody
reorders is a list of everything ever suggested, sorted by date. Moving an item
changes nothing that was agreed, so it needs no approval and no record.

## Statuses, and the one that lies

Five: `todo`, `long-term`, `in-progress`, `blocked`, `done`.

`long-term` earns its place by being honest. Without it, everything anyone might
ever want sits in `todo`, the list runs to two hundred items, and people stop
reading it — at which point the backlog has stopped working while still looking
maintained. `long-term` says *wanted, deliberately not now*, and it wants a
reason beside it.

`done` is the one that lies if you let it. It means **the item left this queue**
— merged as a requirement, ruled a duplicate, or refused — not that anything
shipped. What shipped is a question for the spec and the release history. A
backlog that answers it too starts competing with the spec, and the spec is the
one under version control with an id space and a contradiction check.

## Jira: read the status, never write it

An item may carry a Jira key, and when it does, **Jira owns its status**.

- The local vocabulary stops applying. The row shows what Jira last said.
- The mapping between Jira's workflow states and these five is declared once in
  `.claude/productizer/config.json` under `jira.status_map`, not guessed per item.
  **The shipped map is a starting point that has never met a live Jira** — see
  *The status map is unverified* below before you trust a row it produced.
- **Nothing is written back.** This file does not move tickets. A markdown table
  arguing with a Jira workflow, a board filter and three automation rules loses,
  and it loses silently — the write appears to succeed and a rule reverts it an
  hour later. Move the ticket in Jira.
- **The key is the join, never the title.** Titles drift on both sides; keys do
  not. This is the same rule the spec follows for requirement ids and for the
  same reason.
- **In a published view the key is a link**, built from `jira.site` in
  `.claude/productizer/config.json` as `<site>/browse/<KEY>`. A key rendered as plain text
  makes the reader copy it into a search box, and half of them will not bother —
  at which point the status on the row is the only thing anyone ever reads, and
  it is the one thing this file does not own.
- **Unreachable Jira is a stated fact, not a stale number.** Show
  `unknown (Jira unreachable <when>)`. A status shown without qualification is
  read as current, and a stale "In Progress" is worse than no status at all
  because someone will plan around it.

## The status map is unverified

**As of 2026-09-06 not one entry in the shipped `jira.status_map` has been run
against a real Jira instance.** Eleven states are mapped and zero were tested.
The template ships them because a map has to start somewhere, not because they
were confirmed. Read them as a guess with a date on it.

What *was* done on that date is a check against Atlassian's own documentation,
which is enough to say three useful things.

**One more thing to know before writing a consumer, measured 2026-09-06:**
`status_map` carries **twelve** keys, not eleven. The twelfth is `_note`,
the paragraph above living inside the block it documents. Nothing reads
the map today — `status_map` appears only in these documents, the template
and a generated page, in no `.sh` and no `.py` — so the extra key is inert.
The first consumer written will iterate it and find a status named `_note`
mapping to a wall of prose. Skip keys beginning `_`, or move the note out
before you read the map; do not discover this from a backlog row that says
an item is `_note`.

**Status names are per project, so no shipped list can be right everywhere.**
Atlassian's Jira Cloud platform OpenAPI
(`developer.atlassian.com/cloud/jira/platform/swagger-v3.v3.json`, retrieved
2026-09-06) documents `GET /rest/api/3/project/{projectIdOrKey}/statuses` as
"Returns the valid statuses for a project. The statuses are grouped by issue
type, as each project has a set of valid issue types and each issue type has a
set of valid statuses." A status is scoped `PROJECT` or `GLOBAL`, and creating
one takes any name up to 255 characters. Whatever your board calls its states,
it is the map that has to move.

**The category is the only thing stable across instances, and there are exactly
three.** "All statuses, even custom statuses you create yourself, must belong to
one of three status categories – To do, In progress, or Done."
(`support.atlassian.com/jira-cloud-administration/docs/what-is-a-workflow-status/`,
retrieved 2026-09-06). The same OpenAPI types `statusCategory` as a closed enum,
`TODO | IN_PROGRESS | DONE`. That is why the map keys on names rather than
categories: three categories cannot express `blocked` or `long-term`, and losing
those two would cost more than the map's inaccuracy does. But it follows that an
unmapped name is never *unknown* — it has a category, and the category answers.
Fall back to `TODO → todo`, `IN_PROGRESS → in-progress`, `DONE → done`, and say
on the row that the fallback was used, for the same reason an unreachable Jira
is stated rather than rounded off.

**Seven of the eleven are real defaults, three were invented, one is not a
status at all.** Measured 2026-09-06 against Atlassian's list of the statuses
that ship with Jira
(`support.atlassian.com/jira-cloud-administration/docs/what-are-issue-statuses-priorities-and-resolutions/`):

- **Named there:** `To Do`, `Backlog`, `Selected for Development`,
  `In Progress`, `In Review`, `Done`, `Closed`.
- **Not on that page:** `In Dev`, `On Hold`, `Blocked`. Plausible team
  conventions, and an admin may well have created them — but Jira does not
  supply them, so a repo that inherits these three has inherited somebody's
  habits.
- **Not a status:** `Won't Do`. That page lists "Won't do" under *resolutions*,
  and spells it with a lower-case d. A resolution never appears where a status
  name is compared, so the row cannot fire unless someone has separately made a
  status by that name. It is kept rather than deleted because names are
  arbitrary and deleting it would be its own guess.

Matching is exact-string, and Atlassian's own pages spell one state both
"In Progress" and "In progress" — which is the last argument for reading the
project's statuses instead of trusting the eleven.

See `references/integrations.md` for the binding, and `templates/jira-intent.md`
for how an intent joins its ticket once work starts.

## Why the published view may reorder, when no other view may

Every other view in this lifecycle is strictly read-only, and
`references/views.md` is emphatic about it: *nothing is ever read back out of a
view into the spec*, because a view that becomes editable stops the committed
chain being the audit trail.

The backlog view is the one place that rule can relax, and only because of what
the backlog is. Reordering changes **nothing that was agreed** — it does not
touch a requirement, a ruling or a principle, and it produces no claim about the
product. The audit trail is untouched by moving `B7` above `B4`.

Even so, the view does not write the file. It cannot: a published page has no
filesystem. What it does is let you drag items into the order you want and then
hand you the reordered table to paste, or a prompt that applies it. **The file
stays the source of truth and the only edit surface** — the drag is a way of
composing an edit, not a way of skipping one.

Adding an item is the same: the view can compose one, and the file records it.

**Every row carries its own action.** `start work` on an item names *that* item —
its id, its text, its Jira key if it has one — so nothing has to be re-typed or
re-identified, and the prompt it hands over says what Stage 1 must do: classify
against the whole spec before anything is planned, record the issue in Notes,
and **stop if it contradicts something agreed**. An item already `in-progress`
offers `open it` instead: where it got to, and what is holding it.

**Sorting by status is a way of looking, not a reordering — and the view has to
know the difference.** While the list is grouped by status, its visible order is
no longer the ranking. So dragging is disabled and the copy-back is withdrawn:
the only thing worse than a stale priority order is one that was silently
rewritten by a sort. Switching back to rank restores the file's order exactly.

Status precedence for that grouping is `in-progress`, `blocked`, `todo`,
`long-term`, `done` — what is moving first, what is stuck second, and what is
deliberately parked near the bottom. Within a group, file order is preserved.

## What does not belong in it

- **Requirements.** Agreed behaviour has an `R` id and lives in the spec.
- **Bugs against agreed behaviour.** That is drift or an incident, and it enters
  at Stage 1 against the requirement it violates (`references/drift.md`).
- **Anything already specified.** Intake will rule it a duplicate — the right
  answer, reached expensively. Check the spec first.

## Bug or feature — the tracker already knows

There is no `Kind` column and there will not be one. The tracker has `bug` and
`enhancement`, they mean exactly this, and a second field saying what the first
one says disagrees with it the moment someone edits one and not the other. That
is the same reason there is no priority column.

**bug** — something already agreed is not being honoured, or cannot be. Code
failing a requirement, or a requirement that is unfollowable as written.

**enhancement** — nothing agreed covers it yet.

**The kind belongs to the intent, not to the backlog item.** You cannot know
which one something is until it has been classified against the spec: "the
system fails a requirement" is a claim about a requirement that exists, and an
item sitting in the queue has not been checked against anything. Labelling it
when it is written down decides at the wrong moment, by the wrong person, using
the least information anyone will ever have about it.

So the label goes on at intake, on the issue, by whoever classified it.
