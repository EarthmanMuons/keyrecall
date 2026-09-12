# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Changed

- Learner model `v1-9`. Every reduction over competencies now runs in
  `Competency.values` order rather than the order the exercise's own set
  iterates in, so a serialized exercise sums to the same bits as the presented
  one. The version moves because the arithmetic can.
- `LearnerModel` takes no behavioral switch. `attributesDemonstratedDifficulty`
  and `includesCoordinationInChallenge` are read from the model version, so the
  version identifies one transition function and cannot name two.
- `applyOutcome` validates the whole transition before it writes anything, and
  requires every propagating layer of the state to stand exactly at the
  attempt's time. `LearnerState.requireAlignedAt` is that check;
  `lastPropagatedAt` is a summary rather than proof, since a maximum cannot see
  a layer left behind. The `applyRetainedDurabilityInference` flag is gone:
  disabling the posterior is a parameter with a version behind it.
- `propagateAndApplyOutcome` is the composite for callers with no reason to
  separate the two halves, and is atomic with respect to every rejection
  including propagation's own. `LearnerState.adoptFrom` is how it commits, so a
  caller holding one competency or one material's memory keeps holding the same
  object.
- An attempt that never began carries no execution evidence: positive competency
  or material-execution weights are refused, while reduced weights from an
  attempt that did begin stay welcome.
- `Outcome`, `Prediction`, and `EvidenceWeights` reject values outside their
  documented ranges at construction.
- An attempt that established no pace records no performed tempo, rather than
  filing one at the bottom of the ladder. `Outcome.measuredTempoRatio` is the
  one reading of the sentinel.
- Learner model `v1-8` adds minor-arpeggio topology as a distinct competency.

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
