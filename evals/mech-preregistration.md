# Mechanism corpus: pre-registration

Written 2026-09-27, before any case in `evals/mech-cases/` has been run by
anyone against any model, and before the harness has been seen to run a
scaffold at all. Every expectation below was fixed before a result existed. A
result that contradicts one is reported as a contradiction, and this file is not
edited to match it. Amendments go in the dated section at the end, never in
place.

Tree fingerprint at registration (see the end of this file for how to
recompute it): `93208dbba97b70d7b33081eff3c5ce4333b359cd4236ecd5247aee50fa6f4021`

Companion to `hard-preregistration.md` and `hard-results.md`, which are not
touched. The b18-hard fingerprint `00daa68d7a5fae5bf35efca8e122252401d146d77a163531e8b3a12707ee4cc4`
recomputes unchanged after this corpus was written.

## Why this corpus exists

Two instrument findings from the b18-hard run (2026-09-26, 840 runs), both
counted from the traces, not inferred:

1. **The mechanism was never exercised.** The `spec` skill fired in 48 of 280
   plugin-arm runs; `Read` fired in 0 of all 840. The b18-hard
   pre-registration named a Read of `references/rulings.md` or
   `references/ears.md` as the only route to an effect on H07, H08, H11 and H12,
   so that route is unmeasured. The cause is the corpus: every prompt carried
   the spec and constitution verbatim, and `check-hard-corpus.py` enforced it.
   A model already holding the spec has no reason to look for it. The one
   captured Skill argument said so in as many words.
2. **Saturation.** The shared falsifier "not hard for a bare model" (bare 19 or
   more of 20) fired on 11 of 14 cases in stage 1.

The product's claim is not "given the spec, classify well". It is: **when an
intent arrives, the model finds the living spec, classifies the intent against
it, and halts on a contradiction.** b18-hard tested the second half with the
first half done for the model. This corpus puts the spec where a repository
using the plugin keeps it - `.claude/productizer/spec.md` and
`.claude/productizer/constitution.md` in the run's working directory - and
leaves finding it to the model.

## What changed from b18-hard, and what did not

| | b18-hard (H) | b18-mech (M) |
|---|---|---|
| Intents | 14 | the same 14, byte-identical (checked) |
| Ground truth, twin pairing, outcome graders 01-06 and 99 | - | the same; 01 differs only in its weight paragraph (checked) |
| Spec and constitution | inlined in the prompt | on disk, written by `scaffold.sh` from `evals/mech-fixtures/`, byte-identical to the H fixtures (sha256 recorded in the checker) |
| Prompt wording | "Run intake…", "reproduced in full in this message", "against the spec and the constitution above" | see *What the prompt says*; the path, the plugin and the words *spec* and *constitution* are absent (checked) |
| Tools | Read, Glob, Grep, Skill | the same |
| `max_turns` / `timeout_seconds` | 10 / 300 | 20 / 600 - finding a file costs turns, and a run that exhausts its turns is incomplete, not a fail |
| Mechanism graders | `99-skill-fired` only | plus `00`, `90`, `91`, `92`, `93` (below) |
| Tag | `b18-hard` | `b18-mech` |
| Per case | `prompt.md`, `graders/` | plus `case.yaml` and `scaffold.sh` - see *Unverified before stage 1*, item 2 |

## Unverified before stage 1

Nothing in this section has been executed. `claude plugin eval` (CLI 2.1.265)
prints an early-access notice and does nothing on this machine; it was not run
and no attempt was made to enable it. The only evidence is (a) one measured fact
from a kept b18-hard trace - **the model's working directory was a directory
named `cwd` inside `home` inside the run's own fresh temporary directory** - and
(b) a static reading of the
installed 2.1.265 CLI bundle, which is not execution and can be wrong in any
detail a minified reading can get wrong.

### 1. What `scaffold_script` is, and where it runs

Two candidate semantics. Neither is established.

- **A - a path.** The value names a file, resolved against the case directory,
  and the harness runs it with bash in the run's working directory. The static
  reading points here: the case schema's `context.scaffold_script` is resolved
  by the same routine that rejects a case-authored path which "escapes the case
  directory" or "does not exist", and the resolved file is handed to `bash` as
  its only argument, with the working directory set to the run's working
  directory, stdout discarded, stderr kept for the failure message, and a
  120-second kill.
