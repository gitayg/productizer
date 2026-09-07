# Productizer — living spec

System
: `<system-name>` — the exact noun every requirement below uses. Never vary it.

Spec location
: `.claude/productizer/spec.md`. Inside `.claude/` deliberately: build tooling, static
site generators, doc builds and packaging all skip that directory, so the spec
is never rendered as a page or shipped in a release.

Next requirement id
: `R42` — allocate from here, then increment. This is the highest id the spec
has ever used, not a count of the rows on screen. Ids are never reused and
never renumbered, and stay unique across the whole repo even if this spec is
later split into several files.

Requirements
: 35 active, 6 superseded, 0 withdrawn.

Audit trail
: `git log -p .claude/productizer/spec.md`. Each commit is one change, joined to the
issue that drove it by the branch name and the PR title. There is no
per-change copy of this spec.

## How to read this file

This is the one spec for the repo, and it is always current. An intent — a
file, text typed by a user, a GitHub Issue, a Jira ticket — is an **input**. It
is classified against what is already here, merged in, and then done with. Work
is built from the delta this file gained, not from the intent.

- **Requirements are EARS**, one per sentence, one `shall` each, grouped below
  by pattern. Patterns, id discipline and the intake classification — extend,
  refine, contradict, duplicate — are in `references/ears.md`.
- **Every requirement carries a status marker** on the line after it:

  | Status | Meaning | Recorded as |
  |---|---|---|
  | Active | Current agreed behaviour | no marker; the requirement, plain |
  | Superseded | Replaced by another requirement | `Superseded by R58.` plus one line on why |
  | Withdrawn | The behaviour no longer exists at all | `Withdrawn.` plus one line on why |

- **Nothing is ever deleted.** A superseded or withdrawn requirement keeps its
  original sentence, in place, so the file reads as the record of what was
  agreed and when it stopped being true. Deleting one breaks every plan, test,
  review finding and PR title that cites it, silently.
- **Refining keeps the id.** Making a requirement stricter, more specific or
  more measurable without changing what is agreed is an edit in place. Changing
  the behaviour allocates a new id and supersedes the old one.
- **A contradiction stops the process.** When an incoming intent conflicts with
  an active requirement, do not supersede it. Record the conflict under *Areas
  of concern*, name both owners, and ask a human which wins. Record the ruling
  before writing either requirement.

## Scope

The durable boundary of this system, not of any one change.

In scope
- Holding one living spec per product, and classifying every arriving intent
  against the whole of it.
- Halting when an intent contradicts an agreed requirement, and recording the
  ruling that resolves it.
- Declaring and running the checks a change must pass, and refusing a check
  that cannot show what it examined.
- Publishing read-only views of all of the above, regenerated from the files.
- Gating the two irreversible acts — deploying and publishing — behind a person.

Out of scope
- Writing the code. The agent already does that; this governs what it is
  allowed to build and when it must stop.
- Being a ticket tracker. Where a backlog item names a Jira key, Jira owns that
  item's status and nothing is written back to it.
- Hosting, CI, or deployment mechanics. Those belong to the repo's own tooling;
  this only decides whether the change may proceed.

## Requirement index

Maintain this once the spec passes roughly thirty requirements — it is how the
file stays skimmable at two hundred. One row per requirement, in id order.

| Id | Area | Pattern | Status | Verified by |
|---|---|---|---|---|
| R1 | <area> | ubiquitous | active | `<test name>` |
| R2 | <area> | event | superseded by R41 | — |
| R3 | <area> | state | withdrawn | — |

## Requirements

### Ubiquitous — always active

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent: never reused, never renumbered.
- **R3** — The lifecycle shall keep a replaced requirement's original text in the spec, marked superseded.
- **R4** — Every published view shall be read-only with respect to the spec.
- **R5** — Every check shall declare what it must have examined for its pass to count.
- **R39** — Every check tool shall carry a self-test that reaches each exit code it can return.

### Event-driven

- **R6** — When an intent arrives, the lifecycle shall classify it against the whole living spec as exactly one of extend, refine, duplicate or contradict.
- **R7** — When an intent is classified, the lifecycle shall record the classification in the spec's change log.
  Superseded by R32. R7 required a change-log row for EVERY classification, and that log is defined as one row per commit to this file - so a classification that merges nothing was asked for a row in a table keyed on an event that did not happen. Narrowed to the classifications that actually change the spec.
