# Known limitations

What Productizer's mechanisms cannot do, written down so nobody has to
rediscover it. Everything here was reproduced, not reasoned about; where a
limitation has a reproduction it is given in full, and where a claim was **not**
tested it says so.

This file is worth having only if it is true. Add to it when you find something;
do not remove an entry because it is unflattering.

Measured on git 2.50.1 (Apple Git-155), macOS, 2026-08-29.

---

## Requirement traceability — `Productizer-Req:` and `COV_` ids

Convention and commands: `plugins/productizer/skills/spec/references/traceability.md`.

### 1 · `git commit --amend -m` destroys the trailer

The most important one, and the reason this file exists.

`--amend -m` replaces the commit message wholesale. The `prepare-commit-msg`
hook does fire, but git hands it exactly the same arguments as an ordinary
`-m` commit, so **the hook cannot tell an amend from a first commit** and cannot
safely recover the old message. Measured:

```
git commit -m "..."          ->  hook argv: ($1=.git/COMMIT_EDITMSG, $2=message)
git commit --amend -m "..."  ->  hook argv: ($1=.git/COMMIT_EDITMSG, $2=message)
git commit --amend           ->  hook argv: ($1=.git/COMMIT_EDITMSG, $2=commit, $3=HEAD)
```

Only the third form carries a distinguishing argument — and that form does not
need it, because git seeds the editor with the old message, trailer included.

The tempting fix is for the hook to read `HEAD`'s trailer and re-apply it. It is
wrong: on a plain `-m` commit that same code copies the **parent commit's** ids
onto an unrelated change. A provenance record that is confidently wrong is worse
than one that is missing, so the hook does not do it.

**Reproduction**

```
$ PRODUCTIZER_REQ=R1 git commit -q -m "a change that serves R1"
prepare-commit-msg: Productizer-Req: R1  (from $PRODUCTIZER_REQ)

$ git log -1 --format=%B
a change that serves R1

Productizer-Req: R1

$ git commit --amend -q -m "reworded, and the provenance is gone"
prepare-commit-msg: no requirement id found in $PRODUCTIZER_REQ or the branch
name, so this commit will carry no Productizer-Req trailer.

$ git log -1 --format=%B
reworded, and the provenance is gone

$ req-trailer.sh --validate --rev HEAD
req-trailer: CANNOT DETERMINE — commit HEAD carries no 'Productizer-Req:' trailer.
There is nothing to validate. An absent trailer is not a valid one — it is an
untraced change.
$ echo $?
4
```

**Mitigations, all three reproduced**

1. **Name the ids on the amend.** The hook puts them straight back.

   ```
   $ PRODUCTIZER_REQ=R1 git commit --amend -q -m "reworded, provenance restored"
   prepare-commit-msg: Productizer-Req: R1  (from $PRODUCTIZER_REQ)
   $ req-trailer.sh --validate --rev HEAD
   req-trailer: commit HEAD — 1 cited id(s) all exist in .claude/productizer/spec.md (3 active, 1 superseded, 1 withdrawn on file).
   $ echo $?
   0
   ```

2. **Put the id in the branch name.** Then no environment variable is needed and
   the amend repairs itself, every time, for everyone on that branch.

   ```
   $ git branch -m fix/R1-branch-carries-the-id
   $ git commit --amend -q -m "reworded again, no env var this time"
   prepare-commit-msg: Productizer-Req: R1  (from branch 'fix/R1-branch-carries-the-id')
   ```

3. **Amend without `-m`.** `git commit --amend` opens the editor pre-filled with
   the old message; the trailer is already there and nothing is lost. Verified
   on a branch whose name held no id and with `$PRODUCTIZER_REQ` unset.

The backstop for all three is `req-trailer.sh --validate` in a pre-push hook or
in CI. It exits 4 — *cannot determine*, not *pass* — on a commit with no
trailer, so a silently amended-away trailer fails the check instead of passing
it.

### 2 · A squash merge hides the trailer from git's own trailer parser

