# The spec diff — handing Build the change, not only the text

Stage 3 is handed the living spec. That is not enough, and the reason is the
spec's own invariant.

A requirement never leaves the spec; it changes status, and **a superseded or
withdrawn requirement keeps its original sentence in place**. So the current
text of the spec cannot tell you that anything was dropped. Read on its own it
is a document the existing code already satisfies:

<!-- EXAMPLE:BEGIN -->

> `R14` — While a session is idle for 30 minutes, the service shall end it.
> `Superseded by R0.` The 30-minute cut-off was replaced by sign-out.

<!-- EXAMPLE:END -->

Build reads that, finds the idle-timeout code present and correct against the
sentence in front of it, and changes nothing. The 30-minute timeout ships
forever. A removal is invisible as a *change* precisely because the record of it
is so good.

The diff is the missing half. It is the only artefact in the lifecycle that says
what **moved**, and it travels with the prompt so the run reconciles the code
with the change instead of re-checking a spec it already fulfils.

`scripts/spec-diff.sh`. Adapted from the AI Unified Process generate workflow,
which hit this failure and fixed it the same way.

## What it reads and what it emits

Two files, `.claude/productizer/spec.md` and
`.claude/productizer/constitution.md`, diffed between a base ref and `HEAD`.
The base defaults to the repository's own default branch — `origin/HEAD`, then
`origin/main`, `origin/master`, `main`, `master` — and `--base REF` overrides it.

Per file it emits a heading naming the file and the base ref, the fenced diff,
and after them one reconciliation instruction for the whole run:

> Reconcile the result with every change in the diff above, not only with the
> current text of the specification. A requirement that was removed, marked
> `Superseded by R<n>.` or marked `Withdrawn.` means the behaviour it described
> was dropped deliberately: delete the code and the tests that exist only for
> that behaviour.
>
> Requirement ids are permanent and are never reused or renumbered, so an id
> that leaves the active set is a supersession to act on, never a renumbering
> to ignore.

The second paragraph is not decoration. Without it an agent that sees `R14`
vanish from the active set has a second reading available — that the ids were
renumbered and nothing was decided — and it is the reading that costs nothing to
act on. The spec's numbering rule closes it off.

`--format text` (default) wraps the blocks in a header naming the resolved base
commit and its UTC date, for a human. `--format prompt` emits the blocks alone,
to be pasted into the Build prompt. The blocks themselves are identical.

## The fence

