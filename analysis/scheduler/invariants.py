#!/usr/bin/env python3
"""Scripted boundary/mechanical-correctness checks for the scheduler
pipeline prototype (Pass 1 scope only).

Mirrors ../learner-model/invariants.py's plain-assertion, printed
pass/fail style. These checks prove the four-stage information-boundary
contract (docs/learner-model/04-v1-scheduler.md) holds mechanically -
that a forbidden input can't move a stage's decision, and that the trace
correctly distinguishes real pipeline execution from counterfactual
diagnostics. They do NOT test behavioral quality (guidance fading, no
endless repetition, etc.) - that's §10, Pass 2, not built yet.

Usage:
    python invariants.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "learner-model"))

from candidates import (
    InstrumentProfile,
    SessionState,
    generate_candidates,
)
from config import load_params as load_scheduler_params
from domain import GuidanceContext
from model import Prediction
from params import load_params as load_learner_params
from pipeline import (
    StageStatus,
    _guidance_probe_eligible,
    eligibility_tier,
    recovery_target,
    run_pipeline,
    safety_check,
    select_next,
)
from simulate import MATERIALS, fixed_exercise, initial_state
from state import COMPETENCIES
from synthetic import PROFILES


class InvariantFailure(Exception):
    pass


def _seed_all_materials(state, learner_params) -> None:
    """Gives every material a MaterialMemoryState entry at its default
    prior - mathematically identical to having none (retrievability_or_
    prior() falls back to the same prior either way), so this changes
    nothing about any Prediction. It only removes candidates from the
    new_material challenge exception, letting genuine
    within/outside-band behavior be observed."""
    for material in MATERIALS:
        state.material_memory_for(material.material_id, learner_params)


def check_generation_depends_only_on_domain_inputs() -> None:
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    instrument = InstrumentProfile()

    beginner_state = initial_state(PROFILES["beginner"], learner_params)
    advanced_state = initial_state(PROFILES["advanced"], learner_params)
    session_a = SessionState()
    session_b = SessionState(
        attempts_this_session=30,
        recent_material_ids=["C_MAJOR", "C_MAJOR"],
        last_failed_exercise=fixed_exercise(MATERIALS[0], "RIGHT"),
    )

    candidates_a = generate_candidates(instrument, MATERIALS)
    candidates_b = generate_candidates(instrument, MATERIALS)
    traces_a = run_pipeline(
        beginner_state, session_a, candidates_a, scheduler_params, learner_params, 0.0
    )
    traces_b = run_pipeline(
        advanced_state, session_b, candidates_b, scheduler_params, learner_params, 0.0
    )

    set_a = {t.exercise for t in traces_a}
    set_b = {t.exercise for t in traces_b}
    if set_a != set_b:
        raise InvariantFailure(
            f"generated candidate set changed with learner/session state: "
            f"{len(set_a)} vs {len(set_b)} candidates"
        )


def check_eligibility_depends_only_on_competencies() -> None:
    import math

    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    state = initial_state(PROFILES["advanced"], learner_params)
    exercise = fixed_exercise(MATERIALS[0], "TOGETHER")

    tier1, _ = eligibility_tier(state, exercise, scheduler_params)

    material_id = MATERIALS[0].material_id
    state.material_memory_for(material_id, learner_params)
    memory = state.material_memory[material_id]
    memory.log_current_half_life = math.log(0.001)
    memory.log_consolidated_half_life = math.log(0.001)
    state.material_execution_for(material_id, "TOGETHER", 0.0, learner_params)
    state.material_execution[(material_id, "TOGETHER")].residual_mean = -5.0

    tier2, _ = eligibility_tier(state, exercise, scheduler_params)
    if tier1 != tier2:
        raise InvariantFailure(
            f"eligibility tier changed from memory/execution variation alone: {tier1} -> {tier2}"
        )

    state.competencies["RH_SCALE_EXECUTION"].mean = -5.0
    state.competencies["LH_SCALE_EXECUTION"].mean = -5.0
    tier3, _ = eligibility_tier(state, exercise, scheduler_params)
    if tier3 != "PROVISIONALLY_ELIGIBLE":
        raise InvariantFailure(
            f"expected PROVISIONALLY_ELIGIBLE after lowering RH/LH means, got {tier3}"
        )


def check_safety_depends_only_on_session() -> None:
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    instrument = InstrumentProfile()
    candidates = generate_candidates(instrument, MATERIALS)[:50]

    beginner_state = initial_state(PROFILES["beginner"], learner_params)
    advanced_state = initial_state(PROFILES["advanced"], learner_params)
    session = SessionState(attempts_this_session=5)

    traces_a = run_pipeline(
        beginner_state, session, candidates, scheduler_params, learner_params, 0.0
    )
    traces_b = run_pipeline(
        advanced_state, session, candidates, scheduler_params, learner_params, 0.0
    )
    for ta, tb in zip(traces_a, traces_b, strict=True):
        if (
            ta.safety_allowed != tb.safety_allowed
            or ta.safety_reason != tb.safety_reason
        ):
            raise InvariantFailure("safety decision changed with learner state alone")

    cap = scheduler_params.safety.max_session_attempts
    allowed_under, _ = safety_check(
        SessionState(attempts_this_session=cap - 1), scheduler_params
    )
    allowed_at, _ = safety_check(
        SessionState(attempts_this_session=cap), scheduler_params
    )
    if not allowed_under or allowed_at:
        raise InvariantFailure(
            "safety suppression did not trigger exactly at the session cap"
        )


def check_challenge_band_ignores_priority_terms() -> None:
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    state = initial_state(PROFILES["beginner"], learner_params)
    _seed_all_materials(state, learner_params)
    candidates = generate_candidates(InstrumentProfile(), MATERIALS)

    session_a = SessionState()
    session_b = SessionState(
        attempts_this_session=3, recent_material_ids=["C_MAJOR"] * 5
    )
    traces_a = run_pipeline(
        state, session_a, candidates, scheduler_params, learner_params, 0.0
    )
    traces_b = run_pipeline(
        state, session_b, candidates, scheduler_params, learner_params, 0.0
    )

    by_exercise_b = {t.exercise: t for t in traces_b}
    for ta in traces_a:
        tb = by_exercise_b[ta.exercise]
        if ta.challenge_within_band != tb.challenge_within_band:
            raise InvariantFailure(
                "challenge_within_band changed when only R/I/V/G-relevant session "
                "history (diversity) changed"
            )


def check_challenge_bypass_is_independent_of_band() -> None:
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    instrument = InstrumentProfile()
    candidates = generate_candidates(instrument, MATERIALS)

    fresh_state = initial_state(PROFILES["beginner"], learner_params)
    traces_fresh = run_pipeline(
        fresh_state, SessionState(), candidates, scheduler_params, learner_params, 0.0
    )

    seeded_state = initial_state(PROFILES["beginner"], learner_params)
    _seed_all_materials(seeded_state, learner_params)
    traces_seeded = run_pipeline(
        seeded_state, SessionState(), candidates, scheduler_params, learner_params, 0.0
    )

    by_exercise_seeded = {t.exercise: t for t in traces_seeded}
    saw_bypass_change = False
    for t_fresh in traces_fresh:
        t_seeded = by_exercise_seeded[t_fresh.exercise]
        if t_fresh.challenge_within_band != t_seeded.challenge_within_band:
            raise InvariantFailure(
                "challenge_within_band changed when only bypass-affecting state "
                "(material-memory existence) changed"
            )
        if t_fresh.challenge_bypass != t_seeded.challenge_bypass:
            saw_bypass_change = True
    if not saw_bypass_change:
        raise InvariantFailure(
            "expected challenge_bypass to differ between fresh and pre-seeded material state"
        )


def check_provisional_tier_never_outranks_fully_eligible() -> None:
    """Real run_pipeline() exercise, not two hand-built CandidateTraces
    with rank_key set directly from _TIER_RANK (which would prove
    select_next() sorts tuples correctly but nothing about whether
    run_pipeline() itself derives the tier portion of rank_key right -
    e.g. a bug hardcoding rank_key's first element to 0 for every
    candidate would still pass a test built that way, the same
    structural gap the original check 8 had).

    Two different materials so R/I/V can be pushed independently: the
    provisional candidate is stacked to dominate every secondary
    criterion, so a pass can only mean tier - not R/I/V/G - decided it.
    """
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()

    material_provisional = MATERIALS[0]  # C_MAJOR
    material_fully = MATERIALS[3]  # A_NATURAL_MINOR
    ex_provisional = fixed_exercise(material_provisional, "TOGETHER")
    ex_fully = fixed_exercise(material_fully, "RIGHT")

    # beginner's default RH/LH means sit below the REQUIRES threshold, so
    # the TOGETHER exercise is genuinely PROVISIONALLY_ELIGIBLE; the
    # RIGHT-hand exercise has no REQUIRES relationship at all (§5.1), so
    # it's genuinely FULLY_ELIGIBLE regardless of competency.
    state = initial_state(PROFILES["beginner"], learner_params)

    # I(e): flatten every competency's variance, then inflate only the
    # ones exclusive to ex_provisional (MAJOR_SCALE_TOPOLOGY,
    # LH_SCALE_EXECUTION, HANDS_TOGETHER_COORDINATION - ex_fully touches
    # none of these), so ex_provisional's information() is dominated by
    # a huge margin while ex_fully's stays at the flat floor.
    for cid in COMPETENCIES:
        state.competencies[cid].variance = 0.05
    for cid in (
        "MAJOR_SCALE_TOPOLOGY",
        "LH_SCALE_EXECUTION",
        "HANDS_TOGETHER_COORDINATION",
    ):
        state.competencies[cid].variance = 100.0

    # V(e): penalize only ex_fully's material via recent session history.
    session = SessionState(recent_material_ids=[material_fully.material_id] * 5)

    traces = run_pipeline(
        state,
        session,
        [ex_provisional, ex_fully],
        scheduler_params,
        learner_params,
        0.0,
        overrides={ex_provisional: "override", ex_fully: "override"},
    )
    by_exercise = {t.exercise: t for t in traces}
    provisional = by_exercise[ex_provisional]
    fully = by_exercise[ex_fully]

    if provisional.eligibility_tier != "PROVISIONALLY_ELIGIBLE":
        raise InvariantFailure(
            "test setup error: expected ex_provisional to be PROVISIONALLY_ELIGIBLE, "
            f"got {provisional.eligibility_tier}"
        )
    if fully.eligibility_tier != "FULLY_ELIGIBLE":
        raise InvariantFailure(
            f"test setup error: expected ex_fully to be FULLY_ELIGIBLE, got {fully.eligibility_tier}"
        )
    if not (
        provisional.retention >= fully.retention
        and provisional.information > fully.information
        and provisional.diversity > fully.diversity
    ):
        raise InvariantFailure(
            "test setup error: the provisional candidate does not actually "
            f"dominate R/I/V (R={provisional.retention} vs {fully.retention}, "
            f"I={provisional.information} vs {fully.information}, "
            f"V={provisional.diversity} vs {fully.diversity})"
        )

    winner = select_next(traces)
    if winner is not fully:
        raise InvariantFailure(
            "a PROVISIONALLY_ELIGIBLE candidate that dominates every R/I/V/G term "
            "still outranked a FULLY_ELIGIBLE one via run_pipeline's real rank_key"
        )


def check_only_reached_priority_status_is_ranked() -> None:
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    state = initial_state(PROFILES["advanced"], learner_params)
    _seed_all_materials(state, learner_params)
    candidates = generate_candidates(InstrumentProfile(), MATERIALS)

    cap = scheduler_params.safety.max_session_attempts
    suppressed_traces = run_pipeline(
        state,
        SessionState(attempts_this_session=cap),
        candidates,
        scheduler_params,
        learner_params,
        0.0,
    )
    if any(t.priority_status is StageStatus.REACHED for t in suppressed_traces):
        raise InvariantFailure(
            "a safety-suppressed session still produced a REACHED priority_status"
        )
    if any(t.rank_key is not None for t in suppressed_traces):
        raise InvariantFailure(
            "a safety-suppressed candidate carried a non-None rank_key"
        )
    if not all(isinstance(t.prediction, Prediction) for t in suppressed_traces):
        raise InvariantFailure(
            "safety-suppressed candidates lost their diagnostic Prediction"
        )
    if select_next(suppressed_traces) is not None:
        raise InvariantFailure(
            "select_next returned a candidate despite session-wide safety suppression"
        )

    traces = run_pipeline(
        state, SessionState(), candidates, scheduler_params, learner_params, 0.0
    )
    rejected = [
        t for t in traces if t.challenge_bypass is None and not t.challenge_within_band
    ]
    if not rejected:
        raise InvariantFailure(
            "no genuinely-rejected (non-exception) candidate found to test against"
        )
    for t in rejected:
        if t.priority_status is StageStatus.REACHED:
            raise InvariantFailure(
                "a challenge-rejected, non-exception candidate reached priority ranking"
            )
        if t.rank_key is not None:
            raise InvariantFailure(
                "a challenge-rejected, non-exception candidate carried a non-None rank_key"
            )
        if t.challenge_survived:
            raise InvariantFailure(
                "challenge_survived was True despite no bypass and outside the band"
            )

    winner = select_next(traces)
    if winner is None or winner.priority_status is not StageStatus.REACHED:
        raise InvariantFailure(
            "select_next did not return a genuinely REACHED candidate"
        )


def check_named_exceptions_bypass_challenge_and_reach_priority() -> None:
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    candidates = generate_candidates(InstrumentProfile(), MATERIALS)

    fresh_state = initial_state(PROFILES["beginner"], learner_params)
    traces = run_pipeline(
        fresh_state, SessionState(), candidates, scheduler_params, learner_params, 0.0
    )
    new_material_traces = [t for t in traces if t.challenge_bypass == "new_material"]
    if not new_material_traces:
        raise InvariantFailure(
            "expected some new_material bypasses on a fresh LearnerState"
        )
    for t in new_material_traces:
        if not t.challenge_survived or t.priority_status is not StageStatus.REACHED:
            raise InvariantFailure(
                "new_material bypass did not survive/reach priority ranking"
            )

    # Recovery is exclusive (04-v1-scheduler.md §6, Pass-2b): with a
    # recovery context active, only the exact one-step-more-guidance
    # sibling of the failed exercise may survive - not "some candidate
    # gets a recovery label," everything else must be excluded even if
    # it would otherwise be within-band or new_material-eligible.
    seeded_state = initial_state(PROFILES["beginner"], learner_params)
    _seed_all_materials(seeded_state, learner_params)
    failed_exercise = fixed_exercise(MATERIALS[0], "RIGHT")
    target = recovery_target(failed_exercise)
    recovery_traces = run_pipeline(
        seeded_state,
        SessionState(last_failed_exercise=failed_exercise),
        candidates,
        scheduler_params,
        learner_params,
        0.0,
    )
    survivors = [t for t in recovery_traces if t.challenge_survived]
    if len(survivors) != 1 or survivors[0].exercise != target:
        raise InvariantFailure(
            f"expected exactly the recovery target ({target}) to survive, got "
            f"{[t.exercise for t in survivors]}"
        )
    if (
        survivors[0].challenge_bypass != "recovery"
        or survivors[0].priority_status is not StageStatus.REACHED
    ):
        raise InvariantFailure(
            "recovery target did not survive via the recovery bypass / reach "
            "priority ranking"
        )

    one_candidate = candidates[0]
    override_traces = run_pipeline(
        seeded_state,
        SessionState(),
        [one_candidate],
        scheduler_params,
        learner_params,
        0.0,
        overrides={one_candidate: "override"},
    )
    t = override_traces[0]
    if (
        t.challenge_bypass != "override"
        or not t.challenge_survived
        or t.priority_status is not StageStatus.REACHED
    ):
        raise InvariantFailure("override bypass did not survive/reach priority ranking")


def check_priority_does_not_reconsume_challenge_difficulty() -> None:
    """Real run_pipeline() exercise, not two hand-built CandidateTraces
    with a rank_key set equal by construction (which would prove nothing
    about run_pipeline's actual derivation). Raising RH_SCALE_EXECUTION's
    mean moves execution_p (and so overall_p) sharply, but touches none
    of R (memory-only), I (variance-only, not mean), V (session-only), or
    G (constant) - so rank_key must come out identical for both."""
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    exercise = fixed_exercise(MATERIALS[0], "RIGHT")

    state_low = initial_state(PROFILES["beginner"], learner_params)
    state_high = initial_state(PROFILES["beginner"], learner_params)
    state_high.competencies["RH_SCALE_EXECUTION"].mean = 20.0
    _seed_all_materials(state_low, learner_params)
    _seed_all_materials(state_high, learner_params)

    session = SessionState()
    # override forces admission regardless of where overall_p lands, so
    # this isolates stage 4 from stage 3's own (correct) sensitivity to
    # overall_p.
    traces_low = run_pipeline(
        state_low,
        session,
        [exercise],
        scheduler_params,
        learner_params,
        0.0,
        overrides={exercise: "override"},
    )
    traces_high = run_pipeline(
        state_high,
        session,
        [exercise],
        scheduler_params,
        learner_params,
        0.0,
        overrides={exercise: "override"},
    )
    t_low, t_high = traces_low[0], traces_high[0]

    if abs(t_low.prediction.overall_p - t_high.prediction.overall_p) < 0.1:
        raise InvariantFailure(
            f"test setup error: overall_p did not differ enough between scenarios "
            f"({t_low.prediction.overall_p:.3f} vs {t_high.prediction.overall_p:.3f})"
        )
    if t_low.rank_key != t_high.rank_key:
        raise InvariantFailure(
            f"rank_key changed ({t_low.rank_key} -> {t_high.rank_key}) from a "
            "competency-mean change that only moved overall_p, holding R/I/V/G's "
            "own inputs (memory, variance, session) fixed"
        )


def check_information_term_does_not_leak_into_challenge() -> None:
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    state_a = initial_state(PROFILES["beginner"], learner_params)
    state_b = initial_state(PROFILES["beginner"], learner_params)
    for cid in COMPETENCIES:
        state_b.competencies[cid].variance = state_a.competencies[cid].variance * 50.0
    _seed_all_materials(state_a, learner_params)
    _seed_all_materials(state_b, learner_params)

    candidates = generate_candidates(InstrumentProfile(), MATERIALS)
    traces_a = run_pipeline(
        state_a, SessionState(), candidates, scheduler_params, learner_params, 0.0
    )
    traces_b = run_pipeline(
        state_b, SessionState(), candidates, scheduler_params, learner_params, 0.0
    )

    by_exercise_b = {t.exercise: t for t in traces_b}
    saw_information_difference = False
    for ta in traces_a:
        tb = by_exercise_b[ta.exercise]
        if abs(ta.information - tb.information) > 1e-9:
            saw_information_difference = True
        if (
            ta.challenge_within_band != tb.challenge_within_band
            or ta.challenge_bypass != tb.challenge_bypass
        ):
            raise InvariantFailure(
                "challenge decision changed when only competency variance (I(e)'s input) changed"
            )
    if not saw_information_difference:
        raise InvariantFailure(
            "expected I(e) to differ once competency variance was scaled up"
        )


def check_anchor_movement_does_not_reset_guidance_probe_history() -> None:
    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    state = initial_state(PROFILES["advanced"], learner_params)
    material = MATERIALS[0]
    memory = state.material_memory_for(material.material_id, learner_params)
    memory.memory_anchor_at = 0.0
    memory.factual_last_retrieval_at = 0.0
    memory.last_retrieval_attempt_at = 0.0
    exercise = fixed_exercise(
        material, "RIGHT", guidance=GuidanceContext(notes_previewed=True)
    )
    now = scheduler_params.guidance_probe.min_days_since_last_retrieval + 1.0
    if not _guidance_probe_eligible(state, exercise, now, scheduler_params):
        raise InvariantFailure(
            "test setup error: factual history was not probe-eligible"
        )

    # Simulate supported-practice activation restoration without changing the
    # factual successful-retrieval event. If probe timing read the anchor, this
    # would make the same candidate too recent.
    memory.memory_anchor_at = now - 0.1
    if not _guidance_probe_eligible(state, exercise, now, scheduler_params):
        raise InvariantFailure("activation movement reset factual probe history")


def check_consolidation_alone_has_no_immediate_scheduler_effect() -> None:
    import math

    learner_params = load_learner_params()
    scheduler_params = load_scheduler_params()
    instrument = InstrumentProfile()
    candidates = generate_candidates(instrument, MATERIALS)
    state_a = initial_state(PROFILES["advanced"], learner_params)
    state_b = initial_state(PROFILES["advanced"], learner_params)
    _seed_all_materials(state_a, learner_params)
    _seed_all_materials(state_b, learner_params)
    for memory in state_b.material_memory.values():
        memory.log_consolidated_half_life = math.log(30.0)

    traces_a = run_pipeline(
        state_a,
        SessionState(),
        candidates,
        scheduler_params,
        learner_params,
        0.0,
    )
    traces_b = run_pipeline(
        state_b,
        SessionState(),
        candidates,
        scheduler_params,
        learner_params,
        0.0,
    )
    by_exercise_b = {trace.exercise: trace for trace in traces_b}
    for trace_a in traces_a:
        trace_b = by_exercise_b[trace_a.exercise]
        immediate_a = (
            trace_a.eligibility_tier,
            trace_a.safety_allowed,
            trace_a.prediction,
            trace_a.challenge_within_band,
            trace_a.challenge_bypass,
            trace_a.challenge_survived,
            trace_a.retention,
            trace_a.information,
            trace_a.diversity,
            trace_a.goals,
            trace_a.rank_key,
        )
        immediate_b = (
            trace_b.eligibility_tier,
            trace_b.safety_allowed,
            trace_b.prediction,
            trace_b.challenge_within_band,
            trace_b.challenge_bypass,
            trace_b.challenge_survived,
            trace_b.retention,
            trace_b.information,
            trace_b.diversity,
            trace_b.goals,
            trace_b.rank_key,
        )
        if immediate_a != immediate_b:
            raise InvariantFailure(
                "consolidation-only variation changed an immediate scheduler input"
            )


CHECKS: list[tuple[str, object]] = [
    (
        "generation depends only on domain inputs",
        check_generation_depends_only_on_domain_inputs,
    ),
    (
        "eligibility tier depends only on competencies",
        check_eligibility_depends_only_on_competencies,
    ),
    (
        "safety suppression depends only on session state",
        check_safety_depends_only_on_session,
    ),
    (
        "challenge band ignores priority (R/I/V/G) terms",
        check_challenge_band_ignores_priority_terms,
    ),
    (
        "challenge bypass is independent of the band decision",
        check_challenge_bypass_is_independent_of_band,
    ),
    (
        "a provisional tier never outranks a fully-eligible one",
        check_provisional_tier_never_outranks_fully_eligible,
    ),
    (
        "only REACHED priority_status candidates are ranked",
        check_only_reached_priority_status_is_ranked,
    ),
    (
        "named exceptions bypass challenge and reach priority ranking",
        check_named_exceptions_bypass_challenge_and_reach_priority,
    ),
    (
        "priority ranking does not re-consume challenge difficulty",
        check_priority_does_not_reconsume_challenge_difficulty,
    ),
    (
        "the information term does not leak into challenge admission",
        check_information_term_does_not_leak_into_challenge,
    ),
    (
        "activation movement does not reset factual guidance-probe history",
        check_anchor_movement_does_not_reset_guidance_probe_history,
    ),
    (
        "consolidation alone has no immediate scheduler effect",
        check_consolidation_alone_has_no_immediate_scheduler_effect,
    ),
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
    print(f"{len(CHECKS) - failures}/{len(CHECKS)} invariants passed")
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
