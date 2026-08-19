"""Stages 2-4 (eligibility, challenge filtering, priority ranking),
CandidateTrace, and run_pipeline().

Every candidate gets a fully populated CandidateTrace regardless of
whether an earlier stage's real decision would have excluded it - that's
the traceability property this prototype exists to establish. But a
computed value is not the same claim as "the real pipeline consulted
this": StageStatus keeps that distinction explicit rather than implicit
in whether a field happens to be populated. See
docs/learner-model/04-v1-scheduler.md for the boundary contract this
implements.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from candidates import SessionState
from config import Params as SchedulerParams
from domain import MOTOR_COMPETENCIES, TOPOLOGY_COMPETENCIES, Exercise, structural_q
from model import Prediction, motor_loadings, predicted_success, topology_loadings
from params import Params as LearnerParams
from state import COMPETENCIES, LearnerState

_TIER_RANK = {"PROVISIONALLY_ELIGIBLE": 0, "FULLY_ELIGIBLE": 1}


class StageStatus(Enum):
    """REACHED: the real pipeline reached this stage for this candidate
    (which path through the stage controlled the outcome - band vs.
    bypass, for challenge - is a separate question, answered by that
    stage's own fields, e.g. challenge_bypass). NOT_REACHED: an earlier
    stage's real decision already excluded this candidate; any value
    stored alongside is diagnostic-only, not evidence the stage ran."""

    REACHED = "reached"
    NOT_REACHED = "not_reached"


@dataclass
class CandidateTrace:
    exercise: Exercise

    # Stage 2a: REQUIRES (§5.1, soft - never suppresses, always evaluated)
    eligibility_tier: str  # FULLY_ELIGIBLE | PROVISIONALLY_ELIGIBLE
    eligibility_reason: str

    # Stage 2b: SchedulerSafetyPolicy (§5.2, hard - can suppress)
    safety_allowed: bool
    safety_reason: str

    # Stage 3: challenge filtering (§6). within_band/bypass/survived are
    # ALWAYS computed (diagnostic value); challenge_status says whether
    # that computation reflects the real pipeline (safety allowed it
    # through) or is counterfactual (safety suppressed this candidate
    # first, so stage 3 never actually ran for it).
    challenge_status: StageStatus
    prediction: Prediction
    challenge_within_band: bool
    challenge_bypass: str | None  # new_material | recovery | override | None
    challenge_survived: bool  # within_band or bypass is not None

    # Stage 4: priority ranking (§7). R/I/V/G are ALWAYS computed
    # (diagnostic); rank_key is the actual-ranking indicator and is None
    # whenever priority_status is NOT_REACHED, never populated
    # speculatively.
    priority_status: StageStatus
    retention: float
    information: float
    diversity: float
    goals: float
    rank_key: tuple[int, float, float, float, float] | None


def eligibility_tier(
    state: LearnerState, exercise: Exercise, params: SchedulerParams
) -> tuple[str, str]:
    """Stage 2a (§5.1). Reads LatentCompetencyState only. Only
    relationship implemented: RH/LH -> HANDS_TOGETHER_COORDINATION;
    everything else defaults to FULLY_ELIGIBLE ("REQUIRES relationships
    beyond the RH/LH -> HT example" stays open, §9)."""
    if exercise.hands != "TOGETHER":
        return "FULLY_ELIGIBLE", "no REQUIRES relationship defined for this exercise"
    threshold = params.eligibility.hand_together_competency_threshold
    rh = state.competencies["RH_SCALE_EXECUTION"].mean
    lh = state.competencies["LH_SCALE_EXECUTION"].mean
    if rh >= threshold and lh >= threshold:
        return (
            "FULLY_ELIGIBLE",
            f"RH/LH means ({rh:.2f}/{lh:.2f}) meet threshold ({threshold:.2f})",
        )
    return (
        "PROVISIONALLY_ELIGIBLE",
        f"RH/LH means ({rh:.2f}/{lh:.2f}) below threshold ({threshold:.2f})",
    )


def safety_check(session: SessionState, params: SchedulerParams) -> tuple[bool, str]:
    """Stage 2b (§5.2). Reads SessionState only."""
    cap = params.safety.max_session_attempts
    attempts = session.attempts_this_session
    if attempts >= cap:
        return False, f"session attempt cap reached ({attempts}/{cap})"
    return True, f"within session attempt cap ({attempts}/{cap})"


def challenge_within_band(prediction: Prediction, params: SchedulerParams) -> bool:
    """Stage 3 (§6). Reads Prediction.overall_p for this candidate only."""
    return params.challenge.p_min <= prediction.overall_p <= params.challenge.p_max


def _guidance_probe_eligible(
    state: LearnerState, exercise: Exercise, now: float, params: SchedulerParams
) -> bool:
    """One step down from full cueing only (notes_previewed, not
    concurrent_pitch_cues) - a successful probe is itself a genuine
    retrieval test (§18.2), so it can re-anchor the memory clock and let
    normal admission take over from there; no need to probe straight to
    fully unguided. Requires a prior confirmed success and enough
    elapsed time since it - probing again immediately would be
    redundant."""
    guidance = exercise.guidance
    if guidance.concurrent_pitch_cues or not guidance.notes_previewed:
        return False
    memory_state = state.material_memory[exercise.material.material_id]
    if memory_state.last_retrieval_at is None:
        return False
    elapsed = now - memory_state.last_retrieval_at
    return elapsed >= params.guidance_probe.min_days_since_last_retrieval


def challenge_bypass(
    state: LearnerState,
    exercise: Exercise,
    session: SessionState,
    prediction: Prediction,
    now: float,
    scheduler_params: SchedulerParams,
    override: str | None,
) -> str | None:
    """Named exceptions (§6).

    new_material: unseen material is admitted only through the
    introduction envelope (p_introduction_min <= overall_p), not
    unconditionally - a too-hard realization of new material is still
    rejected. The threshold applies to the same overall_p every learner
    profile already produces, so which specific realizations clear it is
    naturally learner-sensitive without branching on tier explicitly.

    recovery: the prior attempt in this session failed - checked before
    guidance_probe, so a failed probe doesn't immediately re-probe.

    guidance_probe: see _guidance_probe_eligible().

    override: caller-supplied, for diagnostic-probe/explicit-learner-
    request scenarios that aren't derivable from state alone.
    """
    if override is not None:
        return override
    if exercise.material.material_id not in state.material_memory:
        if prediction.overall_p >= scheduler_params.challenge.p_introduction_min:
            return "new_material"
        return None
    if session.last_outcome_failed:
        return "recovery"
    if _guidance_probe_eligible(state, exercise, now, scheduler_params):
        return "guidance_probe"
    return None


def _memory_uncertainty(
    state: LearnerState, material_id: str, learner_params: LearnerParams
) -> float:
    memory_state = state.material_memory.get(material_id)
    if memory_state is None:
        return learner_params.material_memory.prior_uncertainty
    if memory_state.last_retrieval_at is None:
        return memory_state.cold_start_uncertainty
    return memory_state.half_life_uncertainty


def retrieval_opportunity(exercise: Exercise) -> float:
    """How capable this specific candidate is of generating genuine
    retrieval evidence: retrieval_demand() when retrieval_observed()
    (matching model.py's real evidence_weights() memory_weight), 0.0
    when continuous cueing means retrieval isn't tested at all (§18.2 -
    retrieval_succeeded stays None, categorically, not a weak signal).
    Shared by retention() and information() so both read the same
    guidance-derived evidence-capacity concept rather than each
    reimplementing it - exactly the kind of duplicated-but-drifting
    signal this project keeps finding and removing."""
    guidance = exercise.guidance
    if not guidance.retrieval_observed():
        return 0.0
    return guidance.retrieval_demand()


def retention_need(prediction: Prediction) -> float:
    """Material-level retention urgency: 1 - M (§23's simplest form,
    ignoring uncertainty for this pass). A property of the material's
    memory state alone, independent of which candidate is asking - see
    retention() for the candidate-actionable version actually used in
    ranking."""
    return 1.0 - prediction.independent_retrieval_p


def retention(prediction: Prediction, exercise: Exercise) -> float:
    """R(e), §7.2. retention_need(material) scaled by whether THIS
    candidate can actually act on it, not copied onto every guidance
    variant unconditionally.

    Pass-2 scenarios 1 and 2 (04-v1-scheduler.md §10) found the
    unconditional form's failure mode directly: once the scheduler
    shifted to a continuously-cued variant, retrieval was correctly
    never tested (retrieval_succeeded stays None), so
    MaterialMemoryState's clock could never re-anchor;
    independent_retrieval_p then only decayed further, making R rise
    without bound and entrenching the exact candidate whose every
    attempt left that retention need exactly as unresolved as before.
    Multiplying by retrieval_opportunity(e) means a candidate that
    cannot supply retrieval evidence cannot win priority ranking on the
    strength of a retrieval deficit it structurally cannot remediate -
    without resetting the memory clock itself, which would manufacture
    evidence the learner model explicitly never observed."""
    return retention_need(prediction) * retrieval_opportunity(exercise)


def information(
    state: LearnerState, exercise: Exercise, learner_params: LearnerParams
) -> float:
    """I(e), §7.2: candidate-specific expected uncertainty reduction, not
    merely current-uncertainty lookup. Weights reuse the same
    guidance-derived quantities model.py's real evidence_weights() uses,
    via retrieval_opportunity(). Read-only: never creates a
    MaterialMemoryState/MaterialExecutionState entry, so computing this
    is never itself evidence.

    A capability-weighted variant (multiplying each term by execution_p/
    independent_retrieval_p) was tried and reverted: it re-derived the
    same difficulty structure challenge filtering already consumes
    (execution_p = sigmoid(competency - difficulty)), violating the
    "priority ranking does not re-consume challenge difficulty" boundary
    invariant, and it didn't even change the scenario 4 outcome it was
    meant to fix. See 04-v1-scheduler.md Pass-2 notes."""
    q = structural_q(exercise)
    motor_q = motor_loadings(q)
    topology_q = topology_loadings(q)
    retrieval_demand = exercise.guidance.retrieval_demand()

    competency_term = 0.0
    for c in COMPETENCIES:
        variance = state.competencies[c].variance
        if c in MOTOR_COMPETENCIES:
            loading, weight = motor_q[c], 1.0
        else:
            assert c in TOPOLOGY_COMPETENCIES
            loading, weight = topology_q[c], retrieval_demand
        competency_term += variance * loading * weight

    material_id = exercise.material.material_id
    memory_uncertainty = _memory_uncertainty(state, material_id, learner_params)
    memory_term = memory_uncertainty * retrieval_opportunity(exercise)

    execution_state = state.material_execution.get((material_id, exercise.hands))
    execution_variance = (
        execution_state.residual_variance
        if execution_state is not None
        else learner_params.material_execution.prior_variance
    )
    execution_term = execution_variance * 1.0

    return competency_term + memory_term + execution_term


def diversity(exercise: Exercise, session: SessionState) -> float:
    """V(e), §7.2/§9: simple recency count over a fixed window, not
    decayed. Higher (less recently seen) is better, matching R/I/G's
    higher-is-better convention."""
    count = session.recent_material_ids.count(exercise.material.material_id)
    return -float(count)


def goals(exercise: Exercise) -> float:
    """G(e), §9: no goals data model exists yet; explicitly stubbed at
    0, not faked."""
    del exercise
    return 0.0


def run_pipeline(
    state: LearnerState,
    session: SessionState,
    candidates: list[Exercise],
    scheduler_params: SchedulerParams,
    learner_params: LearnerParams,
    now: float,
    overrides: dict[Exercise, str] | None = None,
) -> list[CandidateTrace]:
    """Computes every stage's diagnostic value for every candidate, but
    derives challenge_status/priority_status from the real upstream
    decisions and only sets rank_key when priority_status is REACHED -
    mirroring how learner-model's harness always records
    state_before/state_after regardless of which update branch ran,
    while keeping the actual decision unambiguous.

    overrides maps a candidate to a caller-supplied challenge_bypass
    reason (diagnostic probe / explicit learner request, §6) - these
    aren't derivable from state alone, so scripted scenarios supply them
    explicitly rather than the pipeline guessing.
    """
    overrides = overrides or {}
    traces: list[CandidateTrace] = []

    for exercise in candidates:
        tier, tier_reason = eligibility_tier(state, exercise, scheduler_params)
        allowed, safety_reason = safety_check(session, scheduler_params)

        prediction = predicted_success(state, exercise, now, learner_params)
        within_band = challenge_within_band(prediction, scheduler_params)
        bypass = challenge_bypass(
            state,
            exercise,
            session,
            prediction,
            now,
            scheduler_params,
            overrides.get(exercise),
        )
        survived = within_band or bypass is not None
        challenge_status = StageStatus.REACHED if allowed else StageStatus.NOT_REACHED

        r = retention(prediction, exercise)
        i = information(state, exercise, learner_params)
        v = diversity(exercise, session)
        g = goals(exercise)
        priority_reached = challenge_status is StageStatus.REACHED and survived
        priority_status = (
            StageStatus.REACHED if priority_reached else StageStatus.NOT_REACHED
        )
        rank_key = (
            (_TIER_RANK[tier], r, i, v, g)
            if priority_status is StageStatus.REACHED
            else None
        )

        traces.append(
            CandidateTrace(
                exercise=exercise,
                eligibility_tier=tier,
                eligibility_reason=tier_reason,
                safety_allowed=allowed,
                safety_reason=safety_reason,
                challenge_status=challenge_status,
                prediction=prediction,
                challenge_within_band=within_band,
                challenge_bypass=bypass,
                challenge_survived=survived,
                priority_status=priority_status,
                retention=r,
                information=i,
                diversity=v,
                goals=g,
                rank_key=rank_key,
            )
        )

    return traces


def select_next(traces: list[CandidateTrace]) -> CandidateTrace | None:
    """Highest rank_key among traces with priority_status REACHED - higher
    tier always wins regardless of R/I/V/G (§7.1); within a tier, higher
    R/I/V/G wins (§7.2/§22's lexicographic form)."""
    reached = [t for t in traces if t.priority_status is StageStatus.REACHED]
    if not reached:
        return None
    return max(reached, key=lambda t: t.rank_key)
