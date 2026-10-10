# Drift — checking whether the code still does what the spec says

The lifecycle closes intent → spec → code. Nothing closes the other direction.
A requirement can stop being true without any intent arriving: refactored away,
disabled behind a flag, broken by a change nobody connected to it. The spec goes
on asserting it.

That is a spec that lies, and it is worse than no spec. No spec makes nobody
read it; a lying spec is read, cited in reviews, planned from, and turned into
acceptance criteria that assert behaviour the system no longer has.

The drift check is the reverse read: **does the code still honour the spec?** It
produces findings for a human to rule on. It never changes a requirement.

## What it is not

- Not intake. Intake classifies an *intent* against the spec. Drift compares
  *shipped code* against the spec, and there is no intent involved — that is
  precisely the gap.
- Not a review pass. Review judges a diff against requirements the diff cites.
  Drift judges the whole active requirement set against the whole codebase, and
  the requirements nobody has touched for a year are the ones it exists for.
- Not a gate. It is expensive and partly judgement-based; wiring it into a merge
  gate produces false refusals, and a gate that refuses wrongly gets disabled.

## Evidence that a requirement is honoured

Rank every finding by the strongest evidence available for it. The rank is part
of the finding — a conclusion drawn from code reading must never be reported at
the same weight as a passing test.

| Rank | Evidence | Reads as |
|---|---|---|
| 1 | The requirement's acceptance-criteria test passed in the latest run on the default branch | honoured |
| 2 | An indirect check covers the same observable — contract test, schema check, runtime assertion, a metric with a band | honoured, name the check |
| 3 | Code inspection: the path exists and produces the requirement's observable response, cited `file:line` | likely honoured, low confidence |
| 4 | Nothing found either way | **unverified** — not a gap |

Rules that keep the ladder honest:

- **A test that exists and fails is not weak evidence — it is a finding.** Rank
  1 requires a pass. A failing acceptance test is the strongest possible
  evidence of drift, not an absence of evidence.
- **A skipped, quarantined or `xfail` test is rank 4, not rank 1.** A suite that
  reports green while the case never executes is absence dressed as evidence,
  and it is the single most common way drift goes unnoticed for a year.
- **A stale run is not a run.** Name the run id and its commit. If the newest
  run predates the head of the default branch, drop to rank 3.
- **State the configuration you evaluated.** Behaviour reachable only behind a
  flag that is off in production is not honoured in the default configuration.
  Report it as `specified-not-implemented (flag: <name>, off)` — the requirement
  says the system shall, not that it could if switched on.
- **Not every requirement has a test, and that is expected.** The spec's
  acceptance-criteria table already tracks that; a requirement it lists as
  unmapped starts at rank 3 at best, and the finding is about coverage, not
  about the code being wrong.
- **Absence of evidence is its own bucket.** Never fold rank 4 into
  `specified-not-implemented`. Reporting "unverified" as "not implemented" sends
  a human to look for a bug that does not exist, and after the second time they
  stop reading the report.

## Gap types

Exactly four outcomes of a comparison. Every row in the report is one of them.

**`implemented-not-specified`** — the code does something no active requirement
asks for. Usually a feature that shipped without going through intake, or
behaviour that grew out of a bug fix. It is a candidate intent, not a missing
requirement: it goes to intake as an `extend` if a human wants it agreed, and to
an issue if they want it removed. Scope that nobody agreed to is the ordinary
cause.

**`specified-not-implemented`** — an active requirement with no code and no
check honouring it. Three usual causes, and the report should guess which:
never built (the spec PR merged, the code PR did not), refactored away, or
switched off behind a flag.

**`contradicts`** — the code observably does the opposite of what the
requirement says. The strongest finding class and the rarest. Cite the
requirement sentence and the `file:line` or the failing test that shows the
opposite. Treat it exactly as intake treats a contradiction: a stop, ruled on by
a human.

**`unverified`** — no evidence either way. Report the count and the ids; do not
propose a disposition for these beyond "add a check".

## What the tool does about it

It writes a report and raises questions. It changes no agreed behaviour.

- **It never edits a requirement.** Not the sentence, not the status marker, not
  its acceptance-criteria row, not the counter.
- **It never deletes.** Marking a requirement `Withdrawn.` is a spec write, and
  a spec write follows a recorded ruling. *"Nothing is ever deleted. A
  superseded or withdrawn requirement keeps its original sentence, in place."*
- **It never allocates a requirement id.** Specifying discovered behaviour is an
  intake `extend`, and the allocator has one writer
  (`references/spec-stores.md`).
