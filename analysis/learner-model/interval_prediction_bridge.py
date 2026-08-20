"""Pass 7: post-success interval-identifiability bridge characterization.

The bridge is an epistemic prediction sidecar. It may borrow learner-level
placement evidence after a material's first factual success while durability is
still underidentified. It never changes stored durability, consolidation,
ordinary update equations, scheduler policy, or synthetic learner truth.

Outputs (in --output-dir):
    bridge_profile_summary.csv
    bridge_variant_summary.csv
    bridge_phase_summary.csv
    bridge_threshold_summary.csv
    bridge_trajectories.csv
"""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import math
import os
import random
from collections import Counter, defaultdict
from dataclasses import dataclass
from itertools import pairwise
from pathlib import Path
from statistics import mean
from typing import Any

import cross_material_placement as pass6
import pipeline
from candidates import InstrumentProfile
from config import load_params as load_scheduler_params
from longitudinal import NoAdmittedCandidate, SchedulerAgent
from model import (
    evidence_weights,
    predicted_success,
    update,
)
from params import load_params as load_learner_params
from synthetic import sample_outcome

ATTEMPTS = pass6.ATTEMPTS
SESSION_ATTEMPTS = pass6.SESSION_ATTEMPTS
DAY_STEP = pass6.DAY_STEP
EARLY_SELECTIONS = pass6.EARLY_SELECTIONS
MATERIAL_POOL = pass6.MATERIAL_POOL
FIXTURES = pass6.FIXTURES
DEFAULT_SEEDS = 30
DEFAULT_WORKERS = min(8, os.cpu_count() or 1)

VARIANTS = (
    "control",
    "bridge_until_second",
    "bridge_until_informative",
    "decaying_bridge",
)
BRIDGE_MAX_WEIGHT = 0.5
INTERVAL_INFORMATION_THRESHOLD = 0.25
INFORMATION_THRESHOLDS = (0.10, 0.25, 0.50, 1.00)
EPSILON = 1e-9


@dataclass
class IntervalEvidenceState:
    factual_attempts_after_first_success: int = 0
    accumulated_information: float = 0.0


def clamp_probability(value: float) -> float:
    return min(1.0 - EPSILON, max(EPSILON, value))


def logit(value: float) -> float:
    probability = clamp_probability(value)
    return math.log(probability / (1.0 - probability))


def logistic(value: float) -> float:
    return 1.0 / (1.0 + math.exp(-value))


def interval_information(
    ordinary_prediction: float, elapsed_days: float, half_life_days: float
) -> float:
    """Bernoulli information proxy for log half-life at this interval."""
    if elapsed_days <= 0.0 or half_life_days <= 0.0:
        return 0.0
    probability = clamp_probability(ordinary_prediction)
    scaled_interval = math.log(2.0) * elapsed_days / half_life_days
    information = probability * scaled_interval * scaled_interval / (1.0 - probability)
    return max(0.0, min(1.0, information))


def prediction_phase(
    state, material_id: str, interval_state: IntervalEvidenceState
) -> str:
    memory = state.material_memory.get(material_id)
    if memory is None or memory.factual_last_retrieval_at is None:
        return "before_first_factual_success"
    if interval_state.accumulated_information < INTERVAL_INFORMATION_THRESHOLD:
        return "post_success_interval_unidentified"
    return "interval_identified"


def bridge_weight(variant: str, interval_state: IntervalEvidenceState) -> float:
    if variant == "control":
        return 0.0
    if variant == "bridge_until_second":
        return (
            BRIDGE_MAX_WEIGHT
            if interval_state.factual_attempts_after_first_success == 0
            else 0.0
        )
    if variant == "bridge_until_informative":
        return (
            BRIDGE_MAX_WEIGHT
            if interval_state.accumulated_information < INTERVAL_INFORMATION_THRESHOLD
            else 0.0
        )
    if variant == "decaying_bridge":
        return BRIDGE_MAX_WEIGHT * math.exp(
            -interval_state.accumulated_information / INTERVAL_INFORMATION_THRESHOLD
        )
    raise ValueError(f"unknown bridge variant: {variant}")


def blended_prediction(ordinary: float, placement: float, weight: float) -> float:
    if weight <= 0.0:
        return ordinary
    return logistic((1.0 - weight) * logit(ordinary) + weight * logit(placement))


