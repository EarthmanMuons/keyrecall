# Changelog

## Unreleased

- `PerformanceMeasurement.handAsynchronies` carries each measured spread with
  the moment it happened at, and `handAsynchroniesMs` reads the values off it.
  `looseMoments` names the moments outside the policy's synchronized bound, so a
  caller can ask where the hands were apart rather than only how far apart they
  got.

## 0.1.0

- Measurement of a single-hand aligned performance, and its conversion into an
  `Outcome`.
