# Which model runs a stage

Every stage names a model and an effort in `.claude/productizer/config.json` under `models`.
The defaults are recommendations that ship with the skill; change any of them.
But the block divides into two halves, and confusing them is the whole reason
this file exists.

## Enforced, or merely intended

**Enforced.** A stage that begins a **fresh context** — a subagent — carries its
model and effort in frontmatter. The runtime honours it. `enforced: true` in the
config means the stage has somewhere to put the setting.

**Intended.** A stage that runs **in your session** inherits your session's
model, whatever this file says. There is no mechanism by which a markdown file
retunes the conversation you are already in. For those stages the config is a
recommendation, and the skill's job is to *say which stage it is entering* so
you can change model yourself before it runs.

**Never claim a stage runs on a model it does not.** A preference nothing
enforces is documentation, and documentation that reads like a control is worse
than no control — someone budgets against it, or trusts a review they think ran
adversarially at high effort when it inherited whatever was already loaded.

## The defaults, and why each one

| Stage | Effort | Model | Enforced | Why |
|---|---|---|---|---|
| **0c import** | high | inherit | no | Inferring requirements from code nobody has read is the hardest inference here, and each mistake becomes a requirement someone later confirms |
| **2 intake** | high | inherit | no | Contradiction detection against the whole spec is the hardest call in the lifecycle, and a missed contradiction merges silently |
| **3 build** | inherit | inherit | no | Your session, your choice |
| **4A tests** | inherit | inherit | no | Runs in your session against a written plan |
| **4B evals** | low | cheap | **yes** | Mechanical pass/fail, 20–50 nightly — this is where cost actually lives |
| **4C checks** | none | **none** | **yes** | No model in this path at all |
| **5 review** | high | inherit | **yes** | Fresh context, adversarial, low volume — the one place raising effort is cheap and obviously worth it |
| **5B document** | medium | inherit | **yes** | Reads the whole active spec and maps every section to ids; cheap models drop the mapping and write plausible prose instead |
| **5C announce** | high | inherit | **yes** | Every claim must trace to a merged PR or a requirement id, and this is the one artifact that leaves the building |
| **6 diagnose** | low | cheap | **yes** | 2σ is summarising. Raise it for 3σ, which proposes a change |

`inherit` means take the session's. `cheap` means the smallest model that can do
the job — name the actual model id if you want to pin one.

`models.review` also sets the advisory half of `/productizer:spec-review`
(`references/spec-review.md`), which runs in a fresh context from
`templates/agent-spec-reviewer.md`. Enforced only when that agent is installed
and dispatched as itself; the skill says which happened.

## Stage 5 takes no model, deliberately

`checks: {model: none}` is not an omission. Stage 5 runs the scripts you
declared and compares what they examined against what they promised. That
comparison is arithmetic. A model asked *did this check pass* will find the
green summary line convincing, which is precisely the failure the stage exists
to prevent — a scanner reporting `Grade A (100/100)` after opening one file of
forty-eight produces a summary a model has every reason to believe.

The same holds for control-band detection at Stage 9: tiers are compared
numerically, and the model enters only afterwards, to explain.

## Raising effort where it pays

Effort buys the most at the two points where being wrong is expensive and the
volume is low: **intake**, because a merged contradiction is discovered months
later by someone building on both sides of it, and **review**, because it is the
last read before a human's. Both are single-digit calls per change.

It buys the least where volume is high and the judgement is mechanical: nightly
evals and 2σ diagnosis. Those run tens of times a day and answer questions with
a right answer.

Spend accordingly. A configuration that runs everything at high effort is not
more careful — it is the same care with a larger bill, and it makes the nightly
suite expensive enough to switch off, which costs the regression net.

## Changing it

Edit `models` in `.claude/productizer/config.json`. Nothing regenerates it and no update
overwrites it — it is your file.

For an **enforced** stage the value reaches the subagent's frontmatter, so the
change takes effect on the next run. For an **intended** stage the skill reads
the value out when the stage begins and leaves the choice to you; it will not
pretend to have applied it.

If a stage is missing from the block, the skill says so and continues at the
session's settings rather than guessing a default — a silently invented model is
the same failure as a claimed one.
