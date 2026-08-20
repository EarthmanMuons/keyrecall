#!/usr/bin/env python3
"""Isolated reacquisition experiment - a diagnostic, not a fix.

Pass 4 (analysis/scheduler/stress.py) found that the "returning" profile's
seeded material (C_MAJOR, true half-life 6.0 days, last true retrieval 14
days before trial start) never has a single successful retrieval across a
full 300-attempt/150-day trial at pool_size=1. Reading synthetic.py's
sample_outcome() confirms why: the only code path that ever moves
TrueMaterialMemory.last_retrieval_at is a genuine, retrieval-observed
success. Supported practice that doesn't produce one - most of what a
decayed-memory learner produces - has zero effect on the hidden ground
truth. Conditions 1-4 below established that mechanism A (a causal
relearning/exposure effect, distinct from retrieval-evidence observation)
is required: a crude existence-proof nudge reliably broke the loop at
doses >= 0.05 and did not at 0.02.

This file's second half compares candidate mechanism SHAPES against the
same trajectory: half-life strengthening, anchor movement, and a hybrid -
locally dose-matched at the reference returning state so a faster recovery
reflects dynamical form, not an arbitrarily stronger perturbation. Still a
diagnostic, not a committed design.

Two conceptually separate candidate mechanisms, not conflated here:
    A. Relearning/exposure - supported practice causally strengthens true
       memory even without an independent-retrieval observation.
    B. Savings - previously-learned material reacquires faster than
       genuinely novel material, via retained historical state. Left open;
       a later, separate question - the new-material trajectory below is
       descriptive of this boundary, not a verdict on it.

No changes to synthetic.py, model.py, state.py, simulate.py, pipeline.py,
longitudinal.py, candidates.py, or any config.toml/params.toml.
TrueMaterialMemory.retrievability() only ever reads last_retrieval_at and
half_life_days, so there is no injection point for a genuinely separate
"memory anchor" field without modifying the shared model - the shapes below
mutate those two real fields directly as a diagnostic shortcut, standing in
for what a real implementation would represent more cleanly (e.g. a
dedicated memory_anchor_at, decoupled from the retrieval-history field it
would otherwise conflate with). That shortcut must not be mistaken for the
recommended production design.

Usage:
    python reacquisition_experiment.py
    python reacquisition_experiment.py --output-dir generated
"""

from __future__ import annotations

import argparse
import copy
import csv
import math
import random
import sys
from collections.abc import Callable
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
NEW_MATERIAL = TechnicalMaterial("G", "MAJOR")  # distinct material_id for the
# never-anchored trajectory - never touches the "returning" profile's own
# pre-seeded C_MAJOR entry
STARTING_HALF_LIFE_DAYS = 6.0
STARTING_GAP_DAYS = 14.0  # matches synthetic.py's own "returning" profile comment

SESSION_COUNT = 15
ATTEMPTS_PER_SESSION = 20
ATTEMPTS = SESSION_COUNT * ATTEMPTS_PER_SESSION  # 300
DAY_STEP = 0.5
SEED = 103  # one of Pass 4's own core_sweep seeds - condition 4 is checked
# against that actual finding, not a freshly-generated similar one

PROBE_THRESHOLD = 0.5  # "genuine test more likely than not to succeed"


def _guidance_independence(exercise: Exercise) -> int:
    if exercise.guidance.concurrent_pitch_cues:
        return 0
    if exercise.guidance.notes_previewed:
        return 1
    return 2


def _returning_truth() -> TrueLearnerProfile:
    truth = copy.deepcopy(PROFILES["returning"])
    truth.true_material_memory = {
        "C_MAJOR": TrueMaterialMemory(
            half_life_days=STARTING_HALF_LIFE_DAYS, last_retrieval_at=-STARTING_GAP_DAYS
        )
    }
    return truth


def _new_material_truth() -> TrueLearnerProfile:
    """No pre-seeded TrueMaterialMemory entry at all - relies on
    synthetic.py's own _true_memory_for() lazy-init default
    (last_retrieval_at=None, half_life_days=profile.default_half_life_days)."""
    truth = copy.deepcopy(PROFILES["returning"])
    truth.true_material_memory = {}
    return truth


def _delta_q(before: float, after: float) -> float:
    """q = -log2(retrievability) = elapsed/half_life, a common coordinate
    across shapes (half-life increments alone are meaningless for
    anchor_movement_only, whose half-life increment is always zero).
    Positive delta_q means the event reduced effective memory age."""
    return -math.log2(before) - (-math.log2(after))


