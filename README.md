# Productizer — plugin distribution

Packages the `spec` skill as a Claude Code plugin, served from a
marketplace in this repository. Written for one publisher and many consumer
repositories: install once at user scope and the skill is available in every
project, without copying it into each `.claude/skills/`.

## Layout

```
productizer/
├── .claude-plugin/
│   └── marketplace.json          # the marketplace catalogue
├── plugins/
│   └── productizer/
│       ├── .claude-plugin/
│       │   └── plugin.json       # the plugin manifest
│       ├── commands/
│       │   └── upgrade.md        # /productizer:upgrade
│       └── skills/
│           └── spec/
│               ├── SKILL.md
│               ├── references/
│               ├── scripts/
│               └── templates/
└── README.md
```

The marketplace and the plugin live in the same repository. The plugin entry
uses a relative-path source, `./plugins/productizer`, which resolves against
the marketplace root — the directory containing `.claude-plugin/`, not the
`.claude-plugin/` directory itself.

Both manifests pass `claude plugin validate <path> --strict`.

Relative-path sources only resolve when the marketplace is added from a git
source or a local directory. Adding it by direct URL to `marketplace.json`
downloads that one file and the path will not resolve.

## Versioning: explicit `version`, bumped per release

`plugin.json` sets `"version": "4.57.0"`.

Claude Code resolves a plugin's version from the first source that is set:
`plugin.json`, then the marketplace entry, then the resolved commit SHA of the
source. The version is the cache key that decides whether an update exists.

Two behaviours follow:

- **With `version` set** — consumers receive an update only when the field is
  bumped. Pushing commits without bumping it changes nothing for them, and
  `claude plugin update` reports the plugin is already at the latest version.
- **Without `version` anywhere** — the resolved commit SHA becomes the version,
  so every commit to this repository ships to everyone on their next update.

Explicit versioning is chosen. This skill governs how work is specified,
reviewed and gated across many repositories; a half-finished edit to a stage
definition reaching every repository on the next commit is a worse failure than
a release lagging by a day. Bumping is the publisher's deliberate act of saying
the change is ready. SHA versioning is the right choice for a plugin under
active development by its only consumer — that is not this case.

Follow semantic versioning: MAJOR for breaking stage or artefact changes, MINOR
for new stages or templates, PATCH for wording and fixes.

## `/plugin` is an interactive panel

`/plugin` and its subcommands open a terminal panel inside a running Claude
Code session. They cannot be run from a plain shell, a script, or CI. Anything
below written as `/plugin ...` must be typed inside `claude`. The `claude
plugin ...` shell equivalents run from any shell and do not open the panel —
use those for scripting.

## Consumers: add the marketplace

Inside a `claude` session:

```
/plugin marketplace add gitayg/productizer
```

`owner/repo` is the GitHub shorthand. A full git URL works for any other host.
A local checkout works too, for testing before publishing:

```
/plugin marketplace add /path/to/productizer
```

Shell equivalent: `claude plugin marketplace add gitayg/productizer`.

## Consumers: install

```
/plugin install productizer@productizer
```

The panel then asks for an installation scope. Choose **user** so the skill is
available in every repository — that is the point of packaging it. Project
scope writes the plugin into that repository's `.claude/settings.json` and
shares it with collaborators; local scope is that repository only, for you.

Non-interactive equivalent, which installs to user scope unless `--scope` is
passed:

```
claude plugin install productizer@productizer
```

Naming the marketplace explicitly (`plugin@marketplace`) makes Claude Code
refresh the marketplace before the lookup, so a freshly published plugin is
found. Installing by bare plugin name reads the cached catalogue.

A shell install does not affect the running session. Run `/reload-plugins` in
an open session, or restart.

## Consumers: update

```
claude plugin update productizer
```

A restart is required to apply it. `--scope` targets a non-user installation.

If the marketplace catalogue itself is stale, refresh it first:

```
claude plugin marketplace update productizer
```

## Per-repo templates

Every template resolves repo-first:

```
.claude/productizer/templates/<name>     the repo's own version
templates/<name>                         the plugin's default
```

Commit the ones that differ and the whole repo gets them, the same way
`CLAUDE.md` is the repo's. Override one file and inherit the rest; a plugin
update never overwrites them.

## Consumers: enable auto-update

Auto-update is per marketplace, and it is **off by default** for third-party
and local marketplaces — only the official Anthropic marketplaces default to
on. Enable it explicitly:

1. Run `/plugin`
2. Select **Marketplaces**
3. Choose `productizer`
4. Select **Enable auto-update**

With it on, Claude Code refreshes the marketplace and updates installed plugins
in the background after session start, with a random delay of up to ten
minutes. The running session keeps the versions it launched with; a
notification prompts for `/reload-plugins`, or the new version loads next
launch.

Auto-update never bypasses the version decision above — it still only installs
when the resolved version changes, which for this plugin means when the
`version` field is bumped.

`DISABLE_AUTOUPDATER` turns plugin auto-updates off along with Claude Code's
own. To keep plugin auto-updates while pinning Claude Code, set
`FORCE_AUTOUPDATE_PLUGINS=1` alongside it.

