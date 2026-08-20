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
truth. This experiment isolates that question, with scheduler policy
removed as a variable for Conditions 1-3, and the real scheduler used only
as a reference reproduction (Condition 4) and one perturbation target
(Condition 5's dose sweep).

Two conceptually separate candidate mechanisms, not conflated here:
    A. Relearning/exposure - supported practice causally strengthens true
       memory even without an independent-retrieval observation. This
       experiment tests only whether A ALONE is sufficient to break the
       pathological loop - not its correct mathematical form.
    B. Savings - previously-learned material reacquires faster than
       genuinely novel material, via retained historical state. Left open;
       a later, separate question.

No changes to synthetic.py, model.py, state.py, simulate.py, pipeline.py,
longitudinal.py, candidates.py, or any config.toml/params.toml. The
"hypothetical relearning nudge" below is local to this script only, never
wired into the shared model.

Usage:
    python reacquisition_experiment.py
    python reacquisition_experiment.py --output-dir generated
"""

from __future__ import annotations

import argparse
import copy
import csv
import random
import sys
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
STARTING_HALF_LIFE_DAYS = 6.0
STARTING_GAP_DAYS = 14.0  # matches synthetic.py's own "returning" profile comment

SESSION_COUNT = 15
ATTEMPTS_PER_SESSION = 20
ATTEMPTS = SESSION_COUNT * ATTEMPTS_PER_SESSION  # 300
DAY_STEP = 0.5
SEED = 103  # one of Pass 4's own core_sweep seeds - condition 4 is checked
# against that actual finding, not a freshly-generated similar one

# Existence-proof dial, not a proposed production value: 0.0 IS Condition 4
# (the reference reproduction); the rest are Condition 5's dose sweep.
ORACLE_DOSES = (0.0, 0.02, 0.05, 0.10, 0.20)
ORACLE_NOMINAL_DOSE = 0.10

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


def _hypothetical_relearning_nudge(
    truth: TrueLearnerProfile, material_id: str, now: float, fraction: float
) -> None:
    """Applies only to completed, started attempts - a well-executed guided
    repetition, not "retrieval_succeeded" (would collapse this into the
    existing mechanism) and not merely "attempted" (would reward a fumbled
    rep as much as a clean one). Moves last_retrieval_at partially toward
    `now` rather than resetting it outright - a single genuine independent
    success still fully resets it (unchanged, real mechanism); this only
    ever produces a partial, cumulative effect. Never touches
    Outcome.retrieval_succeeded/retrieval_observed - only the hidden
    ground truth's own evolution rule changes."""
    true_memory = truth.true_material_memory[material_id]
    true_memory.last_retrieval_at += fraction * (now - true_memory.last_retrieval_at)


def _row(
    attempt_index: int,
    at_days: float,
    before: float,
    after: float,
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
        "model_belief_retrievability": model_belief,
        "guidance_independence": _guidance_independence(exercise),
        "retrieval_succeeded": outcome.retrieval_succeeded,
        "started": outcome.started,
        "completed": outcome.completed,
        "challenge_bypass": challenge_bypass,
    }


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
    learner_params: LearnerParams, guidance: GuidanceContext
) -> list[dict[str, Any]]:
    truth = _returning_truth()
    state = initial_state(truth, learner_params, now=0.0)
    rng = random.Random(SEED)
    now = 0.0
    rows = []
    material_id = MATERIAL.material_id
    for i in range(ATTEMPTS):
        now += DAY_STEP
        state.propagate(now, learner_params)
        exercise = fixed_exercise(MATERIAL, "RIGHT", guidance=guidance)
        true_memory = truth.true_material_memory[material_id]
        before = true_memory.retrievability(now, truth.memory_prior)
        prediction = predicted_success(state, exercise, now, learner_params)
        outcome = sample_outcome(truth, exercise, now, rng)
        weights = evidence_weights(exercise, outcome)
        update(state, exercise, outcome, weights, prediction, now, learner_params)
        after = true_memory.retrievability(now, truth.memory_prior)
        rows.append(
            _row(i, now, before, after, state, learner_params, exercise, outcome, None)
        )
    return rows


