#!/usr/bin/env bash
# build-plan-page.sh PLAN [--root DIR] [--out FILE] [--stylesheet PATH|none]
# build-plan-page.sh --selftest | --version | --help
#
# Turns one change's plan (templates/plan.md) into ONE self-contained HTML
# page a person reads instead of the text: every section, each passage with a
# comment button, each open question as a button per option plus an answer of
# their own, and a "Copy answers" action that hands back a fenced block the
# agent validates with plan-answers.py. references/plan-page.md is the whole
# design; what matters here:
#
# THE PAGE IS NOT A VIEW AND HOLDS NOTHING. It is built from plan.md every
# time, it requests no capability, it loads nothing and sends nothing, and it
# writes no file: what the person decides leaves it only as text they copy,
# or as a file their own browser saves when the page is opened from disk.
# plan.md stays the source of truth and the only edit surface (P3).
#
# THE PLAN IS UNTRUSTED INPUT. Every byte of its text is HTML-escaped into
# element text or a quoted attribute, and the capability object's name is
# written `&#99;laude`, as build-view.sh writes it (R121), so a plan quoting
# a capability request is not one. The page's only script is the template's,
# byte for byte; no plan text is ever written into it. check-plan-page.py
# holds both on built pages.
#
# THE PROJECT'S OWN LOOK. `plan_page.stylesheet` in config.json names a CSS
# file in the repository; plan-theme.py takes custom properties of a colour
# or font shape from its `:root` and nothing else. No configuration, a file
# that cannot be read, one outside the repository or one that sets nothing
# usable gives the built-in theme, and the page says which - never an error.
#
# PLAN is read under --root (default: the git top level, else the working
# directory) when relative, and must be a file named plan.md inside it, not
# reached through a symbolic link. --out defaults to a file in $TMPDIR named
# for the plan's directory, never a path in the repository. The page is written
# to a private file renamed into place, so a link at --out is replaced, never
# written through.
#
# EXIT CODES ARE THE CONTRACT
#   0  the page was written, or every self-test case held
#   1  the plan's open questions do not follow the fixed syntax, and nothing
#      was written; under --selftest, a case that did not hold
#   2  bad usage, a PLAN that is not a readable plan.md inside the root, or a
#      missing template
set -euo pipefail

VERSION="build-plan-page 1.0"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$HERE")"
TEMPLATE="$SKILL/templates/plan-page.html"
SELF="$HERE/build-plan-page.sh"

PLAN=""; ROOT=""; OUT=""; STYLESHEET=""; MODE=build
usage() { echo "usage: build-plan-page.sh PLAN [--root DIR] [--out FILE] [--stylesheet PATH|none] | --selftest | --version" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --version) echo "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --selftest|--self-test) MODE=selftest; shift ;;
    --root) [ $# -ge 2 ] || { echo "build-plan-page: --root needs a directory" >&2; usage; }; ROOT="$2"; shift 2 ;;
    --out) [ $# -ge 2 ] || { echo "build-plan-page: --out needs a file" >&2; usage; }; OUT="$2"; shift 2 ;;
    --stylesheet) [ $# -ge 2 ] || { echo "build-plan-page: --stylesheet needs a path or none" >&2; usage; }; STYLESHEET="$2"; shift 2 ;;
    -*) echo "build-plan-page: unknown option: $1" >&2; usage ;;
    *) [ -z "$PLAN" ] || { echo "build-plan-page: one plan at a time" >&2; usage; }; PLAN="$1"; shift ;;
  esac
done
[ -f "$TEMPLATE" ] || { echo "build-plan-page: missing template: $TEMPLATE" >&2; exit 2; }

