import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);

  Exercise exerciseUnder(GuidanceContext guidance) => Exercise.linear(
    material: material,
    hands: HandConfiguration.right,
    octaves: 1,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
    guidance: guidance,
  );

  final exercise = exerciseUnder(GuidanceContext.unguided);
  final realization = realize(exercise);
  final expected = [
    for (final moment in realization.moments)
      moment.noteFor(Hand.right)!.midiNote,
  ];

  /// A performance, with one note per [gapMs] unless [gaps] says otherwise.
  PerformanceTranscript played(
    List<int> midiNotes, {
    int gapMs = 1000,
    List<int>? gaps,
  }) {
    var transcript = PerformanceTranscript.empty;
    var at = 0;
    for (final (index, midiNote) in midiNotes.indexed) {
      at += index == 0 ? 0 : (gaps == null ? gapMs : gaps[index - 1]);
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: material),
        timestampMs: at,
      );
    }
    return transcript;
  }

  PerformanceMeasurement measured(
    List<int> midiNotes, {
    List<int>? gaps,
    MeasurementPolicy policy = MeasurementPolicy.standard,
  }) => measure(
    realization: realization,
    transcript: played(midiNotes, gaps: gaps),
    policy: policy,
  );

  group('a clean performance', () {
    test('is complete, retrieved, and right in every channel', () {
      final measurement = measured(expected);

      expect(measurement.started, isTrue);
      expect(measurement.completed, isTrue);
      expect(measurement.retrievedIndependently, isTrue);
      expect(measurement.materialAppeared, 1.0);
      expect(measurement.pitchIntegrity, 1.0);
      expect(measurement.topologyAccuracy, 1.0);
      expect(measurement.continuity, 1.0);
      expect(measurement.temporalStability, 1.0);
    });

    test('reports the tempo it was played at', () {
      // One note a second against a 60bpm request.
      expect(
        measured(expected).achievedTempoRatioFor(exercise.conditions),
        closeTo(1.0, 0.001),
      );
      expect(
        measured(
          expected,
          gaps: List.filled(7, 500),
        ).achievedTempoRatioFor(exercise.conditions),
        closeTo(2.0, 0.001),
      );
    });
  });

  group('an octave slip', () {
    final measurement = measured([...expected]..[3] = expected[3] - 12);

    test('is the right degree and the wrong sounded pitch', () {
      expect(measurement.topologyAccuracy, 1.0);
      expect(measurement.pitchIntegrity, lessThan(1.0));
      expect(measurement.materialAppeared, 1.0);
    });

    test('does not cost the learner their retrieval', () {
      expect(
        measurement.retrievedIndependently,
        isTrue,
        reason:
            'factual scale memory is about the degrees, and landing an '
            'octave away is a fact about where the hand went',
      );
    });
  });

  group('a wrong note', () {
    final measurement = measured([...expected]..[2] = 66);

    test('costs retrieval, degree, and pitch', () {
      expect(measurement.retrievedIndependently, isFalse);
      expect(measurement.topologyAccuracy, lessThan(1.0));
      expect(measurement.pitchIntegrity, lessThan(1.0));
      expect(measurement.materialAppeared, lessThan(1.0));
      expect(
        measurement.completed,
        isTrue,
        reason: 'a wrong note in place still reached the end of the scale',
      );
    });
  });

  group('replaying the note just played', () {
    test('keeps retrieval, since the right material came out twice', () {
      final measurement = measured([...expected]..insert(2, expected[1]));

      expect(measurement.repeats, 1);
      expect(measurement.intrusions, 0);
      expect(measurement.retrievedIndependently, isTrue);
      expect(measurement.topologyAccuracy, 1.0, reason: 'no degree was wrong');
      expect(measurement.pitchIntegrity, lessThan(1.0));
    });

    test('costs timing when it delays the note that follows', () {
      // The repeat pushes the note after it half a beat late.
      final delayed = [1000, 1000, 1500, 1000, 1000, 1000, 1000, 1000];
      final measurement = measured(
        [...expected]..insert(2, expected[1]),
        gaps: delayed,
      );

      expect(
        measurement.retrievedIndependently,
        isTrue,
        reason: 'the right material still came out',
      );
      expect(
        measurement.continuity,
        lessThan(1.0),
        reason:
            'exempting a repeat from retrieval does not pretend it never '
            'happened',
      );
    });

    test('costs nothing in timing when it fits inside the beat', () {
      // The extra note lands between two expected ones that stay on the pulse.
      final inTime = [1000, 500, 500, 1000, 1000, 1000, 1000, 1000];
      final measurement = measured(
        [...expected]..insert(2, expected[1]),
        gaps: inTime,
      );

      expect(
        measurement.temporalStability,
        1.0,
        reason:
            'timing is read over the notes the exercise asked for, so an '
            'extra note that leaves their pulse alone did not disturb it',
      );
    });

    test('breaks retrieval when the policy says so', () {
      final measurement = measured(
        [...expected]..insert(2, expected[1]),
        policy: const MeasurementPolicy(
          repeatedMatchedPitchBreaksRetrieval: true,
        ),
      );

      expect(measurement.retrievedIndependently, isFalse);
    });

    test('a different extra note is an intrusion, not a repeat', () {
      final measurement = measured([...expected]..insert(2, 61));

      expect(measurement.repeats, 0);
      expect(measurement.intrusions, 1);
      expect(measurement.retrievedIndependently, isFalse);
    });
  });

  group('a correction', () {
    test('is complete and not clean retrieval', () {
      // C D F E F G A B C: the F arrives early, then the E is played.
      final measurement = measured([
        expected[0],
        expected[1],
        expected[3],
        ...expected.sublist(2),
      ]);

      expect(measurement.completed, isTrue);
      expect(measurement.retrievedIndependently, isFalse);
      expect(
        measurement.materialAppeared,
        1.0,
        reason:
            'every note did eventually appear, which is what this channel '
            'is for; whether it appeared first time is retrieval',
      );
    });
  });

  group('stopping partway', () {
    final measurement = measured(expected.take(4).toList());

    test('is incomplete and not retrieved', () {
      expect(measurement.started, isTrue);
      expect(measurement.completed, isFalse);
      expect(measurement.retrievedIndependently, isFalse);
      expect(measurement.materialAppeared, 0.5);
    });
  });

  group('playing nothing', () {
    test('never started', () {
      final measurement = measured(const []);

      expect(measurement.started, isFalse);
      expect(measurement.completed, isFalse);
      expect(measurement.materialAppeared, 0.0);
    });
  });

  group('timing', () {
    test(
      'a single pause breaks continuity without costing steadiness much',
      () {
        final gaps = [1000, 1000, 1000, 5000, 1000, 1000, 1000];
        final measurement = measured(expected, gaps: gaps);

        expect(measurement.continuity, 0.0);
        expect(
          measurement.temporalStability,
          greaterThan(0.0),
          reason: 'one interruption is not the same as playing unevenly',
        );
      },
    );

    test('alternating fast and slow costs steadiness without a break', () {
      final gaps = [400, 1600, 400, 1600, 400, 1600, 400];
      final measurement = measured(expected, gaps: gaps);

      expect(measurement.temporalStability, 0.0);
      expect(
        measurement.continuity,
        greaterThan(0.0),
        reason: 'nothing here stopped, it just never settled',
      );
    });

    test(
      'too few notes to time reports no timing rather than perfect timing',
      () {
        final measurement = measured(expected.take(2).toList());

        expect(measurement.dispersion, isNull);
        expect(measurement.continuity, 0.0);
        expect(measurement.temporalStability, 0.0);
      },
    );
  });

  group('where the timing went wrong', () {
    test('names the moment the longest gap ran up to', () {
      final gaps = [1000, 1000, 1000, 5000, 1000, 1000, 1000];
      final measurement = measured(expected, gaps: gaps);

      expect(
        measurement.longestGapBeforePosition,
        4,
        reason:
            'the gap sits between the fourth and fifth notes, and the '
            'fifth is the one somebody can be pointed at',
      );
    });

    test('says nothing when there was no worst gap to locate', () {
      final measurement = measured(expected.take(2).toList());

      expect(measurement.worstIntervalRatio, isNull);
      expect(measurement.longestGapBeforePosition, isNull);
    });

    test('locates the gap by when playing resumed, not by what was played', () {
      final gaps = [1000, 1000, 1000, 5000, 1000, 1000, 1000];
      final wrongNote = measured([...expected]..[4] = 66, gaps: gaps);

      expect(wrongNote.longestGapBeforePosition, 4);
    });
  });

  group('a wrong note played exactly on the beat', () {
    test('costs pitch and degree, and nothing in timing', () {
      final measurement = measured([...expected]..[2] = 66);

      expect(measurement.topologyAccuracy, lessThan(1.0));
      expect(measurement.pitchIntegrity, lessThan(1.0));
      expect(
        measurement.temporalStability,
        1.0,
        reason: 'wrong note, perfectly in time, is a valid observation',
      );
      expect(measurement.continuity, 1.0);
    });

    test('an octave slip is the same: timing is untouched', () {
      final measurement = measured([...expected]..[3] = expected[3] - 12);

      expect(measurement.pitchIntegrity, lessThan(1.0));
      expect(
        measurement.temporalStability,
        1.0,
        reason:
            'a substituted note is still the event the learner produced '
            'for a note the exercise asked for, so dropping it from the '
            'timing series would let a pitch error manufacture a pause',
      );
      expect(measurement.continuity, 1.0);
    });
  });

  group('the boundary between alignment and measurement', () {
    test('timing cannot change the correspondence', () {
      final steady = measured(expected);
      final ragged = measured(
        expected,
        gaps: [200, 3000, 150, 4000, 180, 2500, 220],
      );

      expect(
        ragged.alignment.noteEdits,
        steady.alignment.noteEdits,
        reason:
            'the same notes in the same order correspond identically however '
            'they sat in time, though each moment records when it happened',
      );
      expect(ragged.temporalStability, lessThan(steady.temporalStability));
    });
  });

  group('the outcome it supports', () {
    test('carries the measurement into the model vocabulary', () {
      final outcome = outcomeFor(
        measurement: measured(expected),
        exercise: exercise,
      );

      expect(outcome.retrieval, FactualRetrieval.succeeded);
      expect(outcome.completed, isTrue);
      expect(outcome.motorScore, 1.0);
      expect(outcome.practiceQuality, 1.0);
    });

    test('a cued attempt never tests retrieval, however well it went', () {
      final cued = exerciseUnder(GuidanceContext.continuouslyCued);
      final outcome = outcomeFor(
        measurement: measure(
          realization: realize(cued),
          transcript: played(expected),
        ),
        exercise: cued,
      );

      expect(outcome.retrieval, FactualRetrieval.notTested);
      expect(
        outcome.practiceQuality,
        1.0,
        reason: 'the practice was still good practice',
      );
    });

    test('a previewed attempt does test it', () {
      final previewed = exerciseUnder(GuidanceContext.notesPreviewedOnly);
      final outcome = outcomeFor(
        measurement: measure(
          realization: realize(previewed),
          transcript: played([...expected]..[2] = 66),
        ),
        exercise: previewed,
      );

      expect(outcome.retrieval, FactualRetrieval.failed);
    });

    test(
      'a terrible attempt still measures, rather than going unavailable',
      () {
        final outcome = outcomeFor(
          measurement: measured(const [61, 63, 66, 68, 70]),
          exercise: exercise,
        );

        expect(outcome.started, isTrue);
        expect(outcome.retrieval, FactualRetrieval.failed);
        expect(outcome.materialRetrieval, 0.0);
        expect(
          outcome.topologyAccuracy,
          lessThan(0.2),
          reason:
              'measurement availability is about whether the observation '
              'model can read the attempt, never about how it went',
        );
      },
    );
  });
}
