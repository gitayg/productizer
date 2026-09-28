# The checks stage

Security and quality checks are a stage a team configures, not a list baked
into the tool. The declaration is `.claude/productizer/checks.yaml`
(`templates/checks.yaml`); the runner is `scripts/run-checks.sh`; the output is
`.claude/productizer/checks-result.json`, which the review stage reads.

The runner decides nothing. Which checks exist, what triggers each one, whether
it blocks, and what it must have covered all come out of the config. A change
to the checks stage is a diff against that file, reviewed like code, with the
same audit trail as everything else in this lifecycle.

## Where it sits

```
3 · build  →  4 · test  →  [ CHECKS ]  →  5 · deploy (review, gate)  →  6 · maintain
```

It runs after the change builds and its tests pass, and before a human is asked
to look at it. That position is deliberate in both directions:

- **After build**, because a check needs a diff to scope itself against. Before
  the code exists there is nothing to scan and every check is hollow.
- **Before review**, because a reviewer's attention is the scarcest thing in the
  pipeline. Sending a diff to review with an unrun scanner spends it on
  something a machine settles in ninety seconds.

It runs **locally, before the push**. Wiring it into CI alone breaks the secret
scan: a required CI check blocks the merge, but it runs after the push, and by
then the secret is on the remote and must be rotated. Blocking the merge is the
whole remedy for a failing test; for a secret it fixes nothing. Run it as a
pre-push step, and run it again in CI if you want the merge blocked too.

## Where paths resolve from

Three separate resolutions decide what this stage even looks at, and each one
sat in front of the next. The runner now prints all of them:

```
config: /path/to/repo/.claude/productizer/checks.yaml (the default, under the git work tree holding the working directory)
root:   /path/to/repo (the git work tree holding the config)
result: /path/to/repo/.claude/productizer/checks-result.json
```

| What | Resolved against | Fallback |
|---|---|---|
| `--config`, when given | the working directory, exactly as typed | none — someone typed it |
| the **default** config | the git work tree holding the working directory | then the one holding the runner itself; then the working directory |
| `ROOT`, and so every relative path *inside* the config | `--root`, else the git work tree holding the config | the config's own directory, with git's own explanation quoted |
| `--changed` | the working directory, which is what typing a path means | then the repository root; a miss names both places searched |

**All three were once relative to the working directory, and each hid the one
below it.**

The default config path is relative to the *repository*, not to wherever the
caller is standing. Resolving it against the working directory meant the runner
could only ever start from the repo root — from anywhere else it said `no
config at .claude/productizer/checks.yaml` and stopped, in front of everything
else here.

`ROOT` was taken from `dirname <config>`, which for the default config is
`.claude/productizer`, two levels down:

```
  MISSING_TOOL hygiene   block  exit -   version unknown
     -> declared tool not installed: ./scripts/check-hygiene.sh.
result: .../.claude/productizer/.claude/productizer/checks-result.json
```

The tool was present and executable the whole time. That is a **manufactured
absence** — the same false negative as a scanner reporting nothing because it
opened nothing — and worse than an ordinary path bug for two reasons: a
cannot-run status blocks whatever the check's severity says, so it becomes a
hard refusal in the most ordinary invocation there is; and the doubled
`policy.output` had the stage silently building a nested shadow of its own
config directory. Both `policy.output` guards — relative, and contained under
the root — held throughout. They were simply anchored to the wrong root.

And `--changed README.md` from a subdirectory reported the file as not existing
while it sat at the repository root.

### What the runner substitutes into a `command`

A `command` is an argv list the runner hands to a tool as it stands, with three
exceptions, and nothing else is ever rewritten:

| Placeholder | Becomes | Where it is allowed |
|---|---|---|
| `{file}` | one path from the change set; the tool runs once per path | `mode: per_file`, in `command` |
| `{files}` | every path in the change set, one argument each | `mode: batch`, in `command` |
| `{base}` | the full SHA of the commit the change is measured against — the merge base the result file records as `change.base`, never the ref that was typed | `command` only, never as the program |

**`{base}` exists because a check cannot see what changed unless it is told.**
The two governance checks compared the working tree against `HEAD`, were
declared with no base, and the runner passes a check nothing but its argv. On a
clean CI checkout the working tree *is* `HEAD`, so they could not fire: a
weakening of `secret-scan` committed and run through the runner read `PASS` on
both, while the same tool given `--base HEAD~1` named it. Found by measuring
recall on planted defects, not by reading the code.

It is data, not a program. It is refused in `command[0]`, in the script an
interpreter is handed, and in `version_command`, `requires` and the coverage
commands, where nothing would substitute it and the literal text would reach a
tool. The value is checked to be 40 hex digits before it is used.

**A run with no base does not guess one.** Under `--changed`, which names paths
and no commit, a check whose command takes `{base}` is never invoked and reads
`no_base` — a status that blocks at any severity, like `missing_tool`, because a
check that compares against a base measures nothing without one.

### Testing this class of bug

Two ways a test can agree with itself while all of the above is live, both
observed:

- **Supplying an absolute `--config`** skips the default lookup entirely. The
  test then exercises only the resolutions behind it and passes from every
  directory. Test the **bare** invocation.
- **Asserting only that runs agree** proves nothing here, because the wrong
  root was the *same* wrong root from every working directory. Assert the
  **value**: that the reported root is the repository, that no declared tool
  reads as absent, and that no nested `.claude` tree appears.

`scripts/fixtures/root-resolution.sh` pins all of it — bare invocation, four
working directories including one outside the repository, and assertions on
values rather than agreement. It has been seen failing against each of the
three sites broken on its own.

One thing it deliberately does *not* compare: the parenthesis on the `config:`
line legitimately differs from outside the repository, where the default is
found under the work tree holding the runner rather than the one holding the
working directory. Same file, different route, and naming the route is the
point of the line.

## What the review stage gets

`checks-result.json` is the handover, and it is evidence rather than a summary.
Per check it records the exact argv, the tool's version string, the exit code,
what triggered it, what it covered, and what it did not. A review that opens
that file can tell the difference between "the SAST pass found nothing" and
"the SAST pass loaded no rules", which is the difference this whole stage
exists to make legible.

Exit codes follow the same convention as the rest of the skill
(`references/delegation.md`, `templates/threshold.sh`):

