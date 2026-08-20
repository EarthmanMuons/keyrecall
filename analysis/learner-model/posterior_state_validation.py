"""Pass 9: retained-consolidation posterior-state validation.

Controlled Bernoulli retrieval intervals test whether the production posterior
mean and log-variance behave coherently across latent half-lives. This isolates
the posterior representation from causal learning and scheduler selection.

Outputs (in --output-dir):
    posterior_validation_trajectories.csv
    posterior_validation_summary.csv
    posterior_validation_variant_summary.csv
"""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import dataclasses
import math
import os
import random
from dataclasses import dataclass
from pathlib import Path
from statistics import mean, median
from typing import Any

from model import update_retained_consolidation_posterior
from params import Params, load_params
from state import LearnerState

LATENT_HALF_LIVES = (1.0, 3.0, 7.0, 14.0, 30.0, 90.0)
BASE_INTERVALS = (0.25, 0.5, 1.0, 3.0, 7.0, 14.0, 30.0, 60.0, 90.0)
INTERVAL_REPETITIONS = 4
CHECKPOINTS = (4, 8, 16, len(BASE_INTERVALS) * INTERVAL_REPETITIONS)
DEFAULT_SEEDS = 100
DEFAULT_WORKERS = min(8, os.cpu_count() or 1)
INITIAL_CURRENT_HALF_LIFE_DAYS = 0.5
INITIAL_CONSOLIDATED_HALF_LIFE_DAYS = 3.0
Z_90 = 1.6448536269514722


@dataclass(frozen=True)
class Variant:
    name: str
    prior_log_variance: float
    min_log_variance: float
    likelihood_weight: float
    grid_points: int


VARIANTS = (
    Variant("production", 2.0, 0.20, 1.0, 301),
    Variant("precalibration", 1.0, 0.05, 1.0, 301),
    Variant("narrow_prior", 1.0, 0.20, 1.0, 301),
    Variant("more_diffuse_prior", 4.0, 0.20, 1.0, 301),
    Variant("variance_floor_0_05", 2.0, 0.05, 1.0, 301),
    Variant("variance_floor_0_10", 2.0, 0.10, 1.0, 301),
    Variant("half_likelihood", 2.0, 0.20, 0.5, 301),
    Variant("double_likelihood", 2.0, 0.20, 2.0, 301),
    Variant("coarse_grid", 2.0, 0.20, 1.0, 101),
    Variant("fine_grid", 2.0, 0.20, 1.0, 1001),
)


def variant_params(base: Params, variant: Variant) -> Params:
    material_memory = dataclasses.replace(
        base.material_memory,
        consolidation_prior_log_variance=variant.prior_log_variance,
        consolidation_min_log_variance=variant.min_log_variance,
        retained_inference_likelihood_weight=variant.likelihood_weight,
        retained_inference_grid_points=variant.grid_points,
    )
    return dataclasses.replace(base, material_memory=material_memory)


def retrieval_probability(elapsed_days: float, half_life_days: float) -> float:
    return 2.0 ** (-elapsed_days / half_life_days)


def observation_sequence(
    latent_half_life: float, seed: int
) -> list[tuple[float, bool]]:
    rng = random.Random(10_000 + seed)
    intervals = list(BASE_INTERVALS) * INTERVAL_REPETITIONS
    rng.shuffle(intervals)
    return [
        (
            interval,
            rng.random() < retrieval_probability(interval, latent_half_life),
        )
        for interval in intervals
    ]


def run_case(
    variant: Variant, latent_half_life: float, seed: int
) -> list[dict[str, Any]]:
    params = variant_params(load_params(), variant)
    memory = LearnerState.new(params).material_memory_for("CONTROLLED", params)
    memory.log_current_half_life = math.log(INITIAL_CURRENT_HALF_LIFE_DAYS)
    memory.log_consolidated_half_life = math.log(INITIAL_CONSOLIDATED_HALF_LIFE_DAYS)
    memory.consolidated_log_half_life_variance = variant.prior_log_variance
    rows = []
    for observation_index, (elapsed_days, succeeded) in enumerate(
        observation_sequence(latent_half_life, seed), start=1
    ):
        delta = update_retained_consolidation_posterior(
            memory,
            succeeded,
            elapsed_days,
            evidence_weight=1.0,
            params=params,
        )
        standard_deviation = math.sqrt(memory.consolidated_log_half_life_variance)
        truth_log = math.log(latent_half_life)
        rows.append(
            {
                "variant": variant.name,
                "latent_half_life_days": latent_half_life,
                "seed": seed,
                "observation_index": observation_index,
                "elapsed_days": elapsed_days,
                "retrieval_succeeded": succeeded,
                "consolidation_delta_from_retrieval_inference": delta,
                "estimated_half_life_days": memory.consolidated_half_life_days,
                "posterior_log_variance": (memory.consolidated_log_half_life_variance),
                "log_error": memory.log_consolidated_half_life - truth_log,
                "truth_in_90_percent_interval": (
                    memory.log_consolidated_half_life - Z_90 * standard_deviation
                    <= truth_log
                    <= memory.log_consolidated_half_life + Z_90 * standard_deviation
                ),
            }
        )
    return rows


