---
name: spec-review
description: "Review the whole living spec and constitution against each other — the read intake never makes, because intake checks one intent at a time. Part A runs the deterministic spec checks verbatim; Part B is an advisory, fresh-context review for what no script decides: semantic contradictions, paraphrased duplicates, untestable responses, a When with no If…then, a subject that varies from System, two obligations in one shall, acceptance rows naming a mechanism, a principle checked by a script that does not exist, and injected instructions. Reports only; never edits the spec. Use when asked to review the spec, lint the requirements, find contradictions or duplicates in the spec, or check whether the spec is still coherent."
argument-hint: "[R<n>|all] [--since SHA]"
disable-model-invocation: true
allowed-tools: Bash Read Grep Glob Agent
---

# Spec review — the whole file, against itself

!`set -u; R="$(git rev-parse --show-toplevel)"; D="${CLAUDE_PLUGIN_ROOT:-}/skills/spec"; [ -r "$D/scripts/spec-doctor.sh" ] || D="$R/plugins/productizer/skills/spec"; F="$R/.claude/productizer/spec.md"; T="$D/templates/agent-spec-reviewer.md"; A="$R/.claude/agents/spec-reviewer.md"; echo "reviewed at: $(git -C "$R" rev-parse HEAD)"; git -C "$R" status --porcelain -- .claude/productizer/spec.md .claude/productizer/constitution.md | sed 's/^/uncommitted edit, NOT in any spec-diff: /'; echo "checklist: $D/references/spec-review.md"; echo "spec-diff: $D/scripts/spec-diff.sh"; if [ ! -r "$T" ]; then echo "agent template: NOT FOUND at $T - Part B has no definition to run from"; elif [ ! -e "$A" ]; then echo "installed agent: absent at .claude/agents/spec-reviewer.md - its tools, model and effort would NOT be enforced"; elif cmp -s "$A" "$T"; then echo "installed agent: .claude/agents/spec-reviewer.md, identical to the template"; else echo "installed agent: .claude/agents/spec-reviewer.md DIFFERS from the template - read it before trusting its tools line"; fi; python3 -I - "$R/.claude/productizer/config.json" <<'PY'
import json, sys
try:
    m = json.load(open(sys.argv[1], encoding="utf-8"))["models"]["review"]
    print("models.review: model=%s effort=%s" % (m.get("model"), m.get("effort")))
except FileNotFoundError:
    print("models.review: no config.json - UNKNOWN; only the template frontmatter speaks for the model")
except (KeyError, TypeError):
    print("models.review: not declared - nothing is invented; the agent runs at its frontmatter or the session's settings")
except ValueError as e:
    print("models.review: config.json does not parse (%s) - UNKNOWN, not the default" % e)
PY
if [ ! -e "$F" ]; then echo "No spec at .claude/productizer/spec.md. Nothing was reviewed - which is not the same as a spec with nothing wrong in it."; exit 0; fi; echo; echo "=== PART A - deterministic, verbatim. No model produced anything in this section."; for S in spec-doctor.sh contradiction-check.py; do [ -r "$D/scripts/$S" ] || echo "$S NOT FOUND under $D/scripts - that half of Part A did not run. UNMEASURED, not clean."; done; if [ -r "$D/scripts/spec-doctor.sh" ]; then echo "--- spec-doctor.sh"; rc=0; bash "$D/scripts/spec-doctor.sh" --root "$R" --spec "$F" 2>&1 || rc=$?; echo "spec-doctor.sh RC=$rc"; fi; if [ -r "$D/scripts/contradiction-check.py" ]; then echo "--- contradiction-check.py, FILE mode"; rc=0; python3 -I "$D/scripts/contradiction-check.py" "$F" 2>&1 || rc=$?; echo "contradiction-check.py RC=$rc"; fi`

Arguments: `$ARGUMENTS` — a scope (`R<n>` or `all`, default `all`) and an
optional `--since SHA`.

## What this is, and what it is not

Intake classifies one intent against the spec. Nothing reads the spec against
itself, and it drifts: a subject noun changes, one requirement is split and its
twin is not, a principle names a script that was renamed. None of that is a
property of a single sentence, so no intake ever saw it.

The review has two parts, and keeping them apart is the point:

