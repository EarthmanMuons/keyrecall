import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// Whether the altered-form waiver can actually be earned by playing.
///
/// `fluentHandsTogetherFloor` and `advancedMean` are both 1.0, set
/// independently and for different reasons, and two independently reasonable
/// constants meeting at an exact boundary is how the cold-start regime went
/// wrong. So this asks the question through the real update path rather than
/// by assigning a mean: a state built by placement and moved by outcomes,
/// rather than one written to say what a test needs.
///
/// Reachability is the point. A floor nothing can cross is a phase nobody
/// escapes, and a floor placement already sits on is no floor at all.
void main() {
  const model = LearnerModel();
  const pipeline = SchedulerPipeline(learner: model);

  final together = exerciseFor(
    TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.together,
    octaves: 1,
    guidance: GuidanceContext.unguided,
  );
  final harmonic = exerciseFor(
    TechnicalMaterial('A', ScaleForm.harmonicMinor),
    guidance: GuidanceContext.continuouslyCued,
  );

  Outcome handsTogether({required double quality}) => Outcome(
    started: true,
    retrieval: FactualRetrieval.succeeded,
    completed: true,
    materialRetrieval: 1.0,
    pitchIntegrity: quality,
    continuity: quality,
    temporalStability: quality,
    achievedTempoRatio: 1.0,
    topologyAccuracy: 1.0,
    coordination: quality,
  );

  /// Plays hands-together attempts of the given qualities, and reports after
  /// which one the waiver opened, or null when it never did.
  int? opensAfter(PlacementTier tier, List<double> qualities) {
    final state = model.placementState(tier, at: t0);
    for (final (index, quality) in qualities.indexed) {
      final at = t0.add(Duration(minutes: 5 * (index + 1)));
      final outcome = handsTogether(quality: quality);
      model.propagate(state, at);
      model.applyOutcome(
        state: state,
        exercise: together,
        outcome: outcome,
        weights: evidenceWeightsFor(together, outcome),
        prediction: model.predict(state, together, at: at),
        at: at,
      );
      if (pipeline.eligibilityFor(state, harmonic).tier ==
          EligibilityTier.fullyEligible) {
        return index + 1;
      }
    }
    return null;
  }

  test('placement alone never waives, however advanced the claim', () {
    final claimed = model.placementState(PlacementTier.advanced, at: t0);

    expect(
      pipeline.eligibilityFor(claimed, harmonic).tier,
      EligibilityTier.provisionallyEligible,
      reason:
          'the coordination mean is already at the floor and nothing has been '
          'played, which is the whole reason the waiver reads evidence as '
          'well as the mean',
    );
  });

  test('one hands-together scale played well is enough', () {
    expect(
      opensAfter(PlacementTier.advanced, List.filled(4, 1.0)),
      1,
      reason:
          'somebody who arrived playing scales shows it once rather than '
          'demonstrating six of them in each hand',
    );
  });

  test('claiming advanced and playing poorly waives nothing', () {
    expect(
      opensAfter(PlacementTier.advanced, List.filled(8, 0.5)),
      isNull,
      reason: 'the claim opens nothing the playing does not support',
    );
  });

  test('a bad first attempt costs attempts, not the waiver', () {
    expect(
      opensAfter(PlacementTier.advanced, [0.2, 1.0, 1.0, 1.0, 1.0]),
      3,
      reason:
          'one ragged attempt at an unfamiliar app should not lock an '
          'experienced player out of material they can play',
    );
  });

  test('the floor is out of reach for a learner still in the phase', () {
    for (final tier in [PlacementTier.beginner, PlacementTier.someExperience]) {
      expect(
        opensAfter(tier, List.filled(14, 1.0)),
        isNull,
        reason:
            'the ordinary path is how ${tier.id} gets there, and it is not a '
            'slower version of this one',
      );
    }
  });
}