- **B - inline bash.** The value is itself the script, run as `bash -c
  "<value>"`, in some directory.

The corpus is written for A: `case.yaml` sets `scaffold_script: scaffold.sh`,
and `scaffold.sh` sits in the case directory. It is also written so that one
smoke run tells A from B, and tells where it ran, because every way the script
can land in the wrong place has its own exit code. Each outcome below was
produced locally by `check-mech-corpus.py --selftest`, which runs the canonical
script with bash in throwaway directories (codes 0, 3, 4, 5 and 127 all
observed). That shows what the script does; it does not show what the harness
does.

| Smoke-run outcome | Means | Then |
|---|---|---|
| a load error naming `case.yaml`, `scaffold_script`, or an unknown frontmatter key | the harness does not accept this case layout | amend before stage 1 |
| `scaffold failed (exit 127)` | the value was run as a command, not a path: **B**, or A resolved against a directory without the file | amend: B needs a different `case.yaml`, which this checker would then have to allow |
| `scaffold failed (exit 3)` | ran as a path, but not from the case directory (a copy elsewhere): the relative fixture path does not resolve | amend: fixtures must travel with the script |
| `scaffold failed (exit 4)` | ran with the **case directory** as its working directory | amend; nothing was written into the corpus, which the script guarantees |
| `scaffold failed (exit 5)` | the working directory already held `.claude/productizer/` - e.g. the directory `plugin eval` was invoked from | **stop**. This is the case the refusal exists for: from the repository root it would otherwise have overwritten this repository's real spec |
| exit 0, but `00-scaffold-present` fails | the scaffold wrote somewhere other than the model's working directory (A, wrong directory) | amend |
| no `scaffold:` line, `00` fails | the scaffold never ran - `--scaffold` omitted (it is off by default) | re-run with `--scaffold` |
| exit 0, `00` passes **in both arms**, and the kept run directory holds `home/cwd/.claude/productizer/spec.md` and `constitution.md` whose sha256 match `evals/mech-fixtures/` | **A holds**, in the model's working directory | proceed to stage 1 |

### 2. Why each case has a `case.yaml`

The static reading says `prompt.md` frontmatter accepts only `schema_version`,
`name`, `description`, `tags`, `plugins`, `runs`, `expected_outcome`, `model`,
`max_turns`, `timeout_seconds`, `allowed_tools`, `artifact_publish`,
`growthbook_overrides`, `append_system_prompt` and `env`, and refuses any other
key. By the same reading, `scaffold_script` is not among them and belongs under
`context:` in the `case.yaml` schema, and a case directory holding both files is
read as one case, `case.yaml` first and `prompt.md` over it. So each case carries a three-line
`case.yaml` (`schema_version: "1.1"`, `context.scaffold_script: scaffold.sh`) and
nothing else, and `check-mech-corpus.py` holds that text byte for byte - a
`case.yaml` can also carry `execution.prompt`, `history_file`, `add_dirs` and
`env`, any of which could put the spec back in front of the model. **This is an
addition to the case layout the brief for this corpus described (`prompt.md` +
`graders/`), made because that layout has nowhere the static reading says a
scaffold can be declared.** If the smoke run loads the cases without error, the
reading was right on this point; if it refuses them, item 1's first row applies.

### 3. The other things the smoke run must show

- **`00-scaffold-present` reads the run's working directory.** It is a regex
  grader whose target is `{source: file, path: .claude/productizer/spec.md}`;
  the static reading resolves that against the run's working directory. A pass
  in both arms with the scaffold at exit 0 confirms it.
- **`input_match` sees Read's arguments as JSON.** Measured for Skill in
  b18-hard (grader and traces agreed 48/48 and 232/232); inferred, not
  measured, for Read's `file_path`. Check the smoke run's `90` result against
  its trace by hand.
- **Both ablation arms run the scaffold.** `00` must pass in the bare arm too.
- **Whether Glob and Grep list a dot-directory.** If they do not, a bare model
  that searches with them can never find `.claude/productizer/` without guessing
  the path, and the bare discovery rate below is an artefact of the tool, not
  of the model. Read from the stage-1 traces: for every bare run, which Glob and
  Grep calls it made and whether any returned a path under `.claude/`.
