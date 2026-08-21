"""Performance model (§10) and evidence/update model (§9.3, §14-§18).

Uses the collision-free descriptive notation summarized in GLOSSARY.md rather
than historical single-letter symbols retained in parts of 03-v1-math.md.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from domain import MOTOR_COMPETENCIES, TOPOLOGY_COMPETENCIES, Exercise, structural_q
from params import Params
from state import COMPETENCIES, LearnerState, MaterialMemoryState, logit

HAND_PAIR = {
    "RH_SCALE_EXECUTION": "LH_SCALE_EXECUTION",
    "LH_SCALE_EXECUTION": "RH_SCALE_EXECUTION",
}


def normalized_loadings(q: dict[str, int]) -> dict[str, float]:
    """q_{e,k}, derived from structural Q (§9.2)."""
    relevant = [k for k, v in q.items() if v]
    if not relevant:
        return dict.fromkeys(q, 0.0)
    weight = 1.0 / len(relevant)
    return {k: (weight if k in relevant else 0.0) for k in q}


def _subset_loadings(q: dict[str, int], subset: frozenset[str]) -> dict[str, float]:
    """q_{e,k} restricted to and renormalized within one competency subset,
    for the retrieval/motor/topology-specific predictions below."""
    relevant = [k for k, v in q.items() if v and k in subset]
    if not relevant:
        return dict.fromkeys(q, 0.0)
    weight = 1.0 / len(relevant)
    return {k: (weight if k in relevant else 0.0) for k in q}


def motor_loadings(q: dict[str, int]) -> dict[str, float]:
    return _subset_loadings(q, MOTOR_COMPETENCIES)


def topology_loadings(q: dict[str, int]) -> dict[str, float]:
    return _subset_loadings(q, TOPOLOGY_COMPETENCIES)


def effective_competency_mean(
    state: LearnerState, competency_id: str, params: Params
) -> float:
    """Stored mean plus a correlated-prior adjustment for prediction only
    (02-v1-design.md §9.1.5). Never writes the paired competency's stored
    state; shrinks toward 0 as the target's own variance shrinks."""
    target = state.competencies[competency_id]
    paired_id = HAND_PAIR.get(competency_id)
    if paired_id is None:
        return target.mean

    paired = state.competencies[paired_id]
    tau = params.hand_transfer.shrinkage_tau
    shrinkage = target.variance / (target.variance + tau)
    return target.mean + params.hand_transfer.rho_hand * shrinkage * (
        paired.mean - target.mean
    )


def task_difficulty_motor(exercise: Exercise, params: Params) -> float:
    """D_motor(e): difficulty of the execution stage only. Positive = harder."""
    d = params.difficulty
    tempo_term = d.tempo_beta * math.log(exercise.tempo_bpm / d.reference_tempo_bpm)
    octave_term = d.octave_beta * max(0, exercise.octaves - 1)
    hand_term = d.hand_beta * (1.0 if exercise.hands == "TOGETHER" else 0.0)
    direction_term = d.direction_beta * (
        1.0 if exercise.direction == "UP_DOWN" else 0.0
    )
    return tempo_term + octave_term + hand_term + direction_term


def predicted_independent_retrieval_p(
    state: LearnerState, exercise: Exercise, now: float, params: Params
) -> float:
    """M(t): probability the material would be retrieved without external
    support."""
    material_id = exercise.material.material_id
    memory_state = state.material_memory.get(material_id)
    if memory_state is not None:
        return memory_state.retrievability_or_prior(now, params)
    return params.material_memory.prior_retrievability


def predicted_material_available_p(
    independent_retrieval_p: float, exercise: Exercise
) -> float:
    """1 - d*(1-M): guidance can supply material the learner wouldn't
    independently retrieve. Mirrors synthetic.py's effective_retrievability
    formula."""
    retrieval_demand = exercise.guidance.retrieval_demand()
    return 1.0 - retrieval_demand * (1.0 - independent_retrieval_p)


