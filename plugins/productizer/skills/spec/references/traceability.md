# Traceability — from a requirement id to the commits and the tests

The spec already owns the hard half of traceability: **permanent requirement
ids**, never reused and never renumbered (R2). That gives every agreement a
name that stays valid for the life of the product.

What it did not give you is the reverse lookup. Given `R14`, nothing could
answer *which commits built this*, and given a commit, nothing recorded *which
agreement it served*. This file closes both directions with two conventions and
one script, `scripts/req-trailer.sh`.

| Direction | Mechanism | Failure it makes visible |
|---|---|---|
| requirement → commits | `Productizer-Req:` git trailer | a requirement nothing was ever committed for |
| requirement → tests | `COV_<id>_<slug>` coverage id | a requirement nothing tests |
| commit → requirement | the same trailer, read backwards | a commit citing an id that does not exist |
| test → requirement | the same coverage id, read backwards | a test still guarding a superseded requirement |

## 1 · The commit trailer

```
Productizer-Req: R14,R22
```

One line, at the end of the commit message, in the trailer block. Ids are
comma-separated and carry no other punctuation. `R14` — this repo's format, not
`R-014` and not `REQ-14`; `req-trailer.sh` refuses anything else by name rather
than repairing it, because a repaired id is a shape the spec's own readers do
not match.

### Why a trailer, and not a database

Because it costs nothing and survives everything. A trailer is part of the
commit object, so it clones, fetches, rebases, cherry-picks, mirrors and
`format-patch`es with it, and it is queryable on a machine that has never heard
of this repo's tooling:

```sh
TZ=UTC git log --grep='Productizer-Req:.*R14'
```

There is no service to run, no table to migrate, no id map to keep in step with
the spec, and nothing that rots the day the tool that wrote it is uninstalled.
Every alternative — an issue link, a PR label, a spreadsheet, a row in a
database — is a second store that drifts from the first the moment someone edits
one and not the other. This one cannot drift, because there is only one copy of
it and it is inside the thing it describes.

### Installing the hook

```sh
cp plugins/productizer/skills/spec/templates/prepare-commit-msg.sh \
   .git/hooks/prepare-commit-msg
chmod +x .git/hooks/prepare-commit-msg
mkdir -p .claude/productizer/bin
cp plugins/productizer/skills/spec/scripts/req-trailer.sh .claude/productizer/bin/
```

It is a **git** hook, not a Claude Code hook: it is registered by living at that
path, it takes no JSON on stdin, and `settings.json` knows nothing about it.
`.git/hooks/` is not committed and not cloned, so every clone installs it again
— that is git's design, not an oversight of this one.

The hook takes the ids from, in order:

1. `$PRODUCTIZER_REQ` — `PRODUCTIZER_REQ=R14,R22 git commit -m "…"`.
2. The branch name. `feat/R14-halt-on-contradiction` gives R14;
   `R14-R22-intake` gives both. An `R<n>` run counts only when it stands alone,
   so `PR2`, `CORS` and `v2R` are not read as ids.
3. Nothing — it says so once on stderr and gets out of the way.

**It does not block your commit**, with one exception. A missing trailer is a
gap in a record, not an unsafe act, and a hook that refuses to let you commit
because it could not guess an id from a branch name is a hook that gets deleted
within a day, which costs the record everything. The exception is an id **you
named yourself** in `$PRODUCTIZER_REQ` that the spec does not contain: that is a
false provenance record being written deliberately, and it aborts. Ids merely
inferred from a branch name never abort anything.

Enforcement belongs where it can see the whole change — `--validate` in a
pre-push hook or in CI, `--orphans` against the spec.

## 2 · Coverage ids

```
COV_<requirement-id>_<slug>

COV_R14_halts_on_contradiction
COV_R16_unmeasured_is_not_zero
```

Put one in the name of the test, or in a comment on it — anywhere in a tracked
file. What matters is that the token exists in the tree and that a reader can
see which test it belongs to.

### The rule that makes this work: there is no second id authority

The requirement id appears **verbatim** inside the coverage id. Consequences,
all of them deliberate:

- A coverage id cannot be minted without naming a requirement.
- Coverage ids are never numbered, allocated, or renumbered. There is no
  `COV` counter to keep, and nothing to reconcile.
- A coverage id stops resolving the moment the requirement it names stops
  standing — which is exactly when someone should look at it.

An independent coverage namespace mapped to requirements by a table would be a
second permanent-id authority, and two id authorities in one repo disagree.
This one is derived, so it cannot.

### Note on the examples above

`COV_R14_halts_on_contradiction` in the paragraph above is a **literal token in
a tracked file**, and `--coverage` scans tracked files textually. If this
reference doc is inside the repository being scanned, it counts as coverage of
R14 and R16. That is why `req-trailer.sh` itself carries no literal example in
its header — it gets vendored into the repositories it scans, and its own
documentation would have shown up as real coverage. See KNOWN_LIMITATIONS.md.

