# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Fixed

- `admissionBandOf` places arpeggios by the geography of their chord rather than
  answering `foundation` for everything without a scale form. A white-key triad
  is foundation material, a white root with black keys inside it is early
  transfer, a black root is later still, and an all-black triad is the latest
  band. Material neither family places now falls to the latest band, as the
  documented intent already said.

### Added

- `Exercise.hashCode` is computed once per exercise rather than on every lookup.
- `distinctCandidatesOf`, which assembles a scope's candidate envelope by
  material rather than by hashing every generated exercise.
- Initial extraction of the KeyRecall V1 practice domain into a standalone pure
  Dart package: `TechnicalMaterial` and `ScaleForm`, `Exercise` with
  `ExercisePattern`, `ExecutionConditions`, and `GuidanceContext`,
  `MotorOpportunity` sites, the `Competency` ontology with its motor and
  topology channels, `Exercise.structuralQ`, `InstrumentProfile`, and the
  `v1ScaleCatalog` scale set.

### Changed

- The supported arpeggio corpus now covers all 12 canonical major and minor
  root-position tonics in both hands. Every record carries source status,
  explicit descent symmetry, and generative one-, two-, and four-octave
  fingering, while inversions and unsupported enharmonic spellings remain
  absent.
- Material families now declare their supported octave sequence, whether wider
  spans require local evidence, whether hands-together work requires separate
  hands, and any prerequisite material identities. Arpeggios declare
  `1 -> 2 -> 4` spans and root position before inversions.
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
