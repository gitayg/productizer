"""The reading of a change's plan that build-plan-page.sh and plan-answers.py
both load by path, so the page and the validator can never disagree about
which sections, passages and open questions a plan holds. No command line.

A PLAN (templates/plan.md) is read line by line:

  title      the first line, when it is a `# ` heading
  section    a markdown heading (`#` to `######`), or a line holding only the
             name of a section the template names, with or without `#`s.
             Lines before the first section form a `preamble` section.
  passage    one block inside a section: a paragraph, a list item with the
             lines under it, or a fenced block. Each has an ANCHOR,
             `<section slug>/<n>`, n counting the section's passages from 1.
             A comment on the page names one anchor, and the validator
             resolves it here.

OPEN QUESTIONS, the fixed syntax, inside the `Open questions` section:

  - Q1: the question, on one line or continued on indented lines under it
    - A: one option
    - B: another option

A question is a list item at the left margin reading `Q<n>: <text>`; its
options are the indented list items under it reading `<letter>: <text>`,
lettered from A with none skipped, two at least. Every question also takes
an answer of the person's own (`other`). A question whose text is only a
template placeholder (`<...>`) is not open: it is shown as text and nothing
answers it. Anything else in the section that is a list item is malformed,
and so is a question id used twice or already under `Decisions`.

AN ANSWERS BLOCK, the text the page hands back:

  ```productizer-plan-answers
  format: 1
  plan: docs/sdlc/B7/plan.md
  plan-sha256: <64 lowercase hex>
  decide Q1 B
  decide Q2 other "an answer of the person's own"
  decide Q3 A "a note on the choice"
  comment risks/1 "the quoted passage text" "the note"
  ```

Every free-text value is a JSON string on its item's line, so a note can
hold any character - a newline, a backquote fence - and still never end the
block or start a line of its own.
"""
import hashlib
import json
import re

SECTION_NAMES = ("Open questions", "Decisions", "Files that change", "Order of work",
                 "Risks", "Proof", "Revert")
FORMAT = "1"
FENCE_OPEN = "```productizer-plan-answers"
FENCE_CLOSE = "```"

HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
ITEM_RE = re.compile(r"^( *)([-*]|\d+\.)\s+(.*)$")
FENCE_RE = re.compile(r"^\s*(```+|~~~+)")
QUESTION_RE = re.compile(r"^(Q[1-9][0-9]{0,3}):\s*(.*)$", re.S)
OPTION_RE = re.compile(r"^([A-Z]):\s*(.+)$", re.S)
PLACEHOLDER_RE = re.compile(r"<[^<>]*>")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
CODE_RE = re.compile(r"`([^`]+)`")
BOLD_RE = re.compile(r"\*\*([^*]+)\*\*")


class Malformed(Exception):
    pass


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def slugify(title, taken):
    base = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-") or "section"
    slug, n = base, 1
    while slug in taken:
        n += 1
        slug = "%s-%d" % (base, n)
    taken.add(slug)
    return slug


def section_title(line):
    m = HEADING_RE.match(line)
    if m:
        return m.group(2)
    bare = line.strip().lstrip("#").strip()
    for name in SECTION_NAMES:
        if bare.lower() == name.lower():
            return name
    return None


def plain(text):
    """The text a passage shows: code spans and bold without their marks,
    whitespace collapsed. A quoted comment is matched against this."""
    return " ".join(BOLD_RE.sub(r"\1", CODE_RE.sub(r"\1", text)).split())


def blocks_of(lines):
    out, para, fence = [], None, None
    for line in lines:
        if fence is not None:
            if line.strip().startswith(fence) and not line.strip().strip("`~"):
                fence = None
            else:
                out[-1]["lines"].append(line)
            continue
        m = FENCE_RE.match(line)
        if m:
            fence, para = m.group(1), None
            out.append({"kind": "code", "indent": 0, "lines": [], "info": line.strip()[len(m.group(1)):].strip()})
            continue
        if not line.strip():
            para = None
            continue
        item = ITEM_RE.match(line)
        if item:
            para = {"kind": "li", "indent": len(item.group(1)), "marker": item.group(2), "lines": [item.group(3)]}
            out.append(para)
        elif para is not None and (para["kind"] == "p" or line.startswith(" ")):
            para["lines"].append(line.strip())
        else:
            para = {"kind": "p", "indent": 0, "lines": [line.strip()]}
            out.append(para)
    for b in out:
        b["text"] = "\n".join(b["lines"])
        b["plain"] = b["text"] if b["kind"] == "code" else plain(b["text"])
    return out


def parse(text):
    """The plan as {title, sections, questions, decided}. Raises Malformed
    when the open questions do not follow the fixed syntax."""
    lines = text.split("\n")
    title = None
    if lines and HEADING_RE.match(lines[0]) and HEADING_RE.match(lines[0]).group(1) == "#":
        title = HEADING_RE.match(lines[0]).group(2)
        lines = lines[1:]
    raw, cur = [], {"title": "Before the first section", "lines": [], "preamble": True}
    for line in lines:
        name = section_title(line)
        if name is not None:
            raw.append(cur)
            cur = {"title": name, "lines": [], "preamble": False}
        else:
            cur["lines"].append(line)
    raw.append(cur)
    taken, sections = set(), []
    for s in raw:
        if s["preamble"] and not any(line.strip() for line in s["lines"]):
            continue
        slug = slugify("preamble" if s["preamble"] else s["title"], taken)
        blocks = blocks_of(s["lines"])
        for n, b in enumerate(blocks, 1):
            b["anchor"] = "%s/%d" % (slug, n)
        sections.append({"title": s["title"], "slug": slug, "blocks": blocks})
    decided = []
    for s in sections:
        if s["title"].lower() == "decisions":
            for b in s["blocks"]:
                m = QUESTION_RE.match(b["text"]) if b["kind"] == "li" and b["indent"] == 0 else None
                if m:
                    decided.append(m.group(1))
    questions = []
    for s in sections:
        if s["title"].lower() == "open questions":
            questions.extend(questions_of(s["blocks"]))
    seen = set()
    for q in questions:
        if q["id"] in seen:
            raise Malformed("%s is asked twice under Open questions" % q["id"])
        if q["id"] in decided:
            raise Malformed("%s is both open and under Decisions" % q["id"])
        seen.add(q["id"])
    return {"title": title, "sections": sections, "decided": decided,
            "questions": [q for q in questions if not q["placeholder"]]}


