# Hard corpus: pre-registration

Written 2026-09-13, before any case in `evals/hard-cases/` has been run by
anyone against any model. Every expectation below was fixed before a result
existed. A result that contradicts one is reported as a contradiction, and this
file is not edited to match it. Amendments go in the dated section at the end,
never in place.

Tree fingerprint at registration (see the end of this file for how to
recompute it): `00daa68d7a5fae5bf35efca8e122252401d146d77a163531e8b3a12707ee4cc4`

## Why this corpus exists

The 26-case corpus is at its ceiling as an instrument. Across every case where
the bare model ever failed (P03, P01, N05; 84 runs) the bare and plugin arms both
passed 30 of 42, Fisher two-tailed p = 1.0, and only 2 of 21 probed cases showed
any bare failure. More runs of those cases cannot move that. This corpus tries to
be harder, and to be hard in places where the plugin has something a bare model
does not.

## What the plugin arm actually has in this harness

Cases run with `allowed_tools: [Read, Glob, Grep, Skill]`. There is no Bash, so
**`contradiction-check.py` cannot run in either arm** and no case here is
grounded in it. The only mechanism that reaches the model is prose: the `spec`
skill's `SKILL.md`, and any `references/*.md` file the model chooses to Read.
That split matters, because several of the rules these cases lean on live only in
a reference file:

| Rule | Where it lives | Reaches the plugin arm |
|---|---|---|
| Check the constitution first; a principle binds unwritten requirements | `SKILL.md` | always, once the skill loads |
| Inferred requirements cannot trigger the halt | `SKILL.md` | always |
| Unquantified adjectives are arguments deferred to review | `SKILL.md` | always |
| A later intent against a ruling with no requirement left is a contradiction; do not read a ruling wider than it was written | `references/rulings.md` | only if Read |
| Refine vs contradict is interval inclusion; "genuinely unclear" is a contradiction | `references/ears.md` | only if Read |
| Match on trigger and system, not wording | `references/ears.md` | only if Read |

So a plugin effect on H07, H08, H11 or H12 that appears without a Read of the
reference it depends on is not that mechanism. That is only checkable with a
tool-call record; see *Measuring whether the skill fired*.

## Design

- **14 cases, 7 twin pairs, one shared fixture.** Every must-halt case has a
  must-not-halt twin on the same spec and constitution, with an intent that
  differs in the one respect that decides the class. A plugin that simply halts
  more gains on one twin and loses on the other, so the primary endpoint is the
  halt decision pooled over both halves, not recall.
- **One fixture, deliberately long.** `hard-fixtures/booking-spec.md` carries 38
  active requirements, one superseded, one withdrawn, two inferred, a design
  section, a change log and a decision record: about 14 KB of prompt against
  about 5.5 KB for P02. Length is part of the difficulty, and it is a confound:
  a plugin effect common to every pair cannot be told apart from "the plugin
  reads long specs more carefully". The twins control halt bias, not length.
- **Same format as `evals/cases/`**, graders and weights byte-for-byte from
  P03 (must-halt) and N05 (must-not-halt) with only the conflict or reason
  sentence, the ids and the class changed. `check-hard-corpus.py` runs
  `check-corpus.py`'s own structural check over this directory.

## Graders: which are deterministic

| Grader | Type | Used for the primary endpoint |
|---|---|---|
| `01-contradiction-detected` / `01-no-false-halt` | regex on the VERDICT line | **yes** |
| `03-both-sides-cited` / `03-ids-cited` | regex on ids | yes for H10 and H13 only, see below |
| `02-correct-class` (negatives) | regex | secondary |
| `02-work-halted`, `04-*`, `05-conflict-stated`, `06-ruling-requested` | LLM judge | secondary only |
| `99-skill-fired` | tool_used | indicator, unscored |

