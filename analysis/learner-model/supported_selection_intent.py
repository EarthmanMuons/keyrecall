"""Pass 11: supported-selection intent and cost characterization.

This diagnostic decomposes post-observation supported selections by scheduler
intent. It records expected information, realized state changes, later guidance
fading, and an unpresented unguided-sibling counterfactual. It changes neither
the production scheduler nor the learner model.

Outputs (in --output-dir):
    supported_selection_events.csv
    supported_selection_profile_summary.csv
    guidance_probe_summary.csv
    recovery_support_summary.csv
    supported_counterfactual_summary.csv
"""

from __future__ import annotations

import argparse
import concurrent.futures
import copy
import csv
import dataclasses
import os
import random
from collections import defaultdict
from pathlib import Path
from statistics import mean
from typing import Any

import cold_start_identifiability as pass5
import prior_knowledge_placement as pass10
from candidates import InstrumentProfile
from config import load_params as load_scheduler_params
from domain import MOTOR_COMPETENCIES, GuidanceContext, structural_q
from longitudinal import NoAdmittedCandidate, SchedulerAgent
from model import evidence_weights, predicted_success, update
from params import load_params as load_learner_params
from pipeline import StageStatus, run_pipeline
from synthetic import sample_outcome

ATTEMPTS = pass5.ATTEMPTS
SESSION_ATTEMPTS = pass5.SESSION_ATTEMPTS
DAY_STEP = pass5.DAY_STEP
EARLY_SELECTIONS = pass5.EARLY_ATTEMPTS
MATERIAL_POOL = pass5.MATERIAL_POOL
FIXTURES = pass10.FIXTURES
DEFAULT_SEEDS = 30
DEFAULT_WORKERS = min(8, os.cpu_count() or 1)


def operative_memory_uncertainty(state, material_id: str, params) -> float:
    memory = state.material_memory.get(material_id)
    if memory is None:
        return params.material_memory.prior_uncertainty
    if memory.memory_anchor_at is None:
        return memory.cold_start_uncertainty
    return memory.current_half_life_uncertainty


def relevant_competency_variance(state, exercise) -> float:
    q = structural_q(exercise)
    return sum(state.competencies[key].variance for key, value in q.items() if value)


def execution_variance(state, exercise, params) -> float:
    key = (exercise.material.material_id, exercise.hands)
    execution = state.material_execution.get(key)
    return (
        execution.residual_variance
        if execution is not None
        else params.material_execution.prior_variance
    )


def motor_competency_mean(state, exercise) -> float:
    q = structural_q(exercise)
    values = [
        state.competencies[key].mean
        for key, loading in q.items()
        if loading and key in MOTOR_COMPETENCIES
    ]
    return mean(values) if values else 0.0


def support_intent(bypass: str | None) -> str:
    if bypass in ("recovery", "guidance_probe", "bootstrap_probe"):
        return bypass
    return "ordinary"


def counterfactual_reason(trace, scheduler_params, recovery_active: bool) -> str:
    if trace.priority_status is StageStatus.REACHED:
        return "admitted"
    if not trace.safety_allowed:
        return "safety"
    if recovery_active:
        return "recovery_exclusive"
    if trace.prediction.overall_p < scheduler_params.challenge.p_min:
        return "too_hard"
    if trace.prediction.overall_p > scheduler_params.challenge.p_max:
        return "too_easy"
    return "not_admitted_other"


def predicted_limiting_dimension(prediction) -> str:
    components = {
        "memory": prediction.material_available_p,
        "execution": prediction.execution_p,
        "topology": prediction.topology_p,
    }
    return min(components, key=components.__getitem__)


def row_limiting_dimension(row: dict[str, Any]) -> str:
    components = {
        "memory": float(row["pre_predicted_material_available_p"]),
        "execution": float(row["pre_predicted_execution_p"]),
        "topology": float(row["pre_predicted_topology_p"]),
    }
    return min(components, key=components.__getitem__)


def rank_terms_changed(before, after) -> bool:
    return any(
        abs(a - b) > 1e-12
        for a, b in (
            (before.retention, after.retention),
            (before.information, after.information),
            (before.diversity, after.diversity),
            (before.goals, after.goals),
        )
    )


