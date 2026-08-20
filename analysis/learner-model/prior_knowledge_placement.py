"""Pass 10: prior-knowledge placement-policy characterization.

Cross-material evidence is consumed only as permission to reduce support on the
first encounter with an unseen material. It never changes predicted memory,
stored material state, learner parameters, candidate eligibility, or ranking.

Outputs (in --output-dir):
    prior_knowledge_trajectories.csv
    prior_knowledge_first_encounters.csv
    prior_knowledge_seed_summary.csv
    prior_knowledge_profile_summary.csv
    prior_knowledge_variant_summary.csv
    prior_knowledge_reversals.csv
"""

from __future__ import annotations

import argparse
import concurrent.futures
import copy
import csv
import dataclasses
import os
import random
from collections import Counter, defaultdict
from dataclasses import dataclass
from itertools import pairwise
from pathlib import Path
from statistics import mean
from typing import Any

import cold_start_identifiability as pass5
import cross_material_placement as pass6
from candidates import InstrumentProfile
from config import load_params as load_scheduler_params
from domain import Exercise, GuidanceContext
from longitudinal import NoAdmittedCandidate, SchedulerAgent
from model import evidence_weights, predicted_success, update
from params import load_params as load_learner_params
from simulate import fixed_exercise
from synthetic import PROFILES, TrueLearnerProfile, TrueMaterialMemory, sample_outcome

ATTEMPTS = pass5.ATTEMPTS
SESSION_ATTEMPTS = pass5.SESSION_ATTEMPTS
DAY_STEP = pass5.DAY_STEP
EARLY_SELECTIONS = pass5.EARLY_ATTEMPTS
MATERIAL_POOL = pass5.MATERIAL_POOL
DEFAULT_SEEDS = 30
DEFAULT_WORKERS = min(8, os.cpu_count() or 1)

VARIANTS = ("control", "notes_permission", "unguided_permission", "tiered")
LIGHT_EVIDENCE_COUNT = 2
LIGHT_EFFECTIVE_PRIOR = 0.55
UNGUIDED_EVIDENCE_COUNT = 3
UNGUIDED_EFFECTIVE_PRIOR = 0.60
MIXED_STRONG_COUNT = 3
SPARSE_STRONG_COUNT = 2
COMMON_KEY_IDS = frozenset({"C_MAJOR", "G_MAJOR", "F_MAJOR"})


@dataclass(frozen=True)
class Fixture:
    label: str
    source_profile: str
    memory_prior: float
    current_half_life_days: float
    knowledge_pattern: str = "global"


FIXTURES = (
    Fixture("beginner", "beginner", 0.40, 4.0),
    Fixture(
        "technique_strong_memory_weak",
        "technique_strong_memory_weak",
        0.15,
        0.5,
    ),
    Fixture(
        "memory_strong_technique_weak",
        "memory_strong_technique_weak",
        0.85,
        20.0,
    ),
    Fixture("broadly_strong", "advanced", 0.85, 20.0),
    Fixture("mixed_prior_knowledge", "advanced", 0.15, 0.5, "mixed"),
    Fixture("sparse_expert", "advanced", 0.15, 0.5, "sparse"),
    Fixture("common_keys_expert", "advanced", 0.15, 0.5, "common_keys"),
)


def build_truth(
    fixture: Fixture, seed: int
) -> tuple[TrueLearnerProfile, dict[str, str]]:
    truth = copy.deepcopy(PROFILES[fixture.source_profile])
    truth.name = fixture.label
    truth.memory_prior = fixture.memory_prior
    truth.default_current_half_life_days = fixture.current_half_life_days
    truth.true_material_memory.clear()

    default_class = (
        "strong"
        if fixture.memory_prior >= 0.70
        else "weak"
        if fixture.memory_prior <= 0.30
        else "ordinary"
    )
    material_ids = [material.material_id for material in MATERIAL_POOL]
    classes = dict.fromkeys(material_ids, default_class)
    if fixture.knowledge_pattern == "global":
        return truth, classes

    if fixture.knowledge_pattern == "common_keys":
        strong_ids = COMMON_KEY_IDS
    else:
        count = (
            MIXED_STRONG_COUNT
            if fixture.knowledge_pattern == "mixed"
            else SPARSE_STRONG_COUNT
        )
        strong_ids = frozenset(
            random.Random(100_000 + seed).sample(material_ids, count)
        )

    for material_id in material_ids:
        classes[material_id] = "strong" if material_id in strong_ids else "weak"
        if material_id not in strong_ids:
            continue
        truth.true_material_memory[material_id] = TrueMaterialMemory(
            current_half_life_days=20.0,
            consolidated_half_life_days=20.0,
            memory_anchor_at=0.0,
            factual_last_retrieval_at=0.0,
            last_retrieval_attempt_at=0.0,
        )
    return truth, classes


