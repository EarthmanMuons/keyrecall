"""Pass 15: low-yield probe ranking-alternative characterization.

At the unchanged Pass 14 trigger boundary, diagnostic sidecars can replace the
winning guidance probe with a specific already-admitted action. Event-local and
10-selection consequence metrics compare the retention-first control with an
other-material bootstrap probe, stronger same-material support, and an
information-before-retention comparator. Production policy remains unchanged.

Outputs (in --output-dir):
    probe_ranking_trajectories.csv
    probe_ranking_events.csv
    probe_ranking_choice_summary.csv
    probe_ranking_horizon_summary.csv
    probe_ranking_paired_horizons.csv
    probe_ranking_paired_summary.csv
    probe_ranking_paired_profile_summary.csv
    probe_ranking_seed_summary.csv
    probe_ranking_profile_summary.csv
    probe_ranking_variant_summary.csv
"""

from __future__ import annotations

import argparse
import concurrent.futures
import copy
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
import probe_alternative_actions as pass14
import supported_selection_intent as pass11
from candidates import InstrumentProfile
from config import load_params as load_scheduler_params
from longitudinal import NoAdmittedCandidate, SchedulerAgent
from model import evidence_weights, predicted_success, update
from params import load_params as load_learner_params
from pipeline import (
    StageStatus,
    repetition_guard,
    run_pipeline,
)
from synthetic import sample_outcome

ATTEMPTS = pass5.ATTEMPTS
SESSION_ATTEMPTS = pass5.SESSION_ATTEMPTS
DAY_STEP = pass5.DAY_STEP
MATERIAL_POOL = pass5.MATERIAL_POOL
FIXTURES = pass10.FIXTURES
DEFAULT_SEEDS = 30
DEFAULT_WORKERS = min(8, os.cpu_count() or 1)
HORIZON_SELECTIONS = 10
STRONGER_SUPPORT_FAILURE_THRESHOLD = 2

VARIANTS = (
    "control",
    "bootstrap_alternative",
    "stronger_support_repeated",
    "stronger_support_once",
    "information_before_retention",
)


def consecutive_failures(history: list[dict[str, Any]]) -> int:
    count = 0
    for event in reversed(history):
        if event["retrieval_succeeded"] is not False:
            break
        count += 1
    return count


def information_first_choice(agent, state, session, now):
    traces = run_pipeline(
        state,
        session,
        agent.candidates,
        agent.scheduler_params,
        agent.learner_params,
        now,
    )
    admitted = [
        trace
        for trace in repetition_guard(traces, session, agent.scheduler_params)
        if trace.priority_status is StageStatus.REACHED
    ]
    return max(
        admitted,
        key=lambda trace: (
            trace.rank_key[0],
            trace.information,
            trace.retention,
            trace.diversity,
            trace.goals,
        ),
        default=None,
    )


def choose_alternative(
    variant,
    agent,
    state,
    session,
    now,
    original,
    alternatives,
    prior_failures,
    support_already_inserted,
):
    if variant == "control":
        return original, "retention_first_probe"
    if variant == "bootstrap_alternative":
        candidate = alternatives["admitted_non_probe"]
        if (
            candidate is not None
            and candidate.priority_status is StageStatus.REACHED
            and candidate.challenge_bypass == "bootstrap_probe"
            and candidate.exercise.material != original.exercise.material
        ):
            return candidate, "other_material_bootstrap"
        return original, "probe_no_bootstrap_alternative"
    if variant in ("stronger_support_repeated", "stronger_support_once"):
        candidate = alternatives["memory_support"]
        if (
            prior_failures >= STRONGER_SUPPORT_FAILURE_THRESHOLD
            and (variant != "stronger_support_once" or not support_already_inserted)
            and candidate is not None
            and candidate.priority_status is StageStatus.REACHED
            and candidate.exercise.material == original.exercise.material
            and candidate.exercise.guidance.concurrent_pitch_cues
        ):
            return candidate, "same_material_stronger_support"
        return original, "probe_no_qualifying_support"
    if variant == "information_before_retention":
        candidate = information_first_choice(agent, state, session, now)
        if candidate is not None:
            action = (
                "information_first_kept_probe"
                if candidate.exercise == original.exercise
                else "information_first_alternative"
            )
            return candidate, action
        return original, "probe_no_information_alternative"
    raise ValueError(f"unknown variant: {variant}")


