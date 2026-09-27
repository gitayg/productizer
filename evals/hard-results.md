# B18 hard corpus — results

Run 2026-09-26. Companion to `hard-preregistration.md`, which is **left exactly as
it was written**: a pre-registration that gets edited after the numbers arrive is
not one. Everything that disagrees with it is recorded here as a disagreement.

Every figure below was recomputed in the main session from the run's own result
files and traces, independently of the report that produced it — the two agreed
to six decimal places on the endpoint, and the Fisher implementation was
cross-checked against a brute-force one on the pre-registration's own published
B18 self-check (3/10 vs 5/10 → 0.649917, both).

## The primary endpoint is null

Halt decision correct, pooled over all 14 cases, Fisher exact two-tailed,
alpha 0.05:

```
BARE   : 239/280 = 0.8536
PLUGIN : 235/280 = 0.8393
Fisher exact two-tailed p = 0.725287      NOT significant
incomplete runs: 0 in both arms, so the comparison is not confounded by them
```

**No effect, and the point estimate points the wrong way** — the plugin arm is 4
runs worse. This reproduces B18's earlier null on a corpus built to be harder, at
n=280 per arm instead of 42 pooled. That is the pre-registered n, with 0.876
power for 62.5%→75% and 0.962 for 75%→87.5%, so an effect of that size is now
EXCLUDED rather than merely unobserved. That exclusion is the result; the earlier
n could not support it.

The endpoint is the sum of two graders, one per case type, and they are reported
apart because they answer different questions:

| | bare | plugin |
|---|---|---|
| `01-contradiction-detected` (7 must-halt cases) | 125/140 = 0.89 | 120/140 = 0.86 |
| `01-no-false-halt` (7 twin cases) | 114/140 = 0.81 | 115/140 = 0.82 |

## Stage 1 — the difficulty screen, and the stop rule that did not fire

280 bare runs, 0 incomplete. **Pooled bare 242/280 = 0.8643**, below the 95% that
would have stopped the work, so stage 2 was required.

| case | type | bare | pre-registered range | verdict |
|---|---|---|---|---|
| H01 | must-halt | 20/20 = 1.00 | 55–85% | above |
| H02 | twin | 20/20 = 1.00 | 85–100% | in range |
| H03 | must-halt | 20/20 = 1.00 | 60–90% | above |
| H04 | twin | 15/20 = 0.75 | 85–100% | **below** |
| H05 | must-halt | 20/20 = 1.00 | 70–95% | above |
| H06 | twin | 19/20 = 0.95 | 70–95% | in range |
| H07 | must-halt | 20/20 = 1.00 | 40–80% | above |
| H08 | twin | 20/20 = 1.00 | 75–95% | above |
| H09 | twin | 0/20 = 0.00 | 30–70% | **below** |
| H10 | must-halt | 20/20 = 1.00 | 50–85% | above |
| H11 | must-halt | 8/20 = 0.40 | 30–70% | in range |
| H12 | twin | 20/20 = 1.00 | 80–100% | in range |
| H13 | must-halt | 20/20 = 1.00 | 40–75% | above |
| H14 | twin | 20/20 = 1.00 | 80–100% | in range |

**The shared falsifier — "this case is not hard for a bare model", at 19 or more
of 20 — fired on 11 of the 14 cases.** The harder corpus is at its ceiling on
eleven of its own cases. The stop rule missed only because H04, H09 and H11 pulled
the pool down to 86%. A corpus whose cases are individually saturated cannot show
an improvement on them whatever the treatment is, and that, not the p-value, is
the most useful thing this run learned about the instrument.

## Stage 2 — per case, descriptive only

The pre-registration declares per-case results descriptive: 20 per arm detects
only very large effects. These p-values are uncorrected and there are fourteen of
them.

