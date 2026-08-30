import 'package:meta/meta.dart';

/// One of the seven letter names, with the pitch class it names unaltered.
enum NoteLetter {
  c('C', 0),
  d('D', 2),
  e('E', 4),
  f('F', 5),
  g('G', 7),
  a('A', 9),
  b('B', 11);

  const NoteLetter(this.label, this.naturalPitchClass);

  /// The letter itself, `A` through `G`.
  final String label;

  /// The pitch class this letter names with no accidental.
  final int naturalPitchClass;

  /// The letter [steps] letters above this one, wrapping through G to A.
  NoteLetter stepsAbove(int steps) => values[(index + steps) % values.length];

  /// The letter written [label].
  ///
  /// Throws [ArgumentError] when [label] is not a letter name.
  static NoteLetter fromLabel(String label) => values.firstWhere(
    (letter) => letter.label == label.toUpperCase(),
    orElse: () => throw ArgumentError.value(label, 'label', 'not a letter'),
  );
}

/// A written pitch: a letter, an accidental, and an octave.
///
/// The canonical form for anything that has to be *notated*, because a MIDI
/// number cannot be notated. 70 is B♭ in one key and A♯ in another, and G♯
/// harmonic minor needs F𝄪 for its seventh degree, which no MIDI number
/// distinguishes from G. [midiNote] is derived from the spelling rather than
/// stored beside it, so the two can never disagree.
///
/// [octave] is scientific pitch notation, where middle C is C4. It follows the
/// letter, not the sound: C♭4 is written in the fourth octave and sounds a
/// semitone below C4.
@immutable
class SpelledPitch {
  /// The letter this pitch is written with.
  final NoteLetter letter;

  /// Semitones the accidental raises the letter, from -2 to 2.
  final int alteration;

  /// Scientific octave, where middle C is C4.
  final int octave;

  /// Throws [ArgumentError] for an accidental beyond a double flat or double
  /// sharp, which no scale in the catalog needs and no staff draws.
  SpelledPitch({
    required this.letter,
    required this.octave,
    this.alteration = 0,
  }) {
    if (alteration < -2 || alteration > 2) {
      throw ArgumentError.value(
        alteration,
        'alteration',
        'must be between a double flat and a double sharp',
      );
    }
  }

  /// The same spelling [octaves] higher, or lower for a negative count.
  ///
  /// Spelling is untouched, because moving by whole octaves cannot change a
  /// letter or an accidental. An F sharp stays an F sharp.
  SpelledPitch shiftedByOctaves(int octaves) => octaves == 0
      ? this
      : SpelledPitch(
          letter: letter,
          octave: octave + octaves,
          alteration: alteration,
        );

  /// The pitch class this spelling sounds.
  int get pitchClass => (letter.naturalPitchClass + alteration + 12) % 12;

  /// Which key on the instrument this is written for.
  int get midiNote => (octave + 1) * 12 + letter.naturalPitchClass + alteration;

  /// How this pitch is written, such as `F#` or `Ebb`.
  String get label => letter.label + _accidental;

  /// How this pitch reads to a musician, such as `F♯` or `E𝄫`.
  String get prettyLabel => letter.label + _prettyAccidental;

  String get _accidental => switch (alteration) {
    -2 => 'bb',
    -1 => 'b',
    0 => '',
    1 => '#',
    _ => '##',
  };

  String get _prettyAccidental => switch (alteration) {
    -2 => '𝄫',
    -1 => '♭',
    0 => '',
    1 => '♯',
    _ => '𝄪',
  };

  /// The spelling of [midiNote] as [letter], or null when that letter cannot
  /// write that pitch without more than a double accidental.
  ///
  /// The letter is the caller's to choose, because it is what the musical
  /// context decides: the fifth degree of a scale is spelled on the fifth
  /// letter whatever it sounds like.
  static SpelledPitch? forMidiNote(int midiNote, {required NoteLetter letter}) {
    // Semitones from the letter's natural spelling to the target pitch,
    // normalized so a letter near an octave boundary alters by a little rather
    // than by eleven.
    var alteration = (midiNote - letter.naturalPitchClass) % 12;
    if (alteration > 6) alteration -= 12;
    if (alteration < -2 || alteration > 2) return null;

    final octave = (midiNote - letter.naturalPitchClass - alteration) ~/ 12 - 1;
    return SpelledPitch(letter: letter, alteration: alteration, octave: octave);
  }

  @override
  bool operator ==(Object other) =>
      other is SpelledPitch &&
      other.letter == letter &&
      other.alteration == alteration &&
      other.octave == octave;

  @override
  int get hashCode => Object.hash(letter, alteration, octave);

  @override
  String toString() => '$label$octave';
}
