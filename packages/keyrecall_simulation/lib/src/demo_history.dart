import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'python_compatible_random.dart';
import 'synthetic_performance.dart';
import 'synthetic_player.dart';

/// When demo history starts, fixed so every run produces the same history.
final DateTime demoHistoryStart = DateTime.utc(2026, 6);

/// When demo history ends.
final DateTime demoHistoryEnd = DateTime.utc(2026, 9, 29);

/// One day [practiceDemoHistory] practices on.
typedef DemoSession = ({DateTime start, int slots});

/// Practice days after [from] through [until], at the irregular pace a real
/// learner keeps.
///
/// Mostly evenings, fewer on weekends, with the occasional stretch away so the
/// history has gaps to return from. Days and hours are UTC, so the result
/// depends on [seed] and nothing else.
List<DemoSession> demoSessions({
  required DateTime from,
  required DateTime until,
  int seed = 0,
}) {
  final random = math.Random(seed);
  final first = from.toUtc();
  final last = until.toUtc();
  final sessions = <DemoSession>[];
  var awayUntil = first;
  for (
    var day = DateTime.utc(first.year, first.month, first.day + 1);
    !day.isAfter(last);
    day = DateTime.utc(day.year, day.month, day.day + 1)
  ) {
    if (day.isBefore(awayUntil)) continue;
    if (random.nextDouble() < 0.025) {
      awayUntil = day.add(Duration(days: 3 + random.nextInt(8)));
      continue;
    }
    final weekend = day.weekday >= DateTime.saturday;
    if (random.nextDouble() > (weekend ? 0.45 : 0.7)) continue;
    final start = day.add(
      Duration(
        hours: weekend ? 10 + random.nextInt(6) : 18 + random.nextInt(4),
        minutes: random.nextInt(60),
      ),
    );
    if (start.isAfter(last)) continue;
    sessions.add((start: start, slots: 8 + random.nextInt(23)));
  }
  return sessions;
}

/// Practices [profile] as [player] through [sessions], writing to [store].
///
/// Through a real [PracticeSession], so the scheduler chooses every exercise
/// and every record is one the app could have written. Only the person at the
/// instrument is synthetic. Attempts are spaced a minute or two apart, the
/// time one actually takes, and ids are numbered rather than random, so the
/// same inputs write the same journal. [onSession] reports each session as it
/// closes.
Future<void> practiceDemoHistory({
  required PracticeStore store,
  required Profile profile,
  required SyntheticPlayer player,
  required List<TechnicalMaterial> materials,
  required List<DemoSession> sessions,
  int seed = 0,
  void Function(int completed, int total)? onSession,
}) async {
  final playing = player.begin();
  final random = PythonCompatibleRandom(seed);
  final spacing = math.Random(seed);
  var ids = 0;

  for (final (index, (:start, :slots)) in sessions.indexed) {
    playing.restUntil(start);
    final session = await PracticeSession.open(
      store: store,
      profile: profile,
      materials: materials,
      sessionId: 'demo-session-$index',
      nextId: () => 'demo-${ids++}',
    );
    var at = start;
    for (var slot = 0; slot < slots; slot++) {
      at = at.add(Duration(seconds: 50 + spacing.nextInt(100)));
      final decision = await session.decideOutcome(at: at);
      if (decision case PresentedAttempt(:final exercise, decision: final d)) {
        await session.acknowledgePresentation(d.attemptId);
        await session.closeWithOutcome(
          playing.play(exercise, random),
          observedWallTime: at,
        );
      } else if (decision case PresentedAcquisition(:final task)) {
        await session.closeAcquisition(
          performAcquisition(state: playing, task: task, rng: random),
          at: at,
        );
      } else {
        break;
      }
    }
    await session.saveCheckpoint();
    onSession?.call(index + 1, sessions.length);
  }
}
