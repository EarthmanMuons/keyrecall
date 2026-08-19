#!/usr/bin/env python3
"""Scripted invariant checks for the learner-model prototype.

Mirrors analysis/scale-motor/analyze.py's plain-assertion, printed
pass/fail style rather than introducing a test framework for one script.

Usage:
    python invariants.py
"""

from __future__ import annotations

import random
import sys
from collections.abc import Callable
from itertools import pairwise

from domain import Exercise, GuidanceContext, TechnicalMaterial
from model import Outcome, evidence_weights, predicted_success, update
from params import load_params
from simulate import fixed_exercise, initial_state, run
from state import LearnerState
from synthetic import PROFILES

C_MAJOR = TechnicalMaterial("C", "MAJOR")
D_HARMONIC_MINOR = TechnicalMaterial("D", "HARMONIC_MINOR")
F_SHARP_HARMONIC_MINOR = TechnicalMaterial("F#", "HARMONIC_MINOR")


class InvariantFailure(Exception):
    pass


def _full_outcome(retrieval_succeeded: bool = True) -> Outcome:
    return Outcome(
        started=True,
        retrieval_succeeded=retrieval_succeeded,
        completed=True,
        material_retrieval=1.0,
        pitch_integrity=1.0,
        continuity=1.0,
        temporal_stability=1.0,
        achieved_tempo_ratio=1.0,
    )


def check_bounds() -> None:
    params = load_params()
    trace, _state, _truth = run("advanced", attempts=150, seed=0, params=params)
    for record in trace:
        p = record["predicted_p"]
        if not (0.0 <= p <= 1.0):
            raise InvariantFailure(f"predicted_p out of bounds: {p}")
        if not (0.0 <= record["outcome"]["material_retrieval"] <= 1.0):
            raise InvariantFailure("material_retrieval out of bounds")

        q = record["Q"]
        if not all(v in (0, 1) for v in q.values()):
            raise InvariantFailure(f"Q not binary: {q}")

        loadings = record["q"]
        total = sum(loadings.values())
        if any(v == 1 for v in q.values()):
            if abs(total - 1.0) > 1e-9:
                raise InvariantFailure(f"q does not sum to 1: {loadings}")
        elif total != 0:
            raise InvariantFailure(f"q nonzero with empty Q: {loadings}")

        for w in record["evidence_weights"]["competencies"].values():
            if not (0.0 <= w <= 1.0):
                raise InvariantFailure(f"competency evidence weight out of bounds: {w}")
        if not (0.0 <= record["evidence_weights"]["material_execution"] <= 1.0):
            raise InvariantFailure("material_execution weight out of bounds")
        if not (0.0 <= record["evidence_weights"]["material_memory"] <= 1.0):
            raise InvariantFailure("material_memory weight out of bounds")

        for layer in ("state_before", "state_after"):
            snap = record[layer]
            for c in snap["competencies"].values():
                if c["variance"] <= 0:
                    raise InvariantFailure(f"non-positive competency variance: {c}")
            for m in snap["material_memory"].values():
                if m["half_life_days"] <= 0:
                    raise InvariantFailure(f"non-positive half-life: {m}")
                if m["uncertainty"] <= 0:
                    raise InvariantFailure(f"non-positive memory uncertainty: {m}")
                if not (0.0 <= m["cold_start_estimate"] <= 1.0):
                    raise InvariantFailure(f"cold_start_estimate out of bounds: {m}")
            for e in snap["material_execution"].values():
                if e["residual_variance"] <= 0:
                    raise InvariantFailure(f"non-positive execution variance: {e}")


def check_determinism() -> None:
    params = load_params()
    trace1, _, _ = run("beginner", attempts=60, seed=7, params=params)
    trace2, _, _ = run("beginner", attempts=60, seed=7, params=params)
    if trace1 != trace2:
        raise InvariantFailure("same profile+seed+script produced different traces")


