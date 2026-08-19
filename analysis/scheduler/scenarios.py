#!/usr/bin/env python3
"""Longitudinal behavioral scenarios for the scheduler pipeline
(docs/learner-model/04-v1-scheduler.md §10, Pass 2).

Mirrors ../learner-model/invariants.py's plain-assertion, printed
pass/fail style, per §10's own instruction. Deliberately separate from
invariants.py (Pass 1's boundary/mechanical-correctness checks): these
ask a different question - "does the pipeline behave well over
repeated scheduler -> outcome -> learner-update -> scheduler cycles,"
not "does a forbidden input move a stage's decision." A FAIL here can
be a genuine Pass-2 finding, not necessarily a regression to fix before
moving on - several already drove real policy revisions (R(e), I(e),
the guidance-probe and introduction bypasses, the repetition guard).

Usage:
    python scenarios.py
"""

from __future__ import annotations

import random
import sys
from itertools import pairwise
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "learner-model"))

from candidates import InstrumentProfile, SessionState
from config import load_params as load_scheduler_params
from longitudinal import NoAdmittedCandidate, SchedulerAgent
from model import Prediction
from params import load_params as load_learner_params
from pipeline import (
    CandidateTrace,
    StageStatus,
    eligibility_tier,
    repetition_guard,
    select_next,
)
from simulate import MATERIALS, fixed_exercise, initial_state, run
from synthetic import PROFILES


class InvariantFailure(Exception):
    pass


def run_sessions(
    profile_name: str,
    agent: SchedulerAgent,
    learner_params,
    session_count: int,
    attempts_per_session: int,
    seed: int,
):
    """Runs several scheduler-driven sessions back to back, resetting
    SessionState at each boundary (a fresh practice sitting) while
    LearnerState/TrueLearnerProfile and simulated time carry over
    unbroken. A long behavioral horizon is several bounded sessions, not
    one run past SchedulerSafetyPolicy's own attempt cap - that would
    silently hand later attempts to a fallback the scheduler never
    chose, contaminating memory/competency/session state with exercises
    it explicitly did not select. Propagates NoAdmittedCandidate if any
    attempt in any session finds nothing admitted; callers not
    specifically testing that condition should let it surface as a
    failure, not swallow it."""
    state = None
    truth = None
    now = 0.0
    rng = random.Random(seed)
    for session_index in range(session_count):
        if session_index > 0:
            agent.new_session()
        trace, state, truth = run(
            profile_name,
            attempts=attempts_per_session,
            seed=seed,
            params=learner_params,
            state=state,
            truth=truth,
            start_now=now,
            rng=rng,
            agent_pick=agent.pick,
            agent_on_outcome=agent.on_outcome,
        )
        now = trace[-1]["at_days"]
    return state, truth


def check_guidance_fades_as_memory_strengthens() -> None:
    """04-v1-scheduler.md §30 "guidance that never fades."

    Originally: a cued attempt never tests retrieval (retrieval_succeeded
    stays None, §18.2), so once the scheduler shifted to full cueing it
    could never re-anchor the memory clock and got stuck there
    permanently. Resolved by the guidance_probe bypass (see
    challenge_bypass()), which offers a one-step-less-guided variant
    once enough time has passed since the last confirmed retrieval.
    """
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    instrument = InstrumentProfile()
    agent = SchedulerAgent(instrument, [MATERIALS[0]], scheduler_params, learner_params)

    try:
        run_sessions(
            "technique_strong_memory_weak",
            agent,
            learner_params,
            session_count=3,
            attempts_per_session=20,
            seed=0,
        )
    except NoAdmittedCandidate as exc:
        raise InvariantFailure(
            f"scheduler produced no admitted candidate: {exc}"
        ) from exc

    def independence(exercise) -> int:
        if exercise.guidance.concurrent_pitch_cues:
            return 0
        if exercise.guidance.notes_previewed:
            return 1
        return 2

    selections = [r.selected for r in agent.records if r.selected is not None]
    if len(selections) < 10:
        raise InvariantFailure(
            f"too few admitted attempts to evaluate this at all ({len(selections)}/60)"
        )

    independences = [independence(t.exercise) for t in selections]
    tail_window = 10
    tail, earlier = independences[-tail_window:], independences[:-tail_window]
    if all(level == 0 for level in tail) and any(level > 0 for level in earlier):
        raise InvariantFailure(
            f"guidance became permanently stuck at maximum support for the final "
            f"{tail_window} attempts, despite less-guided attempts earlier in the run "
            "- see this check's docstring for the observed mechanism"
        )