| case | bare | plugin | delta | p (descriptive) |
|---|---|---|---|---|
| H01 | 20/20 = 1.000 | 20/20 = 1.000 | +0.000 | 1.0000 |
| H02 | 20/20 = 1.000 | 20/20 = 1.000 | +0.000 | 1.0000 |
| H03 | 20/20 = 1.000 | 20/20 = 1.000 | +0.000 | 1.0000 |
| H04 | 17/20 = 0.850 | 15/20 = 0.750 | −0.100 | 0.6948 |
| H05 | 20/20 = 1.000 | 20/20 = 1.000 | +0.000 | 1.0000 |
| H06 | 17/20 = 0.850 | 18/20 = 0.900 | +0.050 | 1.0000 |
| H07 | 20/20 = 1.000 | 20/20 = 1.000 | +0.000 | 1.0000 |
| H08 | 20/20 = 1.000 | 20/20 = 1.000 | +0.000 | 1.0000 |
| H09 | 0/20 = 0.000 | 2/20 = 0.100 | +0.100 | 0.4872 |
| H10 | 20/20 = 1.000 | 20/20 = 1.000 | +0.000 | 1.0000 |
| H11 | 5/20 = 0.250 | 0/20 = 0.000 | −0.250 | **0.0471** |
| H12 | 20/20 = 1.000 | 20/20 = 1.000 | +0.000 | 1.0000 |
| H13 | 20/20 = 1.000 | 20/20 = 1.000 | +0.000 | 1.0000 |
| H14 | 20/20 = 1.000 | 20/20 = 1.000 | +0.000 | 1.0000 |

**H11 reaches p = 0.0471 with the plugin as the WORSE arm**, 5/20 → 0/20. It is
one of fourteen uncorrected tests, which is roughly what chance produces, and the
pre-registration already declared these descriptive. **It is not a finding that
the plugin harms detection**, and it is recorded here rather than dropped because
dropping the one result that embarrasses the thing being tested is how a null
becomes a positive.

Arm-level cost and latency: bare $0.0999/run, plugin $0.1122/run (+12.3%); 44.9 vs
48.1 s/run (+7.2%). B18 measured +57% to +112% cost overhead on five cases; that
does **not** reproduce here, for the reason in the next section.

## The mechanism the corpus was built to test was never exercised

Counted from every trace of all 840 runs, not inferred:

```
stage 2, plugin arm : Skill 48 of 280 runs (17.1%)   Read 0   references/*.md Reads 0
stage 2, bare arm   : Skill  0 of 280 runs           Read 0
stage 1 (bare)      : Skill  0 of 280 runs           Read 0
traces missing 0    is_error 0    runs with no tool call at all: 232 of 280 in the plugin arm
```

Two claims, kept apart because collapsing them would misreport one:

**As an intent-to-treat result the endpoint stands and is the finding.** Install
this plugin, run these prompts, and you get 235/280 against 239/280. That is what
a user gets, and it does not depend on the skill firing.

**As a test of the mechanism, it is void — and that is a fact about the corpus,
not about the plugin.** The pre-registration named `references/rulings.md` and
`references/ears.md` as the only route by which H07, H08, H11 and H12 could show
an effect, and said that an effect appearing without a Read of the reference it
depends on is not that mechanism. **Measured reference Reads: zero, in 840 runs.**
Those four cases cannot speak for or against it in either direction.

The cause is visible in the one captured Skill argument: `Intake classification
only, spec and constitution provided inline in the user message. Do not read or
write any repository files.` The prompts are self-contained by design —
`check-corpus.py` requires the fixture inlined verbatim — so a model that already
holds the spec has little reason to invoke a skill whose job is to fetch it. Any
future run that wants to test the mechanism has to stop handing the spec over in
the prompt, which is a different corpus.

## Deviations from the pre-registered plan

1. **The model was pinned to `claude-sonnet-5`.** The pre-registration is silent
   on the model, and its cost arithmetic implies this one. Measured: one bare H01
   run cost $0.280748 on the CLI default and $0.099232 on sonnet-5, 2.8×. At the
   default, the pre-registered 280 runs per arm did not fit the ceiling, and
   cutting runs would have changed the design rather than the price. Every B18
   figure the power table descends from was taken on this model.
2. **`plugin eval` is gated in CLI 2.1.265** and printed an early-access notice
   while doing nothing; the earlier B18 run used 2.1.251, before the gate. An
   enablement variable was set **inline on the invocation only** and written to no
   settings file. The variable's name is deliberately NOT recorded in this
   repository: it enables a feature outside its rollout, and a public repo is the
   wrong place to publish that. Anyone reproducing this needs the CLI to offer
   `plugin eval` normally.