- **R8** — When a requirement is added, the lifecycle shall allocate the next unused id and record it in the acceptance criteria table.
  Superseded by R35. Split into R35 and R36 — the sentence carried two obligations under one id, and no single check asserted both, so it read `Partial` while both halves were in fact asserted.
- **R9** — When a release is prepared, the lifecycle shall regenerate the user guide from the active requirements.
- **R10** — When a repository with history is imported, the lifecycle shall mark every drafted requirement inferred and unconfirmed.
- **R11** — When a published view is regenerated, the lifecycle shall read every figure in it from a file in the repository.
- **R32** — When a classification changes the spec, the lifecycle shall record it in the spec's change log.
- **R35** — When a requirement is added, the lifecycle shall allocate the next unused id.
- **R36** — When a requirement is added, the lifecycle shall record it in the acceptance criteria table.
- **R37** — When a person overrides a failing check, the lifecycle shall record the override in a file naming the check, the authority and the reason.
- **R40** — When the check suite runs, the lifecycle shall run the self-test of every check tool it invokes.

### State-driven

- **R12** — While a contradiction is unruled, the lifecycle shall merge no spec change that depends on it.
- **R13** — While a check tool named by the configuration is absent, the lifecycle shall report that check as missing rather than skipped.
- **R38** — While a failing check is overridden, the lifecycle shall render it as failed and waived, and never as passed.

### Unwanted behaviour

- **R14** — If an intent contradicts an active requirement, then the lifecycle shall stop and ask which wins, and shall merge nothing.
  Superseded by R33. Split into R23 and R24 — the sentence carried two obligations under one id, so a test could satisfy one half and leave the other unasserted. R23 was itself split again under B31 into R33 and R34, so the pointer moved to R33 rather than leaving a chain that ends on a superseded requirement: a citation has to reach a requirement someone can still read as current. This sentence's obligations now live in R33 (stop), R34 (ask) and R24 (merge nothing).

- **R15** — If a check exits zero having examined less than it declared, then the lifecycle shall report it as hollow and treat it as a failure.
- **R16** — If a value could not be measured, then the lifecycle shall report it as unmeasured and shall not record it as zero.
  Superseded by R25. Split into R25 and R26 — the sentence carried two obligations under one id, so a test could satisfy one half and leave the other unasserted.

- **R17** — If a command would publish or deploy, then the gate shall block it until a person approves.
- **R18** — If a configured command names a shell or an interpreter with an inline program, then the lifecycle shall refuse to run it.
- **R19** — If the spec home is unreachable, then the lifecycle shall stop rather than classify against a remembered copy.
- **R20** — If a survey finds too little evidence to draft from, then the lifecycle shall refuse to draft a spec from it.
- **R23** — If an intent contradicts an active requirement, then the lifecycle shall stop and ask which wins.
  Superseded by R33. Split into R33 and R34 — the sentence carried two obligations under one id, and no single check asserted both, so it read `Partial` while both halves were in fact asserted.
- **R24** — If an intent contradicts an active requirement, then the lifecycle shall merge nothing.
- **R25** — If a value could not be measured, then the lifecycle shall report it as unmeasured.
- **R26** — If a value could not be measured, then the lifecycle shall not record it as zero.
- **R29** — If a configured command would let the repository being examined select an executable in any argv position, then the lifecycle shall refuse to run it.
- **R31** — If a published view declares a capability that can publish new versions of itself, then the lifecycle shall refuse to publish it.
- **R33** — If an intent contradicts an active requirement, then the lifecycle shall stop.
- **R34** — If an intent contradicts an active requirement, then the lifecycle shall ask which wins.
- **R41** — If an active requirement's sentence was rewritten in place, then the lifecycle shall report as suspect every artifact citing that requirement whose own line has not changed since that rewrite.

### Optional

- **R21** — Where a backlog item names a Jira key, the lifecycle shall read that item's status from Jira and shall write nothing back.
  Superseded by R27. Split into R27 and R28 — the sentence carried two obligations under one id, so a test could satisfy one half and leave the other unasserted.

- **R22** — Where a repository declares its own check tools, the lifecycle shall run them only if the configuration explicitly opts in.
- **R27** — Where a backlog item names a Jira key, the lifecycle shall read that item's status from Jira.
- **R28** — Where a backlog item names a Jira key, the lifecycle shall write nothing back to Jira.
- **R30** — Where a published view hands over its evidence as a file, the lifecycle shall use a capability that writes only to the viewer's own device.

## Design

