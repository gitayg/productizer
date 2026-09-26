# Risk tiers, and calibrating a check before it blocks

Two mechanisms, one discipline. Both were built as INSTRUMENTS FIRST and gate
nothing, and that ordering is the point rather than an unfinished state.

| Mechanism | Declared in | Measured by | Gates anything today |
|---|---|---|---|
| Risk tiers by path | `.claude/productizer/risk-tiers.yaml` | `scripts/classify-change-risk.sh` | no |
| Over-fire before blocking | nothing yet — the rule is proposed below | `scripts/measure-check-overfire.sh` | no |

## Part 1 · Risk tiers, so review attention is not flat

### The problem

Every change in this repository meets the same gates. To Stage 5, a one-line
rewrite of a requirement's sentence and a two-hundred-line addition to a fixture
corpus are the same event. Nothing says which one is worth a person's afternoon.

### Two axes, not one score

| Axis | Means | Declared by a path? |
|---|---|---|
| **RISK** | how bad it is if this change is wrong | **yes** — it is a property of what was touched |
| **COMPLEXITY** | how much planning the change needs | **no** — it is a property of the change |

The policy declares risk and nothing else, and the tool prints
`complexity: unmeasured` on **every** run. That is not a gap waiting to be
filled. A single blended score hides exactly the case this mechanism exists for:
a one-line edit to the living spec is **maximum risk and minimum complexity at
once**, and any tool that multiplies them together reports it as medium
everything.

What the tool *does* measure beside risk is **size** — files touched, lines added
and removed, from the diff, when a `--base` is given. Size is printed as size and
is never called complexity. With no diff it prints `unmeasured`, not `0 files`.

### The tiers

| Tier | Means | What it asks for |
|---|---|---|
| `red` | a structural decision — what the product promises, or what the gate permits | a person decides; an agent does not land it unattended |
| `amber` | shipped machinery — code that runs on a stranger's machine | the falsification P1 already demands: red before the fix, green after |
| `blue` | autonomous-safe — prose, recorded evidence, corpora, the backlog | an agent may land it on its own judgement |

The policy carries **42 ordered rules** — 14 red, 13 amber, 15 blue — and the
list's **order is the ranking**, highest first. A change set is given the
highest tier any of its paths reached, and the per-tier counts are printed so a
reader sees the shape and not only the verdict.

### A rename yields both paths, on purpose

`--base` takes the diff with `--no-renames`, so a moved file reports the OLD path
as well as the new one. The old path is the one the policy may have a rule for,
and git's rename detection collapses the pair. **Verified on a constructed repo**:
`git diff --name-only --cached HEAD` after a `git mv` prints only `docs/new.md`,
and the same command with `--no-renames` prints `docs/new.md` and `docs/old.md`.
This is the same defect B56 records for the check runner, avoided here rather than
fixed there.

### Grey is not a tier

A path no rule covers is **unclassified**, and the tool exits 1 on it.
Unclassified means *nobody has decided about this path* — it does **not** mean low
risk. There is deliberately **no catch-all rule** at the bottom of the policy: a
catch-all would make every new path low-risk on the day it was added, which is
the day nobody has looked at it.

This is R26's rule about numbers, applied to words. A value that could not be
measured is never rendered as zero; a path nobody classified is never rendered as
the bottom tier.

### How the policy was calibrated, with the numbers that moved it

`classify-change-risk.sh --calibrate` classifies every path of every commit
reachable from HEAD and prints the distribution. It is a **report, not a
verdict** — a distribution cannot say a tier is set correctly. What it can say is
when a tier has **stopped discriminating**.

**The first draft**, over all 121 commits, verbatim:

```
      commits read:          121
      path-changes:         1547
      red                         210   13.6%
      amber                       691   44.7%
      blue                        646   41.8%
      grey (unclassified)           0    0.0%
      distinct paths:        740
    commits by their highest tier
      red                                  111   91.7%
      amber                                  6    5.0%
      blue                                   4    3.3%
```

**111 of 121 commits red.** The cause is mechanical, and measuring it took one
more command: `plugins/*/.claude-plugin/plugin.json` is touched by **106 of 121
commits**, because the version is bumped before every commit, and **56 commits
were red for no other reason than that bump**. A tier reached by 92% of commits
is a second word for "a commit".

