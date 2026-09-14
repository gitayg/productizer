# Documentation and go-to-market, per release

Two stages that run **once per release**, not once per intent. Stages 1–5 move
one change; a release is the batch a user actually receives, and it is the first
moment anyone outside the team is affected by any of it.

- **7 · Document** — the user guide, regenerated from the spec and the release.
- **8 · Announce** — the release post and the release email, drafted from the
  delta and the merged PRs.

Templates: `templates/user-guide.md`, `templates/release-blog.md`,
`templates/release-email.md`.

## Why per release rather than per intent

Per-intent documentation produces a changelog with headings on it. Each entry is
accurate and the document as a whole describes no product — the reader gets
twelve small announcements and no account of what the thing does now. It also
documents work nobody has received yet: an intent merged behind a flag is in the
guide before it is in the product.

Per release is also the only cadence at which the **removals** are visible.
Within one intent, a superseded requirement looks like an edit. Across a
release, the set of superseded and withdrawn ids is the list of things that used
to work and no longer do — the changes readers most need and least often get.

## What the stage reads

Nothing is authored from memory of the work. Both stages read:

| Source | Gives |
|---|---|
| The living spec, active requirements | what the product does now — the guide's sections |
| Superseded and withdrawn since the last release | what changed and what was removed |
| The spec deltas in the release's PRs | which change served which requirement, and why |
| The merged PRs | what actually shipped, as opposed to what was planned |
| The released build | the screenshots, and the commands, run |

The spec answers *what is true*; the PRs answer *what shipped in this batch*.
Both are needed, and they disagree more often than anyone expects — a merged PR
that changed no requirement is either undocumented behaviour or a refactor, and
the difference matters enough to ask.

## The rules that are not negotiable

**The agent drafts, a person approves, the agent runs it.** 5C is an agent
stage like the rest: it writes both artefacts, captures the screenshots,
verifies the release is live and installable, runs the pre-publish checklist,
and says which items it could not verify itself. Then it stops and asks.

What the person owns is the **decision**, not the typing. Handing them a command
to paste is a worse design in both directions: it drops them into a terminal to
run something they did not compose and cannot easily check, and it makes the
approval a chore - and a chore becomes a rubber stamp. Asking plainly and then
executing on an explicit yes keeps the judgement with the human and the
mechanics with the agent, which is the split the whole lifecycle uses.

An explicit yes means this publish. Not silence, not an inferred yes, and not a
yes given to some earlier question. The publish is enforced as a hook
(`templates/publish-gate.sh`) rather than left as a convention — a rule the
agent is asked to remember is a rule it eventually reasons past.

The gate denies the commands that reach an audience — `gh release create`,
`npm publish`, a tag push, a mail API, a site deploy — and allows everything
the agent needs to do its own work, including committing drafts and rendering
images. Same shape as the production gate at Stage 6, for the same reason:
every other artefact here is a commit someone can revert; a post is indexed and
forwarded within minutes, and mail cannot be recalled.

**In this repository, CI drafts the GitHub release and a person publishes it.**
Measured 2026-09-14: of 81 version tags, 22 had a release page, and nothing in
the workflow had ever created one - while several release checklists said a tag
push did. The `release-draft` job in `.github/workflows/checks.yml` now runs on a
version-tag push, only after `checks` passed on that tag. It assembles the notes
with `build-release-notes.sh`, creates the release as a **draft**, and reads it
back, failing the job if the release is anything but a draft. A draft is visible
only to people with write access, so nothing has reached an audience yet: the
person publishing edits the evidence into prose, runs the checklist above, and
presses Publish. The job never edits a release that already exists. This is the
same split as the rest of the stage, with the typing moved into CI rather than
into a command someone runs by hand. The notes are evidence, not the post.

**Screenshots come from the released build, in this session, with the version in
the filename.** A screenshot from the previous release is a lie with a picture
attached, and it is the most common way documentation goes silently wrong: the
prose gets reviewed, the image does not.

**Every number was measured.** "Twice as fast" requires two measurements, the
machine, and what was measured. A benchmark reasoned about rather than run is
the fastest way to lose the readers this is written for.

**Every claim traces to a merged PR or a requirement id.** A post is a claim
about the product made in public. If the trace cannot be produced, the sentence
comes out — including the ones that are probably true.

**Name what is not in the release.** The adjacent thing this release does not
do, and whether it is coming. Readers find that out in ten minutes regardless;
the only choice is whether they hear it from you first.

**Scrub before it leaves.** Customer names, repo names, internal hostnames and
the employer's name are all reasons a draft never becomes a post. Check the
screenshots too — a terminal title bar, a browser tab and a sidebar each carry
more than the person capturing them intends.

## Coverage, stated rather than assumed

The guide's requirement mapping names, for each section, which active
requirements it covers — and then names the **actives with no section**. An
omission and full coverage look identical unless the gap is stated, which is the
same reason a check declares what it must have examined (`references/checks.md`).

Undocumented is a legitimate state. Silently undocumented is not.

## The website checklist

A release that changes what the product *is* changes what the site must *say*.
Stage 8 is not done when the post is published; it is done when the site no
longer describes the previous release.

The distinction that matters here is **generated versus hand-maintained**,
because it is the only thing predicting which item goes stale. A generated file
cannot be forgotten — it can only be wrong, and it is wrong loudly. A
hand-maintained file goes stale **silently**: nothing fails, nothing warns, and
the omission is discovered by a reader months later. Every item below is
labelled, and the hand-maintained ones are the checklist's entire reason for
existing.