How the requirements are met. Components, data flow, the decisions that were
not obvious. Anything a test cannot observe belongs here, not above. Organise
by the same areas the requirements use, and cite the ids each note serves.

### <area>
<Design notes. Serves R1, R4.>

## Areas of concern

Flag these explicitly rather than resolving them silently. Where two policies
contradict, name the conflict and both policy owners — do not pick a winner. An
intent that contradicts an active requirement lands here first and stays open
until a human rules on it.

| # | Concern | Requirements | Policy / owner | Raised by | Status |
|---|---|---|---|---|---|

## Acceptance criteria

| Requirement | Verified by |
|---|---|
| R1 | `spec-home` check over `check-spec-home.sh` — reads `product.spec_home`, refuses a repo it cannot open rather than counting it as having no spec. Declared and passing 2026-08-30. Its limitation is declared with it: a product whose repos are not all declared is invisible to it. |
| R2 | `references/ears.md` id-lifecycle rules; reviewed at intake |
| R5 | `scripts/run-checks.sh` coverage assertion; `hollow` path |
| R11 | `scripts/build-view.sh` — byte-identical across runs and timezones |
| R15 | `run-checks.sh` hollow detection — proven on a stub and on real semgrep |
| R17 | `templates/publish-gate.sh` — 42-case block corpus, 41-case allow corpus |
| R18 | `run-checks.sh` argv[0] validation — shells, interpreters, repo-local paths |
| R20 | `scripts/import-survey.sh` Verdict section |
| R22 | `policy.allow_repo_local_tools`, default false |
| R23 | Two halves, asserted separately. **Stop:** `scripts/contradiction-check.py --selftest` — 9 true positives, precision 1.00, measured 2026-09-03 (was 7 before the disposition lexicon and the bound-parser fixes; the count moves with the corpus, so it carries its date). **Ask:** `ruling-requested` check over `check-ruling-requested.sh` — fails when a concern is open with no ruling file, when a pending ruling is cited by nothing, and when a pending ruling still wears the template. Proven by removing a raised ruling and watching it go red 2026-08-30 |
| R24 | `nothing-merged` check over the committed fixture `fixtures/nothing-merged/`, driven through the real contradiction path. Four assertions reported separately: the spec is byte-identical with `## Areas of concern` excised (the stop is required to append a row there), no requirement id was allocated, the change log gained no row, the acceptance table gained no row. Each falsified on its own. The id assertion also covers ids taken INSIDE the excised section — a gap found by falsifying, not by reading: the first version went green on it. Both premises guarded — an intent that does not contradict, or a merge path that exited non-zero, is exit 2, because a spec left untouched by an error is not a spec the lifecycle declined to merge |
| R25 | `check-hygiene.sh`, `stage-status.sh`, `build-view.sh` unmeasured states (inherited from R16) |
| R26 | `no-fabricated-zero` check over the committed fixture `fixtures/fabricated-zero/`. It reads THE RESULT FILE, never the printed line, because the two are separable and were shown to be: a run can print `spec coverage: UNMEASURED` and write `units_total: 0` in the same breath, passing R25 and failing R26. Seven assertions, each naming which of absent / null / zero / value the field is in. Falsified three ways — all five denominator fields zeroed, one check row's coverage block zeroed alone, and `units_total` zeroed alone. Both premises guarded: an installed tool or a readable spec is exit 2, unmeasured, never a pass |
| R27 | **Out of force here, and re-measured every run.** `jira-unbound` check reads `config.json` and the backlog and claims `n/a` only while `jira` is null and no row names a key. The claim is bound to the check passing, so binding Jira or writing a key into the backlog fails it, voids the claim, and returns R27 to `Missing`. Nothing asserts the guarded behaviour, because nothing here implements it — building the integration is a backlog item |
| R28 | **Out of force here, and re-measured every run.** Same guard and same measurement as R27, via the same `jira-unbound` check. With no binding and no key there is no Jira to write back to, so the obligation not to write is unreachable rather than unimplemented |
| R29 | `run-checks.sh` argv validation over EVERY element, not `value[0]`. Falsified against HEAD with a marker file: `awk` with a positional program, `python3` naming a repo-local script as an ARGUMENT, and `make` each exited 0 with the payload executed; all three now refuse at validation with the payload absent. The repo's own config still passes under `allow_repo_local_tools: true`, and is refused with it false. |
| R30 | **Nothing yet.** The capability is not declared by any view today - `views.publish_as_artifact` is on and no page asks for `downloads`. A verifier would assert that a view offering a file uses only a capability that writes to the viewer's device, and that the offer is refusable by the viewer. Not built |
| R31 | `view-read-only` check - already asserts the published page declares no capability that can publish a new version of itself, and fails on an unrecognised capability name because one that has not been shown to be output-only has not been shown to be safe. Falsified 2026-08-30 against a page declaring the self-publishing capability, and against one declaring only `downloads`, which passes |
| R3 | `superseded-text` check over `check-superseded-text.sh` — diffs each superseded requirement's text against the last commit at which it was still active, choosing that baseline per requirement. The first check here to read git history. Falsified by editing a superseded sentence and watching it go red; a shallow clone is refused, never passed. |
| R4 | `view-read-only` check — both halves. The generator moves no repository file (every file hashed before and after, content and mtime), and the page declares no capability that can publish a new version of itself. Falsified four ways on the first half and three on the second; a page that could not be built is exit 2, never zero capabilities. |
| R6 | `classification-provenance` check — asserts every active requirement id was in the context the classification was made from, and that exactly one classification was recorded. Falsified by dropping an active id from a record's scope list. |
| R32 | **Nothing yet.** A verifier would assert that every change-log row cites an intent, and that a commit changing the Requirements section carries a row. The inverse - a classification that merged nothing and wrote no row - is correct by construction under R32 and needs no check. Not built |
| R33 | `solver-corpus` check running `contradiction-check.py --selftest` on every commit — the solver halts on a real contradiction and stays quiet on a non-conflict, precision 1.00 over the committed corpus. This is the half R23 credited to a CI step that carried no coverage claim |
| R34 | `ruling-requested` check — a raised concern must cite a ruling that exists, is cited back, and is filled in enough to answer. Falsified by removing a raised ruling and watching it go red. Known gap, inherited from R23: a contradiction stopped with nothing written to the spec leaves it nothing to find |
| R35 | `spec-integrity` check — the `Next requirement id` counter is strictly above every id ever used, superseded and withdrawn included, and every addition is named in the change log. Falsified by setting the counter below a used id, which drops R8.1 to 4 of 28 while R8.2 still holds |
| R36 | `acceptance-rows` check — every active requirement has a row in this table. Falsified by adding an active requirement with no row. Known gap, inherited from R8: it asserts a row EXISTS, never that the row is true |
| R37 | `waiver-rendering` check — a waiver file that omits the check, the authority or the reason is a finding, and a waiver naming a check that does not exist is a finding. Falsified per field |
| R38 | `waiver-rendering` check — a waived failing check is rendered `FAIL - WAIVED BY <authority>` and its status stays `fail`; the run reports it as waived rather than passed, and P1 is why: the measurement does not move because a person decided something about it |
| R8 | `acceptance-rows` check — asserts every active requirement has a row here. Superseded, withdrawn and inferred requirements are exempt, the last per `references/import.md:70`. Measured 2026-08-30: 25 active, 25 rows. |
| R9 | `guide-current` check over `build-guide.sh --check` — regenerates the guide's requirements section into memory and reports drift without writing. Falsified by weakening a requirement's wording inside the markers; missing markers are refused rather than guessed at. |
| R10 | `import-marking` check — fails a requirement attributed to an import that carries no inferred marking. Attribution is structural, from a marked sibling's change-log row or introducing commit; the naive signal (the word *import* in a message) was built first and measured as unusable. **Declared limitation:** an import that marked nothing and named no stage is invisible, and the run says so. |
| R12 | `pending-ruling-scope` check — refuses a spec change touching the requirement a pending ruling names, and prints the allocations it lets through so the decision not to block is visible. Falsified both ways: the contested requirement blocks, an unrelated one does not. |
| R13 | `missing-tool-reported` check over a committed fixture in `fixtures/missing-tool/` — six assertions, including that an absent tool changes the VERDICT and not only the status, because a status that does not change the verdict is a skip wearing a different name. The fixture guards its own premise: point it at an installed tool and it reports unmeasured, not a pass. |
| R19 | `spec-home-stop` check — four constructed trees, two differing only in whether one classification record exists. An unreachable spec home with nothing classified is clean; the same tree with a record is a finding; a record that cannot name its spec commit is a finding; a reachable home with a well-formed record stays clean. Each assertion falsified separately. The row previously named `classification-provenance`, which asserts that a record carries the commit and hash it was made against and claims R6 — related mechanism, different obligation. `acceptance-rows` 1.1 caught the disagreement between this row and the claim |
| R39 | `selftest-coverage` check over `check-selftest-coverage.sh` — reads the tools the declared checks and `.github/workflows/checks.yml` actually invoke and reports which carry a self-test that ANSWERS, by running it rather than by grepping for the flag. **Measured 2026-09-06: 34 of 34.** Every repository check tool now carries one; 28 were written in a single pass and each was seen failing on a deliberate break before being believed. **The clause `reaches each exit code it can return` is now COUNTED, NOT ASSERTED.** It is knowable only to the self-test, so it is a reporting protocol — one line, `exit codes reached: <codes>   documented: <codes>`, both halves bare integer lists, the reached half computed from the cases as they ran — parsed out of each self-test's own output. Three figures are kept apart and never added: how many DECLARE, how many of those drove every code they document, and how many were NOT ASKED. **Measured 2026-09-07: 34 of 34 declare, 34 of 34 complete, 0 unmeasured.** (Superseded: on 2026-09-06 this read 3 of 34 declaring and 31 unmeasured — 11 silent, 20 emitting a prose codes line with no `documented:` half. The 31 emitters were then written, each computing its reached-list from the cases as they ran.) One documented code was found genuinely undriven by the declaration and was fixed by DRIVING it, not by trimming the contract: `contradiction-check.py` documents exit 2 and its file mode cannot produce one, so three real usage cases were added. No exit code rests on any of them: a self-test never asked which codes it drove has not been shown incomplete, and this reader cannot tell a computed reached-list from a hardcoded one. NOT asserted, still: Most self-tests assert the exit CODE only, and four separate falsifications during that pass kept exit 1 while the defect was live — a renumbering read as a deletion, per-line clearing reverted to per-file, an assertion switched off entirely — so a case red for the WRONG REASON is invisible unless the case also asserts a sentence. Each tool prints its own `NOT ASSERTED:` line saying which it does |
| R40 | `selftest-coverage` check over `check-selftest-coverage.sh` — distinct from R39: R39 obliges a self-test to EXIST, this obliges something to RUN it. **Measured 2026-09-06: 34 of 34**, each named on its own line in the workflow. A loop over a glob would run every self-test and still leave this at zero, because reachability is read from the workflow SOURCE; and no line is guarded with `\|\|` and no step sets `continue-on-error`, both of which the check treats as SWALLOWED — a self-test whose failure cannot set the run's exit code has not been run in any sense that matters. **CORRECTION, measured 2026-09-06:** an earlier version of this row claimed `check-nothing-merged.sh --selftest` existed. It did not, and the first correction was also wrong: that file never advertised the flag at all — the string in it is a line-wrapped reference to `contradiction-check.py --selftest`, a DIFFERENT tool. It has a real self-test now. NOT asserted: reachability is static, so a self-test run by a Makefile, a git hook or a person is invisible, and a declared check whose tool is absent at run time reads as reached while running nothing |
| R41 | **Nothing yet.** `check-suspect-links.sh` covers the case where the rewrite is INSIDE the range measured, and `checks.yaml` already declares the gap: it compares against ONE base ref. DEMONSTRATED 2026-09-05 on a constructed history outside this repo - R1 inverted in place from `exactly one` to `at most three`, two unrelated commits on top: the default base exits 0 PASS with `sentence changed in place: 0` while the stale acceptance row goes unflagged, and the same tree with a base behind the rewrite exits 1 and flags it. A verifier would choose the baseline PER REQUIREMENT, at the commit that requirement's own sentence last changed |

