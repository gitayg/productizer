# Productizer — one-page guide

Code stopped being the bottleneck. The stages around it — planning, review,
deployment, maintenance — still run at human speed, and that is where the time
now goes. This plugin runs a nine-stage lifecycle where **every stage leaves a
committed record and the next stage begins by reading it**.

An intent is an **input**, not a file you keep. It is classified against the
repo's living spec, merged in, and the work is built from what the spec gained:

```
intent (issue | text box | file)
  → intake → living spec → plan.md → diff + tests → PR → incident → new intent
```

The spec lives at `.claude/productizer/spec.md` — one per product, always
current, and inside `.claude/` so no build, packaging step or doc generator
ever picks it up. The record of any single change is the spec diff, joined to
its issue by the branch name and PR title.

## Install

```bash
claude plugin marketplace add gitayg/productizer
claude plugin install productizer
```

Already have a personal copy at `~/.claude/skills/spec/`? Move it
aside. Plugin skills are namespaced, so they do not replace it — both load, both
compete for the same triggers, and `claude plugin update` moves only one of
them. Two copies is silent drift.

### Three commands, typed with a slash

Everything below can also be reached by asking in English — the skill triggers
on what you are trying to do, not on a keyword. The slash forms exist because a
capability nobody can find is one nobody uses, and a menu you can scroll beats
remembering the sentence that triggers it.

| | |
|---|---|
| `/productizer:help` | every command, read from the installed plugin rather than from memory |
| `/productizer:dashboard` | regenerate the view from this repo's files and publish it |
| `/productizer:check` | run the declared checks over the current change |
| `/productizer:backlog` | the queue in front of the lifecycle — see it, add to it, start an item |
| `/productizer:answer` | every question the repo is holding open for a person, one at a time |
| `/productizer:import` | a repo that already exists — draft from its evidence, or read that evidence as drift if it already has a spec |
| `/productizer:spec` | the whole lifecycle — intake, classification, deltas, releases |
| `/productizer:upgrade` | what this repo installed from an older plugin and was never told about — reports only, applies nothing |

Type `/productizer` and the menu lists them. The bare forms — `/dashboard`,
`/check` — work too unless another plugin has claimed the name.

Seven are marked so the model will not invoke them on its own — `help`,
`dashboard`, `check`, `backlog`, `answer`, `import` and `upgrade`. One publishes a page, one
runs every declared tool in the repo, one edits the queue and one starts asking
you questions — none of those should happen because a sentence sounded like a
request for it. You type those. `spec` is the opposite: it is meant to trigger
from what you are doing.

`upgrade` is typed, never triggered, and its "changes nothing" is a
permission rather than a promise. Its frontmatter pre-approves only `Read`,
re-running `upgrade-drift.sh`, and `echo`, and denies `Write`, `Edit` and
`NotebookEdit`. Measured headless on 2026-09-14: five out-of-scope calls —
`mktemp`, a shell redirect, a chained `touch`, a `python3` write and the Write
tool — were all denied, and the same five went through with the scope widened.
Read-only commands such as `ls` and `find` still run without asking, and in a
live session an out-of-scope call prompts you rather than being denied.

(Superseded 2026-09-14, twice: this paragraph first said "All four are marked",
beside a table of seven commands; then said six were marked and that `upgrade`
had unscoped Bash — backlog item B55, now done.)

`answer` is the one worth knowing about. It reads the spec, the rulings and the
backlog and finds what is genuinely waiting on a person — a requirement nothing
asserts, a contradiction nobody ruled, an item that named what it is blocked on
— then puts them **one at a time**, with what it already found about each. It
caught nine stale rows on its first run: requirements whose verifiers had been
built and declared while the table still said nothing asserted them.

## First run in a repo

Just describe what you want. The skill works out which stage you are in from
the issue and the branch, so it knows whether you are starting or resuming.

The first time it needs GitHub or Jira, it asks once — repo, source of truth,
project key — and writes `.claude/productizer/config.json`. It never asks again
in that repo, and it never asks at all in a scheduled run, where nobody is
there to answer.

"Skip Jira — GitHub only" is a real answer, not a half-configuration.

Scaffolding writes an **empty** spec and an **empty** constitution. The templates
carry worked examples so you can see the shape — `R1`…`R6`, `P1`…`P5` — and
`scripts/scaffold.sh` strips them on the way in. A seeded requirement is one
nobody agreed to, and it gets cited before anyone notices it was a sample. The
script also refuses to overwrite, and refuses a destination `.gitignore` would
swallow, because a spec that cannot be committed is not an audit trail.

If the repo already has history, Stage 0c surveys it first. When the survey
finds too little to work from it says so and stops, rather than handing the
drafting step an empty page to invent on.

## The stages

| | You do | You get |
|---|---|---|
| **1 Plan** | describe the problem in plain language | a labelled issue |
| **2 Design** | rule on anything that contradicts the spec | a spec delta, in EARS |
| **3 Build** | interrogate the plan before any code | `plan.md`, then the implementation |
| **4 Test** | nothing — it verifies before you look | passing checks, pasted |
| **5 Check** | declare which checks matter, once | a result that says what was examined |
| **6 Deploy** | judge intent and risk, not mechanics | draft PR, review findings |
| **7 Document** | nothing — it reads the spec | the user guide, regenerated per release |
| **8 Announce** | publish it yourself | a drafted post and release email |
| **9 Maintain** | triage what production surfaced | a new issue, back to stage 1 |

Stages never skip forward, and nothing plans from an intent that has not been
through intake — until then you cannot know whether the work extends the spec or
contradicts it, and the second one is a stop, not a task.

The skill loads in three layers. Its name and description are always in
context; the `SKILL.md` body, about 12.6 KB, loads when the skill triggers and
holds the routing, the stage map and the rules for every turn; the detail of a
stage is in `references/stage-*.md`, which the body tells the model to read
before it enters that stage, and the scripts' exit codes are in
`references/scripts.md`. The body was 35.5 KB until v4.73.0. In tokens that is
an estimate, from bytes at the repository's calibrated 3.74-4.27 bytes per
token: about 2,650-3,030 for the body after its frontmatter, down from about
8,000-9,150. The advisory `skill-body-budget` check holds the body under
13,000 bytes and every path it names to a file that exists; no eval shows a
model opens a stage file when it enters the stage.

## The backlog, in front of all of it

Stage 1 assumes an intent exists. In practice somebody wanted the thing weeks
earlier, and in between it lived in a head or a Slack thread. The backlog is
where that waiting happens on purpose — `.claude/productizer/backlog.md`,
`B`-numbered, ordered by priority.

**There is no priority field.** The order of the file is the ranking. Two
representations of one ordering disagree the first time someone edits one and
not the other, and then nobody can say which is the real queue.

**Nothing in it is agreed.** An item can be picked up, taken through intake, and
refused for contradicting a requirement settled two years ago. That is intake
working, and it is exactly why the backlog is not a second spec.

Five statuses: `todo`, `long-term`, `in-progress`, `blocked`, `done` — where
`done` means *left the queue*, not *shipped*. What shipped is a question for the
spec and the release history.

**An item can name a Jira key, and then Jira owns its status.** The mapping is
declared once in `.claude/productizer/config.json`, and nothing is ever written
back: a markdown table arguing with a Jira workflow, a board filter and three
automation rules loses, and loses silently. Move the ticket in Jira.

The published backlog view is the one view you may rearrange, because reordering
changes nothing that was agreed. Even then it does not write the file — it hands
you the reordered table to paste. Files stay the only edit surface.

## The four answers intake can give

Every intent is classified against the whole current spec, and only two of the
four produce work:

| | Meaning | What happens |
|---|---|---|
| **Extend** | not covered yet | new requirement ids, written in EARS |
| **Refine** | right but imprecise | same id, tightened, recorded |
| **Duplicate** | already specified | cite the id and stop |
| **Contradict** | the spec forbids what you asked for | **stop and ask which wins** |

