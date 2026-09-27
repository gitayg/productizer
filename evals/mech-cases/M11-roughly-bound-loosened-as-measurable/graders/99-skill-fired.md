---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?spec"'
min: 1
weight: 1
---

Indicator, not a criterion. Under `--ablation with-without` this grader is
reported as a plugin-fired indicator and is not scored, so it cannot inflate
either arm. It exists to tell a red case caused by the plugin apart from a red
case caused by the plugin never loading.