def uncertainty_snapshot(state, exercise, learner_params):
    material_id = exercise.material.material_id
    memory = state.material_memory.get(material_id)
    consolidation = (
        memory.consolidated_log_half_life_variance
        if memory is not None
        else learner_params.material_memory.consolidation_prior_log_variance
    )
    return {
        "memory": pass11.operative_memory_uncertainty(
            state, material_id, learner_params
        ),
        "consolidation": consolidation,
        "competency": pass11.relevant_competency_variance(state, exercise),
        "execution": pass11.execution_variance(state, exercise, learner_params),
    }


def event_local_deltas(before, after):
    return {
        "memory_uncertainty_reduction": before["memory"] - after["memory"],
        "consolidation_log_variance_reduction": (
            before["consolidation"] - after["consolidation"]
        ),
        "competency_variance_reduction": (before["competency"] - after["competency"]),
        "execution_variance_reduction": before["execution"] - after["execution"],
    }


def max_revisit_gap(rows):
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


def execute_trace(state, truth, agent, rng, trace, now, learner_params):
    exercise = trace.exercise
    material_id = exercise.material.material_id
    prediction = predicted_success(state, exercise, now, learner_params)
    true_p = pass10.true_retrievability(truth, material_id, now)
    before = uncertainty_snapshot(state, exercise, learner_params)
    outcome = sample_outcome(truth, exercise, now, rng)
    weights = evidence_weights(exercise, outcome)
    update(state, exercise, outcome, weights, prediction, now, learner_params)
    after = uncertainty_snapshot(state, exercise, learner_params)
    agent.on_outcome(exercise, outcome, now)
    return {
        "material_id": material_id,
        "at_days": now,
        "scheduler_intent": pass11.support_intent(trace.challenge_bypass),
        "guidance_level": pass5.guidance_level(exercise),
        "completed": outcome.completed,
        "retrieval_observed": outcome.retrieval_succeeded is not None,
        "retrieval_succeeded": (
            outcome.retrieval_succeeded
            if outcome.retrieval_succeeded is not None
            else ""
        ),
        "predicted_retrieval_p": prediction.independent_retrieval_p,
        "true_retrieval_p": true_p,
        "retrieval_bias": prediction.independent_retrieval_p - true_p,
        **event_local_deltas(before, after),
    }


def paired_action_candidates(
    agent, state, session, now, original, alternatives, prior_failures
):
    candidates = [("retention_first_probe", original)]
    admitted_non_probe = alternatives["admitted_non_probe"]
    if (
        admitted_non_probe is not None
        and admitted_non_probe.priority_status is StageStatus.REACHED
        and admitted_non_probe.challenge_bypass == "bootstrap_probe"
    ):
        candidates.append(("bootstrap_alternative", admitted_non_probe))
    ordinary = alternatives["ordinary_band"]
    if ordinary is not None and ordinary.priority_status is StageStatus.REACHED:
        candidates.append(("ordinary_band_alternative", ordinary))
    stronger = alternatives["memory_support"]
    if (
        prior_failures >= STRONGER_SUPPORT_FAILURE_THRESHOLD
        and stronger is not None
        and stronger.priority_status is StageStatus.REACHED
    ):
        candidates.append(("stronger_support_after_2_failures", stronger))
    information_first = information_first_choice(agent, state, session, now)
    if information_first is not None:
        candidates.append(("information_before_retention", information_first))
    return candidates