def true_retrievability(
    truth: TrueLearnerProfile, material_id: str, now: float
) -> float:
    memory = truth.true_material_memory.get(material_id)
    if memory is None:
        return truth.memory_prior
    return memory.retrievability(now, truth.memory_prior)


def guidance_rank(guidance: GuidanceContext) -> int:
    if guidance.concurrent_pitch_cues:
        return 2
    if guidance.notes_previewed:
        return 1
    return 0


def permission_level(variant: str, placement: pass6.PlacementMemoryState) -> str:
    light = (
        placement.evidence_count >= LIGHT_EVIDENCE_COUNT
        and placement.effective_prior >= LIGHT_EFFECTIVE_PRIOR
    )
    unguided = (
        placement.evidence_count >= UNGUIDED_EVIDENCE_COUNT
        and placement.effective_prior >= UNGUIDED_EFFECTIVE_PRIOR
    )
    if variant == "control":
        return "ordinary"
    if variant == "notes_permission":
        return "notes_previewed" if light else "ordinary"
    if variant == "unguided_permission":
        return "unguided" if light else "ordinary"
    if variant == "tiered":
        if unguided:
            return "unguided"
        return "notes_previewed" if light else "ordinary"
    raise ValueError(f"unknown variant: {variant}")


def apply_permission(
    exercise: Exercise, permission: str, first_encounter: bool
) -> tuple[Exercise, bool]:
    if not first_encounter or permission == "ordinary":
        return exercise, False
    target = (
        GuidanceContext()
        if permission == "unguided"
        else GuidanceContext(notes_previewed=True)
    )
    if guidance_rank(target) >= guidance_rank(exercise.guidance):
        return exercise, False
    return dataclasses.replace(exercise, guidance=target), True


def material_has_factual_evidence(state, material_id: str) -> bool:
    memory = state.material_memory.get(material_id)
    return memory is not None and memory.last_retrieval_attempt_at is not None