def check_no_endless_repetition() -> None:
    """04-v1-scheduler.md §30 "repeating the same material indefinitely."

    Originally a guidance/memory feedback trap: a cued attempt has
    retrieval_succeeded=None (never tested, §18.2), so once the
    scheduler shifted to a fully-cued variant the memory clock could
    never re-anchor, and unboundedly rising R entrenched that material.
    R(e)'s retrieval_opportunity weighting and repetition_guard() (see
    that function) resolved it at this longitudinal scale; the guard's
    own two properties are tested directly in
    check_repetition_guard_prevents_perseveration().
    """
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    instrument = InstrumentProfile()
    agent = SchedulerAgent(instrument, MATERIALS[:3], scheduler_params, learner_params)

    try:
        run_sessions(
            "advanced",
            agent,
            learner_params,
            session_count=4,
            attempts_per_session=20,
            seed=1,
        )
    except NoAdmittedCandidate as exc:
        raise InvariantFailure(
            f"scheduler produced no admitted candidate: {exc}"
        ) from exc

    selections = [
        r.selected.exercise.material.material_id
        for r in agent.records
        if r.selected is not None
    ]
    window = scheduler_params.diversity.recent_window
    max_run, current_run = 1, 1
    for prev, cur in pairwise(selections):
        current_run = current_run + 1 if cur == prev else 1
        max_run = max(max_run, current_run)

    if max_run > window:
        raise InvariantFailure(
            f"one material was selected {max_run} times in a row, exceeding the "
            f"diversity window ({window}) - see this check's docstring for the "
            "observed guidance/memory feedback mechanism"
        )


def check_repetition_guard_prevents_perseveration() -> None:
    """repetition_guard() (pipeline.py), a pre-selection filter rather
    than another priority term - under lexicographic R>I>V, V can only
    break exact ties, so no V penalty could stop a material whose R wins
    outright. Two properties: with an alternative available, an
    over-repeated material must not win; with no alternative, the guard
    must not force no admission.

    Direct CandidateTrace construction, not run_pipeline() output: this
    tests repetition_guard() itself (a pure function of traces/session),
    not whether run_pipeline() wires it up - SchedulerAgent already does
    that (check_no_endless_repetition). A real-prediction setup makes
    which material "should" win on R/I hard to control precisely (guard
    band membership, cued-vs-tested state, etc. all confound it); a
    controlled rank_key removes that confound.
    """
    scheduler_params = load_scheduler_params()
    cap = scheduler_params.diversity.max_consecutive_material_attempts

    ex_a = fixed_exercise(MATERIALS[0], "RIGHT")
    ex_b = fixed_exercise(MATERIALS[1], "RIGHT")
    prediction = Prediction(
        independent_retrieval_p=0.7,
        material_available_p=0.7,
        execution_p=0.9,
        topology_p=0.8,
    )
    shared = {
        "eligibility_tier": "FULLY_ELIGIBLE",
        "eligibility_reason": "",
        "safety_allowed": True,
        "safety_reason": "",
        "challenge_status": StageStatus.REACHED,
        "prediction": prediction,
        "challenge_within_band": True,
        "challenge_bypass": None,
        "challenge_survived": True,
        "priority_status": StageStatus.REACHED,
    }
    # A dominates R/I so it would win outright without the guard.
    trace_a = CandidateTrace(
        exercise=ex_a,
        retention=0.9,
        information=1.0,
        diversity=0.0,
        goals=0.0,
        rank_key=(1, 0.9, 1.0, 0.0, 0.0),
        **shared,
    )
    trace_b = CandidateTrace(
        exercise=ex_b,
        retention=0.1,
        information=0.5,
        diversity=0.0,
        goals=0.0,
        rank_key=(1, 0.1, 0.5, 0.0, 0.0),
        **shared,
    )

    if select_next([trace_a, trace_b]) is not trace_a:
        raise InvariantFailure("test setup error: expected A to win without the guard")

    session = SessionState(recent_material_ids=[MATERIALS[0].material_id] * cap)
    guarded = repetition_guard([trace_a, trace_b], session, scheduler_params)
    winner = select_next(guarded)
    if winner is None:
        raise InvariantFailure(
            "test setup error: expected an admitted winner with two materials available"
        )
    if winner is trace_a:
        raise InvariantFailure(
            f"repetition guard did not exclude a material selected {cap} times in a "
            "row despite an alternative material being available"
        )

    single_session = SessionState(recent_material_ids=[MATERIALS[0].material_id] * cap)
    single_guarded = repetition_guard([trace_a], single_session, scheduler_params)
    if select_next(single_guarded) is None:
        raise InvariantFailure(
            "repetition guard suppressed the only admissible material, forcing no admission"
        )