def run_case(variant: str, fixture: pass6.Fixture, seed: int) -> list[dict[str, Any]]:
    base_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    truth, material_classes = pass6.build_truth(fixture, seed)
    state = pass6.pass5.common_estimator_state(base_params)
    placement = pass6.PlacementMemoryState.new(base_params)
    interval_states: dict[str, IntervalEvidenceState] = defaultdict(
        IntervalEvidenceState
    )
    agent = SchedulerAgent(
        InstrumentProfile(), list(MATERIAL_POOL), scheduler_params, base_params
    )
    rng = random.Random(seed)
    rows = []
    now = 0.0
    selection_index = 0
    original_pipeline_retrieval = pipeline.predicted_independent_retrieval_p

    def diagnostic_retrieval_prediction(
        candidate_state, exercise, candidate_now, learner_params
    ) -> float:
        ordinary = original_pipeline_retrieval(
            candidate_state, exercise, candidate_now, learner_params
        )
        material_id = exercise.material.material_id
        phase = prediction_phase(
            candidate_state, material_id, interval_states[material_id]
        )
        if phase != "post_success_interval_unidentified":
            return ordinary
        weight = bridge_weight(variant, interval_states[material_id])
        return blended_prediction(ordinary, placement.effective_prior, weight)

    pipeline.predicted_independent_retrieval_p = diagnostic_retrieval_prediction
    try:
        for attempt_index in range(ATTEMPTS):
            if attempt_index and attempt_index % SESSION_ATTEMPTS == 0:
                agent.new_session()
            now += DAY_STEP
            state.propagate(now, base_params)
            learner_params = pass6.effective_learner_params(
                state,
                placement,
                "control" if variant == "control" else "pooled_prior",
                base_params,
            )
            agent.learner_params = learner_params

            try:
                exercise = agent.pick(rng, attempt_index, state, now)
            except NoAdmittedCandidate:
                rows.append(
                    {
                        "variant": variant,
                        "profile": fixture.label,
                        "seed": seed,
                        "attempt_index": attempt_index,
                        "selection_index": "",
                        "at_days": now,
                        "selected": False,
                        "material_id": "",
                        "truth_memory_class": "",
                        "prediction_phase": "none",
                        "guidance_level": "none",
                        "challenge_bypass": "none",
                        "challenge_within_band": "",
                        "retrieval_observed": False,
                        "retrieval_succeeded": "",
                        "ordinary_retrieval_p": "",
                        "scheduler_retrieval_p": "",
                        "true_retrieval_p": "",
                        "ordinary_retrieval_bias": "",
                        "scheduler_retrieval_bias": "",
                        "bridge_weight": 0.0,
                        "interval_information_before": "",
                        "interval_information_added": 0.0,
                        "placement_effective_prior": placement.effective_prior,
                        "placement_evidence_count": placement.evidence_count,
                        "current_half_life_before": "",
                        "consolidated_half_life_before": "",
                        "current_half_life_after": "",
                        "consolidated_half_life_after": "",
                    }
                )
                continue

            selected_trace = agent.records[-1].selected
            assert selected_trace is not None
            material_id = exercise.material.material_id
            interval_state = interval_states[material_id]
            phase = prediction_phase(state, material_id, interval_state)
            weight = (
                bridge_weight(variant, interval_state)
                if phase == "post_success_interval_unidentified"
                else 0.0
            )
            ordinary_prediction = predicted_success(
                state, exercise, now, learner_params
            )
            scheduler_prediction = selected_trace.prediction
            expected_scheduler_retrieval = blended_prediction(
                ordinary_prediction.independent_retrieval_p,
                placement.effective_prior,
                weight,
            )
            if not math.isclose(
                scheduler_prediction.independent_retrieval_p,
                expected_scheduler_retrieval,
                rel_tol=0.0,
                abs_tol=1e-12,
            ):
                raise AssertionError("selected trace did not use diagnostic bridge")

            memory_before = state.material_memory.get(material_id)
            had_factual_success = (
                memory_before is not None
                and memory_before.factual_last_retrieval_at is not None
            )
            first_factual = not pass6.material_has_factual_evidence(state, material_id)
            elapsed_days = (
                now - memory_before.memory_anchor_at
                if memory_before is not None
                and memory_before.memory_anchor_at is not None
                else 0.0
            )
            half_life_days = (
                memory_before.current_half_life_days
                if memory_before is not None
                else learner_params.material_memory.initial_current_half_life_days
            )
            consolidated_before = (
                memory_before.consolidated_half_life_days
                if memory_before is not None
                else learner_params.material_memory.initial_current_half_life_days
            )
            true_p = pass6.true_retrievability(truth, material_id, now)
            outcome = sample_outcome(truth, exercise, now, rng)
            weights = evidence_weights(exercise, outcome)
            information_added = 0.0
            if had_factual_success and outcome.retrieval_succeeded is not None:
                information_added = weights.material_memory * interval_information(
                    ordinary_prediction.independent_retrieval_p,
                    elapsed_days,
                    half_life_days,
                )
                interval_state.factual_attempts_after_first_success += 1
                interval_state.accumulated_information += information_added

            update(
                state,
                exercise,
                outcome,
                weights,
                ordinary_prediction,
                now,
                learner_params,
            )
            agent.on_outcome(exercise, outcome, now)
            memory_after = state.material_memory[material_id]
            if (
                variant != "control"
                and first_factual
                and outcome.retrieval_succeeded is not None
            ):
                placement.observe(
                    bool(outcome.retrieval_succeeded), weights.material_memory
                )

            rows.append(
                {
                    "variant": variant,
                    "profile": fixture.label,
                    "seed": seed,
                    "attempt_index": attempt_index,
                    "selection_index": selection_index,
                    "at_days": now,
                    "selected": True,
                    "material_id": material_id,
                    "truth_memory_class": material_classes[material_id],
                    "prediction_phase": phase,
                    "guidance_level": pass6.pass5.guidance_level(exercise),
                    "challenge_bypass": selected_trace.challenge_bypass or "none",
                    "challenge_within_band": selected_trace.challenge_within_band,
                    "retrieval_observed": outcome.retrieval_succeeded is not None,
                    "retrieval_succeeded": (
                        outcome.retrieval_succeeded
                        if outcome.retrieval_succeeded is not None
                        else ""
                    ),
                    "ordinary_retrieval_p": (
                        ordinary_prediction.independent_retrieval_p
                    ),
                    "scheduler_retrieval_p": (
                        scheduler_prediction.independent_retrieval_p
                    ),
                    "true_retrieval_p": true_p,
                    "ordinary_retrieval_bias": (
                        ordinary_prediction.independent_retrieval_p - true_p
                    ),
                    "scheduler_retrieval_bias": (
                        scheduler_prediction.independent_retrieval_p - true_p
                    ),
                    "bridge_weight": weight,
                    "interval_information_before": (
                        interval_state.accumulated_information - information_added
                    ),
                    "interval_information_added": information_added,
                    "placement_effective_prior": placement.effective_prior,
                    "placement_evidence_count": placement.evidence_count,
                    "current_half_life_before": half_life_days,
                    "consolidated_half_life_before": consolidated_before,
                    "current_half_life_after": memory_after.current_half_life_days,
                    "consolidated_half_life_after": (
                        memory_after.consolidated_half_life_days
                    ),
                }
            )
            selection_index += 1
    finally:
        pipeline.predicted_independent_retrieval_p = original_pipeline_retrieval

    return rows


