# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Added

- Initial port of the KeyRecall V1 scheduler from the Python prototype under
  `analysis/scheduler/`: candidate generation, the eligibility, safety,
  challenge, and priority stages, per-candidate `CandidateTrace` records,
  lexicographic `RankKey` ranking, the repetition guard, and the new-material,
  guidance-probe, bootstrap-probe, recovery, and override admission exceptions.
- `v1SchedulerConfig`, at registry version `v1-3`. It began as
  `v1PrototypeSchedulerConfig`, mirroring `v1-prototype-0` in
  `analysis/scheduler/config.toml`, and was renamed when it stopped carrying
  only the prototype's values.
- A diagnostic fairness guard at selection: once enough selection opportunities
  have passed with an independence probe ranked and losing, the highest-ranked
  one is taken. Beside the repetition guard rather than in the rank key or as
  another bypass.
- An observation probe: after a run of attempts in which retrieval went
  unobserved, one retrieval-observing candidate is admitted whatever its
  predicted success, reported as `ChallengeBypass.observationProbe`.
- A tempo probe: an attempt completed cleanly, evenly, unbroken, from memory,
  and comfortably faster than requested opens a `ChallengeBypass.tempoProbe`
  context, which admits the same task at the fastest offered tempo the learner
  reached and nothing else. Exclusive and one decision long, like recovery.
- Realization-family pacing at selection, configured by `SchedulerConfig.pacing`
  and null where allocation is unpaced. Exercises declare the family keys they
  consume; a family that holds much of a rolling window with little managed
  execution to show for it has its candidates set aside, but only when another
  family offers a candidate at least as ready and never when nothing else is
  admitted. The window lives on `SessionState`, and `SelectionResult.pacing`
  reports what the filter did with each slot. The constants are provisional; see
  `docs/design/realization-family-pacing.md`.
- A form-introduction prerequisite: harmonic and melodic minor wait on a breadth
  of retrieved major and natural-minor material, spread across bands, reported
  as `harmonicMinorRepertoireBreadth` and `melodicMinorRepertoireBreadth`.
  Waived for a learner whose single-hand execution is already fluent.

### Changed

- Challenge admission now consumes coordination-aware overall prediction for
  hands-together candidates. Admission exceptions are otherwise unchanged.
- The configuration classes assert their own bounds, so the shipped registry is
  checked where it is declared.
