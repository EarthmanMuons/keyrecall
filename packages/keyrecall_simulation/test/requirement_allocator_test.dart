import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  group('the allocation choice', () {
    // Candidates are named for the requirement they serve, and rank in the
    // order of their names.
    AllocationChoice<String>? choose({
      String winner = 'w',
      bool winnerProtected = false,
      List<String> protectedCandidates = const [],
      Map<String, int> waiting = const {},
      Map<String, String>? best,
      int breadth = 5,
      int k = 2,
    }) => allocate<String>(
      winner: winner,
      winnerProtected: winnerProtected,
      protectedCandidates: protectedCandidates,
      waiting: waiting,
      bestByRequirement: best ?? {for (final id in waiting.keys) id: id},
      breadth: breadth,
      k: k,
      compare: (a, b) => a.compareTo(b),
      serves: (id, candidate) => candidate == id,
    );

    test('leaves the slot while nothing is owed', () {
      expect(choose(waiting: {'a': 10}), isNull);
    });

    test('owes relative to how much is actionable', () {
      expect(choose(waiting: {'a': 9}, breadth: 5), isNull);
      expect(choose(waiting: {'a': 9}, breadth: 4)?.requirementId, 'a');
    });

    test('leaves a winner that already serves owed work, or is protected', () {
      expect(choose(winner: 'a', waiting: {'a': 20}), isNull);
      expect(choose(winnerProtected: true, waiting: {'a': 20}), isNull);
    });

    test('lets protected reviews go first, ranked among themselves', () {
      final choice = choose(
        protectedCandidates: ['p', 'q'],
        waiting: {'a': 20},
      );
      expect(choice?.candidate, 'q');
      expect(choice?.reason, 'protected');
    });

    test('serves the most overdue, rank breaking ties', () {
      expect(choose(waiting: {'a': 30, 'b': 20})?.requirementId, 'a');
      expect(choose(waiting: {'a': 30, 'b': 30})?.requirementId, 'b');
    });

    test('promises nothing an owed requirement cannot be served by', () {
      expect(choose(waiting: {'a': 30}, best: const {}), isNull);
      expect(
        choose(waiting: {'a': 30, 'b': 11}, best: {'b': 'b'})?.requirementId,
        'b',
      );
    });
  });

  group('waiting', () {
    RequirementObservation observed(
      String id, {
      bool due = true,
      bool actionable = true,
      bool served = false,
    }) => RequirementObservation(
      decision: 0,
      requirementId: id,
      materialId: 'C_MAJOR',
      familyId: 'SCALE',
      due: due,
      covered: false,
      admitted: actionable,
      fullyRanked: actionable,
      materialRanked: actionable,
      heldForRecovery: false,
      servedMaterial: served,
      served: served,
    );

    test('counts opportunities, while the journal counter counts due time', () {
      final allocator = RequirementAllocator(k: 2, protectionFloor: 0.6)
        ..record([observed('r')])
        ..record([observed('r', actionable: false)])
        ..record([observed('r')]);

      expect(allocator.waitingFor('r'), 2);
      expect(allocator.journalWaitingFor('r'), 3);
    });

    test('clears on service, and leaves with the scope', () {
      final allocator = RequirementAllocator(k: 2, protectionFloor: 0.6)
        ..record([observed('r'), observed('s')])
        ..record([observed('r', served: true), observed('s')])
        ..record([observed('r')]);

      expect(allocator.waitingFor('r'), 1);
      expect(allocator.waitingFor('s'), 0);
      expect(allocator.journalWaitingFor('s'), 0);
    });
  });

  group('a seeded run', () {
    final sessions = demoSessions(
      from: demoHistoryStart,
      until: demoHistoryStart.add(const Duration(days: 12)),
    );

    test('changes nothing while nothing is owed', () async {
      final baseline = await runServiceCensus(
        player: PlayerArchetypes.developing,
        sessions: sessions,
      );
      final unreachable = await runServiceCensus(
        player: PlayerArchetypes.developing,
        sessions: sessions,
        intervention: RequirementAllocator(k: 1 << 20, protectionFloor: 0),
      );

      expect(unreachable.substitutions, isEmpty);
      String journal(ServiceCensus census) => (AttemptJournal(
        JournalHeader(profileId: 'census', createdAt: demoHistoryStart),
      )..appendAll(census.records)).toJsonLines();
      expect(journal(unreachable), journal(baseline));
    });

    test(
      "takes only ranking's slots, for work that survived selection",
      () async {
        final census = await runServiceCensus(
          player: PlayerArchetypes.developing,
          sessions: sessions,
          intervention: RequirementAllocator(k: 1, protectionFloor: 0.7),
        );

        expect(census.substitutions, isNotEmpty);
        for (final substitution in census.substitutions) {
          expect(substitution.displacedStage, SelectionStage.ranking);
          expect(substitution.promotedSelectable, isTrue);
          expect(substitution.promotedFullyEligible, isTrue);
          expect(substitution.promotedServesRequirement, isTrue);
        }
        const learner = LearnerModel();
        expect(
          replayJournal(
            AttemptJournal(
              JournalHeader(profileId: 'census', createdAt: demoHistoryStart),
            )..appendAll(census.records),
            model: learner,
            initial: learner.placementState(
              PlacementTier.beginner,
              at: demoHistoryStart,
            ),
          ).isFaithful,
          isTrue,
        );
      },
    );
  });
}
