"""Pass 14: low-yield guidance-probe alternative-action characterization.

For probes identifiable as late or repeatedly low-yield before presentation,
enumerate progressively relaxed alternatives from the unchanged candidate
pipeline. A matched end-session sidecar tests intentional no-selection. No
production scheduler or learner behavior changes.

Outputs (in --output-dir):
    probe_alternative_events.csv
    probe_alternative_availability.csv
    probe_alternative_kinds.csv
    probe_alternative_rejections.csv
    probe_alternative_clock_summary.csv
    probe_alternative_policy_seed_summary.csv
    probe_alternative_policy_summary.csv
    probe_alternative_policy_profile_summary.csv
"""

from __future__ import annotations

import argparse
import concurrent.futures
import copy
import csv
import math
import os
import random
from collections import Counter, defaultdict
from itertools import pairwise
from pathlib import Path
from statistics import mean
from typing import Any

import cold_start_identifiability as pass5
import guidance_probe_yield as pass13
import prior_knowledge_placement as pass10
import supported_selection_intent as pass11
from candidates import InstrumentProfile
from config import load_params as load_scheduler_params
from longitudinal import NoAdmittedCandidate, SchedulerAgent
from model import evidence_weights, predicted_success, update
from params import load_params as load_learner_params
from pipeline import StageStatus, run_pipeline, select_scheduler_choice
from synthetic import sample_outcome

ATTEMPTS = pass5.ATTEMPTS
SESSION_ATTEMPTS = pass5.SESSION_ATTEMPTS
DAY_STEP = pass5.DAY_STEP
MATERIAL_POOL = pass5.MATERIAL_POOL
FIXTURES = pass10.FIXTURES
VARIANTS = ("control", "end_session")
DEFAULT_SEEDS = 30
DEFAULT_WORKERS = min(8, os.cpu_count() or 1)


def is_trigger(history: list[dict[str, Any]]) -> bool:
    return trigger_reason(history) != ""


def trigger_reason(history: list[dict[str, Any]]) -> str:
    next_ordinal = len(history) + 1
    if next_ordinal >= 9:
        return "late_ordinal"
    recent = history[-pass13.LOW_YIELD_HISTORY_LENGTH :]
    if len(recent) == pass13.LOW_YIELD_HISTORY_LENGTH and all(
        pass13.event_is_low_yield(event) for event in recent
    ):
        return "low_yield_history"
    return ""


def rejection_reason(trace, scheduler_params) -> str:
    if trace is None:
        return "unavailable"
    if trace.priority_status is StageStatus.REACHED:
        return "admitted"
    if not trace.safety_allowed:
        return "safety"
    if trace.prediction.overall_p < scheduler_params.challenge.p_min:
        return "too_hard"
    if trace.prediction.overall_p > scheduler_params.challenge.p_max:
        return "too_easy"
    return "not_admitted_other"


def same_realization(left, right) -> bool:
    return (
        left.material == right.material
        and left.hands == right.hands
        and left.octaves == right.octaves
        and left.direction == right.direction
        and left.tempo_bpm == right.tempo_bpm
        and left.opportunities == right.opportunities
    )


def motor_easier(candidate, probe) -> bool:
    return (
        candidate.material == probe.material
        and candidate.hands == probe.hands
        and candidate.guidance == probe.guidance
        and candidate.tempo_bpm <= probe.tempo_bpm
        and candidate.octaves <= probe.octaves
        and (candidate.direction == probe.direction or candidate.direction == "UP")
        and (
            candidate.tempo_bpm < probe.tempo_bpm
            or candidate.octaves < probe.octaves
            or candidate.direction != probe.direction
        )
    )


def band_distance(overall_p: float, scheduler_params) -> float:
    lo, hi = scheduler_params.challenge.p_min, scheduler_params.challenge.p_max
    if overall_p < lo:
        return lo - overall_p
    if overall_p > hi:
        return overall_p - hi
    return 0.0


def best_trace(traces, session, scheduler_params):
    return (
        select_scheduler_choice(traces, session, scheduler_params) if traces else None
    )


def highest_overall(traces):
    return max(traces, key=lambda trace: trace.prediction.overall_p, default=None)