def predicted_execution_p(
    state: LearnerState, exercise: Exercise, params: Params
) -> float:
    """P(acceptable motor execution | material available)."""
    q = structural_q(exercise)
    loadings = motor_loadings(q)
    competency_term = sum(
        loadings[k] * effective_competency_mean(state, k, params)
        for k in MOTOR_COMPETENCIES
    )

    material_id = exercise.material.material_id
    execution_state = state.material_execution.get((material_id, exercise.hands))
    residual_term = (
        execution_state.residual_mean if execution_state is not None else 0.0
    )

    eta_exec = competency_term + residual_term - task_difficulty_motor(exercise, params)
    return 1.0 / (1.0 + math.exp(-eta_exec))


def predicted_topology_p(
    state: LearnerState, exercise: Exercise, params: Params
) -> float:
    """P(scale-form/pitch topology correctly known)."""
    q = structural_q(exercise)
    loadings = topology_loadings(q)
    topology_term = sum(
        loadings[k] * effective_competency_mean(state, k, params)
        for k in TOPOLOGY_COMPETENCIES
    )
    return 1.0 / (1.0 + math.exp(-topology_term))


@dataclass(frozen=True)
class Prediction:
    independent_retrieval_p: float
    material_available_p: float
    execution_p: float
    topology_p: float

    @property
    def overall_p(self) -> float:
        return self.material_available_p * self.execution_p


def predicted_success(
    state: LearnerState, exercise: Exercise, now: float, params: Params
) -> Prediction:
    """Two-stage: P(overall) = P(material available) * P(acceptable
    execution | available), §10. Read-only: never inserts state, so a
    snapshot taken before calling this reflects everything it used, and
    predicting is never itself evidence."""
    independent_retrieval_p = predicted_independent_retrieval_p(
        state, exercise, now, params
    )
    return Prediction(
        independent_retrieval_p=independent_retrieval_p,
        material_available_p=predicted_material_available_p(
            independent_retrieval_p, exercise
        ),
        execution_p=predicted_execution_p(state, exercise, params),
        topology_p=predicted_topology_p(state, exercise, params),
    )


@dataclass(frozen=True)
class Outcome:
    started: bool  # did execution begin at all (cueing can make this true)
    # True/False: independent retrieval was tested, NOT attenuated by
    # cueing. None: this attempt wasn't an independent-retrieval
    # observation at all (e.g. concurrent pitch cues), not a tested failure.
    retrieval_succeeded: bool | None
    completed: bool
    material_retrieval: float  # [0,1], continuous, cue-inclusive observation
    pitch_integrity: float
    continuity: float
    temporal_stability: float
    achieved_tempo_ratio: float
    topology_accuracy: float  # pitch/form knowledge, independent of motor quality


@dataclass(frozen=True)
class EvidenceWeights:
    """w[a,k] (§9.3), w_r (§16), w_M (§18): three distinct quantities, not
    one scalar (GLOSSARY.md, “Evidence weight”)."""

    competencies: dict[str, float]
    material_execution: float
    material_memory: float


@dataclass(frozen=True)
class MemoryUpdateDiagnostics:
    """Event-local attribution, not persistent learner state."""

    consolidation_delta_from_retrieval_inference: float = 0.0
    consolidation_delta_from_causal_formation: float = 0.0


def _retained_probability(elapsed_days: float, half_life_days: float) -> float:
    return min(
        1.0 - 1e-12,
        max(1e-12, 2.0 ** (-elapsed_days / half_life_days)),
    )


