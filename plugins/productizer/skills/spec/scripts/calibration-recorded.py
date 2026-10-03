#!/usr/bin/env python3
"""The measurement behind check-calibration-recorded.sh. See that file's header
for R50, R51, the record's schema, and what is not asserted.

Reads the declared checks and the calibration record, resolves every check's
EFFECTIVE severity the way the runner does (its own `severity` key, else
`defaults.severity`, else `block`), skips `enabled: false`, and for every
enabled blocking check prints one unindented verdict line - `upheld` or
`FINDING` - followed by indented detail. Notes about records that name no
blocking check are printed after, and are never findings.

Exit: 0 every enabled blocking check upheld, 1 at least one finding, 2 an input
that could not be read or parsed. The caller owns usage errors.
"""

import datetime
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - the caller probes for PyYAML first
    sys.stderr.write("check-calibration-recorded: PyYAML is not importable\n")
    raise SystemExit(2)

SHA_RX = re.compile(r"^[0-9a-f]{7,40}$")
DATE_RX = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
RULINGS = ("genuine", "false-positive")

# A ruling is a PERSON's. The same word list req-trailer.sh refuses in a
# Signed-off-by, plus the words an agent uses for itself. Word-boundaried, so
# `Roberta` is not `bot` and `Kai` is not `ai`.
AGENT_WORDS = ("claude", "anthropic", "gpt", "openai", "copilot", "cursor",
               "codeium", "codex", "gemini", "llm", "bot", "devin", "aider",
               "windsurf", "agent", "subagent", "assistant", "ai")


def refuse(msg):
    sys.stderr.write("check-calibration-recorded: %s\n" % msg)
    raise SystemExit(2)


def load(path, what):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return yaml.safe_load(fh)
    except OSError as exc:
        refuse("could not read the %s at %s: %s. Nothing was examined, so "
               "nothing is upheld - unmeasured, not clean." % (what, path, exc.strerror))
    except yaml.YAMLError as exc:
        refuse("the %s at %s is not parseable YAML: %s"
               % (what, path, str(exc).replace("\n", " ")))


def names_agent(value):
    for w in AGENT_WORDS:
        if re.search(r"(^|[^A-Za-z0-9])%s([^A-Za-z0-9]|$)" % re.escape(w), value, re.I):
            return w
    return None


def is_date(v):
    if isinstance(v, datetime.date):
        return True
    return isinstance(v, str) and bool(DATE_RX.match(v))


def is_count(v):
    return isinstance(v, int) and not isinstance(v, bool)


def short(sha):
    return str(sha)[:12]


def judge_measured_by(rec, problems):
    mb = rec.get("measured_by")
    if not isinstance(mb, dict):
        problems.append("malformed record: no `measured_by` - which tool, which "
                        "version and which day took this is not recorded")
        return
    for key in ("tool", "version"):
        if not isinstance(mb.get(key), (str, int, float)) or str(mb.get(key)).strip() == "":
            problems.append("malformed record: `measured_by.%s` is missing" % key)
    if not is_date(mb.get("date")):
        problems.append("malformed record: `measured_by.date` is missing or not YYYY-MM-DD")


