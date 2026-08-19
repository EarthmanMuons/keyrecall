"""InstrumentProfile, SessionState, and stage 1 (candidate generation).

Named candidates.py rather than domain.py: see config.py's docstring for
why a scheduler-side file can't share a bare module name with a
learner-model-side file when both directories sit on sys.path at once.

04-v1-scheduler.md §4: candidate generation is pure combinatorics over
domain/instrument validity. It takes no LatentCompetencyState,
MaterialMemoryState, MaterialExecutionState, or SessionState argument at
all - the absence of the parameter is the boundary enforcement.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from itertools import product

from domain import Exercise, GuidanceContext, TechnicalMaterial

HANDS: tuple[str, ...] = ("RIGHT", "LEFT", "TOGETHER")
OCTAVES: tuple[int, ...] = (1, 2)
DIRECTIONS: tuple[str, ...] = ("UP", "UP_DOWN")
TEMPI: tuple[float, ...] = (60, 80, 100, 120)

# 04-v1-scheduler.md §10's guidance-fading scenario needs lower-guidance
# variants of the same material to exist as candidates in the first
# place; generation offers all three so later stages have something to
# admit or reject, rather than baking a guidance choice in here.
GUIDANCE_VARIANTS: tuple[GuidanceContext, ...] = (
    GuidanceContext(),
    GuidanceContext(notes_previewed=True),
    GuidanceContext(concurrent_pitch_cues=True),
)


@dataclass(frozen=True)
class InstrumentProfile:
    """GLOSSARY.md §7. key_count gates max playable octave span; a
    deliberately simple proxy (octaves * 12 <= key_count) stands in for
    real register/capability checking until domain data exists."""

    key_count: int = 88


@dataclass
class SessionState:
    """GLOSSARY.md §4/§8. attempts_this_session and recent_material_ids
    drive SchedulerSafetyPolicy (§5.2) and diversity (§7.2);
    last_failed_exercise drives the "recovery after failure" challenge
    exception (§6) - the exercise itself, not just whether one failed, so
    recovery can target its exact one-step-more-guidance sibling rather
    than any candidate at all."""

    attempts_this_session: int = 0
    recent_material_ids: list[str] = field(default_factory=list)
    last_failed_exercise: Exercise | None = None


def _fits_instrument(octaves: int, instrument: InstrumentProfile) -> bool:
    return octaves * 12 <= instrument.key_count


def _build_opportunities(octaves: int, direction: str) -> frozenset[str]:
    """Simulation fixture, mirroring learner-model/simulate.py's
    build_opportunities - not domain inference."""
    opportunities = {"SCALAR_CROSSING"}
    if octaves >= 2:
        opportunities.add("MULTI_OCTAVE_CONTINUATION")
    if direction == "UP_DOWN":
        opportunities.add("DIRECTION_REVERSAL")
    return frozenset(opportunities)


def generate_candidates(
    instrument: InstrumentProfile,
    materials: list[TechnicalMaterial],
) -> list[Exercise]:
    """Stage 1 (§4). Pure domain/instrument combinatorics: no learner or
    session state parameter exists to read, by construction."""
    candidates: list[Exercise] = []
    for material, hands, octaves, direction, tempo, guidance in product(
        materials, HANDS, OCTAVES, DIRECTIONS, TEMPI, GUIDANCE_VARIANTS
    ):
        if not _fits_instrument(octaves, instrument):
            continue
        candidates.append(
            Exercise(
                material=material,
                hands=hands,
                octaves=octaves,
                direction=direction,
                tempo_bpm=tempo,
                guidance=guidance,
                opportunities=_build_opportunities(octaves, direction),
            )
        )
    return candidates
