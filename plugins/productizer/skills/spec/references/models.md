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

## The advisor

`models.advisor` is optional and is not a stage: it is a string naming a model,
or `null`. Claude Code's advisor tool (experimental,
https://code.claude.com/docs/en/advisor) lets the running model consult a
second, usually stronger model. Per that page, the advisor "receives the full
conversation, including every tool call and result", and the model "tends to
consult before committing to an approach, when an error keeps recurring, and
before declaring a task done, but the timing is model-driven rather than
rule-based"; "There is no setting to cap or force advisor calls."

**Where Productizer passes it.** Only the unattended CI build
(`templates/build-from-spec.yml`, `references/ci-build.md`). `build-dispatch.sh
prepare` adds one line `--advisor <model>` after `--model` and `--effort`, and
`agent-args` re-checks it. Absent or `null` adds nothing - the flags are
byte-identical to a config without the key. The value must be a JSON string
shaped like a model name, held to the same shape as `models.build.model`: a
letter or digit first, then only letters, digits and `. _ : @ -`. An alias
(`opus`, `sonnet`, `fable`) or a full id (`claude-opus-5-5`) passes. Anything
else - empty, a number or object, `inherit`, `cheap`, `none`, a space, a
newline, a leading `-` - refuses the run (exit 3) before any model is called;
it is never passed through, because it lands in the agent's argv. Whether the
pairing is allowed is checked by Claude Code at launch, not by Productizer.

**Advice, never a gate.** Nothing guarantees the advisor is called, and the
docs say an advisor ranked below the main model is not attached, and a pairing
the API refuses is dropped "so you see no error and get no advisor calls". No
Productizer check, stage transition or review may rely on an advisor having
run. Setting `models.advisor` changes what the build agent may ask, not what
the lifecycle verifies.

**What it sees and costs.** Every advisor call sends the whole transcript -
repository files the agent read, the spec diff, every tool result - to the
advisor model, and its tokens bill at the advisor model's rates on top of the
main model's; the advisor's read is not prompt-cached. Choose it as you would
a model you are willing to show the repository to and pay for per call.

**Limits (from the docs, not measured here).** Anthropic API and subscription
accounts only - not Amazon Bedrock, Claude Platform on AWS, Google Cloud's
Agent Platform or Microsoft Foundry; through a gateway set by
`ANTHROPIC_BASE_URL` it depends on the gateway forwarding the request intact.
It stays off when feature-flag fetching is off (for example `DISABLE_TELEMETRY`
set). `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1` disables it; the flag is then
accepted with no effect. `claude --help` does not list `--advisor`.

**Accepted pairings**, copied from the docs on 2026-10-25 (an advisor must rank
at or above the main model; rows run from the lowest-ranked main model):

| Main model | Accepted advisors |
| - | - |
| Haiku 4.5 | Fable, Opus, Sonnet, Haiku 5.5 |
| Sonnet 4.6 | Fable, Opus, Sonnet, Haiku 5.5 |
| Opus 4.6 | Fable, Opus, Sonnet 5 or later, Haiku 5.5 |
| Sonnet 5 or Haiku 5.5 | Fable, Opus 4.7 or later, Sonnet 5 or later, Haiku 5.5 |
| Opus 4.7 or Opus 4.8 | Fable, Opus 4.7 or later, Sonnet 5.5 |
| Sonnet 5.5 | Fable, Opus 5 or later, Sonnet 5.5 |
| Opus 5 or Opus 5.5 | Fable, Opus 5 or later |
| Fable 5 | Fable 5.1 or Fable 5 |
| Fable 5.1 | Fable 5.1 |

The page adds version floors (for example Haiku 5.5 as main or advisor needs
Claude Code v2.1.293 or later) and that Haiku 4.5 "can call the advisor but
can't act as one". The table changes with releases; read the page before
choosing.

**Measured here** (2026-10-25, local `claude -p` 2.1.295, not in CI):
`claude --advisor notamodel -p "say hi"` printed `Error: The model "notamodel"
cannot be used as an advisor.` and exited 1; `claude -p --advisor opus "Reply
with the single word ok."` with the default model printed `ok` and exited 0.
That proves the flag is accepted headless, not that an advisor was attached or
called. Nothing has been run inside the CI action.

**In an attended session** Productizer passes nothing: `models.advisor` is not
read there. Use `/advisor <model>` (`/advisor off` to stop; it also works with
`-p` from v2.1.260) or launch with `claude --advisor <model>`. `/advisor` saves
the choice to `advisorModel` in `~/.claude/settings.json`. The settings
reference lists `advisorModel` for every settings file, so a committed project
`.claude/settings.json` could set it too - which the CI build's `repo-settings`
option would hand the agent; not measured here.

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