- **`.claude/` in the working directory.** Claude Code treats a working
  directory's `.claude/` as project configuration. `productizer/` is not a
  location it loads from, but that is not verified, nor whether a Read there
  prompts for permission inside the harness.

## Design decisions

### 1. What the prompt says

```
A new intent has arrived for the `booking service`:

<the H intent, verbatim>

Classify this intent against what this product has already agreed, as exactly
one of **extend**, **refine**, **duplicate** or **contradict**. Cite every
requirement id (`R…`) and principle id (`P…`) that bears on the decision, state
what happens next, and say plainly what has and has not been merged.

End your reply with exactly this line, and nothing after it:

VERDICT: <EXTEND|REFINE|DUPLICATE|CONTRADICT>
```

**Decision: the primary condition names no path, no file, no plugin, and
neither the word *spec* nor *constitution*, but it does say that agreements
exist.** Reasons:

- Naming `.claude/productizer/spec.md` hands the bare arm the mechanism under
  test. The comparison would again be "classify, given the spec", which is
  b18-hard with one extra tool call.
- Naming nothing at all - dropping "what this product has already agreed" -
  makes the four classes meaningless (refine, duplicate or contradict *what?*),
  and a bare model that concludes there is nothing to compare against is
  answering the question it was asked. That test would be stacked in the
  plugin's favour: the plugin arm is told by its own skill description that a
  living spec exists at `.claude/productizer/spec.md`; the bare arm would be told
  nothing is there to find.
- "What this product has already agreed" is what a user of a spec-driven
  repository knows and would say. It gives both arms a reason to look and
  neither a place to look. The output-format line keeps `R…` and `P…` because
  graders 03 need the ids; it tells a bare model that the agreements are
  numbered, which is fair - a user would know that too.
- "Run intake" is gone: *intake* is the skill's own name for the stage, and
  priming the skill is the plugin's job, not the prompt's. "Merged" stays, from
  the H wording, because grader 02 judges whether the reply says nothing was
  merged.

**The neutral hint is a pre-registered secondary condition, not the primary,
and it is not built here.** Its text is fixed now: the prompt gains, after the
first line, exactly `This repository keeps its agreed requirements under
`.claude/productizer/`.` - nothing else changes, tag `b18-mech-hint`. It is
built and run **only if** stage 2 shows a plugin advantage on the primary
endpoint at p < 0.05 **and** the stage-2 bare arm Read the spec (grader `90`) in
fewer than half its runs. Then the question it answers is the one that matters:
is the plugin's advantage the doctrine, or only knowing where the file is? If
the hint closes the gap, it is the path. Built otherwise, it would spend 560
runs on a question the primary had not raised.

### 2. Tool grant

**Decision: unchanged, `[Read, Glob, Grep, Skill]`.** Holding it fixed makes the
spec's location the only material difference from b18-hard, so an M-versus-H
difference can be attributed.

