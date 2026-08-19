#!/usr/bin/env python3
"""Pass 3: parameter robustness/sensitivity sweep
(docs/learner-model/04-v1-scheduler.md §9's still-heuristic constants).

Reuses scenarios.py's 10 Pass-2 behavioral checks as the pass/fail oracle,
rather than a parallel continuous-metric sweep (contrast
../learner-model/analyze.py's 0.5x/1x/2x drift sweep): scheduler params are
mostly probability bounds or small counts, not free-scaling rates, and the
whole point of this pass is that "does Pass 2's already-validated behavior
still hold" is a stronger claim than a fresh, unvalidated metric could make.

Two phases:
    Phase A - sweep one parameter at a time across an absolute-value grid
        (default always included), reporting the SAMPLED passing region
        around today's default - not a located boundary. A 5-point grid can
        only tell you "0.50 passed, 0.40 failed," never that the true
        boundary is exactly 0.476.
    Phase B - sweep 4 hand-picked, architecturally-motivated parameter pairs
        together, looking for brittle interactions: a cell where both
        individual values held in Phase A alone, but the combination fails.
        Some cells deliberately violate a documented relationship between
        the two parameters (e.g. p_introduction_min >= p_min) - those are
        still executed and recorded, but classified out_of_contract, not
        conflated with an ordinary brittle interaction.

`guidance_probe.min_days_since_last_retrieval` also governs
bootstrap_probe's own threshold (pipeline.py's _bootstrap_probe_eligible,
04-v1-scheduler.md §9's already-flagged-open coupling) - referred to below
as the "shared probe interval," not "the guidance-probe interval," since
perturbing it moves both mechanisms at once.

Two of the 10 oracle checks are structurally insensitive to all 6 swept
parameters by construction, not by omission:
    "eligibility progresses as RH/LH competency grows" drives
        simulate.run() directly via exercise_fn, never touching
        SchedulerAgent/run_pipeline() at all.
    "recovery preserves motor challenge" - its single-candidate exclusive-
        recovery setup short-circuits challenge_bypass() before any of the
        6 swept fields are ever read, and its 1-material SessionState can
        never trigger the repetition guard.
A flat 100%-pass row for both, across every cell in both phases, is the
expected result, not a null one.

Does not retune config.toml - characterizes, per this pass's own scope.

Usage:
    python sensitivity.py
    python sensitivity.py --output-dir generated
"""

from __future__ import annotations

import argparse
import csv
import dataclasses
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "learner-model"))

from config import Params as SchedulerParams
from config import load_params as load_scheduler_params
from params import Params as LearnerParams
from params import load_params as load_learner_params
from scenarios import CHECKS, InvariantFailure

PARAMETER_GRID: dict[tuple[str, str], tuple[float, ...]] = {
    ("challenge", "p_min"): (0.40, 0.50, 0.60, 0.70, 0.80),
    ("challenge", "p_max"): (0.75, 0.82, 0.90, 0.95, 0.98),
    ("challenge", "p_introduction_min"): (0.05, 0.10, 0.15, 0.25, 0.65),
    ("guidance_probe", "min_days_since_last_retrieval"): (1.0, 2.5, 5.0, 10.0, 20.0),
    ("diversity", "max_consecutive_material_attempts"): (2, 3, 5, 8, 12),
    ("diversity", "recent_window"): (3, 5, 10, 15, 25),
}
DEFAULT_INDEX = 2
SUB_GRID_INDICES = (0, 2, 4)

# 04-v1-scheduler.md §6.1 documents p_introduction_min as "a separate,
# LOWER threshold than the steady-state band"; config.toml documents the
# repetition cap as intentionally below the diversity window. "valid" gates
# whether a Phase-B cell is even executed (a structurally degenerate
# combination isn't informative); "in_contract" gates only how an executed
# cell is classified.
INTERACTION_PAIRS: list[dict[str, Any]] = [
    {
        "a": ("challenge", "p_min"),
        "b": ("challenge", "p_max"),
        "valid": lambda p_min, p_max: p_min < p_max,
        "skip_reason": "p_min >= p_max (inverted/degenerate band)",
        "in_contract": None,
    },
    {
        "a": ("challenge", "p_introduction_min"),
        "b": ("challenge", "p_min"),
        "valid": None,
        "skip_reason": "",
        "in_contract": lambda p_intro, p_min: p_intro < p_min,
    },
    {
        "a": ("guidance_probe", "min_days_since_last_retrieval"),
        "b": ("diversity", "max_consecutive_material_attempts"),
        "valid": None,
        "skip_reason": "",
        "in_contract": None,
    },
    {
        "a": ("diversity", "max_consecutive_material_attempts"),
        "b": ("diversity", "recent_window"),
        "valid": None,
        "skip_reason": "",
        "in_contract": lambda cap, window: cap < window,
    },
]