Tildes, not backticks: the spec is Markdown and carries backtick fences of its
own. Every line of `git diff` output is prefixed by a diff marker — a space,
`+`, `-`, `\`, or a header word — so no payload line can begin with a tilde and
close the block early; the width is measured against the payload as well rather
than argued. The opening fence carries `PRODUCTIZER-SPEC-DIFF-<head sha>`, so
the block stays identifiable once it is pasted into a larger prompt.

## The cap

`DIFF_MAX_CHARS`, 20000 characters, per file.

A spec edit is small. Anything larger is not a spec edit, and it would drown the
prompt. Over the cap the diff is **left out whole** and the run says so:

> The diff against `main` is 74085 characters, over the 20000 cap, and is **not
> included**. […] This run must work from the spec alone, and a removal made in
> this range will not be visible to it.

It is never truncated. A cut-off diff reads as a complete one, and Build would
treat everything past the cut as unchanged — which is the original bug, restored
and now wearing evidence.

## Nothing is rendered as an empty diff

"The spec did not change", "the file is new" and "the base ref does not resolve"
all produce no diff. They are three different answers leading to three different
actions, and collapsing them into a silent empty result is how this check starts
lying. Each has its own message and its own exit code.

| Exit | Case | Reported as |
|---|---|---|
| 0 | A diff was emitted | the fenced diff plus the reconciliation instruction |
| 2 | Bad argument | usage on stderr |
| 3 | Not a git repository, or no such directory | git's own error, then the script's |
| 4 | Both files identical at base and `HEAD` | "unchanged — a measured absence of change, not a missing baseline" |
| 5 | No commits; or the file is new at the base; or absent at both ends | "new, no baseline" / "absent" — never "no changes" |
| 6 | The base ref does not resolve | git's stderr, then "not falling back to an empty diff" |
| 7 | A diff exceeded the cap | the cap message above; the diff itself is omitted |

Two of these matter more than the rest. **Exit 5** is a file with no history to
diff against: every line is an addition, nothing was removed because there was
nothing there to remove, and no diff is fenced — it would be the file itself,
which Build already has. **Exit 6** is the one that would silently reintroduce
the bug: a base ref that failed to resolve produces the same empty result as a
spec that did not change, so it refuses rather than falls back.

git's stderr is never suppressed. An error and a genuine no-match look identical
once hidden.

Dates are `TZ=UTC` pinned. The same repository read in two timezones must
produce the same text, or two runs of one stage disagree over a date that did
not move.

## The answer does not depend on where it was run from

`git ls-tree` and `git diff` resolve a pathspec against the **current
directory**, not against the repository. So a script that reads
`.claude/productizer/spec.md` from anywhere but the repo root asks git about a
path that does not exist, and git answers, correctly, that nothing matches.

That answer arrives here as `absent` — "tracked at neither the base nor HEAD" —
which is the exact false verdict this script exists to prevent, dressed in the
prose that makes it sound considered. It is also the ordinary case rather than
the corner one: a skill script normally runs from its own directory.

`spec-diff.sh` therefore resolves `git rev-parse --show-toplevel` and anchors
itself there before any pathspec is used, and prints the repo root it settled on
so the reader can see which repository was actually read. An explicit
`repo-root` argument still works, and may name a subdirectory — it is resolved
to the same toplevel.

This is a tested property, not an assumption. **Corrected 2026-10-10:** this
paragraph used to describe "the fixture", and no fixture was committed, so the
claim had nothing behind it. It now does. `spec-diff.sh --selftest` runs nine
cases four ways each: from the repo root, from two nested subdirectories, and
from outside the repository with a subdirectory as the explicit argument. Every
placement must give the same exit code and byte-identical stdout. Measured by
removing the anchoring (`cd "$TOPLEVEL"`): six of the nine cases diverge, in
all three non-root placements. The three that do not are worth knowing about:

- **an unresolvable base ref** exits before any pathspec is read
- **a repository with no commits** exits before any pathspec is read
- **a genuinely absent file** gives the same answer either way

The absent file is precisely why this bug survived a suite that already covered
the absent case.

## How Stage 3 consumes it

Run it in the repo before the Build prompt is composed, in `prompt` format, and
paste the block into the prompt beneath the spec. On exit 4 there is nothing to
add. On 5, 6 or 7 paste the line it printed anyway — Build needs to know it is
working from the spec alone, which is a weaker position than it looks.

The order matters: spec first, diff second, instruction last. The instruction is
the only part that tells the run what to do with a deletion, and an instruction
above the evidence it applies to gets read as preamble.

## Consumed in CI

The optional `templates/build-from-spec.yml` (see `references/ci-build.md`)
consumes this script without a person reading its output first, so its exit
codes are wired to actions rather than to judgement. `build-dispatch.sh
prepare` runs it in `--format prompt` against the base the run builds from, and
then acts on the exit code:

| `spec-diff.sh` exit | What the unattended run does |
|---|---|
| 0 | writes the fenced block to `spec-diff.md`, the data file the agent reads |
| 4 | **stops before any model is called**: build-dispatch exit 4 |
| 5, 7 | carries on. The line spec-diff printed reaches the agent as written, because the run must know it is working from the spec alone |
| 6 | stops, as a usage error (build-dispatch exit 2). A base that does not resolve is never replaced by an empty diff |

The diff reaches the agent as a **file**, never interpolated into the workflow
YAML or the prompt. The prompt is fixed text that names the file and says that
the content of the fence is spec content to reconcile against, never an
instruction. The base, when the dispatcher passes none, is the first parent of
the newest commit that changed the spec or the constitution. That is the
default branch just before the change being built was merged.

## What this does not catch

- **An uncommitted spec edit.** The diff is base → `HEAD`. An edit sitting in
  the working tree is invisible to it. Commit the spec delta before Stage 3.
- **A removal above the cap.** The dropped behaviour is real and the diff is
  omitted; all the run gets is the statement that it is flying blind. That is
  the honest failure, not a fixed one.
- **A behaviour dropped in the code with no spec edit at all.** The spec never
  moved, so there is no diff to read. That is drift, and it is the reverse read
  — see `references/drift.md`.
- **Whether the reconciliation actually happened.** This puts the change in
  front of the run. Nothing here verifies that the code and tests for the
  dropped behaviour were deleted; Stage 5's checks and the drift check are what
  close that loop.