def update_retained_consolidation_posterior(
    memory_state: MaterialMemoryState,
    retrieval_succeeded: bool,
    elapsed_days: float,
    evidence_weight: float,
    params: Params,
) -> float:
    """Apply factual interval likelihood to retained consolidation.

    The state is a Gaussian posterior approximation in log-half-life space.
    The likelihood is evaluated across the broad memory bounds, then the
    posterior mean is projected onto the current-durability envelope. Returns
    the consolidation change in days.
    """
    mm = params.material_memory
    if (
        evidence_weight <= 0.0
        or mm.retained_inference_likelihood_weight <= 0.0
        or elapsed_days < mm.retained_inference_min_interval_days
    ):
        return 0.0

    grid_points = mm.retained_inference_grid_points
    if grid_points < 3:
        raise ValueError("retained_inference_grid_points must be at least 3")
    lower = math.log(mm.min_half_life_days)
    upper = math.log(mm.max_memory_half_life_days)
    if lower >= upper:
        return 0.0

    prior_mean = memory_state.log_consolidated_half_life
    prior_variance = max(
        mm.consolidation_min_log_variance,
        memory_state.consolidated_log_half_life_variance,
    )
    grid_step = (upper - lower) / (grid_points - 1)
    effective_weight = evidence_weight * mm.retained_inference_likelihood_weight
    grid: list[float] = []
    log_weights: list[float] = []
    for index in range(grid_points):
        log_half_life = lower + index * grid_step
        probability = _retained_probability(elapsed_days, math.exp(log_half_life))
        log_likelihood = (
            math.log(probability) if retrieval_succeeded else math.log1p(-probability)
        )
        log_prior = -0.5 * (log_half_life - prior_mean) ** 2 / prior_variance
        grid.append(log_half_life)
        log_weights.append(log_prior + effective_weight * log_likelihood)

    maximum = max(log_weights)
    weights = [math.exp(value - maximum) for value in log_weights]
    total_weight = sum(weights)
    posterior_mean = (
        sum(value * weight for value, weight in zip(grid, weights, strict=True))
        / total_weight
    )
    posterior_variance = (
        sum(
            weight * (value - posterior_mean) ** 2
            for value, weight in zip(grid, weights, strict=True)
        )
        / total_weight
    )

    consolidation_before = memory_state.consolidated_half_life_days
    projected_mean = max(memory_state.log_current_half_life, posterior_mean)
    projection_error = projected_mean - posterior_mean
    memory_state.log_consolidated_half_life = projected_mean
    memory_state.consolidated_log_half_life_variance = max(
        mm.consolidation_min_log_variance,
        posterior_variance + projection_error * projection_error,
    )
    return memory_state.consolidated_half_life_days - consolidation_before


def evidence_weights(exercise: Exercise, outcome: Outcome) -> EvidenceWeights:
    q = structural_q(exercise)
    relevant = [k for k, v in q.items() if v]

    if not outcome.started:
        # Informative about memory, almost nothing about execution (§20.6) -
        # unless retrieval wasn't even being tested (continuous cueing),
        # in which case this attempt yields no memory evidence either.
        return EvidenceWeights(
            competencies=dict.fromkeys(COMPETENCIES, 0.0),
            material_execution=0.0,
            material_memory=0.0 if outcome.retrieval_succeeded is None else 0.8,
        )

    execution_weight = 1.0 if outcome.completed else 0.4
    retrieval_demand = exercise.guidance.retrieval_demand()

    # Topology is a pitch-knowledge question like memory: a cued attempt is
    # barely informative about it, unlike motor competencies.
    competency_weights = {}
    for k in COMPETENCIES:
        if k not in relevant:
            competency_weights[k] = 0.0
        elif k in TOPOLOGY_COMPETENCIES:
            competency_weights[k] = execution_weight * retrieval_demand
        else:
            competency_weights[k] = execution_weight

    # None: retrieval wasn't observed (continuous cueing), not a tested
    # failure - this attempt gives zero MaterialMemory evidence, however
    # many times it's repeated, rather than accumulating as weak evidence.
    if outcome.retrieval_succeeded is None:
        memory_weight = 0.0
    else:
        memory_weight = retrieval_demand * (1.0 if outcome.completed else 0.6)

    return EvidenceWeights(
        competencies=competency_weights,
        material_execution=execution_weight,
        material_memory=memory_weight,
    )