def add_later_fading(rows: list[dict[str, Any]]) -> None:
    selected = [row for row in rows if row["selected"]]
    for index, row in enumerate(selected):
        if not row["supported"]:
            continue
        current_rank = int(row["guidance_rank"])
        later = next(
            (
                candidate
                for candidate in selected[index + 1 :]
                if candidate["material_id"] == row["material_id"]
                and int(candidate["guidance_rank"]) < current_rank
            ),
            None,
        )
        row["later_guidance_faded"] = later is not None
        row["selections_until_guidance_faded"] = (
            int(later["selection_index"]) - int(row["selection_index"])
            if later is not None
            else ""
        )


def run_case(fixture: pass10.Fixture, seed: int) -> list[dict[str, Any]]:
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    truth, material_classes = pass10.build_truth(fixture, seed)
    state = pass5.common_estimator_state(learner_params)
    agent = SchedulerAgent(
        InstrumentProfile(), list(MATERIAL_POOL), scheduler_params, learner_params
    )
    rng = random.Random(seed)
    consecutive_factual_failures: defaultdict[str, int] = defaultdict(int)
    rows: list[dict[str, Any]] = []
    now = 0.0
    selection_index = 0

    for attempt_index in range(ATTEMPTS):
        if attempt_index and attempt_index % SESSION_ATTEMPTS == 0:
            agent.new_session()
        now += DAY_STEP
        state.propagate(now, learner_params)
        session_before = copy.deepcopy(agent.session)

        try:
            exercise = agent.pick(rng, attempt_index, state, now)
        except NoAdmittedCandidate:
            rows.append(
                {
                    "profile": fixture.label,
                    "seed": seed,
                    "attempt_index": attempt_index,
                    "selection_index": "",
                    "at_days": now,
                    "selected": False,
                    "material_id": "",
                    "truth_memory_class": "",
                    "guidance_level": "none",
                    "guidance_rank": "",
                    "supported": False,
                    "support_intent": "none",
                    "early_selection": False,
                }
            )
            continue

        selected = agent.records[-1].selected
        assert selected is not None
        material_id = exercise.material.material_id
        guidance_level = pass5.guidance_level(exercise)
        guidance_rank = pass10.guidance_rank(exercise.guidance)
        supported = guidance_rank > 0
        intent = support_intent(selected.challenge_bypass)
        previous_selected = next(
            (row for row in reversed(rows) if row["selected"]), None
        )
        recovery_trigger = previous_selected if intent == "recovery" else None
        if (
            recovery_trigger is not None
            and recovery_trigger["retrieval_succeeded"] is not False
        ):
            raise AssertionError("recovery was not preceded by a factual failure")
        true_p = pass10.true_retrievability(truth, material_id, now)
        memory_before = state.material_memory.get(material_id)
        memory_anchor_before = (
            memory_before.memory_anchor_at if memory_before is not None else None
        )
        last_success_before = (
            memory_before.factual_last_retrieval_at
            if memory_before is not None
            else None
        )
        pre_memory_uncertainty = operative_memory_uncertainty(
            state, material_id, learner_params
        )
        pre_consolidation_variance = (
            memory_before.consolidated_log_half_life_variance
            if memory_before is not None
            else learner_params.material_memory.consolidation_prior_log_variance
        )
        pre_current_half_life = (
            memory_before.current_half_life_days
            if memory_before is not None
            else learner_params.material_memory.initial_current_half_life_days
        )
        pre_consolidated_half_life = (
            memory_before.consolidated_half_life_days
            if memory_before is not None
            else learner_params.material_memory.initial_current_half_life_days
        )
        pre_competency_variance = relevant_competency_variance(state, exercise)
        pre_execution_variance = execution_variance(state, exercise, learner_params)
        pre_motor_mean = motor_competency_mean(state, exercise)

        unguided = dataclasses.replace(exercise, guidance=GuidanceContext())
        counterfactual = run_pipeline(
            state,
            session_before,
            [unguided],
            scheduler_params,
            learner_params,
            now,
        )[0]
        recovery_active = session_before.last_failed_exercise is not None
        counterfactual_rejection = counterfactual_reason(
            counterfactual, scheduler_params, recovery_active
        )
        counterfactual_limiting = predicted_limiting_dimension(
            counterfactual.prediction
        )

        prediction = predicted_success(state, exercise, now, learner_params)
        outcome = sample_outcome(truth, exercise, now, rng)
        weights = evidence_weights(exercise, outcome)
        update(
            state,
            exercise,
            outcome,
            weights,
            prediction,
            now,
            learner_params,
        )

        post_prediction = predicted_success(state, exercise, now, learner_params)
        post_trace = run_pipeline(
            state,
            session_before,
            [exercise],
            scheduler_params,
            learner_params,
            now,
        )[0]
        memory_after = state.material_memory[material_id]
        post_memory_uncertainty = operative_memory_uncertainty(
            state, material_id, learner_params
        )
        post_competency_variance = relevant_competency_variance(state, exercise)
        post_execution_variance = execution_variance(state, exercise, learner_params)
        post_motor_mean = motor_competency_mean(state, exercise)
        agent.on_outcome(exercise, outcome, now)

        rows.append(
            {
                "profile": fixture.label,
                "seed": seed,
                "attempt_index": attempt_index,
                "selection_index": selection_index,
                "at_days": now,
                "selected": True,
                "material_id": material_id,
                "truth_memory_class": material_classes[material_id],
                "guidance_level": guidance_level,
                "guidance_rank": guidance_rank,
                "supported": supported,
                "support_intent": intent,
                "early_selection": selection_index < EARLY_SELECTIONS,
                "true_retrieval_p": true_p,
                "high_true_retrieval": true_p >= 0.70,
                "retrieval_observed": outcome.retrieval_succeeded is not None,
                "retrieval_succeeded": (
                    outcome.retrieval_succeeded
                    if outcome.retrieval_succeeded is not None
                    else ""
                ),
                "completed": outcome.completed,
                "memory_evidence_weight": weights.material_memory,
                "expected_information": selected.information,
                "pre_predicted_retrieval_p": prediction.independent_retrieval_p,
                "pre_predicted_material_available_p": prediction.material_available_p,
                "pre_predicted_execution_p": prediction.execution_p,
                "pre_predicted_topology_p": prediction.topology_p,
                "pre_predicted_overall_p": prediction.overall_p,
                "post_predicted_retrieval_p": (post_prediction.independent_retrieval_p),
                "post_predicted_overall_p": post_prediction.overall_p,
                "retrieval_prediction_change": (
                    post_prediction.independent_retrieval_p
                    - prediction.independent_retrieval_p
                ),
                "overall_prediction_change": (
                    post_prediction.overall_p - prediction.overall_p
                ),
                "pre_memory_uncertainty": pre_memory_uncertainty,
                "post_memory_uncertainty": post_memory_uncertainty,
                "memory_uncertainty_reduction": (
                    pre_memory_uncertainty - post_memory_uncertainty
                ),
                "pre_consolidation_log_variance": pre_consolidation_variance,
                "post_consolidation_log_variance": (
                    memory_after.consolidated_log_half_life_variance
                ),
                "consolidation_log_variance_reduction": (
                    pre_consolidation_variance
                    - memory_after.consolidated_log_half_life_variance
                ),
                "competency_variance_reduction": (
                    pre_competency_variance - post_competency_variance
                ),
                "execution_variance_reduction": (
                    pre_execution_variance - post_execution_variance
                ),
                "pre_motor_competency_mean": pre_motor_mean,
                "post_motor_competency_mean": post_motor_mean,
                "motor_competency_change": post_motor_mean - pre_motor_mean,
                "pre_current_half_life_days": pre_current_half_life,
                "pre_consolidated_half_life_days": pre_consolidated_half_life,
                "post_current_half_life_days": memory_after.current_half_life_days,
                "post_consolidated_half_life_days": (
                    memory_after.consolidated_half_life_days
                ),
                "time_since_last_success_days": (
                    now - last_success_before if last_success_before is not None else ""
                ),
                "had_memory_anchor": memory_anchor_before is not None,
                "recent_factual_failures": consecutive_factual_failures[material_id],
                "recovery_trigger_guidance_level": (
                    recovery_trigger["guidance_level"]
                    if recovery_trigger is not None
                    else ""
                ),
                "recovery_trigger_predicted_retrieval_p": (
                    recovery_trigger["pre_predicted_retrieval_p"]
                    if recovery_trigger is not None
                    else ""
                ),
                "recovery_trigger_predicted_overall_p": (
                    recovery_trigger["pre_predicted_overall_p"]
                    if recovery_trigger is not None
                    else ""
                ),
                "recovery_trigger_limiting_dimension": (
                    row_limiting_dimension(recovery_trigger)
                    if recovery_trigger is not None
                    else ""
                ),
                "counterfactual_unguided_admitted": (
                    counterfactual.priority_status is StageStatus.REACHED
                ),
                "counterfactual_unguided_within_band": (
                    counterfactual.challenge_within_band
                ),
                "counterfactual_unguided_bypass": (
                    counterfactual.challenge_bypass or "none"
                ),
                "counterfactual_rejection_reason": counterfactual_rejection,
                "counterfactual_limiting_dimension": counterfactual_limiting,
                "counterfactual_predicted_retrieval_p": (
                    counterfactual.prediction.independent_retrieval_p
                ),
                "counterfactual_predicted_overall_p": (
                    counterfactual.prediction.overall_p
                ),
                "selected_admission_changed_after": (
                    post_trace.priority_status is not selected.priority_status
                ),
                "selected_rank_terms_changed_after": rank_terms_changed(
                    selected, post_trace
                ),
                "later_guidance_faded": "",
                "selections_until_guidance_faded": "",
            }
        )

        if outcome.retrieval_succeeded is False:
            consecutive_factual_failures[material_id] += 1
        elif outcome.retrieval_succeeded is True:
            consecutive_factual_failures[material_id] = 0
        selection_index += 1

    add_later_fading(rows)
    return rows


