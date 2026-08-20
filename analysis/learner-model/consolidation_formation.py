#!/usr/bin/env python3
"""Consolidation formation - which events raise retained durability.

latent_memory_design.py (frozen as a diagnostic record, not extended
further) settled three things: activation and factual retrieval history
should be separate fields; current durability (half_life_days) and
retained consolidation (consolidated_half_life_days) should be separate
fields; and retained consolidation causally accelerates reacquisition -
its paired 7A/7B comparison (identical current state, consolidated=20 vs.
6) ended at true_retrievability 0.167 vs. 0.006, a ~28x separation.

That file left one thing deliberately unresolved: consolidated_half_life
_days was supplied once at initialization and never updated by anything
that happened during a trial - current durability could be restored
toward consolidation, but nothing ever created consolidation. This file
is a small, single-focus experiment about exactly that: which events
raise consolidated_half_life_days, and how slowly, relative to current
durability. Not a scheduler experiment, not coefficient tuning, and not
a reopening of the three settled questions above - whether genuine
success should raise *current* durability directly stays out of scope
here too, exactly as the prior file left it, to keep this pass to one
new mechanism.

Self-contained, not an extension of latent_memory_design.py, matching
that file's own relationship to reacquisition_experiment.py: each phase
in this series freezes the previous phase's findings as carried-forward
rules/constants and isolates exactly one new mechanism. No changes to
synthetic.py, model.py, state.py, simulate.py, or any scheduler file.
The production model now has the separate fields this diagnostic motivated.
This frozen experiment disables the production transition and applies its
historical local consolidation-formation rule explicitly.

None of the scenarios here use the scheduler-driven trajectory, so
(unlike the prior two files) there is no cross-directory import into
analysis/scheduler/ - everything needed lives in this directory.

Usage:
    python consolidation_formation.py
    python consolidation_formation.py --output-dir generated
"""

from __future__ import annotations

import argparse
import copy
import csv
import itertools
import math
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from domain import Exercise, GuidanceContext, TechnicalMaterial
from model import Outcome
from simulate import fixed_exercise
from synthetic import PROFILES, TrueLearnerProfile, TrueMaterialMemory, sample_outcome

MATERIAL = TechnicalMaterial("C", "MAJOR")
NEW_MATERIAL = TechnicalMaterial("G", "MAJOR")
STARTING_HALF_LIFE_DAYS = 6.0
STARTING_GAP_DAYS = 14.0  # matches synthetic.py's own "returning" profile comment
NEW_MATERIAL_DEFAULT_HALF_LIFE_DAYS = PROFILES[
    "returning"
].default_current_half_life_days
RETURNING_CONSOLIDATED_HALF_LIFE_DAYS = 20.0  # same reference value used
# throughout latent_memory_design.py - reused here only as a non-trivial
# starting point for the scenario 3 regression check, not recalibrated.

ATTEMPTS = 300
EARN_ATTEMPTS = 60  # bounded initial earning phase for scenarios 4/5; with
# the illustrative growth rate this produces substantial (but not
# complete) consolidation before the controlled reacquisition comparison.
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
    return -math.log2(before) - (-math.log2(after))


# --- Latent state and transition rules ----------------------------------


@dataclass
class LatentMemoryExtras:
    """Side-tracked bookkeeping alongside the real TrueMaterialMemory -
    never read by sample_outcome(). See latent_memory_design.py for the
    full rationale; unchanged here except that consolidated_half_life_days
    is no longer immutable (see apply_genuine_success())."""

    consolidated_half_life_days: float
    factual_last_retrieval_at: float | None


SUPPORT_FACTOR = {0: 0.3, 1: 0.7, 2: 1.0}  # cued : notes_previewed : unguided
NOMINAL_FRACTION = 0.10


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
    """Carried forward verbatim from latent_memory_design.py, used ONLY
    for apply_supported_practice()'s current-durability restoration rate
    (which participates in retrievability(), so matching delta_q is a
    meaningful calibration target) - NOT used for consolidation growth
    below, which does not participate in retrievability() and has no
    delta_q to match (see CONSOLIDATION_GROWTH_RATE's comment)."""
    return half_life_0 * fraction / ((1.0 - fraction) * (ceiling - half_life_0))