**After moving that one rule from red to amber**, same command, verbatim:

```
      red                         104    6.7%
      amber                       797   51.5%
      blue                        646   41.8%
      grey (unclassified)           0    0.0%
    commits by their highest tier
      red                                   55   45.5%
      amber                                 62   51.2%
      blue                                   4    3.3%
      grey (every path unclassified)         0    0.0%
```

45.5% red is still high, and that is a fact about this repository rather than
about the policy: its product **is** the governance layer, so the spec, the gate
and the workflow are what it spends its commits on.

### The paths that actually change here

Measured over all 121 commits, most first:

| Path | Tier | Commits |
|---|---|---|
| `plugins/productizer/.claude-plugin/plugin.json` | amber | 95 |
| `README.md` | blue | 85 |
| `.claude/productizer/backlog.md` | blue | 53 |
| `.claude/productizer/checks-result.json` | blue | 43 |
| `.claude/productizer/checks.yaml` | red | 33 |
| `GUIDE.md` | blue | 33 |
| `.claude/productizer/spec.md` | red | 24 |
| `.../scripts/build-view.sh` | amber | 23 |
| `.../references/views.md` | blue | 17 |
| `.../scripts/run-checks.sh` | amber | 17 |
| `.../templates/view.html` | amber | 17 |
| `.../scripts/contradiction-check.py` | amber | 16 |
| `.../skills/spec/SKILL.md` | amber | 13 |
| `.github/workflows/checks.yml` | red | 12 |

`plugin.json`'s own count differs from the 106 above because 106 counts every
`plugins/*/.claude-plugin/plugin.json`, including the two pre-rename plugin
directories.

**Grey residue: none.** Every one of the 740 distinct paths in this repository's
history matched a rule. That is a property of a policy written *after* reading
the history, and it says nothing about a path added tomorrow — which is exactly
why there is no catch-all.

### Two holes, named rather than closed

**`checks-result.json` is blue, and a hand-forged one reads blue.** It is the
recorded result of the gate, so editing it by hand is forging a measurement. It
is still blue, because the runner rewrites it on 43 of 121 commits and red would
have meant "regenerated" more often than "decided something". Nothing in a path
distinguishes a regenerated artifact from a forged one. What would close it is a
check comparing the committed file against a fresh run.

**`plugin.json` is amber, and a changed description reads amber.** A version bump
and a change to the declared skills, commands or description are one path.
Closing it needs a rule that reads the field that changed.

## Part 2 · Calibrate a check before it blocks

### The gap this closes

`severity: advise` has been available from the start and three checks use it, so
the advisory mode was never the gap. The gap is that **no check here had ever
been measured for firing on the wrong things** before being made blocking. Every
severity in `checks.yaml` was an argument. A blocking check that fires on correct
work gets routed around, and a routed-around gate measures nothing.

### What the number is, and what it is not

`measure-check-overfire.sh --check <id> --commits N` replays a check against each
of the last N commits, each against the tree as it stood at that commit, and
counts the fires.

Every commit replayed is **already on the branch**. So a fire is one of two
things and the tool cannot tell them apart:

- a genuine defect that merged anyway, or
- a false positive.

The figure is therefore reported as a **fire rate** and described as an **upper
bound on over-fire**, never as an over-fire rate. Calling it an over-fire rate
would assert that every historical fire was wrong, which is the flattering
direction. The fires are printed with their commit subjects so a person can rule
on each one.

A third possibility is structural: an **anachronism**. A check written today,
replayed against a tree from before the requirement it asserts existed, fires
correctly and measures nothing about over-firing. A per-commit verdict list is
printed so a run of consecutive early fires is visible, and the rate is **not**
adjusted for it — adjusting would need the human ruling this tool does not do.

### The denominator is verdicts, not triggers

A replay that refused, timed out, or found no tool **did not examine that
commit**. Putting those under the line would shrink the rate towards zero — the
more often a check cannot run, the cleaner it would look. That is the
fabricated-zero failure with a division in front of it.

So the rate is `fired / (passed + fired)`, the non-verdict commits are reported
separately and excluded, and a check that triggered but returned a verdict on
**nothing** prints `n/a` and exits 4 rather than `0.0%`.

