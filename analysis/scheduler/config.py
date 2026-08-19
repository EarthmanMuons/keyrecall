"""Versioned heuristic parameter registry for the scheduler prototype.

Loads config.toml into a typed Params object, matching
../learner-model/params.py's pattern. Named config.py/config.toml rather
than params.py/params.toml: both scheduler and learner-model directories
sit on sys.path at once (pipeline.py needs both), and Python resolves a
bare module name to whichever file it finds first, so two files named
params.py in different directories can't both be imported by that name in
the same process.

Every value here is a deliberately simple Pass-1 placeholder
(docs/learner-model/04-v1-scheduler.md §9), not a tuned policy decision -
see config.toml's header comment.

Requires: Python 3.11+ (tomllib)
"""

from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class EligibilityParams:
    hand_together_competency_threshold: float


@dataclass(frozen=True)
class SafetyParams:
    max_session_attempts: int


@dataclass(frozen=True)
class ChallengeParams:
    p_min: float
    p_max: float


@dataclass(frozen=True)
class DiversityParams:
    recent_window: int


@dataclass(frozen=True)
class Params:
    model_version: str
    eligibility: EligibilityParams
    safety: SafetyParams
    challenge: ChallengeParams
    diversity: DiversityParams


DEFAULT_PARAMS_PATH = Path(__file__).with_name("config.toml")


def load_params(path: Path | None = None) -> Params:
    with (path or DEFAULT_PARAMS_PATH).open("rb") as fh:
        data = tomllib.load(fh)
    return Params(
        model_version=data["model_version"],
        eligibility=EligibilityParams(**data["eligibility"]),
        safety=SafetyParams(**data["safety"]),
        challenge=ChallengeParams(**data["challenge"]),
        diversity=DiversityParams(**data["diversity"]),
    )
