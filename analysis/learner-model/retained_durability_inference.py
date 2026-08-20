"""Pass 8: estimator-side retained-durability inference characterization.

Controlled factual retrieval histories compare mechanisms that may revise the
estimated consolidation envelope from elapsed retrieval evidence. Production
truth, causal consolidation formation, and scheduler behavior remain frozen.

Outputs (in --output-dir):
    retained_inference_trajectories.csv
    retained_inference_summary.csv
    retained_inference_profiles.csv
    retained_inference_profile_summary.csv
    retained_inference_scheduler.csv
    retained_inference_scheduler_summary.csv
"""

from __future__ import annotations

import argparse
import concurrent.futures
import copy
import csv
import math
import os
import random
from dataclasses import dataclass
from pathlib import Path
from statistics import mean
from typing import Any

import cold_start_identifiability as pass5
from domain import GuidanceContext, TechnicalMaterial
from model import Outcome, evidence_weights, predicted_success, update
from params import Params, load_params
from simulate import MATERIALS, fixed_exercise
from state import LearnerState
from synthetic import PROFILES, TrueLearnerProfile, TrueMaterialMemory, sample_outcome

MATERIAL = TechnicalMaterial("C", "MAJOR")
EXERCISE = fixed_exercise(
    MATERIAL,
    "RIGHT",
    guidance=GuidanceContext(),
    octaves=1,
    direction="UP",
    tempo_bpm=80.0,
)

VARIANTS = (
    "control",
    "success_only_score",
    "signed_score",
    "bayesian_posterior",
)
PROFILE_VARIANTS = ("control", "signed_score", "bayesian_posterior")
SCHEDULER_VARIANTS = PROFILE_VARIANTS
SCORE_GAIN = 0.5
MAX_SCORE = 4.0
MAX_LOG_STEP = 1.0
POSTERIOR_GRID_POINTS = 301
MIN_VARIANCE = 1e-6
PROFILE_SEEDS = 30
DEFAULT_WORKERS = min(8, os.cpu_count() or 1)
PROFILE_TIMES = (0.5, 7.5, 21.5, 42.5, 70.5, 105.5)
PROFILE_MATERIALS = tuple(MATERIALS[:7])
MIXED_STRONG_MATERIAL_COUNT = 3


@dataclass(frozen=True)
class Event:
    elapsed_days: float
    succeeded: bool
    execution_quality: float


@dataclass(frozen=True)
class Trajectory:
    name: str
    events: tuple[Event, ...]


@dataclass(frozen=True)
class ProfileFixture:
    label: str
    source_profile: str
    memory_prior: float
    current_half_life_days: float
    mixed_prior_knowledge: bool = False


PROFILE_FIXTURES = (
    ProfileFixture("beginner", "beginner", 0.40, 4.0),
    ProfileFixture(
        "technique_strong_memory_weak",
        "technique_strong_memory_weak",
        0.15,
        0.5,
    ),
    ProfileFixture(
        "memory_strong_technique_weak",
        "memory_strong_technique_weak",
        0.85,
        20.0,
    ),
    ProfileFixture("broadly_strong", "advanced", 0.85, 20.0),
    ProfileFixture(
        "mixed_prior_knowledge",
        "advanced",
        0.15,
        0.5,
        mixed_prior_knowledge=True,
    ),
)


def repeated_events(
    count: int, elapsed_days: float, succeeded: bool, quality: float = 1.0
) -> tuple[Event, ...]:
    return tuple(Event(elapsed_days, succeeded, quality) for _ in range(count))


TRAJECTORIES = (
    Trajectory("massed_success", repeated_events(10, 1.0 / 1440.0, True)),
    Trajectory("daily_success", repeated_events(6, 1.0, True)),
    Trajectory("weekly_success", repeated_events(4, 7.0, True)),
    Trajectory("biweekly_success", repeated_events(4, 14.0, True)),
    Trajectory("twenty_day_success", repeated_events(3, 20.0, True)),
    Trajectory("biweekly_failure", repeated_events(4, 14.0, False, 0.0)),
    Trajectory(
        "late_reversal",
        (
            Event(14.0, True, 1.0),
            Event(14.0, True, 1.0),
            Event(14.0, False, 0.0),
            Event(14.0, False, 0.0),
        ),
    ),
    Trajectory(
        "biweekly_success_weak_execution",
        repeated_events(3, 14.0, True, 0.2),
    ),
    Trajectory(
        "biweekly_success_strong_execution",
        repeated_events(3, 14.0, True, 1.0),
    ),
)


