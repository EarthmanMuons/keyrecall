import 'package:meta/meta.dart';

/// Whether a key went down or came up.
enum InputNoteEventType { noteOn, noteOff }

/// A key press or release, without timing.
///
/// The simpler of the two input vocabularies, for consumers that care only
/// about what is sounding right now. Anything measuring a performance wants
/// the timestamped stream instead.
@immutable
class InputNoteEvent {
  /// Whether the key went down or came up.
  final InputNoteEventType type;

  /// Which note, as a MIDI note number.
  final int noteNumber;

  /// How hard it was struck or released, from 0 to 127.
  final int velocity;

  /// Throws [RangeError] for a note or velocity outside MIDI range.
  InputNoteEvent({
    required this.type,
    required this.noteNumber,
    required this.velocity,
  }) {
    if (noteNumber < 0 || noteNumber > 127) {
      throw RangeError.range(noteNumber, 0, 127, 'noteNumber');
    }
    if (velocity < 0 || velocity > 127) {
      throw RangeError.range(velocity, 0, 127, 'velocity');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is InputNoteEvent &&
      other.type == type &&
      other.noteNumber == noteNumber &&
      other.velocity == velocity;

  @override
  int get hashCode => Object.hash(type, noteNumber, velocity);

  @override
  String toString() => '${type.name}($noteNumber, velocity: $velocity)';
}
