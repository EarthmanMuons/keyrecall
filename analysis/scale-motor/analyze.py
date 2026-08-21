#!/usr/bin/env python3
"""Verify KeyRecall's V1 scale motor taxonomy and generate analysis CSVs.

Input:
    motor-realizations.yaml

Outputs:
    motor-realizations.csv
    technical-events.csv

The YAML is the preserved 96-record analysis dataset. This script independently
re-derives each record's motor realization from its compact canonical fingering
summary, verifies that all records are rotations of DIATONIC_3_4_CYCLE, checks
the stored derived fields, and generates the disposable CSV analysis artifacts.

Requires:
    Python 3.11+
    PyYAML

Usage:
    python analyze.py
    python analyze.py path/to/motor-realizations.yaml
    python analyze.py --input data.yaml --output-dir generated
"""

from __future__ import annotations

import argparse
import csv
from collections import Counter
from pathlib import Path
from typing import Any

import yaml

RH_BASE = (1, 2, 3, 1, 2, 3, 4)
LH_BASE = tuple(reversed(RH_BASE))
EXPECTED_RECORDS = 96

PITCH_CLASS = {
    "C": 0,
    "C#": 1,
    "Db": 1,
    "D": 2,
    "Eb": 3,
    "E": 4,
    "F": 5,
    "F#": 6,
    "Gb": 6,
    "G": 7,
    "G#": 8,
    "Ab": 8,
    "A": 9,
    "Bb": 10,
    "B": 11,
}

SCALE_INTERVALS = {
    "major": (0, 2, 4, 5, 7, 9, 11),
    "natural_minor": (0, 2, 3, 5, 7, 8, 10),
    "harmonic_minor": (0, 2, 3, 5, 7, 8, 11),
    # KeyRecall fixed-form/jazz melodic minor: raised 6 and 7 both ways.
    "melodic_minor": (0, 2, 3, 5, 7, 9, 11),
}

BLACK_PITCH_CLASSES = {1, 3, 6, 8, 10}


def rotations(seq: tuple[int, ...]) -> list[tuple[int, ...]]:
    return [seq[i:] + seq[:i] for i in range(len(seq))]


def parse_summary(summary: str) -> tuple[int, ...]:
    if len(summary) != 8 or any(ch not in "12345" for ch in summary):
        raise ValueError(f"Invalid fingering summary: {summary!r}")
    return tuple(int(ch) for ch in summary)


def derive_realization(summary: str, hand: str) -> dict[str, Any]:
    """Derive continuation phase/boundaries from an 8-note display summary.

    The first digit is the initial tonic. Digits 2..7 expose the first six
    positions of the seven-note continuation cycle. Matching those six
    positions against rotations of the hand's canonical cycle uniquely
    identifies phase. The eighth digit is the terminal tonic and is compared
    with the inferred cycle's final position.
    """
    fingers = parse_summary(summary)
    base = RH_BASE if hand == "RH" else LH_BASE

    entry = fingers[0]
    observed_cycle_prefix = fingers[1:7]

    matches = [
        (phase, cycle)
        for phase, cycle in enumerate(rotations(base))
        if cycle[:6] == observed_cycle_prefix
    ]

    if len(matches) != 1:
        raise ValueError(
            f"{hand} {summary}: expected one cycle-phase match, got {matches}"
        )

    phase, cycle = matches[0]
    terminal = fingers[-1]

    return {
        "entry": entry,
        "cycle": cycle,
        "phase": phase,
        "entry_override": entry if entry != cycle[-1] else None,
        "terminal_override": terminal if terminal != cycle[-1] else None,
    }


def normalize_optional_int(value: Any) -> int | None:
    if value in (None, "", False):
        return None
    return int(value)


