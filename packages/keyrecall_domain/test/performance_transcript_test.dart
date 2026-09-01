import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  final material = TechnicalMaterial('F#', ScaleForm.harmonicMinor);

  PerformanceTranscript playing(List<int> midiNotes) {
    var transcript = PerformanceTranscript.empty;
    for (final (index, midiNote) in midiNotes.indexed) {
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: material),
        timestampMs: 1000 + index * 250,
      );
    }
    return transcript;
  }

  group('what a transcript keeps', () {
    test('every note, in the order it arrived', () {
      final transcript = playing([66, 68, 69]);

      expect(transcript.length, 3);
      expect(
        [for (final note in transcript.notes) note.midiNote],
        [66, 68, 69],
      );
      expect([for (final note in transcript.notes) note.sequence], [0, 1, 2]);
    });

    test('a repeated note twice, because it was played twice', () {
      expect(playing([66, 66]).length, 2);
    });

    test('a note nobody asked for', () {
      // C natural is not in F# harmonic minor. It is still what happened.
      final transcript = playing([60]);

      expect(transcript.notes.single.midiNote, 60);
    });

    test('arrival times, uninterpreted', () {
      final transcript = playing([66, 68]);

      expect(transcript.notes.first.timestampMs, 1000);
      expect(transcript.notes.last.timestampMs, 1250);
    });
  });

  test('appending leaves the original alone', () {
    final first = playing([66]);
    final second = first.appending(
      pitch: spellObservedPitch(68, material: material),
      timestampMs: 2000,
    );

    expect(first.length, 1);
    expect(second.length, 2);
  });

  group('construction invariants', () {
    final pitch = spellObservedPitch(66, material: material);

    test('sequence is contiguous from zero', () {
      expect(
        () => PerformanceTranscript([
          PlayedNote(sequence: 1, pitch: pitch, timestampMs: 1000),
        ]),
        throwsArgumentError,
      );
    });

    test('timestamps preserve arrival order', () {
      expect(
        () => PerformanceTranscript([
          PlayedNote(sequence: 0, pitch: pitch, timestampMs: 1001),
          PlayedNote(sequence: 1, pitch: pitch, timestampMs: 1000),
        ]),
        throwsArgumentError,
      );
    });

    test('individual positions and timestamps are nonnegative', () {
      expect(
        () => PlayedNote(sequence: -1, pitch: pitch, timestampMs: 0),
        throwsArgumentError,
      );
      expect(
        () => PlayedNote(sequence: 0, pitch: pitch, timestampMs: -1),
        throwsArgumentError,
      );
    });
  });

  group('spelling an observation', () {
    test('writes a scale member the way the scale writes it', () {
      // The seventh degree of F# harmonic minor is E#, not F.
      expect(spellObservedPitch(77, material: material).label, 'E#');
    });

    test('follows the key when the note is outside the scale', () {
      final sharpKey = spellObservedPitch(
        61,
        material: TechnicalMaterial('F#', ScaleForm.harmonicMinor),
      );
      final flatKey = spellObservedPitch(
        61,
        material: TechnicalMaterial('F', ScaleForm.major),
      );

      expect(sharpKey.label, 'C#');
      expect(
        flatKey.label,
        'Db',
        reason: 'a stray accidental should look like the ones around it',
      );
    });

    test('cannot see where in the exercise the note fell', () {
      // Same note, same material, same answer, wherever it arrived: the
      // signature has no room for an expected position.
      expect(
        spellObservedPitch(66, material: material),
        spellObservedPitch(66, material: material),
      );
    });
  });
}