# --- Candidate mechanism shapes (local to this script; not wired into
# synthetic.py) -------------------------------------------------------

SUPPORT_FACTOR = {0: 0.3, 1: 0.7, 2: 1.0}  # cued : notes_previewed : unguided
# Not "less support is worse" - generation/retrieval effort plausibly
# supplies a different memory event than pure following.

NOMINAL_FRACTION = 0.10  # the already-proven-sufficient anchor-movement
# dose from the first experiment - the common calibration target every
# shape below is matched to
HALF_LIFE_CEILING_DAYS = 60.0  # 10x the starting half-life; a diagnostic
# stand-in for "retained historical potential," not a production proposal


def _support_factor(exercise: Exercise) -> float:
    return SUPPORT_FACTOR[_guidance_independence(exercise)]


def _practice_quality(outcome: Outcome) -> float:
    """Bounded [0,1]; 0 for a failed-to-start or incomplete repetition (no
    strengthening from a fumbled attempt) - otherwise a blend of
    continuity/temporal_stability/pitch_integrity as a proxy for "engaged,
    competent repetition.\""""
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
    """Solves for the rate `r` in a saturating update
    half_life += r*(ceiling-half_life) such that ONE full-dose (support=1,
    quality=1) application produces the SAME immediate change in
    -log2(retrievability) = elapsed/half_life as anchor movement's
    `fraction` produces at the reference state (elapsed=STARTING_GAP_DAYS,
    half_life=half_life_0).
        r = half_life_0 * fraction / ((1 - fraction) * (ceiling - half_life_0))
    """
    return half_life_0 * fraction / ((1.0 - fraction) * (ceiling - half_life_0))


ANCHOR_MOVEMENT_RATE = NOMINAL_FRACTION
HALF_LIFE_GROWTH_RATE = _matched_saturating_half_life_rate(
    NOMINAL_FRACTION, STARTING_HALF_LIFE_DAYS, HALF_LIFE_CEILING_DAYS
)
HYBRID_ANCHOR_RATE = NOMINAL_FRACTION / 2  # half-dose via each pathway
HYBRID_HALF_LIFE_RATE = _matched_saturating_half_life_rate(
    NOMINAL_FRACTION / 2, STARTING_HALF_LIFE_DAYS, HALF_LIFE_CEILING_DAYS
)


def shape_half_life_only(
    true_memory: TrueMaterialMemory, exercise: Exercise, now: float, quality: float
) -> None:
    gain = HALF_LIFE_GROWTH_RATE * _support_factor(exercise) * quality
    true_memory.half_life_days += gain * (
        HALF_LIFE_CEILING_DAYS - true_memory.half_life_days
    )
    # last_retrieval_at never touched.


def shape_anchor_movement_only(
    true_memory: TrueMaterialMemory, exercise: Exercise, now: float, quality: float
) -> None:
    if true_memory.last_retrieval_at is None:
        return  # no anchor exists yet to move
    fraction = ANCHOR_MOVEMENT_RATE * _support_factor(exercise) * quality
    true_memory.last_retrieval_at += fraction * (now - true_memory.last_retrieval_at)


def shape_hybrid(
    true_memory: TrueMaterialMemory, exercise: Exercise, now: float, quality: float
) -> None:
    support = _support_factor(exercise)
    true_memory.half_life_days += (
        HYBRID_HALF_LIFE_RATE
        * support
        * quality
        * (HALF_LIFE_CEILING_DAYS - true_memory.half_life_days)
    )
    if true_memory.last_retrieval_at is not None:
        fraction = HYBRID_ANCHOR_RATE * support * quality
        true_memory.last_retrieval_at += fraction * (
            now - true_memory.last_retrieval_at
        )


SHAPES: dict[str, Callable[[TrueMaterialMemory, Exercise, float, float], None]] = {
    "half_life_only": shape_half_life_only,
    "anchor_movement_only": shape_anchor_movement_only,
    "hybrid": shape_hybrid,
}


def _apply_shape(
    shape: Callable[[TrueMaterialMemory, Exercise, float, float], None] | None,
    true_memory: TrueMaterialMemory,
    exercise: Exercise,
    outcome: Outcome,
    now: float,
) -> None:
    """Applies the shape only for productive practice (quality>0) that did
    NOT already produce a genuine retrieval success - a real success goes
    through the existing, unmodified sample_outcome() transition already;
    applying an instructional update on top of it would double-count.
    Isolates exactly the missing pathway: productive practice WITHOUT a
    genuine success."""
    if shape is None:
        return
    quality = _practice_quality(outcome)
    if quality <= 0.0 or outcome.retrieval_succeeded is True:
        return
    shape(true_memory, exercise, now, quality)


