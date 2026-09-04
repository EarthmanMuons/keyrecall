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
- `Profile`, with opaque version 4 UUID identifiers, so several people can share
  one install. Every attempt record and checkpoint is scoped by profile id, and
  a journal refuses an attempt belonging to another profile.
- `journalSequence`, a contiguous journal-global position, so a checkpoint can
  say where it sits in a history spanning many sessions and a lost record is
  detectable.
- `observedWallTime`, the optional raw device reading, kept separate from the
  model timeline that drives decay.

### Changed

- Attempt schema 4 records exact motor-opportunity sites. Version 1 through 3
  records and pending decisions retain their opportunity kinds without inventing
  event locations.
- Attempt schema 3 records coordination prediction. Version 1 and 2 records and
  pending decisions upgrade with a coordination probability of one, preserving
  their former challenge semantics.
