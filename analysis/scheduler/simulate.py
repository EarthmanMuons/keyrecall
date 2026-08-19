#!/usr/bin/env python3
"""CLI: run the scheduler pipeline once against a scripted LearnerState/
SessionState and emit a JSON-lines trace of every candidate's full
CandidateTrace - predictions, eligibility, challenge, and priority
components, real and counterfactual alike.

No longitudinal loop yet (that's Pass 2, docs/learner-model/
04-v1-scheduler.md §10); this exercises one scheduling decision at a
time. See invariants.py for the boundary properties this pipeline should
satisfy.

Usage:
    python simulate.py --learner beginner --session cold-start
    python simulate.py --learner advanced --session post-failure --out trace.jsonl
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "learner-model"))

from candidates import (
    InstrumentProfile,
    SessionState,
    generate_candidates,
)
from config import Params as SchedulerParams
from config import load_params as load_scheduler_params
from params import load_params as load_learner_params
from pipeline import CandidateTrace, run_pipeline, select_next
from simulate import MATERIALS, initial_state
from synthetic import PROFILES

SESSION_PRESET_NAMES = (
    "cold-start",
    "mid-session",
    "post-failure",
    "session-cap-reached",
)


def _session_presets(scheduler_params: SchedulerParams) -> dict[str, SessionState]:
    """session-cap-reached reads the cap from the loaded scheduler_params
    rather than hardcoding it, so it still means what its name says under
    --scheduler-params pointing at a non-default config.toml."""
    return {
        "cold-start": SessionState(),
        "mid-session": SessionState(
            attempts_this_session=10,
            recent_material_ids=["C_MAJOR", "C_MAJOR", "G_MAJOR"],
        ),
        "post-failure": SessionState(attempts_this_session=5, last_outcome_failed=True),
        "session-cap-reached": SessionState(
            attempts_this_session=scheduler_params.safety.max_session_attempts
        ),
    }


def _trace_to_dict(trace: CandidateTrace) -> dict:
    exercise = trace.exercise
    return {
        "exercise": {
            "material_id": exercise.material.material_id,
            "hands": exercise.hands,
            "octaves": exercise.octaves,
            "direction": exercise.direction,
            "tempo_bpm": exercise.tempo_bpm,
            "guidance": {
                "notes_previewed": exercise.guidance.notes_previewed,
                "concurrent_pitch_cues": exercise.guidance.concurrent_pitch_cues,
            },
        },
        "eligibility_tier": trace.eligibility_tier,
        "eligibility_reason": trace.eligibility_reason,
        "safety_allowed": trace.safety_allowed,
        "safety_reason": trace.safety_reason,
        "challenge_status": trace.challenge_status.value,
        "prediction": dataclasses.asdict(trace.prediction)
        | {"overall_p": trace.prediction.overall_p},
        "challenge_within_band": trace.challenge_within_band,
        "challenge_bypass": trace.challenge_bypass,
        "challenge_survived": trace.challenge_survived,
        "priority_status": trace.priority_status.value,
        "retention": trace.retention,
        "information": trace.information,
        "diversity": trace.diversity,
        "goals": trace.goals,
        "rank_key": trace.rank_key,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--learner", required=True, choices=sorted(PROFILES))
    parser.add_argument(
        "--session", default="cold-start", choices=sorted(SESSION_PRESET_NAMES)
    )
    parser.add_argument("--now", type=float, default=0.0)
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--learner-params", type=Path, default=None)
    parser.add_argument("--scheduler-params", type=Path, default=None)
    args = parser.parse_args()

    learner_params = load_learner_params(args.learner_params)
    scheduler_params = load_scheduler_params(args.scheduler_params)

    profile = PROFILES[args.learner]
    state = initial_state(profile, learner_params, now=args.now)
    session = _session_presets(scheduler_params)[args.session]

    instrument = InstrumentProfile()
    candidate_exercises = generate_candidates(instrument, MATERIALS)
    traces = run_pipeline(
        state, session, candidate_exercises, scheduler_params, learner_params, args.now
    )
    winner = select_next(traces)

    fh = args.out.open("w", encoding="utf-8") if args.out else sys.stdout
    try:
        for trace in traces:
            fh.write(json.dumps(_trace_to_dict(trace)) + "\n")
        fh.write(
            json.dumps(
                {"selected": _trace_to_dict(winner) if winner is not None else None}
            )
            + "\n"
        )
    finally:
        if args.out:
            fh.close()


if __name__ == "__main__":
    main()