That last row is the point of the whole design, and it is the one thing this does
that the alternatives do not. Spec Kit, OpenSpec and BMAD are all good and all
more popular; two of them can even name a conflict. None of them stop — Spec Kit
"recommends resolving", BMAD surfaces the conflict and applies the change anyway.
Detection that does not halt is advice, and advice gets skimmed.

This is not a new idea. Requirements engineering has argued for set-level
consistency since Nuseibeh and Easterbrook in 2000, and ISO/IEC/IEEE 29148 lists
it as a property a requirement set must have. What seems to be new is shipping it
inside an AI coding agent, where the halt actually lands on the thing writing the
code.

Requirement ids are permanent. Nothing is deleted; a replaced requirement is
marked `Superseded by R0.` and keeps its original text, because plans, tests,
review findings and PR titles all cite these ids, and a reused id redirects every
one of those citations silently. BMAD holds the same rule in nearly the same
words, so this is table stakes done properly rather than a differentiator — but
most tools renumber per feature, which breaks every citation you ever wrote.

## The solver has a floor, and CI holds it there

Under the classification sits a deterministic second opinion, and
`evals/solver-probe.py` measures it against the 26 cases written to the classes
it is expected to find hard. CI now gates that measurement against a baseline
**measured 2026-09-05**: 8 caught, 1 missed, 0 false positives, 10 stayed
quiet.

Both halves of that are needed, and only one of them is expressible as a
declared check. `checks.yaml` coverage has `min_covered`, which is a floor;
half of this gate is a **ceiling** — false positives at most zero. A gate that
can only assert its floor stays green through a solver that has started halting
on non-conflicts, and a checker that halts on non-conflicts gets switched off,
after which nothing is checked at all.

The probe always exits `0`, so the step parses the counts rather than reading a
status. **A count whose line is absent from the output is NOT MEASURED and
fails the step** — never read as a zero, which would turn a probe that printed
nothing into a perfect score. `undecided` is deliberately unbounded: a case
moving from undecided to caught is the improvement the corpus exists to
provoke, and a bound there would block it.

## Where all the intents live

There is no folder of intents to manage. Under the `issues` model an intent is a
labelled issue on the repo it concerns, which makes "what is in flight across
every repo" one query:

```bash
gh search issues --owner YOUR-ORG --label sdlc:intent --state open --limit 100
```

Two things to know before relying on that: `--limit` caps at 1000 with no paging
past it, and an empty result is indistinguishable from a label that exists
nowhere — both print nothing and exit 0. Validate a negative with a label you
know exists.

## What makes stage 2 matter

Requirements are written in EARS — one requirement per sentence, one `shall`
each, numbered and never renumbered:

> When `<trigger>`, the `<system>` shall `<response>`.
> If `<unwanted trigger>`, then the `<system>` shall `<response>`.

The response must be observable from outside the system, or it is a design note,
not a requirement. This is what turns "do the tests actually assert the
criteria?" from an argument into a check. A spec with no `If` requirements has
not considered failure, and the tests will inherit that gap.

## Products can span repos

A product is one or more repos. Exactly one of them is the **spec home** and
holds `.claude/productizer/spec.md`; the others point at it:

```json
"product": {
  "name": "orders",
  "spec_repo": "acme/orders-api",
  "repos": ["acme/orders-api", "acme/orders-web"]
}
```

One spec, one id space, one allocator. It has to work this way: two allocators
both hand out `R42`, and a reused id silently redirects every test, plan and PR
that cites it. It also means contradiction detection covers the whole product —
a front end and its API can no longer agree to opposite behaviour, which is
exactly where that bug lives.

A single-repo product is the ordinary case: it is its own spec home and nothing
extra happens.

## Seeing it

Files are what you edit. When you want to *look* instead, ask — "show me the
pipeline", "let me see the spec" — and you get a published view: the fleet
across every repo, one product's spec, an intake classification, or a band's
history. Each is regenerated from the files and republished to the same URL, so
you get one link per view rather than one per glance.

Views are read-only by design. Nothing is ever read back out of one into the
spec: the moment a view became the thing you edit, the committed chain would
stop being the audit trail.

## Make it yours, per repo

Everything the lifecycle produces already lives in the repo: the binding
(`.claude/productizer/config.json`), the artifacts (`docs/sdlc/`), the review
policy (`REVIEW.md`), the bands (`ops/bands.yaml`). The templates that shape
them can be too:

```
.claude/productizer/templates/spec.md     this repo's spec shape
.claude/productizer/templates/REVIEW.md   this repo's review passes
```

Repo-first, plugin as fallback. Commit only what differs — one file overrides
one template and inherits the rest — and a plugin update never touches them.
Same idea as `CLAUDE.md`: the repo's conventions belong to the repo.

## Two things that run without you

- **Nightly evals** regression-test your agent configuration — `CLAUDE.md`,
  skills, hooks — against real past tasks. It reports; it cannot block a merge.
  If you need a gate, that one belongs in CI.
- **Control bands** — Anthropic's design from the playbook, not ours — watch a
  metric and act by tier: 1σ log, 2σ diagnose
  read-only, 3σ propose via PR. Detection is deterministic — no model decides
  whether something broke. A finding is opened as an issue and goes through
  intake like any other intent, which is how the loop closes — and what stops a
  production signal silently contradicting an agreed requirement.

The skill installs both, refuses to install an eval task against an empty suite,
and warns that scheduled tasks only run while the app is open.

## The checks are yours to declare

Stage 5 runs whatever you put in `.claude/productizer/checks.yaml` — a secret
scan on every change, a linter on the paths that have one, a heavier ruleset on
anything touching auth. Triggers are `always`, path globs, or **requirement
tags**, which is what makes the scrutiny per-item: an auth requirement earns
the auth ruleset, a copy edit does not.

Every check states what it must have examined, and that is the part that
matters. A scanner reporting *Grade A (100/100)* after opening one file of
forty-eight is not a pass, and without a coverage assertion it is
indistinguishable from one. A check that exits clean having examined less than
it declared comes back **hollow**, and hollow blocks like a failure.

Commands are argv lists, never shell strings. The file is committed, so a string
would let anyone who lands a commit choose what runs on the machine of whoever
pulls it.

### The hygiene check is two checks

The one that ships carries **generic** rules only — credential shapes, personal
filesystem paths, machine hostnames, private key headers. Everything any repo
needs, and nothing that identifies anyone.

Names you cannot publish go in a **local list** the shipped check reads at
runtime: `--patterns FILE`, else `$PRODUCTIZER_HYGIENE_PATTERNS`, else
`.claude/productizer/hygiene-local.txt`, which you gitignore.

The split exists because a single list has to spell the private names in order
to catch them — so in a public repo the gate publishes exactly which names its
author is hiding. A deny list is a map of what someone is protecting.

If the local list is named and unreadable the check exits 2, never 0. A
configured private list that quietly fell back to generic-only would report
clean while checking none of the names you cared about.

### A rewritten sentence flags everything that cites it

Permanent ids are why a citation survives, and they are also how one goes
quietly wrong. `R5` means whatever R5 says today: rewrite its sentence and
every acceptance row, every coverage claim and every downstream requirement
naming `R5` keeps pointing at it, keeps resolving, and now describes something
nobody re-read.

The `suspect-links` check — `check-suspect-links.sh` — finds exactly that
shape: a requirement whose sentence changed **in place**, its id and its status
both unchanged, and every tracked file still citing that id whose own line did
not move in the same change. A supersede or a withdrawal is not its business;
those leave a forward pointer a reader can follow, and `check-superseded-text.sh`
owns them. Collapsing the two would turn one supersede into three false flags.

