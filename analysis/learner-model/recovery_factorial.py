"""Pass 17: factorial recovery-support characterization.

Recovery events are assigned one of six diagnostic actions crossing retained
memory guidance with no, one-step, or floor motor simplification. The action is
applied at every production recovery trigger, without a limiting-dimension
classifier. Production scheduler, estimator, and synthetic truth remain frozen.

Outputs (in --output-dir):
    recovery_factorial_trajectories.csv
    recovery_factorial_events.csv
    recovery_factorial_episodes.csv
    recovery_factorial_seed_summary.csv
    recovery_factorial_profile_summary.csv
    recovery_factorial_variant_summary.csv
    recovery_factorial_dimension_strata.csv
    recovery_factorial_effects.csv
"""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import math
import os
import random
from collections import Counter
from pathlib import Path
from statistics import mean, stdev
from typing import Any

import cold_start_identifiability as pass5
import prior_knowledge_placement as pass10
import recovery_modality as pass12
import supported_selection_intent as pass11
from candidates import InstrumentProfile
from config import load_params as load_scheduler_params
from longitudinal import NoAdmittedCandidate, SchedulerAgent
from model import evidence_weights, predicted_success, update
from params import load_params as load_learner_params
from synthetic import sample_outcome

ATTEMPTS = pass5.ATTEMPTS
SESSION_ATTEMPTS = pass5.SESSION_ATTEMPTS
DAY_STEP = pass5.DAY_STEP
MATERIAL_POOL = pass5.MATERIAL_POOL
FIXTURES = pass10.FIXTURES
DEFAULT_SEEDS = 30
DEFAULT_WORKERS = min(8, os.cpu_count() or 1)

MEMORY_LEVELS = ("off", "on")
MOTOR_LEVELS = ("none", "step", "floor")
VARIANTS = tuple(
    f"memory_{memory}_motor_{motor}"
    for memory in MEMORY_LEVELS
    for motor in MOTOR_LEVELS
)
CONTROL = "memory_on_motor_none"


def variant_levels(variant: str) -> tuple[str, str]:
    _, memory, _, motor = variant.split("_")
    return memory, motor


def choose_action(variant: str, agent, failed, production_recovery, state, now):
    memory_level, motor_level = variant_levels(variant)
    base = failed if memory_level == "off" else production_recovery
    if motor_level == "none":
        return base, True
    if motor_level == "step":
        options = pass12.one_step_motor_candidates(agent.candidates, base)
        if not options:
            return base, False
        return (
            max(
                options,
                key=lambda exercise: (
                    predicted_success(
                        state, exercise, now, agent.learner_params
                    ).execution_p,
                    -exercise.tempo_bpm,
                    -exercise.octaves,
                    exercise.direction == "UP",
                ),
            ),
            True,
        )
    floor = pass12.motor_floor_candidate(agent.candidates, base)
    return (base, False) if floor is None else (floor, floor != base)


def consolidation_variance(state, material_id: str, params) -> float:
    return state.material_memory_for(
        material_id, params
    ).consolidated_log_half_life_variance


