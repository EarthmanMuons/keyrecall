import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart' show alice, learner, params, t0;

/// What an attempt on a transport nothing has characterized is worth.
///
/// The whole chain, from a note carrying no performance time to what the
/// learner model does with it. The claim is narrow and load-bearing: timing
/// evidence is absent, everything else is untouched, and absence is never a
/// poor score.
void main() {
  final exercise = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.together,
    octaves: 1,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
  );
  final realization = realize(exercise);

  /// The exercise played correctly, on the beat, with the hands 30 ms apart.
  ///
  /// [timed] says whether the instrument's clock could place the notes. The
  /// arrival clock is identical either way, which is the point: nothing may
  /// read it.
  PerformanceTranscript played({required bool timed}) {
    var transcript = PerformanceTranscript.empty;
    for (final (position, moment) in realization.moments.indexed) {
      final atMs = 1000 + position * 1000;
      for (final (index, note) in moment.notes.indexed) {
        final onMs = atMs + index * 30;
        transcript = transcript.appending(
          pitch: note.pitch,
          timestampMs: onMs,
          performanceTimeUs: timed ? onMs * 1000 : null,
        );
      }
    }
    return transcript;
  }

  Outcome outcomeOf({required bool timed}) => outcomeFor(
    measurement: measure(
      realization: realization,
      transcript: played(timed: timed),
    ),
    exercise: exercise,
  );

  final at = t0.plusDays(1);

  LearnerState taught({required bool timed}) {
    final state = learner.placementState(
      PlacementTier.someExperience,
      at: alice.createdAt,
    );
    final outcome = outcomeOf(timed: timed);
    learner.propagateAndApplyOutcome(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: evidenceWeightsFor(exercise, outcome),
      prediction: learner.predict(
        state.copy()..propagateTo(at, params),
        exercise,
        at: at,
      ),
      at: at,
    );
    return state;
  }

  test('the same playing is measured the same way but for timing', () {
    final timed = outcomeOf(timed: true);
    final untimed = outcomeOf(timed: false);

    expect(untimed.started, timed.started);
    expect(untimed.completed, timed.completed);
    expect(untimed.retrieval, timed.retrieval);
    expect(untimed.materialRetrieval, timed.materialRetrieval);
    expect(untimed.pitchIntegrity, timed.pitchIntegrity);
    expect(untimed.topologyAccuracy, timed.topologyAccuracy);
  });

  test('and carries no timing evidence at all', () {
    final timed = outcomeOf(timed: true);
    final untimed = outcomeOf(timed: false);

    expect(timed.continuity, isNotNull);
    expect(timed.temporalStability, isNotNull);
    expect(timed.coordination, isNotNull);
    expect(timed.measuredTempoRatio, isNotNull);
    expect(timed.motorScore, isNotNull);

    expect(untimed.continuity, isNull);
    expect(untimed.temporalStability, isNull);
    expect(untimed.coordination, isNull);
    expect(untimed.measuredTempoRatio, isNull);
    expect(untimed.motorScore, isNull);
  });

  // Absence is not a bad score. Practice quality reads the channels the
  // attempt established, so playing nobody could time is read on its pitches.
  test('absence does not read as poor playing', () {
    expect(outcomeOf(timed: false).practiceQuality, greaterThan(0.9));
    expect(
      outcomeOf(timed: false).practiceQuality,
      outcomeOf(timed: true).practiceQuality,
    );
  });

  group('what the learner does with it', () {
    test('the motor channel learns nothing rather than something bad', () {
      final outcome = outcomeOf(timed: false);
      final weights = evidenceWeightsFor(exercise, outcome);

      expect(weights.materialExecution, 0.0);
      for (final competency in Competency.values) {
        if (competency.isTopology) continue;
        expect(
          weights.competencies[competency] ?? 0.0,
          0.0,
          reason: '$competency learns from timing nobody measured',
        );
      }
    });

    test('what the pitches taught is identical either way', () {
      final timed = taught(timed: true);
      final untimed = taught(timed: false);

      for (final competency in Competency.values) {
        if (!competency.isTopology) continue;
        expect(
          untimed.competency(competency).mean,
          timed.competency(competency).mean,
          reason: '$competency reads the pitches, not the clock',
        );
      }
      expect(
        untimed.materialMemory.keys,
        timed.materialMemory.keys,
        reason: 'the same material was practised',
      );
    });

    // The motor competencies keep their priors rather than moving toward a
    // bad score, which is what an unobserved channel has to look like.
    test('the motor competencies are left where they were', () {
      final untimed = taught(timed: false);
      final untouched = learner.placementState(
        PlacementTier.someExperience,
        at: alice.createdAt,
      );

      for (final competency in Competency.values) {
        if (competency.isTopology) continue;
        expect(
          untimed.competency(competency).mean,
          untouched.competency(competency).mean,
          reason: '$competency was never observed',
        );
      }
      expect(untimed.materialExecution, isEmpty);
    });
  });
}
