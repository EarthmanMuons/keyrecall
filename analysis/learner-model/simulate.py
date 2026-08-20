#!/usr/bin/env python3
"""CLI: run a synthetic learner profile through N practice attempts and
emit a JSON-lines trace of predictions, outcomes, evidence, and state.

No MIDI parsing, no UI, no production scheduler. This exercises the
mathematics in docs/learner-model/03-v1-math.md against synthetic
longitudinal practice; see invariants.py for the specific properties it
should satisfy.

Usage:
    python simulate.py --profile beginner --attempts 200 --seed 0
    python simulate.py --profile advanced --attempts 100 --seed 1 --out trace.jsonl
"""

from __future__ import annotations

import argparse
import copy
import json
import random
import sys
from collections.abc import Callable
from pathlib import Path

from domain import Exercise, GuidanceContext, TechnicalMaterial, structural_q
from model import (
    Outcome,
    evidence_weights,
    normalized_loadings,
    predicted_success,
    update,
)
from params import Params, load_params
from state import LearnerState
from synthetic import PROFILES, TrueLearnerProfile, sample_outcome

MATERIALS = [
    TechnicalMaterial("C", "MAJOR"),
    TechnicalMaterial("G", "MAJOR"),
    TechnicalMaterial("F", "MAJOR"),
    TechnicalMaterial("A", "NATURAL_MINOR"),
    TechnicalMaterial("D", "HARMONIC_MINOR"),
    TechnicalMaterial("F#", "HARMONIC_MINOR"),
    TechnicalMaterial("E", "MELODIC_MINOR"),
]

HANDS = ("RIGHT", "LEFT", "TOGETHER")

ExerciseFn = Callable[[random.Random, int], Exercise]

# Richer, opt-in pick/outcome hooks for a stateful caller (e.g. the
# scheduler prototype) that needs LearnerState/now to decide, and needs
# to know what happened afterward to update its own bookkeeping.
# Deliberately separate from ExerciseFn rather than widening its arity:
# several existing exercise_fn closures across invariants.py/analyze.py
# already conform to the plain (rng, index) shape, and this keeps every
# one of them working unchanged.
AgentPickFn = Callable[[random.Random, int, LearnerState, float], Exercise]
AgentOutcomeFn = Callable[[Exercise, Outcome, float], None]


def initial_state(
    profile: TrueLearnerProfile, params: Params, now: float = 0.0
) -> LearnerState:
    """Cold start seeded from self-report tier (GLOSSARY.md §12): shifts the
    prior mean, keeps uncertainty broad regardless of tier."""
    tier_mean = {
        "beginner": params.placement.beginner_mean,
        "some_experience": params.placement.some_experience_mean,
        "advanced": params.placement.advanced_mean,
    }[profile.self_report_tier]
    state = LearnerState.new(params, now=now, competency_prior_mean=tier_mean)
    for c in state.competencies.values():
        c.variance = params.placement.prior_variance_broad
    return state


def random_exercise(rng: random.Random, _index: int) -> Exercise:
    material = rng.choice(MATERIALS)
    hands = rng.choice(HANDS)
    octaves = rng.choice([1, 2])
    direction = rng.choice(["UP", "UP_DOWN"])
    tempo = rng.choice([60, 80, 100, 120])
    guidance = GuidanceContext(
        notes_previewed=rng.random() < 0.3,
        concurrent_pitch_cues=rng.random() < 0.15,
    )
    opportunities = build_opportunities(octaves, direction)
    return Exercise(
        material=material,
        hands=hands,
        octaves=octaves,
        direction=direction,
        tempo_bpm=tempo,
        guidance=guidance,
        opportunities=opportunities,
    )


def build_opportunities(octaves: int, direction: str) -> frozenset[str]:
    """Simulation fixture, not domain inference (see domain.py)."""
    opportunities = {"SCALAR_CROSSING"}
    if octaves >= 2:
        opportunities.add("MULTI_OCTAVE_CONTINUATION")
    if direction == "UP_DOWN":
        opportunities.add("DIRECTION_REVERSAL")
    return frozenset(opportunities)


def fixed_exercise(
    material: TechnicalMaterial,
    hands: str,
    guidance: GuidanceContext | None = None,
    octaves: int = 2,
    direction: str = "UP_DOWN",
    tempo_bpm: float = 80,
) -> Exercise:
    """Scripted exercise for invariant checks and diagnostics that need a
    fixed, repeatable scenario rather than random_exercise()."""
    return Exercise(
        material=material,
        hands=hands,
        octaves=octaves,
        direction=direction,
        tempo_bpm=tempo_bpm,
        guidance=guidance or GuidanceContext(),
        opportunities=build_opportunities(octaves, direction),
    )