**This was found by running the tool, not by reasoning about it.** The first real
run, of `acceptance-rows` over 20 commits, came back:

```
    triggered:                      20
      pass                           0
      FIRED (a declared fail)        0
      refused                       20
    fire rate over merged history: 0/20 = 0.0%
```

20 refusals out of 20, published as a 0.0% fire rate. The cause was that almost
every check here locates its own root with `git rev-parse --show-toplevel`, and a
tree extracted with `git archive` carries no `.git`. Two changes followed: the
denominator became verdicts, and the extracted tree is now given an **empty** git
repository — `git init` and nothing else. That asymmetry is deliberate: a check
needing only the root now works, and a check reading **history** finds no HEAD and
refuses, which is counted as a refusal and never as a pass. Committing the tree
would have handed those checks a one-commit history that is not this repository,
and they would have answered confidently about it.

### How a tree is obtained, and why not `git checkout`

`git archive <commit>` extracted under a temporary directory. **Not** `git
checkout` and **not** `git worktree`: this repository is routinely worked on by
several agents at once, and a measurement that moved the work tree or wrote into
`.git` would corrupt whatever else was running. Nothing in this tool writes
inside the repository.

### A per_file check is invoked for every file, not the first one

A `mode: per_file` check is run once per triggering file and the invocations are
folded **worst first** — undeclared, then refused, then fired, then passed — so a
commit where one file of ten failed is a commit the check fired on. The first
version invoked only the first file, which would have systematically pushed every
per_file check's rate downward; an under-count reads as a low fire rate, which is
the flattering direction. The unit stays the **commit**: this tool counts commits,
not files.

### The per-commit timeout kills a process group, not a child

`subprocess.run(timeout=)` kills only the direct child. A check that spawns the
runner leaves grandchildren holding the pipes open, and the read blocks long after
the timeout has fired. **Measured, not reasoned:** a replay of `selftest-coverage`
with a 25-second per-run limit was still alive after twenty minutes and had
produced no line. The replay now runs each invocation in its own session and kills
the whole group on timeout, after which a second attempt at the same check left one
process alive at a time instead of several.

The self-test drives the timeout and asserts the bucket, but **it cannot falsify
the group kill** — its hanging fixture leaves a grandchild that exits by itself
after five seconds, so a child-only kill still reaches exit 4 and still reports
four timeouts; it only makes the run take 24.8s instead of about 4s. The fixture
sleeps five seconds rather than ten minutes deliberately: a case that HANGS when
the line regresses would hang the suite rather than fail it. The twenty-minute
observation, not the self-test, is the group kill's evidence, and the self-test
says so on every run.

### Which checks can be measured, and which cannot

`measure-check-overfire.sh --list` computes this rather than asserting it.
Measured on this machine, over the 38 checks in `checks.yaml`:

**30 of 38 measurable. 8 not, for three reasons:**

| Check | Why not |
|---|---|
| `superseded-text` | reads git history; an extracted tree carries no `.git` |
| `pending-ruling-scope` | reads git history |
| `spec-integrity` | reads git history |
| `changelog-row` | reads git history |
| `suspect-links` | reads git history |
| `sast-auth` | disabled — a shut guard fires on nothing |
| `secure-coding-controls` | disabled |
| `pii-log-scan` | disabled |

An unmeasurable check is **not** a check with a 0% fire rate. Its rate prints
`n/a` for a shut guard and `?` for a tool this machine does not have, and neither
of those is a number.

**The measurable count is machine-dependent, and says so.** `shellcheck`,
`gitleaks`, `semgrep` and `npm` are all present here, so no check landed in the
`tool absent` bucket. On CI or a fresh clone the same command will report fewer
measurable checks and name which tool was missing, which is the correct answer
rather than a worse one.

**Some measurable checks are expensive, and how expensive is not something
`--list` can tell you.** `unmeasured-report`, `no-fabricated-zero`,
`missing-tool-reported`, `declared-scope`, `cannot-run-coverage` and
`waiver-rendering` each work by running **the whole runner** over a fixture, so a
30-commit replay is 30 suite runs. A 30-commit replay of `unmeasured-report` was
started and abandoned after minutes without finishing a single figure, and those
six have **no rate here** — a rate nobody waited for is a fabricated one.