def check_chunked_run_matches_single_run() -> None:
    """A caller threading one rng across several chunked run() calls (e.g.
    to checkpoint state mid-simulation) should see the same stochastic
    process as one long call, not a replayed one: run() reseeds from `seed`
    only when no rng= is given, so the chunking itself must not perturb
    the sequence."""
    params = load_params()

    def rh_c_major_only(_rng: random.Random, _i: int) -> Exercise:
        return fixed_exercise(C_MAJOR, "RIGHT")

    single_trace, _state, _truth = run(
        "advanced", attempts=40, seed=11, params=params, exercise_fn=rh_c_major_only
    )

    chunk_rng = random.Random(11)
    chunked_trace: list[dict] = []
    state, truth, now = None, None, 0.0
    for _ in range(4):
        trace, state, truth = run(
            "advanced",
            attempts=10,
            seed=11,
            params=params,
            exercise_fn=rh_c_major_only,
            state=state,
            truth=truth,
            start_now=now,
            rng=chunk_rng,
        )
        now = trace[-1]["at_days"]
        chunked_trace.extend(trace)

    if len(single_trace) != len(chunked_trace):
        raise InvariantFailure(
            f"chunked run produced {len(chunked_trace)} attempts, "
            f"single run produced {len(single_trace)}"
        )

    for i, (single, chunked) in enumerate(zip(single_trace, chunked_trace)):
        # attempt_index is local to each run() call, so it legitimately
        # differs between the single call and each 10-attempt chunk.
        single_rest = {k: v for k, v in single.items() if k != "attempt_index"}
        chunked_rest = {k: v for k, v in chunked.items() if k != "attempt_index"}
        if single_rest != chunked_rest:
            raise InvariantFailure(
                f"attempt {i}: chunked run diverged from a single equivalent run"
            )


def check_prediction_does_not_mutate_state() -> None:
    params = load_params()
    state = initial_state(PROFILES["advanced"], params)
    exercise = fixed_exercise(C_MAJOR, "RIGHT")

    before = state.snapshot()
    predicted_success(state, exercise, now=1.0, params=params)
    predicted_success(state, exercise, now=1.0, params=params)
    after = state.snapshot()

    if before != after:
        raise InvariantFailure("predicted_success() changed state without update()")


def _assert_untouched_means_stable(
    untouched: list[str], before: dict, after: dict
) -> None:
    for k in untouched:
        if before[k]["mean"] != after[k]["mean"]:
            raise InvariantFailure(
                f"{k} was never in this exercise's Q but its mean moved: "
                f"{before[k]['mean']} -> {after[k]['mean']}"
            )


def check_unrelated_competencies_do_not_move() -> None:
    params = load_params()

    def rh_c_major_only(_rng: random.Random, _i: int) -> Exercise:
        return fixed_exercise(C_MAJOR, "RIGHT")

    trace, state, _truth = run(
        "advanced", attempts=80, seed=1, params=params, exercise_fn=rh_c_major_only
    )
    q = trace[0]["Q"]
    touched = {k for k, v in q.items() if v}
    untouched = [k for k in state.competencies if k not in touched]
    if not untouched:
        raise InvariantFailure("test setup error: every competency was touched")

    before = trace[0]["state_before"]["competencies"]
    after = trace[-1]["state_after"]["competencies"]
    _assert_untouched_means_stable(untouched, before, after)


def check_meta_sanity_broken_rule_is_caught() -> None:
    """Corrupt a snapshot the way a real bug would and confirm
    _assert_untouched_means_stable() (the helper the real check above uses)
    actually catches it."""
    params = load_params()

    def rh_c_major_only(_rng: random.Random, _i: int) -> Exercise:
        return fixed_exercise(C_MAJOR, "RIGHT")

    trace, _state, _truth = run(
        "advanced", attempts=10, seed=1, params=params, exercise_fn=rh_c_major_only
    )
    q = trace[0]["Q"]
    untouched = [k for k, v in q.items() if not v]

    before = trace[0]["state_before"]["competencies"]
    corrupted_after = {
        k: dict(v) for k, v in trace[-1]["state_after"]["competencies"].items()
    }
    corrupted_after[untouched[0]]["mean"] += 0.5  # simulate a bug

    try:
        _assert_untouched_means_stable(untouched, before, corrupted_after)
    except InvariantFailure:
        return
    raise InvariantFailure(
        "meta-check failed to notice the deliberately corrupted competency mean"
    )


