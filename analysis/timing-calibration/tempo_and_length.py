"""Reads a timing-calibration run and separates two hypotheses about dispersion.

The constants in `MeasurementPolicy` were fitted on five takes at one tempo and
one traversal length. Two questions have since been asked of them that those
takes cannot answer, and they push the same direction, so a run that varies
only one of them cannot tell them apart:

- **tempo.** Dispersion is an interquartile range over a median, so the
  variation it allows shrinks in milliseconds as somebody plays faster. Whether
  real playing shrinks with it is the open question. If absolute spread stays
  flat from 60 to 120 while dispersion climbs, there is a constant component
  and the allowance needs an absolute floor.

- **length.** The quartile estimator takes `ordered[n // 4]` and
  `ordered[3 * n // 4]`, which spans the 17th to 83rd percentile of a
  seven-interval traversal and roughly the 25th to 75th of a twenty-nine
  interval one. Exercise length therefore changes what dispersion means before
  any playing is considered.

So this reports each take under both estimators. If a one-octave penalty
largely disappears under interpolated quartiles, the estimator is the thing to
fix, and fitting an absolute floor first would have baked an artifact into the
policy.

Usage:

    uv run analysis/timing-calibration/tempo_and_length.py <run.json>
"""

import itertools
import json
import statistics
import sys
from collections import defaultdict


def discrete_quartiles(values):
    """What the app computes today, in Dart and in `analyze.py`."""
    ordered = sorted(values)
    return ordered[len(ordered) // 4], ordered[3 * len(ordered) // 4]


def interpolated_quartiles(values):
    """A conventional 25th and 75th percentile, linearly interpolated."""
    ordered = sorted(values)
    lo, hi = statistics.quantiles(ordered, n=4, method="inclusive")[0::2]
    return lo, hi


def dispersion(intervals, quartiles):
    median = statistics.median(intervals)
    if median <= 0:
        return None
    low, high = quartiles(intervals)
    return (high - low) / median


def intervals_of(take):
    times = [note["ms"] for note in take["notes"]]
    return [b - a for a, b in itertools.pairwise(times)]


def main(path):
    with open(path) as file:
        run = json.load(file)
    rows = defaultdict(list)

    for take in run["takes"]:
        intervals = intervals_of(take)
        if len(intervals) < 4:
            continue
        median = statistics.median(intervals)
        discrete = dispersion(intervals, discrete_quartiles)
        interpolated = dispersion(intervals, interpolated_quartiles)
        low, high = discrete_quartiles(intervals)
        rows[(take["octaves"], take["tempo_bpm"])].append(
            {
                "median": median,
                "spread_ms": high - low,
                "discrete": discrete,
                "interpolated": interpolated,
                "n": len(intervals),
            }
        )

    print(
        f"{'span':>5} {'bpm':>5} {'n':>3} {'median':>8} {'spread':>8} "
        f"{'dispersion':>11} {'interpolated':>13}"
    )
    for octaves, bpm in sorted(rows):
        takes = rows[(octaves, bpm)]
        print(
            f"{octaves:5d} {bpm:5.0f} {len(takes):3d} "
            f"{statistics.mean(t['median'] for t in takes):8.0f} "
            f"{statistics.mean(t['spread_ms'] for t in takes):8.1f} "
            f"{statistics.mean(t['discrete'] for t in takes):11.3f} "
            f"{statistics.mean(t['interpolated'] for t in takes):13.3f}"
        )

    print()
    print("tempo at fixed length: does absolute spread stay flat while")
    print("dispersion climbs? that is the case for an absolute floor.")
    print("length at fixed tempo: does the one-octave penalty survive the")
    print("interpolated estimator? if not, fix the estimator first.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
