import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'input_integrity.dart';
import 'input_temporal_event.dart';

const _noteSetEquality = SetEquality<int>();

/// What is sounding, as reconstructed from the normalized stream alone.
///
/// The other half of the reducer's contract: replaying every event it emits
/// through this must arrive at the snapshot it holds. A consumer that cannot
/// see the source's internals still knows exactly what the source believes.
@immutable
class InputTemporalState {
  /// Notes whose keys are held.
  final Set<int> pressedNoteNumbers;

  /// Notes released but still sounding under the pedal.
  final Set<int> sustainedNoteNumbers;

  /// Whether the pedal is down.
  final bool pedalDown;

  /// The fault that ended the observation, if one did.
  final InputIntegrityFault? fault;

  const InputTemporalState({
    this.pressedNoteNumbers = const {},
    this.sustainedNoteNumbers = const {},
    this.pedalDown = false,
    this.fault,
  });

  /// Nothing sounding, pedal up, no fault.
  static const InputTemporalState silent = InputTemporalState();

  /// Every note sounding, however it is being held.
  Set<int> get soundingNoteNumbers => {
    ...pressedNoteNumbers,
    ...sustainedNoteNumbers,
  };

  /// Whether an integrity fault ended the observation.
  bool get isFaulted => fault != null;

  /// This state as a snapshot.
  InputTemporalSnapshot get snapshot => InputTemporalSnapshot(
    pressedNoteNumbers: pressedNoteNumbers,
    sustainedNoteNumbers: sustainedNoteNumbers,
    pedalDown: pedalDown,
  );

  @override
  bool operator ==(Object other) =>
      other is InputTemporalState &&
      other.pedalDown == pedalDown &&
      other.fault == fault &&
      _noteSetEquality.equals(other.pressedNoteNumbers, pressedNoteNumbers) &&
      _noteSetEquality.equals(other.sustainedNoteNumbers, sustainedNoteNumbers);

  @override
  int get hashCode => Object.hash(
    pedalDown,
    fault,
    _noteSetEquality.hash(pressedNoteNumbers),
    _noteSetEquality.hash(sustainedNoteNumbers),
  );

  /// This state after [event].
  InputTemporalState applying(InputTemporalEvent event) {
    switch (event) {
      case InputTemporalNoteOnEvent(:final noteNumber):
        // A reattack takes the note back from the pedal: it is held again.
        return InputTemporalState(
          pressedNoteNumbers: {...pressedNoteNumbers, noteNumber},
          sustainedNoteNumbers: {...sustainedNoteNumbers}..remove(noteNumber),
          pedalDown: pedalDown,
        );
      case InputTemporalNoteOffEvent(:final noteNumber):
        return InputTemporalState(
          pressedNoteNumbers: {...pressedNoteNumbers}..remove(noteNumber),
          sustainedNoteNumbers: pedalDown
              ? {...sustainedNoteNumbers, noteNumber}
              : ({...sustainedNoteNumbers}..remove(noteNumber)),
          pedalDown: pedalDown,
        );
      case InputTemporalPedalEvent(:final down):
        // Lifting the pedal damps everything it was holding. No note-offs
        // follow, because those already arrived when the keys came up.
        return InputTemporalState(
          pressedNoteNumbers: pressedNoteNumbers,
          sustainedNoteNumbers: down ? sustainedNoteNumbers : const {},
          pedalDown: down,
        );
      case InputTemporalResetEvent(:final snapshot):
        return InputTemporalState(
          pressedNoteNumbers: snapshot.pressedNoteNumbers,
          sustainedNoteNumbers: snapshot.sustainedNoteNumbers,
          pedalDown: snapshot.pedalDown,
        );
      case InputTemporalFaultEvent(:final fault):
        return InputTemporalState(fault: fault);
    }
  }
}
