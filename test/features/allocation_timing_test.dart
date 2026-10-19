import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/practice/allocation_timing.dart';

void main() {
  test('the fold timing reads the history a decision would fold', () async {
    final placedAt = DateTime.utc(2026, 9, 30, 12);
    final session = await PracticeSession.open(
      store: InMemoryPracticeStore(),
      profile: Profile(
        id: 'timing',
        displayName: 'Timing',
        createdAt: placedAt,
        placement: PlacementTier.someExperience,
      ),
      materials: [
        ScaleMaterial('C', ScaleForm.major),
        ScaleMaterial('G', ScaleForm.major),
      ],
    );
    for (var slot = 0; slot < 3; slot++) {
      await session.decideOutcome(
        at: placedAt.add(Duration(minutes: 2 * (slot + 1))),
      );
      await session.closeUnmeasured(
        termination: AttemptTermination.inputInterrupted,
      );
    }

    final timing = timeAllocationFold(session, runs: 5);

    expect(timing.attempts, 3);
    expect(timing.history.observed, 3);
    expect(timing.median, lessThanOrEqualTo(timing.p95));
    expect(describeAllocationTiming(timing), contains('3 observed, 0 stale'));
  });
}
