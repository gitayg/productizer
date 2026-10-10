# Spec format — the normative grammar

What `scripts/validate-spec.py` reads, and what it refuses. This file is the
grammar; `references/ears.md` is the reasoning behind the requirement sentences
and the id lifecycle. Where the two disagree, this file describes what the tool
actually enforces and `ears.md` describes what the lifecycle actually wants —
the disagreements that exist today are named under *Known inconsistencies*
rather than resolved by inventing a rule neither file had.

The grammar exists because Productizer's two load-bearing invariants are
otherwise enforced by prose alone:

1. **Requirements are EARS.** One sentence, one obligation, a named trigger and
   an observable response.
2. **Ids are permanent.** Never reused, never renumbered, and a superseded
   requirement keeps its original text verbatim.

Prose loses to a hurried agent at 2 a.m. A grammar does not.

## Severities

| Severity | Means | Consequence |
|---|---|---|
| **ERROR** | The document cannot be parsed, or a permanence invariant is broken | A downstream citation stops resolving, or silently resolves to different behaviour. Nothing errors anywhere else — that is what makes it the expensive class. |
| **WARN** | It parses and the ids hold, but the contract is violated in a way something later mangles or half-tests | A requirement with two obligations gets one test. A missing reason line records that something changed and not why. |

`--strict` promotes WARN to failure. Newly written spec content should pass
`--strict`; a spec that predates the validator must at minimum be ERROR-free.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Clean (no ERROR; with `--strict`, no WARN either) |
| 1 | At least one ERROR (with `--strict`, at least one WARN) |
| 2 | Usage error |
| 3 | `--self-test` failed |
| 4 | **NOT MEASURED** — a file could not be read, its kind could not be determined, or it holds no requirements/principles/items to check |

Exit 4 exists because of P1. A spec that was not read has not passed, and the
run prints `NOT MEASURED: <path>` with **no counts at all** rather than
`0 error(s), 0 warning(s)`. A fabricated zero reads exactly like a real one a
month later.

## Output form

```
<file>:<line>: <SEVERITY> <CODE> <message>
```

Greppable, anchored to a line, sorted by `(line, code, message)`. No wall clock,
environment or network is read, so two runs over the same input are
byte-identical.

## Document kinds

Detected from content, overridable with `--kind`:

| Kind | Detected by |
|---|---|
| `spec` | a `## Requirements` heading, or a `Next requirement id` field |
| `constitution` | a `## Principles` heading, or a `Next principle id` field |
| `backlog` | a `Next backlog id` field, or a `# … backlog` title |

Anything else is `KIND_UNKNOWN` at exit 4 — never "clean".

---

## 1. Requirement ids

### Form

```
- **R<n>** — <EARS sentence>
```

- `R` followed by a decimal integer with **no leading zero**. `R7`, never `R07`
  — a citation naming `R7` does not resolve to `R07`, and nothing errors.
- The separator is an **em dash** (`—`). A hyphen or en dash parses but is
  non-canonical.
- The id lives in `**bold**`, in a top-level list item, inside the
  `## Requirements` section. Ids written anywhere else in the file are
  *citations*, not definitions.
- One id space per repo. `R` never shares a counter or a prefix with `P`
  (principles), `B` (backlog) or `D` (rulings).

### Permanence

The counter is declared in the header:

```
Next requirement id
: `R23` — allocate from here, then increment.
```

- It is the **highest id the spec has ever used**, not a count of rows on
  screen. Removing behaviour does not free its id.
- The counter **never rewinds**. Every defined id must be strictly below it; an
  id at or above the counter means the next allocation reuses a live id.
- Ids are **appended**. Within one pattern section they ascend; a descending id
  is the signature of an insertion or a renumber.
- Ids are **unique across the repo**, not the file, so a spec split across
  several files still allocates from one counter.

### Renumbering

Renumbering is prohibited and it is **not fully detectable from one file** — a
spec renumbered wholesale is internally consistent. It is decidable against an
earlier copy, which is what `--baseline` is for:

