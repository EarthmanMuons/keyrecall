# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Added

- The arpeggio census reports introduction pressure and follow-through:
  introductions per twenty-slot window, open unresolved material, revisit gaps,
  and second-attempt, other-hand, and wider-span rates within twenty slots of a
  first exposure. A `breadth` mode runs concurrent-introduction counterfactuals
  against the paired scale-only control.
- Full-catalog arpeggio characterization now compares the two-material fixture,
  all 24 root-position arpeggios, and the full mixed scale/arpeggio corpus. It
  reports fingering-family and hand-configuration concentration and can run
  deterministic trajectories through bounded isolate workers.
- The arpeggio entry-tempo census now varies the complete resolved family
  policy, distinguishing challenge sensitivity from entry-contract mismatch.
- An arpeggio-policy census over real scoped practice sessions, reporting family
  allocation, acquisition-floor dependence, progression gates, prediction
  ranges, terminal outcomes, and scale-milestone shifts. Paired arms vary family
  transfer, floor shape, and initial tempo without changing production policy.
- Mixed scale/arpeggio trajectory characterization across every placement prior
  and multiple seeds, including explicit blocked termination when no candidate
  remains admitted.
- Hands-together evidence and coordination-aware admission diagnostics at
  independent-trajectory grain, distinguishing a coordination-caused band
  crossing from coordination merely being the weaker motor factor.
- A paired same-seed experiment comparing current HT execution progression with
  diagnostic-only suppression when coordination is the weaker factor.
- A realization-family pacing census covering allocation, yield, concentration,
  return paths, and motion balance across learner archetypes.
- `PacingLog`, which accumulates the realization-family pacing decisions of one
  trajectory. The mechanism itself was settled here and now ships in
  `keyrecall_scheduler`.
- A paired same-seed experiment comparing current scheduling against
  realization-family pressure across archetypes.
- `FamilySetAside` and a diagnostic reporting how ready the best cross-family
  alternative is wherever pressure displaces a candidate.
- `requireReadyAlternative`, which relieves a pressured family only when a
  surviving candidate is at least as ready as the one it displaces.
- Realization rank, ranking terms, inert-substitution detection, and per-slot
  relief-criterion comparison in the set-aside diagnostic.
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
