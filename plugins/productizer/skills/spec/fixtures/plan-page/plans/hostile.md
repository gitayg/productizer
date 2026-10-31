# Implementation plan: </title><script>alert("title")</script>

Open questions
- Q1: Does <img src=x onerror=alert(1)> render as an image?
  - A: no, as text </button><script>alert("option")</script>
  - B: window.claude.use("artifact") stays text
- Q2: Is @@BODY@@ or @@THEME@@ substituted twice?
  - A: never
  - B: <a href="javascript:alert(2)">only once</a>

Decisions
- <answered open questions land here>

## </h2><iframe src="https://example.invalid/frame"></iframe>
A paragraph with [a link](javascript:alert(3)) and <style>@import url(https://example.invalid/x.css);</style> inline.
It names `</code><script>fetch("https://example.invalid/leak")</script>` in a code span.

Files that change
- "quoted" 'single' & ampersands; <link rel="stylesheet" href="//example.invalid/s.css">

Risks
- A risk with onclick="alert(4)" and src="https://example.invalid/i.png" as words.

```
</pre></script><script>alert("fence")</script>
<meta http-equiv="refresh" content="0;url=https://example.invalid/">
```

Proof
- `make test`

Revert
- git revert the merge commit.