The bound is not the technique, though: `untrusted-execution` also runs the runner
and came back at `0/30 = 0.0%` inside a 25-second-per-commit cap. `--list` computes
whether a check CAN be replayed, not what the replay costs, and the cost has to be
found by trying.

**A FINDING ABOUT AN EXISTING CHECK, not about this tool.**
`check-spec-home-stop.sh` returned **exit 128 on all 30 replays**, and 128 is not
among the `pass: [0] / fail: [1] / refused: [2]` its `checks.yaml` entry declares.
Reproduced by hand in an extracted tree with an empty repository initialised:

```
  declared home: example/home-repo, spec path .claude/productizer/spec.md
spec-home-stop/02-classified-anyway/.claude/productizer/classifications/123.md
fatal: your current branch 'main' does not have any commits yet
```

Under `set -e` a git fatal escapes as git's own 128 instead of becoming the
check's documented refusal. The condition that triggers it here — a work tree with
no commits — is synthetic, so this is not a defect anyone has hit in normal use;
what it shows is that the check's `refused` leg does not cover every way its git
calls can fail. This tool counted those 30 runs in the **undeclared exit** bucket
and refused to call any of them a pass, which is the bucket existing for exactly
this.

**A check that reads history WITHOUT declaring git refuses, and is counted as a
refusal.** `classification-provenance` is the real case, and the run is the
evidence for the whole no-verdict design: it triggered on all 30 commits, refused
on all 30, and the tool printed `fire rate: n/a` and exited 4 rather than
`0/30 = 0.0%`. Reproduced by hand in an extracted tree with an empty repository
initialised, verbatim:

```
REFUSED: 6 record(s) cite a commit this clone cannot resolve, so whether they
were classified against the whole spec is UNKNOWN - not yes, and not no.
```

It declares no `git` in `requires`, so `--list` reports it measurable, and it is —
it just cannot return a verdict in a tree with no history. The refusal is the
check behaving correctly and the exit 4 is this tool behaving correctly; what
neither can do is produce a rate.

**`requires: [git]` is read as "reads history", and those are not the same
thing.** A check can need git only to LOCATE ITS OWN ROOT — which is what
`classify-change-risk.sh` itself does — and the heuristic excludes it anyway. The
error is in the **conservative** direction: it refuses to measure some checks it
could have measured, rather than publishing a rate for a check whose answer the
extraction distorted. A precise version would have to distinguish `rev-parse
--show-toplevel` from `rev-list`, which means reading the tool rather than its
declaration.

**Two further limits on which checks this can honestly speak for.** A
`requires: [git]` entry is how the tool detects a history-reading check; a check
that reads history **without declaring git** would be replayed and would refuse
rather than lie, which lands it in the excluded-from-denominator bucket and
eventually in exit 4. And a commit that only **deletes** files does not trigger a
path-scoped check, because a deleted path is not handed to a check — the same
behaviour the runner has, and the reason the tool's own fixture measures 1/2
rather than 1/3.

### What the measurements actually say

**21 of the 30 measurable checks were replayed.** Each was measured on this machine
against the tree as it stood at each commit. Every figure is `fires / verdicts`;
the fourth column is triggering commits that returned no verdict and are excluded
from the denominator. The nine not replayed are the six that run the whole runner
per commit — `missing-tool-reported`, `no-fabricated-zero`, `cannot-run-coverage`,
`declared-scope`, `unmeasured-report`, `waiver-rendering` — plus
`view-publish-refused`, `dependency-audit` and `sast`, whose replay was simply not
attempted. None of those nine has a figure here.