def _verify_matched_initial_dose() -> None:
    """Prints each shape's actual immediate delta_q at the reference
    returning state for one full-strength (support=1, quality=1)
    application - confirms the calibration is doing what it claims,
    including for the hybrid, whose two composed transformations don't
    algebraically guarantee an identical combined delta_q to the
    standalone shapes (they interact nonlinearly: moving the anchor
    changes `elapsed`, which changes what the already-applied half-life
    change did to q)."""
    print("Matched initial dose check (delta_q at the reference state, full strength):")
    unguided = fixed_exercise(MATERIAL, "RIGHT")  # support_factor=1.0
    for name, shape in SHAPES.items():
        memory = TrueMaterialMemory(
            half_life_days=STARTING_HALF_LIFE_DAYS, last_retrieval_at=-STARTING_GAP_DAYS
        )
        before = memory.retrievability(0.0, 0.4)
        shape(memory, unguided, 0.0, 1.0)
        after = memory.retrievability(0.0, 0.4)
        print(f"  {name:<24} delta_q={_delta_q(before, after):.4f}")
    print()


# --- Row construction --------------------------------------------------


def _row(
    attempt_index: int,
    at_days: float,
    before: float,
    after: float,
    half_life_days: float,
    state,
    learner_params: LearnerParams,
    exercise: Exercise,
    outcome: Outcome,
    challenge_bypass: str | None,
) -> dict[str, Any]:
    material_id = exercise.material.material_id
    belief = state.material_memory.get(material_id)
    model_belief = (
        belief.retrievability_or_prior(at_days, learner_params)
        if belief is not None
        else learner_params.material_memory.prior_retrievability
    )
    return {
        "attempt_index": attempt_index,
        "at_days": at_days,
        "true_retrievability_before": before,
        "true_retrievability_after": after,
        "delta_q": _delta_q(before, after),
        "half_life_days": half_life_days,
        "model_belief_retrievability": model_belief,
        "guidance_independence": _guidance_independence(exercise),
        "retrieval_succeeded": outcome.retrieval_succeeded,
        "started": outcome.started,
        "completed": outcome.completed,
        "challenge_bypass": challenge_bypass,
    }


# --- Conditions 1-3: no scheduler, no shape -----------------------------


def condition_no_practice_rows() -> list[dict[str, Any]]:
    """Pure decay baseline - no attempts at all, TrueMaterialMemory.
    retrievability() evaluated at 300 points spaced by DAY_STEP across the
    same 150-day horizon, for direct comparison against the
    true_retrievability_before column of the practice-based conditions."""
    truth = _returning_truth()
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
                "model_belief_retrievability": None,
                "guidance_independence": None,
                "retrieval_succeeded": None,
                "started": None,
                "completed": None,
                "challenge_bypass": None,
            }
        )
    return rows


def _run_fixed_practice(
    learner_params: LearnerParams,
    guidance: GuidanceContext,
    *,
    truth: TrueLearnerProfile | None = None,
    material: TechnicalMaterial = MATERIAL,
    shape: Callable[[TrueMaterialMemory, Exercise, float, float], None] | None = None,
) -> list[dict[str, Any]]:
    truth = truth if truth is not None else _returning_truth()
    state = initial_state(truth, learner_params, now=0.0)
    rng = random.Random(SEED)
    now = 0.0
    rows = []
    material_id = material.material_id
    for i in range(ATTEMPTS):
        now += DAY_STEP
        state.propagate(now, learner_params)
        exercise = fixed_exercise(material, "RIGHT", guidance=guidance)
        true_memory = truth.true_material_memory.get(material_id)
        if true_memory is None:
            # lazy-init default, mirrors state.py's own material_memory_for()
            true_memory = TrueMaterialMemory(
                half_life_days=truth.default_half_life_days
            )
            truth.true_material_memory[material_id] = true_memory
        before = true_memory.retrievability(now, truth.memory_prior)
        prediction = predicted_success(state, exercise, now, learner_params)
        outcome = sample_outcome(truth, exercise, now, rng)
        weights = evidence_weights(exercise, outcome)
        update(state, exercise, outcome, weights, prediction, now, learner_params)
        _apply_shape(shape, true_memory, exercise, outcome, now)
        after = true_memory.retrievability(now, truth.memory_prior)
        rows.append(
            _row(
                i,
                now,
                before,
                after,
                true_memory.half_life_days,
                state,
                learner_params,
                exercise,
                outcome,
                None,
            )
        )
    return rows