def placeholder_only(text):
    return not PLACEHOLDER_RE.sub("", text).strip(" \n-—")


def questions_of(blocks):
    out, q = [], None
    for b in blocks:
        if b["kind"] != "li":
            if b["kind"] == "code" and q is not None:
                raise Malformed("a fenced block sits inside %s" % q["id"])
            q = None
            continue
        if b["indent"] == 0:
            m = QUESTION_RE.match(b["text"])
            if not m:
                raise Malformed("an item under Open questions is not `- Q<n>: <question>`: %s" % b["text"][:60])
            q = {"id": m.group(1), "text": m.group(2).strip(), "anchor": b["anchor"], "options": [],
                 "placeholder": placeholder_only(m.group(2))}
            b["question"] = q["id"]
            out.append(q)
            continue
        m = OPTION_RE.match(b["text"])
        if q is None or not m:
            raise Malformed("an indented item under Open questions is not an option `- <letter>: <text>` "
                            "under a question: %s" % b["text"][:60])
        want = chr(ord("A") + len(q["options"]))
        if m.group(1) != want:
            raise Malformed("%s's options are lettered from A with none skipped; %s came where %s was due"
                            % (q["id"], m.group(1), want))
        q["options"].append({"key": m.group(1), "text": m.group(2).strip()})
        b["option"] = (q["id"], m.group(1))
    for q in out:
        if not q["placeholder"] and len(q["options"]) < 2:
            raise Malformed("%s offers %d option(s); a question offers two at least" % (q["id"], len(q["options"])))
    return out


def passages(model):
    return dict((b["anchor"], (s, b)) for s in model["sections"] for b in s["blocks"])


def answers_block(text):
    """The one answers block in TEXT as (header, items); raises Malformed.
    Text around the block is ignored, so a person can paste it with a note."""
    lines = text.replace("\r\n", "\n").split("\n")
    starts = [i for i, line in enumerate(lines) if line.strip() == FENCE_OPEN]
    if not starts:
        raise Malformed("no answers block: no line reading %s" % FENCE_OPEN)
    if len(starts) > 1:
        raise Malformed("%d answers blocks; hand over one at a time" % len(starts))
    body = []
    for line in lines[starts[0] + 1:]:
        if line.strip() == FENCE_CLOSE:
            break
        body.append(line)
    else:
        raise Malformed("the answers block is never closed by a line reading %s" % FENCE_CLOSE)
    body = [line.strip() for line in body if line.strip()]
    header = {}
    for key in ("format", "plan", "plan-sha256"):
        if not body or not body[0].startswith(key + ": "):
            raise Malformed("the block's header is `format: 1`, `plan: <path>`, `plan-sha256: <hex>`, "
                            "in that order; `%s:` is not where it belongs" % key)
        header[key] = body.pop(0)[len(key) + 2:].strip()
    if header["format"] != FORMAT:
        raise Malformed("format %s is not one this validator reads (it reads %s)" % (header["format"], FORMAT))
    if not SHA_RE.match(header["plan-sha256"]):
        raise Malformed("plan-sha256 is not 64 lowercase hex digits")
    items = [item(line) for line in body]
    return header, items


def strings(rest):
    out, dec, i = [], json.JSONDecoder(), 0
    while i < len(rest):
        if rest[i] != '"':
            raise ValueError
        value, i = dec.raw_decode(rest, i)
        out.append(value)
        if i < len(rest):
            if rest[i] != " ":
                raise ValueError
            i += 1
    return out


def item(line):
    m = re.match(r"^(decide) (Q[1-9][0-9]{0,3}) (other|[A-Z])(?: (.*))?$", line)
    tail = 4
    if not m:
        m, tail = re.match(r"^(comment) ([a-z0-9-]+/[1-9][0-9]*)(?: (.*))?$", line), 3
    if not m:
        raise Malformed("a line in the block is neither `decide Q<n> <option>` nor `comment <anchor> ...`: %s"
                        % line[:60])
    try:
        rest = strings(m.group(tail)) if m.group(tail) else []
    except ValueError:
        raise Malformed("the text on this line is not quoted JSON strings: %s" % line[:60])
    if m.group(1) == "decide":
        if len(rest) > 1 or (m.group(3) == "other" and not (rest and rest[0].strip())):
            raise Malformed("%s: an `other` answer carries its text, and a decision at most one note" % m.group(2))
        return {"kind": "decide", "id": m.group(2), "option": m.group(3), "text": rest[0] if rest else ""}
    if len(rest) != 2 or not rest[1].strip():
        raise Malformed("comment on %s: a comment carries a quote (\"\" for the whole passage) and a note"
                        % m.group(2))
    return {"kind": "comment", "anchor": m.group(2), "quote": rest[0], "note": rest[1]}
