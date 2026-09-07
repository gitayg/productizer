# spec-kit input — `--format speckit`

`validate-spec.py --format speckit SPEC.md` reads a GitHub
[spec-kit](https://github.com/github/spec-kit) `spec.md`, rewrites its notation
into the grammar in `references/format-spec.md` **in memory**, and runs the
existing checks against the result. The file on disk is never written. The
adapter is `scripts/speckit_adapt.py`.

The point is not that Productizer's format is better. It is that **enforcement
is separable from authoring**. A spec-kit spec and a Productizer spec carry the
same semantic content — one behaviour per bullet, an id, a modal obligation —
in different notation. Seven purely mechanical line rewrites move the notation
across, and the EARS and id checks then apply to a document nobody wrote for
them.

## Running it

```
validate-spec.py --format speckit specs/001-my-feature/spec.md
validate-spec.py --format speckit --baseline OLD.md specs/001-my-feature/spec.md
```

Diagnostics are reported against the **source** line number, not against an
offset in the adapted text, so a finding names the line the author would edit.
`--counts` is refused under `--format speckit`: it compares the header's
declared totals with the file, and a spec-kit header declares none. So are
`--kind constitution` and `--kind backlog` — the adapter produces a spec.

Every adaptation line is prefixed `speckit:`, and **`--quiet` does not
suppress them**. `--quiet` drops the summary line; a quiet run that also
dropped the `n/a` block would silently skip seven families of check and print
nothing about it, which is the thing the block exists to prevent. Filter on the
prefix if you only want the `path:line:` records.

## The seven rules

Every rule is a substitution on **one line**, decided by that line alone.
Nothing is invented, reordered, merged, split or reworded. A line no rule
matches is copied through byte for byte **and reported** on the
`passed through, no rule matched` line, because a silent pass-through is
indistinguishable from a rule that worked.

| # | Rewrite | Why it is needed |
|---|---|---|
| 1 | `## Requirements *(mandatory)*` → `## Requirements` | `detect_kind` matches `^##\s+Requirements$` anchored at end of line. The template's annotation alone is what makes an otherwise well-formed spec exit 4 `KIND_UNKNOWN`. |
| 2 | `### Functional Requirements` → `### Ubiquitous` | The Productizer grammar names an EARS pattern class in the sub-heading. spec-kit has one requirements sub-heading and no pattern classes, so there is no claim to preserve — this rule **synthesises** one. |
| 3 | `FR-0NN` → `R<n>` | Id shape. Leading zeros dropped, `FR-` prefix dropped. `FR-007` → `R7`. |
| 4 | `:` after the id → em dash | `BULLET_RE` reads the character after `**id**` as the separator, and the em dash is the grammar's canonical one. Measured by disabling this rule alone on the corpus: the requirement text still parses, but every requirement raises `ID_SEPARATOR` — 14 warnings on 14 requirements. |
| 5 | `System MUST` → `The system shall`; `System MUST NOT` → `The system shall not`; `Users MUST be able to` → `The system shall allow users to` | EARS wants a named system and `shall`; spec-kit writes RFC 2119 `MUST` with an implicit subject. Anchored at the start of the requirement body, longest form first. |
| 6 | `### Key Entities` → `## Key Entities` | Not cosmetic. At level 3 the section stays **inside** `## Requirements`, and every entity bullet under it is then read as a requirement bullet with no id — one `ID_MALFORMED` per entity. Promoting it to level 2 closes the requirements section where spec-kit means it to close. |
| 7 | synthesise `Next requirement id` | spec-kit records its allocator nowhere. This field is **derived** from the file: one above the highest FR id present, inserted immediately before the `## Requirements` heading. |

Rule 6 runs before the bullet rules: it decides where `## Requirements` ends,
and reading it later would already have mis-read the bullets it exists to move
out of the way.

## What survives the crossing

These checks apply to adapted text exactly as they apply to a hand-written
Productizer spec, and a finding from any of them is a finding about the
spec-kit spec:

- **The whole EARS family** — `EARS_NO_SHALL`, `EARS_PATTERN`,
  `EARS_MULTIPLE_SHALL`, `EARS_EMPTY`, `EARS_NO_FULL_STOP`,
  `EARS_IF_MISSING_THEN`, `EARS_UNQUANTIFIED`, `EARS_VAGUE_QUANTITY`.
- **Id hygiene within the file** — `ID_MALFORMED`, `ID_REUSED`,
  `ID_OUT_OF_ORDER`, `TEXT_DUPLICATE`.
- **The permanence family, but only with `--baseline`**, and only against an
  earlier copy of the **same** feature directory's `spec.md` — see the scope
  note below.

## What is structurally impossible

`--format speckit` prints these as `n/a` and does not run them. **A check that
cannot apply is `n/a`, never a pass.** The count rides on the summary line so a
zero-error run cannot be quoted as a clean bill of health.

| Reported `n/a` | Why it cannot apply |
|---|---|
| `STATUS_DUPLICATE`, `STATUS_MALFORMED`, `STATUS_NO_REASON` | spec-kit records no per-requirement status. Every adapted requirement is active by construction. |
| `SUPERSEDE_SELF`, `SUPERSEDE_BACKWARD`, `SUPERSEDE_TARGET_ABSENT`, `SUPERSEDED_TEXT_OVERWRITTEN` | spec-kit has no supersession. A changed requirement is edited in place or appended, never marked as replaced by another id. |
| `COUNTER_MISSING`, `COUNTER_MALFORMED`, `ID_AT_OR_ABOVE_COUNTER` | The allocator is synthesised by rule 7 *from the ids in the file*, so it cannot disagree with them. Nothing is compared. |
| `COUNT_MISMATCH` | A spec-kit header declares no active/superseded/withdrawn totals, so there is no declared number to re-count against. |
| `CITATION_UNKNOWN` | spec-kit has no `## Acceptance criteria`, `## Change log`, `## Decision record` or `## Design` section, and its acceptance scenarios cite no requirement ids. No citation is resolved. |
| `EARS_SECTION_MISMATCH` | Rule 2 wrote the `### Ubiquitous` heading the requirement would be judged against. A mismatch measures the adapter's guess, not the spec. This is the one on the list that genuinely *can* fire; dropping it is a fairness rule, not a convenience. |
| `RENUMBERED`, `ID_DISAPPEARED`, `ID_IDENTITY_CHANGED`, `SUPERSEDED_TEXT_CHANGED`, `COUNTER_REWOUND` | Reachable only with `--baseline`. Listed as `n/a` when it is absent; when it is given these run and the family count drops by one. |

**Id scope.** spec-kit ids are unique within one `specs/<nnn>-<slug>/`
directory and every directory starts again at `FR-001`, so `R1` in two feature
directories is two different requirements. A `--baseline` comparison is only
meaningful against an earlier copy of the same directory's `spec.md`.

That scope is also why the **cross-file** checks — `ID_DEFINED_TWICE` and
citations resolved against sibling spec files, added 2026-09-06, and
`COUNTER_DISAGREES`, `SIBLING_ID_AT_OR_ABOVE_COUNTER` and
`TEXT_DUPLICATE_ACROSS_FILES`, added 2026-09-07 — are **not applied** under
`--format speckit`. A Productizer spec split across several files is one spec
with one id space; two spec-kit `spec.md` files are two id spaces that both
start at `FR-001`, so every id would collide and every collision would be rule
3's doing rather than the author's. The allocator checks fail the same way for
a second reason: rule 7 *synthesises* the `Next requirement id` field a
spec-kit file does not carry, so comparing two synthesised allocators would
compare the adapter with itself. The same fairness rule that makes
`EARS_SECTION_MISMATCH` `n/a`. A run given more than one spec-kit file prints
the suppression on a `speckit:` line, naming all five, and says in it that not
applied is not a pass; it is **not** counted in the `n/a` family total, which
reports what `speckit_adapt.py` declares.

**`--repo` and spec-kit do not combine, and that is a refusal rather than a
gap.** `--repo ROOT` discovers a Productizer spec from `spec.path`; a spec-kit
repository keeps its specs under `specs/<nnn>-<slug>/spec.md`, one id space per
directory, which is not the thing `--repo` is describing. The two are a usage
error together rather than a silent adaptation of one into the other.

## Being fair to spec-kit

Three corrections to easy but wrong readings, all of them checked rather than
assumed:

**The per-feature directory scope is a design choice, not a defect.** Ids are
stable within it. Measured on the experiment corpus: an update run that added
two requirements to `specs/001-archive-old-files/spec.md` left `FR-001`
through `FR-012` byte-for-byte identical and appended `FR-013` and `FR-014`.
Adapting the pre-update and post-update files and diffing the first twelve
requirement lines gives an empty diff. Nothing was renumbered.

**`/speckit-analyze` does detect conflicting requirements.** Its own skill file
lists "Duplication Detection", "Conflicting requirements", and grades a
"Duplicate or conflicting requirement" as **HIGH**. The difference from
`contradiction-check.py` is LLM judgement versus deterministic interval
arithmetic — not presence versus absence of the capability.

**An earlier claim in this project that spec-kit "commits zero specs of its
own" was wrong**, and is retracted here rather than repeated. The `.gitignore`
entries in question exist to keep machine-local dogfooding scaffolding out of
the repository, and the comments above them say so. The generated project's
`.specify/.gitignore` opens with "Machine-local Spec Kit state — not meant to
be shared", and ignores a per-checkout pointer file and per-machine config
overrides. Take the charitable reading first; it is usually the correct one.

*Not verified in this run:* spec-kit's own repository `.gitignore` was not
fetched, so the retraction above rests on the generated project's copy and on
the general shape of the claim, not on the exact upstream line.

## The measured evidence

Corpus: a real `specify-cli` project (`speckit_version` `1.0.5.dev0`,
recorded in `.specify/init-options.json`), one feature directory, fourteen
functional requirements, generated and then updated by a real CLI run.

**Native validation refuses the file.**

```
$ validate-spec.py specs/001-archive-old-files/spec.md
spec.md:1: ERROR KIND_UNKNOWN: not a Productizer spec, constitution or
  backlog: no `## Requirements`, `## Principles` or `Next backlog id`.
  Nothing was checked
NOT MEASURED: spec.md. No counts are reported for it -- a file that was
  not read has not passed.
→ exit 4
```

**Adapted validation reads it, and finds something real.**

```
$ validate-spec.py --format speckit specs/001-archive-old-files/spec.md
...
spec.md:101: WARN EARS_UNQUANTIFIED: R7 uses the unquantified term
  `sufficient`; give a number or drop it
1 file(s) checked: 0 error(s), 1 warning(s), 7 check family(ies) n/a
→ exit 0
```

Line 101 is `FR-007`, whose text is "System MUST record **sufficient**
information about each archived file…". The spec-kit-generated checklist for
this same feature — `checklists/requirements.md`, line 17 — already carries
`- [x] Requirements are testable and unambiguous`. An unquantifiable adjective
inside a requirement that a generated checklist has ticked as unambiguous is
exactly the class of defect a deterministic grammar catches and a judgement
pass does not.

**The contradiction checker, stated precisely.** `contradiction-check.py` takes
one requirement per line as `R<n>: <text>`, which is a different input shape
from the bullet grammar, so the requirement lines have to be extracted and
reshaped; `--format speckit` does not feed it. With that done:

| Invocation | Native `FR-0NN: System MUST …` | Adapted `R<n>: The system shall …` |
|---|---|---|
| `--pair A B` | `one or both statements are not EARS`, **exit 2** | parses; verdict returned, exit 0 or 1 |
| `FILE` (14 requirements) | 14 × `unparsed (…, not an EARS pattern)`, then `0 requirements, 0 pairs: nothing decidable as a contradiction`, **exit 0** | 3 halts on `R5/R7`, `R5/R10`, `R7/R10`, **exit 1** |

Two things are worth stating exactly, because both are easy to overstate:

- The three halts are **`UNDECIDED`, not `CONTRADICTION`**. In file mode
  `run_file` returns 1 for *any* halt, and `UNDECIDED` is by that tool's own
  design "the escape hatch: anything outside the fragment is handed back for
  judgement instead of being silently passed". Nothing in this corpus was
  decided to be a contradiction. A claim that the adapted run "found a
  contradiction" would be wrong.
- The native file-mode run exits **0**, not 2. That is the more alarming half:
  fourteen requirements went unparsed and the run still returned success,
  because a corpus of zero parsed requirements has zero contradictory pairs.

## Each rule falsified

Every rule was disabled on its own against the corpus and the consequence
observed, rather than argued from the code:

| Rule broken | What went red |
|---|---|
| 6 (`### Key Entities`) | `--format speckit` exit 0 → **1**, with five `ID_MALFORMED` errors at source lines 112–116 — one per entity bullet, each reported under its entity name as if it were a requirement id. `--self-test` exit 0 → **3**, five findings. |
| 4 (`:` → em dash) | 14 `ID_SEPARATOR` warnings where there were none. `--self-test` exit 0 → **3**. |

Restoring each returned the run to exit 0 with one warning and the self-test to
`25 fixtures, 0 failures`, which is what `--self-test` printed when this
section was written.

**Re-observed 2026-09-07 — the self-test now prints `41 fixtures, 0 failures`.**
Nine further fixtures landed with the per-repo discovery work: red and green
pairs for `COUNTER_DISAGREES`, `SIBLING_ID_AT_OR_ABOVE_COUNTER` and
`TEXT_DUPLICATE_ACROSS_FILES`, one for the same id in both halves being
`ID_DEFINED_TWICE` and not also a text duplicate, one proving all three inert
on a single file, and one that drives `main --repo` against a real directory
tree — including the case that falsifies discovery itself, two spec files on
disk with the config declaring only one. The paragraph below is the record of
the previous measurement and is left as written.

**Observed 2026-09-06 — the self-test then printed `32 fixtures, 0 failures`.**
The number above is left as it stands because it is a record of what was
measured then, not a specification. Two things moved it, neither of them a
change to the adapter or to any rule in the table:

- **Six fixtures were added**, for the cross-file checks described under *Id
  scope*: `ID_DEFINED_TWICE`, the citation union, the two directions of
  inertness on a single file, and one fixture that drives `main` on real files
  rather than assembling the sibling index itself. That last one earns its
  place: deleting the index-building call from `main` was tried, and every
  other new fixture stayed green while a real two-file split went back to
  0 errors and 29 false warnings.
- **The count is no longer typed.** `--self-test` derives it from a registry of
  named cases, under a rule stated beside that registry: one entry per named
  case, registered by `run`, `run_set` or an explicit `case(...)`; supporting
  documents another case needs — a baseline, a spec a constitution resolves
  against — are not cases. Under that rule the fixtures that existed before
  this change count **26**, not 25. The 25 was a hand-maintained literal whose
  counting rule was never written down, so the difference is a difference of
  rule and is not evidence that a fixture was lost.

What was **not** re-measured: the two rows in the table above and the
`## Being fair to spec-kit` measurements were taken against an external spec-kit
experiment corpus (`specs/001-archive-old-files/spec.md`) that is not in this
repository, and it was not re-run. What was re-measured is that single-file
`--format speckit` output is byte-identical to the same command at `8216ab6` —
so nothing in this document's spec-kit behaviour changed, only the count on the
last line of `--self-test`.

## Known limitations

- **The adapter is deliberately shallow.** Anything spec-kit writes outside the
  seven shapes above is carried through untouched. That is reported, not
  silently absorbed, but it means a spec-kit spec whose requirement bodies use
  other phrasings will produce `EARS_PATTERN` findings that are about the
  adapter's coverage rather than about the requirement.
- **`### Functional Requirements` is the only requirements sub-heading
  recognised.** A spec-kit spec with a `### Non-Functional Requirements`
  section keeps that heading, and its bullets are read with no pattern-section
  claim attached.
- **User-story acceptance scenarios are not touched.** spec-kit's
  Given/When/Then scenarios live under the user stories, cite no ids, and have
  no Productizer counterpart in this adaptation. `check-acceptance-rows.sh`,
  which reads a named acceptance table, has nothing to read.
- **Only `spec.md` is adapted.** spec-kit's `plan.md`, `tasks.md`, checklists
  and `.specify/memory/constitution.md` have no adaptation here. In particular
  a spec-kit constitution is *not* readable as a Productizer constitution, and
  `--format speckit --kind constitution` is refused rather than attempted.