def simulate_paired_horizon(
    fixture,
    seed,
    trigger_id,
    attempt_index,
    now,
    original_material,
    action,
    first_trace,
    state,
    truth,
    agent,
    rng,
    learner_params,
):
    branch_state = copy.deepcopy(state)
    branch_truth = copy.deepcopy(truth)
    branch_agent = copy.deepcopy(agent)
    branch_rng = copy.deepcopy(rng)
    branch_agent.records[-1].selected = first_trace
    immediate = execute_trace(
        branch_state,
        branch_truth,
        branch_agent,
        branch_rng,
        first_trace,
        now,
        learner_params,
    )
    future_rows = []
    no_admissions = 0
    future_now = now
    next_attempt = attempt_index + 1
    maximum_attempt = attempt_index + 4 * SESSION_ATTEMPTS
    while len(future_rows) < HORIZON_SELECTIONS and next_attempt <= maximum_attempt:
        if next_attempt % SESSION_ATTEMPTS == 0:
            branch_agent.new_session()
        future_now += DAY_STEP
        branch_state.propagate(future_now, learner_params)
        try:
            branch_agent.pick(branch_rng, next_attempt, branch_state, future_now)
        except NoAdmittedCandidate:
            no_admissions += 1
            next_attempt += 1
            continue
        chosen = branch_agent.records[-1].selected
        assert chosen is not None
        future_rows.append(
            execute_trace(
                branch_state,
                branch_truth,
                branch_agent,
                branch_rng,
                chosen,
                future_now,
                learner_params,
            )
        )
        next_attempt += 1

    observed = [row for row in future_rows if row["retrieval_observed"]]
    returns = [row for row in future_rows if row["material_id"] == original_material]
    factual_returns = [row for row in returns if row["retrieval_observed"]]
    first_return = returns[0] if returns else None
    first_factual_return = factual_returns[0] if factual_returns else None
    return {
        "profile": fixture.label,
        "seed": seed,
        "trigger_id": trigger_id,
        "trigger_attempt_index": attempt_index,
        "trigger_at_days": now,
        "original_material_id": original_material,
        "action": action,
        "first_material_id": immediate["material_id"],
        "first_scheduler_intent": immediate["scheduler_intent"],
        "first_guidance_level": immediate["guidance_level"],
        "immediate_completed": immediate["completed"],
        "immediate_retrieval_observed": immediate["retrieval_observed"],
        "immediate_retrieval_succeeded": immediate["retrieval_succeeded"],
        "horizon_complete": len(future_rows) == HORIZON_SELECTIONS,
        "horizon_selection_count": len(future_rows),
        "horizon_retrieval_observation_count": len(observed),
        "horizon_retrieval_success_count": sum(
            row["retrieval_succeeded"] is True for row in observed
        ),
        "horizon_completion_count": sum(row["completed"] for row in future_rows),
        "horizon_memory_uncertainty_reduction": sum(
            row["memory_uncertainty_reduction"] for row in future_rows
        ),
        "horizon_consolidation_log_variance_reduction": sum(
            row["consolidation_log_variance_reduction"] for row in future_rows
        ),
        "horizon_competency_variance_reduction": sum(
            row["competency_variance_reduction"] for row in future_rows
        ),
        "horizon_execution_variance_reduction": sum(
            row["execution_variance_reduction"] for row in future_rows
        ),
        "horizon_recovery_count": sum(
            row["scheduler_intent"] == "recovery" for row in future_rows
        ),
        "horizon_no_admission_count": no_admissions,
        "horizon_material_coverage": len({row["material_id"] for row in future_rows}),
        "horizon_original_material_count": len(returns),
        "horizon_retrieval_mae": (
            mean(abs(float(row["retrieval_bias"])) for row in observed)
            if observed
            else ""
        ),
        "horizon_retrieval_brier": (
            mean(
                (
                    float(row["predicted_retrieval_p"])
                    - float(row["retrieval_succeeded"])
                )
                ** 2
                for row in observed
            )
            if observed
            else ""
        ),
        "returned_to_original_material": first_return is not None,
        "selections_until_original_material_return": (
            future_rows.index(first_return) + 1 if first_return is not None else ""
        ),
        "days_until_original_material_return": (
            float(first_return["at_days"]) - now if first_return is not None else ""
        ),
        "returned_to_factual_test": first_factual_return is not None,
        "selections_until_factual_return": (
            future_rows.index(first_factual_return) + 1
            if first_factual_return is not None
            else ""
        ),
        "days_until_factual_return": (
            float(first_factual_return["at_days"]) - now
            if first_factual_return is not None
            else ""
        ),
    }


