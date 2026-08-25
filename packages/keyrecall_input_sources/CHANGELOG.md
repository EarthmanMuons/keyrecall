# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Added

- `inputEventClockProvider`, the monotonic clock shared by every input source,
  moved here from `keyrecall_midi` so a synthetic source does not have to depend
  on the MIDI package to obtain one.
