import 'spelled_pitch.dart';
import 'technical_material.dart';

/// How pitches are written down, for material and for playing.
///
/// Two entry points that must not be confused. [spellExpectedPitch] is
/// structural: the sixth degree is written on the sixth letter because that is
/// what a scale degree *is*, whatever it sounds like. [spellObservedPitch] is
/// interpretive: a note nobody asked for has no degree, so it is spelled in
/// the key the learner was already told they are playing in.
///
/// [spellObservedPitch] cannot see the realization, and its signature is what
/// guarantees that: knowing which expected note an observation lines up with
/// is a judgment about the performance, and spelling must not smuggle one in.

/// How the tonic of [material] is written.
SpelledPitch tonicSpellingOf(TechnicalMaterial material) {
  final tonic = material.tonic;
  return SpelledPitch(
    letter: NoteLetter.fromLabel(tonic[0]),
    // Only the letter and the accidental are read; the octave comes from
    // whichever note is being spelled.
    octave: 4,
    alteration: tonic.length == 1 ? 0 : (tonic[1] == '#' ? 1 : -1),
  );
}

/// The pitch class of a canonical tonic such as `C`, `F#`, or `Bb`.
///
/// Throws [ArgumentError] for anything [TechnicalMaterial] would reject.
int pitchClassOf(String tonic) {
  if (!TechnicalMaterial.isCanonicalTonic(tonic)) {
    throw ArgumentError.value(tonic, 'tonic', 'not a canonical tonic');
  }
  return SpelledPitch(
    letter: NoteLetter.fromLabel(tonic[0]),
    octave: 4,
    alteration: tonic.length == 1 ? 0 : (tonic[1] == '#' ? 1 : -1),
  ).pitchClass;
}

/// How [midiNote] is written when it is [degree] steps above the tonic of
/// [material].
///
/// Throws [StateError] when the degree cannot be written on its letter within
/// double accidentals.
SpelledPitch spellExpectedPitch({
  required TechnicalMaterial material,
  required int degree,
  required int midiNote,
}) {
  final topology = material.topology;
  final cycle = (degree / topology.degreesPerOctave).floor();
  final index = degree - cycle * topology.degreesPerOctave;
  final letter = tonicSpellingOf(material).letter.stepsAbove(
    topology.originLetterOffset +
        cycle * NoteLetter.values.length +
        topology.letterOffsets[index],
  );
  final pitch = SpelledPitch.forMidiNote(midiNote, letter: letter);
  if (pitch == null) {
    throw StateError(
      '${material.materialId} cannot be spelled on ${letter.label} within '
      'double accidentals',
    );
  }
  return pitch;
}

/// How [midiNote] is written when someone played it during [material].
///
/// A note belonging to the scale is written the way that scale writes it. Any
/// other note is written with the accidental the key leans on, so an F sharp
/// minor attempt spells a stray black key as a sharp and an E flat one spells
/// it as a flat. Nothing here says whether the note was correct, or where in
/// the exercise it fell.
SpelledPitch spellObservedPitch(
  int midiNote, {
  required TechnicalMaterial material,
}) {
  final tonic = tonicSpellingOf(material);
  final topology = material.topology;

  var alterations = 0;
  for (final (degree, interval) in topology.semitoneOffsets.indexed) {
    final letter = tonic.letter.stepsAbove(
      topology.originLetterOffset + topology.letterOffsets[degree],
    );
    final memberPitchClass =
        (tonic.pitchClass + topology.originSemitoneOffset + interval) % 12;
    if (memberPitchClass == midiNote % 12) {
      final member = SpelledPitch.forMidiNote(midiNote, letter: letter);
      if (member != null) return member;
    }
    final natural = letter.naturalPitchClass;
    alterations += _signedDistance(memberPitchClass - natural);
  }

  // Outside the scale: follow the key's own leaning rather than defaulting to
  // sharps, so a stray accidental looks like the ones around it.
  final pitchClass = midiNote % 12;
  final natural = _letterFor(pitchClass);
  final letter =
      natural ??
      (alterations >= 0
          ? _letterFor((pitchClass + 11) % 12)
          : _letterFor((pitchClass + 1) % 12));

  final pitch = letter == null
      ? null
      : SpelledPitch.forMidiNote(midiNote, letter: letter);
  if (pitch == null) {
    throw StateError('$midiNote cannot be spelled in ${material.materialId}');
  }
  return pitch;
}

/// The letter that names [pitchClass] with no accidental, if one does.
NoteLetter? _letterFor(int pitchClass) {
  for (final letter in NoteLetter.values) {
    if (letter.naturalPitchClass == pitchClass % 12) return letter;
  }
  return null;
}

/// Semitones from a letter to a pitch class, as the smaller of the two ways
/// round.
int _signedDistance(int semitones) {
  var distance = semitones % 12;
  if (distance > 6) distance -= 12;
  return distance;
}