| Check | Window | Fire rate | Excluded | Note |
|---|---|---|---|---|
| `acceptance-rows` | last 30 | **0/29 = 0.0%** | 1 refused | the refusal is at `1534065` (v4.37.1) |
| `hygiene` | last 30 | **0/30 = 0.0%** | — | generic rules only; the private list is gitignored and absent from an extracted tree |
| `spec-home` | last 30 | **0/30 = 0.0%** | — | |
| `ruling-requested` | last 30 | **0/30 = 0.0%** | — | |
| `jira-unbound` | last 30 | **0/30 = 0.0%** | — | |
| `guide-current` | last 30 | **0/30 = 0.0%** | — | |
| `import-marking` | last 30 | **0/30 = 0.0%** | — | |
| `view-read-only` | last 30 | **0/30 = 0.0%** | — | |
| `template-frontmatter` | last 30 | **0/30 = 0.0%** | — | |
| `classification-provenance` | last 30 | **`n/a`, exit 4** | 30 refused | no verdict on any commit; see below |
| `retrieval-budget` | last 30 | **0/12 = 0.0%** | 18 refused | |
| `nothing-merged` | last 30 | **0/30 = 0.0%** | — | |
| `spec-home-stop` | last 30 | **`n/a`, exit 4** | 30 undeclared exits | it exits **128**; see below |
| **`stderr-suppression`** | last 30 | **2/17 = 11.8%** | — | 13 commits touched no shell. **Both fires ruled genuine** — see below |
| `installed-copies` | last 30 | **0/30 = 0.0%** | — | |
| `secret-scan` | last 30 | **0/30 = 0.0%** | — | `gitleaks` present on this machine |
| `untrusted-execution` | last 30 | **0/30 = 0.0%** | — | it runs the whole runner over fixtures and still finished inside 25s per commit |
| `publish-gate-decides` | last 30 | **0/30 = 0.0%** | — | |
| `solver-corpus` | last 30 | **0/30 = 0.0%** | — | |
| `shell-lint` | last 30 | **0/17 = 0.0%** | — | 13 of 30 commits touched no `.sh`, so it did not trigger |
| `acceptance-rows` | last 80 | **0/74 = 0.0%** | 1 refused, 5 tool-absent | the 5 are commits before the check script existed |
| `selftest-coverage` | last 30 | **1/1 = 100.0%** | 1 refused, 15 tool-absent, 13 timed out | a rate over one verdict; see below |

**The fire bucket registers on real data.** `stderr-suppression` gives the one
usable rate — 2 fires over 17 verdicts, both ruled, below — and
`selftest-coverage` gives the clearest argument for the verdict-count floor in the
rule below:

```
    triggered:                      30
      pass                           0
      FIRED (a declared fail)        1
      refused                        1
      tool absent at that commit    15
      timed out                     13
    verdicts (pass or fail):         1   <- the denominator
    fire rate over merged history: 1/1 = 100.0%
    29 triggering commit(s) produced NO verdict and are excluded from
    the denominator, never counted as a pass.
```

`100.0%` over **one** verdict is not a measurement, and the run says so in the
same breath by printing the denominator. The fire is at `a274b801` —
*"v4.48.0 — something is looking now, and it says 28 tools are untested"* — which
is a commit that landed while the coverage it checks was knowingly incomplete, so
it is the anachronism case rather than a false positive. Under the rule below this
check does not earn `block` on this evidence: it cleared no verdict floor.

The 15 `tool absent` commits are older than the check's own script; the 13
timeouts are this check replaying 38 self-tests inside a 25-second cap.

Read the 0.0% rows as *these checks did not fire on the merged history they were
replayed against*, which is what they say. **One check has had its fires ruled and
its measured false-positive rate is 0 of 17**; for every other row the figure is
still an upper bound, because a check that never fired has nothing to rule and a
check that fired once has not been opened.

### The one check that has actually been calibrated

`stderr-suppression` is `severity: block` today, and it is the only check here
whose fires have been **ruled**. Over the last 30 commits it triggered on 17,
returned a verdict on all 17, and fired on 2 — a raw fire rate of **11.8%**, which
is above the 10% the rule below asks for.

Both fires were then opened by hand, which is what turns an upper bound into a
number. Each is a **genuine suppression present in the tree at that commit**, not a
false positive:

| Commit | Ruling |
|---|---|
| `1029c597` (v4.44.0) | `build-view.sh` lines 122, 125, 127, 129 each suppressed stderr |
| `434bd790` (v4.55.0) | `upgrade-drift.sh:688` suppressed stderr |

So its **ruled false-positive rate is 0/17 = 0.0%**, and its raw fire rate of
11.8% is entirely real defects that merged. This is the first number in this
repository that says anything about whether a blocking check blocks the wrong
things, and the answer for this one is that it does not.

