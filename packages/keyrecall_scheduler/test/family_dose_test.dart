import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

/// What contraction may and may not do.
///
/// The strength of a contraction is a judgment nobody has calibrated, so
/// nothing here asserts one. What is asserted is the direction: evidence of
/// the family working can only relax it, and it can never take a slot away
/// from a learner with nothing else to do.
void main() {
  const config = DoseConfig();

  Exercise exerciseFor(HandConfiguration hands) => Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: hands,
  );

  List<FamilyObservation> window(List<(HandConfiguration, bool)> attempts) => [
    for (final (hands, productive) in attempts)
      FamilyObservation(
        families: handMotionFamilies(exerciseFor(hands)),
        productive: productive,
      ),
  ];

  List<(HandConfiguration, bool)> runOf(
    HandConfiguration hands,
    int count, {
    required bool productive,
  }) => [for (var i = 0; i < count; i++) (hands, productive)];

  double doseOf(List<(HandConfiguration, bool)> attempts, String family) =>
      familyDose(family, window: window(attempts), config: config);

  group('what a contraction reads', () {
    test('a family with too little evidence is left alone', () {
      final attempts = [
        ...runOf(HandConfiguration.together, 3, productive: false),
        ...runOf(HandConfiguration.right, 9, productive: true),
      ];

      expect(doseOf(attempts, 'hands:together'), 0);
    });

    test('a family that yields nothing contracts fully', () {
      final attempts = [
        ...runOf(HandConfiguration.together, 6, productive: false),
        ...runOf(HandConfiguration.right, 6, productive: false),
      ];

      expect(doseOf(attempts, 'hands:together'), 1);
      expect(doseOf(attempts, 'hands:right'), 1);
    });

    test('a family holding a minority of the window still contracts', () {
      // The case pacing cannot see: four attempts of twelve, none of which
      // worked, is well under any share floor. Halved here rather than full,
      // because the hands this learner is coordinating are working separately.
      final attempts = [
        ...runOf(HandConfiguration.together, 4, productive: false),
        ...runOf(HandConfiguration.right, 8, productive: true),
      ];

      expect(doseOf(attempts, 'hands:together'), 0.5);
    });

    test('managed execution can only relax a contraction', () {
      var previous = 1.0;
      for (var produced = 0; produced <= 4; produced++) {
        final attempts = [
          ...runOf(HandConfiguration.together, produced, productive: true),
          ...runOf(HandConfiguration.together, 8 - produced, productive: false),
          ...runOf(HandConfiguration.right, 4, productive: true),
        ];
        final dose = doseOf(attempts, 'hands:together');

        expect(dose, lessThanOrEqualTo(previous));
        previous = dose;
      }
      expect(previous, 0);
    });

    test('productive prerequisite work can only relax a contraction', () {
      final unsupported = [
        ...runOf(HandConfiguration.together, 6, productive: false),
        ...runOf(HandConfiguration.right, 6, productive: false),
      ];
      final supported = [
        ...runOf(HandConfiguration.together, 6, productive: false),
        ...runOf(HandConfiguration.right, 6, productive: true),
      ];

      expect(
        doseOf(supported, 'hands:together'),
        lessThan(doseOf(unsupported, 'hands:together')),
      );
    });

    test('a family with no declared prerequisite reads its own yield only', () {
      final attempts = [
        ...runOf(HandConfiguration.left, 6, productive: false),
        ...runOf(HandConfiguration.right, 6, productive: true),
      ];

      expect(doseOf(attempts, 'hands:left'), 1);
    });
  });

  group('what a contraction does to a slot', () {
    const pipeline = SchedulerPipeline(learner: LearnerModel());
    final dosing = pipeline.config.withDose(config);

    test('a family under its cadence is held back', () {
      final session = SessionState(
        recentFamilies: window([
          ...runOf(HandConfiguration.right, 6, productive: true),
          ...runOf(HandConfiguration.together, 6, productive: false),
        ]),
      );
      final contracted = familiesOverDose(
        window: session.recentFamilies,
        config: config,
      );

      expect(contracted.keys, contains('hands:together'));
      expect(
        isOverDosed(exerciseFor(HandConfiguration.together), contracted),
        isTrue,
      );
      expect(
        isOverDosed(exerciseFor(HandConfiguration.right), contracted),
        isFalse,
      );
    });

    test('a family that has waited its cadence is offered again', () {
      final session = SessionState(
        recentFamilies: window([
          ...runOf(HandConfiguration.together, 6, productive: false),
          ...runOf(HandConfiguration.right, 6, productive: true),
        ]),
      );

      expect(
        familiesOverDose(window: session.recentFamilies, config: config),
        isEmpty,
      );
    });

    test('a slot holding only contracted work keeps it', () {
      final session = SessionState(
        recentFamilies: window([
          ...runOf(HandConfiguration.right, 6, productive: true),
          ...runOf(HandConfiguration.together, 6, productive: false),
        ]),
      );
      final only = [_trace(exerciseFor(HandConfiguration.together))];
      final decision = SchedulerPipeline(
        learner: const LearnerModel(),
        config: dosing,
      ).doseOf(only, session);

      expect(decision.disposition, DoseDisposition.unrelieved);
      expect(decision.selectable, only);
    });

    test('nothing happens without a dose policy', () {
      final session = SessionState(
        recentFamilies: window([
          ...runOf(HandConfiguration.right, 6, productive: true),
          ...runOf(HandConfiguration.together, 6, productive: false),
        ]),
      );
      final paced = [
        _trace(exerciseFor(HandConfiguration.together)),
        _trace(exerciseFor(HandConfiguration.right)),
      ];
      final decision = pipeline.doseOf(paced, session);

      expect(decision.disposition, DoseDisposition.inactive);
      expect(decision.selectable, paced);
    });

    test('a contracted family loses the slot to other work', () {
      final session = SessionState(
        recentFamilies: window([
          ...runOf(HandConfiguration.right, 6, productive: true),
          ...runOf(HandConfiguration.together, 6, productive: false),
        ]),
      );
      final paced = [
        _trace(exerciseFor(HandConfiguration.together)),
        _trace(exerciseFor(HandConfiguration.right)),
      ];
      final decision = SchedulerPipeline(
        learner: const LearnerModel(),
        config: dosing,
      ).doseOf(paced, session);

      expect(decision.disposition, DoseDisposition.contracted);
      expect(decision.selectable, [paced.last]);
    });
  });

  group('the cadence a contraction asks for', () {
    test('no contraction asks for no gap', () {
      expect(doseGap(0, config), 1);
    });

    test('full contraction asks for the widest gap', () {
      expect(doseGap(1, config), config.maximumGap);
    });

    test('the gap never exceeds the widest', () {
      for (var step = 0; step <= 10; step++) {
        final gap = doseGap(step / 10, config);
        expect(gap, inInclusiveRange(1, config.maximumGap));
      }
    });
  });
}

CandidateTrace _trace(Exercise exercise) => CandidateTrace(
  exercise: exercise,
  eligibility: const EligibilityDecision(
    EligibilityTier.fullyEligible,
    'eligible',
  ),
  safety: const SafetyDecision(true, 'safe'),
  challengeStatus: StageStatus.reached,
  prediction: const Prediction(
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
);
