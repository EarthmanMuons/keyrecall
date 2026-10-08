import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final from = demoHistoryStart;

  test('sessions fall inside the span, in order, one a day at most', () {
    final sessions = demoSessions(from: from, until: demoHistoryEnd);
    final days = [
      for (final (:start, slots: _) in sessions)
        DateTime.utc(start.year, start.month, start.day),
    ];

    expect(sessions, isNotEmpty);
    expect(sessions.first.start.isAfter(from), isTrue);
    expect(sessions.last.start.isAfter(demoHistoryEnd), isFalse);
    expect(days.toSet(), hasLength(sessions.length));
    expect(days, orderedEquals([...days]..sort()));
  });

  Future<InMemoryPracticeStore> practiced(
    Profile profile,
    List<DemoSession> sessions, {
    void Function(int completed, int total)? onSession,
  }) async {
    final store = InMemoryPracticeStore(createdAt: from);
    await practiceDemoHistory(
      store: store,
      profile: profile,
      player: PlayerArchetypes.developing,
      materials: allPracticeMaterials,
      sessions: sessions,
      onSession: onSession,
    );
    return store;
  }

  final profile = Profile(
    id: 'demo',
    displayName: 'Demo',
    createdAt: from,
    placement: PlayerArchetypes.developing.placement,
  );
  final sessions = demoSessions(
    from: from,
    until: from.add(const Duration(days: 10)),
  );

  test('the history replays into a fluency day per session', () async {
    var reported = 0;
    final store = await practiced(
      profile,
      sessions,
      onSession: (completed, _) => reported = completed,
    );

    final history = await readFluencyHistory(
      store,
      profile.id,
      partition: DayPartition.utc,
      onSaveFailure: (error, stackTrace) => fail('$error'),
    );
    expect(reported, sessions.length);
    expect(history.days, hasLength(sessions.length));
    expect(history.days.expand((day) => day.tempos), isNotEmpty);
  });

  test('the same inputs write the same journal', () async {
    Future<String> journal() async => (await (await practiced(
      profile,
      sessions,
    )).loadJournal(profile.id)).toJsonLines();

    expect(await journal(), await journal());
  });
}
