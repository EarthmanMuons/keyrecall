import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final sessions = demoSessions(
    from: demoHistoryStart,
    until: demoHistoryStart.add(const Duration(days: 10)),
  );
  String journal(ServiceCensus census) => (AttemptJournal(
    JournalHeader(profileId: 'census', createdAt: demoHistoryStart),
  )..appendAll(census.records)).toJsonLines();

  test('ends where the next decision would have observed', () async {
    final ended = await runServiceCensus(
      player: PlayerArchetypes.developing,
      sessions: sessions,
    );
    final last = sessions.last;
    final continued = await runServiceCensus(
      player: PlayerArchetypes.developing,
      sessions: [
        ...sessions.take(sessions.length - 1),
        (start: last.start, slots: last.slots + 1),
      ],
    );

    final next = continued.observations.last.decision;
    final observed = {
      for (final o in continued.observations)
        if (o.decision == next) o.requirementId: o.covered,
    };
    expect(next, ended.decisions.length);
    expect({
      for (final r in ended.terminal) r.requirementId: r.covered,
    }, observed);
    expect(
      ServiceOutcomes.of(ended).covered.values.fold(0, (a, b) => a + b),
      observed.values.where((covered) => covered).length,
    );
  });

  test('finishing decides nothing and writes nothing', () async {
    final census = await runServiceCensus(
      player: PlayerArchetypes.developing,
      sessions: sessions,
    );
    final unfinished = ServiceCensus(
      census.observations,
      census.decisions,
      records: census.records,
    );

    expect(census.terminal, isNotEmpty);
    expect(unfinished.digest, census.digest);
    expect(census.records.length, lessThanOrEqualTo(census.decisions.length));
    expect(journal(unfinished), journal(census));
  });

  test('a run with no attempts ends with nothing covered', () async {
    final census = await runServiceCensus(
      player: PlayerArchetypes.developing,
      sessions: [(start: sessions.first.start, slots: 0)],
    );

    expect(census.records, isEmpty);
    expect(census.terminal, isNotEmpty);
    expect(census.terminal.where((r) => r.covered), isEmpty);
    expect(ServiceOutcomes.of(census).covered.values, everyElement(0));
  });

  test('settles a follow-through on the final attempt exactly once', () async {
    final followThrough = FollowThrough(
      RequirementAllocator(k: 2, protectionFloor: 0.6),
    );
    final census = await runServiceCensus(
      player: PlayerArchetypes.scaleStrongArpeggioWeak,
      sessions: sessions,
      intervention: followThrough,
    );

    expect(followThrough.events, isNotEmpty);
    for (final event in followThrough.events) {
      expect(event.journalIndex, lessThan(census.records.length));
      expect(event.outcome, isNotNull);
    }
  });
}
