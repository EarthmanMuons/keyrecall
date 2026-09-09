import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  /// A beginner working one scale and managing none of it.
  Future<PracticeSession> struggling(PracticeStore store) => openSession(
    store,
    materials: [fixtureMaterials.first],
    placement: PlacementTier.beginner,
  );

  /// An attempt that started and taught the model something without
  /// demonstrating a tempo, which is the state the floor check reads.
  Outcome managedNothing() => outcomeOf(
    retrieval: FactualRetrieval.notTested,
    quality: 0.1,
    tempoRatio: 0.3,
  );

  test('ordinary practice reaches supported work', () async {
    final session = await struggling(InMemoryPracticeStore(createdAt: t0));
    final presented = <Exercise>[];

    for (var slot = 0; slot < 12; slot++) {
      final at = t0.plusDays(0.5 * (slot + 1));
      final decision = await session.decideOutcome(at: at);
      if (decision is PresentedAcquisition) {
        // The floor it offers is one the learner has actually been asked for
        // and demonstrated nothing at, which is the whole of the entry rule.
        expect(presented, contains(decision.task.parent));
        expect(decision.task.timing, TimingDemand.unmetered);
        return;
      }
      final attempt = decision as PresentedAttempt;
      presented.add(attempt.exercise);
      await session.acknowledgePresentation();
      await session.closeWithOutcome(managedNothing(), observedWallTime: at);
    }

    fail('a learner who manages nothing was never offered supported work');
  });

  test('a first meeting is whatever placement and ranking make of it', () async {
    // Nothing about this material has been observed, so there is no reason yet
    // to ask its gentlest question. Somebody who arrived able to play is not
    // sent to the bottom of a family they may not need.
    final session = await struggling(InMemoryPracticeStore(createdAt: t0));
    final first =
        await session.decideOutcome(at: t0.plusDays(0.5)) as PresentedAttempt;

    expect(first.exercise.guidance, isNot(GuidanceContext.continuouslyCued));
  });

  test('the floor is asked once ordinary work there shows nothing', () async {
    // Evidence in the context and no frontier is a reason to find out whether
    // the minimum ordinary realization can be managed. It is not yet a reason
    // to remove the tempo from it, and it is asked of the context that showed
    // nothing rather than of every context at once.
    final session = await struggling(InMemoryPracticeStore(createdAt: t0));
    final seen = <Exercise>[];

    for (var slot = 0; slot < 12; slot++) {
      final at = t0.plusDays(0.5 * (slot + 1));
      final attempt = await session.decideOutcome(at: at) as PresentedAttempt;
      if (attempt.exercise.guidance == GuidanceContext.continuouslyCued) {
        // Ordinary work in this exact context came first and established
        // nothing, which is what asked for the floor.
        expect(
          seen.where(
            (earlier) =>
                earlier.material == attempt.exercise.material &&
                earlier.conditions.hands == attempt.exercise.conditions.hands,
          ),
          isNotEmpty,
        );
        return;
      }
      seen.add(attempt.exercise);
      await session.acknowledgePresentation();
      await session.closeWithOutcome(managedNothing(), observedWallTime: at);
    }

    fail('the declared floor was never asked for');
  });
}
