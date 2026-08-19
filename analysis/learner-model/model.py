"""Performance model (§10) and evidence/update model (§9.3, §14-§18).

Uses descriptive names rather than 03-v1-math.md's single-letter symbols
(D(e), D_e, G_e, ...): that notation cleanup (GLOSSARY.md §11) is still
pending and code doesn't need to inherit its collisions.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from domain import TOPOLOGY_COMPETENCIES, Exercise, structural_q
from params import Params
from state import COMPETENCIES, LearnerState

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


def task_difficulty(exercise: Exercise, params: Params) -> float:
    """Diff(e), §11. Positive = harder. guidance_beta must be positive:
    it's multiplied by retrieval demand (0=cued, 1=unguided), and less
    support shouldn't make execution easier."""
    d = params.difficulty
    tempo_term = d.tempo_beta * math.log(exercise.tempo_bpm / d.reference_tempo_bpm)
    octave_term = d.octave_beta * max(0, exercise.octaves - 1)
    hand_term = d.hand_beta * (1.0 if exercise.hands == "TOGETHER" else 0.0)
    direction_term = d.direction_beta * (
        1.0 if exercise.direction == "UP_DOWN" else 0.0
    )
    guidance_term = d.guidance_beta * exercise.guidance.retrieval_demand()
    return tempo_term + octave_term + hand_term + direction_term + guidance_term


def memory_transform(retrievability: float) -> float:
    """z(M), §10.1: logit of retrievability, clipped away from 0/1."""
    eps = 1e-4
    m = min(max(retrievability, eps), 1 - eps)
    return math.log(m / (1 - m))


def predicted_success(
    state: LearnerState, exercise: Exercise, now: float, params: Params
) -> float:
    """p_hat, §10. Read-only: never inserts state, so a snapshot taken
    before calling this reflects everything it used, and predicting is
    never itself evidence."""
    q = structural_q(exercise)
    loadings = normalized_loadings(q)
    competency_term = sum(
        loadings[k] * effective_competency_mean(state, k, params) for k in COMPETENCIES
    )

    material_id = exercise.material.material_id
    memory_state = state.material_memory.get(material_id)
    retrievability = (
        memory_state.retrievability_or_prior(now, params)
        if memory_state is not None
        else params.material_memory.prior_retrievability
    )
    memory_term = params.performance.gamma_memory * memory_transform(retrievability)

    execution_state = state.material_execution.get((material_id, exercise.hands))
    residual_term = (
        execution_state.residual_mean if execution_state is not None else 0.0
    )

    eta = (
        competency_term
        + memory_term
        + residual_term
        - task_difficulty(exercise, params)
    )
    return 1.0 / (1.0 + math.exp(-eta))


@dataclass(frozen=True)
class Outcome:
    started: bool  # did execution begin at all (cueing can make this true)
    retrieval_succeeded: bool  # independent retrieval, NOT attenuated by cueing
    completed: bool
    material_retrieval: float  # [0,1], continuous, cue-inclusive observation
    pitch_integrity: float
    continuity: float
    temporal_stability: float
    achieved_tempo_ratio: float


@dataclass(frozen=True)
class EvidenceWeights:
    """w[a,k] (§9.3), w_r (§16), w_M (§18): three distinct quantities, not
    one scalar (GLOSSARY.md §11)."""

    competencies: dict[str, float]
    material_execution: float
    material_memory: float


def evidence_weights(exercise: Exercise, outcome: Outcome) -> EvidenceWeights:
    q = structural_q(exercise)
    relevant = [k for k, v in q.items() if v]

    if not outcome.started:
        # Informative about memory, almost nothing about execution (§20.6).
        return EvidenceWeights(
            competencies=dict.fromkeys(COMPETENCIES, 0.0),
            material_execution=0.0,
            material_memory=0.8,
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
    predicted_p: float,
    now: float,
    params: Params,
) -> None:
    """Applies §15/§15.1, §16, §18 updates in place; zero-weight layers are
    left untouched."""
    q = structural_q(exercise)
    loadings = normalized_loadings(q)

    observed_success = (
        outcome.pitch_integrity + outcome.continuity + outcome.temporal_stability
    ) / 3.0
    prediction_error = observed_success - predicted_p

    for k in COMPETENCIES:
        w = weights.competencies[k]
        if w <= 0.0 or loadings[k] <= 0.0:
            continue
        c = state.competencies[k]
        c.mean += params.competency.learning_rate * loadings[k] * w * prediction_error
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
            * prediction_error
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
    had_ever_retrieved = memory_state.last_retrieval_at is not None
    if weights.material_memory > 0.0:
        # Success = independent retrieval (§5.1), not pitch quality and not
        # merely starting: cueing can make outcome.started true without
        # retrieval_succeeded, and that should not count as evidence the
        # material is independently retrievable.
        factor = (
            params.material_memory.success_growth
            if outcome.retrieval_succeeded
            else params.material_memory.failure_shrink
        )
        memory_state.half_life_days *= factor**weights.material_memory
        memory_state.uncertainty = max(
            params.material_memory.min_uncertainty,
            memory_state.uncertainty
            * (1 - params.material_memory.evidence_shrinkage * weights.material_memory),
        )
        if not had_ever_retrieved and not outcome.retrieval_succeeded:
            # No successful retrieval has ever anchored the half-life clock,
            # so a failure here can only move the cold-start estimate itself.
            memory_state.cold_start_estimate = max(
                0.0,
                memory_state.cold_start_estimate
                * (
                    1
                    - params.material_memory.evidence_shrinkage
                    * weights.material_memory
                ),
            )

    if outcome.retrieval_succeeded:  # clock resets on independent retrieval only
        memory_state.last_retrieval_at = now
