#!/usr/bin/env python3
"""Pass 4: broad stochastic generalization/stress characterization
(docs/learner-model/04-v1-scheduler.md).

Pass 2 (scenarios.py) says: these known mechanisms work in deliberately
constructed cases. Pass 3 (sensitivity.py) says: those conclusions aren't
artifacts of one exact configuration. Pass 4 says: now stop constructing
trajectories around the mechanisms and see what the scheduler actually
does - broad, long, heterogeneous trajectories outside the exact scenarios
that shaped the mechanisms in the first place.

Two different kinds of output, deliberately not one battery of pass/fail
assertions:
    descriptive metrics   collected across every trial, inspected for
                          tails/anomalies by a human - see stress_trials.csv
                          and stress_materials.csv. Not evidence of a bug by
                          themselves.
    universal hard        checked continuously and exhaustively across
    properties (#1-#6)    every trial - genuine assertions, distinct from
                          the descriptive metrics. See stress_violations.csv
                          (empty = clean).

Does not import scenarios.py - no Pass-2 oracle reuse this pass, and no
retuning of config.toml or changes to pipeline.py/candidates.py/
longitudinal.py unless a genuine structural failure is found (same rule as
Pass 3). Weighted R/I/V/G ranking is out of scope.

Usage:
    python stress.py
    python stress.py --output-dir generated
"""

from __future__ import annotations

import argparse
import copy
import csv
import random
import sys
from collections import Counter
from dataclasses import dataclass
from itertools import pairwise
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "learner-model"))

from candidates import InstrumentProfile, generate_candidates
from config import Params as SchedulerParams
from config import load_params as load_scheduler_params
from domain import GuidanceContext
from longitudinal import AttemptRecord, NoAdmittedCandidate, SchedulerAgent
from model import Outcome, Prediction, evidence_weights, predicted_success, update
from params import Params as LearnerParams
from params import load_params as load_learner_params
from pipeline import (
    CandidateTrace,
    StageStatus,
    _bootstrap_probe_eligible,
    _guidance_probe_eligible,
    recovery_target,
    run_pipeline,
)
from simulate import MATERIALS, fixed_exercise, initial_state, run
from state import LearnerState
from synthetic import PROFILES, TrueLearnerProfile

CORE_PROFILES = tuple(sorted(PROFILES))
CORE_POOL_SIZES = (1, 3, 7)
CORE_SEEDS = tuple(range(100, 110))
CORE_SESSION_COUNT = 15
CORE_ATTEMPTS_PER_SESSION = 20
DAY_STEP = 0.5

# Exhaustive, not sampled: property #5 needs to know every REACHED
# candidate's material, not just the top few by rank. runners_up is
# otherwise identical to longitudinal.py's own diagnostic list - a plain
# sort over already-computed traces, not extra pipeline work - so an
# unbounded top_n costs a bigger sort and a bigger per-attempt trace list,
# not a bigger computation. Memory is trial-scoped: agent/records are
# discarded after each trial's rows are extracted (run_trial()), so this
# doesn't accumulate across the sweep.
EXHAUSTIVE_TOP_N = 10_000

SECONDARY_PROFILES = ("beginner", "advanced")
SECONDARY_SEEDS = tuple(range(5))
COMPETENCY_OFFSETS = (-1.0, 1.0)
RESTRICTED_KEY_COUNT = 12  # forces octaves=1 only (2*12=24 > 12)

MIXED_MEMORY_PROFILES = ("technique_strong_memory_weak", "memory_strong_technique_weak")
MIXED_MEMORY_CONDITIONS = (
    "unseen",
    "recently_successful",
    "stale",
    "repeatedly_failed",
    "never_successful",
)
BOOTSTRAP_TRAP_BOUND = 30  # cf. scenarios.py's 25, bumped for ~4x longer trials


def _guidance_independence(exercise) -> int:
    if exercise.guidance.concurrent_pitch_cues:
        return 0
    if exercise.guidance.notes_previewed:
        return 1
    return 2


@dataclass(frozen=True)
class TrialSpec:
    trial_kind: (
        str  # core_sweep | competency_override | restricted_instrument | mixed_memory
    )
    profile_name: str
    pool_size: int
    material_ids: tuple[str, ...]
    seed: int
    instrument_key_count: int = 88
    competency_offset: float = 0.0
    mixed_memory_condition_by_material: dict[str, str] | None = None
    session_count: int = CORE_SESSION_COUNT
    attempts_per_session: int = CORE_ATTEMPTS_PER_SESSION


def build_core_specs() -> list[TrialSpec]:
    specs = []
    for profile_name in CORE_PROFILES:
        for pool_size in CORE_POOL_SIZES:
            material_ids = tuple(m.material_id for m in MATERIALS[:pool_size])
            for seed in CORE_SEEDS:
                specs.append(
                    TrialSpec(
                        trial_kind="core_sweep",
                        profile_name=profile_name,
                        pool_size=pool_size,
                        material_ids=material_ids,
                        seed=seed,
                    )
                )
    return specs


def build_competency_override_specs() -> list[TrialSpec]:
    specs = []
    for profile_name in SECONDARY_PROFILES:
        for offset in COMPETENCY_OFFSETS:
            material_ids = tuple(m.material_id for m in MATERIALS[:3])
            for seed in SECONDARY_SEEDS:
                specs.append(
                    TrialSpec(
                        trial_kind="competency_override",
                        profile_name=profile_name,
                        pool_size=3,
                        material_ids=material_ids,
                        seed=seed,
                        competency_offset=offset,
                    )
                )
    return specs


def build_restricted_instrument_specs() -> list[TrialSpec]:
    specs = []
    for profile_name in SECONDARY_PROFILES:
        material_ids = tuple(m.material_id for m in MATERIALS[:3])
        for seed in SECONDARY_SEEDS:
            specs.append(
                TrialSpec(
                    trial_kind="restricted_instrument",
                    profile_name=profile_name,
                    pool_size=3,
                    material_ids=material_ids,
                    seed=seed,
                    instrument_key_count=RESTRICTED_KEY_COUNT,
                )
            )
    return specs


