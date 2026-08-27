import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

import 'support/recorded_takes.dart';

/// Real two-hand playing, from what the exercise asked for to what the learner
/// model is told.
///
/// The stages are pinned where they live. What this covers is that they
/// compose on recorded performances rather than on transcripts written to
/// compose.
void main() {
  final at = DateTime.utc(2026);
  const model = LearnerModel();

  Exercise exerciseFor(String take) {
    final (tonic, form) = recordedTakes[take]!;
    return Exercise.linear(
      material: TechnicalMaterial(tonic, form),
      hands: HandConfiguration.together,
      octaves: 1,
    );
  }

  PerformanceMeasurement measuredTake(
    String take, {
    PerformanceTranscript? transcript,
  }) => measure(
    realization: realizationOf(take),
    transcript: transcript ?? transcriptOf(take),
  );

  /// How far applying [outcome] moves the coordination competency, and how far
  /// it was from what was predicted.
  ({double movement, double surprise}) coordinationEvidenceOf(
    Exercise exercise,
    Outcome outcome,
  ) {
    final state = model.newState(at: at);
    final before = state.competency(Competency.handsTogetherCoordination).mean;
    final surprise =
        (outcome.coordination ?? 0) -
        model.coordinationProbability(state, exercise);

    model.applyOutcome(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: evidenceWeightsFor(exercise, outcome),
      prediction: model.predict(state, exercise, at: at),
      at: at,
    );

    return (
      movement:
          state.competency(Competency.handsTogetherCoordination).mean - before,
      surprise: surprise,
    );
  }

  group('every recorded take reaches the learner model', () {
    for (final take in recordedTakes.keys) {
      test(take, () {
        final exercise = exerciseFor(take);
        final measurement = measuredTake(take);
        final outcome = outcomeFor(
          measurement: measurement,
          exercise: exercise,
        );

        expect(realizationOf(take).hands, {Hand.left, Hand.right});
        expect(
          exercise.structuralQ,
          contains(Competency.handsTogetherCoordination),
        );

        expect(measurement.expectedNotes, 30);
        expect(measurement.expectedMoments, 15);
        expect(measurement.correspondedTwoHandMoments, greaterThan(0));

        expect(outcome.coordination, isNotNull);
        expect(outcome.coordination, inInclusiveRange(0, 1));
        expect(outcome.coordination, measurement.coordination);

        final weights = evidenceWeightsFor(exercise, outcome);
        expect(weights[Competency.handsTogetherCoordination], greaterThan(0));

        final evidence = coordinationEvidenceOf(exercise, outcome);
        expect(
          evidence.movement.sign,
          evidence.surprise.sign,
          reason:
              'the competency moves the way the score surprised the '
              'prediction',
        );
      });
    }

    test('the hands that execute learn from how it was played', () {
      final exercise = exerciseFor('comfortable-c-major');
      final outcome = outcomeFor(
        measurement: measuredTake('comfortable-c-major'),
        exercise: exercise,
      );
      final state = model.newState(at: at);
      final before = state.competency(Competency.rhScaleExecution).mean;

      model.applyOutcome(
        state: state,
        exercise: exercise,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        prediction: model.predict(state, exercise, at: at),
        at: at,
      );

      for (final hand in [
        Competency.rhScaleExecution,
        Competency.lhScaleExecution,
      ]) {
        expect(
          state.competency(hand).mean,
          greaterThan(before),
          reason: '$hand still reads the motor channel',
        );
      }
    });
  });

  group('what the corpus says about coordination', () {
    double coordinationOf(String take) => measuredTake(take).coordination!;

    test('comfortable playing is at least as together as any of it', () {
      final comfortable = coordinationOf('comfortable-c-major');

      for (final take in recordedTakes.keys) {
        expect(
          coordinationOf(take),
          lessThanOrEqualTo(comfortable),
          reason: take,
        );
      }
    });

    test('hands a whole step apart are the least together', () {
      final apart = coordinationOf('hands-out-of-phase-c-major');

      for (final take in recordedTakes.keys.where(
        (take) => take != 'hands-out-of-phase-c-major',
      )) {
        expect(coordinationOf(take), greaterThan(apart), reason: take);
      }
    });

    test('spread between moments is not spread between hands', () {
      final rolled = measuredTake('deliberate-rolled-c-major');

      expect(
        rolled.temporalStability,
        0.0,
        reason: 'deliberately spread in time',
      );
      expect(
        rolled.coordination,
        1.0,
        reason:
            'and its hands still arrived together, which is a different '
            'question and a different channel',
      );
    });
  });

  group('when a hand stops arriving', () {
    /// The comfortable take with the upper note dropped from the first
    /// [moments] pairs, which arrive two at a time.
    PerformanceTranscript withoutRightHand(int moments) {
      final played = transcriptOf('comfortable-c-major').notes;
      var transcript = PerformanceTranscript.empty;
      for (var pair = 0; pair * 2 + 1 < played.length; pair++) {
        final arrivals = [played[pair * 2], played[pair * 2 + 1]];
        final upper = arrivals.reduce(
          (a, b) => a.midiNote >= b.midiNote ? a : b,
        );
        for (final note in arrivals) {
          if (pair < moments && note == upper) continue;
          transcript = transcript.appending(
            pitch: note.pitch,
            timestampMs: note.timestampMs,
          );
        }
      }
      return transcript;
    }

    test('coordination is read from fewer moments', () {
      final measurement = measuredTake(
        'comfortable-c-major',
        transcript: withoutRightHand(5),
      );

      expect(measurement.correspondedTwoHandMoments, 10);
      expect(measurement.coordination, isNotNull);
      expect(measurement.expectedNotes, 30);
      expect(measurement.expectedMoments, 15);
      expect(measurement.materialProduced, 25);
    });

    test('and disappears rather than falling to zero', () {
      final exercise = exerciseFor('comfortable-c-major');
      final measurement = measuredTake(
        'comfortable-c-major',
        transcript: withoutRightHand(15),
      );
      final outcome = outcomeFor(measurement: measurement, exercise: exercise);

      expect(measurement.correspondedTwoHandMoments, 0);
      expect(measurement.coordination, isNull);
      expect(measurement.materialProduced, 15);
      expect(measurement.expectedNotes, 30);

      expect(outcome.coordination, isNull);
      expect(
        evidenceWeightsFor(
          exercise,
          outcome,
        ).competencies.containsKey(Competency.handsTogetherCoordination),
        isFalse,
      );
      expect(coordinationEvidenceOf(exercise, outcome).movement, 0);
    });
  });
}
