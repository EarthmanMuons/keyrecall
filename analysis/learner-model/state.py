"""Estimated learner state: three layers plus deterministic time propagation.

Implements docs/learner-model/03-v1-math.md §4 (competency), §5/§7
(material memory / execution residual), and the time-propagation rules in
§7.1/§8.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from params import Params

COMPETENCIES: tuple[str, ...] = (
    "MAJOR_SCALE_TOPOLOGY",
    "NATURAL_MINOR_TOPOLOGY",
    "HARMONIC_MINOR_TOPOLOGY",
    "MELODIC_MINOR_TOPOLOGY",
    "RH_SCALE_EXECUTION",
    "LH_SCALE_EXECUTION",
    "SCALAR_CROSSING",
    "MULTI_OCTAVE_CONTINUATION",
    "DIRECTION_REVERSAL",
    "HANDS_TOGETHER_COORDINATION",
)


@dataclass
class CompetencyState:
    competency_id: str
    mean: float
    variance: float
    updated_at: float
    last_evidence_at: float | None = None

    def propagate(self, now: float, params: Params) -> None:
        """Time-only update: variance grows, mean is unchanged (§8)."""
        delta = now - self.updated_at
        if delta > 0:
            self.variance += params.competency.uncertainty_diffusion * delta
        self.updated_at = now


@dataclass
class MaterialMemoryState:
    material_id: str
    log_half_life: float
    uncertainty: float
    cold_start_estimate: float
    last_retrieval_at: float | None = None

    @property
    def half_life_days(self) -> float:
        return math.exp(self.log_half_life)

    def retrievability(self, now: float) -> float:
        """M(t), §5. Raises if never retrieved; see retrievability_or_prior()."""
        if self.last_retrieval_at is None:
            raise RuntimeError(
                f"{self.material_id}: no retrieval yet, elapsed time is "
                "undefined; call retrievability_or_prior() instead"
            )
        delta = now - self.last_retrieval_at
        return 2.0 ** (-delta / self.half_life_days)

    def retrievability_or_prior(self, now: float, params: Params) -> float:
        """Before any successful retrieval, uses cold_start_estimate rather
        than a fixed prior, so a failed unguided attempt can still move the
        next prediction even though the half-life clock hasn't started."""
        if self.last_retrieval_at is None:
            return self.cold_start_estimate
        return self.retrievability(now)


@dataclass
class MaterialExecutionState:
    material_id: str
    execution_context: str  # RIGHT | LEFT | TOGETHER
    residual_mean: float
    residual_variance: float
    updated_at: float
    last_evidence_at: float | None = None

    def propagate(self, now: float, params: Params) -> None:
        """Time-only update: residual reverts toward 0, uncertainty grows
        (§7.1). rho(delta) = exp(-delta/tau); f(delta) = delta. Both are
        explicit heuristic choices, not established by current research."""
        delta = now - self.updated_at
        if delta > 0:
            tau = params.material_execution.mean_reversion_tau_days
            self.residual_mean *= math.exp(-delta / tau)
            self.residual_variance += (
                params.material_execution.uncertainty_diffusion * delta
            )
        self.updated_at = now


@dataclass
class LearnerState:
    competencies: dict[str, CompetencyState]
    material_memory: dict[str, MaterialMemoryState] = field(default_factory=dict)
    material_execution: dict[tuple[str, str], MaterialExecutionState] = field(
        default_factory=dict
    )

    @classmethod
    def new(
        cls,
        params: Params,
        now: float = 0.0,
        competency_prior_mean: float | None = None,
    ) -> LearnerState:
        prior_mean = (
            params.competency.prior_mean
            if competency_prior_mean is None
            else competency_prior_mean
        )
        return cls(
            competencies={
                cid: CompetencyState(
                    competency_id=cid,
                    mean=prior_mean,
                    variance=params.competency.prior_variance,
                    updated_at=now,
                )
                for cid in COMPETENCIES
            }
        )

    def material_memory_for(
        self, material_id: str, params: Params
    ) -> MaterialMemoryState:
        if material_id not in self.material_memory:
            self.material_memory[material_id] = MaterialMemoryState(
                material_id=material_id,
                log_half_life=math.log(params.material_memory.initial_half_life_days),
                uncertainty=params.material_memory.prior_uncertainty,
                cold_start_estimate=params.material_memory.prior_retrievability,
            )
        return self.material_memory[material_id]

    def material_execution_for(
        self, material_id: str, execution_context: str, now: float, params: Params
    ) -> MaterialExecutionState:
        key = (material_id, execution_context)
        if key not in self.material_execution:
            self.material_execution[key] = MaterialExecutionState(
                material_id=material_id,
                execution_context=execution_context,
                residual_mean=0.0,
                residual_variance=params.material_execution.prior_variance,
                updated_at=now,
            )
        return self.material_execution[key]

    def propagate(self, now: float, params: Params) -> None:
        for state in self.competencies.values():
            state.propagate(now, params)
        for state in self.material_execution.values():
            state.propagate(now, params)
        # MaterialMemoryState needs no propagate(): retrievability is
        # computed on demand from last_retrieval_at, not stored as a
        # decaying value that would otherwise go stale between calls.

    def snapshot(self) -> dict:
        """JSON-serializable snapshot for trace output."""
        return {
            "competencies": {
                cid: {"mean": c.mean, "variance": c.variance}
                for cid, c in self.competencies.items()
            },
            "material_memory": {
                mid: {
                    "half_life_days": m.half_life_days,
                    "log_half_life": m.log_half_life,
                    "uncertainty": m.uncertainty,
                    "cold_start_estimate": m.cold_start_estimate,
                    "last_retrieval_at": m.last_retrieval_at,
                }
                for mid, m in self.material_memory.items()
            },
            "material_execution": {
                f"{mid}/{ctx}": {
                    "residual_mean": e.residual_mean,
                    "residual_variance": e.residual_variance,
                }
                for (mid, ctx), e in self.material_execution.items()
            },
        }
