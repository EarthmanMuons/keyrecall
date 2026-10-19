import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

void main() {
  group('the allocation choice', () {
    // Candidates are named for the requirement they serve, and rank in the
    // order of their names.
    AllocationChoice<String>? choose({
      String winner = 'w',
      bool winnerProtected = false,
      Map<String, int> waiting = const {},
      Map<String, String>? best,
      int breadth = 5,
      int k = 2,
    }) => allocate<String>(
      winner: winner,
      winnerProtected: winnerProtected,
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
    WaitCounters fold(List<AllocationEvidence> evidence) =>
        evidence.fold(const WaitCounters.empty(), (c, e) => c.advance(e));

    test('counts missed opportunities and clears on service', () {
      final counters = fold([
        AllocationEvidence(served: [], missed: ['r', 's']),
        AllocationEvidence(served: ['r'], missed: ['s']),
        AllocationEvidence(served: [], missed: ['r']),
      ]);

      expect(counters['r'], 1);
      expect(counters['s'], 2);
    });

    test('keeps a requirement the evidence does not name', () {
      final counters = fold([
        AllocationEvidence(served: [], missed: ['r', 's']),
        AllocationEvidence(served: [], missed: ['r']),
        AllocationEvidence(served: [], missed: []),
      ]);

      expect(counters['s'], 1);
      expect(counters.asMap, {'r': 2, 's': 1});
    });

    test('keeps the order requirements began waiting in', () {
      final counters = fold([
        AllocationEvidence(served: [], missed: ['a', 'b']),
        AllocationEvidence(served: [], missed: ['b', 'a']),
      ]);

      expect(counters.asMap.keys, ['a', 'b']);
    });
  });

  test('a blocked slot is not an allocation opportunity', () {
    final blocked = SelectionBlocked(
      traces: const [],
      selectable: const [],
      pacing: const PacingDecision.inactive([]),
      introductions: IntroductionDecision.inactive(const []),
      reason: BlockedReason.admissionExhausted,
    );
    expect(isAllocationOpportunity(blocked), isFalse);
  });
}