def judge_measured(rec):
    """Returns (problems, summary, pending_lines)."""
    problems = []
    win = rec.get("window")
    commits = None
    span = "?"
    if not isinstance(win, dict):
        problems.append("malformed record: no `window` - the commit range the rate "
                        "was taken over is not recorded")
    else:
        for key in ("first", "last"):
            v = win.get(key)
            if not isinstance(v, str) or not SHA_RX.match(v):
                problems.append("malformed record: `window.%s` is not a commit sha" % key)
        commits = win.get("commits")
        if not is_count(commits) or commits < 1:
            problems.append("malformed record: `window.commits` is not a positive count")
            commits = None
        if win.get("history") not in ("empty", "clone"):
            problems.append("malformed record: `window.history` must be `empty` or `clone`")
        span = "%s..%s" % (short(win.get("first")), short(win.get("last")))

    verdicts = rec.get("verdicts")
    fires = rec.get("fires")
    if "verdicts" not in rec or verdicts is None:
        problems.append("malformed record: no verdict count (`verdicts`) - a fire "
                        "rate with no denominator is not a rate")
        verdicts = None
    elif not is_count(verdicts) or verdicts < 0:
        problems.append("malformed record: `verdicts` is not a count")
        verdicts = None
    elif verdicts == 0:
        problems.append("malformed record: zero verdicts is not a measured rate - "
                        "a check that returned no verdict was never calibrated, "
                        "and belongs in an `uncalibrated` record with that reason")
        verdicts = None
    elif commits is not None and verdicts > commits:
        problems.append("malformed record: %d verdicts over a window of %d commits"
                        % (verdicts, commits))

    if not is_count(fires) or fires < 0:
        problems.append("malformed record: no fire count (`fires`)")
        fires = None
    elif verdicts is not None and fires > verdicts:
        problems.append("malformed record: %d fires over %d verdicts" % (fires, verdicts))
        fires = None

    rate = rec.get("fire_rate")
    if fires is not None and verdicts is not None:
        want = "%d/%d = %.1f%%" % (fires, verdicts, 100.0 * fires / verdicts)
        if rate != want:
            problems.append("malformed record: `fire_rate` reads %r, and %d fires over "
                            "%d verdicts is %r" % (rate, fires, verdicts, want))

    judge_measured_by(rec, problems)

    rulings = rec.get("rulings")
    if rulings is None:
        rulings = []
    pending = []
    if not isinstance(rulings, list):
        problems.append("malformed record: `rulings` is not a list")
        rulings = []
    seen = set()
    ruled = 0
    for i, r in enumerate(rulings):
        if not isinstance(r, dict):
            problems.append("malformed record: rulings[%d] is not a mapping" % i)
            continue
        sha = r.get("commit")
        if not isinstance(sha, str) or not SHA_RX.match(sha):
            problems.append("malformed record: rulings[%d] names no commit sha" % i)
            continue
        if sha in seen:
            problems.append("malformed record: fire %s is ruled twice" % short(sha))
            continue
        seen.add(sha)
        kind = r.get("ruling")
        by = r.get("by")
        note = r.get("note")
        if kind == "pending":
            pending.append("fire %s is ruled `pending` - not a person's ruling, so it "
                           "does not count%s" % (short(sha),
                                                 (". Note: %s" % note) if note else ""))
            continue
        if kind not in RULINGS:
            problems.append("malformed record: fire %s has ruling %r; a ruling is "
                            "`genuine`, `false-positive` or `pending`" % (short(sha), kind))
            continue
        if not isinstance(by, str) or not by.strip():
            problems.append("fire %s is ruled %s with no `by` - a ruling nobody made "
                            "is not a person's ruling" % (short(sha), kind))
            continue
        agent = names_agent(by)
        if agent:
            problems.append("fire %s was ruled by %r, which names an agent (%s) - an "
                            "agent's judgement is not a person's ruling"
                            % (short(sha), by, agent))
            continue
        if not is_date(r.get("date")):
            problems.append("fire %s is ruled by %s with no `date` (YYYY-MM-DD)"
                            % (short(sha), by))
            continue
        ruled += 1
    if fires is not None:
        if len(seen) < fires:
            problems.append("%d of %d fire(s) in the window have no ruling at all"
                            % (fires - len(seen), fires))
        elif len(seen) > fires:
            problems.append("malformed record: %d rulings for %d fires" % (len(seen), fires))

    summary = "measured %s over %s commits (%s), %s of %s fire(s) ruled by a person" % (
        rate if isinstance(rate, str) else "?",
        commits if commits is not None else "?", span, ruled,
        fires if fires is not None else "?")
    return problems + pending, summary


def judge_uncalibrated(rec):
    problems = []
    reason = rec.get("reason")
    if not isinstance(reason, str) or not reason.strip():
        problems.append("malformed record: an uncalibrated record with no reason - "
                        "R51 records WHY the rate could not be measured")
    judge_measured_by(rec, problems)
    return problems, "uncalibrated (R51): %s" % (reason if isinstance(reason, str) else "?")


