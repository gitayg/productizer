# The plan page — reading a plan, commenting on it, deciding what it left open

Read this before building a plan page, and before applying the answers one
hands back. A plan (`templates/plan.md`) is the file the build is held to; the
page is a way to read it and to answer it, and nothing else.

## What it is, and what it is not

`scripts/build-plan-page.sh` turns one `docs/sdlc/<item>/plan.md` into one
self-contained HTML page: every section of the plan, a **Comment** button on
every passage (and a quote taken from words selected inside one passage), and
each open question as a button per option plus an answer of the person's own.
**Copy answers** hands back a fenced **answer set** the agent validates with
`scripts/plan-answers.py` and, once valid, writes into the plan.

**It is not a view** (`references/views.md`). A view is a read-only picture of
lifecycle state. The plan page shows one plan, and the person composes answers
on it - so the rules that make that safe are stated once, here:

- **The plan stays the source of truth and the only edit surface.** The page is
  built from `plan.md` every time and holds no state: closing it loses what was
  entered, and nothing is kept in browser storage.
- **It requests no capability** - not `downloads`, not anything - **and writes
  no file.** What the person decides leaves it as text they copy, or as a file
  their own browser saves when the page was opened from disk.
- **Answers reach `plan.md` alone**, through `plan-answers.py`, which refuses a
  set naming any other file. Nothing from the page ever reaches the spec. This
  is the shape P3 already gives the backlog view's reordering: the page composes,
  hands back, and a file is edited by the agent and committed.
- **It loads nothing and sends nothing.** No script, stylesheet, font, image or
  frame from anywhere, and no request out of the page.

`scripts/check-plan-page.py` (the `plan-page` check) builds pages with the real
builder and holds them to all of that.

## Open questions, the fixed syntax

In the plan's `Open questions` section:

```
Open questions
- Q1: How many retries before a job is dead-lettered?
  - A: three, then dead-letter
  - B: five, with backoff
```

A question is a list item at the left margin reading `Q<n>: <text>` (it may run
on to indented lines under it); its options are the indented items under it
reading `<letter>: <text>`, lettered from `A` with none skipped, two at least.
Every question also takes an answer of the person's own. A question whose text
is only a template placeholder (`<...>`) is not open. Any other list item in the
section, a question asked twice, or one already under `Decisions` stops the
build: exit 1, nothing written, and the message says which.

`Decisions` is where answered questions land:

```
Decisions
- Q1: How many retries before a job is dead-lettered?
  Decided: B - five, with backoff
  Note: with a cap of 60s
```

## Building and opening it

```bash
scripts/build-plan-page.sh docs/sdlc/B7/plan.md            # to $TMPDIR/plan-page-B7.html
scripts/build-plan-page.sh docs/sdlc/B7/plan.md --out FILE
open "$TMPDIR/plan-page-B7.html"                           # macOS; xdg-open on Linux
```

The page is byte-identical for the same plan and stylesheet. It never writes into
the repository by default. It is written to a private file and renamed into
place, so a symbolic link left at the output path is replaced, never written
through. Open it for the person when a plan has open
questions or when they ask to read the plan; say what to do in one line. It may
also be published as an Artifact **with no capabilities**. When the clipboard
refuses the copy - a sandboxed frame may; that was not measured inside an
Artifact - the page says so and selects its answer set in a box to copy by
hand. The save-as-file link is offered only when the page is not in a frame.

## The answer set

```productizer-plan-answers
format: 1
plan: docs/sdlc/B7/plan.md
plan-sha256: 3f2a…(64 hex)
decide Q1 B "with a cap of 60s"
decide Q2 other "the errors table, with a type column"
comment risks/1 "retried forever" "say how a permanent error is told apart"
```

A comment names a passage by its anchor, `<section slug>/<n>`, n counting the
section's passages from 1, and carries the quoted words (`""` for the whole
passage) and the note. Every free-text value is a JSON string on its line, so a
note can hold any character and never ends the block. Text around the block is
ignored, so the person can paste it with a sentence of their own.

## Back to the agent

```bash
scripts/plan-answers.py answers.txt                         # or - for standard input
scripts/plan-answers.py --plan docs/sdlc/B7/plan.md answers.txt
scripts/plan-answers.py --apply answers.txt                 # writes the decisions
```

It refuses (exit 1, nothing written) a set whose plan has changed since the
page was built - **rebuild the page and answer again** - one naming a question
the plan does not hold open, an option it does not offer, a passage it does not
hold or words that passage does not say, and a plan path that is absolute,
holds `..`, is not a `plan.md` or is reached through a symbolic link. A valid
set prints one line per decision and per comment: work from that, never from
the raw block. `--apply` moves the answered questions into `Decisions` and
leaves the rest of the plan byte for byte; **comments are never written** -
they are free text, and the agent works them into the plan itself. Commit the
plan afterwards, as any plan edit.

## The project's own look

`plan_page.stylesheet` in `.claude/productizer/config.json` names a CSS file in
the repository - a design-tokens file, typically. `scripts/plan-theme.py` reads
**only** `--name: value` custom properties, from `:root` or `html` (light) and
from `:root` inside `@media (prefers-color-scheme: dark)` or a rule on
`[data-theme="dark"]`, `:root[data-theme="dark"]`, `.dark`, `:root.dark` or
`html.dark` (dark), resolving `var()` up to eight deep. A value is taken only
when it is a colour (`#hex`, a colour word, or `rgb()`/`hsl()`/`hwb()`/`lab()`/
`lch()`/`oklab()`/`oklch()` holding numbers alone) or a list of font family
names. `url(`, `@import`, a backslash, a `;`, a brace or a `<` is never a colour
or a font, so nothing from the file can load anything or end the style element.

The page's tokens and the names read for each, first set wins, unless
`plan_page.tokens` names one (`{"accent": "--brand-500"}`):

| Token | Read from |
|---|---|
| `bg` | `--background` `--bg` `--color-bg` `--color-background` |
| `surface` | `--surface` `--card` `--color-surface` `--color-card` |
| `text` | `--foreground` `--text` `--fg` `--color-text` `--color-fg` `--color-foreground` |
| `muted` | `--muted-foreground` `--text-muted` `--muted` `--color-muted` `--color-text-muted` |
| `border` | `--border` `--color-border` |
| `accent` | `--accent` `--primary` `--color-accent` `--color-primary` |
| `accent-text` | `--accent-foreground` `--primary-foreground` `--on-accent` `--on-primary` `--color-on-primary` |
| `font` | `--font-sans` `--font-body` `--font-family` `--font` |
| `mono` | `--font-mono` `--font-code` `--mono` |

A token the stylesheet does not give keeps the built-in value; a stylesheet
with no dark colours leaves the dark page wholly built-in. No configuration, a
file that cannot be read, one outside the repository, one over 512 KB or one
that sets nothing usable gives the **built-in theme**, light and dark, and the
page says why under its title. That is never an error.

## What it does not do

- **It cannot know the person read the page**, or read all of it.
- **A comment is free text the agent interprets.** The validator checks where it
  points, not what it means.
- **Nothing but `plan.md` is reached**, and only through the validator.
- **The theme reads custom properties only.** Colours set any other way, a
  bare `0 0% 100%` HSL triplet, and a font that is not installed on the
  reader's machine are not taken; a font is named, never loaded.
- **No check runs the page in a browser.** The checks read the page's bytes and
  its HTML parse; the buttons, the comments and the copy were driven by hand.
