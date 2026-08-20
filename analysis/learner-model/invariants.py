#!/usr/bin/env python3
"""Scripted invariant checks for the learner-model prototype.

Mirrors analysis/scale-motor/analyze.py's plain-assertion, printed
pass/fail style rather than introducing a test framework for one script.

Usage:
    python invariants.py
"""

from __future__ import annotations

import math
import random
import sys
from collections.abc import Callable
from itertools import pairwise

from domain import Exercise, GuidanceContext, TechnicalMaterial
from model import Outcome, evidence_weights, predicted_success, update
from params import load_params
from simulate import fixed_exercise, initial_state, run
from state import (
    LearnerState,
    V1MaterialMemoryState,
    upgrade_v1_material_memory,
)
from synthetic import PROFILES, TrueMaterialMemory, apply_true_memory_transition

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
        topology_accuracy=1.0,
    )


def _anchor_memory(
    memory,
    at: float,
    *,
    current_half_life_days: float | None = None,
    consolidated_half_life_days: float | None = None,
) -> None:
    memory.memory_anchor_at = at
    memory.factual_last_retrieval_at = at
    memory.last_retrieval_attempt_at = at
    if current_half_life_days is not None:
        memory.log_current_half_life = math.log(current_half_life_days)
        memory.log_consolidated_half_life = math.log(
            consolidated_half_life_days
            if consolidated_half_life_days is not None
            else current_half_life_days
        )


