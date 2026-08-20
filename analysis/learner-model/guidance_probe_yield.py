"""Pass 13: guidance-probe marginal-yield and termination characterization.

Stage 1 measures probe sequences by ordinal and pre-probe uncertainty without
changing policy. Stage 2 compares diagnostic suppression sidecars. No variant
changes learner transitions or production scheduler configuration.

Outputs (in --output-dir):
    guidance_probe_events.csv
    guidance_probe_exact_ordinal_summary.csv
    guidance_probe_ordinal_summary.csv
    guidance_probe_uncertainty_summary.csv
    guidance_probe_consolidation_variance_summary.csv
    guidance_probe_information_calibration.csv
    guidance_probe_policy_seed_summary.csv
    guidance_probe_policy_profile_summary.csv
    guidance_probe_policy_variant_summary.csv
"""

from __future__ import annotations

import argparse
import concurrent.futures
import copy
import csv
import dataclasses
import math
import os
import random
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from itertools import pairwise
from pathlib import Path
from statistics import mean
from typing import Any

import cold_start_identifiability as pass5
import prior_knowledge_placement as pass10
import supported_selection_intent as pass11
from candidates import InstrumentProfile
from config import load_params as load_scheduler_params
from domain import GuidanceContext
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
DEFAULT_SEEDS = 30
DEFAULT_WORKERS = min(8, os.cpu_count() or 1)

VARIANTS = (
    "control",
    "minimum_spacing",
    "success_cooldown",
    "failure_cooldown",
    "uncertainty_threshold",
    "low_yield_history",
)

# Diagnostic policy values, not production calibration.
MINIMUM_PROBE_SPACING_DAYS = 10.0
SUCCESS_COOLDOWN_DAYS = 15.0
FAILURE_COOLDOWN_DAYS = 5.0
LOW_MEMORY_UNCERTAINTY = 0.25
LOW_CONSOLIDATION_VARIANCE = 0.40
LOW_YIELD_HISTORY_LENGTH = 2
LOW_YIELD_RETRIEVAL_CHANGE = 0.05
LOW_YIELD_MEMORY_REDUCTION = 0.02
LOW_YIELD_CONSOLIDATION_REDUCTION = 0.05
LOW_YIELD_COMPETENCY_REDUCTION = 0.03
LOW_YIELD_EXECUTION_REDUCTION = 0.02


@dataclass
class ProbeHistory:
    events_by_material: defaultdict[str, list[dict[str, Any]]] = field(
        default_factory=lambda: defaultdict(list)
    )
    suppressed_winners: int = 0


def uncertainty_band(value: float) -> str:
    if value <= LOW_MEMORY_UNCERTAINTY:
        return "low"
    if value <= 0.60:
        return "medium"
    return "high"


def consolidation_variance_band(value: float) -> str:
    if value <= LOW_CONSOLIDATION_VARIANCE:
        return "low"
    if value <= 1.0:
        return "medium"
    return "high"


def ordinal_band(ordinal: int) -> str:
    if ordinal <= 2:
        return "1-2"
    if ordinal <= 5:
        return "3-5"
    if ordinal <= 8:
        return "6-8"
    return "9+"


def event_is_low_yield(event: dict[str, Any]) -> bool:
    return (
        abs(float(event["retrieval_prediction_change"])) < LOW_YIELD_RETRIEVAL_CHANGE
        and float(event["memory_uncertainty_reduction"]) < LOW_YIELD_MEMORY_REDUCTION
        and float(event["consolidation_log_variance_reduction"])
        < LOW_YIELD_CONSOLIDATION_REDUCTION
        and float(event["competency_variance_reduction"])
        < LOW_YIELD_COMPETENCY_REDUCTION
        and float(event["execution_variance_reduction"]) < LOW_YIELD_EXECUTION_REDUCTION
    )


