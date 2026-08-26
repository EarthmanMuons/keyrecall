import 'package:crisp_notation/crisp_notation.dart' as crisp;
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall/features/practice/fingering.dart';
import 'package:keyrecall/features/practice/staff_score.dart';

void main() {
  Exercise exerciseOf({
    String tonic = 'C',
    ScaleForm form = ScaleForm.major,
    HandConfiguration hands = HandConfiguration.right,
    int octaves = 1,
    ScaleDirection direction = ScaleDirection.up,
  }) => Exercise.linear(
    material: TechnicalMaterial(tonic, form),
    hands: hands,
    octaves: octaves,
    direction: direction,
  );

  List<crisp.NoteElement> notesOf(crisp.Score score) => [
    for (final measure in score.measures)
      for (final element in measure.elements)
        if (element is crisp.NoteElement) element,
  ];

  test('writes one quarter note per moment, in order', () {
    final score = staffScoreFor(realize(exerciseOf()), Hand.right);
    final notes = notesOf(score);

    expect(notes.length, 8);
    expect(
      notes.every((note) => note.duration == crisp.NoteDuration.quarter),
      isTrue,
    );
    expect(notes.first.pitches.single, const crisp.Pitch(crisp.Step.c));
    expect(
      notes.last.pitches.single,
      const crisp.Pitch(crisp.Step.c, octave: 5),
    );
  });

  test('carries the realization spelling onto the staff', () {
    final score = staffScoreFor(
      realize(exerciseOf(tonic: 'G#', form: ScaleForm.harmonicMinor)),
      Hand.right,
    );
    final seventh = notesOf(score)[6].pitches.single;

    expect(
      seventh,
      const crisp.Pitch(crisp.Step.f, alter: 2, octave: 5),
      reason: 'the seventh degree is written F double-sharp, not G',
    );
    expect(seventh.midiNumber, 79);
  });

  test('writes an accidental wherever one is needed', () {
    final score = staffScoreFor(
      realize(exerciseOf(tonic: 'D', form: ScaleForm.harmonicMinor)),
      Hand.right,
    );
    final notes = notesOf(score);

    // D E F G A Bb C#: the two altered degrees say so, since there is no key
    // signature to imply them.
    expect(notes[5].showAccidental, isTrue);
    expect(notes[6].showAccidental, isTrue);
    expect(notes[0].showAccidental, isNull);
  });

  test('fills bars of four and lets the last one run short', () {
    final score = staffScoreFor(realize(exerciseOf()), Hand.right);

    expect(
      [for (final measure in score.measures) measure.elements.length],
      [4, 4],
    );

    final fifteen = staffScoreFor(
      realize(exerciseOf(direction: ScaleDirection.upDown)),
      Hand.right,
    );
    expect(
      [for (final measure in fifteen.measures) measure.elements.length],
      [4, 4, 4, 3],
    );
  });

  test('gives each hand its own clef and each note a stable id', () {
    final realization = realize(exerciseOf(hands: HandConfiguration.together));
    final grand = grandStaffFor(realization);

    expect(grand.upper.clef, crisp.Clef.treble);
    expect(grand.lower.clef, crisp.Clef.bass);
    expect(notesOf(grand.upper).first.id, staffElementId(Hand.right, 0));
    expect(notesOf(grand.lower).first.id, staffElementId(Hand.left, 0));
    expect(
      notesOf(grand.lower).first.pitches.single.midiNumber,
      realization.moments.first.noteFor(Hand.left)!.midiNote,
    );
  });

  group('what fingering the staff writes', () {
    test('teaches the first octave and then only the crossings', () {
      final exercise = exerciseOf(octaves: 2);
      final full = fingeringFor(exercise, Hand.right)!;
      final shown = displayFingeringFor(exercise, Hand.right)!;
      final degrees = scaleFormIntervals[ScaleForm.major]!.length;

      expect(shown.length, full.length);
      expect(
        shown.sublist(0, degrees + 1),
        full.sublist(0, degrees + 1),
        reason: 'the first octave is where the pattern is learned',
      );
      expect(
        shown.skip(degrees + 1).where((finger) => finger != null).length,
        lessThan(full.length - degrees - 1),
        reason: 'the rest is a repeat, so most of it goes unwritten',
      );
      expect(shown.last, full.last);
    });

    test('writes the finger a crossing starts from, not just the thumb', () {
      final exercise = exerciseOf(octaves: 2, direction: ScaleDirection.upDown);
      final full = fingeringFor(exercise, Hand.right)!;
      final shown = displayFingeringFor(exercise, Hand.right)!;

      for (var i = 1; i < full.length; i++) {
        if ((full[i] - full[i - 1]).abs() == 1) continue;
        expect(
          shown[i - 1],
          full[i - 1],
          reason: 'a lone digit names a finger; a pair names the motion',
        );
      }
    });

    test('never leaves a thumb crossing unwritten', () {
      final exercise = exerciseOf(octaves: 2, direction: ScaleDirection.upDown);
      final full = fingeringFor(exercise, Hand.right)!;
      final shown = displayFingeringFor(exercise, Hand.right)!;

      for (var i = 1; i < full.length; i++) {
        if ((full[i] - full[i - 1]).abs() == 1) continue;
        expect(
          shown[i],
          full[i],
          reason: 'position $i is where the hand changes shape',
        );
      }
    });

    test('a left-off digit is no digit, not a zero', () {
      final exercise = exerciseOf(octaves: 2);
      final score = staffScoreFor(
        realize(exercise),
        Hand.right,
        fingering: displayFingeringFor(exercise, Hand.right),
      );

      for (final note in notesOf(score)) {
        expect(note.fingerings.length, lessThanOrEqualTo(1));
      }
    });
  });
}
