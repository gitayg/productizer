# Import — adopting a codebase that already exists

The rest of this skill assumes a repo starts with an empty spec and accretes
requirements one intent at a time. Almost no repo is in that state. The ordinary
case is six hundred commits, no spec, and nobody left who can say why half of it
is the way it is.

Import is the bridge: from an existing codebase to a living spec that describes
what it already does, so change tracking can start from today rather than from a
rewrite. It runs once per product, as **Stage 0c**, after Stage 0a has scaffolded
the empty spec and before the first intake.

Prompt: `templates/import.md`. Survey: `scripts/import-survey.sh`.

## The thing that makes this hard

Extraction is not the hard part. Reading routes and test names out of a repo is
mechanical, and the survey does it in under a second.

The hard part is that **a requirement reverse-engineered from code is a
description of behaviour, not an agreed decision.** Nobody ratified it. Some of
it describes bugs. Some of it describes behaviour three people have been quietly
working around for a year.

Write those sentences into the spec as though they were agreed and three things
break at once, none of them visibly:

- **The audit trail becomes fiction.** The spec's whole claim is that
  `git log -p .claude/productizer/spec.md` is a history of decisions. An import that
  writes two hundred requirements in one commit makes the first and largest entry
  in that history a record of nothing having been decided.
- **The contradiction halt starts defending accidents.** Stage 2 stops the work
  when an intent conflicts with an active requirement, and that stop is expensive
  and correct — precisely because an active requirement means somebody agreed.
  Point it at an imported bug and the process now blocks the fix, with the
  authority of a decision nobody made.
- **Every downstream citation inherits the confidence.** Plans cite ids, tests
  cite ids, review findings cite ids. A requirement gets more solid the more it
  is referenced, and none of those references re-check where it came from.

So the design question is not how to extract more. It is how to keep imported
requirements permanently distinguishable from agreed ones until somebody looks.

## The mechanism: an inferred status that cannot halt

Imported requirements land as **inferred** and become active only when a human
confirms them.

An inferred requirement is a normal EARS sentence with a marker line beneath it,
in the same position `templates/spec.md` already puts `Superseded by R0.` and
`Withdrawn.`:

```
- **R8** — When a client requests an app icon, the `crane` server shall send a
  publicly cacheable response.
  Inferred from test `app icons stay cacheable — public, unchanging, fetched
  constantly` (`test/api-cache-control.test.js`). Unconfirmed.
```

Four properties follow from that, and they are the whole design:

1. **It carries its provenance.** Anyone reading the requirement, or a plan
   citing it, can reach the evidence in one hop. A requirement whose citation no
   longer resolves is a requirement to re-check, and that is now visible.
2. **It cannot stop work.** Only active requirements trigger the Stage 2
   contradiction halt. A conflict with an inferred requirement is downgraded to
   the confirmation question — *the code does X today; is X intended?* — which is
   the question that needed asking anyway. This is the single rule that stops the
   lifecycle defending imported accidents.
3. **It is not counted as verified.** Inferred requirements get no acceptance
   criteria row. The comparison between active requirements and criteria rows is
   what answers "do the tests assert the criteria", and inferred rows would
   inflate that answer with behaviour nobody agreed to test.
4. **Promotion is a commit.** Confirming a requirement deletes one line and adds
   a criteria row and a decision-record entry. The spec diff then names which
   sentences a specific person ratified on a specific day — which is the audit
   trail the lifecycle claims to sell, now genuinely earned rather than asserted.

### Alternatives considered, and why they lose

**A separate provisional id space (`I1`, `I2`), promoted to `R` ids.** Cleaner
looking, and fatal: promotion would have to renumber, and renumbering silently
redirects every citation made in the meantime. Ids are never renumbered is the
one absolute rule in `references/ears.md`, and this would break it on a schedule.
Inferred requirements therefore take real ids from the normal counter, and a
rejected one is withdrawn with its id spent. Spending an id on a rejected
inference is a real cost and the right one.

**A separate file — `spec.inferred.md` — merged on confirmation.** Splits the id
allocator, which is the mistake the products-and-repos section already refuses
for the same reason. Two allocators eventually hand out the same number.

