#!/usr/bin/env python3
"""Behavioral diagnostics for the learner-model prototype.

The invariant suite (invariants.py) answers "does the model violate
architectural rules?". This script answers a different question: "what
does the model actually do over months of synthetic practice, and which
heuristic parameters actually matter?" It runs simulate.run() under
scripted scenarios, derives summary CSVs from the resulting traces, and
prints a short report. No pass/fail assertions here; the CSVs are for
human inspection.

Outputs (in --output-dir):
    calibration.csv            predicted_p vs. observed outcome, bucketed
    competency_convergence.csv estimated competency mean vs. true value over time
    memory_tracking.csv        estimated vs. true retrievability for one material
    residual_localization.csv  material-specific residual trajectory (vs. control)
    uncertainty_behavior.csv   competency variance across practice/idle/practice
    hand_transfer.csv          borrowed vs. stored LH mean across RH-only/LH-only phases
    reacquisition.csv          predicted_p/pitch trajectory, returning vs. beginner
    guidance_sensitivity.csv   predicted_p and evidence weights across guidance levels
    parameter_sensitivity.csv  0.5x/1x/2x sweep over named heuristic parameters

Usage:
    python analyze.py
    python analyze.py --output-dir generated
"""

from __future__ import annotations

import argparse
import copy
import csv
import dataclasses
import math
import random
from collections.abc import Callable
from pathlib import Path
from typing import Any

from domain import GuidanceContext, TechnicalMaterial
from model import (
    Outcome,
    effective_competency_mean,
    evidence_weights,
    predicted_success,
    update,
)
from params import Params, load_params
from simulate import fixed_exercise, initial_state, run
from state import LearnerState
from synthetic import PROFILES, TrueMaterialMemory, sample_outcome

C_MAJOR = TechnicalMaterial("C", "MAJOR")
D_HARMONIC_MINOR = TechnicalMaterial("D", "HARMONIC_MINOR")
F_SHARP_HARMONIC_MINOR = TechnicalMaterial("F#", "HARMONIC_MINOR")

FULL_OUTCOME = Outcome(
    started=True,
    retrieval_succeeded=True,
    completed=True,
    material_retrieval=1.0,
    pitch_integrity=1.0,
    continuity=1.0,
    temporal_stability=1.0,
    achieved_tempo_ratio=1.0,
    topology_accuracy=1.0,
)

GUIDANCE_LEVELS = {
    "unguided": GuidanceContext(),
    "notes_previewed": GuidanceContext(notes_previewed=True),
    "concurrent_pitch_cues": GuidanceContext(concurrent_pitch_cues=True),
}

CONVERGENCE_PROFILES = (
    "beginner",
    "advanced",
    "rh_strong_lh_weak",
    "technique_strong_memory_weak",
    "memory_strong_technique_weak",
)


def _scale_value(base: float, factor: float) -> float:
    return base * factor


def _scale_distance_from_one(base: float, factor: float) -> float:
    """For growth/shrink multipliers whose neutral value is 1, not 0
    (03-v1-math.md §25: success_growth > 1, 0 < failure_shrink < 1).
    Scaling the raw value can cross that boundary (e.g. success_growth
    0.5x would drop below 1 and start shrinking on success); scaling the
    distance from 1 keeps every factor on the same side of it."""
    return 1 + factor * (base - 1)


# (params.toml section, field, value transform). Most parameters have no
# semantic boundary at a nonzero value, so raw multiplication is fine; the
# growth/shrink pair needs _scale_distance_from_one instead.
SWEEP_PARAMETERS: list[tuple[str, str, Callable[[float, float], float]]] = [
    ("competency", "learning_rate", _scale_value),
    ("competency", "uncertainty_diffusion", _scale_value),
    ("competency", "evidence_shrinkage", _scale_value),
    ("material_memory", "success_growth", _scale_distance_from_one),
    ("material_memory", "failure_shrink", _scale_distance_from_one),
    ("material_execution", "learning_rate", _scale_value),
    ("material_execution", "mean_reversion_tau_days", _scale_value),
    ("hand_transfer", "rho_hand", _scale_value),
]
SWEEP_FACTORS = (0.5, 1.0, 2.0)

