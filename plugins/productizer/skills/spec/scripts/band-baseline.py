#!/usr/bin/env python3
"""band-baseline.py - the window and tier arithmetic the band detection
commands share, loaded by path by band-revert-rate.py and band-review-rounds.py
so the two metrics are measured against their baseline one way. No CLI.

A band's value is measured over the WINDOW of the last DAYS days ending at NOW,
and its baseline is the same metric over the COUNT windows of DAYS days before
it, end to end. The tier is how far the value sits ABOVE the baseline's mean,
in the baseline's sample standard deviations: under 1 is within band, then
1sigma, 2sigma, 3sigma - the tiers bands.yaml names. Only a rise is a breach:
both metrics are worse when higher, and a drop in review rounds is what the
revert-rate band is there to watch.

NOT MEASURED, never a guess:
  - the current window holds nothing to measure (the metric says what)
  - fewer than MIN_BASELINE earlier windows hold a value
  - the earlier windows have no spread and the value sits above their mean,
    so how many deviations it sits there is undefined
The Western Electric run rules over several windows are not evaluated: one
point, one distance.
"""
import datetime
import statistics

MIN_BASELINE = 3
TIERS = ((3.0, "3sigma"), (2.0, "2sigma"), (1.0, "1sigma"))


class NotMeasured(Exception):
    pass


def windows(now, days, count):
    """[(start, end)] epoch seconds, end inclusive: index 0 is the current
    window, 1..count the earlier ones."""
    width = days * 86400
    return [(now - (k + 1) * width, now - k * width) for k in range(count + 1)]


def inside(t, window):
    return window[0] < t <= window[1]


def classify(value, earlier):
    """{mean, sd, sigma, tier, n} of a value against the earlier windows'
    values (None for a window with nothing to measure)."""
    have = [v for v in earlier if v is not None]
    if len(have) < MIN_BASELINE:
        raise NotMeasured("%d earlier window(s) hold a value, fewer than %d to make a baseline"
                          % (len(have), MIN_BASELINE))
    mean = statistics.mean(have)
    sd = statistics.stdev(have)
    if sd == 0:
        if value > mean:
            raise NotMeasured("the %d earlier windows all read %.4f and this one %.4f: no spread to measure "
                              "the rise in" % (len(have), mean, value))
        return {"mean": mean, "sd": sd, "sigma": 0.0, "tier": "within", "n": len(have)}
    sigma = (value - mean) / sd
    tier = "within"
    for bound, name in TIERS:
        if sigma >= bound:
            tier = name
            break
    return {"mean": mean, "sd": sd, "sigma": sigma, "tier": tier, "n": len(have)}


def stamp(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def report(tool, metric, days, now, rows, empty):
    """(exit code, lines). rows: [(label, value or None)] for windows 0..count,
    each label naming what was counted; empty names what a window with no
    value lacks."""
    out = ["%s: metric %s, window %d day(s) ending %s" % (tool, metric, days, stamp(now))]
    for k, (label, value) in enumerate(rows):
        shown = "%.4f" % value if value is not None else "nothing to measure"
        out.append("  window %d%s: %s = %s" % (k, " (current)" if k == 0 else "", label, shown))
    current = rows[0][1]
    if current is None:
        return 3, out + ["NOT MEASURED: the current window holds %s" % empty]
    out.append("value: %.4f" % current)
    try:
        b = classify(current, [v for _, v in rows[1:]])
    except NotMeasured as exc:
        return 3, out + ["NOT MEASURED: %s" % exc]
    out.append("baseline: %d earlier window(s) with a value, mean %.4f, sd %.4f" % (b["n"], b["mean"], b["sd"]))
    out.append("sigma: %+.2f" % b["sigma"])
    out.append("tier: %s" % b["tier"])
    return 0, out


def parse_args(args, extra):
    """{days, windows, now, extra keys} from argv, or None on bad usage."""
    opts = {"days": 30, "windows": 6, "now": None}
    opts.update(extra)
    while args:
        a = args.pop(0)
        key = a[2:] if a.startswith("--") else None
        if key not in opts or not args:
            return None
        val = args.pop(0)
        if key in ("days", "windows"):
            if not val.isdigit() or int(val) < 1:
                return None
            opts[key] = int(val)
        elif key == "now":
            try:
                opts["now"] = int(val)
            except ValueError:
                return None
        else:
            opts[key] = val
    return opts
