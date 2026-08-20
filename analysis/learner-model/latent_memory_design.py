#!/usr/bin/env python3
"""Latent memory state design - activation, durability, and consolidation.

The mechanism-shape comparison (reacquisition_experiment.py) found hybrid
(anchor movement + half-life strengthening together) recovers a decayed
"returning" material fastest, but its diagnostic ceiling
(half_life -> 60.0 for every material alike) let it silently accumulate
durability on material that was never anchored in the first place - the
new-material check there showed half-life climbing past 30 days on a
material with zero retrieval history. That ceiling should not go to
production literally.

This file designs the fix: durability should strengthen toward a
material-specific retained CEILING, not a universal one. A material that
has never exceeded its own starting durability has a zero gap to grow
into (inert by construction); a material that was previously
well-consolidated does not. `consolidated_half_life_days` below is that
ceiling - in this diagnostic it is a fixed value supplied once at
initialization, never updated by anything that happens during a trial
(see apply_supported_practice()'s comment for why the update formula
cannot raise it, by construction, not by omission). What should be
allowed to raise it before this becomes production state - literal
historical maximum? A slowly-retained consolidation trace? A Bayesian
prior over past durability? - is an open question this file does not
resolve, only uses as a fixed diagnostic input.

Distinct from, not an extension of, reacquisition_experiment.py: that
file is a complete record of the existence-proof and shape-comparison
passes; this is its own experiment, testing a specific state design
against a behavioral matrix rather than comparing mechanism shapes.

No changes to synthetic.py, model.py, state.py, simulate.py, pipeline.py,
longitudinal.py, candidates.py, or any config.toml/params.toml.
TrueMaterialMemory.retrievability() only ever reads last_retrieval_at and
half_life_days, so memory_anchor_at is represented here by mutating
last_retrieval_at directly (the same diagnostic shortcut as the prior
experiment) - not the recommended production representation.

Usage:
    python latent_memory_design.py
    python latent_memory_design.py --output-dir generated
"""

from __future__ import annotations

import argparse
import copy
import csv
import math
import random
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

# append, not insert(0): scheduler/ has its own simulate.py, which would
# otherwise shadow this directory's simulate.py.
sys.path.append(str(Path(__file__).resolve().parent.parent / "scheduler"))

from candidates import InstrumentProfile
from config import Params as SchedulerParams
from config import load_params as load_scheduler_params
from domain import Exercise, GuidanceContext, TechnicalMaterial
from longitudinal import NoAdmittedCandidate, SchedulerAgent
from model import Outcome, evidence_weights, predicted_success, update
from params import Params as LearnerParams
from params import load_params as load_learner_params
from simulate import fixed_exercise, initial_state
from synthetic import PROFILES, TrueLearnerProfile, TrueMaterialMemory, sample_outcome

MATERIAL = TechnicalMaterial("C", "MAJOR")
NEW_MATERIAL = TechnicalMaterial("G", "MAJOR")
STARTING_HALF_LIFE_DAYS = 6.0
STARTING_GAP_DAYS = 14.0  # matches synthetic.py's own "returning" profile comment
NEW_MATERIAL_DEFAULT_HALF_LIFE_DAYS = PROFILES["returning"].default_half_life_days
# Read from the profile itself, not hardcoded - _true_memory_for()'s lazy
# init uses this exact value for any material with no seeded entry, and a
# hardcoded copy could silently drift from it.
RETURNING_CONSOLIDATED_HALF_LIFE_DAYS = 20.0  # illustrative "once well-
# consolidated" stand-in, not derived from anything - same status as the
# prior experiment's HALF_LIFE_CEILING_DAYS
ALREADY_STRONG_HALF_LIFE_DAYS = 20.0  # equals its own consolidated ceiling

SESSION_COUNT = 15
ATTEMPTS_PER_SESSION = 20
ATTEMPTS = SESSION_COUNT * ATTEMPTS_PER_SESSION  # 300
DAY_STEP = 0.5
SEED = 103  # one of Pass 4's own core_sweep seeds