```bash
git show HEAD~1:.claude/productizer/spec.md > /tmp/spec-before.md
python3 scripts/validate-spec.py --baseline /tmp/spec-before.md .claude/productizer/spec.md
```

Against a baseline, an id whose text now sits under a different id is
`RENUMBERED`, an id that vanished is `ID_DISAPPEARED`, and a rewound counter is
`COUNTER_REWOUND`. Without a baseline the validator can only see the in-file
signatures (`ID_REUSED`, `ID_OUT_OF_ORDER`, `ID_AT_OR_ABOVE_COUNTER`,
`TEXT_DUPLICATE`). See *What the validator does not catch*.

---

## 2. EARS sentences

One requirement is one sentence, ending in a full stop, naming its system
before `shall`. Six patterns, recognised by their opening clause:

| Pattern | Shape | Section heading |
|---|---|---|
| ubiquitous | `The <system> shall <response>.` (also `Every …`) | `### Ubiquitous` |
| event | `When <trigger>, the <system> shall <response>.` | `### Event-driven` |
| state | `While <state>, the <system> shall <response>.` | `### State-driven` |
| unwanted | `If <unwanted trigger>, then the <system> shall <response>.` | `### Unwanted behaviour` |
| optional | `Where <feature is included>, the <system> shall <response>.` | `### Optional` |
| complex | `While <state>, when <trigger>, the <system> shall <response>.` | `### Complex` |

- A requirement matching **no** pattern is an ERROR: it has no trigger a test
  can arrange, or no system that owns the response.
- A requirement with **no `shall`** states no obligation and is an ERROR.
- The pattern must match the section it is filed under. `#### area`
  sub-headings inside a pattern section do not change the pattern.
- `If` without `then` parses but is non-canonical.
- Unquantified terms (`fast`, `robust`, `reasonable`, `appropriate`, `timely`,
  `gracefully`, …) and weak words (`should`, `etc.`, `and/or`, `if possible`,
  `as appropriate`, `easily`, `TBD`, adapted from the AI Unified Process) are
  each an argument deferred to review: `EARS_UNQUANTIFIED`, WARN. Give a number
  or drop the word. Only active requirement text is judged, never a superseded
  or withdrawn one, whose text is retained verbatim; and a term inside a code
  span is a mention, not a use, so a requirement about this check can name
  `should`. The full list is in `references/ears.md`.

Superseded and withdrawn requirements stay in the pattern section they were
written in. There is no archive section — moving them breaks the one thing that
keeps their ids findable.

---

## 3. Status markers

A status marker sits on the line **directly beneath** the requirement, indented
as a continuation of the list item. The id is not repeated — the line above
already carries it.

```
- **R7** — When an intent arrives, the lifecycle shall classify it.
  Superseded by R41. The classification became four-valued.

- **R9** — The lifecycle shall mirror the spec to the wiki.
  Withdrawn. The wiki was retired; nothing consumed the mirror.
```

| Status | Marker | Rule |
|---|---|---|
| Active | *(no marker)* | The requirement, plain |
| Superseded | `Superseded by R<n>.` + one line on why | Points **forward** to a newly allocated, higher id |
| Withdrawn | `Withdrawn.` + one line on why | The behaviour no longer exists at all |

**The original sentence is retained verbatim.** This is the rule the whole
supersession model rests on: a status line without the text it applies to is not
a record, and a superseded requirement carrying its *replacement's* text is a
deletion wearing a marker. The validator catches two forms of the violation —
in-file, a superseded requirement whose text equals its replacement's
(`SUPERSEDED_TEXT_OVERWRITTEN`); against a baseline, any edit at all to a
superseded or withdrawn requirement's text (`SUPERSEDED_TEXT_CHANGED`).

Nothing is ever deleted. A requirement missing from the file but present in the
baseline is an ERROR, not a tidy-up.

---

## 4. Constitution — `P`-numbered principles

```
### P1 — A value that was not measured is never recorded as a measurement
Active. Ratified 2026-08-28 by the maintainer.

<the bound, in prose>

Prevents
: <the failure it prevents>

Checked by
: <the test, gate or rule that enforces it>

Enforced by
: R13, R15, R16, R20.
```