It is declared `advise`, not `block`, and that is the honest setting. **It
cannot tell a semantic rewrite from a typo fix** — `recieve` to `receive` and
`shall` to `shall not` are one measurement to it — and it prints that limit on
every run, clean or not. A gate that holds a merge on a distinction it cannot
make is a gate people route around, and a routed-around gate measures nothing.
Exit `2` still blocks whatever the severity says: a flag you can disagree with
is cheap, and not knowing is not.

### A contradiction now writes the question down

Classifying an intent as *contradict* stops the work, and a stop nobody was
asked to answer is indistinguishable from a stop that was abandoned. So the
ruling is drafted **before** the question is asked out loud: `request-ruling.sh`
allocates the ids, writes both requirements verbatim, fills both columns of the
cost table, adds the concern row, and prints the path to name in the message.
Ask first and write after, and the session can end before anything exists.

`pending-rulings.sh` reports what is waiting — keeping *never raised one*,
*cannot read the directory* and *genuinely none* as three different answers,
because only the third one is zero. The `ruling-requested` check fails when a
concern is open with no ruling behind it, when a pending ruling is cited by
nothing, and when a pending ruling is still wearing the template. A ruling that
still reads like the template is a file, not an ask.

## Checking a spec this lifecycle did not write

`validate-spec.py --format speckit <file>` adapts a spec-kit spec in memory and validates it. The
file on disk is never written.

Seven mechanical rules, no semantic rewriting: `FR-0NN` becomes `R<n>`, `System MUST` becomes `The
system shall`, the id separator becomes an em dash, headings are normalised, and an id allocator is
synthesized. A line matching no rule passes through untouched and is counted, so nothing is
silently reshaped.

**Seven check families report `n/a` and are never counted as passes** - supersession, per-requirement
status, the id counter, count-mismatch, citations, section-match and the permanence baseline. They
are not skipped because they are hard; spec-kit's format has no such concept, so a pass would be a
claim about something that does not exist.

It earns its keep: on a real spec-kit spec it reported `EARS_UNQUANTIFIED: R7 uses the unquantified
term 'sufficient'` - in a feature whose own spec-kit-generated checklist had ticked *Requirements
are testable and unambiguous*.

Be accurate about what this does and does not show. spec-kit's per-feature directory scope is a
design choice, not a defect, and its ids are stable within it - measured, by diffing an adapted
pre-update snapshot against the current file: byte-identical for the first twelve requirements,
zero renumbering. Its `analyze` step does detect conflicting requirements; the difference is
deterministic arithmetic against LLM judgement, not presence against absence.

## A rail to move between the drawings

The Visualizer builds its own left navigation at load, from the sections actually present, taking
each label from that section's heading. Nothing lists the sections twice - a hardcoded rail would
go stale the day a seventh drawing is added.

A section that could not run stays in the rail and is marked, quoting its own reason. A section
reporting a measured zero is left unmarked, because it was measured. Hiding an unmeasurable section
from navigation would conceal exactly what this product exists to surface.

## The ratio, and when it moved

The Visualizer opens with one number: the share of check tools carrying a self-test, with its
delta and the date it last moved. A ratio, not a count - a count of self-tests rises when tools
are added and tells you nothing.

The chart under it is there because a POLICY CHANGE SHOULD BE VISIBLE AS A SHAPE. Walking this
repository's history: eleven days flat at 2 to 4 self-tested tools while the tool count climbed to
29, then one commit to 32 of 32, and 43 of 43 once the v4.61.0 tools were declared. You can see the day it started mattering without reading a
commit message.

Hovering a point prints the QUOTIENT, not only its two inputs - a tooltip that shows 31 and 3 and
leaves the division to the reader is how a ratio stops being read. Where the denominator is zero
it prints `nothing to divide here` and the line breaks rather than interpolating.

The denominator is named on the page, because there are two defensible ones and they disagree:
every `.sh` and `.py` in the tree gives 58, while the check tools the suite actually invokes gives
32. The series uses the second and was falsified against the real tool at four historical commits.

**What is deliberately not drawn.** Covered / Partial / Missing over time would need the suite RUN
at each commit. The only record of a run is `checks-result.json`, which 63 of 108 commits carry -
the last on 2026-09-02, and none of the 23 commits since, which includes the step this section is
about. A line drawn from that would stop before the thing the page is showing you, so the row
renders the has-not-run glyph and says why instead.

## The config that decides what is checked is now itself checked

Loosening a check used to be an ordinary diff that nothing read. Measured on this repository at
v4.60.0, five ways - deleting a check from `checks.yaml`, flipping its `severity: block` to
`advise`, adding `enabled: false`, replacing `always: true` with a glob that matches nothing, and
deleting a tool's `--selftest` line from the workflow - each committed on its own clone and each run
through the whole suite. **All five exited 0 PASS.** The gate over the publish hook was real; the
file that decides which gates exist was read by nothing.

Two checks close that, and they are deliberately not one. `governance-weakening` ADVISES over the
whole surface, because most weakenings are deliberate and a blocking sweep over a file people edit
every day would be switched off inside a week; it reports what moved and what it was, for example
`WEAKENED: checks[secret-scan].severity (effective)  was 'block'  is now 'advise'`, and leaves the
judgement to a person. `governance-self-footing` BLOCKS, and asserts only this pair's own
declaration: a diff that switches off the check watching for switched-off checks is the one move
that cannot be left to advice.

The surface is named FIELDS, not text. A comment, a `why:`, a `limitations:` entry and a reflow are
outside it on purpose - that is where the reasoning lives, it changes constantly, and a rule that
went red on rewrapped prose teaches people to ignore it. Effective severity is resolved rather than
read, because lowering `defaults.severity` weakens every check that never mentions severity and no
check's own line moves.

## Risk tiers, and what a check must prove before it may block

Not every change deserves the same attention, so `classify-change-risk.sh` reports a tier per
changed path and the rule that decided it, against `.claude/productizer/risk-tiers.yaml`. Two
things about it are deliberate and both are refusals to invent:

A path no rule covers reads `unclassified` and exits 1. There is no catch-all rule, because a
catch-all makes every path added tomorrow low-risk on the day nobody has looked at it - the
fabricated zero of R26, in words rather than in numbers. And COMPLEXITY prints `unmeasured` on every
single run: no path predicts how much planning a change needs, and deriving it from the tier would
print the tier twice under two names.

The policy was calibrated before it shipped, and one rule moved because of the number. The first
draft put **111 of 121 commits** in the top tier, because `plugin.json` is touched by 106 of 121 -
the version is bumped before every commit. A tier reached by 92% of commits is a second word for "a
commit", so that rule moved down; it now reads 55 of 121, which is what this repository is rather
than what the policy is.

`measure-check-overfire.sh` replays a check over merged history and computes the rate that would let
it earn `severity: block`: at least 20 commits returning a VERDICT, every fire in that window ruled
by a person, and the ruled FALSE-POSITIVE count at or below 10%. Two measurements changed that rule
while it was being written. Capping the RAW rate at 10% would have demoted `stderr-suppression`, a
correct blocking check, for doing its job at 11.8% - so the clause counts ruled false positives, of
which it has none. And a fixed 30-commit window is too narrow for a path-scoped check: 13 of 30
commits touch no shell at all, so that check reaches 17 verdicts and not 30, which is why the window
is the movable part. **No check in this repository has yet been shown to satisfy the rule** -
`stderr-suppression` clears the ruling and false-positive clauses and misses the 20-verdict floor at
17 - and the rule is documented rather than enforced, which is recorded as B76.

## Every check tool tests itself, and the suite runs those tests

R108 obliges a check tool to carry a self-test that reaches each exit code it can return. R40
obliges the suite to run it. Both read **43 of 43** as of 2026-09-26 (32 of 32 on 2026-09-06); 28 of those self-tests were
written in one pass, and every one was seen FAILING on a deliberate break before it was believed.

