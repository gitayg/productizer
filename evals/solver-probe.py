#!/usr/bin/env python3
"""Run the deterministic second opinion over this corpus, and report what it misses.

`claude plugin eval` measures the whole classifier: the model, reading the skill,
against a spec fixture. This script measures only the part of that classifier
that is arithmetic — `skills/spec/scripts/contradiction-check.py` — over the same
26 cases, by rendering each case's arriving intent as the EARS requirement it
would become and pairing it with the active requirement it collides with.

It exists because the two numbers answer different questions and get confused:

  contradiction-check.py --selftest   recall 0.70 over its own 21-pair corpus
  solver-probe.py                     recall over THIS corpus's 16 must-halt cases

The second number is the honest one for the gap this corpus was built to attack.
The first corpus was written by the hand that wrote the checker; this one was
written to the classes `references/solver.md` names as undecidable.

Cases whose conflict runs through a constitution principle have no EARS pair at
all — a principle is not a requirement and the checker never sees one. Those are
recorded as `no-pair`, which is a structural miss, not an unlucky one.

A probe whose numbers never move is measuring nothing, so it ships with two
interventions on the checker it measures:

    --break guards    disable the guard relation, the defence that produces the
                      checker's precision. Nothing in the halt column should move
                      on this corpus, because these negatives are quiet for a
                      different reason — the lexicon never fires on them at all.
    --break lexicon   add the six disposition pairs these misses would need.
                      Recall must rise. If it does not, the false-negative column
                      is a constant and this probe is decorative.

Usage:
    solver-probe.py                    table, confusion matrix, recall
    solver-probe.py --break lexicon    the intervention that must move recall
    solver-probe.py --break guards     the intervention that must not
    solver-probe.py --selftest         drive this probe's own exit contract

BOTH INTERVENTIONS ABOVE ARE INVERTED IN PRACTICE, AND THIS PARAGRAPH IS THE
WARNING RATHER THAN THE FIX. Measured: `--break lexicon` moves nothing and says
so - every pair it holds is already in the shipped lexicon - and `--break
guards` moves the halt column from 8 true positives to 12. So the sentences
above describe what each ablation was written to do, not what it does. That is
backlog B40 and it is open; `--selftest` pins the measured behaviour so a
change to it is caught, and does NOT assert the promise.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKER = os.path.join(HERE, os.pardir, "plugins", "productizer", "skills",
                       "spec", "scripts", "contradiction-check.py")


def load_checker():
    # Importing the checker must leave no trace in the plugin tree.
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("cc", CHECKER)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["cc"] = mod          # dataclasses resolves annotations via sys.modules
    spec.loader.exec_module(mod)
    return mod


# (case slug, must the pipeline halt, active requirement, the intent as EARS)
# A None pair means the conflict has no requirement-to-requirement form.
PAIRS = [
    ("P01-domain-entailment-access-log", True,
     "R2: When a subject requests erasure, the records service shall remove all personal data held for that subject within 30 days.",
     "R12: When a subject requests erasure, the records service shall retain the access log entries naming that subject for 7 years."),
    ("P02-vocabulary-drift-cancel-terminate", True,
     "R2: When a customer cancels their subscription, the billing service shall stop charging them at the end of the current cycle.",
     "R11: When a subscriber terminates their plan, the billing service shall issue a final charge at the next cycle."),
    ("P03-unquantified-adjective-latency", True,
     "R2: When a client requests a report, the api gateway shall respond in under 500 ms.",
     "R9: When a client requests a report at peak, the api gateway shall respond in a second or two."),
    ("P04-vocabulary-drift-expunge-archive", True,
     "R8: Where the tenant has enabled archival, the records service shall move records older than 365 days to cold storage.",
     "R12: Where records are older than twelve months, the records service shall expunge them."),
    ("P05-vocabulary-drift-unauthenticated-probe", True,
     "R1: The api gateway shall resolve a principal for every request before routing it.",
     "R9: Where a route is a health probe, the api gateway shall serve the caller without an identity lookup."),
    ("P06-constitution-fail-open-on-timeout", True,
     "R3: If the policy service does not answer within 200 ms, then the api gateway shall deny the request.",
     "R9: If the policy service does not answer within 200 ms, then the api gateway shall allow the request."),
    ("P07-constitution-cross-tenant-benchmark", True,
     "R11: When a tenant administrator requests a usage report, the records service shall report only that tenant's records.",
     "R12: When a tenant administrator requests a usage report, the records service shall show the tenant its position against the median across all customers."),
    ("P08-constitution-inplace-webhook-rename", True,
     "R6: When an invoice is issued, the billing service shall publish an invoice.issued webhook carrying the field amount_cents.",
     "R11: When an invoice is issued, the billing service shall publish an invoice.issued webhook carrying the field amount_minor_units."),
    ("P09-superseded-text-misread-as-live", True,
     "R9: If a provider posts a settlement callback the billing service cannot verify, then the billing service shall queue it for retry.",
     "R11: If a provider posts a settlement callback the billing service cannot verify, then the billing service shall reject it with 400."),
    ("P10-numeric-availability-unit-drift", True,
     "R5: The api gateway shall be available for at least 99.9 percent of each calendar month.",
     "R9: The api gateway shall be unavailable for no more than 90 minutes of each calendar month."),
    ("P11-numeric-retention-weeks-versus-days", True,
     "R2: When a subject requests erasure, the records service shall remove all personal data held for that subject within 30 days.",
     "R12: When a subject requests erasure, the records service shall preserve the data for at least 6 weeks."),
    ("P12-conflict-across-three-requirements", True,
     "R3: If the policy service does not answer within 200 ms, then the api gateway shall deny the request.",
     "R9: While the policy service is slow, the api gateway shall serve the report from cache."),
    ("P13-transitive-closed-account-charge", True,
     "R2: When a customer cancels their subscription, the billing service shall stop charging them at the end of the current cycle.",
     "R11: When a customer closes their account, the billing service shall continue charging them until the minimum term is served."),
    ("P14-guard-narrowing-opposed-response", True,
     "R5: While an account is in arrears for more than 14 days, the billing service shall suspend the account.",
     "R11: While an enterprise account is in arrears for more than 30 days, the billing service shall keep the account fully active."),
    ("P15-vocabulary-drift-dunning-abandon", True,
     "R4: When a payment fails, the billing service shall retry the payment once every 24 hours for 3 days.",
     "R11: When an authorisation is declined, the billing service shall abandon the retries and mark the invoice uncollectible."),
    ("P16-conflict-framed-as-refinement", True,
     "R7: If a refund is requested more than 90 days after the charge, then the billing service shall decline the refund.",
     "R11: If a refund is requested more than 90 days after the charge, then the billing service shall honour the refund."),

    ("N01-extend-data-portability", False,
     "R2: When a subject requests erasure, the records service shall remove all personal data held for that subject within 30 days.",
     "R12: When a subject requests a copy of their data, the records service shall provide a machine-readable export."),
    ("N02-refine-tighten-latency-bound", False,
     "R2: When a client requests a report, the api gateway shall respond in under 500 ms.",
     "R2: When a client requests a report, the api gateway shall respond in under 300 ms."),
    ("N03-duplicate-cancel-stops-billing", False,
     "R2: When a customer cancels their subscription, the billing service shall stop charging them at the end of the current cycle.",
     "R11: When a customer cancels their subscription, the billing service shall stop charging them at the end of the current cycle."),
    ("N04-near-miss-different-trigger", False,
     "R2: When a client requests a report, the api gateway shall respond in under 500 ms.",
     "R9: When a client requests a dashboard, the api gateway shall respond in under 2000 ms."),
    ("N05-near-miss-negated-guard", False,
     "R3: If the policy service does not answer within 200 ms, then the api gateway shall deny the request.",
     "R9: If the policy service answers within 200 ms, then the api gateway shall include the policy decision id in the response headers."),
    ("N06-near-miss-disjoint-numeric-guards", False,
     "R4: While a client has made more than 100 requests in the last minute, the api gateway shall reject further requests with 429.",
     "R9: While a client has made fewer than 10 requests in the last minute, the api gateway shall skip the rate-limit check."),
    ("N07-vocabulary-drift-is-duplicate", False,
     "R2: When a customer cancels their subscription, the billing service shall stop charging them at the end of the current cycle.",
     "R11: When a subscriber terminates their plan, the billing service shall cease billing them from the end of the current cycle."),
    ("N08-resembles-superseded-text-only", False,
     "R9: If a provider posts a settlement callback the billing service cannot verify, then the billing service shall queue it for retry.",
     "R11: If a provider posts a verified settlement callback naming an unknown invoice, then the billing service shall park it in a review queue."),
    ("N09-extend-complies-with-principle", False,
     "R11: When a tenant administrator requests a usage report, the records service shall exclude any figure derived from another tenant's records.",
     "R12: When a tenant administrator requests a usage report, the records service shall include a month-over-month trend for that tenant's own figures."),
    ("N10-refine-adds-precision-not-meaning", False,
     "R5: While an account is in arrears for more than 14 days, the billing service shall suspend the account.",
     "R5: While an account is in arrears for more than 14 consecutive days, the billing service shall suspend the account."),
]


# The dispositions this corpus opposes that the shipped lexicon does not carry.
MISSING_PAIRS = [
    ("remove", "retain"), ("remove", "preserve"), ("expunge", "move"),
    ("decline", "honour"), ("suspend", "keep"), ("abandon", "retry"),
]


def run(cc, brk: str | None) -> int:
    if brk == "guards":
        cc.guard_relation = lambda a, b: (cc.GUARD_EQUAL, "BROKEN: guard relation disabled")
    elif brk == "lexicon":
        # Only the pairs the shipped lexicon does NOT already carry. Once they
        # land in contradiction-check.py this list is a duplicate, the ablation
        # adds nothing, and it would report a zero delta that reads exactly like
        # "the lexicon does not matter" - a control asserting over an empty set,
        # which has bitten this repository twice. So it is computed, and an
        # empty result is announced rather than run silently.
        have = {tuple(sorted(pair)) for pair in cc.EXCLUSIVE_PAIRS}
        add = [p for p in MISSING_PAIRS if tuple(sorted(p)) not in have]
        if not add:
            print("--break lexicon adds nothing: every pair it holds is already in\n"
                  "the shipped lexicon, so this run is identical to the un-ablated one.\n"
                  "The gap it was written to measure is closed. Re-point MISSING_PAIRS\n"
                  "at dispositions the corpus opposes and the lexicon still lacks\n"
                  "before reading any delta from it.\n")
        cc.EXCLUSIVE_PAIRS = list(cc.EXCLUSIVE_PAIRS) + add

    rows = []
    for slug, should_halt, sa, sb in PAIRS:
        a, b = cc.parse(sa), cc.parse(sb)
        if a is None or b is None:
            rows.append((slug, should_halt, "PARSE-FAIL", "one side is not EARS"))
            continue
        v = cc.compare(a, b)
        rows.append((slug, should_halt, v.verdict, v.reason))

    width = max(len(r[0]) for r in rows)
    print(f"{'case':<{width}} {'wanted':<8} {'solver':<14}  why")
    print("-" * (width + 8 + 14 + 6))
    tp = fn = fp = tn = und = 0
    for slug, should_halt, verdict, why in rows:
        wanted = "HALT" if should_halt else "quiet"
        does_halt = verdict == cc.CONTRADICTION
        mark = " "
        if verdict == cc.UNDECIDED:
            und += 1
            mark = "?"
        elif should_halt and does_halt:
            tp += 1
        elif should_halt:
            fn += 1
            mark = "*"
        elif does_halt:
            fp += 1
            mark = "!"
        else:
            tn += 1
        print(f"{mark}{slug:<{width - 1}} {wanted:<8} {verdict:<14}  {why}")

    print("\nHalt, or do not halt — deterministic second opinion only")
    print(f"  true positives  (caught)          : {tp}")
    print(f"  false negatives (missed silently) : {fn}")
    print(f"  false positives (halted wrongly)  : {fp}")
    print(f"  true negatives  (stayed quiet)    : {tn}")
    print(f"  undecided       (escalated)       : {und}")
    if tp + fp:
        print(f"  precision : {tp / (tp + fp):.2f}")
    if tp + fn:
        print(f"  recall    : {tp / (tp + fn):.2f}   (n={tp + fn} must-halt cases)")
    print("\nThis is NOT the classifier's recall. It is the arithmetic floor under it.")
    print("The classifier's recall is what `claude plugin eval` measures; see")
    print("plugins/productizer/skills/spec/references/evals.md.")
    return 0


# ---------------------------------------------------------------------------
# --selftest - R39: THIS TOOL REACHES EACH EXIT CODE IT CAN RETURN, ON PURPOSE.
#
# Five cases, driven as subprocesses of this same file so the argument parser,
# the checker loader and the reporting are all on the path. Nothing is stubbed
# and nothing is asserted by reading source: the exit code is read off a real
# run.
#
#   bare           the probe over the committed corpus            -> 0
#   break-guards   the guard-relation ablation                    -> 0
#   break-lexicon  the lexicon ablation                           -> 0
#   no-checker     this file run from a directory where the
#                  checker path does not resolve                  -> 2
#   bad-break      a --break value argparse does not accept       -> 2
#
# THIS SCRIPT CAN RETURN 0 AND 2 AND NOTHING ELSE, and that is stated rather
# than padded. `run` always returns 0 - a corpus where every case missed is
# still a measurement and is reported as one - so there is no exit 1 to reach,
# and inventing a case that produced one would mean changing what this tool
# does in order to have something to test.
#
# ---------------------------------------------------------------------------
# THE TWO ABLATIONS ARE PINNED TO WHAT THEY MEASURABLY DO, WHICH IS NOT WHAT
# THE DOCSTRING ABOVE SAYS THEY DO. THIS IS BACKLOG B40 AND IT IS STILL OPEN.
#
# The docstring promises:
#
#   --break lexicon   "Recall must rise. If it does not, the false-negative
#                     column is a constant and this probe is decorative."
#   --break guards    "Nothing in the halt column should move on this corpus."
#
# Measured, on the tree this self-test ships in:
#
#   --break lexicon   moves NOTHING. It prints its own "adds nothing" notice -
#                     every pair MISSING_PAIRS holds is already in the shipped
#                     lexicon - and the confusion matrix is identical to the
#                     un-ablated run.
#   --break guards    MOVES THE HALT COLUMN, from 8 true positives to 12.
#
# So both advertised controls are inverted. The numbers below pin the BEHAVIOUR
# and not the promise, deliberately: a self-test written to the docstring would
# be red today against a tool that is working exactly as it currently works,
# and one that asserted nothing about the ablations would let the real numbers
# drift with nobody noticing. Neither of those is fixed here. When B40 is
# closed these figures MUST move, this self-test will go red saying so, and the
# right response is to update them and the docstring together - not to loosen
# the assertion.
# ---------------------------------------------------------------------------

# case -> (true positives, false negatives, false positives, true negatives,
#          undecided) as measured, plus a substring the run must print.
_SELFTEST_MATRIX = {
    "bare": ((8, 1, 0, 10, 7), "This is NOT the classifier's recall"),
    "break-guards": ((12, 1, 0, 10, 3), "BROKEN: guard relation disabled"),
    "break-lexicon": ((8, 1, 0, 10, 7), "--break lexicon adds nothing"),
}

_COUNT_RE = re.compile(
    r"true positives\D+(\d+).*?"
    r"false negatives\D+(\d+).*?"
    r"false positives\D+(\d+).*?"
    r"true negatives\D+(\d+).*?"
    r"undecided\D+(\d+)", re.S)


def _drive(argv, cwd=None):
    """Run this file as a subprocess. Returns (exit code, stdout, stderr).

    Nothing is suppressed: both streams are captured and both are searched, so
    a case that exits 2 for a reason other than its own is visible rather than
    read as the reason it declares.
    """
    proc = subprocess.run([sys.executable, os.path.abspath(__file__)] + argv,
                          cwd=cwd, capture_output=True, text=True)
    return proc.returncode, proc.stdout, proc.stderr


def selftest() -> int:
    cases = 0
    failed = 0

    def report(name, want, got, why):
        nonlocal cases, failed
        cases += 1
        if got == want:
            print("  held:    case %-14s expected %s  observed %s  %s"
                  % (name, want, got, why))
        else:
            print("  FINDING: case %-14s expected %s  observed %s  %s"
                  % (name, want, got, why))
            failed += 1

    # The clean case GUARDS THE OTHERS' PREMISE. If the bare probe does not
    # run, every case below would be red for that reason rather than its own,
    # and nothing would have been measured.
    rc, out, err = _drive([])
    if rc != 0:
        sys.stderr.write("solver-probe: --selftest: the bare probe exited %d, not 0, so no case "
                         "below could be attributed to what it was written to test. Unmeasured, "
                         "not a corpus that held.\n%s\n" % (rc, err.strip()))
        return 2

    outputs = {"bare": (rc, out, err)}
    for name, argv in (("break-guards", ["--break", "guards"]),
                       ("break-lexicon", ["--break", "lexicon"])):
        outputs[name] = _drive(argv)

    for name in ("bare", "break-guards", "break-lexicon"):
        rc, out, err = outputs[name]
        report(name, 0, rc, "the probe ran and reported a confusion matrix")

    # The measured ablation behaviour, pinned. See the B40 block above: these
    # are what the ablations DO, not what the docstring says they do.
    for name in ("bare", "break-guards", "break-lexicon"):
        want_counts, want_text = _SELFTEST_MATRIX[name]
        _, out, err = outputs[name]
        m = _COUNT_RE.search(out)
        got_counts = tuple(int(g) for g in m.groups()) if m else None
        cases += 1
        held = got_counts == want_counts and want_text in (out + err)
        print("  %s case %-14s matrix (tp,fn,fp,tn,und) expected %s  observed %s%s"
              % ("held:   " if held else "FINDING:", name, want_counts, got_counts,
                 "" if want_text in (out + err) else "  and it did not print %r" % want_text))
        if not held:
            failed += 1

    # A directory from which this file's own CHECKER path does not resolve. The
    # copy is what is run, so the `checker not found` branch is reached for
    # real rather than simulated by patching a constant.
    tmp = tempfile.mkdtemp(prefix="solver-probe-selftest.")
    try:
        stray = os.path.join(tmp, "solver-probe.py")
        shutil.copyfile(os.path.abspath(__file__), stray)
        proc = subprocess.run([sys.executable, stray], cwd=tmp,
                              capture_output=True, text=True)
        report("no-checker", 2, proc.returncode,
               "a copy of this file where the checker it measures is not on the path it "
               "computes: the measurement is refused rather than reported as an empty corpus")
        if "checker not found" not in proc.stderr:
            print("  note: the no-checker case exited %d without saying `checker not found`; "
                  "it may have been refused for some other reason." % proc.returncode)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    rc, _, _ = _drive(["--break", "there-is-no-such-ablation"])
    report("bad-break", 2, rc,
           "a --break value the parser does not accept: bad usage is refused rather than "
           "silently read as no ablation at all")

    print("  self-test cases driven: %d, exit codes reached: 0, 2. Cases that did not hold: %d"
          % (cases, failed))
    print("  NOT REACHED: exit 1. This tool has no failure exit - `run` returns 0 over any "
          "corpus, including one where every case missed - so there is no code 1 to drive, "
          "and no case here pretends to drive one.")
    print("  NOT ASSERTED: that the ablations do what the module docstring says they do. They "
          "do not, both are inverted, and that is backlog B40 - still open. The matrix rows "
          "above pin what they measurably do so a change is caught; they are not a claim that "
          "the documented control holds.")
    if failed:
        sys.stderr.write("solver-probe: %d self-test case(s) did not produce the exit code or "
                         "the measurement they declare.\n" % failed)
        return 1
    print("  R39 for this tool: the self-test exists and reaches 0 and 2, the only two codes "
          "this tool can return, by driving the real probe rather than reading its source.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--break", dest="brk", choices=("guards", "lexicon"),
                    help="intervene on the checker and re-run, to prove the probe is live")
    # `--self-test` is an alias, not a second flag: this repository spells the
    # same obligation both ways and a tool that answers only one spelling reads
    # as carrying no self-test to whichever scanner is looking for the other.
    ap.add_argument("--selftest", "--self-test", dest="selftest", action="store_true",
                    help="drive this probe's own exit contract and report what held")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not os.path.exists(CHECKER):
        print(f"checker not found at {CHECKER}", file=sys.stderr)
        return 2
    return run(load_checker(), args.brk)


if __name__ == "__main__":
    sys.exit(main())
