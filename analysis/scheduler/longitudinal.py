"""Adapts the four-stage pipeline into learner-model/simulate.py's
run()'s agent_pick/agent_on_outcome hooks, so run() drives repeated
scheduler -> outcome -> learner-update -> scheduler cycles without a
second update simulator (docs/learner-model/04-v1-scheduler.md §10,
Pass 2). run()'s own predict/sample/weight/update sequence is untouched;
SchedulerAgent only supplies what to present next and reacts to what
happened, exactly the "scheduler becomes the exercise_fn" shape.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from heapq import nlargest

from candidates import InstrumentProfile, SessionState, generate_candidates
from config import Params as SchedulerParams
from domain import Exercise, TechnicalMaterial
from model import Outcome
from params import Params as LearnerParams
from pipeline import (
    CandidateTrace,
    repetition_guard,
    run_pipeline,
    select_scheduler_choice,
)
from state import LearnerState


class NoAdmittedCandidate(Exception):
    """Raised by SchedulerAgent.pick() when no candidate reached
    priority_status REACHED - never silently papered over with
    random_exercise(), which would train the learner model on an
    exercise the scheduler explicitly did not choose. A scenario that
    isn't specifically testing this condition should let it propagate
    (or catch it and fail loudly), not swallow it."""


@dataclass
class AttemptRecord:
    attempt_index: int
    at_days: float
    selected: CandidateTrace | None
    runners_up: list[CandidateTrace] = field(default_factory=list)
    # Set by on_outcome() right after pick() appends this record - run()'s
    # own JSON-lines trace doesn't carry retrieval_succeeded, and scenarios
    # need the real, unserialized Outcome to distinguish tested-and-failed
    # from never-tested (03-v1-math.md §18.2).
    outcome: Outcome | None = None
    # Optional exhaustive witness used by broad stress checks. This keeps
    # the set of admitted materials without retaining every full trace.
    admitted_material_ids: frozenset[str] | None = None


class SchedulerAgent:
    """Owns SessionState across one run() call and a compact per-attempt
    log of what was selected vs. what nearly was - the "winning trace
    plus a compact runner-up set" the user asked for, so a "why X not Y"
    question is answerable without persisting every candidate from every
    attempt (often 1000+, per Pass 1's simulate.py)."""

    def __init__(
        self,
        instrument: InstrumentProfile,
        materials: list[TechnicalMaterial],
        scheduler_params: SchedulerParams,
        learner_params: LearnerParams,
        top_n: int = 5,
        capture_admitted_material_ids: bool = False,
    ) -> None:
        self.instrument = instrument
        self.materials = materials
        self.scheduler_params = scheduler_params
        self.learner_params = learner_params
        self.top_n = top_n
        self.capture_admitted_material_ids = capture_admitted_material_ids
        self.candidates = generate_candidates(instrument, materials)
        self.session = SessionState()
        self.records: list[AttemptRecord] = []

    def new_session(self) -> None:
        """Starts a fresh practice sitting: resets SessionState
        (attempts_this_session, recent_material_ids, last_failed_exercise)
        while LearnerState/TrueLearnerProfile and simulated time carry
        over unbroken via the caller's own state=/truth=/start_now=
        threading (see run_sessions() in scenarios.py). A long
        behavioral horizon is several bounded sessions, not one run past
        SchedulerSafetyPolicy's own attempt cap."""
        self.session = SessionState()

    def pick(
        self, rng: random.Random, index: int, state: LearnerState, now: float
    ) -> Exercise:
        traces = run_pipeline(
            state,
            self.session,
            self.candidates,
            self.scheduler_params,
            self.learner_params,
            now,
        )
        winner = select_scheduler_choice(traces, self.session, self.scheduler_params)
        guarded = repetition_guard(traces, self.session, self.scheduler_params)
        # repetition_guard() falls back to the raw, unfiltered traces list
        # when nothing reached priority ranking at all (its own "never
        # force zero admission" rule has nothing to guard in that case) -
        # those entries carry rank_key=None, unsortable by <. Excluding
        # them here is never a loss: a NOT_REACHED candidate was never a
        # real runner-up, and winner is already None in exactly this case
        # (raised as NoAdmittedCandidate below), so this list should be
        # empty then regardless.
        runners_up = nlargest(
            self.top_n,
            (t for t in guarded if t is not winner and t.rank_key is not None),
            key=lambda t: t.rank_key,
        )
        admitted_material_ids = (
            frozenset(
                t.exercise.material.material_id
                for t in guarded
                if t.rank_key is not None
            )
            if self.capture_admitted_material_ids
            else None
        )
        self.records.append(
            AttemptRecord(
                attempt_index=index,
                at_days=now,
                selected=winner,
                runners_up=runners_up,
                admitted_material_ids=admitted_material_ids,
            )
        )
        self.session.attempts_this_session += 1

        if winner is None:
            raise NoAdmittedCandidate(
                f"no candidate reached priority_status REACHED at attempt {index} "
                f"(now={now}, session.attempts_this_session="
                f"{self.session.attempts_this_session})"
            )
        return winner.exercise

    def on_outcome(self, exercise: Exercise, outcome: Outcome, now: float) -> None:
        del now
        self.records[-1].outcome = outcome
        # is False, not "not True": retrieval_succeeded is None means
        # "not tested" (e.g. continuous cueing), categorically distinct
        # from a genuine failure (03-v1-math.md §18.2) - recovery must
        # not trigger on an attempt that never tested retrieval at all.
        self.session.last_failed_exercise = (
            exercise if outcome.retrieval_succeeded is False else None
        )
        self.session.recent_material_ids.append(exercise.material.material_id)
        window = self.scheduler_params.diversity.recent_window
        if len(self.session.recent_material_ids) > window:
            self.session.recent_material_ids.pop(0)