def verify_record(record: dict[str, Any]) -> dict[str, Any]:
    derived = derive_realization(record["display_summary"], record["hand"])

    if record.get("motor_family") != "DIATONIC_3_4_CYCLE":
        raise AssertionError(
            f"{record['form']} {record['tonic']} {record['hand']}: "
            f"unexpected motor family {record.get('motor_family')!r}"
        )

    expected_orientation = (
        "RH_ASCENDING" if record["hand"] == "RH" else "LH_ASCENDING_REVERSED"
    )
    if record.get("orientation") != expected_orientation:
        raise AssertionError(
            f"{record['form']} {record['tonic']} {record['hand']}: orientation mismatch"
        )

    stored_cycle = tuple(int(x) for x in record["cycle"])
    checks = {
        "entry": int(record["entry"]),
        "cycle": stored_cycle,
        "phase": int(record["phase"]),
        "entry_override": normalize_optional_int(record.get("entry_override")),
        "terminal_override": normalize_optional_int(record.get("terminal_override")),
    }

    for field, stored in checks.items():
        if stored != derived[field]:
            raise AssertionError(
                f"{record['form']} {record['tonic']} {record['hand']}: "
                f"{field} stored={stored!r}, derived={derived[field]!r}"
            )

    return {**record, **derived}


def key_class(pitch: int) -> str:
    return "BLACK" if pitch % 12 in BLACK_PITCH_CLASSES else "WHITE"


def generate_fingers(record: dict[str, Any], octaves: int = 2) -> list[int]:
    fingers = [record["entry"]]
    for _ in range(octaves):
        fingers.extend(record["cycle"])
    if record["terminal_override"] is not None:
        fingers[-1] = record["terminal_override"]
    return fingers


def generate_pitches(tonic: str, form: str, octaves: int = 2) -> list[int]:
    tonic_pc = PITCH_CLASS[tonic]
    intervals = SCALE_INTERVALS[form]

    pitches: list[int] = []
    for octave in range(octaves):
        pitches.extend(tonic_pc + interval + 12 * octave for interval in intervals)
    pitches.append(tonic_pc + 12 * octaves)
    return pitches


def crossing_kind(
    hand: str, direction: str, from_finger: int, to_finger: int
) -> str | None:
    if 1 not in (from_finger, to_finger):
        return None

    other = to_finger if from_finger == 1 else from_finger
    if other not in (3, 4):
        return None

    if hand == "RH":
        if direction == "ASC":
            motion = "THUMB_UNDER" if to_finger == 1 else "FINGER_OVER"
        else:
            motion = "FINGER_OVER" if from_finger == 1 else "THUMB_UNDER"
    else:
        if direction == "ASC":
            motion = "FINGER_OVER" if from_finger == 1 else "THUMB_UNDER"
        else:
            motion = "THUMB_UNDER" if to_finger == 1 else "FINGER_OVER"

    return f"{motion}_{other}"


def generate_events(
    records: list[dict[str, Any]], octaves: int = 2
) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []

    for record in records:
        fingers = generate_fingers(record, octaves)
        pitches = generate_pitches(record["tonic"], record["form"], octaves)

        if len(fingers) != len(pitches):
            raise AssertionError(
                f"Length mismatch for {record['form']} "
                f"{record['tonic']} {record['hand']}"
            )

        streams = (
            ("ASC", fingers, pitches),
            ("DESC", list(reversed(fingers)), list(reversed(pitches))),
        )

        for direction, fs, ps in streams:
            for i, (f1, f2, p1, p2) in enumerate(zip(fs, fs[1:], ps, ps[1:])):
                interval = abs(p2 - p1)
                events.append(
                    {
                        "form": record["form"],
                        "tonic": record["tonic"],
                        "hand": record["hand"],
                        "direction": direction,
                        "index": i,
                        "from_finger": f1,
                        "to_finger": f2,
                        "from_key_class": key_class(p1),
                        "to_key_class": key_class(p2),
                        "interval_semitones": interval,
                        "octave_boundary": (i + 1) % 7 == 0,
                        "crossing": crossing_kind(record["hand"], direction, f1, f2)
                        or "",
                    }
                )

    return events


def write_realizations_csv(path: Path, records: list[dict[str, Any]]) -> None:
    fields = [
        "form",
        "tonic",
        "hand",
        "display_summary",
        "motor_family",
        "orientation",
        "phase",
        "entry",
        "cycle",
        "entry_override",
        "terminal_override",
    ]

    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        for record in records:
            row = dict(record)
            row["cycle"] = "".join(str(x) for x in record["cycle"])
            writer.writerow({field: row.get(field) for field in fields})


