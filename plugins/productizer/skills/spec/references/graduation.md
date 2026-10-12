# Graduation — turning repeated corrections into permanent guidance

Every session produces corrections: a human telling the agent it got something
wrong. They are the cheapest signal the lifecycle generates and the one it
discards fastest, because they live in a transcript nobody opens twice. The next
session repeats the mistake, and the correction is made again.

Graduation is the loop that stops that: harvest the corrections, cluster them,
and walk each cluster up a ladder until it stops needing to be said.

`scripts/graduate.sh` runs it. `scripts/usage-audit.sh` measures the friction
this repo's own scripts cause, which is the same question pointed inward.

## What counts as a correction

A user message is a correction when all of these hold:

- it follows at least one assistant turn in the same conversation — the first
  message of a session is the task, not a correction to it;
- it matches at least one entry in the **cue lexicon** (`graduate.sh lexicon`):
  negation, prohibition, repetition, wrongness, undo, redirection, omission;
- it is under 1200 characters. A long message containing "don't" is a brief, and
  letting briefs in poisons every cluster they touch.

Everything else is not counted. The lexicon is a list of named regexes printed
on demand, so a disagreement about what was counted is settled by reading it,
not by re-running a model.

## The threshold is conversations, not occurrences

**Three distinct conversations.** That is the number, it lives in
`THRESHOLD_CONVERSATIONS` in `graduate.sh`, and it appears nowhere else.

Ten repeats inside one session is one lesson landing badly. Three across three
sessions is a rule the repo needs. Counting messages conflates them and promotes
whichever conversation was most frustrating; counting conversations promotes
whatever keeps coming back.

Repetition inside a conversation is not discarded — it is recorded separately as
**pain**, capped at 3, because having to say a thing twice in one sitting is
friction even when it is not breadth.

A subagent is its own conversation. It carries the parent session id but runs in
its own context and is corrected on its own, so conversation identity is
`sessionId/agentId`. Keying on the session alone counted eleven parallel agents
as one.

## Clustering is a lexicon, not a model

Each correction is tagged against the **topic lexicon**: a named regex, a flag
saying whether a deterministic check could ever assert the thing, and a
second-person sentence. One cluster per tag. A message matching several tags
joins several clusters.

This is deliberately weaker than embedding the messages and clustering by
similarity. Similarity would group better and produce a number nobody can argue
with, which is the wrong trade for output a human has to rule on. Productizer's
shape everywhere else is a decidable fragment plus an explicit escape hatch, and
this is that shape:

**A correction that matches no topic tag becomes `UNDECIDED`.** It is not
guessed at and not dropped. It is presented as its own card, and the human
decides whether the lexicon is missing a tag or the cue lexicon is too wide.
That is the escape hatch, and it escalates rather than resolving itself.

## The ladder: prose → skill → hook → CI gate

> Instructions are advisory and decay as the context window fills. Checks are
> deterministic and never tire.

That is the whole reason the ladder exists. A rule written in prose is read
early in a session and forgotten late in it. The same rule expressed as a check
fires on the last commit of a long day exactly as it fired on the first.

| Rung | Where it lands | What it costs |
|---|---|---|
| prose | `CLAUDE.md` | free, and decays with context |
| skill | `.claude/productizer/graduated/<tag>.md` | retrieved on demand, still advisory |
| hook | `.claude/hooks/graduated-<tag>.sh` | fires every time, needs an assertion |
| ci-gate | `.claude/productizer/checks.yaml` | blocks a merge, needs a command |

The rung is chosen from `score = signals × conversations × pain`, where
`signals` is how many distinct cue types the cluster attracted:

- `score < 12` → prose
- `score < 36` → skill
- `score < 72` → hook
- `score ≥ 72` → ci-gate

**A cluster the lexicon marks as not mechanically checkable is capped at skill,
whatever its score.** A gate that cannot be written is not a gate, it is a
promise. `scope-discipline` with 12 conversations scores 72 and still stops at
skill, because no command asserts "did not go beyond what was asked".

Two things this deliberately does not do. It does not silently take the top
rung — the recommendation is printed beside the evidence that produced it, and
applying is a separate decision. And the hook and gate operations it drafts are
**stubs that assert nothing**, marked as such in the file they write. The
lexicon knows a cluster is the kind of thing a check could assert; it cannot
write the assertion. A hook that always passes is worse than no hook, so the
stub says so in its own body rather than looking finished.

## Evidence, then a human decision

Each promoted cluster is presented as a card carrying:

- the evidence count **in conversations**, not messages;
- a one-sentence second-person summary — *"In 4 conversations, you asked agents
  to run the tests before saying a change was ready"*;
- the arithmetic, printed: `signals × conversations × pain = score`;
- the recommended rung, and why it was capped if it was;
- the concrete operations, marked `+` create, `~` update, `−` remove;
- a unified diff per file;
- the command that prints the raw excerpts behind the claim, grouped by
  conversation with `file:line` for each.

