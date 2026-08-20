"""Pass 12: dimension-targeted recovery modality characterization.

Execution-limited factual failures can receive an existing exercise sibling
that reduces motor challenge without adding memory guidance. Memory-limited and
topology-limited failures retain production recovery. All interventions are
diagnostic sidecars; production scheduler and learner semantics remain frozen.

Outputs (in --output-dir):
    recovery_modality_trajectories.csv
    recovery_modality_events.csv
    recovery_modality_episodes.csv
    recovery_modality_seed_summary.csv
    recovery_modality_profile_summary.csv
    recovery_modality_variant_summary.csv
"""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import os
import random
from collections import Counter, defaultdict
from itertools import pairwise
from pathlib import Path
from statistics import mean
from typing import Any

import cold_start_identifiability as pass5
import prior_knowledge_placement as pass10
import supported_selection_intent as pass11
from candidates import DIRECTIONS, OCTAVES, TEMPI, InstrumentProfile
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

VARIANTS = ("control", "dimension_targeted", "motor_floor_diagnostic")


def same_recovery_family(candidate, failed) -> bool:
    return (
        candidate.material == failed.material
        and candidate.hands == failed.hands
        and candidate.guidance == failed.guidance
    )


def one_step_motor_candidates(candidates, failed) -> list:
    tempo_index = TEMPI.index(failed.tempo_bpm)
    octave_index = OCTAVES.index(failed.octaves)
    direction_index = DIRECTIONS.index(failed.direction)
    desired: set[tuple[float, int, str]] = set()
    if tempo_index > 0:
        desired.add((TEMPI[tempo_index - 1], failed.octaves, failed.direction))
    if octave_index > 0:
        desired.add((failed.tempo_bpm, OCTAVES[octave_index - 1], failed.direction))
    if direction_index > 0:
        desired.add((failed.tempo_bpm, failed.octaves, DIRECTIONS[direction_index - 1]))
    return [
        candidate
        for candidate in candidates
        if same_recovery_family(candidate, failed)
        and (candidate.tempo_bpm, candidate.octaves, candidate.direction) in desired
    ]


def motor_floor_candidate(candidates, failed):
    return next(
        (
            candidate
            for candidate in candidates
            if same_recovery_family(candidate, failed)
            and candidate.tempo_bpm == min(TEMPI)
            and candidate.octaves == min(OCTAVES)
            and candidate.direction == DIRECTIONS[0]
        ),
        None,
    )


def choose_motor_recovery(variant: str, agent, failed, state, now):
    if variant == "dimension_targeted":
        options = one_step_motor_candidates(agent.candidates, failed)
        if not options:
            return None
        return max(
            options,
            key=lambda exercise: (
                predicted_success(
                    state, exercise, now, agent.learner_params
                ).execution_p,
                -exercise.tempo_bpm,
                -exercise.octaves,
                exercise.direction == DIRECTIONS[0],
            ),
        )
    if variant == "motor_floor_diagnostic":
        floor = motor_floor_candidate(agent.candidates, failed)
        return None if floor == failed else floor
    return None


def limiting_dimension(prediction) -> str:
    return pass11.predicted_limiting_dimension(prediction)


def max_revisit_gap(rows: list[dict[str, Any]]) -> float:
    visits: defaultdict[str, list[float]] = defaultdict(list)
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


