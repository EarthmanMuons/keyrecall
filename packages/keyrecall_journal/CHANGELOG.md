# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Changed

- Attempt schema 10 records the rank key's shape progression term. An earlier
  record reads it as zero because it was not recorded, which says nothing about
  how that decision ranked shapes.
- Session export schema version 3 names the session `session_id`, as the attempt
  and acquisition journals do. `SittingExport` and its codec are now
  `SessionExport`, `encodeSessionExport`, and `decodeSessionExport`.

- A record whose outcome and presentation disagree about whether a pulse was
  supplied is refused on reading. `AttemptRecord.pulseDisagreement` says why,
  and a record with no presentation has nothing to disagree with.

- Attempt schema version 7 and acquisition schema version 9 record a pulse's
  count-in and continuing beats separately, and an outcome's pulse maintenance.
  Earlier records upgrade to a count-in with nothing after it and an outcome
  that tested the pulse, which practice never asked otherwise; one whose
  conditions asked for a metronome is refused rather than split.
- Attempt schema version 8 and acquisition schema version 10 record how many
  continuing beats were shown on screen. Earlier records read as none shown,
  since no build before showed one.

- The acquisition decoder hands a repetition count to `TraversalRepetitions`
  instead of judging it, so what counts as a valid count stays a domain rule
  rather than a serialization one. An invalid count is still a decode failure.

- The historical fixtures are now named by learner model version. The `v1-8`
  pair is kept byte for byte, and what this build does with it is tested:
  readable, refused by exact replay, re-estimated only on request, and a cache
  miss as a checkpoint. That version could not be made replayable, because it
  named a transition whose summation order followed the order an exercise's
  opportunities happened to iterate in. The `v1-9` pair is the same history
  re-recorded, and it still replays exactly.

### Added

- `replayJournal` takes an optional `observe` callback, called with the state
  each attempt was decided against. A diagnostic seam: replay behaves
  identically whether or not one is passed.

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