**A publisher cannot turn this on for you.** There is no `autoUpdate` field in
`marketplace.json`; the setting lives on the consumer's side. For a team, an
administrator can set `"autoUpdate": true` on the marketplace's
`extraKnownMarketplaces` entry in managed settings, which enables it for the
organisation without each person toggling it:

```json
{
  "extraKnownMarketplaces": {
    "productizer": {
      "source": { "source": "github", "repo": "gitayg/productizer" },
      "autoUpdate": true
    }
  }
}
```

## Publisher: shipping a change

1. Edit the skill under `plugins/productizer/skills/spec/`.
   Shell scripts must pass `npx shellcheck --severity=warning`; the plugin
   ships a check that enforces exactly that, and its own scripts are held to
   it. `scripts/contradiction-check.py --selftest` must stay at precision 1.00
   with no false positives, and `evals/solver-probe.py` must stay inside the
   baseline CI gates it against — at least 9 caught, at most 1 missed, at most
   0 false positives, at least 10 quiet, measured 2026-09-06. That step parses
   the probe's counts rather than its exit status, because the probe always
   exits 0; a count whose line is missing from the output is treated as **not
   measured** and fails, never as a zero.
   Upgraded the plugin in a repo scaffolded by an older version? Run
   `/productizer:upgrade`. It compares five things — the version that
   scaffolded the repo, installed executables against the templates they came
   from, schema versions, checks the plugin ships that the repo never
   declared, and templates that gained content — and **changes nothing**: it
   reports the drift and the exact diff, and a person applies each one. It
   never executes anything from the repo it is reading, and it deliberately
   does NOT follow `spec.path` from that repo's config, because following it
   would let a foreign repo choose what gets opened. Exit `3` outranks `1`: a
   dimension it could not measure beats findings, because a report with a hole
   in it has not found nothing.

   Changing `.claude/productizer/spec.md` too? Run `scripts/spec-doctor.sh`
   first. It runs the existing spec checks and changes nothing: `0` clean, `1`
   findings, `2` a section could not run at all — which outranks findings,
   because a report with a hole in it has not found nothing, it has not looked.
   It carries `--selftest` (32 cases, run by the workflow) and is deliberately
   NOT a declared check: it calls a `WARN` a finding where `validate-spec.py`
   exits 0, so gating on it would turn any pre-existing warning red and the
   first thing anyone did would be to delete the step.
2. Bump `version` in `plugins/productizer/.claude-plugin/plugin.json`.
   Nothing ships without this.
3. Run `claude plugin validate ./plugins/productizer --strict` and
   `claude plugin validate . --strict`. Both must pass.
4. Commit and push to the default branch.
5. Optionally tag the release: `claude plugin tag ./plugins/productizer`
   creates a `{name}--v{version}` git tag and checks that `plugin.json` and the
   marketplace entry agree.

Consumers with auto-update on pick the change up on their next session.
Consumers without it run `claude plugin update productizer`.

Step 2 is the whole contract. A change pushed without a bump is invisible.

### Commit trailers

`scripts/req-trailer.sh --add R14,R22 --file .git/COMMIT_EDITMSG --assisted-by`
records which requirements the commit served and that a model helped write it.
It never writes `Signed-off-by`, because only a human can certify the DCO, and
never `Co-authored-by`, which credits a person. `--tools "..."` appends
specialised analysis tools and refuses the basic ones — `git`, `make`, a
compiler, an editor — with exit `2` and nothing written.
`scripts/req-trailer.sh --authorship --rev <rev>` reads a commit back and exits
`3` when it claims otherwise.

### Reporting a change on its pull request

`scripts/pr-spec-comment.sh --base origin/main` renders what the change did to
the spec as markdown **on stdout**. It posts nothing: `--post`, `--publish`,
`--gh`, `--comment` and `--pr` each exit `2` with no output, pointing at
`.claude/hooks/publish-gate.sh`, because posting to a pull request is a publish
and this repository routes every publish through that gate. Exit `5` means the
report was rendered but at least one section could not be measured and says so
in place.

## Precedence, and the personal copy at `~/.claude/skills/`

Skills at the enterprise, personal and project levels compete for one name:
enterprise overrides personal, and personal overrides project. Plugin skills do
not enter that contest. They are namespaced `plugin-name:skill-name`, so a
plugin skill never overrides — and is never overridden by — a same-named skill
at another level.

Concretely, once this plugin is installed while
`~/.claude/skills/spec/` still exists:

- Both load. Neither wins.
- Both descriptions sit in context on every session, competing for the same
  triggers.
- The personal copy answers the unqualified name, `spec`; the plugin copy
  answers `productizer:spec`. The plugin is `productizer`; the skill inside it
  keeps the name `spec`, which is what it does.
- They drift. `claude plugin update` moves the plugin copy and never touches
  the personal one, so the repository the owner edits and the skill that
  actually fires diverge silently.

Therefore: **after confirming the plugin loads, remove the personal copy.**
Move it aside rather than deleting outright, then delete once a session has run
against the plugin:

```
mv ~/.claude/skills/spec ~/.claude/skills/.spec.bak
```

From then on this repository is the only source. Edits go here, get a version
bump, and reach all sixteen repositories through the marketplace.
