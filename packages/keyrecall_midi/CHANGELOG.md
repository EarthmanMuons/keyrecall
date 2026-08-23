# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Added

- MIDI transport vendored from WhatChord: the plugin boundary, the device graph
  manager, the connection state machine with auto-reconnect and backoff, note
  and pedal state tracking, and the normalized temporal event stream. See
  VENDORED.md.
- The upstream tests for the vendored providers, so the behavior is checkable
  here rather than only in WhatChord.
