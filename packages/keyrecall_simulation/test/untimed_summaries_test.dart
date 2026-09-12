import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What a summary says about attempts whose timing went unmeasured.
///
/// Every statistic here is an average, and an average of nothing is not zero.
/// A sitting of attempts too short to time observed no motor quality and no
/// pace, and a profile that reported zeros would be fitted against numbers
/// nobody played.
void main() {
  final exercise = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    octaves: 1,
    tempoBpm: 60,
  );

  Outcome outcomeWith({double? continuity, double? temporalStability}) =>
      Outcome(
        started: true,
        retrieval: FactualRetrieval.succeeded,
        completed: true,
        materialRetrieval: 1,
        pitchIntegrity: 1,
        continuity: continuity,
        temporalStability: temporalStability,
        achievedTempoRatio: continuity == null ? 0 : 1,
        topologyAccuracy: 1,
      );

  final untimed = outcomeWith();
  final timed = outcomeWith(continuity: 1, temporalStability: 1);

  SittingProfile profileWith(Outcome outcome, {int attempts = 8}) => profileOf([
    for (var index = 0; index < attempts; index++)
      AttemptObservation(exercise, outcome, seenBefore: true),
  ]);

  group('a sitting nothing timed', () {
    final profile = profileWith(untimed);

    test('reports no motor score for the hand that played', () {
      expect(untimed.motorScore, isNull);
      expect(profile.motor, isNot(contains(HandConfiguration.right)));
    });

    test('reports no pace, by any of the three tempo readings', () {
      expect(profile.achievedTempo, isNot(contains(HandConfiguration.right)));
      expect(profile.tempoRatio, isNull);
      expect(profile.sprintShare, isNull);
    });

    test('still reports what it did observe', () {
      expect(profile.attempts, 8);
      expect(profile.completionRate, 1.0);
    });

    test('observes neither hand ability nor sprinting', () {
      final answers = identifiabilityOf(
        ensemble: const [],
        observed: profile,
        vary: firstSitting,
      );

      expect(
        answers[PlayerParameter.rightHandAbility],
        Identifiability.unobserved,
      );
      expect(
        answers[PlayerParameter.sprintProbability],
        Identifiability.unobserved,
      );
      expect(
        answers[PlayerParameter.naturalTempoRight],
        Identifiability.unobserved,
      );
    });

    test('is no distance from a sitting that measured something else', () {
      // Every term the two profiles could be compared on is absent from one of
      // them, and an absent term is skipped rather than compared against a
      // zero.
      expect(
        profileDistance(profile, profileWith(timed)),
        profileDistance(profile, profileWith(untimed)),
      );
    });
  });

  group('a sitting that measured its timing', () {
    final profile = profileWith(timed);

    test('reports the hand it measured', () {
      expect(profile.motor[HandConfiguration.right], 1.0);
      expect(profile.achievedTempo[HandConfiguration.right], 60.0);
      expect(profile.tempoRatio, 1.0);
      expect(
        profile.sprintShare,
        0.0,
        reason: 'nobody sprinted, which is a reading rather than an absence',
      );
    });

    test('observes the hand ability and the sprinting', () {
      final answers = identifiabilityOf(
        ensemble: const [],
        observed: profile,
        vary: firstSitting,
      );

      expect(
        answers[PlayerParameter.rightHandAbility],
        isNot(Identifiability.unobserved),
      );
      expect(
        answers[PlayerParameter.sprintProbability],
        isNot(Identifiability.unobserved),
      );
    });
  });

  group('a milestone whose windows nothing timed', () {
    /// A run of [slots] attempts, two octaves from [milestoneAt] onward.
    Trajectory runOf({
      required Outcome outcome,
      int slots = 40,
      int milestoneAt = 15,
    }) => Trajectory(
      playerId: 'untimed',
      seed: 0,
      slots: [
        for (var index = 0; index < slots; index++)
          _slotOf(
            index,
            outcome: outcome,
            octaves: index < milestoneAt ? 1 : 2,
          ),
      ],
    );

    test('reports no shock, rather than a drop to zero', () {
      expect(milestoneShocks(runOf(outcome: untimed), window: 15), isEmpty);
    });

    test('while a timed run reports one', () {
      final shocks = milestoneShocks(runOf(outcome: timed), window: 15);

      expect(shocks.single.milestone, Milestone.twoOctaves);
      expect(shocks.single.before, 1.0);
      expect(shocks.single.after, 1.0);
      expect(shocks.single.delta, 0.0);
    });

    test('and a run that stops being timed reports only what it measured', () {
      // Timed up to the milestone and untimed after it. The window after
      // measured nothing, so there is no comparison to make, and calling that
      // a fall from 1.0 to 0.0 would invent the worst shock in the run.
      final trajectory = Trajectory(
        playerId: 'half_timed',
        seed: 0,
        slots: [
          for (var index = 0; index < 40; index++)
            _slotOf(
              index,
              outcome: index < 15 ? timed : untimed,
              octaves: index < 15 ? 1 : 2,
            ),
        ],
      );

      expect(milestoneShocks(trajectory, window: 15), isEmpty);
    });
  });
}

/// One slot of a constructed run, with nothing in it but what a shock reads.
TrajectorySlot _slotOf(
  int index, {
  required Outcome outcome,
  required int octaves,
}) {
  final exercise = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    octaves: octaves,
    tempoBpm: 60,
  );
  return TrajectorySlot(
    index: index,
    at: DateTime.utc(2026).add(Duration(minutes: index)),
    sitting: 0,
    chosen: exercise,
    winner: CandidateTrace(
      exercise: exercise,
      eligibility: const EligibilityDecision(
        EligibilityTier.fullyEligible,
        'eligible',
      ),
      safety: const SafetyDecision(true, 'safe'),
      challengeStatus: StageStatus.reached,
      prediction: Prediction(
        independentRetrievalP: 0.8,
        materialAvailableP: 0.8,
        executionP: 0.8,
        coordinationP: 1.0,
        topologyP: 0.8,
      ),
      isWithinChallengeBand: true,
      challengeBypass: null,
      challengeSurvived: true,
      priorityStatus: StageStatus.reached,
      rankKey: const RankKey(
        tier: EligibilityTier.fullyEligible,
        coordinationTransition: false,
        retention: 0,
        information: 0,
        diversity: 0,
        goals: 0,
        realization: RealizationRank.unmeasured,
        realizationFit: 0,
      ),
    ),
    alternatives: const [],
    performedTempoBpm: 60,
    outcome: outcome,
    managedExecution: const LearnerModel().executionWasManaged(outcome),
    frontierBefore: const {},
    frontierAfter: const {},
    pacedBefore: 0,
    transferableBefore: 0,
    candidates: const CandidateStageCounts(
      generated: 1,
      evaluated: 1,
      eligible: 1,
      admitted: 1,
      selectable: 1,
    ),
    handsTogether: HandsTogetherStages(
      prerequisiteSatisfied: const {},
      eligible: const {},
      admitted: const {},
      selectable: const {},
    ),
    probe: ProbeState.none,
  );
}
