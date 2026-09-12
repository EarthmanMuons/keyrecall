import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/fixtures.dart';

/// Serializing history must not change what the model learns from it.
///
/// The codec sorts an exercise's opportunities, so the set it decodes iterates
/// in a different order than the one that was presented. The learner sums its
/// per-competency terms in the order its loadings arrive, floating-point
/// addition is not associative, and a state hash is exact, so the two have to
/// be kept apart deliberately: the ordering check below is the one that bites,
/// and the trajectories around it are the property it exists to protect.
void main() {
  /// Every shape the recorded exercise varies in.
  final exercises = <Exercise>[
    for (final material in [
      TechnicalMaterial('C', ScaleForm.major),
      TechnicalMaterial('F#', ScaleForm.harmonicMinor),
      ArpeggioMaterial('B', ArpeggioQuality.minor),
    ])
      for (final hands in HandConfiguration.values)
        for (final direction in ExerciseDirection.values)
          for (final octaves in [1, 2, 3])
            Exercise.linear(
              material: material,
              hands: hands,
              octaves: octaves,
              direction: direction,
              tempoBpm: 76,
              guidance: GuidanceContext.unguided,
            ),
  ];

  /// Outcomes spanning what the update path branches on.
  final outcomes = <Outcome>[
    outcomeOf(quality: 0.95),
    outcomeOf(quality: 0.42, completed: false),
    outcomeOf(retrieval: FactualRetrieval.failed, quality: 0.3),
    outcomeOf(
      retrieval: FactualRetrieval.failed,
      started: false,
      completed: false,
      quality: 0.0,
    ),
  ];

  String hashOfTrajectory(List<Exercise> trajectory) {
    final state = model.placementState(PlacementTier.someExperience, at: t0);
    for (var index = 0; index < trajectory.length; index++) {
      final exercise = trajectory[index];
      final outcome = outcomes[index % outcomes.length];
      final at = t0.plusDays(0.5 * (index + 1));
      model.propagate(state, at);
      model.applyOutcome(
        state: state,
        exercise: exercise,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        prediction: model.predict(state, exercise, at: at),
        at: at,
      );
    }
    return learnerStateHash(state);
  }

  test('the recorded exercise iterates in a different order', () {
    // What the checks below are for. Sorting the opportunities is the codec's
    // own canonical form, so the decoded set really does come back in another
    // order, and a reader who assumed otherwise would be reading a tautology.
    expect(
      exercises.where((exercise) {
        final reread = decodeExercise(encodeExercise(exercise));
        return reread.structuralQ.join() != exercise.structuralQ.join();
      }),
      isNotEmpty,
    );
  });

  test('the codec cannot change the order the model sums in', () {
    const channels = [motorLoadings, topologyLoadings, coordinationLoadings];
    for (final exercise in exercises) {
      final reread = decodeExercise(encodeExercise(exercise));
      for (final loadings in channels) {
        expect(
          loadings(reread.structuralQ).keys,
          orderedEquals(loadings(exercise.structuralQ).keys),
          reason: '$exercise sums in a different order once written down',
        );
      }
    }
  });

  test('an exercise learns identically before and after serialization', () {
    final reread = [
      for (final exercise in exercises)
        decodeExercise(encodeExercise(exercise)),
    ];

    expect(hashOfTrajectory(reread), hashOfTrajectory(exercises));
  });

  test('each exercise on its own survives the round trip exactly', () {
    for (final exercise in exercises) {
      final reread = decodeExercise(encodeExercise(exercise));
      expect(
        hashOfTrajectory([reread]),
        hashOfTrajectory([exercise]),
        reason: '$exercise learns differently once written down',
      );
    }
  });

  test('a recorded journal replays faithfully once written and read', () {
    final recorded = recordSession(attempts: 8);
    final reread = AttemptJournal.fromJsonLines(recorded.journal.toJsonLines());

    final replayed = replayJournal(
      reread,
      model: model,
      initial: recorded.initial,
    );

    expect(replayed.divergences, isEmpty, reason: replayed.divergences.join());
  });
}