# --- --selftest ------------------------------------------------------------
# One case per exit code, each driven as a subprocess of this file and each
# naming the code it expects and a sentence the run must print. Page bytes are
# then read back for what the page must hold. What the page must NOT hold - a
# capability request, a network reference, plan text as markup - is
# check-plan-page.py's, over pages this script builds.
if [ "$MODE" = selftest ]; then
  T="$(mktemp -d "${TMPDIR:-/tmp}/build-plan-page-selftest.XXXXXX")"
  trap 'rm -rf "$T"' EXIT
  DRIVEN=0; FAILED=0; CODES=""
  drive() {
    _name="$1"; _want="$2"; _need="$3"; shift 3
    set +e; _out="$(bash "$SELF" "$@" 2>&1)"; _rc=$?; set -e
    DRIVEN=$((DRIVEN + 1)); CODES="$CODES$_rc
"
    if [ "$_rc" -ne "$_want" ] || ! grep -qF -- "$_need" <<<"$_out"; then
      printf '  FAIL %-28s wanted exit %s saying %s; got %s:\n' "$_name" "$_want" "$_need" "$_rc"
      printf '%s\n' "$_out" | tail -5 | sed 's/^/         /'
      FAILED=$((FAILED + 1)); return 0
    fi
    printf '  ok   %-28s exit %s, and it said: %s\n' "$_name" "$_rc" "$_need"
  }
  # page NAME FILE NEEDLE... : every needle is in the built page's bytes
  page() {
    _name="$1"; _file="$2"; shift 2
    DRIVEN=$((DRIVEN + 1))
    for _n in "$@"; do
      if ! grep -qF -- "$_n" "$_file"; then
        printf '  FAIL %-28s the page holds no %s\n' "$_name" "$_n"; FAILED=$((FAILED + 1)); return 0
      fi
    done
    printf '  ok   %-28s the page holds all %d expected strings\n' "$_name" "$#"
  }
  # nopage NAME FILE NEEDLE... : no needle is in the built page's bytes
  nopage() {
    _name="$1"; _file="$2"; shift 2
    DRIVEN=$((DRIVEN + 1))
    for _n in "$@"; do
      if grep -qF -- "$_n" "$_file"; then
        printf '  FAIL %-28s the page holds %s\n' "$_name" "$_n"; FAILED=$((FAILED + 1)); return 0
      fi
    done
    printf '  ok   %-28s the page holds none of %d strings\n' "$_name" "$#"
  }
  R="$T/repo"; P="docs/sdlc/B7"
  mkdir -p "$R/$P" "$R/.claude/productizer" "$R/styles"
  cat >"$R/$P/plan.md" <<'MD'
# Implementation plan: a bounded retry queue

Open questions
- Q1: How many retries before a job is dead-lettered?
  - A: three, then dead-letter
  - B: five, with backoff
- Q2: Where does the dead-letter list live?
  - A: a table beside the queue
  - B: a file per day
  - C: the existing errors table

Decisions
- <answered open questions land here, written by plan-answers.py --apply>

Files that change
- src/queue.py — a bounded retry queue (`MAX_RETRIES`)

Order of work
1. Write the failing test.
2. Make it pass.

Risks
- A permanent error retried forever.

Proof
- tests/test_queue.py::test_stops_after_five; `make test`