# Which of sweep_metric()'s bundle a parameter's classification should be
# judged on. final_competency_error is computed from a random-exercise run
# spanning every layer, so it moves for competency parameters but is only
# weakly coupled to e.g. memory or hand-transfer parameters; judging every
# parameter against it would let those look falsely "robust" just because
# the wrong metric was watched.
RELEVANT_METRICS: dict[tuple[str, str], tuple[str, ...]] = {
    ("competency", "learning_rate"): ("final_competency_error",),
    ("competency", "uncertainty_diffusion"): ("final_competency_error",),
    ("competency", "evidence_shrinkage"): ("final_competency_error",),
    ("material_memory", "success_growth"): ("memory_retrievability_error",),
    ("material_memory", "failure_shrink"): ("memory_retrievability_error",),
    ("material_execution", "learning_rate"): ("residual_localization_gap",),
    ("material_execution", "mean_reversion_tau_days"): ("residual_localization_gap",),
    ("hand_transfer", "rho_hand"): ("hand_transfer_effect",),
}


def observed_success(outcome: dict[str, Any]) -> float:
    """The same quantity model.update() treats as ground truth per attempt."""
    return (
        outcome["pitch_integrity"]
        + outcome["continuity"]
        + outcome["temporal_stability"]
    ) / 3.0


def rh_only(_rng: random.Random, _i: int) -> Any:
    return fixed_exercise(C_MAJOR, "RIGHT")


def lh_only(_rng: random.Random, _i: int) -> Any:
    return fixed_exercise(C_MAJOR, "LEFT")


def calibration_rows(
    params: Params, attempts: int = 500, seed: int = 0
) -> list[dict[str, Any]]:
    trace, _state, _truth = run("advanced", attempts=attempts, seed=seed, params=params)
    buckets: dict[int, list[tuple[float, float, bool]]] = {i: [] for i in range(10)}
    for record in trace:
        p = record["predicted_p"]
        bucket = min(9, int(p * 10))
        buckets[bucket].append(
            (p, observed_success(record["outcome"]), record["outcome"]["started"])
        )

    rows = []
    for bucket, entries in buckets.items():
        if not entries:
            continue
        n = len(entries)
        rows.append(
            {
                "bucket_low": bucket / 10,
                "bucket_high": (bucket + 1) / 10,
                "n": n,
                "mean_predicted_p": sum(p for p, _, _ in entries) / n,
                "mean_observed_success": sum(a for _, a, _ in entries) / n,
                "started_fraction": sum(1 for _, _, s in entries if s) / n,
            }
        )
    return rows


def competency_convergence_rows(
    params: Params, attempts: int = 300, checkpoint_every: int = 20, seed: int = 0
) -> list[dict[str, Any]]:
    """initial_abs_error/error_reduction distinguish "large error because the
    placement prior started far away" from "model failed to learn despite
    evidence": a profile with a bad prior and a profile that isn't learning
    can land on the same abs_error, but not the same error_reduction."""
    rows = []
    for profile_name in CONVERGENCE_PROFILES:
        trace, _state, truth = run(
            profile_name, attempts=attempts, seed=seed, params=params
        )
        initial = trace[0]["state_before"]["competencies"]
        initial_abs_error = {
            competency_id: abs(values["mean"] - truth.true_competencies[competency_id])
            for competency_id, values in initial.items()
        }
        for checkpoint_index in range(checkpoint_every - 1, attempts, checkpoint_every):
            snapshot = trace[checkpoint_index]["state_after"]["competencies"]
            for competency_id, values in snapshot.items():
                true_value = truth.true_competencies[competency_id]
                abs_error = abs(values["mean"] - true_value)
                rows.append(
                    {
                        "profile": profile_name,
                        "attempt_index": checkpoint_index + 1,
                        "competency_id": competency_id,
                        "mean": values["mean"],
                        "variance": values["variance"],
                        "true_value": true_value,
                        "abs_error": abs_error,
                        "initial_abs_error": initial_abs_error[competency_id],
                        "error_reduction": initial_abs_error[competency_id] - abs_error,
                    }
                )
    return rows