A third figure sits beside those two and is never added to them: whether each self-test SAYS which
exit codes it drove. `43 of 43` declare, and `43 of 43` drove every code they document. That figure
is counted and not enforced, because a declaration is the self-test's own account of itself rather
than an observation - but it is the line that caught `spec-requirements.sh` printing a tally and no
declaration at all. Its contract documents an exit 3 for a disagreeing case, which no ordinary case
can reach, so it now drives 3 by breaking a COPY of itself on purpose and asserting that the break
applied. Trimming 3 out of the documented list would have been the other way to make the figure go
green, and it would have made the contract a description of the self-test instead of the reverse.

The self-tests build fixtures under `mktemp -d` and never touch the repository. Two of them cannot
reach their exit 1 from fixtures at all - for `check-missing-tool` and `check-no-fabricated-zero`,
exit 1 means the RUNNER regressed, and no input makes a correct runner fabricate a zero - so they
copy the scripts directory and patch the COPY, verifying the patch applied and refusing with exit 2
if it did not. A moved line becomes unmeasured, never a silent second copy of the clean case.

**The lesson from writing them, which is worth more than the count.** An exit-code-only self-test
misses real regressions. Four separate falsifications kept exit 1 while the defect was live: a
renumbering read as a deletion, per-line clearing reverted to per-file, an assertion switched off
entirely. Only the cases that assert a SENTENCE caught those. Every tool prints a `NOT ASSERTED:`
line saying which kind it is.

The wiring in `.github/workflows/checks.yml` names all 32 on their own lines rather than looping
over a glob, because reachability is read from the workflow SOURCE - a loop would run every
self-test and leave R40 reporting that nothing invokes them. No line is guarded with a shell OR and
no step sets `continue-on-error`; the check treats both as SWALLOWED, on the reasoning that a
self-test whose failure cannot set the run's exit code has not been run in any sense that matters.

One honest gap: `evals/solver-probe.py` has no exit 1 to reach - its run function returns 0 over
any corpus - and its self-test prints `NOT REACHED:` rather than inventing a case for it.

## A check that counts what nobody is testing

`check-selftest-coverage.sh` reads the tools the declared checks and the workflow actually
invoke, then reports which carry a self-test and which of those anything runs. It exists because
R108 obliges a check tool to carry a self-test and R40 obliges the suite to run it.

It is red, and that is the point. Measured 2026-09-06: **4 of 32** repository check tools carry a
self-test that answers, and **3 of those 4** are invoked by something. It names the other 28 one
by one, and it reports ITSELF as an R40 finding rather than exempting the tool doing the counting.

A subtlety worth knowing before you read the coverage line: a check that FAILS voids its own
`spec_units` claim - `run-checks.sh` lists `fail` in `VOID_RUN` - so R108 and R40 still read
`Missing` even though a check now names them. What changed is the reason, from *no check names
this requirement* to *a check named it, came back red, and therefore measured nothing here*. The
only route to `Partial` is writing the 28 self-tests. Nobody was looking; now something is.

A tool that dispatches a self-test in a shape the scanner does not recognise reads as carrying
none, which over-reports the shortfall - the safe direction, and stated rather than hidden. And
R108's second clause, *reaches each exit code it can return*, is not measured at all: no self-test
here reports which exit codes it drove.

## The system, drawn from the files that define it

The Visualizer's first board is the architecture: the nine lifecycle stages with what each one
reads and names, the three places work can be refused, and the principles that sit above every
requirement.

Nothing in it is a list kept in the generator. The stages and their order come from `SKILL.md`'s
own `### n - Name` headings, the artifacts from its own Stage/Templates table, the gates from what
is actually installed and executable, the refusal contract from `run-checks.sh`'s own exit-code
header, and the principles from `constitution.md`'s own `### Pn` blocks. Rename a stage in
`SKILL.md` and the board renames with it - which is the point, because a lifecycle drawn from a
list inside the builder is one nobody can correct by editing the skill.

Remove any of those files and the board says NOT RUN and which file is missing. It never draws an
empty diagram: a product with no stages and a product whose description is missing are different
answers, and only one of them is about the product.

Two things it reports that nothing else had noticed: `SKILL.md` declares nine stages while
`stage-status.sh` emits thirteen rows, and `artifact-gate.sh` ships in `templates/` while
appearing in no row of the Stage/Templates table.

## One page you read before you touch the spec

The checks above are all here and they are all separate, and nobody runs five
scripts before editing a requirement — so a defect only one of them reports
sits in that one script's output and becomes furniture. This repo's own header
said `28 active, 4 superseded` while the file held 32 and 6, reported the whole
time by a tool nobody was running.

`spec-doctor.sh` runs them and lays the answers out together: grammar and id
permanence, the declared counts against the counted ones, superseded chains,
acceptance rows, and rulings waiting on a person. It computes nothing a tool
already computes, and **it changes nothing**, so you can run it twice and
compare.

```bash
plugins/productizer/skills/spec/scripts/spec-doctor.sh
```

Three exit codes, and the third is the point: `0` every section ran and found
nothing, `1` every section ran and there are findings, `2` a section **could
not run** — a missing tool, an unreadable spec, a tool that refused.
Could-not-measure outranks findings deliberately, so a page with a hole in it
never exits `1` and claims to have looked. Both are printed and both are
counted on the summary line; only the ranking is opinionated.

A warning is a finding here. `validate-spec.py` exits `0` on warnings because
it gates CI and a pre-existing warning must not block a merge. The doctor is
not a gate — it is the page you read before you touch the file — and a warning
nobody is told about is the failure it exists to end.

### The header can disagree with the file, and now that is an error

`validate-spec.py --counts` prints what the spec's header declares beside what
the file actually counts, plus the header line those counts derive:

```
COUNT     .claude/productizer/spec.md  active  28  32
DECLARED  .claude/productizer/spec.md  17  28 active, 6 superseded, 0 withdrawn.
DERIVED   .claude/productizer/spec.md  17  32 active, 6 superseded, 0 withdrawn.
```

`DERIVED` is the line to paste when the two disagree. `--counts` reports and
exits `0` whatever it finds; the gating happens on an ordinary run, where
`COUNT_MISMATCH` is now an **ERROR** rather than a warning, and a stale header
fails the file instead of decorating it.

## Docs and go-to-market, per release

Two stages run once per **release**, not once per intent.

**7 Document** regenerates the user guide from the active spec. Per intent you
would get a changelog with headings — every entry accurate, the document as a
whole describing no product. Per release is also the only cadence at which
removals are visible: within one change a superseded requirement looks like an
edit, but across a release the superseded and withdrawn ids are exactly the list
of things that used to work and no longer do. Screenshots are captured from the
released build with the version in the filename, because prose gets reviewed and
images do not.

**8 Announce** drafts the release post and the release email from the spec
deltas and the merged PRs. Every claim traces to one of them, every number was
measured, and the post names the adjacent thing the release does *not* do.

**Agent-driven, human-gated.** Stage 8 runs as an agent stage like the others —
it writes both artefacts, captures the screenshots, checks the release is
actually installable, and reports what it could not verify. The publish itself
is a hook (`publish-gate.sh`), not a convention: it blocks `gh release create`,
`npm publish`, a tag push, a mail API and a site deploy, and allows everything
the agent needs for its own work. A rule the agent is only asked to remember is
a rule it eventually reasons past.

### The pull-request comment renders; it never posts

`pr-spec-comment.sh` writes the markdown for *what this change did to the
spec* — the requirement delta, whether anything was classified `contradict`,
the recorded check verdicts, the solver probe's counts — **to stdout, and
nowhere else**.

```bash
plugins/productizer/skills/spec/scripts/pr-spec-comment.sh --base origin/main
```

`--post`, `--publish`, `--gh`, `--comment` and `--pr` are each **refused with
exit `2` and not one byte on stdout**, and each refusal says why: posting to a
pull request is a publish, every publish here goes through `publish-gate.sh`,
and a script that posted by itself would route around that gate inside the
repository that ships it. The report's own footer names the command a person
may choose to run, and the checklist that command needs first.