Revert
- git revert the merge commit; the queue table is dropped by migration 0042's down step.
MD
  PLANSHA="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$R/$P/plan.md")"
  printf '{"plan_page": {"stylesheet": null}}\n' >"$R/.claude/productizer/config.json"

  printf 'build-plan-page --selftest\n'
  drive built                 0 'wrote'                    "$P/plan.md" --root "$R" --out "$T/a.html"
  page  every-section         "$T/a.html" '>Open questions</h2>' '>Decisions</h2>' '>Files that change</h2>' \
        '>Order of work</h2>' '>Risks</h2>' '>Proof</h2>' '>Revert</h2>' 'Make it pass.' 'migration 0042'
  page  every-question        "$T/a.html" 'data-q="Q1"' 'data-q="Q2"' 'data-key="A"' 'data-key="C"' \
        'data-key="other"' 'five, with backoff' 'the existing errors table'
  page  answers-header        "$T/a.html" "data-plan=\"$P/plan.md\"" "data-sha=\"$PLANSHA\"" \
        "'format: 1'" "'plan: '" "'plan-sha256: '" 'productizer-plan-answers'
  page  passage-anchors       "$T/a.html" 'data-anchor="risks/1"' 'data-anchor="order-of-work/2"' \
        'data-anchor="files-that-change/1"'
  page  builtin-no-config     "$T/a.html" 'Theme: built-in' 'names no stylesheet'
  bash "$SELF" "$P/plan.md" --root "$R" --out "$T/a2.html" >/dev/null
  DRIVEN=$((DRIVEN + 1))
  if cmp -s "$T/a.html" "$T/a2.html"; then printf '  ok   %-28s two builds are byte-identical\n' deterministic
  else printf '  FAIL %-28s two builds of one plan differ\n' deterministic; FAILED=$((FAILED + 1)); fi
  printf 'victim\n' >"$T/victim.txt"; ln -s "$T/victim.txt" "$T/linked-out.html"
  bash "$SELF" "$P/plan.md" --root "$R" --out "$T/linked-out.html" >/dev/null
  DRIVEN=$((DRIVEN + 1))
  if [ "$(cat "$T/victim.txt")" = victim ] && [ ! -L "$T/linked-out.html" ] && cmp -s "$T/a.html" "$T/linked-out.html"
  then printf '  ok   %-28s a link at --out is replaced, its target untouched\n' out-link-not-followed
  else printf '  FAIL %-28s a link at --out was written through\n' out-link-not-followed; FAILED=$((FAILED + 1)); fi

  cat >"$R/styles/tokens.css" <<'CSS'