def enumerate_alternatives(agent, state, session, probe_trace, now):
    traces = run_pipeline(
        state,
        session,
        agent.candidates,
        agent.scheduler_params,
        agent.learner_params,
        now,
    )
    probe = probe_trace.exercise
    non_probe_admitted = [
        trace
        for trace in traces
        if trace.priority_status is StageStatus.REACHED
        and trace.challenge_bypass != "guidance_probe"
    ]
    ordinary_band = [
        trace
        for trace in non_probe_admitted
        if trace.challenge_bypass is None and trace.challenge_within_band
    ]
    provisional = [
        trace
        for trace in non_probe_admitted
        if trace.eligibility_tier == "PROVISIONALLY_ELIGIBLE"
    ]
    exact_stronger = next(
        (
            trace
            for trace in traces
            if same_realization(trace.exercise, probe)
            and trace.exercise.guidance.concurrent_pitch_cues
        ),
        None,
    )
    motor = highest_overall(
        [trace for trace in traces if motor_easier(trace.exercise, probe)]
    )
    memory_support = highest_overall(
        [
            trace
            for trace in traces
            if trace.exercise.material == probe.material
            and trace.exercise.guidance.concurrent_pitch_cues
        ]
    )
    other_outside = min(
        (
            trace
            for trace in traces
            if trace.exercise.material != probe.material
            and trace.safety_allowed
            and trace.challenge_status is StageStatus.REACHED
            and trace.priority_status is StageStatus.NOT_REACHED
            and trace.challenge_bypass != "guidance_probe"
        ),
        key=lambda trace: band_distance(
            trace.prediction.overall_p, agent.scheduler_params
        ),
        default=None,
    )
    return {
        "admitted_non_probe": best_trace(
            non_probe_admitted, session, agent.scheduler_params
        ),
        "ordinary_band": best_trace(ordinary_band, session, agent.scheduler_params),
        "provisional": best_trace(provisional, session, agent.scheduler_params),
        "recovery_like": exact_stronger,
        "easier_motor": motor,
        "memory_support": memory_support,
        "other_near_band": other_outside,
    }


def trace_fields(prefix: str, trace, scheduler_params) -> dict[str, Any]:
    if trace is None:
        return {
            f"{prefix}_available": False,
            f"{prefix}_admitted": False,
            f"{prefix}_rejection_reason": "unavailable",
            f"{prefix}_material_id": "",
            f"{prefix}_eligibility_tier": "",
            f"{prefix}_bypass": "",
            f"{prefix}_predicted_retrieval_p": "",
            f"{prefix}_predicted_overall_p": "",
            f"{prefix}_retention": "",
            f"{prefix}_information": "",
            f"{prefix}_diversity": "",
            f"{prefix}_goals": "",
            f"{prefix}_rank_key": "",
        }
    return {
        f"{prefix}_available": True,
        f"{prefix}_admitted": trace.priority_status is StageStatus.REACHED,
        f"{prefix}_rejection_reason": rejection_reason(trace, scheduler_params),
        f"{prefix}_material_id": trace.exercise.material.material_id,
        f"{prefix}_eligibility_tier": trace.eligibility_tier,
        f"{prefix}_bypass": trace.challenge_bypass or "none",
        f"{prefix}_predicted_retrieval_p": (trace.prediction.independent_retrieval_p),
        f"{prefix}_predicted_overall_p": trace.prediction.overall_p,
        f"{prefix}_retention": trace.retention,
        f"{prefix}_information": trace.information,
        f"{prefix}_diversity": trace.diversity,
        f"{prefix}_goals": trace.goals,
        f"{prefix}_rank_key": repr(trace.rank_key) if trace.rank_key else "",
    }


def probe_event(
    variant,
    fixture,
    seed,
    selection_index,
    now,
    state,
    probe_trace,
    history,
    alternatives,
    learner_params,
    scheduler_params,
):
    material_id = probe_trace.exercise.material.material_id
    memory = state.material_memory[material_id]
    previous = history[-1] if history else None
    event = {
        "variant": variant,
        "profile": fixture.label,
        "seed": seed,
        "selection_index": selection_index,
        "at_days": now,
        "material_id": material_id,
        "probe_number": len(history) + 1,
        "triggered_low_yield_alternative_check": is_trigger(history),
        "low_yield_trigger_reason": trigger_reason(history),
        "probe_expected_information": probe_trace.information,
        "probe_retention": probe_trace.retention,
        "probe_diversity": probe_trace.diversity,
        "probe_goals": probe_trace.goals,
        "probe_rank_key": repr(probe_trace.rank_key),
        "probe_predicted_retrieval_p": (probe_trace.prediction.independent_retrieval_p),
        "probe_predicted_overall_p": probe_trace.prediction.overall_p,
        "pre_memory_uncertainty": pass11.operative_memory_uncertainty(
            state, material_id, learner_params
        ),
        "pre_consolidation_log_variance": (memory.consolidated_log_half_life_variance),
        "time_since_factual_success_days": (
            now - memory.factual_last_retrieval_at
            if memory.factual_last_retrieval_at is not None
            else ""
        ),
        "time_since_factual_attempt_days": (
            now - memory.last_retrieval_attempt_at
            if memory.last_retrieval_attempt_at is not None
            else ""
        ),
        "time_since_previous_probe_days": (
            now - float(previous["at_days"]) if previous is not None else ""
        ),
        "consecutive_prior_probe_failures": (
            0
            if previous is None or previous["retrieval_succeeded"] is True
            else int(previous["consecutive_prior_probe_failures"]) + 1
        ),
        "action_taken": "probe",
        "retrieval_succeeded": "",
        "retrieval_prediction_change": "",
        "absolute_retrieval_prediction_change": "",
        "memory_uncertainty_reduction": "",
        "consolidation_log_variance_reduction": "",
        "competency_variance_reduction": "",
        "execution_variance_reduction": "",
    }
    for name, trace in alternatives.items():
        event.update(trace_fields(name, trace, scheduler_params))
    return event


