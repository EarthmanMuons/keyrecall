/// The normalized live-input vocabulary for KeyRecall.
///
/// Every input source reduces to [InputTemporalEvent], whatever it is
/// underneath: a MIDI instrument, a synthetic source for demos and tests, or
/// anything added later. Normalizing here is what keeps the rest of the app
/// from reasoning about transports, and what lets a practice loop be exercised
/// end to end before any hardware is involved.
///
/// The vocabulary is ported from the WhatChord input layer, which had already
/// worked out the cases that matter: repeated note-ons for a held key, a
/// reattack after the pedal released a note, all-notes-off, and the reset
/// boundaries that stop a consumer from believing keys are held that nobody is
/// holding.
library;

export 'src/input_event_clock.dart';
export 'src/input_note_event.dart';
export 'src/input_temporal_event.dart';