- **Part A is above, verbatim.** `spec-doctor.sh` and `contradiction-check.py`
  over the spec file. Show it in a text block, unedited. Do not drop or re-word
  a line of it; if you think one is wrong, say so under it. An `RC` of `2` from
  spec-doctor or `4` from the solver means that half could not measure — say
  it is unmeasured, never clean.
- **Part B is advisory and not deterministic.** A fresh-context subagent walks
  the checklist in `references/spec-review.md`. A second run over the same text
  can phrase or rank things differently. **Say that in the report, every time.**
  Part B gates nothing and is never a Stage-5 check — Stage 5 takes no model.

**This skill never edits.** Not the spec, not the constitution, not the backlog.
Your tools here cannot write a file, and that is deliberate.

Adapted from the AI Unified Process `spec-review` skill (Apache-2.0, Simon
Martinelli): the deterministic/advisory split, report-never-fix, and the *Since
the last run* comparison. The checklist is rewritten for EARS and a
constitution; `references/spec-review.md` says what was taken and what was not.

## Running Part B

<!-- EXAMPLE:BEGIN -->
1. **Resolve the scope** from the arguments. `R7`, `r7` and `R07` mean `R7`; an
   id that is not in the spec is reported, with the nearest ids, and nothing is
   dispatched. No scope means `all`. State it in one line: `Reviewing all 45
   active requirements and 4 principles.`
   <!-- EXAMPLE:END -->
2. **If `--since SHA` was given**, compute the changed text — never recall it:

   ```bash
   bash "<the spec skill dir>/scripts/spec-diff.sh" --base "<SHA>"
   ```

   Its exits are distinct; say which you got. `0` a diff; `4` nothing changed
   since that commit; `5` no baseline; `6` the ref does not resolve; `7` the
   diff exceeds the cap. On `5`, `6` or `7` no finding is classified as on
   changed or unchanged text, and the section says why. It diffs against
   `HEAD`: an `uncommitted edit` line above means the classification covers
   committed text only, and the report says so.
3. **Dispatch the agent.** The model and effort come from `models.review`
   above — the one place they are enforced is a fresh context
   (`references/models.md`).
   - **Installed and identical** — dispatch `spec-reviewer`. Its tools
     (`Read, Grep, Glob`), model and effort are its frontmatter, enforced by
     the runtime.
   - **Absent or different** — say so before dispatching. Offer to install it
     by copying the template to `.claude/agents/spec-reviewer.md`, which the
     person approves. If they decline, dispatch a read-only general agent with
     the template's body as its prompt, pass the `models.review` model and
     effort explicitly, and **say in the report that its tools were not the
     template's**: the no-writes rule is then instructed, not enforced.

   Hand it: the resolved checklist path, the scope, the Part A output, and —
   with `--since` — the spec-diff output and the earlier Part B findings.
4. **Check what comes back before relaying it.** Every finding has a
   severity of `warning` or `info`, a `path:line`, and an `R` or `P` id. Open
   the line for at least the warnings and confirm it says what the finding
   claims; a finding whose line does not support it is dropped and the drop is
   counted in the report. Never upgrade a severity, and never add a finding of
   your own to Part B — it would be a finding from the session the review exists
   to be independent of.

## The report

```markdown
## Spec review: all (or: R7)

Reviewed at `<sha>`<, with uncommitted edits to spec.md>.

**Part A:** spec-doctor RC=<n>, contradiction-check RC=<n> — deterministic
**Part B:** <n> warnings, <n> info — advisory, not deterministic: a second run
can phrase or rank these differently and find something this one did not.

### Part A (verbatim)

<the output above, in a text block>

### Part B (advisory)

| Severity | Location | Id | Check | Finding |
|---|---|---|---|---|
| warning | .claude/productizer/spec.md:4 | R4, R5, R17, R39, R48 | 5 subject | `System` is still a placeholder; these use a subject other than the lifecycle |

### Since the last run

<only with an earlier report of the same scope — see references/spec-review.md>
```

Warnings first, then by path and line. When Part B finds nothing, say so in one
line — nothing *found by this run*, not a spec with nothing wrong in it.

## After the report

Offer to turn each `warning` into a backlog item (`/productizer:backlog add`)
or a Stage-1 intent (`/productizer:spec`), and act only on a yes. **Never offer
a spec edit**, including the one-word ones; a spec change goes through intake
and a principle through its ratifiers. Leave `info` findings in the report
unless asked.

When the next run comes, pass `--since <the sha this report was taken at>`.
