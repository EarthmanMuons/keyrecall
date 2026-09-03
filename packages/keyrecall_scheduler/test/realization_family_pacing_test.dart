import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

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
      final session = SessionState();
      for (var i = 0; i < 7; i++) {
        _record(session, HandConfiguration.together, productive: false);
      }

      expect(_pressure(session, 'hands:together'), 0);
    });

    test('rises on a dominant family that yields nothing', () {
      final session = _filled(together: 6, right: 2, productive: false);

      expect(_pressure(session, 'hands:together'), closeTo(0.25, 1e-9));
      expect(_pressure(session, 'hands:right'), 0);
      expect(_pressured(session), contains('hands:together'));
    });

    test('relaxes as the dominant family produces managed execution', () {
      final session = _filled(together: 6, right: 2, productive: true);

      expect(_pressure(session, 'hands:together'), 0);
      expect(_pressured(session), isEmpty);
    });

    test('accumulates on the shared strand across both motions', () {
      final session = SessionState();
      for (var i = 0; i < 6; i++) {
        _record(
          session,
          HandConfiguration.together,
          motion: i.isEven ? HandMotion.parallel : HandMotion.contrary,
          productive: false,
        );
      }
      for (var i = 0; i < 2; i++) {
        _record(session, HandConfiguration.right, productive: true);
      }

      expect(_pressured(session), {'hands:together'});
      expect(
        isPressured(
          _exercise(HandConfiguration.together, motion: HandMotion.parallel),
          _pressured(session),
        ),
        isTrue,
      );
    });

    test('forgets a family once the window has moved past it', () {
      final session = _filled(together: 6, right: 2, productive: false);
      for (var i = 0; i < 8; i++) {
        _record(session, HandConfiguration.left, productive: true);
      }

      expect(_pressure(session, 'hands:together'), 0);
    });
  });

  group('opaque family keys', () {
    test('an unrelated vocabulary paces identically', () {
      Set<String> strands(Exercise exercise) =>
          exercise.conditions.hands == HandConfiguration.together
          ? {'strand-a'}
          : {'strand-b'};
      final session = SessionState();
      for (var i = 0; i < 6; i++) {
        _record(
          session,
          HandConfiguration.together,
          productive: false,
          families: strands,
        );
      }
      for (var i = 0; i < 2; i++) {
        _record(
          session,
          HandConfiguration.right,
          productive: true,
          families: strands,
        );
      }

      expect(_pressured(session), {'strand-a'});
      expect(_pressure(session, 'strand-a'), closeTo(0.25, 1e-9));
    });
  });

  group('selection invariants', () {
    test('pressure only ever removes candidates', () {
      final traces = [
        _trace(HandConfiguration.together, 0.3),
        _trace(HandConfiguration.right, 0.3, material: 1),
      ];

      final selectable = _pacedPipeline().selectable(traces, _saturated());

      expect(selectable, hasLength(1));
      expect(selectable.single.exercise, traces.last.exercise);
      expect(traces, containsAll(selectable));
    });

    test('pacing never empties a selectable set', () {
      final traces = [
        _trace(HandConfiguration.together, 0.3),
        _trace(HandConfiguration.together, 0.2, motion: HandMotion.contrary),
      ];

      final decision = _pacedPipeline().pace(traces, _saturated());

      expect(decision.selectable, hasLength(2));
      expect(decision.disposition, PacingDisposition.unrelieved);
      expect(decision.setAside, isNull);
    });

    test('no relief without a cross-family alternative at least as ready', () {
      final traces = [
        _trace(HandConfiguration.together, 0.4),
        _trace(HandConfiguration.right, 0.2, material: 1),
      ];

      final decision = _pacedPipeline().pace(traces, _saturated());

      expect(decision.selectable, hasLength(2));
      expect(decision.disposition, PacingDisposition.unready);
      expect(decision.setAside, isNull);
    });

    test('relief takes a cross-family alternative that is ready', () {
      final traces = [
        _trace(HandConfiguration.together, 0.2),
        _trace(HandConfiguration.right, 0.4, material: 1),
      ];

      final decision = _pacedPipeline().pace(traces, _saturated());

      expect(decision.selectable, hasLength(1));
      expect(decision.disposition, PacingDisposition.relieved);
      final setAside = decision.setAside!;
      expect(setAside.isRelievable, isTrue);
      expect(
        handMotionFamilies(
          setAside.relieving.exercise,
        ).intersection(setAside.pressuredFamilies),
        isEmpty,
      );
    });

    test('an ungated policy relieves toward a less ready alternative', () {
      final traces = [
        _trace(HandConfiguration.together, 0.4),
        _trace(HandConfiguration.right, 0.2, material: 1),
      ];

      final decision = _pacedPipeline(
        requireReadyAlternative: false,
      ).pace(traces, _saturated());

      expect(decision.disposition, PacingDisposition.relieved);
      expect(decision.setAside!.isRelievable, isFalse);
    });

    test('an unpaced configuration leaves the guarded set alone', () {
      final traces = [
        _trace(HandConfiguration.together, 0.2),
        _trace(HandConfiguration.right, 0.4, material: 1),
      ];

      final decision = SchedulerPipeline(
        learner: learner,
        config: config.withPacing(null),
      ).pace(traces, _saturated());

      expect(decision.selectable, traces);
      expect(decision.disposition, PacingDisposition.inactive);
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

/// The shipped policy, with its window narrowed so a test can saturate it.
const PacingConfig _pacing = PacingConfig(
  window: 8,
  shareFloor: 0.5,
  minFamilyAttempts: 4,
  setAsideAt: 0.15,
  requireReadyAlternative: true,
);

SchedulerPipeline _pacedPipeline({bool requireReadyAlternative = true}) =>
    SchedulerPipeline(
      learner: learner,
      config: config.withPacing(
        PacingConfig(
          window: _pacing.window,
          shareFloor: _pacing.shareFloor,
          minFamilyAttempts: _pacing.minFamilyAttempts,
          setAsideAt: _pacing.setAsideAt,
          requireReadyAlternative: requireReadyAlternative,
        ),
      ),
    );

void _record(
  SessionState session,
  HandConfiguration hands, {
  required bool productive,
  HandMotion motion = HandMotion.parallel,
  RealizationFamilyResolver families = handMotionFamilies,
}) => session.recordFamilySelection(
  _exercise(hands, motion: motion),
  productive: productive,
  config: _pacing,
  families: families,
);

double _pressure(SessionState session, String family) =>
    familyPressure(family, window: session.recentFamilies, config: _pacing);

Set<String> _pressured(SessionState session) =>
    pressuredFamilies(window: session.recentFamilies, config: _pacing);

/// A session whose window is saturated with unproductive hands-together work.
SessionState _saturated() =>
    _filled(together: _pacing.window, right: 0, productive: false);

SessionState _filled({
  required int together,
  required int right,
  required bool productive,
}) {
  final session = SessionState();
  for (var i = 0; i < together; i++) {
    _record(session, HandConfiguration.together, productive: productive);
  }
  for (var i = 0; i < right; i++) {
    _record(session, HandConfiguration.right, productive: true);
  }
  return session;
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

Exercise _exercise(
  HandConfiguration hands, {
  HandMotion motion = HandMotion.parallel,
  int material = 0,
}) => Exercise.linear(
  material: materials[material],
  hands: hands,
  octaves: 1,
  direction: ExerciseDirection.up,
  tempoBpm: 60,
  handMotion: motion,
);
