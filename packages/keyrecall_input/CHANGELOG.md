# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Added

- The normalized live-input vocabulary, ported from the WhatChord input layer:
  the sealed `InputTemporalEvent` family, `InputTemporalSnapshot` with the
  states an instrument cannot be in ruled out, `InputNoteEvent`, and the
  monotonic `InputEventClock` with stopwatch and manual implementations.