def run(
    profile_name: str,
    attempts: int,
    seed: int,
    params: Params,
    day_step: float = 0.5,
    exercise_fn: ExerciseFn | None = None,
    state: LearnerState | None = None,
    truth: TrueLearnerProfile | None = None,
    start_now: float = 0.0,
    rng: random.Random | None = None,
    agent_pick: AgentPickFn | None = None,
    agent_on_outcome: AgentOutcomeFn | None = None,
) -> tuple[list[dict], LearnerState, TrueLearnerProfile]:
    # PROFILES is shared; deep-copy so mutations to hidden ground truth don't
    # leak across separate run() calls. Pass truth= back in to continue a
    # multi-stage simulation instead of restarting the hidden learner fresh.
    profile = truth if truth is not None else copy.deepcopy(PROFILES[profile_name])
    # rng= lets a caller thread one stream across several chunked run() calls
    # (e.g. to checkpoint state mid-simulation) so the chunking itself doesn't
    # replay the same draws each chunk; seed is only used to seed a fresh one.
    active_rng = rng if rng is not None else random.Random(seed)
    if state is None:
        state = initial_state(profile, params, now=start_now)
    now = start_now
    pick = exercise_fn or random_exercise
    trace: list[dict] = []

    for i in range(attempts):
        now += day_step
        state.propagate(now, params)
        # agent_pick takes priority when supplied: it needs live
        # state/now to decide (e.g. the scheduler prototype), which
        # plain ExerciseFn closures never have a way to receive.
        exercise = (
            agent_pick(active_rng, i, state, now) if agent_pick else pick(active_rng, i)
        )

        state_before = state.snapshot()
        prediction = predicted_success(state, exercise, now, params)
        outcome = sample_outcome(profile, exercise, now, active_rng)
        weights = evidence_weights(exercise, outcome)
        memory_update = update(
            state, exercise, outcome, weights, prediction, now, params
        )
        state_after = state.snapshot()
        if agent_on_outcome is not None:
            agent_on_outcome(exercise, outcome, now)

        trace.append(
            {
                "attempt_index": i,
                "at_days": now,
                "profile": profile_name,
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
                    "opportunities": sorted(exercise.opportunities),
                },
                "Q": structural_q(exercise),
                "q": normalized_loadings(structural_q(exercise)),
                "predicted_independent_retrieval_p": prediction.independent_retrieval_p,
                "predicted_material_available_p": prediction.material_available_p,
                "predicted_execution_p": prediction.execution_p,
                "predicted_topology_p": prediction.topology_p,
                "predicted_p": prediction.overall_p,
                "outcome": {
                    "started": outcome.started,
                    "completed": outcome.completed,
                    "material_retrieval": outcome.material_retrieval,
                    "pitch_integrity": outcome.pitch_integrity,
                    "continuity": outcome.continuity,
                    "temporal_stability": outcome.temporal_stability,
                    "achieved_tempo_ratio": outcome.achieved_tempo_ratio,
                    "topology_accuracy": outcome.topology_accuracy,
                },
                "evidence_weights": {
                    "competencies": weights.competencies,
                    "material_execution": weights.material_execution,
                    "material_memory": weights.material_memory,
                },
                "memory_update": {
                    "consolidation_delta_from_retrieval_inference": (
                        memory_update.consolidation_delta_from_retrieval_inference
                    ),
                    "consolidation_delta_from_causal_formation": (
                        memory_update.consolidation_delta_from_causal_formation
                    ),
                },
                "state_before": state_before,
                "state_after": state_after,
            }
        )

    return trace, state, profile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, choices=sorted(PROFILES))
    parser.add_argument("--attempts", type=int, default=100)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--params", type=Path, default=None)
    args = parser.parse_args()

    params = load_params(args.params)
    trace, _final_state, _truth = run(args.profile, args.attempts, args.seed, params)

    fh = args.out.open("w", encoding="utf-8") if args.out else sys.stdout
    try:
        for record in trace:
            fh.write(json.dumps(record) + "\n")
    finally:
        if args.out:
            fh.close()


if __name__ == "__main__":
    main()