PROBE_THRESHOLD = 0.5  # "genuine test more likely than not to succeed"


def _guidance_independence(exercise: Exercise) -> int:
    if exercise.guidance.concurrent_pitch_cues:
        return 0
    if exercise.guidance.notes_previewed:
        return 1
    return 2


def _delta_q(before: float, after: float) -> float:
    """q = -log2(retrievability); positive delta_q means the event reduced
    effective memory age."""
    return -math.log2(before) - (-math.log2(after))


# --- Latent state and transition rules ----------------------------------


@dataclass
class LatentMemoryExtras:
    """Side-tracked bookkeeping alongside the real TrueMaterialMemory -
    never read by sample_outcome(). TrueMaterialMemory.last_retrieval_at
    is repurposed here as "memory_anchor_at" (moved by supported practice,
    not just genuine success); factual_last_retrieval_at tracks what that
    field would mean under its ORIGINAL, unmodified semantics (set only
    by genuine success), so the report can show the two diverging.

    consolidated_half_life_days is named deliberately not "peak": it is
    an IMMUTABLE restoration ceiling in this diagnostic (see
    apply_supported_practice()), supplied once at initialization."""

    consolidated_half_life_days: float
    factual_last_retrieval_at: float | None


def apply_genuine_success(
    true_memory: TrueMaterialMemory, extras: LatentMemoryExtras, now: float
) -> None:
    true_memory.last_retrieval_at = now
    extras.factual_last_retrieval_at = now
    # half_life_days / consolidated_half_life_days UNCHANGED here - an
    # explicitly open question (design choice #1 below), not assumed
    # either way.


def apply_supported_practice(
    true_memory: TrueMaterialMemory,
    extras: LatentMemoryExtras,
    exercise: Exercise,
    now: float,
    quality: float,
    anchor_rate: float,
    half_life_rate: float,
) -> None:
    support = _support_factor(exercise)
    if true_memory.last_retrieval_at is not None:
        fraction = anchor_rate * support * quality
        true_memory.last_retrieval_at += fraction * (
            now - true_memory.last_retrieval_at
        )
    gain = half_life_rate * support * quality
    true_memory.half_life_days += gain * (
        extras.consolidated_half_life_days - true_memory.half_life_days
    )
    # consolidated_half_life_days is NOT updated here. For any gain in
    # [0, 1], half_life_days moves TOWARD consolidated_half_life_days and
    # can never exceed it, so a max(consolidated, half_life_days) update
    # after this line would always be a no-op. consolidated_half_life_days
    # is therefore a fixed ceiling for the duration of this diagnostic -
    # what (if anything) should be allowed to raise it is deferred, not
    # answered by these rules.


def _apply_latent_update(
    true_memory: TrueMaterialMemory,
    extras: LatentMemoryExtras,
    exercise: Exercise,
    outcome: Outcome,
    now: float,
    anchor_rate: float,
    half_life_rate: float,
) -> None:
    if outcome.retrieval_succeeded is True:
        apply_genuine_success(true_memory, extras, now)
        return
    quality = _practice_quality(outcome)
    if quality <= 0.0:
        return
    apply_supported_practice(
        true_memory, extras, exercise, now, quality, anchor_rate, half_life_rate
    )


# --- Calibration (locally matched dose, same discipline as the prior
# experiment) -------------------------------------------------------------

SUPPORT_FACTOR = {0: 0.3, 1: 0.7, 2: 1.0}  # cued : notes_previewed : unguided
NOMINAL_FRACTION = 0.10  # the already-proven-sufficient anchor-movement
# dose from the existence-proof experiment


def _support_factor(exercise: Exercise) -> float:
    return SUPPORT_FACTOR[_guidance_independence(exercise)]


def _practice_quality(outcome: Outcome) -> float:
    if not outcome.started or not outcome.completed:
        return 0.0
    return max(
        0.0,
        min(
            1.0,
            (outcome.continuity + outcome.temporal_stability + outcome.pitch_integrity)
            / 3.0,
        ),
    )