| Exit | Meaning | What to do |
|---|---|---|
| 0 | every blocking check ran, covered what it declared, and found nothing | continue |
| 3 | **refused** — a deliberate no | read which check and why; fix the change or the config |
| 2 | bad usage, or a config that will not parse or validate | fix the invocation or the config, not the code |
| 1 | the runner crashed | unverified. Not a pass, and not a finding either |

3 and 1 stay distinct because a gate that exits the same way when it says no as
when it falls over is unreadable in a log, and the wrong thing gets fixed.

## Merging the result file

The result file is committed, because `build-view.sh` reads it out of the
repository and the dashboard has to render offline from a fresh clone. The
price is that any two branches that both ran the suite differ in it, and every
merge of the two conflicts. That is not a papercut: it happened on a
cherry-pick and on all three rebases of a three-PR stack in one day.

**Every ordinary resolution of that conflict fabricates a measurement.** Taking
one side keeps a `change.files` naming that side's files while the merged tree
carries both. Taking the other is the same lie mirrored. Editing the markers
assembles a run nobody performed. All three write a number nobody measured,
which is P1 broken with a merge tool holding the pen — and the result is
indistinguishable, a month later, from a real one.

So `.gitattributes` hands the path to `scripts/merge-checks-result.sh`, which
resolves it the only honest way — by re-measuring the merged tree — and refuses
whenever it cannot. It never picks a side. Its full reasoning is in its header.

**A fresh clone does NOT have it.** This is the part to be plain about. Git
will not let a repository define a merge driver, for exactly the reason P4
gives: a repository that could name a program to run would be choosing what
executes on the machine that cloned it. `merge.<name>.driver` is therefore
local config only, and `.gitattributes` on its own is inert. **Git says nothing
when it is missing** — the merge simply takes the ordinary conflict. That
failure is safe, and it is the one to design for. What is not safe is believing
the driver is active when it is not, so the script reports what git actually
sees rather than what the repository says:

```
plugins/productizer/skills/spec/scripts/merge-checks-result.sh --status
```

Two lines activate it per clone, and the second is a decision, not boilerplate:

```
git config merge.productizer-checks-result.driver \
  "$(git rev-parse --show-toplevel)/plugins/productizer/skills/spec/scripts/merge-checks-result.sh %O %A %B %L %P %X %Y"
git config merge.productizer-checks-result.trustrepo true
```

`trustrepo` is the P4 decision in the same shape as `allow_repo_local_tools`.
Measuring the merged tree means running the merged tree's `checks.yaml` and its
check scripts, and the branch being merged wrote them. Those cannot be
separated — measuring a tree is running its tooling. So the grant is explicit,
lives in `.git/config` where no branch can write it, and is off until a person
sets it. Without it every merge refuses.

### What it refuses, and why each refusal is right

| It refuses when | Because |
|---|---|
| `trustrepo` is unset | it would run the incoming branch's check scripts on the strength of nothing (P4) |
| it cannot identify and verify both sides | `%X`/`%Y` are conflict LABELS, not revisions; during a rebase or cherry-pick git passes a sentence. Each candidate is proved by hashing the blob it holds at this path against the temp file git supplied, and an unproved candidate is discarded |
| it cannot identify the ancestor the operation is using | a merge's is `merge-base`, a cherry-pick's is the parent of the picked commit; off the wrong ancestor it would rebuild a different tree |
| **anything else in the merge also conflicts** | a person is about to hand-edit those, so the tree it just rebuilt is not the tree that will be committed. Measuring it would record a result for a tree that never existed — the same fabrication, differently spelled |
| the suite exits 1 or 2 | no verdict was reached, so there is nothing measured to write. Exit 3 is a real verdict and IS recorded: a merged tree that fails its checks must be committed as failing them |

Every refusal writes the ordinary conflict markers into the file before exiting
non-zero. That is not cosmetic. Git uses whatever the driver leaves in `%A`
whatever its exit status, and `%A` arrives holding our side verbatim — so a
driver that exits 1 without touching it leaves a file flagged unresolved that
reads as perfectly clean, which somebody stages.

### Known limitations, measured

- **It costs a full suite run per invocation** — about 70 seconds for this
  repo, once per conflicting merge, and once per commit in a rebase.
- **It measures the tree, not the commit.** The merge commit does not exist
  while the driver runs, so the driver measures a synthetic commit wrapping the
  merged tree. Anything a check derives from git history differs slightly from
  what the same tree measures after the merge lands. Compared against an
  independent run of the merged tree, 1419 of 1422 recorded values matched;
  the three that did not were two check durations and one page-byte count that
  depends on the commit's identity.
- **A path containing a newline could be missed** by the other-conflicts scan.
  It parses `git merge-tree -z` with `tr`, because BSD awk cannot split on NUL
  — `RS="\0"` is read as the empty string, which is awk's paragraph mode.
- It does nothing for a fresh clone, CI, or anyone who has not run the two
  config lines. Whether that is enough is the open question below.

### The alternative this does not close

Not committing the file at all remains on the table, and the measurement
favours it more than it favours this driver.

Three things read the committed copy, and all three already distinguish absent
from unreadable from a measured zero. Removed from a fresh clone:
`build-view.sh` exits 0 and renders `—` with "not run · nothing has been
checked"; `stage-status.sh` reports Stage 5 as "not run · no
checks-result.json"; `signals.sh` exits 0 and records `local_checks` as
`ABSENT` with "Nothing locally verified — which is not the same as locally
clean." CI does not read it at all — `.github/workflows/checks.yml` writes its
own result to `$RUNNER_TEMP`. Every one of those is what P1 asks for anyway,
and none of it needs a line of new code.

Against that, the conflict then cannot occur on any machine, configured or
not — whereas this driver protects only the clones whose owners ran two
commands, at about 70 seconds each time.

## Who owns the file

One named person accountable for the checks stage — in most orgs a security or
engineering manager, not the tech lead of whichever team is shipping today.

Three rules make that ownership real:

- **Changes go through review like code.** The file is committed. Loosening a
  check is a diff someone approved, with a date on it.
- **The owner is not in the change's critical path.** An owner who can be
  reached mid-change to soften a check is not a gate, they are a queue.
- **The agent does not edit it.** If the agent can rewrite the checks stage
  when a check blocks it, the stage is advisory. Deny it in managed settings
  alongside the hooks directory:
  `"deny": ["Edit(.claude/productizer/checks.yaml)"]`.

## Settings that are not locally overridable