Nothing unmeasured is rendered as zero. *The change adds no requirement*, *the
base ref does not resolve*, *the diff was over the cap so it was not read* and
*the spec is not readable* all end in an empty id list, and they are four
different facts. Each gets its own sentence, and the ones that are an absence
of measurement rather than a measured absence exit **`5` — rendered, but
partial** — so a caller knows the report has a hole without reading it. Exit
`3` means it never started: not a git work tree, no such directory,
`spec-diff.sh` unusable, or no `evals/solver-probe.py` - the report requires the
repository's solver probe, so its absence is a refusal, not a partial report.

The delta itself comes from `spec-diff.sh`, and the base commit that tool
resolves is the base every other section is measured against. One resolution of
one ref anchors the whole report, rather than the repo holding two answers to
one question.

## Handing the record to somebody outside

`emit-attestation.sh` turns the living spec, the acceptance rows and the
recorded check results into a **CycloneDX 1.6 Attestations** document —
requirements as `definitions.standards`, one claim per requirement, check runs
as evidence:

```bash
plugins/productizer/skills/spec/scripts/emit-attestation.sh --out attestation.cdx.json
```

What matters is what it refuses to write. A requirement whose conformance was
never measured gets a **rationale and no score**, never a zero and never an
invented number: on this repository 20 of 32 mapped requirements carry a score
and 12 carry only the reason there is none. Evidence is emitted with **no
author** rather than a model's name in `evidence.author`, which CycloneDX types
as a person. The facts the schema has no field for — how many commits carry a
`Productizer-Req` trailer, how many carry `Assisted-by` — go into the
document's root `properties` rather than being bent into a field that means
something else.

Exit `0` emitted and fully measured, `1` emitted with findings, `2` could not
measure and **nothing was emitted**. It prints its own list of what it could
not say, including that with no rulings directory the document attests no human
ruling — which is unknown, not zero.

## What a commit says about who wrote it

`req-trailer.sh --add` records which requirements a commit served.
`--assisted-by` adds the authorship half, following the rule the Linux kernel
publishes in `Documentation/process/coding-assistants.rst`:

```bash
req-trailer.sh --add R14,R22 --file .git/COMMIT_EDITMSG \
  --assisted-by --tools "coccinelle sparse"
```

appends

```
Productizer-Req: R14,R22
Assisted-by: LLM coccinelle sparse
```

**`Signed-off-by` is never written, and neither is `Co-authored-by`.** Only a
human can certify the DCO, and `Co-authored-by` takes a name and an address
that git and every forge resolve to a *person* — a person-shaped claim a model
cannot hold. Basic development tools are refused rather than listed: `--tools
"git make"` exits `2`, writes nothing, and quotes the rule back at you. Only
the specialised analysis tools belong on that line.

`--authorship` reads it back, over a message (`--file`) or a commit (`--rev`),
and exits `3` on a finding. It states its own limit on every run: the agent
check is a word list of fourteen names, so a clean run shows that **no named
agent signed off**, never that a human did — and a message with no
`Assisted-by` is not a message written without assistance, it is one that did
not say.

## Choosing the model per stage

Each stage names a model and an effort in `.claude/productizer/config.json`,
shipped with recommended defaults. Two halves, and they are not
interchangeable: a stage that starts a **subagent** carries the setting in
frontmatter and it is enforced; a stage that runs **in your session** inherits
your session model whatever the file says, so the skill tells you which stage
it is entering instead of pretending to have applied something.

Effort buys most at **intake** and **review** — low volume, expensive to get
wrong. It buys least on nightly evals and 2σ diagnosis, which run constantly and
have right answers. Running everything at high effort is the same care with a
larger bill, and it makes the nightly suite expensive enough to switch off.

Stage 5 takes **no model at all**. It compares coverage arithmetically; a model
asked *did this check pass* believes the green summary line, which is the
failure the stage exists to prevent.

