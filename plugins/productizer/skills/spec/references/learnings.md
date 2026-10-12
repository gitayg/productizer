# Learnings — what was noticed, kept below the spec

The living spec answers one question: what does this system do. Everything in
it is an obligation somebody agreed to, and every id in it can be held against
a test.

Work produces a second kind of knowledge that answers nothing of the sort. "The
build fails unless the generator is run first" is true, useful, expensive to
rediscover — and it is nobody's obligation. No one agreed to it, no test can
hold anyone to it, and there is no one to hold. Forced into `spec.md` it does
not become a requirement; it corrupts the one thing that file is for, because a
reader can no longer tell which lines were agreed and which were merely
noticed.

So there is a storage gap, not only a retrieval one, and the answer is a store
beside the spec and **below** it.

## Where learnings live

```
.claude/productizer/learnings/L<n>-<slug>.md
```

One file per learning, committed to the repo beside the spec. Shape:
`templates/learnings.md`. Written and read by `scripts/learnings.sh`.

This is deliberately the same shape as `rulings/`, and for the same reasons:

- **Committed, not ticketed.** A learning that lives only in a chat log or an
  issue comment leaves with the tracker and takes the reason for itself with it.
- **Beside the spec, not inside it.** The spec records what is agreed. At fifty
  learnings, inlining them buries the requirements they sit under.
- **`.claude/` is routinely gitignored.** `learnings.sh add` runs
  `git check-ignore` on the path it just wrote and warns on stdout's sibling
  stream when it is ignored. A store that cannot be committed is a local notes
  folder wearing the name of a record.
- **Cite `L7`, never the path.** The slug is decoration for humans scanning
  `ls`. A tidy-up rename breaks every path reference, silently.
- **One file per learning, not one file of learnings.** A single appended file
  is one line of `git blame` per entry and a merge conflict per parallel
  session, and — the operative reason here — it collapses the three store
  states below into one. There is no directory to be absent, so "nobody has
  ever recorded a learning" and "there are none right now" become the same
  observation, which is the exact fabricated-zero this product refuses. The
  rejected alternative was an append-only `learnings.jsonl`; it is cheaper to
  write and it cannot make that distinction.

## Ids: `L`, its own space

**Learnings get `L1`, `L2`, …** allocated max + 1, never filling a gap. A gap
is a file that was removed, and filling it re-points every citation that named
the old one.

The prefix is free and had to be. `R` is requirements, `P` is principles, `D`
is rulings, `C` is the *Areas of concern* rows, `B` is the backlog. A grep for
`\bL[0-9]+\b` across the plugin, the spec home and the repo scripts returns
nothing, so no existing citation can be re-resolved by introducing this one.
`L` also reads as what it is at a glance, which matters in a store whose whole
risk is being mistaken for the spec. Jira keys carry a dash (`PROJ-123`), so a
bare `L7` cannot be confused with one either.

Ids are permanent, monotonic and never reused, exactly as in the spec. A
learning is never deleted and never rewritten after the fact — it changes
status. The observation was true *as an observation* when it was written, and
editing it destroys the only evidence of how it looked before anyone knew
better.

| Status | Meaning |
|---|---|
| `unverified` | Observed once. Nothing independent has confirmed it. **The default.** |
| `verified` | Corroborated by a source that is not the one that observed it. |
| `graduated` | Turned out to be an obligation. It is now an `R` id and stops being served. |
| `withdrawn` | Observed to be false. Kept, because the record of a wrong belief is worth having. |

## Subordinate to the spec, and what that means mechanically

A learning **informs; it never obligates and it never outranks a requirement.**
Three consequences, all enforced somewhere rather than asserted here:

1. **Obligation language is a finding.** `check` scans the quoted observation
   of every `unverified` learning for `must`, `shall`, `always`, `never`,
   `required`, `mandatory`, `guaranteed`, and reports each hit by file and
   line. An observation written as an instruction reads as a requirement to
   every later reader, and it got there without passing intake.
