import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final sessions = demoSessions(
    from: demoHistoryStart,
    until: demoHistoryStart.add(const Duration(days: 12)),
  );
  String journal(ServiceCensus census) => (AttemptJournal(
    JournalHeader(profileId: 'census', createdAt: demoHistoryStart),
  )..appendAll(census.records)).toJsonLines();

  test('changes nothing while disabled', () async {
    final allocated = await runServiceCensus(
      player: PlayerArchetypes.scaleStrongArpeggioWeak,
      sessions: sessions,
      intervention: RequirementAllocator(k: 2, protectionFloor: 0.6),
    );
    final counted = FollowThrough(
      RequirementAllocator(k: 2, protectionFloor: 0.6),
      enabled: false,
    );
    final disabled = await runServiceCensus(
      player: PlayerArchetypes.scaleStrongArpeggioWeak,
      sessions: sessions,
      intervention: counted,
    );

    expect(counted.events, isEmpty);
    expect(counted.waiting['available'], greaterThan(0));
    expect(journal(disabled), journal(allocated));
  });

  test('follows each strand through once, with a timing-valid realization that '
      'survived selection', () async {
    final followThrough = FollowThrough(
      RequirementAllocator(k: 2, protectionFloor: 0.6),
    );
    final census = await runServiceCensus(
      player: PlayerArchetypes.scaleStrongArpeggioWeak,
      sessions: sessions,
      intervention: followThrough,
    );

    final events = followThrough.events;
    expect(events, isNotEmpty);
    expect({for (final e in events) e.strand}, hasLength(events.length));
    expect(census.records, hasLength(census.decisions.length));
    for (final event in events) {
      final played = census.records[event.decision].exercise;
      expect(executionContextOf(played), event.strand);
      expect(TimingCapacity.of(played).supportsMotorScore, isTrue);
      expect(event.outcome, isNotNull);
    }
    final given = [
      for (final s in census.substitutions)
        if (s.reason == 'follow-through') s,
    ];
    expect(given, hasLength(events.length));
    for (final substitution in given) {
      expect(substitution.displacedStage, SelectionStage.ranking);
      expect(substitution.promotedSelectable, isTrue);
      expect(substitution.promotedFullyEligible, isTrue);
      expect(substitution.promotedServesRequirement, isTrue);
    }
  });
}
