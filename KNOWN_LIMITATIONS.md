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
known. R110 holds that a reviewer agent is granted no tool that can write a
file, and `check-frontmatter.py` asserts it on the frontmatter `name` only. A
reviewer that writes through Bash or an MCP tool passes.

### 14 · The CI build template has never run end to end

`templates/build-from-spec.yml` runs a stage unattended in an adopter's
repository. It has **never run on GitHub**: this repository is public, holds no
model secrets, and a run costs model spend. What is measured is its static
properties (`check-ci-template.py`, 16 of 16) and both ends of
`build-dispatch.sh` against local repositories, with `gh` stubbed and origin a
local bare repository (130 of 130 since 1.3). Not measured: the action itself, a real
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
under `--unattended` an allowlist bounds the list (items 19 and 20). Since 1.6,
under `--unattended`, a classification record or stage snapshot ADDED is refused
(B137), and so is a change to any file a check declared in `checks.yaml` at the
base runs (B136), though not a file such a script calls that `checks.yaml` does
not name (item 20). Attended, nothing shows the list is complete (B125).

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
and lets the dispatcher narrow them, never widen them (R113). Measured locally on
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
the README section on the template, the `references/scripts.md` rows for the
two scripts that serve it, and SKILL.md's Stage 6. It stays until the runner measurements it waits on are made:
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
`Jenkinsfile`, `azure-pipelines.yml`, `GEMINI.md` or a `package.json` script.
None of those is on the list. Since 1.6 (v4.72.0, B136) a file a check declared
in `checks.yaml` at the base runs - its program, `version_command`, coverage
commands, an interpreter's first operand and every `requires` entry - is
refused under `--unattended`. Since 1.8 (v4.72.2, B152, the maintainer's
strict rule) the set is read without recognising any interpreter: the program,
every literal non-option token, bare words included, every `--opt=` and glued
value (a bare word too, since 1.9, B158), and the module paths of a
dotted name, read by `argv-classify.py`, which `run-checks.sh` shares. A
placeholder handed to a program off the plugin's data-only list is exit 4
under `--unattended` (B156); wrap the command in a repository script.
Since 1.10 (v4.73.2, B147) every script a protected
script names by its path is protected too, to any depth (see 37). What is
still admitted is a script reached through a name built at run time, and a
data file a check script reads. A tool that finds and runs repository files by
itself, with no argument naming them, is gated by neither script: test
discovery, `.semgrepignore`, `.npmrc`, `conftest.py`, a git alias. With the
opt-in off `run-checks.sh` does not refuse `.` (the root, by ruling, B154), a
value inside a comma-separated list, or a name a tool resolves through
node_modules. Since 1.3 (v4.72.3, B157) it judges each command again just
before it runs, so a path an earlier check wrote is refused when a later check
names it, and it counts a value spelled as a path under the root whether or not
it exists. Since 1.4 (v4.72.4, B159, the maintainer's narrow exception) a
registry id handed to semgrep's `--config`, `--config=` or `-c` - `p/`, `r/` or
`s/` and one name - is not counted while neither tree holds a file or directory
by that name, judged case-folded on a disk that folds case, at load and again
before it runs; once one exists the id is a path and needs the opt-in. It rests
on semgrep reading a registry id from its registry, measured with 1.171.0 on
2026-10-14 and not re-measured by any check. `-f`, an abbreviated `--conf` and
a glued `-cVALUE` get no exception, nor does semgrep named by a path or with
`--allow-local-builds`. `stage-advance.sh` still protects the id. Still not
judged: a file written between that judgement and the exec, or by a process an
earlier check left running. The data-only list (shellcheck, semgrep, grep,
each voided by named options) rests on the tools' `--help`, read 2026-10-13;
an option a later release adds is not on it. A `run-checks.sh --config` other than the
default is not read. PyYAML, installed in `prepare` to read the set, is
pinned by hash since v4.73.2 (B148, see 38). Attended runs apply the list alone. The plugin manifests under `.claude-plugin/` declare hooks
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
unmeasured. Since v4.72.0 the `release-workflow-safe` check reads the release
jobs statically (B142), and the requirements drafted for them are added as
R136 to R138; see item 31 for what that check does not see.

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

## Added in v4.71.0

### 26 · `jira.status_map` has never been run against a real Jira

The eleven-state mapping from Jira workflow states to backlog statuses in
`plugins/productizer/skills/spec/templates/config.json` has never been run
against a real Jira instance. It was checked on 2026-09-06 against Atlassian's
published documentation only (`references/backlog.md`, "The status map is
unverified"), and nothing in the repository reads it. The maintainer ruled on
2026-10-13 to keep it and not test it now (B4): it ships as a starting point,
and the template's own `_note` key says the same. Edit it against your
project's statuses before relying on it.

### 27 · A plugin manifest is refused only when no person is at the keyboard

`stage-advance.sh` refuses a change to a `.claude-plugin/` manifest only under
`--unattended`, where any path with a component beginning with a dot is outside
the allowlist (the `unattended-shape-46` case). Attended, the named forbidden
set does not list it, so a manifest edit is allowed: version bumps edit it, and
refusing it attended would refuse 22 of this repository's own version bumps
(measured at v4.69.1, B135). A manifest declares hooks and MCP servers, so an
attended stage run can still change what steers an agent there; a person sees
that change.

### 28 · A design move's requirement-index exception is on the path, not the bytes

Since `stage-advance.sh` 1.5 an attended move to design may MODIFY
`.claude/productizer/requirement-index.md` (B112). The exception is granted on
the exact path and git's status `M`. The stage guard does not check that the
new content is what `build-requirement-index.sh` writes; the
`requirement-index-current` check does, when the checks run, so a hand-edited
index passes the guard and fails the checks. Under `--unattended` the index
stays refused.

## Added in v4.72.0

### 29 · The view draws a GitHub link only for `github.com/<owner>/<name>`

`build-view.sh` 1.1 builds a file or commit link from the `origin` remote only
when it is `https://github.com/<owner>/<name>` or `git@github.com:<owner>/<name>`
and both names are GitHub's own characters (letters, digits, `.`, `-`, `_`);
any other remote - another host, a mirror, a quote in the name - gets no link
rather than an escaped one (B139). Since 1.2 (v4.73.2, B146) a file path inside
such a link is percent-encoded, every character but letters, digits, `/` and
`_.-~`; that GitHub serves an encoded path as that file was not measured.

### 30 · `CLAUDE_TRANSCRIPTS` is not resolved under the root

Under the maintainer's ruling "converge on repo root" (B140, B141), a relative
path option of the eight scripts it covers is read under the repository root
rather than the working directory, and `--root` itself is read from the working
directory once. `graduate.sh` also reads a default transcripts directory from
the `CLAUDE_TRANSCRIPTS` environment variable; that is not a path option and is
used as it reads, so a relative value there is still relative to the working
directory. The lifecycle's other scripts were not swept for the same defect.

### 31 · `check-release-workflow.py` is static

It reads `.github/workflows/checks.yml` and runs nothing (B142). That GitHub
enforces the permissions the file declares, that a pinned commit is the release
its comment names, and that a tag push really attaches the pinned copy are
proven only by a real tag push. Its repository-code rule is the lexical one
`check-ci-template.py` uses, so a command spelled through a variable or an
alias, or code a system tool or another repository's action runs, is not seen;
the lines that pin the copy are matched in order, not as control flow. It needs
PyYAML, so it runs with `python3`, not `python3 -I`, which hides the user site.

## Added in v4.73.0

### 32 · An advisor set in `models.advisor` has never run in CI

`build-dispatch.sh` 1.3 passes `models.advisor` to the unattended build as one
`--advisor` argument (B161). An advisor set there has never run in CI; a set
key is not evidence an advisor was called. One local `claude -p --advisor opus`
call printed `ok`, exit 0, which shows the flag is accepted at launch and
nothing more: whether the action passes it through, whether an advisor
attaches, and when the model consults it are unmeasured, and the timing is the
model's choice, so nothing can force or cap a call. Claude Code's
`advisorModel` setting can be set in any settings file, so a committed project
`.claude/settings.json` holding it could turn an advisor on in CI with no
`models.advisor` (unmeasured); `--advisor` overrides it for the session. The
advisor reads the whole transcript, repository content included, and bills at
its own model's rates. Attended sessions do not read `models.advisor`.

### 33 · Nothing shows a model reads the stage file the skill body names

Since v4.73.0 (B162) the spec skill's `SKILL.md` keeps the routing, the stage
map and the per-turn rules, and each stage's detail is in a
`references/stage-*.md` file the body says to read before that stage. The
advisory `skill-body-budget` check holds the size and that each named file
exists; no eval shows a model opens the named reference when it enters a
stage. A topic that was in the always-loaded further-reading table now takes
one more read. The token savings are an estimate from bytes, not a count.

## Added in v4.73.1

### 34 · `secret-scan` keeps its trace log out of the result; its report is trusted to be redacted

gitleaks 8.30.1 at `--log-level trace` writes the value of a candidate it skips
to standard error, unredacted despite `--redact` (measured with a made-up key:
`TRC skipping finding: rule allowlist ... finding=<the value>`). Before v4.73.1
(B163) a short report - a `.gitleaks.toml` with three rules - let that line
into the result's `output_tail`. `secret-scan` now declares `stderr:
coverage_only`: its standard error is read for coverage and kept out of the
result and the printed tail. What is kept is the SARIF report on standard
output, and that it holds no value rests on `--redact`, checked for one
made-up key and two other made-up tokens, not for every rule. gitleaks itself is
not run by the runner's self-test; the mechanism is asserted with grep.

### 35 · The semgrep checks count a partly parsed file as not examined

Since v4.73.1 (B164) `sast`, `sast-auth` and `secure-coding-controls` count a
file only when semgrep lists it under `paths.scanned` and names it under neither
`errors` nor `paths.skipped`. semgrep 1.171.0 lists a JavaScript file with a
syntax error under both `paths.scanned` and `errors` (PartialParsing), having
run its rules over the part it parsed; such a file now makes the check hollow
rather than passing. The self-test reads a hand-written report modelled on
that output, not one semgrep produced; `paths.skipped` appears only under
`--verbose`, which the checks do not pass, so its exclusion is asserted only
against the hand-written report. Nothing watches the `json_paths` declaration
itself: `governance-weakening` does not read a coverage pattern or key path.

### 36 · Only a leading `-` is rewritten in a changed path

Since v4.73.1 (B165) `run-checks.sh` 1.5 hands a changed path that begins with
`-` to a tool as `./-...`. Before it, shellcheck and semgrep refused such a
file - the check read `refused`, which blocked the run, so nothing passed
unexamined; measured with shellcheck and semgrep, not with every data-only
tool. No other path is rewritten, and a tool that reads `./` as something other
than the current directory is not covered.

## Added in v4.73.2

### 37 · Under `--unattended`, a script is followed only through a name written whole

Since v4.73.2 (B147) `stage-advance.sh` 1.10 protects every script a protected
script names by its path, read from the base tree, resolved against that
script's directory and the root, to any depth. A script is a file with an
executable mode or a script extension. It reads names, not code: a script
reached through a name built at run time (`"$dir/$name"`, a glob, a variable),
or spelled with a character outside letters, digits and `_.@+/-`, is not
followed, and neither is a data file a script reads (a config, a rules file),
which can steer a check as surely. A script named only in a comment or a string
it never runs is protected anyway. On this repository the protected list grew
from 89 paths to 114. Since v4.74.1 (B176) 1.11 follows a symbolic link too: the
link is protected and so is the file it points to, read from the base tree, and
that file is followed if it is a script. A link whose target leaves the
repository, is absolute, or names nothing the base tree holds stays protected
and is not followed, and the reason says so; what such a link reaches at run
time is not judged. This repository holds no symbolic link, so its own list did
not change: 122 paths at 55e56c1 and after. Since v4.75.1 (B180) 1.12 resolves
a link's target, and a path a protected script names, one component at a time
as the kernel does: a component that is a link is replaced by that link's
target before a later `..` applies, and every link so passed is protected.
1.11 read the target as text, so `helper.sh -> dirlink/../real.sh` protected a
`real.sh` beside the link that never runs. A walk through more than 40 links
ends there and its target is not followed, though a kernel allowing more would
reach it; a component the base tree does not hold is walked as a directory,
which protects a path the kernel would refuse to reach.

### 38 · PyYAML's hashes were read from PyPI, not from a wheel

Since v4.73.2 (B148) the `checks` and `release-prep` jobs and the CI build
template's `prepare` job install PyYAML 6.0.2 with `--require-hashes` and
`--only-binary :all:`. The two hashes are PyPI's, for the CPython 3.12
manylinux wheels, x86_64 and aarch64, read from PyPI's JSON API on 2026-10-28;
no wheel was downloaded to check them and no runner has installed with them yet,
so the next CI run is the first proof. A runner on another architecture or
another Python would find no wheel whose hash is named, and pip's hash-checking
mode should then fail the install rather than fall back; that was not run. `yaml-hash-pinned` reads the flags in the `run:` text, not the
requirements line it writes. Since v4.74.1 (B177) it reads them as arguments of
the same pip install: the `run:` is split into commands, comments are cut where
bash cuts them and a redirection's file is no argument, so a flag handed to
`echo` after `;` no longer counts. Since v4.75.1 (B179) a `#` right after the
`)` or the backquote that closes a command substitution is part of a word, as
bash reads it, and a comment begun inside backquotes ends at the closing one;
1.3 cut both to the line end and hid an unhashed install written after them.
The comment reading follows bash's word starts, not its whole grammar, and
1.4's guess at that grammar was wrong: it counted parentheses to tell a
subshell's `)` from a substitution's, and a `case` pattern's `)` or a `(` in a
heredoc's body put the count out of step, so an install after `)#` was hidden
again (B182). Since v4.75.2 a `#` right after any `)` starts no comment, a
subshell's included - a comment there is read as commands, a deliberate
over-report - and only space, tab and a line end are blanks, as in bash. Where
the reading cannot follow bash it does not guess: a `run:` holding a `#` that
may begin a comment beside a heredoc, `case`, `${`, `((`, `[`, an alias or
posix mode, a `$'...'` string, a substitution inside double quotes, a quote or
a backslash inside backquotes, a `(` inside a word, an unmatched `)` or
backquote, or a quote after `)#` is reported as not read, even where bash would
run nothing wrong. Reading such a `run:` with no comment cut at all was tried
and rejected: a flag written in a real comment then counted. The list is what
probing found, not a proof that bash has nothing else; an alias or posix mode
turned on through a quoted or variable word or a sourced file is not seen, and
only GNU bash 5.3 and 3.2 on macOS ran the fixtures. It is still a reading of shell text, not
bash: a pip install inside `sh -c` or `eval`, or inside a quoted `$(...)`, is
reported rather than read, a pip spelled through a variable is not seen, and a
`--no-binary` written into the requirements file or `PIP_NO_BINARY` is not
read. semgrep, installed in its own virtual environment,
is still pinned by version alone, and its dependencies not at all.

### 39 · A kept step's changed body is undecided, never a weakening

Since v4.73.2 (B149) `governance-weakening` compares a job's `needs:` and `if:`
and the `run:`, `with:`, `env:` and `shell:` of a step whose key did not move.
A `needs:` that only lost a job, and an `if:` added to a job, are weakenings; a
rewritten body or condition is UNDECIDED, because whether the new one asserts
less is not decided here, so a routine edit to a step's `run:` now reads as an
advisory finding. Since v4.74.1 (B175) a step that keeps its `id` while the
action it `uses` becomes another, its `@ref` aside, is UNDECIDED too: nothing
here orders one action against another, and a pin bump stays quiet. A job's
`runs-on`, `timeout-minutes`, `strategy` and `container` are still not
compared.

### 40 · Probing self-tests side by side shortens the run, not one probe

Since v4.73.2 (B160) `selftest-coverage` probes four self-tests at once, each
under its own 180s. Measured here with that limit raised to 900s: one at a time
at v4.73.1, 63 probes took 1271s at load average 55 to 69; four at a time, 271s
at 69 to 115, the slowest probe 165s. It does not shorten any one probe: on a
machine slow enough that a single self-test passes 180s - `stage-advance.sh`
took 185s one at a time here, and three self-tests did under amd64 emulation -
the probe still reads `?` and the check refuses. That no two self-tests write
one shared path is read off their source, not enforced. Its duration on an idle
machine was not measured.

## Added in v4.74.0

### 41 · A review record is checked; the review it describes is not

Since v4.74.0 (B166, B167, B169) `check-review-record.py` reads a change's
review record (`templates/review-record.md`) and fails one whose finding has
no location, severity or class, whose count is wrong or not `no issues`, whose
finding sits under an ignored path or repeats an earlier round's, whose fourth
round names no rethought approach, whose round does not start from the last
round's head, whose answer has no reason, or whose Important finding is still
open. It reads text. Whether a finding is true, whether a fix fixed it, whether
a reason is a good one, and whether a review happened at all are not measured:
a review nobody recorded is invisible, and an author can mark an Important
finding `rejected` with any reason. The same bug at a moved line is not a
re-report to it. Ignored paths are fnmatch globs, where `*` crosses `/`, not
gitignore patterns, and a cell holding a literal `|` splits its row. The round
cap holds the in-session Stage 6 loop; the CI build template runs no reviewer.
The template's `review-record` check triggers on `docs/sdlc/**/review.md`, the
default artifacts path, and reads not_triggered in this repository, which keeps
no review records.

### 42 · A pull request body is read only when someone saves it to a file

Since v4.74.0 (B168) `check-plan-record.py` fails a plan with no `Proof` or no
`Revert` beyond the template's placeholder, and with `--kind pr-body` a body
with no *How it was tested* or *How to revert*, and since v4.77.0 no *Proof it
works* (limitation 48). The template's `plan-record`
check reads plans; a body lives on GitHub and nothing in the lifecycle fetches
one. Whether the tests named were run, and whether the revert path works, are
not measured.

### 43 · CODEOWNERS is checked; the settings that make it bind are not

Since v4.74.0 (B172) `check-approval-rules.py` reads the CODEOWNERS GitHub
would read and fails when a file under `.claude/productizer/` or
`.github/workflows/`, or one a change adds there, has no owner other than a
bot. Code owner review, stale approvals dismissed on a new commit,
most-recent-push approval, no bypass, and whether GitHub Actions may approve a
pull request are settings on GitHub, named in
`references/stage-3-6-build.md` from GitHub's documentation and measured by
nothing here; whether an approval made with `GITHUB_TOKEN` counts toward
required reviews is not stated in that documentation. A bot is recognised only
by a `[bot]` suffix, so a machine user with a plain name reads as a person and
a team as people. Since v4.75.0 (B178) this repository commits
`.github/CODEOWNERS` and its own `approval-rules` check runs and passes; whether
"Require review from Code Owners" is on for its `main` is the maintainer's
setting, not changed here and not known. Requiring the person who dispatched an
agent run as a reviewer of its pull request is not built (B173).

## Added in v4.75.0

### 44 · A reviewer case is scored by location; the workflow that runs the reviewer never ran

Since v4.75.0 (B170) a revert or an incident becomes a case under
`evals/reviewer/` (`templates/reviewer-case.md`), and `score-reviewer-case.py`
scores a review record against it with no model: caught when round 1 reviewed
the case's change and an Important finding's line range covers the bug. It
matches text. A finding at the right line about a different bug is a catch, a
finding one line off the recorded range is a miss, and whether the case's bug
location is the real one is a person's to judge. `templates/agent-evals.yml`
runs the reviewer agent on each case and saves what it prints as the record;
it has never run on a GitHub runner, and whether `claude -p --agent
sdlc-reviewer` prints a record the scorer reads is not measured. A scheduled
eval task installed from `templates/scheduled-evals.md` reads every
subdirectory of `evals/` as a prompt and will meet `evals/reviewer/`, which
holds none. `check-revert-cases.py` finds a revert by its `This reverts commit`
line: a revert written by hand without it, and an incident, are not seen, so a
missing incident case is noticed only by a person.

### 45 · Two more bands, measured one point at a time

Since v4.75.0 (B171) `band-revert-rate.py` and `band-review-rounds.py` measure
the revert rate and the review rounds per change over the last 30 days against
the six 30-day windows before, and print a tier from the value's distance above
their mean. Only that one point is read: the Western Electric run rules the
first band's `bands.yaml` names are not evaluated for these two. Only a rise is
a breach. A baseline of equal values, common for a team that rarely reverts,
leaves a rise unmeasured (exit 3), and fewer than three earlier windows with a
value leaves the band unmeasured: on this repository, 2026-10-28, both bands
read NOT MEASURED. A change is a first-parent commit, so a repository that
merges with merge commits and one that squashes count the same work alike, but
one that pushes many commits straight to the default branch counts each. A
change with no review record is invisible to the rounds band. Each added band
has its own bands file, binding and scheduled task; the comparison of the
binding with the frozen literal is the prompt's, made by a model, as for the
first band, and no task was installed in this release. The band view
(`build-view.sh`) still shows only `ops/bands.yaml`.

## Added in v4.75.1

### 46 · The view's reading of a path on another drive was driven with ntpath, not run on Windows

Since v4.75.1 (B181) `build-view.sh` 1.3 reads its own output file, and a
result file it names on the page, as outside the repository when the two are on
different drives, where 1.2 called `os.path.relpath`, which on Windows raises
for two drives: the dashboard writes under the temp directory, on C:, so a
repository on D: would not build. That failure was reproduced with `ntpath`,
not on Windows. The self-test's A17 hands the two functions Windows paths
through Python's `ntpath` on this machine. No Windows machine has built a page,
so any other path the builder reads on Windows is not known to work.

## Added in v4.76.0

### 47 · The caps on the unattended build have never stopped a run

Since v4.76.0 (B183) every run of the CI build template passes the agent
`--max-turns` and `--max-budget-usd`, from `models.build_caps` or the built-in
defaults of 100 turns and 20.00 dollars, and the template's agent step carries
those defaults itself. What holds this up is read, not run:

- **No capped run has happened.** The template has never run on a GitHub
  runner (limitation 18), so no run has been stopped by either cap. The
  self-tests assert the lines `prepare` writes and `agent-args` passes, and the
  `caps` assertion reads the YAML.
- **The flags are taken from Claude Code's documentation.** Its CLI reference
  documents both as print mode only: `--max-turns` "Exits with an error when the
  limit is reached. No limit by default.", and `--max-budget-usd` stops the run
  at Claude Code's own client-side cost estimate, which "can differ from your
  bill". `claude --help` in 2.1.295 lists `--max-budget-usd` and not
  `--max-turns`. The action runs the CLI through the Agent SDK, which documents
  both as options; that it reaches print mode there was read in the SDK's
  source, not run.
- **The spend cap can be passed.** Claude Code checks it after each response,
  so a run can end above it by the response that crossed it, plus what running
  subagents spend before they stop.
- **A capped run opens nothing.** Read in the action's source at the pinned
  commit: a result that is not a success fails the step, so the `generate` job
  fails and `deliver` never runs. The work done up to the cap is lost, not
  delivered as a partial draft.
- **The prepared caps win by the action's parsing.** The template's own caps
  come first and the prepared ones follow; the action keeps the last value of a
  flag that does not accumulate. Read in its source at the pinned commit, not
  run.
- **The defaults were chosen, not measured.** 100 turns and 20.00 dollars have
  not been compared with a real plan or build run; a repository whose runs need
  more sets `models.build_caps`.
- **The scheduled prompts get no cap from this.** `templates/scheduled-*.md`
  run as scheduled agents outside the template, and nothing here bounds them.

## Added in v4.77.0

### 48 · The proof on a pull request is checked as text, and nothing produces it

Since v4.77.0 (B184) `templates/pull-request.md` asks for *Proof it works*:
what a person sees when using the change, against the original request, each
item naming the `R<n>`, `B<n>` or `#<n>` it answers and carrying a screenshot,
a recording, a fenced log or a link to a run's artifact, or the one line
`**n/a** - <reason>`. `check-plan-record.py --kind pr-body` reads it. What it
does not do:

- **It reads text.** A screenshot of the wrong page, a link that does not open,
  a log from another build and an id the item does not answer all pass. Whether
  the evidence shows what the request asked is the reviewer's to read
  (`REVIEW.md`), and an `n/a` reason is read only for being there.
- **Nothing produces the proof.** The lifecycle runs no browser, takes no
  screenshot and uploads nothing to GitHub; exercising the change end to end
  and attaching the evidence is the author's. The intent asked for the pipeline
  to do both; only the checking half is built.
- **A body is read only when saved to a file** (limitation 42): nothing fetches
  one from GitHub, so a body edited on GitHub after it was checked is not
  re-read.
- **The CI build template's draft fails its own checker.** `deliver` writes the
  body before anyone has used the change, so it carries *How it was tested*,
  *Proof it works* and *How to revert* as placeholders owed by the author before
  the pull request leaves draft, and `check-plan-record.py --kind pr-body` exits
  1 on it, 0 of 3 assertions held, by design. Nothing checks that the author
  filled them before marking it ready; that is the reviewer's.
- **Its shapes are fixed.** A proof item is a list line at the left margin; a
  paragraph of proof with no list marker is refused, and an id is read only
  outside the item's fences.

## Added in v4.78.0

### 49 · The plan page is read as bytes, and the person's reading of it is not known

Since v4.78.0 (B185) `scripts/build-plan-page.sh` turns a plan into a page a
person comments on and answers, and `scripts/plan-answers.py` takes the answer
set back into the plan (`references/plan-page.md`). What it does not do:

- **It cannot know the person read the page**, or that an answer is a
  considered one. A valid answer set says which buttons were pressed.
- **A comment is free text the agent interprets.** The validator checks the
  passage it names and the words it quotes, not what it means; comments are
  printed and never written into the plan.
- **No check runs the page in a browser.** `check-plan-page.py` reads the built
  page's bytes and its HTML parse - Python's parser standing in for a
  browser's - against lists of elements, attributes and APIs, and holds the
  script to the template's byte for byte. The buttons, the selection comment
  and the copy were driven by hand in one browser in the session that built
  them.
- **The clipboard may refuse.** In a sandboxed frame - an Artifact, say - the
  copy can be refused; the page then says so and selects its answer set for the
  person to copy by hand. Whether an Artifact frame refuses it was not
  measured. The save-as-file link is offered only outside a frame.
- **A capability granted at publish time is not seen.** The page asks for none,
  and the checks read the page; `artifact-gate.sh` refuses a self-publishing
  capability in the publish call and allows `downloads`, so publishing the plan
  page with `downloads` granted would not be refused. Publish it with none.
- **The theme reads custom properties only**, and only of a colour or a
  font-name shape. A bare `0 0% 100%` triplet, colours set any other way, and
  a font not installed on the reader's machine are not taken; a font is named,
  never loaded, and no contrast is measured.
- **The open-question syntax is fixed.** A question is `- Q<n>: ...` at the
  left margin with options `  - A: ...` under it; anything else in the section
  stops the build, and a plan edited between building the page and answering
  it refuses the answers until the page is rebuilt.