def run_case(variant: str, fixture: pass10.Fixture, seed: int):
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    truth, _classes = pass10.build_truth(fixture, seed)
    state = pass5.common_estimator_state(learner_params)
    agent = SchedulerAgent(
        InstrumentProfile(), list(MATERIAL_POOL), scheduler_params, learner_params
    )
    histories: defaultdict[str, list[dict[str, Any]]] = defaultdict(list)
    rng = random.Random(seed)
    rows, events = [], []
    now = 0.0
    selection_index = 0
    ended_session = False

    for attempt_index in range(ATTEMPTS):
        if attempt_index and attempt_index % SESSION_ATTEMPTS == 0:
            agent.new_session()
            ended_session = False
        now += DAY_STEP
        state.propagate(now, learner_params)
        if ended_session:
            rows.append({"selected": False, "ended_session": True})
            continue
        session_before = copy.deepcopy(agent.session)
        try:
            exercise = agent.pick(rng, attempt_index, state, now)
        except NoAdmittedCandidate:
            rows.append({"selected": False, "ended_session": False})
            continue
        selected = agent.records[-1].selected
        assert selected is not None
        material_id = exercise.material.material_id
        intent = pass11.support_intent(selected.challenge_bypass)
        event = None
        if intent == "guidance_probe":
            history = histories[material_id]
            alternatives = enumerate_alternatives(
                agent, state, session_before, selected, now
            )
            event = probe_event(
                variant,
                fixture,
                seed,
                selection_index,
                now,
                state,
                selected,
                history,
                alternatives,
                learner_params,
                scheduler_params,
            )
            if (
                variant == "end_session"
                and event["triggered_low_yield_alternative_check"]
            ):
                event["action_taken"] = "end_session"
                events.append(event)
                agent.records[-1].selected = None
                ended_session = True
                rows.append({"selected": False, "ended_session": True})
                continue

        prediction = predicted_success(state, exercise, now, learner_params)
        true_p = pass10.true_retrievability(truth, material_id, now)
        pre_memory = pass11.operative_memory_uncertainty(
            state, material_id, learner_params
        )
        memory_before = state.material_memory.get(material_id)
        pre_consolidation = (
            memory_before.consolidated_log_half_life_variance
            if memory_before is not None
            else learner_params.material_memory.consolidation_prior_log_variance
        )
        pre_competency = pass11.relevant_competency_variance(state, exercise)
        pre_execution = pass11.execution_variance(state, exercise, learner_params)
        outcome = sample_outcome(truth, exercise, now, rng)
        weights = evidence_weights(exercise, outcome)
        update(state, exercise, outcome, weights, prediction, now, learner_params)
        post_prediction = predicted_success(state, exercise, now, learner_params)
        post_memory = pass11.operative_memory_uncertainty(
            state, material_id, learner_params
        )
        post_competency = pass11.relevant_competency_variance(state, exercise)
        post_execution = pass11.execution_variance(state, exercise, learner_params)
        agent.on_outcome(exercise, outcome, now)
        rows.append(
            {
                "selected": True,
                "ended_session": False,
                "material_id": material_id,
                "at_days": now,
                "retrieval_observed": outcome.retrieval_succeeded is not None,
                "retrieval_succeeded": (
                    outcome.retrieval_succeeded
                    if outcome.retrieval_succeeded is not None
                    else ""
                ),
                "predicted_retrieval_p": prediction.independent_retrieval_p,
                "true_retrieval_p": true_p,
                "retrieval_bias": prediction.independent_retrieval_p - true_p,
                "scheduler_intent": intent,
            }
        )
        if event is not None:
            event.update(
                {
                    "retrieval_succeeded": outcome.retrieval_succeeded,
                    "retrieval_prediction_change": (
                        post_prediction.independent_retrieval_p
                        - prediction.independent_retrieval_p
                    ),
                    "absolute_retrieval_prediction_change": abs(
                        post_prediction.independent_retrieval_p
                        - prediction.independent_retrieval_p
                    ),
                    "memory_uncertainty_reduction": pre_memory - post_memory,
                    "consolidation_log_variance_reduction": (
                        pre_consolidation
                        - state.material_memory[
                            material_id
                        ].consolidated_log_half_life_variance
                    ),
                    "competency_variance_reduction": (pre_competency - post_competency),
                    "execution_variance_reduction": pre_execution - post_execution,
                }
            )
            histories[material_id].append(event)
            events.append(event)
        selection_index += 1
    return rows, events