- Heading form `### P<n> — <title>`, inside `## Principles`. An `R`-prefixed id
  here is an ERROR: `R` and `P` never share a prefix, and the collision is
  silent.
- `Next principle id : `P<n>`` is the counter, with the same never-rewind rule
  as requirements.
- The status line is the **first line under the heading**, using the spec's
  vocabulary so nobody learns two:

  | Status | Recorded as |
  |---|---|
  | Active | `Active.` + ratification date and who ratified it |
  | Superseded | `Superseded by P<n> <date>.` + one line on why |
  | Withdrawn | `Withdrawn <date>.` + one line on why |

- Every active principle names a `Checked by`. A principle nothing checks is a
  slogan: it gets cited in review, argued about, and never enforced.
- Under `--repo ROOT`, every backticked token in an active principle's
  `Checked by` that is a script filename (`*.sh`, `*.py`, `*.js`, optionally
  with a directory part) must match the basename of some file under ROOT,
  `.git` excluded. One that does not is `PRINCIPLE_CHECK_ABSENT`, a WARN, on
  the line naming it: the principle cites a check nothing can run. The value
  may wrap over several lines; every line up to the blank one is read.

  | Code | Sev | Fires on |
  |---|---|---|
  | `PRINCIPLE_CHECK_ABSENT` | WARN | an active principle's `Checked by` names a `*.sh`/`*.py`/`*.js` file that no file under the `--repo` root carries the basename of |
- `Enforced by` cites requirement ids. When the spec is passed on the same
  command line, those ids are resolved against it.
- Three to eight principles. Past eight it is a second spec, and a second spec
  is read by nobody.

---

## 5. Backlog — `B`-ids

```
| Id | What is wanted | Status | Jira | Raised | Notes |
|---|---|---|---|---|---|
| B1 | Take one intent through all nine stages | `todo` | — | maintainer, 2026-08-28 | … |
```

- `B<n>`, no leading zero, allocated from `Next backlog id` and kept for life —
  an item that becomes an intent carries its `B` id into the intent.
- `B` never shares a counter with `R`, `P` or `D`.
- Local status vocabulary: `todo`, `long-term`, `in-progress`, `blocked`,
  `done`. **An item naming a Jira key does not carry its own status** — Jira
  owns it, and the vocabulary above does not apply, so the status is not
  checked for those rows.
- File order **is** the priority. There is no priority field to disagree with
  it, and none is checked.

---

## 6. Tolerances — parsed, no diagnostic

Deliberate, and each one exists because the alternative is a false positive on
a document that is correct:

- **`<angle-bracket>` placeholders.** An unscaffolded template writes
  `` `R<n>` `` as its counter and `The <system> shall <response>.` as its
  requirement. Counters, count fields, table rows and requirement sentences
  containing a placeholder are skipped, not failed.
- **`<!-- EXAMPLE:BEGIN … EXAMPLE:END -->` blocks are skipped entirely.**
  Scaffolding deletes them; their contents are worked examples, never agreed
  content. A file whose only requirements live inside an example block reports
  `NO_REQUIREMENTS` at exit 4 — correctly, since it holds none.
- **Wrapped requirement lines** are joined into the sentence above.
- **`#### area` sub-headings** inside a pattern section.
- **Unknown header fields and extra sections** are kept verbatim and ignored.
- **A superseded target in another file** is a WARN, not an ERROR: the spec is
  permitted to split across files, and the validator only ever sees the files
  it was given.
- **Citations are only resolved in five sections** — *Acceptance criteria*,
  *Change log*, *Areas of concern*, *Decision record* and *Design*. *How to read
  this file* quotes `R58` as an illustration and the *Requirement index* is
  documented as optional and frequently stale; resolving ids there produces
  noise, not findings.

---

## 7. Known inconsistencies

Recorded rather than resolved — the shipped files and `ears.md` genuinely
disagree, and picking a winner here would be inventing a rule.