def attach_horizon_metrics(rows, events):
    selected = [row for row in rows if row["selected"]]
    selected_by_index = {int(row["selection_index"]): row for row in selected}
    for event in events:
        trigger_index = int(event["selection_index"])
        trigger_attempt = int(event["attempt_index"])
        window = [
            selected_by_index[index]
            for index in range(
                trigger_index + 1,
                min(trigger_index + HORIZON_SELECTIONS + 1, len(selected)),
            )
        ]
        complete = len(window) == HORIZON_SELECTIONS
        end_attempt = int(window[-1]["attempt_index"]) if window else trigger_attempt
        no_admissions = [
            row
            for row in rows
            if not row["selected"]
            and trigger_attempt < int(row["attempt_index"]) <= end_attempt
        ]
        observed = [row for row in window if row["retrieval_observed"]]
        original_material = event["original_material_id"]
        returns = [row for row in window if row["material_id"] == original_material]
        factual_returns = [row for row in returns if row["retrieval_observed"]]
        first_return = returns[0] if returns else None
        first_factual_return = factual_returns[0] if factual_returns else None
        event.update(
            {
                "horizon_complete": complete,
                "horizon_selection_count": len(window),
                "horizon_retrieval_observation_count": len(observed),
                "horizon_retrieval_success_count": sum(
                    row["retrieval_succeeded"] is True for row in observed
                ),
                "horizon_completion_count": sum(row["completed"] for row in window),
                "horizon_memory_uncertainty_reduction": sum(
                    row["memory_uncertainty_reduction"] for row in window
                ),
                "horizon_consolidation_log_variance_reduction": sum(
                    row["consolidation_log_variance_reduction"] for row in window
                ),
                "horizon_competency_variance_reduction": sum(
                    row["competency_variance_reduction"] for row in window
                ),
                "horizon_execution_variance_reduction": sum(
                    row["execution_variance_reduction"] for row in window
                ),
                "horizon_recovery_count": sum(
                    row["scheduler_intent"] == "recovery" for row in window
                ),
                "horizon_no_admission_count": len(no_admissions),
                "horizon_material_coverage": len(
                    {row["material_id"] for row in window}
                ),
                "horizon_original_material_count": len(returns),
                "horizon_retrieval_mae": (
                    mean(abs(float(row["retrieval_bias"])) for row in observed)
                    if observed
                    else ""
                ),
                "horizon_retrieval_brier": (
                    mean(
                        (
                            float(row["predicted_retrieval_p"])
                            - float(row["retrieval_succeeded"])
                        )
                        ** 2
                        for row in observed
                    )
                    if observed
                    else ""
                ),
                "returned_to_original_material": first_return is not None,
                "selections_until_original_material_return": (
                    int(first_return["selection_index"]) - trigger_index
                    if first_return is not None
                    else ""
                ),
                "days_until_original_material_return": (
                    float(first_return["at_days"]) - float(event["at_days"])
                    if first_return is not None
                    else ""
                ),
                "returned_to_factual_test": first_factual_return is not None,
                "selections_until_factual_return": (
                    int(first_factual_return["selection_index"]) - trigger_index
                    if first_factual_return is not None
                    else ""
                ),
                "days_until_factual_return": (
                    float(first_factual_return["at_days"]) - float(event["at_days"])
                    if first_factual_return is not None
                    else ""
                ),
            }
        )