def outcome_for(event: Event) -> Outcome:
    if not event.succeeded:
        return Outcome(
            started=False,
            retrieval_succeeded=False,
            completed=False,
            material_retrieval=0.0,
            pitch_integrity=0.0,
            continuity=0.0,
            temporal_stability=0.0,
            achieved_tempo_ratio=0.0,
            topology_accuracy=0.0,
        )
    quality = event.execution_quality
    return Outcome(
        started=True,
        retrieval_succeeded=True,
        completed=True,
        material_retrieval=1.0,
        pitch_integrity=quality,
        continuity=quality,
        temporal_stability=quality,
        achieved_tempo_ratio=quality,
        topology_accuracy=1.0,
    )


def initial_state(params: Params) -> LearnerState:
    state = LearnerState.new(params, now=0.0, competency_prior_mean=0.0)
    memory = state.material_memory_for(MATERIAL.material_id, params)
    initial = params.material_memory.initial_current_half_life_days
    memory.log_current_half_life = math.log(initial)
    memory.log_consolidated_half_life = math.log(initial)
    memory.memory_anchor_at = 0.0
    memory.factual_last_retrieval_at = 0.0
    memory.last_retrieval_attempt_at = 0.0
    return state


def retained_probability(elapsed_days: float, half_life_days: float) -> float:
    return min(
        1.0 - 1e-12,
        max(1e-12, 2.0 ** (-elapsed_days / half_life_days)),
    )


def likelihood_score(
    succeeded: bool, elapsed_days: float, half_life_days: float
) -> tuple[float, float]:
    probability = retained_probability(elapsed_days, half_life_days)
    scaled_interval = math.log(2.0) * elapsed_days / half_life_days
    score = (
        scaled_interval
        if succeeded
        else -probability * scaled_interval / (1.0 - probability)
    )
    information = probability * scaled_interval * scaled_interval / (1.0 - probability)
    return score, information


def apply_score_inference(
    memory,
    event: Event,
    evidence_weight: float,
    params: Params,
    *,
    failures_enabled: bool,
) -> None:
    if not event.succeeded and not failures_enabled:
        return
    score, information = likelihood_score(
        event.succeeded,
        event.elapsed_days,
        memory.consolidated_half_life_days,
    )
    bounded_score = max(-MAX_SCORE, min(MAX_SCORE, score))
    step = (
        SCORE_GAIN
        * memory.consolidated_half_life_uncertainty
        * evidence_weight
        * bounded_score
    )
    step = max(-MAX_LOG_STEP, min(MAX_LOG_STEP, step))
    proposed = memory.log_consolidated_half_life + step
    memory.log_consolidated_half_life = min(
        math.log(params.material_memory.max_memory_half_life_days),
        max(memory.log_current_half_life, proposed),
    )
    memory.consolidated_half_life_uncertainty = max(
        params.material_memory.min_uncertainty,
        memory.consolidated_half_life_uncertainty
        / (
            1.0
            + memory.consolidated_half_life_uncertainty * evidence_weight * information
        ),
    )


