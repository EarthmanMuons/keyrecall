import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final from = DateTime.utc(2026, 3, 1);
  final until = DateTime.utc(2026, 7, 1);

  test('sessions fall inside the span, in order, one a day at most', () {
    final sessions = demoSessions(from: from, until: until);
    final days = sessions.map((session) => CalendarDay.localOf(session.start));

    expect(sessions, isNotEmpty);
    expect(sessions.first.start.isAfter(from), isTrue);
    expect(sessions.last.start.isAfter(until), isFalse);
    expect(days.toSet(), hasLength(sessions.length));
    expect(days.toList(), orderedEquals(days.toList()..sort()));
  });

  test('the history replays into a fluency day per session', () async {
    final sessions = demoSessions(
      from: from,
      until: from.add(const Duration(days: 10)),
    );
    final store = InMemoryPracticeStore(createdAt: from);
    final profile = Profile(
      id: 'demo',
      displayName: 'Demo',
      createdAt: from,
      placement: PlayerArchetypes.developing.placement,
    );
    var reported = 0;

    await practiceDemoHistory(
      store: store,
      profile: profile,
      player: PlayerArchetypes.developing,
      materials: allPracticeMaterials,
      sessions: sessions,
      onSession: (completed, _) => reported = completed,
    );

    final history = await readFluencyHistory(
      store,
      profile.id,
      partition: DayPartition.local(),
      onSaveFailure: (error, stackTrace) => fail('$error'),
    );
    expect(reported, sessions.length);
    expect(history.days, hasLength(sessions.length));
    expect(history.days.expand((day) => day.tempos), isNotEmpty);
  });
}
