"""Pass 16: probe-failure completion-need characterization.

Use paired Pass 15 control-state rollouts as outcome labels, then describe
stronger-support treatment effects only by state observable before selection.
No classifier or scheduler policy is fitted or changed.

Outputs (in --output-dir):
    probe_completion_need_labeled_events.csv
    probe_completion_need_summary.csv
    probe_completion_need_profile_summary.csv
    probe_completion_need_strata.csv
    probe_completion_need_regions.csv
"""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import itertools
import os
from pathlib import Path
from statistics import mean

import prior_knowledge_placement as pass10
import probe_ranking_tradeoff as pass15

DEFAULT_SEEDS = 30
DEFAULT_WORKERS = min(8, os.cpu_count() or 1)
MIN_REGION_COUNT = 50

PREDICTOR_FIELDS = (
    "profile",
    "seed",
    "trigger_id",
    "attempt_index",
    "at_days",
    "original_material_id",
    "probe_number",
    "consecutive_prior_probe_failures",
    "consecutive_prior_probe_completion_failures",
    "previous_probe_failure_mode",
    "previous_probe_completed",
    "previous_probe_retrieval_succeeded",
    "recent_3_completion_failure_count",
    "recent_5_completion_failure_count",
    "recent_3_factual_failure_count",
    "recent_5_factual_failure_count",
    "control_predicted_retrieval_p",
    "control_predicted_material_available_p",
    "control_predicted_execution_p",
    "control_predicted_topology_p",
    "control_predicted_overall_p",
    "execution_minus_material_available",
    "execution_minus_retrieval",
    "current_half_life_days",
    "consolidated_half_life_days",
    "memory_uncertainty",
    "consolidation_log_variance",
    "competency_variance",
    "execution_residual_variance",
    "days_since_factual_success",
    "days_since_factual_attempt",
    "probe_retention",
    "probe_information",
    "stronger_support_predicted_overall_p",
    "stronger_support_predicted_execution_p",
    "stronger_support_overall_gain",
    "stronger_support_same_realization",
)

EFFECT_FIELDS = (
    "immediate_completed",
    "immediate_retrieval_observed",
    "horizon_retrieval_observation_count",
    "horizon_retrieval_success_count",
    "horizon_completion_count",
    "horizon_memory_uncertainty_reduction",
    "horizon_consolidation_log_variance_reduction",
    "horizon_competency_variance_reduction",
    "horizon_execution_variance_reduction",
    "horizon_recovery_count",
    "horizon_no_admission_count",
    "horizon_material_coverage",
    "horizon_original_material_count",
    "horizon_retrieval_mae",
    "horizon_retrieval_brier",
    "selections_until_original_material_return",
    "days_until_original_material_return",
    "selections_until_factual_return",
    "days_until_factual_return",
)

PRIMARY_STRATA = (
    "control_overall_band",
    "control_execution_band",
    "support_gain_band",
    "recent_completion_failure_band",
)


def probability_band(value):
    value = float(value)
    if value < 0.20:
        return "lt_0.20"
    if value < 0.40:
        return "0.20_to_0.40"
    if value < 0.60:
        return "0.40_to_0.60"
    return "ge_0.60"


def gain_band(value):
    value = float(value)
    if value < 0.15:
        return "lt_0.15"
    if value < 0.30:
        return "0.15_to_0.30"
    if value < 0.45:
        return "0.30_to_0.45"
    return "ge_0.45"


def signed_gap_band(value):
    value = float(value)
    if value < -0.20:
        return "lt_-0.20"
    if value < 0.0:
        return "-0.20_to_0"
    if value < 0.20:
        return "0_to_0.20"
    return "ge_0.20"


def count_band(value):
    value = int(value)
    if value <= 1:
        return "0_to_1"
    if value <= 3:
        return "2_to_3"
    return "4_to_5"


def ordinal_band(value):
    value = int(value)
    if value <= 10:
        return "9_to_10"
    if value <= 14:
        return "11_to_14"
    return "15_plus"