def apply_bayesian_inference(
    memory, event: Event, evidence_weight: float, params: Params
) -> None:
    mm = params.material_memory
    lower = math.log(mm.min_half_life_days)
    upper = math.log(mm.max_memory_half_life_days)
    step = (upper - lower) / (POSTERIOR_GRID_POINTS - 1)
    prior_mean = memory.log_consolidated_half_life
    prior_variance = max(MIN_VARIANCE, memory.consolidated_half_life_uncertainty)
    log_weights = []
    grid = []
    for index in range(POSTERIOR_GRID_POINTS):
        log_half_life = lower + index * step
        half_life = math.exp(log_half_life)
        probability = retained_probability(event.elapsed_days, half_life)
        log_likelihood = (
            math.log(probability) if event.succeeded else math.log1p(-probability)
        )
        log_prior = -0.5 * (log_half_life - prior_mean) ** 2 / prior_variance
        grid.append(log_half_life)
        log_weights.append(log_prior + evidence_weight * log_likelihood)

    maximum = max(log_weights)
    weights = [math.exp(value - maximum) for value in log_weights]
    total = sum(weights)
    posterior_mean = (
        sum(value * weight for value, weight in zip(grid, weights, strict=True)) / total
    )
    posterior_variance = (
        sum(
            weight * (value - posterior_mean) ** 2
            for value, weight in zip(grid, weights, strict=True)
        )
        / total
    )
    memory.log_consolidated_half_life = min(
        upper,
        max(memory.log_current_half_life, posterior_mean),
    )
    memory.consolidated_half_life_uncertainty = max(
        mm.min_uncertainty, posterior_variance
    )


def apply_inference(
    variant: str, memory, event: Event, evidence_weight: float, params: Params
) -> None:
    if variant == "control":
        return
    if variant == "success_only_score":
        apply_score_inference(
            memory,
            event,
            evidence_weight,
            params,
            failures_enabled=False,
        )
        return
    if variant == "signed_score":
        apply_score_inference(
            memory,
            event,
            evidence_weight,
            params,
            failures_enabled=True,
        )
        return
    if variant == "bayesian_posterior":
        apply_bayesian_inference(memory, event, evidence_weight, params)
        return
    raise ValueError(f"unknown inference variant: {variant}")


def run_trajectory(
    variant: str, trajectory: Trajectory, params: Params
) -> list[dict[str, Any]]:
    state = initial_state(params)
    now = 0.0
    rows = []
    for event_index, event in enumerate(trajectory.events, start=1):
        now += event.elapsed_days
        state.propagate(now, params)
        memory = state.material_memory[MATERIAL.material_id]
        prediction = predicted_success(state, EXERCISE, now, params)
        outcome = outcome_for(event)
        weights = evidence_weights(EXERCISE, outcome)

        current_before = memory.current_half_life_days
        consolidation_before = memory.consolidated_half_life_days
        uncertainty_before = memory.consolidated_half_life_uncertainty
        apply_inference(variant, memory, event, weights.material_memory, params)
        consolidation_after_inference = memory.consolidated_half_life_days
        inference_delta = consolidation_after_inference - consolidation_before

        update(state, EXERCISE, outcome, weights, prediction, now, params)
        current_after = memory.current_half_life_days
        consolidation_after = memory.consolidated_half_life_days
        causal_delta = consolidation_after - consolidation_after_inference
        rows.append(
            {
                "variant": variant,
                "trajectory": trajectory.name,
                "event_index": event_index,
                "at_days": now,
                "elapsed_days": event.elapsed_days,
                "retrieval_succeeded": event.succeeded,
                "execution_quality": event.execution_quality,
                "predicted_retrieval_p": prediction.independent_retrieval_p,
                "current_half_life_before": current_before,
                "consolidated_half_life_before": consolidation_before,
                "consolidation_uncertainty_before": uncertainty_before,
                "consolidation_delta_from_retrieval_inference": inference_delta,
                "consolidation_delta_from_causal_formation": causal_delta,
                "current_half_life_after": current_after,
                "consolidated_half_life_after": consolidation_after,
                "consolidation_uncertainty_after": (
                    memory.consolidated_half_life_uncertainty
                ),
            }
        )
    return rows


