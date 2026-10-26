# Stages 7 and 8 in full: document, announce

Read this before Stage 7 regenerates the guide and before Stage 8 drafts a
release post or email. SKILL.md keeps the rules; this is both stages as a
whole, with the reasons. Release mechanics: `references/release.md`.

### 7 · Document — regenerate the guide, per release
The user guide is generated **once per release**, not per intent
(`templates/user-guide.md`, `references/release.md`). Per-intent docs produce a
changelog with headings: every entry accurate, the document as a whole
describing no product. Sections map to **active** requirement ids, so behaviour
that was superseded or withdrawn leaves the guide without anyone remembering to
delete it, and the mapping table names the **actives with no section** — an
omission and full coverage look identical unless the gap is stated.
**Screenshots come from the released build, in this session, with the version in
the filename.** A screenshot from the previous release is a lie with a picture
attached, and it is the one thing in a document that gets published unreviewed.

### 8 · Announce — agent-driven, human-gated
The release post and the release email are drafted from the spec deltas and the
merged PRs (`templates/release-blog.md`, `templates/release-email.md`). Different
audiences: the post is for people who do not use the product, the email is for
people who do and may **have to act**, so its action-needed block comes first or
is deleted outright. **Every claim traces to a merged PR or a requirement id,
every number was measured, and the release names what it does not do.** Scrub
customer names, repo names, internal hostnames and the employer's name — from
the screenshots too, where a title bar or a sidebar carries more than whoever
captured it intended.

**The stage runs as an agent stage; the publish waits on a person.** The agent does the
whole job — writes both artefacts, captures the screenshots from the released
build, verifies the version is live and installable, runs the pre-publish
checklist and reports which items it could not verify itself. What it does not do
is decide. It shows the draft, names what it could not verify, and asks; on an
explicit yes it runs the command itself. The person owns the judgement, not the
typing - handing them something to paste makes approval a chore, and a chore
becomes a rubber stamp. `templates/publish-gate.sh` blocks the commands that reach an
audience — `gh release create`, `npm publish`, a tag push, a mail API, a site
deploy — and lets everything the agent needs for its own work through.

Same shape as Stage 6, and for the same reason: every other artefact in this
lifecycle is a commit somebody can revert. A post is indexed and forwarded
within minutes, and mail cannot be recalled.
