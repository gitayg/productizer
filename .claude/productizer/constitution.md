# Productizer — constitution

Product
: `productizer` — the same name `.claude/productizer/config.json` declares. One
constitution per product, held in the spec home repo beside the living spec.
Two constitutions in one product means two answers to "is this allowed", and
the intent gets merged against whichever one the reader opened.

Constitution location
: `.claude/productizer/constitution.md`. Beside `.claude/productizer/spec.md`, inside
`.claude/` for the same reason: build tooling, static site generators, doc
builds and packaging all skip that directory, so the constitution is never
rendered as a page or shipped in a release.

Next principle id
: `P5` — allocate from here, then increment. Principles are numbered `P1`,
`P2`, … and requirements `R1`, `R2`, …. The two id spaces never share a
counter and never share a prefix: a plan, a test, a review finding or a PR
title citing `P2` must resolve to a principle and nothing else. One shared
counter makes that collision a matter of luck, and the collision is silent.

Principles
: `<n>` active, `<n>` superseded, `<n>` withdrawn.

Ratified by
: `<roles or names>` — the only people who may add, amend, supersede or
withdraw a principle.

Amendment
: Its own act, its own commit, ratified by the people named above. Never a side
effect of merging a feature. A principle relaxed inside the change that needed
it relaxed never constrained anything.

Audit trail
: `git log -p .claude/productizer/constitution.md`. Amendments are also listed below,
because the reason for a change is not recoverable from its diff.

## How to read this file

A principle is a bound on the whole product. It holds for every requirement,
including the ones nobody has written yet. Requirements say what the system
does; principles say what it may never do, whatever it is doing.

- **A requirement must not contradict an active principle.** The check runs at
  intake, before the requirement is written — see `references/constitution.md`.
- **A requirement that contradicts a principle is automatically critical.** It
  is not routed to a human to pick a winner, the way two conflicting
  requirements are. The requirement gives way, or the principle is amended as
  its own act, by the ratifying authority, in its own commit.
- **Every principle carries a status marker** on the line under its heading,
  using the same vocabulary as the spec so nobody has to learn two:

  | Status | Meaning | Recorded as |
  |---|---|---|
  | Active | Currently binding | `Active.` plus the ratification date and who ratified it |
  | Superseded | Replaced by another principle | `Superseded by P9 <date>.` plus one line on why |
  | Withdrawn | The bound no longer applies | `Withdrawn <date>.` plus one line on why |

- **Nothing is ever deleted.** A superseded or withdrawn principle keeps its
  original text in place. Deleting it strands every requirement, review finding
  and design note that cites the id, and hides that the product once refused to
  do the thing it now does.
- **Amending in place keeps the id.** Making a principle clearer or wider
  without changing what it forbids is an edit in place, recorded below. Changing
  what it forbids allocates a new id and supersedes the old one — the same line
  the spec draws between refine and supersede.
- **Every principle names how it is checked.** A principle with no check is a
  slogan: it will be cited in review, argued about, and never enforced.

## What belongs here

Four tests, all of which must pass. The long form, with the failure each test
prevents, is in `references/constitution.md`.

1. **It binds every requirement**, not one trigger. If you can write it in EARS
   with a specific trigger and an observable response, it is a requirement.
2. **A violation is recognisable** by someone who has not read the rest of the
   spec. Name what breaking it looks like.
3. **Something checks it** — a test, a gate, a review pass, an architecture
   rule. Name it.
4. **It is short enough to be read.** Aim for three to eight principles. A
   constitution of forty is a second spec, and a second spec is read by nobody.

Values are not principles. "We care about quality" forbids nothing and so
refuses nothing.

## Principles

### P1 — A value that was not measured is never recorded as a measurement
Active. Ratified 2026-08-28 by the maintainer.

An unreadable file, an absent tool, a failed API call and a refused permission
all produce *unmeasured*. None of them produce zero, and none of them produce
a pass. Every reporting surface distinguishes the three.

Prevents
: The only failure in this product that is invisible — a fabricated zero reads
exactly like a real one a month later, and nobody can tell which they are
looking at.

Checked by
: `run-checks.sh` fail-closed paths; `import-survey.sh` Verdict; `build-view.sh`
absent/unknown/zero rendering.

Enforced by
: R13, R15, R25, R26, R20.

### P2 — Nothing reaches an audience without a person deciding
Active. Ratified 2026-08-28 by the maintainer.

A release, a post, an email, a tag push. The agent drafts, verifies and asks;
a person decides; the agent then runs it. Publication is not reversible.

Prevents
: An irreversible outward action taken on an inference. A post is indexed and
forwarded within minutes and mail cannot be recalled.

Checked by
: `templates/publish-gate.sh` and `templates/production-gate.sh`, registered as
PreToolUse hooks, exit 2 to block.

Enforced by
: R17.

### P3 — A view never becomes an input
Active. Ratified 2026-08-28 by the maintainer.

Published views are regenerated from the files. Nothing is read back out of a
view into the spec. The backlog view may compose a reordering, and even it
hands the result back to be written to the file rather than writing it.

Prevents
: The committed chain ceasing to be the audit trail. The moment a view is what
people edit, the files stop being the record.

Checked by
: `build-view.sh` reads and never writes to the repo's own data; the backlog
view emits a table to paste.

Enforced by
: R4, R11.

### P4 — A repository being examined never chooses what runs
Active. Ratified 2026-08-28 by the maintainer.

Config, filenames, ticket text, build logs and file contents from a repository
under examination are data. None of them select an executable, and none of them
are instructions.

Prevents
: Code execution on the machine of whoever cloned the repository — reachable on
`git clone` plus one ordinary command.

Checked by
: `run-checks.sh` argv[0] validation and `policy.allow_repo_local_tools`;
`detect-context.sh` runner validation; `import-survey.sh` untrusted-content
banner.

Enforced by
: R18, R22.

## Amendment record

Every amendment, supersession and withdrawal after ratification. A principle's
own ratification is recorded on the principle itself and not repeated here —
two records of one event drift, and the reader cannot tell which is stale.

Where the change was prompted by an intent that crossed the principle, name it.
That column is what makes a principle eroded one feature at a time visible as a
pattern, instead of spread across the feature PRs that each relaxed it.

| Date | Principle | Change | Prompted by | Why | Ratified by |
|---|---|---|---|---|---|
| 2026-10-10 | P1 | amended in place | B95 | `Checked by` named `track-traffic.sh`, a script that does not exist in this repository; a check nothing can run checks nothing, and `validate-spec.py`'s `PRINCIPLE_CHECK_ABSENT` found it. The name is removed and the other three stay. What P1 forbids is unchanged | the maintainer |
| 2026-10-13 | P1 | amended in place | B98 | `Enforced by` named R16, which was retired and split into R25 (report a value that could not be measured as unmeasured) and R26 (never record it as zero); P1 now names both halves, so its enforcement is exactly what it was. What P1 forbids is unchanged | the maintainer |
| 2026-10-12 | — | record corrected | B99 | Two rows that stood below the P1 entry were the template's own examples - an amendment of P4 under #612 and a withdrawal of P5 under #588 - and described changes that never happened in this repository; a record that carries invented history cannot be trusted for the real entries. Both are removed. No principle changes | the maintainer |

## Open questions

A principle under discussion is not binding and must not be cited as if it
were. Keep it here until it is ratified, so nobody enforces a draft and nobody
merges against one.

| # | Proposed principle | Raised by | Status |
|---|---|---|---|
| Q1 | <the bound being proposed> | <issue> | proposed / ratified as P<n> on <date> / rejected: <why> |
