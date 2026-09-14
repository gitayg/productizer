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

Usage:
    check-hard-corpus.py
    check-hard-corpus.py --recall <aggregate-result.json>
"""

from __future__ import annotations

import importlib.util
import os
import re
import sys

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


def main() -> int:
    mod = load()
    if len(sys.argv) > 1:
        sys.argv[0] = "check-corpus.py"
        return mod.main()
    rc = mod.structural()
    return rc or plugin_paths(mod)


if __name__ == "__main__":
    sys.exit(main())
