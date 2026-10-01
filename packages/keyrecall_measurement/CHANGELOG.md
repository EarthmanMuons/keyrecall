# Changelog

## Unreleased

- `PerformanceMeasurement.handAsynchronies` carries each measured spread with
  the moment it happened at, and `handAsynchroniesMs` reads the values off it.
  `looseMoments` names the moments outside the policy's synchronized bound, so a
  caller can ask where the hands were apart rather than only how far apart they
  got.

## [Unreleased]

### Changed

- `MeasurementPolicy.minimumTimedIntervalMs`, 20 ms by default. Below it the
  median wait between moments is the clock's resolution rather than pacing, so
  `TimingEvidence` reads no pace, reference, dispersion, or worst ratio, and
  continuity, steadiness, and achieved tempo all report absence together. A
  median wait of zero or less is below the floor like any other, rather than
  being read as too few waits to judge. Timing evidence now reads the policy
  measurement was given rather than the standard one.

- `outcomeFor` takes the presentation's delivery and marks pulse maintenance
  untested when any beat reached the learner once the attempt began.

## 0.1.0

- Measurement of a single-hand aligned performance, and its conversion into an
  `Outcome`.