A `checks.local.yaml` beside `checks.yaml` is read, and almost all of it is
ignored on purpose.

The split is one question: **does this setting change what someone else reads?**
`checks-result.json` is the handover to review, so a setting that decides what
gets examined, or whether the run blocks, decides what everyone downstream
sees. That is a team decision, and it is honoured only from the committed file,
where it sits in a diff somebody approved.

| Setting | Honoured from | Why |
|---|---|---|
| `timeout_seconds`, per check and in `defaults` | committed **or** local | how long a slow laptop may take is nobody else's business |
| every `policy` key — `empty_run`, `output`, `spec`, `spec_coverage`, `allow_repo_local_tools`, `waivers` | committed only | each one decides what the whole run means |
| `severity` | committed only | whether a finding blocks a merge is not a per-developer choice |
| `enabled`, `when`, `command`, `requires`, `mode`, `exit_codes`, `coverage`, `version_command` | committed only | all of them change what is examined |

**Ignored, never silently.** A dropped override nobody is told about looks
exactly like an honoured one to the person who wrote it, so the runner names
each one on stderr and records them in the result:

```
run-checks: WARNING: ignoring `policy.empty_run` from checks.local.yaml. It is a team-level setting: it decides
what gets examined or whether this run blocks, so it is honoured only from the committed checks.yaml where
everyone who reads this repo's results can see it. Locally overridable: timeout_seconds.
run-checks: WARNING: ignoring `defaults.severity` from checks.local.yaml. ...
run-checks: WARNING: ignoring `checks[probe].severity` from checks.local.yaml. ...
run-checks: WARNING: ignoring `checks[probe].when` from checks.local.yaml. ...
  FAIL      probe              block  exit 1    probe 1.0  covered 2/2 files
ignored 4 local override(s) of team-level settings: policy.empty_run, defaults.severity,
checks[probe].severity, checks[probe].when. Team-level settings are honoured only from the committed config.
REFUSED: probe (fail)
EXIT=3
```

The same loosening, committed instead of local, is simply honoured — `advise`,
advisory, `EXIT=0`. The rule is about *where the decision lives*, not about
forbidding the decision.

Two more refusals belong to the same idea:

- **A config where every check is `enabled: false` is exit 2.** A configuration
  with no active verification refuses to load rather than exit 0 having
  verified nothing. It is one line of YAML away in every repo that has this
  file, and it is the largest hollow pass available.
- **A check that could not run blocks, whatever its severity.** `advise` means
  "argue with this check's findings". It has never meant "it is acceptable for
  this check to be absent", so `missing_tool`, `timeout`, `no_version`,
  `refused` and `unmapped_exit` block even on an advisory check. Only a check
  that ran and reached a verdict — `fail`, `hollow` — is softened by `advise`.

## Per-item scoping

A requirement touching authentication deserves more than a copy edit. Each
check declares `when`, and any one of three things can trigger it:

| Trigger | Written as | Scoped to |
|---|---|---|
| always | `always: true` | every change |
| path | `paths: ["**/*.sh"]` | changes touching matching files |
| tag | `tags: [auth, pii]` | changes whose requirements carry that tag |

**Paths scope to what the change touched. Tags scope to what it means.** A path
trigger hands the check only the files that matched its globs. A tag or an
`always` trigger says something about the change as a whole, so the check gets
every changed file. That distinction matters: a change tagged `auth` that edits
one template and one route should have both scanned by the auth ruleset, not
just the file whose extension happened to match.

Tags come from the living spec. The requirement ids a change cites carry the
tags; the checks stage reads them off the change and scopes accordingly. This
is the payoff for keeping requirements in one place — the scanner list follows
the meaning of the work, and nobody maintains a second classification.

Observed, on the same two files:

```
### N. a copy edit, no tags -> only the baseline triggers
checks stage: 2 declared, 1 triggered by 2 changed files
  PASS      copy-edit-baseline block  exit 0    wc (coreutils)  covered 2

### O. same files, requirement tagged auth -> the auth pass triggers too
checks stage: 2 declared, 2 triggered by 2 changed files and tags [auth, pii]
  PASS      copy-edit-baseline block  exit 0    wc (coreutils)  covered 2
  PASS      sast-auth          block  exit 0    sast-auth 2.1  covered 2/2 files
```

Globs are small on purpose: `**` crosses directory separators, `*` and `?` do
not. `scripts/*.sh` does not match `scripts/deploy/rollback.sh`. Shell-style
globbing that lets `*` cross `/` reads as if it scopes tightly while matching
half the repo, and nobody notices until an audit.

## Control frameworks: a tag is just a string

`when.tags` matches the tags a change's requirements carry, and a tag is an
arbitrary string. So a control id is a tag like any other:

```yaml
  - id: secure-coding-controls
    when:
      tags: ["A.8.28", "A.8.26", "42001-6.1.3"]
```

Tag a requirement in the living spec with the control it serves, and that
control's checks fire on exactly the changes that touch it, and on nothing
else. Nobody maintains a second classification, and there is no quarterly
reconciliation between the spec and a spreadsheet, because there is no
spreadsheet.

Observed, on the shipped template, same repo, same file:

```
### P. a change with no control tag -> the control check does not fire
checks stage: 9 declared, 4 triggered by 1 changed files

### Q. the same change, requirement tagged 42001-6.1.3
checks stage: 9 declared, 7 triggered by 2 changed files and tags [42001-6.1.3]
secure-coding-controls   triggered=True   by=['tag:42001-6.1.3']
```

**Quote the ids.** `A.8.28` survives bare, but YAML reads `8.28` as a number
and `42001-6.1.2` is not obviously a string to a parser. Quote them all and
stop thinking about it.

### What this buys

For each control id you tag: a dated, per-change record of which tool ran, at
which version, over which files, what it covered, and whether it blocked -
generated by the run rather than typed afterwards, and landing in
`checks-result.json`. That is the artefact an auditor is usually asked to
reconstruct from memory and screenshots.

### What this is not, plainly

**This is the evidence layer UNDER a management system. It is not a management
system, and a slide that says "ISO 27001 compliant" on the strength of it is
wrong.** It does not do:

- **Risk assessment.** Nothing here identifies a risk, scores it, or chooses a
  treatment. A tag says a control is relevant to a requirement. It does not say
  the control is sufficient, or that the risk was ever assessed.
