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
- `v1PrototypeSchedulerConfig`, mirroring the `v1-prototype-0` registry in
  `analysis/scheduler/config.toml`.
