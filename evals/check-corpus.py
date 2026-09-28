#!/usr/bin/env python3
"""Structural checks on the corpus, and the recall figure from a real run.

Three jobs, none of which need a model:

1. **Fixture drift.** Every case inlines its spec fixture into `prompt.md`,
   because an eval run gets a throwaway workspace with no repository in it. That
   makes `fixtures/` and the prompts two copies of the same text, and two copies
   drift. This asserts each prompt still contains its fixture byte for byte.
2. **Shape.** Case count, criteria count, and the weight actually carried by the
   recall criterion in each arm — the number `references/evals.md` quotes, read
   off the files rather than remembered.
3. **Recall.** Given an `aggregate-result.json` from `claude plugin eval`, the
   confusion matrix over the binary question the plugin asks: halt, or do not
   halt. Recall is read from the must-halt cases' detection grader, precision
   from the must-not-halt cases'. Nothing else in the run is allowed to move it.

Usage:
    check-corpus.py
    check-corpus.py --recall evals/results/<timestamp>/aggregate-result.json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CASES = os.path.join(HERE, "cases")
FIX = os.path.join(HERE, "fixtures")

DETECT = "01-contradiction-detected"
NO_FALSE_HALT = "01-no-false-halt"


def case_dirs():
    return sorted(d for d in os.listdir(CASES)
                  if os.path.isdir(os.path.join(CASES, d)))


def weight_of(path: str) -> int:
    m = re.search(r"^weight:\s*(\d+)\s*$", open(path).read(), re.M)
    return int(m.group(1)) if m else 0


def structural() -> int:
    fixtures = {f: open(os.path.join(FIX, f)).read().strip()
                for f in sorted(os.listdir(FIX)) if f.endswith(".md")}
    problems = []
    pos = neg = 0
    scored = indicators = 0
    detect_share = []
    for slug in case_dirs():
        d = os.path.join(CASES, slug)
        if not os.path.isfile(os.path.join(d, "prompt.md")):
            problems.append(f"{slug}: no prompt.md, so no fixture can be checked as inlined")
        else:
            prompt = open(os.path.join(d, "prompt.md")).read()
            hits = [f for f, text in fixtures.items() if text in prompt]
            specs = [f for f in hits if f.endswith("-spec.md")]
            consts = [f for f in hits if f.endswith("-constitution.md")]
            if len(specs) != 1 or len(consts) != 1:
                problems.append(f"{slug}: expected exactly one spec and one constitution "
                                f"inlined verbatim, found {specs} and {consts}")
        if not os.path.isdir(os.path.join(d, "graders")):
            problems.append(f"{slug}: no graders/ directory, so the case is neither must-halt "
                            f"nor must-not-halt and is not counted")
            continue
        graders = sorted(os.listdir(os.path.join(d, "graders")))
        names = [g[:-3] for g in graders]
        is_pos = DETECT in names
        pos, neg = (pos + 1, neg) if is_pos else (pos, neg + 1)
        if not is_pos and NO_FALSE_HALT not in names:
            problems.append(f"{slug}: neither {DETECT} nor {NO_FALSE_HALT} present")
        total = 0
        for g in graders:
            w = weight_of(os.path.join(d, "graders", g))
            if g.startswith("99-"):
                indicators += 1
            else:
                scored += 1
                total += w
        if is_pos and "02-work-halted.md" not in graders:
            problems.append(f"{slug}: must-halt case has {DETECT}.md but no 02-work-halted.md")
        keys = [DETECT, "02-work-halted"] if is_pos else [NO_FALSE_HALT]
        kw = sum(weight_of(os.path.join(d, "graders", k + ".md")) for k in keys if k + ".md" in graders)
        detect_share.append((slug, is_pos, kw, total))

    print(f"cases                : {pos + neg}  ({pos} must-halt, {neg} must-not-halt)")
    print(f"scored criteria      : {scored}")
    print(f"unscored indicators  : {indicators}   (tool_used: Skill, with-only under ablation)")
    print(f"grader files         : {scored + indicators}")
    p = [(w, t) for _, is_p, w, t in detect_share if is_p]
    n = [(w, t) for _, is_p, w, t in detect_share if not is_p]
    corpus = os.path.basename(CASES)
    if p:
        print(f"recall-bearing weight: {p[0][0]}/{p[0][1]} = {p[0][0] / p[0][1]:.0%} of a must-halt case's score")
        print(f"                       (detect the contradiction + halt the work)")
    else:
        print("recall-bearing weight: n/a (no must-halt case)")
        problems.append(f"{corpus}: no must-halt case (none carries {DETECT}.md), so recall has nothing to measure")
    if n:
        print(f"precision-bearing wt : {n[0][0]}/{n[0][1]} = {n[0][0] / n[0][1]:.0%} of a must-not-halt case's score")
    else:
        print("precision-bearing wt : n/a (no must-not-halt case)")
        problems.append(f"{corpus}: no must-not-halt case (none carries {NO_FALSE_HALT}.md), "
                        f"so precision has nothing to measure")
    if pos + neg:
        print(f"positive share       : {pos}/{pos + neg} = {pos / (pos + neg):.0%} of cases must halt")
    if problems:
        print("\nPROBLEMS", file=sys.stderr)
        for p_ in problems:
            print("  " + p_, file=sys.stderr)
        return 1
    print("\nfixtures inlined verbatim in every case; grader shape consistent")
    return 0


def recall(path: str) -> int:
    doc = json.load(open(path))
    tp = fn = fp = tn = 0
    missing = []
    for case in doc.get("cases", []):
        name = case.get("name", "?")
        runs = case.get("arms", {}).get("with", [])
        if not runs:
            missing.append(name)
            continue
        want_halt = None
        passed = 0
        counted = 0
        for run in runs:
            for g in run.get("graders", []):
                if g.get("name") == DETECT:
                    want_halt, counted = True, counted + 1
                    passed += 1 if g.get("passed") else 0
                elif g.get("name") == NO_FALSE_HALT:
                    want_halt, counted = False, counted + 1
                    passed += 1 if g.get("passed") else 0
        if want_halt is None or not counted:
            missing.append(name)
            continue
        # A case counts as halting when the majority of its runs did.
        majority = passed * 2 > counted
        if want_halt:
            tp, fn = (tp + 1, fn) if majority else (tp, fn + 1)
        else:
            tn, fp = (tn + 1, fp) if majority else (tn, fp + 1)

    print(f"  true positives  (contradiction detected, work halted) : {tp}")
    print(f"  false negatives (missed silently)                     : {fn}")
    print(f"  false positives (halted on a non-conflict)            : {fp}")
    print(f"  true negatives  (correctly stayed quiet)              : {tn}")
    if tp + fp:
        print(f"  precision : {tp / (tp + fp):.2f}   (n={tp + fp})")
    if tp + fn:
        print(f"  recall    : {tp / (tp + fn):.2f}   (n={tp + fn} must-halt cases)")
    if tp + fn < 30:
        print(f"\n  n={tp + fn} is a cohort, not a population. Quote this recall with its n")
        print("  attached and never as a bare number: at this size one case is 6 points.")
    for m in missing:
        print(f"  no detection grader result for case {m}", file=sys.stderr)
    return 1 if missing else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--recall", metavar="AGGREGATE_JSON",
                    help="compute the confusion matrix from a plugin eval result document")
    args = ap.parse_args()
    if args.recall:
        return recall(args.recall)
    return structural()


if __name__ == "__main__":
    sys.exit(main())
