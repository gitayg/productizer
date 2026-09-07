#!/usr/bin/env python3
"""Run the deterministic second opinion over this corpus, and report what it misses.

`claude plugin eval` measures the whole classifier: the model, reading the skill,
against a spec fixture. This script measures only the part of that classifier
that is arithmetic — `skills/spec/scripts/contradiction-check.py` — over the same
26 cases, by rendering each case's arriving intent as the EARS requirement it
would become and pairing it with the active requirement it collides with.

It exists because the two numbers answer different questions and get confused:

  contradiction-check.py --selftest   recall 0.94 over its own 33-pair corpus
  solver-probe.py                     recall over THIS corpus's 16 must-halt cases

The second number is the honest one for the gap this corpus was built to attack.
The first corpus was written by the hand that wrote the checker; this one was
written to the classes `references/solver.md` names as undecidable.

Cases whose conflict runs through a constitution principle have no EARS pair at
all — a principle is not a requirement and the checker never sees one. Those are
recorded as `no-pair`, which is a structural miss, not an unlucky one.

A probe whose numbers never move is measuring nothing, so it ships with two
interventions on the checker it measures. WHAT EACH ONE DOES, MEASURED
2026-09-06 ON THE TREE THIS FILE SHIPS IN — not what it was written to do:

    --break guards    disable the guard relation. THIS MOVES THE HALT COLUMN:
                      true positives 9 -> 12, undecided 6 -> 3, recall
                      0.90 -> 0.92. The guard relation is what holds this
                      corpus's remaining misses at UNDECIDED, so disabling it
                      is the intervention that is live here. Precision does not
                      move (1.00, no negative flips), which is the part worth
                      reading: the negatives are quiet for a reason the guard
                      relation is not carrying.
    --break lexicon   add the disposition pairs MISSING_PAIRS holds. THIS MOVES
                      NOTHING, and announces that rather than reporting a zero
                      delta. All six pairs shipped in contradiction-check.py —
                      the ablation measured what adding them was worth, they
                      were added, and the ablation became a duplicate of the
                      un-ablated run. Its zero is a closed gap, not a control.

Usage:
    solver-probe.py                    table, confusion matrix, recall
    solver-probe.py --break guards     the intervention that moves the matrix
    solver-probe.py --break lexicon    a spent ablation, kept for its notice
    solver-probe.py --selftest         drive this probe's own exit contract

TWO CLAIMS WERE WITHDRAWN FROM THIS DOCSTRING ON 2026-09-06 (backlog B40).
Until that date it advertised `--break lexicon` as "the intervention that must
move recall. If it does not, the false-negative column is a constant and this
probe is decorative", and `--break guards` as the control on which "nothing in
the halt column should move". BOTH WERE INVERTED, exactly reversing which one
demonstrated the matrix was live — and a self-check that reads as passed while
being inverted is worse than no claim, so the claims are gone rather than
restated.

THE OTHER FIX WAS TRIED FIRST AND IS NOT AVAILABLE HONESTLY. Re-pointing
MISSING_PAIRS at dispositions this corpus opposes and the lexicon still lacks
would have made `--break lexicon` live again. There are none. Every remaining
must-halt case was enumerated against every candidate pair drawn from its own
two response clauses, and:

  * P04, P07, P12, P14, P15 cannot be flipped to CONTRADICTION by ANY lexicon
    pair. Four of them already fire on a shipped pair and are held at UNDECIDED
    by guard overlap (0%, 25%, 57%, 0%); P07 is the scope heuristic. The
    lexicon is not the binding constraint on any of them.

    P14 WAS THE ONE OF THOSE FIVE THAT HAD A BINDING CONSTRAINT WORTH LIFTING,
    and it was the guard side, exactly as the line above says. Its two guards -
    *an account in arrears for more than 14 days* and *an enterprise account in
    arrears for more than 30 days* - share 57% of their terms, so they read as
    UNKNOWN, while the second ENTAILS the first: it says everything the first
    says and its range on time sits inside the first's. `guard_entailment` in
    contradiction-check.py now proves that with the interval arithmetic the
    file already carried, and P14 convicts (2026-09-06). Nothing was added to
    any lexicon to do it, which is what makes it consistent with the
    enumeration above rather than a refutation of it.
  * P03, P05, P08 can be flipped, but only by pairs that are not oppositions:
    ('500','second') and ('under','two') for P03, ('every','caller') and
    ('before','identity') for P05, ('cents','minor') for P08. Declaring any of
    those an antonym is fabricating a lexicon entry to make an ablation work,
    which is the failure this whole tool exists to detect. P03 and P08 are also
    cases the solver is meant to miss — an unquantified adjective, and a rename
    only a person can tell from an addition.

An upper bound was run to make the negative measurable rather than argued: with
EXCLUSIVE_PAIRS replaced by every response stem opposed to every other — the
maximal lexicon, which no honest addition can exceed — recall does reach 1.00,
and it does so by opposing 'abandon' to 'day' and 'data' to 'export', losing a
true negative to a false positive on the way. So recall is lexicon-movable in
principle and not by anything true. That is the evidence for withdrawing rather
than re-pointing.

WHAT IS LEFT IS STILL A LIVE PROBE. `--break guards` moves three cases from
UNDECIDED into the halt column, so the confusion matrix is demonstrably not a
constant. The demonstration just runs through the ablation the old docstring
called the control, and this file now says so.
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


# The dispositions this corpus opposes that the shipped lexicon DID NOT carry
# when this list was written. All six have since shipped in
# contradiction-check.py, which is why `--break lexicon` is now a no-op. The
# list is kept because it is the record of what the ablation measured before
# the gap was closed, and because computing the difference against the shipped
# lexicon is what lets the ablation ANNOUNCE its emptiness instead of reporting
# a zero delta. See the module docstring for why it was not re-pointed.
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
                  "The gap it was written to measure is closed, and re-pointing this\n"
                  "ablation was tried on 2026-09-06 and refused: no remaining miss in\n"
                  "this corpus is held back by a pair the lexicon lacks. Read no delta\n"
                  "from this run - the live intervention is `--break guards`.\n")
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
# THE TWO ABLATIONS ARE PINNED TO WHAT THEY MEASURABLY DO. AS OF 2026-09-06
# THAT IS ALSO WHAT THE DOCSTRING SAYS THEY DO - B40 IS CLOSED BY WITHDRAWAL.
#
# The docstring used to promise:
#
#   --break lexicon   "Recall must rise. If it does not, the false-negative
#                     column is a constant and this probe is decorative."
#   --break guards    "Nothing in the halt column should move on this corpus."
#
# Both were inverted. Measured, on the tree this self-test ships in:
#
#   --break lexicon   moves NOTHING. It prints its own "adds nothing" notice -
#                     every pair MISSING_PAIRS holds is already in the shipped
#                     lexicon - and the confusion matrix is identical to the
#                     un-ablated run.
#   --break guards    MOVES THE HALT COLUMN, from 9 true positives to 12.
#
# THE FIGURES BELOW DID NOT MOVE WHEN B40 CLOSED, AND THAT IS SAID PLAINLY
# BECAUSE THE PREVIOUS VERSION OF THIS BLOCK PREDICTED THEY WOULD. It said
# "when B40 is closed these figures MUST move, this self-test will go red
# saying so". That prediction assumed the fix would be to re-point
# MISSING_PAIRS at pairs that genuinely move recall. Those pairs were looked
# for on 2026-09-06 and do not exist - every remaining must-halt miss is held
# by the guard relation, by a scope heuristic, or is a case the solver is meant
# to miss, and the only pairs that would flip any of them are not oppositions
# at all. The evidence is in the module docstring. So the fix was to withdraw
# the two claims instead, no measured count changed, and this self-test is
# green for the same reason it was green before: it pins BEHAVIOUR.
#
# THEY MOVED ON 2026-09-06, AND THIS IS WHAT MOVED THEM. `guard_entailment`
# in contradiction-check.py proves that one guard entails the other when it
# says everything the other says and its range on a shared dimension sits
# inside the other's - P14's *more than 30 days* inside *more than 14 days*.
# P14 leaves the undecided column and convicts: bare and break-lexicon go from
# (8, 1, 0, 10, 7) to (9, 1, 0, 10, 6). `break-guards` does not move, because
# disabling the guard relation already convicted P14. Nothing was added to any
# lexicon, so B40's enumeration above is untouched by this.
#
# WHAT IS STILL TRUE OF THESE NUMBERS. They are a drift guard, not a
# demonstration that the documented control holds - there is no longer a
# documented control to hold. If they move, the checker underneath moved, and
# the right response is to find out why before updating them. CI's baseline in
# `.github/workflows/checks.yml` gates the same four counts and must be kept in
# step with this dict.
# ---------------------------------------------------------------------------

# case -> (true positives, false negatives, false positives, true negatives,
#          undecided) as measured, plus a substring the run must print.
_SELFTEST_MATRIX = {
    "bare": ((9, 1, 0, 10, 6), "This is NOT the classifier's recall"),
    "break-guards": ((12, 1, 0, 10, 3), "BROKEN: guard relation disabled"),
    "break-lexicon": ((9, 1, 0, 10, 6), "--break lexicon adds nothing"),
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
    # R39.b: the reached half of the declaration at the end of this function is
    # ACCUMULATED here, one entry per case as it runs, off the exit code the
    # child actually returned. A literal list would satisfy the reader that
    # parses the line and prove nothing.
    reached = set()

    def report(name, want, got, why):
        nonlocal cases, failed
        cases += 1
        reached.add(got)
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

    print("  self-test cases driven: %d. Cases that did not hold: %d"
          % (cases, failed))
    # The R39.b declaration. The reached half is computed from the cases above;
    # the documented half is this file's contract, stated in the R39 block near
    # the top of this section: 0 and 2 and nothing else.
    documented = (0, 2)
    print("    exit codes reached: %s   documented: %s"
          % (" ".join(str(c) for c in sorted(reached)),
             " ".join(str(c) for c in documented)))
    missing = [c for c in documented if c not in reached]
    print("  NOT REACHED: exit 1. This tool has no failure exit - `run` returns 0 over any "
          "corpus, including one where every case missed - so there is no code 1 to drive, "
          "and no case here pretends to drive one.")
    print("  NOT ASSERTED: that either ablation is a control. It is not asserted because the "
          "module no longer claims it - B40 was closed on 2026-09-06 by withdrawing two "
          "inverted claims, not by making either ablation live. The matrix rows above pin what "
          "the ablations measurably do, so a change is caught; `--break guards` moving three "
          "cases is what shows the matrix is not a constant.")
    if failed:
        sys.stderr.write("solver-probe: %d self-test case(s) did not produce the exit code or "
                         "the measurement they declare.\n" % failed)
        return 1
    if missing:
        sys.stderr.write("solver-probe: documented exit code(s) no case reached: %s\n"
                         % " ".join(str(c) for c in missing))
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