**Import nothing; let intake discover the spec over time.** Honest, and it is
what happens today by default. It fails because the first intake has nothing to
classify against, so every early intent classifies as *extend*, and the
contradiction detection — the only reason the living spec earns its cost — does
not start working until the spec has accidentally caught up with the code, which
takes years.

**Import everything and mark the whole spec provisional at the header.** A file-
level caveat is read once and then never again, while ids are cited forever. The
status has to travel with the requirement.

## Two strengths inside `inferred`

`inferred` answers *has anybody agreed to this?* It does not answer *how good is
the evidence?*, and those are different questions with different consequences.

A requirement read from a route plus a test that exercises it, and a requirement
read from a bullet in a README, are both unagreed. They are not both equally
likely to be **true**. Once they are written in the same form, the person doing
the ratification cannot tell them apart, and ratifying the second is a much
larger act than ratifying the first — they are being asked to vouch for a
sentence nothing has ever checked.

So `inferred` carries a strength, written into the marker line:

```
- **R7** — When an authenticated platform administrator requests
  `GET /api/version-check`, the `crane` server shall return the available
  release version.
  Inferred from `server/index.js:462`. Unconfirmed.

- **R9** — When an order is placed after 16:00, the `northwind` dispatcher shall
  ship it the following day.
  Inferred (weak evidence) from `notes/dispatch.md` heading "Cut-off".
  Unconfirmed. No code, test or config in this repo asserts this.
```

Strength is a property of the evidence, not a confidence someone chose. The
survey measures it and the Verdict names it:

- **strong** — behaviour the code states to a machine: a declared entry point, a
  route or RPC handler, a CLI subcommand or flag, an exported symbol, a config
  key the code reads or declares, a test name, an error path.
- **weak** — what the repo says about itself: README and doc headings, CI job and
  step names, the inventory of skills and scripts, change history.

Why the marker and not a separate section, a separate file, or a header caveat:
all three were already rejected above for the `inferred` status itself, for
reasons that apply unchanged here. A caveat is read once; ids are cited forever.

### Why the refusal became a fork

The survey used to tally strong evidence only, and stop below the threshold. The
refusal was correct about the evidence and wrong about what to do with it: it
threw away every weak source it had already collected.

Measured, on this product's own repository, before the change:

```
behaviour sections     routes 2, test names 0, error paths 0, entry points 0
collected and discarded  Existing docs 60, Doc headings 18, Change history 20,
                         CI and gates 2
verdict                NOT ENOUGH EVIDENCE TO DRAFT A SPEC.
```

A hundred lines of real evidence, discarded, on the repository of the tool doing
the discarding. Two things were wrong and only one of them was the threshold —
the probes also recognised nothing but HTTP services, so a product made of
scripts and skills had no surface the survey could see. Both are fixed: the
probes widened (below), and the threshold became a fork.

The fork has three outcomes and the Verdict prints exactly one of them, above a
per-section tally showing the numbers that produced it:

| Verdict | Condition | Meaning |
|---|---|---|
| `DRAFT TIER: STRONG` | strong ≥ 8 | Draft as normal, up to 30, code citations. |
| `DRAFT TIER: WEAK` | strong < 8 and weak ≥ 6 | Draft up to 10, every one marked `(weak evidence)`, and report the strong-tier gap as the headline finding. |
| `NOT ENOUGH EVIDENCE` | both under floor | Refuse. Ask for the entry points by hand. |

**The bottom is still reachable and still means what it said.** A directory with
no README worth reading, no CI, no doc headings and no history is not a project
that describes itself, and the survey refuses there exactly as it did before.
Adding a second tier below the first would have quietly removed the refusal, and
a survey that always finds something to draft from is a survey that has stopped
being evidence.

**The weak tier does not soften the strong one.** The two tallies are separate
counters; no weak line can push a strong total over its floor, and the Verdict
prints both numbers with both floors whichever way it went. The failure this
guards against is not drafting from weak evidence — that is the point of the tier
— it is drafting from weak evidence and describing it as strong.

## The procedure

1. **Bind and scaffold first** (Stages 0 and 0a). Import writes into an existing
   empty spec; it does not create one.