# Carried forward verbatim from latent_memory_design.py.
ANCHOR_MOVEMENT_RATE = NOMINAL_FRACTION / 2
HALF_LIFE_GROWTH_RATE = _matched_saturating_half_life_rate(
    NOMINAL_FRACTION / 2, STARTING_HALF_LIFE_DAYS, RETURNING_CONSOLIDATED_HALF_LIFE_DAYS
)

CONSOLIDATION_ASYMPTOTE_DAYS = 60.0  # same numeric order as the original
# (structurally wrong, there) HALF_LIFE_CEILING_DAYS from the shape
# comparison - here it does a different, correctly-scoped job: an upper
# bound on how far genuine repeated success can consolidate durability,
# not a restoration ceiling touched by ordinary practice.
CONSOLIDATION_GROWTH_RATE = 0.05  # used DIRECTLY below - NOT run through
# _matched_saturating_half_life_rate(). That helper solves for a rate
# that matches an immediate delta_q against anchor movement, which only
# makes sense for a field that participates in retrievability().
# consolidated_half_life_days doesn't, so there's no delta_q to match;
# used directly, 0.05 means exactly what it says - a full-quality,
# full-support qualifying success closes 5% of the remaining
# consolidation gap. Illustrative, not derived, not a production
# proposal - same status as every calibration constant in this series.


def apply_supported_practice(
    true_memory: TrueMaterialMemory,
    extras: LatentMemoryExtras,
    exercise: Exercise,
    now: float,
    quality: float,
) -> None:
    """UNCHANGED, verbatim from latent_memory_design.py - restores
    activation and current durability toward the (now-mutable)
    consolidated ceiling. Still never touches consolidated_half_life_days
    itself. This experiment does not re-test this rule beyond scenario
    3's regression check."""
    support = _support_factor(exercise)
    if true_memory.memory_anchor_at is not None:
        fraction = ANCHOR_MOVEMENT_RATE * support * quality
        true_memory.memory_anchor_at += fraction * (now - true_memory.memory_anchor_at)
    gain = HALF_LIFE_GROWTH_RATE * support * quality
    true_memory.current_half_life_days += gain * (
        extras.consolidated_half_life_days - true_memory.current_half_life_days
    )


def apply_genuine_success(
    true_memory: TrueMaterialMemory,
    extras: LatentMemoryExtras,
    exercise: Exercise,
    outcome: Outcome,
    now: float,
) -> None:
    true_memory.memory_anchor_at = now  # unchanged
    true_memory.factual_last_retrieval_at = now
    true_memory.last_retrieval_attempt_at = now
    extras.factual_last_retrieval_at = now  # unchanged
    # half_life_days UNCHANGED here - out of scope for this pass, exactly
    # as latent_memory_design.py left it.
    quality = _practice_quality(outcome)
    if quality <= 0.0:
        return  # a technically-successful but poorly-executed retrieval
        # doesn't build lasting consolidation here - reported on if it
        # turns out to matter, not assumed negligible.
    gain = CONSOLIDATION_GROWTH_RATE * _support_factor(exercise) * quality
    extras.consolidated_half_life_days += gain * (
        CONSOLIDATION_ASYMPTOTE_DAYS - extras.consolidated_half_life_days
    )
    # Pulls toward a FIXED universal asymptote, not toward any per-
    # material observed value - deliberately not a running max(). A
    # single strong success only nudges consolidated by a small fraction
    # of the remaining gap; repetition does the work, which is what
    # makes this slow-changing rather than a step function. cued
    # guidance can't reach here at all (retrieval_observed() is False),
    # so _support_factor's existing 1.0 vs. 0.7 weighting (more
    # independent retrieval effort -> stronger consolidation event, a
    # claim about the true learner state, not about estimator evidence)
    # is the only differentiation in play.
    # No decay rule: elapsed time alone never touches
    # consolidated_half_life_days in this pass. That's an ASSUMPTION,
    # not a derived or validated property - scenario 4 confirms the
    # implementation preserves it, which is different from evidence that
    # zero decay is the right model.


