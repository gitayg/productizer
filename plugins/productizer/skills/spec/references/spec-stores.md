# Spec stores — the living spec in its own repository

The default is a **spec home**: one repo in the product holds
`.claude/productizer/spec.md` and also holds code. Every other repo points at it. That
works, and for most products it is the right shape.

A **spec store** is the alternative: the living spec lives in a repository of
its own, holding no product code, and every repo in the product consumes it
**read-only**. One spec, one id space, one allocator — the same invariants, moved
out of a code repo.

This is a variant of the layout SKILL.md already describes, not a replacement
for it. Everything in *Products and repos* still holds: one living spec per
product, ids never reused, intake classified against the whole spec.

## What changes and what does not

| | Spec home (default) | Spec store |
|---|---|---|
| Where the spec lives | inside a code repo | its own repo, no product code |
| Who may write it | that repo's writers | the store's writers only |
| How other repos read it | across a repo boundary | across a repo boundary |
| Id allocator | one, in the home | one, in the store |
| Intake when unreachable | stops | stops |

The read is across a boundary either way. A store does not remove that cost; it
removes the *asymmetry* — no repo in the product is privileged, and nobody
inherits write access to the spec by being a committer on the busiest service.

## Config

Declare the store where the home would have been declared. Both forms are the
`product` block in `.claude/productizer/config.json`:

```json
"product": {
  "name": "orders",
  "spec_repo": "acme/orders-spec",
  "spec_kind": "store",
  "spec_ref": "main",
  "spec_path": ".claude/productizer/spec.md",
  "repos": ["acme/orders-api", "acme/orders-web", "acme/orders-jobs"]
}
```

`spec_kind` is `home` (default, omit it) or `store`. When it is `store`,
`spec_repo` is not in `repos` — it holds no code and ships nothing.

**Pin `spec_ref` to a branch, never to a commit.** A repo pinned to a sha
classifies today's intent against last quarter's agreements and reports
`duplicate` and `extend` confidently wrong. Shas belong in the *record of what
was read*, not in the binding.

### `product.spec_path` is not `spec.path`

These two keys look like one key spelled twice. They are not, and reading
either as the other is how a tool ends up checking the wrong file and
reporting a pass.

| Key | Scope | Resolved against | Read by |
|---|---|---|---|
| `spec.path` | this work tree | the local repo root | `validate-spec.py --repo`, `check-spec-home.sh`, `check-spec-home-stop.sh`, `check-spec-integrity.sh` |
| `product.spec_path` | inside `spec_repo` | the store checkout, at `spec_ref` | the fetch in *How a consuming repo reads it* below |

`product.spec_path` is the path the fetch in step 1 asks the store for. It is
**never** joined to a local repo root — a consuming repo's tree has no file at
that path except a cache, and a cache is not the spec. `spec.path` is the only
key any local tool resolves against a work tree.

A config that declares both and disagrees is refused rather than resolved:
two answers to where the spec is, and nothing states which wins.

### What a store-shaped repo gets from the local tools

`validate-spec.py --repo ROOT` describes a **work tree**. It opens no network
connection, follows no binding, and reads no credential — so it cannot reach a
store, and it does not try. When the config declares `spec_kind: store` it
**refuses at exit 4** with `DISCOVERY_REFUSED`, naming the store and the ref,
and reads nothing.

That refusal is the point. Every consuming repo caches the store somehow —
*"a clone, a CI checkout, a mirrored file"*, as **What it costs** says below —
and the cache usually lands at exactly the default spec path. Before the
refusal existed, `--repo` in a consuming repo discovered that cache, checked
it, and printed `1 file(s) checked: 0 error(s), 0 warning(s)`: a clean result
about another repository's file, at a sha nobody printed, in the tool that is
the single source of *which files are the spec*.

To check the store, point the tool at a checkout of the store itself. That is
an operator naming a directory, not a config naming one — which is also why a
`spec.path` that leaves the work tree (absolute, or climbing out with `..`) is
refused: a repository being examined does not choose what gets read on the
machine that cloned it.

## When it earns the extra repo

Take a store only when at least one of these is true:

- **Three or more repos** in the product, none of them the obvious owner. With
  two, one is nearly always the natural home; a store buys nothing and costs a
  repo.
- **The spec's readers and the code's writers are different populations** —
  compliance, support, a partner team — and the code repo cannot be opened to
  them. Copying the spec somewhere they can read it creates a second copy, and
  a second copy is a second allocator waiting to happen.
- **Write access to the spec must be narrower than write access to any code
  repo.** In a home, anyone who can merge to the home repo can merge a spec
  edit. Branch protection on a path is weaker than branch protection on a repo,
  and the failure is silent: an agreed requirement changes inside a code PR
  nobody read as a spec change.
- **The home repo is unstable** — being split, archived, or renamed. A spec that
  moves whenever the code is reorganised loses its history at exactly the moment
  the history is worth most.

## When it is overkill

- **A single-repo product must never do this.** The repo is its own spec home,
  the `repos` list has one entry, and a second repository adds a boundary, a
  credential and a second PR to every change in exchange for nothing. SKILL.md
  already says it plainly: *"Do not make a separate spec repo for a product that
  is one repo."*
- **Two repos with one team and one access list.** Designate a home.
- **A product still finding its shape.** Requirement churn is highest in the
  first weeks, and that is when the two-PR cost bites hardest. Start with a
  home; migrating to a store later is a file move, migrating back is the same.

## How a consuming repo reads it

The consuming repo never holds an editable copy. It fetches the store at the
binding's ref, uses it, and records what it read.

