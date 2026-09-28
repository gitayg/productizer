#!/usr/bin/env python3
"""Run check-corpus.py's structural and recall checks over evals/hard-cases/.

The hard corpus lives beside the original rather than inside it, so the 26-case
figures that references/evals.md, GUIDE.md and the CI workflow quote do not
move. This wrapper reuses check-corpus.py unchanged and only points it at the
other directory pair:

    evals/hard-cases/     the cases
    evals/hard-fixtures/  the spec and constitution each case inlines verbatim

It adds one check the original does not need: every case's `plugins:` path must
resolve from the case directory, because a path that resolves to nothing turns
the plugin arm into a second bare arm and the comparison into noise.

What it asserts. Each is broken on purpose in --selftest, in a scratch copy of
the corpus, and must come back red there with its reason before it is believed.

  inlined      each prompt contains exactly one `*-spec.md` and exactly one
               `*-constitution.md` from hard-fixtures/, byte for byte
  graders      a must-not-halt case carries 01-no-false-halt.md, a must-halt
               case carries 02-work-halted.md beside 01-contradiction-detected.md
  files        every case has a prompt.md and a graders/ directory
  both classes the corpus holds at least one must-halt and one must-not-halt
               case, or recall or precision has nothing to measure
  plugins      each prompt's `plugins: ["<path>"]` names a directory that
               exists, resolved from the case directory; checked only once
               the two above hold
  recall       with --recall, every case in the result document has a `with`
               arm carrying a detection grader result

NOTE. Each of those is a sentence naming the case (or the corpus directory)
and what is missing, at exit 1. Until B82 a missing grader, prompt.md or
graders/, or an empty class, ended in a Python traceback instead, also exit 1.
A grader counts as present only under its exact name, so a case-only rename is
a finding on macOS as it is on Linux.

Usage:
    check-hard-corpus.py
    check-hard-corpus.py --recall <aggregate-result.json>
    check-hard-corpus.py --selftest

Exit: 0 clean · 1 an assertion above failed, or the checker crashed with a
      Python traceback (an unreadable result document, a missing
      hard-fixtures/), or a self-test case failed · 2 bad usage, rejected by
      check-corpus.py's argument parser
"""

from __future__ import annotations