The LLM graders need a judge because each asks whether prose does something (halts
in words, refuses to resolve, states a conflict, reasons soundly) that no pattern
can recognise without also accepting a reply that quotes the pattern. None of them
feeds the primary endpoint. **H10 and H13 are conjoined with grader 03**: in H10
a halt citing only the inferred R35 is right by accident, and in H13 a halt that
does not name both R22 and R24 did not find the chain. For those two cases a
primary pass is `01 AND 03`.

## Per-case registration

Rates are the expected pass rate of the primary endpoint over runs. "Premise"
is the claim the case was built on; its falsifier is what would show the case does
not do what it was designed to do. Every case also carries one shared falsifier:
**if bare passes the primary endpoint in 19 or more of 20 stage-1 runs, the case
is not hard for a bare model** and is reported as such, whatever the plugin does.

| Case | Halt? | Mechanism the plugin has | Bare | Plugin | Expected direction | Premise falsified if |
|---|---|---|---|---|---|---|
| H01 far waitlist hold | yes | read the whole spec; match trigger not wording (ears.md) | 55-85% | 55-85% | **none** | plugin beats bare at p < 0.05: then the effect is procedural, and the "no mechanism difference" premise is wrong |
| H02 its twin | no | same | 85-100% | 80-100% | none | either arm false-halts on more than 3 of 20: the twin is not a clean control |
| H03 principle body, sync cancel keeps deposit | yes | constitution first (SKILL.md) | 60-90% | 65-95% | plugin slightly better | bare cites P2 in 19+/20 halts: the principle-body placement is not hiding anything |
| H04 its twin | no | same | 85-100% | 75-100% | plugin possibly **worse** ("automatically critical" priming) | plugin false-halts less than bare at p < 0.05 |
| H05 superseded id cited by the intent | yes | supersession markers; neither arm has an edge | 70-95% | 70-95% | none | bare classifies EXTEND citing R11 as live in 0 of 20: the id anchor is not a lure |
| H06 its twin, stale citation, no conflict | no | "genuinely unclear is a contradiction" (ears.md) | 70-95% | 60-95% | plugin **worse** | plugin false-halts less than bare at p < 0.05 |
| H07 withdrawn requirement, ruling D3 | yes | rulings against a withdrawn requirement are contradictions (rulings.md) | 40-80% | 55-90% | plugin better, only if rulings.md is Read | bare halts citing D3 in 19+/20; or the plugin is better in runs that never Read rulings.md |
| H08 its twin, ruling scope excludes minors | no | "a ruling read wider than it was written" (rulings.md) cuts both ways | 75-95% | 60-95% | plugin **worse** | plugin false-halts less than bare at p < 0.05 |
| H09 conflict with an inferred requirement only | no | inferred cannot halt (SKILL.md); the legend is in the fixture, so both arms can read it | 30-70% | 50-90% | plugin better | bare stays quiet in 19+/20: the legend alone is enough and the skill adds nothing |
| H10 inferred R35 masks active R12 | yes | same rule, which may make the plugin stop at R35 | 50-85% | 35-80% | plugin **worse** | plugin beats bare on `01 AND 03` at p < 0.05 |
| H11 "roughly 800 ms" loosened to p95 900 framed as measurable | yes | interval rule (ears.md); unquantified adjectives (SKILL.md) | 30-70% | 45-85% on 01; lower on 04 | plugin better on detection, **worse on grader 04** (the P03 reframing) | plugin grader-04 pass rate is not below bare's in stage 2 |
| H12 its twin, tightened to 750 | no | same | 80-100% | 75-100% | none on 01; plugin possibly worse on 04 | either arm false-halts on more than 3 of 20 |
| H13 joint conflict R24 then R22 | yes | classify against every active requirement | 40-75% | 40-75% | none | bare passes `01 AND 03` in 19+/20 |
| H14 its twin, warning that restates the chain | no | same | 80-100% | 80-100% | none | either arm false-halts on more than 3 of 20 |

