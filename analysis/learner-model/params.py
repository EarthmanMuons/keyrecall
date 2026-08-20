"""Versioned heuristic parameter registry for the learner-model prototype.

Loads params.toml into a typed Params object. Every numeric constant there
is a heuristic V1 choice (docs/learner-model/03-v1-math.md §25), not a
research-established coefficient, and is kept out of the model/state code
so it can be swapped without touching logic.

Requires: Python 3.11+ (tomllib)
"""

from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CompetencyParams:
    prior_mean: float
    prior_variance: float
    min_variance: float
    learning_rate: float
    uncertainty_diffusion: float
    evidence_shrinkage: float


@dataclass(frozen=True)
class MaterialMemoryParams:
    initial_current_half_life_days: float
    alpha_current_durability: float
    reversion_lambda_current_durability: float
    min_half_life_days: float
    max_memory_half_life_days: float
    prior_retrievability: float
    prior_uncertainty: float
    consolidation_prior_log_variance: float
    consolidation_min_log_variance: float
    retained_inference_min_interval_days: float
    retained_inference_likelihood_weight: float
    retained_inference_grid_points: int
    min_uncertainty: float
    evidence_shrinkage: float
    alpha_cold_start: float
    reversion_lambda_cold_start: float
    min_cold_start_probability: float
    max_cold_start_probability: float
    supported_activation_restoration_rate: float
    supported_current_durability_rate: float
    success_current_durability_rate: float
    consolidation_growth_rate: float
    consolidation_growth_target_days: float
    supported_practice_factor_concurrent_cues: float
    supported_practice_factor_notes_previewed: float
    supported_practice_factor_unguided: float
    retrieval_success_factor_notes_previewed: float
    retrieval_success_factor_unguided: float


@dataclass(frozen=True)
class MaterialExecutionParams:
    prior_variance: float
    min_variance: float
    learning_rate: float
    mean_reversion_tau_days: float
    uncertainty_diffusion: float
    evidence_shrinkage: float


@dataclass(frozen=True)
class HandTransferParams:
    rho_hand: float
    shrinkage_tau: float


@dataclass(frozen=True)
class DifficultyParams:
    tempo_beta: float
    octave_beta: float
    hand_beta: float
    direction_beta: float
    reference_tempo_bpm: float


@dataclass(frozen=True)
class PlacementParams:
    beginner_mean: float
    some_experience_mean: float
    advanced_mean: float
    prior_variance_broad: float


@dataclass(frozen=True)
class Params:
    model_version: str
    competency: CompetencyParams
    material_memory: MaterialMemoryParams
    material_execution: MaterialExecutionParams
    hand_transfer: HandTransferParams
    difficulty: DifficultyParams
    placement: PlacementParams


DEFAULT_PARAMS_PATH = Path(__file__).with_name("params.toml")


def load_params(path: Path | None = None) -> Params:
    with (path or DEFAULT_PARAMS_PATH).open("rb") as fh:
        data = tomllib.load(fh)
    return Params(
        model_version=data["model_version"],
        competency=CompetencyParams(**data["competency"]),
        material_memory=MaterialMemoryParams(**data["material_memory"]),
        material_execution=MaterialExecutionParams(**data["material_execution"]),
        hand_transfer=HandTransferParams(**data["hand_transfer"]),
        difficulty=DifficultyParams(**data["difficulty"]),
        placement=PlacementParams(**data["placement"]),
    )