def summarize(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for row in rows:
        grouped.setdefault((row["variant"], row["trajectory"]), []).append(row)
    results = []
    for (variant, trajectory), group in sorted(grouped.items()):
        results.append(
            {
                "variant": variant,
                "trajectory": trajectory,
                "event_count": len(group),
                "final_current_half_life_days": group[-1]["current_half_life_after"],
                "final_consolidated_half_life_days": group[-1][
                    "consolidated_half_life_after"
                ],
                "final_consolidation_uncertainty": group[-1][
                    "consolidation_uncertainty_after"
                ],
                "total_consolidation_delta_from_retrieval_inference": sum(
                    row["consolidation_delta_from_retrieval_inference"] for row in group
                ),
                "total_consolidation_delta_from_causal_formation": sum(
                    row["consolidation_delta_from_causal_formation"] for row in group
                ),
                "mean_absolute_retrieval_surprise": mean(
                    abs(
                        float(row["retrieval_succeeded"]) - row["predicted_retrieval_p"]
                    )
                    for row in group
                ),
            }
        )
    return results


def check_isolation(rows: list[dict[str, Any]]) -> None:
    for variant in VARIANTS:
        weak = next(
            row
            for row in rows
            if row["variant"] == variant
            and row["trajectory"] == "biweekly_success_weak_execution"
            and row["event_index"] == 1
        )
        strong = next(
            row
            for row in rows
            if row["variant"] == variant
            and row["trajectory"] == "biweekly_success_strong_execution"
            and row["event_index"] == 1
        )
        if not math.isclose(
            weak["consolidation_delta_from_retrieval_inference"],
            strong["consolidation_delta_from_retrieval_inference"],
            rel_tol=0.0,
            abs_tol=1e-12,
        ):
            raise AssertionError(f"{variant}: inference depends on execution quality")
        if not (
            strong["consolidation_delta_from_causal_formation"]
            > weak["consolidation_delta_from_causal_formation"]
        ):
            raise AssertionError(f"{variant}: causal formation ignored quality")

    summaries = {(row["variant"], row["trajectory"]): row for row in summarize(rows)}
    for variant in ("signed_score", "bayesian_posterior"):
        massed = summaries[(variant, "massed_success")]
        if abs(massed["total_consolidation_delta_from_retrieval_inference"]) >= 0.02:
            raise AssertionError(f"{variant}: massed retrieval created durability")
        interval_deltas = [
            summaries[(variant, trajectory)][
                "total_consolidation_delta_from_retrieval_inference"
            ]
            for trajectory in (
                "daily_success",
                "weekly_success",
                "biweekly_success",
                "twenty_day_success",
            )
        ]
        if interval_deltas != sorted(interval_deltas):
            raise AssertionError(f"{variant}: inference is not interval-sensitive")

    for variant in ("signed_score", "bayesian_posterior"):
        reversal = [
            row
            for row in rows
            if row["variant"] == variant and row["trajectory"] == "late_reversal"
        ]
        if not (
            reversal[-1]["consolidated_half_life_after"]
            < reversal[1]["consolidated_half_life_after"]
        ):
            raise AssertionError(f"{variant}: failures did not reverse inference")

    one_sided = [
        row
        for row in rows
        if row["variant"] == "success_only_score"
        and row["trajectory"] == "late_reversal"
    ]
    if not math.isclose(
        one_sided[-1]["consolidated_half_life_after"],
        one_sided[1]["consolidated_half_life_after"],
    ):
        raise AssertionError("success-only comparator unexpectedly reversed")


def build_profile_truth(
    fixture: ProfileFixture, seed: int
) -> tuple[TrueLearnerProfile, dict[str, str]]:
    truth = copy.deepcopy(PROFILES[fixture.source_profile])
    truth.name = fixture.label
    truth.memory_prior = fixture.memory_prior
    truth.default_current_half_life_days = fixture.current_half_life_days
    truth.true_material_memory.clear()

    default_class = "strong" if fixture.memory_prior >= 0.70 else "weak"
    material_classes = dict.fromkeys(
        (material.material_id for material in PROFILE_MATERIALS), default_class
    )
    if not fixture.mixed_prior_knowledge:
        return truth, material_classes

    chooser = random.Random(100_000 + seed)
    strong_ids = set(
        chooser.sample(
            [material.material_id for material in PROFILE_MATERIALS],
            MIXED_STRONG_MATERIAL_COUNT,
        )
    )
    for material in PROFILE_MATERIALS:
        material_id = material.material_id
        if material_id not in strong_ids:
            continue
        material_classes[material_id] = "strong"
        truth.true_material_memory[material_id] = TrueMaterialMemory(
            current_half_life_days=20.0,
            consolidated_half_life_days=20.0,
            memory_anchor_at=0.0,
            factual_last_retrieval_at=0.0,
            last_retrieval_attempt_at=0.0,
        )
    return truth, material_classes


def true_retrievability(
    truth: TrueLearnerProfile, material_id: str, now: float
) -> float:
    memory = truth.true_material_memory.get(material_id)
    if memory is None:
        return truth.memory_prior
    return memory.retrievability(now, truth.memory_prior)


def run_profile_case(
    variant: str, fixture: ProfileFixture, seed: int, params: Params
) -> list[dict[str, Any]]:
    truth, material_classes = build_profile_truth(fixture, seed)
    state = LearnerState.new(params, now=0.0, competency_prior_mean=0.0)
    rng = random.Random(seed)
    rows = []
    for round_index, now in enumerate(PROFILE_TIMES, start=1):
        state.propagate(now, params)
        for material in PROFILE_MATERIALS:
            exercise = fixed_exercise(
                material,
                "RIGHT",
                guidance=GuidanceContext(),
                octaves=1,
                direction="UP",
                tempo_bpm=80.0,
            )
            material_id = material.material_id
            actual_probability = true_retrievability(truth, material_id, now)
            prediction = predicted_success(state, exercise, now, params)
            outcome = sample_outcome(truth, exercise, now, rng)
            weights = evidence_weights(exercise, outcome)
            memory = state.material_memory_for(material_id, params)
            consolidation_before = memory.consolidated_half_life_days
            anchor_before = memory.memory_anchor_at
            factual = outcome.retrieval_succeeded is not None
            interval_identified = factual and anchor_before is not None

            if interval_identified:
                apply_inference(
                    variant,
                    memory,
                    Event(
                        elapsed_days=now - anchor_before,
                        succeeded=bool(outcome.retrieval_succeeded),
                        execution_quality=0.0,
                    ),
                    weights.material_memory,
                    params,
                )
            consolidation_after_inference = memory.consolidated_half_life_days
            update(state, exercise, outcome, weights, prediction, now, params)
            rows.append(
                {
                    "variant": variant,
                    "fixture": fixture.label,
                    "seed": seed,
                    "material_id": material_id,
                    "material_class": material_classes[material_id],
                    "round_index": round_index,
                    "at_days": now,
                    "elapsed_interval_days": (
                        now - anchor_before if anchor_before is not None else ""
                    ),
                    "retrieval_observed": factual,
                    "retrieval_succeeded": (
                        outcome.retrieval_succeeded if factual else ""
                    ),
                    "true_retrieval_p": actual_probability,
                    "predicted_retrieval_p": prediction.independent_retrieval_p,
                    "retrieval_error": (
                        prediction.independent_retrieval_p - actual_probability
                    ),
                    "interval_evidence_available": interval_identified,
                    "consolidation_delta_from_retrieval_inference": (
                        consolidation_after_inference - consolidation_before
                    ),
                    "consolidation_delta_from_causal_formation": (
                        memory.consolidated_half_life_days
                        - consolidation_after_inference
                    ),
                    "current_half_life_after": memory.current_half_life_days,
                    "consolidated_half_life_after": (
                        memory.consolidated_half_life_days
                    ),
                    "consolidation_uncertainty_after": (
                        memory.consolidated_half_life_uncertainty
                    ),
                }
            )
    return rows


def summarize_profiles(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, str, str], list[dict[str, Any]]] = {}
    for row in rows:
        key = (row["variant"], row["fixture"], row["material_class"])
        grouped.setdefault(key, []).append(row)

    results = []
    for (variant, fixture, material_class), group in sorted(grouped.items()):
        final_rows = [row for row in group if row["round_index"] == len(PROFILE_TIMES)]
        interval_rows = [row for row in group if row["interval_evidence_available"]]
        results.append(
            {
                "variant": variant,
                "fixture": fixture,
                "material_class": material_class,
                "attempt_count": len(group),
                "interval_evidence_count": len(interval_rows),
                "mean_retrieval_bias": mean(row["retrieval_error"] for row in group),
                "mean_absolute_retrieval_error": mean(
                    abs(row["retrieval_error"]) for row in group
                ),
                "post_interval_retrieval_bias": (
                    mean(row["retrieval_error"] for row in interval_rows)
                    if interval_rows
                    else ""
                ),
                "final_current_half_life_days": mean(
                    row["current_half_life_after"] for row in final_rows
                ),
                "final_consolidated_half_life_days": mean(
                    row["consolidated_half_life_after"] for row in final_rows
                ),
                "total_consolidation_delta_from_retrieval_inference": sum(
                    row["consolidation_delta_from_retrieval_inference"] for row in group
                ),
                "total_consolidation_delta_from_causal_formation": sum(
                    row["consolidation_delta_from_causal_formation"] for row in group
                ),
            }
        )
    return results


