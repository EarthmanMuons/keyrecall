"""Pass 5: cold-start identifiability and retrieval observability.

Every latent profile starts from the same estimator state. The scheduler then
drives a seven-material pool through repeated sessions while this script records
which choices expose factual retrieval evidence, how quickly memory predictions
separate, and the costs of initially placing a learner too low or too high.

This is characterization only. It does not alter learner or scheduler params.

Outputs (in --output-dir):
    cold_start_profile_summary.csv
    cold_start_seed_summary.csv
    cold_start_trajectories.csv
    cold_start_observability.csv
"""

from __future__ import annotations

import argparse
import concurrent.futures
import copy
import csv
import os
import random
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from statistics import mean
from typing import Any

SCHEDULER_DIR = Path(__file__).resolve().parent.parent / "scheduler"
sys.path.append(str(SCHEDULER_DIR))

from candidates import InstrumentProfile
from config import load_params as load_scheduler_params
from longitudinal import NoAdmittedCandidate, SchedulerAgent
from model import evidence_weights, predicted_success, update
from params import load_params as load_learner_params
from simulate import MATERIALS
from state import LearnerState
from synthetic import PROFILES, TrueLearnerProfile, sample_outcome

ATTEMPTS = 60
SESSION_ATTEMPTS = 20
DAY_STEP = 0.5
EARLY_ATTEMPTS = 20
CALIBRATION_TOLERANCE = 0.10
CALIBRATION_WINDOW = 5
DIVERGENCE_THRESHOLD = 0.15
DEFAULT_SEEDS = 30
DEFAULT_WORKERS = min(8, os.cpu_count() or 1)
MATERIAL_POOL = tuple(MATERIALS[:7])


@dataclass(frozen=True)
class Fixture:
    label: str
    source_profile: str
    memory_prior: float
    current_half_life_days: float


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
)


def build_truth(fixture: Fixture) -> TrueLearnerProfile:
    truth = copy.deepcopy(PROFILES[fixture.source_profile])
    truth.name = fixture.label
    truth.memory_prior = fixture.memory_prior
    truth.default_current_half_life_days = fixture.current_half_life_days
    truth.true_material_memory.clear()
    return truth


def common_estimator_state(learner_params) -> LearnerState:
    state = LearnerState.new(learner_params, now=0.0, competency_prior_mean=0.0)
    for competency in state.competencies.values():
        competency.variance = learner_params.placement.prior_variance_broad
    return state


def true_retrievability(
    truth: TrueLearnerProfile, material_id: str, now: float
) -> float:
    memory = truth.true_material_memory.get(material_id)
    if memory is None:
        return truth.memory_prior
    return memory.retrievability(now, truth.memory_prior)


def guidance_level(exercise) -> str:
    if exercise.guidance.concurrent_pitch_cues:
        return "concurrent_pitch_cues"
    if exercise.guidance.notes_previewed:
        return "notes_previewed"
    return "unguided"


def run_case(fixture: Fixture, seed: int) -> list[dict[str, Any]]:
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    truth = build_truth(fixture)
    state = common_estimator_state(learner_params)
    agent = SchedulerAgent(
        InstrumentProfile(),
        list(MATERIAL_POOL),
        scheduler_params,
        learner_params,
    )
    rng = random.Random(seed)
    rows = []
    now = 0.0
    selection_index = 0

    for attempt_index in range(ATTEMPTS):
        if attempt_index and attempt_index % SESSION_ATTEMPTS == 0:
            agent.new_session()
        now += DAY_STEP
        state.propagate(now, learner_params)

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
                    "guidance_level": "none",
                    "challenge_bypass": "none",
                    "challenge_within_band": "",
                    "retrieval_observed": False,
                    "retrieval_succeeded": "",
                    "predicted_retrieval_p": "",
                    "true_retrieval_p": "",
                    "retrieval_bias": "",
                    "memory_anchor_at": "",
                    "factual_last_retrieval_at": "",
                    "cold_start_estimate": "",
                    "cold_start_uncertainty": "",
                    "current_half_life_days": "",
                    "current_half_life_uncertainty": "",
                    "consolidated_half_life_days": "",
                }
            )
            continue

        selected = agent.records[-1].selected
        assert selected is not None
        material_id = exercise.material.material_id
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
        memory = state.material_memory[material_id]
        rows.append(
            {
                "profile": fixture.label,
                "seed": seed,
                "attempt_index": attempt_index,
                "selection_index": selection_index,
                "at_days": now,
                "selected": True,
                "material_id": material_id,
                "guidance_level": guidance_level(exercise),
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
                "memory_anchor_at": (
                    memory.memory_anchor_at
                    if memory.memory_anchor_at is not None
                    else ""
                ),
                "factual_last_retrieval_at": (
                    memory.factual_last_retrieval_at
                    if memory.factual_last_retrieval_at is not None
                    else ""
                ),
                "cold_start_estimate": memory.cold_start_estimate,
                "cold_start_uncertainty": memory.cold_start_uncertainty,
                "current_half_life_days": memory.current_half_life_days,
                "current_half_life_uncertainty": memory.current_half_life_uncertainty,
                "consolidated_half_life_days": memory.consolidated_half_life_days,
            }
        )
        selection_index += 1

    return rows