def main(argv):
    if len(argv) != 3:
        refuse("internal: the helper takes <checks.yaml> <calibration.yaml>")
    checks_fp, cal_fp = argv[1], argv[2]
    cfg = load(checks_fp, "declared checks")
    cal = load(cal_fp, "calibration record")

    if not isinstance(cfg, dict) or not isinstance(cfg.get("checks"), list):
        refuse("the declared checks at %s hold no `checks` list" % checks_fp)
    defaults = cfg.get("defaults") or {}
    if not isinstance(defaults, dict):
        refuse("`defaults` in %s is not a mapping" % checks_fp)
    if not isinstance(cal, dict) or not isinstance(cal.get("checks"), list):
        refuse("the calibration record at %s holds no `checks` list" % cal_fp)

    declared = {}
    order = []
    for i, chk in enumerate(cfg["checks"]):
        if not isinstance(chk, dict) or not isinstance(chk.get("id"), str) or not chk["id"]:
            refuse("checks[%d] in %s is not a mapping with an `id`" % (i, checks_fp))
        enabled = chk.get("enabled", True)
        if not isinstance(enabled, bool):
            refuse("%s.enabled must be true or false, not %r - the runner refuses "
                   "this config too" % (chk["id"], enabled))
        sev = chk.get("severity", defaults.get("severity", "block"))
        if sev not in ("block", "advise"):
            refuse("%s has effective severity %r; the runner knows `block` and "
                   "`advise` only" % (chk["id"], sev))
        declared[chk["id"]] = (enabled, sev)
        order.append(chk["id"])

    records = {}
    notes = []
    for i, rec in enumerate(cal["checks"]):
        if not isinstance(rec, dict) or not isinstance(rec.get("id"), str) or not rec["id"]:
            notes.append("calibration checks[%d] names no `id`, so it is nobody's "
                         "record and was not read" % i)
            continue
        records.setdefault(rec["id"], []).append(rec)

    blocking = [c for c in order if declared[c][0] and declared[c][1] == "block"]
    skipped_disabled = [c for c in order if not declared[c][0]]

    print("check-calibration-recorded: %d enabled blocking check(s) declared in %s; "
          "records read from %s" % (len(blocking), checks_fp, cal_fp))
    findings = 0
    for cid in blocking:
        recs = records.get(cid)
        if not recs:
            findings += 1
            print("FINDING  %s  no calibration record" % cid)
            print("    R50 needs its fire rate over merged history, its verdict count "
                  "and a person's ruling on every fire; R51, if no rate could be "
                  "measured, needs an `uncalibrated` record with the reason")
            continue
        if len(recs) > 1:
            findings += 1
            print("FINDING  %s  %d records - which one holds is ambiguous" % (cid, len(recs)))
            continue
        rec = recs[0]
        status = rec.get("status")
        if status == "measured":
            problems, summary = judge_measured(rec)
        elif status == "uncalibrated":
            problems, summary = judge_uncalibrated(rec)
        else:
            problems, summary = (["malformed record: `status` is %r; it is `measured` "
                                  "or `uncalibrated`" % (status,)], "status unknown")
        if problems:
            findings += 1
            print("FINDING  %s  %s" % (cid, summary))
            for p in problems:
                print("    %s" % p)
        else:
            print("upheld   %s  %s" % (cid, summary))

    for cid in sorted(records):
        if cid not in declared:
            notes.append("record for %r: checks.yaml declares no such check" % cid)
        elif not declared[cid][0]:
            notes.append("record for %r: the check is disabled, so its record is "
                         "not required" % cid)
        elif declared[cid][1] != "block":
            notes.append("record for %r: the check is not blocking (effective "
                         "severity %s), so its record is not required" % (cid, declared[cid][1]))
    if skipped_disabled:
        notes.append("skipped, enabled: false: %s" % ", ".join(skipped_disabled))
    if notes:
        print("notes - none of these is a finding")
        for n in notes:
            print("    NOTE  %s" % n)

    print("blocking checks examined: %d   upheld: %d   with findings: %d"
          % (len(blocking), len(blocking) - findings, findings))
    if findings:
        print("FAIL: %d of %d blocking check(s) lack a calibration record a person "
              "can stand behind" % (findings, len(blocking)))
        return 1
    print("PASS: every enabled blocking check has its calibration recorded")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
