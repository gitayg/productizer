#!/usr/bin/env python3
"""Static checks on the b18-mech corpus, where the living spec lives on disk.

The b18-hard corpus (`evals/hard-cases/`) inlined the spec and constitution in
every prompt. In its 840 runs no model Read a single file, so the route the
plugin claims - find the living spec, classify against it, halt on a
contradiction - was never exercised. This corpus mirrors those 14 cases one for
one, and moves the two fixtures out of the prompt and into the run's working
directory through a scaffold script, so finding the spec is part of the task.

    evals/mech-cases/M01-<slug>/   prompt.md  case.yaml  scaffold.sh  graders/
    evals/mech-fixtures/           booking-spec.md  booking-constitution.md

What it asserts. Every assertion is broken on purpose in --selftest and must
come back red there, with the reason, before it is believed.

  corpus       exactly 14 case directories, M01..M14, each named for its H twin
  tags         every case anywhere under evals/ carrying b18-mech is one of
               these 14 (prompt.md frontmatter and case.yaml both scanned), and
               none of them carries b18-hard - so `--tag b18-mech` selects
               exactly this corpus
  layout       each case directory holds prompt.md, case.yaml, scaffold.sh and
               graders/, and nothing else
  frontmatter  prompt.md keys, name, tools, turns and the plugins path
  case.yaml    byte-identical to CASE_YAML: schema_version and
               context.scaffold_script only - no prompt, history, env or extra
               directory can reach the model through it
  scaffold     byte-identical to SCAFFOLD, the only text this corpus may run
  fixtures     exactly two files, each at its recorded sha256
  off-prompt   no run of SHINGLE consecutive words from either fixture appears
               in any prompt, and no prompt names the spec, its path or the
               plugin
  mirror       each M intent, tag list and outcome grader equals its H
               counterpart; grader 01 differs only in its weight paragraph,
               which must state the weights the case actually carries
  graders      the grader set per case type, and the mechanism graders
               byte-identical to their canonical text
  pairing      M(2k-1) and M(2k) hold exactly one must-halt case, and the
               positive/negative tag agrees with the grader

Usage:
    check-mech-corpus.py                check evals/ and print the fingerprint
    check-mech-corpus.py --root <dir>   check another evals directory
    check-mech-corpus.py --selftest

Exit: 0 clean · 1 the corpus breaks an assertion (or a self-test case failed)
      · 2 could not run: bad usage, or a directory it needs is missing
"""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

TAG = "b18-mech"
OLD_TAG = "b18-hard"
N_CASES = 14
# The off-prompt signal: a run of SHINGLE consecutive words, lower-cased with
# punctuation and markdown dropped, shared by a prompt and either fixture. Word
# runs rather than a substring test because a substring misses a requirement that
# was re-wrapped, re-cased or had its bold markers stripped on the way in, which
# is how text gets pasted. Measured when this was written: the longest run any
# legitimate prompt shares with the fixtures is 7 words (M04's intent, which is
# H04's verbatim), and the shortest requirement is 13. 10 clears the first by 3
# and still catches any whole requirement.
SHINGLE = 10

FIXTURES = {
    "booking-constitution.md": "17c74802a156d7cffc13855dc3572cc4e76e7c343d800bf85992d35bf227f60b",
    "booking-spec.md": "e2c787cfce231922b4505ff8a109666ead051c29d16ef4ff0cd2f7a1c11d6b86",
}

PROMPT_KEYS = ["name", "tags", "plugins", "runs", "max_turns", "timeout_seconds", "allowed_tools"]
PROMPT_VALUES = {
    "plugins": '["../../../plugins/productizer"]',
    "runs": "3",
    "max_turns": "20",
    "timeout_seconds": "600",
    "allowed_tools": "[Read, Glob, Grep, Skill]",
}
PLUGIN_REL = "../../../plugins/productizer"

# A prompt body may not hand the model the mechanism under test. The spec's path,
# the plugin's name and the nouns the plugin uses for the two files all stay out.
# The frontmatter is harness configuration the model never sees, and its
# `plugins:` line necessarily names the plugin, so it is exempt.
FORBIDDEN = [
    (r"\.claude", ".claude"),
    (r"productizer", "productizer"),
    (r"\bspec\b", "the word 'spec'"),
    (r"constitution", "constitution"),
    (r"fixture", "fixture"),
]

CASE_ENTRIES = ["case.yaml", "graders", "prompt.md", "scaffold.sh"]

CASE_YAML = """\
schema_version: "1.1"
context:
  scaffold_script: scaffold.sh
"""

SCAFFOLD = """\
#!/usr/bin/env bash
# Scaffold for one b18-mech eval case. It puts the living spec and the
# constitution where a repository using the plugin keeps them, under
# .claude/productizer/ in the working directory, and does nothing else: no
# network, no other command, no read outside evals/mech-fixtures/.
# evals/check-mech-corpus.py holds the only permitted text of this file and
# fails on any byte of difference.
#
# Each refusal has its own exit code, so one smoke run says where the harness
# ran it: 3 the fixtures are not beside this script, 4 the working directory is
# this case directory, 5 the working directory already holds a spec.
set -euo pipefail
here="${BASH_SOURCE[0]%/*}"
[ "$here" != "${BASH_SOURCE[0]}" ] || here=.
fixtures="$here/../../mech-fixtures"
if [ ! -r "$fixtures/booking-spec.md" ] || [ ! -r "$fixtures/booking-constitution.md" ]; then
  echo "scaffold: fixtures not readable under $fixtures" >&2
  exit 3
fi
if [ "$(cd "$here" && pwd -P)" = "$(pwd -P)" ]; then
  echo "scaffold: the working directory is the case directory; refusing to write into the corpus" >&2
  exit 4
fi
if [ -e .claude/productizer ]; then
  echo "scaffold: .claude/productizer already exists here; refusing to overwrite a spec" >&2
  exit 5
fi
mkdir -p .claude
mkdir .claude/productizer
cp "$fixtures/booking-spec.md" .claude/productizer/spec.md
cp "$fixtures/booking-constitution.md" .claude/productizer/constitution.md
"""