- **The one thing it does write to the spec is a concern.** Raising a ruling
  adds a `C<n>` row to *Areas of concern* and a `D<n>` ruling file, per
  `references/rulings.md`. That records a question; it agrees nothing.
- **It opens issues, not commits to code.** A finding a human accepts becomes an
  issue — the same door Stage 1 uses — and re-enters the lifecycle at intake.

The output is `templates/converge.md`: a report with one row per finding, a
proposed disposition, and an empty ruling column.

**Finding ids are local to the report.** `F1`, `F2` number the rows of one run
and are cited nowhere else. Permanence belongs to the ids that carry agreements
— the requirement `R<n>`, the concern `C<n>`, the ruling `D<n>` — and inventing
a fourth permanent id space for observations that expire on the next run buys a
counter to get wrong.

## Why not just update the spec to match the code

Because it resolves the argument in favour of whatever was last shipped, which
is backwards for a tool whose entire premise is that agreed behaviour outranks
accidents.

Tessl's spec-driven tile instructs the opposite — *"update the spec to match
current implementation"* when the spec is stale. Concretely, that is wrong for
five reasons:

1. **It launders regressions into requirements.** A requirement broken by a bad
   deploy is rewritten to describe the breakage. The incident is now the agreed
   behaviour, no test will ever fail for it again, and the eval that should have
   been added never is.
2. **It makes the spec redundant.** A file that is regenerated from the code is
   a serialisation of the code, with the added cost of looking like an
   agreement. Nobody needs a second, lossier copy of `main`.
3. **It destroys the audit trail.** The record is `git log -p
   .claude/productizer/spec.md`, where each commit joins to an issue and a decision. A
   commit that joins only to a refactor answers "what did we agree" with "what
   did we happen to ship".
4. **It converts a stop into a silent merge.** A `contradicts` finding is the
   same object as an intake contradiction, and the lifecycle's third
   non-negotiable is that *"a contradiction stops the work"* — never superseded
   without a human deciding, and never because the new one is newer. Code is
   newer by construction.
5. **It hands the pen to whoever last merged.** A careless or hostile change to
   the code becomes the requirement, and the next review — which checks diffs
   against the spec — approves the next change on that basis. The direction of
   authority must run spec → code, or the spec authorises nothing.

The correct output of a drift check is a **finding a human rules on**. Fixing
the code and changing the agreement are both legitimate answers; only a person
gets to pick.

## The ruling

A finding that proposes changing the spec — retire, refine, or specify — is a
contradiction between agreed behaviour and shipped code, and it uses the ruling
mechanism in `references/rulings.md` unchanged. The only substitution is what
stands opposite the requirement: shipped code rather than an incoming intent.
Code being newer is not an argument, for the reason above.

Raise it the way intake raises one, and in the same order: allocate the next
`D<n>` and `C<n>`, write the ruling file from `templates/ruling.md` with both
sides stated verbatim, add the `C<n>` row as `open: D<n>`, commit, **then** ask.
Writing before asking is the mechanism — a question asked in a session that then
ends leaves nothing behind, which is the failure the whole file exists to
prevent.

The agent drafts the conflict, the question and the costs. It never fills
`Ruling`, `Ruled by` or `Reasoning`. A drift finding that resolves itself is the
auto-update above, wearing a form.

A ruling picks one of four outcomes, and each is executed by the stage that owns
it — never by the drift run:

| Ruling | Means | Executed by |
|---|---|---|
| **Fix the code** | the requirement stands; the code is wrong | issue → Stage 1, then the normal lifecycle |
| **Refine the requirement** | it was imprecise, the behaviour is agreed | intake `refine` — same id, changed text |
| **Retire the requirement** | the behaviour is genuinely gone by decision | intake supersede or `Withdrawn.` marker, with a reason line; never a deletion |
| **Specify the code** | the behaviour is wanted and was never written down | intake `extend` — new ids from the one allocator |

Until it is ruled, the finding sits in *Areas of concern* as `C<n>`, in the
table that already exists for exactly this and which *"stays open until a human
rules on it."* A ruling nobody answers lapses; lapsing expires the question and
never the requirement, so the requirement the drift run challenged still stands
— which is the safe default, and the opposite of what an auto-update does.

Not every row needs a ruling. `fix the code` changes no agreed behaviour: open
the issue and let it run the lifecycle. Raise a ruling only where the proposal
is to change what the spec says.

## The reverse direction — `scripts/drift-reverse.sh`

