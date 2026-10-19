import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart'
    hide AttemptRecord;

void main() {
  final sessions = demoSessions(
    from: demoHistoryStart,
    until: demoHistoryStart.add(const Duration(days: 14)),
  );
  final player = PlausibilityCohort.profiles[9].player;

  Map<String, Object?> withoutAllocation(AttemptRecord record) =>
      record.toJson()..remove('allocation');

  test(
    'an assigned profile decides what the characterized allocator did',
    () async {
      final allocator = RequirementAllocator(k: 2, protectionFloor: 0.6);
      final characterized = await runServiceCensus(
        player: player,
        sessions: sessions,
        playerSeed: 100,
        intervention: allocator,
      );
      final production = await runServiceCensus(
        player: player,
        sessions: sessions,
        playerSeed: 100,
        scheduling: SchedulingAssignment.allocationPilot,
      );

      expect(characterized.substitutions, hasLength(14));
      expect(
        [for (final record in production.records) withoutAllocation(record)],
        [for (final record in characterized.records) withoutAllocation(record)],
      );
      expect(
        [
          for (final record in production.records)
            if (record.allocation case AllocationObserved(
              :final owedRequirementId?,
            ))
              owedRequirementId,
        ],
        [
          for (final substitution in characterized.substitutions)
            substitution.requirementId,
        ],
      );
      for (final record in production.records) {
        expect(
          record.allocation.policy,
          AllocationPolicyIdentity(
            assigned: SchedulingAssignment.allocationPilot.id,
            effective: SchedulingAssignment.allocationPilot.id,
          ),
        );
      }
    },
  );

  test(
    'shadow evidence is what the census observed of each decision',
    () async {
      late AcquisitionJournal acquisition;
      final census = await runServiceCensus(
        player: player,
        sessions: sessions,
        playerSeed: 100,
        onClose: (session, _, _) => acquisition = session.acquisitionJournal,
      );
      final byDecision = <int, List<RequirementObservation>>{};
      for (final observation in census.observations) {
        byDecision.putIfAbsent(observation.decision, () => []).add(observation);
      }
      final ordinary = [
        for (final decision in census.decisions)
          if (decision.stage != 'acquisition') decision.decision,
      ];

      expect(ordinary, hasLength(census.records.length));
      for (final (index, record) in census.records.indexed) {
        final observed = byDecision[ordinary[index]]!;
        final allocation = record.allocation as AllocationObserved;
        expect(allocation.owedRequirementId, isNull);
        expect(
          allocation.evidence,
          AllocationEvidence(
            served: [
              for (final o in observed)
                if (o.served) o.requirementId,
            ],
            missed: [
              for (final o in observed)
                if (o.deferred) o.requirementId,
            ],
          ),
          reason: 'attempt $index',
        );
      }

      final offers = [
        for (final decision in census.decisions)
          if (decision.stage == 'acquisition') decision.decision,
      ];
      expect(offers, isNotEmpty);
      expect(acquisition.attempts, hasLength(offers.length));
      for (final (index, record) in acquisition.attempts.indexed) {
        final observed = byDecision[offers[index]]!;
        expect(
          (record.allocation as AllocationObserved).evidence,
          AllocationEvidence(
            served: const [],
            missed: [
              for (final o in observed)
                if (o.deferred) o.requirementId,
            ],
          ),
          reason: 'acquisition $index',
        );
      }
    },
  );
}