**An advisor, optional.** Set `models.advisor` to a model alias or id
(`"opus"`, say) and the unattended CI build passes it as `--advisor`, so the
build agent can consult a second model ([Claude Code's
advisor](https://code.claude.com/docs/en/advisor)). The advisor reads the whole
transcript, repository content included, and its tokens bill at its own model's
rates. It is advice, never a gate: nothing forces a call, and no check relies on
one. Absent or `null` passes nothing; any value that is not a model name refuses
the run before a model is called. In a session, use `/advisor <model>` or
`claude --advisor <model>` - Productizer does not read `models.advisor` there.
A committed project `.claude/settings.json` holding `advisorModel` can turn an
advisor on in CI without `models.advisor`; `--advisor` overrides it for the
session.

**Caps on the unattended build, always.** The CI build passes the agent
`--max-turns` and `--max-budget-usd` on every run, from `models.build_caps`
(`max_turns`, `max_budget_usd`) or, when those are absent or `null`, the
built-in 100 turns and 20.00 dollars - the run is never uncapped, and the
dispatch log says which values are defaults. Claude Code stops the run at
either cap; the spend cap is its own estimate and can be passed by one
response. A cap that is not a positive number refuses the run before a model is
called. The job's `timeout-minutes` stays the third stop. Scheduled prompts are
not capped by this, and no capped run has happened on a real runner yet.

## Starting from a repo that already exists

Stage 0c surveys a repo with history — routes, tests, error paths, config — and
drafts at most 30 requirements from what it found, each carrying the file, line
or test it came from. **Every one lands `inferred` and unconfirmed.** Inferred
requirements cannot trigger the contradiction stop, or the lifecycle starts
defending whatever the code happened to do on import day, bugs included. A
human confirming one promotes it, and that promotion is a commit.

## Optional: delegate the middle

If you have a real check runner — plan-vs-diff, tests-vs-criteria, a pre-push
gate — point at it and stages 3-5 delegate to it instead:

```bash
export SDLC_CHECK_RUNNER="/path/to/your/check-runner"
```

Enforced beats advisory. The skill probes by *running* it, never by checking the
file exists, and tells you which way it resolved.

## What it guarantees today

Everything above argues for the shape. This is the agreed set — the requirements
the spec holds active right now, in the EARS patterns stage 2 writes them in, and
nothing else. It is the one part of this page nobody edits by hand: stage 7
regenerates it from `.claude/productizer/spec.md` on every release, so a guide
promising behaviour nobody agreed to would have to survive a release to do it.
Edit the spec; this section follows.

<!-- productizer:requirements:begin -->
<!-- Generated from `.claude/productizer/spec.md` by
     plugins/productizer/skills/spec/scripts/build-guide.sh. Everything between
     these two markers is rewritten on every release - edit the spec, not this. -->

**163 requirements are active**, and they are the whole of what has been
agreed.

Thirty-three more are superseded and none withdrawn, and neither kind is
listed here. The spec keeps both forever with their text intact, so a citation
written two years ago still leads somewhere — but a guide is read by someone
deciding what to do next, and a superseded sentence gives them no sign it
stopped being true.

**Always, with no trigger.** Twenty-two requirements hold whatever else is
happening:

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent: never reused,
  never renumbered.
- **R3** — The lifecycle shall keep a replaced requirement's original text in
  the spec, marked superseded.
- **R73** — The lifecycle shall not count a change to the backlog as evidence
  for a stage advance.
- **R74** — The lifecycle shall match a stage run's changed path against the
  paths it refuses after folding case, Unicode normalisation and format
  characters, granting an exception to those paths on the exact path alone.
- **R106** — The lifecycle shall keep every published view read-only with
  respect to the spec.
- **R107** — The lifecycle shall make every check declare what it must have
  examined for its pass to count.
- **R108** — The lifecycle shall make every check tool carry a self-test that
  reaches each exit code it can return.
- **R109** — The lifecycle shall make every commit record name each path that
  commit's diff touches.
- **R110** — The lifecycle shall grant every reviewer agent no tool that can
  write a file.
- **R111** — The lifecycle shall make every pull request an unattended run
  opens name the run that opened it.
- **R112** — The lifecycle shall run every unattended agent step with no token
  that can write to the repository.
- **R113** — The lifecycle shall run every unattended agent step with no
  permission beyond what the repository's committed agent settings grant.
- **R114** — The lifecycle shall run every unattended agent step with no tool
  that executes commands.
- **R115** — The lifecycle shall interpolate no `${{ }}` expression into a
  `run:` script of the CI build template.
- **R129** — The lifecycle shall keep every package install and YAML read out
  of the CI template's job that holds a write token.
- **R130** — The lifecycle shall hand the CI template's deliver job the
  protected list through an artifact the agent's job never downloads.
- **R144** — The lifecycle shall hold the data-only list in the plugin and
  never read it from the repository's own configuration.
- **R149** — The lifecycle shall count a configured argument that holds a
  slash, holds no whitespace and resolves under the repository root as naming
  a path inside that repository, whether or not that path exists yet, except a
  semgrep registry id that R148 excludes.
- **R153** — The lifecycle shall keep the spec skill's stage detail in
  reference files that the skill's body names at the stage that needs them, so
  that the body loaded on every trigger carries only the routing, the stage
  map and the per-turn rules.
- **R192** — The lifecycle shall pass the unattended build agent a cap on the
  number of its agentic turns.
- **R193** — The lifecycle shall pass the unattended build agent a cap on its
  spend in US dollars.

**When something arrives.** Forty-one things happen on a discrete trigger:

- **R6** — When an intent arrives, the lifecycle shall classify it against the
  whole living spec as exactly one of extend, refine, duplicate or contradict.
- **R9** — When a release is prepared, the lifecycle shall regenerate the user
  guide from the active requirements.
- **R10** — When a repository with history is imported, the lifecycle shall
  mark every drafted requirement inferred and unconfirmed.
- **R11** — When a published view is regenerated, the lifecycle shall read
  every figure in it from a file in the repository.
- **R32** — When a classification changes the spec, the lifecycle shall record
  it in the spec's change log.
- **R35** — When a requirement is added, the lifecycle shall allocate the next
  unused id.
- **R36** — When a requirement is added, the lifecycle shall record it in the
  acceptance criteria table.
- **R37** — When a person overrides a failing check, the lifecycle shall
  record the override in a file naming the check, the authority and the
  reason.
- **R40** — When the check suite runs, the lifecycle shall run the self-test
  of every check tool it invokes.
- **R42** — When a change set is classified, the lifecycle shall report the
  risk tier of each path it touches and the rule that decided it.
- **R47** — When a check declaration moves between a base and the working
  tree, the lifecycle shall report which declaration moved and what it was.
- **R58** — When the Build stage starts, the lifecycle shall hand it the
  spec's diff against the base it builds from.
- **R59** — When an unattended run produces a change, the lifecycle shall
  deliver it as a draft pull request.
- **R64** — When an unattended run's change has been committed, the lifecycle
  shall push nothing until a decision made on that commit allows it.
- **R68** — When an unattended run's change is captured, the lifecycle shall
  compute it with version-control settings the agent could not have written.
- **R69** — When an unattended run runs a shell after the agent step in the
  agent's own job, the lifecycle shall give that shell no environment setting,
  from the agent or alterable by it, that names a file for the shell to
  source.
- **R88** — When a classification is recorded with a root given, the lifecycle
  shall write the record under that root, whatever the working directory.
- **R92** — When the import marking is examined, the lifecycle shall count a
  backlog line as evidence of an import only where the commit that added it
  also introduced requirements.
- **R93** — When a change adds a line to the backlog, the lifecycle shall
  resolve every requirement id on that line against the spec.
- **R95** — When an acceptance row cites a path or a script, the lifecycle
  shall resolve it in the exact case its directory lists.
- **R104** — When a published view draws a state, the lifecycle shall give it
  a glyph and a state word unique among the states of its kind, on the plain
  page and under `forced-colors: active` and `prefers-contrast: more`.
- **R116** — When the agent's job reads the flags prepared for an unattended
  run, the lifecycle shall make the CI build template pass the agent only
  lines it has matched against the fixed shapes `build-dispatch.sh prepare`
  writes, a last line with no newline included.
- **R117** — When the stderr-suppression check scans a YAML file, the
  lifecycle shall make it examine only `run:` values.
- **R118** — When the lifecycle renders a pull request body, the lifecycle
  shall name in it only artifacts that exist in the repository it is rendered
  in.
- **R119** — When a check does not pass, the lifecycle shall print the last 20
  lines of the check's own output beneath its row in the checks stage.
- **R120** — When the CI replay runs a workflow step, the lifecycle shall run
  it with no system or global git configuration and with git's default branch
  set to master.
- **R121** — When the view builder embeds repository-derived text in the page,
  the lifecycle shall encode the capability object's name so that it does not
  appear verbatim as an identifier.
- **R125** — When a stage advance to design is judged without `--unattended`,
  the lifecycle shall permit its change to modify the requirement index and to
  add classification records.
- **R128** — When an unattended stage decision is handed a protected list, the
  lifecycle shall judge the change against that list and read no YAML.
- **R132** — When an unattended stage run adds a classification record or a
  stage snapshot, the lifecycle shall refuse the stage move.
- **R133** — When a workflow job's own permissions, or a new job's compared
  against the workflow's default at the base, grant a scope at a higher level
  than before, the lifecycle shall report that scope as a weakening of the
  governance surface.
- **R134** — When the lifecycle compares workflow steps between a base and the
  working tree, the lifecycle shall match them by id, or else by name and the
  action used with its ref ignored, and never by position.
- **R135** — When the view builder or the page writes a link whose value
  derives from the origin remote, a tracked path or jira.site, the lifecycle
  shall write it as an attribute-escaped http(s) URL or write no link.
- **R136** — When a version tag is pushed, the lifecycle shall attach to the
  draft release a copy of the CI build template pinned to the tag's commit,
  made by a job holding no write token.
- **R139** — When the import marking is examined and the repository history
  cannot be walked, the lifecycle shall refuse to report that no import is on
  the record.
- **R140** — When the import marking is examined, the lifecycle shall count a
  backlog line as evidence of an import only where it is a new gap row whose
  item opens with the import stage's id.
- **R141** — When a lifecycle script is given a relative path option other
  than its root, the lifecycle shall resolve it under the repository root
  rather than the working directory.
- **R145** — When a configured command is about to run and the configuration
  has not opted in to running the repository's own commands, the lifecycle
  shall judge that command against the repository as it stands at that moment.
- **R150** — When `models.advisor` in config.json names a model, the lifecycle
  shall pass it to the unattended build agent as one `--advisor <model>`
  argument and as nothing else.
- **R151** — When `models.advisor` is absent or null, the lifecycle shall pass
  the unattended build agent the same arguments as a configuration that lacks
  the key.
- **R194** — When `models.build_caps` in config.json sets no value for a cap,
  the lifecycle shall pass the unattended build agent that cap's built-in
  default, reported by prepare as the default.

**For as long as a state lasts.** Nine requirements are true for the duration
of a state, not at a moment inside it:

- **R13** — While a check tool named by the configuration is absent, the
  lifecycle shall report that check as missing rather than skipped.
- **R38** — While a failing check is overridden, the lifecycle shall render it
  as failed and waived, and never as passed.
- **R45** — While a change's risk tier is reported, the lifecycle shall report
  that change's complexity as unmeasured.
- **R71** — While an unattended run holds a token that can write to the
  repository, the lifecycle shall execute no code from the repository it is
  writing to.
- **R91** — While a stage run is judged under `--unattended`, the lifecycle
  shall refuse that run's change to a path that holds a character outside
  ASCII or has a component that begins with a dot, except the backlog, the
  plan in plan mode and the spec outside build mode on their exact paths.
- **R103** — While a contradiction is unruled, the lifecycle shall merge no
  spec change that adds, refines or supersedes a requirement named in that
  contradiction.
- **R122** — While PRODUCTIZER_SHA is the forty-`0` placeholder, the lifecycle
  shall make the CI build template refuse to run before checking anything out,
  naming the command that prints a release's commit id.
- **R137** — While the release-draft job holds a token that can write to the
  repository, the lifecycle shall check out nothing in it.
- **R138** — While the release-draft job holds a token that can write to the
  repository, the lifecycle shall run no code from the repository in it.

**When something goes wrong.** Eighty-one defences, written as `If … then`
because a designed path and a defended one are not the same thing:

- **R18** — If a configured command names a shell or an interpreter with an
  inline program, then the lifecycle shall refuse to run it.
- **R19** — If the spec home is unreachable, then the lifecycle shall stop
  rather than classify against a remembered copy.
- **R20** — If a survey finds too little evidence to draft from, then the
  lifecycle shall refuse to draft a spec from it.
- **R24** — If an intent contradicts an active requirement, then the lifecycle
  shall merge nothing.
- **R25** — If a value could not be measured, then the lifecycle shall report
  it as unmeasured.
- **R26** — If a value could not be measured, then the lifecycle shall not
  record it as zero.
- **R31** — If a published view declares a capability that can publish new
  versions of itself, then the lifecycle shall refuse to publish it.
- **R34** — If an intent contradicts an active requirement, then the lifecycle
  shall ask which wins.
- **R41** — If an active requirement's sentence was rewritten in place, then
  the lifecycle shall report as suspect every artifact citing that requirement
  whose own line has not changed since that rewrite.
- **R43** — If a changed path matches no risk rule, then the lifecycle shall
  report that path as unclassified.
- **R44** — If a changed path matches no risk rule, then the lifecycle shall
  not report that path as a risk tier.
- **R46** — If a change's complexity was not measured, then the lifecycle
  shall not derive it from that change's risk tier.
- **R51** — If a check's fire rate over merged history could not be measured,
  then the lifecycle shall record that its severity was never calibrated.
- **R52** — If a change adds a citation of a requirement id that the spec does
  not hold, then the lifecycle shall report that citation as dangling.
- **R53** — If a change adds a citation of a superseded requirement, then the
  lifecycle shall report the active requirement that replaced it.
- **R54** — If a stage run produced no change outside the lifecycle's own
  bookkeeping, then the lifecycle shall not advance that work's stage.
- **R55** — If a stage advance would move work to a stage at or before its
  current stage, then the lifecycle shall refuse it.
- **R60** — If an unattended run would write to the default branch, then the
  lifecycle shall refuse to write it.
- **R63** — If a stage run changed a path its target stage does not permit, or
  a path that decides what CI runs, what an agent is told or allowed, or how
  git treats a path, then the lifecycle shall refuse to deliver that change,
  judging the paths git applies rather than the text of the patch.
- **R66** — If an unattended stage run's change would delete one of the
  lifecycle's own bookkeeping records, then the lifecycle shall refuse to
  deliver that change.
- **R70** — If a command an unattended run runs after the agent step is not
  git reading the repository's committed configuration, then the lifecycle
  shall run it with its working directory outside every tree the agent or its
  delivered patch could have written.
- **R72** — If a build-mode stage run changed no path outside the lifecycle's
  artifacts directory, then the lifecycle shall not advance that work's stage.
- **R75** — If a stage run's change creates or retargets a symbolic link, or
  adds, repoints or removes a submodule entry, then the lifecycle shall refuse
  to deliver that change.
- **R76** — If a stage run's change would modify a stage snapshot or a
  classification record, then the lifecycle shall refuse to deliver that
  change.
- **R77** — If a build-mode stage run's change removes or rewrites an existing
  line of the backlog, then the lifecycle shall refuse to deliver that change.
- **R83** — If an unattended stage run's change touches the lifecycle's checks
  result, then the lifecycle shall refuse to deliver that change.
- **R84** — If the repository has no solver probe, then the lifecycle shall
  refuse to render a pull request body.
- **R89** — If the spec path given for a classification is outside the root,
  then the lifecycle shall refuse to record it.
- **R90** — If a stage run's changed path holds a character outside ASCII and
  either has a component that begins with a dot or, read with each such
  character as any character, is a path the lifecycle refuses, then the
  lifecycle shall refuse to deliver that change.
- **R96** — If a check exits zero having examined less than it declared, then
  the lifecycle shall report it as hollow.
- **R97** — If a check exits zero having examined less than it declared, then
  the lifecycle shall treat it as a failure.
- **R98** — If a check is declared blocking, then the lifecycle shall record
  its fire rate over merged history.
- **R99** — If a check is declared blocking, then the lifecycle shall record
  how many commits returned a verdict in the window its fire rate covers.
- **R100** — If a check is declared blocking, then the lifecycle shall record
  a person's ruling on every fire in the window its fire rate covers.
- **R101** — If an intent contradicts an active requirement, then the
  lifecycle shall stop that intent until a person rules on the contradiction.
- **R102** — If a configured command would let the repository being examined
  select an executable in any argv position, and the configuration has not
  opted in to repository-declared check tools, then the lifecycle shall refuse
  to run it.
- **R105** — If the user guide cannot be regenerated, then the lifecycle shall
  not prepare the release.
- **R123** — If a command would publish or deploy, then the lifecycle shall
  not run it until a person approves.
- **R124** — If a flag line prepared for an unattended run is outside the
  fixed shapes `build-dispatch.sh prepare` writes, repeats a flag, or the
  prepared flags lack the Bash deny, then the lifecycle shall refuse the run.
- **R126** — If an unattended stage run changes a file that a check declared
  in `.claude/productizer/checks.yaml` at the base executes, then the
  lifecycle shall refuse the stage move.
- **R127** — If an unattended stage run must read
  `.claude/productizer/checks.yaml` at the base and cannot, then the lifecycle
  shall refuse to decide the stage move.
- **R131** — If the deliver job has no protected list for its HEAD while that
  HEAD has a `.claude/productizer/checks.yaml`, then the lifecycle shall
  refuse to deliver.
- **R142** — If a configured command names a path inside the repository being
  examined in any argument, and the configuration has not opted in to
  repository-declared check tools, then the lifecycle shall refuse to run it.
- **R143** — If a configured command hands the files under check to a program
  that is not on the plugin's data-only list, and the configuration has not
  opted in to repository-declared check tools, then the lifecycle shall refuse
  to run it.
- **R147** — If an unattended stage run changes a file named by the value an
  option carries in a check declared in `.claude/productizer/checks.yaml` at
  the base, whether or not that value is spelled as a path, then the lifecycle
  shall refuse the stage move.
- **R148** — If a configured command hands the semgrep data-only tool a
  registry id as its configuration, and no repository path of that name
  exists, then the lifecycle shall not count that id as a repository path.
- **R152** — If `models.advisor` is set to a value that is not a model name,
  then the lifecycle shall refuse to dispatch the build before a model is
  called.
- **R155** — If semgrep does not list a file under `paths.scanned`, or names
  it under `errors` or `paths.skipped`, then the lifecycle shall not count
  that file as examined by a semgrep check.
- **R156** — If a changed path that is substituted into a check's command
  begins with `-`, then the lifecycle shall pass it with a `./` prefix.
- **R157** — If a tracked path that the view builder links to its file on
  GitHub holds a character other than a letter, a digit, `/` or one of `_.-~`,
  then the lifecycle shall percent-encode that character in the link.
- **R158** — If an unattended stage run changes a script that, at the base, a
  script run by a check declared in `.claude/productizer/checks.yaml` names by
  its path, directly or through other scripts so named, then the lifecycle
  shall refuse the stage move.
- **R159** — If a workflow job that the lifecycle ships or runs installs
  PyYAML, then the lifecycle shall install only a wheel whose sha256 hash that
  job names.
- **R160** — If a workflow job kept between the base and the working tree
  loses a job from its `needs:` and gains none, or gains an `if:` it did not
  have, then the lifecycle shall report that move as a weakening of the
  governance surface.
- **R161** — If a workflow job kept between the base and the working tree has
  its `if:` rewritten, or a step that keeps its key has its `if:`, `run:`,
  `with:`, `env:` or `shell:` changed, then the lifecycle shall report that
  move as undecided.
- **R163** — If a finding in a review record names no file and line, no
  severity of Important, Nit or Pre-existing, or no bug class, then the
  lifecycle shall fail that review record.
- **R164** — If a review round in a review record states a finding count other
  than the number of findings it records, or records none and does not state
  `no issues`, then the lifecycle shall fail that review record.
- **R165** — If a finding in a review record is located under a path the
  review policy lists as ignored, then the lifecycle shall fail that review
  record.
- **R166** — If a review record holds more than three review rounds and does
  not state the approach that replaced patching, then the lifecycle shall fail
  that review record.
- **R167** — If a review round after the first in a review record does not
  start from the commit at which the round before it ended, then the lifecycle
  shall fail that review record.
- **R168** — If a review record holds a finding at the location and of the bug
  class of a finding from an earlier round, then the lifecycle shall fail that
  review record.
- **R169** — If a review record holds an Important finding whose status is
  open, then the lifecycle shall fail that review record.
- **R170** — If a finding in a review record has a status other than open,
  fixed, rejected, intentional or irrelevant, or a status other than open with
  no reason stated, then the lifecycle shall fail that review record.
- **R171** — If a change's plan has no section saying how the change is shown
  to work or no section saying how to revert it, or holds only the template's
  placeholder in either, then the lifecycle shall fail that plan.
- **R172** — If a pull request body handed to the lifecycle has no section
  saying how the change was tested or no section saying how to revert it, or
  holds only the template's placeholder in either, then the lifecycle shall
  fail that body.
- **R173** — If no CODEOWNERS file is where GitHub reads one, or the one
  GitHub reads leaves a file under `.claude/productizer/` or
  `.github/workflows/`, or a file a change adds there, with no owner other
  than a bot, then the lifecycle shall report that file as having no human
  code owner.
- **R174** — If a workflow step that keeps its key between the base and the
  working tree uses an action whose name, its `@ref` left out, differs from
  the one it used at the base, then the lifecycle shall report that move as
  undecided.
- **R175** — If an unattended stage run changes a symbolic link that, at the
  base, a check declared in `.claude/productizer/checks.yaml` runs or a script
  so run names by its path, directly or through other scripts or links so
  named, or changes the file or directory that link points to at the base,
  then the lifecycle shall refuse the stage move.
- **R176** — If a symbolic link protected from an unattended stage run points,
  at the base, outside the repository or to no path the base tree holds, then
  the lifecycle shall report that link as protected and its target as not
  followed.
- **R177** — If a `run:` that names PyYAML, in a workflow the lifecycle ships
  or runs, holds a pip install command, split from the commands around it at
  `;`, `&`, `&&`, `\|\|`, `\|` and line ends, that does not itself carry
  `--require-hashes` and `--only-binary :all:`, or carries `--no-binary` or
  another `--only-binary` value, then the lifecycle shall report that install
  as not pinned by hash.
- **R178** — If a review record scored against a reviewer case holds no
  round-1 Important finding whose location covers the case's confirmed bug, or
  its first round did not review the case's change, then the lifecycle shall
  score that case as missed.
- **R179** — If a reviewer case names no change as a commit, no confirmed bug
  as a `path:line` under the root or no fix, then the lifecycle shall refuse
  to score that case.
- **R180** — If a commit in a change carries a `This reverts commit` line
  naming a commit that no reviewer case under `evals/reviewer/` names as its
  change, then the lifecycle shall fail that change.
- **R181** — If a pull request changes `REVIEW.md`, then the lifecycle shall
  re-score the reviewer against every reviewer case.
- **R184** — If a band's current window holds no merged change or no review
  record, or fewer than three earlier windows hold a value, or the earlier
  windows all hold one value and the current value is above it, then the
  lifecycle shall report that band as not measured.
- **R187** — If a `run:` that names PyYAML, in a workflow the lifecycle ships
  or runs, holds a `#` that bash does not read as starting a comment, as one
  right after a `)` or a backquote that closes a command substitution, or a
  comment that bash ends at a closing backquote, then the lifecycle shall read
  a pip install after that `#` or that backquote as a command.
- **R188** — If a symbolic link's target, or a path that a script protected
  from an unattended stage run names, passes at the base through another
  symbolic link, then the lifecycle shall protect the file or directory the
  kernel reaches by following that link before a later `..` applies, and every
  link passed.
- **R189** — If resolving the target of a symbolic link protected from an
  unattended stage run passes through more than 40 symbolic links at the base,
  then the lifecycle shall report that link as protected and its target as not
  followed.
- **R190** — If the file a view is written to, or a path a view publishes, is
  on another drive than the repository, then the lifecycle shall build the
  view and read that path as outside the repository.
- **R191** — If a `run:` that names PyYAML, in a workflow the lifecycle ships
  or runs, holds a `#` that bash may read as starting a comment beside shell
  whose comments or quotes the lifecycle does not follow, as a heredoc, a
  `case`, a parameter expansion, a substitution inside double quotes or a
  quote inside backquotes, then the lifecycle shall report that `run:` as not
  read.
- **R195** — If a cap in `models.build_caps` is set to a value that is not a
  positive number of the shape the lifecycle passes on, then the lifecycle
  shall refuse to dispatch the build before a model is called.
- **R196** — If the flags prepared for an unattended run lack a turn cap or a
  spend cap, then the lifecycle shall refuse the run.

**Only where the feature is present.** Ten requirements apply only to a build
that includes the feature:

- **R22** — Where a repository declares its own check tools, the lifecycle
  shall run them only if the configuration explicitly opts in.
- **R27** — Where a backlog item names a Jira key, the lifecycle shall read
  that item's status from Jira.
- **R28** — Where a backlog item names a Jira key, the lifecycle shall write
  nothing back to Jira.
- **R30** — Where a published view hands over its evidence as a file, the
  lifecycle shall use a capability that writes only to the viewer's own
  device.
- **R154** — Where a check declares its standard error coverage-only, the
  lifecycle shall write nothing from that stream into the checks result except
  the items its coverage pattern captures.
- **R162** — Where the self-test coverage check is given a probe job count
  above one, the lifecycle shall run up to that many self-test probes at once,
  each under its own probe time limit.
- **R182** — Where a repository binds the revert-rate band, the lifecycle
  shall measure it as the commits of the last 30 days carrying a `This reverts
  commit` line divided by the changes merged in those 30 days.
- **R183** — Where a repository binds the review-rounds band, the lifecycle
  shall measure it as the mean number of rounds in the review records last
  changed in the last 30 days.
- **R185** — Where a repository binds a band beside the first, the lifecycle
  shall run that band's detection command only when that band's own binding
  matches the literal frozen into that band's own scheduled task.
- **R186** — Where a repository binds a band beside the first, the lifecycle
  shall leave the first band's bands file, binding and scheduled task prompt
  as they were.

Every id above is permanent. A plan, a test or a PR title naming `R1` will
still mean this sentence in two years, which is why ids are never reused and
never renumbered. The whole spec — the superseded text included, with the
acceptance criteria and the change log — is at `.claude/productizer/spec.md`.
<!-- productizer:requirements:end -->

## The rules it will not bend

1. Leave the record. Work that changed no spec and cites no issue did not happen.
2. Read the whole spec before changing it, not just the conversation.
3. A contradiction stops the work until a human rules.
4. Flag policy conflicts; never silently pick a winner.
5. Verify before reporting done, and paste the output.
6. Fix the code, not the test.
7. The agent acts up to the production gate and never past it.

Humans keep every judgement. Configuration handles the mechanics.