What a model that cannot write **can** demonstrate: that it looked (Glob, Grep,
Read, all in the tool-call record), what it read (the `file_path` of each
Read), whether it loaded the skill, and what it says it would do. What it
**cannot** demonstrate: that it would not have merged. Grader 02 ("nothing was
merged") is a judgement of words, and a model without Write cannot merge
whatever it says, so no run here shows the stop the product promises happening
on disk. A later corpus could grant Write and grade the file itself - a
`{source: file}` regex that fails if `spec.md` gains `R43` - but that needs an
operator `--allow-tools` grant and changes a second variable at once. Bash stays
out for the same reason as in b18-hard, and one more: with Bash the plugin arm
could run `contradiction-check.py`, which is a different claim from the one
under test.

### 3. Mechanism graders

| Grader | What it measures | Arm | Scored in the harness | Role here |
|---|---|---|---|---|
| `00-scaffold-present` | the run's working directory holds the scaffolded spec | both | yes, weight 1 | **validity**: a run failing it is excluded and counted, never scored |
| `90-spec-read` | a Read whose `file_path` ends `.claude/productizer/spec.md` | both | yes, weight 1 | **pre-registered secondary endpoint**: the discovery rate |
| `91-constitution-read` | the same for `constitution.md` | both | yes, weight 1 | secondary, descriptive |
| `92-rulings-read` | a Read of the plugin's `references/rulings.md` | with-only | no | indicator |
| `93-ears-read` | a Read of the plugin's `references/ears.md` | with-only | no | indicator |
| `99-skill-fired` | a Skill call naming `spec` | with-only (default for Skill) | no | indicator, unchanged from H |

Why this split:

- **`90` and `91` must be `arm: both`.** The discovery comparison *is* the two
  arms' rates. A with-only grader is dropped from the bare arm entirely, which
  would leave the plugin's number with nothing to compare to. The harness offers
  no "measured in both arms but unscored"; `arm: both` is scored. So they carry
  weight 1 each, and the harness's per-case score and its Δ are **not** an
  endpoint of this study - the primary endpoint is read off grader 01 alone, as
  in b18-hard. The 01 grader text says so: 3 of the 28 must-halt points and 3 of
  the 17 must-not-halt points check that the run had a spec and read it, not how
  it classified.
- **`92` and `93` are with-only** because the bare arm has no plugin and so no
  such file; its zero would be structural, not measured.
- **`00` is `arm: both`** because the bare arm needs the same proof that it had
  a spec to find. Without it, a run whose scaffold silently did not happen reads
  exactly like a run that never looked.
- Reading the plugin's references is the route b18-hard pre-registered for
  M07/M08 (`rulings.md`) and M01/M02/M06/M11/M12 (`ears.md`). **The rule carries
  over: a plugin effect on those cases that appears in runs which never Read the
  relevant reference is not that mechanism.** `92` and `93` are on every case, so
  their base rate on the cases that do not need them is visible too.
- **The skill description is a second route, and it is separated.** The plugin
  arm's model sees the `spec` skill's description, which names
  `.claude/productizer/spec.md`, whether or not the skill fires. A plugin-arm
  Read of the spec with `99` red came by the description; with `99` green, by the
  skill. Both are the product; they are reported apart.

### 4. Predicted bare rates, and what falsifies them

**The one unknown that drives everything is d, the rate at which a bare run
Reads the spec.** It has never been measured. The prompt gives a reason to look
and no place; whether Glob and Grep even surface a dot-directory is unverified
(above). The honest prior is wide: **d_bare between 0.2 and 0.9.** For the plugin
arm, whose skill description names the path, **d_plugin between 0.7 and 1.0.**

A run that does not find the spec cannot cite R14 or D3; the most likely reply
is EXTEND, which **fails every must-halt case and passes every twin.** A bare
arm that never looks would score about 50% pooled - 0 on seven cases, 100 on
seven. So predictions are built from d and the b18-hard stage-1 bare rate r for
the same case, which is the best measurement there is of classification once
the spec is in hand: must-halt ≈ d·r, twin ≈ (1 − d) + d·r.

| Case | Halt? | H stage-1 bare | **Predicted bare** | Predicted plugin | Expected direction | Falsified if |
|---|---|---|---|---|---|---|
| M01 far waitlist hold | yes | 1.00 | **20-90%** | 70-100% | plugin better (discovery) | bare ≥ 19/20: not hard even off the prompt |
| M02 twin | no | 1.00 | **90-100%** | 90-100% | none | either arm false-halts on more than 3 of 20 |
| M03 principle body | yes | 1.00 | **10-90%** | 65-100% | plugin better | bare ≥ 19/20. The conflict is only in the constitution's body, so this case also needs `91`: a halt in a run with `91` red is reported as a guess, not a detection |
| M04 twin | no | 0.75 | **75-100%** | 70-100% | plugin possibly worse | plugin false-halts less than bare at p < 0.05 |
| M05 superseded id cited | yes | 1.00 | **20-90%** | 70-100% | plugin better | bare ≥ 19/20 |
| M06 twin | no | 0.95 | **85-100%** | 80-100% | none | either arm false-halts on more than 3 of 20 |
| M07 withdrawn + D3 | yes | 1.00 | **20-90%** | 70-100% | plugin better | bare ≥ 19/20; or a plugin gain only in runs with `92` red |
| M08 twin | no | 1.00 | **90-100%** | 85-100% | none | either arm false-halts on more than 3 of 20 |
| M09 inferred-only | no | 0.00 | **10-80%** | 0-40% | **plugin worse** | plugin beats bare at p < 0.05 |
| M10 inferred masks R12 (`01 AND 03`) | yes | 1.00 | **20-90%** | 65-100% | plugin better | bare ≥ 19/20 |
| M11 roughly-bound loosened | yes | 0.40 | **0-40%** | 0-30% | none, or plugin worse as in H | plugin better only in runs with `93` red |
| M12 twin | no | 1.00 | **90-100%** | 85-100% | none | either arm false-halts on more than 3 of 20 |
| M13 joint R24→R22 (`01 AND 03`) | yes | 1.00 | **20-90%** | 70-100% | plugin better | bare ≥ 19/20 |
| M14 twin | no | 1.00 | **90-100%** | 90-100% | none | either arm false-halts on more than 3 of 20 |

**The twins become easy for a bare model that never looks, and that is said
plainly rather than hidden.** A non-looker passes all seven by staying quiet.
M09 is the sharpest: bare halted on the inferred-only conflict in 20 of 20 H runs
once it had the spec, so here *finding* the spec is what makes a run fail, and
the plugin arm, which finds it more, is predicted worse. What this does to the
endpoint: the pooled halt decision now scores discovery **and** its cost -
finding the spec is rewarded on the must-halt half and exposes the run to
over-halting on the twin half (M04, M06, M09). That is the right accounting for
the product's claim, which is about the whole behaviour, but it means the twin
half no longer controls halt bias for runs that did not look. Two secondary
analyses restore that control, both descriptive because conditioning on a Read
is conditioning on something that happened after assignment: the halt decision
among runs with `90` green, per arm; and the false-halt rate among twin runs with
`90` green, per arm.

**Pooled.** From the ranges above: bare **55-85%**, plugin **70-85%**, expected
direction plugin better, driven by must-halt discovery and partly paid back on
the twins. **Falsified**, for the premise that moving the spec off the prompt
makes the task harder, if stage-1 pooled bare is **0.85 or higher** - b18-hard
measured 0.8643 with the spec inlined. Falsified the other way, for the premise
that a bare model will look at all, if stage-1 bare `90` is **0 of 280**; that
is not a stop (below), but then the primary is a test of discovery alone and is
reported as such.

**The saturation stop rule, restated.** The shared per-case falsifier stays: bare
≥ 19 of 20 on a must-halt case in stage 1 means that case is not hard for a bare
model even with the spec off the prompt. On the twins, ≥ 19 of 20 is *predicted*
for M02, M08, M12 and M14 and is not a falsifier: twins are controls, not hard
cases.

### 5. Primary endpoint, n, power, cost

**Kept from b18-hard, unchanged:** halt decision correct (must-halt halted,
must-not-halt did not; M10 and M13 need grader 03 as well), pooled over all 14
cases, Fisher exact two-tailed, alpha 0.05, bare against plugin, **20 runs per
case per arm, 280 per arm.** Every case contributes 20 runs to each arm, so the
case mix is identical in both and the unstratified test is conservative. Keeping
n makes the M and H figures directly comparable; the prediction spread above is
too wide to power against with any confidence, and a changed n would be tuned to
a guess.

**Secondary, pre-registered and tested:** the discovery rate, grader `90`,
pooled, bare against plugin, Fisher exact two-tailed, alpha 0.05. **Secondary,
descriptive:** recall over the 7 must-halt cases; false-halt rate over the 7
twins; each pair; `91`, `92`, `93`, `99` per arm and per case; the conditional
analyses in section 4; each LLM grader; cost and duration per arm; the bare
arm's Glob and Grep calls and whether any returned a `.claude/` path.

**Power**, from `evals/hard-power.py` (exact Fisher, its self-check passing
first: `Fisher check: 3/10 vs 5/10 -> p = 0.6499 (published 0.6499)`), power at
the pre-registered 280 per arm, and the n that reaches 80%:

| Bare | Plugin | Power at 280/arm | n/arm for 80% |
|---|---|---|---|
| 0.60 | 0.75 | 0.962 | 164 |
| 0.65 | 0.80 | 0.975 | 150 |
| 0.70 | 0.85 | 0.988 | 131 |
| 0.75 | 0.85 | 0.819 | 267 |
| 0.70 | 0.80 | **0.753** | 311 |

A 15-point effect is well covered. **A 10-point effect near the middle of the
predicted ranges is not**: 0.70 against 0.80 has 0.753 power at 280, and 80%
needs 311 per arm. That is stated now so a null at a 10-point gap is not later
read as an exclusion. b18-hard could exclude 62.5→75; this corpus can exclude
15-point effects and cannot exclude 10-point ones.

**Exclusions.**

- **Invalid:** the harness reports `scaffold failed`, or `00-scaffold-present`
  fails. Counted per arm, never scored. The scaffold is deterministic, so **one
  invalid run stops the stage**: it is a harness fault, and every other run in
  the stage is suspect until it is explained.
- **Incomplete:** `is_error: true`, a timeout, or the turn limit reached, as the
  trace records it. Counted per arm, never scored; if one arm's count exceeds the
  other's by more than 5, the comparison is reported as confounded.
- **Changed from b18-hard: a completed reply with no VERDICT line is NOT
  excluded.** It is scored as the graders score it (must-halt fails, twin
  passes) and counted separately. In b18-hard a missing verdict could only be a
  formatting lapse; here "I could not find what this product agreed" is a
  plausible, treatment-dependent outcome, and excluding it would censor exactly
  the failure the corpus exists to see. A sensitivity analysis with those runs
  excluded is reported beside the primary.

**Cost.** Measured b18-hard figures on `claude-sonnet-5`, from `hard-results.md`:
**$0.0999 per bare run, $0.1122 per plugin run.** (`hard-results.md` does not
say whether judge calls are inside those figures.)

| Stage | Runs | At b18-hard's measured rates |
|---|---|---|
| 0, smoke | 1 bare + 1 plugin | $0.21 |
| 1, bare only | 280 bare | $27.97 |
| 2, A/B | 280 bare + 280 plugin | $27.97 + $31.42 = $59.39 |
| Total | 842 | **$87.57** |

**That table is not an estimate of this corpus, and the plugin arm will cost
more than it says by an amount that cannot be measured yet.** b18-hard's plugin
arm cost only 12% more than bare because the skill fired in 17% of runs and
nothing was ever Read. A plugin run here that does what the product intends
reads the spec and constitution (about 13 KB), may load `SKILL.md` (30,142
bytes) and may Read `references/rulings.md` (12,530) and `references/ears.md`
(20,031) - up to about 76 KB of tool results, roughly 19,500 tokens at the
calibrated 3.89 bytes per token, carried across more turns than b18-hard's
mostly single-turn runs. The bare arm moves both ways: its prompt is about 13 KB
shorter, a run that Reads the spec gets it back, and a run that never looks is
cheaper than any b18-hard run. **The smoke run's two costs are the first
measurement. Before stage 1, stages 1 and 2 are re-costed from them and the
re-costing is recorded as a dated amendment**; if it exceeds what the maintainer
will spend, stage 2 is cut to n = 10 per case per arm only by amendment made
before stage 2 starts, never after, and its power (0.439 for 70→80, 0.828 for
70→85 at 140 per arm) is quoted with it.

### 6. Discovery - running exactly these 14

`claude plugin eval .` discovers every case under `evals/`. With this corpus
there are **54**: 26 in `evals/cases/`, 14 in `evals/hard-cases/`, 14 here.
`check-mech-corpus.py` counts them and prints `cases carrying b18-mech : 14 of 54`.

**The filter is `--tag b18-mech`**, which every M case carries and nothing else
under `evals/` does. The checker proves that statically: it walks all of
`evals/`, reads the tags of every directory holding a `prompt.md` or a
`case.yaml` (flow or block list), and fails if any case outside `mech-cases/`
carries `b18-mech`, if any M case lacks it, or if any M case carries `b18-hard`
(which would put it back into `--tag b18-hard`). The static reading says the
harness matches a tag by exact membership in the case's tag list, not by
substring, so `b18-mech` cannot select `b18-mech-hint` or the reverse; that is
**not verified by execution**. The harness prints a line of the form
`Ablation: 2 arms × N cases` before the first run: **if N is not 14 (1 for the
smoke run's `--case`), the run is interrupted before it spends.**

## Run plan

Nothing below has been executed. Spending is the maintainer's call. Every stage
runs from a throwaway clone, never the live repository - b18-hard's own rule,
with one more reason here: the scaffold writes into a working directory, and
exit 5 exists because the repository root is the one place it must never write.
Model pinned to `claude-sonnet-5`, the model every b18-hard figure is from (the
b18-hard pre-registration was silent on it; this one is not). The plugin version
and the sha256 of `SKILL.md`, `references/rulings.md` and `references/ears.md`
are recorded with every stage; 4.61.2 at registration.

**Stage 0: smoke.** From a clone:

```
claude plugin eval . --tag b18-mech --case 'M01-*' --runs 1 \
  --scaffold --keep-temp --no-publish --model claude-sonnet-5
```

Read against the table in *Unverified before stage 1*, item 1, and check each
point in item 3. Record the outcome as an amendment before stage 1. Any outcome
other than the last row means the corpus is amended and this stage is repeated.

**Stage 1: difficulty screen, bare arm only.** All 14 cases, 20 runs each, 280
runs. The bare arm is built as in b18-hard (`--ablation none` has no bare-only
mode): in the clone, the `plugins:` line is deleted from the 14 `prompt.md`
files and nothing else, which `check-mech-corpus.py` will then report as a
frontmatter-keys failure on all 14 - that failure is the record of the edit and
is quoted in the results. `suite.plugins: []`, not the arm label, proves the arm
was bare. Stop rules, checked in order:

1. **Validity.** Any invalid run: stop, explain, re-run stage 1 whole.
2. **Saturation, unchanged from b18-hard.** Pooled bare ≥ 95%: stop.
3. **The relocation did nothing.** Bare `90` ≥ 95% (266 of 280) **and** pooled
   bare ≥ 0.85: stop. Bare finds the spec essentially always and classifies as
   well as it did with the spec inlined; stage 2 would repeat b18-hard's null at a
   higher price. That is itself the finding: moving the spec off the prompt does
   not make a bare model miss it.

Stage-1 runs are never pooled into stage 2.

**Stage 2: A/B, all 14 cases whatever stage 1 found per case**, 20 per case per
arm, `--ablation with-without`, `--scaffold`, `--keep-temp` (the traces are the
evidence for every tool-call figure). Primary and secondary endpoints as in
section 5. Stage-2 bare and stage-1 bare are two measurements, never combined.

**Then, only on its trigger:** the hint condition (section 1).

## Considered and rejected

| Candidate | Why rejected, or what was done instead |
|---|---|
| Keep the spec inline and add graders for Reads | b18-hard, measured: 0 Reads in 840 runs. The graders would read zero. |
| Name the path in the primary prompt | Hands the bare arm the mechanism; kept as the fixed-text secondary hint condition instead. |
| Name nothing about prior agreements | The four classes lose their referent, and only the plugin arm would know a spec exists. |
| Embed the fixtures in `scaffold.sh` as heredocs | Two copies of 13 KB that drift, and a 14 KB script nobody reads line by line. The script copies from `mech-fixtures/`, whose bytes the checker pins. |
| One shared scaffold, symlinked into each case | The static reading rejects a scaffold path that leaves the case directory; 14 byte-identical copies cost nothing when the checker pins them. |
| Grant Write and grade the spec file on disk | The better test of the stop, and a second variable; next corpus, not this one. |
| Grant Bash | Runs the solver in the plugin arm: a different claim. |
| Drop the twins that become easy | Selects the corpus on a predicted result, and loses the only guard against a plugin that halts on everything. |
| Primary = recall on the must-halt half only | The same loss. Recall is secondary. |
| A `description:` or `append_system_prompt` for context | Both reach the model; the checker forbids every frontmatter key but the seven used. |

## Isolation

- `evals/hard-cases/`, `evals/hard-fixtures/`, `evals/cases/`, both old
  checkers and both old documents are untouched. After this corpus was written:
  `check-hard-corpus.py` exit 0; `check-corpus.py` still reports 26 cases; the
  b18-hard fingerprint recomputes to `00daa68d…4cc4`.
- `evals/solver-probe.py` iterates a hard-coded `PAIRS` list and reads nothing
  here.
- `check-mech-corpus.py` **reads** `evals/hard-cases/` for the mirror check and
  exits 2 if it is missing. It never writes there. The scaffold never reads
  `evals/hard-fixtures/`, and the checker fails if it would.
- `scaffold.sh` passes `shellcheck` at every severity and this repository's
  stderr-suppression check.

## Recomputing the fingerprint

```
cd evals && find mech-cases mech-fixtures -type f | LC_ALL=C sort \
  | xargs shasum -a 256 | shasum -a 256
```

`python3 evals/check-mech-corpus.py` prints the same value computed in Python.

## Amendments

### A1 — 2026-09-27: stage 0 ran, semantics A holds, and one open design question

Recorded before stage 1, as *Run plan* requires. Nothing above this heading was
edited; this section is the only change to the document since registration.

**Registration version.** This document says `4.61.2 at registration`. It was
written against 4.61.2 and committed in 4.62.0 (`7c083eb`); the plugin the smoke
run loaded was **4.62.0**. The prose that reaches the plugin arm at that commit:
`SKILL.md` `a9f60820…c85d`, `references/rulings.md` `32165fa0…2d29`,
`references/ears.md` `fc18d486…a1b`. Corpus fingerprint `93208dbb…4021`,
unchanged.

**The run.** From a throwaway clone at `7c083eb`, exactly the stage-0 command
above, plus output paths outside the repository and `--max-cost-usd 1.00` as a
hard bound. The enablement variable `plugin eval` needs in CLI 2.1.265 was set
inline on that one invocation, with the maintainer's explicit approval for this
corpus, and written to no settings file. Harness exit 1, which is its "a case
scored below 1.0" code, as in every b18-hard run; no load error and no
`scaffold failed` line. **$0.3721 in total**: plugin arm $0.2538 in 9 turns, bare
arm $0.1183 in 4.

**Unverified before stage 1, item 1 — settled: the last row of the table.**
`00-scaffold-present` passed in **both** arms, and both kept run directories hold
`home/cwd/.claude/productizer/spec.md` and `constitution.md` whose sha256 equal
`evals/mech-fixtures/` exactly (`e2c787cf…6b86`, `17c74802…f60b`). The value is a
path, run in the model's working directory, and it runs in the bare arm too.

**Item 2 — settled.** The harness loaded a case directory holding both
`case.yaml` and `prompt.md` without complaint.

**Item 3 — settled, each checked against the trace by hand.**

- `input_match` sees Read's arguments: `90-spec-read` passed in both arms, and
  the traces show one Read of the spec each — by a relative path in the plugin arm
  (`.claude/productizer/spec.md`) and by an absolute one in the bare arm. The
  grader matched both forms.
- Glob lists a dot-directory. The bare arm's FIRST call was `Glob **/*`, and its
  next was a Read of the spec by absolute path, so the glob returned it. Bare
  discovery is not a tool artefact.
- No permission prompt interrupted a Read under `.claude/` in either arm.

Tool calls, verbatim order — plugin: `Skill`, `Glob .claude/productizer/**`,
`Glob **/spec.md`, `Read spec.md`, `Read constitution.md`,
`Glob .claude/productizer/**/*`, `Grep waitlist`. Bare: `Glob **/*`,
`Read spec.md`, `Read constitution.md`. `92-rulings-read` and `93-ears-read`: 0 in
the plugin arm. Both arms answered CONTRADICT; both scored 0.964.

**Re-costing, as *Run plan* requires.** One run per arm on one case is not an
estimate of a mean, and is recorded only as the first figure there is: bare
$0.1183, plugin $0.2538 — the plugin arm now costs **2.1×** the bare arm, where
b18-hard's cost 1.12×, because the mechanism fires. At those two figures stage 1
(280 bare runs) is about $33 and stage 2 (280 per arm) about $104, so stages 1
and 2 together run to about **$137**, above b18-hard's $88 and above the $120
ceiling b18-hard ran under. A spend for stage 1 has to be approved against this
figure, not the $87.57 in section 5.

**Open before stage 1 — not decided here, because it is a design change and
belongs to the maintainer.** The scaffold writes the spec and the constitution
into an otherwise EMPTY working directory, so the bare arm's `Glob **/*` returned
nothing but the two files the corpus is testing whether it will find. That is
not the situation the product claims to help with, where the spec is two files
among hundreds. Stop rule 3 ("the relocation did nothing") is therefore likely to
fire for a reason that is a property of the empty workspace rather than of the
model, and a stage 1 that stops on it would have measured the scaffold, not the
plugin. One run cannot show the rate; it shows the route, and the route is
exactly the one an empty directory makes free. The candidate amendment is to
scaffold a realistic repository around the spec — the same tree in every case,
and a fixture of its own — which would change `scaffold.sh`, the fixtures, and
the fingerprint, and so has to be registered as a new amendment with its own
fingerprint before stage 1 runs.