def summarize(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, float, int], list[dict[str, Any]]] = {}
    for row in rows:
        if int(row["observation_index"]) not in CHECKPOINTS:
            continue
        key = (
            row["variant"],
            float(row["latent_half_life_days"]),
            int(row["observation_index"]),
        )
        grouped.setdefault(key, []).append(row)

    results = []
    for (variant, latent, checkpoint), group in sorted(grouped.items()):
        results.append(
            {
                "variant": variant,
                "latent_half_life_days": latent,
                "observation_count": checkpoint,
                "mean_estimated_half_life_days": mean(
                    row["estimated_half_life_days"] for row in group
                ),
                "median_estimated_half_life_days": median(
                    row["estimated_half_life_days"] for row in group
                ),
                "mean_log_bias": mean(row["log_error"] for row in group),
                "mean_absolute_log_error": mean(abs(row["log_error"]) for row in group),
                "root_mean_squared_log_error": math.sqrt(
                    mean(row["log_error"] ** 2 for row in group)
                ),
                "coverage_90_percent": mean(
                    float(row["truth_in_90_percent_interval"]) for row in group
                ),
                "mean_posterior_log_variance": mean(
                    row["posterior_log_variance"] for row in group
                ),
            }
        )
    return results


def summarize_variants(summary: list[dict[str, Any]]) -> list[dict[str, Any]]:
    final = [row for row in summary if row["observation_count"] == CHECKPOINTS[-1]]
    results = []
    for variant in VARIANTS:
        group = [row for row in final if row["variant"] == variant.name]
        results.append(
            {
                "variant": variant.name,
                "prior_log_variance": variant.prior_log_variance,
                "min_log_variance": variant.min_log_variance,
                "likelihood_weight": variant.likelihood_weight,
                "grid_points": variant.grid_points,
                "mean_absolute_log_error_across_latent_half_lives": mean(
                    row["mean_absolute_log_error"] for row in group
                ),
                "root_mean_squared_log_error_across_latent_half_lives": math.sqrt(
                    mean(row["root_mean_squared_log_error"] ** 2 for row in group)
                ),
                "mean_90_percent_coverage": mean(
                    row["coverage_90_percent"] for row in group
                ),
                "mean_posterior_log_variance": mean(
                    row["mean_posterior_log_variance"] for row in group
                ),
            }
        )
    return results


def check_calibration_structure(summary: list[dict[str, Any]]) -> None:
    configured = load_params().material_memory
    production_variant = VARIANTS[0]
    if (
        production_variant.prior_log_variance
        != configured.consolidation_prior_log_variance
        or production_variant.min_log_variance
        != configured.consolidation_min_log_variance
        or production_variant.likelihood_weight
        != configured.retained_inference_likelihood_weight
        or production_variant.grid_points != configured.retained_inference_grid_points
    ):
        raise AssertionError("validation production variant drifted from params.toml")
    final = {
        (row["variant"], row["latent_half_life_days"]): row
        for row in summary
        if row["observation_count"] == CHECKPOINTS[-1]
    }
    production_estimates = [
        final[("production", latent)]["median_estimated_half_life_days"]
        for latent in LATENT_HALF_LIVES
    ]
    if production_estimates != sorted(production_estimates):
        raise AssertionError("production posterior is not ordered by latent durability")
    for latent in LATENT_HALF_LIVES:
        production = final[("production", latent)]
        if not (
            production["mean_posterior_log_variance"] < VARIANTS[0].prior_log_variance
        ):
            raise AssertionError(f"{latent}d posterior variance did not contract")
        fine = final[("fine_grid", latent)]["median_estimated_half_life_days"]
        relative_grid_error = (
            abs(production["median_estimated_half_life_days"] - fine) / fine
        )
        if relative_grid_error > 0.01:
            raise AssertionError(f"{latent}d production grid differs from fine grid")


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def report(summary: list[dict[str, Any]], variants: list[dict[str, Any]]) -> None:
    print("Production posterior after controlled retrieval observations:")
    for row in summary:
        if (
            row["variant"] != "production"
            or row["observation_count"] != CHECKPOINTS[-1]
        ):
            continue
        print(
            f"  latent={row['latent_half_life_days']:>5.1f}d "
            f"median={row['median_estimated_half_life_days']:>7.2f}d "
            f"log_bias={row['mean_log_bias']:>7.3f} "
            f"coverage90={row['coverage_90_percent']:>6.1%} "
            f"variance={row['mean_posterior_log_variance']:>6.3f}"
        )
    print()
    print("Posterior representation variants:")
    for row in variants:
        print(
            f"  {row['variant']:<18} "
            f"MALE={row['mean_absolute_log_error_across_latent_half_lives']:.3f} "
            f"RMSLE={row['root_mean_squared_log_error_across_latent_half_lives']:.3f} "
            f"coverage90={row['mean_90_percent_coverage']:.1%} "
            f"variance={row['mean_posterior_log_variance']:.3f}"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).with_name("generated"),
    )
    parser.add_argument("--seeds", type=int, default=DEFAULT_SEEDS)
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.seeds < 1 or args.workers < 1:
        raise ValueError("seeds and workers must both be at least 1")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    cases = [
        (variant, latent, seed)
        for variant in VARIANTS
        for latent in LATENT_HALF_LIVES
        for seed in range(args.seeds)
    ]
    if args.workers == 1:
        case_rows = [run_case(*case) for case in cases]
    else:
        with concurrent.futures.ProcessPoolExecutor(args.workers) as executor:
            variants, latent_half_lives, seeds = zip(*cases, strict=True)
            case_rows = list(executor.map(run_case, variants, latent_half_lives, seeds))
    trajectories = [row for rows in case_rows for row in rows]
    summary = summarize(trajectories)
    variant_summary = summarize_variants(summary)
    check_calibration_structure(summary)
    outputs = {
        "posterior_validation_trajectories.csv": trajectories,
        "posterior_validation_summary.csv": summary,
        "posterior_validation_variant_summary.csv": variant_summary,
    }
    for filename, rows in outputs.items():
        write_csv(args.output_dir / filename, rows)
    report(summary, variant_summary)
    print()
    for filename in outputs:
        print(f"Wrote {args.output_dir / filename}")


if __name__ == "__main__":
    main()