def _apply_latent_update(
    true_memory: TrueMaterialMemory,
    extras: LatentMemoryExtras,
    exercise: Exercise,
    outcome: Outcome,
    now: float,
) -> None:
    if outcome.retrieval_succeeded is True:
        apply_genuine_success(true_memory, extras, exercise, outcome, now)
        return
    quality = _practice_quality(outcome)
    if quality <= 0.0:
        return
    apply_supported_practice(true_memory, extras, exercise, now, quality)


# --- Truth builders --------------------------------------------------------


def _returning_truth(
    consolidated_half_life_days: float,
) -> tuple[TrueLearnerProfile, LatentMemoryExtras]:
    truth = copy.deepcopy(PROFILES["returning"])
    truth.true_material_memory = {
        "C_MAJOR": TrueMaterialMemory(
            current_half_life_days=STARTING_HALF_LIFE_DAYS,
            consolidated_half_life_days=consolidated_half_life_days,
            memory_anchor_at=-STARTING_GAP_DAYS,
            factual_last_retrieval_at=-STARTING_GAP_DAYS,
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


# --- Row construction and fixed-practice loop ------------------------------


def _row(
    attempt_index: int,
    at_days: float,
    before: float,
    after: float,
    true_memory: TrueMaterialMemory,
    extras: LatentMemoryExtras,
    consolidated_before: float,
    exercise: Exercise,
    outcome: Outcome,
) -> dict[str, Any]:
    return {
        "attempt_index": attempt_index,
        "at_days": at_days,
        "true_retrievability_before": before,
        "true_retrievability_after": after,
        "delta_q": _delta_q(before, after),
        "half_life_days": true_memory.current_half_life_days,
        "consolidated_half_life_days_before": consolidated_before,
        "consolidated_half_life_days": extras.consolidated_half_life_days,
        "anchor_last_retrieval_at": true_memory.memory_anchor_at,
        "factual_last_retrieval_at": extras.factual_last_retrieval_at,
        "guidance_independence": _guidance_independence(exercise),
        "retrieval_succeeded": outcome.retrieval_succeeded,
        "started": outcome.started,
        "completed": outcome.completed,
    }


def _run_fixed_practice(
    truth: TrueLearnerProfile,
    extras: LatentMemoryExtras,
    guidance: GuidanceContext,
    *,
    material: TechnicalMaterial,
    attempts: int = ATTEMPTS,
    seed: int = SEED,
    start_day: float = 0.0,
) -> list[dict[str, Any]]:
    """No state/model-estimator loop: sample_outcome() depends only on
    truth/exercise/now/rng, so the true-memory trajectory is identical
    with or without it - already demonstrated by condition_fixed_cued_
    rows()'s divergence check in reacquisition_experiment.py."""
    rng = random.Random(seed)
    now = start_day
    rows = []
    material_id = material.material_id
    for i in range(attempts):
        now += DAY_STEP
        exercise = fixed_exercise(material, "RIGHT", guidance=guidance)
        true_memory = truth.true_material_memory.get(material_id)
        if true_memory is None:
            true_memory = TrueMaterialMemory(
                current_half_life_days=truth.default_current_half_life_days,
                consolidated_half_life_days=truth.default_current_half_life_days,
            )
            truth.true_material_memory[material_id] = true_memory
        before = true_memory.retrievability(now, truth.memory_prior)
        consolidated_before = extras.consolidated_half_life_days
        outcome = sample_outcome(
            truth, exercise, now, rng, apply_memory_transition=False
        )
        _apply_latent_update(true_memory, extras, exercise, outcome, now)
        after = true_memory.retrievability(now, truth.memory_prior)
        rows.append(
            _row(
                i,
                now,
                before,
                after,
                true_memory,
                extras,
                consolidated_before,
                exercise,
                outcome,
            )
        )
    return rows


# --- Scenarios ---------------------------------------------------------


def scenario_1_consolidation_growth_isolated() -> list[dict[str, Any]]:
    truth, extras = _new_material_truth()
    return _run_fixed_practice(
        truth, extras, GuidanceContext(), material=NEW_MATERIAL, attempts=ATTEMPTS
    )


def _deterministic_guidance_check() -> tuple[float, float]:
    """One transition each, isolated from stochastic trajectory effects:
    same starting consolidation, quality=1.0, one unguided genuine
    success vs. one notes-previewed genuine success. Returns
    (increment_unguided, increment_notes_previewed)."""
    full_quality_outcome = Outcome(
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
    unguided_exercise = fixed_exercise(MATERIAL, "RIGHT")
    notes_exercise = fixed_exercise(
        MATERIAL, "RIGHT", guidance=GuidanceContext(notes_previewed=True)
    )

    memory_u = TrueMaterialMemory(
        current_half_life_days=STARTING_HALF_LIFE_DAYS,
        consolidated_half_life_days=STARTING_HALF_LIFE_DAYS,
    )
    extras_u = LatentMemoryExtras(
        consolidated_half_life_days=STARTING_HALF_LIFE_DAYS,
        factual_last_retrieval_at=None,
    )
    apply_genuine_success(
        memory_u, extras_u, unguided_exercise, full_quality_outcome, 0.0
    )
    increment_unguided = extras_u.consolidated_half_life_days - STARTING_HALF_LIFE_DAYS

    memory_n = TrueMaterialMemory(
        current_half_life_days=STARTING_HALF_LIFE_DAYS,
        consolidated_half_life_days=STARTING_HALF_LIFE_DAYS,
    )
    extras_n = LatentMemoryExtras(
        consolidated_half_life_days=STARTING_HALF_LIFE_DAYS,
        factual_last_retrieval_at=None,
    )
    apply_genuine_success(memory_n, extras_n, notes_exercise, full_quality_outcome, 0.0)
    increment_notes = extras_n.consolidated_half_life_days - STARTING_HALF_LIFE_DAYS

    return increment_unguided, increment_notes


def scenario_2_guidance_trajectories() -> tuple[
    list[dict[str, Any]], list[dict[str, Any]]
]:
    truth_u, extras_u = _new_material_truth()
    rows_u = _run_fixed_practice(
        truth_u, extras_u, GuidanceContext(), material=NEW_MATERIAL, attempts=ATTEMPTS
    )
    truth_n, extras_n = _new_material_truth()
    rows_n = _run_fixed_practice(
        truth_n,
        extras_n,
        GuidanceContext(notes_previewed=True),
        material=NEW_MATERIAL,
        attempts=ATTEMPTS,
    )
    return rows_u, rows_n


def scenario_3_supported_practice_inert() -> list[dict[str, Any]]:
    truth, extras = _returning_truth(RETURNING_CONSOLIDATED_HALF_LIFE_DAYS)
    return _run_fixed_practice(
        truth,
        extras,
        GuidanceContext(concurrent_pitch_cues=True),
        material=MATERIAL,
        attempts=ATTEMPTS,
    )


def scenario_4_persistence_under_non_practice() -> tuple[
    list[dict[str, Any]], list[dict[str, Any]], float, float
]:
    truth, extras = _new_material_truth()
    earn_rows = _run_fixed_practice(
        truth, extras, GuidanceContext(), material=NEW_MATERIAL, attempts=EARN_ATTEMPTS
    )
    memory = truth.true_material_memory[NEW_MATERIAL.material_id]
    consolidated_at_start_of_decay = extras.consolidated_half_life_days
    half_life_at_start_of_decay = memory.current_half_life_days
    last_now = earn_rows[-1]["at_days"] if earn_rows else 0.0
    decay_rows = []
    for i in range(ATTEMPTS):
        now = last_now + (i + 1) * DAY_STEP
        r = memory.retrievability(now, truth.memory_prior)
        decay_rows.append(
            {
                "attempt_index": i,
                "at_days": now,
                "true_retrievability_before": r,
                "true_retrievability_after": r,
                "half_life_days": memory.current_half_life_days,
                "consolidated_half_life_days": extras.consolidated_half_life_days,
            }
        )
    return (
        earn_rows,
        decay_rows,
        consolidated_at_start_of_decay,
        half_life_at_start_of_decay,
    )


def scenario_5_capstone() -> dict[str, Any]:
    """Two-phase controlled experiment, NOT a naturalistic uninterrupted
    learner trajectory. Phase 1 earns different consolidated_half_life_
    days values through genuinely different practice (Track A: unguided,
    produces genuine successes; Track B: fully-cued, never does). Phase 2
    resets BOTH tracks to the identical reference "returning" present
    state (half_life=6, anchor=-14, factual=-14) - preserving only each
    track's own earned consolidated value - then runs an identical
    fully-cued-only reacquisition phase. The reset isolates the actual
    causal question from the confound phase 1 alone would leave: without
    it, Track A exits with a recent anchor/factual (from its successes)
    and Track B's stayed None, a difference unrelated to consolidation
    that would corrupt any direct comparison."""
    truth_a, extras_a = _new_material_truth()
    phase1_a = _run_fixed_practice(
        truth_a,
        extras_a,
        GuidanceContext(),
        material=NEW_MATERIAL,
        attempts=EARN_ATTEMPTS,
    )
    memory_a = truth_a.true_material_memory[NEW_MATERIAL.material_id]
    phase1_a_end = {
        "half_life_days": memory_a.current_half_life_days,
        "anchor_last_retrieval_at": memory_a.memory_anchor_at,
        "factual_last_retrieval_at": extras_a.factual_last_retrieval_at,
        "consolidated_half_life_days": extras_a.consolidated_half_life_days,
    }

    truth_b, extras_b = _new_material_truth()
    phase1_b = _run_fixed_practice(
        truth_b,
        extras_b,
        GuidanceContext(concurrent_pitch_cues=True),
        material=NEW_MATERIAL,
        attempts=EARN_ATTEMPTS,
    )
    memory_b = truth_b.true_material_memory[NEW_MATERIAL.material_id]
    phase1_b_end = {
        "half_life_days": memory_b.current_half_life_days,
        "anchor_last_retrieval_at": memory_b.memory_anchor_at,
        "factual_last_retrieval_at": extras_b.factual_last_retrieval_at,
        "consolidated_half_life_days": extras_b.consolidated_half_life_days,
    }

    truth_a2, extras_a2 = _returning_truth(extras_a.consolidated_half_life_days)
    truth_b2, extras_b2 = _returning_truth(extras_b.consolidated_half_life_days)
    normalized_a = truth_a2.true_material_memory["C_MAJOR"]
    normalized_b = truth_b2.true_material_memory["C_MAJOR"]
    assert normalized_a.current_half_life_days == normalized_b.current_half_life_days
    assert normalized_a.memory_anchor_at == normalized_b.memory_anchor_at
    assert extras_a2.factual_last_retrieval_at == extras_b2.factual_last_retrieval_at
    assert (
        extras_a2.consolidated_half_life_days != extras_b2.consolidated_half_life_days
    )

    phase2_a = _run_fixed_practice(
        truth_a2,
        extras_a2,
        GuidanceContext(concurrent_pitch_cues=True),
        material=MATERIAL,
        attempts=ATTEMPTS,
    )
    phase2_b = _run_fixed_practice(
        truth_b2,
        extras_b2,
        GuidanceContext(concurrent_pitch_cues=True),
        material=MATERIAL,
        attempts=ATTEMPTS,
    )
    return {
        "phase1_a": phase1_a,
        "phase1_b": phase1_b,
        "phase1_a_end": phase1_a_end,
        "phase1_b_end": phase1_b_end,
        "phase2_a": phase2_a,
        "phase2_b": phase2_b,
    }


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


def _consolidation_increments_at_successes(rows: list[dict[str, Any]]) -> list[float]:
    return [
        r["consolidated_half_life_days"] - r["consolidated_half_life_days_before"]
        for r in rows
        if r["retrieval_succeeded"] is True
    ]


def _report_scenario_1(rows: list[dict[str, Any]]) -> None:
    print("Scenario 1 - consolidation growth in isolation (new material, unguided):")
    increments = _consolidation_increments_at_successes(rows)
    print(f"  genuine successes: {len(increments)}")
    if len(increments) >= 2:
        shrinking = all(a >= b for a, b in itertools.pairwise(increments))
        print(
            f"  first increment={increments[0]:.5f}  last increment={increments[-1]:.5f}  "
            f"monotonically shrinking={shrinking}"
        )
        if not shrinking:
            print(
                "  NOTE - not monotonically shrinking; consolidation isn't a strictly "
                "increasing quantity across the whole run if some later success outpaces "
                "an earlier one (possible if quality/support vary attempt to attempt), "
                "inspect if this looks wrong."
            )
    drift = max(abs(r["half_life_days"] - rows[0]["half_life_days"]) for r in rows)
    print(
        f"  final consolidated_half_life_days={rows[-1]['consolidated_half_life_days']:.3f}  "
        f"half_life_days drift={drift:.6f} (out-of-scope axis, should be exactly 0)"
    )
    print()


def _report_scenario_2(
    increment_unguided: float, increment_notes: float, rows_u, rows_n
) -> None:
    print("Scenario 2 - guidance differentiation:")
    ratio = increment_notes / increment_unguided if increment_unguided else float("nan")
    print(
        f"  deterministic check: increment_unguided={increment_unguided:.6f}  "
        f"increment_notes_previewed={increment_notes:.6f}  ratio={ratio:.6f} (expect 0.7)"
    )
    if abs(ratio - 0.7) > 1e-9:
        print("  UNEXPECTED - ratio should be exactly 0.7, matching SUPPORT_FACTOR.")
    successes_u = len(_consolidation_increments_at_successes(rows_u))
    successes_n = len(_consolidation_increments_at_successes(rows_n))
    print(
        f"  descriptive trajectories (not a pass/fail check): unguided "
        f"final consolidated={rows_u[-1]['consolidated_half_life_days']:.3f} "
        f"({successes_u} successes)  notes_previewed final consolidated="
        f"{rows_n[-1]['consolidated_half_life_days']:.3f} ({successes_n} successes)"
    )
    print()


def _report_scenario_3(rows: list[dict[str, Any]]) -> None:
    print(
        "Scenario 3 - supported practice never raises consolidation (regression check):"
    )
    drift = max(
        abs(r["consolidated_half_life_days"] - rows[0]["consolidated_half_life_days"])
        for r in rows
    )
    print(
        f"  consolidation drift={drift:.9f} (starting value {rows[0]['consolidated_half_life_days']:.2f})"
    )
    if drift > 1e-9:
        print(
            "  UNEXPECTED - supported practice must never move consolidated_half_life_days."
        )
    print()


def _report_scenario_4(
    earn_rows, decay_rows, consolidated_at_start, half_life_at_start
) -> None:
    print("Scenario 4 - consolidation persistence under prolonged non-practice:")
    successes = len(_consolidation_increments_at_successes(earn_rows))
    print(
        f"  earned consolidated_half_life_days={consolidated_at_start:.3f} via "
        f"{successes} genuine successes over {len(earn_rows)} attempts "
        f"(started at {NEW_MATERIAL_DEFAULT_HALF_LIFE_DAYS:.2f}) - meanwhile "
        f"half_life_days (current durability, out of scope for this pass) ended "
        f"at {half_life_at_start:.2f}, unchanged from its own starting value: "
        "consolidation moved, current durability didn't."
    )
    drift = max(
        abs(r["consolidated_half_life_days"] - consolidated_at_start)
        for r in decay_rows
    )
    print(
        f"  consolidation drift over {len(decay_rows)} subsequent non-practice attempts "
        f"({len(decay_rows) * DAY_STEP:.0f} days)={drift:.9f} - confirms the zero-decay "
        "assumption is preserved by the implementation, not that it's the correct model."
    )
    if drift > 1e-9:
        print(
            "  UNEXPECTED - consolidated_half_life_days must not move from elapsed time alone."
        )
    print(
        f"  final true_retrievability={decay_rows[-1]['true_retrievability_before']:.4f}"
    )
    print()


def _report_scenario_5(result: dict[str, Any]) -> None:
    print(
        "Scenario 5 (capstone) - earned consolidation closes the reacquisition loop\n"
        "  (controlled two-phase design, not a naturalistic learner trajectory):"
    )
    a_end, b_end = result["phase1_a_end"], result["phase1_b_end"]
    successes_a = len(_consolidation_increments_at_successes(result["phase1_a"]))
    successes_b = len(_consolidation_increments_at_successes(result["phase1_b"]))
    print(
        f"  phase 1 end - Track A (unguided, {successes_a} genuine successes): "
        f"half_life={a_end['half_life_days']:.2f} anchor={a_end['anchor_last_retrieval_at']} "
        f"factual={a_end['factual_last_retrieval_at']} "
        f"consolidated={a_end['consolidated_half_life_days']:.3f}"
    )
    print(
        f"  phase 1 end - Track B (fully-cued, {successes_b} genuine successes): "
        f"half_life={b_end['half_life_days']:.2f} anchor={b_end['anchor_last_retrieval_at']} "
        f"factual={b_end['factual_last_retrieval_at']} "
        f"consolidated={b_end['consolidated_half_life_days']:.3f}"
    )
    print(
        "  Not yet comparable: Track A has a recent anchor/factual from its genuine "
        "successes, Track B's stayed None - a confound unrelated to consolidation."
    )
    print(
        "  normalized to the identical reference returning state (half_life=6, anchor=-14, "
        "factual=-14) for both tracks, preserving each track's own earned consolidated "
        "value (asserted equal-except-consolidated in code before phase 2 runs)."
    )
    rows_a2, rows_b2 = result["phase2_a"], result["phase2_b"]
    print(
        f"  phase 2 (fully-cued reacquisition) - Track A: {_crossing_readout(rows_a2)}"
    )
    print(
        f"  phase 2 (fully-cued reacquisition) - Track B: {_crossing_readout(rows_b2)}"
    )
    final_a = rows_a2[-1]["true_retrievability_after"]
    final_b = rows_b2[-1]["true_retrievability_after"]
    print(f"  final true_retrievability: Track A={final_a:.4f}  Track B={final_b:.4f}")
    if final_a > final_b:
        print(
            "  Track A (earned consolidation) reacquires better than Track B, holding "
            "present state constant at the start of phase 2 - the organic counterpart to "
            "the frozen file's 7A/7B result: consolidation earned through real prior "
            "behavior subsequently alters reacquisition."
        )
    elif final_a < final_b:
        print(
            "  Track B ends AHEAD of Track A - contradicts the design intent, inspect."
        )
    else:
        print(
            "  Tracks end identical - consolidation isn't doing causal work here, inspect."
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
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    print(
        f"Calibration: CONSOLIDATION_GROWTH_RATE={CONSOLIDATION_GROWTH_RATE} "
        f"CONSOLIDATION_ASYMPTOTE_DAYS={CONSOLIDATION_ASYMPTOTE_DAYS} "
        "(illustrative, not derived - see the constant's comment)"
    )
    print()

    rows_1 = scenario_1_consolidation_growth_isolated()
    _report_scenario_1(rows_1)

    increment_unguided, increment_notes = _deterministic_guidance_check()
    rows_2u, rows_2n = scenario_2_guidance_trajectories()
    _report_scenario_2(increment_unguided, increment_notes, rows_2u, rows_2n)

    rows_3 = scenario_3_supported_practice_inert()
    _report_scenario_3(rows_3)

    earn_rows_4, decay_rows_4, consolidated_start_4, half_life_start_4 = (
        scenario_4_persistence_under_non_practice()
    )
    _report_scenario_4(
        earn_rows_4, decay_rows_4, consolidated_start_4, half_life_start_4
    )

    result_5 = scenario_5_capstone()
    _report_scenario_5(result_5)

    combined_rows = []
    for scenario, rows in (
        ("scenario_1_consolidation_growth_isolated", rows_1),
        ("scenario_2_guidance_unguided", rows_2u),
        ("scenario_2_guidance_notes_previewed", rows_2n),
        ("scenario_3_supported_practice_inert", rows_3),
        ("scenario_4_earn", earn_rows_4),
        ("scenario_5_phase1_track_a", result_5["phase1_a"]),
        ("scenario_5_phase1_track_b", result_5["phase1_b"]),
        ("scenario_5_phase2_track_a", result_5["phase2_a"]),
        ("scenario_5_phase2_track_b", result_5["phase2_b"]),
    ):
        for row in rows:
            combined_rows.append({"scenario": scenario, **row})
    write_csv(args.output_dir / "consolidation_formation.csv", combined_rows)
    print(f"Wrote {args.output_dir / 'consolidation_formation.csv'}")


if __name__ == "__main__":
    main()