`git merge --squash` (and GitHub's "Squash and merge") concatenates the messages
it swallows and **indents every line by four spaces**. The trailer text survives,
but it is no longer in the trailer block, so git stops treating it as a trailer:

```
$ git log -1 --format='%(trailers:key=Productizer-Req,valueonly)'
                      <- empty
$ git log -1 --format=%B | git interpret-trailers --parse
                      <- empty
$ git log --grep='^Productizer-Req:' --format='%h %s'
                      <- no match: the ^ anchor fails on an indented line
$ git log --grep='Productizer-Req:' --format='%h %s'
3bca457 Squashed commit of the following:
```

`req-trailer.sh` handles this — it strips leading whitespace before matching,
and its `--grep` filter is deliberately **not** anchored — and a squashed commit
validates correctly:

```
$ req-trailer.sh --validate --rev HEAD
req-trailer: commit HEAD — 3 cited id(s) all exist in .claude/productizer/spec.md (3 active, 1 superseded, 1 withdrawn on file).
```

But anything else you point at these commits will not. `%(trailers:…)` in a
`git log` format, `git interpret-trailers --parse`, a forge's trailer UI, and any
`^`-anchored grep all come up empty on a squash-merged commit. If your project
squash-merges, drop the `^` from every hand-written query.

Not tested: GitHub's server-side squash-merge specifically. The local
`git merge --squash` above is a proxy for it, and GitHub's default squash message
is built the same way, but that is an inference, not a measurement.

### 3 · Only HEAD's ancestry is searched

`--query` and `--orphans` run `git log HEAD`. A commit that exists only on an
unmerged branch, only on a remote that has not been fetched, or only in someone
else's clone is invisible, and the requirement it claims is reported as
orphaned. Reproduced simply by running `--orphans` on `main` and on a feature
branch and getting different answers:

```
$ git checkout main && req-trailer.sh --orphans
History: walked 5 commit(s) of HEAD; 2 carry a Productizer-Req trailer; 2 distinct id(s) claimed.
ORPHANED — active, and no commit claims it (2):
  R2
  R5

$ git checkout clean-history && req-trailer.sh --orphans
History: walked 6 commit(s) of HEAD; 3 carry a Productizer-Req trailer; 3 distinct id(s) claimed.
Every active requirement is claimed by at least one commit, and every claimed id
exists. Measured from the counts above.
```

Both answers are correct for the history they were asked about. Neither is a
statement about the project. Every report prints how many commits it walked, so
a number that came from a truncated history can be spotted — but the tool cannot
tell a **shallow clone** from a genuinely short history, and does not try.

### 4 · A rebase or cherry-pick multiplies the claims

Trailers survive `git rebase`, `git cherry-pick` and `git format-patch | git am`
— all three reproduced, each producing a new sha with an identical trailer:

```
before rebase:      33c0bac  Productizer-Req: R2,R5
after  rebase:      db24bed  Productizer-Req: R2,R5
after  cherry-pick: 8ae08b1  Productizer-Req: R2,R5
```

Which means the commit count in `--query` counts **commits, not units of work**.
After a rebase that duplicated a commit onto a branch you still have, one change
reads as two:

```
$ req-trailer.sh --query R1
R1 — active
3 commit(s) carry this id. Walked 8 commit(s); 5 carry a Productizer-Req trailer; git log --grep matched 5.

  d1b87f55b2e3  2026-08-29 08:14:22 UTC  cover the requirements
  24301111e71b  2026-08-29 08:11:43 UTC  hold exactly one living spec
  78b1782941d9  2026-08-29 08:11:43 UTC  hold exactly one living spec
```

Read that number as "at least one commit claims this", never as an amount of
work done.

### 5 · The coverage scan is textual, so documentation counts as coverage

`--coverage` greps tracked files for `COV_R<n>…`. It has no idea whether the
token it found is a test, a comment, a design note, or a sentence about the
convention itself. Found the hard way: the first version of `req-trailer.sh`
carried `COV_R14_contradiction_halts` as an example in its own header, and

- in a repo that had vendored the script, that example was reported as a
  **dangling** coverage id (the fixture spec had no R14), and
- in the Productizer repo, where R14 **does** exist, the same example would have
  been reported as genuine coverage of R14 — a false pass, which is the
  direction that matters.

```
DANGLING — a COV_ identifier names an id the spec does not contain (1):
  COV_R14_contradiction_halts   .claude/productizer/bin/req-trailer.sh  (no such requirement)
```

`req-trailer.sh` now carries no literal `COV_R<n>` token anywhere, verified:

```
$ grep -c -E 'COV_R[0-9]+' scripts/req-trailer.sh
0
```

`references/traceability.md` still does, on purpose — a convention document has
to show the convention — and says so in the document. So does this file. If
either is copied into a repository being scanned, it registers as coverage of
the requirements it names; measured, by copying both into a fixture tree:

```
DANGLING — a COV_ identifier names an id the spec does not contain (5):
  COV_R14_                        docs/KNOWN_LIMITATIONS.md  (no such requirement)
  COV_R14_contradiction_halts     docs/KNOWN_LIMITATIONS.md  (no such requirement)
  COV_R14_halts_on_contradiction  docs/traceability.md       (no such requirement)
  COV_R16_unmeasured_is_not_zero  docs/traceability.md       (no such requirement)
  COV_R99_this_id_never_existed   tests/test_spec.py         (no such requirement)
```

They show as *dangling* there only because that fixture's spec has no R14 or
R16. In this repository both ids exist, so the same tokens would be reported as
genuine **coverage** — the false pass, not the noisy false alarm.

There is no exclusion mechanism. Adding one means adding a way to mark a token
"not real", which is a way to mark a real gap "covered". Reading the file path
in the report is cheaper and harder to abuse.

### 6 · Gitignored trees are not scanned

`--coverage` uses `git ls-files` by default, so anything gitignored is invisible
and the search silently shrinks to fit. The report always names which list it
used (`git ls-files (gitignored files NOT scanned)` / `find`). Pass
`--include-ignored` to walk with `find` instead. Same blind spot, same flag, and
the same reasoning as `scripts/drift-reverse.sh`.

### 7 · The trailer is a claim, not evidence

Nothing checks that a commit citing R14 has anything to do with R14. Nothing
checks that a `COV_R14_…` test runs, passes, or exercises the behaviour R14
describes. A commit can claim every id in the spec and satisfy `--orphans`
completely.

These are pointers for a reader, in the same spirit as `drift-reverse.sh`: they
find the places worth reading and refuse to call the rest clean. Treating a
green `--orphans` as evidence of implemented requirements is a misreading the
tool cannot prevent.

### 8 · `--add` validates only when it can reach the spec

Run outside a repository that has `.claude/productizer/spec.md`, `--add` writes
the trailer without checking the ids exist, so the hook keeps working in a repo
that has not been scaffolded yet. When the spec **is** reachable it refuses an
unknown id and leaves the message file byte-for-byte unmodified:

<!-- EXAMPLE:BEGIN -->
```
$ req-trailer.sh --add R99 --file msg.txt
req-trailer: refusing to write a trailer naming an id that
.claude/productizer/spec.md does not contain:
  R99 — not in the spec
The commit message was NOT modified.
$ echo $?
3
```
<!-- EXAMPLE:END -->

### 9 · `.git/hooks/` is not cloned

The hook is a file in `.git/`, so it is not committed, not cloned, and not
distributed. Every developer installs it themselves, and a fresh clone has no
trailer automation until they do. `core.hooksPath` pointed at a tracked
directory solves this repo-wide; it is a repo-level decision this skill does not
make for you. Not implemented, not tested.

### 10 · Not proven

Stated for completeness — these were **not** measured:

- GitHub / GitLab server-side squash-merge and rebase-merge message formats.
- `git filter-branch` / `git filter-repo` rewrites.
- Behaviour on git older than 2.50.1. `git interpret-trailers` (used by `--add`)
  has existed since 2.1 and `--if-exists replace` since 2.4, but no older
  version was run.
- Windows, and any non-UTF-8 commit message encoding.
- Repositories large enough for the single `git log` pass in `--orphans` to be
  slow. It reads every commit message in HEAD's ancestry, once, with no limit.

---

## Citations, stage advance and whole-spec review — added in v4.66.0

### 11 · `dangling-citations` has never once found a real dangling citation here

`scripts/check-citations.sh` resolves every requirement id on the lines a
change adds. A citation is a token, `R` and digits, so an example id in a
self-test, a doc illustrating the id grammar or a `checks.yaml` comment reads
exactly like a real one. Replayed over every commit in this repository against
its parent, 2026-10-12, with the check as it was (1.0) and as it is (1.1):

```
139 commits in history
 22 refused (no spec yet), 1 with no parent
116 measured
1.0: 27 exit 1, 94 findings
1.1: 26 exit 1, 91 findings
```

Read one by one in the 2026-10-10 replay, none was a citation anybody meant
(`references/traceability.md`), and 1.1 differs only in reading `R0`, the
reserved example id, as an example. **Finding precision on this history is
zero, and it cannot change**: a marker added today does not reach a commit
already made. What changed is the tree those commits built. Every example id in
it is now `R0` or inside an `<!-- EXAMPLE:BEGIN -->` block, so a change adding
every tracked file reads 0 findings where it read 20 (B101, v4.68.0). The check
stays advisory, and R52 and R53 `Partial`, until changes made after that give it
a precision of its own. The reading of the history is a judgement, not a
measurement.

### 12 · `stage-advance.sh` has one caller, and it is not a tracker

It decides whether a work item's stage may move, and `references/integrations.md`
says every tracker move goes through it first. Since v4.67.0 one thing does
call it: `build-dispatch.sh deliver`, in the copyable CI template, asks it
before delivering an unattended run's patch, and again on the commit it made. No tracker move, label or hook
calls it, so a ticket's stage can still move on a run that produced nothing.
`stage-advance-guard` runs its self-test, which proves the decider, not that
anyone asks it. Searched 2026-10-10: outside its own file it is invoked only by
`build-dispatch.sh` and the self-test lines of `checks.yaml` and the workflow.

### 13 · `/productizer:spec-review` Part B is unmeasured

Part A is deterministic. Part B hands the checklist to a clean-context reviewer
agent, and it has **never been dispatched live**: the checklist was walked once
by hand over this spec (B102), so what Part B finds, misses and invents is not
known. R57 holds that a reviewer agent is granted no tool that can write a
file, and `check-frontmatter.py` asserts it on the frontmatter `name` only. A
reviewer that writes through Bash or an MCP tool passes.

### 14 · The CI build template has never run end to end

`templates/build-from-spec.yml` runs a stage unattended in an adopter's
repository. It has **never run on GitHub**: this repository is public, holds no
model secrets, and a run costs model spend. What is measured is its static
properties (`check-ci-template.py`, 14 of 14) and both ends of
`build-dispatch.sh` against local repositories, with `gh` stubbed and origin a
local bare repository (94 of 94). Not measured: the action itself, a real
`gh`, that a draft stays a draft, and that GitHub runs the template's calls of
the script as written (check-ci-template.py asserts the call text since B118,
not its execution). A pull request it opens with the workflow's
`GITHUB_TOKEN` does not start the adopter's `pull_request` checks - GitHub's
rule, quoted in `references/ci-build.md`, not measured here.

### 15 · The paths `stage-advance.sh` refuses are a list, not a proof

Since 1.1 it judges the paths git applies rather than the patch's text, and
refuses by default everything under `.github/` and `.claude/` and a named set of
files that steer CI or an agent - CLAUDE.md, AGENTS.md, `.mcp.json`,
`.gitattributes`, `.gitmodules`, hook managers and others. Since 1.2 a name is
matched after folding case, Unicode normalisation and format characters, so a
variant a checkout folds onto a rule file is refused, and a symbolic link or a
submodule entry is refused at any path. In an attended run only, a rewritten
checks result is still allowed (its writer, `run-checks.sh`, rewrites it every
run). Since 1.3, under `--unattended` - which the CI template's `deliver` passes
on both of its calls - any change to the checks result is refused, because
nothing in an unattended pipeline writes it (maintainer ruling 2026-10-12,
B126). Since 1.4 a homoglyph from another script is read rather than folded, and
under `--unattended` an allowlist bounds the list (items 19 and 20). Attended,
nothing shows the list is complete (B125).

The same default-deny refuses a design move that writes
`.claude/productizer/` files such as `requirement-index.md`, which this
repository's own design commits do. Which of those a design stage may write is
undecided (B112).

The 1.0 this replaced judged a patch by its `diff --git` headers, and git
writes other paths than those: nine reproductions had it allow a patch while git
wrote a workflow or `checks.yaml`. That version is in v4.66.0 (f1f44f3), which
was never pushed.

### 16 · Whether the action honours committed permissions is unmeasured

The CI template gives the agent the repository's committed Claude Code settings
and lets the dispatcher narrow them, never widen them (R65). Measured locally on
2026-10-10, `claude -p` 2.1.295 in a workspace it had not been told to trust
**ignored** a committed `permissions.allow` entry and a committed
`defaultMode: bypassPermissions`, while it honoured committed deny rules and a
committed `defaultMode: acceptEdits` (`references/ci-build.md`). The action runs
the Agent SDK, not `claude -p`. If it behaves the same, build mode cannot run
the repository's tests under the default option. Not measured on a runner: this
repository holds no model secrets, a run costs model spend, and trust state
lives in the user's own Claude Code configuration in their home directory,
outside any repository (B113).

### 17 · What the unattended pipeline runs AFTER the agent is hardened, not proven on a runner

v4.67.2 audited every command the pipeline runs after the agent step. Three
guards were added and are exercised by self-tests, but the properties that need
a real GitHub runner are still unmeasured (B121, B122):

- **`gh pr create` runs from `$ROOT`, not the patch-applied worktree** (R70,
  `build-dispatch.sh`). The one post-agent command that is not git against the
  committed config no longer has its working directory inside patch-controlled
  content. Measured by the self-test's `gh` stub recording its directory; the
  real `gh` and a real GitHub are not exercised.
- **`BASH_ENV`/`ENV` are pinned empty on the post-agent capture step** (R69,
  the template, asserted by `check-ci-template.py` `post-agent-env`). The agent
  cannot set either today - it has no shell and cannot write `$GITHUB_ENV` - so
  this guards the invariant against a future CLI or action change. That the
  runner honours the pin is not measured.
- **`pr-spec-comment.sh` reads the Stage 5 result with an isolated interpreter**
  (`python3 -I` plus a `sys.path` scrub). A `json.py` planted beside the result
  was reproduced being imported in place of the standard library on the HEAD
  version; it is **not reachable through the template** (the body is rendered
  from the default-branch tip, never the applied worktree - and since v4.67.3 in
  `prepare`, with no write token), so the fix is defense in depth for the
  general tool, with a falsified regression test.

Not proven without a runner: that the action's own post steps (it runs
`post-buffered-inline-comments` under `bun` with the read-only token) touch
nothing agent-controlled in the working directory; and everything already listed
under item 14 and B121.

