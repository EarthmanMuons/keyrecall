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

  Exercise together({int octaves = 1, double tempoBpm = 60}) => exerciseFor(
    material,
    hands: HandConfiguration.together,
    octaves: octaves,
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
          (material.materialId, hands),
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

  test('and the first attempt ends it, however it went', () {
    // The attempt rather than the success. What the scheduler owes is bringing
    // the work into practice; how it went is evidence like any other.
    final state = readyForBoth();
    state
            .materialExecutionFor(
              (material.materialId, HandConfiguration.together),
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
  });
}