def suppress_probe(
    variant: str,
    material_id: str,
    now: float,
    state,
    history: ProbeHistory,
    learner_params,
) -> bool:
    events = history.events_by_material[material_id]
    if variant == "control" or not events:
        return False
    latest = events[-1]
    if variant == "minimum_spacing":
        return now - float(latest["at_days"]) < MINIMUM_PROBE_SPACING_DAYS
    if variant == "success_cooldown":
        return bool(latest["retrieval_succeeded"]) and (
            now - float(latest["at_days"]) < SUCCESS_COOLDOWN_DAYS
        )
    if variant == "failure_cooldown":
        return latest["retrieval_succeeded"] is False and (
            now - float(latest["at_days"]) < FAILURE_COOLDOWN_DAYS
        )
    if variant == "uncertainty_threshold":
        if material_id not in state.material_memory:
            return False
        return (
            pass11.operative_memory_uncertainty(state, material_id, learner_params)
            <= LOW_MEMORY_UNCERTAINTY
        )
    if variant == "low_yield_history":
        recent = events[-LOW_YIELD_HISTORY_LENGTH:]
        return len(recent) == LOW_YIELD_HISTORY_LENGTH and all(
            event_is_low_yield(event) for event in recent
        )
    raise ValueError(f"unknown variant: {variant}")


def choose_with_suppression(
    variant: str,
    agent: SchedulerAgent,
    original,
    state,
    now: float,
    session_before,
    history: ProbeHistory,
):
    if original.challenge_bypass != "guidance_probe" or not suppress_probe(
        variant,
        original.exercise.material.material_id,
        now,
        state,
        history,
        agent.learner_params,
    ):
        return original

    history.suppressed_winners += 1
    traces = run_pipeline(
        state,
        session_before,
        agent.candidates,
        agent.scheduler_params,
        agent.learner_params,
        now,
    )
    allowed = [
        trace
        for trace in traces
        if trace.challenge_bypass != "guidance_probe"
        or not suppress_probe(
            variant,
            trace.exercise.material.material_id,
            now,
            state,
            history,
            agent.learner_params,
        )
    ]
    return select_scheduler_choice(allowed, session_before, agent.scheduler_params)


def update_pending_admissions(
    history: ProbeHistory,
    state,
    session,
    scheduler_params,
    learner_params,
    now: float,
    selection_index: int,
) -> None:
    for events in history.events_by_material.values():
        for event in events:
            if event["later_unguided_admitted"] != "":
                continue
            sibling = dataclasses.replace(event["exercise"], guidance=GuidanceContext())
            trace = run_pipeline(
                state,
                session,
                [sibling],
                scheduler_params,
                learner_params,
                now,
            )[0]
            if trace.priority_status is not StageStatus.REACHED:
                continue
            event["later_unguided_admitted"] = True
            event["days_until_unguided_admission"] = now - float(event["at_days"])
            event["selections_until_unguided_admission"] = selection_index - int(
                event["selection_index"]
            )


def max_revisit_gap(rows: list[dict[str, Any]]) -> float:
    visits: defaultdict[str, list[float]] = defaultdict(list)
    for row in rows:
        if row["selected"]:
            visits[row["material_id"]].append(float(row["at_days"]))
    return max(
        (
            later - earlier
            for values in visits.values()
            for earlier, later in pairwise(values)
        ),
        default=0.0,
    )