3. **The bare arm had to be constructed.** `--ablation none` runs the *plugin*
   arm alone; there is no `without-only`. Stage 1 therefore used a copy of the 14
   cases with only the `plugins:` frontmatter line removed — verified otherwise
   byte-identical, bodies `diff`-clean and graders `diff -r`-clean — which leaves
   `suite.plugins: []` and `Skill called 0x`. **Read the stage-1 files with care:
   the tool labels that single arm `with` although it carries no plugin.** The
   `suite.plugins: []` field, not the arm label, is what proves it was bare.
4. **`--keep-temp` makes the tool-call record available**, which the
   pre-registration's *Measuring whether the skill fired* section says it is not.
   `trace.jsonl` carries `is_error`, the final text and every tool call;
   `stream-json` was unnecessary. The grader and the traces agree exactly —
   `(indicator_passed, trace_has_Skill)` is `(True,True)×48` and
   `(False,False)×232`.

## Where it disagrees with the pre-registration

- **Ten of fourteen bare rates missed their pre-registered range**, eight above
  and two below. H09 is the sharpest: predicted 30–70%, measured **0.00** — bare
  halted on the inferred-only conflict in all 20 runs. The document had already
  flagged H09's ground truth as partly the plugin's own doctrine and asked for it
  to be reported separately; stage 2 reads bare 0/20, plugin 2/20, p = 0.4872.
- **H11's direction is backwards.** Predicted plugin 45–85% on detection;
  measured 0%. Bare came in at 25%, itself below its own 30–70%.
- **The cost floor was wrong in the plugin arm's favour**: assumed $0.1378 for
  the plugin arm, measured $0.1122 — below the floor. Same cause as everything
  else here: a 17% skill-firing rate.
- **Bare is noisy at n = 20.** The identical H04 bare cell read 15/20 in stage 1
  and 17/20 in stage 2; H11 bare read 8/20 then 5/20. That is direct support for
  the pre-registration's refusal to pool stage 1 into stage 2, and the two bare
  figures here (0.8643 and 0.8536) are two separate measurements, never combined.

## Not proven

- **Whether the skill would be reached for at all if the prompt did not carry the
  spec inline.** Untested, and untestable in this corpus by construction.
- **The reference-file mechanism** for H07, H08, H11, H12. Zero Reads in 840 runs.
- **Anything about plugin 4.61.0 or later.** This measured **4.60.0**, recorded in
  all 14 stage-2 files. Mitigating, and checked with git rather than assumed:
  `SKILL.md`, `references/rulings.md` and `references/ears.md` are byte-identical
  between `5117f48` and the commit that followed the run, so the prose reaching
  the plugin arm did not change. `evals/` was untouched and the corpus fingerprint
  `00daa68d7a5fae5bf35efca8e122252401d146d77a163531e8b3a12707ee4cc4` is unchanged
  before and after.
- **Per-case conclusions.** 20 per arm, descriptive, and H11's p is one of 14
  uncorrected.
- **A second rater.** One blind judge on the LLM graders, as in B18. The
  pre-registration recommends a second rater on 20% of runs and does not cost it.
- **Judge-model variance.** `--judge-model` was never varied.
- **`06-ruling-requested` at 0.13 bare / 0.22 plugin** is the dominant scored
  failure in both arms — the model halts and cites both sides but does not request
  a `D`-numbered ruling. That is a real behavioural gap and it is outside this
  endpoint; it was not investigated here.

## Reproducing it

Run from a clone, never the live repo — this run used one at `5117f48`, and
`git status --porcelain evals/` was empty afterwards. Raw artefacts are not
committed: `evals/results/` is gitignored, the 28 result files are 8.7 MB, and
842 kept trace directories under `/private/tmp/e-*` total 88 MB. They are the
evidence for every tool-call and incomplete figure above and can be deleted once
this document is trusted.

The incomplete-detector was falsified before its zero was believed: synthetic
traces confirm it flags a missing VERDICT line and an `is_error: true`
independently, and passes a normal run. Verdict classes in stage 2: CONTRADICT
296, EXTEND 189, REFINE 75, DUPLICATE 0.