def memory_tracking_rows(
    params: Params, attempts: int = 60, seed: int = 0, day_step: float = 2.0
) -> list[dict[str, Any]]:
    """Estimated vs. true retrievability for one material under repeated
    practice. Steps the loop directly rather than using simulate.run():
    true_material_memory is hidden ground truth simulate.run()'s trace
    intentionally doesn't expose, and this needs its per-attempt value.

    Records *_before alongside *_after: a successful retrieval resets both
    clocks at `now`, so the after-values look artificially well-aligned
    regardless of model quality. The before-values are what actually
    generated the retrieval probability and what predicted_success() saw;
    calibration/sensitivity metrics should use those, not the after-values.
    """
    profile = copy.deepcopy(PROFILES["beginner"])
    # Pre-seed so a before-reading is defined on the very first attempt too,
    # mirroring synthetic._true_memory_for()'s lazy-init default.
    profile.true_material_memory["C_MAJOR"] = TrueMaterialMemory(
        half_life_days=profile.default_half_life_days
    )
    rng = random.Random(seed)
    state = LearnerState.new(params)
    exercise = fixed_exercise(C_MAJOR, "RIGHT")
    true_memory = profile.true_material_memory["C_MAJOR"]
    now = 0.0
    rows = []

    for i in range(attempts):
        now += day_step
        state.propagate(now, params)

        # Mirrors predicted_success()'s own fallback: no MaterialMemoryState
        # exists until the first update() call creates one.
        memory_before = state.material_memory.get("C_MAJOR")
        model_retrievability_before = (
            memory_before.retrievability_or_prior(now, params)
            if memory_before is not None
            else params.material_memory.prior_retrievability
        )
        true_retrievability_before = true_memory.retrievability(
            now, profile.memory_prior
        )

        prediction = predicted_success(state, exercise, now, params)
        outcome = sample_outcome(profile, exercise, now, rng)
        weights = evidence_weights(exercise, outcome)
        update(state, exercise, outcome, weights, prediction, now, params)

        memory_after = state.material_memory["C_MAJOR"]
        rows.append(
            {
                "attempt_index": i,
                "at_days": now,
                "model_retrievability_before": model_retrievability_before,
                "true_retrievability_before": true_retrievability_before,
                "model_retrievability_after": memory_after.retrievability_or_prior(
                    now, params
                ),
                "true_retrievability_after": true_memory.retrievability(
                    now, profile.memory_prior
                ),
                "half_life_days": memory_after.half_life_days,
                "retrieval_succeeded": outcome.retrieval_succeeded,
            }
        )
    return rows


def residual_localization_rows(
    params: Params, attempts: int = 120, seed: int = 4
) -> list[dict[str, Any]]:
    def alternating(_rng: random.Random, i: int) -> Any:
        material = F_SHARP_HARMONIC_MINOR if i % 2 == 0 else D_HARMONIC_MINOR
        return fixed_exercise(material, "RIGHT")

    rows = []
    for condition, profile_name in (
        ("control", "advanced"),
        ("treatment", "material_specific_difficulty"),
    ):
        trace, _state, _truth = run(
            profile_name,
            attempts=attempts,
            seed=seed,
            params=params,
            exercise_fn=alternating,
        )
        for record in trace:
            execution = record["state_after"]["material_execution"]
            f_sharp = execution.get("F#_HARMONIC_MINOR/RIGHT", {}).get("residual_mean")
            d = execution.get("D_HARMONIC_MINOR/RIGHT", {}).get("residual_mean")
            if f_sharp is None or d is None:
                continue
            rows.append(
                {
                    "condition": condition,
                    "attempt_index": record["attempt_index"],
                    "f_sharp_residual": f_sharp,
                    "d_residual": d,
                    "gap": f_sharp - d,
                }
            )
    return rows