def condition_fixed_cued_rows(learner_params: LearnerParams) -> list[dict[str, Any]]:
    """Under the current model this is provably identical to Condition 1
    on the true-retrievability column (retrieval_observed() is False
    throughout, so sample_outcome() never touches last_retrieval_at) -
    included to demonstrate that empirically rather than only assert it."""
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


def condition_scheduler_driven_rows(
    truth: TrueLearnerProfile,
    learner_params: LearnerParams,
    scheduler_params: SchedulerParams,
    *,
    oracle_fraction: float = 0.0,
) -> list[dict[str, Any]]:
    """oracle_fraction=0.0 IS Condition 4 (the reference reproduction) -
    not a separate function; Conditions 4 and 5 share this exact code
    path, so a difference in outcome can only be attributed to the nudge
    itself. Reproduces Pass 4's own session structure exactly: 15 sessions
    x 20 attempts, agent.new_session() between them, one rng threaded
    across the whole trial - run_pipeline()/select_scheduler_choice()/
    repetition_guard() consume no randomness, only sample_outcome() does,
    so this reproduces Pass 4's actual seed=103 trajectory attempt for
    attempt, not just an analogous one. NoAdmittedCandidate is allowed to
    propagate and end the trial early - the row count itself is part of
    the finding, not something to paper over with retry machinery."""
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
            if oracle_fraction and outcome.started and outcome.completed:
                _hypothetical_relearning_nudge(truth, material_id, now, oracle_fraction)
            agent.on_outcome(exercise, outcome, now)
            after = true_memory.retrievability(now, truth.memory_prior)
            rows.append(
                _row(
                    len(rows),
                    now,
                    before,
                    after,
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
    oracle_fraction: float,
) -> tuple[list[dict[str, Any]], str]:
    truth = _returning_truth()
    try:
        rows = condition_scheduler_driven_rows(
            truth, learner_params, scheduler_params, oracle_fraction=oracle_fraction
        )
        return rows, ""
    except NoAdmittedCandidate as exc:
        return [], f"NoAdmittedCandidate: {exc}"


# --- Output and report -------------------------------------------------


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


def report(all_rows: dict[str, list[dict[str, Any]]]) -> None:
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

    print(
        "Condition 4 (scheduler_driven, oracle_fraction=0.0) - Pass 4 seed=103 reproduction:"
    )
    condition4 = all_rows["scheduler_driven_oracle_0.0"]
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

    print("Dose sweep (Condition 4 + Condition 5), scheduler_driven_oracle_{dose}:")
    for dose in ORACLE_DOSES:
        rows = all_rows[f"scheduler_driven_oracle_{dose}"]
        summary = _summarize_scheduler_condition(rows)
        label = "Condition 4 (reference)" if dose == 0.0 else f"dose={dose}"
        crossed = (
            f"crossed p>={PROBE_THRESHOLD} at attempt {summary['first_probe_threshold_attempt']}"
            if summary["first_probe_threshold_attempt"] is not None
            else f"never crossed p>={PROBE_THRESHOLD}"
        )
        succeeded = (
            f"first success at attempt {summary['first_success_attempt']}"
            if summary["first_success_attempt"] is not None
            else "no genuine success"
        )
        print(
            f"  {label:<26} attempts_reached={summary['attempts_reached']:<4} "
            f"successes={summary['successes']:<3} {crossed:<32} {succeeded}"
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
    for dose in ORACLE_DOSES:
        rows, error = _run_scheduler_condition_safe(
            learner_params, scheduler_params, dose
        )
        if error:
            print(f"scheduler_driven_oracle_{dose}: {error}")
        all_rows[f"scheduler_driven_oracle_{dose}"] = rows

    combined_rows = []
    for condition, rows in all_rows.items():
        for row in rows:
            combined_rows.append({"condition": condition, **row})
    write_csv(args.output_dir / "reacquisition_experiment.csv", combined_rows)

    report(all_rows)

    print()
    print(f"Wrote {args.output_dir / 'reacquisition_experiment.csv'}")


if __name__ == "__main__":
    main()