def optional_mean(rows: list[dict[str, Any]], field: str) -> float | None:
    values = [float(row[field]) for row in rows if row[field] != ""]
    return mean(values) if values else None


def summarize_group(rows: list[dict[str, Any]], keys: dict[str, str]) -> dict[str, Any]:
    observed = [row for row in rows if row["retrieval_observed"]]
    return {
        **keys,
        "selection_count": len(rows),
        "early_selection_count": sum(row["early_selection"] for row in rows),
        "high_true_retrieval_count": sum(row["high_true_retrieval"] for row in rows),
        "notes_previewed_count": sum(
            row["guidance_level"] == "notes_previewed" for row in rows
        ),
        "concurrent_cues_count": sum(
            row["guidance_level"] == "concurrent_pitch_cues" for row in rows
        ),
        "retrieval_observation_fraction": mean(
            float(row["retrieval_observed"]) for row in rows
        ),
        "retrieval_success_fraction": (
            mean(float(row["retrieval_succeeded"]) for row in observed)
            if observed
            else None
        ),
        "mean_expected_information": optional_mean(rows, "expected_information"),
        "mean_memory_evidence_weight": optional_mean(rows, "memory_evidence_weight"),
        "mean_memory_uncertainty_reduction": optional_mean(
            rows, "memory_uncertainty_reduction"
        ),
        "mean_consolidation_log_variance_reduction": optional_mean(
            rows, "consolidation_log_variance_reduction"
        ),
        "mean_competency_variance_reduction": optional_mean(
            rows, "competency_variance_reduction"
        ),
        "mean_execution_variance_reduction": optional_mean(
            rows, "execution_variance_reduction"
        ),
        "mean_absolute_retrieval_prediction_change": mean(
            abs(float(row["retrieval_prediction_change"])) for row in rows
        ),
        "mean_absolute_overall_prediction_change": mean(
            abs(float(row["overall_prediction_change"])) for row in rows
        ),
        "later_guidance_faded_fraction": mean(
            float(row["later_guidance_faded"]) for row in rows
        ),
        "mean_selections_until_guidance_faded": optional_mean(
            rows, "selections_until_guidance_faded"
        ),
        "unguided_counterfactual_admitted_fraction": mean(
            float(row["counterfactual_unguided_admitted"]) for row in rows
        ),
        "selected_admission_changed_after_fraction": mean(
            float(row["selected_admission_changed_after"]) for row in rows
        ),
        "selected_rank_terms_changed_after_fraction": mean(
            float(row["selected_rank_terms_changed_after"]) for row in rows
        ),
        "recovery_trigger_memory_limited_count": sum(
            row["recovery_trigger_limiting_dimension"] == "memory" for row in rows
        ),
        "recovery_trigger_execution_limited_count": sum(
            row["recovery_trigger_limiting_dimension"] == "execution" for row in rows
        ),
        "recovery_trigger_topology_limited_count": sum(
            row["recovery_trigger_limiting_dimension"] == "topology" for row in rows
        ),
        "mean_recovery_trigger_predicted_retrieval_p": optional_mean(
            rows, "recovery_trigger_predicted_retrieval_p"
        ),
        "mean_recovery_trigger_predicted_overall_p": optional_mean(
            rows, "recovery_trigger_predicted_overall_p"
        ),
    }