2. **A learning that contradicts an active requirement is a finding, not a
   fact.** It goes through intake like any other intent — the same road Stage 9
   uses for code-versus-spec drift. No script decides this; it needs a reader,
   and that limitation is printed in `check`'s own output.
   <!-- EXAMPLE:BEGIN -->
3. **Graduation is one-way and recorded.** When an observation turns out to be
   a real obligation, the requirement is merged into the spec first — an id in
   the spec *is* the merge — and `learnings.sh graduate --id L7 --to R58` then
   records that it happened. The learning keeps `L7` so the trail from "someone
   noticed this" to "the spec now requires it" survives, and stops being served.
   `graduate` refuses an `R` id the spec does not define or no longer marks
   active: a trail to nowhere is worse than no trail, because it looks like one.
   <!-- EXAMPLE:END -->

## The citation, and the check it makes possible

`About: R14, R19` is the one thing this store can do that a free-text notes
file cannot. Because ids are permanent, a citation stays meaningful for as long
as the spec does — so **"this learning is about a requirement that has since
been superseded" is mechanically detectable.**

`check` resolves every citation against the same spec baseline
`drift-reverse.sh` walks the code with, parsed with the same awk pattern
matching `**R<n>**` definitions and the `Superseded by` / `Withdrawn.` line
beneath them. That pattern now has four readers; the copy is noted in each of
them, because four counters for one number disagree the moment one is edited.

Three outcomes, all findings:

| What the citation resolves to | Why it is reported |
|---|---|
| superseded / withdrawn | The learning is about an agreement that no longer governs. It may still be true; it is certainly no longer about what it says it is about. |
| absent from the spec | The spec never deletes, so an id it does not hold resolves to nothing. |
| not a bare `R<n>` | A citation nothing can resolve is decoration. |

`add` resolves `--about` **before** it writes anything and refuses a dead or
absent id. A learning created citing a superseded requirement is stale on the
day it is born, and the check that should have caught a real decay would then
be reporting the store's own scaffolding.

## Unverified by default, and why the corroborator must differ

`add` always writes `Status: unverified`. There is no flag to skip it.

`verify --id L7 --by <source>` **refuses when `--by` equals the `Observed by:`
line.** This is the whole mechanism, not a nicety: a run that can confirm its
own learning promotes whatever it just wrote, and from that moment `verified`
means nothing anywhere in the store. The refusal is exit 6 and it names the
reason.

The template asks for *What would corroborate it* at the moment the learning is
written, while the observation is fresh. Written afterwards, whatever evidence
happens to turn up looks exactly like the evidence that was wanted.

**What corroboration is not:** proof. `check` verifies states, dates, fields
and citations. Whether a learning is *true* is not checkable and is not
claimed — a corroborated learning that is wrong passes every line of the check,
and the check says so in its own output.

**The corroboration threshold is one independent source, and that number is not
derived.** It is the smallest value that enforces the rule above, and it is a
placeholder for a number a corpus audit should set: how many independent
observations a repo actually produces for one recurring fact, measured over a
real store. Until that audit exists, do not raise the threshold on judgement —
a gate tuned by taste is a gate whose number nobody can defend, and the two
rejected alternatives were both taste. Rejected: *two independent sources*
(defensible-sounding, but a store that never accumulates two observations of
anything would then hold nothing verified, which is a gate that passes nothing
— the mirror of a gate that passes everything, and no better); and *no
threshold at all, a human flips the state* (removes the one automatic refusal
that makes the state mean anything).

## Staleness is derived, never stored

Age comes from `Observed:`, computed against today in UTC. There is no `stale`
field and there will not be one — a stored flag has to be updated by someone,
and nobody will.

`--dormant-after DAYS` (default 180) moves an old learning to `dormant` in the
listing. **Dormancy is presentation.** It is not a finding, it fails nothing,
and it deletes nothing: a dormant learning is still there, still cited, still
readable. Serving it less is the entire effect.