def uncertainty_behavior_rows(
    params: Params, practice_attempts: int = 30, idle_days: float = 180.0, seed: int = 6
) -> list[dict[str, Any]]:
    rows = []
    state = initial_state(PROFILES["advanced"], params)

    trace, state, truth = run(
        "advanced",
        attempts=practice_attempts,
        seed=seed,
        params=params,
        exercise_fn=rh_only,
        state=state,
    )
    for record in trace:
        rows.append(
            {
                "phase": "practice_1",
                "attempt_index": record["attempt_index"],
                "at_days": record["at_days"],
                "variance": record["state_after"]["competencies"]["RH_SCALE_EXECUTION"][
                    "variance"
                ],
            }
        )
    now = trace[-1]["at_days"]

    now += idle_days
    state.propagate(now, params)
    rows.append(
        {
            "phase": "idle",
            "attempt_index": None,
            "at_days": now,
            "variance": state.competencies["RH_SCALE_EXECUTION"].variance,
        }
    )

    trace2, state, _truth2 = run(
        "advanced",
        attempts=practice_attempts,
        seed=seed + 1,
        params=params,
        exercise_fn=rh_only,
        state=state,
        truth=truth,
        start_now=now,
    )
    for record in trace2:
        rows.append(
            {
                "phase": "practice_2",
                "attempt_index": record["attempt_index"],
                "at_days": record["at_days"],
                "variance": record["state_after"]["competencies"]["RH_SCALE_EXECUTION"][
                    "variance"
                ],
            }
        )
    return rows