def run_case(variant: str, fixture: Fixture, seed: int) -> list[dict[str, Any]]:
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    truth, material_classes = build_truth(fixture, seed)
    state = pass5.common_estimator_state(learner_params)
    placement = pass6.PlacementMemoryState.new(learner_params)
    agent = SchedulerAgent(
        InstrumentProfile(), list(MATERIAL_POOL), scheduler_params, learner_params
    )
    rng = random.Random(seed)
    seen_materials: set[str] = set()
    factual_evidence_materials: set[str] = set()
    rows: list[dict[str, Any]] = []
    now = 0.0
    selection_index = 0

    for attempt_index in range(ATTEMPTS):
        if attempt_index and attempt_index % SESSION_ATTEMPTS == 0:
            agent.new_session()
        now += DAY_STEP
        state.propagate(now, learner_params)
        permission_before = permission_level(variant, placement)

        try:
            proposed = agent.pick(rng, attempt_index, state, now)
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
                    "first_encounter": False,
                    "proposed_guidance_level": "none",
                    "guidance_level": "none",
                    "placement_override": False,
                    "placement_permission_before": permission_before,
                    "placement_permission_after": permission_before,
                    "challenge_bypass": "none",
                    "retrieval_observed": False,
                    "retrieval_succeeded": "",
                    "predicted_retrieval_p": "",
                    "predicted_overall_p": "",
                    "observed_quality": "",
                    "true_retrieval_p": "",
                    "retrieval_bias": "",
                    "first_factual_observation": False,
                    "placement_effective_prior": placement.effective_prior,
                    "placement_evidence_count": placement.evidence_count,
                }
            )
            continue

        selected = agent.records[-1].selected
        assert selected is not None
        material_id = proposed.material.material_id
        first_encounter = material_id not in seen_materials
        first_factual = not material_has_factual_evidence(state, material_id)
        exercise, overridden = apply_permission(
            proposed, permission_before, first_encounter
        )
        if guidance_rank(exercise.guidance) > guidance_rank(proposed.guidance):
            raise AssertionError("placement policy added support")
        if overridden and not first_encounter:
            raise AssertionError("placement policy changed a repeated encounter")

        prediction = predicted_success(state, exercise, now, learner_params)
        true_p = true_retrievability(truth, material_id, now)
        outcome = sample_outcome(truth, exercise, now, rng)
        weights = evidence_weights(exercise, outcome)
        observed_quality = mean(
            (
                outcome.pitch_integrity,
                outcome.continuity,
                outcome.temporal_stability,
            )
        )
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

        is_first_factual = (
            first_factual
            and outcome.retrieval_succeeded is not None
            and material_id not in factual_evidence_materials
        )
        if is_first_factual:
            placement.observe(
                bool(outcome.retrieval_succeeded), weights.material_memory
            )
            factual_evidence_materials.add(material_id)
        permission_after = permission_level(variant, placement)

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
                "first_encounter": first_encounter,
                "proposed_guidance_level": pass5.guidance_level(proposed),
                "guidance_level": pass5.guidance_level(exercise),
                "placement_override": overridden,
                "placement_permission_before": permission_before,
                "placement_permission_after": permission_after,
                "challenge_bypass": selected.challenge_bypass or "none",
                "retrieval_observed": outcome.retrieval_succeeded is not None,
                "retrieval_succeeded": (
                    outcome.retrieval_succeeded
                    if outcome.retrieval_succeeded is not None
                    else ""
                ),
                "predicted_retrieval_p": prediction.independent_retrieval_p,
                "predicted_overall_p": prediction.overall_p,
                "observed_quality": observed_quality,
                "true_retrieval_p": true_p,
                "retrieval_bias": prediction.independent_retrieval_p - true_p,
                "first_factual_observation": is_first_factual,
                "placement_effective_prior": placement.effective_prior,
                "placement_evidence_count": placement.evidence_count,
            }
        )
        seen_materials.add(material_id)
        selection_index += 1

    return rows


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
    early = selected[:EARLY_SELECTIONS]
    observed = [row for row in selected if row["retrieval_observed"]]
    first_encounters = [row for row in selected if row["first_encounter"]]
    observed_first_encounters = [
        row for row in first_encounters if row["retrieval_observed"]
    ]
    counts = Counter(row["material_id"] for row in selected)
    threshold_rows = [
        row for row in selected if row["placement_permission_before"] != "ordinary"
    ]
    reversals = [
        row
        for row in selected
        if row["placement_permission_before"] != "ordinary"
        and row["placement_permission_after"] == "ordinary"
    ]
    first = rows[0]
    return {
        "variant": first["variant"],
        "profile": first["profile"],
        "seed": first["seed"],
        "early_unnecessary_cueing_count": sum(
            float(row["true_retrieval_p"]) >= 0.70
            and row["guidance_level"] != "unguided"
            for row in early
        ),
        "early_unguided_low_memory_count": sum(
            float(row["true_retrieval_p"]) <= 0.30
            and row["guidance_level"] == "unguided"
            for row in early
        ),
        "first_encounter_count": len(first_encounters),
        "first_encounter_unguided_count": sum(
            row["guidance_level"] == "unguided" for row in first_encounters
        ),
        "first_encounter_notes_previewed_count": sum(
            row["guidance_level"] == "notes_previewed" for row in first_encounters
        ),
        "first_encounter_concurrent_cues_count": sum(
            row["guidance_level"] == "concurrent_pitch_cues" for row in first_encounters
        ),
        "first_encounter_success_rate": (
            mean(float(row["retrieval_succeeded"]) for row in observed_first_encounters)
            if observed_first_encounters
            else None
        ),
        "false_high_placement_count": sum(
            row["guidance_level"] == "unguided"
            and float(row["true_retrieval_p"]) <= 0.30
            for row in first_encounters
        ),
        "false_low_placement_count": sum(
            row["guidance_level"] != "unguided"
            and float(row["true_retrieval_p"]) >= 0.70
            for row in first_encounters
        ),
        "strong_first_encounter_cueing_count": sum(
            row["truth_memory_class"] == "strong"
            and row["guidance_level"] != "unguided"
            for row in first_encounters
        ),
        "weak_first_encounter_unguided_count": sum(
            row["truth_memory_class"] == "weak" and row["guidance_level"] == "unguided"
            for row in first_encounters
        ),
        "materials_tested_before_threshold": (
            int(threshold_rows[0]["placement_evidence_count"])
            if threshold_rows
            else None
        ),
        "attempts_until_threshold": (
            int(threshold_rows[0]["selection_index"]) + 1 if threshold_rows else None
        ),
        "attempts_until_confidence_reverses": (
            int(reversals[0]["selection_index"])
            - int(threshold_rows[0]["selection_index"])
            + 1
            if reversals and threshold_rows
            else None
        ),
        "placement_override_count": sum(row["placement_override"] for row in selected),
        "early_guided_guidance_probe_count": sum(
            row["guidance_level"] != "unguided"
            and row["challenge_bypass"] == "guidance_probe"
            for row in early
        ),
        "early_guided_recovery_count": sum(
            row["guidance_level"] != "unguided"
            and row["challenge_bypass"] == "recovery"
            for row in early
        ),
        "retrieval_prediction_mae": mean(
            abs(float(row["retrieval_bias"])) for row in observed
        ),
        "retrieval_prediction_brier": mean(
            (float(row["predicted_retrieval_p"]) - float(row["retrieval_succeeded"]))
            ** 2
            for row in observed
        ),
        "overall_prediction_mae": mean(
            abs(float(row["predicted_overall_p"]) - float(row["observed_quality"]))
            for row in selected
        ),
        "recovery_fraction": mean(
            row["challenge_bypass"] == "recovery" for row in selected
        ),
        "max_material_selection_fraction": max(counts.values()) / len(selected),
        "max_revisit_gap_days": max_revisit_gap(rows),
        "no_admission_count": sum(not row["selected"] for row in rows),
    }