### 18 · EXPERIMENTAL — the CI build template has never run on a real GitHub runner

This workflow has never run on a real GitHub runner. Its main protection, that
the AI gets no shell, was measured only with a local CLI. Do not adopt it yet.

That statement heads `templates/build-from-spec.yml`, `references/ci-build.md`,
the README section on the template and the SKILL.md rows for the two scripts
that serve it. It stays until the runner measurements it waits on are made:
B113 (whether the action honours the repository's committed permission
settings) and B121 (the no-shell template measured end to end on GitHub). Each
guarantee the template states - no shell for the agent, no write token beside
it, no repository code in the job that writes (R71, v4.67.3), a draft pull
request only - is proven by self-tests against local repositories and by static
checks of the YAML, and by nothing that ran on GitHub.

## Added in v4.70.0

### 19 · `stage-advance.sh` refuses some legitimate non-ASCII names

1.4 reads each non-ASCII character of a changed path as any character (one, or
none to one for a combining mark or a filler, one to two for a Latin letter),
and refuses the path if a reading is a refused one. No confusables table is
used, so the reading is a superset of one, and it over-refuses: a six-letter
Cyrillic file name ending `.md` reads as `AGENTS.md` and is refused, in an
attended run too. A non-ASCII name under a dot component is refused outright.
Measured on this repository's history at v4.69.1: 0 of 2127 changed paths in
144 commits hold a byte outside ASCII, so nothing here was refused by it. Not
refused: a reading of three or more characters for one, a component with no
ASCII letter or digit, and a homoglyph made of ASCII alone (`rn` for `m`).

