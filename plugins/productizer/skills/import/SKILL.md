---
name: import
description: "Onboard a repository that already exists — Stage 0c. Surveys the code read-only for what it can actually evidence, then drafts requirements from that evidence, every one marked inferred and unconfirmed until a person confirms it. If the repo already holds a spec, the same evidence is drift rather than a draft, and it asks what to do instead of guessing. Use when adopting the lifecycle in an existing project, bringing a legacy repo under a spec, importing a codebase, checking a repo against its own spec, or asking what this repo already does."
argument-hint: "[repo-path]"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit AskUserQuestion
---

# Stage 0c — a repo that already exists

!`set -e; T="${1:-}"; R="$(cd "${T:-.}" && pwd)" || { echo "no such path: $T"; exit 0; }; SPEC="$R/.claude/productizer/spec.md"; STATE="none"; N=0; if [ -e "$SPEC" ] && [ ! -r "$SPEC" ]; then STATE="unreadable"; elif [ -r "$SPEC" ]; then N="$(grep -cE '^- \*\*R[0-9]+\*\*' "$SPEC" || true)"; if [ "${N:-0}" -gt 0 ]; then STATE="live"; else STATE="scaffold"; fi; fi; echo "SPEC STATE: $STATE ($N requirement(s)) at .claude/productizer/spec.md"; echo; case "$STATE" in unreadable) echo "A spec file exists here and cannot be read. Whether this repo is already onboarded is UNKNOWN, and unknown is not permission - surveying is safe, but nothing may be written into a spec nobody could open. Fix the permissions, then re-run."; exit 0 ;; live) echo "This repo is ALREADY UNDER A SPEC. Read the survey below as DRIFT, not as a draft."; echo "The evidence is identical either way; what changes is what it is evidence OF." ;; scaffold) echo "A spec file exists but declares no requirements. Treating it as scaffolding. It was already here; this run did not create it." ;; none) echo "No spec here. This is a genuine import." ;; esac; echo; S="${CLAUDE_PLUGIN_ROOT}/skills/spec/scripts/import-survey.sh"; [ -r "$S" ] || S="$(git rev-parse --show-toplevel)/plugins/productizer/skills/spec/scripts/import-survey.sh"; if [ ! -r "$S" ]; then echo "import-survey.sh not found. No survey was run - which is not the same as a repo with nothing in it."; exit 0; fi; echo "surveying: $R"; echo; bash "$S" "$R" 2>&1 | head -160; echo; echo "(survey truncated at 160 lines for reading; re-run the script directly for the whole report)"`

## If SPEC STATE is `live`, stop and ask

The survey's Verdict answers *"is there enough evidence to draft"*. It does not
answer *"should you draft here"*. A repo already holding agreed requirements
answers the second question on its own.

**With a spec in place this is drift, not an import.** The evidence is identical
either way — the same routes, the same CLI surface, the same config keys. What
changes is what it is evidence *of*. With no spec, behaviour the code states
becomes the spec. With a spec already agreed, that same behaviour is measured
*against* the spec, and whether the code or the spec is wrong is a question for
a person.

So **ask them**, with `AskUserQuestion`, before touching anything. Three
answers, and none of them is a default:

| | |
|---|---|
| **Use it** | Read the survey as drift against the existing spec. Report behaviour the code states that no requirement covers, and requirements the code no longer evidences. Change nothing; a drift report is a finding, not an edit. |
| **Update it** | Same reading, then take each finding through intake as an intent — classified against the whole living spec, merged only if it passes. Slower, and the only route that changes agreed requirements without overwriting them. |
| **Delete it** | Start over from the code. **Move the spec aside, never delete it** — it holds decisions somebody made, and the acceptance rows, rulings and change log go with it. Then this becomes a real import. |

Say which you would pick and why. **Use it** is usually right first: the drift
report costs nothing, and it tells you whether the spec is wrong, the code is
wrong, or neither — which is the thing you need before choosing between the
other two.

Never pick for them, and never treat a repo with a spec as an import because the
Verdict happened to say STRONG.

## If SPEC STATE is `none`: read the Verdict first

**If it says there is not enough evidence, stop.** A spec drafted from a repo
that could not evidence its own behaviour is a spec of guesses wearing the
authority of a committed file — and every later classification is made against
it. Say what was missing and what would fix it. "Add a test that names the
behaviour" is a real answer; inventing the requirement is not.

## What a drafted requirement is, and is not

Everything drafted here is **inferred and unconfirmed**. That is not a
formality:

- It carries the marking in the spec until a person confirms it.
- **It gets no acceptance-criteria row.** That table answers "do the tests
  assert this", and an inferred requirement has not been agreed, so a row for
  it would answer a question nobody asked.
- It cannot trigger the Stage 2 contradiction halt. An imported guess must not
  block a real intent with the authority of a decision nobody made.

Write down what each one was read *from* — the test, the route, the flag, the
doc heading. A requirement whose evidence is not recorded cannot be confirmed
later by anyone except whoever drafted it, and they will not remember either.

## Then confirm them in batches

Do not ask about twenty-five requirements at once. Take them a batch at a time,
quote each sentence in full with the citation it carries, and take the answer by
id. **Promote nothing that was not named, and never treat silence as a yes** —
silence is the most common way an inferred requirement becomes an agreed one
without anybody deciding.

A requirement confirmed loses the marking and earns its acceptance row. One
refused is withdrawn with `Rejected at import:` and the reason. Both are
answers; neither is the default.

## What this does not do

The survey is **read-only and executes nothing** from the repo it reads — a
`package.json` script or a Makefile target is quoted as text, never run. That is
deliberate: a repo being examined never chooses what runs on the machine
examining it.

It reports what it can evidence, which is not the same as what the code does.
Behaviour with no test, no route, no flag and no doc is invisible to it, and the
report says what it looked at rather than implying it looked at everything.