- **One `shall` per requirement.** `ears.md` rule 1 is unambiguous: an `and` in
  the response is two requirements wearing one id. The repo's own
  `.claude/productizer/spec.md` breaks it three times — **R14**, **R16** and
  **R21** each carry two `shall` clauses. Because reality disagrees with the
  rule, the validator reports `EARS_MULTIPLE_SHALL` at **WARN**, not ERROR: the
  real spec stays green by default and fails `--strict` until either the three
  requirements are split or the rule is amended. Reporting it as clean would
  make the rule decorative.
- **Naming the system the same way every time.** `ears.md` rule 2 asks for one
  system noun. The real spec uses four — *the lifecycle*, *every published
  view*, *every check*, *the gate*. Some of those are genuinely sub-components
  and some may be drift, and no grammar can tell the two apart. **Not
  enforced.**
- **The requirement index.** `templates/spec.md` ships an index whose example
  rows (`R1`, `R2 superseded by R41`, `R3 withdrawn`) contradict the real
  requirements carrying those ids. The index is documented as optional until
  the spec passes thirty requirements. **Not enforced, and not cross-checked
  against the requirements.**
- **The amendment record.** The shipped `constitution.md` names `P5` in its
  amendment record while `P5` is also the next unallocated principle id. The
  amendment record is prose about history, not a principle definition, so it is
  not parsed.

---

## 8. What the validator does not catch

Stated plainly, because a checker whose blind spots are undocumented is worse
than no checker: it converts "nobody looked" into "it passed".

- **A renumber, from one file alone.** A wholesale renumber is internally
  consistent. Only `--baseline` decides it. Without a baseline you get the
  signatures, not the fact.
- **A refinement that is really a contradiction.** `200 ms → 100 ms` and
  `200 ms → 500 ms` are the same edit to a text differ. Semantic contradiction
  is `scripts/contradiction-check.py`'s job, and even it reports UNDECIDED
  rather than guessing.
- **Whether a requirement is correct.** EARS makes a requirement unambiguous,
  not right. A precisely worded requirement can still be the wrong thing to
  build.
- **Whether the reason line is true.** `Superseded by R41. Because.` satisfies
  the grammar completely.
- **Whether `Checked by` names something that exists, beyond a script
  filename under `--repo`.** `PRINCIPLE_CHECK_ABSENT` reads only backticked
  `*.sh`/`*.py`/`*.js` names, matches them by basename anywhere in the work
  tree (so a same-named file in the wrong directory satisfies it), and runs
  only under `--repo`, because a file named on the command line has no root.
  A test name, a hook or a CI job is not checked. A script that ships in the
  plugin rather than in the repo IS checked, and in a consuming repo it is
  reported absent: a false alarm, and a WARN for that reason. Nothing checks
  that the named check actually enforces the principle.
- **System-name drift** (see *Known inconsistencies*).
- **Ids allocated in another repo or another file.** The counter is checked
  against the ids in the files given, and nothing else.
- **Uncommitted or in-flight edits.** It reads the files on disk it was pointed
  at, and nothing about branches, other clones or other sessions.
- **Gaps in the id sequence.** Legal — a split spec has them by construction —
  so an absent id is only reported against a baseline that had it.
- **Prose anywhere outside the sections named above.** Design notes, scope,
  concerns and rulings are read for citations at most.

---

## 9. Running it

```bash
# the usual pass
python3 scripts/validate-spec.py .claude/productizer/spec.md \
                                 .claude/productizer/constitution.md \
                                 .claude/productizer/backlog.md

# new content must survive this
python3 scripts/validate-spec.py --strict .claude/productizer/spec.md

# the permanence checks, against the previous commit
git show HEAD~1:.claude/productizer/spec.md > /tmp/spec-before.md
python3 scripts/validate-spec.py --baseline /tmp/spec-before.md .claude/productizer/spec.md

# the validator checking itself
python3 scripts/validate-spec.py --self-test
```

Passing the spec and the constitution on one command line lets the
constitution's `Enforced by` ids resolve against real requirements; passing the
constitution alone skips that one check rather than guessing.

Python 3 standard library only, no third-party imports, no network.
