"""Timing calibration: what steady playing looks like on this stack.

Measurement turns matched-note onsets into two scores, and both need to know
where ordinary playing ends. This reports the two quantities they are built
from, per hand, for each recorded take:

- **dispersion**, the interquartile range of the inter-onset intervals over
  their median, which is what temporal stability reacts to;
- **the longest interval**, as a multiple of the upper quartile, which is what
  continuity reacts to.

Both are robust on purpose. A mean-based spread makes one long pause look like
unsteady playing, and measuring the longest gap against the median makes merely
uneven playing look interrupted, so the two scores would move together instead
of saying different things.

Reuses the takes recorded for onset grouping, and the same hand-and-degree
assignment, which is legitimate offline and forbidden to the production layer.

Run with `uv run --no-project python analysis/timing-calibration/analyze.py`.
"""

import json
import pathlib
import statistics as st
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "onset-grouping"))

from analyze import TAKES, assign, expected


def quartiles(values):
    """The lower and upper quartiles, interpolated, matching the Dart.

    Not ``ordered[n // 4]``: that index is a different percentile at every
    length, so exercise length changed what dispersion meant before any
    playing was considered.
    """
    lower, _, upper = st.quantiles(sorted(values), n=4, method="inclusive")
    return lower, upper


def per_hand(notes):
    tonic = min(n["note"] for n in notes)
    hands = assign(notes, expected(tonic), expected(tonic + 12))
    for hand in ("lh", "rh"):
        times = [hands[hand][p]["ms"] for p in sorted(hands[hand])]
        if len(times) < 4:
            continue
        intervals = [times[i + 1] - times[i] for i in range(len(times) - 1)]
        median = st.median(intervals)
        low, high = quartiles(intervals)
        yield hand, median, (high - low) / median, max(intervals) / high


def main():
    print(f"{'take':34} {'hand':4} {'median':>8} {'dispersion':>11} {'worst':>7}")
    for path in sorted(TAKES.glob("*.json")):
        take = json.loads(path.read_text())
        for hand, median, dispersion, worst in per_hand(take["notes"]):
            print(
                f"{take['label'][:34]:34} {hand:4} {median:7.0f}ms "
                f"{dispersion:11.3f} {worst:7.2f}"
            )


if __name__ == "__main__":
    main()