- **A Statement of Applicability.** No list of which controls apply, which are
  excluded, and why. Excluding a control is a documented decision that this
  file cannot make and does not record.
- **Asset inventory.** No register of systems, data stores, owners, or
  classifications.
- **Incident management.** Nothing detects, triages, escalates, or records an
  incident. This stage runs before a merge; incidents happen after one.
- **Access review, supplier management, business continuity, awareness
  training, physical security.** Untouched, entirely.
- **Internal audit or management review** - the two things a certification body
  actually asks to see. A check cannot audit itself, and this stage already
  declines to judge whether the declared checks are the right ones. See *What
  this stage does not do*.
- **Coverage of a control across the estate.** The denominator this runner
  computes is over REQUIREMENTS in the spec, not over controls in a framework.
  A control that no requirement carries is invisible here: the run can tell you
  a requirement is uncovered, and it can tell you this change was scanned. It
  cannot tell you a control is uncovered, because it has no list of the
  controls that were meant to exist.

The honest sentence is "changes touching A.8.28 were scanned by X at version Y,
over these files, on these dates". Not "we are compliant with A.8.28".

## Blocking and advising

`severity: block` fails the run. `severity: advise` reports into the result and
the review brief without changing the exit code. Advisory is for a check with a
known false-positive rate that is still worth a reviewer's eye.

The failure mode to watch is the check that stays advisory forever. Promote one
to blocking the week its findings stop being argued with; an advisory check
nobody ever promotes is a check nobody reads. The runner names advisory
failures separately in the summary so they cannot be lost in a green run.

## Scanner theatre

**A check that passes tells you nothing unless you know what it examined.**

The worked example is real. This skill was audited by a security scanner called
`ecc-agentshield`. It reported **Grade A, 97 out of 100**. It had opened **one
of the thirty-three files** in the directory, because it only reads files named
`CLAUDE.md` and `settings.json`. Pointed at an empty directory it reports
**Grade A, 100 out of 100, 70 payloads, 70 blocked**. Canaries planted in the
shell scripts — an AWS key, a `curl | bash` — went undetected, and the grade
did not move.

Nothing about that output is a lie. The tool did block seventy payloads in the
one file it read. The grade is arithmetic over what it examined. The failure is
that the report never states the denominator, so a reader supplies their own —
the whole repo — and gets a number that means something entirely different from
what it says.

This is not one bad tool. It is the default shape of a scanner report, and it
survives because a green result is what everyone wanted anyway.

### Four properties that separate a real check from a decorative one

**1 · It reports what it covered, and the runner checks the number.**

Every check declares a `coverage` assertion, and the runner fails the check
when reality falls short — whatever exit code the tool returned. There are four
ways to obtain the number, in rough order of how hard they are to fake:

| `from` | The tool tells you | Fools |
|---|---|---|
| `per_file_exit` | it is invoked once per file; a file it bounced off is a file it did not check | almost nothing |
| `stdout_paths` | it names each file it scanned; compared against the change | a tool that lies in its own report |
| `command` | a separate enumeration command lists what it would cover | a stale enumeration |
| `stdout_count` | it prints how many items it processed | any tool that prints a number regardless |

Prefer `per_file_exit` where the cost is bearable. It is the only one that does
not take the tool's word for anything: the runner watches each file be accepted
or refused, one process at a time. Batch mode lets a scanner choose which files
it feels like opening and still exit 0, which is exactly what happened above.

Run against the config that reproduces the AgentShield behaviour, with the same
forty-eight files:

```
checks stage: 2 declared, 2 triggered by 48 changed files
  PASS      shell-lint         block  exit 0    ShellCheck - shell script analysis tool vers  covered 6/6 files
  HOLLOW    agentshield        block  exit 0    agentshield-stub 0.0  covered 1/48 files
             -> exited 0 but did not examine 47 of the 48 files in scope (SKILL.md, references/constitution.md,
                references/delegation.md, references/drift.md, references/ears.md, ...). A check that examined
                nothing is a failure, not a pass.
REFUSED: agentshield (hollow)
```

`HOLLOW` is the whole point. The tool exited 0 and claimed a perfect grade. The
stage refused it anyway, and named the forty-seven files nobody looked at.

**2 · It records the version of the tool that produced the verdict.**

A blocking check must declare `version_command`; the runner refuses a config
where one does not, and fails a check whose tool cannot state its version. The
version is not parsed or compared against a minimum — it only has to *change*
when the tool changes. A scanner that silently regresses between releases, or a
ruleset that quietly stopped downloading, is invisible in a stream of green
runs and obvious in a diff of two result files.

`min_rules` is the same idea aimed at the rules rather than the binary. A
ruleset that failed to download is an empty ruleset, and an empty ruleset
passes everything at high speed. Declare how many rules must load and enumerate
them with `rules_command`.

**3 · It has been seen failing.**

Break the check on purpose, watch it go red, revert, and note what you broke.
A check never observed failing is decoration, and the decoration is
indistinguishable from the real thing until an incident.

For the shell linter in `templates/checks.yaml`, that evidence looks like this
— the same config, run against three scripts and then against the clean one:

```
### A. broken scripts present -> expect FAIL, exit 3
  FAIL      shell-lint         block  exit 1    ShellCheck ...  covered 3/3 files
             -> the check reported findings.
REFUSED: shell-lint (fail)
EXIT=3

### B. same config, only the clean script -> expect PASS, exit 0
  PASS      shell-lint         block  exit 0    ShellCheck ...  covered 1/1 files
PASS: every blocking check ran, covered what it declared, and found nothing.
EXIT=0
```

Do that for every check before you believe the stage. It is twenty minutes once
and it is the only thing that distinguishes this config from the one that
graded an empty directory at 100.

**4 · It is measured against a denominator it did not choose.**

The three properties above share one hole: **the check author declares what the
check is measured against.** `coverage` says what must have been examined, and
the person writing the check writes it. A check can shrink its own scope and
still pass honestly, because the thing it is measured against is the thing it
picked.

So the unit list comes from somewhere the check cannot edit. `policy.spec`
names the living spec; the runner enumerates every **active** requirement from
it — the `- **R7** — ...` bullets, minus anything the following line marks
superseded or withdrawn — and that set is the denominator. Each check then
declares `coverage.spec_units`: which requirements it verifies, and how.

