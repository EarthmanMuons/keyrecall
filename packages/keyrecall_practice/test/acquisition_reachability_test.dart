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
      await session.acknowledgePresentation(attempt.decision.attemptId);
      await session.closeWithOutcome(managedNothing(), observedWallTime: at);
    }

    fail('a learner who manages nothing was never offered supported work');
  });

  test('a hand is asked for ascending before up and down', () async {
    // Reversal is an added demand, and information gain alone made up and down
    // the first thing a hand was ever asked for.
    final session = await struggling(InMemoryPracticeStore(createdAt: t0));
    final seen = <Exercise>[];

    for (var slot = 0; slot < 8; slot++) {
      final at = t0.plusDays(0.5 * (slot + 1));
      final decision = await session.decideOutcome(at: at);
      if (decision is PresentedAcquisition) {
        await session.closeAcquisition(PerformanceTranscript.empty, at: at);
        continue;
      }
      final attempt = decision as PresentedAttempt;
      final exercise = attempt.exercise;
      if (exercise.conditions.direction == ExerciseDirection.upDown) {
        expect(
          seen.where(
            (earlier) =>
                earlier.material == exercise.material &&
                earlier.conditions.hands == exercise.conditions.hands &&
                earlier.conditions.direction == ExerciseDirection.up,
          ),
          isNotEmpty,
          reason: 'up and down came before this hand was asked for ascending',
        );
      }
      seen.add(exercise);
      await session.acknowledgePresentation(attempt.decision.attemptId);
      await session.closeWithOutcome(managedNothing(), observedWallTime: at);
    }

    // Both hands were met, and neither was met with a reversal.
    expect(
      seen.map((exercise) => exercise.conditions.hands).toSet(),
      hasLength(greaterThan(1)),
    );
  });

  test('one parent does not take every slot after it stalls', () async {
    // A floor that qualifies goes on qualifying until it is managed. Without a
    // step aside the sitting stops interleaving at exactly the point the
    // learner is finding hardest.
    final session = await struggling(InMemoryPracticeStore(createdAt: t0));
    final offered = <String>[];

    for (var slot = 0; slot < 14; slot++) {
      final at = t0.plusDays(0.5 * (slot + 1));
      final decision = await session.decideOutcome(at: at);
      if (decision is PresentedAcquisition) {
        offered.add(decision.task.parent.toString());
        await session.closeAcquisition(PerformanceTranscript.empty, at: at);
        continue;
      }
      final attempt = decision as PresentedAttempt;
      offered.add('ordinary');
      await session.acknowledgePresentation(attempt.decision.attemptId);
      await session.closeWithOutcome(managedNothing(), observedWallTime: at);
    }

    expect(
      offered.where((entry) => entry != 'ordinary'),
      isNotEmpty,
      reason: 'supported work was never offered at all',
    );
    for (var i = 1; i < offered.length; i++) {
      if (offered[i] == 'ordinary') continue;
      expect(
        offered[i],
        isNot(offered[i - 1]),
        reason: 'the same parent was offered on consecutive opportunities',
      );
    }
  });

  test('a stalled parent comes back after one opportunity', () async {
    final session = await struggling(InMemoryPracticeStore(createdAt: t0));
    final offered = <String>[];

    for (var slot = 0; slot < 14; slot++) {
      final at = t0.plusDays(0.5 * (slot + 1));
      final decision = await session.decideOutcome(at: at);
      if (decision is PresentedAcquisition) {
        offered.add(decision.task.parent.toString());
        await session.closeAcquisition(PerformanceTranscript.empty, at: at);
        continue;
      }
      final attempt = decision as PresentedAttempt;
      offered.add('ordinary');
      await session.acknowledgePresentation(attempt.decision.attemptId);
      await session.closeWithOutcome(managedNothing(), observedWallTime: at);
    }

    // Stepping aside is a step, not a wait: a parent that is still stuck is
    // offered again rather than being finished with.
    final repeated = offered
        .where((entry) => entry != 'ordinary')
        .fold<Map<String, int>>({}, (counts, entry) {
          counts.update(entry, (count) => count + 1, ifAbsent: () => 1);
          return counts;
        });
    expect(repeated.values, anyElement(greaterThan(1)));
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
      await session.acknowledgePresentation(attempt.decision.attemptId);
      await session.closeWithOutcome(managedNothing(), observedWallTime: at);
    }

    fail('the declared floor was never asked for');
  });
}