def check_profile_pairing(rows: list[dict[str, Any]]) -> None:
    grouped: dict[tuple[str, int, str, int], list[dict[str, Any]]] = {}
    for row in rows:
        key = (
            row["fixture"],
            int(row["seed"]),
            row["material_id"],
            int(row["round_index"]),
        )
        grouped.setdefault(key, []).append(row)
    for key, group in grouped.items():
        outcomes = {
            (row["retrieval_observed"], row["retrieval_succeeded"]) for row in group
        }
        true_probabilities = {row["true_retrieval_p"] for row in group}
        if len(outcomes) != 1 or len(true_probabilities) != 1:
            raise AssertionError(f"unpaired profile trajectory: {key}")


def run_scheduler_case(
    variant: str, fixture: ProfileFixture, seed: int
) -> list[dict[str, Any]]:
    learner_params = load_params()
    scheduler_params = pass5.load_scheduler_params()
    truth, material_classes = build_profile_truth(fixture, seed)
    state = pass5.common_estimator_state(learner_params)
    agent = pass5.SchedulerAgent(
        pass5.InstrumentProfile(),
        list(PROFILE_MATERIALS),
        scheduler_params,
        learner_params,
    )
    rng = random.Random(seed)
    rows = []
    now = 0.0
    selection_index = 0

    for attempt_index in range(pass5.ATTEMPTS):
        if attempt_index and attempt_index % pass5.SESSION_ATTEMPTS == 0:
            agent.new_session()
        now += pass5.DAY_STEP
        state.propagate(now, learner_params)
        try:
            exercise = agent.pick(rng, attempt_index, state, now)
        except pass5.NoAdmittedCandidate:
            rows.append(
                {
                    "variant": variant,
                    "fixture": fixture.label,
                    "seed": seed,
                    "attempt_index": attempt_index,
                    "selection_index": "",
                    "selected": False,
                    "material_id": "",
                    "material_class": "",
                    "guidance_level": "none",
                    "retrieval_observed": False,
                    "retrieval_succeeded": "",
                    "true_retrieval_p": "",
                    "predicted_retrieval_p": "",
                    "retrieval_error": "",
                    "consolidation_delta_from_retrieval_inference": "",
                    "consolidation_delta_from_causal_formation": "",
                    "current_half_life_after": "",
                    "consolidated_half_life_after": "",
                }
            )
            continue

        material_id = exercise.material.material_id
        actual_probability = true_retrievability(truth, material_id, now)
        prediction = predicted_success(state, exercise, now, learner_params)
        outcome = sample_outcome(truth, exercise, now, rng)
        weights = evidence_weights(exercise, outcome)
        memory = state.material_memory_for(material_id, learner_params)
        consolidation_before = memory.consolidated_half_life_days
        anchor_before = memory.memory_anchor_at
        factual = outcome.retrieval_succeeded is not None
        if factual and anchor_before is not None:
            apply_inference(
                variant,
                memory,
                Event(
                    elapsed_days=now - anchor_before,
                    succeeded=bool(outcome.retrieval_succeeded),
                    execution_quality=0.0,
                ),
                weights.material_memory,
                learner_params,
            )
        consolidation_after_inference = memory.consolidated_half_life_days
        update(
            state,
            exercise,
            outcome,
            weights,
            prediction,
            now,
            learner_params,
        )
        agent.on_outcome(exercise, outcome, now)
        rows.append(
            {
                "variant": variant,
                "fixture": fixture.label,
                "seed": seed,
                "attempt_index": attempt_index,
                "selection_index": selection_index,
                "selected": True,
                "material_id": material_id,
                "material_class": material_classes[material_id],
                "guidance_level": pass5.guidance_level(exercise),
                "retrieval_observed": factual,
                "retrieval_succeeded": (outcome.retrieval_succeeded if factual else ""),
                "true_retrieval_p": actual_probability,
                "predicted_retrieval_p": prediction.independent_retrieval_p,
                "retrieval_error": (
                    prediction.independent_retrieval_p - actual_probability
                ),
                "consolidation_delta_from_retrieval_inference": (
                    consolidation_after_inference - consolidation_before
                ),
                "consolidation_delta_from_causal_formation": (
                    memory.consolidated_half_life_days - consolidation_after_inference
                ),
                "current_half_life_after": memory.current_half_life_days,
                "consolidated_half_life_after": memory.consolidated_half_life_days,
            }
        )
        selection_index += 1
    return rows


