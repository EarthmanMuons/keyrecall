import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

/// What conditions a learner has actually demonstrated on a material.
///
/// A learner fact rather than scheduler bookkeeping, which is why it sits on
/// the execution residual: it makes the same kind of claim, about the same
/// material and the same hand. It is also durable, so what moves it and what
/// does not is worth pinning rather than leaving to whichever caller reads it.
void main() {
  const model = LearnerModel();
  const params = v1PrototypeLearnerParams;
  final t0 = DateTime.utc(2026);

  Exercise scale({
    HandConfiguration hands = HandConfiguration.right,
    int octaves = 1,
    double tempoBpm = 60,
  }) => Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: hands,
    octaves: octaves,
    tempoBpm: tempoBpm,
    guidance: GuidanceContext.continuouslyCued,
  );

  Outcome played({required double quality, bool completed = true}) => Outcome(
    started: true,
    retrieval: FactualRetrieval.notTested,
    completed: completed,
    materialRetrieval: 1.0,
    pitchIntegrity: quality,
    continuity: quality,
    temporalStability: quality,
    achievedTempoRatio: 1.0,
    topologyAccuracy: quality,
  );

  /// Plays [exercise] and returns the frontier it left behind.
  MaterialExecutionState after(
    LearnerState state,
    Exercise exercise,
    Outcome outcome, {
    int minutes = 5,
  }) {
    final at = t0.add(Duration(minutes: minutes));
    model.propagate(state, at);
    model.applyOutcome(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: evidenceWeightsFor(exercise, outcome),
      prediction: model.predict(state, exercise, at: at),
      at: at,
    );
    return state.materialExecutionFor(
      ('C_MAJOR', exercise.conditions.hands),
      at,
      params,
    );
  }

  LearnerState fresh() =>
      model.placementState(PlacementTier.someExperience, at: t0);

  test('a managed attempt moves the frontier to what it asked for', () {
    final frontier = after(
      fresh(),
      scale(octaves: 2, tempoBpm: 84),
      played(quality: 1.0),
    );

    expect(frontier.demonstratedOctaves, 2);
    expect(frontier.demonstratedTempoAt(2), 84);
    expect(
      frontier.demonstratedTempoAt(1),
      0,
      reason:
          'one octave was never played, and two maxima would have said '
          'it was',
    );
  });

  test('a faster attempt that fell apart moves nothing', () {
    final state = fresh();
    after(state, scale(tempoBpm: 60), played(quality: 1.0));
    final frontier = after(
      state,
      scale(tempoBpm: 120),
      played(quality: 0.1),
      minutes: 10,
    );

    expect(
      frontier.demonstratedTempoAt(1),
      60,
      reason: 'a tempo somebody could not manage is not where they go on from',
    );
  });

  test('a wider attempt that never finished moves nothing', () {
    final state = fresh();
    after(state, scale(), played(quality: 1.0));
    final frontier = after(
      state,
      scale(octaves: 2),
      played(quality: 1.0, completed: false),
      minutes: 10,
    );

    expect(frontier.demonstratedOctaves, 1);
  });

  test('it is a maximum, so slower work does not walk it back', () {
    final state = fresh();
    after(state, scale(tempoBpm: 96), played(quality: 1.0));
    final frontier = after(
      state,
      scale(tempoBpm: 60),
      played(quality: 1.0),
      minutes: 10,
    );

    expect(frontier.demonstratedTempoAt(1), 96);
  });

  test('two maxima are not a place anybody has been', () {
    // The reason this is a tempo per span rather than a widest span and a
    // fastest tempo. Both of these were managed and two octaves at 96 was
    // not, so nothing may read it as a baseline to step on from.
    final state = fresh();
    after(state, scale(octaves: 1, tempoBpm: 96), played(quality: 1.0));
    final frontier = after(
      state,
      scale(octaves: 2, tempoBpm: 60),
      played(quality: 1.0),
      minutes: 10,
    );

    expect(frontier.demonstratedOctaves, 2);
    expect(frontier.demonstratedTempoAt(1), 96);
    expect(
      frontier.demonstratedTempoAt(2),
      60,
      reason:
          'not 96, which is the widest span and the fastest tempo read '
          'as a pair they were never played as',
    );
  });

  test('a span nobody has reached has no tempo at all', () {
    final frontier = after(fresh(), scale(), played(quality: 1.0));

    expect(frontier.demonstratedTempoAt(2), 0);
  });

  test('one hand says nothing about the other', () {
    final state = fresh();
    after(state, scale(octaves: 2, tempoBpm: 96), played(quality: 1.0));

    expect(
      state
          .materialExecutionFor(('C_MAJOR', HandConfiguration.left), t0, params)
          .demonstratedOctaves,
      0,
      reason:
          'a right hand that has played two octaves is not a left hand '
          'that has',
    );
    expect(
      state
          .materialExecutionFor(
            ('C_MAJOR', HandConfiguration.together),
            t0,
            params,
          )
          .demonstratedOctaves,
      0,
      reason: 'and hands together is a third frontier again',
    );
  });

  test('copying a state carries it', () {
    // The replay path copies state constantly, and a field it drops is a
    // divergence that only shows up once a checkpoint is involved.
    final state = fresh();
    after(state, scale(octaves: 2, tempoBpm: 84), played(quality: 1.0));

    final copied = state.copy().materialExecutionFor(
      ('C_MAJOR', HandConfiguration.right),
      t0,
      params,
    );
    expect(copied.demonstratedOctaves, 2);
    expect(copied.demonstratedTempoAt(2), 84);
  });
}
