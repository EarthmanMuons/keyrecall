# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Added

- Hands-together evidence and coordination-aware admission diagnostics at
  independent-trajectory grain, distinguishing a coordination-caused band
  crossing from coordination merely being the weaker motor factor.
- A paired same-seed experiment comparing current HT execution progression
  with diagnostic-only suppression when coordination is the weaker factor.
- A realization-family pacing census covering allocation, yield, concentration,
  return paths, and motion balance across learner archetypes.
- `RealizationFamilyPacing`, a rolling allocation-and-yield model over declared
  realization-family keys, and `FamilyPacedPipeline`, which applies its pressure
  at selection beside the repetition guard.
- A paired same-seed experiment comparing current scheduling against
  realization-family pressure across archetypes.
- Initial port of the KeyRecall synthetic harness from the Python prototypes:
  the seven `SyntheticProfile` hidden learners, outcome sampling and true memory
  transitions, `PracticeSimulation`, and the `SchedulerAgent` that drives the
  real pipeline inside a run.
- `PythonCompatibleRandom`, a Mersenne Twister reproducing CPython's
  `random.Random` stream, and `attemptTraceToJson`, so a Dart run can be diffed
  attempt by attempt against the reference implementation.
- A `simulate` executable mirroring `analysis/learner-model/simulate.py`.

### Added

- `discreteTraceDigest`, an exact cross-implementation hash of a run's
  categorical decisions and outcomes, with `tool/reference_digest.py` producing
  the same digest from the Python prototype.
- `fullTraceDigest`, a full-precision regression sentinel for this
  implementation.