def hand_transfer_rows(
    params: Params, phase_attempts: int = 60, chunk: int = 10, seed: int = 2
) -> list[dict[str, Any]]:
    lh_probe = fixed_exercise(C_MAJOR, "LEFT")
    rows = []
    state = initial_state(PROFILES["advanced"], params)
    now = 0.0
    truth = None
    attempt_index = 0

    def record(phase: str) -> None:
        rows.append(
            {
                "phase": phase,
                "attempt_index": attempt_index,
                "at_days": now,
                "stored_lh_mean": state.competencies["LH_SCALE_EXECUTION"].mean,
                "effective_lh_mean": effective_competency_mean(
                    state, "LH_SCALE_EXECUTION", params
                ),
                # execution_p, not overall_p: transfer acts on the competency
                # mean, which only enters the execution stage now.
                "predicted_lh_execution_p": predicted_success(
                    state, lh_probe, now, params
                ).execution_p,
            }
        )

    # One rng per phase, threaded across that phase's chunks: run() would
    # otherwise reseed from `seed` every chunk and replay the same draws.
    record("rh_only")
    rh_rng = random.Random(seed)
    for _ in range(phase_attempts // chunk):
        trace, state, truth = run(
            "advanced",
            attempts=chunk,
            seed=seed,
            params=params,
            exercise_fn=rh_only,
            state=state,
            truth=truth,
            start_now=now,
            rng=rh_rng,
        )
        now = trace[-1]["at_days"]
        attempt_index += chunk
        record("rh_only")

    lh_rng = random.Random(seed + 1)
    for _ in range(phase_attempts // chunk):
        trace, state, truth = run(
            "advanced",
            attempts=chunk,
            seed=seed + 1,
            params=params,
            exercise_fn=lh_only,
            state=state,
            truth=truth,
            start_now=now,
            rng=lh_rng,
        )
        now = trace[-1]["at_days"]
        attempt_index += chunk
        record("lh_only")

    return rows


def reacquisition_rows(
    params: Params, attempts: int = 30, seed: int = 5
) -> list[dict[str, Any]]:
    rows = []
    for profile_name in ("returning", "beginner"):
        trace, _state, _truth = run(
            profile_name,
            attempts=attempts,
            seed=seed,
            params=params,
            exercise_fn=rh_only,
        )
        for record in trace:
            rows.append(
                {
                    "profile": profile_name,
                    "attempt_index": record["attempt_index"],
                    "predicted_p": record["predicted_p"],
                    "started": record["outcome"]["started"],
                    "pitch_integrity": record["outcome"]["pitch_integrity"],
                }
            )
    return rows


def guidance_sensitivity_rows(params: Params) -> list[dict[str, Any]]:
    """predicted_independent_retrieval_p and predicted_execution_p should be
    identical across every guidance level: that's the hurdle split actually
    holding (see the "guidance affects material availability, not
    retrieval or execution" invariant). Only predicted_material_available_p,
    and therefore predicted_p, should move."""
    state = initial_state(PROFILES["advanced"], params)
    rows = []
    for level, guidance in GUIDANCE_LEVELS.items():
        exercise = fixed_exercise(C_MAJOR, "RIGHT", guidance=guidance)
        prediction = predicted_success(state, exercise, now=1.0, params=params)
        weights = evidence_weights(exercise, FULL_OUTCOME)
        rows.append(
            {
                "guidance_level": level,
                "predicted_independent_retrieval_p": prediction.independent_retrieval_p,
                "predicted_material_available_p": prediction.material_available_p,
                "predicted_execution_p": prediction.execution_p,
                "predicted_p": prediction.overall_p,
                "memory_weight": weights.material_memory,
                "topology_weight": weights.competencies["MAJOR_SCALE_TOPOLOGY"],
                "motor_weight": weights.competencies["RH_SCALE_EXECUTION"],
            }
        )
    return rows


def scaled_params(
    params: Params,
    section: str,
    field_name: str,
    factor: float,
    transform: Callable[[float, float], float],
) -> Params:
    section_obj = getattr(params, section)
    scaled_value = transform(getattr(section_obj, field_name), factor)
    new_section = dataclasses.replace(section_obj, **{field_name: scaled_value})
    return dataclasses.replace(params, **{section: new_section})


def memory_retrievability_error_metric(
    params: Params, attempts: int = 40, seed: int = 0
) -> float:
    """Mean pre-attempt |model - true| retrievability gap (see
    memory_tracking_rows()'s *_before fields)."""
    rows = memory_tracking_rows(params, attempts=attempts, seed=seed)
    gaps = [
        abs(row["model_retrievability_before"] - row["true_retrievability_before"])
        for row in rows
    ]
    return sum(gaps) / len(gaps)


def residual_localization_gap_metric(
    params: Params, attempts: int = 80, seed: int = 4
) -> float:
    """Mean |F#-vs-D residual gap| over the treatment profile's last 10
    attempts. Not compared to a ground-truth value: the deliberately
    mismatched estimator/generator (see synthetic.py) means there's no
    "correct" residual to recover, only whether a persistent material-
    specific offset is being localized at all, and how strongly."""
    rows = residual_localization_rows(params, attempts=attempts, seed=seed)
    treatment_gaps = [row["gap"] for row in rows if row["condition"] == "treatment"]
    tail = treatment_gaps[-10:]
    return abs(sum(tail) / len(tail))


def hand_transfer_effect_metric(
    params: Params, phase_attempts: int = 40, chunk: int = 10, seed: int = 2
) -> float:
    """Correlated-transfer boost at the end of RH-only practice: how far
    effective_lh_mean (used for prediction) has pulled ahead of
    stored_lh_mean (never directly updated by RH evidence)."""
    rows = hand_transfer_rows(
        params, phase_attempts=phase_attempts, chunk=chunk, seed=seed
    )
    rh_only_rows = [row for row in rows if row["phase"] == "rh_only"]
    last = rh_only_rows[-1]
    return last["effective_lh_mean"] - last["stored_lh_mean"]


def sweep_metric(params: Params, attempts: int = 150, seed: int = 0) -> dict[str, Any]:
    """One scenario per layer, summarized into a metric bundle. bounds_ok
    catches outright breakage anywhere in the bundle (a raised exception or
    non-finite value from any sub-metric also counts); the rest are
    magnitudes a sensitive parameter should visibly move, scoped to the
    layer it actually governs (see RELEVANT_METRICS)."""
    trace, state, truth = run("advanced", attempts=attempts, seed=seed, params=params)

    bounds_ok = all(
        0.0 <= record["predicted_p"] <= 1.0
        and 0.0 <= record["predicted_independent_retrieval_p"] <= 1.0
        and 0.0 <= record["predicted_material_available_p"] <= 1.0
        and 0.0 <= record["predicted_execution_p"] <= 1.0
        and 0.0 <= record["predicted_topology_p"] <= 1.0
        and all(
            0.0 <= w <= 1.0 for w in record["evidence_weights"]["competencies"].values()
        )
        and all(
            c["variance"] > 0 for c in record["state_after"]["competencies"].values()
        )
        and all(
            m["half_life_days"] > 0 and m["uncertainty"] > 0
            for m in record["state_after"]["material_memory"].values()
        )
        for record in trace
    )

    final_competency_error = sum(
        abs(c.mean - truth.true_competencies[cid])
        for cid, c in state.competencies.items()
    ) / len(state.competencies)

    prediction_alignment_error = sum(
        abs(record["predicted_p"] - observed_success(record["outcome"]))
        for record in trace
    ) / len(trace)

    metrics: dict[str, Any] = {
        "bounds_ok": bounds_ok,
        "final_competency_error": final_competency_error,
        "prediction_alignment_error": prediction_alignment_error,
    }

    for name, compute in (
        (
            "memory_retrievability_error",
            lambda: memory_retrievability_error_metric(params),
        ),
        ("residual_localization_gap", lambda: residual_localization_gap_metric(params)),
        ("hand_transfer_effect", lambda: hand_transfer_effect_metric(params)),
    ):
        try:
            value = compute()
            if not math.isfinite(value):
                raise ValueError(f"{name} not finite: {value}")
        except Exception:  # noqa: BLE001 - non-finite/crashed is itself bounds_ok=False
            metrics["bounds_ok"] = False
            value = None
        metrics[name] = value

    return metrics


def classify_sensitivity(
    metrics_by_factor: dict[float, dict[str, Any]], relevant_metrics: tuple[str, ...]
) -> tuple[str, str]:
    """Heuristic classification for a human to sanity-check, not a strict
    test: out-of-bounds anywhere in the sweep is structurally_unstable;
    otherwise a >50% relative swing in any of this parameter's relevant
    metrics (not a single fixed metric for every parameter) is sensitive,
    else robust. Returns (classification, triggering_metric) so the CSV
    records which metric the call was actually based on."""
    if any(not m["bounds_ok"] for m in metrics_by_factor.values()):
        return "structurally_unstable", ""

    triggering_metric = ""
    largest_relative_spread = 0.0
    for metric_name in relevant_metrics:
        values = [m[metric_name] for m in metrics_by_factor.values()]
        baseline = metrics_by_factor[1.0][metric_name]
        spread = max(values) - min(values)
        relative_spread = spread / abs(baseline) if baseline else spread
        if relative_spread > largest_relative_spread:
            largest_relative_spread = relative_spread
            triggering_metric = metric_name

    classification = "sensitive" if largest_relative_spread > 0.5 else "robust"
    return classification, triggering_metric


METRIC_FIELDS = (
    "final_competency_error",
    "prediction_alignment_error",
    "memory_retrievability_error",
    "residual_localization_gap",
    "hand_transfer_effect",
)


def parameter_sensitivity_rows(params: Params) -> list[dict[str, Any]]:
    rows = []
    for section, field_name, transform in SWEEP_PARAMETERS:
        label = f"{section}.{field_name}"
        relevant_metrics = RELEVANT_METRICS[(section, field_name)]
        metrics_by_factor: dict[float, dict[str, Any]] = {}

        for factor in SWEEP_FACTORS:
            swept_params = scaled_params(params, section, field_name, factor, transform)
            try:
                metrics = sweep_metric(swept_params)
                error = ""
            except Exception as exc:  # noqa: BLE001 - a crash is itself a finding
                metrics = {"bounds_ok": False, **dict.fromkeys(METRIC_FIELDS)}
                error = repr(exc)
            metrics_by_factor[factor] = metrics
            rows.append(
                {
                    "parameter": label,
                    "factor": factor,
                    "value": getattr(getattr(swept_params, section), field_name),
                    "bounds_ok": metrics["bounds_ok"],
                    **{field: metrics[field] for field in METRIC_FIELDS},
                    "relevant_metrics": ",".join(relevant_metrics),
                    "error": error,
                }
            )

        classification, triggering_metric = classify_sensitivity(
            metrics_by_factor, relevant_metrics
        )
        for row in rows[-len(SWEEP_FACTORS) :]:
            row["classification"] = classification
            row["triggering_metric"] = triggering_metric

    return rows


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def report(
    calibration: list[dict[str, Any]],
    convergence: list[dict[str, Any]],
    memory: list[dict[str, Any]],
    residual: list[dict[str, Any]],
    uncertainty: list[dict[str, Any]],
    hand_transfer: list[dict[str, Any]],
    reacquisition: list[dict[str, Any]],
    guidance: list[dict[str, Any]],
    sensitivity: list[dict[str, Any]],
) -> None:
    print("Calibration (predicted_p vs. observed success, by bucket):")
    for row in calibration:
        print(
            f"  [{row['bucket_low']:.1f},{row['bucket_high']:.1f}) n={row['n']:<4} "
            f"predicted={row['mean_predicted_p']:.3f} observed={row['mean_observed_success']:.3f}"
        )
    print()

    print(
        "Competency convergence, final abs error (initial error, proportion corrected):"
    )
    final_attempt = max(row["attempt_index"] for row in convergence)
    for profile_name in CONVERGENCE_PROFILES:
        final_rows = [
            row
            for row in convergence
            if row["profile"] == profile_name and row["attempt_index"] == final_attempt
        ]
        mean_abs_error = sum(row["abs_error"] for row in final_rows) / len(final_rows)
        mean_initial = sum(row["initial_abs_error"] for row in final_rows) / len(
            final_rows
        )
        proportion_corrected = (
            (mean_initial - mean_abs_error) / mean_initial if mean_initial else 0.0
        )
        print(
            f"  {profile_name}: {mean_abs_error:.3f} "
            f"(initial {mean_initial:.3f}, corrected {proportion_corrected:.0%})"
        )
    print()

    gaps = [
        abs(row["model_retrievability_before"] - row["true_retrievability_before"])
        for row in memory
    ]
    print(
        f"Memory tracking: mean pre-attempt model-vs-true retrievability gap "
        f"{sum(gaps) / len(gaps):.3f} (peak {max(gaps):.3f}); first/last "
        f"{gaps[0]:.3f}/{gaps[-1]:.3f} can understate divergence because both "
        f"retrievability estimates may approach 0 late in the run"
    )
    print()

    control_gaps = [row["gap"] for row in residual if row["condition"] == "control"]
    treatment_gaps = [row["gap"] for row in residual if row["condition"] == "treatment"]
    print(
        f"Residual localization, mean F#-vs-D gap: "
        f"control={sum(control_gaps) / len(control_gaps):.3f} "
        f"treatment={sum(treatment_gaps) / len(treatment_gaps):.3f}"
    )
    print()

    def variance_at(phase: str, first: bool) -> float:
        matches = [row["variance"] for row in uncertainty if row["phase"] == phase]
        return matches[0] if first else matches[-1]

    print(
        "Uncertainty: practice_1 "
        f"{variance_at('practice_1', True):.3f} -> {variance_at('practice_1', False):.3f}, "
        f"idle -> {variance_at('idle', False):.3f}, "
        f"practice_2 -> {variance_at('practice_2', False):.3f}"
    )
    print()

    rh_end = [row for row in hand_transfer if row["phase"] == "rh_only"][-1]
    lh_end = [row for row in hand_transfer if row["phase"] == "lh_only"][-1]
    print(
        "Hand transfer: after RH-only, effective LH mean "
        f"{rh_end['effective_lh_mean']:.3f} vs. stored {rh_end['stored_lh_mean']:.3f}; "
        f"after LH-only, effective {lh_end['effective_lh_mean']:.3f} vs. stored "
        f"{lh_end['stored_lh_mean']:.3f}"
    )
    print()

    print("Reacquisition, mean predicted_p over first 10 attempts:")
    for profile_name in ("returning", "beginner"):
        first_ten = [
            row["predicted_p"]
            for row in reacquisition
            if row["profile"] == profile_name and row["attempt_index"] < 10
        ]
        print(f"  {profile_name}: {sum(first_ten) / len(first_ten):.3f}")
    print()

    print(
        "Guidance sensitivity (independent_retrieval_p and execution_p should "
        "be constant across levels):"
    )
    for row in guidance:
        print(
            f"  {row['guidance_level']:<22} "
            f"independent_retrieval_p={row['predicted_independent_retrieval_p']:.3f} "
            f"material_available_p={row['predicted_material_available_p']:.3f} "
            f"execution_p={row['predicted_execution_p']:.3f} "
            f"overall_p={row['predicted_p']:.3f} memory_w={row['memory_weight']:.3f} "
            f"topology_w={row['topology_weight']:.3f} motor_w={row['motor_weight']:.3f}"
        )
    print()

    print("Parameter sensitivity (metric that triggered the classification):")
    seen = set()
    for row in sensitivity:
        if row["parameter"] in seen:
            continue
        seen.add(row["parameter"])
        trigger = f" ({row['triggering_metric']})" if row["triggering_metric"] else ""
        print(f"  {row['parameter']:<40} {row['classification']}{trigger}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).with_name("generated"),
        help="Directory for generated CSVs (default: ./generated)",
    )
    parser.add_argument(
        "--params", type=Path, default=None, help="Explicit params.toml path"
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    params = load_params(args.params)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    calibration = calibration_rows(params)
    convergence = competency_convergence_rows(params)
    memory = memory_tracking_rows(params)
    residual = residual_localization_rows(params)
    uncertainty = uncertainty_behavior_rows(params)
    hand_transfer = hand_transfer_rows(params)
    reacquisition = reacquisition_rows(params)
    guidance = guidance_sensitivity_rows(params)
    sensitivity = parameter_sensitivity_rows(params)

    outputs = {
        "calibration.csv": calibration,
        "competency_convergence.csv": convergence,
        "memory_tracking.csv": memory,
        "residual_localization.csv": residual,
        "uncertainty_behavior.csv": uncertainty,
        "hand_transfer.csv": hand_transfer,
        "reacquisition.csv": reacquisition,
        "guidance_sensitivity.csv": guidance,
        "parameter_sensitivity.csv": sensitivity,
    }
    for filename, rows in outputs.items():
        write_csv(args.output_dir / filename, rows)

    report(
        calibration,
        convergence,
        memory,
        residual,
        uncertainty,
        hand_transfer,
        reacquisition,
        guidance,
        sensitivity,
    )

    print()
    for filename in outputs:
        print(f"Wrote {args.output_dir / filename}")


if __name__ == "__main__":
    main()