Everything above reads spec → code: for each requirement, is it still honoured?
Run only in that direction the check is half a check. It can never produce an
`implemented-not-specified` row, because it only ever looks where a requirement
already points, and that gap type is defined by the absence of a requirement to
point with.

The blind spot is created by this spec's own invariant. *"Nothing is ever
deleted. A superseded or withdrawn requirement keeps its original sentence, in
place."* That is the right rule — it is what keeps every plan, test and PR title
that cites an id resolvable — but it has a consequence. When a requirement stops
being current, the code it justified does not stop. Nothing throws, no test goes
red, no id dangles. The behaviour simply keeps running with an agreement behind
it that has been replaced, and the forward pass will never ask about it, because
the forward pass starts from the requirement and that requirement is no longer
in the set it walks.

`scripts/drift-reverse.sh` walks the other way. It reads the code and asks which
of it has no current requirement behind it.

### What it is

**Evidence for a human or an agent to judge.** Every row it emits is labelled a
candidate and carries a `file:line`. It concludes nothing, opens nothing, and
writes nothing to the spec — the dispositions and the ruling machinery above are
unchanged, and a candidate that survives judgement becomes an ordinary
`implemented-not-specified` row that goes to intake as an `extend` or to an issue
for removal.

It is a shell script, and it is worth being blunt about the ceiling that
implies. **It cannot read code.** It cannot distinguish a second parallel
implementation from a legitimate second caller, an abandoned validation from a
defensive one, or a field the spec forgot from a field the spec never wanted.
What it can do is find the places worth reading, and refuse to call the rest
clean.

### The four signals

| | Signal | What a row proves | What it does not prove |
|---|---|---|---|
| **A** | A requirement id cited in code, comments or tests that the spec marks **superseded or withdrawn** | Someone wrote the id down deliberately, and the agreement behind it has since been replaced | That the code is wrong. A changelog entry or a migration note citing a superseded id is correct and should stay |
| **B** | A cited id **below** the spec's `Next requirement id` watermark that the spec no longer contains | The id was allocated, and its requirement is not in the file — which this spec forbids, so something was deleted or the citation belongs to another product | That behaviour drifted. A copied snippet or a renamed product carries ids too |
| **D** | A cited id **at or above** the watermark — never allocated here | Only that the token exists | Almost nothing. Prose that explains the id convention cites ids that were never allocated, and this pass cannot tell that sentence from a citation |
| **C** | A test whose name is built entirely from words that appear nowhere in the spec | That a test names a flow in vocabulary the spec does not use | That the flow is gone. It matches vocabulary, not meaning |

For ONE change rather than the whole tree, `scripts/check-citations.sh` resolves
only the citations that change adds, split on the same watermark - see
`references/traceability.md` section 6. A citation already in the tree at the
base stays this pass's business.

B and D are split on the watermark for one reason: without the split they are
one bucket, and on this repo that bucket is 71 rows of documentation examples
with the two interesting ones — had there been any — buried in them. A report
nobody finishes reading is a report that found nothing. **Read A, then B. Read D
only when A and B are empty and you still suspect something.**

Signal C is the weakest of the four and is reported last on purpose. Its
anchoring is deliberate: the paren-less RSpec form (`it "…" do`) is matched only
at the start of a line, because unanchored it matched ordinary prose — *"do not
caption it \"screenshot\""* in a template became a candidate — and a signal that
fires on sentences trains its reader to skip the section.

### The two kinds of nothing

The script keeps them apart, because they call for opposite actions and
collapsing them is exactly the failure this repo blocks on elsewhere:
*"If a value could not be measured, then the lifecycle shall report it as
unmeasured and shall not record it as zero."*

| Outcome | Exit | Reads as |
|---|---|---|
| Files were walked, citations were found, none pointed at a dead requirement | `0`, `no-candidates` | **A measured zero.** The report shows the counts it was measured from — how many files, how many live citations |
| No file could be walked, **or** the tree carries no id-reference convention at all | `4`, `cannot-determine` | **Not a pass.** The signals print as `not evaluated`, never as `none found`, and the report says the run failed to reach a position from which zero would mean anything |
| No spec, or a spec with no requirement ids in it | `2` | Nothing to compare against, so nothing was compared |
| Anything else | `1` | Crashed before reaching a report. Read as undetermined, never as clean |

The convention check is what makes the `4` real. A repo that never writes
requirement ids into its code produces no A and no B rows for a reason that has
nothing to do with drift, and reporting that as "0 candidates" is a clean bill
of health issued by a search that never had anything to find. The report also
distinguishes a *confirmed* convention (some citation names a live requirement)
from an *unconfirmed* one (ids appear, none of them current) — in the second
case an `R2` in a formula and a citation are indistinguishable, and the report
says so.

