# Forked from WhatChord

This package started as a copy of the WhatChord MIDI feature
(`~/src/whatchord/lib/features/midi/`) and is now a fork: it answers to
KeyRecall, and tracking upstream is no longer a goal.

## Why it was copied rather than rewritten

The value of this code is not its shape, it is the accumulated knowledge of what
real instruments and real platforms do. Hard timeouts exist because plugin calls
hang on some devices. Reconciliation on resume exists because iOS drops
Bluetooth links while backgrounded without emitting timely events. Reconnect
target remapping exists because platforms can expose the same physical device
with a changed id across sessions. The single-flight guard exists because
overlapping reconnect runs left stale retry state in the UI.

None of that is visible from reading the code. Rewriting it would have meant
rediscovering it.

## What that means for changes

Change it the way you would change any package here. Correctness work,
refactoring, and repository style all apply, and nothing has to be justified
against upstream first.

What remains true is the direction of the debt: WhatChord is where this
knowledge was earned, so a transport bug fixed here is worth reporting there.
The reverse no longer holds. KeyRecall measures performance, WhatChord
recognizes chords, and the two want different things from the same radio.

## How it already differs

Kept because it is the list worth reading before backporting anything to
WhatChord, not because a diff against upstream is expected to be clean.

- The input vocabulary moved to `keyrecall_input`, so the imports point there.
- `midiPreferenceStoreProvider` is the store this package persists to, declared
  here and overridden at startup. Upstream reaches for the host app's
  `sharedPreferencesProvider`, which would make every app setting depend on the
  MIDI package to find its own storage.
- `inputEventClockProvider` comes from `keyrecall_input_sources`, which sits
  below every input source. A synthetic source has no business depending on this
  package to find out what time it is.
- Doc comments referring to `MidiConnectionStatus` and
  `midiConnectionStatusProvider` were reworded, because those symbols did not
  come across and a dangling reference is worse than a slightly different
  comment.
- The input boundary was taken over outright. Upstream reads the raw message
  stream from several places at once, each drawing its own conclusions;
  KeyRecall needs one interpretation it can prove things about, so
  `midi_input_notifier.dart` owns an `InputReducer` and everything else reads
  it. What that displaced:
  - `midi_note_state_notifier.dart` no longer tracks notes. `MidiNoteState` is
    now derived from the reducer's snapshot, so sounding state and the event
    stream cannot disagree. Its pedal latch went with it, unused.
  - `midi_temporal_events_provider.dart` no longer normalizes. It delivers what
    the reducer produced.
  - `midi_note_events_provider.dart` and `midi_message_providers.dart` are gone.
    Both were second readings of the wire, and the first substituted note zero
    for a message without one.
  - `MidiBleService.onMidiMessages` carries `MidiSourceMessage` rather than a
    bare message. Upstream discards the device, transport, channel, and plugin
    timestamp the plugin supplies; without them nothing downstream can tell the
    adopted instrument from any other live source. Each transport subscription
    also mints its own session token, so a reconnect that reuses a device id is
    a different source rather than the same one.
  - `MidiBleService` reports a BLE instrument the plugin has handed off to the
    platform MIDI stack as the host route. Upstream takes the plugin's transport
    label, which names the device type and so says `ble` for both paths, whose
    timestamps come from different clocks.
  - `app_midi_lifecycle_provider.dart` ends the observation when the app leaves
    the foreground and opens a new one on resume. The connection is still kept,
    exactly as upstream keeps it.

  This is KeyRecall deciding that measurement needs a boundary WhatChord has no
  use for. See [`docs/system/input.md`](../../docs/system/input.md).

- Connection attempts carry a generation so a manual selection supersedes
  reconnect discovery, backoff, and pending connection results. Cancel
  suppresses automatic reconnect, and disconnect also tears down a pending
  native connection. Late results cannot overwrite or disconnect a newer
  selection. Native teardown is tracked per device, and a new connection waits
  for that device's pending teardown, including cleanup from a stale connection
  completion.

- Dropped: `midi_connection_status_provider.dart` and everything under `pages/`
  and `widgets/`. Those are presentation, and they carried WhatChord's design
  system and its chord and key features with them. KeyRecall will write its own
  against the same state.

The tests under `test/` came across too, with the same import rewrites. They are
what makes this behavior checkable here rather than only upstream.

## What was not brought over

The demo input source, which lives outside the MIDI feature in WhatChord
(`features/demo/`). KeyRecall wrote its own in `lib/features/demo_input/`.