def run_case(variant: str, fixture: pass10.Fixture, seed: int):
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    truth, _classes = pass10.build_truth(fixture, seed)
    state = pass5.common_estimator_state(learner_params)
    agent = SchedulerAgent(
        InstrumentProfile(), list(MATERIAL_POOL), scheduler_params, learner_params
    )
    histories: defaultdict[str, list[dict[str, Any]]] = defaultdict(list)
    support_inserted_since_probe: set[str] = set()
    rng = random.Random(seed)
    rows: list[dict[str, Any]] = []
    events: list[dict[str, Any]] = []
    paired_rows: list[dict[str, Any]] = []
    now = 0.0
    selection_index = 0

    for attempt_index in range(ATTEMPTS):
        if attempt_index and attempt_index % SESSION_ATTEMPTS == 0:
            agent.new_session()
        now += DAY_STEP
        state.propagate(now, learner_params)
        session_before = copy.deepcopy(agent.session)
        try:
            agent.pick(rng, attempt_index, state, now)
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
                    "scheduler_intent": "none",
                }
            )
            continue

        original = agent.records[-1].selected
        assert original is not None
        original_material = original.exercise.material.material_id
        original_intent = pass11.support_intent(original.challenge_bypass)
        chosen = original
        action = "production_winner"
        event = None
        if original_intent == "guidance_probe":
            history = histories[original_material]
            if pass14.is_trigger(history):
                alternatives = pass14.enumerate_alternatives(
                    agent, state, session_before, original, now
                )
                failures = consecutive_failures(history)
                if variant == "control":
                    trigger_id = (
                        f"{fixture.label}:{seed}:{attempt_index}:{original_material}"
                    )
                    for paired_action, paired_trace in paired_action_candidates(
                        agent,
                        state,
                        session_before,
                        now,
                        original,
                        alternatives,
                        failures,
                    ):
                        paired_rows.append(
                            simulate_paired_horizon(
                                fixture,
                                seed,
                                trigger_id,
                                attempt_index,
                                now,
                                original_material,
                                paired_action,
                                paired_trace,
                                state,
                                truth,
                                agent,
                                rng,
                                learner_params,
                            )
                        )
                chosen, action = choose_alternative(
                    variant,
                    agent,
                    state,
                    session_before,
                    now,
                    original,
                    alternatives,
                    failures,
                    original_material in support_inserted_since_probe,
                )
                event = {
                    "variant": variant,
                    "profile": fixture.label,
                    "seed": seed,
                    "attempt_index": attempt_index,
                    "selection_index": selection_index,
                    "at_days": now,
                    "original_material_id": original_material,
                    "probe_number": len(history) + 1,
                    "consecutive_prior_probe_failures": failures,
                    "trigger_reason": pass14.trigger_reason(history),
                    "action": action,
                    "alternative_applied": chosen.exercise != original.exercise,
                    **pass14.trace_fields("probe", original, scheduler_params),
                    **pass14.trace_fields(
                        "admitted_non_probe",
                        alternatives["admitted_non_probe"],
                        scheduler_params,
                    ),
                    **pass14.trace_fields(
                        "ordinary_band",
                        alternatives["ordinary_band"],
                        scheduler_params,
                    ),
                    **pass14.trace_fields(
                        "stronger_support",
                        alternatives["memory_support"],
                        scheduler_params,
                    ),
                    **pass14.trace_fields("chosen", chosen, scheduler_params),
                }
                events.append(event)

        agent.records[-1].selected = chosen
        exercise = chosen.exercise
        material_id = exercise.material.material_id
        intent = pass11.support_intent(chosen.challenge_bypass)
        if action == "same_material_stronger_support":
            support_inserted_since_probe.add(original_material)
        prediction = predicted_success(state, exercise, now, learner_params)
        true_p = pass10.true_retrievability(truth, material_id, now)
        before = uncertainty_snapshot(state, exercise, learner_params)
        outcome = sample_outcome(truth, exercise, now, rng)
        weights = evidence_weights(exercise, outcome)
        update(state, exercise, outcome, weights, prediction, now, learner_params)
        after = uncertainty_snapshot(state, exercise, learner_params)
        agent.on_outcome(exercise, outcome, now)
        deltas = event_local_deltas(before, after)
        row = {
            "variant": variant,
            "profile": fixture.label,
            "seed": seed,
            "attempt_index": attempt_index,
            "selection_index": selection_index,
            "at_days": now,
            "selected": True,
            "material_id": material_id,
            "scheduler_intent": intent,
            "guidance_level": pass5.guidance_level(exercise),
            "completed": outcome.completed,
            "retrieval_observed": outcome.retrieval_succeeded is not None,
            "retrieval_succeeded": (
                outcome.retrieval_succeeded
                if outcome.retrieval_succeeded is not None
                else ""
            ),
            "predicted_retrieval_p": prediction.independent_retrieval_p,
            "true_retrieval_p": true_p,
            "retrieval_bias": prediction.independent_retrieval_p - true_p,
            "trigger_action": action if event is not None else "",
            **deltas,
        }
        rows.append(row)
        if event is not None:
            event.update(
                {
                    "chosen_material_id": material_id,
                    "chosen_scheduler_intent": intent,
                    "chosen_guidance_level": pass5.guidance_level(exercise),
                    "immediate_completed": outcome.completed,
                    "immediate_retrieval_observed": (
                        outcome.retrieval_succeeded is not None
                    ),
                    "immediate_retrieval_succeeded": (
                        outcome.retrieval_succeeded
                        if outcome.retrieval_succeeded is not None
                        else ""
                    ),
                    **{f"immediate_{key}": value for key, value in deltas.items()},
                }
            )
        if intent == "guidance_probe":
            history = histories[material_id]
            history.append(
                {
                    "at_days": now,
                    "retrieval_succeeded": outcome.retrieval_succeeded,
                    "retrieval_prediction_change": (
                        predicted_success(
                            state, exercise, now, learner_params
                        ).independent_retrieval_p
                        - prediction.independent_retrieval_p
                    ),
                    **deltas,
                }
            )
            support_inserted_since_probe.discard(material_id)
        selection_index += 1

    attach_horizon_metrics(rows, events)
    final_memory_uncertainties = [
        pass11.operative_memory_uncertainty(state, material.material_id, learner_params)
        for material in MATERIAL_POOL
    ]
    final_consolidation_variances = [
        (
            state.material_memory[
                material.material_id
            ].consolidated_log_half_life_variance
            if material.material_id in state.material_memory
            else learner_params.material_memory.consolidation_prior_log_variance
        )
        for material in MATERIAL_POOL
    ]
    return (
        rows,
        events,
        paired_rows,
        mean(final_memory_uncertainties),
        mean(final_consolidation_variances),
    )