MECH_GRADERS = {
    "00-scaffold-present.md": """\
---
type: regex
pattern: 'Next requirement id\\s*\\n:\\s*`R43`'
match: contains
target: {source: file, path: .claude/productizer/spec.md}
arm: both
weight: 1
---

Run validity, not an outcome. Passes when the run's working directory holds the
living spec the scaffold copies in, read from disk after the run. A run where
this fails never had a spec to find, and says nothing about finding one: it is
excluded and counted, never scored as a pass or a fail of the halt decision.
`arm: both` because the bare arm needs the same proof.
""",
    "90-spec-read.md": """\
---
type: tool_used
tool: Read
input_match: '"file_path"\\s*:\\s*"[^"]*\\.claude/productizer/spec\\.md"'
min: 1
arm: both
weight: 1
---

The mechanism under test, read from the tool-call record: did the run Read the
living spec at `.claude/productizer/spec.md`. Nothing in the prompt names that
path. `arm: both` because the comparison IS the two arms' rates; a with-only
grader would drop the bare arm's figure. It is a pre-registered secondary
endpoint, not part of the halt decision.
""",
    "91-constitution-read.md": """\
---
type: tool_used
tool: Read
input_match: '"file_path"\\s*:\\s*"[^"]*\\.claude/productizer/constitution\\.md"'
min: 1
arm: both
weight: 1
---

Did the run Read the constitution at `.claude/productizer/constitution.md`.
Principles bind requirements nobody has written yet (M03), so a run that finds
the spec and never opens this file cannot see that conflict. `arm: both`, for
the same reason as `90`.
""",
    "92-rulings-read.md": """\
---
type: tool_used
tool: Read
input_match: 'references/rulings\\.md"'
min: 1
arm: with-only
weight: 1
---

Indicator, not a criterion. Did the plugin arm Read the plugin's
`references/rulings.md`, the only place the rules M07 and M08 lean on are
written. The bare arm has no such file, so its zero would be structural rather
than measured: `arm: with-only`, reported and not scored.
""",
    "93-ears-read.md": """\
---
type: tool_used
tool: Read
input_match: 'references/ears\\.md"'
min: 1
arm: with-only
weight: 1
---

Indicator, not a criterion. Did the plugin arm Read the plugin's
`references/ears.md`, where the interval rule (M11, M12) and match-on-trigger
(M01, M02) live. With-only for the same reason as `92`.
""",
}

HALT = "01-contradiction-detected"
TWIN = "01-no-false-halt"
HALT_OUTCOME = [HALT, "02-work-halted", "03-both-sides-cited", "04-no-silent-supersede",
                "05-conflict-stated", "06-ruling-requested", "99-skill-fired"]
TWIN_OUTCOME = [TWIN, "02-correct-class", "03-ids-cited", "04-reasoning-sound", "99-skill-fired"]

OLD_HALT_PARA = (
    "This is the recall criterion. It carries 10 of the 25 scored weight points in\n"
    "this case, and together with the halt criterion beside it 16 of 25 — 64 percent\n"
    "of the score, against the 43 percent the mirror-image criterion carries in a\n"
    "must-not-halt case.")
OLD_TWIN_PARA = (
    "This is the precision criterion. It carries 6 of the 14 scored weight points\n"
    "here — 43 percent of this case's score — against the 16 of 25 that detection and\n"
    "halting carry together in a must-halt case, which is 64 percent.")

H_INTENT = re.compile(r"\n## Arriving intent\n\n(.*?)\n\n## What to produce\n", re.S)
M_OPEN = "A new intent has arrived for the `booking service`:\n\n"
M_BODY_TAIL = """\
Classify this intent against what this product has already agreed, as exactly
one of **extend**, **refine**, **duplicate** or **contradict**. Cite every
requirement id (`R…`) and principle id (`P…`) that bears on the decision, state
what happens next, and say plainly what has and has not been merged.

End your reply with exactly this line, and nothing after it:

VERDICT: <EXTEND|REFINE|DUPLICATE|CONTRADICT>
"""


class CannotRun(Exception):
    pass


