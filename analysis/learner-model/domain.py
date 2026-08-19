"""Synthetic domain: technical material, exercises, and the Q-matrix rule.

No real fingering/scale data or MotorRealization generator exists yet, so
structural_q() (§9.1) reads crossing/continuation/reversal opportunities
from an explicit fixture on the Exercise rather than inferring them.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from state import COMPETENCIES

FORMS = ("MAJOR", "NATURAL_MINOR", "HARMONIC_MINOR", "MELODIC_MINOR")

TOPOLOGY_COMPETENCY = {
    "MAJOR": "MAJOR_SCALE_TOPOLOGY",
    "NATURAL_MINOR": "NATURAL_MINOR_TOPOLOGY",
    "HARMONIC_MINOR": "HARMONIC_MINOR_TOPOLOGY",
    "MELODIC_MINOR": "MELODIC_MINOR_TOPOLOGY",
}

# A pitch-knowledge question like memory: a cued attempt is barely
# informative about these, unlike motor competencies.
TOPOLOGY_COMPETENCIES = frozenset(TOPOLOGY_COMPETENCY.values())

MOTOR_COMPETENCIES = frozenset(COMPETENCIES) - TOPOLOGY_COMPETENCIES

OPPORTUNITY_COMPETENCY = {
    "SCALAR_CROSSING": "SCALAR_CROSSING",
    "MULTI_OCTAVE_CONTINUATION": "MULTI_OCTAVE_CONTINUATION",
    "DIRECTION_REVERSAL": "DIRECTION_REVERSAL",
}


@dataclass(frozen=True)
class TechnicalMaterial:
    tonic: str
    form: str

    @property
    def material_id(self) -> str:
        return f"{self.tonic}_{self.form}"


@dataclass(frozen=True)
class GuidanceContext:
    notes_previewed: bool = False
    concurrent_pitch_cues: bool = False

    def retrieval_demand(self) -> float:
        """d_e in [0,1], §6. Heuristic mapping, not research-established."""
        if self.concurrent_pitch_cues:
            return 0.05
        if self.notes_previewed:
            return 0.6
        return 1.0

    def retrieval_observed(self) -> bool:
        """Whether this attempt can serve as an independent-retrieval
        observation at all. Concurrent pitch cues supply the material
        continuously, so independent retrieval is never actually tested,
        regardless of how low retrieval_demand() says the bar was."""
        return not self.concurrent_pitch_cues


@dataclass(frozen=True)
class Exercise:
    material: TechnicalMaterial
    hands: str  # RIGHT | LEFT | TOGETHER
    octaves: int
    direction: str  # UP | UP_DOWN
    tempo_bpm: float
    guidance: GuidanceContext = field(default_factory=GuidanceContext)
    opportunities: frozenset[str] = frozenset()


def structural_q(exercise: Exercise) -> dict[str, int]:
    """Q_{e,k} in {0,1}, generated from exercise composition (§9.1)."""
    q = dict.fromkeys(COMPETENCIES, 0)
    q[TOPOLOGY_COMPETENCY[exercise.material.form]] = 1
    if exercise.hands in ("RIGHT", "TOGETHER"):
        q["RH_SCALE_EXECUTION"] = 1
    if exercise.hands in ("LEFT", "TOGETHER"):
        q["LH_SCALE_EXECUTION"] = 1
    for opportunity, competency in OPPORTUNITY_COMPETENCY.items():
        if opportunity in exercise.opportunities:
            q[competency] = 1
    if exercise.hands == "TOGETHER":
        q["HANDS_TOGETHER_COORDINATION"] = 1
    return q
