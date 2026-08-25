"""Onset grouping calibration: how far apart do hands-together notes arrive?

Reads the takes recorded by the app's onset diagnostic and reports the two
distributions a grouping stage would have to separate: the gap between the two
notes of one intended moment, and the gap between one moment and the next.

Run with `uv run --no-project python analysis/onset-grouping/analyze.py`.

Every take here is a major scale, one octave, hands together in octaves, up and
back down. Matching an observation to a hand and a scale degree uses that
knowledge, which is legitimate offline: the point is to measure what the
grouping stage would face, and the grouping stage itself is never allowed to
know any of it.
"""

import itertools
import json
import pathlib
import statistics as st

MAJOR = [0, 2, 4, 5, 7, 9, 11]
TAKES = pathlib.Path(__file__).parent / "takes"

# How far ahead in a hand's expected sequence to look when an observation does
# not match the next note, so a skipped note does not derail the whole walk.
LOOKAHEAD = 3


def expected(tonic):
    """One octave up and back down, the apex played once."""
    up = [tonic + i for i in MAJOR] + [tonic + 12]
    return up + up[-2::-1]


def assign(notes, lh_seq, rh_seq):
    """Assign each observation to a hand and a position in that hand's scale."""
    index = {"lh": 0, "rh": 0}
    seqs = {"lh": lh_seq, "rh": rh_seq}
    out = {"lh": {}, "rh": {}}

    for note in notes:
        matches = []
        for hand in ("lh", "rh"):
            seq, at = seqs[hand], index[hand]
            for ahead in range(min(LOOKAHEAD, len(seq) - at)):
                if seq[at + ahead] == note["note"]:
                    matches.append((ahead, hand, at + ahead))
                    break
        if not matches:
            continue
        # Prefer the hand that needs no skip, then the one lagging behind.
        matches.sort(key=lambda m: (m[0], index[m[1]]))
        _, hand, position = matches[0]
        out[hand][position] = note
        index[hand] = position + 1
    return out


def quantiles(values):
    ordered = sorted(values)
    return (
        ordered[0],
        st.median(ordered),
        ordered[int(len(ordered) * 0.9)] if len(ordered) > 1 else ordered[0],
        ordered[-1],
    )


def analyze(path):
    take = json.loads(path.read_text())
    notes = take["notes"]
    tonic = min(n["note"] for n in notes)
    hands = assign(notes, expected(tonic), expected(tonic + 12))

    positions = sorted(set(hands["lh"]) & set(hands["rh"]))
    deltas = [hands["rh"][p]["ms"] - hands["lh"][p]["ms"] for p in positions]
    starts = sorted(min(hands["lh"][p]["ms"], hands["rh"][p]["ms"]) for p in positions)
    steps = [starts[i + 1] - starts[i] for i in range(len(starts) - 1)]

    # The case a timing threshold cannot survive: two observations close enough
    # in time to look simultaneous that belong to different moments.
    where = {}
    for hand in ("lh", "rh"):
        for position, note in hands[hand].items():
            where[id(note)] = position
    confusable = []
    for a, b in itertools.pairwise(notes):
        if b["ms"] - a["ms"] > 50:
            continue
        pa, pb = where.get(id(a)), where.get(id(b))
        if pa is not None and pb is not None and pa != pb:
            confusable.append((a["note"], b["note"], b["ms"] - a["ms"], pa, pb))

    return {
        "label": take["label"],
        "notes": len(notes),
        "moments": len(positions),
        "pair_gaps": [abs(d) for d in deltas],
        "steps": steps,
        "lh_leads": sum(1 for d in deltas if d > 0),
        "rh_leads": sum(1 for d in deltas if d < 0),
        "ties": sum(1 for d in deltas if d == 0),
        "confusable": confusable,
    }


def main():
    results = [analyze(p) for p in sorted(TAKES.glob("*.json"))]

    for r in results:
        lo, med, p90, hi = quantiles(r["pair_gaps"])
        slo, smed, _, shi = quantiles(r["steps"])
        print(f"\n=== {r['label']}")
        print(f"  {r['notes']} notes, {r['moments']} moments matched")
        print(f"  pair gap ms:  min {lo}  median {med}  p90 {p90}  max {hi}")
        print(f"                all: {sorted(r['pair_gaps'])}")
        print(f"  step gap ms:  min {slo}  median {smed}  max {shi}")
        print(
            f"  leads: LH {r['lh_leads']}  RH {r['rh_leads']}  "
            f"same millisecond {r['ties']}"
        )
        verdict = "OVERLAP" if hi >= slo else "separable"
        print(f"  widest pair {hi} vs shortest step {slo}: {verdict}")
        if r["confusable"]:
            print(f"  within 50ms but different moments: {r['confusable']}")

    pairs = [g for r in results for g in r["pair_gaps"]]
    steps = [s for r in results for s in r["steps"]]
    print(f"\n=== pooled: {len(pairs)} pairs, {len(steps)} steps")
    print("  absolute threshold sweep")
    for t in (25, 40, 50, 75, 100, 120, 150, 200):
        split = sum(1 for g in pairs if g > t)
        merge = sum(1 for s in steps if s <= t)
        print(
            f"    T={t:4}ms  moments torn apart {split:3}/{len(pairs)}   "
            f"moments glued together {merge:3}/{len(steps)}"
        )

    # Tested and did not help: normalizing by the take's own median step, in
    # case the tolerance scales with tempo rather than being absolute.
    print("  relative threshold sweep, gap as a fraction of the median step")
    rel_pairs, rel_steps = [], []
    for r in results:
        median_step = st.median(r["steps"])
        rel_pairs += [g / median_step for g in r["pair_gaps"]]
        rel_steps += [s / median_step for s in r["steps"]]
    for f in (0.15, 0.25, 0.35, 0.5, 0.6):
        split = sum(1 for g in rel_pairs if g > f)
        merge = sum(1 for s in rel_steps if s <= f)
        print(
            f"    F={f:4}   moments torn apart {split:3}/{len(rel_pairs)}   "
            f"moments glued together {merge:3}/{len(rel_steps)}"
        )

    simultaneous = sum(r["ties"] for r in results)
    print(f"\n  arrivals in the same millisecond: {simultaneous}")
    print(
        "  takes where a timing threshold would confidently group notes from "
        f"different moments: {sum(1 for r in results if r['confusable'])}"
        f"/{len(results)}"
    )


if __name__ == "__main__":
    main()