2. **Run the survey.** `scripts/import-survey.sh <repo-path>`. Read all of it.
3. **Name the system**, once, from the manifest or entry point.
4. **Draft up to thirty inferred requirements**, in the order
   `templates/import.md` sets: test names, then observable surface, then error
   paths, then config-gated behaviour. Every one carries a citation.
5. **Write the refusals down as gaps**, in the same pass - the same commit as
   the draft. The list of what could not be inferred is worth more than the
   draft, because it is the list of questions only a person can answer. Write
   each gap as a backlog row whose item opens with the stage -
   `| B<n> | Stage 0c could not infer ... |`. Only a row of that shape, written
   new in the commit that drafted the requirements, counts as a record of the
   import (`check-import-marking.sh` 1.3); prose that mentions the stage, or a
   row appended or edited later, does not.
6. **Raise contested behaviour under *Areas of concern***, not as a corrected
   requirement.
7. **Confirm in batches of about ten**, in the session, by id.
8. **Record the import as one change-log row**, and each ratification batch in
   the decision record.

Steps 4 to 8 are one round. A large system gets several, scoped by area, spaced
by whatever pace a human can genuinely review at.

## The survey script

`scripts/import-survey.sh [repo-path]` gathers the evidence and nothing else. It
emits a plain-text report: languages, manifests, declared and inferred entry
points, **CLI surface**, **public API**, HTTP routes and RPC handlers, file-based
routes, config and feature flag reads, **declared config schema keys**, config
files, test files, test names, error paths, docs and doc headings, CI and gate
files, **CI job and step names**, the **skill and script inventory**, and change
history. Each section declares which tier it feeds, and the Verdict prints the
per-section tally it decided on.

### The probes that are not about HTTP

Four of the five sections in bold above were added because the survey could
describe a web service and almost nothing else. A product whose entire surface is
a command-line tool, a library, a set of skills or a pile of scripts produced an
empty behaviour tally and a refusal, and the refusal read as *this repo has no
behaviour* when it meant *this survey only knows how to look for routes*.

- **CLI surface** (strong). `argparse` / `click` / `typer`; `commander`, `yargs`,
  `process.argv`; `cobra` and the Go `flag` package; `clap`; and, for shell, a
  `usage()` function, a `Usage:` banner and the `case` branches that dispatch
  subcommands and flags. A subcommand is the same kind of claim as a route: a
  caller depends on the name.
- **Public API** (strong). Exported symbols — `export` and `module.exports`,
  module-level `def` and `class`, exported Go funcs and types, `pub` items, public
  Java and Kotlin declarations, Ruby modules and `def self.` — plus `bin`,
  `exports`, `main` in `package.json` and `console_scripts` / `[project.scripts]`
  in Python packaging. Lines already reported under *Entry points — declared* are
  filtered out before this section is counted, because a `bin` map is one
  committed decision and counting it twice is how a survey talks itself into
  confidence it did not earn.
- **Config schema keys** (strong). The declared setting *names* in `config.json`,
  `settings.yaml`, a `*.config.toml` and the like. Names only, and enforced
  twice: every line is rewritten to drop everything right of the key, and any line
  that did not survive that rewrite is dropped rather than printed. A config file
  that is not a `.env` can still hold a token, and this report gets pasted into
  chats.
- **CI job and step names** (weak). Workflow job ids, `name:`, `needs:`,
  `runs-on:`, `uses:`, and GitLab stages. A job name is a statement of what must
  hold before a change ships. It is weak because it is a string somebody typed:
  a job called `test` proves a job called `test` exists and nothing about what it
  asserts. The pattern deliberately does not match generic `key: value`, because a
  workflow `env:` block holds literal values.
- **Skill and script inventory** (weak). `SKILL.md` files and their `name` /
  `description` frontmatter, plugin manifests, and the scripts under `scripts/`,
  `bin/` and `hooks/`. For a repo whose product *is* its documents and scripts,
  this is the closest thing it has to a surface. The scripts' own `usage()` text
  is not repeated here — it is reported at strong tier under *CLI surface*, and
  repeating it would inflate the weak tally with lines already counted.

