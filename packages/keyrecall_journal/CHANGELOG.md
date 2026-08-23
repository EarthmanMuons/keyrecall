# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Added

- Initial attempt-journal boundary: `AttemptRecord` with identity, model
  provenance, presented exercise, scheduler decision, observation, evidence
  weights, and memory attribution; an append-only `AttemptJournal` that is
  idempotent on the attempt id and encodes to JSON lines; and
  `LearnerStateCheckpoint` as content-hashed, disposable acceleration.
- `replayJournal` in exact and counterfactual modes, recomputing each attempt
  and comparing against what was recorded rather than reapplying it.
- Serialization for the domain, learner, and scheduler types, owned here rather
  than on the model types, with validation of the persisted-state invariants on
  read.
