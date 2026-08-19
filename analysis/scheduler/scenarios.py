#!/usr/bin/env python3
"""Longitudinal behavioral scenarios for the scheduler pipeline
(docs/learner-model/04-v1-scheduler.md §10, Pass 2).

Mirrors ../learner-model/invariants.py's plain-assertion, printed
pass/fail style, per §10's own instruction. Deliberately separate from
invariants.py (Pass 1's boundary/mechanical-correctness checks): these
ask a different question - "does the pipeline behave well over
repeated scheduler -> outcome -> learner-update -> scheduler cycles,"
not "does a forbidden input move a stage's decision." A FAIL here can
be a genuine, useful Pass-2 finding about Pass 1's deliberately simple
placeholders (see scenarios 2 and 4's docstrings), not necessarily a
regression to fix before moving on - see the Pass-2 plan.

Usage:
    python scenarios.py
"""

from __future__ import annotations

import random
import sys
from itertools import pairwise
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "learner-model"))

from candidates import InstrumentProfile
from config import load_params as load_scheduler_params
from longitudinal import NoAdmittedCandidate, SchedulerAgent
from params import load_params as load_learner_params
from pipeline import eligibility_tier
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

    Verified by direct inspection over a corrected, uncontaminated
    multi-session run - the fuller picture than either of this check's
    two earlier drafts assumed. The scheduler does *not* simply prefer
    guidance from the start: session 1 (20 attempts) stays fully
    unguided, repeatedly using the recovery bypass as unguided retrieval
    keeps failing. But partway into session 2 it shifts to the
    maximally-cued variant and then never leaves - every remaining
    attempt through the end of session 3 stays fully cued. A cued
    attempt has retrieval_succeeded=None (never tested, §18.2 -
    correctly, not a bug), so MaterialMemoryState's clock can never
    re-anchor once the scheduler is in that state; independent_retrieval_p
    can then only keep decaying, which keeps making the cued variant the
    only (or most rewarded) admissible one. That's §30's named pathology
    taken literally: once guidance is reached, it never fades back
    toward independence, because the one thing that would let it happen
    - a genuinely tested retrieval - is exactly what the trapped state
    avoids. A real, informative Pass-2 characterization, not a
    regression to patch here.
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

    Expected finding, not a bug to pre-fix: verified by direct
    inspection (not guessed), the actual observed mechanism is a
    guidance/memory feedback trap, not a simple R-vs-I tie. One early
    unguided success anchors MaterialMemoryState's clock
    (last_retrieval_at, §5.2). From then on the scheduler keeps
    selecting a fully-cued variant of the same material - cueing raises
    material_available_p, so a cued candidate is the one most likely to
    clear the challenge band. But a cued attempt has
    retrieval_succeeded=None (never tested, §18.2 - correctly, not a
    bug), so the clock is never reset. Elapsed time since that one
    anchor grows every attempt, decaying independent_retrieval_p
    unboundedly, which keeps raising R = 1 - independent_retrieval_p
    (§23's simplest form), which keeps making this material win the
    ranking - a self-sustaining trap where leaning on guidance
    perpetuates the very weakness that justified leaning on it. That's a
    genuine, informative Pass-2 characterization (a variant of §30's
    "guidance removed before independent retrieval is plausible," run in
    reverse), not a regression to patch here.
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

    Expected finding, not a bug to pre-fix: information() reads only
    competency VARIANCE, and initial_state() sets the same
    prior_variance_broad regardless of self-report tier - only the MEAN
    differs by tier. A never-practiced material's new_material bypass
    also means overall_p (which the mean does drive) never gates
    admission. So under Pass 1's placeholders, the first new-material
    selection may legitimately be identical across profiles; that's a
    real characterization of I(e)'s current form (04-v1-scheduler.md
    §9), not a regression to patch here.
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
