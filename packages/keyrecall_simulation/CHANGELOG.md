# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Added

- Initial port of the KeyRecall synthetic harness from the Python prototypes:
  the seven `SyntheticProfile` hidden learners, outcome sampling and true memory
  transitions, `PracticeSimulation`, and the `SchedulerAgent` that drives the
  real pipeline inside a run.
- `PythonCompatibleRandom`, a Mersenne Twister reproducing CPython's
  `random.Random` stream, and `attemptTraceToJson`, so a Dart run can be diffed
  attempt by attempt against the reference implementation.
- A `simulate` executable mirroring `analysis/learner-model/simulate.py`.