Run from the site repo root, after a build. `SLUG` is the new product or page
stem (`productizer`, `productizer-vs-*`).

**Sitemap — GENERATED. Verify, do not edit.**

```bash
npx @11ty/eleventy --quiet
grep -o '<loc>[^<]*</loc>' _site/sitemap.xml | grep "$SLUG"
```

Expect one `<loc>` per new page. Zero means the page is not in the build, not
that the sitemap is wrong — fix the page, never the sitemap. Editing generated
output produces a file that is correct until the next build.

**`llms.txt` and `llms-full.txt` — HAND-MAINTAINED. These are the ones that rot.**

```bash
grep -ci "$SLUG" llms.txt llms-full.txt
```

Zero on a shipped product is the failure this checklist was written for. Nothing
generates these files, nothing validates them, and no build breaks when they are
a release behind — so they are wrong for as long as nobody looks. A new product
needs its own section in **both**: `llms.txt` gets the positioning line, the
blockquote and the link list; `llms-full.txt` gets the long-form entry and a
`## Site structure` line per page. Adding pages to an existing product is the
same check with a smaller diff, and is missed more often than adding a product.

Also update, in the same pass, the cross-product lines that name the portfolio —
the count and product list in the `llms.txt` header, and the "technical
reference for X and Y" pointer. They are prose, so no count catches them.

**`robots.txt` — HAND-MAINTAINED, rarely changes.**

```bash
cat _site/robots.txt
```

Confirm no `Disallow` matches the new paths. A blanket `Allow: /` covers new
pages automatically; a per-path allowlist does not, and that is the trap.

**Per-page `<head>` — GENERATED FROM A TEMPLATE, so a template defect hits every
page using it at once.**

```bash
for f in _site/${SLUG}*.html; do
  h=$(sed -n '1,/<\/head>/p' "$f")
  printf "%-40s can=%s og=%s tw=%s ld=%s ent=%s\n" "$f" \
    "$(printf '%s' "$h" | grep -c 'rel="canonical"')" \
    "$(printf '%s' "$h" | grep -c 'property="og:')" \
    "$(printf '%s' "$h" | grep -c 'name="twitter:')" \
    "$(printf '%s' "$h" | grep -c 'application/ld+json')" \
    "$(printf '%s' "$h" | grep -c '&[a-z]\{2,\};')"
done
```

`ent` counts entity sequences in the **source**, which makes a non-zero value a
lead and never a finding. **Verify it by parsing before you report it.** The
four `productizer-vs-*` pages score `ent=3` — `<title>`, `og:title` and
`twitter:title` each written with `&mdash;` and `&middot;` where the other pages
use the literal characters — and this renders **correctly**. `<title>` is
RCDATA and `content` is an attribute value; both decode character references.
Measured on the live page, `document.title` is `Productizer vs Entire — a
declared spec vs captured agent sessions · glick.run`, and
`/&(mdash|middot);/.test(document.title)` is `false`.

A raw-source grep therefore reports a browser-tab defect that no browser shows.
This exact false positive has already been escalated once as a live bug. Decide
it with a parser:

```bash
python3 - "$f" <<'PY'
import sys
from html.parser import HTMLParser
class T(HTMLParser):
    def __init__(s):
        super().__init__(convert_charrefs=True); s.t=None; s.i=False
    def handle_starttag(s,tag,a):
        s.i = (tag=='title')
    def handle_endtag(s,tag):
        if tag=='title': s.i=False
    def handle_data(s,d):
        if s.i and s.t is None: s.t=d
p=T(); p.feed(open(sys.argv[1],encoding='utf-8').read())
print(repr(p.t))
PY
```

A real title defect is one that survives decoding — the parsed string still
containing `&mdash;`, or an empty or duplicated title. Source-level entity style
is a consistency preference, worth normalising in the template but not a release
blocker, and not a bug to file.

**Structured data — HAND-MAINTAINED per page type.** Present where the page
warrants it, and parsing:

```bash
python3 - "$f" <<'PY'
import sys,re,json
h=open(sys.argv[1],encoding='utf-8').read()
for b in re.findall(r'<script[^>]*ld\+json[^>]*>(.*?)</script>',h,re.S):
    try: print(json.loads(b).get('@type','?'))
    except Exception as e: print('INVALID',e)
PY
```

Valid JSON is the low bar; the `@type` must also match what the page is. A
comparison page is not a `SoftwareApplication`. Absence is a legitimate state —
the four `productizer-vs-*` pages currently carry none, while `productizer.html`
(`SoftwareApplication`), `productizer-features.html` (`ItemList`) and
`productizer-comparison.html` (`BreadcrumbList` + `ItemList`) do — but it should
be a decision rather than an accident. This is the one real gap on those four
pages, and unlike the entity style above it is not a false positive.

**An empty grep is not a confirmed absence.** Every check above returns zero both
when the thing is missing and when the pattern, the path or the glob is wrong.
Positive-control each one against a product already on the site before believing
a zero:

```bash
grep -ci productizer llms.txt llms-full.txt   # must be non-zero; if it is not, the command is broken
```

The same trap applies to the HTTP check. glick.run serves a **soft 404** — an
unknown path returns `200` with the homepage body — so a status code proves
nothing on its own. Assert the page's own title:

```bash
curl -s "https://glick.run/${SLUG}.html" | sed -n 's:.*<title>\(.*\)</title>.*:\1:p'
```

A page that returns `200` while serving the homepage title does not exist.