### 20 · A steering file that is ASCII, has no dot and is not on the list

Under `--unattended` 1.4 allows only ASCII paths with no component beginning
with a dot, bar the backlog, the plan and the spec on their exact paths, so
most tools' configuration is refused without being named. What the allowlist
still admits, and the named list must catch, is an ASCII, dot-free file:
`Jenkinsfile`, `azure-pipelines.yml`, `GEMINI.md`, a `package.json` script, or
a script `checks.yaml` runs - an unattended build may edit that last one and
neuter the check that runs it. None of those is on the list. Attended runs
apply the list alone. The plugin manifests under `.claude-plugin/` declare hooks
and MCP servers and are refused unattended by their dot; attended they are not
on the list, because adding them would refuse 22 of this repository's own
version bumps, and that needs a ruling.

### 21 · The view builder's encoding holds only while embedded text reaches no code-executing sink

`build-view.sh` writes the capability object's name in embedded repository text
as a character reference in HTML and as a `\u0063` escape in a JavaScript
string, so the page never carries it verbatim and `check-view-readonly.sh` can
keep reading every byte (B115). Both decode back to the text in the browser.
That is safe only while the decoded text lands where nothing runs it: a
character reference inside an event handler or a `javascript:` URL decodes to
code the browser runs and the check could no longer read. No such sink exists
in the builder today, and nothing but review keeps it that way.