def optional_mean(rows, field):
    values = [float(row[field]) for row in rows if row.get(field, "") != ""]
    return mean(values) if values else None


def summarize_seed(rows, events, variant, fixture, seed, final_memory, final_cons):
    selected = [row for row in rows if row["selected"]]
    observed = [row for row in selected if row["retrieval_observed"]]
    counts = Counter(row["material_id"] for row in selected)
    return {
        "variant": variant,
        "profile": fixture.label,
        "seed": seed,
        "selected_count": len(selected),
        "trigger_count": len(events),
        "alternative_applied_count": sum(
            event["alternative_applied"] for event in events
        ),
        "guidance_probe_count": sum(
            row["scheduler_intent"] == "guidance_probe" for row in selected
        ),
        "bootstrap_probe_count": sum(
            row["scheduler_intent"] == "bootstrap_probe" for row in selected
        ),
        "recovery_count": sum(
            row["scheduler_intent"] == "recovery" for row in selected
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
        "final_mean_memory_uncertainty": final_memory,
        "final_mean_consolidation_log_variance": final_cons,
    }


SEED_FIELDS = (
    "selected_count",
    "trigger_count",
    "alternative_applied_count",
    "guidance_probe_count",
    "bootstrap_probe_count",
    "recovery_count",
    "retrieval_prediction_mae",
    "retrieval_prediction_brier",
    "max_material_selection_fraction",
    "max_revisit_gap_days",
    "no_admission_count",
    "final_mean_memory_uncertainty",
    "final_mean_consolidation_log_variance",
)


def grouped_seed_summaries(seed_rows, include_profile):
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
        result.append(
            {
                "variant": variant,
                **({"profile": profile} if profile is not None else {}),
                **{
                    field: mean(float(row[field]) for row in group)
                    for field in SEED_FIELDS
                },
            }
        )
    return result


def summarize_choices(events):
    result = []
    for variant in VARIANTS:
        group = [event for event in events if event["variant"] == variant]
        counts = Counter(event["action"] for event in group)
        for action, count in sorted(counts.items()):
            result.append(
                {
                    "variant": variant,
                    "action": action,
                    "count": count,
                    "fraction": count / len(group) if group else None,
                    "immediate_completion_fraction": optional_mean(
                        [event for event in group if event["action"] == action],
                        "immediate_completed",
                    ),
                    "immediate_retrieval_observation_fraction": optional_mean(
                        [event for event in group if event["action"] == action],
                        "immediate_retrieval_observed",
                    ),
                    "immediate_retrieval_success_fraction": optional_mean(
                        [
                            event
                            for event in group
                            if event["action"] == action
                            and event["immediate_retrieval_succeeded"] != ""
                        ],
                        "immediate_retrieval_succeeded",
                    ),
                }
            )
    return result


HORIZON_FIELDS = (
    "horizon_retrieval_observation_count",
    "horizon_retrieval_success_count",
    "horizon_completion_count",
    "horizon_memory_uncertainty_reduction",
    "horizon_consolidation_log_variance_reduction",
    "horizon_competency_variance_reduction",
    "horizon_execution_variance_reduction",
    "horizon_recovery_count",
    "horizon_no_admission_count",
    "horizon_material_coverage",
    "horizon_original_material_count",
    "horizon_retrieval_mae",
    "horizon_retrieval_brier",
    "returned_to_original_material",
    "selections_until_original_material_return",
    "days_until_original_material_return",
    "returned_to_factual_test",
    "selections_until_factual_return",
    "days_until_factual_return",
)


def summarize_horizons(events):
    result = []
    for variant in VARIANTS:
        complete = [
            event
            for event in events
            if event["variant"] == variant and event["horizon_complete"]
        ]
        result.append(
            {
                "variant": variant,
                "complete_horizon_count": len(complete),
                **{field: optional_mean(complete, field) for field in HORIZON_FIELDS},
            }
        )
    return result


PAIRED_FIELDS = (
    "immediate_completed",
    "immediate_retrieval_observed",
    "horizon_retrieval_observation_count",
    "horizon_retrieval_success_count",
    "horizon_completion_count",
    "horizon_memory_uncertainty_reduction",
    "horizon_consolidation_log_variance_reduction",
    "horizon_competency_variance_reduction",
    "horizon_execution_variance_reduction",
    "horizon_recovery_count",
    "horizon_no_admission_count",
    "horizon_material_coverage",
    "horizon_original_material_count",
    "horizon_retrieval_mae",
    "horizon_retrieval_brier",
    "returned_to_original_material",
    "selections_until_original_material_return",
    "days_until_original_material_return",
    "returned_to_factual_test",
    "selections_until_factual_return",
    "days_until_factual_return",
)


def summarize_paired_horizons(paired_rows, include_profile=False):
    controls = {
        row["trigger_id"]: row
        for row in paired_rows
        if row["action"] == "retention_first_probe"
    }
    result = []
    keys = (
        [
            (action, fixture.label)
            for action in dict.fromkeys(row["action"] for row in paired_rows)
            for fixture in FIXTURES
        ]
        if include_profile
        else [
            (action, None)
            for action in dict.fromkeys(row["action"] for row in paired_rows)
        ]
    )
    for action, profile in keys:
        group = [
            row
            for row in paired_rows
            if row["action"] == action
            and row["horizon_complete"]
            and (profile is None or row["profile"] == profile)
        ]
        if not group:
            continue
        summary = {
            "action": action,
            **({"profile": profile} if profile is not None else {}),
            "paired_horizon_count": len(group),
        }
        for field in PAIRED_FIELDS:
            comparable = [
                row
                for row in group
                if row.get(field, "") != ""
                and controls[row["trigger_id"]].get(field, "") != ""
            ]
            summary[field] = optional_mean(group, field)
            summary[f"delta_vs_control_{field}"] = (
                mean(
                    float(row[field]) - float(controls[row["trigger_id"]][field])
                    for row in comparable
                )
                if comparable
                else None
            )
        result.append(summary)
    return result


def write_csv(path, rows):
    with path.open("w", newline="", encoding="utf-8") as handle:
        fieldnames = list(dict.fromkeys(key for row in rows for key in row))
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir", type=Path, default=Path(__file__).with_name("generated")
    )
    parser.add_argument("--seeds", type=int, default=DEFAULT_SEEDS)
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    return parser.parse_args()