def _matched_saturating_half_life_rate(
    fraction: float, half_life_0: float, ceiling: float
) -> float:
    return half_life_0 * fraction / ((1.0 - fraction) * (ceiling - half_life_0))


# Both pathways fire together on every qualifying supported-practice
# attempt (this design hardcodes the hybrid shape - the prior comparison
# already settled that question), so the dose is split in half between
# them, matching the prior experiment's HYBRID_*_RATE convention.
ANCHOR_MOVEMENT_RATE = NOMINAL_FRACTION / 2
HALF_LIFE_GROWTH_RATE = _matched_saturating_half_life_rate(
    NOMINAL_FRACTION / 2, STARTING_HALF_LIFE_DAYS, RETURNING_CONSOLIDATED_HALF_LIFE_DAYS
)


def _verify_matched_initial_dose() -> None:
    print(
        "Matched initial dose check (delta_q at the returning reference state, "
        "full strength, both pathways combined):"
    )
    unguided = fixed_exercise(MATERIAL, "RIGHT")  # support_factor=1.0
    memory = TrueMaterialMemory(
        half_life_days=STARTING_HALF_LIFE_DAYS, last_retrieval_at=-STARTING_GAP_DAYS
    )
    extras = LatentMemoryExtras(
        consolidated_half_life_days=RETURNING_CONSOLIDATED_HALF_LIFE_DAYS,
        factual_last_retrieval_at=-STARTING_GAP_DAYS,
    )
    before = memory.retrievability(0.0, 0.4)
    apply_supported_practice(
        memory, extras, unguided, 0.0, 1.0, ANCHOR_MOVEMENT_RATE, HALF_LIFE_GROWTH_RATE
    )
    after = memory.retrievability(0.0, 0.4)
    print(f"  delta_q={_delta_q(before, after):.4f}")
    print()


# --- Truth builders --------------------------------------------------------


def _returning_truth(
    consolidated_half_life_days: float,
) -> tuple[TrueLearnerProfile, LatentMemoryExtras]:
    truth = copy.deepcopy(PROFILES["returning"])
    truth.true_material_memory = {
        "C_MAJOR": TrueMaterialMemory(
            half_life_days=STARTING_HALF_LIFE_DAYS, last_retrieval_at=-STARTING_GAP_DAYS
        )
    }
    extras = LatentMemoryExtras(
        consolidated_half_life_days=consolidated_half_life_days,
        factual_last_retrieval_at=-STARTING_GAP_DAYS,
    )
    return truth, extras


def _new_material_truth() -> tuple[TrueLearnerProfile, LatentMemoryExtras]:
    truth = copy.deepcopy(PROFILES["returning"])
    truth.true_material_memory = {}
    extras = LatentMemoryExtras(
        consolidated_half_life_days=NEW_MATERIAL_DEFAULT_HALF_LIFE_DAYS,
        factual_last_retrieval_at=None,
    )
    return truth, extras


def _already_strong_truth() -> tuple[TrueLearnerProfile, LatentMemoryExtras]:
    truth = copy.deepcopy(PROFILES["returning"])
    truth.true_material_memory = {
        "C_MAJOR": TrueMaterialMemory(
            half_life_days=ALREADY_STRONG_HALF_LIFE_DAYS, last_retrieval_at=-1.0
        )
    }
    extras = LatentMemoryExtras(
        consolidated_half_life_days=ALREADY_STRONG_HALF_LIFE_DAYS,
        factual_last_retrieval_at=-1.0,
    )
    return truth, extras


# --- Row construction and fixed-practice loop ------------------------------


