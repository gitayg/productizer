#!/usr/bin/env python3
"""Runs per arm needed to detect a pass-rate difference, by exact Fisher power.

The run plan in `hard-preregistration.md` quotes its n from this file, not from
memory. No model is called and nothing is read from disk.

Power is computed exactly, not simulated: for runs n per arm and true pass rates
p1 (bare) and p2 (plugin), it sums the probability of every 2x2 outcome whose
two-sided Fisher exact p-value is below alpha. Exact power is a sawtooth in n,
so the n printed is the smallest n on a coarse-then-fine search that reaches the
target power; a neighbouring n can dip just below it. The normal-approximation n
is printed beside it so the two can be compared.

Before any power is computed, the Fisher implementation is checked against the
figure already published for P03 in the backlog (3/10 against 5/10 gives
p = 0.6499). If that check fails, nothing else is printed and it exits 1.

Usage:
    hard-power.py                 the scenario table
    hard-power.py P1 P2           one scenario, e.g. hard-power.py 0.625 0.75
"""

from __future__ import annotations

import math
import sys

ALPHA = 0.05
TARGET = 0.80


def log_choose(n: int, k: int) -> float:
    return math.lgamma(n + 1) - math.lgamma(k + 1) - math.lgamma(n - k + 1)


def fisher_pvalues(n1: int, n2: int, k: int) -> dict[int, float]:
    """Two-sided Fisher p-value for every x (passes in arm 1) given k total passes."""
    lo, hi = max(0, k - n2), min(k, n1)
    logden = log_choose(n1 + n2, k)
    pmf = {x: math.exp(log_choose(n1, x) + log_choose(n2, k - x) - logden)
           for x in range(lo, hi + 1)}
    out = {}
    for x, px in pmf.items():
        out[x] = min(1.0, sum(p for p in pmf.values() if p <= px * (1 + 1e-7)))
    return out


def fisher(x1: int, n1: int, x2: int, n2: int) -> float:
    return fisher_pvalues(n1, n2, x1 + x2)[x1]


def binom_pmf(n: int, p: float) -> list[float]:
    return [math.exp(log_choose(n, x) + x * math.log(p) + (n - x) * math.log1p(-p))
            for x in range(n + 1)]


def power(n: int, p1: float, p2: float) -> float:
    b1, b2 = binom_pmf(n, p1), binom_pmf(n, p2)
    cache: dict[int, dict[int, float]] = {}
    total = 0.0
    for x in range(n + 1):
        for y in range(n + 1):
            k = x + y
            if k not in cache:
                cache[k] = fisher_pvalues(n, n, k)
            if cache[k][x] < ALPHA:
                total += b1[x] * b2[y]
    return total


def normal_n(p1: float, p2: float) -> int:
    za, zb = 1.959964, 0.841621
    pbar = (p1 + p2) / 2
    num = za * math.sqrt(2 * pbar * (1 - pbar)) + zb * math.sqrt(p1 * (1 - p1) + p2 * (1 - p2))
    return math.ceil((num / (p2 - p1)) ** 2)


def exact_n(p1: float, p2: float) -> int:
    n = max(10, normal_n(p1, p2) // 2)
    while power(n, p1, p2) < TARGET:
        n += 10
    while n > 10 and power(n - 1, p1, p2) >= TARGET:
        n -= 1
    return n


def main() -> int:
    got = fisher(3, 10, 5, 10)
    if abs(got - 0.6499) > 0.0005:
        print(f"Fisher check FAILED: 3/10 vs 5/10 gave {got:.4f}, published 0.6499", file=sys.stderr)
        return 1
    print(f"Fisher check: 3/10 vs 5/10 -> p = {got:.4f} (published 0.6499)\n")
    if len(sys.argv) == 3:
        scenarios = [(float(sys.argv[1]), float(sys.argv[2]))]
    else:
        scenarios = [(0.625, 0.75), (0.70, 0.85), (0.60, 0.80), (0.50, 0.75), (0.40, 0.70)]
    print(f"two-sided alpha {ALPHA}, power {TARGET:.0%}")
    print(f"{'bare':>6} {'plugin':>7} {'normal n/arm':>13} {'exact n/arm':>12} {'power at exact n':>17}")
    for p1, p2 in scenarios:
        n = exact_n(p1, p2)
        print(f"{p1:>6.3f} {p2:>7.3f} {normal_n(p1, p2):>13} {n:>12} {power(n, p1, p2):>17.3f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