def condition_fixed_cued_rows(learner_params: LearnerParams) -> list[dict[str, Any]]:
    """Under the current model (shape=None) this is provably identical to
    Condition 1 on the true-retrievability column (retrieval_observed() is
    False throughout, so sample_outcome() never touches last_retrieval_at)
    - included to demonstrate that empirically rather than only assert
    it."""
    return _run_fixed_practice(
        learner_params, GuidanceContext(concurrent_pitch_cues=True)
    )


def condition_fixed_notes_previewed_rows(
    learner_params: LearnerParams,
) -> list[dict[str, Any]]:
    """Retrieval-opportunity-FREQUENCY control, not a test of relearning
    from supported practice. retrieval_observed() is True here, so
    retrieval_succeeded is genuinely tested every attempt, unthrottled by
    any probe interval. If this eventually recovers, it demonstrates "more
    frequent genuine testing can escape the state under the EXISTING
    model" - useful, but not evidence for a relearning/exposure effect: it
    uses the exact same already-established success mechanism as
    everything else, just tests it far more often than the scheduler's own
    ~1-in-10 cadence does."""
    return _run_fixed_practice(learner_params, GuidanceContext(notes_previewed=True))


# --- Condition 4 / mechanism-shape trajectory 1: scheduler-driven -------


def condition_scheduler_driven_rows(
    truth: TrueLearnerProfile,
    learner_params: LearnerParams,
    scheduler_params: SchedulerParams,
    *,
    shape: Callable[[TrueMaterialMemory, Exercise, float, float], None] | None = None,
) -> list[dict[str, Any]]:
    """shape=None IS Condition 4 (the reference reproduction) - not a
    separate code path; every shape comparison shares this exact loop, so
    a difference in outcome can only be attributed to the shape itself.
    Reproduces Pass 4's own session structure exactly: 15 sessions x 20
    attempts, agent.new_session() between them, one rng threaded across
    the whole trial - run_pipeline()/select_scheduler_choice()/
    repetition_guard() consume no randomness, only sample_outcome() does,
    so shape=None reproduces Pass 4's actual seed=103 trajectory attempt
    for attempt. NoAdmittedCandidate is allowed to propagate and end the
    trial early - the row count itself is part of the finding."""
    instrument = InstrumentProfile()
    agent = SchedulerAgent(
        instrument, [MATERIAL], scheduler_params, learner_params, top_n=1
    )
    state = initial_state(truth, learner_params, now=0.0)
    rng = random.Random(SEED)
    now = 0.0
    rows: list[dict[str, Any]] = []
    material_id = MATERIAL.material_id

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
            update(state, exercise, outcome, weights, prediction, now, learner_params)
            _apply_shape(shape, true_memory, exercise, outcome, now)
            agent.on_outcome(exercise, outcome, now)
            after = true_memory.retrievability(now, truth.memory_prior)
            rows.append(
                _row(
                    len(rows),
                    now,
                    before,
                    after,
                    true_memory.half_life_days,
                    state,
                    learner_params,
                    exercise,
                    outcome,
                    agent.records[-1].selected.challenge_bypass,
                )
            )
    return rows


def _run_scheduler_condition_safe(
    learner_params: LearnerParams,
    scheduler_params: SchedulerParams,
    shape: Callable[[TrueMaterialMemory, Exercise, float, float], None] | None,
) -> tuple[list[dict[str, Any]], str]:
    truth = _returning_truth()
    try:
        rows = condition_scheduler_driven_rows(
            truth, learner_params, scheduler_params, shape=shape
        )
        return rows, ""
    except NoAdmittedCandidate as exc:
        return [], f"NoAdmittedCandidate: {exc}"