def profile_summaries(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result = []
    for fixture in FIXTURES:
        profile_rows = [row for row in events if row["profile"] == fixture.label]
        for intent in ("ordinary", "recovery", "guidance_probe", "bootstrap_probe"):
            group = [row for row in profile_rows if row["support_intent"] == intent]
            if group:
                result.append(
                    summarize_group(group, {"profile": fixture.label, "intent": intent})
                )
    return result


def intent_summary(events: list[dict[str, Any]], intent: str) -> list[dict[str, Any]]:
    result = []
    for fixture in FIXTURES:
        group = [
            row
            for row in events
            if row["profile"] == fixture.label and row["support_intent"] == intent
        ]
        if group:
            result.append(
                summarize_group(group, {"profile": fixture.label, "intent": intent})
            )
    return result


def counterfactual_summaries(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: defaultdict[tuple[str, str, str, str], list[dict[str, Any]]] = defaultdict(
        list
    )
    for row in events:
        key = (
            row["profile"],
            row["support_intent"],
            row["counterfactual_rejection_reason"],
            row["counterfactual_limiting_dimension"],
        )
        groups[key].append(row)
    return [
        {
            "profile": key[0],
            "intent": key[1],
            "counterfactual_rejection_reason": key[2],
            "counterfactual_limiting_dimension": key[3],
            "selection_count": len(group),
            "high_true_retrieval_count": sum(
                row["high_true_retrieval"] for row in group
            ),
            "mean_counterfactual_predicted_retrieval_p": optional_mean(
                group, "counterfactual_predicted_retrieval_p"
            ),
            "mean_counterfactual_predicted_overall_p": optional_mean(
                group, "counterfactual_predicted_overall_p"
            ),
        }
        for key, group in sorted(groups.items())
    ]


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def report(profile_rows: list[dict[str, Any]]) -> None:
    print("Pass 11 supported selections by profile and intent:")
    print(
        "  profile                         intent             count early "
        "high_memory cf_admit info memory_delta fade"
    )
    for row in profile_rows:
        print(
            f"  {row['profile']:<31} {row['intent']:<18} "
            f"{row['selection_count']:>5} {row['early_selection_count']:>5} "
            f"{row['high_true_retrieval_count']:>11} "
            f"{row['unguided_counterfactual_admitted_fraction']:>8.3f} "
            f"{row['mean_expected_information']:>5.3f} "
            f"{row['mean_memory_uncertainty_reduction']:>12.4f} "
            f"{row['later_guidance_faded_fraction']:>5.3f}"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir", type=Path, default=Path(__file__).with_name("generated")
    )
    parser.add_argument("--seeds", type=int, default=DEFAULT_SEEDS)
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    return parser.parse_args()


def run_case_star(args: tuple[pass10.Fixture, int]) -> list[dict[str, Any]]:
    return run_case(*args)


def main() -> None:
    args = parse_args()
    if args.seeds < 1 or args.workers < 1:
        raise SystemExit("--seeds and --workers must be positive")
    jobs = [(fixture, seed) for fixture in FIXTURES for seed in range(args.seeds)]
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        chunks = list(pool.map(run_case_star, jobs))
    rows = [row for chunk in chunks for row in chunk]
    events = [row for row in rows if row["selected"] and row["supported"]]
    profile_rows = profile_summaries(events)
    guidance_rows = intent_summary(events, "guidance_probe")
    recovery_rows = intent_summary(events, "recovery")
    counterfactual_rows = counterfactual_summaries(events)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    artifacts = {
        "supported_selection_events.csv": events,
        "supported_selection_profile_summary.csv": profile_rows,
        "guidance_probe_summary.csv": guidance_rows,
        "recovery_support_summary.csv": recovery_rows,
        "supported_counterfactual_summary.csv": counterfactual_rows,
    }
    for name, artifact_rows in artifacts.items():
        if artifact_rows:
            write_csv(args.output_dir / name, artifact_rows)
    report(profile_rows)


if __name__ == "__main__":
    main()