import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def load():
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location(
        "check_corpus", os.path.join(HERE, "check-corpus.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.CASES = os.path.join(HERE, "hard-cases")
    mod.FIX = os.path.join(HERE, "hard-fixtures")
    return mod


def plugin_paths(mod) -> int:
    bad = []
    for slug in mod.case_dirs():
        d = os.path.join(mod.CASES, slug)
        m = re.search(r'^plugins:\s*\["([^"]+)"\]', open(os.path.join(d, "prompt.md")).read(), re.M)
        if m is None or not os.path.isdir(os.path.normpath(os.path.join(d, m.group(1)))):
            bad.append(slug)
    for slug in bad:
        print(f"  {slug}: plugins path does not resolve from the case directory", file=sys.stderr)
    return 1 if bad else 0


# ---------------------------------------------------------------- self-test

DOCUMENTED = (0, 1, 2)
FIRST_SEEN = "fixtures inlined verbatim in every case; grader shape consistent"


def _edit(path, old, new):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if old not in text:
        raise AssertionError(f"break did not apply: {old!r} not in {path}")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text.replace(old, new, 1))


def _write(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def _case(E, n):
    base = os.path.join(E, "hard-cases")
    return os.path.join(base, next(d for d in sorted(os.listdir(base)) if d.startswith(f"H{n:02d}-")))


def _swap_plugins_for_file(E):
    target = os.path.join(os.path.dirname(E), "plugins", "productizer")
    shutil.rmtree(target)
    _write(target, "not a directory\n")


def _drop_class(E, grader):
    base = os.path.join(E, "hard-cases")
    for d in os.listdir(base):
        if grader in os.listdir(os.path.join(base, d, "graders")):
            shutil.rmtree(os.path.join(base, d))


def _aggregate(E, cases):
    path = os.path.join(E, "aggregate-result.json")
    _write(path, json.dumps({"cases": cases}))
    return path


def _grader_runs(name, results):
    return [{"graders": [{"name": "99-skill-fired", "passed": True}, {"name": name, "passed": r}]}
            for r in results]


def _matrix(E):
    # One case per cell, and the tie in P-tie (1 of 2) pins the STRICT majority.
    # Every `without` arm is five failed runs: read by mistake, it outvotes each
    # `with` arm and moves all four cells, so it must be ignored.
    return _aggregate(E, [
        {"name": "P-major", "arms": {"with": _grader_runs("01-contradiction-detected", [True, True, False]),
                                     "without": _grader_runs("01-contradiction-detected", [False] * 5)}},
        {"name": "P-tie", "arms": {"with": _grader_runs("01-contradiction-detected", [True, False]),
                                   "without": _grader_runs("01-contradiction-detected", [False] * 5)}},
        {"name": "N-major", "arms": {"with": _grader_runs("01-no-false-halt", [True, True, True]),
                                     "without": _grader_runs("01-no-false-halt", [False] * 5)}},
        {"name": "N-minor", "arms": {"with": _grader_runs("01-no-false-halt", [False, False, True]),
                                     "without": _grader_runs("01-no-false-halt", [False] * 5)}},
    ])


MATRIX_LINES = (
    "  true positives  (contradiction detected, work halted) : 1\n"
    "  false negatives (missed silently)                     : 1\n"
    "  false positives (halted on a non-conflict)            : 1\n"
    "  true negatives  (correctly stayed quiet)              : 1\n"
    "  precision : 0.50   (n=2)\n"
    "  recall    : 0.50   (n=2 must-halt cases)\n")


def _cases():
    """(label, setup(E) -> argv, want_rc, stream, [substrings that must appear])."""
    H02 = "H02-far-waitlist-hold-respected"
    H03 = "H03-constitution-sync-cancel-keeps-deposit"
    H05 = "H05-superseded-cited-by-id-second-reminder"
    H04 = "H04-constitution-sync-cancel-refunds"
    H06 = "H06-superseded-cited-by-id-no-conflict"
    H01 = "H01-far-waitlist-hold-public-search"
    H14 = "H14-joint-no-show-warning"
    PLUG = 'plugins: ["../../../plugins/productizer"]\n'
    return [
        ("pristine copy of the corpus", lambda E: [], 0, "stdout",
         ["cases                : 14  (7 must-halt, 7 must-not-halt)", FIRST_SEEN]),
        ("the inlined spec edited by one character in one prompt",
         lambda E: (_edit(os.path.join(_case(E, 3), "prompt.md"),
                          "# Booking service — living spec", "# Booking service - living spec"), [])[1],
         1, "stderr",
         [f"{H03}: expected exactly one spec and one constitution inlined verbatim, "
          "found [] and ['booking-constitution.md']"]),
        ("the constitution fixture edited, so no prompt inlines it",
         lambda E: (_edit(os.path.join(E, "hard-fixtures", "booking-constitution.md"),
                          "# Booking — constitution", "# Booking - constitution"), [])[1],
         1, "stderr",
         [f"{H14}: expected exactly one spec and one constitution inlined verbatim, "
          "found ['booking-spec.md'] and []"]),
        ("a second spec fixture that every prompt also contains",
         lambda E: (_write(os.path.join(E, "hard-fixtures", "extra-spec.md"), "Run intake on the intent below\n"), [])[1],
         1, "stderr",
         [f"{H03}: expected exactly one spec and one constitution inlined verbatim, "
          "found ['booking-spec.md', 'extra-spec.md'] and ['booking-constitution.md']"]),
        ("a second constitution fixture that every prompt also contains",
         lambda E: (_write(os.path.join(E, "hard-fixtures", "extra-constitution.md"),
                           "Run intake on the intent below\n"), [])[1],
         1, "stderr",
         [f"{H03}: expected exactly one spec and one constitution inlined verbatim, "
          "found ['booking-spec.md'] and ['booking-constitution.md', 'extra-constitution.md']"]),
        ("a must-not-halt case loses 01-no-false-halt.md",
         lambda E: (os.rename(os.path.join(_case(E, 2), "graders", "01-no-false-halt.md"),
                              os.path.join(_case(E, 2), "graders", "01-renamed.md")), [])[1],
         1, "stderr",
         [f"  {H02}: neither 01-contradiction-detected nor 01-no-false-halt present"]),
        ("a must-halt case loses 02-work-halted.md",
         lambda E: (os.remove(os.path.join(_case(E, 1), "graders", "02-work-halted.md")), [])[1],
         1, "stderr",
         [f"  {H01}: must-halt case has 01-contradiction-detected.md but no 02-work-halted.md"]),
        ("a case loses prompt.md",
         lambda E: (os.remove(os.path.join(_case(E, 3), "prompt.md")), [])[1],
         1, "stderr",
         [f"  {H03}: no prompt.md, so no fixture can be checked as inlined"]),
        ("a case loses its graders/ directory",
         lambda E: (shutil.rmtree(os.path.join(_case(E, 4), "graders")), [])[1],
         1, "stderr",
         [f"  {H04}: no graders/ directory, so the case is neither must-halt nor must-not-halt "
          "and is not counted"]),
        ("every must-halt case removed",
         lambda E: (_drop_class(E, "01-contradiction-detected.md"), [])[1],
         1, "stderr",
         ["  hard-cases: no must-halt case (none carries 01-contradiction-detected.md), "
          "so recall has nothing to measure"]),
        ("every must-not-halt case removed",
         lambda E: (_drop_class(E, "01-no-false-halt.md"), [])[1],
         1, "stderr",
         ["  hard-cases: no must-not-halt case (none carries 01-no-false-halt.md), "
          "so precision has nothing to measure"]),
        ("a plugins path one level short",
         lambda E: (_edit(os.path.join(_case(E, 5), "prompt.md"), PLUG,
                          'plugins: ["../../plugins/productizer"]\n'), [])[1],
         1, "stderr",
         [f"  {H05}: plugins path does not resolve from the case directory"]),
        ("the plugins line removed from a prompt",
         lambda E: (_edit(os.path.join(_case(E, 6), "prompt.md"), PLUG, ""), [])[1],
         1, "stderr",
         [f"  {H06}: plugins path does not resolve from the case directory"]),
        ("the plugins path names a file, not a directory",
         lambda E: (_swap_plugins_for_file(E), [])[1],
         1, "stderr",
         [f"  {H14}: plugins path does not resolve from the case directory"]),
        ("--recall over a four-cell confusion matrix with a tie",
         lambda E: ["--recall", _matrix(E)], 0, "stdout", [MATRIX_LINES]),
        ("--recall with a case that has no with arm",
         lambda E: ["--recall", _aggregate(E, [
             {"name": "P-major", "arms": {"with": _grader_runs("01-contradiction-detected", [True])}},
             {"name": "Z-armless", "arms": {"without": _grader_runs("01-contradiction-detected", [True])}}])],
         1, "stderr", ["  no detection grader result for case Z-armless"]),
        ("--recall with a case whose runs carry no detection grader",
         lambda E: ["--recall", _aggregate(E, [
             {"name": "P-major", "arms": {"with": _grader_runs("01-contradiction-detected", [True])}},
             {"name": "Z-ungraded", "arms": {"with": _grader_runs("03-both-sides-cited", [True])}}])],
         1, "stderr", ["  no detection grader result for case Z-ungraded"]),
        ("--recall on a result document that does not exist (a traceback)",
         lambda E: ["--recall", os.path.join(E, "absent.json")], 1, "stderr",
         ["FileNotFoundError", "absent.json"]),
        ("an unknown argument", lambda E: ["--bogus"], 2, "stderr",
         ["error: unrecognized arguments: --bogus"]),
        ("--recall with no value", lambda E: ["--recall"], 2, "stderr",
         ["error: argument --recall: expected one argument"]),
        ("--selftest with an extra argument is not a self-test", lambda E: ["--selftest", "--bogus"], 2, "stderr",
         ["error: unrecognized arguments: --selftest --bogus"]),
    ]


def _scratch(self_path):
    top = tempfile.mkdtemp(prefix="hard-selftest-")
    E = os.path.join(top, "evals")
    for d in ("hard-cases", "hard-fixtures"):
        shutil.copytree(os.path.join(HERE, d), os.path.join(E, d))
    shutil.copy(os.path.join(HERE, "check-corpus.py"), os.path.join(E, "check-corpus.py"))
    shutil.copy(self_path, os.path.join(E, "check-hard-corpus.py"))
    os.makedirs(os.path.join(top, "plugins", "productizer"))
    return E


def _invoke(script, argv):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    r = subprocess.run([sys.executable, script] + argv, capture_output=True, text=True, env=env)
    return r.returncode, r.stdout, r.stderr


def selftest() -> int:
    self_path = os.path.abspath(__file__)
    fails = total = 0
    reached = []

    real_rc, real_out, real_err = _invoke(self_path, [])
    if real_rc != 0:
        print(f"  FAIL  the real corpus is not clean (exit {real_rc}), so every case below measured a broken copy",
              file=sys.stderr)
        print("        " + (real_err.strip().splitlines() or [""])[-1], file=sys.stderr)
        fails += 1

    for label, setup, want_rc, stream, wants in _cases():
        total += 1
        E = _scratch(self_path)
        try:
            argv = setup(E)
            rc, out, err = _invoke(os.path.join(E, "check-hard-corpus.py"), argv)
        except AssertionError as e:
            rc, out, err = -1, "", f"(break did not apply) {e}"
        finally:
            shutil.rmtree(os.path.dirname(E))
        reached.append(rc)
        text = out if stream == "stdout" else err
        missing = [w for w in wants if w not in text]
        ok = rc == want_rc and not missing
        if ok and label.startswith("pristine") and real_rc == 0 and out != real_out:
            ok, missing = False, ["stdout identical to the real corpus's"]
        fails += 0 if ok else 1
        print(f"  {'ok  ' if ok else 'FAIL'}  exit {rc} (want {want_rc})  {label}")
        if not ok:
            print(f"        missing from {stream}: {missing}")
            tail = (err.strip() or out.strip()).splitlines()
            print(f"        got: {tail[-1] if tail else '(nothing)'}")
        elif rc != 0:
            print(f"        red: {wants[-1]}")

    print(f"\n{total - fails} of {total} cases held")
    codes = sorted(set(c for c in reached if c >= 0))
    print(f"    exit codes reached: {' '.join(str(c) for c in codes)}   "
          f"documented: {' '.join(str(c) for c in DOCUMENTED)}")
    print("    NOT ASSERTED: that every missing file is a named finding - a missing hard-fixtures/ "
          "still ends in a traceback (exit 1). The shape figures the "
          "pristine run prints are compared with the real corpus's, never with a recorded value, so "
          "only the case count is pinned. No `claude plugin eval` result format is read beyond the "
          "fields --recall uses.")
    missing_codes = sorted(set(DOCUMENTED) - set(codes))
    if missing_codes:
        print(f"FAIL: documented code(s) {missing_codes} never driven by any case", file=sys.stderr)
        fails += 1
    return 0 if fails == 0 else 1


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        return selftest()
    mod = load()
    if len(sys.argv) > 1:
        sys.argv[0] = "check-corpus.py"
        return mod.main()
    rc = mod.structural()
    return rc or plugin_paths(mod)


if __name__ == "__main__":
    sys.exit(main())
