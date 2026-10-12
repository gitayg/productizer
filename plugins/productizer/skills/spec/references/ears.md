# EARS — requirements a test can assert

Easy Approach to Requirements Syntax. Five sentence patterns, one requirement
per sentence. The point is not tidiness: prose requirements read fine and cannot
be tested, so Stage 4's question — *do the tests actually assert the criteria* —
stays a matter of opinion. EARS makes it checkable, because every requirement
already names its trigger, its precondition and an observable response.

EARS is not ours. It was published by Alistair Mavin, Philip Wilkinson, Adrian
Harwood and Mark Novak as *Easy Approach to Requirements Syntax (EARS)* at the
17th IEEE International Requirements Engineering Conference (RE'09), and was
developed at Rolls-Royce to write engine-control requirements against
airworthiness regulation. That origin is the reason to use it rather than
invent a house syntax: the patterns have been applied to requirements where
being wrong is not a defect report, and they are already understood by people
who have never heard of this tool. The canonical description is at
<https://alistairmavin.com/ears/>. Where this document and Mavin's differ,
his is the standard and this one is the bug.

## The five patterns

**Ubiquitous** — always active, no precondition.
> The `<system>` shall `<response>`.

**Event-driven** — a discrete trigger.
> When `<trigger>`, the `<system>` shall `<response>`.

**State-driven** — true for the duration of a state.
> While `<state>`, the `<system>` shall `<response>`.

**Unwanted behaviour** — the error and abuse cases. Use `if`, never `when`; the
distinction is what separates a designed path from a defended one.
> If `<unwanted trigger>`, then the `<system>` shall `<response>`.

**Optional feature** — only when the feature is present in the build.
> Where `<feature is included>`, the `<system>` shall `<response>`.

**Complex** — a state and a trigger together. Stack them in this order only.
> While `<state>`, when `<trigger>`, the `<system>` shall `<response>`.

## Rules that make them testable

1. **One requirement per sentence, one `shall` per requirement.** An `and` in the
   response is two requirements wearing one id, and they will be half-tested.
2. **Name the system explicitly**, the same way every time. "The service", "it"
   and "the system" used interchangeably across a spec hide which component owns
   the behaviour.
3. **The response must be observable** from outside the thing being specified. If
   a test cannot see it, it is a design note, not a requirement — move it.
4. **Number every requirement** (`R1`, `R2`, …). The id is the handle everything
   downstream cites, and it is permanent — see *Requirement identity and
   lifecycle* below for allocation, supersession and the rules against reuse.
   The id grammar itself is normative and executable: `references/format-spec.md`
   states it, `scripts/validate-spec.py` enforces it.
5. **No unquantified adjectives and no weak words.** Fast, robust,
   user-friendly, appropriate, as needed; and the weak words `should`, `etc.`,
   `and/or`, `if possible`, `as appropriate`, `easily` and `TBD`. Each is an
   argument deferred to review. Give a number or drop it, and a `should` is a
   `shall` or it is nothing. The weak words are adapted from the AI Unified
   Process (Apache-2.0, Simon Martinelli), whose spec linter keeps the same
   list.
6. **Unwanted-behaviour requirements are not optional.** A spec with no `If`
   requirements has not considered failure, and the tests will inherit that gap.

## Requirement identity and lifecycle

The spec is not a per-feature document that gets thrown away. One living spec per
repo at `.claude/productizer/spec.md` accumulates every intent that has been merged into
it, so a requirement outlives the change that introduced it. The id is the only
stable handle the rest of the lifecycle has on a requirement, which makes id
discipline the load-bearing part of the spec rather than its housekeeping.

### Allocation

Ids are monotonic. The next requirement takes the next number, and the counter
never rewinds. Removing a requirement does not free its id: if one is gone and
the highest id ever allocated is `R<n>`, the next requirement is `R<n+1>`. Allocate
from the highest id the spec has ever used, not from the highest one still
active, and not from a count of the rows on screen.

The counter belongs to the repo, not to a file or a section. A spec that grows
past one file — split by area, by service, by anything — must still hand out ids
that are unique across the whole repo, because every citation elsewhere names
only `R14`, never the file it was living in that week.

### Never reuse, never renumber

Reusing an id is the single most damaging thing that can happen to the spec, and
it is silent. A test asserting `R14`, a plan naming `R14`, a PR titled for `R14`,
a review finding filed against `R14` — all of them keep resolving, and all of
them now point at a different requirement. Nothing errors. The suite stays green
while it asserts behaviour nobody agreed to. Renumbering does the same damage
wholesale, in one commit, to every id after the insertion point.

There is no repair short of reading every citation in the repo's history and
deciding which requirement each one meant. Treat both as prohibited.

### Supersession, not deletion

A requirement never leaves the spec. It changes status.

| Status | When | Recorded as |
|---|---|---|
| Active | Current agreed behaviour | The requirement, plain |
| Superseded | The behaviour is replaced by another requirement | `Superseded by R0.` plus one line on why |
| Withdrawn | The behaviour no longer exists at all | `Withdrawn.` plus one line on why |

The marker goes on the line directly beneath the requirement, which already
carries the id — repeating it there adds nothing. Keep the original sentence in
place under either marker; a status line without the text it applies to is not a
record. Superseded requirements point forward to
what replaced them, so a citation from two years ago still leads somewhere.
Withdrawn ones state the reason, so the next person to propose the same thing
finds out it was considered and dropped.

Deleting the row instead saves nothing and costs the spec its second job: being
a readable record of what was agreed and when.

### Contradiction is a stop, not a merge

When an incoming intent contradicts an active requirement, the work stops and a
human decides which wins. Not the agent, not the author of the intent by
implication, not whichever sentence happens to be merged last.

The reason is asymmetry of failure. A contradiction resolved silently changes
agreed behaviour with nobody approving the change, and produces a spec that is
confidently wrong — internally tidy, downstream-citable, and describing something
no one signed off. A contradiction surfaced produces a spec that is obviously
incomplete, which is a state everyone can see and act on. Prefer the visible
failure every time.

A good stop is short and decidable:

> Stop — conflict with the existing spec.
> `R14`: While a session is idle for 30 minutes, the service shall end it.
> Incoming: While a session is idle, the service shall keep it alive until the
> user signs out.
> These cannot both hold: R14 ends idle sessions, the new intent preserves them.
> Which governs?

Three things make it usable: both requirement ids quoted with their text, the
conflict stated in one sentence rather than argued, and one explicit question.
Once the human decides, record the decision — the losing requirement is marked
superseded with a pointer to the winner, and the reason line names the decision,
not just the mechanics.

### Classifying an incoming intent

At intake, every requirement in an incoming intent is one of four things against
the existing spec. Classify each one before writing anything.

| Class | Test | Action |
|---|---|---|
| **Extend** | No active requirement covers this trigger and response | Allocate new ids and append |
| **Refine** | An active requirement covers it, and the intent makes it stricter, more specific or more measurable without changing what is agreed | Edit in place, same id, record what changed and why |
| **Contradict** | An active requirement covers it and the two cannot both hold | Stop and ask |
| **Duplicate** | An active requirement already says this | Cite the id, add nothing, stop |

Practical guidance for telling them apart:

- **Match on trigger and system, not on wording.** Two sentences about "the
  export endpoint" that fire on different triggers are two requirements. Two
  sentences with the same trigger and the same system are the same requirement
  wearing different prose, however differently they read.
- **Refine versus contradict** turns on whether the old requirement stays true.
  Tightening 200 ms to 100 ms is a refinement: everything that satisfies the new
  requirement satisfied the old one. Moving 200 ms to 500 ms is a contradiction,
  however small the number looks, because behaviour previously forbidden is now
  required.
- **Refine versus extend** turns on whether the trigger is the same. Adding a
  precondition that narrows an existing requirement is a refinement. Adding a
  second trigger is a new requirement — do not bolt an `and` onto an existing
  one, which is rule 1 broken by another route.
- **Duplicate is a real outcome, not a failure to find anything to do.** Saying
  "already specified as `R23`" and stopping is the correct result for an intent
  that restates settled behaviour. Adding a near-identical requirement under a
  new id splits the citations for one behaviour across two ids, and the tests
  will follow only one of them.
- **When the classification is genuinely unclear, treat it as a contradiction**
  and ask. The cost of a needless question is one round trip; the cost of a
  wrong silent merge is a spec that lies.

Unwanted-behaviour requirements need the same pass. An incoming `if` that
defends the same trigger as an existing one with a different response is a
contradiction, not a second defence.

## Anti-patterns, with the fix

| Written as | Why it fails | Rewrite |
|---|---|---|
| The system should handle invalid input gracefully. | No trigger, no observable response, "gracefully" is unquantified | If the request body fails schema validation, then the API shall reject it with 400 and an error naming the failing field. |
| When a user logs in and their session expires, the system shall notify them. | Two requirements in one | Split: one event-driven for login, one state-driven or unwanted-behaviour for expiry. |
| The service shall be fast. | Untestable | While under 100 concurrent requests, the service shall return p95 latency under 200 ms. |
| The system shall support export. | No trigger, no actor, no shape | When an operator requests an export, the service shall write a CSV containing one row per record. |

## How this feeds the later stages

- **Stage 3** — `plan.md` names which requirement ids each file change serves. A
  requirement no file claims is a gap; a file serving no requirement is scope
  creep, and the plan-vs-diff check will say so.
- **Stage 4** — each requirement maps to at least one test. The trigger becomes
  the arrange-and-act, the response becomes the assert. A requirement with no
  test is the answer to "do the tests assert the criteria", stated as a fact
  rather than argued.
- **Stage 6** — the compliance pass reads the diff against these ids instead of
  against a paragraph of prose.

Point a criteria checker at the requirements section directly — that is what the
numbering and the one-response rule are for.

## Checking it instead of trusting it

Everything above is prose, and prose loses to a hurried agent. The two rules
that cost the most when they are broken — EARS syntax and id permanence — are
therefore also a grammar (`references/format-spec.md`) and a checker
(`scripts/validate-spec.py`, Python 3 standard library only).

```bash
python3 scripts/validate-spec.py .claude/productizer/spec.md \
                                 .claude/productizer/constitution.md \
                                 .claude/productizer/backlog.md
python3 scripts/validate-spec.py --strict .claude/productizer/spec.md
python3 scripts/validate-spec.py --self-test
```

Two severities. **ERROR** is a document that cannot be parsed or an invariant
that is broken — the failures that resolve silently downstream instead of
erroring. **WARN** is a document that parses and holds its ids but violates the
contract in a way something later mangles or half-tests. `--strict` promotes
WARN to failure; new spec content should pass it, and a spec written before the
checker existed should at minimum be ERROR-free.

Output is `file:line: SEVERITY CODE message`, sorted and free of any clock, so
it greps and it diffs. Exit 0 clean, 1 failed, 2 usage, 3 self-test failed, and
**4 for NOT MEASURED** — a file that could not be read or that holds no
requirements prints no counts at all, because a fabricated `0 errors` reads
exactly like a real one a month later.

### Requirement ids

| Code | Sev | Fires on |
|---|---|---|
| `ID_MALFORMED` | ERROR | an id that is not `R<n>`, leading zeros included |
| `ID_REUSED` | ERROR | the same id defined twice |
| `ID_AT_OR_ABOVE_COUNTER` | ERROR | an id at or above `Next requirement id` — the next allocation reuses it |
| `COUNTER_MISSING` / `COUNTER_MALFORMED` | ERROR | no usable counter, so reuse cannot be ruled out |
| `ID_OUT_OF_ORDER` | WARN | a descending id within one pattern section: the signature of an insertion or renumber |
| `ID_SEPARATOR` | WARN | something other than an em dash after the id |
| `TEXT_DUPLICATE` | WARN | one behaviour under two active ids, so its citations split |

### EARS syntax

| Code | Sev | Fires on |
|---|---|---|
| `EARS_NO_SHALL` | ERROR | no obligation stated |
| `EARS_PATTERN` | ERROR | matches none of the six patterns |
| `EARS_EMPTY` | ERROR | an id with no requirement text |
| `EARS_MULTIPLE_SHALL` | WARN | more than one obligation under one id |
| `EARS_IF_MISSING_THEN` | WARN | `If …, the system shall`, without `then` |
| `EARS_SECTION_MISMATCH` | WARN | the pattern and its heading disagree |
| `EARS_UNQUANTIFIED` | WARN | an unquantified or weak term in an active requirement: `adequate(ly)`, `appropriate(ly)`, `as needed`, `easy`, `efficient(ly)`, `fast`, `flexible`, `gracefully`, `intuitive`, `optimal`, `performant`, `properly`, `quick(ly)`, `reasonable`/`reasonably`, `reliable`/`reliably`, `robust`, `scalable`, `seamless(ly)`, `sufficient(ly)`, `timely`, `user-friendly`, `where possible`, and the weak words `and/or`, `as appropriate`, `easily`, `etc.`, `if possible`, `should`, `TBD`. Case-insensitive, whole words. Not judged: superseded or withdrawn text (retained verbatim), and a term inside a code span, which mentions the word rather than using it |
| `EARS_NO_FULL_STOP` | WARN | one requirement is one sentence |

### Supersession and permanence

| Code | Sev | Fires on |
|---|---|---|
| `SUPERSEDED_TEXT_OVERWRITTEN` | ERROR | a superseded requirement carrying its replacement's text |
| `STATUS_MALFORMED` | ERROR | a marker that is neither `Superseded by R<n>.` nor `Withdrawn.` |
| `STATUS_DUPLICATE` | ERROR | two status markers on one requirement |
| `SUPERSEDE_SELF` | ERROR | a requirement superseded by itself |
| `SUPERSEDE_TARGET_ABSENT` | WARN | the replacement is not in the files given — legal only for a split spec |
| `SUPERSEDE_BACKWARD` | WARN | superseded by a *lower* id; a replacement is newly allocated |
| `STATUS_NO_REASON` | WARN | the marker records that it changed, not why |

### Against a previous copy (`--baseline`)

A renumber cannot be seen in one file — a renumbered spec is internally
consistent. Against an earlier copy it is arithmetic:

| Code | Sev | Fires on |
|---|---|---|
| `RENUMBERED` | ERROR | agreed text now carrying a different id |
| `ID_DISAPPEARED` | ERROR | an id in the baseline and not in the file: a deletion |
| `SUPERSEDED_TEXT_CHANGED` | ERROR | a superseded or withdrawn requirement whose text was edited rather than retained |
| `ID_IDENTITY_CHANGED` | ERROR | an active requirement rewritten wholesale under the same id |
| `PATTERN_CHANGED` | ERROR | the trigger changed pattern, which makes it a different requirement |
| `COUNTER_REWOUND` | ERROR | the counter went backwards |
| `STATUS_REVERTED` | WARN | superseded or withdrawn, now active again |

### Constitution and backlog

`PRINCIPLE_MALFORMED`, `PRINCIPLE_ID_REUSED`, `PRINCIPLE_ID_PREFIX` (an `R` id
inside `## Principles`), `PRINCIPLE_ID_AT_OR_ABOVE_COUNTER`,
`PRINCIPLE_COUNTER_MISSING` / `_MALFORMED`, `PRINCIPLE_STATUS_MISSING` and
`PRINCIPLE_STATUS_MALFORMED` are ERROR; `PRINCIPLE_NO_CHECK` (a principle
nothing checks is a slogan), `PRINCIPLE_NO_RATIFIER`, `PRINCIPLE_NO_DATE`,
`PRINCIPLE_SUPERSEDE_TARGET_ABSENT`, `PRINCIPLE_ENFORCED_UNKNOWN`,
`PRINCIPLE_TOO_MANY` and `PRINCIPLE_CHECK_ABSENT` (under `--repo` only: an active
principle's `Checked by` names a script, `*.sh`, `*.py` or `*.js`, and no file
of that name exists anywhere under the root) are WARN. The backlog carries the same id checks under
`BACKLOG_*`, plus `BACKLOG_STATUS_UNKNOWN` for a status outside the vocabulary
on a row that names no Jira key.

Whole-document failures — `KIND_UNKNOWN`, `NO_REQUIREMENTS_SECTION`,
`NO_REQUIREMENTS`, `NO_PRINCIPLES*`, `NO_BACKLOG_ITEMS*`, `IO` — all exit 4 and
report NOT MEASURED rather than a count.

### What it does not catch

The blind spots matter more than the coverage, because an undocumented one
turns "nobody looked" into "it passed". The full list is in
`references/format-spec.md`; the ones worth carrying in your head:

- **A renumber, without `--baseline`.** In-file you get the signatures, not the
  fact.
- **A refinement that is really a contradiction.** `200 ms → 100 ms` and
  `200 ms → 500 ms` look identical to a text differ. That is
  `scripts/contradiction-check.py`'s question, and even it answers UNDECIDED
  rather than guessing.
  <!-- EXAMPLE:BEGIN -->
- **Whether a reason line is true.** `Superseded by R41. Because.` is
  grammatical.
  <!-- EXAMPLE:END -->
- **System-name drift.** `ears.md` rule 2 asks for one system noun; the real
  spec uses four, some of them genuinely sub-components. No grammar separates a
  component from drift, so it is not enforced.
- **Whether a requirement is correct.** Which is what Stage 2's review is for.

One inconsistency is worth knowing before you run it: rule 1 above says one
`shall` per requirement, and this repo's own spec breaks it at **R14**, **R16**
and **R21**. That is why `EARS_MULTIPLE_SHALL` is WARN rather than ERROR — the
spec is green by default and fails `--strict` until the three are split or the
rule is amended. Reporting it clean would make rule 1 decorative.

## All five, and why that is not what "EARS support" usually means

Five patterns is the whole grammar, and dropping any of them is not a
simplification — it removes the requirements that pattern was the only way to
express. Without **While**, a requirement that holds for the duration of a state
gets rewritten as an event and loses the state. Without **Where**, an
optional-feature requirement becomes an unconditional one, which is a different
and stronger claim than anyone agreed to. Without the `If`/`when` split, a
defended failure path and a designed happy path become the same sentence shape,
and the spec stops recording which is which.

This matters because the surrounding ecosystem is not shipping five. Surveying
the spec-driven tools in September 2026, the most-starred EARS-adjacent MCP
server drops **While** and **Where** entirely, conflates event-driven with
unwanted-behaviour, and never uses the word EARS anywhere in its documentation.
What propagates under the name is frequently an unattributed three-line subset.
A request to add EARS validation to one of the largest spec-driven frameworks
was closed with no maintainer response.

So "supports EARS" is not a capability claim worth trusting on its own, and it
is not one this document asks anyone to take on trust either. The check is
mechanical: `scripts/validate-spec.py` compiles a pattern for each of the six
forms — complex, state-driven, event-driven, unwanted-behaviour,
optional-feature and ubiquitous — and a requirement matching none of them is
reported by id. It additionally enforces one `shall` per requirement, a named
system before the `shall`, and the `If <trigger>, then the <system> shall
<response>.` form specifically. Run it against a spec and read the output; that
is a shorter route to the truth than reading anyone's feature list, including
this one.

## What EARS does not do

It does not make a requirement correct, only unambiguous. A precisely worded
requirement can still be the wrong thing to build, which is what Stage 2's review
against `intent.md` is for. It also does not suit everything: a genuinely
narrative constraint ("this must not surprise existing API consumers") is better
as a design note than as a `shall` sentence contorted into a pattern.