Files that could not be read are listed by name and counted separately from
files scanned. Binary and empty files are counted as skipped. Neither is ever
folded into the scanned total, because a file that was not searched is not a
file that came back clean.

### The gitignore blind spot

By default the file list comes from `git ls-files`, so **gitignored and
untracked trees are not scanned** and the report says so on every run. That is
usually right and occasionally very wrong: a generated-then-ignored directory
can hold the only copy of the behaviour in question, and the search silently
shrinks to fit. `rg` has the same blind spot for the same reason. Pass
`--include-ignored` to walk the tree with `find` instead, and do it at least
once before believing a clean result.

The spec store itself (`.claude/productizer/`) is never scanned. It is the
baseline, not behaviour, and scanning it would report every requirement as a
citation of itself.

### What this does not catch

Understating this is the house style; overstating it is the failure mode. The
pass is blind to all of the following, and none of them are rarities:

- **Behaviour that cites no id.** By far the largest gap. Most code in most
  repos never writes a requirement id down, and this pass sees none of it: an
  unspecified field, a validation nobody asked for, a message the spec never
  mentions, a flag whose off-branch is dead code. Signal C reaches a sliver of
  it through test names and nothing else does.
- **A second parallel implementation** of something already specified. AI
  Unified Process's reverse pass names this explicitly, and it is the one signal
  from theirs this script cannot reproduce — theirs is stack-bound, with one
  file per use case and a known set of class names to count. There is nothing
  stack-agnostic to count here. It needs a reader.
- **Behaviour named in the spec's own vocabulary.** Signal C is a vocabulary
  test. A test that reuses the spec's nouns for a flow the spec has dropped
  passes it silently.
- **Drift with no textual trace at all** — a configuration default, a cron
  entry, a dependency's behaviour, anything whose evidence is not a line in a
  file in this tree.
- **Deleted requirements.** An id removed from the spec entirely reads as a
  citation of an unknown id at best, and as nothing at all if no code cites it.
  That is one more reason the spec never deletes.

A clean reverse run therefore means: *no code in the scanned files cites a
requirement that has stopped being current.* It does not mean the code holds no
unspecified behaviour, and the report must never be summarised as though it did.

### Running the reverse pass

```
drift-reverse.sh [repo-root] [--format text|json] [--include-ignored]
                 [--limit N] [--out FILE]
```

Same cadence as the forward pass — on a schedule and before a release — and the
same rule against wiring it into a merge gate. It is emphatically not a gate: it
produces candidates, a gate needs findings, and a gate that refuses on a
candidate gets disabled within a week.

`--format json` is the machine-readable form; every candidate carries
`"verdict": "candidate-requires-judgment"`, and the top-level `status` is
`candidates`, `no-candidates` or `cannot-determine`. `--limit` caps each signal
and reports the remainder as a count, per *"cap the report"* above. The output
is deterministic and any git date is pinned to UTC, so two runs of an unchanged
tree are byte-identical and a diff between runs means something.

## Running it

**On a schedule** — monthly for a stable product, weekly for one changing fast —
and **before a release**, where the useful question is which requirements were
last proven honoured and when. Also on demand: after a large refactor, or when a
review cites a requirement and nobody can find the test.

Not on every commit. The check reads the whole active requirement set against
the whole codebase; run at that frequency it is slow, noisy and ignored.

**Cap the report.** Rank the findings, report the top ones in full and the rest
as counts by type. A run that emits two hundred rows is a run nobody reads, and
the ten that mattered are lost with the rest.

**Report what you could not check.** A drift run that silently skips a repo, a
language it cannot parse, or a suite that would not build reports green for the
wrong reason. The unscanned list belongs in the report, above the findings.

## Multi-repo products

The check is scoped to the **product**, not the repo. The spec is one file
covering every repo, and the acceptance criteria name which repo verifies each
requirement — *"because the requirement and its test no longer necessarily live
together."*

- Read the spec from the home or the store (`references/spec-stores.md`) and
  record the sha you read. If it is unreachable, the run **stops** — it does not
  report clean.
- A requirement whose criteria name a repo you did not scan is **unverified**,
  never `specified-not-implemented`. Missing this rule makes a run inside one
  service report every front-end requirement as unimplemented, which is how a
  drift report loses its readers on the first run.
- Say which repos were scanned, at which commits, and which were not.