def run_case_star(args):
    return run_case(*args)


def main():
    args = parse_args()
    jobs = [
        (variant, fixture, seed)
        for variant in VARIANTS
        for fixture in FIXTURES
        for seed in range(args.seeds)
    ]
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        chunks = list(pool.map(run_case_star, jobs))
    rows = [
        row
        for trajectory, _events, _paired, _mem, _cons in chunks
        for row in trajectory
    ]
    events = [
        event
        for _rows, case_events, _paired, _mem, _cons in chunks
        for event in case_events
    ]
    paired_rows = [
        row
        for _rows, _events, case_paired, _mem, _cons in chunks
        for row in case_paired
    ]
    seed_rows = [
        summarize_seed(rows, events, *job, final_memory, final_cons)
        for (rows, events, _paired, final_memory, final_cons), job in zip(
            chunks, jobs, strict=True
        )
    ]
    profile_rows = grouped_seed_summaries(seed_rows, include_profile=True)
    variant_rows = grouped_seed_summaries(seed_rows, include_profile=False)
    choice_rows = summarize_choices(events)
    horizon_rows = summarize_horizons(events)
    paired_summary = summarize_paired_horizons(paired_rows)
    paired_profile_summary = summarize_paired_horizons(
        paired_rows, include_profile=True
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    artifacts = {
        "probe_ranking_trajectories.csv": rows,
        "probe_ranking_events.csv": events,
        "probe_ranking_choice_summary.csv": choice_rows,
        "probe_ranking_horizon_summary.csv": horizon_rows,
        "probe_ranking_paired_horizons.csv": paired_rows,
        "probe_ranking_paired_summary.csv": paired_summary,
        "probe_ranking_paired_profile_summary.csv": paired_profile_summary,
        "probe_ranking_seed_summary.csv": seed_rows,
        "probe_ranking_profile_summary.csv": profile_rows,
        "probe_ranking_variant_summary.csv": variant_rows,
    }
    for name, artifact_rows in artifacts.items():
        write_csv(args.output_dir / name, artifact_rows)
    print("Ranking variants:")
    for row in variant_rows:
        print(row)
    print("Ten-selection horizons:")
    for row in horizon_rows:
        print(row)
    print("Paired control-state horizons:")
    for row in paired_summary:
        print(row)


if __name__ == "__main__":
    main()