def uncertainty_band(value):
    value = float(value)
    if value <= 0.25:
        return "low"
    if value <= 0.60:
        return "medium"
    return "high"


def variance_band(value):
    value = float(value)
    if value <= 0.40:
        return "low"
    if value <= 1.0:
        return "medium"
    return "high"


def add_bands(row):
    row.update(
        {
            "control_retrieval_band": probability_band(
                row["control_predicted_retrieval_p"]
            ),
            "control_overall_band": probability_band(
                row["control_predicted_overall_p"]
            ),
            "control_execution_band": probability_band(
                row["control_predicted_execution_p"]
            ),
            "support_gain_band": gain_band(row["stronger_support_overall_gain"]),
            "execution_minus_memory_band": signed_gap_band(
                row["execution_minus_material_available"]
            ),
            "recent_completion_failure_band": count_band(
                row["recent_5_completion_failure_count"]
            ),
            "recent_factual_failure_band": count_band(
                row["recent_5_factual_failure_count"]
            ),
            "probe_ordinal_band": ordinal_band(row["probe_number"]),
            "memory_uncertainty_band": uncertainty_band(row["memory_uncertainty"]),
            "consolidation_variance_band": variance_band(
                row["consolidation_log_variance"]
            ),
            "execution_variance_band": variance_band(
                row["execution_residual_variance"]
            ),
        }
    )
    return row


def paired_effect(event, control, support):
    row = {field: event[field] for field in PREDICTOR_FIELDS}
    for field in EFFECT_FIELDS:
        if control.get(field, "") == "" or support.get(field, "") == "":
            row[f"control_{field}"] = control.get(field, "")
            row[f"support_{field}"] = support.get(field, "")
            row[f"delta_{field}"] = ""
            continue
        control_value = float(control[field])
        support_value = float(support[field])
        row[f"control_{field}"] = control_value
        row[f"support_{field}"] = support_value
        row[f"delta_{field}"] = support_value - control_value
    row["completion_recovery_benefit"] = (
        row["delta_immediate_completed"] > 0 and row["delta_horizon_recovery_count"] < 0
    )
    row["strict_oracle_benefit"] = (
        row["completion_recovery_benefit"]
        and row["delta_days_until_factual_return"] != ""
        and row["delta_horizon_retrieval_mae"] != ""
        and row["delta_horizon_retrieval_brier"] != ""
        and row["delta_days_until_factual_return"] <= 0
        and row["delta_horizon_retrieval_mae"] <= 0
        and row["delta_horizon_retrieval_brier"] <= 0
    )
    return add_bands(row)


def run_case(fixture, seed):
    _rows, events, paired_rows, _memory, _consolidation = pass15.run_case(
        "control", fixture, seed
    )
    event_by_id = {event["trigger_id"]: event for event in events}
    paired_by_key = {(row["trigger_id"], row["action"]): row for row in paired_rows}
    labeled = []
    for trigger_id, event in event_by_id.items():
        control = paired_by_key[(trigger_id, "retention_first_probe")]
        support = paired_by_key.get((trigger_id, "stronger_support_after_2_failures"))
        if support is None:
            continue
        labeled.append(paired_effect(event, control, support))
    return labeled


def optional_mean(rows, field):
    values = [float(row[field]) for row in rows if row.get(field, "") != ""]
    return mean(values) if values else None


SUMMARY_EFFECTS = (
    "delta_immediate_completed",
    "delta_immediate_retrieval_observed",
    "delta_horizon_retrieval_observation_count",
    "delta_horizon_retrieval_success_count",
    "delta_horizon_memory_uncertainty_reduction",
    "delta_horizon_consolidation_log_variance_reduction",
    "delta_horizon_competency_variance_reduction",
    "delta_horizon_execution_variance_reduction",
    "delta_horizon_recovery_count",
    "delta_horizon_no_admission_count",
    "delta_horizon_material_coverage",
    "delta_horizon_retrieval_mae",
    "delta_horizon_retrieval_brier",
    "delta_selections_until_original_material_return",
    "delta_days_until_factual_return",
)


