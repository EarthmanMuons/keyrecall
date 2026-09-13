# Vendored from WhatChord

Most of this package is copied from the WhatChord MIDI feature
(`~/src/whatchord/lib/features/midi/`) rather than written here.

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

These files are deliberately kept close to their origin, including formatting
and comment style that does not match the rest of this repository. That is the
cost of being able to compare against upstream later.

- **Fixing a transport bug here?** Consider whether WhatChord has it too.
- **Restyling?** Don't, unless the file is being taken over outright.
- **Adding KeyRecall-specific behavior?** Put it in a new file rather than
  threading it through a vendored one.

## What was changed on the way in

Every adjustment is listed here, so a future diff against upstream has a known
set of expected differences rather than a mystery.

- The input vocabulary moved to `keyrecall_input`, so the imports point there.
- `sharedPreferencesProvider` is defined in this package instead of being
  imported from the host app's core.
- `inputEventClockProvider` comes from `keyrecall_input_sources`, which sits
  below every input source. A synthetic source has no business depending on this
  package to find out what time it is.
- Doc comments referring to `MidiConnectionStatus` and
  `midiConnectionStatusProvider` were reworded, because those symbols were not
  vendored and a dangling reference is worse than a slightly different comment.
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
  - `app_midi_lifecycle_provider.dart` ends the observation when the app leaves
    the foreground and opens a new one on resume. The connection is still kept,
    exactly as upstream keeps it.

  A transport bug fixed here is still worth checking against WhatChord. A
  divergence in this list is not: it is KeyRecall deciding that measurement
  needs a boundary WhatChord has no use for. See
  [`docs/system/input.md`](../../docs/system/input.md).

- Dropped: `midi_connection_status_provider.dart` and everything under `pages/`
  and `widgets/`. Those are presentation, and they carried WhatChord's design
  system and its chord and key features with them. KeyRecall will write its own
  against the same state.

The tests under `test/` came across too, with the same import rewrites. They are
what makes the vendored behavior checkable here rather than only upstream.

## What was not brought over yet

The demo input source, which lives outside the MIDI feature in WhatChord
(`features/demo/`). It is what makes the practice loop runnable with no hardware
attached, and it is the obvious next thing to vendor.
