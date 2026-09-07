# Upgrading a repo that installed this plugin

`scaffold.sh` never overwrites. Its own sentence:

> scaffolding never replaces work

That is correct and it should stay. The consequence, which was not written
down anywhere until now, is that **a repo is scaffolded exactly once and is
never upgraded.** Every later plugin release changes the templates, the hooks
and the shipped check list, and the repo that installed version X keeps what
version X gave it, forever, with nothing telling it.

`check-installed-copies.sh` already names the sharp end of this in its own
header and then scopes itself to the plugin's own repository:

> the dangerous direction is the other one - this repo hardening its own gate
> while every repo installing the plugin keeps the weaker copy

`/productizer:upgrade` is pointed at the case that header describes and cannot
reach: some other repo, scaffolded at some earlier version.

## The five dimensions, and why they are reported separately

They fail separately and a person acts on them separately, so collapsing them
into one "out of date" verdict would lose the only thing that makes the report
actionable.

1. **Version provenance** — which plugin version is installed, against which
   version scaffolded the repo.
2. **Installed executables** — hooks that landed from a template and are no
   longer that template. Byte-compared; never run.
3. **Schema versions** — `config.json` (`version: 2`) and `checks.yaml`
   (`version: 1`) carry their **own** schema versions, independent of the
   plugin's `4.x`. A repo can be a schema revision behind while every file
   looks fine and every check is green.
4. **Checks shipped but never declared** — check ids the plugin's `checks.yaml`
   template now carries that the repo's `checks.yaml` has never named. An
   undeclared check does not run, and never running a check is not passing it.
5. **Templates that gained content** — lines a template has that the repo's
   copy does not.

### Why dimension 5 compares the *scaffolded* form of a template

`scaffold.sh` strips every fenced `EXAMPLE:BEGIN … EXAMPLE:END` block on the
way in, because the worked examples are numbered — R1…R6 in the spec, P1…P5 in
the constitution — and copying them verbatim seeds a repo with requirements
nobody agreed to.

Diffing the *shipped* template instead reports those blocks as content every
scaffolded repo is missing, forever. Measured on a real repo before the fix:
77 lines on `spec.md` and 77 on `constitution.md`, all of it the examples doing
exactly what they exist to do. After applying the same strip: 17 and 8. A
finding that can never be actioned and never goes away trains a reader to skip
the section, which is worse than not printing it.

## Recording the version that scaffolded a repo — a proposal, not a change

**Recommendation: yes, a repo should record it — and NOT inside `config.json`.**

Nothing written by `scaffold.sh` or `init.sh` carries the plugin version today.
That is measured, not assumed, and it is why dimension 1 reads `unknown` on
every existing repo and why `/productizer:upgrade` exits `3` rather than `0`
on a repo that is in fact perfectly current. Unknown is the honest answer and
it is a bad steady state.

**Not in `config.json`.** That file's `version: 2` is a **schema** version, and
it is a hand-edited seed. Putting a plugin version beside it conflates two
versions that move for unrelated reasons, and a schema field living in a file
people edit will drift the first time someone hand-copies a block from a newer
template.

**Proposed instead: `.claude/productizer/installed.json`,** written by
`init.sh` (never by `scaffold.sh`, which copies one template and has no
business knowing what plugin it belongs to):

```json
{
  "plugin_version": "4.54.0",
  "scaffolded_utc": "2026-09-07T00:00:00Z",
  "files": {
    ".claude/productizer/checks.yaml": "<sha256 of the file as written>",
    ".claude/hooks/publish-gate.sh":   "<sha256 of the file as written>"
  }
}
```

Three things this buys, in order of how much they matter:

1. **`files` makes drift DIRECTIONAL, which today it is not.** Right now, when
   a repo's copy differs from a template, nobody can say whether the repo
   edited it or the template moved. Those are opposite facts needing opposite
   responses — one is a local decision to respect, the other is an upgrade to
   apply — and `/productizer:upgrade` currently has to report the difference
   without being able to say which. A baseline hash settles it: repo copy
   equals baseline and template moved → an upgrade to offer; repo copy differs
   from baseline → a local edit to leave alone. This is the strongest argument
   for the file, stronger than the version string.
2. `plugin_version` turns dimension 1 from `unknown` (exit 3) into a real
   measurement, and lets `--scaffolded-version` go back to being what it is:
   a human's assertion for a repo predating the file.
3. `scaffolded_utc` dates the baseline, so "no upgrade in eleven releases" is
   a statement someone can check.

**Costs, stated rather than glossed:**

- It is a schema change and a new file in every scaffolded repo, so it needs
  the same review any schema change gets.
- The file is only true at the moment it is written. Anyone who applies an
  upgrade by hand without updating it leaves a baseline that lies, which is
  worse than the honest `unknown` it replaces. That argues for `installed.json`
  being written by whatever applies an upgrade, not only by `init.sh` — which
  is more work than it first looks and is the reason this is a proposal.
- `/productizer:upgrade` already reads `installed.json` if it is there and
  falls back to `unknown` when it is not, so the reader half is done and the
  proposal is only about the writer half.

**This was deliberately not implemented here.** `scaffold.sh`, `init.sh` and
the `config.json` template are owned elsewhere, and a schema change is not a
thing to land as a side effect of adding a report.

## Known limitations

- **`spec.path` is not followed.** `config.json` can relocate the spec. This
  tooling looks for it at the scaffolded location and nowhere else, because
  following a path out of a foreign repo's committed config would let that repo
  choose what gets opened and then printed into a report. A repo that relocated
  its spec is reported as **unmeasured**, not as clean.
- **The file table is fixed.** Dimension 5 walks a table written into the
  script. A template added to the plugin that nobody adds to that table is
  invisible here, and the self-test says so rather than implying otherwise.
- **`upgrade-drift.sh` is not a declared check.** It is not in `checks.yaml`
  and not in the workflow, so `check-selftest-coverage.sh` does not build it
  into its tool set and its self-test is never run by the suite. It satisfies
  R39 (it carries one, and reaches every code it documents) and not R40 (the
  suite does not invoke it) until someone declares it.
