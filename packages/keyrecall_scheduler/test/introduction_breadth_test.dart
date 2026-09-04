import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

void main() {
  group('unresolved introductions', () {
    test('counts material met but never retrieved', () {
      final state = stateAt(PlacementTier.beginner);
      _met(state, 0);
      _met(state, 1, retrieved: true);

      expect(_unresolved(state, _catalogCap), {'catalog': 1});
    });

    test('ignores material no candidate names', () {
      final state = stateAt(PlacementTier.beginner);
      _met(state, 0);

      expect(
        unresolvedIntroductions(
          state: state,
          materialFamilies: const {},
          config: _catalogCap,
        ),
        isEmpty,
      );
    });

    test('gives each family its own budget', () {
      final state = stateAt(PlacementTier.beginner);
      _met(state, 0);
      _met(state, 1);

      expect(_unresolved(state, _familyCap), {
        TechnicalMaterial.scaleFamilyId: 2,
      });
    });
  });

  group('what the cap acts on', () {
    test('the other hand of material already met is not breadth', () {
      final state = stateAt(PlacementTier.beginner);
      _met(state, 0);

      expect(widensCatalog(_introduction(0), state), isFalse);
      expect(widensCatalog(_introduction(1), state), isTrue);
    });

    test('work that is not an introduction is never withheld', () {
      final state = stateAt(PlacementTier.beginner);

      expect(
        widensCatalog(
          _trace(0, bypass: ChallengeBypass.executionProgression),
          state,
        ),
        isFalse,
      );
    });
  });

  group('selection invariants', () {
    test('the cap only ever removes candidates', () {
      final state = _atCap();
      final traces = [_introduction(2), _trace(0)];

      final decision = _cappedPipeline().capIntroductions(
        traces,
        _evaluated(traces),
        state,
      );

      expect(decision.disposition, IntroductionDisposition.withheld);
      expect(decision.withheld, 1);
      expect(decision.selectable, [traces.last]);
    });

    test('the cap never empties a selectable set', () {
      final state = _atCap();
      final traces = [_introduction(2), _introduction(3)];

      final decision = _cappedPipeline().capIntroductions(
        traces,
        _evaluated(traces),
        state,
      );

      expect(decision.disposition, IntroductionDisposition.unrelieved);
      expect(decision.selectable, traces);
    });

    test('a budget with room leaves the guarded set alone', () {
      final state = stateAt(PlacementTier.beginner);
      _met(state, 0);
      final traces = [_introduction(2), _trace(0)];

      final decision = _cappedPipeline().capIntroductions(
        traces,
        _evaluated(traces),
        state,
      );

      expect(decision.disposition, IntroductionDisposition.inactive);
      expect(decision.selectable, traces);
    });

    test('an uncapped configuration leaves the guarded set alone', () {
      final state = _atCap();
      final traces = [_introduction(2), _trace(0)];

      final decision = pipeline.capIntroductions(
        traces,
        _evaluated(traces),
        state,
      );

      expect(decision.disposition, IntroductionDisposition.inactive);
      expect(decision.selectable, traces);
    });

    test('a caller without learner state applies no cap', () {
      final traces = [_introduction(2), _trace(0)];

      final decision = _cappedPipeline().capIntroductions(
        traces,
        _evaluated(traces),
        null,
      );

      expect(decision.disposition, IntroductionDisposition.inactive);
    });

    test('retrieving one material makes room for the next', () {
      final state = _atCap();
      final traces = [_introduction(2), _trace(0)];

      state.materialMemory[materials[0].materialId]!.factualLastRetrievalAt =
          t0;

      expect(
        _cappedPipeline()
            .capIntroductions(traces, _evaluated(traces), state)
            .disposition,
        IntroductionDisposition.inactive,
      );
    });
  });
}

const _catalogCap = IntroductionConfig(
  concurrentUnresolved: 2,
  scope: IntroductionScope.catalog,
);

const _familyCap = IntroductionConfig(
  concurrentUnresolved: 2,
  scope: IntroductionScope.family,
);

SchedulerPipeline _cappedPipeline() => SchedulerPipeline(
  learner: learner,
  config: config.withIntroductions(_catalogCap),
);

/// The slot's whole evaluated set, which is what names each material's family.
List<CandidateTrace> _evaluated(List<CandidateTrace> guarded) => [
  ...guarded,
  _trace(0),
  _trace(1),
];

/// A state holding exactly the cap's worth of unresolved introductions.
LearnerState _atCap() {
  final state = stateAt(PlacementTier.beginner);
  _met(state, 0);
  _met(state, 1);
  return state;
}

void _met(LearnerState state, int material, {bool retrieved = false}) {
  final memory = state.materialMemoryFor(
    materials[material].materialId,
    learnerParams,
  );
  if (retrieved) memory.factualLastRetrievalAt = t0;
}

Map<String, int> _unresolved(LearnerState state, IntroductionConfig config) =>
    unresolvedIntroductions(
      state: state,
      materialFamilies: {
        for (final material in materials)
          material.materialId: material.familyId,
      },
      config: config,
    );

CandidateTrace _introduction(int material) =>
    _trace(material, bypass: ChallengeBypass.newMaterial);

CandidateTrace _trace(
  int material, {
  ChallengeBypass bypass = ChallengeBypass.executionProgression,
}) => CandidateTrace(
  exercise: exerciseFor(materials[material]),
  eligibility: const EligibilityDecision(
    EligibilityTier.fullyEligible,
    'eligible',
  ),
  safety: const SafetyDecision(true, 'safe'),
  challengeStatus: StageStatus.reached,
  prediction: Prediction(
    independentRetrievalP: 1,
    materialAvailableP: 1,
    executionP: 0.5,
    coordinationP: 1,
    topologyP: 1,
  ),
  isWithinChallengeBand: false,
  challengeBypass: bypass,
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
