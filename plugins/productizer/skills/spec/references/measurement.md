# Measurement — does the process actually help?

The honest answer today is that nobody in this field can say. The most candid
statement of the gap comes from a team that has shipped this kind of process
commercially: *"we do not have a clean way to measure the overall alignment
quality of a project at a given moment, or to compare it across projects."*
This plugin was in the same position, and every competitor studied still is.

That is not an argument for measuring nothing. It is an argument against the two
things usually reached for instead — an LLM judging its own workflow's output,
and a golden dataset that becomes a second spec nobody maintains. Both drift,
and both drift in the flattering direction.

What is here instead: three instruments that are deterministic, cheap, and
narrow. Each measures one thing precisely and is explicit about the much larger
thing it does not measure.

| Instrument | Script | Answers | Unit |
|---|---|---|---|
| Retrieval budget | `scripts/retrieval-budget.sh` | is the spec still cheap to retrieve from? | characters (a proxy, calibrated 2026-09-05) |
| A/B harness | `scripts/ab-harness.sh` | does the process cost more, and how much more? | ms, USD |
| Stage snapshot | `scripts/stage-snapshot.sh` | how much did a human have to rewrite? | lines (a proxy) |

## The rule that governs all three

**A value that could not be measured is never rendered as zero.**

Zero is a measurement. It means free, or instant, or *the human accepted the
draft as written*. None of those is what "no baseline", "the arm never
completed", "the stage produced nothing" or "the model was unavailable" means,
and rendering them as `0` turns four different situations into one reassuring
number that a dashboard will average.

So every instrument prints a distinct word — `no-baseline`, `unmeasured`,
`unavailable`, `no-complete-runs`, `stage-produced-nothing`, `artifact-missing`,
`unmeasurable`, `target-missing` — and exits with a distinct code. This suite is
the most tempting place in the plugin to invent a comforting figure. It does not.

## 1 · Retrieval budget — the regression eval

Fixed prompts, each naming the one requirement it must reach. Measure how much
of `spec.md` has to be read to reach it, record a baseline, and fail when a
later run leaves the band.

No judge. No golden answers. Just a number that either moved or did not — which
is the whole point: a verifiable reward, not a graded one.

**Mechanism.** Retrieval is modelled as the two steps an agent actually takes.
Search the spec for the prompt's terms; a line is a *candidate* when it contains
at least one term, case-insensitively, as a substring. Then read the candidates
in file order until the target's definition line — the one carrying `**R<n>**` —
is reached. The budget is the total size of the candidate lines read, up to and
including the target line.

That figure rises for the three reasons spec retrieval actually degrades: the
target moved down the file, the terms started matching more of the spec, or the
spec grew around it.

**The unit is a proxy, and it is named as one.** The unit is characters (bytes,
`LC_ALL=C`). It is **not** a token count. A true token count needs the tokeniser
of the model doing the retrieval, which means a model call — neither
deterministic nor free — and a proxy printed under the word "tokens" is a
fabricated measurement. Every place the figure appears, in the script's output
and in the recorded baseline, says `a PROXY for a token budget, not a token
count`.

**Outcomes.**

| Outcome | Means | Exit |
|---|---|---|
| `in-band` | within baseline ±band (default 20%) | 0 |
| `out-of-band-high` | retrieval got more expensive | 4 |
| `out-of-band-low` | retrieval got cheaper by more than the band — also a change, also worth a look | 4 |
| `full-scan` | the target exists but no term reaches it, so the agent must read the whole file. Fails regardless of the band: the search step did not work | 4 |
| `target-missing` | the requirement id has no definition line. Budget prints `unmeasured`, never `0` | 4 |
| `no-baseline` | measured, but nothing to compare against. **Not a pass** | 5 |
| no prompt set | nothing was measured at all | 6 |

`--record` refuses to write a baseline while any prompt is `full-scan` or
`target-missing`. A baseline taken from a spec that already fails the eval makes
the failure the norm.

**Files.** `.claude/productizer/retrieval-prompts.tsv` (`id`, target `R`-id,
terms) and `.claude/productizer/retrieval-baseline.tsv` (`id`, chars, mix). Both
are committed; the baseline moves in a reviewed commit, like any other threshold.
The third field is optional and a two-field baseline still reads correctly.

**Both files now exist here, and the instrument has run.** First measured
**2026-09-06** against `spec.md` at 29751 bytes, sha256 `7204e9cb…`: ten prompts,
all ten reaching their target, none falling back to `full-scan` and none
`target-missing`. The per-prompt budget spans **124 to 1532 characters**, median
786.5, total 7495 — so the most expensive question in the set reads 5.2% of the
file and the cheapest 0.4%. Recorded `mix` is 0% on seven prompts and 17%, 21%
and 27% on the three whose candidate lines pass through this file's tables and
backticked prose; mix is recorded and never banded, so not one of those figures
is a pass or a fail. The 2026-09-05 calibration puts candidate slices of this
spec at 3.79–4.31 bytes per token, which makes these budgets of the order of 30
to 400 tokens — an order derived from a measured range, not itself a
measurement, which is why the check prints no token count and neither does this
sentence.