def check_hand_transfer_via_prediction_not_cross_update() -> None:
    params = load_params()
    state = initial_state(PROFILES["advanced"], params)
    now = 0.0

    lh_probe = fixed_exercise(C_MAJOR, "LEFT")
    p_before = predicted_success(state, lh_probe, now, params)
    lh_mean_before = state.competencies["LH_SCALE_EXECUTION"].mean

    def rh_only(_rng: random.Random, _i: int) -> Exercise:
        return fixed_exercise(C_MAJOR, "RIGHT")

    trace, state, truth = run(
        "advanced",
        attempts=60,
        seed=2,
        params=params,
        exercise_fn=rh_only,
        state=state,
        start_now=now,
    )
    now = trace[-1]["at_days"]

    lh_mean_after_rh = state.competencies["LH_SCALE_EXECUTION"].mean
    if lh_mean_after_rh != lh_mean_before:
        raise InvariantFailure(
            "RH-only practice moved the stored LH_SCALE_EXECUTION mean "
            f"({lh_mean_before} -> {lh_mean_after_rh}); transfer must go "
            "through prediction, not direct cross-updating"
        )

    p_after_rh = predicted_success(state, lh_probe, now, params)
    if not (p_after_rh > p_before):
        raise InvariantFailure(
            f"predicted LH success didn't improve from correlated RH "
            f"evidence: {p_before} -> {p_after_rh}"
        )

    variance_after_rh = state.competencies["LH_SCALE_EXECUTION"].variance

    def lh_only(_rng: random.Random, _i: int) -> Exercise:
        return fixed_exercise(C_MAJOR, "LEFT")

    # truth=truth carries the hidden ground truth forward too: without it,
    # run() would deep-copy a fresh "advanced" profile and the synthetic
    # person would forget the RH phase even though the estimator remembers it.
    _trace2, state, _truth2 = run(
        "advanced",
        attempts=60,
        seed=3,
        params=params,
        exercise_fn=lh_only,
        state=state,
        truth=truth,
        start_now=now,
    )

    lh_mean_after_lh = state.competencies["LH_SCALE_EXECUTION"].mean
    variance_after_lh = state.competencies["LH_SCALE_EXECUTION"].variance
    if lh_mean_after_lh == lh_mean_after_rh:
        raise InvariantFailure("direct LH evidence never moved the LH mean")
    if not (variance_after_lh < variance_after_rh):
        raise InvariantFailure(
            "direct LH evidence should shrink LH variance below its "
            f"RH-transfer-only level: {variance_after_rh} -> {variance_after_lh}"
        )


def check_material_specific_residual_does_not_contaminate_competency() -> None:
    """Compares the within-run F#-vs-D residual gap, not F#(treatment) vs.
    F#(control) directly: the estimator/generator are deliberately mismatched
    (see synthetic.py), so even the control's residuals aren't near zero, and
    an absolute threshold on one material alone would be comparing against
    the wrong baseline."""
    params = load_params()

    def alternating_harmonic_minor_rh(rng: random.Random, i: int) -> Exercise:
        material = F_SHARP_HARMONIC_MINOR if i % 2 == 0 else D_HARMONIC_MINOR
        return fixed_exercise(material, "RIGHT")

    _control_trace, control_state, _ = run(
        "advanced",
        attempts=120,
        seed=4,
        params=params,
        exercise_fn=alternating_harmonic_minor_rh,
    )
    _trace, state, _truth = run(
        "material_specific_difficulty",
        attempts=120,
        seed=4,
        params=params,
        exercise_fn=alternating_harmonic_minor_rh,
    )

    f_sharp_key = ("F#_HARMONIC_MINOR", "RIGHT")
    d_key = ("D_HARMONIC_MINOR", "RIGHT")

    def gap(s) -> float:
        return (
            s.material_execution[f_sharp_key].residual_mean
            - s.material_execution[d_key].residual_mean
        )

    control_gap = gap(control_state)
    treatment_gap = gap(state)
    if not (treatment_gap < control_gap - 0.15):
        raise InvariantFailure(
            f"F#-vs-D residual gap not substantially more negative in "
            f"treatment than control: control={control_gap}, treatment={treatment_gap}"
        )

    for competency in ("HARMONIC_MINOR_TOPOLOGY", "RH_SCALE_EXECUTION"):
        control_mean = control_state.competencies[competency].mean
        treatment_mean = state.competencies[competency].mean
        if abs(treatment_mean - control_mean) > 0.5:
            raise InvariantFailure(
                f"{competency} drifted too far from control despite the "
                f"badness being material-specific: control={control_mean}, "
                f"treatment={treatment_mean}"
            )


