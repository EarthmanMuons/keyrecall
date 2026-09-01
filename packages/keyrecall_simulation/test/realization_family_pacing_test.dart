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

  group('opaque family keys', () {
    test('an unrelated vocabulary paces identically', () {
      Set<String> strands(Exercise exercise) =>
          exercise.conditions.hands == HandConfiguration.together
          ? {'strand-a'}
          : {'strand-b'};
      final pacing = RealizationFamilyPacing(
        resolver: strands,
        config: const RealizationFamilyPacingConfig(window: 8),
      );
      for (var i = 0; i < 6; i++) {
        pacing.record(_exercise(HandConfiguration.together), productive: false);
      }
      for (var i = 0; i < 2; i++) {
        pacing.record(_exercise(HandConfiguration.right), productive: true);
      }

      expect(pacing.pressuredFamilies(), {'strand-a'});
      expect(pacing.pressure('strand-a'), closeTo(0.25, 1e-9));
    });
  });

  group('selection invariants', () {
    test('pressure only ever removes candidates', () {
      final pipeline = _paced(pressuredOn: HandConfiguration.together);
      final traces = [
        _trace(HandConfiguration.together, 0.3),
        _trace(HandConfiguration.right, 0.3, material: 1),
      ];

      final selectable = pipeline.selectable(traces, SessionState());

      expect(selectable, hasLength(1));
      expect(selectable.single.exercise, traces.last.exercise);
      expect(traces, containsAll(selectable));
    });

    test('pacing never empties a selectable set', () {
      final pipeline = _paced(pressuredOn: HandConfiguration.together);
      final traces = [
        _trace(HandConfiguration.together, 0.3),
        _trace(HandConfiguration.together, 0.2, motion: HandMotion.contrary),
      ];

      final selectable = pipeline.selectable(traces, SessionState());

      expect(selectable, hasLength(2));
      expect(pipeline.setAsides, isEmpty);
      expect(pipeline.unrelievedSlots, 1);
    });

    test('no relief without a cross-family alternative at least as ready', () {
      final pipeline = _paced(
        pressuredOn: HandConfiguration.together,
        requireReadyAlternative: true,
      );
      final traces = [
        _trace(HandConfiguration.together, 0.4),
        _trace(HandConfiguration.right, 0.2, material: 1),
      ];

      final selectable = pipeline.selectable(traces, SessionState());

      expect(selectable, hasLength(2));
      expect(pipeline.setAsides, isEmpty);
      expect(pipeline.unreadySlots, 1);
    });

    test('relief takes a cross-family alternative that is ready', () {
      final pipeline = _paced(
        pressuredOn: HandConfiguration.together,
        requireReadyAlternative: true,
      );
      final traces = [
        _trace(HandConfiguration.together, 0.2),
        _trace(HandConfiguration.right, 0.4, material: 1),
      ];

      final selectable = pipeline.selectable(traces, SessionState());

      expect(selectable, hasLength(1));
      expect(pipeline.setAsides, hasLength(1));
      final setAside = pipeline.setAsides.single;
      expect(setAside.isRelievable, isTrue);
      expect(
        handMotionFamilies(
          setAside.relieving.exercise,
        ).intersection(setAside.pressuredFamilies),
        isEmpty,
      );
    });
  });

  group('trajectory invariants', () {
    const seeds = 4;
    const slots = 40;

    /// The production contract: pressure detects concentration, and relief
    /// requires an alternative that is not a step backward.
    FamilyPacedPipeline contractPipeline() =>
        _pacedPipeline(requireReadyAlternative: true);

    for (final player in PlayerArchetypes.all) {
      test('${player.id} keeps pacing inside admission', () {
        for (var seed = 0; seed < seeds; seed++) {
          final pipeline = contractPipeline();
          final trajectory = runTrajectory(
            player: player,
            seed: seed,
            materials: v1ScaleCatalog,
            slots: slots,
            pipeline: pipeline,
          );
          for (final slot in trajectory.slots) {
            expect(
              slot.winner.isRanked,
              isTrue,
              reason: 'slot ${slot.index} chose an unadmitted exercise',
            );
            expect(
              slot.candidates.selectable,
              greaterThan(0),
              reason: 'slot ${slot.index} was left with nothing selectable',
            );
          }
          for (final setAside in pipeline.setAsides) {
            expect(setAside.isRelievable, isTrue);
            expect(setAside.pressured.isRanked, isTrue);
            expect(setAside.relieving.isRanked, isTrue);
          }
        }
      });

      test('${player.id} is untouched where pressure never forms', () {
        for (var seed = 0; seed < seeds; seed++) {
          final pipeline = contractPipeline();
          final paced = runTrajectory(
            player: player,
            seed: seed,
            materials: v1ScaleCatalog,
            slots: slots,
            pipeline: pipeline,
          );
          if (pipeline.setAsides.isNotEmpty) continue;
          final base = runTrajectory(
            player: player,
            seed: seed,
            materials: v1ScaleCatalog,
            slots: slots,
          );
          expect(
            [for (final slot in paced.slots) slot.chosen],
            [for (final slot in base.slots) slot.chosen],
          );
        }
      });
    }
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

CandidateTrace _trace(
  HandConfiguration hands,
  double executionP, {
  HandMotion motion = HandMotion.parallel,
  int material = 0,
}) => CandidateTrace(
  exercise: _exercise(hands, motion: motion, material: material),
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

FamilyPacedPipeline _pacedPipeline({bool requireReadyAlternative = false}) =>
    FamilyPacedPipeline(
      learner: const LearnerModel(),
      pacing: RealizationFamilyPacing(
        config: RealizationFamilyPacingConfig(
          requireReadyAlternative: requireReadyAlternative,
        ),
      ),
    );

/// A pipeline whose window is already saturated with unproductive work in
/// [pressuredOn], so the next selection sees that family under pressure.
FamilyPacedPipeline _paced({
  required HandConfiguration pressuredOn,
  bool requireReadyAlternative = false,
}) {
  final pipeline = _pacedPipeline(
    requireReadyAlternative: requireReadyAlternative,
  );
  final config = pipeline.pacing.config;
  for (var i = 0; i < config.window; i++) {
    pipeline.pacing.record(_exercise(pressuredOn), productive: false);
  }
  return pipeline;
}

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
  int material = 0,
}) => Exercise.linear(
  material: allScales[material],
  hands: hands,
  octaves: 1,
  direction: ScaleDirection.up,
  tempoBpm: 60,
  handMotion: motion,
);