That default is also not derived, and it is only allowed to be undefended
because of what it does *not* do. A horizon that deleted, or failed a check,
would need a number somebody could defend. One that changes a column does not.

**A date that does not parse gives an age of an em dash — never an age of
forever.** Reading an unreadable date as infinitely old buries exactly the
entries with the least provenance to recover them by, and it does it silently.

## Three states of the store, never collapsed

This is P1 — *a value that was not measured is never recorded as a
measurement* — applied to a directory.

| State | Word | Count | Exit |
|---|---|---|---|
| The directory does not exist | `never-recorded` | an em dash | 5 |
| It exists and cannot be opened | `unknown` | an em dash | 3 |
| It exists, is readable, holds no learning | `empty` | `0` | 0 |

Only the third is a zero, and it is a measured one. The first two are reported
as unmeasured and exit non-zero so that no caller can mistake either for a
clean, empty store.

An unmatched glob arrives at bash as a literal path, so `L*.md` expanding to
nothing proves nothing at all. The states are told apart by an explicit
directory test — `-e`, then `-d`, then `-r` and `-x` — and never by trusting a
count that came out of a loop.

## Reporting by location, never by quoting content

A learning is free text a stranger can write, and this output lands in a
model's context before a human has read a word of it.

Every subcommand emits **ids, statuses, dates, counts and paths**. Never the
title, never the observation, never the provenance string. `check` reports a
finding as `<path>:<line>: <what class of problem>` and expects the reader to
open the file — the same rule `check-hygiene.sh` follows, and for the same
reason it learned it: printing the offending line put the offending content
into a committed report, so finding a leak created one.

Inside the file the observation is written as a markdown blockquote, so no line
of it can forge a `Status:` header for a counter to match, or a `##` heading
for a reader to trust.

## The table

`list --format table` emits a markdown table, which `build-view.sh` parses. A
cell containing a literal `|` tears the row and silently re-columns everything
after it, so every cell goes through one escaping helper on its way out — even
the ones that are ids and dates and cannot contain a pipe. The exception is the
habit that eventually ships the bug.

An `unverified` row does not render as the bare word. It renders as
`UNVERIFIED - not corroborated`, because a status word in a status column
disappears at a glance and this is the one thing about a learning a reader must
not miss.

## Using it

<!-- EXAMPLE:BEGIN -->
```bash
S=plugins/productizer/skills/spec/scripts/learnings.sh

# record what was seen. Provenance is required; unverified is not optional.
bash "$S" add --what-file /tmp/observation.txt \
              --source 'ci run 4182' --about R14 --slug generator-ordering

bash "$S" list                     # ids, states, ages, locations
bash "$S" list --format count
bash "$S" check                    # citations, fields, states, obligation language

bash "$S" verify   --id L1 --by 'session 2026-08-30'   # refuses the observer
bash "$S" graduate --id L1 --to R58                     # after R58 is merged
```
<!-- EXAMPLE:END -->

`--root` defaults to `git rev-parse --show-toplevel`, never the working
directory. A default of `.` resolves to a different store from every
subdirectory and answers confidently from the wrong one; that class of bug has
been paid for here four separate times.

Exit codes are the contract: `0` did the thing or measured a clean check, `1`
findings, `2` usage, `3` an input could not be read, `4` cannot determine, `5`
the store has never been created, `6` refused.

## What this store cannot do

- **It cannot tell you whether a learning is true.** Nothing here reads the
  world. `verified` means a second source said so, which is a procedural fact,
  not a factual one.
- **It cannot detect a learning that contradicts an active requirement.** That
  needs a reader. It is a finding for intake, and routing it there is a human
  step.
- **It cannot find the learning nobody wrote down.** Everything here is
  precision data — what somebody bothered to record. There is no view of the
  recall gap and there cannot be one.
- **It cannot stop a learning being read as a rule.** It can refuse obligation
  language, mark unverified rows loudly, and keep the file below the spec.
  Whether a reader honours the tier is not mechanically enforceable, which is
  why the tier is stated in the first line of every file the store writes.