**It changed the rule.** The first draft of the rule below capped the RAW fire
rate at 10%, and on this evidence that draft would have demoted a correct blocking
check to `advise` for catching two real defects. The clause is now about the RULED
false-positive rate, which is the quantity anybody actually cares about, and the
raw rate is what tells a person how much ruling there is to do.

### The proposed rule — what earns `block`

Not implemented, and deliberately: this is a proposal for the maintainer, since
changing what blocks a merge is a decision and not a measurement.

> **A check may be declared `severity: block` when, over a window of merged
> commits, it returned a VERDICT on at least 20 of them, EVERY fire in that window
> has been ruled by a person as either a genuine defect or a false positive, and
> the ruled FALSE-POSITIVE count is at or below 10% of the verdicts. Until all
> three hold it ships `severity: advise`. A check that cannot be measured over
> history does not thereby earn `block`; it earns an explicit `limitations` entry
> saying its severity was never calibrated. The window, the counts and the rulings
> are recorded where the check is declared, so a later reader can disagree with the
> figures rather than with the decision.**

Each clause exists for a reason, and two of them exist because a measurement
contradicted an earlier draft:

- **a verdict on at least 20** — a floor on the denominator. 2 fires out of 2
  verdicts is 100% and 0 out of 1 is 0%, and neither is a measurement. The same
  rule the A/B harness enforces with `--min-n`. `selftest-coverage` reads
  `1/1 = 100.0%` and `stderr-suppression` reads `2/17`, and the floor is what stops
  either being quoted as a rate.
- **a window, not "the last 30"** — the first draft fixed the window at 30 merged
  commits, near the 18 the comparison project used. Measurement killed the fixed
  number: `shell-lint` and `stderr-suppression` both reach only 17 verdicts in 30
  commits, because 13 of those commits touched no shell at all. A path-scoped check
  needs a wider window to clear the same floor, and the window therefore has to be
  the thing that moves.
- **the ruled FALSE-POSITIVE count, not the raw fire rate** — the first draft
  capped the raw rate at 10%. `stderr-suppression`'s raw rate is 11.8% and **both
  its fires are real defects**, so that draft would have demoted a correct blocking
  check for doing its job. The raw rate measures how much ruling there is to do;
  only the ruling measures over-firing.
- **10% of verdicts** — a **proposed threshold, not a derived one**. Nothing here
  has measured what false-positive rate makes people route around a gate. It is
  written as a number so the next person can disagree with a number rather than
  with a mood.
- **every fire ruled** — because the tool reports an upper bound, and an
  uninspected 10% could be ten false positives. Ruling two fires took about a
  minute each: extract the tree, run the check on the changed files, read what it
  named.
- **unmeasurable does not earn `block`** — the loophole is otherwise obvious: a
  check nobody can replay would inherit `block` by being unmeasured, which is the
  fabricated zero again.

**Applied to what has been measured: no check yet satisfies it.**
`stderr-suppression` satisfies the ruling clause and the false-positive clause
(0/17) and misses the 20-verdict floor at 17. The **fourteen** checks that read
`0/30 = 0.0%` satisfy the floor and the false-positive clause trivially and have
no fire to rule, which is the vacuous case the maintainer has to decide about.
`selftest-coverage`, `classification-provenance` and `spec-home-stop` are not in
the running: 1, 0 and 0 verdicts respectively.

### Where the two mechanisms meet

A check's severity and a change's tier are different decisions and must not be
collapsed. A `blue` change can still fail a blocking hygiene check, and it
should. What the tier changes is **whose attention** a change needs; what the
calibration changes is **which checks are allowed to stop it**.

## Running them

```bash
# the tier of the working tree against a base, with the deciding rules
bash plugins/productizer/skills/spec/scripts/classify-change-risk.sh --base HEAD~1

# the tier of one named path set - bare arguments are paths, which is the shape
# the check runner produces when it substitutes {files}
bash plugins/productizer/skills/spec/scripts/classify-change-risk.sh \
  .claude/productizer/spec.md README.md

# the policy against this repository's whole history
bash plugins/productizer/skills/spec/scripts/classify-change-risk.sh --calibrate

# which checks can be replayed at all
bash plugins/productizer/skills/spec/scripts/measure-check-overfire.sh --list

# one check's fire rate over the last 30 commits, which is the default window
bash plugins/productizer/skills/spec/scripts/measure-check-overfire.sh \
  --check acceptance-rows
```