def update(
    state: LearnerState,
    exercise: Exercise,
    outcome: Outcome,
    weights: EvidenceWeights,
    prediction: Prediction,
    now: float,
    params: Params,
    *,
    apply_retained_durability_inference: bool = True,
) -> MemoryUpdateDiagnostics:
    """Applies §15/§15.1, §16, §18 updates in place; zero-weight layers are
    left untouched.

    Motor competencies and the execution residual update from a motor-only
    delta, prediction.execution_p vs. (continuity + temporal_stability) / 2:
    pitch_integrity is excluded because synthetic.py blends it 60/40 with
    material_retrieval, so it isn't purely motor evidence. Topology
    competencies update from a separate delta, prediction.topology_p vs.
    topology_accuracy, so neither channel can move the other's competencies.

    Returns event-local memory attribution. For anchored factual retrieval,
    retained-consolidation inference runs before current-durability evidence;
    causal formation runs afterward.
    """
    q = structural_q(exercise)
    motor_q_loadings = motor_loadings(q)
    topology_q_loadings = topology_loadings(q)

    y_motor = (outcome.continuity + outcome.temporal_stability) / 2.0
    delta_exec = y_motor - prediction.execution_p
    delta_topology = outcome.topology_accuracy - prediction.topology_p

    for k in COMPETENCIES:
        w = weights.competencies[k]
        if k in TOPOLOGY_COMPETENCIES:
            loading, delta = topology_q_loadings[k], delta_topology
        else:
            loading, delta = motor_q_loadings[k], delta_exec
        if w <= 0.0 or loading <= 0.0:
            continue
        c = state.competencies[k]
        c.mean += params.competency.learning_rate * loading * w * delta
        c.variance = max(
            params.competency.min_variance,
            c.variance * (1 - params.competency.evidence_shrinkage * w),
        )
        c.last_evidence_at = now

    material_id = exercise.material.material_id

    if weights.material_execution > 0.0:
        execution_state = state.material_execution_for(
            material_id, exercise.hands, now, params
        )
        execution_state.residual_mean += (
            params.material_execution.learning_rate
            * weights.material_execution
            * delta_exec
        )
        execution_state.residual_variance = max(
            params.material_execution.min_variance,
            execution_state.residual_variance
            * (
                1
                - params.material_execution.evidence_shrinkage
                * weights.material_execution
            ),
        )
        execution_state.last_evidence_at = now

    memory_state = state.material_memory_for(material_id, params)
    had_memory_anchor = memory_state.memory_anchor_at is not None
    pre_attempt_current_half_life = memory_state.current_half_life_days
    mm = params.material_memory
    inference_delta = 0.0
    causal_formation_delta = 0.0

    # Observation history is factual bookkeeping, not an evidence-weighted
    # estimate. None means retrieval was never tested, so it updates neither
    # factual timestamp.
    if outcome.retrieval_succeeded is not None:
        memory_state.last_retrieval_attempt_at = now

    if (
        apply_retained_durability_inference
        and had_memory_anchor
        and outcome.retrieval_succeeded is not None
    ):
        inference_delta = update_retained_consolidation_posterior(
            memory_state,
            outcome.retrieval_succeeded,
            now - memory_state.memory_anchor_at,
            weights.material_memory,
            params,
        )

    if weights.material_memory > 0.0:
        # Success = independent retrieval (§5.1), not pitch quality and not
        # merely starting: cueing can make outcome.started true without
        # retrieval_succeeded, and that should not count as evidence the
        # material is independently retrievable.
        y_retrieval = 1.0 if outcome.retrieval_succeeded else 0.0

        if had_memory_anchor:
            delta_memory = y_retrieval - prediction.independent_retrieval_p
            log_half_life_prior = math.log(mm.initial_current_half_life_days)
            new_log_half_life = memory_state.log_current_half_life + (
                weights.material_memory
                * (
                    mm.alpha_current_durability * delta_memory
                    - mm.reversion_lambda_current_durability
                    * (memory_state.log_current_half_life - log_half_life_prior)
                )
            )
            memory_state.log_current_half_life = min(
                max(new_log_half_life, math.log(mm.min_half_life_days)),
                memory_state.log_consolidated_half_life,
            )
            memory_state.current_half_life_uncertainty = max(
                mm.min_uncertainty,
                memory_state.current_half_life_uncertainty
                * (1 - mm.evidence_shrinkage * weights.material_memory),
            )
        elif not outcome.retrieval_succeeded:
            # Half-life clock never anchored yet: cold_start_estimate is the
            # operative prediction, not log_half_life, so only it (and its
            # own uncertainty) moves.
            delta_cold_start = y_retrieval - memory_state.cold_start_estimate
            logit_cold_start_prior = logit(mm.prior_retrievability)
            new_logit_cold_start = (
                memory_state.logit_cold_start
                + weights.material_memory
                * (
                    mm.alpha_cold_start * delta_cold_start
                    - mm.reversion_lambda_cold_start
                    * (memory_state.logit_cold_start - logit_cold_start_prior)
                )
            )
            memory_state.logit_cold_start = min(
                max(new_logit_cold_start, logit(mm.min_cold_start_probability)),
                logit(mm.max_cold_start_probability),
            )
            memory_state.cold_start_uncertainty = max(
                mm.min_uncertainty,
                memory_state.cold_start_uncertainty
                * (1 - mm.evidence_shrinkage * weights.material_memory),
            )

    quality = 0.0
    if outcome.started and outcome.completed:
        quality = max(
            0.0,
            min(
                1.0,
                (
                    outcome.continuity
                    + outcome.temporal_stability
                    + outcome.pitch_integrity
                )
                / 3.0,
            ),
        )

    if exercise.guidance.concurrent_pitch_cues:
        guidance_kind = "cued"
    elif exercise.guidance.notes_previewed:
        guidance_kind = "notes"
    else:
        guidance_kind = "unguided"

    if outcome.retrieval_succeeded is True:
        # A first success cannot identify a forgetting rate because no
        # anchored interval preceded it. It can still causally establish
        # stronger post-attempt memory through this transition.
        memory_state.memory_anchor_at = now
        memory_state.factual_last_retrieval_at = now
        success_factor = {
            "notes": mm.retrieval_success_factor_notes_previewed,
            "unguided": mm.retrieval_success_factor_unguided,
        }[guidance_kind]
        consolidation_gap = max(
            0.0,
            mm.consolidation_growth_target_days
            - memory_state.consolidated_half_life_days,
        )
        consolidation_before_formation = memory_state.consolidated_half_life_days
        new_consolidation = consolidation_before_formation + (
            mm.consolidation_growth_rate * success_factor * quality * consolidation_gap
        )
        new_consolidation = min(new_consolidation, mm.max_memory_half_life_days)
        # Evidence correction is allowed to revise current durability down,
        # but successful retrieval has a nonnegative causal learning effect
        # relative to the incoming state. The complete success update therefore
        # cannot finish below its pre-attempt current durability.
        current_base = max(
            pre_attempt_current_half_life, memory_state.current_half_life_days
        )
        new_current = current_base + (
            mm.success_current_durability_rate
            * success_factor
            * quality
            * (new_consolidation - current_base)
        )
        memory_state.log_consolidated_half_life = math.log(new_consolidation)
        memory_state.log_current_half_life = math.log(new_current)
        causal_formation_delta = new_consolidation - consolidation_before_formation
        return MemoryUpdateDiagnostics(inference_delta, causal_formation_delta)

    if quality <= 0.0:
        return MemoryUpdateDiagnostics(inference_delta, causal_formation_delta)

    practice_factor = {
        "cued": mm.supported_practice_factor_concurrent_cues,
        "notes": mm.supported_practice_factor_notes_previewed,
        "unguided": mm.supported_practice_factor_unguided,
    }[guidance_kind]
    if memory_state.memory_anchor_at is not None:
        fraction = mm.supported_activation_restoration_rate * practice_factor * quality
        memory_state.memory_anchor_at += fraction * (
            now - memory_state.memory_anchor_at
        )
    new_current = memory_state.current_half_life_days + (
        mm.supported_current_durability_rate
        * practice_factor
        * quality
        * (
            memory_state.consolidated_half_life_days
            - memory_state.current_half_life_days
        )
    )
    memory_state.log_current_half_life = math.log(new_current)
    return MemoryUpdateDiagnostics(inference_delta, causal_formation_delta)
