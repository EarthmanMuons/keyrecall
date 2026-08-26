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
- `v1SchedulerConfig`, at registry version `v1-1`. It began as
  `v1PrototypeSchedulerConfig`, mirroring `v1-prototype-0` in
  `analysis/scheduler/config.toml`, and was renamed when it stopped carrying
  only the prototype's values.
- A tempo probe: an attempt completed cleanly, evenly, unbroken, from memory,
  and comfortably faster than requested opens a `ChallengeBypass.tempoProbe`
  context, which admits the same task at the fastest offered tempo the learner
  reached and nothing else. Exclusive and one decision long, like recovery.
- A form-introduction prerequisite: harmonic and melodic minor wait on a breadth
  of retrieved major and natural-minor material, spread across bands, reported
  as `harmonicMinorRepertoireBreadth` and `melodicMinorRepertoireBreadth`.
  Waived for a learner whose single-hand execution is already fluent.

### Changed

- The configuration classes assert their own bounds, so the shipped registry is
  checked where it is declared.
