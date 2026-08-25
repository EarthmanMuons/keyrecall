# keyrecall_input

The normalized live-input vocabulary for
[KeyRecall](https://github.com/EarthmanMuons/keyrecall). Pure Dart, no Flutter
dependencies.

Every input source reduces to `InputTemporalEvent`, whatever it is underneath: a
MIDI instrument, a synthetic source for demos and tests, or anything added
later. Normalizing here keeps the rest of the app from reasoning about
transports, and lets a practice loop be exercised end to end before any hardware
is involved.

## The vocabulary

| Event                       | Meaning                                                       |
| --------------------------- | ------------------------------------------------------------- |
| `InputTemporalNoteOnEvent`  | A key was struck. Velocity 1 to 127.                          |
| `InputTemporalNoteOffEvent` | A key was released. The note may still sound under the pedal. |
| `InputTemporalPedalEvent`   | The sustain pedal moved.                                      |
| `InputTemporalResetEvent`   | The stream restarted, carrying what was sounding.             |

The family is sealed, so a consumer that forgets a case fails to compile rather
than silently ignoring input.

## What the stream guarantees

By the time events reach this form the cleanup has already happened:

- A repeated note-on for a key that is already held is **not** an event, because
  nothing changed.
- A note-on after the pedal released a note **is** one, because a reattack is
  real playing.
- A note-on with zero velocity is a release, and arrives as a note-off.
- Pedal release clears what the pedal was holding.
- All-notes-off arrives as a reset.

Timestamps come from a monotonic `InputEventClock`, not a wall clock. A clock
correction mid-performance must not be able to reorder what was played.

`InputTemporalSnapshot` refuses states an instrument cannot be in: a note that
is both held and sustained, or sustained notes with the pedal up.

## Resets matter to a practice attempt

A reset is an administrative boundary, not something anybody played: a source
swap, a disconnect, an all-notes-off, or a repair of drifted state.

It carries a snapshot so a consumer tracking held notes is not left believing
keys are held that nobody is holding. For KeyRecall specifically, a reset in the
middle of an attempt is also the signal that the observation is **incomplete**:
what follows cannot be compared against what came before as though it were
continuous, and the attempt should be recorded as interrupted rather than scored
as though it finished.

## Provenance

Ported from the WhatChord input layer, which had already worked out the cases
above against real instruments. The vocabulary is carried over deliberately
rather than reinvented; the transport that produces it, and the Riverpod
providers that wire it up, are a separate concern.

## Usage

```dart
import 'package:keyrecall_input/keyrecall_input.dart';

void main() {
  final clock = ManualInputClock();
  final events = <InputTemporalEvent>[
    InputTemporalResetEvent(
      timestampMs: clock(),
      snapshot: InputTemporalSnapshot.silent,
    ),
  ];

  clock.advance(120);
  events.add(
    InputTemporalNoteOnEvent(
      timestampMs: clock(),
      noteNumber: 60,
      velocity: 90,
    ),
  );

  for (final event in events) {
    final described = switch (event) {
      InputTemporalNoteOnEvent(:final noteNumber) => 'struck $noteNumber',
      InputTemporalNoteOffEvent(:final noteNumber) => 'released $noteNumber',
      InputTemporalPedalEvent(:final down) => 'pedal ${down ? 'down' : 'up'}',
      InputTemporalResetEvent() => 'stream reset',
    };
    print('${event.timestampMs}ms: $described');
  }
}
```