def attempts_to_stable_calibration(rows: list[dict[str, Any]]) -> int | None:
    selected = [row for row in rows if row["selected"]]
    for start in range(len(selected) - CALIBRATION_WINDOW + 1):
        window = selected[start : start + CALIBRATION_WINDOW]
        if all(
            abs(float(row["retrieval_bias"])) <= CALIBRATION_TOLERANCE for row in window
        ):
            return int(window[0]["selection_index"]) + 1
    return None


def attempts_to_stable_challenge_band(rows: list[dict[str, Any]]) -> int | None:
    selected = [row for row in rows if row["selected"]]
    for start in range(len(selected) - CALIBRATION_WINDOW + 1):
        window = selected[start : start + CALIBRATION_WINDOW]
        if all(row["challenge_within_band"] for row in window):
            return int(window[0]["selection_index"]) + 1
    return None


def summarize_seed(rows: list[dict[str, Any]]) -> dict[str, Any]:
    selected = [row for row in rows if row["selected"]]
    observed = [row for row in selected if row["retrieval_observed"]]
    successes = [row for row in observed if row["retrieval_succeeded"] is True]
    early = [row for row in selected if int(row["selection_index"]) < EARLY_ATTEMPTS]
    if not selected:
        fixture_row = rows[0]
        return {
            "profile": fixture_row["profile"],
            "seed": fixture_row["seed"],
            "initial_retrieval_bias": None,
            "attempts_to_first_observed_retrieval": None,
            "attempts_to_first_successful_retrieval": None,
            "attempts_to_calibrated_band": None,
            "calibrated_by_end": False,
            "attempts_to_stable_challenge_band": None,
            "stable_challenge_band_by_end": False,
            "early_retrieval_observation_fraction": None,
            "early_recovery_fraction": None,
            "early_concurrent_cue_fraction": None,
            "early_unnecessary_cueing_count": 0,
            "early_unguided_low_memory_count": 0,
            "final_retrieval_bias": None,
            "final_retrieval_mae": None,
            "final_cold_start_uncertainty": None,
            "final_current_half_life_uncertainty": None,
            "no_admission_count": len(rows),
        }

    tail = selected[-10:]
    first = selected[0]
    calibrated_at = attempts_to_stable_calibration(rows)
    challenge_band_at = attempts_to_stable_challenge_band(rows)

    return {
        "profile": first["profile"],
        "seed": first["seed"],
        "initial_retrieval_bias": first["retrieval_bias"],
        "attempts_to_first_observed_retrieval": (
            int(observed[0]["selection_index"]) + 1 if observed else None
        ),
        "attempts_to_first_successful_retrieval": (
            int(successes[0]["selection_index"]) + 1 if successes else None
        ),
        "attempts_to_calibrated_band": calibrated_at,
        "calibrated_by_end": calibrated_at is not None,
        "attempts_to_stable_challenge_band": challenge_band_at,
        "stable_challenge_band_by_end": challenge_band_at is not None,
        "early_retrieval_observation_fraction": mean(
            1.0 if row["retrieval_observed"] else 0.0 for row in early
        ),
        "early_recovery_fraction": mean(
            1.0 if row["challenge_bypass"] == "recovery" else 0.0 for row in early
        ),
        "early_concurrent_cue_fraction": mean(
            1.0 if row["guidance_level"] == "concurrent_pitch_cues" else 0.0
            for row in early
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
        "final_retrieval_bias": mean(float(row["retrieval_bias"]) for row in tail),
        "final_retrieval_mae": mean(abs(float(row["retrieval_bias"])) for row in tail),
        "final_cold_start_uncertainty": mean(
            float(row["cold_start_uncertainty"]) for row in tail
        ),
        "final_current_half_life_uncertainty": mean(
            float(row["current_half_life_uncertainty"]) for row in tail
        ),
        "no_admission_count": sum(1 for row in rows if not row["selected"]),
    }


def mean_optional(rows: list[dict[str, Any]], field: str) -> float | None:
    values = [float(row[field]) for row in rows if row[field] is not None]
    return mean(values) if values else None


def attempts_to_profile_divergence(
    trajectories: list[dict[str, Any]], profile: str
) -> int | None:
    grouped: dict[tuple[str, int], list[float]] = defaultdict(list)
    for row in trajectories:
        if row["selected"]:
            grouped[(row["profile"], int(row["selection_index"]))].append(
                float(row["predicted_retrieval_p"])
            )
    beginner_means = {
        attempt: mean(values)
        for (label, attempt), values in grouped.items()
        if label == "beginner"
    }
    profile_means = {
        attempt: mean(values)
        for (label, attempt), values in grouped.items()
        if label == profile
    }
    for start in range(ATTEMPTS - CALIBRATION_WINDOW + 1):
        window = range(start, start + CALIBRATION_WINDOW)
        if all(
            attempt in beginner_means
            and attempt in profile_means
            and abs(profile_means[attempt] - beginner_means[attempt])
            >= DIVERGENCE_THRESHOLD
            for attempt in window
        ):
            return window[0] + 1
    return None


def profile_summary_rows(
    seed_rows: list[dict[str, Any]], trajectories: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    rows = []
    for fixture in FIXTURES:
        profile_rows = [row for row in seed_rows if row["profile"] == fixture.label]
        rows.append(
            {
                "profile": fixture.label,
                "initial_retrieval_bias": mean_optional(
                    profile_rows, "initial_retrieval_bias"
                ),
                "attempts_to_first_observed_retrieval": mean_optional(
                    profile_rows, "attempts_to_first_observed_retrieval"
                ),
                "attempts_to_first_successful_retrieval": mean_optional(
                    profile_rows, "attempts_to_first_successful_retrieval"
                ),
                "attempts_to_calibrated_band": mean_optional(
                    profile_rows, "attempts_to_calibrated_band"
                ),
                "calibrated_by_end_fraction": mean(
                    1.0 if row["calibrated_by_end"] else 0.0 for row in profile_rows
                ),
                "attempts_to_stable_challenge_band": mean_optional(
                    profile_rows, "attempts_to_stable_challenge_band"
                ),
                "stable_challenge_band_by_end_fraction": mean(
                    1.0 if row["stable_challenge_band_by_end"] else 0.0
                    for row in profile_rows
                ),
                "attempts_to_diverge_from_beginner": (
                    0
                    if fixture.label == "beginner"
                    else attempts_to_profile_divergence(trajectories, fixture.label)
                ),
                "early_retrieval_observation_fraction": mean_optional(
                    profile_rows, "early_retrieval_observation_fraction"
                ),
                "early_recovery_fraction": mean_optional(
                    profile_rows, "early_recovery_fraction"
                ),
                "early_concurrent_cue_fraction": mean_optional(
                    profile_rows, "early_concurrent_cue_fraction"
                ),
                "early_unnecessary_cueing_count": mean_optional(
                    profile_rows, "early_unnecessary_cueing_count"
                ),
                "early_unguided_low_memory_count": mean_optional(
                    profile_rows, "early_unguided_low_memory_count"
                ),
                "final_retrieval_bias": mean_optional(
                    profile_rows, "final_retrieval_bias"
                ),
                "final_retrieval_mae": mean_optional(
                    profile_rows, "final_retrieval_mae"
                ),
                "final_cold_start_uncertainty": mean_optional(
                    profile_rows, "final_cold_start_uncertainty"
                ),
                "final_current_half_life_uncertainty": mean_optional(
                    profile_rows, "final_current_half_life_uncertainty"
                ),
                "no_admission_count": mean_optional(profile_rows, "no_admission_count"),
            }
        )
    return rows


def observability_rows(trajectories: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, int, str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in trajectories:
        if not row["selected"]:
            continue
        selection_index = int(row["selection_index"])
        window_start = (selection_index // 5) * 5 + 1
        keys = (
            (row["profile"], window_start, "ALL", "ALL"),
            (
                row["profile"],
                window_start,
                row["guidance_level"],
                row["challenge_bypass"],
            ),
        )
        for key in keys:
            grouped[key].append(row)

    rows = []
    for (profile, window_start, guidance, bypass), group in sorted(grouped.items()):
        observed = sum(1 for row in group if row["retrieval_observed"])
        successes = sum(1 for row in group if row["retrieval_succeeded"] is True)
        rows.append(
            {
                "profile": profile,
                "selection_window": f"{window_start}-{window_start + 4}",
                "guidance_level": guidance,
                "challenge_bypass": bypass,
                "probe_type": (
                    bypass
                    if bypass in {"bootstrap_probe", "guidance_probe"}
                    else "none"
                ),
                "selection_count": len(group),
                "retrieval_observation_count": observed,
                "retrieval_observation_fraction": observed / len(group),
                "retrieval_success_count": successes,
                "retrieval_success_fraction_when_observed": (
                    successes / observed if observed else None
                ),
            }
        )
    return rows


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("")
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def check_contracts(trajectories: list[dict[str, Any]], learner_params) -> None:
    """Protect the experiment from fixture and censoring drift."""
    reference = common_estimator_state(learner_params)
    for material in MATERIAL_POOL:
        reference.material_memory_for(material.material_id, learner_params)
    for fixture in FIXTURES:
        candidate = common_estimator_state(learner_params)
        for material in MATERIAL_POOL:
            candidate.material_memory_for(material.material_id, learner_params)
        if candidate != reference:
            raise AssertionError(
                f"{fixture.label}: estimator initialization differs across fixtures"
            )

    for row in trajectories:
        if not row["selected"]:
            continue
        expected_observed = row["guidance_level"] != "concurrent_pitch_cues"
        if row["retrieval_observed"] is not expected_observed:
            raise AssertionError(
                "retrieval observability no longer matches the guidance contract: "
                f"{row['profile']} seed={row['seed']} "
                f"attempt={row['attempt_index']}"
            )


def display_optional(value: Any, digits: int = 2) -> str:
    return "n/a" if value is None else f"{float(value):.{digits}f}"


def report(summary: list[dict[str, Any]], observability: list[dict[str, Any]]) -> None:
    print("Cold-start profile identification (means across seeds):")
    print(
        "  profile                           initial_bias first_obs calibrated "
        "challenge early_cued final_bias"
    )
    for row in summary:
        print(
            f"  {row['profile']:<33} "
            f"{display_optional(row['initial_retrieval_bias']):>12} "
            f"{display_optional(row['attempts_to_first_observed_retrieval']):>9} "
            f"{display_optional(row['attempts_to_calibrated_band']):>10} "
            f"{display_optional(row['attempts_to_stable_challenge_band']):>9} "
            f"{display_optional(row['early_unnecessary_cueing_count']):>10} "
            f"{display_optional(row['final_retrieval_bias']):>10}"
        )
    print()

    print("Retrieval observability by early five-selection window:")
    for row in observability:
        if (
            row["guidance_level"] != "ALL"
            or int(row["selection_window"].split("-")[0]) > 20
        ):
            continue
        print(
            f"  {row['profile']:<33} {row['selection_window']:<5} "
            f"observed={row['retrieval_observation_fraction']:.1%} "
            f"n={row['selection_count']}"
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
    cases = [(fixture, seed) for fixture in FIXTURES for seed in range(args.seeds)]

    if args.workers == 1:
        case_rows = [run_case(*case) for case in cases]
    else:
        with concurrent.futures.ProcessPoolExecutor(args.workers) as executor:
            fixtures, seeds = zip(*cases, strict=True)
            case_rows = list(executor.map(run_case, fixtures, seeds))

    trajectories = [row for rows in case_rows for row in rows]
    seed_summary = [summarize_seed(rows) for rows in case_rows]
    summary = profile_summary_rows(seed_summary, trajectories)
    observability = observability_rows(trajectories)
    check_contracts(trajectories, load_learner_params())

    outputs = {
        "cold_start_profile_summary.csv": summary,
        "cold_start_seed_summary.csv": seed_summary,
        "cold_start_trajectories.csv": trajectories,
        "cold_start_observability.csv": observability,
    }
    for filename, rows in outputs.items():
        write_csv(args.output_dir / filename, rows)
    report(summary, observability)
    print()
    for filename in outputs:
        print(f"Wrote {args.output_dir / filename}")


if __name__ == "__main__":
    main()