CHECK_DEFAULT_SEED: dict[str, int | None] = {
    "guidance fades as memory strengthens": 0,
    "no endless repetition of one material": 1,
    "repetition guard prevents perseveration": None,
    "old material resurfaces after going unpracticed": 2,
    "new-material introduction is learner-sensitive": 0,
    "eligibility progresses as RH/LH competency grows": 5,
    "failure recovery is temporary": 6,
    "guidance probe failure does not cascade to independence": 0,
    "recovery preserves motor challenge": None,
    "never-successful material is not permanently trapped": 2,
}
SEED_OFFSETS_PHASE_A = (0, 10, 20)
SEED_OFFSETS_PHASE_B = (0, 10)

DISPLAY_LABELS: dict[tuple[str, str], str] = {
    ("guidance_probe", "min_days_since_last_retrieval"): (
        "guidance_probe.min_days_since_last_retrieval (shared probe interval "
        "- also governs bootstrap_probe)"
    ),
}


def display_label(section: str, field_name: str) -> str:
    return DISPLAY_LABELS.get((section, field_name), f"{section}.{field_name}")


def seeds_for_check(
    default_seed: int | None, offsets: tuple[int, ...]
) -> tuple[int | None, ...]:
    if default_seed is None:
        return (None,)
    return tuple(default_seed + offset for offset in offsets)


def assert_grid_matches_defaults(params: SchedulerParams) -> None:
    for (section, field_name), grid in PARAMETER_GRID.items():
        live_value = getattr(getattr(params, section), field_name)
        if live_value != grid[DEFAULT_INDEX]:
            raise ValueError(
                f"PARAMETER_GRID[{section}.{field_name}][{DEFAULT_INDEX}] = "
                f"{grid[DEFAULT_INDEX]!r} no longer matches config.toml's live "
                f"value {live_value!r} - update the grid before trusting this sweep"
            )


def scaled_scheduler_params(
    params: SchedulerParams, section: str, field_name: str, value: float
) -> SchedulerParams:
    section_obj = getattr(params, section)
    new_section = dataclasses.replace(section_obj, **{field_name: value})
    return dataclasses.replace(params, **{section: new_section})


def run_check(
    fn: Any,
    scheduler_params: SchedulerParams,
    learner_params: LearnerParams,
    seed: int | None,
) -> tuple[bool | None, bool, str]:
    """Returns (passed, inconclusive, message); passed is None iff
    inconclusive is True. A handful of scenarios.py checks raise
    InvariantFailure with a "test setup error:" prefix when a scripted
    scenario's own precondition wasn't reproduced by this particular seed
    (e.g. no guidance-probe failure occurred in this run at all) - that is
    evidence the seed was unlucky for this check, not evidence about the
    swept parameter, and must not count as a failure of the oracle."""
    try:
        fn(scheduler_params=scheduler_params, learner_params=learner_params, seed=seed)
    except InvariantFailure as exc:
        message = str(exc)
        if message.startswith("test setup error:"):
            return None, True, message
        return False, False, message
    except Exception as exc:  # noqa: BLE001 - a crash is itself a finding
        return False, False, f"CRASH: {exc!r}"
    return True, False, ""


