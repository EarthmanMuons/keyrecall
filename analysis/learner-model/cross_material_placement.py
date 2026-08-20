"""Pass 6: cross-material placement-memory characterization.

This diagnostic compares production behavior with two placement-only sidecars.
Both pool the first factual retrieval observation from each material into an
epistemic learner-level prior for still-unestablished materials. Neither changes
ordinary material-memory transitions or scheduler policy.

Outputs (in --output-dir):
    placement_profile_summary.csv
    placement_variant_summary.csv
    placement_trajectories.csv
    placement_reversibility.csv
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
from candidates import InstrumentProfile
from config import load_params as load_scheduler_params
from longitudinal import NoAdmittedCandidate, SchedulerAgent
from model import evidence_weights, predicted_success, update
from params import Params as LearnerParams
from params import load_params as load_learner_params
from state import LearnerState, logit
from synthetic import PROFILES, TrueLearnerProfile, TrueMaterialMemory, sample_outcome

ATTEMPTS = pass5.ATTEMPTS
SESSION_ATTEMPTS = pass5.SESSION_ATTEMPTS
DAY_STEP = pass5.DAY_STEP
EARLY_SELECTIONS = pass5.EARLY_ATTEMPTS
MATERIAL_POOL = pass5.MATERIAL_POOL
DEFAULT_SEEDS = 30
DEFAULT_WORKERS = min(8, os.cpu_count() or 1)

VARIANTS = ("control", "pooled_prior", "pooled_prior_uncertainty")
PLACEMENT_PRIOR_STRENGTH = 2.0
MIXED_STRONG_MATERIAL_COUNT = 3


@dataclass(frozen=True)
class Fixture:
    label: str
    source_profile: str
    memory_prior: float
    current_half_life_days: float
    mixed_prior_knowledge: bool = False


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
    Fixture(
        "mixed_prior_knowledge",
        "advanced",
        0.15,
        0.5,
        mixed_prior_knowledge=True,
    ),
)


@dataclass
class PlacementMemoryState:
    """Epistemic placement belief, never synthetic learner truth."""

    prior_estimate: float
    prior_uncertainty: float
    estimate: float
    uncertainty: float
    evidence_count: int = 0
    evidence_mass: float = 0.0
    weighted_successes: float = 0.0

    @classmethod
    def new(cls, params: LearnerParams) -> PlacementMemoryState:
        mm = params.material_memory
        return cls(
            prior_estimate=mm.prior_retrievability,
            prior_uncertainty=mm.prior_uncertainty,
            estimate=mm.prior_retrievability,
            uncertainty=mm.prior_uncertainty,
        )

    @property
    def confidence(self) -> float:
        if self.prior_uncertainty <= 0.0:
            return 1.0
        return max(0.0, min(1.0, 1.0 - self.uncertainty / self.prior_uncertainty))

    @property
    def effective_prior(self) -> float:
        return self.prior_estimate + self.confidence * (
            self.estimate - self.prior_estimate
        )

    def observe(self, succeeded: bool, weight: float) -> None:
        if weight <= 0.0:
            return
        self.evidence_count += 1
        self.evidence_mass += weight
        self.weighted_successes += weight * float(succeeded)
        denominator = PLACEMENT_PRIOR_STRENGTH + self.evidence_mass
        self.estimate = (
            PLACEMENT_PRIOR_STRENGTH * self.prior_estimate + self.weighted_successes
        ) / denominator
        self.uncertainty = self.prior_uncertainty * (
            PLACEMENT_PRIOR_STRENGTH / denominator
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
    material_classes = dict.fromkeys(
        (material.material_id for material in MATERIAL_POOL), default_class
    )
    if not fixture.mixed_prior_knowledge:
        return truth, material_classes

    chooser = random.Random(100_000 + seed)
    strong_ids = set(
        chooser.sample(
            [material.material_id for material in MATERIAL_POOL],
            MIXED_STRONG_MATERIAL_COUNT,
        )
    )
    for material in MATERIAL_POOL:
        material_id = material.material_id
        if material_id not in strong_ids:
            material_classes[material_id] = "weak"
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


def material_has_factual_evidence(state: LearnerState, material_id: str) -> bool:
    memory = state.material_memory.get(material_id)
    return memory is not None and memory.last_retrieval_attempt_at is not None


def effective_learner_params(
    state: LearnerState,
    placement: PlacementMemoryState,
    variant: str,
    base_params: LearnerParams,
) -> LearnerParams:
    if variant == "control":
        return base_params

    mm = base_params.material_memory
    cold_uncertainty = (
        placement.uncertainty
        if variant == "pooled_prior_uncertainty"
        else mm.prior_uncertainty
    )
    effective_mm = dataclasses.replace(
        mm,
        prior_retrievability=placement.effective_prior,
        prior_uncertainty=cold_uncertainty,
    )
    for memory in state.material_memory.values():
        if memory.last_retrieval_attempt_at is not None:
            continue
        if memory.memory_anchor_at is not None:
            raise AssertionError("an anchored material lacks factual retrieval history")
        memory.logit_cold_start = logit(placement.effective_prior)
        if variant == "pooled_prior_uncertainty":
            memory.cold_start_uncertainty = cold_uncertainty
    return dataclasses.replace(base_params, material_memory=effective_mm)


def run_case(variant: str, fixture: Fixture, seed: int) -> list[dict[str, Any]]:
    base_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    truth, material_classes = build_truth(fixture, seed)
    state = pass5.common_estimator_state(base_params)
    placement = PlacementMemoryState.new(base_params)
    agent = SchedulerAgent(
        InstrumentProfile(),
        list(MATERIAL_POOL),
        scheduler_params,
        base_params,
    )
    rng = random.Random(seed)
    rows = []
    now = 0.0
    selection_index = 0

    for attempt_index in range(ATTEMPTS):
        if attempt_index and attempt_index % SESSION_ATTEMPTS == 0:
            agent.new_session()
        now += DAY_STEP
        state.propagate(now, base_params)
        learner_params = effective_learner_params(
            state, placement, variant, base_params
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
                    "guidance_level": "none",
                    "challenge_bypass": "none",
                    "challenge_within_band": "",
                    "retrieval_observed": False,
                    "retrieval_succeeded": "",
                    "predicted_retrieval_p": "",
                    "true_retrieval_p": "",
                    "retrieval_bias": "",
                    "first_factual_observation": False,
                    "placement_memory_estimate": placement.estimate,
                    "placement_effective_prior": placement.effective_prior,
                    "placement_memory_uncertainty": placement.uncertainty,
                    "placement_memory_evidence_count": placement.evidence_count,
                }
            )
            continue

        selected = agent.records[-1].selected
        assert selected is not None
        material_id = exercise.material.material_id
        first_factual = not material_has_factual_evidence(state, material_id)
        prediction = predicted_success(state, exercise, now, learner_params)
        true_p = true_retrievability(truth, material_id, now)
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
        agent.on_outcome(exercise, outcome, now)

        is_first_factual_observation = (
            first_factual and outcome.retrieval_succeeded is not None
        )
        if variant != "control" and is_first_factual_observation:
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
                "guidance_level": pass5.guidance_level(exercise),
                "challenge_bypass": selected.challenge_bypass or "none",
                "challenge_within_band": selected.challenge_within_band,
                "retrieval_observed": outcome.retrieval_succeeded is not None,
                "retrieval_succeeded": (
                    outcome.retrieval_succeeded
                    if outcome.retrieval_succeeded is not None
                    else ""
                ),
                "predicted_retrieval_p": prediction.independent_retrieval_p,
                "true_retrieval_p": true_p,
                "retrieval_bias": prediction.independent_retrieval_p - true_p,
                "first_factual_observation": is_first_factual_observation,
                "placement_memory_estimate": placement.estimate,
                "placement_effective_prior": placement.effective_prior,
                "placement_memory_uncertainty": placement.uncertainty,
                "placement_memory_evidence_count": placement.evidence_count,
            }
        )
        selection_index += 1

    return rows


def attempts_to_diverge_from_beginner(
    trajectories: list[dict[str, Any]], variant: str, profile: str
) -> int | None:
    grouped: dict[tuple[str, int], list[float]] = defaultdict(list)
    for row in trajectories:
        if row["variant"] != variant or not row["selected"]:
            continue
        grouped[(row["profile"], int(row["selection_index"]))].append(
            float(row["predicted_retrieval_p"])
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
    for start in range(ATTEMPTS - pass5.CALIBRATION_WINDOW + 1):
        window = range(start, start + pass5.CALIBRATION_WINDOW)
        if all(
            index in beginner
            and index in target
            and abs(target[index] - beginner[index]) >= pass5.DIVERGENCE_THRESHOLD
            for index in window
        ):
            return start + 1
    return None


def max_revisit_gap(rows: list[dict[str, Any]]) -> float:
    visits: dict[str, list[float]] = defaultdict(list)
    for row in rows:
        if row["selected"]:
            visits[row["material_id"]].append(float(row["at_days"]))
    gaps = [
        later - earlier
        for material_visits in visits.values()
        for earlier, later in pairwise(material_visits)
    ]
    return max(gaps, default=0.0)


def summarize_seed(rows: list[dict[str, Any]]) -> dict[str, Any]:
    selected = [row for row in rows if row["selected"]]
    early = selected[:EARLY_SELECTIONS]
    observed = [row for row in selected if row["retrieval_observed"]]
    tail = selected[-10:]
    counts = Counter(row["material_id"] for row in selected)
    first = rows[0]
    return {
        "variant": first["variant"],
        "profile": first["profile"],
        "seed": first["seed"],
        "attempts_to_calibrated_band": pass5.attempts_to_stable_calibration(rows),
        "calibrated_by_end": pass5.attempts_to_stable_calibration(rows) is not None,
        "attempts_to_stable_challenge_band": (
            pass5.attempts_to_stable_challenge_band(rows)
        ),
        "stable_challenge_band_by_end": (
            pass5.attempts_to_stable_challenge_band(rows) is not None
        ),
        "early_retrieval_observation_fraction": mean(
            float(row["retrieval_observed"]) for row in early
        ),
        "early_recovery_fraction": mean(
            row["challenge_bypass"] == "recovery" for row in early
        ),
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
        "final_retrieval_bias": mean(float(row["retrieval_bias"]) for row in tail),
        "retrieval_prediction_mae": mean(
            abs(float(row["retrieval_bias"])) for row in observed
        ),
        "retrieval_prediction_brier": mean(
            (float(row["predicted_retrieval_p"]) - float(row["retrieval_succeeded"]))
            ** 2
            for row in observed
        ),
        "max_material_selection_fraction": (
            max(counts.values(), default=0) / len(selected) if selected else 0.0
        ),
        "max_revisit_gap_days": max_revisit_gap(rows),
        "no_admission_count": sum(not row["selected"] for row in rows),
        "final_placement_estimate": float(rows[-1]["placement_memory_estimate"]),
        "final_placement_effective_prior": float(rows[-1]["placement_effective_prior"]),
        "final_placement_uncertainty": float(rows[-1]["placement_memory_uncertainty"]),
        "final_placement_evidence_count": int(
            rows[-1]["placement_memory_evidence_count"]
        ),
    }


def optional_mean(rows: list[dict[str, Any]], field: str) -> float | None:
    values = [float(row[field]) for row in rows if row[field] is not None]
    return mean(values) if values else None


def profile_summaries(
    seed_summaries: list[dict[str, Any]], trajectories: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    rows = []
    numeric_fields = (
        "attempts_to_calibrated_band",
        "attempts_to_stable_challenge_band",
        "early_retrieval_observation_fraction",
        "early_recovery_fraction",
        "early_unnecessary_cueing_count",
        "early_unguided_low_memory_count",
        "early_strong_material_cueing_count",
        "early_weak_material_unguided_count",
        "final_retrieval_bias",
        "retrieval_prediction_mae",
        "retrieval_prediction_brier",
        "max_material_selection_fraction",
        "max_revisit_gap_days",
        "no_admission_count",
        "final_placement_estimate",
        "final_placement_effective_prior",
        "final_placement_uncertainty",
        "final_placement_evidence_count",
    )
    for variant in VARIANTS:
        for fixture in FIXTURES:
            group = [
                row
                for row in seed_summaries
                if row["variant"] == variant and row["profile"] == fixture.label
            ]
            summary = {"variant": variant, "profile": fixture.label}
            summary.update(
                {field: optional_mean(group, field) for field in numeric_fields}
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
            rows.append(summary)
    return rows


def variant_summaries(
    seed_summaries: list[dict[str, Any]], trajectories: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    rows = []
    for variant in VARIANTS:
        selected = [
            row for row in trajectories if row["variant"] == variant and row["selected"]
        ]
        observed = [row for row in selected if row["retrieval_observed"]]
        seed_group = [row for row in seed_summaries if row["variant"] == variant]
        rows.append(
            {
                "variant": variant,
                "retrieval_observation_count": len(observed),
                "retrieval_prediction_bias": mean(
                    float(row["retrieval_bias"]) for row in observed
                ),
                "retrieval_prediction_mae": mean(
                    abs(float(row["retrieval_bias"])) for row in observed
                ),
                "retrieval_prediction_brier": mean(
                    (
                        float(row["predicted_retrieval_p"])
                        - float(row["retrieval_succeeded"])
                    )
                    ** 2
                    for row in observed
                ),
                "recovery_fraction": mean(
                    row["challenge_bypass"] == "recovery" for row in selected
                ),
                "mean_max_material_selection_fraction": optional_mean(
                    seed_group, "max_material_selection_fraction"
                ),
                "mean_max_revisit_gap_days": optional_mean(
                    seed_group, "max_revisit_gap_days"
                ),
                "mean_no_admission_count": optional_mean(
                    seed_group, "no_admission_count"
                ),
            }
        )
    return rows


def reversibility_rows(params: LearnerParams) -> list[dict[str, Any]]:
    rows = []
    for sequence_name, outcomes in (
        ("late_contradiction", (True, True, True, False, False, False)),
        ("late_confirmation", (False, False, False, True, True, True)),
    ):
        placement = PlacementMemoryState.new(params)
        for index, succeeded in enumerate(outcomes, start=1):
            placement.observe(succeeded, 1.0)
            rows.append(
                {
                    "sequence": sequence_name,
                    "observation_index": index,
                    "retrieval_succeeded": succeeded,
                    "placement_memory_estimate": placement.estimate,
                    "placement_effective_prior": placement.effective_prior,
                    "placement_memory_uncertainty": placement.uncertainty,
                    "placement_memory_evidence_count": placement.evidence_count,
                }
            )
    return rows


def check_intervention_boundary(params: LearnerParams) -> None:
    state = pass5.common_estimator_state(params)
    established = state.material_memory_for(MATERIAL_POOL[0].material_id, params)
    established.memory_anchor_at = 1.0
    established.factual_last_retrieval_at = 1.0
    established.last_retrieval_attempt_at = 1.0
    unestablished = state.material_memory_for(MATERIAL_POOL[1].material_id, params)
    before = copy.deepcopy(state)
    placement = PlacementMemoryState.new(params)
    placement.observe(True, 1.0)
    effective = effective_learner_params(
        state, placement, "pooled_prior_uncertainty", params
    )
    established_before = before.material_memory[MATERIAL_POOL[0].material_id]
    if established != established_before:
        raise AssertionError("placement intervention changed established state")
    if state.competencies != before.competencies:
        raise AssertionError("placement intervention changed competency state")
    if effective.material_memory.initial_current_half_life_days != (
        params.material_memory.initial_current_half_life_days
    ):
        raise AssertionError("placement intervention changed durability initialization")
    restored = dataclasses.replace(
        effective.material_memory,
        prior_retrievability=params.material_memory.prior_retrievability,
        prior_uncertainty=params.material_memory.prior_uncertainty,
    )
    if restored != params.material_memory:
        raise AssertionError("placement intervention changed ordinary memory params")
    if unestablished.current_half_life_days != (
        before.material_memory[MATERIAL_POOL[1].material_id].current_half_life_days
    ):
        raise AssertionError("placement intervention changed current durability")
    if unestablished.consolidated_half_life_days != (
        before.material_memory[MATERIAL_POOL[1].material_id].consolidated_half_life_days
    ):
        raise AssertionError("placement intervention changed consolidation")


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
    print("Placement variants by profile (means across seeds):")
    print(
        "  variant                         profile                         "
        "unneeded_cue low_memory_unguided final_bias"
    )
    for row in profile_rows:
        print(
            f"  {row['variant']:<31} {row['profile']:<31} "
            f"{display(row['early_unnecessary_cueing_count']):>12} "
            f"{display(row['early_unguided_low_memory_count']):>19} "
            f"{display(row['final_retrieval_bias']):>10}"
        )
    print()
    print("Aggregate guardrails across Pass 6 fixtures:")
    for row in variant_rows:
        print(
            f"  {row['variant']:<31} "
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
    params = load_learner_params()
    check_intervention_boundary(params)
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
    seed_summaries = [summarize_seed(rows) for rows in case_rows]
    profiles = profile_summaries(seed_summaries, trajectories)
    variants = variant_summaries(seed_summaries, trajectories)
    reversibility = reversibility_rows(params)
    outputs = {
        "placement_profile_summary.csv": profiles,
        "placement_variant_summary.csv": variants,
        "placement_trajectories.csv": trajectories,
        "placement_reversibility.csv": reversibility,
    }
    for filename, rows in outputs.items():
        write_csv(args.output_dir / filename, rows)
    report(profiles, variants)
    print()
    for filename in outputs:
        print(f"Wrote {args.output_dir / filename}")


if __name__ == "__main__":
    main()
