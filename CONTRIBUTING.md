# Contributing

Suggestions are welcome, and they go through the same lifecycle this plugin
describes. That is deliberate: the repo is its own worked example.

## Suggest something

Open an issue with the **Intent** template. It asks for a problem, a proposed
outcome, who it affects, the constraints and the open questions — the shape the
skill uses at Stage 1, not a feature request form.

Describe the problem rather than the implementation. An intent that names a
solution has already made the design decision, and the interesting part of the
decision is usually the part that was skipped.

If it is not yet shaped like a problem, use [Discussions](../../discussions)
instead. Half-formed is fine there.

## What happens to it

Every intent is classified against the living spec:

| | |
|---|---|
| **Extend** | not covered yet — new requirements |
| **Refine** | covered, but imprecise — tightened in place |
| **Duplicate** | already specified — you get the requirement id |
| **Contradict** | conflicts with something agreed — labelled `sdlc:contradiction`, and nothing merges until it is ruled on |

A duplicate is not a rejection. It means the behaviour is specified, so if it is
not working, that is a bug and a more useful thing to know.

A contradiction is not a rejection either. It means two reasonable people want
opposite things, and the ruling gets recorded with its reasoning rather than
settled by whoever asked last.

## Changing the skill

Pull requests are welcome. Two things to know:

- **The skill is prose that an agent follows**, so wording is behaviour. A
  sentence that reads as a suggestion will be treated as one.
- **Requirement ids are permanent.** Never renumber, never reuse. A reused id
  silently redirects every test, plan and PR that cites it.

Match the existing voice: terse, declarative, and honest about what a thing
costs. Every rule in these files earns its place by naming the failure it
prevents — if you cannot name one, the rule probably is not needed.

## Before you push

Commit first, then replay CI against the commit:

```bash
python3 scripts/replay-ci.py
```

It clones the repo into a temporary directory, checks out the commit, and runs
the `checks` job's steps from `.github/workflows/checks.yml` in order, as the
runner would. It prints one line per step and exits 0 only if every step that
ran passed. It never writes to your working tree.

The local suite (`run-checks.sh`) is not enough on its own. It runs against
your working tree, and CI runs against a fresh checkout. That gap let four
failures reach `main` behind a green local run:

- **A check only CI ran.** The workflow validates the spec with `--repo .`,
  and no declared check did, so a stale header count passed locally.
- **Untracked files.** A local run's change set leaves them out, so 198 new
  paths were never risk-classified.
- **A tool only one machine had.** It came from an npx cache, so a check CI
  could not run passed locally.
- **A file a scanner skips by name.** gitleaks allowlists `package-lock.json`,
  so a committed one was never read and `secret-scan` was hollow. Only
  replaying CI's own steps in a clean clone caught it.

It does not replay `uses:` actions, or steps that only install a tool. For
those it uses your machine's copy of the tool, and names it. A step your
machine refuses but CI's runner accepts is reported as **HOST-REFUSED**. The
one measured case is Homebrew's Python refusing `pip install` (PEP 668). It is
excused only when a later step verifies what the install was for. Otherwise it
is a failure. Either way, it is never counted as passed.

The push base defaults to `origin/main` as you last fetched it, which is what
CI will diff against. Run it before you push: afterwards the base equals the
commit and the change set is empty. `--base SHA` sets the base, `--commit SHA`
replays another commit, and `--keep` keeps the clone. A full run takes several
minutes.

## Reporting something broken

Use the other issue template. Include the prompt, the repo state, and what the
skill did instead of what you expected.
