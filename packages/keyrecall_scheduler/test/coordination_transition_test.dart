import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// The slot after a learner earns coordination on a scale.
///
/// Hands-together work became fully eligible and admissible in the very slot
/// its prerequisite was first satisfied, and was then chosen a median of seven
/// to nineteen slots later, in many sittings never. Attributing every one of
/// those waiting slots found that none of them went to another realization of
/// the same scale: the material simply lost, over and over, to other material.
void main() {
  final material = materials.first;

  Exercise together({
    int octaves = 1,
    double tempoBpm = 60,
    HandMotion handMotion = HandMotion.parallel,
  }) => exerciseFor(
    material,
    hands: HandConfiguration.together,
    octaves: octaves,
    handMotion: handMotion,
    tempoBpm: tempoBpm,
  );

  /// A learner whose hands both know [material] at one octave.
  LearnerState readyForBoth() {
    final state = stateAt(PlacementTier.someExperience);
    state.materialMemoryFor(material.materialId, learnerParams)
      ..memoryAnchorAt = t0
      ..factualLastRetrievalAt = t0;
    for (final hands in [HandConfiguration.right, HandConfiguration.left]) {
      state.materialExecutionFor(
          (material.materialId, hands, HandMotion.parallel),
          t0,
          learnerParams,
        )
        ..readyForHandsTogether(octaves: 1, tempoBpm: 96)
        ..demonstrate(octaves: 1, tempoBpm: 96)
        ..paced(96)
        ..lastEvidenceAt = t0;
    }
    return state;
  }

  test('a scale both hands know is a pending transition', () {
    expect(isCoordinationTransition(readyForBoth(), together()), isTrue);
  });

  test('and an attempt that produced execution evidence ends it', () {
    // The attempt rather than the success. What the scheduler owes is bringing
    // the work into practice; how it went is evidence like any other.
    final state = readyForBoth();
    state
            .materialExecutionFor(
              (
                material.materialId,
                HandConfiguration.together,
                HandMotion.parallel,
              ),
              t0,
              learnerParams,
            )
            .lastEvidenceAt =
        t0;

    expect(isCoordinationTransition(state, together()), isFalse);
  });

  test('single-hand work on the same scale is not one', () {
    // So selecting the material for the right hand neither benefits from the
    // transition nor consumes it, which is what the waiting-slot attribution
    // said matters.
    expect(
      isCoordinationTransition(
        readyForBoth(),
        exerciseFor(material, hands: HandConfiguration.right),
      ),
      isFalse,
    );
  });

  test('nor is a span neither hand has reached', () {
    expect(
      isCoordinationTransition(readyForBoth(), together(octaves: 2)),
      isFalse,
    );
  });

  group('where it sits in the key', () {
    RankKey key({
      required bool transition,
      double retention = 0,
      EligibilityTier tier = EligibilityTier.fullyEligible,
    }) => RankKey(
      tier: tier,
      coordinationTransition: transition,
      retention: retention,
      information: 0,
      diversity: 0,
      goals: 0,
    );

    test('it outranks retention, which is the only way it can fire', () {
      // Measured: the first term separating a waiting hands-together candidate
      // from the winner was retention in eighty-four per cent of slots. Below
      // it, this would never do anything.
      expect(
        key(transition: true).compareTo(key(transition: false, retention: 0.9)),
        greaterThan(0),
      );
    });

    test('and does not outrank eligibility', () {
      // Worth reaching for early is not worth reaching for something the
      // learner is not ready for.
      expect(
        key(
          transition: true,
          tier: EligibilityTier.provisionallyEligible,
        ).compareTo(key(transition: false)),
        lessThan(0),
      );
    });

    test('it participates in value equality and hashing', () {
      final transition = key(transition: true);
      final ordinary = key(transition: false);

      expect(transition, isNot(ordinary));
      expect(transition.hashCode, isNot(ordinary.hashCode));
    });
  });

  group('one transition, whichever way the hands move', () {
    test('both motions are pending before either is played', () {
      final state = readyForBoth();

      expect(isCoordinationTransition(state, together()), isTrue);
      expect(
        isCoordinationTransition(
          state,
          together(handMotion: HandMotion.contrary),
        ),
        isTrue,
      );
    });

    test('playing one ends it for both', () {
      // Once per material, not once per motion. The event is the learner
      // moving from never having coordinated this scale to having done so;
      // meeting the other motion afterwards is ordinary execution
      // progression, which ExecutionAdvance.span and .tempo already offer.
      final state = readyForBoth();
      state
              .materialExecutionFor(
                (
                  material.materialId,
                  HandConfiguration.together,
                  HandMotion.contrary,
                ),
                t0,
                learnerParams,
              )
              .lastEvidenceAt =
          t0;

      expect(isCoordinationTransition(state, together()), isFalse);
      expect(
        isCoordinationTransition(
          state,
          together(handMotion: HandMotion.contrary),
        ),
        isFalse,
      );
    });

    test('the two are distinct candidates', () {
      final parallel = together();
      final contrary = together(handMotion: HandMotion.contrary);

      expect(parallel, isNot(contrary));
      expect(parallel.hashCode, isNot(contrary.hashCode));
      expect(parallel.hasSameRealizationAs(contrary), isFalse);
    });
  });

  group('what actually spends the transition', () {
    Outcome outcome({required bool started}) => Outcome(
      started: started,
      retrieval: FactualRetrieval.succeeded,
      completed: started,
      materialRetrieval: 1.0,
      pitchIntegrity: started ? 1.0 : 0.0,
      continuity: started ? 1.0 : 0.0,
      temporalStability: started ? 1.0 : 0.0,
      achievedTempoRatio: started ? 1.0 : 0.0,
      topologyAccuracy: 1.0,
    );

    LearnerState afterPlaying({required bool started}) {
      final state = readyForBoth();
      final exercise = together();
      final played = outcome(started: started);
      learner.applyOutcome(
        state: state,
        exercise: exercise,
        outcome: played,
        weights: evidenceWeightsFor(exercise, played),
        prediction: learner.predict(state, exercise, at: t0),
        at: t0,
      );
      return state;
    }

    test('a played attempt does', () {
      expect(
        isCoordinationTransition(afterPlaying(started: true), together()),
        isFalse,
      );
    });

    test('an attempt that never started does not', () {
      // Execution evidence is what marks the material as coordinated, and an
      // unstarted attempt carries none: nothing was played, so the learner has
      // not met the coordination task and the transition is still owed them.
      final state = afterPlaying(started: false);

      expect(
        evidenceWeightsFor(
          together(),
          outcome(started: false),
        ).materialExecution,
        0.0,
      );
      expect(isCoordinationTransition(state, together()), isTrue);
      expect(
        isCoordinationTransition(
          state,
          together(handMotion: HandMotion.contrary),
        ),
        isTrue,
      );
    });
  });

  group('which motion the transition is spent on', () {
    RankKey keyWith({required bool contrary}) => RankKey(
      tier: EligibilityTier.fullyEligible,
      coordinationTransition: true,
      contraryCoordination: contrary,
      retention: 0.5,
      information: 1.0,
      diversity: 0,
      goals: 0,
    );

    /// The trace the pipeline produced for [exercise], ranked or not.
    CandidateTrace traceFor(Exercise exercise, LearnerState state) => pipeline
        .evaluate(
          state: state,
          session: SessionState(),
          candidates: [exercise],
          at: t0,
        )
        // Evaluation adds execution neighbors, so the trace for the exercise
        // asked about is picked out rather than assumed to be the only one.
        .firstWhere((trace) => trace.exercise == exercise);

    test('contrary outranks parallel on otherwise equal terms', () {
      expect(
        keyWith(contrary: true).compareTo(keyWith(contrary: false)),
        greaterThan(0),
        reason:
            'the two motions tie on every other term, so without this the '
            'order of HandMotion.values decides which one a learner meets',
      );
    });

    test('and the term sits below the transition it belongs to', () {
      final transition = keyWith(contrary: false);
      final notTransition = RankKey(
        tier: EligibilityTier.fullyEligible,
        retention: 0.5,
        information: 1.0,
        diversity: 0,
        goals: 0,
      );

      expect(
        transition.compareTo(notTransition),
        greaterThan(0),
        reason: 'a parallel transition still outranks no transition at all',
      );
    });

    test('the pipeline marks both motions while the transition is unspent', () {
      final state = readyForBoth();

      expect(traceFor(together(), state).coordinationTransition, isTrue);
      expect(
        traceFor(
          together(handMotion: HandMotion.contrary),
          state,
        ).coordinationTransition,
        isTrue,
      );
    });

    test('and neither once it is spent', () {
      final state = readyForBoth();
      state
              .materialExecutionFor(
                (
                  material.materialId,
                  HandConfiguration.together,
                  HandMotion.parallel,
                ),
                t0,
                learnerParams,
              )
              .lastEvidenceAt =
          t0;

      expect(traceFor(together(), state).coordinationTransition, isFalse);
      expect(
        traceFor(
          together(handMotion: HandMotion.contrary),
          state,
        ).coordinationTransition,
        isFalse,
      );
    });
  });

  group('what actually spends the transition', () {
    Outcome outcome({required bool started}) => Outcome(
      started: started,
      retrieval: FactualRetrieval.succeeded,
      completed: started,
      materialRetrieval: 1.0,
      pitchIntegrity: started ? 1.0 : 0.0,
      continuity: started ? 1.0 : 0.0,
      temporalStability: started ? 1.0 : 0.0,
      achievedTempoRatio: started ? 1.0 : 0.0,
      topologyAccuracy: 1.0,
    );

    LearnerState afterPlaying({required bool started}) {
      final state = readyForBoth();
      final exercise = together();
      final played = outcome(started: started);
      learner.applyOutcome(
        state: state,
        exercise: exercise,
        outcome: played,
        weights: evidenceWeightsFor(exercise, played),
        prediction: learner.predict(state, exercise, at: t0),
        at: t0,
      );
      return state;
    }

    test('a played attempt does', () {
      expect(
        isCoordinationTransition(afterPlaying(started: true), together()),
        isFalse,
      );
    });

    test('an attempt that never started does not', () {
      // Execution evidence is what marks the material as coordinated, and an
      // unstarted attempt carries none: nothing was played, so the learner has
      // not met the coordination task and the transition is still owed them.
      final state = afterPlaying(started: false);

      expect(
        evidenceWeightsFor(
          together(),
          outcome(started: false),
        ).materialExecution,
        0.0,
      );
      expect(isCoordinationTransition(state, together()), isTrue);
      expect(
        isCoordinationTransition(
          state,
          together(handMotion: HandMotion.contrary),
        ),
        isTrue,
      );
    });
  });
}
