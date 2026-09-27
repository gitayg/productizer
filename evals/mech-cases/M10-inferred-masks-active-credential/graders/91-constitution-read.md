---
type: tool_used
tool: Read
input_match: '"file_path"\s*:\s*"[^"]*\.claude/productizer/constitution\.md"'
min: 1
arm: both
weight: 1
---

Did the run Read the constitution at `.claude/productizer/constitution.md`.
Principles bind requirements nobody has written yet (M03), so a run that finds
the spec and never opens this file cannot see that conflict. `arm: both`, for
the same reason as `90`.