### 22 · Links are deliberately not encoded

For the same reason, every value written into an `href` goes through an escape
that encodes nothing beyond the HTML metacharacters, so a repository path or a
Jira key in a link carries the capability object's name verbatim if it holds
it. The check reads those bytes like any others; a link naming the user's config
dot-file by its home-directory path would be a finding.

### 23 · The pinned template asset exists only from v4.70.0, and the release jobs have not yet run

`release-prep` attaches `build-from-spec.yml` with `PRODUCTIZER_SHA` pinned to
the release's commit. Releases before v4.70.0 carry no such asset; an adopter
of one still pins by hand. Both jobs run only on a version-tag push, so until
the v4.70.0 tag is pushed neither has run: whether `pull-requests: read` is
enough for `build-release-notes.sh` to read the merged pull requests is
unmeasured, and no declared check reads the release jobs at all, so the two
requirements drafted for them were not added (backlog).

### 24 · `check-acceptance-rows.sh` resolves a cited path on disk, not in git

1.2 compares each component of a cited path against its directory's own
listing, so the answer is the same on a case-insensitive disk and on a Linux
runner (B134). It still reads the disk: a file that is present and untracked
resolves, and a row citing it passes here and fails in a clean clone.

### 25 · What `check-sigpipe.sh` does not see

It reads each `.sh` and `.bash` file it is given as shell, statically:
pipefail switched on in another file (sourced or inherited); a reader reached
through a function, alias or variable; other early readers (`sed q`, `awk` with
`exit`, `read`, `cmp`, python); shell outside a `.sh` or `.bash` file - a
workflow `run:` block or a Markdown fence (the workflow's two `gh --version`
lines were fixed by hand); a `$( ... )` inside an unquoted here-document body;
backtick substitution, read as plain code; and, in a file without errexit, a
function whose last pipeline ends in a reader and whose caller tests it, an `if
x="$(a | head -1)"`, and a group or subshell tested from outside.