### Exit codes

`classify-change-risk.sh`

| Code | Means |
|---|---|
| 0 | classified — every path matched a rule |
| 1 | at least one path matched no rule: `unclassified`, never a tier and never a pass. Also `--calibrate` reading no commit |
| 2 | could not run — bad usage, two change-set sources, no policy, no `python3`/`yaml`, no git work tree when one was needed, a shallow clone under `--calibrate`, an empty change set |
| 3 | the policy itself is unusable — an undeclared tier, a rule with no glob or no reason, a duplicate glob, a missing `unclassified` block, or `unclassified` claiming to be a tier |

`measure-check-overfire.sh`

| Code | Means |
|---|---|
| 0 | measured — a fire rate over a non-zero verdict count |
| 2 | could not run — bad usage, `--list` with `--check`, `--commits` with `--since`, no config, unparseable config, no `python3`/`yaml`, not a git work tree, a shallow clone, an unknown check id |
| 3 | this check cannot be measured over history — disabled, no command, reads git history, or its tool is absent here. Rate prints `n/a` or `?` |
| 4 | measured nothing — it never triggered, or it triggered and returned a verdict on none of them. Rate prints `n/a` |

### Not proven

- **`--calibrate` and `--base` have no self-test case.** Neither the history
  aggregation nor the SIZE measurement is driven; only the `size: unmeasured`
  wording for a change set with no diff is. Both need a real git history, and a
  self-test that built one would be measuring the fixture it had just written. The
  figures above come from real runs against this repository.
- **The 10% threshold and the 20-verdict floor are not derived.** No measurement
  here says what false-positive rate makes a gate get routed around, and the floor
  is borrowed from the A/B harness's `--min-n` rather than computed.
- **Under-firing is not measured by anything here.** A check that never fires
  scores a perfect 0% and may be proving nothing. R39's falsification requirement
  is the instrument for that; this one is blind to it.
- **The undeclared-exit bucket is read from the source, not driven by a case.**
  Every fixture tool returns a code its own config declares.
- **The group kill on timeout is exercised but its EFFECT is not asserted.** The
  hanging fixture leaves a grandchild that exits by itself after five seconds, so a
  child-only kill still reaches exit 4 and still reports four timeouts — it only
  makes the run take 24.8s instead of about 4s. The twenty-minute observation on
  real data is its evidence.
- **`selftest-coverage`'s single fire is NOT ruled.** It is called an anachronism
  above from reading the commit subject, which is a guess, not the file-level check
  that was done for `stderr-suppression`'s two fires.
- **No check has been shown to satisfy the proposed rule**, and whether a window
  with zero fires satisfies the "every fire ruled" clause vacuously is the
  maintainer's call, not decided here.
- **Only one check's fires have been ruled**, and only two fires exist to rule.
  Every other figure here is still an upper bound.
- **The rulings are in prose in this file, not in any machine-readable place.**
  Nothing re-checks them, and nothing would notice if the window moved and they
  went stale.
- **Six measurable checks have no rate** because replaying them means running the
  whole runner per commit. They are named above, not estimated.
- **One whole-suite run failed transiently and was not traced.** A run of
  `run-checks.sh --base <root commit>` during this work exited 3 on
  `REFUSED: shell-lint (fail)`, while eight other agents were editing shell
  scripts in the same tree. `shellcheck --severity=warning` over every tracked and
  untracked `.sh` immediately afterwards named no failing file, and **two**
  subsequent whole-suite runs with these four files in place both exited **0** —
  the second of them on the final state of this work, reporting *"PASS: every
  blocking check ran, covered what it declared, and found nothing."* So the suite
  is green with this work present, and the earlier failure was not reproduced and
  not attributed.
- **`check-selftest-coverage.sh` reports 38 of 38 tools, and neither of these two
  is among them.** They are undeclared, so R39 and R40 cannot see their
  self-tests, and they read as **uncounted** rather than as covered until a
  `checks.yaml` entry and a workflow line name them.