1. Fetch `product.spec_path` from `spec_repo` at `spec_ref` — a local clone
   the reader updates, or the host's contents API. The path is relative to the
   **store**, never to the consuming repo.
2. **Record the commit sha of what you fetched**, and state it in the intake
   output, the plan and the PR description: *classified against
   `acme/orders-spec@3f9c1a2`.* Without the sha, a classification cannot be
   re-derived later, and every disputed intake becomes an argument about which
   version was on screen.
3. Read it in full. Partial reads defeat contradiction detection, which is the
   only reason the living spec earns its cost.
4. Never write to the fetched copy. If a local clone exists, treat it as
   read-only working state — a spec edit made there is either lost or pushed
   from a repo that has no right to allocate.

Any cached copy carries its sha and its age wherever it is shown. A cache with
no provenance stamp is indistinguishable from the spec, and gets cited as it.

## When the store is unreachable

**Intake stops.** This is not degraded operation; it is the only correct
behaviour, and SKILL.md states it for the home layout in the same words:
*"If the spec home is unreachable, intake cannot run. Say so and stop; never
classify against a spec you could not read, and never fall back to a local
partial copy."*

Say which fetch failed, name the repo and ref, and stop. Then:

| Operation | Store unreachable |
|---|---|
| Classify an intent | **stop** — a `duplicate` or `extend` verdict from a stale spec is a wrong verdict, stated confidently |
| Allocate an id | **stop** — allocating without the tip is how two `R42`s happen |
| Merge a delta | **stop** |
| Run a drift check | **stop** — see `references/drift.md`; report it as unavailable, never as clean |
| Quote a requirement someone already cited | allowed, **only** with its sha and age printed and the words "not authoritative" |

Do not retry silently and do not reconstruct the spec from plans, tests or PR
titles that cite ids. Those cite ids; they do not carry the agreement.

## Keeping one allocator

The allocator is the `Next requirement id` line in `templates/spec.md`. It is
single-writer because exactly one repo may commit to the store. That property is
enforced by repository permissions, not by convention — a second writable copy
is a second allocator, and duplicate ids are the one unrecoverable mistake in
this design.

Allocation is one operation:

1. Read the store at the tip of `spec_ref`. Not a cache.
2. Take ids from `Next requirement id`, write the requirements, bump the line —
   **in the same commit.** A commit that bumps the counter without writing the
   requirement leaks ids; a commit that writes requirements without bumping it
   hands the same ids out twice.
3. Push. If the push is rejected because the tip moved, **re-read and
   re-allocate** — never rebase the old numbers forward.

The counter is a single line, so two concurrent allocations conflict in git
rather than merging cleanly into one wrong file. That conflict is the mechanism.
Never resolve it by keeping both sides' numbers.

**Re-allocating an unmerged proposal is not renumbering.** An id becomes
permanent when it lands on the store's default branch; before that it is a
proposal that nothing cites. Once merged it is fixed forever — *"Ids are never
reused and never renumbered"* — because plans, tests, review findings and PR
titles all cite it. Nothing is ever deleted from the store, superseded and
withdrawn requirements included.

## Joining a spec change to a code change

Two repos, two PRs, one issue. The issue number is the join, and it goes in both
branch names and both PR titles, exactly as it does today.

**The spec PR merges first, always.** A code PR citing an id that does not yet
exist at the store tip cites nothing, and a reviewer checking compliance against
the spec finds no requirement to check against. Order:

1. Spec PR on the store: the delta, the change-log row, the issue number.
2. Merge it. Note the resulting sha.
3. Code PR in the code repo, citing the requirement ids **and** that sha.
4. Review reads the spec at that sha, not at the tip — otherwise a spec change
   landing mid-review silently moves the standard the diff is judged against.

Two failure modes to name, because both are invisible without looking:

- **Spec merged, code never ships.** The spec now asserts behaviour that does
  not exist. Nothing in the lifecycle notices on its own; that is what
  `references/drift.md` is for.
- **Code merged, spec PR abandoned.** The code cites ids that were never
  allocated. Make the code PR's cited ids resolvable against the store a
  required check, or accept that citations rot.

## What it costs

Say this out loud before recommending it:

- **A second repository** to create, permission, back up and keep alive.
- **A second PR for many changes**, with a second review, a second CI wait and a
  second set of approvals. Small refinements feel disproportionate, and a team
  that finds them disproportionate stops making them — which quietly returns you
  to a spec that lies.
- **A sync step that can go stale.** Every consuming repo caches the store
  somehow: a clone, a CI checkout, a mirrored file. Every cache is a chance to
  classify against yesterday. The sha stamp is what makes staleness visible; a
  cache without one is a silent fork.
- **A credential in every consuming repo** if the store is private, including in
  CI. That is a new secret with a rotation problem, and a repo that cannot read
  the store cannot run intake at all.
- **Latency on the tightest loop.** Intake now waits on a network fetch. It is
  the stage that must not be skipped, and it is the one you made slowest.

If none of the triggers above apply, the home layout is better. Fewer moving
parts is not a consolation prize here.

## Migrating

**Home to store.** Create the store repo. Move `.claude/productizer/spec.md` with its
history if the tooling allows — the audit trail is `git log -p` on that file, and
a move that drops it destroys the only per-change record. Update `product` in
every repo's `.claude/productizer/config.json` in one pass. Then **delete the file from the old
home in the same change** and leave the config pointing at the store. Two
editable copies is two allocators; leaving the old one behind "for reference" is
how that happens. The file moves whole — superseded and withdrawn requirements
included. Nothing is removed from the spec by a migration.

**Store to home.** The reverse, with the same rule: one copy at the end.

Either way, the ids do not change. That is the point of them being permanent.