The set spans all five EARS patterns, and one prompt targets a **superseded**
requirement — R14, superseded by R33 — at 994 characters. Deleting R14's
original sentence, the thing R3 forbids, turns that row into `target-missing`
with the budget printed as `unmeasured` and exit 4. So a deletion R3 already
forbids now has a second, independent instrument that notices it.

**The unflattering part, reported rather than tuned away.** Three budgets are
small enough that a ±20% band is only tens of characters wide: `waived-not-pass`
124 (band 99..148), `override-record` 153 (122..183), `view-read-only` 212
(169..254). One new spec line carrying one of those prompts' terms, anywhere
above the target, moves the row out of band by itself — which is exactly what
the falsification did, taking `waived-not-pass` to 242 with a single added
requirement. That is a real property of a percentage band over a small absolute
figure, and these three will be the noisiest rows in the set. It was not fixed
by widening the band or by choosing blander search terms, because both would be
tuning the instrument until it agreed with the answer.

**A measured limitation of the `mix` heuristic.** It tests whether a line
*begins* with a table pipe, so a markdown table row indented by two spaces —
which is how the status table in `spec.md` is written — is counted as prose. Of
the 19 candidate lines behind the `id-permanence` budget, one indented table row
scores as prose and its neighbour scores as markup only because it happens to
contain a backtick. The recorded mix figures are therefore a floor, not a
bracket. This is not corrected here: mix is never compared against anything, and
changing the heuristic would move a recorded figure without any measurement
saying which value is right.

**The calibration, and why there is still no printed token count.** Measured
2026-09-05 against the model's own tokeniser via `/v1/messages/count_tokens`, with
a 7-token per-request overhead subtracted: EARS requirement lines 4.21 bytes per
token, the whole living spec 3.89, YAML 3.84, markdown table rows 3.74, shell with
comments 3.35, Python 3.12, comment-stripped shell 2.33. That is an 85% spread, so
no single factor exists and none is printed. What IS narrow is the band the check
actually reports over: 3.79 to 4.31 across its own candidate slices, a 14% spread,
so N characters is about N/4 tokens on today's spec and nothing wider is claimed.
The exchange rate is a property of the CONTENT, not of the file: 2000 bytes of
prose is 471 tokens and 2000 bytes of comment-stripped shell is 859 - the same
character count for 82% more tokens - which is why a `mix` figure is recorded
beside the character budget and why it is never banded. Nothing has measured what
a healthy mix is, so a band would be a threshold nobody derived.

**What it does not measure.** Whether the requirement it found was the right
one, whether the model would have understood it, or whether the spec is any
good. It measures the *cost of finding a known target* and nothing else. A spec
that is cheap to retrieve from and wrong scores perfectly.

## 2 · A/B harness — the process as the variable

One task, one model, two arms: `process` runs it through the nine stages, `bare`
runs the same model on the same task with none of it. Same model, same task
text, same machine. The harness is the variable and nothing else is.

**Mechanism.** The two arm commands come from `.claude/productizer/ab-task.tsv`.
The harness runs each under `bash -c` with `AB_OUT_DIR`, `AB_TASK` and `AB_ARM`
exported, times it, captures stdout and stderr to files (captured, never
discarded), reads a cost the arm writes to `$AB_OUT_DIR/cost.usd`, and appends a
row to `.claude/productizer/ab-runs.tsv`. `report` reads that file and nothing
else, so the same recorded runs produce the same report bytes.

**The small-n rule.** The only published benchmark that isolates the harness
this way carries the disclosure *"Results are directional (n=1 per arm)"*. That
convention is enforced here rather than left to the writer:

- **Every figure prints its arm count beside it.** `343 (n=1)`. A median with no
  n attached is a claim, not a measurement.
- **Below `--min-n` complete runs in the smaller arm (default 5)** the report is
  labelled `DIRECTIONAL` and states that the harness will not call the
  difference meaningful. The delta is still printed — hiding it would be its own
  dishonesty — and the conclusion is refused.
- **Above the threshold it is still a difference of two medians**, which the
  report says in the same breath. It is not a significance test and does not
  establish causation.
- **An arm with no complete run is `no-complete-runs`, exit 6** — not an arm
  that scored zero.

**Unmeasured values.** A task that exits non-zero is recorded `incomplete` and
excluded from every figure; a run that reports no cost records `unavailable`,
which is what an unreported cost is. Durations are wall-clock measurements —
they are the measurement, not a timestamp — and no timestamp is ever recorded,
so a run's identity is its index within its arm.