def summarize_scheduler(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, str, str], list[dict[str, Any]]] = {}
    for row in rows:
        if not row["selected"]:
            continue
        key = (row["variant"], row["fixture"], row["material_class"])
        grouped.setdefault(key, []).append(row)

    results = []
    for (variant, fixture, material_class), group in sorted(grouped.items()):
        seed_count = len({int(row["seed"]) for row in group})
        early = [row for row in group if int(row["selection_index"]) < 20]
        tail_by_seed: list[dict[str, Any]] = []
        for seed in sorted({int(row["seed"]) for row in group}):
            seed_rows = [row for row in group if int(row["seed"]) == seed]
            tail_by_seed.extend(seed_rows[-10:])
        results.append(
            {
                "variant": variant,
                "fixture": fixture,
                "material_class": material_class,
                "selection_count": len(group),
                "retrieval_observation_fraction": mean(
                    float(row["retrieval_observed"]) for row in group
                ),
                "early_unnecessary_cueing_count_per_seed": sum(
                    1
                    for row in early
                    if float(row["true_retrieval_p"]) >= 0.70
                    and row["guidance_level"] != "unguided"
                )
                / seed_count,
                "early_unguided_low_memory_count_per_seed": sum(
                    1
                    for row in early
                    if float(row["true_retrieval_p"]) <= 0.30
                    and row["guidance_level"] == "unguided"
                )
                / seed_count,
                "final_retrieval_bias": mean(
                    float(row["retrieval_error"]) for row in tail_by_seed
                ),
                "final_retrieval_mae": mean(
                    abs(float(row["retrieval_error"])) for row in tail_by_seed
                ),
                "mean_current_half_life_days": mean(
                    float(row["current_half_life_after"]) for row in tail_by_seed
                ),
                "mean_consolidated_half_life_days": mean(
                    float(row["consolidated_half_life_after"]) for row in tail_by_seed
                ),
                "total_consolidation_delta_from_retrieval_inference": sum(
                    float(row["consolidation_delta_from_retrieval_inference"])
                    for row in group
                ),
                "total_consolidation_delta_from_causal_formation": sum(
                    float(row["consolidation_delta_from_causal_formation"])
                    for row in group
                ),
            }
        )
    return results


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def report(summary: list[dict[str, Any]]) -> None:
    print("Retained-durability inference (final days; inference/causal deltas):")
    for row in summary:
        print(
            f"  {row['variant']:<22} {row['trajectory']:<37} "
            f"current={row['final_current_half_life_days']:>8.3f} "
            f"consolidated={row['final_consolidated_half_life_days']:>8.3f} "
            f"inference={row['total_consolidation_delta_from_retrieval_inference']:>8.3f} "
            f"causal={row['total_consolidation_delta_from_causal_formation']:>8.3f}"
        )