SUMMARY_FIELDS = (
    "early_unnecessary_cueing_count",
    "early_unguided_low_memory_count",
    "first_encounter_count",
    "first_encounter_unguided_count",
    "first_encounter_notes_previewed_count",
    "first_encounter_concurrent_cues_count",
    "first_encounter_success_rate",
    "false_high_placement_count",
    "false_low_placement_count",
    "strong_first_encounter_cueing_count",
    "weak_first_encounter_unguided_count",
    "materials_tested_before_threshold",
    "attempts_until_threshold",
    "attempts_until_confidence_reverses",
    "placement_override_count",
    "early_guided_guidance_probe_count",
    "early_guided_recovery_count",
    "retrieval_prediction_mae",
    "retrieval_prediction_brier",
    "overall_prediction_mae",
    "recovery_fraction",
    "max_material_selection_fraction",
    "max_revisit_gap_days",
    "no_admission_count",
)


def optional_mean(rows: list[dict[str, Any]], field: str) -> float | None:
    values = [float(row[field]) for row in rows if row[field] is not None]
    return mean(values) if values else None


def grouped_summary(
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
        summary.update({field: optional_mean(group, field) for field in SUMMARY_FIELDS})
        result.append(summary)
    return result


def reversal_rows(trajectories: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        row
        for row in trajectories
        if row["selected"]
        and row["placement_permission_before"] != "ordinary"
        and row["placement_permission_after"] == "ordinary"
    ]


def check_boundary() -> None:
    params = load_learner_params()
    placement = pass6.PlacementMemoryState.new(params)
    for _ in range(3):
        placement.observe(True, 1.0)
    sample = fixed_exercise(
        MATERIAL_POOL[0],
        "RIGHT",
        guidance=GuidanceContext(concurrent_pitch_cues=True),
    )
    changed, did_override = apply_permission(sample, "unguided", True)
    if not did_override or guidance_rank(changed.guidance) != 0:
        raise AssertionError(
            "placement permission did not reduce first-encounter support"
        )
    repeated, did_override = apply_permission(sample, "unguided", False)
    if did_override or repeated != sample:
        raise AssertionError("placement permission changed repeated practice")
    if params != load_learner_params():
        raise AssertionError("placement policy changed learner parameters")


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
    print("Pass 10 placement policies by profile (means across seeds):")
    print(
        "  variant                 profile                         "
        "early_cue risky_first false_low"
    )
    for row in profile_rows:
        print(
            f"  {row['variant']:<23} {row['profile']:<31} "
            f"{display(row['early_unnecessary_cueing_count']):>9} "
            f"{display(row['weak_first_encounter_unguided_count']):>11} "
            f"{display(row['false_low_placement_count']):>9}"
        )
    print()
    print("Aggregate guardrails across Pass 10 fixtures:")
    for row in variant_rows:
        print(
            f"  {row['variant']:<23} "
            f"MAE={display(row['retrieval_prediction_mae'])} "
            f"Brier={display(row['retrieval_prediction_brier'])} "
            f"recovery={display(row['recovery_fraction'])} "
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


def main() -> None:
    args = parse_args()
    if args.seeds < 1 or args.workers < 1:
        raise SystemExit("--seeds and --workers must be positive")
    check_boundary()
    jobs = [
        (variant, fixture, seed)
        for variant in VARIANTS
        for fixture in FIXTURES
        for seed in range(args.seeds)
    ]
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        chunks = list(pool.map(run_case_star, jobs))
    trajectories = [row for chunk in chunks for row in chunk]
    seed_rows = [summarize_seed(chunk) for chunk in chunks]
    profile_rows = grouped_summary(seed_rows, include_profile=True)
    variant_rows = grouped_summary(seed_rows, include_profile=False)
    first_encounters = [row for row in trajectories if row["first_encounter"]]
    reversals = reversal_rows(trajectories)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    artifacts = {
        "prior_knowledge_trajectories.csv": trajectories,
        "prior_knowledge_first_encounters.csv": first_encounters,
        "prior_knowledge_seed_summary.csv": seed_rows,
        "prior_knowledge_profile_summary.csv": profile_rows,
        "prior_knowledge_variant_summary.csv": variant_rows,
        "prior_knowledge_reversals.csv": reversals,
    }
    for name, rows in artifacts.items():
        if rows:
            write_csv(args.output_dir / name, rows)
    report(profile_rows, variant_rows)


def run_case_star(args: tuple[str, Fixture, int]) -> list[dict[str, Any]]:
    return run_case(*args)


if __name__ == "__main__":
    main()