def check_bounds() -> None:
    params = load_params()
    trace, _state, _truth = run("advanced", attempts=150, seed=0, params=params)
    for record in trace:
        p = record["predicted_p"]
        if not (0.0 <= p <= 1.0):
            raise InvariantFailure(f"predicted_p out of bounds: {p}")
        if not (0.0 <= record["predicted_independent_retrieval_p"] <= 1.0):
            raise InvariantFailure("predicted_independent_retrieval_p out of bounds")
        if not (0.0 <= record["predicted_material_available_p"] <= 1.0):
            raise InvariantFailure("predicted_material_available_p out of bounds")
        if not (0.0 <= record["predicted_execution_p"] <= 1.0):
            raise InvariantFailure("predicted_execution_p out of bounds")
        if not (0.0 <= record["predicted_topology_p"] <= 1.0):
            raise InvariantFailure("predicted_topology_p out of bounds")
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
                if not (
                    0
                    < m["current_half_life_days"]
                    <= m["consolidated_half_life_days"]
                    <= params.material_memory.max_memory_half_life_days
                ):
                    raise InvariantFailure(f"invalid durability envelope: {m}")
                if m["current_half_life_uncertainty"] <= 0:
                    raise InvariantFailure(
                        f"non-positive current-half-life uncertainty: {m}"
                    )
                if m["consolidated_half_life_uncertainty"] <= 0:
                    raise InvariantFailure(
                        f"non-positive consolidation uncertainty: {m}"
                    )
                if m["cold_start_uncertainty"] <= 0:
                    raise InvariantFailure(f"non-positive cold-start uncertainty: {m}")
                if not (0.0 <= m["cold_start_estimate"] <= 1.0):
                    raise InvariantFailure(f"cold_start_estimate out of bounds: {m}")
                anchor = m["memory_anchor_at"]
                factual = m["factual_last_retrieval_at"]
                attempt = m["last_retrieval_attempt_at"]
                for timestamp in (anchor, factual, attempt):
                    if timestamp is not None and (
                        not math.isfinite(timestamp) or timestamp > record["at_days"]
                    ):
                        raise InvariantFailure(f"invalid memory timestamp: {m}")
                if factual is not None and anchor is None:
                    raise InvariantFailure(f"factual retrieval without anchor: {m}")
                if factual is not None and factual > anchor:
                    raise InvariantFailure(f"factual retrieval after anchor: {m}")
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
    # execution_p, not overall_p: transfer acts on the competency mean, which
    # only enters the execution stage now, and overall_p would also move
    # with C_MAJOR's retrievability (shared across hands) as a confound.
    p_before = predicted_success(state, lh_probe, now, params).execution_p
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

    p_after_rh = predicted_success(state, lh_probe, now, params).execution_p
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
        seed=0,
        params=params,
        exercise_fn=alternating_harmonic_minor_rh,
    )
    _trace, state, _truth = run(
        "material_specific_difficulty",
        attempts=120,
        seed=0,
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
    _anchor_memory(memory, 0.0, current_half_life_days=4.0)

    values = [memory.retrievability(t) for t in (0.0, 1.0, 5.0, 20.0)]
    if not all(a > b for a, b in pairwise(values)):
        raise InvariantFailure(f"retrievability not monotonically decreasing: {values}")


def check_v1_memory_upgrade_is_conservative_and_pure() -> None:
    params = load_params()
    old = V1MaterialMemoryState(
        material_id="C_MAJOR",
        log_half_life=math.log(12.0),
        half_life_uncertainty=0.25,
        logit_cold_start=0.1,
        cold_start_uncertainty=0.4,
        last_retrieval_at=-3.0,
        last_retrieval_attempt_at=-1.0,
    )
    upgraded = upgrade_v1_material_memory(old, params)

    if upgraded.current_half_life_days != 12.0:
        raise InvariantFailure("upgrade changed current durability")
    if upgraded.consolidated_half_life_days != 12.0:
        raise InvariantFailure("upgrade manufactured consolidation headroom")
    if upgraded.memory_anchor_at != -3.0:
        raise InvariantFailure("upgrade changed activation history")
    if upgraded.factual_last_retrieval_at != -3.0:
        raise InvariantFailure("upgrade changed factual retrieval history")
    if upgraded.last_retrieval_attempt_at != -1.0:
        raise InvariantFailure("upgrade changed attempt history")
    if upgraded.current_half_life_uncertainty != 0.25:
        raise InvariantFailure("upgrade changed current uncertainty")
    if (
        upgraded.consolidated_half_life_uncertainty
        != params.material_memory.consolidation_prior_uncertainty
    ):
        raise InvariantFailure("upgrade did not use consolidation's own prior")
    if old.log_half_life != math.log(12.0):
        raise InvariantFailure("upgrade mutated its legacy input")


def check_first_success_causes_memory_formation_without_interval_evidence() -> None:
    params = load_params()
    state = LearnerState.new(params)
    exercise = fixed_exercise(C_MAJOR, "RIGHT")
    memory = state.material_memory_for("C_MAJOR", params)
    current_before = memory.current_half_life_days
    consolidation_before = memory.consolidated_half_life_days
    current_uncertainty_before = memory.current_half_life_uncertainty

    outcome = _full_outcome()
    prediction = predicted_success(state, exercise, now=1.0, params=params)
    update(
        state,
        exercise,
        outcome,
        evidence_weights(exercise, outcome),
        prediction,
        now=1.0,
        params=params,
    )

    if memory.memory_anchor_at != 1.0 or memory.factual_last_retrieval_at != 1.0:
        raise InvariantFailure("first success did not establish both timestamps")
    if not (memory.current_half_life_days > current_before):
        raise InvariantFailure("first success did not strengthen current durability")
    if not (memory.consolidated_half_life_days > consolidation_before):
        raise InvariantFailure("first success did not form consolidation")
    if memory.current_half_life_uncertainty != current_uncertainty_before:
        raise InvariantFailure(
            "first success manufactured interval-evidence confidence"
        )


def check_success_creates_mastery_headroom_but_supported_practice_does_not() -> None:
    params = load_params()
    exercise = fixed_exercise(C_MAJOR, "RIGHT")

    success_state = LearnerState.new(params)
    success_memory = success_state.material_memory_for("C_MAJOR", params)
    _anchor_memory(success_memory, 0.0, current_half_life_days=20.0)
    prediction = predicted_success(success_state, exercise, now=1.0, params=params)
    outcome = _full_outcome()
    update(
        success_state,
        exercise,
        outcome,
        evidence_weights(exercise, outcome),
        prediction,
        now=1.0,
        params=params,
    )
    if not (success_memory.consolidated_half_life_days > 20.0):
        raise InvariantFailure("success did not create new consolidation headroom")
    if not (success_memory.current_half_life_days > 20.0):
        raise InvariantFailure("success did not grow mastery beyond its prior envelope")
    if not (
        success_memory.current_half_life_days
        <= success_memory.consolidated_half_life_days
    ):
        raise InvariantFailure("success broke the durability envelope")

    supported_state = LearnerState.new(params)
    supported_memory = supported_state.material_memory_for("C_MAJOR", params)
    _anchor_memory(supported_memory, 0.0, current_half_life_days=20.0)
    cued = fixed_exercise(
        C_MAJOR, "RIGHT", guidance=GuidanceContext(concurrent_pitch_cues=True)
    )
    supported_outcome = _cued_no_retrieval_probe_outcome()
    prediction = predicted_success(supported_state, cued, now=1.0, params=params)
    update(
        supported_state,
        cued,
        supported_outcome,
        evidence_weights(cued, supported_outcome),
        prediction,
        now=1.0,
        params=params,
    )
    if not math.isclose(supported_memory.current_half_life_days, 20.0):
        raise InvariantFailure("zero-headroom supported practice inflated durability")
    if not math.isclose(supported_memory.consolidated_half_life_days, 20.0):
        raise InvariantFailure("supported practice raised consolidation")


def check_success_cannot_end_below_pre_attempt_current_durability() -> None:
    params = load_params()
    state = LearnerState.new(params)
    memory = state.material_memory_for("C_MAJOR", params)
    _anchor_memory(
        memory,
        0.0,
        current_half_life_days=20.0,
        consolidated_half_life_days=30.0,
    )
    exercise = fixed_exercise(C_MAJOR, "RIGHT")
    now = 0.01
    prediction = predicted_success(state, exercise, now=now, params=params)
    outcome = _full_outcome()
    weights = evidence_weights(exercise, outcome)
    pre_attempt_current = memory.current_half_life_days

    mm = params.material_memory
    evidence_corrected_log = memory.log_current_half_life + (
        weights.material_memory
        * (
            mm.alpha_current_durability * (1.0 - prediction.independent_retrieval_p)
            - mm.reversion_lambda_current_durability
            * (
                memory.log_current_half_life
                - math.log(mm.initial_current_half_life_days)
            )
        )
    )
    evidence_corrected = math.exp(
        min(
            max(evidence_corrected_log, math.log(mm.min_half_life_days)),
            memory.log_consolidated_half_life,
        )
    )
    if not (evidence_corrected < pre_attempt_current):
        raise InvariantFailure(
            "test setup did not produce a downward evidence-only correction"
        )

    update(state, exercise, outcome, weights, prediction, now=now, params=params)

    if memory.current_half_life_days < pre_attempt_current:
        raise InvariantFailure(
            "successful retrieval ended below pre-attempt current durability"
        )
    if memory.current_half_life_days > memory.consolidated_half_life_days:
        raise InvariantFailure("successful retrieval broke the durability envelope")


def check_repeated_successes_strengthen_current_and_consolidated_durability() -> None:
    params = load_params()
    state = LearnerState.new(params)
    memory = state.material_memory_for("C_MAJOR", params)
    _anchor_memory(
        memory,
        0.0,
        current_half_life_days=4.0,
        consolidated_half_life_days=20.0,
    )
    exercise = fixed_exercise(C_MAJOR, "RIGHT")
    current_before = memory.current_half_life_days
    consolidation_before = memory.consolidated_half_life_days
    for now in (2.0, 4.0, 8.0):
        outcome = _full_outcome()
        prediction = predicted_success(state, exercise, now=now, params=params)
        update(
            state,
            exercise,
            outcome,
            evidence_weights(exercise, outcome),
            prediction,
            now=now,
            params=params,
        )
    if memory.current_half_life_days <= current_before:
        raise InvariantFailure("repeated successes left current durability frozen")
    if memory.consolidated_half_life_days <= consolidation_before:
        raise InvariantFailure("repeated successes left consolidation frozen")
    if memory.current_half_life_days > memory.consolidated_half_life_days:
        raise InvariantFailure("repeated successes broke the durability envelope")

    truth_memory = TrueMaterialMemory(
        current_half_life_days=4.0,
        consolidated_half_life_days=20.0,
        memory_anchor_at=0.0,
        factual_last_retrieval_at=0.0,
    )
    for now in (2.0, 4.0, 8.0):
        apply_true_memory_transition(truth_memory, exercise, _full_outcome(), now)
    if not (
        truth_memory.current_half_life_days > 4.0
        and truth_memory.consolidated_half_life_days > 20.0
        and truth_memory.current_half_life_days
        <= truth_memory.consolidated_half_life_days
    ):
        raise InvariantFailure("truth and estimator transition semantics diverged")


def _repeated_unguided_failure(
    state: LearnerState, params, attempts: int
) -> list[float]:
    """Anchors C_MAJOR (one prior retrieval, so log_half_life - not
    logit_cold_start - is the operative quantity being predicted from and
    updated) then feeds unguided failures and returns the log_half_life
    trajectory. Failure, not success, is what the old multiplicative rule
    couldn't stabilize."""
    memory = state.material_memory_for("C_MAJOR", params)
    _anchor_memory(memory, 0.0)
    exercise = fixed_exercise(C_MAJOR, "RIGHT")
    now = 0.0
    log_half_lives = []
    for _ in range(attempts):
        now += 0.5
        state.propagate(now, params)
        outcome = Outcome(
            started=False,
            retrieval_succeeded=False,
            completed=False,
            material_retrieval=0.0,
            pitch_integrity=0.0,
            continuity=0.0,
            temporal_stability=0.0,
            achieved_tempo_ratio=0.0,
            topology_accuracy=0.0,
        )
        weights = evidence_weights(exercise, outcome)
        prediction = predicted_success(state, exercise, now, params)
        update(state, exercise, outcome, weights, prediction, now, params)
        log_half_lives.append(state.material_memory["C_MAJOR"].log_current_half_life)
    return log_half_lives


def check_log_half_life_stays_finite_and_bounded() -> None:
    """C1: repeated failure (the old rule's worst case, driving h -> 0) must
    not underflow or overflow log_half_life past the configured guards."""
    params = load_params()
    state = LearnerState.new(params)
    log_half_lives = _repeated_unguided_failure(state, params, attempts=500)

    final = log_half_lives[-1]
    if not math.isfinite(final):
        raise InvariantFailure(f"log_half_life not finite: {final}")
    lo = math.log(params.material_memory.min_half_life_days)
    hi = math.log(params.material_memory.max_memory_half_life_days)
    if not (lo - 1e-9 <= final <= hi + 1e-9):
        raise InvariantFailure(f"log_half_life {final} outside [{lo}, {hi}]")


def check_repeated_expected_failures_reach_equilibrium() -> None:
    """C2's decisive test: the old multiplicative rule collapsed under
    repeated failure regardless of whether those failures were surprising.
    Once predicted retrievability already reflects the (here, zero) true
    rate, further expected failures should settle into a stable interior
    equilibrium, not keep drifting toward the clip bound."""
    params = load_params()
    state = LearnerState.new(params)
    log_half_lives = _repeated_unguided_failure(state, params, attempts=200)

    late_steps = [abs(b - a) for a, b in pairwise(log_half_lives[-20:])]
    if max(late_steps) > 0.05:
        raise InvariantFailure(
            f"log_half_life still moving substantially after 200 consistent "
            f"failures instead of reaching equilibrium: max late step="
            f"{max(late_steps)}"
        )
    min_bound = math.log(params.material_memory.min_half_life_days)
    if log_half_lives[-1] <= min_bound + 1e-6:
        raise InvariantFailure(
            "log_half_life pinned at the min clip bound rather than settling "
            "at an interior equilibrium"
        )


def _repeated_never_anchored_failure(
    state: LearnerState, params, attempts: int
) -> list[float]:
    """Unlike _repeated_unguided_failure, never anchors: retrieval_succeeded
    is always False, so cold_start_estimate - not log_half_life - stays the
    operative quantity throughout, exercising the pre-anchor update path."""
    exercise = fixed_exercise(C_MAJOR, "RIGHT")
    now = 0.0
    cold_start_estimates = []
    for _ in range(attempts):
        now += 0.5
        state.propagate(now, params)
        outcome = Outcome(
            started=False,
            retrieval_succeeded=False,
            completed=False,
            material_retrieval=0.0,
            pitch_integrity=0.0,
            continuity=0.0,
            temporal_stability=0.0,
            achieved_tempo_ratio=0.0,
            topology_accuracy=0.0,
        )
        weights = evidence_weights(exercise, outcome)
        prediction = predicted_success(state, exercise, now, params)
        update(state, exercise, outcome, weights, prediction, now, params)
        cold_start_estimates.append(
            state.material_memory["C_MAJOR"].cold_start_estimate
        )
    return cold_start_estimates


def check_cold_start_estimate_stays_finite_and_bounded() -> None:
    """C1-equivalent for the cold-start belief: repeated failure must not
    underflow or overflow cold_start_estimate past the configured guards."""
    params = load_params()
    state = LearnerState.new(params)
    cold_start_estimates = _repeated_never_anchored_failure(state, params, attempts=500)

    final = cold_start_estimates[-1]
    if not math.isfinite(final):
        raise InvariantFailure(f"cold_start_estimate not finite: {final}")
    lo = params.material_memory.min_cold_start_probability
    hi = params.material_memory.max_cold_start_probability
    if not (lo - 1e-9 <= final <= hi + 1e-9):
        raise InvariantFailure(f"cold_start_estimate {final} outside [{lo}, {hi}]")


def check_repeated_expected_cold_start_failures_reach_equilibrium() -> None:
    """The cold-start analog of check_repeated_expected_failures_reach_
    equilibrium: repeated *expected* pre-anchor failure should settle at a
    stable interior belief, not keep drifting toward the clip bound the way
    the pre-C2 multiplicative shrink rule did."""
    params = load_params()
    state = LearnerState.new(params)
    cold_start_estimates = _repeated_never_anchored_failure(state, params, attempts=200)

    late_steps = [abs(b - a) for a, b in pairwise(cold_start_estimates[-20:])]
    if max(late_steps) > 0.01:
        raise InvariantFailure(
            f"cold_start_estimate still moving substantially after 200 "
            f"consistent failures instead of reaching equilibrium: max late "
            f"step={max(late_steps)}"
        )
    min_bound = params.material_memory.min_cold_start_probability
    if cold_start_estimates[-1] <= min_bound + 1e-6:
        raise InvariantFailure(
            "cold_start_estimate pinned at the min clip bound rather than "
            "settling at an interior equilibrium"
        )


def check_memory_uncertainty_is_phase_separated() -> None:
    """Pre-anchor evidence should inform cold_start_uncertainty, never
    half_life_uncertainty - carrying shrunk uncertainty across into a
    quantity (log_half_life) no observation has actually spoken to yet
    would misrepresent confidence in a heuristic prior as confidence
    earned from evidence."""
    params = load_params()
    state = LearnerState.new(params)
    exercise = fixed_exercise(C_MAJOR, "RIGHT")
    memory = state.material_memory_for("C_MAJOR", params)
    initial_half_life_uncertainty = memory.current_half_life_uncertainty
    initial_cold_start_uncertainty = memory.cold_start_uncertainty

    now = 0.0
    for _ in range(100):
        now += 0.5
        state.propagate(now, params)
        outcome = Outcome(
            started=False,
            retrieval_succeeded=False,
            completed=False,
            material_retrieval=0.0,
            pitch_integrity=0.0,
            continuity=0.0,
            temporal_stability=0.0,
            achieved_tempo_ratio=0.0,
            topology_accuracy=0.0,
        )
        weights = evidence_weights(exercise, outcome)
        prediction = predicted_success(state, exercise, now, params)
        update(state, exercise, outcome, weights, prediction, now, params)

    if not (memory.cold_start_uncertainty < initial_cold_start_uncertainty):
        raise InvariantFailure(
            "100 pre-anchor failures did not reduce cold_start_uncertainty"
        )
    if memory.current_half_life_uncertainty != initial_half_life_uncertainty:
        raise InvariantFailure(
            f"pre-anchor failures moved half_life_uncertainty: "
            f"{initial_half_life_uncertainty} -> "
            f"{memory.current_half_life_uncertainty}"
        )

    # First successful retrieval anchors the clock but is itself no spaced
    # retention-interval evidence about half-life.
    now += 0.5
    state.propagate(now, params)
    outcome = _full_outcome(retrieval_succeeded=True)
    weights = evidence_weights(exercise, outcome)
    prediction = predicted_success(state, exercise, now, params)
    update(state, exercise, outcome, weights, prediction, now, params)

    if memory.current_half_life_uncertainty != initial_half_life_uncertainty:
        raise InvariantFailure(
            f"the first successful retrieval moved half_life_uncertainty: "
            f"{initial_half_life_uncertainty} -> "
            f"{memory.current_half_life_uncertainty}"
        )

    # A genuinely spaced post-anchor observation should now reduce it.
    now += 5.0
    state.propagate(now, params)
    outcome = _full_outcome(retrieval_succeeded=True)
    weights = evidence_weights(exercise, outcome)
    prediction = predicted_success(state, exercise, now, params)
    update(state, exercise, outcome, weights, prediction, now, params)

    if not (memory.current_half_life_uncertainty < initial_half_life_uncertainty):
        raise InvariantFailure(
            "a genuinely spaced post-anchor observation did not reduce "
            "half_life_uncertainty"
        )


def check_surprising_success_increases_retention() -> None:
    params = load_params()
    state = LearnerState.new(params)
    memory = state.material_memory_for("C_MAJOR", params)
    _anchor_memory(memory, 0.0)
    now = 30.0  # long gap: predicted retrievability is low, so a success is surprising
    state.propagate(now, params)

    exercise = fixed_exercise(C_MAJOR, "RIGHT")
    log_half_life_before = memory.log_current_half_life

    prediction = predicted_success(state, exercise, now, params)
    outcome = _full_outcome(retrieval_succeeded=True)
    weights = evidence_weights(exercise, outcome)
    update(state, exercise, outcome, weights, prediction, now, params)

    if not (memory.log_current_half_life > log_half_life_before):
        raise InvariantFailure(
            f"a surprising successful retrieval did not increase log_half_life: "
            f"{log_half_life_before} -> {memory.log_current_half_life}"
        )


def check_surprising_failure_decreases_retention() -> None:
    params = load_params()
    state = LearnerState.new(params)
    memory = state.material_memory_for("C_MAJOR", params)
    _anchor_memory(memory, 0.0)
    now = 0.1  # short gap: predicted retrievability is high, so a failure is surprising
    state.propagate(now, params)

    exercise = fixed_exercise(C_MAJOR, "RIGHT")
    log_half_life_before = memory.log_current_half_life

    prediction = predicted_success(state, exercise, now, params)
    outcome = Outcome(
        started=False,
        retrieval_succeeded=False,
        completed=False,
        material_retrieval=0.0,
        pitch_integrity=0.0,
        continuity=0.0,
        temporal_stability=0.0,
        achieved_tempo_ratio=0.0,
        topology_accuracy=0.0,
    )
    weights = evidence_weights(exercise, outcome)
    update(state, exercise, outcome, weights, prediction, now, params)

    if not (memory.log_current_half_life < log_half_life_before):
        raise InvariantFailure(
            f"a surprising retrieval failure did not decrease log_half_life: "
            f"{log_half_life_before} -> {memory.log_current_half_life}"
        )


def _cued_no_retrieval_probe_outcome() -> Outcome:
    """Continuous cueing: retrieval_succeeded=None because independent
    retrieval was never tested, not because it was tested and failed."""
    return Outcome(
        started=True,
        retrieval_succeeded=None,
        completed=True,
        material_retrieval=1.0,
        pitch_integrity=1.0,
        continuity=1.0,
        temporal_stability=1.0,
        achieved_tempo_ratio=1.0,
        topology_accuracy=1.0,
    )


def check_unobserved_retrieval_never_moves_memory_state() -> None:
    """A fully cued execution with no independent-retrieval probe
    (retrieval_succeeded=None) must produce zero MaterialMemory evidence
    and leave log_half_life exactly unchanged, however many times it's
    repeated. Tests both sides of the prior: an established high half-life
    should stay high and an established low one should stay low, so
    cueing can't silently pull either toward the prior via repetition."""
    params = load_params()
    exercise = fixed_exercise(
        C_MAJOR, "RIGHT", guidance=GuidanceContext(concurrent_pitch_cues=True)
    )
    outcome = _cued_no_retrieval_probe_outcome()

    for initial_half_life_days in (100.0, 0.5):
        state = LearnerState.new(params)
        memory = state.material_memory_for("C_MAJOR", params)
        _anchor_memory(memory, 0.0, current_half_life_days=initial_half_life_days)
        log_half_life_before = memory.log_current_half_life

        now = 0.0
        for _ in range(50):
            now += 0.5
            state.propagate(now, params)
            weights = evidence_weights(exercise, outcome)
            if weights.material_memory != 0.0:
                raise InvariantFailure(
                    f"unobserved retrieval got nonzero material_memory weight: "
                    f"{weights.material_memory}"
                )
            prediction = predicted_success(state, exercise, now, params)
            update(state, exercise, outcome, weights, prediction, now, params)

        if memory.log_current_half_life != log_half_life_before:
            raise InvariantFailure(
                f"50 fully cued attempts with no retrieval probe moved "
                f"log_half_life (initial {initial_half_life_days}d): "
                f"{log_half_life_before} -> {memory.log_current_half_life}"
            )


def check_observed_low_demand_failures_accumulate_evidence() -> None:
    """The companion to check_unobserved_retrieval_never_moves_memory_state:
    when retrieval genuinely is observed (retrieval_succeeded is a real
    bool, e.g. under notes_previewed rather than concurrent cueing), weak
    evidence should still accumulate over repetition rather than being
    suppressed - confirming the fix didn't zero out real evidence along
    with the unobserved case."""
    params = load_params()
    exercise = fixed_exercise(
        C_MAJOR, "RIGHT", guidance=GuidanceContext(notes_previewed=True)
    )
    outcome = Outcome(
        started=True,
        retrieval_succeeded=False,
        completed=True,
        material_retrieval=0.0,
        pitch_integrity=0.0,
        continuity=1.0,
        temporal_stability=1.0,
        achieved_tempo_ratio=1.0,
        topology_accuracy=1.0,
    )

    state = LearnerState.new(params)
    memory = state.material_memory_for("C_MAJOR", params)
    _anchor_memory(memory, 0.0, current_half_life_days=100.0)
    log_half_life_before = memory.log_current_half_life

    now = 0.0
    for _ in range(20):
        now += 0.5
        state.propagate(now, params)
        weights = evidence_weights(exercise, outcome)
        if weights.material_memory <= 0.0:
            raise InvariantFailure(
                f"genuinely observed low-demand failure got zero weight: "
                f"{weights.material_memory}"
            )
        prediction = predicted_success(state, exercise, now, params)
        update(state, exercise, outcome, weights, prediction, now, params)

    if not (memory.log_current_half_life < log_half_life_before):
        raise InvariantFailure(
            f"20 genuinely observed retrieval failures did not lower "
            f"log_current_half_life: {log_half_life_before} -> "
            f"{memory.log_current_half_life}"
        )


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


def check_guidance_affects_availability_not_retrieval_or_execution() -> None:
    """Direct test of the retrieval/execution split itself: guidance should
    move predicted_material_available_p (cueing supplies material) but
    leave predicted_independent_retrieval_p (cueing doesn't make the
    learner remember better) and predicted_execution_p (cueing doesn't
    make fingers move better) exactly alone. A shared logit with a
    guidance term would fail this."""
    params = load_params()
    state = initial_state(PROFILES["advanced"], params)

    cued = fixed_exercise(
        C_MAJOR, "RIGHT", guidance=GuidanceContext(concurrent_pitch_cues=True)
    )
    uncued = fixed_exercise(C_MAJOR, "RIGHT", guidance=GuidanceContext())

    cued_prediction = predicted_success(state, cued, now=1.0, params=params)
    uncued_prediction = predicted_success(state, uncued, now=1.0, params=params)

    if (
        cued_prediction.independent_retrieval_p
        != uncued_prediction.independent_retrieval_p
    ):
        raise InvariantFailure(
            f"guidance changed predicted_independent_retrieval_p: "
            f"cued={cued_prediction.independent_retrieval_p}, "
            f"uncued={uncued_prediction.independent_retrieval_p}"
        )
    if cued_prediction.execution_p != uncued_prediction.execution_p:
        raise InvariantFailure(
            f"guidance changed predicted_execution_p: "
            f"cued={cued_prediction.execution_p}, uncued={uncued_prediction.execution_p}"
        )
    if not (
        cued_prediction.material_available_p > uncued_prediction.material_available_p
    ):
        raise InvariantFailure(
            f"guidance didn't raise predicted_material_available_p: "
            f"cued={cued_prediction.material_available_p}, "
            f"uncued={uncued_prediction.material_available_p}"
        )


def check_motor_and_topology_updates_are_independent() -> None:
    """Motor competencies move only from delta_exec (continuity/
    temporal_stability vs. execution_p); topology competencies move only
    from delta_topology (topology_accuracy vs. topology_p). Varying one
    signal while holding the other fixed must leave the other channel's
    competencies untouched."""
    params = load_params()
    exercise = fixed_exercise(C_MAJOR, "RIGHT")

    def run_once(topology_accuracy: float, continuity: float) -> LearnerState:
        state = LearnerState.new(params)
        outcome = Outcome(
            started=True,
            retrieval_succeeded=True,
            completed=True,
            material_retrieval=1.0,
            pitch_integrity=1.0,
            continuity=continuity,
            temporal_stability=continuity,
            achieved_tempo_ratio=1.0,
            topology_accuracy=topology_accuracy,
        )
        weights = evidence_weights(exercise, outcome)
        prediction = predicted_success(state, exercise, now=1.0, params=params)
        update(state, exercise, outcome, weights, prediction, now=1.0, params=params)
        return state

    low_topology = run_once(topology_accuracy=0.1, continuity=1.0)
    high_topology = run_once(topology_accuracy=0.9, continuity=1.0)
    if (
        low_topology.competencies["RH_SCALE_EXECUTION"].mean
        != high_topology.competencies["RH_SCALE_EXECUTION"].mean
    ):
        raise InvariantFailure("varying topology_accuracy moved a motor competency")

    low_motor = run_once(topology_accuracy=0.5, continuity=0.1)
    high_motor = run_once(topology_accuracy=0.5, continuity=0.9)
    if (
        low_motor.competencies["MAJOR_SCALE_TOPOLOGY"].mean
        != high_motor.competencies["MAJOR_SCALE_TOPOLOGY"].mean
    ):
        raise InvariantFailure(
            "varying motor evidence (continuity/temporal_stability) moved a "
            "topology competency"
        )


def check_cued_practice_does_not_change_factual_retrieval_history() -> None:
    params = load_params()
    state = LearnerState.new(params)
    memory = state.material_memory_for("C_MAJOR", params)
    _anchor_memory(memory, 0.0)
    factual_at = memory.factual_last_retrieval_at

    exercise = fixed_exercise(
        C_MAJOR, "RIGHT", guidance=GuidanceContext(concurrent_pitch_cues=True)
    )
    outcome = _cued_no_retrieval_probe_outcome()
    weights = evidence_weights(exercise, outcome)
    prediction = predicted_success(state, exercise, now=10.0, params=params)
    update(state, exercise, outcome, weights, prediction, now=10.0, params=params)

    if state.material_memory["C_MAJOR"].factual_last_retrieval_at != factual_at:
        raise InvariantFailure(
            "supported practice manufactured a factual successful retrieval"
        )


def check_unguided_failure_lowers_cold_start_estimate() -> None:
    params = load_params()
    state = LearnerState.new(params)
    exercise = fixed_exercise(C_MAJOR, "RIGHT")  # unguided

    prediction_before = predicted_success(state, exercise, now=1.0, params=params)
    p_before = prediction_before.independent_retrieval_p

    outcome = Outcome(
        started=False,
        retrieval_succeeded=False,
        completed=False,
        material_retrieval=0.05,
        pitch_integrity=0.0,
        continuity=0.0,
        temporal_stability=0.0,
        achieved_tempo_ratio=0.0,
        topology_accuracy=0.0,
    )
    weights = evidence_weights(exercise, outcome)
    update(state, exercise, outcome, weights, prediction_before, now=1.0, params=params)

    p_after = predicted_success(
        state, exercise, now=2.0, params=params
    ).independent_retrieval_p
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
        "v1 memory upgrade is conservative, pure, and uses consolidation's prior",
        check_v1_memory_upgrade_is_conservative_and_pure,
    ),
    (
        "first success forms memory without manufacturing interval evidence",
        check_first_success_causes_memory_formation_without_interval_evidence,
    ),
    (
        "success creates mastery headroom; supported practice does not",
        check_success_creates_mastery_headroom_but_supported_practice_does_not,
    ),
    (
        "success cannot end below pre-attempt current durability",
        check_success_cannot_end_below_pre_attempt_current_durability,
    ),
    (
        "repeated successes strengthen current and consolidated durability",
        check_repeated_successes_strengthen_current_and_consolidated_durability,
    ),
    (
        "log_half_life stays finite and bounded under repeated failure",
        check_log_half_life_stays_finite_and_bounded,
    ),
    (
        "repeated expected failures reach a stable equilibrium, not collapse",
        check_repeated_expected_failures_reach_equilibrium,
    ),
    (
        "cold_start_estimate stays finite and bounded under repeated failure",
        check_cold_start_estimate_stays_finite_and_bounded,
    ),
    (
        "repeated expected cold-start failures reach a stable equilibrium",
        check_repeated_expected_cold_start_failures_reach_equilibrium,
    ),
    (
        "memory uncertainty is phase-separated (cold-start vs. half-life)",
        check_memory_uncertainty_is_phase_separated,
    ),
    (
        "a surprising successful retrieval increases retention",
        check_surprising_success_increases_retention,
    ),
    (
        "a surprising retrieval failure decreases retention",
        check_surprising_failure_decreases_retention,
    ),
    (
        "unobserved retrieval never moves evidence or zero-gap durability",
        check_unobserved_retrieval_never_moves_memory_state,
    ),
    (
        "genuinely observed low-demand failures accumulate evidence",
        check_observed_low_demand_failures_accumulate_evidence,
    ),
    (
        "full cueing gives little memory evidence",
        check_full_cueing_gives_little_memory_evidence,
    ),
    (
        "full cueing gives little topology evidence",
        check_full_cueing_gives_little_topology_evidence,
    ),
    (
        "guidance affects material availability, not retrieval or execution",
        check_guidance_affects_availability_not_retrieval_or_execution,
    ),
    (
        "motor and topology competency updates are independent",
        check_motor_and_topology_updates_are_independent,
    ),
    (
        "cued practice does not change factual retrieval history",
        check_cued_practice_does_not_change_factual_retrieval_history,
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