/* --accent: #ff0000; a comment is not read */
:root {
  --gray-9: #102030;
  --background: #fdfcf8;
  --foreground: var(--gray-9);
  --accent: #0a7d55;
  --font-sans: "Inter Tight", Helvetica, sans-serif;
  --font-mono: "JetBrains Mono", monospace;
  --border: url(https://example.invalid/x.png);
}
@media (prefers-color-scheme: dark) {
  :root { --background: #0c0d10; --accent: oklch(70% 0.15 160); }
}
.card { --accent: #999999; }
CSS
  printf '{"plan_page": {"stylesheet": "styles/tokens.css"}}\n' >"$R/.claude/productizer/config.json"
  drive themed                0 'wrote'                    "$P/plan.md" --root "$R" --out "$T/b.html"
  page  theme-from-config     "$T/b.html" 'Theme: from' 'styles/tokens.css' '--pp-bg:#fdfcf8' \
        '--pp-accent:#0a7d55' '--pp-font:"Inter Tight", Helvetica, sans-serif' '--pp-mono:"JetBrains Mono", monospace'
  page  theme-var-resolved    "$T/b.html" '--pp-text:#102030'
  page  theme-dark            "$T/b.html" '--pp-bg:#0c0d10' '--pp-accent:oklch(70% 0.15 160)' \
        '@media (prefers-color-scheme: light)'
  nopage theme-unsafe-not-taken "$T/b.html" 'example.invalid' '#ff0000' '#999999'

  cat >"$R/styles/hostile.css" <<'CSS'
:root {
  --background: red</style><script>alert(1)</script>;
  --accent: url(https://example.invalid/a);
  --foreground: expression(alert(1));
  --border: #12345g;
  --font-sans: x\;y;
  --muted: "a\"b";
}
@import url("https://example.invalid/i.css");
CSS
  printf ':root { --background: #fff;}</style><script>alert(1)</script><style>:root{--accent: url(https://example.invalid/b)}\n' \
    >"$R/styles/breakout.css"
  drive hostile-css           0 'wrote'                    "$P/plan.md" --root "$R" --stylesheet styles/hostile.css --out "$T/c.html"
  page  hostile-css-builtin   "$T/c.html" 'Theme: built-in' 'sets no custom property'
  nopage hostile-css-dropped  "$T/c.html" 'example.invalid' 'alert(1)' 'expression(' '#12345g' '--pp-bg:red'
  drive breakout-css          0 'wrote'                    "$P/plan.md" --root "$R" --stylesheet styles/breakout.css --out "$T/c2.html"
  page  breakout-css-safe-kept "$T/c2.html" '--pp-bg:#fff'
  nopage breakout-css-dropped "$T/c2.html" 'example.invalid' 'alert(1)'
  drive missing-css           0 'wrote'                    "$P/plan.md" --root "$R" --stylesheet styles/none.css --out "$T/d.html"
  page  missing-css-builtin   "$T/d.html" 'Theme: built-in' 'could not be read'
  printf 'x' >"$T/outside.css"
  drive outside-css           0 'wrote'                    "$P/plan.md" --root "$R" --stylesheet ../outside.css --out "$T/e.html"
  page  outside-css-builtin   "$T/e.html" 'Theme: built-in' 'outside the repository'
  printf '{"plan_page": ' >"$R/.claude/productizer/config.json"
  drive bad-config            0 'wrote'                    "$P/plan.md" --root "$R" --out "$T/f.html"
  page  bad-config-builtin    "$T/f.html" 'Theme: built-in' 'config.json could not be read'
  printf '{"plan_page": {"stylesheet": "styles/tokens.css", "tokens": {"accent": "--gray-9"}}}\n' \
    >"$R/.claude/productizer/config.json"
  drive mapped                0 'wrote'                    "$P/plan.md" --root "$R" --out "$T/g.html"
  page  mapping-wins          "$T/g.html" '--pp-accent:#102030'

  mkdir -p "$R/docs/sdlc/one" "$R/docs/sdlc/skip" "$R/docs/sdlc/dup"
  printf 'Open questions\n- Q1: only one way?\n  - A: yes\n' >"$R/docs/sdlc/one/plan.md"
  printf 'Open questions\n- Q1: which?\n  - A: this\n  - C: that\n' >"$R/docs/sdlc/skip/plan.md"
  printf 'Open questions\n- Q1: which?\n  - A: this\n  - B: that\n\nDecisions\n- Q1: which?\n  Decided: A - this\n' \
    >"$R/docs/sdlc/dup/plan.md"
  drive one-option            1 'offers 1 option'          docs/sdlc/one/plan.md --root "$R" --out "$T/h.html"
  drive skipped-letter        1 'C came where B was due'   docs/sdlc/skip/plan.md --root "$R" --out "$T/h.html"
  drive open-and-decided      1 'both open and under Decisions' docs/sdlc/dup/plan.md --root "$R" --out "$T/h.html"
  DRIVEN=$((DRIVEN + 1))
  if [ -e "$T/h.html" ]; then printf '  FAIL %-28s a malformed plan wrote a page\n' malformed-writes-nothing; FAILED=$((FAILED + 1))
  else printf '  ok   %-28s a malformed plan wrote no page\n' malformed-writes-nothing; fi
  printf '# not a plan\n' >"$R/notes.md"
  mkdir -p "$R/docs/sdlc/lnk"; ln -s ../B7/plan.md "$R/docs/sdlc/lnk/plan.md"
  drive not-a-plan            2 'not a plan.md'            notes.md --root "$R" --out "$T/i.html"
  drive linked-plan           2 'symbolic link'            docs/sdlc/lnk/plan.md --root "$R" --out "$T/i.html"
  drive outside-plan          2 'outside the root'         ../outside.css --root "$R" --out "$T/i.html"
  drive no-such-plan          2 'cannot read'              docs/sdlc/none/plan.md --root "$R" --out "$T/i.html"
  drive no-plan               2 'usage'                    --root "$R"
  drive bad-option            2 'unknown option'           --no-such-option

  REACHED="$(sort -un <<<"$CODES" | grep -v '^$' | tr '\n' ' ' | sed 's/ $//')"
  MISSING=""
  for want in 0 1 2; do grep -qx "$want" <<<"$CODES" || MISSING="$MISSING $want"; done
  printf '  cases driven: %d. Cases that did not hold: %d\n' "$DRIVEN" "$FAILED"
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  printf '  NOT ASSERTED: the page in a browser - the buttons, the comments and the copy\n'
  printf '  are not run here; that a font named by the stylesheet is installed; and what\n'
  printf '  the page must not hold, which check-plan-page.py asserts over built pages.\n'
  printf 'build-plan-page selftest: %d of %d cases held\n' "$((DRIVEN - FAILED))" "$DRIVEN"
  [ "$FAILED" -eq 0 ] && [ -z "$MISSING" ] || exit 1
  exit 0
fi

[ -n "$PLAN" ] || usage
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>&1)" || ROOT="$(pwd)"
fi
[ -d "$ROOT" ] || { echo "build-plan-page: no such directory: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd -P)"
if [ -z "$OUT" ]; then
  OUT="${TMPDIR:-/tmp}/plan-page-$(basename "$(dirname "$PLAN")").html"
fi

PP_ROOT="$ROOT" PP_PLAN="$PLAN" PP_OUT="$OUT" PP_STYLESHEET="$STYLESHEET" PP_TEMPLATE="$TEMPLATE" \
PP_HERE="$HERE" python3 - <<'PY'
import importlib.util
import json
import os
import re
import sys
import tempfile

E = os.environ


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(E["PP_HERE"], name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


model, plantheme = load("plan-model"), load("plan-theme")
root = E["PP_ROOT"]


def die(msg, rc=2):
    sys.stderr.write("build-plan-page: %s\n" % msg)
    sys.exit(rc)


def inside(path):
    real = os.path.realpath(path)
    return real == root or real.startswith(root + os.sep)


plan_arg = E["PP_PLAN"]
plan_path = plan_arg if os.path.isabs(plan_arg) else os.path.join(root, plan_arg)
if not inside(os.path.dirname(os.path.abspath(plan_path))) or not inside(plan_path):
    die("%s is outside the root" % plan_arg)
if os.path.islink(plan_path):
    die("%s is a symbolic link; a plan page is built from the plan file itself" % plan_arg)
rel = os.path.relpath(os.path.abspath(plan_path), root)
if os.path.basename(rel) != "plan.md" or re.search(r"[\x00-\x1f\x7f]", rel):
    die("%s is not a plan.md inside the repository" % plan_arg)
try:
    with open(plan_path, "rb") as fh:
        data = fh.read()
    text = data.decode("utf-8")
except (OSError, UnicodeDecodeError) as exc:
    die("cannot read %s: %s" % (rel, exc.__class__.__name__))
try:
    plan = model.parse(text.replace("\r\n", "\n"))
except model.Malformed as exc:
    die("%s: the open questions do not follow the fixed syntax: %s; nothing written" % (rel, exc), 1)

CAP_NAME = re.compile(r"(?<![A-Za-z0-9_$])claude(?![A-Za-z0-9_$])")


def esc(t):
    t = str(t).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return CAP_NAME.sub("&#99;laude", t.replace('"', "&quot;").replace("'", "&#39;"))


def inline(t):
    out = []
    for n, part in enumerate(re.split(r"`([^`]+)`", " ".join(t.split()))):
        if n % 2:
            out.append("<code>%s</code>" % esc(part))
            continue
        for m, bit in enumerate(re.split(r"\*\*([^*]+)\*\*", part)):
            out.append("<strong>%s</strong>" % esc(bit) if m % 2 else esc(bit))
    return "".join(out)


# --- the theme: never an error, always named on the page -------------------
def theme():
    sheet, mapping = E["PP_STYLESHEET"], {}
    if sheet == "none":
        return "", "built-in, because --stylesheet none was given"
    if not sheet:
        try:
            with open(os.path.join(root, ".claude/productizer/config.json"), "rb") as fh:
                cfg = json.loads(fh.read().decode("utf-8"))
            pp = cfg.get("plan_page") if isinstance(cfg, dict) else None
            pp = pp if isinstance(pp, dict) else {}
        except FileNotFoundError:
            return "", "built-in, because there is no .claude/productizer/config.json"
        except (OSError, ValueError):
            return "", "built-in, because config.json could not be read"
        sheet = pp.get("stylesheet")
        if isinstance(pp.get("tokens"), dict):
            mapping = dict((k, v) for k, v in pp["tokens"].items()
                           if k in plantheme.TOKENS and isinstance(v, str) and plantheme.NAME_RE.match(v))
        if not isinstance(sheet, str) or not sheet:
            return "", "built-in, because config.json names no stylesheet under plan_page"
    path = sheet if os.path.isabs(sheet) else os.path.join(root, sheet)
    if not inside(path):
        return "", "built-in, because %s is outside the repository" % sheet
    try:
        if os.path.getsize(path) > 512 * 1024:
            return "", "built-in, because %s is over 512 KB" % sheet
        with open(path, "rb") as fh:
            css = fh.read().decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return "", "built-in, because %s could not be read (%s)" % (sheet, exc.__class__.__name__)
    light, dark, note = plantheme.theme(css, mapping)
    if note is None:
        return "", ("built-in, because %s sets no custom property on :root of a colour or font shape "
                    "this page takes" % sheet)
    for v in list(light.values()) + list(dark.values()):
        assert not re.search(r"[<>;{}\\]", v), v

    def decl(d, keys):
        return ";".join("--pp-%s:%s" % (k, d[k]) for k in plantheme.TOKENS if k in d and k in keys)
    colours = [k for k in plantheme.TOKENS if k not in plantheme.FONTS]
    css_out = ""
    if decl(light, plantheme.FONTS):
        css_out += ":root{%s}\n" % decl(light, plantheme.FONTS)
    if decl(light, colours):
        css_out += "@media (prefers-color-scheme: light){:root{%s}}\n" % decl(light, colours)
    if dark:
        css_out += "@media (prefers-color-scheme: dark){:root{%s}}\n" % decl(dark, colours)
    return css_out, "from %s: %s" % (sheet, note)


theme_css, theme_note = theme()


# --- the body --------------------------------------------------------------
def passage(sec, b, n):
    ind = min(b["indent"] // 2, 4)
    cls = "passage" + (" ind%d" % ind if ind else "")
    if b["kind"] == "code":
        body = '<pre class="txt">%s</pre>' % esc(b["text"])
    elif b["kind"] == "li":
        body = '<span class="mk">%s</span><span class="txt">%s</span>' % (esc(b["marker"]), inline(b["text"]))
    else:
        body = '<p class="txt">%s</p>' % inline(b["text"])
    return ('<div class="%s" data-anchor="%s" data-section="%s">%s'
            '<button type="button" class="cbtn" aria-label="Comment on %s, passage %d">Comment'
            '<span class="count"></span></button></div>'
            % (cls, esc(b["anchor"]), esc(sec["title"]), body, esc(sec["title"]), n))


def question(q):
    opts = "".join('<button type="button" class="opt" data-key="%s" aria-pressed="false">'
                   '<span class="key">%s</span><span>%s</span></button>'
                   % (esc(o["key"]), esc(o["key"]), inline(o["text"])) for o in q["options"])
    opts += ('<button type="button" class="opt" data-key="other" aria-pressed="false">'
             '<span class="key">Other</span><span>an answer of your own</span></button>')
    return ('<fieldset class="question" data-q="%s"><legend class="qhead"><span class="qid">%s</span>'
            '<span>%s</span></legend><div class="opts">%s</div>'
            '<div class="otherbox" hidden><label class="small">Your answer'
            '<textarea class="other"></textarea></label></div>'
            '<div class="notebox"><label class="small">A note on your choice (optional)'
            '<input type="text" class="note"></label></div></fieldset>'
            % (esc(q["id"]), esc(q["id"]), inline(q["text"]), opts))


open_ids = dict((q["id"], q) for q in plan["questions"])
parts = []
for sec in plan["sections"]:
    parts.append('<section aria-labelledby="h-%s"><h2 id="h-%s">%s</h2>' % (sec["slug"], sec["slug"], esc(sec["title"])))
    shown = 0
    for n, b in enumerate(sec["blocks"], 1):
        if b.get("question") in open_ids:
            parts.append(question(open_ids[b["question"]]))
        elif b.get("option") and b["option"][0] in open_ids:
            continue
        else:
            parts.append(passage(sec, b, n))
        shown += 1
    if not shown:
        parts.append('<p class="empty">This section is empty.</p>')
    parts.append("</section>")

title = plan["title"] or "Plan %s" % rel
nq = len(plan["questions"])
how = ("This page saves nothing and sends nothing. %s Comment on any passage with its Comment button, or select "
       "words inside one passage to quote them. Then copy your answers and paste them to the agent, which "
       "checks them against this plan and writes the decisions into plan.md. Closing the page loses what "
       "you entered." % ("Answer the %d open question%s with the buttons, or give an answer of your own."
                         % (nq, "" if nq == 1 else "s") if nq else "This plan has no open question."))
body = (
    '<main id="plan" data-plan="%s" data-sha="%s">\n<header><h1>%s</h1>'
    '<p class="meta">Plan <span class="mono">%s</span> &middot; sha256 <span class="mono">%s</span></p>'
    '<p class="meta">Theme: %s</p></header>\n<div class="how">%s</div>\n%s\n'
    '<section id="answers" aria-labelledby="h-answers"><h2 id="h-answers">Your answers</h2>'
    '<h3>Comments</h3><ul id="clist" class="clist"></ul>'
    '<div class="row"><button type="button" class="btn primary copy">Copy answers</button>'
    '<a id="save" class="btn" download="plan-answers.md" hidden>Save as a file</a></div>'
    '<p id="status" role="status"></p>'
    '<label class="small" for="out">The answers block. If copying is blocked, select this text and copy it.</label>'
    '<textarea id="out" readonly></textarea></section>\n</main>\n'
    '<div id="bar"><span id="tally"></span><button type="button" class="btn primary copy">Copy answers</button>'
    '<a class="btn" href="#answers">Review answers</a></div>\n'
    '<button type="button" id="selbtn" class="btn" hidden></button>'
    % (esc(rel), model.sha256(data), esc(title), esc(rel), model.sha256(data)[:12], esc(theme_note), esc(how),
       "\n".join(parts)))

with open(E["PP_TEMPLATE"], encoding="utf-8") as fh:
    template = fh.read()
subs = {"TITLE": esc(title), "THEME": theme_css, "BODY": body}
page = re.sub(r"@@(TITLE|THEME|BODY)@@", lambda m: subs[m.group(1)], template)
out = E["PP_OUT"]
# A private file renamed into place: a symbolic link already at OUT is replaced, never written through.
fd, tmp = tempfile.mkstemp(prefix=".plan-page.", dir=os.path.dirname(os.path.abspath(out)))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(page)
    os.replace(tmp, out)
except OSError as e:
    if os.path.exists(tmp):
        os.unlink(tmp)
    die("cannot write %s: %s" % (out, e.strerror or e))
print("build-plan-page: wrote %s from %s (%d section(s), %d open question(s); theme %s)"
      % (out, rel, len(plan["sections"]), nq, theme_note))
PY