def check_old_material_resurfaces() -> None:
    """04-v1-scheduler.md §30 "never revisiting older material." Material
    A is practiced, then only material B is available for a stretch, then
    both are candidates again - A's rising retention need should bring it
    back."""
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    instrument = InstrumentProfile()
    material_a, material_b = MATERIALS[0], MATERIALS[1]

    # Each phase's own SchedulerAgent has a fresh SessionState, and every
    # phase (20/15/20) stays comfortably under the safety cap on its
    # own - already session-shaped - but still guarded defensively:
    # this scenario isn't testing no-admission either.
    try:
        agent_a = SchedulerAgent(
            instrument, [material_a], scheduler_params, learner_params
        )
        trace, state, truth = run(
            "advanced",
            attempts=20,
            seed=2,
            params=learner_params,
            agent_pick=agent_a.pick,
            agent_on_outcome=agent_a.on_outcome,
        )
        now = trace[-1]["at_days"]

        agent_b = SchedulerAgent(
            instrument, [material_b], scheduler_params, learner_params
        )
        trace, state, truth = run(
            "advanced",
            attempts=15,
            seed=2,
            params=learner_params,
            state=state,
            truth=truth,
            start_now=now,
            agent_pick=agent_b.pick,
            agent_on_outcome=agent_b.on_outcome,
        )
        now = trace[-1]["at_days"]

        agent_both = SchedulerAgent(
            instrument, [material_a, material_b], scheduler_params, learner_params
        )
        run(
            "advanced",
            attempts=20,
            seed=2,
            params=learner_params,
            state=state,
            truth=truth,
            start_now=now,
            agent_pick=agent_both.pick,
            agent_on_outcome=agent_both.on_outcome,
        )
    except NoAdmittedCandidate as exc:
        raise InvariantFailure(
            f"scheduler produced no admitted candidate: {exc}"
        ) from exc

    selected_materials = {
        r.selected.exercise.material.material_id
        for r in agent_both.records
        if r.selected is not None
    }
    if material_a.material_id not in selected_materials:
        raise InvariantFailure(
            f"material A ({material_a.material_id}) never resurfaced across 20 "
            "phase-3 attempts after going unpracticed while B was worked"
        )


def check_new_material_introduction_is_learner_sensitive() -> None:
    """04-v1-scheduler.md §24.

    Originally identical first selections across profiles: I(e) read
    only competency variance (equal across tiers at cold start), and the
    old unconditional new_material bypass meant overall_p (which the
    mean drives) never gated admission either. Resolved by making
    new_material conditional on overall_p >= p_introduction_min (see
    challenge_bypass()) - the same overall_p every profile already
    produces, so which realizations clear it is naturally
    learner-sensitive.
    """
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    instrument = InstrumentProfile()

    beginner_state = initial_state(PROFILES["beginner"], learner_params)
    advanced_state = initial_state(PROFILES["advanced"], learner_params)
    agent_beginner = SchedulerAgent(
        instrument, MATERIALS, scheduler_params, learner_params
    )
    agent_advanced = SchedulerAgent(
        instrument, MATERIALS, scheduler_params, learner_params
    )

    try:
        first_beginner = agent_beginner.pick(random.Random(0), 0, beginner_state, 0.0)
        first_advanced = agent_advanced.pick(random.Random(0), 0, advanced_state, 0.0)
    except NoAdmittedCandidate as exc:
        raise InvariantFailure(
            f"scheduler produced no admitted candidate: {exc}"
        ) from exc

    if first_beginner == first_advanced:
        raise InvariantFailure(
            "first new-material selection was identical across beginner/advanced "
            f"profiles ({first_beginner.material.material_id}/{first_beginner.hands}) "
            "- see this check's docstring"
        )


def check_eligibility_progression() -> None:
    """04-v1-scheduler.md §5.1/§7.1. HT starts PROVISIONALLY_ELIGIBLE and
    becomes FULLY_ELIGIBLE only once RH/LH competency practice raises
    both means past the REQUIRES threshold.

    Uses the "advanced" TrueLearnerProfile with a manually depressed
    starting RH/LH mean, not the "beginner" profile: synthetic learners'
    true_competencies are fixed for the run (synthetic.py never improves
    them), and beginner's true competency (-1.5 flat) sits permanently
    below the REQUIRES threshold (0.0) - no amount of practice can
    converge a beginner's estimate past a true value that's itself below
    threshold. Starting an advanced-truth learner's belief artificially
    low (practice can genuinely converge toward the true 1.5) is what
    actually exercises progression rather than measuring a ceiling that
    can never be crossed.
    """
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    state = initial_state(PROFILES["advanced"], learner_params)
    state.competencies["RH_SCALE_EXECUTION"].mean = -0.3
    state.competencies["LH_SCALE_EXECUTION"].mean = -0.3
    ht_probe = fixed_exercise(MATERIALS[0], "TOGETHER")

    tier_before, _ = eligibility_tier(state, ht_probe, scheduler_params)
    if tier_before != "PROVISIONALLY_ELIGIBLE":
        raise InvariantFailure(
            "test setup error: expected the depressed starting means to give "
            f"PROVISIONALLY_ELIGIBLE, got {tier_before}"
        )

    def rh_lh_only(rng: random.Random, _i: int):
        return fixed_exercise(MATERIALS[0], rng.choice(["RIGHT", "LEFT"]))

    _trace, state, _truth = run(
        "advanced",
        attempts=300,
        seed=5,
        params=learner_params,
        exercise_fn=rh_lh_only,
        state=state,
    )

    tier_after, reason_after = eligibility_tier(state, ht_probe, scheduler_params)
    if tier_after != "FULLY_ELIGIBLE":
        raise InvariantFailure(
            f"expected FULLY_ELIGIBLE after 300 attempts of RH/LH practice, got "
            f"{tier_after} ({reason_after})"
        )


