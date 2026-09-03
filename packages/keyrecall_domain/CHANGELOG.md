# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Added

- Initial extraction of the KeyRecall V1 practice domain into a standalone pure
  Dart package: `TechnicalMaterial` and `ScaleForm`, `Exercise` with
  `ExercisePattern`, `ExecutionConditions`, and `GuidanceContext`,
  `MotorOpportunity` sites, the `Competency` ontology with its motor and
  topology channels, `Exercise.structuralQ`, `InstrumentProfile`, and the
  `v1ScaleCatalog` scale set.

### Changed

- Major and minor triad arpeggios represent root, first-inversion, and
  second-inversion topology as distinct material identities. C minor root
  position joins the non-product fixture with sourced fingering.
- Canonical fingerings now use one family-neutral, provenance-bearing
  `entry / cycle / terminal` record with explicit descent symmetry. Supported
  arpeggios use the same representation as scales, and unsupported records are
  absent rather than inferred.
- Motor opportunities retain exact hand and moment sites. Crossing types come
  from canonical fingering records, so arpeggio transitions occur only at
  realized continuation boundaries.
- `GuidanceContext` has exactly three constructible values. Notes previewed
  together with visible cues described the same condition as continuous cueing
  while comparing and hashing differently, and guidance is part of exercise
  identity.
- `TechnicalMaterial`, `ExecutionConditions`, and `InstrumentProfile` validate
  at construction. The tonic must already be canonical, since it feeds the
  persisted material ID and is not repaired silently.