def parameter_sweep_rows(
    base_scheduler_params: SchedulerParams, base_learner_params: LearnerParams
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for (section, field_name), grid in PARAMETER_GRID.items():
        label = f"{section}.{field_name}"
        for value in grid:
            is_default = value == grid[DEFAULT_INDEX]
            swept_params = scaled_scheduler_params(
                base_scheduler_params, section, field_name, value
            )
            for name, fn in CHECKS:
                for seed in seeds_for_check(
                    CHECK_DEFAULT_SEED[name], SEED_OFFSETS_PHASE_A
                ):
                    passed, inconclusive, message = run_check(
                        fn, swept_params, base_learner_params, seed
                    )
                    rows.append(
                        {
                            "parameter": label,
                            "value": value,
                            "is_default": is_default,
                            "check": name,
                            "seed": seed,
                            "passed": passed,
                            "inconclusive": inconclusive,
                            "message": message,
                        }
                    )
    return rows


def classify_check_group(rows: list[dict[str, Any]]) -> str:
    """Aggregates one (parameter value or interaction cell, check)'s seed
    rows into a single verdict. "fails" beats "insufficient" beats "holds"
    in priority: a genuine failure is evidence regardless of how many other
    seeds were inconclusive, but the reverse isn't true - inconclusive rows
    (passed=None, see run_check()) are not neutral padding around a real
    pass, they are an absence of evidence. All seeds missing a check's own
    precondition means this check was never actually evaluated here."""
    if any(r["passed"] is False for r in rows):
        return "fails"
    if any(r["passed"] is True for r in rows):
        return "holds"
    return "insufficient"


def parameter_value_status(value_rows: list[dict[str, Any]]) -> tuple[str, list[str]]:
    """Aggregates one parameter value across every check that ran at it.
    "holds" requires EVERY check to itself have reached "holds" - a check
    with zero conclusive runs at this value cannot vouch for it, so it
    can't count as holding even though nothing failed. Returns
    (status, insufficient_checks)."""
    by_check: dict[str, list[dict[str, Any]]] = {}
    for row in value_rows:
        by_check.setdefault(row["check"], []).append(row)
    insufficient_checks = []
    for check_name, check_rows in by_check.items():
        state = classify_check_group(check_rows)
        if state == "fails":
            return "fails", []
        if state == "insufficient":
            insufficient_checks.append(check_name)
    return ("insufficient" if insufficient_checks else "holds"), insufficient_checks


def classify_parameter_robustness(
    label: str, grid: tuple[float, ...], rows: list[dict[str, Any]]
) -> dict[str, Any]:
    """Reports the widest contiguous sampled-passing run around the
    default, not a located boundary (see module docstring). A value only
    counts toward that run if it genuinely "holds" per
    parameter_value_status() - insufficient coverage is treated the same
    as a failure for boundary-walking purposes, just labeled differently."""
    holds_by_value: dict[float, bool] = {}
    reason_by_value: dict[float, str] = {}
    for value in grid:
        value_rows = [r for r in rows if r["value"] == value]
        status, insufficient_checks = parameter_value_status(value_rows)
        holds_by_value[value] = status == "holds"
        if status == "fails":
            failing = next(r for r in value_rows if r["passed"] is False)
            reason_by_value[value] = (
                f"{failing['check']} (seed={failing['seed']}): {failing['message']}"
            )
        elif status == "insufficient":
            reason_by_value[value] = (
                f"insufficient coverage: {', '.join(insufficient_checks)}"
            )

    default_value = grid[DEFAULT_INDEX]
    if not holds_by_value[default_value]:
        return {
            "parameter": label,
            "classification": "broken_at_default",
            "sampled_passing_low": default_value,
            "sampled_passing_high": default_value,
            "first_failing_below": "",
            "first_failing_above": "",
            "default_failure": reason_by_value[default_value],
        }

    if all(holds_by_value.values()):
        return {
            "parameter": label,
            "classification": "robust",
            "sampled_passing_low": grid[0],
            "sampled_passing_high": grid[-1],
            "first_failing_below": "",
            "first_failing_above": "",
            "default_failure": "",
        }

    low_index = DEFAULT_INDEX
    while low_index > 0 and holds_by_value[grid[low_index - 1]]:
        low_index -= 1
    high_index = DEFAULT_INDEX
    while high_index < len(grid) - 1 and holds_by_value[grid[high_index + 1]]:
        high_index += 1

    first_failing_below = (
        f"{grid[low_index - 1]}: {reason_by_value[grid[low_index - 1]]}"
        if low_index > 0
        else ""
    )
    first_failing_above = (
        f"{grid[high_index + 1]}: {reason_by_value[grid[high_index + 1]]}"
        if high_index < len(grid) - 1
        else ""
    )

    return {
        "parameter": label,
        "classification": "bounded",
        "sampled_passing_low": grid[low_index],
        "sampled_passing_high": grid[high_index],
        "first_failing_below": first_failing_below,
        "first_failing_above": first_failing_above,
        "default_failure": "",
    }


def build_parameter_sensitivity_dataset(
    base_scheduler_params: SchedulerParams, base_learner_params: LearnerParams
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Raw rows, back-filled with each row's parameter-level classification
    fields, plus the per-parameter classification summaries themselves."""
    raw_rows = parameter_sweep_rows(base_scheduler_params, base_learner_params)
    classifications = []
    for (section, field_name), grid in PARAMETER_GRID.items():
        label = f"{section}.{field_name}"
        param_rows = [r for r in raw_rows if r["parameter"] == label]
        summary = classify_parameter_robustness(label, grid, param_rows)
        classifications.append(summary)
        for row in param_rows:
            row["classification"] = summary["classification"]
            row["sampled_passing_low"] = summary["sampled_passing_low"]
            row["sampled_passing_high"] = summary["sampled_passing_high"]
            row["first_failing_below"] = summary["first_failing_below"]
            row["first_failing_above"] = summary["first_failing_above"]
    return raw_rows, classifications


def build_param_holds_lookup(
    parameter_rows: list[dict[str, Any]],
) -> dict[tuple[str, str, float], bool]:
    """Same "holds" definition as classify_parameter_robustness (via the
    shared parameter_value_status()), so a value counted "insufficient"
    there can never be silently treated as safe here."""
    lookup: dict[tuple[str, str, float], bool] = {}
    for (section, field_name), grid in PARAMETER_GRID.items():
        label = f"{section}.{field_name}"
        for value in grid:
            value_rows = [
                r
                for r in parameter_rows
                if r["parameter"] == label and r["value"] == value
            ]
            status, _insufficient_checks = parameter_value_status(value_rows)
            lookup[(section, field_name, value)] = status == "holds"
    return lookup


def pairwise_sweep_rows(
    pair: dict[str, Any],
    base_scheduler_params: SchedulerParams,
    base_learner_params: LearnerParams,
) -> list[dict[str, Any]]:
    (section_a, field_a), (section_b, field_b) = pair["a"], pair["b"]
    label = f"{display_label(section_a, field_a)} x {display_label(section_b, field_b)}"
    grid_a = [PARAMETER_GRID[pair["a"]][i] for i in SUB_GRID_INDICES]
    grid_b = [PARAMETER_GRID[pair["b"]][i] for i in SUB_GRID_INDICES]

    rows: list[dict[str, Any]] = []
    for value_a in grid_a:
        for value_b in grid_b:
            valid = pair["valid"](value_a, value_b) if pair["valid"] else True

            if not valid:
                for name, default_seed in CHECK_DEFAULT_SEED.items():
                    for seed in seeds_for_check(default_seed, SEED_OFFSETS_PHASE_B):
                        rows.append(
                            {
                                "pair": label,
                                "value_a": value_a,
                                "value_b": value_b,
                                "skipped": True,
                                "skip_reason": pair["skip_reason"],
                                "in_contract": None,
                                "check": name,
                                "seed": seed,
                                "passed": None,
                                "inconclusive": False,
                                "message": "",
                            }
                        )
                continue

            in_contract = (
                pair["in_contract"](value_a, value_b) if pair["in_contract"] else True
            )
            swept_params = scaled_scheduler_params(
                base_scheduler_params, section_a, field_a, value_a
            )
            swept_params = scaled_scheduler_params(
                swept_params, section_b, field_b, value_b
            )
            for name, fn in CHECKS:
                for seed in seeds_for_check(
                    CHECK_DEFAULT_SEED[name], SEED_OFFSETS_PHASE_B
                ):
                    passed, inconclusive, message = run_check(
                        fn, swept_params, base_learner_params, seed
                    )
                    rows.append(
                        {
                            "pair": label,
                            "value_a": value_a,
                            "value_b": value_b,
                            "skipped": False,
                            "skip_reason": "",
                            "in_contract": in_contract,
                            "check": name,
                            "seed": seed,
                            "passed": passed,
                            "inconclusive": inconclusive,
                            "message": message,
                        }
                    )
    return rows


def classify_interaction_cell(
    pair: dict[str, Any],
    value_a: float,
    value_b: float,
    in_contract: bool | None,
    cell_rows: list[dict[str, Any]],
    param_holds_lookup: dict[tuple[str, str, float], bool],
) -> str:
    """skipped: never executed (see pairwise_sweep_rows). out_of_contract:
    executed, but deliberately violates a documented parameter relationship
    - recorded, never counted as a brittle-interaction finding. clean:
    in-contract, every check reached "holds" (classify_check_group) - at
    least one conclusive run and no failure. inconclusive: in-contract, no
    check failed, but at least one check never reached a conclusive run at
    this cell - there is no affirmative evidence this cell is safe, so it
    must not be counted as clean. brittle_interaction: in-contract, both
    individual values held in Phase A alone, but the combined cell failed -
    the operational definition of "two individually-safe values combining
    to break something neither breaks alone." expected_failure: in-contract
    but failed, where at least one individual value was ALREADY unsafe in
    Phase A alone - a foreseeable failure, not a surprising interaction."""
    if cell_rows[0]["skipped"]:
        return "skipped"
    if not in_contract:
        return "out_of_contract"

    by_check: dict[str, list[dict[str, Any]]] = {}
    for row in cell_rows:
        by_check.setdefault(row["check"], []).append(row)
    check_states = {name: classify_check_group(rows) for name, rows in by_check.items()}

    if not any(state == "fails" for state in check_states.values()):
        if any(state == "insufficient" for state in check_states.values()):
            return "inconclusive"
        return "clean"

    section_a, field_a = pair["a"]
    section_b, field_b = pair["b"]
    a_held = param_holds_lookup.get((section_a, field_a, value_a), False)
    b_held = param_holds_lookup.get((section_b, field_b, value_b), False)
    return "brittle_interaction" if (a_held and b_held) else "expected_failure"


def build_interaction_dataset(
    base_scheduler_params: SchedulerParams,
    base_learner_params: LearnerParams,
    param_holds_lookup: dict[tuple[str, str, float], bool],
) -> list[dict[str, Any]]:
    """Back-fills each row with its cell's classification. Findings
    (brittle interactions) are read back out of the returned rows by
    report(), not tracked separately, so the CSV and the printed summary
    can never disagree."""
    all_rows: list[dict[str, Any]] = []
    for pair in INTERACTION_PAIRS:
        cell_rows = pairwise_sweep_rows(
            pair, base_scheduler_params, base_learner_params
        )
        seen_cells = {(r["value_a"], r["value_b"]) for r in cell_rows}
        for value_a, value_b in seen_cells:
            this_cell_rows = [
                r
                for r in cell_rows
                if r["value_a"] == value_a and r["value_b"] == value_b
            ]
            in_contract = this_cell_rows[0]["in_contract"]
            classification = classify_interaction_cell(
                pair, value_a, value_b, in_contract, this_cell_rows, param_holds_lookup
            )
            for row in this_cell_rows:
                row["classification"] = classification
        all_rows.extend(cell_rows)
    return all_rows


def count_insufficient_parameter_groups(parameter_rows: list[dict[str, Any]]) -> int:
    """Number of (parameter value, check) groups with zero conclusive runs
    - a coverage gap, not a finding. Independent of
    classify_parameter_robustness's own bookkeeping, so it can serve as a
    cross-check that inconclusive rows didn't quietly erase evidence."""
    groups: dict[tuple[str, float, str], list[dict[str, Any]]] = {}
    for row in parameter_rows:
        groups.setdefault((row["parameter"], row["value"], row["check"]), []).append(
            row
        )
    return sum(
        1 for rows in groups.values() if classify_check_group(rows) == "insufficient"
    )


def count_insufficient_interaction_groups(
    interaction_rows: list[dict[str, Any]],
) -> int:
    """Same coverage check for Phase B, excluding never-executed (skipped)
    cells - those have no conclusive-run expectation to fail."""
    groups: dict[tuple[str, float, float, str], list[dict[str, Any]]] = {}
    for row in interaction_rows:
        if row["skipped"]:
            continue
        groups.setdefault(
            (row["pair"], row["value_a"], row["value_b"], row["check"]), []
        ).append(row)
    return sum(
        1 for rows in groups.values() if classify_check_group(rows) == "insufficient"
    )


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def report(
    parameter_rows: list[dict[str, Any]],
    parameter_classifications: list[dict[str, Any]],
    interaction_rows: list[dict[str, Any]],
) -> None:
    inconclusive_count = sum(1 for r in parameter_rows if r["inconclusive"]) + sum(
        1 for r in interaction_rows if r["inconclusive"]
    )
    insufficient_parameter_groups = count_insufficient_parameter_groups(parameter_rows)
    insufficient_interaction_groups = count_insufficient_interaction_groups(
        interaction_rows
    )
    print(
        f"{inconclusive_count} individual runs inconclusive (a scripted scenario's "
        "own precondition wasn't reproduced by that seed - a 'test setup error:' "
        "from scenarios.py, not a failure of the swept parameter)."
    )
    print(
        f"{insufficient_parameter_groups} parameter-value/check groups lacked a "
        "conclusive run."
    )
    print(
        f"{insufficient_interaction_groups} interaction-cell/check groups lacked a "
        "conclusive run."
    )
    if insufficient_parameter_groups or insufficient_interaction_groups:
        print(
            "Non-zero above: some cells/values below are classified on incomplete "
            "evidence, not because the mechanism was shown safe - see the "
            "'insufficient coverage:' / 'inconclusive' labels in the CSVs."
        )
    print()

    print("Parameter sensitivity (sampled passing region around today's default):")
    for c in parameter_classifications:
        if c["classification"] == "robust":
            print(f"  {c['parameter']:<45} robust across the full sampled grid")
        elif c["classification"] == "broken_at_default":
            print(f"  {c['parameter']:<45} BROKEN AT DEFAULT - {c['default_failure']}")
        else:
            print(
                f"  {c['parameter']:<45} bounded: sampled passing region "
                f"[{c['sampled_passing_low']}, {c['sampled_passing_high']}]"
            )
            if c["first_failing_below"]:
                print(f"      first failure below: {c['first_failing_below']}")
            if c["first_failing_above"]:
                print(f"      first failure above: {c['first_failing_above']}")
    print()

    print("Parameter interactions (4 hand-picked pairs):")
    pair_labels = list(dict.fromkeys(r["pair"] for r in interaction_rows))
    brittle_findings = []
    for pair_label in pair_labels:
        pair_rows = [r for r in interaction_rows if r["pair"] == pair_label]
        cells = {(r["value_a"], r["value_b"]) for r in pair_rows}
        counts = dict.fromkeys(
            (
                "skipped",
                "out_of_contract",
                "brittle_interaction",
                "expected_failure",
                "inconclusive",
                "clean",
            ),
            0,
        )
        for value_a, value_b in cells:
            classification = next(
                r["classification"]
                for r in pair_rows
                if r["value_a"] == value_a and r["value_b"] == value_b
            )
            counts[classification] += 1
            if classification == "brittle_interaction":
                example = next(
                    r
                    for r in pair_rows
                    if r["value_a"] == value_a
                    and r["value_b"] == value_b
                    and r["passed"] is False
                )
                brittle_findings.append((pair_label, value_a, value_b, example))
        print(
            f"  {pair_label:<70} {len(cells)} cells: "
            f"clean={counts['clean']} brittle={counts['brittle_interaction']} "
            f"out_of_contract={counts['out_of_contract']} "
            f"expected_failure={counts['expected_failure']} "
            f"inconclusive={counts['inconclusive']} skipped={counts['skipped']}"
        )
    print()

    if not brittle_findings:
        print("No brittle interactions found among in-contract cells.")
    else:
        print("Brittle interactions:")
        for pair_label, value_a, value_b, example in brittle_findings:
            print(
                f"  {pair_label}: value_a={value_a} value_b={value_b} - "
                f"{example['check']} (seed={example['seed']}) failed: "
                f"{example['message']}"
            )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).with_name("generated"),
        help="Directory for generated CSVs (default: ./generated)",
    )
    parser.add_argument(
        "--scheduler-params", type=Path, default=None, help="Explicit config.toml path"
    )
    parser.add_argument(
        "--learner-params", type=Path, default=None, help="Explicit params.toml path"
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    scheduler_params = load_scheduler_params(args.scheduler_params)
    learner_params = load_learner_params(args.learner_params)
    assert_grid_matches_defaults(scheduler_params)

    args.output_dir.mkdir(parents=True, exist_ok=True)

    parameter_rows, parameter_classifications = build_parameter_sensitivity_dataset(
        scheduler_params, learner_params
    )
    param_holds_lookup = build_param_holds_lookup(parameter_rows)
    interaction_rows = build_interaction_dataset(
        scheduler_params, learner_params, param_holds_lookup
    )

    outputs = {
        "parameter_sensitivity.csv": parameter_rows,
        "parameter_interactions.csv": interaction_rows,
    }
    for filename, rows in outputs.items():
        write_csv(args.output_dir / filename, rows)

    report(parameter_rows, parameter_classifications, interaction_rows)

    print()
    for filename in outputs:
        print(f"Wrote {args.output_dir / filename}")


if __name__ == "__main__":
    main()
