"""The plan page's colours and fonts, read out of a project's own stylesheet.
Loaded by path by build-plan-page.sh; no command line.

ONLY CUSTOM PROPERTIES, AND ONLY VALUES OF A SAFE SHAPE. The stylesheet is a
file in the repository being planned, so it is data, never markup: nothing
from it is copied into the page except a value this module has matched
against a shape that cannot load anything or end the style element.

  read     `--name: value` declarations in a rule whose selector is `:root`
           or `html` (light), and in `:root` inside `@media
           (prefers-color-scheme: dark)` or a rule on `[data-theme="dark"]`,
           `:root[data-theme="dark"]`, `.dark`, `:root.dark` or `html.dark`
           (dark). A selector list counts when one of its parts is one of
           these. Comments are removed first. Nothing else in the file is read.
  resolve  `var(--other)` and `var(--other, fallback)`, against the same
           mode and then the light set, at most eight deep
  accept   a colour: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, a word of
           letters, or rgb() rgba() hsl() hsla() hwb() lab() lch() oklab()
           oklch() holding only digits, `.`, `%`, `+`, `-`, `,`, `/`, spaces
           and the words deg, rad, grad, turn and none; a font: a list of
           family names, each letters, digits, spaces, `_`, `.` and `-`,
           quoted or bare. Anything else - `url(`, `@import`, `;`, `{`, `<`,
           a backslash - is not a colour or a font, and is not taken.
  map      each page token from the property the configuration names for it,
           else from the first of its documented names the stylesheet sets

A token the stylesheet does not give keeps the built-in value for that mode,
and a stylesheet that gives no dark colour leaves the dark page wholly
built-in. A font is named, never loaded: it shows where it is installed.
"""
import re

TOKENS = ("bg", "surface", "text", "muted", "border", "accent", "accent-text", "font", "mono")
FONTS = ("font", "mono")
CANDIDATES = {
    "bg": ("--background", "--bg", "--color-bg", "--color-background"),
    "surface": ("--surface", "--card", "--color-surface", "--color-card"),
    "text": ("--foreground", "--text", "--fg", "--color-text", "--color-fg", "--color-foreground"),
    "muted": ("--muted-foreground", "--text-muted", "--muted", "--color-muted", "--color-text-muted"),
    "border": ("--border", "--color-border"),
    "accent": ("--accent", "--primary", "--color-accent", "--color-primary"),
    "accent-text": ("--accent-foreground", "--primary-foreground", "--on-accent", "--on-primary",
                    "--color-on-primary"),
    "font": ("--font-sans", "--font-body", "--font-family", "--font"),
    "mono": ("--font-mono", "--font-code", "--mono"),
}
LIGHT_SEL = (":root", "html")
DARK_SEL = ('[data-theme="dark"]', ':root[data-theme="dark"]', ".dark", ":root.dark", "html.dark")
NAME_RE = re.compile(r"^--[A-Za-z0-9_-]{1,64}$")
HEX_RE = re.compile(r"^#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")
WORD_RE = re.compile(r"^[a-zA-Z]{3,20}$")
FUNC_RE = re.compile(r"^(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch)\(((?:[0-9.%+\-\s,/]|deg|rad|grad|turn|none){1,80})\)$")
FAMILY_RE = re.compile(r"""^(?:"[A-Za-z0-9 _.-]{1,60}"|'[A-Za-z0-9 _.-]{1,60}'|[A-Za-z][A-Za-z0-9_.-]{0,40}(?: [A-Za-z0-9_.-]{1,40}){0,4})$""")
VAR_RE = re.compile(r"^var\(\s*(--[A-Za-z0-9_-]{1,64})\s*(?:,\s*(.*))?\)$")


def colour(v):
    return bool(HEX_RE.match(v) or WORD_RE.match(v) or FUNC_RE.match(v))


def font(v):
    parts = [p.strip() for p in v.split(",")]
    return 0 < len(parts) <= 8 and all(FAMILY_RE.match(p) for p in parts)


def rules(css, dark=False):
    """(selector, body, dark) for every rule at this level, descending into
    a prefers-color-scheme: dark media block. Unbalanced braces end it."""
    out, i, n = [], 0, len(css)
    while i < n:
        j = css.find("{", i)
        if j < 0:
            break
        sel, depth, k = css[i:j].strip(), 1, j + 1
        while k < n and depth:
            depth += {"{": 1, "}": -1}.get(css[k], 0)
            k += 1
        if depth:
            break
        body = css[j + 1:k - 1]
        if sel.startswith("@media"):
            if re.search(r"prefers-color-scheme\s*:\s*dark", sel):
                out.extend(rules(body, True))
        elif not sel.startswith("@"):
            out.append((sel, body, dark))
        i = k
    return out


def declarations(body):
    out = {}
    if "{" in body:
        return out
    for decl in body.split(";"):
        name, sep, value = decl.partition(":")
        name, value = name.strip(), value.strip()
        if sep and NAME_RE.match(name):
            out[name] = re.sub(r"\s*!important$", "", value)
    return out


def resolve(value, mode, light, depth=0):
    m = VAR_RE.match(value)
    if not m:
        return value
    if depth >= 8:
        return None
    ref = mode.get(m.group(1), light.get(m.group(1)))
    if ref is None:
        return m.group(2).strip() if m.group(2) else None
    return resolve(ref, mode, light, depth + 1)


def theme(css, mapping=None):
    """(light, dark, note): page token -> value for each mode, and the
    sentence the page shows about where they came from."""
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    sets = {False: {}, True: {}}
    for sel, body, dark in rules(css):
        parts = [p.strip() for p in sel.split(",")]
        if dark and any(p in LIGHT_SEL for p in parts):
            sets[True].update(declarations(body))
        elif not dark and any(p in DARK_SEL for p in parts):
            sets[True].update(declarations(body))
        elif not dark and any(p in LIGHT_SEL for p in parts):
            sets[False].update(declarations(body))
    light_raw, dark_raw = sets[False], sets[True]
    mapping = mapping or {}
    picked = {}
    for mode_dark in (False, True):
        raw = dark_raw if mode_dark else light_raw
        got = {}
        for tok in TOKENS:
            if mode_dark and tok in FONTS:
                continue
            names = (mapping[tok],) if tok in mapping else CANDIDATES[tok]
            for name in names:
                if name in raw:
                    v = resolve(raw[name], raw, light_raw)
                    if v is not None and (font(v) if tok in FONTS else colour(v)):
                        got[tok] = v
                    break
        picked[mode_dark] = got
    light, dark = picked[False], picked[True]
    if not light and not dark:
        return {}, {}, None
    note = "%d of %d tokens in light" % (len(light), len(TOKENS))
    note += ", %d of %d colours in dark" % (len(dark), len(TOKENS) - len(FONTS)) if dark else \
        "; it sets no dark colour, so the dark page is the built-in one"
    return light, dark, note