def build_mixed_memory_specs() -> list[TrialSpec]:
    specs = []
    for profile_name in MIXED_MEMORY_PROFILES:
        materials = MATERIALS[: len(MIXED_MEMORY_CONDITIONS)]
        material_ids = tuple(m.material_id for m in materials)
        condition_by_material = dict(
            zip(material_ids, MIXED_MEMORY_CONDITIONS, strict=True)
        )
        for seed in SECONDARY_SEEDS:
            specs.append(
                TrialSpec(
                    trial_kind="mixed_memory",
                    profile_name=profile_name,
                    pool_size=len(materials),
                    material_ids=material_ids,
                    seed=seed,
                    mixed_memory_condition_by_material=condition_by_material,
                )
            )
    return specs


# --- Mixed-memory-state pre-seeding -----------------------------------

FORCED_SUCCESS = Outcome(
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
FORCED_FAILURE = Outcome(
    started=True,
    retrieval_succeeded=False,
    completed=False,
    material_retrieval=0.0,
    pitch_integrity=0.2,
    continuity=0.2,
    temporal_stability=0.2,
    achieved_tempo_ratio=0.2,
    topology_accuracy=0.5,
)

# Relative to trial start (T=0.0). Grounded in the actually-loaded params at
# call time (see seed_mixed_memory_state), not hardcoded numeric bounds -
# these offsets are chosen to land comfortably inside/outside the guidance-
# probe threshold and initial half-life, not to sit exactly on the boundary.
_PRESEED_EVENTS: dict[str, tuple[tuple[float, bool], ...]] = {
    # (offset_days, is_success)
    "unseen": (),
    "recently_successful": ((-1.5, True),),
    "stale": ((-18.0, True),),
    "repeatedly_failed": (
        (-10.0, True),
        (-8.0, False),
        (-6.0, False),
        (-4.0, False),
        (-2.0, False),
    ),
    "never_successful": ((-11.0, False), (-9.0, False), (-7.0, False)),
}


def _apply_forced_outcome(
    state: LearnerState,
    exercise,
    outcome: Outcome,
    now: float,
    learner_params: LearnerParams,
) -> None:
    """propagate -> predict -> weight -> update, matching simulate.run()'s
    own loop body and analyze.py's memory_spacing_sensitivity_rows()
    precedent - a real Outcome forced through the real model, not hand-set
    MaterialMemoryState fields."""
    state.propagate(now, learner_params)
    prediction = predicted_success(state, exercise, now, learner_params)
    weights = evidence_weights(exercise, outcome)
    update(state, exercise, outcome, weights, prediction, now, learner_params)


def _verify_preseed_condition(
    state: LearnerState,
    material_id: str,
    condition: str,
    now: float,
    scheduler_params: SchedulerParams,
    learner_params: LearnerParams,
) -> None:
    """Verifies the BEHAVIORALLY meaningful predicate for each condition,
    via the real eligibility functions the scheduler itself uses - not just
    that some timestamp looks roughly right. A future config.toml/
    params.toml change could otherwise silently break a fixture and produce
    quietly-mislabeled trials. Raises loudly (test-setup-error style, not a
    soft finding) if violated."""
    # Both eligibility functions require notes_previewed guidance
    # specifically (guidance_probe/bootstrap_probe only ever offer that one
    # step-down realization, §6.2/§6.4) - an unguided probe would read as
    # ineligible unconditionally, regardless of elapsed time.
    probe_exercise = fixed_exercise(
        next(m for m in MATERIALS if m.material_id == material_id),
        "RIGHT",
        guidance=GuidanceContext(notes_previewed=True),
    )
    memory_state = state.material_memory.get(material_id)

    if condition == "unseen":
        if memory_state is not None:
            raise AssertionError(
                f"{material_id}: expected no MaterialMemoryState entry"
            )
        return

    guidance_probe_ok = _guidance_probe_eligible(
        state, probe_exercise, now, scheduler_params
    )
    bootstrap_probe_ok = _bootstrap_probe_eligible(
        state, probe_exercise, now, scheduler_params
    )

    if condition == "recently_successful":
        if guidance_probe_ok or bootstrap_probe_ok:
            raise AssertionError(
                f"{material_id}: recently_successful should be too recent for either "
                f"probe (guidance_probe={guidance_probe_ok}, bootstrap_probe={bootstrap_probe_ok})"
            )
    elif condition == "stale":
        if not guidance_probe_ok:
            raise AssertionError(
                f"{material_id}: stale should be guidance-probe eligible"
            )
        retrievability = memory_state.retrievability_or_prior(now, learner_params)
        if retrievability >= 0.1:
            raise AssertionError(
                f"{material_id}: stale retrievability {retrievability:.4f} not materially decayed"
            )
    elif condition == "repeatedly_failed":
        if memory_state is None or memory_state.factual_last_retrieval_at is None:
            raise AssertionError(
                f"{material_id}: repeatedly_failed should stay anchored"
            )
        if not guidance_probe_ok:
            raise AssertionError(
                f"{material_id}: repeatedly_failed should be guidance-probe eligible"
            )
    elif condition == "never_successful":
        if memory_state is None or memory_state.factual_last_retrieval_at is not None:
            raise AssertionError(
                f"{material_id}: never_successful must have "
                "factual_last_retrieval_at=None"
            )
        if not bootstrap_probe_ok:
            raise AssertionError(
                f"{material_id}: never_successful should be bootstrap-probe eligible"
            )
    else:
        raise AssertionError(f"unknown condition {condition!r}")


def seed_mixed_memory_state(
    profile_name: str,
    learner_params: LearnerParams,
    scheduler_params: SchedulerParams,
    condition_by_material: dict[str, str],
) -> tuple[LearnerState, TrueLearnerProfile]:
    """Builds one shared LearnerState via a chronologically-sorted schedule
    of forced Outcome events across the whole material pool, so the trial
    starts with a genuinely heterogeneous inventory - closer to a real
    user's practice history than a uniform cold start, which nothing in
    Pass 1-3 tested. Verifies every material landed in its intended
    condition before returning."""
    truth = copy.deepcopy(PROFILES[profile_name])
    schedule: list[tuple[float, str, bool]] = []
    for material_id, condition in condition_by_material.items():
        for offset, is_success in _PRESEED_EVENTS[condition]:
            schedule.append((offset, material_id, is_success))
    schedule.sort(key=lambda item: item[0])

    earliest = schedule[0][0] if schedule else 0.0
    state = initial_state(truth, learner_params, now=earliest)

    for now, material_id, is_success in schedule:
        material = next(m for m in MATERIALS if m.material_id == material_id)
        exercise = fixed_exercise(material, "RIGHT")
        outcome = FORCED_SUCCESS if is_success else FORCED_FAILURE
        _apply_forced_outcome(state, exercise, outcome, now, learner_params)

    for material_id, condition in condition_by_material.items():
        _verify_preseed_condition(
            state, material_id, condition, 0.0, scheduler_params, learner_params
        )

    return state, truth


# --- Session-chunk resilience -------------------------------------------


@dataclass
class NoAdmissionEvent:
    session_index: int
    attempts_presented: int
    attempts_abandoned: int
    at_days: float
    reason: str


def _classify_no_admission_reason(
    state: LearnerState,
    session,
    candidates: list,
    scheduler_params: SchedulerParams,
    learner_params: LearnerParams,
    now: float,
) -> str:
    """Read-only re-invocation of run_pipeline() for the exact inputs that
    just failed, purely to classify the cause - AttemptRecord never retains
    the excluded candidates, and this is cheaper than adding new
    instrumentation to the frozen longitudinal.py. Only runs on the rare
    no-admission event, never the hot per-attempt path."""
    traces = run_pipeline(
        state, session, candidates, scheduler_params, learner_params, now
    )
    safety_allowed = [t for t in traces if t.safety_allowed]
    if not safety_allowed:
        return "safety_suppressed"
    too_easy = sum(
        1
        for t in safety_allowed
        if t.prediction.overall_p > scheduler_params.challenge.p_max
    )
    too_hard = sum(
        1
        for t in safety_allowed
        if t.prediction.overall_p < scheduler_params.challenge.p_min
    )
    if too_hard == len(safety_allowed) and too_hard:
        return "too_hard"
    if too_easy == len(safety_allowed) and too_easy:
        return "too_easy"
    if too_easy and too_hard:
        return "mixed"
    return "unknown"


def run_trial_sessions(
    profile_name: str,
    agent: SchedulerAgent,
    learner_params: LearnerParams,
    scheduler_params: SchedulerParams,
    candidates: list,
    session_count: int,
    attempts_per_session: int,
    seed: int,
    state: LearnerState,
    truth: TrueLearnerProfile,
    start_now: float,
) -> tuple[LearnerState, TrueLearnerProfile, list[NoAdmissionEvent], list[int]]:
    """Session-chunked, resilient to NoAdmittedCandidate - NOT a reuse of
    scenarios.py's run_sessions(), which intentionally propagates that
    exception for its own behavioral-check purposes. state/truth are always
    caller-constructed (never None going in): run() raises from inside its
    own loop before returning, so internally-constructed state/truth on a
    None-input path would simply be lost. A session is treated as a
    calendar sitting, not a presented-exercise counter: on no-admission,
    `now` advances by the full remaining planned session time before the
    next session starts, so the same unresolved cause isn't replayed at an
    unmoving clock for the rest of the trial."""
    now = start_now
    rng = random.Random(seed)
    no_admission_events: list[NoAdmissionEvent] = []
    session_boundaries: list[int] = []

    for session_index in range(session_count):
        if session_index > 0:
            agent.new_session()
        records_before = len(agent.records)
        try:
            trace, state, truth = run(
                profile_name,
                attempts=attempts_per_session,
                seed=seed,
                params=learner_params,
                day_step=DAY_STEP,
                state=state,
                truth=truth,
                start_now=now,
                rng=rng,
                agent_pick=agent.pick,
                agent_on_outcome=agent.on_outcome,
            )
            now = trace[-1]["at_days"]
        except NoAdmittedCandidate:
            session_records = agent.records[records_before:]
            attempts_presented = sum(
                1 for r in session_records if r.selected is not None
            )
            attempts_abandoned = attempts_per_session - attempts_presented
            failure_record = session_records[-1]
            reason = _classify_no_admission_reason(
                state,
                agent.session,
                candidates,
                scheduler_params,
                learner_params,
                failure_record.at_days,
            )
            no_admission_events.append(
                NoAdmissionEvent(
                    session_index=session_index,
                    attempts_presented=attempts_presented,
                    attempts_abandoned=attempts_abandoned,
                    at_days=failure_record.at_days,
                    reason=reason,
                )
            )
            remaining_after_failure = attempts_abandoned - 1
            now = failure_record.at_days + remaining_after_failure * DAY_STEP
        session_boundaries.append(len(agent.records))

    return state, truth, no_admission_events, session_boundaries


# --- Universal hard properties -------------------------------------------


def _session_start_indices(session_boundaries: list[int]) -> set[int]:
    return {0, *session_boundaries[:-1]}


def check_2_every_selected_admitted(
    records: list[AttemptRecord],
) -> list[dict[str, Any]]:
    violations = []
    for idx, record in enumerate(records):
        if (
            record.selected is not None
            and record.selected.priority_status is not StageStatus.REACHED
        ):
            violations.append(
                {
                    "property_id": 2,
                    "property_name": "every selected candidate admitted",
                    "attempt_index": idx,
                    "at_days": record.at_days,
                    "description": (
                        f"selected exercise has priority_status="
                        f"{record.selected.priority_status}, not REACHED"
                    ),
                }
            )
    return violations


def check_3_recovery_matches_target(
    records: list[AttemptRecord], session_boundaries: list[int]
) -> list[dict[str, Any]]:
    violations = []
    tracker = None  # last selected-and-failed exercise, session-scoped
    starts = _session_start_indices(session_boundaries)
    for idx, record in enumerate(records):
        if idx in starts:
            tracker = None  # new_session() reset
        if record.selected is None:
            continue  # NoAdmittedCandidate: nothing presented, obligation untouched
        if tracker is not None:
            target = recovery_target(tracker)
            if target is None:
                violations.append(
                    {
                        "property_id": 3,
                        "property_name": "recovery == recovery_target()",
                        "attempt_index": idx,
                        "at_days": record.at_days,
                        "description": "tracker set but recovery_target() returned None - unexpected",
                    }
                )
            elif record.selected.exercise != target:
                violations.append(
                    {
                        "property_id": 3,
                        "property_name": "recovery == recovery_target()",
                        "attempt_index": idx,
                        "at_days": record.at_days,
                        "description": (
                            f"expected recovery target {target}, got "
                            f"{record.selected.exercise} (bypass={record.selected.challenge_bypass})"
                        ),
                    }
                )
            elif record.selected.challenge_bypass != "recovery":
                violations.append(
                    {
                        "property_id": 3,
                        "property_name": "recovery == recovery_target()",
                        "attempt_index": idx,
                        "at_days": record.at_days,
                        "description": "exercise matches recovery target but challenge_bypass != 'recovery'",
                    }
                )
        tracker = (
            record.selected.exercise
            if record.outcome is not None
            and record.outcome.retrieval_succeeded is False
            else None
        )
    return violations


def check_4_no_success_without_observation(
    records: list[AttemptRecord],
) -> list[dict[str, Any]]:
    violations = []
    for idx, record in enumerate(records):
        if record.selected is None or record.outcome is None:
            continue
        if (
            record.outcome.retrieval_succeeded is True
            and not record.selected.exercise.guidance.retrieval_observed()
        ):
            violations.append(
                {
                    "property_id": 4,
                    "property_name": "no success without observation",
                    "attempt_index": idx,
                    "at_days": record.at_days,
                    "description": "retrieval_succeeded=True under a non-observing (cued) exercise",
                }
            )
    return violations


def check_5_repetition_cap_obeyed(
    records: list[AttemptRecord],
    session_boundaries: list[int],
    scheduler_params: SchedulerParams,
) -> list[dict[str, Any]]:
    """Exhaustive, not sampled: with EXHAUSTIVE_TOP_N, {winner} | runners_up
    is the complete admitted set for that attempt, so "an alternative was
    admitted" here means "truly admitted," not "happened to be sampled.\""""
    violations = []
    cap = scheduler_params.diversity.max_consecutive_material_attempts
    starts = _session_start_indices(session_boundaries)
    run_material = None
    run_length = 0
    for idx, record in enumerate(records):
        if idx in starts:
            run_material, run_length = None, 0
        if record.selected is None:
            continue
        material_id = record.selected.exercise.material.material_id
        if run_length >= cap and run_material == material_id:
            alternative_exists = any(
                t.exercise.material.material_id != material_id
                for t in record.runners_up
            )
            if alternative_exists:
                violations.append(
                    {
                        "property_id": 5,
                        "property_name": "repetition cap obeyed when an alternative exists",
                        "attempt_index": idx,
                        "at_days": record.at_days,
                        "description": (
                            f"material {material_id} selected again after {run_length} "
                            "consecutive picks, despite an admitted alternative"
                        ),
                    }
                )
        run_length = run_length + 1 if material_id == run_material else 1
        run_material = material_id
    return violations


def check_6_bootstrap_not_permanently_trapped(
    records: list[AttemptRecord], bound: int = BOOTSTRAP_TRAP_BOUND
) -> list[dict[str, Any]]:
    """NOT session-boundary-aware: MaterialMemoryState lives on LearnerState,
    not SessionState. Filtered to one material's own selections (not literal
    temporal adjacency - pool size can exceed 1 here, unlike Pass 2)."""
    violations = []
    per_material: dict[str, dict[str, Any]] = {}
    for idx, record in enumerate(records):
        if record.selected is None or record.outcome is None:
            continue
        material_id = record.selected.exercise.material.material_id
        entry = per_material.setdefault(
            material_id,
            {
                "current_cued_run": 0,
                "max_cued_run": 0,
                "ever_tested": False,
                "ever_succeeded": False,
                "last_violation_idx": None,
                "last_violation_days": None,
            },
        )
        if record.outcome.retrieval_succeeded is not None:
            entry["ever_tested"] = True
        if record.outcome.retrieval_succeeded is True:
            entry["ever_succeeded"] = True
            entry["current_cued_run"] = 0
        elif _guidance_independence(record.selected.exercise) == 0:
            entry["current_cued_run"] += 1
            entry["max_cued_run"] = max(
                entry["max_cued_run"], entry["current_cued_run"]
            )
            entry["last_violation_idx"] = idx
            entry["last_violation_days"] = record.at_days
        else:
            entry["current_cued_run"] = 0

    for material_id, entry in per_material.items():
        if (
            entry["ever_tested"]
            and not entry["ever_succeeded"]
            and entry["max_cued_run"] > bound
        ):
            violations.append(
                {
                    "property_id": 6,
                    "property_name": "no permanently-absorbing full-cue state",
                    "attempt_index": entry["last_violation_idx"],
                    "at_days": entry["last_violation_days"],
                    "description": (
                        f"material {material_id} never anchored, but was selected fully "
                        f"cued {entry['max_cued_run']} consecutive times (bound={bound})"
                    ),
                }
            )
    return violations


def _fake_trace(
    exercise,
    *,
    priority_status=StageStatus.REACHED,
    challenge_bypass=None,
    rank_key=(1, 0.0, 0.0, 0.0, 0.0),
):
    """Minimal CandidateTrace for self-checks - same pattern
    scenarios.py's check_repetition_guard_prevents_perseveration() uses to
    isolate a checker from real prediction machinery."""
    prediction = Prediction(
        independent_retrieval_p=0.7,
        material_available_p=0.7,
        execution_p=0.9,
        topology_p=0.8,
    )
    return CandidateTrace(
        exercise=exercise,
        eligibility_tier="FULLY_ELIGIBLE",
        eligibility_reason="",
        safety_allowed=True,
        safety_reason="",
        challenge_status=StageStatus.REACHED,
        prediction=prediction,
        challenge_within_band=True,
        challenge_bypass=challenge_bypass,
        challenge_survived=True,
        priority_status=priority_status,
        retention=0.0,
        information=0.0,
        diversity=0.0,
        goals=0.0,
        rank_key=rank_key if priority_status is StageStatus.REACHED else None,
    )


def self_check_hard_properties() -> None:
    """Tests of the Pass-4 harness itself, not of the scheduler - given how
    much weight "zero violations" carries, each checker must be proven to
    actually fire on a violating case, not just to stay quiet."""
    material_a = MATERIALS[0]
    material_b = MATERIALS[1]
    unguided = fixed_exercise(material_a, "RIGHT")
    cued = fixed_exercise(
        material_a, "RIGHT", guidance=GuidanceContext(concurrent_pitch_cues=True)
    )
    notes_previewed = fixed_exercise(
        material_a, "RIGHT", guidance=GuidanceContext(notes_previewed=True)
    )

    # #2
    bad = AttemptRecord(
        0, 1.0, _fake_trace(unguided, priority_status=StageStatus.NOT_REACHED)
    )
    good = AttemptRecord(0, 1.0, _fake_trace(unguided))
    assert len(check_2_every_selected_admitted([bad])) == 1
    assert len(check_2_every_selected_admitted([good])) == 0

    # #3
    target = recovery_target(unguided)
    assert target is not None
    failure = AttemptRecord(
        0,
        1.0,
        _fake_trace(unguided),
        outcome=Outcome(True, False, False, 0, 0, 0, 0, 0, 0),
    )
    correct_recovery = AttemptRecord(
        1,
        1.5,
        _fake_trace(target, challenge_bypass="recovery"),
        outcome=Outcome(True, True, True, 1, 1, 1, 1, 1, 1),
    )
    wrong_recovery = AttemptRecord(
        1,
        1.5,
        _fake_trace(fixed_exercise(material_b, "RIGHT"), challenge_bypass="recovery"),
        outcome=Outcome(True, True, True, 1, 1, 1, 1, 1, 1),
    )
    no_admission = AttemptRecord(1, 1.5, None)
    fresh_after_boundary = AttemptRecord(
        2, 2.0, _fake_trace(fixed_exercise(material_b, "RIGHT"))
    )
    assert len(check_3_recovery_matches_target([failure, correct_recovery], [2])) == 0
    assert len(check_3_recovery_matches_target([failure, wrong_recovery], [2])) == 1
    # session 0 = [failure, no_admission] (boundary at 2), session 1 = [fresh_after_boundary]
    assert (
        len(
            check_3_recovery_matches_target(
                [failure, no_admission, fresh_after_boundary], [2, 3]
            )
        )
        == 0
    )

    # #4
    bad_observation = AttemptRecord(
        0, 1.0, _fake_trace(cued), outcome=Outcome(True, True, True, 1, 1, 1, 1, 1, 1)
    )
    good_observation = AttemptRecord(
        0,
        1.0,
        _fake_trace(unguided),
        outcome=Outcome(True, True, True, 1, 1, 1, 1, 1, 1),
    )
    assert len(check_4_no_success_without_observation([bad_observation])) == 1
    assert len(check_4_no_success_without_observation([good_observation])) == 0

    # #5
    scheduler_params = load_scheduler_params()
    cap = scheduler_params.diversity.max_consecutive_material_attempts
    same_material_only = [
        AttemptRecord(i, float(i), _fake_trace(fixed_exercise(material_a, "RIGHT")))
        for i in range(cap)
    ]
    same_material_only.append(
        AttemptRecord(
            cap,
            float(cap),
            _fake_trace(fixed_exercise(material_a, "RIGHT")),
        )
    )
    assert (
        len(
            check_5_repetition_cap_obeyed(
                same_material_only, [len(same_material_only)], scheduler_params
            )
        )
        == 0
    )
    with_alternative = list(same_material_only)
    with_alternative[-1] = AttemptRecord(
        cap,
        float(cap),
        _fake_trace(fixed_exercise(material_a, "RIGHT")),
        runners_up=[_fake_trace(fixed_exercise(material_b, "RIGHT"))],
    )
    assert (
        len(
            check_5_repetition_cap_obeyed(
                with_alternative, [len(with_alternative)], scheduler_params
            )
        )
        == 1
    )

    # #6 - a leading genuine failure establishes ever_tested=True (matching
    # last_retrieval_attempt_at's real semantics); the cued run afterward is
    # what should trip the bound. A material cued from attempt 0 with no
    # leading test is never "genuinely tested," so it must NOT trip #6 -
    # that's the never/unseen case, not the bootstrap-trap case.
    leading_failure = AttemptRecord(
        0,
        0.0,
        _fake_trace(notes_previewed),
        outcome=Outcome(True, False, False, 0.2, 0.2, 0.2, 0.2, 0.2, 0.5),
    )
    cued_records = [leading_failure] + [
        AttemptRecord(
            i + 1,
            float(i + 1),
            _fake_trace(cued),
            outcome=Outcome(True, None, True, 0.5, 0.5, 0.5, 0.5, 1.0, 0.5),
        )
        for i in range(BOOTSTRAP_TRAP_BOUND + 1)
    ]
    assert len(check_6_bootstrap_not_permanently_trapped(cued_records)) == 1
    never_tested = [
        AttemptRecord(
            i,
            float(i),
            _fake_trace(cued),
            outcome=Outcome(True, None, True, 0.5, 0.5, 0.5, 0.5, 1.0, 0.5),
        )
        for i in range(BOOTSTRAP_TRAP_BOUND + 1)
    ]
    assert len(check_6_bootstrap_not_permanently_trapped(never_tested)) == 0
    escaped = list(cued_records)
    midpoint = len(escaped) // 2
    escaped[midpoint] = AttemptRecord(
        midpoint,
        float(midpoint),
        _fake_trace(notes_previewed),
        outcome=Outcome(True, False, True, 0.5, 0.5, 0.5, 0.5, 1.0, 0.5),
    )
    assert len(check_6_bootstrap_not_permanently_trapped(escaped)) == 0


# --- Trial driver ----------------------------------------------------------


def run_trial(
    spec: TrialSpec, scheduler_params: SchedulerParams, learner_params: LearnerParams
) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    materials = [m for m in MATERIALS if m.material_id in spec.material_ids]
    instrument = InstrumentProfile(key_count=spec.instrument_key_count)
    candidates = generate_candidates(instrument, materials)

    # Fixture construction happens OUTSIDE the crash boundary below: a
    # broken fixture is a harness bug that must abort loudly, never a
    # per-trial "crashed" statistic.
    starting_competency_mean = None
    if spec.mixed_memory_condition_by_material is not None:
        state, truth = seed_mixed_memory_state(
            spec.profile_name,
            learner_params,
            scheduler_params,
            spec.mixed_memory_condition_by_material,
        )
    else:
        truth = copy.deepcopy(PROFILES[spec.profile_name])
        state = initial_state(truth, learner_params, now=0.0)
        if spec.competency_offset != 0.0:
            for c in state.competencies.values():
                c.mean += spec.competency_offset
    starting_competency_mean = sum(c.mean for c in state.competencies.values()) / len(
        state.competencies
    )

    agent = SchedulerAgent(
        instrument, materials, scheduler_params, learner_params, top_n=EXHAUSTIVE_TOP_N
    )

    base_row = {
        "trial_kind": spec.trial_kind,
        "profile": spec.profile_name,
        "pool_size": spec.pool_size,
        "material_ids": ",".join(spec.material_ids),
        "seed": spec.seed,
        "instrument_key_count": spec.instrument_key_count,
        "competency_offset": spec.competency_offset,
        "starting_competency_mean": starting_competency_mean,
    }

    try:
        state, truth, no_admission_events, session_boundaries = run_trial_sessions(
            spec.profile_name,
            agent,
            learner_params,
            scheduler_params,
            candidates,
            spec.session_count,
            spec.attempts_per_session,
            spec.seed,
            state,
            truth,
            0.0,
        )
    except Exception as exc:  # noqa: BLE001 - a crash is itself a finding
        trial_row = {
            **base_row,
            "sessions_planned": spec.session_count,
            "attempts_planned_total": spec.session_count * spec.attempts_per_session,
            "crashed": True,
            "crash_message": repr(exc),
        }
        violation_row = {
            **base_row,
            "property_id": 1,
            "property_name": "no crashes",
            "attempt_index": None,
            "at_days": None,
            "description": repr(exc),
        }
        return trial_row, [], [violation_row]

    records = agent.records
    trial_row, material_rows = _compute_metrics(
        base_row, spec, records, no_admission_events
    )
    violations = (
        check_2_every_selected_admitted(records)
        + check_3_recovery_matches_target(records, session_boundaries)
        + check_4_no_success_without_observation(records)
        + check_5_repetition_cap_obeyed(records, session_boundaries, scheduler_params)
        + check_6_bootstrap_not_permanently_trapped(records)
    )
    violation_rows = [{**base_row, **v} for v in violations]
    return trial_row, material_rows, violation_rows


def _compute_metrics(
    base_row: dict[str, Any],
    spec: TrialSpec,
    records: list[AttemptRecord],
    no_admission_events: list[NoAdmissionEvent],
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    presented = [r for r in records if r.selected is not None]
    attempts_presented = len(presented)
    attempts_planned_total = spec.session_count * spec.attempts_per_session
    attempts_abandoned = sum(e.attempts_abandoned for e in no_admission_events)

    bypass_counts = Counter(r.selected.challenge_bypass for r in presented)
    independence_counts = Counter(
        _guidance_independence(r.selected.exercise) for r in presented
    )
    tier_counts = Counter(r.selected.eligibility_tier for r in presented)
    outcome_records = [r for r in presented if r.outcome is not None]
    overall_prediction_errors = [
        r.selected.prediction.overall_p
        - (
            r.outcome.pitch_integrity
            + r.outcome.continuity
            + r.outcome.temporal_stability
        )
        / 3.0
        for r in outcome_records
    ]
    observed_retrievals = [
        r for r in outcome_records if r.outcome.retrieval_succeeded is not None
    ]
    retrieval_prediction_errors = [
        r.selected.prediction.independent_retrieval_p
        - (1.0 if r.outcome.retrieval_succeeded else 0.0)
        for r in observed_retrievals
    ]

    max_run, current_run, current_material = 0, 0, None
    per_material_selections: dict[str, list[float]] = {}
    for r in presented:
        material_id = r.selected.exercise.material.material_id
        current_run = current_run + 1 if material_id == current_material else 1
        current_material = material_id
        max_run = max(max_run, current_run)
        per_material_selections.setdefault(material_id, []).append(r.at_days)

    def frac(n: int) -> float:
        return n / attempts_presented if attempts_presented else 0.0

    all_revisit_gaps: list[float] = []
    material_rows = []
    for material_id in spec.material_ids:
        selections = per_material_selections.get(material_id, [])
        gaps = [b - a for a, b in pairwise(selections)]
        all_revisit_gaps.extend(gaps)

        material_presented = [
            r
            for r in presented
            if r.selected.exercise.material.material_id == material_id
        ]
        first_success = next(
            (
                r
                for r in material_presented
                if r.outcome is not None and r.outcome.retrieval_succeeded is True
            ),
            None,
        )
        cued_run, max_cued_run = 0, 0
        for r in material_presented:
            if _guidance_independence(r.selected.exercise) == 0:
                cued_run += 1
                max_cued_run = max(max_cued_run, cued_run)
            else:
                cued_run = 0
        cued_count = sum(
            1
            for r in material_presented
            if _guidance_independence(r.selected.exercise) == 0
        )
        observed_material_retrievals = [
            r
            for r in material_presented
            if r.outcome is not None and r.outcome.retrieval_succeeded is not None
        ]
        successful_material_retrievals = sum(
            1 for r in observed_material_retrievals if r.outcome.retrieval_succeeded
        )

        condition = (
            spec.mixed_memory_condition_by_material.get(material_id, "")
            if spec.mixed_memory_condition_by_material
            else ""
        )
        material_rows.append(
            {
                **base_row,
                "material_id": material_id,
                "initial_condition": condition,
                "times_selected": len(selections),
                "ever_introduced": len(selections) > 0,
                "ever_succeeded": first_success is not None,
                "attempts_to_first_success": (
                    material_presented.index(first_success) + 1
                    if first_success
                    else None
                ),
                "days_to_first_success": (
                    first_success.at_days if first_success else None
                ),
                "max_consecutive_cued_run": max_cued_run,
                "frac_selections_at_max_cueing": (
                    cued_count / len(material_presented) if material_presented else 0.0
                ),
                "retrieval_observation_count": len(observed_material_retrievals),
                "retrieval_success_count": successful_material_retrievals,
                "retrieval_success_fraction": (
                    successful_material_retrievals / len(observed_material_retrievals)
                    if observed_material_retrievals
                    else None
                ),
                "revisit_interval_mean_days": (sum(gaps) / len(gaps) if gaps else None),
                "revisit_interval_max_days": (max(gaps) if gaps else None),
                "revisit_count": len(gaps),
            }
        )

    materials_introduced = sum(1 for m in material_rows if m["ever_introduced"])
    materials_never_succeeded = sum(
        1 for m in material_rows if m["ever_introduced"] and not m["ever_succeeded"]
    )
    materials_never_selected = sum(1 for m in material_rows if not m["ever_introduced"])
    max_selection_fraction = (
        max((len(v) for v in per_material_selections.values()), default=0)
        / attempts_presented
        if attempts_presented
        else 0.0
    )

    reason_counts = Counter(e.reason for e in no_admission_events)
    trial_row = {
        **base_row,
        "sessions_planned": spec.session_count,
        "attempts_planned_total": attempts_planned_total,
        "attempts_presented": attempts_presented,
        "attempts_abandoned": attempts_abandoned,
        "sessions_with_no_admission": len(no_admission_events),
        "no_admission_event_count": len(no_admission_events),
        "no_admission_rate": attempts_abandoned / attempts_planned_total
        if attempts_planned_total
        else 0.0,
        "no_admission_reason_counts": ",".join(
            f"{k}:{v}" for k, v in reason_counts.items()
        ),
        "max_consecutive_material_run": max_run,
        "max_material_selection_fraction": max_selection_fraction,
        "frac_bypass_none": frac(bypass_counts[None]),
        "frac_recovery": frac(bypass_counts["recovery"]),
        "frac_new_material": frac(bypass_counts["new_material"]),
        "frac_guidance_probe": frac(bypass_counts["guidance_probe"]),
        "frac_bootstrap_probe": frac(bypass_counts["bootstrap_probe"]),
        "frac_override": frac(bypass_counts["override"]),
        "frac_unguided": frac(independence_counts[2]),
        "frac_notes_previewed": frac(independence_counts[1]),
        "frac_concurrent_cues": frac(independence_counts[0]),
        "frac_fully_eligible": frac(tier_counts["FULLY_ELIGIBLE"]),
        "frac_provisionally_eligible": frac(tier_counts["PROVISIONALLY_ELIGIBLE"]),
        "overall_prediction_bias": (
            sum(overall_prediction_errors) / len(overall_prediction_errors)
            if overall_prediction_errors
            else None
        ),
        "overall_prediction_mae": (
            sum(abs(error) for error in overall_prediction_errors)
            / len(overall_prediction_errors)
            if overall_prediction_errors
            else None
        ),
        "retrieval_observation_count": len(observed_retrievals),
        "retrieval_success_fraction": (
            sum(1 for r in observed_retrievals if r.outcome.retrieval_succeeded)
            / len(observed_retrievals)
            if observed_retrievals
            else None
        ),
        "retrieval_prediction_bias": (
            sum(retrieval_prediction_errors) / len(retrieval_prediction_errors)
            if retrieval_prediction_errors
            else None
        ),
        "retrieval_prediction_mae": (
            sum(abs(error) for error in retrieval_prediction_errors)
            / len(retrieval_prediction_errors)
            if retrieval_prediction_errors
            else None
        ),
        "retrieval_prediction_brier": (
            sum(error**2 for error in retrieval_prediction_errors)
            / len(retrieval_prediction_errors)
            if retrieval_prediction_errors
            else None
        ),
        "materials_introduced_count": materials_introduced,
        "materials_never_succeeded_count": materials_never_succeeded,
        "materials_never_selected_count": materials_never_selected,
        "revisit_interval_mean_days": (
            sum(all_revisit_gaps) / len(all_revisit_gaps) if all_revisit_gaps else None
        ),
        "revisit_interval_max_days": (
            max(all_revisit_gaps) if all_revisit_gaps else None
        ),
        "crashed": False,
        "crash_message": "",
    }
    return trial_row, material_rows


# --- Output ----------------------------------------------------------------


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("")
        return
    fieldnames: list[str] = []
    for row in rows:
        for key in row:
            if key not in fieldnames:
                fieldnames.append(key)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def report(
    trial_rows: list[dict[str, Any]],
    material_rows: list[dict[str, Any]],
    violation_rows: list[dict[str, Any]],
) -> None:
    clean_trials = [t for t in trial_rows if not t.get("crashed")]
    print(
        f"{len(trial_rows)} trials run ({len(clean_trials)} completed, "
        f"{len(trial_rows) - len(clean_trials)} crashed)."
    )
    print()

    if clean_trials:
        print("Descriptive metrics across completed trials:")
        for field_name in (
            "no_admission_rate",
            "max_consecutive_material_run",
            "max_material_selection_fraction",
            "frac_recovery",
            "frac_guidance_probe",
            "frac_bootstrap_probe",
            "frac_new_material",
            "frac_concurrent_cues",
            "overall_prediction_bias",
            "overall_prediction_mae",
            "retrieval_success_fraction",
            "retrieval_prediction_bias",
            "retrieval_prediction_mae",
            "retrieval_prediction_brier",
        ):
            values = [
                t[field_name] for t in clean_trials if t.get(field_name) is not None
            ]
            if values:
                values_sorted = sorted(values)
                mean = sum(values) / len(values)
                median = values_sorted[len(values_sorted) // 2]
                print(
                    f"  {field_name:<32} mean={mean:.3f} median={median:.3f} max={max(values):.3f}"
                )
        print()

        retrieval_observation_count = sum(
            t["retrieval_observation_count"] for t in clean_trials
        )
        attempts_presented = sum(t["attempts_presented"] for t in clean_trials)

        def weighted_mean(field_name: str, weight_name: str, total: int) -> float:
            if not total:
                return float("nan")
            return (
                sum(
                    t[weight_name] * t[field_name]
                    for t in clean_trials
                    if t[weight_name]
                )
                / total
            )

        print("Observation-weighted calibration across completed trials:")
        print(f"  retrieval_observation_count       {retrieval_observation_count}")
        for field_name in (
            "retrieval_success_fraction",
            "retrieval_prediction_bias",
            "retrieval_prediction_mae",
            "retrieval_prediction_brier",
        ):
            print(
                f"  {field_name:<35} "
                f"{weighted_mean(field_name, 'retrieval_observation_count', retrieval_observation_count):.3f}"
            )
        for field_name in ("overall_prediction_bias", "overall_prediction_mae"):
            print(
                f"  {field_name:<35} "
                f"{weighted_mean(field_name, 'attempts_presented', attempts_presented):.3f}"
            )
        print()

        print("frac_recovery / frac_guidance_probe by profile (core_sweep only):")
        core = [t for t in clean_trials if t["trial_kind"] == "core_sweep"]
        by_profile: dict[str, list[dict[str, Any]]] = {}
        for t in core:
            by_profile.setdefault(t["profile"], []).append(t)
        for profile_name in sorted(by_profile):
            group = by_profile[profile_name]
            fr = sum(t["frac_recovery"] for t in group) / len(group)
            fg = sum(t["frac_guidance_probe"] for t in group) / len(group)
            print(
                f"  {profile_name:<32} frac_recovery={fr:.3f} frac_guidance_probe={fg:.3f}"
            )
        print()

        print("Notable trials (top 5 by no_admission_rate):")
        for t in sorted(
            clean_trials, key=lambda t: t["no_admission_rate"], reverse=True
        )[:5]:
            print(
                f"  {t['trial_kind']:<20} {t['profile']:<32} pool={t['pool_size']} seed={t['seed']} "
                f"no_admission_rate={t['no_admission_rate']:.3f} reasons={t['no_admission_reason_counts']}"
            )
        print()

        # pool_size=1 guarantees max_material_selection_fraction=1.0 by
        # definition (there is only one material to select) - including it
        # here would drown out genuine concentration at pool_size>1, where
        # the metric actually says something about ranking behavior.
        multi_material_trials = [t for t in clean_trials if t["pool_size"] > 1]
        print(
            "Notable trials (top 5 by max_material_selection_fraction, pool_size>1 only):"
        )
        for t in sorted(
            multi_material_trials,
            key=lambda t: t["max_material_selection_fraction"],
            reverse=True,
        )[:5]:
            print(
                f"  {t['trial_kind']:<20} {t['profile']:<32} pool={t['pool_size']} seed={t['seed']} "
                f"max_material_selection_fraction={t['max_material_selection_fraction']:.3f}"
            )
        print()

    selected_never_succeeded = [
        m for m in material_rows if m["ever_introduced"] and not m["ever_succeeded"]
    ]
    never_selected = [m for m in material_rows if not m["ever_introduced"]]
    print(
        f"Materials selected but never succeeded: {len(selected_never_succeeded)}; "
        f"materials never selected at all: {len(never_selected)}."
    )
    if selected_never_succeeded:
        print("  Examples:")
        for m in selected_never_succeeded[:5]:
            print(
                f"    {m['trial_kind']:<20} {m['profile']:<32} {m['material_id']:<20} "
                f"times_selected={m['times_selected']}"
            )
    print()

    if violation_rows:
        print(f"{len(violation_rows)} HARD-PROPERTY VIOLATIONS FOUND:")
        for v in violation_rows[:30]:
            print(
                f"  property #{v['property_id']} ({v['property_name']}) - "
                f"{v['trial_kind']}/{v['profile']}/pool={v['pool_size']}/seed={v['seed']} "
                f"attempt={v['attempt_index']}: {v['description']}"
            )
        if len(violation_rows) > 30:
            print(
                f"  ... and {len(violation_rows) - 30} more (see stress_violations.csv)"
            )
    else:
        print("No hard-property violations found.")

    override_rows = [t for t in clean_trials if t.get("frac_override", 0.0) > 0.0]
    if override_rows:
        print(
            f"\nWARNING: {len(override_rows)} trials show nonzero frac_override - "
            "stress.py never passes overrides to run_pipeline(), so this indicates a harness bug."
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
    self_check_hard_properties()

    scheduler_params = load_scheduler_params(args.scheduler_params)
    learner_params = load_learner_params(args.learner_params)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    specs = (
        build_core_specs()
        + build_competency_override_specs()
        + build_restricted_instrument_specs()
        + build_mixed_memory_specs()
    )

    trial_rows: list[dict[str, Any]] = []
    material_rows: list[dict[str, Any]] = []
    violation_rows: list[dict[str, Any]] = []
    for spec in specs:
        trial_row, spec_material_rows, spec_violation_rows = run_trial(
            spec, scheduler_params, learner_params
        )
        trial_rows.append(trial_row)
        material_rows.extend(spec_material_rows)
        violation_rows.extend(spec_violation_rows)

    outputs = {
        "stress_trials.csv": trial_rows,
        "stress_materials.csv": material_rows,
        "stress_violations.csv": violation_rows,
    }
    for filename, rows in outputs.items():
        write_csv(args.output_dir / filename, rows)

    report(trial_rows, material_rows, violation_rows)

    print()
    for filename in outputs:
        print(f"Wrote {args.output_dir / filename}")

    if violation_rows:
        sys.exit(1)


if __name__ == "__main__":
    main()