**The script never applies on its own.** There is no auto-apply flag, defaulted
on or otherwise. `apply` requires `--id <tag> --decide accept`, naming one
cluster; without the decision it exits 2 and says why.

## Apply is all-or-nothing and precondition-checked

Every operation records the target's SHA-256 **as it was when the suggestion was
drafted**. Before anything is written, all preconditions are checked:

- a **create** target must not already exist;
- an **update** or **remove** target must exist and still hash to the drafted
  value.

If any precondition fails, **nothing is written at all** — not the operations
that would have succeeded either — and the suggestion is flagged in
`suggestions.json` with the reason and both hash prefixes. The alternative is
silently clobbering your work: the diff a human approved is not the diff that
would land, and applying most of it is worse than applying none.

Recovery is to re-run `present`, which redrafts against the files as they now
are, and review the new diff.

### Undo

`apply` writes a journal recording, per operation, what was there before and the
hash of what it wrote. `undo` restores the prior contents **only if the file
still hashes to what apply wrote**. A file edited after the apply holds work the
journal knows nothing about, and restoring the backup would destroy it — the
same clobber the apply preconditions exist to prevent, pointed the other way. On
any mismatch undo refuses entirely and exits 8.

## Pruning

A file under `.claude/productizer/graduated/` whose tag drew no correction in
the harvest window is offered as a `remove`. It is offered, never taken:
absence in one window is not evidence the lesson stopped mattering — it is
equally consistent with the lesson having worked.

## Nothing is rendered as zero

Four different nothings, four different reports, because they lead to four
different actions:

| Situation | Report | Exit |
|---|---|---|
| No transcript root | "a scan that did not happen" | 3 |
| Root exists, no transcripts | "an empty shelf" | 3 |
| Transcripts that will not parse | "nothing parseable", with the file count | 4 |
| Transcripts read, no cue matched | "a measured zero" | 5 |
| Corrections found, none reaching 3 conversations | the cluster table, with every cluster marked below threshold | 6 |

Only the fourth is a zero. Printing "0 corrections found" for any of the others
reads as *nothing to learn*, which is a claim about the repo rather than a
report about the scan.

## What this loop cannot do

Say this plainly, because the loop looks more powerful than it is.

- **It trains nothing.** It extends a lexicon of regexes with clusters a human
  approved. There is no model, no weights, and no learning. The next run is
  exactly as good as the lexicon a human last edited.
- **It yields precision data, not recall data.** Every record is a correction
  somebody actually voiced. The corrections nobody bothered to voice — the
  agent was wrong and the human fixed it silently, or did not notice — leave no
  trace in any source this reads. That is the false-negative set, and **a
  semantic recall gap cannot be closed with data that contains no false
  negatives.** Harvesting more corrections makes the lexicon wider, which is a
  precision improvement on the messages that do arrive. It says nothing about
  the ones that do not.
  <!-- EXAMPLE:BEGIN -->
- **It is one hand-run iteration, automated.** The precedent is already in this
  repo: `scripts/contradiction-check.py` carries `("reject", "queue")` in
  `EXCLUSIVE_PAIRS` with the note that it was *"added after an end-to-end run
  found the skill's own worked example (R7 against R41) coming back
  CONSISTENT."* One person ran the thing, saw one miss, added one pair.
  Graduation is that loop with the bookkeeping done for you. It is not a
  different kind of thing, and it will not find the pair nobody tripped over.
  <!-- EXAMPLE:END -->
- **Conversation-distinctness is only as good as the transcripts.** A repo whose
  work happens outside Claude Code sessions has no source here, and the correct
  output in that case is "no source", not a small number.
- **PR review comments are declared and not read.** `--source pr` reports what
  `detect-context.sh` says about `gh` and then reports `unavailable`. It never
  fabricates the count.

## Auditing the repo's own friction

`scripts/usage-audit.sh` answers the inward-facing version: how often are these
scripts run, and how often do they fail? Two halves.

**Census** reads transcripts and counts invocations, failures, and whether the
agent recovered on a later try in the same conversation. It reports an error
rate **with its sample size beside it** — a rate without an `n` is a number
people quote. Failure is taken from the harness's `is_error` flag alone; two
looser heuristics were tried and thrown out, one of which counted this repo's
own status lines (`build-view: wrote …`, `score: SCORED …`) as errors because
they share the prefix shape of its error lines. Because an agent's compound
shell line usually ends in a command that succeeds, `is_error` is a **floor**,
and the report prints an upper bound beside it rather than presenting either as
the truth.

**Contract** compares, for each script, the options the argument parser accepts
against the options the help text names. A script whose help text lies about its
arguments manufactures a usage bug in every session that reads it, and each one
looks like an agent mistake. That comparison is static; `--probe` additionally
executes each script with `--help` and with a nonsense flag in an empty
directory, which is a different kind of risk and is therefore off by default.