| Verdict | Means | Who may write it |
|---|---|---|
| `Covered` | this check verifies the requirement | the check |
| `Partial` | part of it — say which part is missing | the check |
| `n/a` | vacuous by the spec itself; **`reason` required** | the check |
| `Missing` | nothing covered it | **the runner only** |

`Missing` is not claimable. It is the one verdict a check must not be able to
write about itself, because it is the verdict that refuses the run.

Three rules are lifted from the AI Unified Process, which arrived at the same
design from the other direction:

- **Every unit gets a row, the covered ones included.** A report listing only
  failures leaves the reader supplying their own denominator, which is the
  AgentShield failure relocated rather than fixed.
- **"Hard to test" is not `n/a`.** An `n/a` takes a requirement out of the
  denominator, so it states why in a line a reviewer can disagree with. An
  `n/a` with no `reason` is a config error, not a pass.
- **A disabled, skipped or todo check covers nothing.** A claim is a claim, not
  coverage. The runner binds each claim to the claiming check's own result: if
  the check is `enabled: false`, its tool is absent, it timed out, it failed or
  it came back hollow, the claim is voided and the unit returns to `Missing`.

Observed — one config, then the same config with a single unit deleted from the
check's own list, and nothing else changed:

```
### full list -> both units covered
  PASS      probe              block  exit 0    probe 1.0  covered 2/2 files
spec coverage: 2 active requirement(s) derived from .claude/productizer/spec.md - 2 Covered, 0 Partial, 0 Missing, 0 n/a
  COVERED  R1    The fixture shall name every file it read.
  COVERED  R2    The fixture shall refuse a file it could not open.
PASS: every blocking check ran, covered what it declared, and found nothing.
EXIT=0

### one line deleted from the check's own spec_units -> the unit does not leave with it
  PASS      probe              block  exit 0    probe 1.0  covered 2/2 files
spec coverage: 2 active requirement(s) derived from .claude/productizer/spec.md - 1 Covered, 0 Partial, 1 Missing, 0 n/a
  COVERED  R1    The fixture shall name every file it read.
  MISSING  R2    The fixture shall refuse a file it could not open.
             -> no check in this config names this requirement
REFUSED: 1 of 2 requirement(s) in .claude/productizer/spec.md are not covered: R2 (Missing).
The denominator is derived from the spec, not from what a check declared about itself.
EXIT=3
```

The check itself did not change. It ran, it covered both files, it exited 0.
The only edit was to the list it published about itself, and that list stopped
being what it is measured against.

A claim voided because the claiming check could not establish anything:

```
  DISABLED  probe-refusal      block  exit -    version unknown
             -> `enabled: false`. A disabled check covers nothing.
  MISSING  R2    The fixture shall refuse a file it could not open.
             -> probe-refusal claimed Covered but the check is disabled, and a disabled, skipped
                or todo check covers nothing
```

**A denominator that could not be computed is never rendered as zero.** An
unreadable spec, one with no requirements in it, or one that declares an id
twice comes back `UNMEASURED` and refuses:

```
spec coverage: UNMEASURED (unreadable). no spec at spec-missing.md, so the coverage denominator
could not be derived. Unmeasured, not zero.
REFUSED: ... A stage that cannot say what it was measured against does not get to report a pass.
EXIT=3

spec coverage: UNMEASURED (no_requirements). spec-empty.md holds no `- **R<n>** - ...` requirement
lines, so the coverage denominator could not be derived. Unmeasured, not zero.

spec coverage: UNMEASURED (unreadable). spec-dup.md declares R1 twice. Ids are permanent and unique,
so a duplicate means the denominator cannot be trusted. Unmeasured, not zero.
```

`units_total` and `counts` stay `null` in `checks-result.json` rather than `0`.
"0 units, all covered" is the same hollow green as a grade over one file out of
thirty-three, printed by a different part of the pipeline.

`policy.spec_coverage` decides when this is enforced:

| Value | Behaviour |
|---|---|
| `auto` (default) | measure as soon as any check declares `spec_units`; while none does, say `not_declared` out loud and do not refuse |
| `require` | always measure; a spec that cannot be read refuses the run, and so does any requirement no check names |
| `report` | always measure, never refuse. The line reads *declared but not enforced* |
| `"off"` | committed, visible opt-out. Quote it — YAML reads a bare `off` as the boolean false |

`auto` exists so that adding this file to a repo mid-adoption does not turn
every run red on day one. What it does not do is report silence as success:
with nothing declared the line reads *unmeasured, not covered*.

**What `require` refuses on, and why it is not "everything Covered".**

`require` used to refuse on `Partial` as well as `Missing`, which made it
unreachable rather than strict. Some obligations cannot be fully proven from
inside a repository at all. In this one: catching a guide sentence that
contradicts a requirement without naming its id needs reading rather than
matching, and `models.checks` forbids a model in this path; whether a downloaded
file lands only on the viewer's device is a fact about the publishing service;
the gate's refusal path needs a forbidden publish actually attempted; a
classification of `duplicate` or `contradict` merges nothing and so writes
nothing to find; and a requirement about an unreachable spec home cannot fire in
a repository whose spec home is reachable. Demanding `Covered` for those demands
a proof that does not exist, and a gate that cannot be satisfied is one somebody
switches off.

So the bar is **nothing may be silently unproven**. `Missing` refuses — no check
names the requirement. A `Partial` is accepted, and what earns it that is the
`reason`: the loader refuses to load a `Partial` without one, so every partial
claim has already said which part is unasserted, in the run's own output, where
a reader can disagree with it.

That guards the failure this stage actually has. A check claiming more than it
proves, or vanishing, lands as `Missing` or as a claim voided by a check that
did not run — and both still refuse.

**`auto` has no middle, which is why `report` exists.** Enforcement under `auto`
is all-or-nothing: the FIRST check to declare a `spec_units` claim turns it on
for the whole spec. A repo adopting this incrementally therefore goes from green
to refusing every run the moment it records its first honest piece of coverage,
which punishes exactly the act the mode is meant to encourage. This repo did it
to itself — four claims, and every run refused on the twenty-one requirements
nobody had mapped yet.

The two obvious ways out are both worse. Deleting the claims destroys a real
record to dodge a verdict. Narrowing the denominator to what checks happen to
claim is the hollow pass this whole stage exists to prevent — a spec of one
requirement, fully covered.