def check_memory_decays_with_elapsed_time() -> None:
    params = load_params()
    state = LearnerState.new(params)
    memory = state.material_memory_for("C_MAJOR", params)
    memory.last_retrieval_at = 0.0
    memory.half_life_days = 4.0

    values = [memory.retrievability(t) for t in (0.0, 1.0, 5.0, 20.0)]
    if not all(a > b for a, b in pairwise(values)):
        raise InvariantFailure(f"retrievability not monotonically decreasing: {values}")


def check_full_cueing_gives_little_memory_evidence() -> None:
    cued = fixed_exercise(
        C_MAJOR, "RIGHT", guidance=GuidanceContext(concurrent_pitch_cues=True)
    )
    uncued = fixed_exercise(C_MAJOR, "RIGHT", guidance=GuidanceContext())
    outcome = _full_outcome()

    cued_weight = evidence_weights(cued, outcome).material_memory
    uncued_weight = evidence_weights(uncued, outcome).material_memory
    if not (cued_weight < 0.2 * uncued_weight):
        raise InvariantFailure(
            f"fully-cued attempt gave too much memory evidence relative to "
            f"unguided: cued={cued_weight}, uncued={uncued_weight}"
        )


def check_full_cueing_gives_little_topology_evidence() -> None:
    cued = fixed_exercise(
        C_MAJOR, "RIGHT", guidance=GuidanceContext(concurrent_pitch_cues=True)
    )
    uncued = fixed_exercise(C_MAJOR, "RIGHT", guidance=GuidanceContext())
    outcome = _full_outcome()

    cued_topology = evidence_weights(cued, outcome).competencies["MAJOR_SCALE_TOPOLOGY"]
    uncued_topology = evidence_weights(uncued, outcome).competencies[
        "MAJOR_SCALE_TOPOLOGY"
    ]
    cued_motor = evidence_weights(cued, outcome).competencies["RH_SCALE_EXECUTION"]
    if not (cued_topology < 0.2 * uncued_topology):
        raise InvariantFailure(
            f"cued attempt gave too much topology evidence: "
            f"cued={cued_topology}, uncued={uncued_topology}"
        )
    if cued_motor <= 0:
        raise InvariantFailure("cueing incorrectly suppressed motor evidence too")


def check_cued_start_does_not_refresh_retrieval_clock() -> None:
    params = load_params()
    state = LearnerState.new(params)
    memory = state.material_memory_for("C_MAJOR", params)
    memory.last_retrieval_at = 0.0
    anchored_at = memory.last_retrieval_at

    exercise = fixed_exercise(
        C_MAJOR, "RIGHT", guidance=GuidanceContext(concurrent_pitch_cues=True)
    )
    outcome = _full_outcome(retrieval_succeeded=False)
    weights = evidence_weights(exercise, outcome)
    predicted_p = predicted_success(state, exercise, now=10.0, params=params)
    update(state, exercise, outcome, weights, predicted_p, now=10.0, params=params)

    if state.material_memory["C_MAJOR"].last_retrieval_at != anchored_at:
        raise InvariantFailure(
            "a cued start without independent retrieval refreshed the memory clock"
        )


def check_unguided_failure_lowers_cold_start_estimate() -> None:
    params = load_params()
    state = LearnerState.new(params)
    exercise = fixed_exercise(C_MAJOR, "RIGHT")  # unguided

    p_before = predicted_success(state, exercise, now=1.0, params=params)

    outcome = Outcome(
        started=False,
        retrieval_succeeded=False,
        completed=False,
        material_retrieval=0.05,
        pitch_integrity=0.0,
        continuity=0.0,
        temporal_stability=0.0,
        achieved_tempo_ratio=0.0,
    )
    weights = evidence_weights(exercise, outcome)
    update(state, exercise, outcome, weights, p_before, now=1.0, params=params)

    p_after = predicted_success(state, exercise, now=2.0, params=params)
    if not (p_after < p_before):
        raise InvariantFailure(
            f"unguided retrieval failure did not lower the next memory-driven "
            f"prediction: {p_before} -> {p_after}"
        )


