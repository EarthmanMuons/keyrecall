import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  test('a blocked decision never becomes a pending attempt', () async {
    final session = await openSession(
      InMemoryPracticeStore(createdAt: t0),
      pipeline: pipelineCappedAt(1),
    );
    final first = await session.decideOutcome(at: t0.plusDays(0.5));
    expect(first, isA<PresentedAttempt>());
    await session.closeWithOutcome(outcomeOf());

    final blocked = await session.decideOutcome(at: t0.plusDays(1));

    expect(blocked, isA<PracticeBlocked>());
    expect(
      (blocked as PracticeBlocked).reason,
      BlockedReason.admissionExhausted,
    );
    expect(session.pending, isNull);
    expect(session.hasOutstandingAttempt, isFalse);
  });
}