def summarize_group(rows, keys):
    return {
        **keys,
        "event_count": len(rows),
        "completion_recovery_benefit_fraction": mean(
            row["completion_recovery_benefit"] for row in rows
        ),
        "strict_oracle_benefit_fraction": mean(
            row["strict_oracle_benefit"] for row in rows
        ),
        **{field: optional_mean(rows, field) for field in SUMMARY_EFFECTS},
    }


def profile_summaries(rows):
    return [
        summarize_group(
            [row for row in rows if row["profile"] == fixture.label],
            {"profile": fixture.label},
        )
        for fixture in pass10.FIXTURES
        if any(row["profile"] == fixture.label for row in rows)
    ]


STRATIFIERS = (
    "control_retrieval_band",
    "control_overall_band",
    "control_execution_band",
    "support_gain_band",
    "execution_minus_memory_band",
    "recent_completion_failure_band",
    "recent_factual_failure_band",
    "previous_probe_failure_mode",
    "probe_ordinal_band",
    "memory_uncertainty_band",
    "consolidation_variance_band",
    "execution_variance_band",
)


def strata_summaries(rows):
    result = []
    for field in STRATIFIERS:
        for value in dict.fromkeys(row[field] for row in rows):
            group = [row for row in rows if row[field] == value]
            result.append(
                summarize_group(
                    group,
                    {"stratifier": field, "stratum": value},
                )
            )
    return result


def qualifies_region(summary):
    return (
        summary["event_count"] >= MIN_REGION_COUNT
        and summary["delta_immediate_completed"] >= 0.25
        and summary["delta_horizon_recovery_count"] <= -0.10
        and summary["delta_days_until_factual_return"] <= 0.0
        and summary["delta_horizon_retrieval_mae"] <= 0.0
        and summary["delta_horizon_retrieval_brier"] <= 0.0
    )


def region_summaries(rows):
    result = []
    for left, right in itertools.combinations(PRIMARY_STRATA, 2):
        values = dict.fromkeys((row[left], row[right]) for row in rows)
        for left_value, right_value in values:
            group = [
                row
                for row in rows
                if row[left] == left_value and row[right] == right_value
            ]
            summary = summarize_group(
                group,
                {
                    "left_predictor": left,
                    "left_value": left_value,
                    "right_predictor": right,
                    "right_value": right_value,
                },
            )
            summary["meets_stopping_rule"] = qualifies_region(summary)
            result.append(summary)
    return result


def write_csv(path, rows):
    with path.open("w", newline="", encoding="utf-8") as handle:
        fieldnames = list(dict.fromkeys(key for row in rows for key in row))
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir", type=Path, default=Path(__file__).with_name("generated")
    )
    parser.add_argument("--seeds", type=int, default=DEFAULT_SEEDS)
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    return parser.parse_args()


def run_case_star(args):
    return run_case(*args)


def main():
    args = parse_args()
    jobs = [
        (fixture, seed) for fixture in pass10.FIXTURES for seed in range(args.seeds)
    ]
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        chunks = list(pool.map(run_case_star, jobs))
    rows = [row for chunk in chunks for row in chunk]
    summary = [summarize_group(rows, {"scope": "all"})]
    profiles = profile_summaries(rows)
    strata = strata_summaries(rows)
    regions = region_summaries(rows)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    artifacts = {
        "probe_completion_need_labeled_events.csv": rows,
        "probe_completion_need_summary.csv": summary,
        "probe_completion_need_profile_summary.csv": profiles,
        "probe_completion_need_strata.csv": strata,
        "probe_completion_need_regions.csv": regions,
    }
    for name, artifact_rows in artifacts.items():
        write_csv(args.output_dir / name, artifact_rows)
    print("Completion-need treatment effect:")
    print(summary[0])
    qualifying = [row for row in regions if row["meets_stopping_rule"]]
    print(f"Qualifying descriptive regions: {len(qualifying)}")
    for row in qualifying:
        print(row)


if __name__ == "__main__":
    main()