def _row(
    attempt_index: int,
    at_days: float,
    before: float,
    after: float,
    true_memory: TrueMaterialMemory,
    extras: LatentMemoryExtras,
    exercise: Exercise,
    outcome: Outcome,
    *,
    challenge_bypass: str | None = None,
    model_belief: float | None = None,
) -> dict[str, Any]:
    return {
        "attempt_index": attempt_index,
        "at_days": at_days,
        "true_retrievability_before": before,
        "true_retrievability_after": after,
        "delta_q": _delta_q(before, after),
        "half_life_days": true_memory.half_life_days,
        "consolidated_half_life_days": extras.consolidated_half_life_days,
        "anchor_last_retrieval_at": true_memory.last_retrieval_at,
        "factual_last_retrieval_at": extras.factual_last_retrieval_at,
        "guidance_independence": _guidance_independence(exercise),
        "retrieval_succeeded": outcome.retrieval_succeeded,
        "started": outcome.started,
        "completed": outcome.completed,
        "challenge_bypass": challenge_bypass,
        "model_belief_retrievability": model_belief,
    }


def _run_fixed_practice(
    truth: TrueLearnerProfile,
    extras: LatentMemoryExtras,
    guidance: GuidanceContext,
    *,
    material: TechnicalMaterial,
    anchor_rate: float,
    half_life_rate: float,
    attempts: int = ATTEMPTS,
    seed: int = SEED,
) -> list[dict[str, Any]]:
    """No state/model-estimator loop here: sample_outcome() depends only
    on truth/exercise/now/rng, and predicted_success()/update() consume no
    randomness, so the true-memory trajectory is identical with or without
    them - see condition_fixed_cued_rows()'s divergence check in
    reacquisition_experiment.py, which already demonstrated this."""
    rng = random.Random(seed)
    now = 0.0
    rows = []
    material_id = material.material_id
    for i in range(attempts):
        now += DAY_STEP
        exercise = fixed_exercise(material, "RIGHT", guidance=guidance)
        true_memory = truth.true_material_memory.get(material_id)
        if true_memory is None:
            true_memory = TrueMaterialMemory(
                half_life_days=truth.default_half_life_days
            )
            truth.true_material_memory[material_id] = true_memory
        before = true_memory.retrievability(now, truth.memory_prior)
        outcome = sample_outcome(truth, exercise, now, rng)
        _apply_latent_update(
            true_memory, extras, exercise, outcome, now, anchor_rate, half_life_rate
        )
        after = true_memory.retrievability(now, truth.memory_prior)
        rows.append(_row(i, now, before, after, true_memory, extras, exercise, outcome))
    return rows


# --- Scenarios ---------------------------------------------------------


def scenario_1_new_material_inert(
    anchor_rate: float, half_life_rate: float
) -> list[dict[str, Any]]:
    truth, extras = _new_material_truth()
    return _run_fixed_practice(
        truth,
        extras,
        GuidanceContext(concurrent_pitch_cues=True),
        material=NEW_MATERIAL,
        anchor_rate=anchor_rate,
        half_life_rate=half_life_rate,
    )


def scenario_2_new_material_eventual_success(
    anchor_rate: float, half_life_rate: float
) -> list[dict[str, Any]]:
    truth, extras = _new_material_truth()
    return _run_fixed_practice(
        truth,
        extras,
        GuidanceContext(notes_previewed=True),
        material=NEW_MATERIAL,
        anchor_rate=anchor_rate,
        half_life_rate=half_life_rate,
    )


def scenario_3_returning_supported_practice(
    anchor_rate: float, half_life_rate: float
) -> list[dict[str, Any]]:
    truth, extras = _returning_truth(RETURNING_CONSOLIDATED_HALF_LIFE_DAYS)
    return _run_fixed_practice(
        truth,
        extras,
        GuidanceContext(concurrent_pitch_cues=True),
        material=MATERIAL,
        anchor_rate=anchor_rate,
        half_life_rate=half_life_rate,
    )