def check_long_nonuse_increases_uncertainty_without_erasing_mean() -> None:
    params = load_params()
    state = LearnerState.new(params, competency_prior_mean=0.7)
    c = state.competencies["RH_SCALE_EXECUTION"]
    mean_before, variance_before = c.mean, c.variance

    state.propagate(now=365.0, params=params)

    if c.mean != mean_before:
        raise InvariantFailure(
            f"nonuse changed the competency mean: {mean_before} -> {c.mean}"
        )
    if not (c.variance > variance_before):
        raise InvariantFailure(
            f"nonuse did not increase uncertainty: {variance_before} -> {c.variance}"
        )


def check_returning_reacquisition_differs_from_beginner() -> None:
    gap_retrievability = (
        PROFILES["returning"]
        .true_material_memory["C_MAJOR"]
        .retrievability(now=0.0, prior=PROFILES["returning"].memory_prior)
    )
    if not (gap_retrievability < 0.3):
        raise InvariantFailure(
            f"returning profile does not encode an actual memory gap at t=0: "
            f"retrievability={gap_retrievability}"
        )

    params = load_params()

    def rh_c_major_only(_rng: random.Random, _i: int) -> Exercise:
        return fixed_exercise(C_MAJOR, "RIGHT")

    trace_returning, _, _ = run(
        "returning", attempts=30, seed=5, params=params, exercise_fn=rh_c_major_only
    )
    trace_beginner, _, _ = run(
        "beginner", attempts=30, seed=5, params=params, exercise_fn=rh_c_major_only
    )

    def started_pitch(trace: list[dict]) -> list[float]:
        return [
            r["outcome"]["pitch_integrity"] for r in trace if r["outcome"]["started"]
        ]

    returning_pitch = started_pitch(trace_returning)
    beginner_pitch = started_pitch(trace_beginner)
    if not returning_pitch or not beginner_pitch:
        raise InvariantFailure("test setup error: no started attempts to compare")

    returning_avg = sum(returning_pitch) / len(returning_pitch)
    beginner_avg = sum(beginner_pitch) / len(beginner_pitch)
    if not (returning_avg > beginner_avg + 0.2):
        raise InvariantFailure(
            f"returning learner's outcomes weren't meaningfully better than a "
            f"true beginner's despite retaining true competency: "
            f"returning={returning_avg}, beginner={beginner_avg}"
        )


CHECKS: list[tuple[str, Callable[[], None]]] = [
    ("bounds", check_bounds),
    ("determinism", check_determinism),
    (
        "chunked run with a threaded rng matches an equivalent single run",
        check_chunked_run_matches_single_run,
    ),
    ("prediction does not mutate state", check_prediction_does_not_mutate_state),
    ("unrelated competencies do not move", check_unrelated_competencies_do_not_move),
    (
        "meta: a deliberately broken rule is actually caught",
        check_meta_sanity_broken_rule_is_caught,
    ),
    (
        "RH -> LH transfer via prediction, not cross-update",
        check_hand_transfer_via_prediction_not_cross_update,
    ),
    (
        "material-specific residual does not contaminate competency (vs. control)",
        check_material_specific_residual_does_not_contaminate_competency,
    ),
    ("memory decays with elapsed time", check_memory_decays_with_elapsed_time),
    (
        "full cueing gives little memory evidence",
        check_full_cueing_gives_little_memory_evidence,
    ),
    (
        "full cueing gives little topology evidence",
        check_full_cueing_gives_little_topology_evidence,
    ),
    (
        "cued start does not refresh the retrieval clock",
        check_cued_start_does_not_refresh_retrieval_clock,
    ),
    (
        "unguided failure lowers the cold-start memory estimate",
        check_unguided_failure_lowers_cold_start_estimate,
    ),
    (
        "long nonuse: uncertainty grows, mean untouched",
        check_long_nonuse_increases_uncertainty_without_erasing_mean,
    ),
    (
        "returning learner's reacquisition differs from a true beginner's",
        check_returning_reacquisition_differs_from_beginner,
    ),
]


def main() -> None:
    failures = 0
    for name, check in CHECKS:
        try:
            check()
        except InvariantFailure as exc:
            print(f"FAIL  {name}: {exc}")
            failures += 1
        except Exception as exc:  # noqa: BLE001 - surface any unexpected error as a failure
            print(f"ERROR {name}: {exc!r}")
            failures += 1
        else:
            print(f"PASS  {name}")

    print()
    print(f"{len(CHECKS) - failures}/{len(CHECKS)} invariants passed")
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