def report_profiles(summary: list[dict[str, Any]]) -> None:
    print("Scheduler-free profile characterization:")
    for row in summary:
        print(
            f"  {row['variant']:<18} {row['fixture']:<32} "
            f"{row['material_class']:<6} "
            f"bias={row['mean_retrieval_bias']:>7.3f} "
            f"post_interval={row['post_interval_retrieval_bias']:>7.3f} "
            f"current={row['final_current_half_life_days']:>7.3f} "
            f"consolidated={row['final_consolidated_half_life_days']:>7.3f}"
        )


def report_scheduler(summary: list[dict[str, Any]]) -> None:
    print("Scheduler consequence characterization:")
    for row in summary:
        print(
            f"  {row['variant']:<18} {row['fixture']:<32} "
            f"{row['material_class']:<6} "
            f"bias={row['final_retrieval_bias']:>7.3f} "
            f"mae={row['final_retrieval_mae']:>7.3f} "
            f"early_cued={row['early_unnecessary_cueing_count_per_seed']:>5.2f} "
            f"current={row['mean_current_half_life_days']:>7.3f} "
            f"consolidated={row['mean_consolidated_half_life_days']:>7.3f}"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).with_name("generated"),
    )
    parser.add_argument("--profile-seeds", type=int, default=PROFILE_SEEDS)
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    parser.add_argument("--skip-scheduler", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.profile_seeds < 1 or args.workers < 1:
        raise ValueError("profile-seeds and workers must both be at least 1")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    params = load_params()
    trajectories = [
        row
        for variant in VARIANTS
        for trajectory in TRAJECTORIES
        for row in run_trajectory(variant, trajectory, params)
    ]
    summary = summarize(trajectories)
    check_isolation(trajectories)
    profile_rows = [
        row
        for variant in PROFILE_VARIANTS
        for fixture in PROFILE_FIXTURES
        for seed in range(args.profile_seeds)
        for row in run_profile_case(variant, fixture, seed, params)
    ]
    profile_summary = summarize_profiles(profile_rows)
    check_profile_pairing(profile_rows)
    scheduler_cases = [
        (variant, fixture, seed)
        for variant in SCHEDULER_VARIANTS
        for fixture in PROFILE_FIXTURES
        for seed in range(args.profile_seeds)
    ]
    if args.skip_scheduler:
        scheduler_case_rows = []
    elif args.workers == 1:
        scheduler_case_rows = [run_scheduler_case(*case) for case in scheduler_cases]
    else:
        with concurrent.futures.ProcessPoolExecutor(args.workers) as executor:
            variants, fixtures, seeds = zip(*scheduler_cases, strict=True)
            scheduler_case_rows = list(
                executor.map(run_scheduler_case, variants, fixtures, seeds)
            )
    scheduler_rows = [row for rows in scheduler_case_rows for row in rows]
    scheduler_summary = summarize_scheduler(scheduler_rows) if scheduler_rows else []
    outputs = {
        "retained_inference_trajectories.csv": trajectories,
        "retained_inference_summary.csv": summary,
        "retained_inference_profiles.csv": profile_rows,
        "retained_inference_profile_summary.csv": profile_summary,
    }
    if scheduler_rows:
        outputs["retained_inference_scheduler.csv"] = scheduler_rows
        outputs["retained_inference_scheduler_summary.csv"] = scheduler_summary
    for filename, rows in outputs.items():
        write_csv(args.output_dir / filename, rows)
    report(summary)
    print()
    report_profiles(profile_summary)
    print()
    if scheduler_summary:
        report_scheduler(scheduler_summary)
        print()
    for filename in outputs:
        print(f"Wrote {args.output_dir / filename}")


if __name__ == "__main__":
    main()
