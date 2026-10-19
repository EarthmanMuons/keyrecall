import 'package:keyrecall_practice/keyrecall_practice.dart';

/// What folding a session's history into allocation's waiting counters costs
/// on this device, and what that history holds.
typedef AllocationTiming = ({
  int attempts,
  int acquisitionAttempts,
  AllocationHistory history,
  Duration median,
  Duration p95,
});

/// Folds [session]'s logs [runs] times, the work a decision does each time
/// history has grown since the last.
AllocationTiming timeAllocationFold(PracticeSession session, {int runs = 31}) {
  final elapsed = <Duration>[];
  late AllocationHistory history;
  for (var run = 0; run < runs; run++) {
    final watch = Stopwatch()..start();
    history = AllocationHistory.of(session.journal, session.acquisitionJournal);
    elapsed.add(watch.elapsed);
  }
  elapsed.sort();
  return (
    attempts: session.journal.length,
    acquisitionAttempts: session.acquisitionJournal.attempts.length,
    history: history,
    median: elapsed[elapsed.length ~/ 2],
    p95: elapsed[((elapsed.length - 1) * 0.95).round()],
  );
}

/// [timing] in the lines the developer screen shows.
List<String> describeAllocationTiming(AllocationTiming timing) {
  String ms(Duration value) =>
      '${(value.inMicroseconds / 1000).toStringAsFixed(1)} ms';
  final history = timing.history;
  return [
    'fold median ${ms(timing.median)}, p95 ${ms(timing.p95)}',
    '${timing.attempts} attempts, '
        '${timing.acquisitionAttempts} acquisition attempts',
    '${history.observed} observed, ${history.staleDecisions} stale',
    for (final MapEntry(:key, :value) in history.gaps.entries)
      '${key.id}: $value',
    '${history.counters.asMap.length} requirements waiting',
  ];
}
