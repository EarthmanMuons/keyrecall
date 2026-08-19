"""Hidden ground-truth learner profiles and synthetic outcome sampling.

Uses a different functional form and fixed coefficients from model.py's
estimator on purpose: if generator and estimator shared one equation, the
invariants would mostly confirm the model can invert its own equation.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass, field

from domain import TOPOLOGY_COMPETENCIES, Exercise, structural_q
from model import Outcome
from state import COMPETENCIES

TRUE_DIFFICULTY = {
    "tempo_beta": 0.5,
    "octave_beta": 0.25,
    "hand_beta": 0.3,
    "direction_beta": 0.1,
    "reference_tempo_bpm": 80.0,
}
TRUE_NOISE_SCALE = 0.12


@dataclass
class TrueMaterialMemory:
    """Ground-truth retrievability, decaying independently of the model's
    MaterialMemoryState estimate."""

    half_life_days: float
    last_retrieval_at: float | None = None

    def retrievability(self, now: float, prior: float) -> float:
        if self.last_retrieval_at is None:
            return prior
        delta = now - self.last_retrieval_at
        return 2.0 ** (-delta / self.half_life_days)


@dataclass
class TrueLearnerProfile:
    name: str
    self_report_tier: str  # beginner | some_experience | advanced
    true_competencies: dict[str, float]
    true_material_execution: dict[tuple[str, str], float] = field(default_factory=dict)
    true_material_memory: dict[str, TrueMaterialMemory] = field(default_factory=dict)
    memory_prior: float = 0.4
    default_half_life_days: float = 4.0


def _flat(value: float) -> dict[str, float]:
    return dict.fromkeys(COMPETENCIES, value)


def _build_profiles() -> dict[str, TrueLearnerProfile]:
    beginner = _flat(-1.5)
    advanced = _flat(1.5)

    rh_strong_lh_weak = dict(advanced)
    rh_strong_lh_weak["LH_SCALE_EXECUTION"] = -1.0

    memory_strong_technique_weak = _flat(0.0)
    for k in (
        "RH_SCALE_EXECUTION",
        "LH_SCALE_EXECUTION",
        "SCALAR_CROSSING",
        "MULTI_OCTAVE_CONTINUATION",
        "DIRECTION_REVERSAL",
        "HANDS_TOGETHER_COORDINATION",
    ):
        memory_strong_technique_weak[k] = -1.2

    return {
        "beginner": TrueLearnerProfile(
            name="beginner",
            self_report_tier="beginner",
            true_competencies=beginner,
        ),
        "advanced": TrueLearnerProfile(
            name="advanced",
            self_report_tier="advanced",
            true_competencies=advanced,
        ),
        "rh_strong_lh_weak": TrueLearnerProfile(
            name="rh_strong_lh_weak",
            self_report_tier="some_experience",
            true_competencies=rh_strong_lh_weak,
        ),
        "technique_strong_memory_weak": TrueLearnerProfile(
            name="technique_strong_memory_weak",
            self_report_tier="advanced",
            true_competencies=dict(advanced),
            memory_prior=0.15,
            default_half_life_days=0.5,
        ),
        "memory_strong_technique_weak": TrueLearnerProfile(
            name="memory_strong_technique_weak",
            self_report_tier="some_experience",
            true_competencies=memory_strong_technique_weak,
            memory_prior=0.85,
            default_half_life_days=20.0,
        ),
        "returning": TrueLearnerProfile(
            name="returning",
            self_report_tier="advanced",
            true_competencies=dict(advanced),
            default_half_life_days=6.0,
            # Actual gap, not just a self-report label (§29.8). 14 days
            # against a 6-day half-life gives ~20% per-attempt retrieval
            # odds: low enough to be a real gap, high enough not to make
            # the test flaky over a bounded number of attempts.
            true_material_memory={
                "C_MAJOR": TrueMaterialMemory(
                    half_life_days=6.0, last_retrieval_at=-14.0
                )
            },
        ),
        "material_specific_difficulty": TrueLearnerProfile(
            name="material_specific_difficulty",
            self_report_tier="advanced",
            true_competencies=dict(advanced),
            true_material_execution={("F#_HARMONIC_MINOR", "RIGHT"): -1.8},
        ),
    }


PROFILES: dict[str, TrueLearnerProfile] = _build_profiles()


def _true_memory_for(
    profile: TrueLearnerProfile, material_id: str
) -> TrueMaterialMemory:
    if material_id not in profile.true_material_memory:
        profile.true_material_memory[material_id] = TrueMaterialMemory(
            half_life_days=profile.default_half_life_days
        )
    return profile.true_material_memory[material_id]


def _true_difficulty(exercise: Exercise) -> float:
    d = TRUE_DIFFICULTY
    tempo_term = d["tempo_beta"] * math.log(
        exercise.tempo_bpm / d["reference_tempo_bpm"]
    )
    octave_term = d["octave_beta"] * max(0, exercise.octaves - 1)
    hand_term = d["hand_beta"] * (1.0 if exercise.hands == "TOGETHER" else 0.0)
    direction_term = d["direction_beta"] * (
        1.0 if exercise.direction == "UP_DOWN" else 0.0
    )
    return tempo_term + octave_term + hand_term + direction_term


def sample_outcome(
    profile: TrueLearnerProfile, exercise: Exercise, now: float, rng: random.Random
) -> Outcome:
    material_id = exercise.material.material_id
    true_memory = _true_memory_for(profile, material_id)
    true_retrievability = true_memory.retrievability(now, profile.memory_prior)
    retrieval_demand = exercise.guidance.retrieval_demand()

    # Independent retrieval: never attenuated by cueing, since it's asking
    # whether the material would be retrievable without support. This is
    # tracked regardless of guidance - the learner's true internal state
    # doesn't depend on what the interface reveals - but whether it's
    # observable to the estimator does; see observed_retrieval_succeeded.
    retrieval_succeeded = rng.random() < true_retrievability
    if retrieval_succeeded:
        true_memory.last_retrieval_at = now

    # Continuous cueing supplies the material outright, so this attempt
    # never actually tests independent retrieval: report no observation at
    # all rather than a low-confidence one, so it can't be repeated into
    # accumulated evidence about a retrieval that was never demonstrated.
    observed_retrieval_succeeded = (
        retrieval_succeeded if exercise.guidance.retrieval_observed() else None
    )

    # Starting is broader: cueing can supply enough support to begin even
    # when independent retrieval would have failed. retrieval_demand=0
    # (full cueing) guarantees a start; retrieval_demand=1 (unguided)
    # reduces to started == retrieval_succeeded.
    started = retrieval_succeeded or (rng.random() < 1.0 - retrieval_demand)

    effective_retrievability = 1.0 - retrieval_demand * (1.0 - true_retrievability)
    material_retrieval = min(
        1.0, max(0.0, rng.gauss(effective_retrievability, TRUE_NOISE_SCALE))
    )

    # Motor quality and topology quality are separate pathways from
    # retrieval and from each other, so a profile can be strong in one and
    # weak in the other (TECHNIQUE_STRONG_MEMORY_WEAK, MEMORY_STRONG_
    # TECHNIQUE_WEAK, and now poor-topology/good-fingers or vice versa).
    q = structural_q(exercise)
    relevant = [k for k, v in q.items() if v]
    motor_relevant = [k for k in relevant if k not in TOPOLOGY_COMPETENCIES]
    topology_relevant = [k for k in relevant if k in TOPOLOGY_COMPETENCIES]

    motor_ability = sum(profile.true_competencies[k] for k in motor_relevant) / max(
        1, len(motor_relevant)
    )
    motor_ability += profile.true_material_execution.get(
        (material_id, exercise.hands), 0.0
    )
    motor_logit = (
        motor_ability - _true_difficulty(exercise) + rng.gauss(0.0, TRUE_NOISE_SCALE)
    )
    motor_quality = 1.0 / (1.0 + math.exp(-motor_logit))

    topology_ability = sum(
        profile.true_competencies[k] for k in topology_relevant
    ) / max(1, len(topology_relevant))
    topology_logit = topology_ability + rng.gauss(0.0, TRUE_NOISE_SCALE)
    topology_quality = 1.0 / (1.0 + math.exp(-topology_logit))

    if not started:
        return Outcome(
            started=False,
            retrieval_succeeded=observed_retrieval_succeeded,
            completed=False,
            material_retrieval=material_retrieval,
            pitch_integrity=0.0,
            continuity=0.0,
            temporal_stability=0.0,
            achieved_tempo_ratio=0.0,
            topology_accuracy=0.0,
        )

    def noisy(center: float) -> float:
        return min(1.0, max(0.0, rng.gauss(center, TRUE_NOISE_SCALE)))

    pitch_integrity = noisy(0.6 * material_retrieval + 0.4 * motor_quality)
    continuity = noisy(motor_quality)
    temporal_stability = noisy(motor_quality)
    completed = motor_quality > 0.3 and rng.random() < motor_quality + 0.2

    return Outcome(
        started=True,
        retrieval_succeeded=observed_retrieval_succeeded,
        completed=completed,
        material_retrieval=material_retrieval,
        pitch_integrity=pitch_integrity,
        continuity=continuity,
        temporal_stability=temporal_stability,
        achieved_tempo_ratio=noisy(motor_quality),
        topology_accuracy=noisy(topology_quality),
    )