## 3 · The commands

```sh
req-trailer.sh --add R14,R22 --file .git/COMMIT_EDITMSG
req-trailer.sh --validate [--file <msg> | --rev <rev>]
req-trailer.sh --query R14
req-trailer.sh --orphans
req-trailer.sh --coverage [--include-ignored]
req-trailer.sh --version | --selftest
```

| Mode | Answers | Notes |
|---|---|---|
| `--add` | — | merges rather than appends; run it twice and the file is byte-identical. Refuses to write an id the spec does not contain, and leaves the file untouched when it refuses. Placement is `git interpret-trailers`, which knows where the trailer block ends and that `#` comment lines are not part of the message. |
| `--validate` | does every cited id exist? | an unknown id is an error naming it. A **superseded or withdrawn** id is a note, not an error — a commit made before the replacement is telling the truth about its own history. |
| `--query` | which commits claim this id? | prints the plain `git log --grep` that answers the same question without this script. |
| `--orphans` | which active requirements does no commit claim? | also reports the reverse: ids claimed by a commit that the spec does not contain. |
| `--coverage` | which active requirements does no `COV_` id name? | also reports **dangling** (names an id the spec never had) and **stale** (names a superseded or withdrawn requirement) coverage ids. |

Exit codes are the contract:

```
0  ran, nothing to report — backed by the counts it printed
1  crashed before reaching a report. Undetermined, never clean
2  bad usage, or no spec / no ids in it — nothing was compared
3  a finding. The run succeeded; what it found did not
4  CANNOT DETERMINE. Not a pass, and not a zero
```

## 4 · The zeros this refuses to print

`0 orphans` reads as a clean bill of health, and several quite different
situations can produce it. R16 says a value that could not be measured is not
recorded as zero, so they are kept apart and each says which one it is:

| Situation | Reported as |
|---|---|
| no living spec | exit 2, "nothing to trace ids against" |
| not a git repository, or git failed | exit 4, naming git's own error |
| a repository with no commits yet | exit 4, "no history to search" |
| commits, but not one carries a trailer | exit 4, "the mechanism is not in use here; coverage is UNKNOWN" |
| commits, some carrying trailers | a measurement — with the counts it was measured from |
| no file could be listed (`--coverage`) | exit 4, "nothing was scanned" |
| files scanned, no `COV_` id anywhere | exit 4, "the convention is not in use here" |

Every measured report prints how many commits it walked and how many carried a
trailer, so an answer that came from a shallow clone or a stray branch can be
recognised as one instead of believed.

## 5 · What this cannot do

The trailer says a commit **claims** an id. It does not say the requirement is
implemented, correct, or finished, and nothing here checks that the diff has
anything to do with the requirement it cites. A coverage id says a token
naming a requirement exists in the tree — not that the test runs, and not that
it passes. Both are pointers for a reader, in the same spirit as
`scripts/drift-reverse.sh`: they find the places worth reading and refuse to
call the rest clean.

The full list, with the reproductions behind it, is in **KNOWN_LIMITATIONS.md**
at the repository root. The one worth knowing before you start:
**`git commit --amend -m` destroys the trailer.**

## 6 · A citation this change adds that resolves to nothing — `scripts/check-citations.sh`

Sections 1 to 5 trace an id after it is written. Nothing checked an id **at the
moment it is written**. A plan, a coverage claim in `checks.yaml`, a comment or
a commit trailer can name an id the spec does not hold, and it reads exactly
like provenance. `check-citations.sh` reads the lines a change **adds** and
resolves every requirement id on them against the spec the change ends at.

```sh
check-citations.sh --base REF [--head REF] [--root DIR]
check-citations.sh --version | --help | --selftest
```

Adapted from the `DANGLING_REF` rule of the AI Unified Process (Apache-2.0, by
Simon Martinelli), whose spec linter refuses a reference to a requirement that
is not in its requirements file. The idea is theirs; the code is not. What is
added here is the split on the counter, the diff scope and the supersede note.

| Output | Meaning | Changes the exit code |
|---|---|---|
| `FINDING CITATION_NEVER_ALLOCATED <path>:<line> <id>` | the id is at or above `Next requirement id`. It was never handed out: a typo, an invention, another product's id, or an example | yes |
| `FINDING CITATION_ALLOCATED_MISSING <path>:<line> <id>` | the id is below the counter and the spec has no row for it. It was handed out and its row is gone, or it lives in a spec file this check does not read | yes |
| `FINDING TRAILER_UNKNOWN_ID <sha> <id>` | a commit in `BASE..HEAD` carries a `Productizer-Req:` id the spec does not hold, as `req-trailer.sh --validate --rev <sha>` reports it | yes |
| `FINDING TRAILER_MALFORMED_ID <sha> <token>` | the same trailer carries a token that is not an id at all | yes |
| `NOTE CITATION_SUPERSEDED <path>:<line> <id> -> <id>` | the id resolves, but to a superseded requirement. The note follows the `Superseded by` chain to the requirement that stands now | no |
| `NOTE CITATION_WITHDRAWN <path>:<line> <id>` | the id resolves to a withdrawn requirement | no |
| `EXAMPLE <path>:<line> <id>` | the id sits inside an EXAMPLE block and was not resolved | no |