def run_case(
    variant: str, fixture: pass10.Fixture, seed: int
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int, float, float]:
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    truth, _material_classes = pass10.build_truth(fixture, seed)
    state = pass5.common_estimator_state(learner_params)
    agent = SchedulerAgent(
        InstrumentProfile(), list(MATERIAL_POOL), scheduler_params, learner_params
    )
    history = ProbeHistory()
    rng = random.Random(seed)
    rows: list[dict[str, Any]] = []
    now = 0.0
    selection_index = 0

    for attempt_index in range(ATTEMPTS):
        if attempt_index and attempt_index % SESSION_ATTEMPTS == 0:
            agent.new_session()
        now += DAY_STEP
        state.propagate(now, learner_params)
        update_pending_admissions(
            history,
            state,
            agent.session,
            scheduler_params,
            learner_params,
            now,
            selection_index,
        )
        session_before = copy.deepcopy(agent.session)

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
                    "scheduler_intent": "none",
                }
            )
            continue

        original = agent.records[-1].selected
        assert original is not None
        chosen = choose_with_suppression(
            variant, agent, original, state, now, session_before, history
        )
        if chosen is None:
            agent.records[-1].selected = None
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
                    "scheduler_intent": "probe_suppressed_no_alternative",
                }
            )
            continue
        agent.records[-1].selected = chosen
        exercise = chosen.exercise
        material_id = exercise.material.material_id
        intent = pass11.support_intent(chosen.challenge_bypass)
        prediction = predicted_success(state, exercise, now, learner_params)
        true_p = pass10.true_retrievability(truth, material_id, now)

        pre_memory_uncertainty = pass11.operative_memory_uncertainty(
            state, material_id, learner_params
        )
        memory_before = state.material_memory.get(material_id)
        pre_consolidation_variance = (
            memory_before.consolidated_log_half_life_variance
            if memory_before is not None
            else learner_params.material_memory.consolidation_prior_log_variance
        )
        pre_competency_variance = pass11.relevant_competency_variance(state, exercise)
        pre_execution_variance = pass11.execution_variance(
            state, exercise, learner_params
        )
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
        memory_after = state.material_memory[material_id]
        post_memory_uncertainty = pass11.operative_memory_uncertainty(
            state, material_id, learner_params
        )
        post_competency_variance = pass11.relevant_competency_variance(state, exercise)
        post_execution_variance = pass11.execution_variance(
            state, exercise, learner_params
        )
        agent.on_outcome(exercise, outcome, now)

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
            "retrieval_observed": outcome.retrieval_succeeded is not None,
            "retrieval_succeeded": (
                outcome.retrieval_succeeded
                if outcome.retrieval_succeeded is not None
                else ""
            ),
            "predicted_retrieval_p": prediction.independent_retrieval_p,
            "true_retrieval_p": true_p,
            "retrieval_bias": prediction.independent_retrieval_p - true_p,
        }
        rows.append(row)

        if intent == "guidance_probe":
            prior_events = history.events_by_material[material_id]
            previous = prior_events[-1] if prior_events else None
            event = {
                **row,
                "probe_number": len(prior_events) + 1,
                "probe_ordinal_band": ordinal_band(len(prior_events) + 1),
                "time_since_previous_probe_days": (
                    now - float(previous["at_days"]) if previous is not None else ""
                ),
                "pre_memory_uncertainty": pre_memory_uncertainty,
                "memory_uncertainty_band": uncertainty_band(pre_memory_uncertainty),
                "pre_consolidation_log_variance": pre_consolidation_variance,
                "consolidation_variance_band": consolidation_variance_band(
                    pre_consolidation_variance
                ),
                "pre_competency_variance": pre_competency_variance,
                "pre_execution_variance": pre_execution_variance,
                "memory_evidence_weight": weights.material_memory,
                "expected_information": chosen.information,
                "retrieval_prediction_change": (
                    post_prediction.independent_retrieval_p
                    - prediction.independent_retrieval_p
                ),
                "memory_uncertainty_reduction": (
                    pre_memory_uncertainty - post_memory_uncertainty
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
                "next_probe_delay_days": "",
                "selections_until_next_probe": "",
                "later_unguided_admitted": "",
                "days_until_unguided_admission": "",
                "selections_until_unguided_admission": "",
                "exercise": exercise,
            }
            if previous is not None:
                previous["next_probe_delay_days"] = now - float(previous["at_days"])
                previous["selections_until_next_probe"] = selection_index - int(
                    previous["selection_index"]
                )
            prior_events.append(event)
        selection_index += 1

    events = [
        event
        for material_events in history.events_by_material.values()
        for event in material_events
    ]
    for event in events:
        event.pop("exercise")
        if event["later_unguided_admitted"] == "":
            event["later_unguided_admitted"] = False
    memory_uncertainties = [
        pass11.operative_memory_uncertainty(state, material.material_id, learner_params)
        for material in MATERIAL_POOL
    ]
    consolidation_variances = [
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
        history.suppressed_winners,
        mean(memory_uncertainties),
        mean(consolidation_variances),
    )


def optional_mean(rows: list[dict[str, Any]], field: str) -> float | None:
    values = [float(row[field]) for row in rows if row[field] != ""]
    return mean(values) if values else None


def summarize_yield(rows: list[dict[str, Any]], keys: dict[str, Any]) -> dict[str, Any]:
    return {
        **keys,
        "probe_count": len(rows),
        "retrieval_success_fraction": mean(
            float(row["retrieval_succeeded"]) for row in rows
        ),
        "mean_expected_information": optional_mean(rows, "expected_information"),
        "mean_absolute_retrieval_prediction_change": mean(
            abs(float(row["retrieval_prediction_change"])) for row in rows
        ),
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
        "mean_next_probe_delay_days": optional_mean(rows, "next_probe_delay_days"),
        "later_unguided_admission_fraction": mean(
            float(row["later_unguided_admitted"]) for row in rows
        ),
        "mean_days_until_unguided_admission": optional_mean(
            rows, "days_until_unguided_admission"
        ),
    }


def yield_group_summaries(
    events: list[dict[str, Any]], field: str
) -> list[dict[str, Any]]:
    control = [row for row in events if row["variant"] == "control"]
    groups: defaultdict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in control:
        groups[("all", str(row[field]))].append(row)
        groups[(row["profile"], str(row[field]))].append(row)
    return [
        summarize_yield(group, {"profile": key[0], field: key[1]})
        for key, group in sorted(groups.items())
    ]


def pearson(rows: list[dict[str, Any]], field: str) -> float | None:
    pairs = [
        (float(row["expected_information"]), float(row[field]))
        for row in rows
        if row[field] != ""
    ]
    if len(pairs) < 2:
        return None
    xs, ys = zip(*pairs, strict=True)
    x_mean, y_mean = mean(xs), mean(ys)
    numerator = sum((x - x_mean) * (y - y_mean) for x, y in pairs)
    denominator = math.sqrt(
        sum((x - x_mean) ** 2 for x in xs) * sum((y - y_mean) ** 2 for y in ys)
    )
    return numerator / denominator if denominator else None


def information_calibration(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    fields = (
        "memory_uncertainty_reduction",
        "consolidation_log_variance_reduction",
        "competency_variance_reduction",
        "execution_variance_reduction",
        "retrieval_prediction_change",
    )
    result = []
    control = [row for row in events if row["variant"] == "control"]
    for profile in ("all", *(fixture.label for fixture in FIXTURES)):
        group = (
            control
            if profile == "all"
            else [r for r in control if r["profile"] == profile]
        )
        result.append(
            {
                "profile": profile,
                "probe_count": len(group),
                **{f"correlation_{field}": pearson(group, field) for field in fields},
            }
        )
    return result


def summarize_seed(
    rows: list[dict[str, Any]],
    events: list[dict[str, Any]],
    suppressed: int,
    final_memory_uncertainty: float,
    final_consolidation_variance: float,
) -> dict[str, Any]:
    selected = [row for row in rows if row["selected"]]
    observed = [row for row in selected if row["retrieval_observed"]]
    counts = Counter(row["material_id"] for row in selected)
    first = rows[0]
    return {
        "variant": first["variant"],
        "profile": first["profile"],
        "seed": first["seed"],
        "guidance_probe_count": len(events),
        "suppressed_probe_winner_count": suppressed,
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
        "later_unguided_admission_fraction": (
            mean(float(row["later_unguided_admitted"]) for row in events)
            if events
            else None
        ),
        "mean_days_until_unguided_admission": optional_mean(
            events, "days_until_unguided_admission"
        ),
        "final_mean_memory_uncertainty": final_memory_uncertainty,
        "final_mean_consolidation_log_variance": final_consolidation_variance,
        "max_material_selection_fraction": max(counts.values()) / len(selected),
        "max_revisit_gap_days": max_revisit_gap(rows),
        "no_admission_count": sum(not row["selected"] for row in rows),
    }


POLICY_FIELDS = (
    "guidance_probe_count",
    "suppressed_probe_winner_count",
    "recovery_count",
    "retrieval_prediction_mae",
    "retrieval_prediction_brier",
    "later_unguided_admission_fraction",
    "mean_days_until_unguided_admission",
    "final_mean_memory_uncertainty",
    "final_mean_consolidation_log_variance",
    "max_material_selection_fraction",
    "max_revisit_gap_days",
    "no_admission_count",
)


def policy_summaries(seed_rows, include_profile: bool):
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
        summary = {"variant": variant}
        if profile is not None:
            summary["profile"] = profile
        summary.update(
            {
                field: mean(
                    float(row[field]) for row in group if row[field] is not None
                )
                if any(row[field] is not None for row in group)
                else None
                for field in POLICY_FIELDS
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


def report(ordinal_rows, variant_rows) -> None:
    print("Control guidance-probe marginal yield by ordinal band:")
    aggregates: defaultdict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in ordinal_rows:
        if row["profile"] == "all":
            aggregates[row["probe_ordinal_band"]].append(row)
    for band in ("1-2", "3-5", "6-8", "9+"):
        group = aggregates[band]
        if not group:
            continue
        print(
            f"  {band:<4} probes={sum(int(r['probe_count']) for r in group):>5} "
            f"info={mean(float(r['mean_expected_information']) for r in group):.3f} "
            f"memory_delta={mean(float(r['mean_memory_uncertainty_reduction']) for r in group):.3f} "
            f"consolidation_delta={mean(float(r['mean_consolidation_log_variance_reduction']) for r in group):.3f}"
        )
    print()
    print("Probe-suppression policy guardrails:")
    for row in variant_rows:
        print(
            f"  {row['variant']:<23} probes={display(row['guidance_probe_count'])} "
            f"suppressed={display(row['suppressed_probe_winner_count'])} "
            f"MAE={display(row['retrieval_prediction_mae'])} "
            f"Brier={display(row['retrieval_prediction_brier'])} "
            f"recovery={display(row['recovery_count'])} "
            f"no_admission={display(row['no_admission_count'])}"
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
    all_events = [
        event for _rows, events, _suppressed, _fm, _fc in chunks for event in events
    ]
    seed_rows = [
        summarize_seed(rows, events, suppressed, final_memory, final_consolidation)
        for rows, events, suppressed, final_memory, final_consolidation in chunks
    ]
    exact_ordinal_rows = yield_group_summaries(all_events, "probe_number")
    ordinal_rows = yield_group_summaries(all_events, "probe_ordinal_band")
    uncertainty_rows = yield_group_summaries(all_events, "memory_uncertainty_band")
    consolidation_rows = yield_group_summaries(
        all_events, "consolidation_variance_band"
    )
    calibration_rows = information_calibration(all_events)
    profile_rows = policy_summaries(seed_rows, include_profile=True)
    variant_rows = policy_summaries(seed_rows, include_profile=False)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    artifacts = {
        "guidance_probe_events.csv": all_events,
        "guidance_probe_exact_ordinal_summary.csv": exact_ordinal_rows,
        "guidance_probe_ordinal_summary.csv": ordinal_rows,
        "guidance_probe_uncertainty_summary.csv": uncertainty_rows,
        "guidance_probe_consolidation_variance_summary.csv": consolidation_rows,
        "guidance_probe_information_calibration.csv": calibration_rows,
        "guidance_probe_policy_seed_summary.csv": seed_rows,
        "guidance_probe_policy_profile_summary.csv": profile_rows,
        "guidance_probe_policy_variant_summary.csv": variant_rows,
    }
    for name, rows in artifacts.items():
        if rows:
            write_csv(args.output_dir / name, rows)
    report(ordinal_rows, variant_rows)


if __name__ == "__main__":
    main()