def check_failure_recovery_is_temporary() -> None:
    """04-v1-scheduler.md §6's named exceptions. Exercises
    SchedulerAgent.on_outcome's own bookkeeping (Pass 1's invariants
    already cover the pipeline's own handling of a given
    last_outcome_failed value): the recovery bypass should apply on the
    attempt right after a genuine failure and not on an attempt that
    followed a success (or an untested attempt)."""
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    instrument = InstrumentProfile()
    agent = SchedulerAgent(instrument, [MATERIALS[0]], scheduler_params, learner_params)

    # 30, not 40: comfortably under the default safety cap rather than
    # exactly at it, so this scenario can't accidentally start depending
    # on session-cap timing to make its point.
    try:
        run(
            "technique_strong_memory_weak",
            attempts=30,
            seed=6,
            params=learner_params,
            agent_pick=agent.pick,
            agent_on_outcome=agent.on_outcome,
        )
    except NoAdmittedCandidate as exc:
        raise InvariantFailure(
            f"scheduler produced no admitted candidate: {exc}"
        ) from exc

    saw_recovery_after_failure = False
    saw_no_recovery_after_non_failure = False
    for i in range(1, len(agent.records)):
        record = agent.records[i]
        prior_record = agent.records[i - 1]
        if record.selected is None or prior_record.outcome is None:
            continue
        # run()'s own JSON-lines trace doesn't carry retrieval_succeeded
        # (see AttemptRecord.outcome's docstring) - read the real Outcome
        # SchedulerAgent.on_outcome() stashed on the prior record instead.
        prior_outcome = prior_record.outcome.retrieval_succeeded
        used_recovery = record.selected.challenge_bypass == "recovery"

        if prior_outcome is False:
            saw_recovery_after_failure = saw_recovery_after_failure or used_recovery
        elif used_recovery:
            raise InvariantFailure(
                f"attempt {i}: recovery bypass applied even though the prior "
                f"attempt's outcome was {prior_outcome!r}, not a genuine failure - "
                "the recovery flag did not clear"
            )
        else:
            saw_no_recovery_after_non_failure = True

    if not saw_recovery_after_failure:
        raise InvariantFailure(
            "test setup error: no attempt followed a genuine retrieval failure "
            "with a recovery-bypassed selection in this run"
        )
    if not saw_no_recovery_after_non_failure:
        raise InvariantFailure(
            "test setup error: every attempt followed a failure - no non-failure "
            "baseline to confirm recovery clears"
        )


CHECKS: list[tuple[str, object]] = [
    (
        "guidance fades as memory strengthens",
        check_guidance_fades_as_memory_strengthens,
    ),
    ("no endless repetition of one material", check_no_endless_repetition),
    (
        "repetition guard prevents perseveration",
        check_repetition_guard_prevents_perseveration,
    ),
    ("old material resurfaces after going unpracticed", check_old_material_resurfaces),
    (
        "new-material introduction is learner-sensitive",
        check_new_material_introduction_is_learner_sensitive,
    ),
    ("eligibility progresses as RH/LH competency grows", check_eligibility_progression),
    ("failure recovery is temporary", check_failure_recovery_is_temporary),
]


def main() -> None:
    failures = 0
    for name, check in CHECKS:
        try:
            check()
        except InvariantFailure as exc:
            print(f"FAIL  {name}: {exc}")
            failures += 1
        except Exception as exc:  # noqa: BLE001 - surface any unexpected error as a failure
            print(f"ERROR {name}: {exc!r}")
            failures += 1
        else:
            print(f"PASS  {name}")

    print()
    print(f"{len(CHECKS) - failures}/{len(CHECKS)} scenarios passed")
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
