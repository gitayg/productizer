# Review record — <issue> <short title>

Rethink: —

## Rounds

| Round | Base | Head | Findings |
|---|---|---|---|
| 1 | <commit this round diffed from> | <commit it reviewed> | <the count, or no issues> |

## Findings

| Id | Round | Severity | Location | Class | Status | Reason |
|---|---|---|---|---|---|---|
| F1 | 1 | <Important, Nit or Pre-existing> | <path:line> | <the bug class, not the one instance> | open | — |

---

Every review round of one change, and how each finding was answered. Commit it
beside the change's plan as `<artifacts.path>/review.md`, and append to it: a
round is a row, never a rewrite of an earlier one. The `review-record` check
(`scripts/check-review-record.py`) reads it against `REVIEW.md`.

**Rounds.** One row per review pass. `Base` and `Head` are commit ids. Round 1
diffs from the change's base; every later round starts from the commit the
round before it ended at, so it reviews only the new diff. `Findings` is the
number of rows below with that round, or the words `no issues` when there are
none — never `0`, never blank: a summary with no count cannot be told from one
nobody wrote.

**Rethink.** After three rounds the author stops patching and rethinks the
approach. A fourth round is refused until the `Rethink:` line above names the
approach that replaced the patching.

**Findings.** Each one carries:

- **Severity** — `Important` (breaks behaviour, leaks data, breaches policy),
  `Nit` (style, naming, preference), or `Pre-existing` (a bug this change did
  not introduce: reported, never charged to it).
- **Location** — `path:line` or `path:line-line`, relative to the repository
  root. A path `REVIEW.md` lists under *Ignored paths* is not reviewed.
- **Class** — the whole bug class, not the one instance, so the author fixes
  every instance and the next round does not find the second one.
- **Status** — `open`, `fixed`, `rejected`, `intentional` or `irrelevant`.
  Every status but `open` states a **Reason**; for `fixed`, the commit that
  fixed it. A later commit that fixes a finding closes it here.

A finding already reported is not reported again: the same location and class
in a later round is refused. **An Important finding left `open` fails the
check, and so blocks the stage.** The way out is the existing waiver
(`templates/waiver.md`) naming the `review-record` check, which a named person
signs and which expires; the check still reads failed and waived, never passed.

The tally of how findings were answered — fixed, rejected, intentional,
irrelevant, open — is printed on every run: it is the measure of a reviewer's
noise.