The two findings are split on the counter because they have different repairs,
the same line `drift-reverse.sh` draws between its signals B and D. Exit `0`
means every added citation resolves, `1` means at least one `FINDING`, and `2`
is a refusal that names its reason: no `--base`, a base or head that does not
resolve, a shallow clone missing the base or the merge base, no spec at HEAD, a
spec with no requirement definitions or no readable counter, or
`req-trailer.sh` answering in a way the check cannot read. A commit with no
trailer is counted and is not a finding here; that is `--orphans`' question.

**What it reads.** Only lines added in `git diff BASE...HEAD`, over tracked
files, with the spec read at HEAD through `spec-requirements.sh`. A citation
that was already in the tree at the base is `drift-reverse.sh`'s business, not
this check's. It does not read paths under `fixtures/` or `evals/`, which carry
their own numbering (the measurement is in `check-suspect-links.sh`); the spec,
`constitution.md` and `backlog.md`, whose citations `validate-spec.py` owns;
or the generated `requirement-index.md`, whose currency
`build-requirement-index.sh --check` already asserts.

### Example ids, measured

A tool about requirement ids writes a lot of ids that are not citations:
self-test corpora, documentation of the id grammar, an output quoting another
tool. Run over every commit in this repository's history, each against its
parent, with the spec as it stood at that commit:

| | Commits |
|---|---|
| in history | 132 |
| refused, no spec yet (22) or no parent (1) | 23 |
| measured | 109 |
| exit 0 | 84 |
| exit 1 | 25 |

Those 25 commits carried 92 findings: 86 never allocated and 6 allocated but
missing. Read one by one, **none was a citation anybody meant**. 28 were the
`contradiction-check.py` self-test corpus, 27 other self-test strings and
script comments, 16 Markdown prose illustrating the id grammar, 11 `why:` and
comment prose in `checks.yaml`, and 10 a generated result file that quoted
another tool's output and is no longer tracked. The 6 missing ones are all the
sentence explaining that ids carry no leading zero. So on this repository the
precision of a finding is zero over its whole history, and one commit in four
would have shown one. That reading of the 92 lines is a judgement, not a
measurement.

One exclusion rule was measured and **rejected**: skip an id inside backticks
or double quotes. It removes 67 of the 92, and it also stops checking 594 of
the 2,351 tokens naming an allocated id in the tree at v4.65.1, a quarter of
them, because a coverage claim's `reason:` and a doc quote real ids as readily
as an example does.

The rule adopted instead costs no coverage, because it is explicit: **an id
between a line that starts with `<!-- EXAMPLE:BEGIN` and the next line that
starts with `<!-- EXAMPLE:END` is not resolved.** Leading whitespace and a `#`
or `//` comment leader are allowed before the marker. It is the marker
`format-spec.md` section 6 already defines, and `validate-spec.py` and
`scaffold.sh` already honour it. The ids inside are still printed, as
`EXAMPLE` lines, so the marker is visible rather than silent, and a `BEGIN`
with no `END` after it skips nothing: a malformed marker fails toward
reporting. The marker must START the line, where `validate-spec.py` accepts it
anywhere in one, and that was measured: run on the commit that lands this
check, the anywhere-in-the-line rule made 31 lines of the check's own
self-test an example block, because code that builds a marker mentions it. It suppresses none of the 92 historic
findings, since none of those lines was marked. It is what a writer uses from
now on, around a worked example:

<!-- EXAMPLE:BEGIN -->
```
FINDING CITATION_NEVER_ALLOCATED notes/plan.md:12 R999
NOTE CITATION_SUPERSEDED notes/plan.md:14 R14 -> R33
```
<!-- EXAMPLE:END -->

In a script, the same marker after a `#` or `//` works, and so does building
the id rather than writing it - the self-tests of this check and of
`req-trailer.sh` write `R$((4 + 3))`, for the reason section 2 gives for
coverage ids.

### What it cannot see

- A citation is a token, `R` and digits with no letter, digit or underscore on
  either side. `R9.1` cites R9. Git's rename score, a storage product or a
  register named the same way is indistinguishable from a citation.
- One spec path, `.claude/productizer/spec.md`. A spec split across files, or
  moved by `config.json`, reads as missing requirements.
- `req-trailer.sh` matches ids with its own pattern, not `spec-requirements.sh`,
  so the two halves can disagree about an id written in bold outside the
  `## Requirements` section.
- A citation is resolved, never read: an id that exists, cited in a sentence
  about something else, is clean.