Four cases are expected to favour the plugin (H03 slightly, H07, H09, H11 on
detection), five to disfavour it on some grader (H04, H06, H08, H10, H11 on 04),
and six to show nothing (H01, H02, H05, H12, H13, H14). Those are the author's
expectations, not a claim.

### Two cases whose ground truth is partly the plugin's own doctrine

- **H09.** Whether a conflict with an unagreed requirement is a halt is a
  position. The fixture states it neutrally in its own legend ("becomes active
  only when a human confirms it") so both arms can read the rule, but a bare
  CONTRADICT is defensible to a reader who weighs the test the requirement was
  read from. Report H09 separately as well as pooled.
- **H07.** D3 says "in any configuration", so CONTRADICT is the neutral reading
  too; but the only reason the class is not EXTEND is the decision record, and
  the rule that says to check it is plugin doctrine. Lower risk than H09.

## Considered and rejected

| Candidate | Why rejected, or what was done instead |
|---|---|
| A spec split across files, with the conflict in the other file | Not testable in this harness. A case must inline everything it grades against (`check-corpus.py` enforces one spec fixture inlined verbatim), so "the other file" is just another heading in one message; the plugin's actual split-spec handling runs through scripts the harness gives no Bash to run. A case where the second file is withheld would have "stop: spec home unreachable" as its right answer, which is not one of the four VERDICT classes. Length and far placement (H01, H13) are the part of this that survives inlining. |
| Contradiction with a principle, as briefed | Already in the corpus as P06, P07, P08; bare passed them in the probe. Kept only in a harder form: the principle's title does not cover the case and no requirement enforces the clause (H03). |
| Requirement superseded in place, intent cites old text, as briefed | Already P09 (bare passed). Kept in a harder form: the intent names the superseded id itself (H05), with a twin whose stale citation is harmless (H06). |
| Unquantified requirement that reads measured, as briefed | Already P03 (the intent was the vague side). Kept inverted: the requirement is the vague side and its acceptance row is the agreed bound (H11, H12). |
| Contradictions visible only against the whole spec, as briefed | Kept, split into far placement under vocabulary drift (H01) and a two-requirement chain (H13). P12 and P13 already cover short-spec versions and bare passed both. |
| A case for `contradiction-check.py`'s decidable fragment | Rejected: the solver cannot run in either arm of this harness, so a case grounded in it measures nothing about the plugin. |
| A Decision-record ruling without a withdrawn requirement | Folded into H07/H08; a ruling with no requirement at all tested the same rule with less signal. |
| A case where the intent carries authority text ("already approved") | Rejected for this corpus: that tests prompt-injection handling, a different claim from classification, and would need its own grader for obeying the text. |

## Isolation

- **`evals/solver-probe.py` does not read this directory.** It iterates a
  hard-coded `PAIRS` list of the 26 original slugs. Its output was captured
  before any file here existed and again after all of them did; the two outputs
  were byte-identical (TP 9, FN 1, FP 0, TN 10, undecided 6). The CI gate on
  those counts cannot move from this corpus.
- **`check-corpus.py` still reports 26 cases.** It is hard-wired to
  `evals/cases/`; `check-hard-corpus.py` reuses it without editing it.
- **`claude plugin eval` WILL see these cases unless filtered.** Its help text
  says it discovers `<eval dir>/**/prompt.md`, and the documented command in
  `references/evals.md` is `claude plugin eval . --no-publish` with the default
  `evals/` dir. Run the original corpus alone with a `--case` glob on the `N`/`P`
  slugs, and this one with `--tag b18-hard`, which every case here carries and
  no original case does. Neither filter has been executed; see *Not proven*.

## Measuring whether the skill fired

`--output-format json` carries no tool-call record, so B18's `99-skill-fired`
was never measured. `claude --help` documents `--output-format stream-json` as
"realtime streaming" output. Recommended, not verified: run the A/B arms with
`--output-format stream-json` (adding `--verbose` if print mode refuses it
without), keep the
stream, and count `Skill` and `Read` tool calls per run, including which
`references/*.md` files were Read. That turns the reference-only rows of the
mechanism table above into something a result can be checked against.

## Run plan

Nothing below has been executed. Spending on model runs is the maintainer's call.

**Stage 1: difficulty screen, bare arm only.** All 14 cases, n = 20 runs each,
280 runs. This is where each case's shared falsifier is read. If pooled bare
correctness on the primary endpoint is **95% or higher, stop**: the corpus is at
its ceiling too, and stage 2 would repeat B18's null at twice the price. Stage-1
runs are never pooled into stage 2; selecting on a bare arm and then reusing it
builds regression to the mean into the comparison, which is what P01 showed at
n=3.

**Stage 2: A/B on all 14 cases, whatever stage 1 found per case.** Dropping
cases that bare passed would select the corpus on a result. n = 20 runs per case
per arm, 280 per arm, 560 runs.

- **Primary endpoint.** Halt decision correct, pooled over all 14 cases (must-halt
  halted, must-not-halt did not; H10 and H13 need grader 03 as well). Fisher
  exact two-tailed, alpha 0.05, bare against plugin. Every case contributes 20
  runs to each arm, so the case mix is identical in both and the unstratified
  test is conservative, not inflated.
- **Secondary, reported, not tested for significance as a family.** Recall over
  the 7 must-halt cases; false-halt rate over the 7 must-not-halt cases; each
  pair; each LLM grader; cost and duration per arm; skill and reference-Read
  counts per arm if stream-json is used.
- **Exclusions.** A run with `is_error: true` or no VERDICT line is `incomplete`,
  counted and reported per arm, never scored as a fail or a pass. If one arm's
  incomplete count exceeds the other's by more than 5, the comparison is reported
  as confounded.
- **Judge.** One blind judge on the LLM graders, as in B18. A second rater on a
  random 20% of runs is recommended and not costed.

**Power**, from `python3 evals/hard-power.py` (exact Fisher, two-tailed alpha
0.05, 80% power; the Fisher routine checks itself against B18's published P03
p = 0.6499 before printing anything):

| Bare | Plugin | n per arm needed |
|---|---|---|
| 0.625 | 0.750 | 230 |
| 0.700 | 0.850 | 131 |
| 0.750 | 0.875 | 165 |
| 0.800 | 0.900 | 214 |
| 0.600 | 0.800 | 90 |

At 280 per arm, power is 0.876 for 62.5% to 75%, 0.962 for 75% to 87.5%, and
0.988 for 70% to 85%. Per case, 20 runs per arm detects only very large effects
(0.4 to 0.7 alone needs 48), so per-case results are descriptive.

**Cost floor**, from B18's measured P02 medians ($0.0651 bare, $0.1378 plugin
per run):

| Stage | Runs | Floor |
|---|---|---|
| 1, bare only | 280 bare | $18.23 |
| 2, A/B | 280 bare + 280 plugin | $18.23 + $38.58 = $56.81 |
| Total | 840 | **$75.04** |

That is a floor, not an estimate. Three things push it up and none is measured:
each prompt here is about 14.3 KB of body against P02's 5.5 KB, roughly 2,250
more input tokens per run at the calibrated 3.89 bytes per token, in both arms;
LLM judge calls (four graders per must-halt run, one per must-not-halt run); and
any retries of incomplete runs. B18's cap was $25, which this plan exceeds in
stage 1 plus half of stage 2. A cheaper stage 2 at n = 10 per case per arm (140
per arm, $28.40 floor) keeps 0.83 power for 70% to 85% but only 0.57 for 62.5%
to 75%.

## Recomputing the fingerprint

```
cd evals && find hard-cases hard-fixtures -type f | LC_ALL=C sort \
  | xargs shasum -a 256 | shasum -a 256
```

## Amendments

None.