def attempts_to_stable_calibration(rows: list[dict[str, Any]]) -> int | None:
    selected = [row for row in rows if row["selected"]]
    window_size = pass6.pass5.CALIBRATION_WINDOW
    for start in range(len(selected) - window_size + 1):
        window = selected[start : start + window_size]
        if all(
            abs(float(row["scheduler_retrieval_bias"]))
            <= pass6.pass5.CALIBRATION_TOLERANCE
            for row in window
        ):
            return int(window[0]["selection_index"]) + 1
    return None


def attempts_to_stable_challenge_band(rows: list[dict[str, Any]]) -> int | None:
    selected = [row for row in rows if row["selected"]]
    window_size = pass6.pass5.CALIBRATION_WINDOW
    for start in range(len(selected) - window_size + 1):
        window = selected[start : start + window_size]
        if all(row["challenge_within_band"] for row in window):
            return int(window[0]["selection_index"]) + 1
    return None


def max_revisit_gap(rows: list[dict[str, Any]]) -> float:
    visits: dict[str, list[float]] = defaultdict(list)
    for row in rows:
        if row["selected"]:
            visits[row["material_id"]].append(float(row["at_days"]))
    return max(
        (
            later - earlier
            for material_visits in visits.values()
            for earlier, later in pairwise(material_visits)
        ),
        default=0.0,
    )