One exclusion had to be narrowed for the two code-surface probes. The shared
test-path filter treats any directory called `spec` or `specs` as a test tree,
which is right for RSpec and wrong for a Claude plugin, whose skill lives in
`skills/spec/`. On this product's own repository that one pattern hid every
script's command-line surface from the survey written to find it. The two new
probes therefore use a variant that anchors bare `spec/` to the repo root, so the
RSpec layout is still excluded and a nested skill directory is not; every
pre-existing section keeps the exact filter it was tuned with, and their output
is unchanged.

Design constraints it holds to:

- **It never writes to the surveyed repo.** Temp files live under `TMPDIR` and
  are removed on exit. Verified by comparing modification times across a run.
- **Its help text describes itself, and is printed by itself.** `--help` and `-h`
  print the usage and exit 0; an unknown option or a second path is refused by
  name and exits 2; an unenterable path exits 1. This is not housekeeping. Before
  it, `--help` had no handler at all: the flag fell through to the repo-path
  variable and into `cd`, which recognised it as its own builtin option and
  printed bash's `cd` help — a complete and correct description of an entirely
  different program, advertising `-L`, `-P` and `-@` as options of this survey,
  at exit 0. Help text that lies is worse than absent help text, because the
  reader stops looking. The usage lives in a `usage()` function inside the script
  rather than in a comment, so the thing that drifts and the thing that prints
  are the same thing.
- **It never executes anything from the repo.** A `package.json` script and a
  `Makefile` target are quoted as text, never run.
- **A value that could not be measured is never rendered as zero.** A probe that
  ran and found nothing prints `(none found)` and tallies 0. A probe that could
  not run at all — the git history on an unreadable checkout — is marked
  `unavailable` and its line count prints as `--` in the Verdict tally, never as
  a number. The two are different facts about the repo and the report has to keep
  them apart, because 0 invites the reader to conclude the thing is absent.
- **It degrades silently.** Every probe prints `(none found)` rather than
  failing. A repo with no tests, no routes and no readable git is a normal input.
  Git being unreadable — a sandboxed path, an export, a bare checkout — removes
  the churn signal and nothing else, and is reported as a line rather than an
  abort. This is not hypothetical: one of the two repos it was developed against
  returns `fatal: unable to access '.git/config': Operation not permitted`.
- **It is bounded.** Vendor, build and VCS directories are pruned; the file list
  is capped; each section is capped; each file gets a quota within a section, so
  one large router cannot spend the whole budget and leave the survey describing
  a corner of the repo as though it were the repo. Where a cap bit, the section
  says `(truncated at N)`. Both development repos survey in under a second.
- **Live secret files never enter the file list** — `.env`, keys, certificates,
  `*.local`. `.env.example` is kept deliberately, and its values are redacted to
  the key names. A survey that quotes the right-hand side of a dotenv line has
  copied a secret into a report that gets pasted into a chat.
- **Repo content cannot forge structure.** Every evidence line is indented, so
  only the script's own headers start at column 0; paths containing control
  characters are dropped before any probe sees them, and the header reports how
  many of the files found were actually scanned. A file whose contents read
  `## Requirements` cannot impersonate a section in a report the agent reads as
  structure.

## What this will get wrong

Concretely, not as a disclaimer.

**The survey**

- **Test names are trusted more than they deserve.** A test named
  *"rejects expired tokens"* that asserts nothing still reads as intent. The
  survey reports names, never assertions, and a skipped or vacuous test looks
  identical to a passing one.
- **Route lists are declarations, not the surface.** A mounted router shows
  where it is mounted, not what it exposes; middleware ordering, auth wrappers
  and dynamic registration are invisible. Routes built by string concatenation or
  registered in a loop do not appear at all.
- **Regex extraction produces false positives.** A file named
  `server/routes/config.js` is listed under config files because it matches on
  name; `process.env[m[1]]` yields a config hit with no name in it. Read the
  citation, not the count.
- **The widened probes are wider, not complete.** Observed firing, each on a real
  repository or on a fixture built for it: the shell, Python, JavaScript, Go
  (cobra and stdlib `flag`) and Rust (clap) CLI probes; the JavaScript, Python,
  Go, Rust, Java and Ruby export probes and the `package.json` / `pyproject.toml`
  declarations; the JSON and TOML config-key probes; the GitHub Actions job
  probe; and the skill and script inventory. **Not observed firing, and therefore
  unverified:** the YAML and INI config-key probes, and the GitLab, Azure,
  Jenkins and CircleCI job probes. An unverified probe returning nothing is not
  evidence of absence, and the Verdict tally is the place to check which probes
  contributed anything at all.