def add_future_metrics(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    selected = [row for row in rows if row["selected"]]
    episode_id = 0
    current_episode: list[dict[str, Any]] = []
    episodes: list[dict[str, Any]] = []

    def finish_episode() -> None:
        nonlocal current_episode
        if not current_episode:
            return
        first = current_episode[0]
        episodes.append(
            {
                "variant": first["variant"],
                "profile": first["profile"],
                "seed": first["seed"],
                "episode_id": first["recovery_episode_id"],
                "material_id": first["material_id"],
                "trigger_dimension": first["trigger_limiting_dimension"],
                "recovery_length": len(current_episode),
                "targeted_recovery_count": sum(
                    row["targeted_recovery_applied"] for row in current_episode
                ),
                "completed_recovery_count": sum(
                    row["completed"] for row in current_episode
                ),
                "ended_with_completed_recovery": current_episode[-1]["completed"],
            }
        )
        current_episode = []

    for index, row in enumerate(selected):
        if row["scheduler_intent"] == "recovery":
            if not current_episode:
                episode_id += 1
            row["recovery_episode_id"] = episode_id
            current_episode.append(row)
        else:
            finish_episode()

        if row["scheduler_intent"] != "recovery":
            continue
        later_same_material = [
            candidate
            for candidate in selected[index + 1 :]
            if candidate["material_id"] == row["material_id"]
        ]
        ordinary = next(
            (
                candidate
                for candidate in later_same_material
                if candidate["scheduler_intent"] == "ordinary"
            ),
            None,
        )
        next_same_material = later_same_material[0] if later_same_material else None
        next_recovery = (
            next_same_material
            if next_same_material is not None
            and next_same_material["scheduler_intent"] == "recovery"
            else None
        )
        row["selections_until_ordinary_admission"] = (
            int(ordinary["selection_index"]) - int(row["selection_index"])
            if ordinary is not None
            else ""
        )
        row["same_dimension_recurred"] = (
            next_recovery is not None
            and next_recovery["trigger_limiting_dimension"]
            == row["trigger_limiting_dimension"]
        )
        row["selections_until_next_recovery"] = (
            int(next_recovery["selection_index"]) - int(row["selection_index"])
            if next_recovery is not None
            else ""
        )
    finish_episode()
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
    rows: list[dict[str, Any]] = []
    last_actual_exercise = None
    last_actual_prediction = None
    last_actual_outcome = None
    now = 0.0
    selection_index = 0

    for attempt_index in range(ATTEMPTS):
        if attempt_index and attempt_index % SESSION_ATTEMPTS == 0:
            agent.new_session()
        now += DAY_STEP
        state.propagate(now, learner_params)

        try:
            control_exercise = agent.pick(rng, attempt_index, state, now)
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
                    "scheduler_intent": "none",
                    "recovery_episode_id": "",
                    "selections_until_ordinary_admission": "",
                    "same_dimension_recurred": "",
                    "selections_until_next_recovery": "",
                }
            )
            continue

        selected = agent.records[-1].selected
        assert selected is not None
        scheduler_intent = pass11.support_intent(selected.challenge_bypass)
        trigger_dimension = ""
        recovery_action = "not_recovery"
        targeted_applied = False
        actual_exercise = control_exercise

        if scheduler_intent == "recovery":
            if (
                last_actual_exercise is None
                or last_actual_prediction is None
                or last_actual_outcome is None
                or last_actual_outcome.retrieval_succeeded is not False
            ):
                raise AssertionError("recovery lacks an immediately preceding failure")
            trigger_dimension = limiting_dimension(last_actual_prediction)
            recovery_action = "memory_guidance"
            if variant != "control" and trigger_dimension == "execution":
                target = choose_motor_recovery(
                    variant, agent, last_actual_exercise, state, now
                )
                if target is not None:
                    actual_exercise = target
                    targeted_applied = True
                    recovery_action = (
                        "motor_step"
                        if variant == "dimension_targeted"
                        else "motor_floor"
                    )
                else:
                    recovery_action = "motor_unavailable_fallback"

        control_prediction = predicted_success(
            state, control_exercise, now, learner_params
        )
        prediction = predicted_success(state, actual_exercise, now, learner_params)
        if targeted_applied:
            if actual_exercise.guidance != last_actual_exercise.guidance:
                raise AssertionError("motor recovery changed memory guidance")
            if prediction.execution_p + 1e-12 < control_prediction.execution_p:
                raise AssertionError("motor recovery increased execution challenge")
            if (
                prediction.material_available_p
                > control_prediction.material_available_p + 1e-12
            ):
                raise AssertionError("motor recovery increased material availability")

        material_id = actual_exercise.material.material_id
        true_p = pass10.true_retrievability(truth, material_id, now)
        pre_memory_uncertainty = pass11.operative_memory_uncertainty(
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
                "profile": fixture.label,
                "seed": seed,
                "attempt_index": attempt_index,
                "selection_index": selection_index,
                "at_days": now,
                "selected": True,
                "material_id": material_id,
                "truth_memory_class": material_classes[material_id],
                "scheduler_intent": scheduler_intent,
                "recovery_action": recovery_action,
                "targeted_recovery_applied": targeted_applied,
                "trigger_limiting_dimension": trigger_dimension,
                "trigger_guidance_level": (
                    pass5.guidance_level(last_actual_exercise)
                    if scheduler_intent == "recovery"
                    else ""
                ),
                "control_recovery_guidance_level": (
                    pass5.guidance_level(control_exercise)
                    if scheduler_intent == "recovery"
                    else ""
                ),
                "actual_guidance_level": pass5.guidance_level(actual_exercise),
                "control_tempo_bpm": control_exercise.tempo_bpm,
                "actual_tempo_bpm": actual_exercise.tempo_bpm,
                "control_octaves": control_exercise.octaves,
                "actual_octaves": actual_exercise.octaves,
                "control_direction": control_exercise.direction,
                "actual_direction": actual_exercise.direction,
                "control_predicted_execution_p": control_prediction.execution_p,
                "actual_predicted_execution_p": prediction.execution_p,
                "execution_probability_gain": (
                    prediction.execution_p - control_prediction.execution_p
                ),
                "control_predicted_material_available_p": (
                    control_prediction.material_available_p
                ),
                "actual_predicted_material_available_p": (
                    prediction.material_available_p
                ),
                "material_availability_change_vs_control": (
                    prediction.material_available_p
                    - control_prediction.material_available_p
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
                "competency_variance_reduction": (
                    pre_competency_variance - post_competency_variance
                ),
                "execution_variance_reduction": (
                    pre_execution_variance - post_execution_variance
                ),
                "recovery_episode_id": "",
                "selections_until_ordinary_admission": "",
                "same_dimension_recurred": "",
                "selections_until_next_recovery": "",
            }
        )
        last_actual_exercise = actual_exercise
        last_actual_prediction = prediction
        last_actual_outcome = outcome
        selection_index += 1

    episodes = add_future_metrics(rows)
    return rows, episodes


