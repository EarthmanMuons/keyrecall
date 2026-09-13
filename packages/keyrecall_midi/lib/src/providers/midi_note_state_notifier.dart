import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/midi_note_state.dart';
import 'midi_input_notifier.dart';

/// What the adopted instrument is holding.
///
/// Derived from the same reducer snapshot the event stream is emitted from,
/// so the two cannot disagree about whether a pitch is sounding.
final midiNoteStateProvider = Provider<MidiNoteState>((ref) {
  final snapshot = ref.watch(
    midiInputProvider.select((state) => state.snapshot),
  );
  return MidiNoteState(
    pressed: snapshot.pressedNoteNumbers,
    sustained: snapshot.sustainedNoteNumbers,
    isPedalDown: snapshot.pedalDown,
  );
});

/// MIDI note numbers for keyboard highlighting.
final midiSoundingNoteNumbersProvider = Provider<Set<int>>((ref) {
  return ref.watch(midiNoteStateProvider.select((s) => s.soundingNoteNumbers));
});

/// Sustain pedal state.
final midiPedalDownProvider = Provider<bool>((ref) {
  return ref.watch(midiNoteStateProvider.select((s) => s.isPedalDown));
});