def read(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def sha256_file(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def split_frontmatter(text: str):
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---\n", 4)
    if end < 0:
        return None, text
    return text[4:end], text[end + 5:]


def top_keys(fm: str) -> dict:
    out = {}
    for line in fm.splitlines():
        m = re.match(r"^([A-Za-z_][\w-]*):(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2).strip()
    return out


def flow_list(value: str):
    m = re.fullmatch(r"\[(.*)\]", value.strip())
    if m is None:
        return None
    return [x.strip().strip('"').strip("'") for x in m.group(1).split(",") if x.strip()]


def tags_in(text: str) -> list:
    """Tags from a YAML-ish document: `tags: [a, b]` or a `tags:` block list."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        m = re.match(r"^tags:(.*)$", line)
        if not m:
            continue
        inline = m.group(1).strip()
        if inline:
            return flow_list(inline) or [inline.strip('"').strip("'")]
        out = []
        for nxt in lines[i + 1:]:
            b = re.match(r"^\s+-\s*(.+?)\s*$", nxt)
            if not b:
                break
            out.append(b.group(1).strip('"').strip("'"))
        return out
    return []


def grader_meta(text: str) -> dict:
    fm, _ = split_frontmatter(text)
    return top_keys(fm or "")


def with_only(meta: dict) -> bool:
    if meta.get("arm") == "with-only":
        return True
    return "arm" not in meta and meta.get("type") == "tool_used" and meta.get("tool") == "Skill"


def words(text: str) -> list:
    return re.findall(r"[a-z0-9]+", text.lower())


def shingles(text: str, k: int) -> set:
    w = words(text)
    return {" ".join(w[i:i + k]) for i in range(len(w) - k + 1)}


def pct(a: int, b: int) -> int:
    return int(a * 100 / b + 0.5)


def halt_para(w01, w02, halt_total, twin_w01, twin_total, mech):
    return (
        f"This is the recall criterion. It carries {w01} of the {halt_total} scored weight points in\n"
        f"this case, and together with the halt criterion beside it {w01 + w02} of {halt_total} — "
        f"{pct(w01 + w02, halt_total)} percent\n"
        f"of the score, against the {pct(twin_w01, twin_total)} percent the mirror-image criterion carries in a\n"
        f"must-not-halt case. {mech} of the {halt_total} check that the run had a spec and\n"
        f"read it, not how it classified (`00`, `90`, `91`).")


def twin_para(w01, twin_total, halt_w, halt_total, mech):
    return (
        f"This is the precision criterion. It carries {w01} of the {twin_total} scored weight points\n"
        f"here — {pct(w01, twin_total)} percent of this case's score — against the {halt_w} of {halt_total} "
        f"that detection and\n"
        f"halting carry together in a must-halt case, which is {pct(halt_w, halt_total)} percent. "
        f"{mech} of the {twin_total}\n"
        f"check that the run had a spec and read it, not how it classified (`00`, `90`, `91`).")


def case_dirs_anywhere(root: str) -> list:
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        if "prompt.md" in filenames or "case.yaml" in filenames:
            found.append(dirpath)
    return found


def tags_of_case(d: str) -> list:
    tags = []
    p = os.path.join(d, "prompt.md")
    if os.path.isfile(p):
        fm, _ = split_frontmatter(read(p))
        tags += tags_in(fm or "")
    y = os.path.join(d, "case.yaml")
    if os.path.isfile(y):
        tags += tags_in(read(y))
    return tags


def fingerprint(root: str) -> str:
    files = []
    for top in ("mech-cases", "mech-fixtures"):
        for dirpath, _, filenames in os.walk(os.path.join(root, top)):
            for f in filenames:
                files.append(os.path.relpath(os.path.join(dirpath, f), root))
    lines = "".join(f"{sha256_file(os.path.join(root, f))}  {f}\n"
                    for f in sorted(files, key=lambda s: s.encode()))
    return hashlib.sha256(lines.encode()).hexdigest()


def check(root: str):
    """Returns (problems, info). Raises CannotRun when a needed directory is missing."""
    cases_dir = os.path.join(root, "mech-cases")
    fix_dir = os.path.join(root, "mech-fixtures")
    hard_dir = os.path.join(root, "hard-cases")
    for d, why in ((root, "the evals directory"), (cases_dir, "the corpus"),
                   (fix_dir, "the fixtures"), (hard_dir, "the H cases the mirror check compares against")):
        if not os.path.isdir(d):
            raise CannotRun(f"{d} is missing ({why}); nothing was checked")

    problems = []
    info = {}

    # fixtures
    present = sorted(os.listdir(fix_dir))
    if present != sorted(FIXTURES):
        problems.append(f"mech-fixtures: expected exactly {sorted(FIXTURES)}, found {present}")
    fixture_text = {}
    for name, want in FIXTURES.items():
        p = os.path.join(fix_dir, name)
        if not os.path.isfile(p):
            problems.append(f"mech-fixtures: {name} missing")
            continue
        got = sha256_file(p)
        if got != want:
            problems.append(f"mech-fixtures: {name} sha256 {got} is not the recorded {want}")
        fixture_text[name] = read(p)
    fixture_shingles = set()
    for text in fixture_text.values():
        fixture_shingles |= shingles(text, SHINGLE)

    # corpus shape
    slugs = sorted(d for d in os.listdir(cases_dir) if os.path.isdir(os.path.join(cases_dir, d)))
    strays = sorted(set(os.listdir(cases_dir)) - set(slugs))
    if strays:
        problems.append(f"mech-cases: entries that are not case directories: {strays}")
    want_ids = [f"M{i:02d}" for i in range(1, N_CASES + 1)]
    ids = [s.split("-", 1)[0] for s in slugs]
    if ids != want_ids:
        problems.append(f"mech-cases: expected {N_CASES} case directories M01..M{N_CASES:02d}, found {len(slugs)}: {ids}")
    hard = {d.split("-", 1)[0][1:]: d for d in os.listdir(hard_dir)
            if os.path.isdir(os.path.join(hard_dir, d))}

    # tags across every case under evals/
    carriers = []
    all_cases = case_dirs_anywhere(root)
    for d in all_cases:
        if TAG in tags_of_case(d):
            carriers.append(os.path.relpath(d, root))
    outside = [c for c in carriers if os.path.dirname(c) != "mech-cases"]
    for c in outside:
        problems.append(f"tags: {c} carries {TAG} but is outside mech-cases; --tag {TAG} would run it")
    info["carriers"] = len(carriers)
    info["all_cases"] = len(all_cases)

    kinds = {}
    totals = {"halt": set(), "twin": set()}
    parsed = {}
    for slug in slugs:
        d = os.path.join(cases_dir, slug)
        num = slug.split("-", 1)[0][1:]
        entries = sorted(os.listdir(d))
        if entries != CASE_ENTRIES:
            problems.append(f"{slug}: unexpected entries {sorted(set(entries) - set(CASE_ENTRIES))}, "
                            f"missing {sorted(set(CASE_ENTRIES) - set(entries))}; a case holds exactly {CASE_ENTRIES}")

        # case.yaml and scaffold
        y = os.path.join(d, "case.yaml")
        if os.path.isfile(y) and read(y) != CASE_YAML:
            problems.append(f"{slug}: case.yaml differs from the canonical text; it may carry only "
                            "schema_version and context.scaffold_script")
        s = os.path.join(d, "scaffold.sh")
        if os.path.isfile(s) and read(s) != SCAFFOLD:
            problems.append(f"{slug}: scaffold.sh differs from the canonical SCAFFOLD; the only script this "
                            "corpus may run creates .claude/productizer/ and copies the two mech-fixtures into it")

        # prompt
        p = os.path.join(d, "prompt.md")
        if not os.path.isfile(p):
            continue
        prompt = read(p)
        fm, body = split_frontmatter(prompt)
        keys = top_keys(fm or "")
        if list(keys) != PROMPT_KEYS:
            problems.append(f"{slug}: prompt.md frontmatter keys {list(keys)} are not exactly {PROMPT_KEYS}")
        if keys.get("name") != slug:
            problems.append(f"{slug}: prompt.md name {keys.get('name')!r} does not match its directory")
        for k, v in PROMPT_VALUES.items():
            if keys.get(k) != v:
                problems.append(f"{slug}: prompt.md {k} is {keys.get(k)!r}, pre-registered {v!r}")
        if not os.path.isdir(os.path.normpath(os.path.join(d, PLUGIN_REL))):
            problems.append(f"{slug}: plugins path {PLUGIN_REL} does not resolve from the case directory")
        tags = flow_list(keys.get("tags", "")) or []
        if TAG not in tags:
            problems.append(f"{slug}: does not carry {TAG}")
        if OLD_TAG in tags:
            problems.append(f"{slug}: carries {OLD_TAG}; --tag {OLD_TAG} would rerun it inside the old corpus")

        shared = sorted(shingles(prompt, SHINGLE) & fixture_shingles)
        if shared:
            problems.append(f"{slug}: prompt shares {len(shared)} run(s) of {SHINGLE} words with the fixtures, "
                            f"e.g. '{shared[0]}'; the spec must reach the model from disk, not the prompt")
        for pat, label in FORBIDDEN:
            if re.search(pat, body, re.I):
                problems.append(f"{slug}: prompt names {label}; it must not point at the spec or the plugin")
                break

        # mirror
        h = hard.get(num)
        intent = None
        head, tail = "\n" + M_OPEN, "\n\n" + M_BODY_TAIL
        if body.startswith(head) and body.endswith(tail) and len(body) > len(head) + len(tail):
            intent = body[len(head):-len(tail)]
        else:
            problems.append(f"{slug}: prompt body is not the pre-registered wording around the intent")
        if h is None or h.split("-", 1)[1] != slug.split("-", 1)[1]:
            problems.append(f"{slug}: no H case with the same number and slug to mirror")
            h_prompt = None
        else:
            h_prompt = read(os.path.join(hard_dir, h, "prompt.md"))
            hm = H_INTENT.search(h_prompt)
            if intent is not None and (hm is None or hm.group(1) != intent):
                problems.append(f"{slug}: mirror: intent differs from {h}")
            h_tags = flow_list(top_keys(split_frontmatter(h_prompt)[0] or "").get("tags", "")) or []
            if [TAG if t == OLD_TAG else t for t in h_tags] != tags:
                problems.append(f"{slug}: mirror: tags {tags} are not {h}'s with {OLD_TAG} -> {TAG}")

        # graders
        gdir = os.path.join(d, "graders")
        if not os.path.isdir(gdir):
            continue
        names = sorted(f[:-3] for f in os.listdir(gdir) if f.endswith(".md"))
        is_halt = HALT in names
        kinds[slug] = "halt" if is_halt else "twin"
        outcome = HALT_OUTCOME if is_halt else TWIN_OUTCOME
        want = sorted(outcome + [m[:-3] for m in MECH_GRADERS])
        if names != want or len(os.listdir(gdir)) != len(want):
            problems.append(f"{slug}: grader set {names} is not the {kinds[slug]} set {want}")
        for m, text in MECH_GRADERS.items():
            gp = os.path.join(gdir, m)
            if os.path.isfile(gp) and read(gp) != text:
                problems.append(f"{slug}: {m} differs from its canonical text")
        metas = {}
        for g in names:
            metas[g] = grader_meta(read(os.path.join(gdir, g + ".md")))
        scored = sum(int(mt.get("weight", "1")) for mt in metas.values() if not with_only(mt))
        totals[kinds[slug]].add(scored)
        parsed[slug] = (d, h, is_halt, metas, scored)

    # weights, then the mirror of the outcome graders, which quotes them
    halt_total = min(totals["halt"]) if totals["halt"] else 0
    twin_total = min(totals["twin"]) if totals["twin"] else 0
    for kind, seen in totals.items():
        if len(seen) > 1:
            problems.append(f"weights: {kind} cases do not all carry the same scored total: {sorted(seen)}")
    mech = sum(int(grader_meta(t).get("weight", "1")) for t in MECH_GRADERS.values()
               if not with_only(grader_meta(t)))
    halt_w = [int(v[3][HALT].get("weight", "0")) + int(v[3].get("02-work-halted", {}).get("weight", "0"))
              for v in parsed.values() if v[2] and HALT in v[3]]
    twin_w = [int(v[3][TWIN].get("weight", "0")) for v in parsed.values() if not v[2] and TWIN in v[3]]
    for slug, (d, h, is_halt, metas, scored) in parsed.items():
        if h is None:
            continue
        hg = os.path.join(hard_dir, h, "graders")
        for g in (HALT_OUTCOME if is_halt else TWIN_OUTCOME):
            mp, hp = os.path.join(d, "graders", g + ".md"), os.path.join(hg, g + ".md")
            if not (os.path.isfile(mp) and os.path.isfile(hp)):
                continue
            mtext, htext = read(mp), read(hp)
            if g == HALT:
                w01, w02 = int(metas[g].get("weight", "0")), int(metas.get("02-work-halted", {}).get("weight", "0"))
                expected = htext.replace(OLD_HALT_PARA, halt_para(
                    w01, w02, halt_total, twin_w[0] if twin_w else 0, twin_total, mech))
                if OLD_HALT_PARA not in htext:
                    expected = None
            elif g == TWIN:
                w01 = int(metas[g].get("weight", "0"))
                expected = htext.replace(OLD_TWIN_PARA, twin_para(
                    w01, twin_total, halt_w[0] if halt_w else 0, halt_total, mech))
                if OLD_TWIN_PARA not in htext:
                    expected = None
            else:
                expected = htext
            if expected is None or mtext != expected:
                problems.append(f"{slug}: mirror: graders/{g}.md is not {h}'s"
                                + (" with the weight paragraph restated for this case's weights"
                                   if g in (HALT, TWIN) else ""))

    # twin pairing
    for i in range(1, N_CASES + 1, 2):
        pair = [s for s in slugs if s.split("-", 1)[0] in (f"M{i:02d}", f"M{i + 1:02d}")]
        halts = [s for s in pair if kinds.get(s) == "halt"]
        if len(pair) == 2 and len(halts) != 1:
            problems.append(f"pair M{i:02d}/M{i + 1:02d}: {len(halts)} must-halt cases; a twin pair holds exactly one")
    for slug, kind in kinds.items():
        tags = tags_of_case(os.path.join(cases_dir, slug))
        want = "positive" if kind == "halt" else "negative"
        if want not in tags or ("negative" if kind == "halt" else "positive") in tags:
            problems.append(f"{slug}: tags say {[t for t in tags if t in ('positive', 'negative')]}, "
                            f"graders say {want}")

    info["halt"] = sum(1 for k in kinds.values() if k == "halt")
    info["twin"] = sum(1 for k in kinds.values() if k == "twin")
    info["halt_total"], info["twin_total"] = halt_total, twin_total
    return problems, info


def run_check(root: str) -> int:
    try:
        problems, info = check(root)
    except CannotRun as e:
        print(f"check-mech-corpus: {e}", file=sys.stderr)
        return 2
    print(f"cases                : {info['halt'] + info['twin']}  ({info['halt']} must-halt, {info['twin']} must-not-halt)")
    print(f"cases carrying {TAG} : {info['carriers']} of {info['all_cases']} cases found under {os.path.basename(root) or root}/")
    print(f"scored weight        : {info['halt_total']} per must-halt case, {info['twin_total']} per must-not-halt case")
    print(f"off-prompt signal    : no {SHINGLE}-word run of either fixture in any prompt")
    if problems:
        print("\nPROBLEMS", file=sys.stderr)
        for p in problems:
            print("  " + p, file=sys.stderr)
        return 1
    print(f"\nfingerprint          : {fingerprint(root)}")
    print("  recompute: cd evals && find mech-cases mech-fixtures -type f | LC_ALL=C sort \\")
    print("               | xargs shasum -a 256 | shasum -a 256")
    print("\nall assertions hold")
    return 0


# ---------------------------------------------------------------- self-test

def _edit(path, old, new, count=1):
    text = read(path)
    if text.count(old) < count:
        raise AssertionError(f"break did not apply: {old!r} not in {path}")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text.replace(old, new, count))


def _append(path, extra):
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(extra)


def _case(E, n):
    base = os.path.join(E, "mech-cases")
    return os.path.join(base, next(d for d in sorted(os.listdir(base)) if d.startswith(f"M{n:02d}-")))


def _hcase(E, n):
    base = os.path.join(E, "hard-cases")
    return os.path.join(base, next(d for d in sorted(os.listdir(base)) if d.startswith(f"H{n:02d}-")))


def _breaks():
    R14 = ("When a slot is freed, the booking service shall offer it only to the first "
           "client on that practitioner's waitlist for 30 minutes.")
    return [
        ("pristine copy of the corpus", lambda E: None, 0, None),
        ("a case directory removed", lambda E: shutil.rmtree(_case(E, 14)), 1, "expected 14 case directories"),
        ("a fifteenth case directory added", lambda E: shutil.copytree(_case(E, 14), os.path.join(E, "mech-cases", "M15-extra")),
         1, "expected 14 case directories"),
        ("b18-mech added to an H case", lambda E: _edit(os.path.join(_hcase(E, 1), "prompt.md"), "b18-hard]", "b18-hard, b18-mech]"),
         1, "is outside mech-cases"),
        ("b18-mech in a block-list case.yaml elsewhere under evals/",
         lambda E: (os.makedirs(os.path.join(E, "cases", "Z99-stray")),
                    _append(os.path.join(E, "cases", "Z99-stray", "case.yaml"), "tags:\n  - positive\n  - b18-mech\n")),
         1, "is outside mech-cases"),
        ("b18-mech removed from M03", lambda E: _edit(os.path.join(_case(E, 3), "prompt.md"), ", b18-mech]", "]"),
         1, "does not carry b18-mech"),
        ("b18-hard added to M04", lambda E: _edit(os.path.join(_case(E, 4), "prompt.md"), "b18-mech]", "b18-mech, b18-hard]"),
         1, "carries b18-hard"),
        ("a stray file in a case directory", lambda E: _append(os.path.join(_case(E, 2), "notes.txt"), "x\n"),
         1, "unexpected entries ['notes.txt']"),
        ("scaffold output planted in a case directory", lambda E: os.makedirs(os.path.join(_case(E, 2), ".claude", "productizer")),
         1, "unexpected entries ['.claude']"),
        ("append_system_prompt added to prompt.md", lambda E: _edit(os.path.join(_case(E, 1), "prompt.md"),
                                                                    "runs: 3\n", "runs: 3\nappend_system_prompt: see .claude/productizer/spec.md\n"),
         1, "frontmatter keys"),
        ("name differs from its directory", lambda E: _edit(os.path.join(_case(E, 5), "prompt.md"), "name: M05-", "name: M5-"),
         1, "does not match its directory"),
        ("Bash added to allowed_tools", lambda E: _edit(os.path.join(_case(E, 6), "prompt.md"), "Skill]", "Skill, Bash]"),
         1, "allowed_tools"),
        ("max_turns changed", lambda E: _edit(os.path.join(_case(E, 6), "prompt.md"), "max_turns: 20", "max_turns: 10"),
         1, "max_turns"),
        ("plugins path no longer resolves", lambda E: shutil.rmtree(os.path.join(os.path.dirname(E), "plugins")),
         1, "plugins path"),
        ("case.yaml gains execution.prompt", lambda E: _append(os.path.join(_case(E, 7), "case.yaml"),
                                                               "execution:\n  prompt: read .claude/productizer/spec.md\n"),
         1, "case.yaml differs"),
        ("case.yaml gains context.history_file", lambda E: _edit(os.path.join(_case(E, 8), "case.yaml"),
                                                                 "  scaffold_script: scaffold.sh\n",
                                                                 "  scaffold_script: scaffold.sh\n  history_file: h.jsonl\n"),
         1, "case.yaml differs"),
        ("scaffold gains a network call", lambda E: _append(os.path.join(_case(E, 9), "scaffold.sh"),
                                                            "curl -s https://example.invalid/x\n"),
         1, "scaffold.sh differs"),
        ("scaffold copies from hard-fixtures", lambda E: _edit(os.path.join(_case(E, 10), "scaffold.sh"),
                                                               "../../mech-fixtures\"", "../../hard-fixtures\""),
         1, "scaffold.sh differs"),
        ("scaffold writes into the parent directory", lambda E: _edit(os.path.join(_case(E, 11), "scaffold.sh"),
                                                                      "mkdir -p .claude\n", "mkdir -p ../.claude\n"),
         1, "scaffold.sh differs"),
        ("a fixture edited by one byte", lambda E: _edit(os.path.join(E, "mech-fixtures", "booking-spec.md"), "`R43`", "`R44`"),
         1, "sha256"),
        ("a third fixture file", lambda E: _append(os.path.join(E, "mech-fixtures", "extra.md"), "x\n"),
         1, "mech-fixtures: expected exactly"),
        ("R14 pasted verbatim into a prompt", lambda E: _edit(os.path.join(_case(E, 1), "prompt.md"),
                                                              "VERDICT: <EXTEND", R14 + "\n\nVERDICT: <EXTEND"),
         1, "shares"),
        ("R14 pasted reflowed, re-cased, markdown stripped",
         lambda E: _edit(os.path.join(_case(E, 2), "prompt.md"), "VERDICT: <EXTEND",
                         "WHEN a slot is\nfreed, THE booking-service shall offer it only\nto the first client\n\nVERDICT: <EXTEND"),
         1, "shares"),
        ("a sentence of the constitution pasted", lambda E: _edit(os.path.join(_case(E, 3), "prompt.md"), "VERDICT: <EXTEND",
                                                                  "A client never loses money over a booking that someone other "
                                                                  "than the client ended.\n\nVERDICT: <EXTEND"),
         1, "shares"),
        ("prompt names the spec path", lambda E: _edit(os.path.join(_case(E, 4), "prompt.md"), "already agreed",
                                                       "already agreed (see .claude/productizer/)"),
         1, "prompt names .claude"),
        ("prompt uses the word spec", lambda E: _edit(os.path.join(_case(E, 5), "prompt.md"), "already agreed",
                                                      "already agreed in its spec"),
         1, "the word 'spec'"),
        ("intent reworded in M07", lambda E: _edit(os.path.join(_case(E, 7), "prompt.md"), "Carers keep asking", "Carers often ask"),
         1, "mirror: intent differs"),
        ("wording around the intent changed", lambda E: _edit(os.path.join(_case(E, 8), "prompt.md"), "state\nwhat happens next",
                                                              "state\nwhat happens to it next"),
         1, "not the pre-registered wording"),
        ("tag list diverges from the H twin", lambda E: _edit(os.path.join(_case(E, 9), "prompt.md"), "[negative, inferred,",
                                                              "[negative, inferred, extra,"),
         1, "mirror: tags"),
        ("outcome grader 05 edited", lambda E: _edit(os.path.join(_case(E, 1), "graders", "05-conflict-stated.md"),
                                                     "Wording need not match.", "Wording must match."),
         1, "mirror: graders/05-conflict-stated.md"),
        ("grader 01 weight changed", lambda E: _edit(os.path.join(_case(E, 3), "graders", HALT + ".md"),
                                                     "weight: 10", "weight: 12"),
         1, "mirror: graders/01-contradiction-detected.md"),
        ("weight paragraph left at the H figures", lambda E: _edit(
            os.path.join(_case(E, 5), "graders", HALT + ".md"), "10 of the 28", "10 of the 25"),
         1, "mirror: graders/01-contradiction-detected.md"),
        ("a scored weight changed (02 halt 6 -> 7) everywhere", lambda E: [
            _edit(os.path.join(_case(E, n), "graders", "02-work-halted.md"), "weight: 6", "weight: 7")
            for n in (1, 3, 5, 7, 10, 11, 13)],
         1, "mirror: graders/02-work-halted.md"),
        ("90-spec-read input_match loosened", lambda E: _edit(os.path.join(_case(E, 6), "graders", "90-spec-read.md"),
                                                              "spec\\.md", "md"),
         1, "90-spec-read.md differs"),
        ("92-rulings-read made scored", lambda E: _edit(os.path.join(_case(E, 7), "graders", "92-rulings-read.md"),
                                                        "arm: with-only", "arm: both"),
         1, "92-rulings-read.md differs"),
        ("91-constitution-read deleted", lambda E: os.remove(os.path.join(_case(E, 8), "graders", "91-constitution-read.md")),
         1, "grader set"),
        ("an extra grader file", lambda E: _append(os.path.join(_case(E, 9), "graders", "98-extra.md"),
                                                   "---\ntype: llm\nweight: 1\n---\n\nx\n"),
         1, "grader set"),
        ("twin broken: M02 made must-halt", lambda E: os.rename(
            os.path.join(_case(E, 2), "graders", TWIN + ".md"), os.path.join(_case(E, 2), "graders", HALT + ".md")),
         1, "pair M01/M02: 2 must-halt"),
        ("positive tag on a must-not-halt case", lambda E: _edit(os.path.join(_case(E, 12), "prompt.md"),
                                                                 "[negative,", "[positive,"),
         1, "graders say negative"),
        ("a fixture deleted", lambda E: os.remove(os.path.join(E, "mech-fixtures", "booking-constitution.md")),
         1, "booking-constitution.md missing"),
        ("a loose file in mech-cases", lambda E: _append(os.path.join(E, "mech-cases", "README.md"), "x\n"),
         1, "not case directories"),
        ("case.yaml deleted, so the case would run with no scaffold",
         lambda E: os.remove(os.path.join(_case(E, 13), "case.yaml")), 1, "missing ['case.yaml']"),
        ("prompt names the constitution", lambda E: _edit(os.path.join(_case(E, 10), "prompt.md"), "already agreed",
                                                          "already agreed in its constitution"),
         1, "prompt names constitution"),
        ("a case renamed away from its H twin", lambda E: os.rename(
            _case(E, 6), os.path.join(E, "mech-cases", "M06-renamed")), 1, "no H case with the same number and slug"),
        ("one case's scored total differs from the rest", lambda E: _edit(
            os.path.join(_case(E, 13), "graders", "00-scaffold-present.md"), "weight: 1", "weight: 2"),
         1, "do not all carry the same scored total"),
        ("mech-cases missing", lambda E: shutil.rmtree(os.path.join(E, "mech-cases")), 2, None),
        ("mech-fixtures missing", lambda E: shutil.rmtree(os.path.join(E, "mech-fixtures")), 2, None),
        ("hard-cases missing, so the mirror cannot be read", lambda E: shutil.rmtree(os.path.join(E, "hard-cases")), 2, None),
    ]


def _scratch(src_root: str) -> str:
    top = tempfile.mkdtemp(prefix="mech-selftest-")
    E = os.path.join(top, "evals")
    for d in ("mech-cases", "mech-fixtures", "hard-cases"):
        shutil.copytree(os.path.join(src_root, d), os.path.join(E, d))
    os.makedirs(os.path.join(top, "plugins", "productizer", ".claude-plugin"))
    return E


def _scaffold_behaviour(E: str) -> list:
    """Run the canonical scaffold for real, in throwaway directories only."""
    out = []
    script = os.path.join(_case(E, 1), "scaffold.sh")
    fixtures = os.path.join(E, "mech-fixtures")

    def run(argv, cwd):
        r = subprocess.run(argv, cwd=cwd, capture_output=True, text=True)
        return r.returncode, r.stderr.strip()

    def tree(d):
        return sorted(os.path.relpath(os.path.join(p, f), d) for p, _, fs in os.walk(d) for f in fs)

    ws = tempfile.mkdtemp(prefix="mech-ws-")
    rc, err = run(["bash", script], ws)
    ok = (rc == 0 and tree(ws) == [".claude/productizer/constitution.md", ".claude/productizer/spec.md"]
          and read(os.path.join(ws, ".claude/productizer/spec.md")) == read(os.path.join(fixtures, "booking-spec.md"))
          and read(os.path.join(ws, ".claude/productizer/constitution.md")) == read(os.path.join(fixtures, "booking-constitution.md")))
    out.append(("path semantics, empty working directory: writes the two fixtures, nothing else", ok, f"exit {rc}"))

    before = read(os.path.join(ws, ".claude/productizer/spec.md"))
    rc, err = run(["bash", script], ws)
    ok = rc == 5 and read(os.path.join(ws, ".claude/productizer/spec.md")) == before
    out.append(("a working directory that already holds a spec: refuses, touches nothing", ok, f"exit {rc}: {err}"))

    case_before = tree(_case(E, 1))
    rc, err = run(["bash", script], _case(E, 1))
    ok = rc == 4 and tree(_case(E, 1)) == case_before
    out.append(("working directory is the case directory: refuses, writes nothing", ok, f"exit {rc}: {err}"))

    moved = tempfile.mkdtemp(prefix="mech-moved-")
    shutil.copy(script, os.path.join(moved, "scaffold.sh"))
    ws3 = tempfile.mkdtemp(prefix="mech-ws-")
    rc, err = run(["bash", os.path.join(moved, "scaffold.sh")], ws3)
    ok = rc == 3 and tree(ws3) == []
    out.append(("script copied away from the corpus before running: refuses, writes nothing", ok, f"exit {rc}: {err}"))

    ws2 = tempfile.mkdtemp(prefix="mech-ws-")
    rc, err = run(["bash", "-c", "scaffold.sh"], ws2)
    ok = rc == 127 and tree(ws2) == []
    out.append(("the value `scaffold.sh` run as inline bash: exits 127, writes nothing", ok, f"exit {rc}: {err}"))

    for d in (ws, ws2, ws3, moved):
        shutil.rmtree(d)
    return out


def selftest() -> int:
    reached = []
    fails = 0
    total = 0
    src = HERE
    try:
        pristine_problems, _ = check(src)
    except CannotRun as e:
        print(f"selftest: the real corpus cannot be checked: {e}", file=sys.stderr)
        return 1
    for label, mutate, want_rc, want_text in _breaks():
        total += 1
        E = _scratch(src)
        try:
            mutate(E)
            try:
                problems, _ = check(E)
                rc = 1 if problems else 0
            except CannotRun as e:
                problems, rc = [str(e)], 2
        except AssertionError as e:
            problems, rc = [f"(break did not apply) {e}"], -1
        finally:
            shutil.rmtree(os.path.dirname(E))
        reached.append(rc)
        hit = None
        if want_text is None:
            hit = problems[0] if problems else ""
            ok = rc == want_rc
        else:
            hit = next((p for p in problems if want_text in p), None)
            ok = rc == want_rc and hit is not None
        fails += 0 if ok else 1
        print(f"  {'ok  ' if ok else 'FAIL'}  exit {rc} (want {want_rc})  {label}")
        if rc != 0:
            print(f"        red: {hit if hit is not None else problems[:1]}")

    for argv, label in ((["--bogus"], "an unknown argument"), (["--root"], "--root with no value")):
        total += 1
        rc = main(argv, quiet=True)
        reached.append(rc)
        ok = rc == 2
        fails += 0 if ok else 1
        print(f"  {'ok  ' if ok else 'FAIL'}  exit {rc} (want 2)  {label}")

    E = _scratch(src)
    if check(E)[0]:
        fails += 1
        print("  FAIL  scaffold behaviour not run: the scratch copy is not clean")
    else:
        for label, ok, detail in _scaffold_behaviour(E):
            total += 1
            fails += 0 if ok else 1
            print(f"  {'ok  ' if ok else 'FAIL'}  scaffold: {label}  ({detail})")
    shutil.rmtree(os.path.dirname(E))

    print(f"\n{total - fails} of {total} cases held")
    codes = sorted(set(c for c in reached if c >= 0))
    print(f"    exit codes reached: {' '.join(str(c) for c in codes)}   documented: 0 1 2")
    print("    NOT ASSERTED: that the harness honours any of this. The scaffold is run here with bash in "
          "throwaway directories, which shows what it does under path semantics and that the same value "
          "fails as inline bash; which one `claude plugin eval --scaffold` uses, and in which directory, is "
          "settled only by the smoke run in mech-preregistration.md. Paraphrase of the spec into a prompt "
          f"is not caught: the off-prompt signal is a {SHINGLE}-word verbatim run.")
    missing = {0, 1, 2} - set(codes)
    if missing:
        print(f"FAIL: documented code(s) {sorted(missing)} never driven by any case", file=sys.stderr)
        fails += 1
    if pristine_problems:
        print("FAIL: the real corpus is not clean, so the pristine case above measured a broken copy", file=sys.stderr)
        fails += 1
    return 0 if fails == 0 else 1


def main(argv, quiet=False) -> int:
    root = HERE
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--selftest" and len(argv) == 1:
            return selftest()
        if a == "--root" and i + 1 < len(argv):
            root = os.path.abspath(argv[i + 1])
            i += 2
            continue
        if not quiet:
            print(f"check-mech-corpus: unknown or incomplete argument {a!r}; see --help in the file header",
                  file=sys.stderr)
        return 2
    return run_check(root)


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    sys.exit(main(sys.argv[1:]))