So `report` changes the **verdict** and never the **measurement**. The
denominator still comes from the spec, every uncovered requirement is still
named, and the line says *declared but not enforced* so nobody reads the run as
clean coverage. It is a committed, visible statement that the mapping is
unfinished. Moving to `require` should be the LAST step of adoption, not the
first: flipping it early refuses every run, and a stage that always refuses is a
stage everybody learns to ignore.

### How the runner fails closed

Fifteen ways a check can look green without being green, and what happens
instead:

| Situation | Naive result | Here |
|---|---|---|
| the config will not parse | partially honoured, some checks dropped | exit 2, nothing runs |
| a declared tool is not installed | skipped, run still green | `missing_tool`, the check fails |
| a check hangs | the job is killed, or waits forever | `timeout`, the check fails |
| the tool returns an exit code nobody mapped | treated as success | `unmapped_exit`, the check fails |
| the tool exits 0 having examined nothing | `PASS` | `hollow`, the check fails |
| no declared check matches the change | green, no checks ran | refused, unless `policy.empty_run: pass` |
| a check quietly shrinks what it claims to cover | green, the check chose its own denominator | the unit is `Missing`, the run refuses |
| the spec cannot be read, or holds no requirements | "0 units, all covered" | `UNMEASURED`, `units_total: null`, refused |
| a disabled or skipped check claims a requirement | the requirement reads as covered | the claim is voided, the unit is `Missing` |
| `n/a` asserted with no reason given | a requirement silently leaves the denominator | exit 2, the config does not load |
| every check is `enabled: false` | exit 0, nothing verified | exit 2, the config refuses to load |
| a local settings file loosens a team-level setting | honoured, and invisible to everyone else | ignored, with a warning naming the setting |
| an advisory check could not run at all | advisory, the run stays green | it blocks: `advise` softens findings, not absence |
| the runner anchors relative paths to the config's own directory | a present tool reads as `missing_tool`; output lands in a nested shadow | the root is the git work tree, printed on every run |
| the runner is started from a subdirectory | `no config at ...`, or a change list that "does not exist" | the default config and the change list are found under the repository root |

Observed, all in one run:

```
  MISSING_TOOL missing-tool       block  exit -    version unknown
             -> declared tool not installed: gitleaks. Not skipped — a check whose tool is absent is a check that did not run.
  TIMEOUT   slow-scan          block  exit 124  sleep 1.0  covered 0
             -> hit the 3s limit. A killed scanner has no verdict; it is not a pass.
  UNMAPPED_EXIT unmapped           block  exit 42   sh 1.0  covered 5
             -> exit 42 is not described in `exit_codes`. An exit code the config does not recognise is treated as a failure: tools add codes between releases.
  HOLLOW    advisory-hollow    advise exit 0    version unknown  covered 0
             -> exited 0 but examined 0, which is below the declared minimum of 1. A check that examined nothing is a failure, not a pass.
```

`policy.empty_run: refuse` is the least obvious of the fifteen and the one that
catches the most. A change nothing checks is not a clean change; it is a change
the config does not describe. The `pass` setting exists so a repo mid-adoption
can opt out of that deliberately, in a committed line someone approved, rather
than by accident.

One more, which the runner reports but cannot fix: a check whose exit code says
*findings* and whose coverage says *nothing examined*. Fixing the finding would
turn that red into a hollow green, so the runner says both in the same line
rather than waiting for the next run to surprise someone.


## Waivers: a person overriding a failing check

Sometimes a real finding is accepted — a known issue with a ticket, a
third-party dependency nobody can patch this week. R37 and R38 say what happens
then, and between them they say the interesting half:

- **R37** — the override is recorded in a file naming the check, the authority
  and the reason.
- **R38** — while it is overridden, the check is rendered as **failed and
  waived**, and never as passed.

### A waiver never changes the measurement

`status` stays `fail`. The findings stay in the result. The coverage numbers
stay. What a waiver changes is exactly two things: whether the run **blocks**,
and how the line **reads**.

```
  FAIL · WAIVED BY A. Maintainer finding   block  exit 1   grep 2.6.0  covered 1/1 files
             -> the check reported findings. WAIVED BY A. Maintainer until 2999-01-01
                (waivers/valid/W1-finding.md): this check does not block, and it did not
                pass - it is still `fail`, and its findings above are unchanged.
waivers: 1 file(s) read from waivers/valid, 1 honoured (today is 2026-09-02)
  HONOURED       waivers/valid/W1-finding.md
PASS: 1 blocking check(s) FAILED and are waived by a person, not by a measurement -
each is still recorded `fail` above. Everything else ran and covered what it declared.
EXIT=0
```

P1 is the whole reason. An overridden check **was** measured, so recording the
override is honest — but a failure rendered green because somebody said so is a
judgment wearing a measurement's clothes, and a month later it reads exactly
like a check that passed. A waiver implemented as "set the status to pass"
satisfies every casual reading of R38 and produces precisely the hollow green
this stage exists to refuse.

### It is off until someone says otherwise, and that is P4

Waiver files live in the repository being examined. A repository that could
waive its own blocking checks would arrive on your machine with them already
disarmed — which is P4, *a repository being examined never chooses what runs*,
failing at the gate rather than at the tool.

So the directory is read only when `checks.yaml` says to read it:

```yaml
policy:
  waivers: .claude/productizer/waivers
```

With no such key nothing is opened, so a clone carrying a `waivers/` directory
waives nothing. Turning it on is one line in the committed config — the same
shape and the same reasoning as `policy.allow_repo_local_tools` — and like
every `policy` key it cannot be turned on from a `checks.local.yaml`.

Three further bounds, none of which is the load-bearing one but each of which
closes a way the first could be walked around:

- **A waiver selects nothing.** No executable, no path, no argv. Its `Check:`
  value is only ever compared against the ids the committed config declares. It
  can narrow what blocks by exactly one already-measured failure; it can never
  widen what runs.
- **It expires.** `Expires:` is required. An unbounded waiver outlives the
  person who wrote it and the finding it was written for.
- **The authority is a label, not a credential.** It is untrusted repository
  text: collapsed to one printable line, truncated, rendered — never executed,
  never resolved as a path, never read as an instruction. It names who to ask.
  What authorises the override is the reviewed commit that added the file,
  which is why the run reports the waiver's **location**. `Reason:` is never
  echoed anywhere; only whether one is recorded.

The residue is stated rather than hidden: someone who can land a commit in a
repo that has already opted in can waive that repo's own failing check until
the expiry. That is the same power as editing `checks.yaml`, it is visible in
the diff and in every run's output, and it is bounded by a date.

