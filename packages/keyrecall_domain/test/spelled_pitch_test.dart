import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  group('what a spelling sounds like', () {
    test('middle C is C4', () {
      expect(SpelledPitch(letter: NoteLetter.c, octave: 4).midiNote, 60);
    });

    test('enharmonics sound alike and are not equal', () {
      final bFlat = SpelledPitch(
        letter: NoteLetter.b,
        octave: 4,
        alteration: -1,
      );
      final aSharp = SpelledPitch(
        letter: NoteLetter.a,
        octave: 4,
        alteration: 1,
      );

      expect(bFlat.midiNote, aSharp.midiNote);
      expect(bFlat, isNot(aSharp));
    });

    test('the octave follows the letter, not the sound', () {
      final cFlat = SpelledPitch(
        letter: NoteLetter.c,
        octave: 4,
        alteration: -1,
      );

      expect(
        cFlat.midiNote,
        59,
        reason: 'C♭4 is written in the fourth octave and sounds below C4',
      );
    });

    test('nothing beyond a double accidental exists', () {
      expect(
        () => SpelledPitch(letter: NoteLetter.c, octave: 4, alteration: 3),
        throwsArgumentError,
      );
    });
  });

  group('spelling a pitch on a chosen letter', () {
    test('writes the alteration the letter needs', () {
      expect(SpelledPitch.forMidiNote(70, letter: NoteLetter.b)!.label, 'Bb');
      expect(SpelledPitch.forMidiNote(70, letter: NoteLetter.a)!.label, 'A#');
    });

    test('crosses an octave boundary by a semitone, not by eleven', () {
      final bSharp = SpelledPitch.forMidiNote(60, letter: NoteLetter.b)!;

      expect(bSharp.label, 'B#');
      expect(bSharp.octave, 3);
      expect(bSharp.midiNote, 60);
    });

    test('refuses a letter too far from the pitch to write', () {
      expect(SpelledPitch.forMidiNote(60, letter: NoteLetter.f), isNull);
    });
  });

  test('letters step and wrap', () {
    expect(NoteLetter.c.stepsAbove(4), NoteLetter.g);
    expect(NoteLetter.g.stepsAbove(4), NoteLetter.d);
    expect(NoteLetter.fromLabel('F'), NoteLetter.f);
    expect(() => NoteLetter.fromLabel('H'), throwsArgumentError);
  });
}
