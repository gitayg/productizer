# <Product> — backlog

Everything wanted and not yet agreed. This is the queue **in front of** the
lifecycle: nothing here has been through intake, so nothing here is a
requirement. An item leaves this file by becoming an intent at Stage 1, and what
happens to it after that is decided by intake, not by whoever wrote it down.

Location
: `.claude/productizer/backlog.md`, beside the living spec, in the spec home repo.

Order is priority
: Top is next. The file's order **is** the ranking — there is no priority field,
because two orderings disagree the moment someone edits one and not the other.
Reordering is an ordinary edit and needs no ceremony: nothing here is agreed, so
nothing is being changed by moving it.

Ids
: Backlog items take `B<n>` and keep it. `B` never shares a counter with `R`
(requirements), `P` (principles) or `D` (rulings). An item that becomes an
intent keeps its `B` id in the intent so the trail from "someone wanted this" to
"the spec now says this" survives.

Next backlog id
: `B<n>`

## Status

| Status | Means | Who moves it |
|---|---|---|
| `todo` | wanted, ready to be picked up | anyone |
| `long-term` | wanted, deliberately not now | anyone, with a reason |
| `in-progress` | Stage 1 has started on it | whoever started |
| `blocked` | cannot proceed, and the blocker is named | whoever found the blocker |
| `done` | it went through intake and reached the spec, or was refused | intake |

**`done` does not mean built.** It means the item left this queue — merged as a
requirement, ruled a duplicate, or refused. The spec records which. A backlog
that reuses `done` to mean shipped starts competing with the spec for the
answer to "what does this system do", and loses.

**An item with a Jira key does not carry its own status.** See below.

## Items

Highest priority first.

| Id | What is wanted | Status | Jira | Raised | Notes |
|---|---|---|---|---|---|
| B7 | &lt;in the words of whoever wants it&gt; | `todo` | — | &lt;who, when&gt; | &lt;why now&gt; |
| B6 | &lt;…&gt; | `in-progress` | `PROJ-412` | &lt;who, when&gt; | intent #128 |
| B4 | &lt;…&gt; | `long-term` | — | &lt;who, when&gt; | waiting on &lt;the thing&gt; |
| B2 | &lt;…&gt; | `blocked` | `PROJ-380` | &lt;who, when&gt; | blocked by &lt;named blocker&gt; |

Write the item in the words of the person who wants it. A backlog rewritten into
implementation language has already made design decisions, and intake will
classify against those decisions instead of against the need.

## Items tracked in Jira

An item may name a Jira key. When it does:

- **Jira owns the status.** The `Status` column shows what Jira last said, and
  the local status vocabulary above does not apply. Two systems tracking one
  item's state disagree within a week, and the one people update is the one
  people look at.
- **The mapping is declared once**, in `.claude/productizer/config.json` under
  `jira.status_map`, so "In Progress" and "In Review" resolve to the same
  thing without anyone guessing per item. Both of those are statuses Jira
  documents as defaults; the map also carries three that it does not, and
  says so on the block itself. **Read your own project's statuses before
  trusting any of it** — status NAMES are per project, and only the three
  status CATEGORIES are stable across instances.
- **Nothing is written back to Jira from here.** Reading is safe; writing puts
  this file in an argument with a workflow, a board and an automation rule that
  it will lose. Moving a Jira ticket happens in Jira.
- **The key is the join.** Never re-title an item to match its ticket — titles
  drift, keys do not.
- **If Jira cannot be read**, say so on the row rather than showing a stale
  status as if it were current. `status: unknown (Jira unreachable <when>)`.

## Starting work

Moving an item to `in-progress` is Stage 1: it becomes an intent, gets an issue,
and enters intake. Record the issue number in Notes so the item and the intent
point at each other.

**Starting work does not agree anything.** An item can be picked up, taken
through intake, and refused because it contradicts a requirement someone agreed
to two years ago. That is intake working, not a mistake — and it is the reason
the backlog is not the spec.

## What does not belong here

- **Requirements.** If it is agreed, it belongs in the spec with an `R` id.
- **Bugs against agreed behaviour.** Those are drift or incidents: they enter at
  Stage 1 as their own intent and get fixed against a requirement that already
  exists.
- **Anything already in the spec.** Intake will classify it a duplicate, which
  is the correct answer arrived at expensively.