# --- Output and report ---------------------------------------------------


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("")
        return
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def _summarize_scheduler_condition(rows: list[dict[str, Any]]) -> dict[str, Any]:
    bootstrap_count = sum(1 for r in rows if r["challenge_bypass"] == "bootstrap_probe")
    recovery_count = sum(1 for r in rows if r["challenge_bypass"] == "recovery")
    successes = sum(1 for r in rows if r["retrieval_succeeded"] is True)
    max_cued_run, current_run = 0, 0
    for r in rows:
        if r["guidance_independence"] == 0:
            current_run += 1
            max_cued_run = max(max_cued_run, current_run)
        else:
            current_run = 0
    first_success_attempt = next(
        (r["attempt_index"] for r in rows if r["retrieval_succeeded"] is True), None
    )
    first_probe_threshold_attempt = next(
        (
            r["attempt_index"]
            for r in rows
            if r["true_retrievability_before"] is not None
            and r["true_retrievability_before"] >= PROBE_THRESHOLD
        ),
        None,
    )
    return {
        "attempts_reached": len(rows),
        "bootstrap_probe_count": bootstrap_count,
        "recovery_count": recovery_count,
        "successes": successes,
        "max_consecutive_cued_run": max_cued_run,
        "first_success_attempt": first_success_attempt,
        "first_probe_threshold_attempt": first_probe_threshold_attempt,
    }


def _diminishing_returns_readout(rows: list[dict[str, Any]]) -> str:
    """Mean delta_q over the first 10 qualifying reps (delta_q != 0) vs.
    the last 10 before crossing PROBE_THRESHOLD (or the last 10 overall if
    it never crosses) - a genuinely saturating shape should show this
    shrink."""
    qualifying = [r for r in rows if r["delta_q"] not in (0.0, None)]
    if len(qualifying) < 2:
        return "insufficient qualifying reps"
    threshold_idx = next(
        (
            i
            for i, r in enumerate(qualifying)
            if r["true_retrievability_before"] >= PROBE_THRESHOLD
        ),
        len(qualifying),
    )
    before_window = qualifying[:10]
    after_window = (
        qualifying[max(0, threshold_idx - 10) : threshold_idx] or qualifying[-10:]
    )
    mean_first = sum(r["delta_q"] for r in before_window) / len(before_window)
    mean_last = sum(r["delta_q"] for r in after_window) / len(after_window)
    return f"mean delta_q first10={mean_first:.5f} last10={mean_last:.5f}"


def _shape_trajectory_summary(rows: list[dict[str, Any]]) -> str:
    threshold_attempt = next(
        (
            r["attempt_index"]
            for r in rows
            if r["true_retrievability_before"] >= PROBE_THRESHOLD
        ),
        None,
    )
    final_half_life = rows[-1]["half_life_days"] if rows else None
    crossed = (
        f"crossed p>={PROBE_THRESHOLD} at attempt {threshold_attempt}"
        if threshold_attempt is not None
        else f"never crossed p>={PROBE_THRESHOLD}"
    )
    return (
        f"{crossed:<32} final_half_life_days={final_half_life:.2f}  "
        f"{_diminishing_returns_readout(rows)}"
    )


