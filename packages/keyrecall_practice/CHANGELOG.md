# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Added

- `PracticeSession`, the attempt transaction: it persists the decision before
  presenting, commits the outcome as an attempt, and recovers from a run
  interrupted anywhere in that sequence.
- `PendingDecision`, the durable record of what was presented but not yet
  answered, deliberately outside the journal.
- `PracticeStore`, the storage port, with an in-memory implementation and
  `FilePracticeStore`, which appends to ordinary files and repairs a torn tail.
- Commit computes the transition on a copy and replaces canonical state only
  after a durable append, so a storage failure that leaves the process running
  can be retried safely.
- Recovery validates a pending decision's profile, journal position, and
  timestamp before accepting it.
- `ProfileRepository`, with in-memory and file-backed implementations, covering
  profile creation, listing, renaming, and selection. Kept separate from
  practice storage, and deliberately without deletion.