### What cannot be waived, and how each one reads

Every waiver file is reported, honoured or not — a waiver that has quietly
stopped applying is the one worth seeing, because it is the difference between
"nobody waived this" and "somebody meant to, and it lapsed".

| Situation | Reported as | Why |
|---|---|---|
| the check failed and the waiver is well-formed and live | `honoured` | the only case that softens anything |
| `Check`, `Authority`, `Reason` or `Expires` is absent | `malformed`, naming the field | R37 requires all three; the runner adds the fourth |
| `Expires` has passed | `expired`, with the date | the check blocks again |
| `Check` names nothing this config declares | `unknown_check` | it matched nothing, so it waives nothing. The unrecognised id is **not** quoted back — it is a stranger's text |
| the check passed, is disabled, was not triggered, or is `advise` | `not_applicable`, naming the status | there is no finding to override |
| the check could not run — `missing_tool`, `timeout`, `no_version`, `refused`, `unmapped_exit` — or came back `hollow` | `not_applicable`, naming the status | these are **absences** of measurement, and a person cannot decide an absence away. This is the same line `advise` is already held to |
| two waivers name one check | `duplicate` | two authorities over one check is not an override; neither is honoured |

`templates/waiver.md` is the file format.

### A waiver does not waive the spec

The waived check is still `fail`, so every `coverage.spec_units` claim it made
is still voided and the requirement goes back to `Missing`. Under
`policy.spec_coverage: require` the run therefore still refuses — on the
**denominator**, not on the check.

That is deliberate and it is not a rough edge to be smoothed. A waiver is a
decision about one finding. It is not a statement that the requirement is
verified, and the coverage report is the one place that must never say
otherwise.

### Testing this class of bug

`scripts/check-waiver-rendering.sh` drives `fixtures/waiver-rendering/` through
the real runner, ten cases, one run and one verdict each — never one run
holding ten checks, because a single run refuses if *any* check refuses and a
regressed case would ride a neighbour's refusal to a green assertion. Eight
assertions per case, counted one by one and reported per case, so a tally says
which behaviour regressed rather than only that something did.

The pair that matters is `waived` and `unwaived`: the same failing check over
the same file with the same waiver file present on disk, one line of config
apart. A check asserting only the waived direction stays green against a runner
that honours every waiver it finds; one asserting only the unwaived direction
stays green against a runner that has stopped honouring waivers at all.

Falsified against the defect it exists for. With the honoured branch changed to
also write `status = "pass"`, the `waived` case drops to 7 of 8 and the run
exits 1; with `policy.waivers` given a default, `unwaived` drops to 1 of 8; with
the expiry comparison removed, `expired` drops to 1 of 8; with `Reason` dropped
from the required fields, `no-reason` drops to 1 of 8; with the duplicate guard
removed, `duplicate` drops to 1 of 8 — and the run then honours the first of the
two waivers and marks the second `not_applicable`, silently. Each break was
reverted and the suite returned to 8/8 on all ten.

## Suppressed stderr

`2>/dev/null` is scanner theatre one level down, inside the tools themselves.
Throw stderr away and an ERROR and a genuine NO-MATCH become the same bytes -
none - so the run is green either way, and every rule above about a hollow
check being a failure is defeated by a redirection nobody reads.

It is not hypothetical here. In one session in this repo it hid three real
defects: a count that was wrong, an absence that was not an absence, and a
check that examined nothing and reported a pass. Same cause, three times.

`check-stderr.sh` refuses, on a line of shell: stderr sent to `/dev/null`,
stderr closed with `2>&-`, both streams binned with `&>/dev/null` or
`>&/dev/null`, and `>/dev/null 2>&1`. It deliberately does **not** refuse a
bare `>/dev/null`: binning stdout says nothing about errors, and stderr still
reaches the log and the caller.

### The exemptions are the hard part

There are legitimate uses, and a rule with no way out gets deleted. So there
are exactly three ways past this check, and two of them cost a sentence:

1. **`command -v x >/dev/null 2>&1`** is exempt structurally, with no entry
   anywhere. It is an existence TEST: the answer is the exit status, and the
   only thing on stderr is "not found" noise about a question already answered.
   This is the *only* structural exemption. Adding more would train people to
   stop reading them.
2. **Inline, for code you own.** `# stderr-ok: <reason>` on the offending line.
3. **An allowlist entry, for code you do not own** - a vendored script, or a
   file another owner is holding. `--allow 'FILE::SNIPPET::REASON'`, passed as
   arguments so the exemptions live in the committed `checks.yaml` beside the
   check that grants them, and are reviewed in the same diff as the code.

**An exemption with no reason is REFUSED - exit 2, not a finding and certainly
not a pass.** A reason under 12 characters is refused the same way. So is an
allowlist snippet that does not itself quote the redirection: a snippet naming
only the surrounding code would exempt that whole line forever, including a
suppression added to it next year. Every occurrence of the snippet is cut out
of the line and what remains is scanned again, so an entry can only ever excuse
the exact redirection it quotes.

That last rule is not theoretical either. The first draft split
`FILE::SNIPPET::REASON` on the *first* separator, which silently ate the
trailing colon of `2>/dev/null || :` and widened the snippet to
`2>/dev/null || ` - an entry that then exempted a `curl ... 2>/dev/null` added
to the same line. A fixture caught it; the split is on the last separator now,
and the cost is that a reason may not contain `::`.

### Observed

```
### R. six spellings of a suppression, one file -> six findings, exit 1
    caught.sh:3: stderr suppressed. ...      # 2>/dev/null
    caught.sh:4: ...                         # 2> /dev/null
    caught.sh:5: ...                         # 2>&-
    caught.sh:6: ...                         # &>/dev/null
    caught.sh:7: ...                         # >& /dev/null
    caught.sh:8: ...                         # >/dev/null 2>&1
exit=1

### S. four `command -v` probes and a bare >/dev/null -> exit 0
exit=0
### S (positive control). the same file with one real suppression appended
    legit-probe.sh:10: stderr suppressed. ...
exit=1

### T. an allowlist entry WITH a reason -> exit 0
### T (no reason) -> check-stderr: allow entry for ... carries no reason.
    An exemption with no reason is refused, not honoured.  exit=2
### T (snippet quotes no redirection) -> ... which contains no stderr
    redirection. ... Refused.  exit=2
```

