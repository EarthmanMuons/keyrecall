#!/usr/bin/env python3
"""Compute the cross-language discrete trace digest from the Python prototype.

The prototype under analysis/ is the reference implementation of the V1 model.
This produces the digest that packages/keyrecall_simulation pins, over exactly
the fields discreteTraceDigest() hashes in Dart: the categorical decisions and
outcomes of a run, and no floating-point value.

Floats are deliberately excluded. The two implementations agree on them only to
about 1e-11 relative, mostly because Dart carries real DateTime timestamps and
rounds the activation anchor to the microsecond while this prototype uses an
unbounded float day count. Rounding those merely to force hash equality would
make the digest less principled than the tolerance comparison beside it.

Usage:
    python3 tool/reference_digest.py --profile advanced --attempts 80 --seed 4
    python3 tool/reference_digest.py --all
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

LEARNER_MODEL = Path(__file__).resolve().parent.parent / "analysis" / "learner-model"
sys.path.insert(0, str(LEARNER_MODEL))

from params import load_params  # noqa: E402
from simulate import run  # noqa: E402
from synthetic import PROFILES  # noqa: E402

# Schema tag, hashed as the first line so the digest is a statement about a
# named record shape rather than about whatever the trace happens to carry.
# Must match discreteDigestSchema in packages/keyrecall_simulation.
SCHEMA = "reference-digest-v1"

# The fields hashed, in order. Must match discreteDigestFields in
# packages/keyrecall_simulation; bump SCHEMA on both sides to change it.
FIELDS = (
    "attempt_index",
    "material_id",
    "hands",
    "octaves",
    "direction",
    "tempo_bpm",
    "guidance_independence",
    "opportunities",
    "started",
    "completed",
    "retrieval",
)

# The runs keyrecall_simulation pins. Keep in step with trace_digest_test.
PINNED_RUNS = (
    ("advanced", 80, 4),
    ("beginner", 80, 4),
    ("returning", 80, 4),
    ("technique_strong_memory_weak", 80, 4),
)


def _discrete_number(value: float) -> str:
    """Integral values print as integers, matching the Dart formatter."""
    return str(int(value)) if float(value).is_integer() else repr(float(value))


def _independence(guidance: dict) -> int:
    """Collapse the two guidance flags onto the support ladder.

    Cues left visible supply the material whether or not the notes were also
    previewed first, so that combination is the same rung as continuous cueing.
    """
    if guidance["concurrent_pitch_cues"]:
        return 0
    if guidance["notes_previewed"]:
        return 1
    return 2


def _discrete_line(index: int, record: dict, retrieval_succeeded: bool | None) -> str:
    """One record, encoded exactly as the Dart builder encodes it.

    Records are flat: no field contains the separator, so two different records
    can never encode to the same line.
    """
    exercise = record["exercise"]
    fields = (
        str(index),
        exercise["material_id"],
        exercise["hands"],
        str(exercise["octaves"]),
        exercise["direction"],
        _discrete_number(exercise["tempo_bpm"]),
        str(_independence(exercise["guidance"])),
        ",".join(sorted(exercise["opportunities"])),
        str(record["outcome"]["started"]).lower(),
        str(record["outcome"]["completed"]).lower(),
        "null" if retrieval_succeeded is None else str(retrieval_succeeded).lower(),
    )
    assert len(fields) == len(FIELDS), "record does not match the declared schema"
    return "|".join(fields)


def digest(profile: str, attempts: int, seed: int) -> str:
    params = load_params()

    # run()'s JSON-lines trace omits retrieval_succeeded, so collect the real
    # Outcome objects through its own observation hook rather than editing the
    # prototype to widen the trace.
    outcomes: list = []
    trace, _state, _truth = run(
        profile,
        attempts=attempts,
        seed=seed,
        params=params,
        agent_on_outcome=lambda _exercise, outcome, _now: outcomes.append(outcome),
    )

    lines = [
        _discrete_line(index, record, outcome.retrieval_succeeded)
        for index, (record, outcome) in enumerate(zip(trace, outcomes, strict=True))
    ]
    return hashlib.sha256("\n".join([SCHEMA, *lines]).encode("utf-8")).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=sorted(PROFILES))
    parser.add_argument("--attempts", type=int, default=80)
    parser.add_argument("--seed", type=int, default=4)
    parser.add_argument(
        "--all", action="store_true", help="Print every pinned run's digest."
    )
    args = parser.parse_args()

    if args.all:
        for profile, attempts, seed in PINNED_RUNS:
            print(f"{profile:<32} {attempts:>4} {seed:>3}  {digest(profile, attempts, seed)}")
        return

    if args.profile is None:
        parser.error("--profile is required unless --all is given")
    print(digest(args.profile, args.attempts, args.seed))


if __name__ == "__main__":
    main()