def scenario_4_returning_scheduler_driven(
    learner_params: LearnerParams,
    scheduler_params: SchedulerParams,
    anchor_rate: float,
    half_life_rate: float,
) -> tuple[list[dict[str, Any]], str]:
    truth, extras = _returning_truth(RETURNING_CONSOLIDATED_HALF_LIFE_DAYS)
    instrument = InstrumentProfile()
    agent = SchedulerAgent(
        instrument, [MATERIAL], scheduler_params, learner_params, top_n=1
    )
    state = initial_state(truth, learner_params, now=0.0)
    rng = random.Random(SEED)
    now = 0.0
    rows: list[dict[str, Any]] = []
    material_id = MATERIAL.material_id
    try:
        for session_index in range(SESSION_COUNT):
            if session_index > 0:
                agent.new_session()
            for _ in range(ATTEMPTS_PER_SESSION):
                now += DAY_STEP
                state.propagate(now, learner_params)
                exercise = agent.pick(rng, len(rows), state, now)
                true_memory = truth.true_material_memory[material_id]
                before = true_memory.retrievability(now, truth.memory_prior)
                prediction = predicted_success(state, exercise, now, learner_params)
                outcome = sample_outcome(truth, exercise, now, rng)
                weights = evidence_weights(exercise, outcome)
                update(
                    state, exercise, outcome, weights, prediction, now, learner_params
                )
                _apply_latent_update(
                    true_memory,
                    extras,
                    exercise,
                    outcome,
                    now,
                    anchor_rate,
                    half_life_rate,
                )
                agent.on_outcome(exercise, outcome, now)
                after = true_memory.retrievability(now, truth.memory_prior)
                belief = state.material_memory.get(material_id)
                model_belief = (
                    belief.retrievability_or_prior(now, learner_params)
                    if belief is not None
                    else learner_params.material_memory.prior_retrievability
                )
                rows.append(
                    _row(
                        len(rows),
                        now,
                        before,
                        after,
                        true_memory,
                        extras,
                        exercise,
                        outcome,
                        challenge_bypass=agent.records[-1].selected.challenge_bypass,
                        model_belief=model_belief,
                    )
                )
        return rows, ""
    except NoAdmittedCandidate as exc:
        return rows, f"NoAdmittedCandidate: {exc}"


def scenario_5_already_strong(
    anchor_rate: float, half_life_rate: float
) -> list[dict[str, Any]]:
    truth, extras = _already_strong_truth()
    return _run_fixed_practice(
        truth,
        extras,
        GuidanceContext(),  # unguided - "ordinary" independent practice
        material=MATERIAL,
        anchor_rate=anchor_rate,
        half_life_rate=half_life_rate,
    )


def scenario_6_prolonged_non_practice() -> list[dict[str, Any]]:
    truth, extras = _returning_truth(RETURNING_CONSOLIDATED_HALF_LIFE_DAYS)
    memory = truth.true_material_memory["C_MAJOR"]
    rows = []
    for i in range(ATTEMPTS):
        now = (i + 1) * DAY_STEP
        r = memory.retrievability(now, truth.memory_prior)
        rows.append(
            {
                "attempt_index": i,
                "at_days": now,
                "true_retrievability_before": r,
                "true_retrievability_after": r,
                "delta_q": 0.0,
                "half_life_days": memory.half_life_days,
                "consolidated_half_life_days": extras.consolidated_half_life_days,
                "anchor_last_retrieval_at": memory.last_retrieval_at,
                "factual_last_retrieval_at": extras.factual_last_retrieval_at,
                "guidance_independence": None,
                "retrieval_succeeded": None,
                "started": None,
                "completed": None,
                "challenge_bypass": None,
                "model_belief_retrievability": None,
            }
        )
    return rows


