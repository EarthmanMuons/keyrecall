import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/practice/attempt_diagnosis.dart';

/// What the screen between attempts is allowed to say about the attempt.
///
/// Driven through the real observation model rather than off hand-written
/// outcomes, because half of what is being tested is whether a place named in
/// a sentence is the place the playing actually went wrong.
void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);

  Exercise exerciseFor(HandConfiguration hands) => Exercise.linear(
    material: material,
    hands: hands,
    octaves: 1,
    direction: ScaleDirection.upDown,
    tempoBpm: 60,
  );

  final exercise = exerciseFor(HandConfiguration.right);
  final realization = realize(exercise);
  final expected = [
    for (final moment in realization.moments)
      moment.noteFor(Hand.right)!.midiNote,
  ];

  /// One note per moment, a second apart unless [gaps] says otherwise.
  PerformanceTranscript played(List<int> midiNotes, {List<int>? gaps}) {
    var transcript = PerformanceTranscript.empty;
    var at = 0;
    for (final (index, midiNote) in midiNotes.indexed) {
      at += index == 0 ? 0 : (gaps?[index - 1] ?? 1000);
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: material),
        timestampMs: at,
      );
    }
    return transcript;
  }

  AttemptClosure closureOf(
    Outcome outcome, {
    AttemptTermination termination = AttemptTermination.learnerStopped,
    Exercise? of,
  }) => AttemptClosure.measured(
    termination: termination,
    outcome: outcome,
    weights: evidenceWeightsFor(of ?? exercise, outcome),
    memoryUpdate: const MemoryUpdateDiagnostics(),
  );

  AttemptDiagnosis diagnosisOf(
    PerformanceTranscript transcript, {
    Exercise? of,
    bool withReading = true,
  }) {
    final played = of ?? exercise;
    final reading = readPerformance(exercise: played, transcript: transcript);
    return diagnose(
      exercise: played,
      closure: closureOf(reading.outcome, of: played),
      reading: withReading ? reading : null,
    )!;
  }

  group('a clean pass', () {
    test('says so, and names nothing that did not happen', () {
      final diagnosis = diagnosisOf(played(expected));

      expect(diagnosis.finished, isTrue);
      expect(diagnosis.fault, isNull);
      expect(diagnosis.where, isNull);
      expect(diagnosis.sentence, 'Clean pass, steady the whole way.');
    });
  });

  group('one fault at a time', () {
    test('a wrong note is a note fault, placed where it was played', () {
      final diagnosis = diagnosisOf(played([...expected]..[3] = 66));

      expect(diagnosis.fault, AttemptFault.notes);
      expect(diagnosis.sentence, 'A pitch slipped on the way up.');
    });

    test('several wrong notes are counted, and placed nowhere', () {
      final wrong = [...expected]
        ..[3] = 66
        ..[10] = 66;
      final diagnosis = diagnosisOf(played(wrong));

      expect(diagnosis.sentence, '2 pitches slipped.');
      expect(
        diagnosis.where,
        isNull,
        reason: 'the first of several is not where all of them were',
      );
    });

    test('a note nobody asked for is not a pitch that slipped', () {
      final diagnosis = diagnosisOf(played([...expected]..insert(4, 66)));

      expect(diagnosis.fault, AttemptFault.notes);
      expect(diagnosis.sentence, 'An extra note crept in on the way up.');
    });

    test('a pause is a continuity fault, placed where playing resumed', () {
      final gaps = List.filled(expected.length - 1, 1000)..[7] = 6000;
      final diagnosis = diagnosisOf(played(expected, gaps: gaps));

      expect(diagnosis.fault, AttemptFault.continuity);
      expect(
        diagnosis.sentence,
        'The notes were right; the pause at the turn broke it up.',
      );
    });

    test('playing unevenly is a steadiness fault, and happened nowhere', () {
      final gaps = [
        for (var i = 0; i < expected.length - 1; i++) i.isEven ? 400 : 1600,
      ];
      final diagnosis = diagnosisOf(played(expected, gaps: gaps));

      expect(diagnosis.fault, AttemptFault.steadiness);
      expect(
        diagnosis.where,
        isNull,
        reason: 'spread is a property of the whole traversal',
      );
      expect(
        diagnosis.sentence,
        'The notes were right; the pulse kept moving around.',
      );
    });
  });

  group('hands together', () {
    final together = exerciseFor(HandConfiguration.together);
    final moments = realize(together).moments;

    /// Both hands on the beat, the right hand [spreadMs] behind from [from].
    PerformanceTranscript withSpread({required int from, int spreadMs = 0}) {
      var transcript = PerformanceTranscript.empty;
      for (final (index, moment) in moments.indexed) {
        final at = index * 1000;
        final spread = index >= from ? spreadMs : 0;
        for (final hand in Hand.values) {
          transcript = transcript.appending(
            pitch: moment.noteFor(hand)!.pitch,
            timestampMs: hand == Hand.right ? at + spread : at,
          );
        }
      }
      return transcript;
    }

    test('together the whole way is its own clean sentence', () {
      final diagnosis = diagnosisOf(withSpread(from: 0), of: together);

      expect(diagnosis.fault, isNull);
      expect(diagnosis.sentence, 'Clean pass, hands together the whole way.');
    });

    test('hands that came apart are named, and placed', () {
      final diagnosis = diagnosisOf(
        withSpread(from: 9, spreadMs: 200),
        of: together,
      );

      expect(diagnosis.fault, AttemptFault.coordination);
      expect(
        diagnosis.sentence,
        'Both hands had the notes, but they came apart on the way down.',
      );
    });
  });

  group('an attempt that did not finish', () {
    test('says where it ran out rather than what went wrong inside it', () {
      final diagnosis = diagnosisOf(played(expected.take(5).toList()));

      expect(diagnosis.finished, isFalse);
      expect(diagnosis.sentence, 'It ran out on the way up.');
    });

    test('playing nothing invents no fault and no place', () {
      final diagnosis = diagnosisOf(PerformanceTranscript.empty);

      expect(diagnosis.started, isFalse);
      expect(diagnosis.sentence, 'Nothing came through.');
    });
  });

  test('declining is reported as what it is, not as a failure to play', () {
    final diagnosis = diagnose(
      exercise: exercise,
      closure: closureOf(
        Outcome(
          started: false,
          retrieval: FactualRetrieval.failed,
          completed: false,
          materialRetrieval: 0,
          pitchIntegrity: 0,
          continuity: 0,
          temporalStability: 0,
          achievedTempoRatio: 0,
          topologyAccuracy: 0,
        ),
        termination: AttemptTermination.learnerDeclined,
      ),
    )!;

    expect(diagnosis.sentence, 'Noted. That one would not come.');
  });

  test('an unmeasured attempt gets no diagnosis at all', () {
    expect(
      diagnose(
        exercise: exercise,
        closure: AttemptClosure.unmeasured(
          termination: AttemptTermination.inactivityTimeout,
        ),
      ),
      isNull,
    );
  });

  group('which fault gets said', () {
    test('the notes come before how they sat in time', () {
      final gaps = List.filled(expected.length - 1, 1000)..[7] = 6000;
      final diagnosis = diagnosisOf(
        played([...expected]..[3] = 66, gaps: gaps),
      );

      expect(diagnosis.fault, AttemptFault.notes);
    });

    test('without the correspondence the channel survives and the place does '
        'not', () {
      final diagnosis = diagnosisOf(
        played([...expected]..[3] = 66),
        withReading: false,
      );

      expect(diagnosis.fault, AttemptFault.notes);
      expect(diagnosis.where, isNull);
      expect(diagnosis.sentence, 'A few pitches slipped.');
      expect(diagnosis.slippedNotes, isNull);
    });
  });
}