def summarize_seed(rows: list[dict[str, Any]]) -> dict[str, Any]:
    selected = [row for row in rows if row["selected"]]
    observed = [row for row in selected if row["retrieval_observed"]]
    early = selected[:EARLY_SELECTIONS]
    tail = selected[-10:]
    counts = Counter(row["material_id"] for row in selected)
    calibrated_at = attempts_to_stable_calibration(rows)
    challenge_at = attempts_to_stable_challenge_band(rows)
    first = rows[0]
    return {
        "variant": first["variant"],
        "profile": first["profile"],
        "seed": first["seed"],
        "attempts_to_calibrated_band": calibrated_at,
        "calibrated_by_end": calibrated_at is not None,
        "attempts_to_stable_challenge_band": challenge_at,
        "stable_challenge_band_by_end": challenge_at is not None,
        "early_unnecessary_cueing_count": sum(
            1
            for row in early
            if float(row["true_retrieval_p"]) >= 0.70
            and row["guidance_level"] != "unguided"
        ),
        "early_unguided_low_memory_count": sum(
            1
            for row in early
            if float(row["true_retrieval_p"]) <= 0.30
            and row["guidance_level"] == "unguided"
        ),
        "early_strong_material_cueing_count": sum(
            1
            for row in early
            if row["truth_memory_class"] == "strong"
            and row["guidance_level"] != "unguided"
        ),
        "early_weak_material_unguided_count": sum(
            1
            for row in early
            if row["truth_memory_class"] == "weak"
            and row["guidance_level"] == "unguided"
        ),
        "final_retrieval_bias": mean(
            float(row["scheduler_retrieval_bias"]) for row in tail
        ),
        "final_current_half_life_days": mean(
            float(row["current_half_life_after"]) for row in tail
        ),
        "final_consolidated_half_life_days": mean(
            float(row["consolidated_half_life_after"]) for row in tail
        ),
        "retrieval_prediction_mae": mean(
            abs(float(row["scheduler_retrieval_bias"])) for row in observed
        ),
        "retrieval_prediction_brier": mean(
            (float(row["scheduler_retrieval_p"]) - float(row["retrieval_succeeded"]))
            ** 2
            for row in observed
        ),
        "recovery_fraction": mean(
            row["challenge_bypass"] == "recovery" for row in selected
        ),
        "max_material_selection_fraction": max(counts.values()) / len(selected),
        "max_revisit_gap_days": max_revisit_gap(rows),
        "no_admission_count": sum(not row["selected"] for row in rows),
    }


def optional_mean(rows: list[dict[str, Any]], field: str) -> float | None:
    values = [float(row[field]) for row in rows if row[field] is not None]
    return mean(values) if values else None


SUMMARY_FIELDS = (
    "attempts_to_calibrated_band",
    "attempts_to_stable_challenge_band",
    "early_unnecessary_cueing_count",
    "early_unguided_low_memory_count",
    "early_strong_material_cueing_count",
    "early_weak_material_unguided_count",
    "final_retrieval_bias",
    "final_current_half_life_days",
    "final_consolidated_half_life_days",
    "retrieval_prediction_mae",
    "retrieval_prediction_brier",
    "recovery_fraction",
    "max_material_selection_fraction",
    "max_revisit_gap_days",
    "no_admission_count",
)


def attempts_to_diverge_from_beginner(
    trajectories: list[dict[str, Any]], variant: str, profile: str
) -> int | None:
    grouped: dict[tuple[str, int], list[float]] = defaultdict(list)
    for row in trajectories:
        if row["variant"] != variant or not row["selected"]:
            continue
        grouped[(row["profile"], int(row["selection_index"]))].append(
            float(row["scheduler_retrieval_p"])
        )
    beginner = {
        index: mean(values)
        for (label, index), values in grouped.items()
        if label == "beginner"
    }
    target = {
        index: mean(values)
        for (label, index), values in grouped.items()
        if label == profile
    }
    window_size = pass6.pass5.CALIBRATION_WINDOW
    for start in range(ATTEMPTS - window_size + 1):
        window = range(start, start + window_size)
        if all(
            index in beginner
            and index in target
            and abs(target[index] - beginner[index]) >= pass6.pass5.DIVERGENCE_THRESHOLD
            for index in window
        ):
            return start + 1
    return None