def add_future_metrics(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    selected = [row for row in rows if row["selected"]]
    episodes: list[dict[str, Any]] = []
    current: list[dict[str, Any]] = []
    episode_id = 0

    def finish() -> None:
        nonlocal current
        if not current:
            return
        first = current[0]
        episodes.append(
            {
                "variant": first["variant"],
                "memory_guidance": first["memory_guidance"],
                "motor_simplification": first["motor_simplification"],
                "profile": first["profile"],
                "seed": first["seed"],
                "episode_id": first["recovery_episode_id"],
                "material_id": first["material_id"],
                "trigger_dimension": first["trigger_limiting_dimension"],
                "recovery_length": len(current),
                "completed_count": sum(row["completed"] for row in current),
                "completed_first_selection": current[0]["completed"],
                "ended_with_completion": current[-1]["completed"],
            }
        )
        current = []

    for index, row in enumerate(selected):
        if row["scheduler_intent"] == "recovery":
            if not current:
                episode_id += 1
            row["recovery_episode_id"] = episode_id
            current.append(row)
        else:
            finish()
        if row["scheduler_intent"] != "recovery":
            continue

        later_same = [
            candidate
            for candidate in selected[index + 1 :]
            if candidate["material_id"] == row["material_id"]
        ]
        ordinary = next(
            (
                candidate
                for candidate in later_same
                if candidate["scheduler_intent"] == "ordinary"
            ),
            None,
        )
        factual = next(
            (candidate for candidate in later_same if candidate["retrieval_observed"]),
            None,
        )
        next_same = later_same[0] if later_same else None
        next_recovery = (
            next_same
            if next_same is not None and next_same["scheduler_intent"] == "recovery"
            else None
        )
        row["selections_until_ordinary_admission"] = (
            int(ordinary["selection_index"]) - int(row["selection_index"])
            if ordinary is not None
            else ""
        )
        row["selections_until_factual_return"] = (
            int(factual["selection_index"]) - int(row["selection_index"])
            if factual is not None
            else ""
        )
        row["factual_return_within_10"] = (
            factual is not None
            and int(factual["selection_index"]) - int(row["selection_index"]) <= 10
        )
        row["same_dimension_recurred"] = (
            next_recovery is not None
            and next_recovery["trigger_limiting_dimension"]
            == row["trigger_limiting_dimension"]
        )
    finish()
    return episodes


def run_case(
    variant: str, fixture: pass10.Fixture, seed: int
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    truth, material_classes = pass10.build_truth(fixture, seed)
    state = pass5.common_estimator_state(learner_params)
    agent = SchedulerAgent(
        InstrumentProfile(), list(MATERIAL_POOL), scheduler_params, learner_params
    )
    rng = random.Random(seed)
    memory_level, motor_level = variant_levels(variant)
    rows: list[dict[str, Any]] = []
    last_exercise = None
    last_prediction = None
    last_outcome = None
    now = 0.0
    selection_index = 0

    for attempt_index in range(ATTEMPTS):
        if attempt_index and attempt_index % SESSION_ATTEMPTS == 0:
            agent.new_session()
        now += DAY_STEP
        state.propagate(now, learner_params)
        try:
            production_exercise = agent.pick(rng, attempt_index, state, now)
        except NoAdmittedCandidate:
            rows.append(
                {
                    "variant": variant,
                    "memory_guidance": memory_level,
                    "motor_simplification": motor_level,
                    "profile": fixture.label,
                    "seed": seed,
                    "attempt_index": attempt_index,
                    "selection_index": "",
                    "at_days": now,
                    "selected": False,
                    "material_id": "",
                    "scheduler_intent": "none",
                    "retrieval_observed": "",
                }
            )
            continue

        selected_trace = agent.records[-1].selected
        assert selected_trace is not None
        scheduler_intent = pass11.support_intent(selected_trace.challenge_bypass)
        actual_exercise = production_exercise
        trigger_dimension = ""
        action_available = True
        motor_simplification_applied = False
        failed_guidance = ""

        if scheduler_intent == "recovery":
            if (
                last_exercise is None
                or last_prediction is None
                or last_outcome is None
                or last_outcome.retrieval_succeeded is not False
            ):
                raise AssertionError("recovery lacks an immediately preceding failure")
            trigger_dimension = pass12.limiting_dimension(last_prediction)
            failed_guidance = pass5.guidance_level(last_exercise)
            actual_exercise, action_available = choose_action(
                variant,
                agent,
                last_exercise,
                production_exercise,
                state,
                now,
            )
            base = last_exercise if memory_level == "off" else production_exercise
            motor_simplification_applied = (
                motor_level != "none" and actual_exercise != base
            )
            expected_guidance = (
                last_exercise.guidance
                if memory_level == "off"
                else production_exercise.guidance
            )
            if actual_exercise.guidance != expected_guidance:
                raise AssertionError("motor factor changed memory guidance")

        production_prediction = predicted_success(
            state, production_exercise, now, learner_params
        )
        prediction = predicted_success(state, actual_exercise, now, learner_params)
        if scheduler_intent == "recovery" and motor_level != "none":
            base = last_exercise if memory_level == "off" else production_exercise
            base_prediction = predicted_success(state, base, now, learner_params)
            if prediction.execution_p + 1e-12 < base_prediction.execution_p:
                raise AssertionError(
                    "motor simplification lowered execution probability"
                )
            if (
                abs(
                    prediction.material_available_p
                    - base_prediction.material_available_p
                )
                > 1e-12
            ):
                raise AssertionError("motor simplification changed memory availability")

        material_id = actual_exercise.material.material_id
        true_p = pass10.true_retrievability(truth, material_id, now)
        pre_memory_uncertainty = pass11.operative_memory_uncertainty(
            state, material_id, learner_params
        )
        pre_consolidation_variance = consolidation_variance(
            state, material_id, learner_params
        )
        pre_competency_variance = pass11.relevant_competency_variance(
            state, actual_exercise
        )
        pre_execution_variance = pass11.execution_variance(
            state, actual_exercise, learner_params
        )
        outcome = sample_outcome(truth, actual_exercise, now, rng)
        weights = evidence_weights(actual_exercise, outcome)
        update(
            state,
            actual_exercise,
            outcome,
            weights,
            prediction,
            now,
            learner_params,
        )
        post_memory_uncertainty = pass11.operative_memory_uncertainty(
            state, material_id, learner_params
        )
        post_consolidation_variance = consolidation_variance(
            state, material_id, learner_params
        )
        post_competency_variance = pass11.relevant_competency_variance(
            state, actual_exercise
        )
        post_execution_variance = pass11.execution_variance(
            state, actual_exercise, learner_params
        )
        agent.on_outcome(actual_exercise, outcome, now)

        rows.append(
            {
                "variant": variant,
                "memory_guidance": memory_level,
                "motor_simplification": motor_level,
                "profile": fixture.label,
                "seed": seed,
                "attempt_index": attempt_index,
                "selection_index": selection_index,
                "at_days": now,
                "selected": True,
                "material_id": material_id,
                "truth_memory_class": material_classes[material_id],
                "scheduler_intent": scheduler_intent,
                "trigger_limiting_dimension": trigger_dimension,
                "action_available": action_available,
                "motor_simplification_applied": motor_simplification_applied,
                "failed_guidance_level": failed_guidance,
                "production_guidance_level": (
                    pass5.guidance_level(production_exercise)
                    if scheduler_intent == "recovery"
                    else ""
                ),
                "actual_guidance_level": pass5.guidance_level(actual_exercise),
                "production_tempo_bpm": production_exercise.tempo_bpm,
                "actual_tempo_bpm": actual_exercise.tempo_bpm,
                "production_octaves": production_exercise.octaves,
                "actual_octaves": actual_exercise.octaves,
                "production_direction": production_exercise.direction,
                "actual_direction": actual_exercise.direction,
                "production_predicted_execution_p": (production_prediction.execution_p),
                "actual_predicted_execution_p": prediction.execution_p,
                "production_predicted_material_available_p": (
                    production_prediction.material_available_p
                ),
                "actual_predicted_material_available_p": (
                    prediction.material_available_p
                ),
                "predicted_retrieval_p": prediction.independent_retrieval_p,
                "predicted_overall_p": prediction.overall_p,
                "true_retrieval_p": true_p,
                "retrieval_bias": prediction.independent_retrieval_p - true_p,
                "retrieval_observed": outcome.retrieval_succeeded is not None,
                "retrieval_succeeded": (
                    outcome.retrieval_succeeded
                    if outcome.retrieval_succeeded is not None
                    else ""
                ),
                "completed": outcome.completed,
                "memory_evidence_weight": weights.material_memory,
                "memory_uncertainty_reduction": (
                    pre_memory_uncertainty - post_memory_uncertainty
                ),
                "consolidation_variance_reduction": (
                    pre_consolidation_variance - post_consolidation_variance
                ),
                "competency_variance_reduction": (
                    pre_competency_variance - post_competency_variance
                ),
                "execution_variance_reduction": (
                    pre_execution_variance - post_execution_variance
                ),
                "recovery_episode_id": "",
                "selections_until_ordinary_admission": "",
                "selections_until_factual_return": "",
                "factual_return_within_10": "",
                "same_dimension_recurred": "",
            }
        )
        last_exercise = actual_exercise
        last_prediction = prediction
        last_outcome = outcome
        selection_index += 1

    return rows, add_future_metrics(rows)


def optional_mean(rows: list[dict[str, Any]], field: str) -> float | None:
    values = [float(row[field]) for row in rows if row[field] != ""]
    return mean(values) if values else None


def summarize_seed(
    rows: list[dict[str, Any]], episodes: list[dict[str, Any]]
) -> dict[str, Any]:
    selected = [row for row in rows if row["selected"]]
    recovery = [row for row in selected if row["scheduler_intent"] == "recovery"]
    observed = [row for row in selected if row["retrieval_observed"]]
    counts = Counter(row["material_id"] for row in selected)
    first = rows[0]
    return {
        "variant": first["variant"],
        "memory_guidance": first["memory_guidance"],
        "motor_simplification": first["motor_simplification"],
        "profile": first["profile"],
        "seed": first["seed"],
        "recovery_selection_count": len(recovery),
        "recovery_episode_count": len(episodes),
        "mean_recovery_episode_length": (
            mean(float(row["recovery_length"]) for row in episodes) if episodes else 0.0
        ),
        "one_selection_exit_fraction": (
            mean(float(row["recovery_length"] == 1) for row in episodes)
            if episodes
            else None
        ),
        "completed_one_selection_exit_fraction": (
            mean(
                float(row["recovery_length"] == 1 and row["completed_first_selection"])
                for row in episodes
            )
            if episodes
            else None
        ),
        "recovery_completion_fraction": optional_mean(recovery, "completed"),
        "motor_simplification_applied_fraction": (
            optional_mean(recovery, "motor_simplification_applied")
            if first["motor_simplification"] != "none"
            else None
        ),
        "recovery_observation_fraction": optional_mean(recovery, "retrieval_observed"),
        "recovery_same_dimension_recurrence_fraction": optional_mean(
            recovery, "same_dimension_recurred"
        ),
        "mean_selections_until_ordinary_admission": optional_mean(
            recovery, "selections_until_ordinary_admission"
        ),
        "mean_selections_until_factual_return": optional_mean(
            recovery, "selections_until_factual_return"
        ),
        "factual_return_within_10_fraction": optional_mean(
            recovery, "factual_return_within_10"
        ),
        "mean_memory_uncertainty_reduction": optional_mean(
            recovery, "memory_uncertainty_reduction"
        ),
        "mean_consolidation_variance_reduction": optional_mean(
            recovery, "consolidation_variance_reduction"
        ),
        "mean_competency_variance_reduction": optional_mean(
            recovery, "competency_variance_reduction"
        ),
        "mean_execution_variance_reduction": optional_mean(
            recovery, "execution_variance_reduction"
        ),
        "retrieval_prediction_bias": mean(
            float(row["retrieval_bias"]) for row in observed
        ),
        "retrieval_prediction_mae": mean(
            abs(float(row["retrieval_bias"])) for row in observed
        ),
        "retrieval_prediction_brier": mean(
            (float(row["predicted_retrieval_p"]) - float(row["retrieval_succeeded"]))
            ** 2
            for row in observed
        ),
        "max_material_selection_fraction": max(counts.values()) / len(selected),
        "max_revisit_gap_days": pass12.max_revisit_gap(rows),
        "no_admission_count": sum(not row["selected"] for row in rows),
    }


SUMMARY_FIELDS = (
    "recovery_selection_count",
    "recovery_episode_count",
    "mean_recovery_episode_length",
    "one_selection_exit_fraction",
    "completed_one_selection_exit_fraction",
    "recovery_completion_fraction",
    "motor_simplification_applied_fraction",
    "recovery_observation_fraction",
    "recovery_same_dimension_recurrence_fraction",
    "mean_selections_until_ordinary_admission",
    "mean_selections_until_factual_return",
    "factual_return_within_10_fraction",
    "mean_memory_uncertainty_reduction",
    "mean_consolidation_variance_reduction",
    "mean_competency_variance_reduction",
    "mean_execution_variance_reduction",
    "retrieval_prediction_bias",
    "retrieval_prediction_mae",
    "retrieval_prediction_brier",
    "max_material_selection_fraction",
    "max_revisit_gap_days",
    "no_admission_count",
)


def grouped_summaries(
    seed_rows: list[dict[str, Any]], include_profile: bool
) -> list[dict[str, Any]]:
    groups = []
    for variant in VARIANTS:
        profiles = (
            [fixture.label for fixture in FIXTURES] if include_profile else [None]
        )
        for profile in profiles:
            rows = [
                row
                for row in seed_rows
                if row["variant"] == variant
                and (profile is None or row["profile"] == profile)
            ]
            memory_level, motor_level = variant_levels(variant)
            summary: dict[str, Any] = {
                "variant": variant,
                "memory_guidance": memory_level,
                "motor_simplification": motor_level,
            }
            if profile is not None:
                summary["profile"] = profile
            for field in SUMMARY_FIELDS:
                values = [float(row[field]) for row in rows if row[field] is not None]
                summary[field] = mean(values) if values else None
            groups.append(summary)
    return groups


def dimension_strata(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result = []
    dimensions = ("memory", "execution", "topology")
    for variant in VARIANTS:
        for profile in [fixture.label for fixture in FIXTURES] + ["all"]:
            for dimension in dimensions:
                rows = [
                    row
                    for row in events
                    if row["variant"] == variant
                    and row["trigger_limiting_dimension"] == dimension
                    and (profile == "all" or row["profile"] == profile)
                ]
                if not rows:
                    continue
                result.append(
                    {
                        "variant": variant,
                        "memory_guidance": rows[0]["memory_guidance"],
                        "motor_simplification": rows[0]["motor_simplification"],
                        "profile": profile,
                        "trigger_limiting_dimension": dimension,
                        "recovery_selection_count": len(rows),
                        "motor_simplification_applied_fraction": mean(
                            float(row["motor_simplification_applied"]) for row in rows
                        ),
                        "recovery_completion_fraction": mean(
                            float(row["completed"]) for row in rows
                        ),
                        "recovery_observation_fraction": mean(
                            float(row["retrieval_observed"]) for row in rows
                        ),
                        "mean_predicted_retrieval_p": mean(
                            float(row["predicted_retrieval_p"]) for row in rows
                        ),
                        "mean_predicted_overall_p": mean(
                            float(row["predicted_overall_p"]) for row in rows
                        ),
                        "mean_memory_uncertainty_reduction": optional_mean(
                            rows, "memory_uncertainty_reduction"
                        ),
                        "mean_consolidation_variance_reduction": optional_mean(
                            rows, "consolidation_variance_reduction"
                        ),
                        "mean_competency_variance_reduction": optional_mean(
                            rows, "competency_variance_reduction"
                        ),
                        "mean_execution_variance_reduction": optional_mean(
                            rows, "execution_variance_reduction"
                        ),
                    }
                )
    return result


def factorial_effects(seed_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    effects: list[dict[str, Any]] = []
    profiles = [fixture.label for fixture in FIXTURES]
    for profile in profiles + ["all"]:
        rows = (
            seed_rows
            if profile == "all"
            else [row for row in seed_rows if row["profile"] == profile]
        )
        cells = {
            (row["profile"], int(row["seed"]), row["variant"]): row for row in rows
        }
        units = sorted({(row["profile"], int(row["seed"])) for row in rows})
        contrasts = []
        for motor in MOTOR_LEVELS:
            contrasts.append(
                (
                    f"memory_on_minus_off_at_{motor}",
                    f"memory_on_motor_{motor}",
                    f"memory_off_motor_{motor}",
                )
            )
        for memory_level in MEMORY_LEVELS:
            for motor in ("step", "floor"):
                contrasts.append(
                    (
                        f"{motor}_minus_none_at_memory_{memory_level}",
                        f"memory_{memory_level}_motor_{motor}",
                        f"memory_{memory_level}_motor_none",
                    )
                )
        for motor in ("step", "floor"):
            for field in SUMMARY_FIELDS:
                estimates = []
                for unit_profile, seed in units:
                    values = [
                        cells[(unit_profile, seed, f"memory_{memory}_motor_{dose}")][
                            field
                        ]
                        for memory, dose in (
                            ("on", motor),
                            ("on", "none"),
                            ("off", motor),
                            ("off", "none"),
                        )
                    ]
                    if all(value is not None for value in values):
                        estimates.append(values[0] - values[1] - values[2] + values[3])
                if estimates:
                    effects.append(
                        {
                            "profile": profile,
                            "metric": field,
                            "contrast": f"memory_x_{motor}_interaction",
                            "estimate": mean(estimates),
                            "paired_standard_error": (
                                stdev(estimates) / math.sqrt(len(estimates))
                                if len(estimates) > 1
                                else 0.0
                            ),
                            "paired_sample_count": len(estimates),
                        }
                    )
        for contrast, high, low in contrasts:
            for field in SUMMARY_FIELDS:
                estimates = []
                for unit_profile, seed in units:
                    high_value = cells[(unit_profile, seed, high)][field]
                    low_value = cells[(unit_profile, seed, low)][field]
                    if high_value is not None and low_value is not None:
                        estimates.append(high_value - low_value)
                if estimates:
                    effects.append(
                        {
                            "profile": profile,
                            "metric": field,
                            "contrast": contrast,
                            "estimate": mean(estimates),
                            "paired_standard_error": (
                                stdev(estimates) / math.sqrt(len(estimates))
                                if len(estimates) > 1
                                else 0.0
                            ),
                            "paired_sample_count": len(estimates),
                        }
                    )
    return effects


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def display(value: Any) -> str:
    return "n/a" if value is None else f"{float(value):.3f}"


def report(profile_rows, variant_rows, effects) -> None:
    print("Pass 17 factorial recovery support:")
    print(
        "  variant                    complete length one_exit observe "
        "factual_return MAE Brier"
    )
    for row in variant_rows:
        print(
            f"  {row['variant']:<26} "
            f"{display(row['recovery_completion_fraction']):>8} "
            f"{display(row['mean_recovery_episode_length']):>6} "
            f"{display(row['completed_one_selection_exit_fraction']):>8} "
            f"{display(row['recovery_observation_fraction']):>7} "
            f"{display(row['mean_selections_until_factual_return']):>14} "
            f"{display(row['retrieval_prediction_mae']):>5} "
            f"{display(row['retrieval_prediction_brier']):>5}"
        )

    for motor in ("step", "floor"):
        print(f"\nHybrid {motor} versus production control by profile:")
        hybrid = f"memory_on_motor_{motor}"
        for profile in [fixture.label for fixture in FIXTURES]:
            control = next(
                row
                for row in profile_rows
                if row["profile"] == profile and row["variant"] == CONTROL
            )
            candidate = next(
                row
                for row in profile_rows
                if row["profile"] == profile and row["variant"] == hybrid
            )
            print(
                f"  {profile:<31} "
                f"completion={candidate['recovery_completion_fraction'] - control['recovery_completion_fraction']:+.3f} "
                f"length={candidate['mean_recovery_episode_length'] - control['mean_recovery_episode_length']:+.3f} "
                f"MAE={candidate['retrieval_prediction_mae'] - control['retrieval_prediction_mae']:+.4f} "
                f"Brier={candidate['retrieval_prediction_brier'] - control['retrieval_prediction_brier']:+.4f}"
            )
    interactions = [
        row
        for row in effects
        if row["profile"] == "all"
        and row["metric"]
        in {"recovery_completion_fraction", "mean_recovery_episode_length"}
        and "interaction" in row["contrast"]
    ]
    print("\nAggregate factorial interactions:")
    for row in interactions:
        print(
            f"  {row['contrast']:<28} {row['metric']:<37} {float(row['estimate']):+.3f}"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir", type=Path, default=Path(__file__).with_name("generated")
    )
    parser.add_argument("--seeds", type=int, default=DEFAULT_SEEDS)
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    return parser.parse_args()


def run_case_star(args):
    return run_case(*args)


def main() -> None:
    args = parse_args()
    if args.seeds < 1 or args.workers < 1:
        raise SystemExit("--seeds and --workers must be positive")
    jobs = [
        (variant, fixture, seed)
        for variant in VARIANTS
        for fixture in FIXTURES
        for seed in range(args.seeds)
    ]
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        chunks = list(pool.map(run_case_star, jobs))
    trajectories = [row for rows, _ in chunks for row in rows]
    episodes = [row for _, episode_rows in chunks for row in episode_rows]
    events = [
        row
        for row in trajectories
        if row["selected"] and row["scheduler_intent"] == "recovery"
    ]
    seed_rows = [summarize_seed(rows, episode_rows) for rows, episode_rows in chunks]
    profile_rows = grouped_summaries(seed_rows, include_profile=True)
    variant_rows = grouped_summaries(seed_rows, include_profile=False)
    strata = dimension_strata(events)
    effects = factorial_effects(seed_rows)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    artifacts = {
        "recovery_factorial_trajectories.csv": trajectories,
        "recovery_factorial_events.csv": events,
        "recovery_factorial_episodes.csv": episodes,
        "recovery_factorial_seed_summary.csv": seed_rows,
        "recovery_factorial_profile_summary.csv": profile_rows,
        "recovery_factorial_variant_summary.csv": variant_rows,
        "recovery_factorial_dimension_strata.csv": strata,
        "recovery_factorial_effects.csv": effects,
    }
    for name, rows in artifacts.items():
        if rows:
            write_csv(args.output_dir / name, rows)
    report(profile_rows, variant_rows, effects)


if __name__ == "__main__":
    main()
