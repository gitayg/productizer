# `fixtures/arch-graph/`

`build-view.sh` derives a declared architecture graph from
`.claude/productizer/checks-result.json` and overlays every active requirement
with one of five states: `measured`, `never_ran`, `void`, `guard_shut`,
`missing`.

**This repository's own result file reaches two of the five.** Measured on
2026-09-07 against `.claude/productizer/checks-result.json` at v4.56.0:

    35 requirements, all `exercised: true`
    38 claims, all `check_status: pass`, none voided
    verdicts: Covered 20, Partial 12, n/a 3, Missing 0

So the live file exercises `measured` (32 requirements) and `guard_shut`
(3 — R10, R27, R28) and nothing else. A self-test driven only by this
repository would exercise two branches of five and could ship the other three
broken without a single case going red. That is the "a control asserting over
an empty set" failure this repository has already shipped more than once, and
the reason `check-ruling-requested.sh` and `check-spec-home-stop.sh` both
drive committed fixtures rather than the live tree.

`five-states.json` is that fixture: a `productizer.checks.result/1` document
built so that each of the five states has exactly one requirement in it, and so
that the state is reached the way the real runner reaches it, not by writing
the state name into the file. `build-view.sh --selftest` drives it and asserts
the whole per-requirement state map, so a deriver that collapses two states, or
loses one, goes red.

## What each requirement in `five-states.json` is for

| id | state | how the fixture reaches it |
|---|---|---|
| `F1` | `measured` | claimed `Covered` by `alpha`, whose status is `pass` and whose claim is not voided |
| `F2` | `void` | claimed `Covered` by `bravo`, whose status is `fail`; the runner voids the claim, so the requirement falls back to `Missing` with `exercised: false` |
| `F3` | `never_ran` | claimed `Covered` by `charlie`, whose status is `not_triggered`; the claim is live (nothing voided it) but no passing check stands behind it |
| `F4` | `guard_shut` | claimed `n/a` by `delta`, which ran and reported the obligation unreachable in this configuration |
| `F5` | `missing` | no check in the fixture names it at all — the claim list is empty |

`F2` and `F3` both end at `verdict: Missing` / `exercised: false`, and they are
in the fixture together on purpose: they are the pair a deriver is most likely
to collapse. A requirement whose evidence was destroyed by a failing check and
a requirement nobody ever ran lead to two different next actions — fix the
check, versus trigger it — and a page that draws them the same way sends a
reader to the wrong one.

## What the fixture also exercises, deliberately

- **A tool named through an interpreter.** `echo`'s command is
  `python3 .../fixture-tool.py`, so the tool node is `fixture-tool.py`. A
  deriver that takes `command[0]` names every such check `python3` and
  collapses them onto one node.
- **A tool whose version probe failed.** `charlie`'s probe exits 1, so its tool
  node is `present: false`. Every probe in this repository's live result exits
  0, so `present: false` exists nowhere but here.
- **A tool shared by two checks.** `alpha` and `foxtrot` both run
  `check-alpha.sh`, so the fixture has 6 checks and 5 tools. That inequality is
  true of this repository's live file too — 32 checks, fewer tools — and is why
  `counts.tools` is measured rather than assumed equal to `counts.checks`.
- **A check that claims nothing.** `foxtrot` makes no coverage claim, so it is a
  node with a `runs` edge and no `claims` edge.
- **Dropped files.** `alpha` drops one deleted and one absent path, so
  `files_dropped` is 2 against 4 handed over.
- **An untriggered check.** `charlie` is `triggered: false`, so it appears in
  `delta.checks_not_triggered` and its requirement is not in
  `delta.requirements_touched`.

Nothing here is a real check, a real requirement or a real tool. The ids are
`F*` and `fixture-*` so that a fixture row can never be mistaken for a row
about this repository.

## `delta/` — the spec delta between a base and the working tree

`delta.spec` needs a git history, and neither this clone's history (an
installed copy has none) nor a hand-typed sha is something a test can stand
on. So `--arch-selftest` builds a repository at test time:

- `base-spec.md` is committed as `.claude/productizer/spec.md` with the author,
  committer, both dates and the message pinned and the user's git configuration
  shut out, so the commit is `022fb0cd90adce89e6759dbc159a67f5f5965766` on every
  machine. `result.json` names that sha as `change.base`, and A10 asserts the
  built sha equals it — an edit to `base-spec.md` that forgets `result.json`
  goes red rather than comparing against nothing.
- `spec.md` is then written over it, uncommitted: the working tree is head.
- `result.json` is `five-states.json` with `F1..F5` renamed `R1..R5` (the
  parser reads `R<n>` ids only) and each unit's text taken from `spec.md`.

| id | base | head | reads |
|---|---|---|---|
| `R1`, `R5` | active | identical | unchanged |
| `R2` | active | sentence rewritten | `changed` |
| `R3` | active, one line | same sentence re-wrapped over two | unchanged |
| `R4` | absent | active | `new` |
| `R6` | active | `Superseded by R4.` | `superseded` |
| `R7` | active | `Withdrawn.` | `withdrawn` |
| `R8` | active | absent | `removed` |
| `R9` | superseded by R1 | identical | unchanged — superseded already, so not newly |
| `R10` | superseded by R6 | superseded by R4 | `changed` — only the pointer moved |

To render it: build that repository by hand the same way, copy `result.json`
to its `.claude/productizer/checks-result.json`, and run `build-view.sh` on it.
