import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import 'input_temporal_events_provider.dart';

/// What the instrument is doing, as reconstructed from the event stream alone.
///
/// Nothing here reads the source's internal state. Tracking notes by watching
/// note-ons, note-offs, pedal events, and resets is exactly what any consumer
/// of live input has to do, so building the display this way keeps the stream
/// honest: if the events were not sufficient to know what is sounding, this
/// would visibly drift.
///
/// Held and sustained notes are kept apart for the same reason the source
/// keeps them apart. A note-off under the pedal ends the hold, not the sound,
/// and collapsing the two here would report silence while the instrument is
/// still ringing. The events carry enough to tell them apart, which is the
/// property this panel exists to demonstrate.
@immutable
class InputActivity {
  /// Notes whose keys are believed to be held.
  final Set<int> pressedNoteNumbers;

  /// Notes released but believed to be ringing under the pedal.
  final Set<int> sustainedNoteNumbers;

  /// Whether the pedal is believed to be down.
  final bool isPedalDown;

  /// The most recent events, newest first, for watching the stream work.
  final List<String> recent;

  /// How many events have arrived since the stream opened.
  final int eventCount;

  /// How many resets have arrived.
  ///
  /// A reset mid-attempt means the observation is not continuous, which is
  /// something a scoring layer will eventually have to refuse to measure
  /// across.
  final int resetCount;

  const InputActivity({
    this.pressedNoteNumbers = const {},
    this.sustainedNoteNumbers = const {},
    this.isPedalDown = false,
    this.recent = const [],
    this.eventCount = 0,
    this.resetCount = 0,
  });

  /// Every note believed to be making sound, however it is being held.
  Set<int> get soundingNoteNumbers => {
    ...pressedNoteNumbers,
    ...sustainedNoteNumbers,
  };

  /// Whether any input has arrived at all.
  bool get isIdle => eventCount == 0;
}

/// How many recent events the panel keeps. Enough to see a scale go by.
const int _recentEventLimit = 12;

/// Live input activity, whichever source is producing it.
final inputActivityProvider =
    NotifierProvider<InputActivityNotifier, InputActivity>(
      InputActivityNotifier.new,
    );

class InputActivityNotifier extends Notifier<InputActivity> {
  @override
  InputActivity build() {
    // Listening here is also what keeps the selected source subscribed for as
    // long as anything is watching activity.
    ref.listen<AsyncValue<InputTemporalEvent>>(inputTemporalEventsProvider, (
      _,
      next,
    ) {
      final event = next.value;
      if (event != null) _record(event);
    }, fireImmediately: true);
    return const InputActivity();
  }

  void _record(InputTemporalEvent event) {
    final pressed = {...state.pressedNoteNumbers};
    final sustained = {...state.sustainedNoteNumbers};
    var pedalDown = state.isPedalDown;

    switch (event) {
      case InputTemporalNoteOnEvent(:final noteNumber):
        // A reattack takes the note back from the pedal: it is held again.
        pressed.add(noteNumber);
        sustained.remove(noteNumber);
      case InputTemporalNoteOffEvent(:final noteNumber):
        pressed.remove(noteNumber);
        if (pedalDown) {
          sustained.add(noteNumber);
        } else {
          sustained.remove(noteNumber);
        }
      case InputTemporalPedalEvent(:final down):
        pedalDown = down;
        // Lifting the pedal damps everything it was holding. No note-offs
        // follow, because those already arrived when the keys came up.
        if (!down) sustained.clear();
      case InputTemporalResetEvent(:final snapshot):
        pressed
          ..clear()
          ..addAll(snapshot.pressedNoteNumbers);
        sustained
          ..clear()
          ..addAll(snapshot.sustainedNoteNumbers);
        pedalDown = snapshot.pedalDown;
    }

    state = InputActivity(
      pressedNoteNumbers: pressed,
      sustainedNoteNumbers: sustained,
      isPedalDown: pedalDown,
      recent: [
        '${event.timestampMs}ms  $event',
        ...state.recent.take(_recentEventLimit - 1),
      ],
      eventCount: state.eventCount + 1,
      resetCount: state.resetCount + (event is InputTemporalResetEvent ? 1 : 0),
    );
  }
}
