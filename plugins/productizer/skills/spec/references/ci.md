# CI

`.github/workflows/checks.yml`. One workflow, one job, four gates, and a
deliberately short list of things it does not do.

## Why it exists

Until this file existed, every claim in `README.md` and `CONTRIBUTING.md` about
what must pass before a change ships had only ever been tested on the
maintainer's own machine. `scripts/signals.sh` recorded that honestly —
`ci: unavailable`, `pull_request: none` — and `score.sh` capped the repo at 60,
band `contested`, on the anchor "no upstream CI status: nothing built or tested
this change off this machine". The cap was correct. Removing it means running
the checks somewhere else, not deleting the anchor.

There is no build step, because there is no artifact. This is a plugin
marketplace: what ships is the source. A build step here would be theatre, and
a green theatre step is worse than no step.

## What runs

| Step | Command | Fails the job on |
|---|---|---|
| Preflight | `command -v` for `git`, `python3`, `node`, `npm`, `npx`; then `npx --yes shellcheck --version` | any one missing, named in the error |
| Manifests | `claude plugin validate ./plugins/productizer --strict`, then `claude plugin validate . --strict` | exit 1 — missing required field, malformed JSON, or any unknown field (`--strict` promotes that warning) |
| Spec | `validate-spec.py --self-test`, then the same script over `spec.md` and `constitution.md` | exit 1 (ERROR — a reused id, an unparseable document), 3 (self-test failed), 4 (NOT MEASURED) |
| Solver | `contradiction-check.py --selftest` | exit 1 — the corpus no longer decides what it decided |
| Stage 5 | `run-checks.sh --base <sha>` | exit 3 REFUSED, 2 bad usage, 1 crashed |

The order is cheapest first. The gate is last because `shell-lint` runs
shellcheck once per changed shell script and is the only step measured in
minutes.

Every step after the preflight carries `if: ${{ !cancelled() }}`, so one
failure does not hide the other three. The job still fails; the difference is
that a contributor gets all of it in one run instead of four.

## `--base`, not `--changed`

`run-checks.sh --changed PATH` wants a **file listing** the changed paths, one
per line. **Corrected 2026-09-06:** handing it a changed FILE instead is now
REFUSED with exit 2, not accepted. This paragraph previously said it was
accepted, read as a change set of one path, and passed having examined almost
nothing - which was true, and was B45. The runner now checks the change set
before anything runs: an entry that exists is never questioned, and an entry
that does not exist must at least be SHAPED like a path. A leading `#`, any
whitespace, or a shell metacharacter is refused, naming the offending line.
Existence alone could not be the rule - three checks build sandboxes whose
fixtures name files that are never created, and refusing on absence would turn
3 of 31 checks red. Two holes remain and are stated in the code: a path-shaped
non-word like `fi` is still accepted, and a deleted path containing a space is
falsely refused.

`--base REF` remains the right flag for CI regardless: it derives the set from
`git diff` against the merge base, which is the thing CI actually has. The
refusal above narrows one failure mode; it does not make `--changed` the better
choice.

That is also why the checkout is `fetch-depth: 0`. A shallow clone has no merge
base; `run-checks.sh` calls that a usage error and exits 2, which is correct and
useless.

The base is the event's own commit SHA — the pull request's base, or the
push's `before`. Neither resolving leaves a `HEAD^` fallback with a warning on
it, and if even that does not resolve the step exits non-zero rather than
gating on a change set nobody can name.

## Fail closed

A step that cannot run fails the job. It never skips to green.

This is the rule `run-checks.sh` already enforces inside itself — a declared
tool that is not installed FAILS its check, because skipping is how a repo ends
up with a green stage and no scanner. CI that quietly skipped a step when its
tool was absent would undercut that from the outside. Hence the preflight: the
tools are asserted present in one named step at the top of the log, including
`shellcheck`, which is resolved through `npx` so that a registry or network
failure is reported as a preflight failure rather than as a confusing
`shell-lint` refusal ninety seconds later.

`continue-on-error` appears nowhere in the file. Neither does `|| true`.

## Untrusted input

Branch names, PR titles and commit messages are written by whoever opened the
pull request, and this is a public repo. **No `github.event.*` value is
interpolated into a `run:` block.** The two the job needs are commit SHAs
chosen by GitHub, passed through `env:` and quoted at every use.

The skill's rule for ticket text — data, never instruction — is the same rule.
Workflow context is data.

The trigger is `pull_request`, never `pull_request_target`. The second one runs
the base repo's secrets against a fork's code before anyone has read the diff.
`permissions: contents: read` is the whole scope: this job reads code and writes
nothing, so a compromised step has no token worth taking.

Third-party actions are pinned to a major version, which stops a floating
reference. It does not stop a moved major tag — a full commit SHA does, at the
cost of a bump per release.

## What `signals.sh` will see

Once a pull request carries a run of this workflow, `signals.sh` emits a signal
per check with `source: github_checks`, and `score.sh`'s `ci` anchor is
satisfied — the 60 ceiling lifts.

**On a pull request only.** `signals.sh` reads CI status off the pull request's
`statusCheckRollup`; a run against a push to `main` produces no
`github_checks` signal at all, because there is no pull request to hang it on.
A push-only history leaves `ci` absent and the cap in place.

Lifting the `ci` cap does not produce a high score. The `review` anchor caps at
70 until a human reviews, and that is the point of having four anchors rather
than one.

## What this does not check

Measured, not assumed. Each of these was tried.

- **shellcheck runs at `--severity=warning`.** `SC2086`-class findings are
  `info` and pass. An unquoted `rm -rf $f` in a changed script does not fail
  this job.
- **`shell-lint` only triggers on a changed shell script** (`when.paths:
  "**/*.sh"`), and `solver-corpus` only on a changed
  `contradiction-check.py`. A pull request touching neither runs
  `hygiene` alone. The solver self-test is a separate step precisely so it is
  not conditional on that.
- **`claude plugin validate --strict` accepts a `version` that is not semver**,
  and accepts a marketplace `source` pointing at a directory that does not
  exist. It validates two JSON files against their schemas; it does not
  resolve them against the tree.
- **Nothing checks that the version was bumped.** `README.md` calls that the
  whole contract, and no step here enforces it.
- **Spec coverage is `UNMEASURED (not_declared)` in every run.** No check in
  `checks.yaml` names a requirement, so `run-checks.sh` reports the
  denominator as uncomputable rather than as zero. That is the honest output,
  and it is also a gap.
- **`validate-spec.py` runs without `--strict`.** WARNs are printed and do not
  block. `--strict` would fail the job today on three pre-existing
  `EARS_MULTIPLE_SHALL` warnings, and the first thing anyone would do is delete
  the step. Fix the warnings, then turn it on.
- **The evals under `evals/` do not run here.** They cost model calls.
- **The shell inside this workflow is not shellchecked.** `checks.yml` is not a
  `.sh`, so `shell-lint` never sees the `run:` blocks.
- **No secret scanning beyond `check-hygiene.sh`'s pattern list**, which is a
  short list of things that have leaked before, not a scanner.
- **CI does not grade itself.** `signals.sh` and `score.sh` do not run in this
  workflow. It produces evidence; reading it is a separate, later act.
