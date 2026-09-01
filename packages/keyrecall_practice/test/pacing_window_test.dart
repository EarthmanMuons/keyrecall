import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  test(
    'reopening carries the allocation window over from the journal',
    () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      for (var i = 0; i < 4; i++) {
        final presented = await session.decide(at: t0.plusDays(0.5 + i));
        await session.closeWithOutcome(
          outcomeFor(presented!.exercise, succeeded: i.isEven),
        );
      }

      final reopened = await openSession(store, sessionId: 'session-2');
      final observed = reopened.session.recentFamilies;

      expect(observed, hasLength(reopened.journal.length));
      expect(
        [for (final observation in observed) observation.families],
        [
          for (final record in reopened.journal.records)
            handMotionFamilies(record.exercise),
        ],
      );
      expect(
        [for (final observation in observed) observation.productive],
        [
          for (final record in reopened.journal.records)
            switch (record.closure.measurement) {
              Measured(:final outcome) => learner.executionWasManaged(outcome),
              MeasurementUnavailable() => false,
            },
        ],
      );
    },
  );

  test('a sitting with no history starts unpressured', () async {
    final session = await openSession(InMemoryPracticeStore(createdAt: t0));

    expect(session.session.recentFamilies, isEmpty);
    expect(
      pressuredFamilies(
        window: session.session.recentFamilies,
        config: v1SchedulerConfig.pacing!,
      ),
      isEmpty,
    );
  });
}