def optional_mean(rows, field):
    values = [float(row[field]) for row in rows if row.get(field, "") != ""]
    return mean(values) if values else None


def summarize_availability(events):
    triggered = [
        row
        for row in events
        if row["variant"] == "control" and row["triggered_low_yield_alternative_check"]
    ]
    result = []
    for profile in ("all", *(fixture.label for fixture in FIXTURES)):
        group = (
            triggered
            if profile == "all"
            else [row for row in triggered if row["profile"] == profile]
        )
        row = {"profile": profile, "trigger_count": len(group)}
        for name in (
            "admitted_non_probe",
            "ordinary_band",
            "provisional",
            "recovery_like",
            "easier_motor",
            "memory_support",
            "other_near_band",
        ):
            row[f"{name}_available_fraction"] = (
                mean(float(item[f"{name}_available"]) for item in group)
                if group
                else None
            )
            row[f"{name}_admitted_fraction"] = (
                mean(float(item[f"{name}_admitted"]) for item in group)
                if group
                else None
            )
            row[f"{name}_mean_overall_p"] = optional_mean(
                group, f"{name}_predicted_overall_p"
            )
        result.append(row)
    return result


def summarize_rejections(events):
    triggered = [
        row
        for row in events
        if row["variant"] == "control" and row["triggered_low_yield_alternative_check"]
    ]
    alternatives = (
        "admitted_non_probe",
        "ordinary_band",
        "provisional",
        "recovery_like",
        "easier_motor",
        "memory_support",
        "other_near_band",
    )
    result = []
    for profile in ("all", *(fixture.label for fixture in FIXTURES)):
        group = (
            triggered
            if profile == "all"
            else [row for row in triggered if row["profile"] == profile]
        )
        for alternative in alternatives:
            counts = Counter(row[f"{alternative}_rejection_reason"] for row in group)
            for reason, count in sorted(counts.items()):
                result.append(
                    {
                        "profile": profile,
                        "alternative": alternative,
                        "rejection_reason": reason,
                        "count": count,
                        "fraction": count / len(group) if group else None,
                    }
                )
    return result


def summarize_kinds(events):
    triggered = [
        row
        for row in events
        if row["variant"] == "control" and row["triggered_low_yield_alternative_check"]
    ]
    alternatives = (
        "admitted_non_probe",
        "ordinary_band",
        "provisional",
        "recovery_like",
        "easier_motor",
        "memory_support",
        "other_near_band",
    )
    result = []
    for profile in ("all", *(fixture.label for fixture in FIXTURES)):
        group = (
            triggered
            if profile == "all"
            else [row for row in triggered if row["profile"] == profile]
        )
        for alternative in alternatives:
            available = [row for row in group if row[f"{alternative}_available"]]
            result.append(
                {
                    "profile": profile,
                    "alternative": alternative,
                    "available_count": len(available),
                    "same_material_fraction": (
                        mean(
                            row[f"{alternative}_material_id"] == row["material_id"]
                            for row in available
                        )
                        if available
                        else None
                    ),
                    "no_bypass_fraction": (
                        mean(
                            row[f"{alternative}_bypass"] == "none" for row in available
                        )
                        if available
                        else None
                    ),
                    "guidance_probe_fraction": (
                        mean(
                            row[f"{alternative}_bypass"] == "guidance_probe"
                            for row in available
                        )
                        if available
                        else None
                    ),
                    "bootstrap_probe_fraction": (
                        mean(
                            row[f"{alternative}_bypass"] == "bootstrap_probe"
                            for row in available
                        )
                        if available
                        else None
                    ),
                }
            )
    return result