### Start it advisory, and diarise the promotion

Run it once before you set `block`. The first run in this repo found **66
occurrences across 8 of 28 shell scripts** - not the 13 anyone expected.
Blocking on day one would have turned the rollout into an argument about the
rule instead of a list of the debt, and a rule people argue with gets switched
off. It ships `advise`, it reports every occurrence into the review brief, and
the count is printed on every run, so the day to promote it to `block` is a
number rather than a judgement call.

### Known limitation

A line whose first non-blank character is `#` is skipped, because a comment
cannot redirect anything. A here-doc that writes a file in a language where `#`
is not a comment could therefore hide a suppression on such a line. No such
case exists in this repo. It is a hole, and it is written down rather than
discovered later.

## One living spec per product

The spec says the lifecycle shall hold exactly one living spec per product.
Until `check-spec-home.sh` existed, nothing asserted it: `product.spec_home`
was declared in `config.json` and never read back, by any script, any hook, or
any of the spec validator's codes. A second `.claude/productizer/spec.md` in a
second repo would have gone unnoticed - two allocators both handing out R42,
two specs both believed, and the divergence found later by whoever trusted the
wrong one.

The check reads `product.spec_home` and `product.repos` out of the config and
asks every repo in the product one question: do you hold the file named by
`spec.path`?

| Answer | Verdict |
|---|---|
| exactly one, and it is the declared home | pass, exit 0 |
| exactly one, but not the declared home | fail, exit 1 - the declaration is a lie and downstream tooling believes it |
| two or more | fail, exit 1 |
| none, every repo reached | fail, exit 1 - a MEASURED zero |
| any repo out of reach | **refused, exit 2** |

It is declared `always`, because this failure does not arrive in a diff. A repo
joins the product, or someone scaffolds a spec in the wrong place, and no file
in this repo changes at all.

### Unreachable is not absent, and that is the whole point

A repo the check cannot open is not a repo with no spec in it. Counting it as
"no spec there" is exactly how a two-spec product reports as a one-spec
product: the second spec is in the repo nobody could reach. So an unreachable
repo is named, with the reason it could not be reached, and the run refuses -
distinct from both pass and fail, and never folded into the count in either
direction.

Observed, on the same fixture product, changing only whether one repo could be
reached:

```
### U. three repos, one with no checkout anywhere
  acme/delta      unreachable  no local checkout found; pass --repo acme/delta=PATH, or --remote
repos declared: 3 / repos reachable: 2 / repos unreachable: 1 / specs found: 1
REFUSED: 1 of 3 repos could not be reached, so the number of living specs is
UNKNOWN - not zero, and not one. A repo nobody could open is where a second
spec hides.
exit=2

### V. the same delta, now mapped to a real checkout that holds no spec
  acme/delta      absent       .../product/delta (--repo mapping)
repos declared: 3 / repos reachable: 3 / repos unreachable: 0 / specs found: 1
PASS: exactly one living spec, in the declared home acme/alpha.
exit=0
```

Same repo, two different sentences, three fields apart. A config that cannot be
read, a config with no `product.repos`, and a config whose JSON does not parse
are all exit 2 for the same reason: a product nobody can enumerate is not a
product with zero repos.

The one ordering rule: two specs already found is a definite answer, so it fails
(1) even when a third repo was unreachable. Unreachability only refuses when it
could still change the verdict.

### Reaching the other repos

In order: an explicit `--repo owner/name=PATH`; the repo the check is running
in, when `github.repo` names it; a working directory whose basename matches; a
sibling checkout holding a `.git` or `.claude`. Nothing matched means
unreachable - never absent.

`--remote` adds a last resort: the GitHub contents API via `gh`. It is **off by
default**, because a check that reaches the network is not deterministic, and a
rate limit or an expired token would read as an outage rather than a verdict.
Even with it on, only an HTTP 404 counts as an answer; every other failure is
unreachable.

## Adding a check

1. Write it in `checks.yaml` with an argv `command` — never a string. This file
   is committed, so a string handed to a shell lets anyone who lands a commit
   choose what runs on the machine of whoever pulls it. The runner refuses one.
2. Scope it. `always` for anything that can hide in any file type; `paths` for
   a language or a directory; `tags` for a class of requirement.
3. Map its exit codes from the vendor's documentation, and confirm them against
   the build you actually have. Separate *findings* from *the tool refused to
   run*: reporting a crash as a finding sends someone to fix code that was
   never the problem.
4. Declare its coverage, preferring `per_file_exit`.
5. Name the requirements it verifies in `coverage.spec_units`, one entry per id,
   with `Covered`, `Partial`, or `n/a` **and a reason**. Ids come from the spec;
   the runner refuses a claim against an id the spec does not list as active.
6. Give it a `version_command`. Blocking checks are refused without one.
7. Break it. Watch it go red. Revert. Note what you broke in the pull request.
8. Start it at `advise` if you expect argument, and diarise the promotion.
   Note that `advise` softens its findings only — an advisory check whose tool
   is missing still blocks.

## What this stage does not do

- **It does not judge whether the declared checks are the right ones.** It
  polices two things and no more: each check covers what it declared, and every
  active requirement in the spec has some check claiming it. A config whose
  checks are individually weak still passes both. `Covered` remains a claim the
  runner can only bind to the claiming check's own result — it cannot read the
  check's body and tell you the assertion inside is trivial. Review the file the
  way you would review an access-control list, on a schedule, and ask what is
  absent rather than whether the present ones passed.
- **It does not sandbox the tools it runs.** Everything in `checks.yaml`
  executes with the runner's privileges. That is why the config is argv-only,
  reviewed like code, and denied to the agent.
- **It does not decide whether a waiver was deserved.** It enforces the shape —
  four recorded fields, a live expiry, a declared check, an actual failure to
  override — and it renders the result where nobody can miss it. Whether the
  named authority should have signed it is a human's call, read in the diff
  that added the file.
- **It does not replace hooks.** A hook is deterministic and fires on every tool
  call; this stage runs once per change. Protected paths and formatting stay in
  hooks (`templates/hooks-settings.json`). Heavy scanners belong here.
- **It does not survive a tool that daemonises.** A timeout kills the check's
  process group. Something that escapes that group outlives the run.
- **It is not a substitute for the review.** It narrows what a reviewer has to
  hold in their head. Every finding it reports is still a human's call, and
  everything it does not know to look for is entirely theirs.