def profile_summaries(
    seed_rows: list[dict[str, Any]], trajectories: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    results = []
    for variant in VARIANTS:
        for fixture in FIXTURES:
            group = [
                row
                for row in seed_rows
                if row["variant"] == variant and row["profile"] == fixture.label
            ]
            summary = {"variant": variant, "profile": fixture.label}
            summary.update(
                {field: optional_mean(group, field) for field in SUMMARY_FIELDS}
            )
            summary["calibrated_by_end_fraction"] = mean(
                row["calibrated_by_end"] for row in group
            )
            summary["stable_challenge_band_by_end_fraction"] = mean(
                row["stable_challenge_band_by_end"] for row in group
            )
            summary["attempts_to_diverge_from_beginner"] = (
                0
                if fixture.label == "beginner"
                else attempts_to_diverge_from_beginner(
                    trajectories, variant, fixture.label
                )
            )
            results.append(summary)
    return results


def variant_summaries(
    seed_rows: list[dict[str, Any]], trajectories: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    results = []
    for variant in VARIANTS:
        selected = [
            row for row in trajectories if row["variant"] == variant and row["selected"]
        ]
        observed = [row for row in selected if row["retrieval_observed"]]
        seeds = [row for row in seed_rows if row["variant"] == variant]
        results.append(
            {
                "variant": variant,
                "retrieval_observation_count": len(observed),
                "retrieval_prediction_bias": mean(
                    float(row["scheduler_retrieval_bias"]) for row in observed
                ),
                "retrieval_prediction_mae": mean(
                    abs(float(row["scheduler_retrieval_bias"])) for row in observed
                ),
                "retrieval_prediction_brier": mean(
                    (
                        float(row["scheduler_retrieval_p"])
                        - float(row["retrieval_succeeded"])
                    )
                    ** 2
                    for row in observed
                ),
                "recovery_fraction": optional_mean(seeds, "recovery_fraction"),
                "mean_max_material_selection_fraction": optional_mean(
                    seeds, "max_material_selection_fraction"
                ),
                "mean_max_revisit_gap_days": optional_mean(
                    seeds, "max_revisit_gap_days"
                ),
                "mean_no_admission_count": optional_mean(seeds, "no_admission_count"),
            }
        )
    return results


def phase_summaries(trajectories: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in trajectories:
        if row["selected"] and row["retrieval_observed"]:
            grouped[(row["variant"], row["profile"], row["prediction_phase"])].append(
                row
            )
    results = []
    for (variant, profile, phase), group in sorted(grouped.items()):
        results.append(
            {
                "variant": variant,
                "profile": profile,
                "prediction_phase": phase,
                "retrieval_observation_count": len(group),
                "ordinary_retrieval_bias": mean(
                    float(row["ordinary_retrieval_bias"]) for row in group
                ),
                "scheduler_retrieval_bias": mean(
                    float(row["scheduler_retrieval_bias"]) for row in group
                ),
                "scheduler_retrieval_mae": mean(
                    abs(float(row["scheduler_retrieval_bias"])) for row in group
                ),
                "scheduler_retrieval_brier": mean(
                    (
                        float(row["scheduler_retrieval_p"])
                        - float(row["retrieval_succeeded"])
                    )
                    ** 2
                    for row in group
                ),
                "mean_bridge_weight": mean(
                    float(row["bridge_weight"]) for row in group
                ),
                "mean_interval_information_before": mean(
                    float(row["interval_information_before"]) for row in group
                ),
            }
        )
    return results


def threshold_summaries(trajectories: list[dict[str, Any]]) -> list[dict[str, Any]]:
    control_post_success = [
        row
        for row in trajectories
        if row["variant"] == "control"
        and row["selected"]
        and row["retrieval_observed"]
        and row["prediction_phase"] != "before_first_factual_success"
    ]
    results = []
    for fixture in FIXTURES:
        profile_rows = [
            row for row in control_post_success if row["profile"] == fixture.label
        ]
        for threshold in INFORMATION_THRESHOLDS:
            for interval_phase, predicate in (
                ("underidentified", lambda value, t=threshold: value < t),
                ("identified", lambda value, t=threshold: value >= t),
            ):
                group = [
                    row
                    for row in profile_rows
                    if predicate(float(row["interval_information_before"]))
                ]
                results.append(
                    {
                        "profile": fixture.label,
                        "information_threshold": threshold,
                        "interval_phase": interval_phase,
                        "retrieval_observation_count": len(group),
                        "retrieval_observation_fraction": (
                            len(group) / len(profile_rows) if profile_rows else 0.0
                        ),
                        "ordinary_retrieval_bias": (
                            mean(float(row["ordinary_retrieval_bias"]) for row in group)
                            if group
                            else None
                        ),
                        "ordinary_retrieval_mae": (
                            mean(
                                abs(float(row["ordinary_retrieval_bias"]))
                                for row in group
                            )
                            if group
                            else None
                        ),
                    }
                )
    return results


def check_diagnostic_boundaries() -> None:
    if interval_information(0.999, 0.0, 3.0) != 0.0:
        raise AssertionError("zero interval produced durability information")
    short = interval_information(2.0 ** (-1.0 / 3.0), 1.0, 3.0)
    long = interval_information(2.0 ** (-3.0 / 3.0), 3.0, 3.0)
    if not 0.0 < short < long:
        raise AssertionError("interval information does not grow over useful range")
    ordinary = 0.25
    placement = 0.75
    bridged = blended_prediction(ordinary, placement, BRIDGE_MAX_WEIGHT)
    if not ordinary < bridged < placement:
        raise AssertionError("logit bridge escaped its endpoints")


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def display(value: Any) -> str:
    return "n/a" if value is None else f"{float(value):.3f}"


def report(profiles: list[dict[str, Any]], variants: list[dict[str, Any]]) -> None:
    print("Bridge variants by profile (means across seeds):")
    print(
        "  variant                    profile                         "
        "unneeded_cue low_memory_unguided final_bias"
    )
    for row in profiles:
        print(
            f"  {row['variant']:<26} {row['profile']:<31} "
            f"{display(row['early_unnecessary_cueing_count']):>12} "
            f"{display(row['early_unguided_low_memory_count']):>19} "
            f"{display(row['final_retrieval_bias']):>10}"
        )
    print()
    print("Aggregate guardrails across Pass 7 fixtures:")
    for row in variants:
        print(
            f"  {row['variant']:<26} "
            f"MAE={row['retrieval_prediction_mae']:.3f} "
            f"Brier={row['retrieval_prediction_brier']:.3f} "
            f"recovery={row['recovery_fraction']:.3f} "
            f"max_gap={row['mean_max_revisit_gap_days']:.2f}d"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).with_name("generated"),
    )
    parser.add_argument("--seeds", type=int, default=DEFAULT_SEEDS)
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.seeds < 1 or args.workers < 1:
        raise ValueError("seeds and workers must both be at least 1")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    check_diagnostic_boundaries()
    cases = [
        (variant, fixture, seed)
        for variant in VARIANTS
        for fixture in FIXTURES
        for seed in range(args.seeds)
    ]
    if args.workers == 1:
        case_rows = [run_case(*case) for case in cases]
    else:
        with concurrent.futures.ProcessPoolExecutor(args.workers) as executor:
            variants, fixtures, seeds = zip(*cases, strict=True)
            case_rows = list(executor.map(run_case, variants, fixtures, seeds))

    trajectories = [row for rows in case_rows for row in rows]
    seed_rows = [summarize_seed(rows) for rows in case_rows]
    profiles = profile_summaries(seed_rows, trajectories)
    variants = variant_summaries(seed_rows, trajectories)
    phases = phase_summaries(trajectories)
    thresholds = threshold_summaries(trajectories)
    outputs = {
        "bridge_profile_summary.csv": profiles,
        "bridge_variant_summary.csv": variants,
        "bridge_phase_summary.csv": phases,
        "bridge_threshold_summary.csv": thresholds,
        "bridge_trajectories.csv": trajectories,
    }
    for filename, rows in outputs.items():
        write_csv(args.output_dir / filename, rows)
    report(profiles, variants)
    print()
    for filename in outputs:
        print(f"Wrote {args.output_dir / filename}")


if __name__ == "__main__":
    main()