**What it does not measure.** Quality of the output, correctness of the output,
or anything about the artifact beyond its size in bytes. It answers *what did
the process cost*, which is half the question. Attaching the other half means
scoring the two arms' outputs, and scoring is exactly where the judge problem
comes back — so the harness deliberately stops short and records the output
paths for a human.

## 3 · Stage snapshot — the human delta

Every artifact in this lifecycle is edited by a human before anyone looks at it.
Measuring the file that survives that measures the writer-plus-agent workflow
and reports it as the agent's output. The contamination runs one way and always
flatters: a bad draft rescued by a careful edit scores as a good draft.

**Mechanism.** Capture the draft the moment the stage produces it, before a
human opens it, into an immutable snapshot. Score that. Then measure separately
what the human changed. **The delta is the measurement** — it says what the
process contributed, not what the final artifact looks like.

Immutability is a property of the files, not a promise in a comment: `snapshot`
refuses to overwrite an existing snapshot (exit 1) and `chmod 444`s what it
writes. A snapshot that can be refreshed after the human edit is not a snapshot;
it is the artifact again, and the delta collapses to zero. `--run <label>` takes
a second, separately named snapshot instead.

**The delta is a proxy, and it is named as one.** Lines added, lines removed,
and both as a percentage of the snapshot's line count. That is a proxy for
*editorial effort*, not for quality. A one-line correction of a wrong number and
a one-line typo fix are the same delta; a reformat that rewrites every line is a
100% delta that changed nothing. Read it as volume of human intervention, per
stage, over time — never as a score, and never on a single artifact.

**Outcomes.**

| Outcome | Means | Exit |
|---|---|---|
| a delta | measured, including a genuine `0%` when the human accepted the draft | 0 |
| `no-snapshot` | nothing was captured. Not a delta of zero | 5 |
| `artifact-missing` | captured, but the file is now gone — deleted, moved, renamed | 6 |
| `stage-produced-nothing` | the stage delivered nothing, so there is no draft a human could have edited. Delta prints `unmeasurable` | 7 |

A missing artifact and an empty one are both recorded at snapshot time as
`state=produced-nothing` with the reason, and exit 8. Writing a zero-byte
snapshot for them would later measure as a zero delta, which would read as *the
human accepted the draft* — the one thing it certainly does not mean.

## Which figures are proxies

Say this out loud whenever any of these numbers is quoted:

| Figure | Direct measurement? | |
|---|---|---|
| retrieval budget, characters | **proxy** | for a token budget. A real token count needs a model call |
| human delta, % of lines | **proxy** | for editorial effort. Not for quality |
| A/B duration, ms | direct | monotonic clock around the arm command |
| A/B cost, USD | direct **when reported** | the arm reports it; otherwise `unavailable`, never `0` |
| A/B output size, bytes | direct | size only. Says nothing about content |
| snapshot bytes, lines, sha256 | direct | of the file as captured |

## What remains unmeasured

**The end-to-end contradiction-classification recall is unmeasured**, and none
of these three instruments closes it.

The question is: of intents that genuinely contradict an active requirement,
what fraction does intake actually halt on? That is the plugin's central claim
and the number nobody has. What *is* measured is narrower and is reported as
such in `references/solver.md`: the deterministic checker alone scores recall
0.67 on a twenty-pair corpus built to be favourable to it. That is one component,
on a small corpus, without the model that sits after it in the real path.

Why each instrument does not close it:

- **Retrieval budget** — no. It bounds one *cause* of a miss: a contradicting
  requirement the agent never retrieved cannot be classified against. Keeping
  the budget in band makes retrieval a less likely explanation for a miss. It
  says nothing about the classifier that did see the requirement, and a
  perfectly cheap retrieval of a requirement the model then misreads scores
  green.
- **A/B harness** — no. It compares cost and duration. It has no notion of a
  correct classification and computes no accuracy of any kind. It could
  *carry* a recall figure if an arm computed one and wrote it out, but the
  harness does not compute it and must not be read as if it did.
- **Stage snapshot** — no. A large human delta on a Stage 2 spec delta is a
  *signal* that a classification needed correcting, but a delta is not a label:
  the human may have been fixing wording. Correlation at best, and unlabelled.

What would close it is the thing this suite otherwise avoids: a labelled corpus
of intents against a known spec, with ground truth for which genuinely
contradict, run through the real intake path and scored on recall. `evals/cases/`
is the beginning of one. Until that exists and is run against the full path,
statements about how often the process catches a contradiction are estimates,
and should be written as estimates.

Also unmeasured, and worth naming rather than implying: whether a spec that is
cheap to retrieve from is a *better* spec; whether a low human delta means the
draft was good or that the reviewer was tired; and whether any of the leading
indicators in `references/stages.md` predict the lagging ones. All three are
plausible. None is measured here.