def write_events_csv(path: Path, events: list[dict[str, Any]]) -> None:
    if not events:
        return
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(events[0]))
        writer.writeheader()
        writer.writerows(events)


def report(records: list[dict[str, Any]], events: list[dict[str, Any]]) -> None:
    families = {record["motor_family"] for record in records}
    rh_cycles = {tuple(record["cycle"]) for record in records if record["hand"] == "RH"}
    lh_cycles = {tuple(record["cycle"]) for record in records if record["hand"] == "LH"}

    phase_counts = Counter((r["hand"], r["phase"]) for r in records)
    boundary_counts = Counter(
        (
            bool(r["entry_override"]),
            bool(r["terminal_override"]),
        )
        for r in records
    )

    event_signatures = {
        (
            e["hand"],
            e["direction"],
            e["from_finger"],
            e["to_finger"],
            e["from_key_class"],
            e["to_key_class"],
            e["interval_semitones"],
            e["octave_boundary"],
            e["crossing"],
        )
        for e in events
    }

    crossing_signatures = {
        (
            e["hand"],
            e["direction"],
            e["crossing"],
            e["from_key_class"],
            e["to_key_class"],
            e["interval_semitones"],
            e["octave_boundary"],
        )
        for e in events
        if e["crossing"]
    }

    crossing_counts = Counter(e["crossing"] for e in events if e["crossing"])
    geometry_counts = Counter(
        (e["from_key_class"], e["to_key_class"]) for e in events if e["crossing"]
    )
    interval_counts = Counter(e["interval_semitones"] for e in events if e["crossing"])

    print(f"Verified records: {len(records)}")
    print(f"Motor families required: {len(families)}")
    print(f"Distinct RH continuation cycles: {len(rh_cycles)}")
    print(f"Distinct LH continuation cycles: {len(lh_cycles)}")
    print(f"Distinct technical-event signatures: {len(event_signatures)}")
    print(f"Distinct crossing signatures: {len(crossing_signatures)}")
    print()

    print("Phase distribution:")
    for key, count in sorted(phase_counts.items()):
        print(f"  {key[0]} phase {key[1]}: {count}")
    print()

    print("Boundary patterns (entry_override, terminal_override):")
    for key, count in sorted(boundary_counts.items()):
        print(f"  {key}: {count}")
    print()

    print("Crossing opportunities:")
    for key, count in sorted(crossing_counts.items()):
        print(f"  {key}: {count}")
    print()

    print("Crossing key geometry:")
    for key, count in sorted(geometry_counts.items()):
        print(f"  {key[0]} -> {key[1]}: {count}")
    print()

    print("Crossing intervals:")
    for interval, count in sorted(interval_counts.items()):
        print(f"  {interval} semitone(s): {count}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "yaml",
        nargs="?",
        type=Path,
        help="Input YAML (default: motor-realizations.yaml)",
    )
    parser.add_argument(
        "--input",
        dest="input_path",
        type=Path,
        help="Explicit input YAML path",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).with_name("generated"),
        help="Directory for generated CSVs (default: ./generated)",
    )
    parser.add_argument(
        "--octaves",
        type=int,
        default=2,
        help="Octaves used for technical-event generation (default: 2)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if args.octaves < 1:
        raise SystemExit("--octaves must be >= 1")

    input_path = (
        args.input_path
        or args.yaml
        or Path(__file__).with_name("motor-realizations.yaml")
    )
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    with input_path.open(encoding="utf-8") as fh:
        data = yaml.safe_load(fh)

    raw_records = data.get("records", [])
    if len(raw_records) != EXPECTED_RECORDS:
        raise AssertionError(
            f"Expected {EXPECTED_RECORDS} records, found {len(raw_records)}"
        )

    records = [verify_record(record) for record in raw_records]
    events = generate_events(records, args.octaves)

    realizations_csv = output_dir / "motor-realizations.csv"
    events_csv = output_dir / "technical-events.csv"

    write_realizations_csv(realizations_csv, records)
    write_events_csv(events_csv, events)
    report(records, events)

    print()
    print(f"Wrote {realizations_csv}")
    print(f"Wrote {events_csv}")


if __name__ == "__main__":
    main()