def report(
    all_rows: dict[str, list[dict[str, Any]]],
    shape_rows: dict[str, dict[str, list[dict[str, Any]]]],
) -> None:
    no_practice = all_rows["no_practice"]
    fixed_cued = all_rows["fixed_cued"]
    print("Condition 1 vs. 2 (no_practice vs. fixed_cued), true_retrievability_before:")
    divergence = next(
        (
            i
            for i, (a, b) in enumerate(zip(no_practice, fixed_cued, strict=True))
            if abs(a["true_retrievability_before"] - b["true_retrievability_before"])
            > 1e-9
        ),
        None,
    )
    if divergence is None:
        print("  identical at every attempt, as expected under the current model.")
    else:
        print(f"  DIVERGES at attempt {divergence} - unexpected, investigate.")
    print()

    fixed_np = all_rows["fixed_notes_previewed"]
    first_np_success = next(
        (r["attempt_index"] for r in fixed_np if r["retrieval_succeeded"] is True), None
    )
    print(
        "Condition 3 (fixed_notes_previewed) - retrieval-opportunity-FREQUENCY control:"
    )
    if first_np_success is None:
        print(f"  no genuine success across {len(fixed_np)} attempts.")
    else:
        print(
            f"  first genuine success at attempt {first_np_success} "
            f"(day {fixed_np[first_np_success]['at_days']:.1f}) - demonstrates more frequent "
            "testing can escape the state under the EXISTING model; not evidence for a "
            "relearning/exposure effect."
        )
    print()

    print("Condition 4 (scheduler_driven, shape=None) - Pass 4 seed=103 reproduction:")
    condition4 = all_rows["scheduler_driven_reference"]
    summary = _summarize_scheduler_condition(condition4)
    for key, value in summary.items():
        print(f"  {key:<28} {value}")
    print(
        "  first 15 attempts (guidance_independence, challenge_bypass, retrieval_succeeded):"
    )
    for r in condition4[:15]:
        print(
            f"    attempt={r['attempt_index']:<3} indep={r['guidance_independence']} "
            f"bypass={r['challenge_bypass']} retrieval_succeeded={r['retrieval_succeeded']}"
        )
    print()

    print(
        "probe N: p(success) for Condition 4 (every non-cued, retrieval-observing attempt):"
    )
    probes = [r for r in condition4 if r["guidance_independence"] != 0]
    for r in probes:
        print(
            f"  attempt={r['attempt_index']:<3} bypass={r['challenge_bypass']:<16} "
            f"p(success)={r['true_retrievability_before']:.4f} "
            f"retrieval_succeeded={r['retrieval_succeeded']}"
        )
    print()

    _verify_matched_initial_dose()

    print("Mechanism-shape comparison, trajectory 1 (scheduler-driven, matched dose):")
    for name in SHAPES:
        rows = shape_rows["scheduler_driven"][name]
        if not rows:
            print(f"  {name:<24} NoAdmittedCandidate - trial ended early")
            continue
        print(f"  {name:<24} {_shape_trajectory_summary(rows)}")
    print()

    print(
        "Mechanism-shape comparison, trajectory 2 (fixed fully-cued on returning material):"
    )
    for name in SHAPES:
        rows = shape_rows["fixed_cued_returning"][name]
        print(f"  {name:<24} {_shape_trajectory_summary(rows)}")
    print()

    print(
        "New-material trajectory (fixed fully-cued, never-anchored - descriptive, "
        "not pass/fail):"
    )
    for name in SHAPES:
        rows = shape_rows["new_material_fixed_cued"][name]
        final_half_life = rows[-1]["half_life_days"]
        never_anchored = all(r["retrieval_succeeded"] is not True for r in rows)
        print(
            f"  {name:<24} last_retrieval_at stayed None: {never_anchored}  "
            f"final half_life_days={final_half_life:.2f} "
            f"(started at {rows[0]['half_life_days']:.2f}) - if anchored now by a genuine "
            f"success, this would be the starting half-life."
        )
    print(
        "  Open question this surfaces, not answered here: should supported practice build\n"
        "  first-time memory the same way it rebuilds decayed memory, and if reacquisition\n"
        "  should be faster than initial acquisition, what historical gate (mechanism B)\n"
        "  would produce that difference?"
    )


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

    all_rows: dict[str, list[dict[str, Any]]] = {
        "no_practice": condition_no_practice_rows(),
        "fixed_cued": condition_fixed_cued_rows(learner_params),
        "fixed_notes_previewed": condition_fixed_notes_previewed_rows(learner_params),
    }
    rows, error = _run_scheduler_condition_safe(learner_params, scheduler_params, None)
    if error:
        print(f"scheduler_driven_reference: {error}")
    all_rows["scheduler_driven_reference"] = rows

    shape_rows: dict[str, dict[str, list[dict[str, Any]]]] = {
        "scheduler_driven": {},
        "fixed_cued_returning": {},
        "new_material_fixed_cued": {},
    }
    for name, shape in SHAPES.items():
        rows, error = _run_scheduler_condition_safe(
            learner_params, scheduler_params, shape
        )
        if error:
            print(f"scheduler_driven[{name}]: {error}")
        shape_rows["scheduler_driven"][name] = rows

        shape_rows["fixed_cued_returning"][name] = _run_fixed_practice(
            learner_params, GuidanceContext(concurrent_pitch_cues=True), shape=shape
        )
        shape_rows["new_material_fixed_cued"][name] = _run_fixed_practice(
            learner_params,
            GuidanceContext(concurrent_pitch_cues=True),
            truth=_new_material_truth(),
            material=NEW_MATERIAL,
            shape=shape,
        )

    combined_rows = []
    for condition, rows in all_rows.items():
        for row in rows:
            combined_rows.append({"condition": condition, **row})
    for trajectory, by_shape in shape_rows.items():
        for shape_name, rows in by_shape.items():
            for row in rows:
                combined_rows.append(
                    {"condition": f"{trajectory}__{shape_name}", **row}
                )
    write_csv(args.output_dir / "reacquisition_experiment.csv", combined_rows)

    report(all_rows, shape_rows)

    print()
    print(f"Wrote {args.output_dir / 'reacquisition_experiment.csv'}")


if __name__ == "__main__":
    main()