## Change log

One row per commit to this file. The issue column is the join to the work that
drove the change; the same identifier appears in the branch name and the PR
title, so the spec diff and the delivery record line up without anyone
maintaining a link.

Each row summarises one change; the full statement of that change — every id
that moved, with its text quoted and its constitution check — is the spec delta
(`templates/spec-delta.md`) in the PR body. The delta is never committed as a
file, because a per-change copy of the spec drifts from the spec the first time
someone edits one and not the other.

| Date | Issue | Branch / PR | Added | Refined | Superseded / withdrawn | Summary |
|---|---|---|---|---|---|---|
| <YYYY-MM-DD> | <#123 / PROJ-123> | `<branch>` / <pr> | R41–R43 | R12 | R7 → R41 | <what changed and why> |
| 2026-09-06 | [#8](https://github.com/gitayg/productizer/issues/8), [#9](https://github.com/gitayg/productizer/issues/9) | `main` / — | R39–R41 | — | — | B42 and B43, both classified `extend` at Stage 1 against all 32 active requirements and the 4 principles. B42 was judged to carry TWO obligations and split, the sixth such split in this spec: R39 obliges a check tool to CARRY a self-test, R40 obliges the suite to RUN it. R41 is B43. Every wording was paired by `contradiction-check.py` against all 32 active requirements: no contradiction, no undecided. R39's subject noun was chosen BROAD over narrow by the maintainer, knowing the measured consequence - 58 scripts, 4 with a self-test - so all three land `Missing` under `spec_coverage: require` and the suite goes red on arrival. That red is the work queue, accepted deliberately. R33, R34 and R38 were also moved to the headings their sentence shape requires, clearing the three long-standing EARS_SECTION_MISMATCH warnings; no sentence, id or status changed |
| 2026-09-02 | [#7](https://github.com/gitayg/productizer/issues/7) | `feature/7-waiver-rendering` / PR | R37–R38 | — | — | B13. A ruling records that a person overruled a failing check; what the CHECK shows afterwards was never decided. Intake split it because the rendering and the FORMAT that records the waiver are two obligations - a ruling file records the decision and no file format records the waiver, which is why this sat blocked by design rather than by effort. P1 constrains the answer: an overridden check WAS measured, so P1 does not forbid this, but a failure rendered green because somebody said so is a judgment wearing a measurement's clothes. So the status stays `fail` and only the rendering and the blocking change. |
| 2026-09-01 | — | — | R33–R36 | — | R8 → R35, R36; R23 → R33, R34 | B31. Each carried two `shall` clauses under one id. The runner takes the best SINGLE claim per requirement, never a union, so a requirement whose halves are asserted by two different checks reads `Partial` forever - which is what both did. Split so every obligation has its own id and its own claim, the same remedy applied to R14, R16 and R21. Originals retained verbatim, marked superseded. |
| 2026-08-29 | — | — | R23–R28 | — | R14 → R23, R24; R16 → R25, R26; R21 → R27, R28 | Each of the three carried two `shall` clauses under one id. Split so every obligation has its own id and neither half can be half-tested. Originals retained verbatim, marked superseded. |
| 2026-08-30 | [#2](https://github.com/gitayg/productizer/issues/2) | `feature/2-argv-any-position` / PR | R29 | — | — | R18 is narrower than P4, the principle it is listed as enforcing: it names a shell or an interpreter with an inline program, and says nothing about the other argv positions. Three bypasses were reproduced against it. Classified `extend` at Stage 1 and kept as extend by ruling: R18 stays active and true. **Recorded against that choice:** R29 subsumes R18, so a test satisfying R18 proves nothing about R29 - the same shape as the defect that split R14, R16 and R21, and the reason supersede was the alternative considered. |
| 2026-08-30 | [#1](https://github.com/gitayg/productizer/issues/1) | `feature/1-view-hands-over-evidence` / PR | R30, R31 | — | — | A published view may hand over its evidence as a file. Two ids, not one: the permission is Optional and the refusal is unwanted behaviour, different EARS categories, and one id would let a test prove the permission while nothing asserted the refusal - the half that protects the spec. R31 is asserted on arrival by the existing `view-read-only` check; R30 is not, and its row says so. |
| 2026-08-30 | [#3](https://github.com/gitayg/productizer/issues/3) | `feature/3-r7-narrowed` / PR | R32 | — | R7 → R32 | R7 could not be satisfied as written: it demanded a change-log row for every classification, and the log is defined as one row per commit to this file. Three classifications the same day merged nothing and so wrote nothing, making them violations of a requirement the practice was right to ignore. Narrowed to classifications that change the spec; a classification that stops is recorded where the intent lives - a `D` ruling and `C` row for a contradiction, the cited id for a duplicate. |

## Decision record

Decisions that shaped the spec but are not themselves requirements — including
every contradiction ruling.

| Date | Decision | Why | Who |
|---|---|---|---|
| <YYYY-MM-DD> | <what was decided> | <the reason, not the restatement> | <name> |
| 2026-08-29 | Split R14, R16 and R21 into new ids rather than editing them in place or amending the one-`shall` rule | A split is not a refinement: two obligations cannot share one id, and the id is what tests and plans cite. Editing in place would leave every existing citation pointing at half of what it used to mean. Amending the rule was the other option `ears.md` names, and was rejected because the rule is what makes a requirement single-assertion testable. | — |