- **A CLI probe reports the parser, not the interface.** Subcommands assembled in
  a loop, dispatched through a lookup table, or generated from a manifest do not
  appear. A repo can plainly have twenty subcommands and show three.
- **An exported symbol is not a public API.** Python has no access control, so
  every module-level `def` is reported; a Go exported func in an internal package
  is exported and private at once. The section over-reports on purpose, and the
  per-file quota is what stops one large module spending the whole cap.
- **Config schema keys are names in a file, not settings the code reads.** A key
  in a template nobody loads looks identical to one the product depends on, and
  the survey cannot tell a schema from an example.
- **Framework coverage is a list, not a rule.** Express-shaped JavaScript,
  Flask/FastAPI/Django, Go router methods, Spring annotations, Rails routes,
  Tauri commands and the MCP SDK's `server.tool` / `addTool` shapes are
  recognised. Anything else — gRPC service definitions, GraphQL schemas,
  message-queue consumers, cron entries, serverless handler manifests — is missed
  silently, and a missed transport looks exactly like a system that does not have
  one. Worse, a covered framework can still be missed: a repo that builds its MCP
  tool catalogue dynamically rather than calling `server.tool` produces an empty
  handler section while plainly having handlers. Of the probes here, only the
  JavaScript, Rust and attribute-following ones have been exercised against a
  real repo; the Python, Go, Java, Ruby and MCP probes are unverified, and an
  unverified probe returning nothing is not evidence of absence.
- **Build output that shadows source is counted twice.** A `dist`-like directory
  under a name not on the prune list produces a duplicate of every finding.
- **Pruning by directory name over-prunes.** A legitimate source directory named
  `build`, `out`, `target` or `vendor` is skipped entirely.
- **Churn is not importance.** The most-changed files on a young repo are the
  version-bumped manifests, every time.

**The requirements drafted from it**

- **Bugs will be written down as behaviour.** This is intended — the alternative
  is a spec that silently disagrees with the running system — but it means a
  fraction of any import is a catalogue of defects phrased as `shall`.
- **Coverage is skewed to whatever is tested.** Well-tested areas produce
  requirements; the untested core produces almost none, which inverts where a
  spec is most needed. Say so in the report rather than letting the shape of the
  draft imply the shape of the system.
- **Everything unobservable is missing.** Batch jobs, migrations, retries,
  caching, back-pressure, anything whose effect is only visible in production.
- **Cross-component behaviour is missing.** The survey reads one repo. A product
  spanning repos gets one repo's surface described as though it were the product.
- **The `Where <feature is included>` requirements will be wrong about
  defaults.** A flag read in code says the branch exists; it does not say which
  way it is set in production, and the survey cannot see production.
- **Thirty requirements will not describe a large system.** The cap is chosen so
  a person can read the draft, not so the draft is complete. An import that feels
  complete has almost certainly stopped being read.
- **A weak-tier draft is a set of questions wearing the grammar of assertions.**
  EARS has no mood for *somebody wrote this down once*, so a weak requirement
  reads with the same authority as a strong one and is held apart only by its
  marker line. That marker is the entire safeguard, which is why dropping it as
  tidying is the specific failure to watch for.
- **A weak tier can be reached for the wrong reason.** Under-eight behaviour
  lines means the probes found little, not that little exists. A codebase in a
  language none of the probes cover produces the same verdict as a documentation
  repo, and the two want completely different next steps. The draft has to say
  which it thinks it is, from the language counts, and be wrong out loud rather
  than quietly.

## Limits worth stating to the user before starting

- Import produces a **starting point that is honest about being one**, not a
  finished spec. The finished spec accretes through intake, as designed.
- The value arrives at **confirmation**, not at drafting. An import nobody
  reviews is worse than no import, because it looks like coverage.
- Requirements that stay `Unconfirmed.` indefinitely are a signal, not debt to
  hide: they are the parts of the system nobody currently owns.
