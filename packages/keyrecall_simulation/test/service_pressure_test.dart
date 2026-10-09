import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  RequirementObservation observed({
    bool actionable = true,
    bool served = false,
    String id = 'r',
  }) => RequirementObservation(
    decision: 0,
    requirementId: id,
    materialId: 'C_MAJOR',
    familyId: 'SCALE',
    due: true,
    covered: false,
    admitted: actionable,
    fullyRanked: actionable,
    materialRanked: actionable,
    heldForRecovery: false,
    servedMaterial: served,
    served: served,
  );

  group('pressure', () {
    test('builds while a requirement is actionable and unserved', () {
      final pressure = ServicePressure(threshold: 3);
      pressure
        ..record([observed()])
        ..record([observed(actionable: false)])
        ..record([observed()]);

      expect(pressure.missedBy('r'), 2);
    });

    test('clears when the requirement is served', () {
      final pressure = ServicePressure(threshold: 3)
        ..record([observed()])
        ..record([observed(served: true)]);

      expect(pressure.missedBy('r'), 0);
    });
  });

  group('a seeded run under the rule', () {
    late ServiceCensus census;
    late ServicePressure pressure;
    const threshold = 5;

    setUpAll(() async {
      pressure = ServicePressure(threshold: threshold);
      census = await runServiceCensus(
        player: PlayerArchetypes.developing,
        sessions: demoSessions(
          from: demoHistoryStart,
          until: demoHistoryStart.add(const Duration(days: 12)),
        ),
        pressure: pressure,
      );
    });

    test('takes only ranking\'s slots, for work that survived selection', () {
      for (final substitution in census.substitutions) {
        expect(substitution.displacedStage, SelectionStage.ranking);
        expect(substitution.promotedSelectable, isTrue);
        expect(substitution.promotedFullyEligible, isTrue);
        expect(substitution.promotedServesRequirement, isTrue);
      }
    });

    test('keeps its suspensions and measures consistent', () {
      for (final id in pressure.suspendedSince.keys) {
        expect(pressure.isSuspended(id), isTrue, reason: id);
      }
      for (final observation in census.observations) {
        expect(observation.retrieval, inInclusiveRange(0, 1));
      }
      final outcomes = ServiceOutcomes.of(census, pressure: pressure);
      for (final share in [
        ...outcomes.fading.values,
        ...outcomes.retrievalAll.values,
        ...outcomes.retrievalCovered.values,
        outcomes.healthyAtEnd,
        outcomes.incomplete,
        outcomes.firstTimedFaltered,
        outcomes.switching,
      ]) {
        expect(share, inInclusiveRange(0, 1));
      }
      expect(outcomes.substitutions, census.substitutions.length);
      expect(
        outcomes.suspendedYetActionable,
        lessThanOrEqualTo(outcomes.suspendedAtEnd),
      );
    });

    test('substitutes only past the threshold, for what it promoted', () {
      expect(census.substitutions, isNotEmpty);
      final byDecision = {
        for (final decision in census.decisions) decision.decision: decision,
      };
      final requirementMaterial = {
        for (final observation in census.observations)
          observation.requirementId: observation.materialId,
      };
      for (final substitution in census.substitutions) {
        expect(substitution.missed, greaterThanOrEqualTo(threshold));
        final decision = byDecision[substitution.decision]!;
        expect(decision.stage, 'servicePressure');
        expect(
          decision.materialId,
          requirementMaterial[substitution.requirementId],
        );
      }
      expect(
        census.decisions.where((d) => d.stage == 'servicePressure'),
        hasLength(census.substitutions.length),
      );
    });

    test('leaves a journal that replays', () {
      final journal = AttemptJournal(
        JournalHeader(profileId: 'census', createdAt: demoHistoryStart),
      )..appendAll(census.records);
      const learner = LearnerModel();
      expect(
        replayJournal(
          journal,
          model: learner,
          initial: learner.placementState(
            PlayerArchetypes.developing.placement,
            at: demoHistoryStart,
          ),
        ).isFaithful,
        isTrue,
      );
    });
  });
}
