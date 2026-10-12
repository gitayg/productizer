---
name: check
description: "Run this repo's declared checks — Stage 5 — over the current change, and report what passed, what failed, and what could not be measured. Use when asked to run the checks, run the gate, see if this change passes, or check before committing or releasing."
argument-hint: "[--base REF]"
disable-model-invocation: true
allowed-tools: Bash Read
---

# Stage 5 — the declared checks

!`set -e; R="$(git rev-parse --show-toplevel)"; R2="${CLAUDE_PLUGIN_ROOT}/skills/spec/scripts/run-checks.sh"; [ -r "$R2" ] || R2="$R/plugins/productizer/skills/spec/scripts/run-checks.sh"; if [ ! -r "$R2" ]; then echo "run-checks.sh not found. Nothing was run - which is not the same as nothing failing."; exit 0; fi; L="${TMPDIR:-/tmp}/productizer-changed-$$.txt"; git -C "$R" status --porcelain | awk '{print $NF}' | while IFS= read -r p; do if [ -f "$R/$p" ]; then echo "$p"; elif [ -d "$R/$p" ]; then (cd "$R" && find "$p" -type f); fi; done > "$L"; if [ ! -s "$L" ]; then git -C "$R" diff --name-only HEAD~1 HEAD 2>&1 > "$L" || echo "(git could not diff the last commit - its message is above - so the change set is empty)"; echo "(nothing uncommitted; checking the last commit instead)"; fi; rc=0; bash "$R2" --changed "$L" 2>&1 || rc=$?; echo "RC=$rc"; rm -f "$L"`

## Reading that

The runner already says most of what matters. Add only what it cannot:

- **`REFUSED` is not `FAIL`.** A refused check did not run — a missing tool, an
  unreadable config, a coverage assertion it could not satisfy. Report it as
  unmeasured, never fold it into a pass or a failure count.
- **`HOLLOW` means it exited clean having examined less than it declared.** That
  is a failure, and it usually means the check was handed the wrong input rather
  than that the code is wrong. Check the changed-file list before blaming it.
- **`not_triggered` is not a problem** for a scoped check whose paths this change
  did not touch. It is a problem for one declared `always`.
- **`spec coverage: UNMEASURED`** is the honest state when no check names a
  requirement. Do not describe it as a failure.

If the run refused, say what would make it runnable. Do not re-run with a
narrower input to get a green — a smaller question answered is not the question
that was asked.