def optional_mean(rows: list[dict[str, Any]], field: str) -> float | None:
    values = [float(row[field]) for row in rows if row[field] != ""]
    return mean(values) if values else None


def summarize_seed(
    rows: list[dict[str, Any]], episodes: list[dict[str, Any]]
) -> dict[str, Any]:
    selected = [row for row in rows if row["selected"]]
    recovery = [row for row in selected if row["scheduler_intent"] == "recovery"]
    execution_recovery = [
        row for row in recovery if row["trigger_limiting_dimension"] == "execution"
    ]
    observed_execution_recovery = [
        row for row in execution_recovery if row["retrieval_observed"]
    ]
    observed = [row for row in selected if row["retrieval_observed"]]
    counts = Counter(row["material_id"] for row in selected)
    first = rows[0]
    return {
        "variant": first["variant"],
        "profile": first["profile"],
        "seed": first["seed"],
        "recovery_selection_count": len(recovery),
        "recovery_episode_count": len(episodes),
        "mean_recovery_episode_length": (
            mean(float(row["recovery_length"]) for row in episodes) if episodes else 0.0
        ),
        "execution_recovery_count": len(execution_recovery),
        "targeted_recovery_count": sum(
            row["targeted_recovery_applied"] for row in recovery
        ),
        "targeted_recovery_availability_fraction": (
            mean(
                row["recovery_action"] != "motor_unavailable_fallback"
                for row in execution_recovery
            )
            if execution_recovery and first["variant"] != "control"
            else None
        ),
        "recovery_completion_fraction": (
            mean(float(row["completed"]) for row in recovery) if recovery else None
        ),
        "execution_recovery_completion_fraction": (
            mean(float(row["completed"]) for row in execution_recovery)
            if execution_recovery
            else None
        ),
        "execution_recovery_observation_fraction": (
            mean(float(row["retrieval_observed"]) for row in execution_recovery)
            if execution_recovery
            else None
        ),
        "execution_recovery_retrieval_success_fraction": (
            mean(
                float(row["retrieval_succeeded"]) for row in observed_execution_recovery
            )
            if observed_execution_recovery
            else None
        ),
        "execution_recovery_same_dimension_recurrence_fraction": (
            mean(float(row["same_dimension_recurred"]) for row in execution_recovery)
            if execution_recovery
            else None
        ),
        "mean_selections_until_ordinary_admission": optional_mean(
            recovery, "selections_until_ordinary_admission"
        ),
        "mean_execution_probability_gain": optional_mean(
            execution_recovery, "execution_probability_gain"
        ),
        "mean_material_availability_change_vs_control": optional_mean(
            execution_recovery, "material_availability_change_vs_control"
        ),
        "mean_memory_uncertainty_reduction": optional_mean(
            recovery, "memory_uncertainty_reduction"
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
        "max_revisit_gap_days": max_revisit_gap(rows),
        "no_admission_count": sum(not row["selected"] for row in rows),
    }


SUMMARY_FIELDS = (
    "recovery_selection_count",
    "recovery_episode_count",
    "mean_recovery_episode_length",
    "execution_recovery_count",
    "targeted_recovery_count",
    "targeted_recovery_availability_fraction",
    "recovery_completion_fraction",
    "execution_recovery_completion_fraction",
    "execution_recovery_observation_fraction",
    "execution_recovery_retrieval_success_fraction",
    "execution_recovery_same_dimension_recurrence_fraction",
    "mean_selections_until_ordinary_admission",
    "mean_execution_probability_gain",
    "mean_material_availability_change_vs_control",
    "mean_memory_uncertainty_reduction",
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
    keys = (
        [(variant, fixture.label) for variant in VARIANTS for fixture in FIXTURES]
        if include_profile
        else [(variant, None) for variant in VARIANTS]
    )
    result = []
    for variant, profile in keys:
        group = [
            row
            for row in seed_rows
            if row["variant"] == variant
            and (profile is None or row["profile"] == profile)
        ]
        summary: dict[str, Any] = {"variant": variant}
        if profile is not None:
            summary["profile"] = profile
        summary.update(
            {
                field: mean(
                    float(row[field]) for row in group if row[field] is not None
                )
                if any(row[field] is not None for row in group)
                else None
                for field in SUMMARY_FIELDS
            }
        )
        result.append(summary)
    return result


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def display(value: Any) -> str:
    return "n/a" if value is None else f"{float(value):.3f}"


def report(
    profile_rows: list[dict[str, Any]], variant_rows: list[dict[str, Any]]
) -> None:
    print("Pass 12 recovery modality by profile:")
    print(
        "  variant                  profile                         recovery "
        "exec_complete recurrence observe ordinary_delay"
    )
    for row in profile_rows:
        print(
            f"  {row['variant']:<24} {row['profile']:<31} "
            f"{display(row['recovery_selection_count']):>8} "
            f"{display(row['execution_recovery_completion_fraction']):>13} "
            f"{display(row['execution_recovery_same_dimension_recurrence_fraction']):>10} "
            f"{display(row['execution_recovery_observation_fraction']):>7} "
            f"{display(row['mean_selections_until_ordinary_admission']):>14}"
        )
    print()
    print("Aggregate guardrails:")
    for row in variant_rows:
        print(
            f"  {row['variant']:<24} "
            f"MAE={display(row['retrieval_prediction_mae'])} "
            f"Brier={display(row['retrieval_prediction_brier'])} "
            f"concentration={display(row['max_material_selection_fraction'])} "
            f"max_gap={display(row['max_revisit_gap_days'])}d"
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
    trajectories = [row for rows, _episodes in chunks for row in rows]
    episodes = [row for _rows, episode_rows in chunks for row in episode_rows]
    events = [
        row
        for row in trajectories
        if row["selected"] and row["scheduler_intent"] == "recovery"
    ]
    seed_rows = [summarize_seed(rows, episode_rows) for rows, episode_rows in chunks]
    profile_rows = grouped_summaries(seed_rows, include_profile=True)
    variant_rows = grouped_summaries(seed_rows, include_profile=False)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    artifacts = {
        "recovery_modality_trajectories.csv": trajectories,
        "recovery_modality_events.csv": events,
        "recovery_modality_episodes.csv": episodes,
        "recovery_modality_seed_summary.csv": seed_rows,
        "recovery_modality_profile_summary.csv": profile_rows,
        "recovery_modality_variant_summary.csv": variant_rows,
    }
    for name, rows in artifacts.items():
        if rows:
            write_csv(args.output_dir / name, rows)
    report(profile_rows, variant_rows)


if __name__ == "__main__":
    main()
