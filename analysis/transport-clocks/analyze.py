#!/usr/bin/env python3
"""What a transport does with time, read off the traces rather than assumed.

Reports the six things that decide whether transport timestamps can become
performance timing, and whether one clock contract can cover every transport:

  tick unit and modulus     what a count is worth, and where it wraps
  simultaneity              whether one delivery keeps distinct stamps
  jitter                    how far a single interval disagrees
  drift                     whether the disagreement accumulates
  gaps                      the wrap ambiguity a silence can hide
  completeness              stamps that are absent or repeated

Nothing here corrects anything. A trace that disagrees with itself is a
finding, not something to smooth out.

Usage: analyze.py takes/*.json
"""

import itertools
import json
import math
import statistics
import sys
from pathlib import Path

# What a wrap looks like: the stamp went backward while arrival went forward.
# The modulus is then whatever makes the two clocks agree again.
KNOWN_MODULI = [8192, 16384, 32768, 65536, 1 << 24, 1 << 32]


def deliveries(trace):
    return [
        record
        for record in trace["records"]
        if record["kind"] == "delivery" and record.get("transport_ts") is not None
    ]


def wrap_estimates(rows):
    """What modulus each backward step implies, if arrival is roughly right."""
    estimates = []
    for before, after in itertools.pairwise(rows):
        raw = after["transport_ts"] - before["transport_ts"]
        if raw < 0:
            arrival = after["arrival_ms"] - before["arrival_ms"]
            estimates.append((before["seq"], after["seq"], arrival - raw))
    return estimates


def nearest_modulus(estimate):
    return min(KNOWN_MODULI, key=lambda candidate: abs(candidate - estimate))


def unwrap(rows, modulus):
    """The transport timeline, continued across its own wraps."""
    timeline = []
    epochs = 0
    for index, row in enumerate(rows):
        if index and row["transport_ts"] < rows[index - 1]["transport_ts"]:
            epochs += 1
        timeline.append(row["transport_ts"] + epochs * modulus)
    return timeline


def describe(path):
    trace = json.loads(Path(path).read_text())
    rows = deliveries(trace)
    platform = trace.get("platform", {})
    instrument = trace.get("instrument") or {}
    print(f"\n=== {Path(path).name}")
    print(
        f"    {trace.get('take')}  {platform.get('os')}  "
        f"{instrument.get('name')} over {instrument.get('transport')}"
        + (f"  ({trace['note']})" if trace.get("note") else "")
    )

    total = len(trace["records"])
    missing = total - len(rows)
    print(f"    {len(rows)} stamped deliveries, {missing} without a stamp")
    if not rows:
        return

    kinds = {}
    for record in trace["records"]:
        if record["kind"] == "delivery":
            kinds[record["message"]] = kinds.get(record["message"], 0) + 1
    unconsumed = kinds.get("other", 0)
    if unconsumed:
        print(
            f"    {unconsumed} of {len(rows)} deliveries are messages "
            f"KeyRecall does not consume"
        )

    estimates = wrap_estimates(rows)
    if estimates:
        values = [value for _, _, value in estimates]
        modulus = nearest_modulus(statistics.median(values))
        print(
            f"    wraps: {len(estimates)} at "
            f"{', '.join(str(value) for value in values)} "
            f"-> modulus {modulus}"
        )
    else:
        # Not a finding of "no modulus", only that this take did not reach it.
        modulus = None
        print("    wraps: none in this take, so no modulus is established")

    # What a count is actually worth. A clock counting something finer than it
    # resolves leaves every delta a multiple of the same number.
    steps = [
        abs(after["transport_ts"] - before["transport_ts"])
        for before, after in itertools.pairwise(rows)
    ]
    positive = [step for step in steps if step > 0]
    if positive:
        granularity = math.gcd(*positive) if len(positive) > 1 else positive[0]
        print(f"    granularity: every step is a multiple of {granularity}")

    timeline = (
        unwrap(rows, modulus) if modulus else [row["transport_ts"] for row in rows]
    )
    arrival = [row["arrival_ms"] for row in rows]

    # One tick is worth this many arrival milliseconds, over the whole take.
    span_transport = timeline[-1] - timeline[0]
    span_arrival = arrival[-1] - arrival[0]
    if span_transport:
        print(
            f"    tick: {span_arrival / span_transport:.6g} ms per count "
            f"over {span_arrival} ms"
        )

    scale = span_arrival / span_transport if span_transport else 1
    jitter = [
        round((arrival[i] - arrival[i - 1]) - (timeline[i] - timeline[i - 1]) * scale)
        for i in range(1, len(rows))
    ]
    if jitter:
        print(
            f"    jitter: {min(jitter)}..{max(jitter)} ms, "
            f"median {statistics.median(jitter):.0f}, "
            f"mean {statistics.mean(jitter):.1f}"
        )
    print(
        f"    drift: {span_arrival - round(span_transport * scale)} ms "
        f"over the take, after scaling"
    )

    # Simultaneity: what arrival collapses and the transport keeps apart.
    # Counted over notes only. A packet's worth of controller traffic sharing
    # one stamp is not the transport losing anything.
    collapsed = 0
    kept = 0
    groups = {}
    for row, stamp in zip(rows, timeline):
        if row["message"] in ("noteOn", "noteOff"):
            groups.setdefault(row["arrival_ms"], []).append(stamp)
    for stamps in groups.values():
        if len(stamps) > 1:
            collapsed += 1
            if len(set(stamps)) > 1:
                kept += 1
    print(
        f"    simultaneity: {collapsed} arrival instants carried several "
        f"notes, {kept} of them with distinct transport stamps"
    )

    # A silence long enough to hide a whole wrap cannot be unwrapped from the
    # stamps alone. This is the number the mapper's gap rule has to answer to.
    gaps = [arrival[i] - arrival[i - 1] for i in range(1, len(rows))]
    longest = max(gaps) if gaps else 0
    if modulus:
        risky = len([gap for gap in gaps if gap >= modulus])
        print(f"    gaps: longest silence {longest} ms, {risky} at or over the modulus")
    else:
        print(f"    gaps: longest silence {longest} ms, nothing to wrap past")

    repeats = sum(
        1
        for i in range(1, len(rows))
        if rows[i]["transport_ts"] == rows[i - 1]["transport_ts"]
    )
    print(f"    repeated stamps: {repeats}")

    onsets(rows, timeline, scale)


def onsets(rows, timeline, scale):
    """What the two clocks say about the playing, which is the whole point.

    Rhythm is read from intervals between strikes. If the transport timeline
    is the better witness, its intervals are the steadier ones for playing
    that was steady, and the difference is what delivery did rather than what
    anybody played.
    """
    strikes = [
        (row["arrival_ms"], stamp)
        for row, stamp in zip(rows, timeline)
        if row["message"] == "noteOn"
    ]
    if len(strikes) < 3:
        return

    by_arrival = [strikes[i][0] - strikes[i - 1][0] for i in range(1, len(strikes))]
    by_transport = [
        round((strikes[i][1] - strikes[i - 1][1]) * scale)
        for i in range(1, len(strikes))
    ]
    for label, series in (("arrival", by_arrival), ("transport", by_transport)):
        median = statistics.median(series)
        spread = statistics.median([abs(value - median) for value in series])
        print(
            f"    onsets by {label:9} median {median:6.0f} ms  "
            f"MAD {spread:5.1f}  range {min(series)}..{max(series)}"
        )


def main(paths):
    if not paths:
        print(__doc__)
        return 1
    for path in sorted(paths):
        describe(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