def scenario_7_paired(
    anchor_rate: float, half_life_rate: float
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """The core savings-validation pair: two returning states, IDENTICAL
    present state (half_life=6, anchor=-14), differing ONLY in
    consolidated_half_life_days (20 vs 6 - the latter a "no retained
    history" control, the same zero-gap inertness as new material). Fully
    cued so genuine success is impossible - any difference in trajectory
    can only come from the consolidated-value-gated half-life pathway,
    not from the real success mechanism both states already share."""
    truth_a, extras_a = _returning_truth(RETURNING_CONSOLIDATED_HALF_LIFE_DAYS)
    truth_b, extras_b = _returning_truth(STARTING_HALF_LIFE_DAYS)
    guidance = GuidanceContext(concurrent_pitch_cues=True)
    rows_a = _run_fixed_practice(
        truth_a,
        extras_a,
        guidance,
        material=MATERIAL,
        anchor_rate=anchor_rate,
        half_life_rate=half_life_rate,
    )
    rows_b = _run_fixed_practice(
        truth_b,
        extras_b,
        guidance,
        material=MATERIAL,
        anchor_rate=anchor_rate,
        half_life_rate=half_life_rate,
    )
    return rows_a, rows_b


# --- Report -------------------------------------------------------------


def _first_probe_crossing(rows: list[dict[str, Any]]) -> int | None:
    return next(
        (
            r["attempt_index"]
            for r in rows
            if r["true_retrievability_before"] >= PROBE_THRESHOLD
        ),
        None,
    )


def _crossing_readout(rows: list[dict[str, Any]]) -> str:
    idx = _first_probe_crossing(rows)
    if idx is not None:
        return f"crossed p>={PROBE_THRESHOLD} at attempt {idx}"
    return f"never crossed p>={PROBE_THRESHOLD} in {len(rows)} attempts"


def _max_abs_drift(rows: list[dict[str, Any]], field: str, start_value: float) -> float:
    return max((abs(r[field] - start_value) for r in rows), default=0.0)


def _report_scenario_1(rows: list[dict[str, Any]]) -> None:
    print(
        "Scenario 1 - new material + supported practice, fully-cued "
        "(no genuine success possible):"
    )
    drift = _max_abs_drift(rows, "half_life_days", rows[0]["half_life_days"])
    anchor_ever_set = any(r["anchor_last_retrieval_at"] is not None for r in rows)
    print(f"  half_life drift={drift:.6f}  anchor ever set={anchor_ever_set}")
    if drift > 1e-9 or anchor_ever_set:
        print("  UNEXPECTED - zero-gap inertness violated, investigate.")
    print()


def _report_scenario_2(rows: list[dict[str, Any]]) -> None:
    print("Scenario 2 - new material + eventual genuine success (notes-previewed):")
    first_success = next(
        (r["attempt_index"] for r in rows if r["retrieval_succeeded"] is True), None
    )
    if first_success is None:
        print(f"  no genuine success across {len(rows)} attempts.")
        print()
        return
    success_row = rows[first_success]
    equal_at_success = (
        abs(
            success_row["anchor_last_retrieval_at"]
            - success_row["factual_last_retrieval_at"]
        )
        < 1e-9
    )
    first_divergence = next(
        (
            r["attempt_index"]
            for r in rows[first_success + 1 :]
            if abs(r["anchor_last_retrieval_at"] - r["factual_last_retrieval_at"])
            > 1e-9
        ),
        None,
    )
    final = rows[-1]
    final_gap = final["anchor_last_retrieval_at"] - final["factual_last_retrieval_at"]
    print(
        f"  first genuine success at attempt {first_success} (day {success_row['at_days']:.1f})"
    )
    print(f"  anchor == factual immediately after: {equal_at_success}")
    if first_divergence is None:
        print("  no subsequent divergence observed.")
    else:
        print(f"  first subsequent divergence at attempt {first_divergence}")
    print(f"  final gap (anchor - factual) = {final_gap:.4f} days")
    print(
        "  half_life_days/consolidated stayed frozen at the starting value throughout,\n"
        "  even after the success - design choice #1, surfaced rather than resolved."
    )
    print()


def _report_scenario_3(rows: list[dict[str, Any]]) -> None:
    print(
        "Scenario 3 - returning material + supported practice, fully-cued (consolidated=20):"
    )
    print(f"  {_crossing_readout(rows)}")
    print(
        f"  final half_life_days={rows[-1]['half_life_days']:.2f} "
        f"(started at {rows[0]['half_life_days']:.2f})"
    )
    print(
        "  No predicted direction relative to the prior experiment's ceiling=60 hybrid\n"
        "  result (attempt 62) - initial dose is matched but this ceiling gives less\n"
        "  headroom, so faster recovery is not assumed."
    )
    print()


def _report_scenario_4(rows: list[dict[str, Any]], error: str) -> None:
    print(
        "Scenario 4 - returning material + scheduler-driven (consolidated=20, SEED=103):"
    )
    if error:
        print(f"  {error}")
    print(f"  attempts_reached={len(rows)}")
    if rows:
        print(f"  {_crossing_readout(rows)}")
        print(
            f"  final half_life_days={rows[-1]['half_life_days']:.2f} "
            f"(started at {rows[0]['half_life_days']:.2f})"
        )
    print("  Same non-prediction as scenario 3.")
    print()


def _report_scenario_5(rows: list[dict[str, Any]]) -> None:
    print(
        "Scenario 5 - already-strong material + ordinary practice (half_life=consolidated=20):"
    )
    drift = _max_abs_drift(rows, "half_life_days", rows[0]["half_life_days"])
    print(f"  half_life drift={drift:.6f} (zero gap to its own consolidated ceiling)")
    if drift > 1e-9:
        print(
            "  UNEXPECTED - zero-gap inertness violated at an already-consolidated ceiling."
        )
    print()


def _report_scenario_6(rows: list[dict[str, Any]]) -> None:
    print("Scenario 6 - prolonged non-practice (pure decay):")
    half_life_drift = _max_abs_drift(rows, "half_life_days", rows[0]["half_life_days"])
    anchor_drift = _max_abs_drift(
        rows, "anchor_last_retrieval_at", rows[0]["anchor_last_retrieval_at"]
    )
    print(
        f"  half_life drift={half_life_drift:.6f}  anchor drift={anchor_drift:.6f}  "
        "(elapsed time alone touches neither)"
    )
    print(f"  final true_retrievability={rows[-1]['true_retrievability_before']:.4f}")
    print()


def _report_scenario_7(
    rows_a: list[dict[str, Any]], rows_b: list[dict[str, Any]]
) -> None:
    print(
        "Scenario 7A/7B - paired comparison, identical present state, consolidated=20 vs 6:"
    )
    print(f"  7A (consolidated=20): {_crossing_readout(rows_a)}")
    print(f"  7B (consolidated=6):  {_crossing_readout(rows_b)}")
    drift_b = _max_abs_drift(rows_b, "half_life_days", rows_b[0]["half_life_days"])
    print(f"  7B half_life drift={drift_b:.6f} - control check, should be exactly zero")
    if drift_b > 1e-9:
        print(
            "  UNEXPECTED - 7B is supposed to be a zero-gap 'no consolidation' control."
        )
    idx_a, idx_b = _first_probe_crossing(rows_a), _first_probe_crossing(rows_b)
    final_a = rows_a[-1]["true_retrievability_after"]
    final_b = rows_b[-1]["true_retrievability_after"]
    print(f"  final true_retrievability: 7A={final_a:.4f}  7B={final_b:.4f}")
    if idx_a is not None and idx_b is None:
        print(
            "  7A recovers, 7B never does, from an IDENTICAL present state - this is the\n"
            "  central evidence: retained historical consolidation alone changes\n"
            "  reacquisition, holding current apparent memory constant."
        )
    elif idx_a is not None and idx_b is not None and idx_a < idx_b:
        print(
            f"  7A recovers faster than 7B ({idx_a} vs {idx_b}) - same conclusion, softer form."
        )
    elif idx_a == idx_b and abs(final_a - final_b) < 0.02:
        print(
            "  7A and 7B behave identically - consolidated value is not doing causal work\n"
            "  in this formulation. That is itself the finding, not a bug to explain away."
        )
    elif idx_a == idx_b is None and final_a > final_b:
        # Neither crosses PROBE_THRESHOLD within this budget, but the binary
        # crossing metric alone would wrongly read as "identical" here -
        # 7A's retained ceiling still measurably slows the decay relative to
        # 7B's zero-gap inertness. Consolidated value is doing real causal
        # work; it just isn't large enough at this calibration/attempt
        # budget to cross the specific probe bar under fully-cued-only
        # practice (matching trajectory 2's "never recovers" finding in the
        # prior shape comparison).
        print(
            "  Neither crosses the probe threshold, but 7A ends well above 7B - "
            "consolidated\n  value measurably slows decay even though this dose/budget isn't "
            "enough to reach\n  the probe bar under fully-cued-only practice."
        )
    else:
        print(
            "  7B recovers at least as fast as 7A - contradicts the design intent, inspect."
        )
    print(
        "  Note: rng draw counts diverge between 7A/7B once their true_retrievability paths\n"
        "  diverge (started's short-circuit depends on it) - the same accepted caveat as the\n"
        "  prior experiment's matched-dose check, not specific to this pair."
    )
    print()


# --- Output/CLI -----------------------------------------------------------


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("")
        return
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).with_name("generated"),
        help="Directory for generated CSVs (default: ./generated)",
    )
    parser.add_argument("--scheduler-params", type=Path, default=None)
    parser.add_argument("--learner-params", type=Path, default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    scheduler_params = load_scheduler_params(args.scheduler_params)
    learner_params = load_learner_params(args.learner_params)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    _verify_matched_initial_dose()

    scenarios: dict[str, list[dict[str, Any]]] = {
        "scenario_1_new_material_inert": scenario_1_new_material_inert(
            ANCHOR_MOVEMENT_RATE, HALF_LIFE_GROWTH_RATE
        ),
        "scenario_2_new_material_eventual_success": scenario_2_new_material_eventual_success(
            ANCHOR_MOVEMENT_RATE, HALF_LIFE_GROWTH_RATE
        ),
        "scenario_3_returning_supported_practice": scenario_3_returning_supported_practice(
            ANCHOR_MOVEMENT_RATE, HALF_LIFE_GROWTH_RATE
        ),
        "scenario_5_already_strong": scenario_5_already_strong(
            ANCHOR_MOVEMENT_RATE, HALF_LIFE_GROWTH_RATE
        ),
        "scenario_6_prolonged_non_practice": scenario_6_prolonged_non_practice(),
    }
    rows_4, error_4 = scenario_4_returning_scheduler_driven(
        learner_params, scheduler_params, ANCHOR_MOVEMENT_RATE, HALF_LIFE_GROWTH_RATE
    )
    scenarios["scenario_4_returning_scheduler_driven"] = rows_4
    rows_7a, rows_7b = scenario_7_paired(ANCHOR_MOVEMENT_RATE, HALF_LIFE_GROWTH_RATE)
    scenarios["scenario_7a_consolidated_20"] = rows_7a
    scenarios["scenario_7b_consolidated_6"] = rows_7b

    _report_scenario_1(scenarios["scenario_1_new_material_inert"])
    _report_scenario_2(scenarios["scenario_2_new_material_eventual_success"])
    _report_scenario_3(scenarios["scenario_3_returning_supported_practice"])
    _report_scenario_4(rows_4, error_4)
    _report_scenario_5(scenarios["scenario_5_already_strong"])
    _report_scenario_6(scenarios["scenario_6_prolonged_non_practice"])
    _report_scenario_7(rows_7a, rows_7b)

    combined_rows = []
    for scenario, rows in scenarios.items():
        for row in rows:
            combined_rows.append({"scenario": scenario, **row})
    write_csv(args.output_dir / "latent_memory_design.csv", combined_rows)
    print(f"Wrote {args.output_dir / 'latent_memory_design.csv'}")


if __name__ == "__main__":
    main()
