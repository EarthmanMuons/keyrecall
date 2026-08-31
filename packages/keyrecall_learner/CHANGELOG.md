# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Added

- Initial port of the KeyRecall V1 learner model from the Python prototype under
  `analysis/learner-model/`: `LearnerState` over competency, material memory,
  and execution-residual layers; five-channel `Prediction`; three-valued
  `FactualRetrieval` observation; `evidenceWeightsFor`; and the ordered memory
  update covering retained-consolidation inference, current-durability
  correction, and causal formation and restoration.
- `v1PrototypeLearnerParams`, mirroring the `v1-prototype-2` registry in
  `analysis/learner-model/params.toml`.

### Changed

- Hands-together challenge prediction now includes bilateral coordination as the
  correlated motor-control bottleneck; single-hand prediction is unchanged.
- Time may only move forward. Propagating backward throws instead of silently
  permitting an interval to be diffused twice, and the check runs before any
  layer is written.
- `LearnerModel.applyOutcome` rejects an attempt that predates the state or the
  material memory it would update.
- `Outcome` validates its scores at construction, and the parameter classes
  assert their own bounds.
- `LearnerParams.copyWith`, for counterfactual replay under an alternative
  parameter set. It requires a new `modelVersion`, so a variant cannot be
  recorded as the registry it was derived from.
