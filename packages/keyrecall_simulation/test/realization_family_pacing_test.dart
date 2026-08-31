import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  group('realization family resolution', () {
    test('hands together declares both a hands and a motion strand', () {
      expect(handMotionFamilies(_exercise(HandConfiguration.right)), {
        'hands:right',
      });
      expect(
        handMotionFamilies(
          _exercise(HandConfiguration.together, motion: HandMotion.contrary),
        ),
        {'hands:together', 'motion:contrary'},
      );
    });
  });

  group('family pressure', () {
    test('stays at zero until the window is full', () {
      final pacing = RealizationFamilyPacing(
        config: const RealizationFamilyPacingConfig(window: 8),
      );
      for (var i = 0; i < 7; i++) {
        pacing.record(_exercise(HandConfiguration.together), productive: false);
      }

      expect(pacing.pressure('hands:together'), 0);
    });

    test('rises on a dominant family that yields nothing', () {
      final pacing = _filled(together: 6, right: 2, productive: false);

      expect(pacing.pressure('hands:together'), closeTo(0.25, 1e-9));
      expect(pacing.pressure('hands:right'), 0);
      expect(pacing.pressuredFamilies(), contains('hands:together'));
    });

    test('relaxes as the dominant family produces managed execution', () {
      final pacing = _filled(together: 6, right: 2, productive: true);

      expect(pacing.pressure('hands:together'), 0);
      expect(pacing.pressuredFamilies(), isEmpty);
    });

    test('accumulates on the shared strand across both motions', () {
      final pacing = RealizationFamilyPacing(
        config: const RealizationFamilyPacingConfig(window: 8),
      );
      for (var i = 0; i < 6; i++) {
        pacing.record(
          _exercise(
            HandConfiguration.together,
            motion: i.isEven ? HandMotion.parallel : HandMotion.contrary,
          ),
          productive: false,
        );
      }
      for (var i = 0; i < 2; i++) {
        pacing.record(_exercise(HandConfiguration.right), productive: true);
      }

      expect(pacing.pressuredFamilies(), {'hands:together'});
      expect(
        pacing.isPressured(
          _exercise(HandConfiguration.together, motion: HandMotion.parallel),
          pacing.pressuredFamilies(),
        ),
        isTrue,
      );
    });

    test('forgets a family once the window has moved past it', () {
      final pacing = _filled(together: 6, right: 2, productive: false);
      for (var i = 0; i < 8; i++) {
        pacing.record(_exercise(HandConfiguration.left), productive: true);
      }

      expect(pacing.pressure('hands:together'), 0);
    });
  });

  group('relievability', () {
    test('a readier alternative can relieve the pressured family', () {
      expect(
        _setAside(pressuredP: 0.20, relievingP: 0.32).isRelievable,
        isTrue,
      );
    });

    test('a less ready alternative cannot', () {
      expect(
        _setAside(pressuredP: 0.20, relievingP: 0.17).isRelievable,
        isFalse,
      );
    });
  });
}

FamilySetAside _setAside({
  required double pressuredP,
  required double relievingP,
}) => FamilySetAside(
  slot: 0,
  pressuredFamilies: const {'hands:together'},
  pressured: _trace(HandConfiguration.together, pressuredP),
  relieving: _trace(HandConfiguration.right, relievingP),
);

CandidateTrace _trace(HandConfiguration hands, double executionP) =>
    CandidateTrace(
      exercise: _exercise(hands),
      eligibility: const EligibilityDecision(
        EligibilityTier.fullyEligible,
        'eligible',
      ),
      safety: const SafetyDecision(true, 'safe'),
      challengeStatus: StageStatus.reached,
      prediction: Prediction(
        independentRetrievalP: 1,
        materialAvailableP: 1,
        executionP: executionP,
        coordinationP: 1,
        topologyP: 1,
      ),
      isWithinChallengeBand: false,
      challengeBypass: ChallengeBypass.executionProgression,
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

RealizationFamilyPacing _filled({
  required int together,
  required int right,
  required bool productive,
}) {
  final pacing = RealizationFamilyPacing(
    config: RealizationFamilyPacingConfig(window: together + right),
  );
  for (var i = 0; i < together; i++) {
    pacing.record(
      _exercise(HandConfiguration.together),
      productive: productive,
    );
  }
  for (var i = 0; i < right; i++) {
    pacing.record(_exercise(HandConfiguration.right), productive: true);
  }
  return pacing;
}

Exercise _exercise(
  HandConfiguration hands, {
  HandMotion motion = HandMotion.parallel,
}) => Exercise.linear(
  material: allScales.first,
  hands: hands,
  octaves: 1,
  direction: ScaleDirection.up,
  tempoBpm: 60,
  handMotion: motion,
);