def correlation(rows, x_field, y_field):
    pairs = [
        (float(row[x_field]), float(row[y_field]))
        for row in rows
        if row.get(x_field, "") != "" and row.get(y_field, "") != ""
    ]
    if len(pairs) < 2:
        return None
    xs, ys = zip(*pairs, strict=True)
    xm, ym = mean(xs), mean(ys)
    numerator = sum((x - xm) * (y - ym) for x, y in pairs)
    denominator = math.sqrt(
        sum((x - xm) ** 2 for x in xs) * sum((y - ym) ** 2 for y in ys)
    )
    return numerator / denominator if denominator else None


def clock_summary(events):
    all_failed = [
        row
        for row in events
        if row["variant"] == "control" and row["retrieval_succeeded"] is False
    ]
    yields = (
        "absolute_retrieval_prediction_change",
        "memory_uncertainty_reduction",
        "consolidation_log_variance_reduction",
    )
    clocks = (
        "time_since_factual_success_days",
        "time_since_factual_attempt_days",
        "time_since_previous_probe_days",
        "consecutive_prior_probe_failures",
    )
    result = []
    for scope, failed in (
        ("all_failed", all_failed),
        (
            "low_yield_failed",
            [row for row in all_failed if row["triggered_low_yield_alternative_check"]],
        ),
    ):
        for clock in clocks:
            result.append(
                {
                    "scope": scope,
                    "clock": clock,
                    "failed_probe_count": len(failed),
                    **{
                        f"correlation_{yield_field}": correlation(
                            failed, clock, yield_field
                        )
                        for yield_field in yields
                    },
                }
            )
    return result


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


def summarize_seed(rows, events, variant, fixture, seed):
    selected = [row for row in rows if row["selected"]]
    observed = [row for row in selected if row["retrieval_observed"]]
    counts = Counter(row["material_id"] for row in selected)
    return {
        "variant": variant,
        "profile": fixture.label,
        "seed": seed,
        "selected_count": len(selected),
        "ended_session_attempt_count": sum(row["ended_session"] for row in rows),
        "low_yield_probe_count": sum(
            row["triggered_low_yield_alternative_check"] for row in events
        ),
        "retrieval_prediction_mae": mean(
            abs(float(row["retrieval_bias"])) for row in observed
        ),
        "retrieval_prediction_brier": mean(
            (float(row["predicted_retrieval_p"]) - float(row["retrieval_succeeded"]))
            ** 2
            for row in observed
        ),
        "recovery_count": sum(
            row["scheduler_intent"] == "recovery" for row in selected
        ),
        "max_material_selection_fraction": (
            max(counts.values()) / len(selected) if selected else 0.0
        ),
        "selected_material_count": len(counts),
        "max_revisit_gap_days": max_revisit_gap(rows),
        "no_selection_count": sum(not row["selected"] for row in rows),
    }


def grouped_policy(seed_rows, include_profile=False):
    fields = (
        "selected_count",
        "ended_session_attempt_count",
        "low_yield_probe_count",
        "retrieval_prediction_mae",
        "retrieval_prediction_brier",
        "recovery_count",
        "max_material_selection_fraction",
        "selected_material_count",
        "max_revisit_gap_days",
        "no_selection_count",
    )
    result = []
    keys = (
        [(variant, fixture.label) for variant in VARIANTS for fixture in FIXTURES]
        if include_profile
        else [(variant, None) for variant in VARIANTS]
    )
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
                **{field: mean(float(row[field]) for row in group) for field in fields},
            }
        )
    return result


def write_csv(path, rows):
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
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
    events = [event for _rows, event_rows in chunks for event in event_rows]
    seed_rows = [
        summarize_seed(rows, event_rows, *job)
        for (rows, event_rows), job in zip(chunks, jobs, strict=True)
    ]
    availability = summarize_availability(events)
    kinds = summarize_kinds(events)
    rejections = summarize_rejections(events)
    clocks = clock_summary(events)
    policies = grouped_policy(seed_rows)
    profile_policies = grouped_policy(seed_rows, include_profile=True)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    artifacts = {
        "probe_alternative_events.csv": events,
        "probe_alternative_availability.csv": availability,
        "probe_alternative_kinds.csv": kinds,
        "probe_alternative_rejections.csv": rejections,
        "probe_alternative_clock_summary.csv": clocks,
        "probe_alternative_policy_seed_summary.csv": seed_rows,
        "probe_alternative_policy_summary.csv": policies,
        "probe_alternative_policy_profile_summary.csv": profile_policies,
    }
    for name, rows in artifacts.items():
        write_csv(args.output_dir / name, rows)
    print("Low-yield probe alternatives:")
    for row in availability:
        if row["profile"] == "all":
            print(row)
    print("No-action comparator:")
    for row in policies:
        print(row)


if __name__ == "__main__":
    main()
