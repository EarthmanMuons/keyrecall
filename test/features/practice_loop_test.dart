import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall/features/practice/practice_providers.dart';
import 'package:keyrecall/features/practice/reported_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('keyrecall_loop_test');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  /// A container over the same storage, as a fresh launch would see it.
  ProviderContainer launch() {
    final container = ProviderContainer(
      overrides: [storageRootProvider.overrideWith((ref) async => root)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<PracticeLoopState> loopOf(ProviderContainer container) =>
      container.read(practiceLoopProvider.future);

  test(
    'a first launch reaches a presented exercise with no decisions asked',
    () async {
      final loop = await loopOf(launch());

      expect(
        loop.profile.displayName,
        isNotEmpty,
        reason: 'an install gets a profile without anyone choosing one',
      );
      expect(loop.presented, isNotNull);
      expect(loop.pending, isNull);
      expect(loop.attemptsRecorded, 0);
    },
  );

  test(
    'reporting a result commits it and presents the next exercise',
    () async {
      final container = launch();
      final first = await loopOf(container);
      final firstId = first.presented!.decision.attemptId;

      await container
          .read(practiceLoopProvider.notifier)
          .report(ReportedResult.clean);
      final next = container.read(practiceLoopProvider).value!;

      expect(next.lastCommitted, isNotNull);
      expect(next.lastCommitted!.identity.attemptId, firstId);
      expect(next.attemptsRecorded, 1);
      expect(next.presented, isNotNull);
      expect(next.presented!.decision.attemptId, isNot(firstId));
      expect(next.pending, isNull);
    },
  );

  test('a second report while one is in flight does nothing at all', () async {
    // The transaction below is safe to retry, which is not the same as being
    // safe to enter twice at once. Entering twice does not corrupt history,
    // because the journal refuses the duplicate, but it refuses it by
    // throwing: the second pass surfaces as a failure the person never caused
    // and cannot act on. Nothing down there serializes writers, so the loop
    // has to.
    final container = launch();
    final before = await loopOf(container);
    expect(before.session.session.attemptsThisSession, 1);

    final seen = <AsyncValue<PracticeLoopState>>[];
    final subscription = container.listen(practiceLoopProvider, (_, next) {
      seen.add(next);
    });
    addTearDown(subscription.close);

    final notifier = container.read(practiceLoopProvider.notifier);
    await Future.wait([
      notifier.report(ReportedResult.clean),
      notifier.report(ReportedResult.clean),
    ]);
    final after = container.read(practiceLoopProvider).value!;

    expect(
      seen.whereType<AsyncError<PracticeLoopState>>(),
      isEmpty,
      reason: 'a second tap must not fail the screen',
    );
    expect(after.session.journal.records, hasLength(1));
    expect(
      after.session.session.attemptsThisSession,
      2,
      reason: 'one commit and one new decision, not two of each',
    );
    expect(after.presented, isNotNull);
  });

  test('history survives a relaunch', () async {
    final first = launch();
    await loopOf(first);
    await first
        .read(practiceLoopProvider.notifier)
        .report(ReportedResult.shaky);
    first.dispose();

    final second = await loopOf(launch());

    expect(
      second.attemptsRecorded,
      1,
      reason: 'the journal is the source of truth, not the process',
    );
  });

  group('an attempt interrupted before it was answered', () {
    test(
      'surfaces as pending on the next launch, presenting nothing new',
      () async {
        // The decision is durable before the exercise is shown, so abandoning
        // the process here is exactly the crash the transaction is built for.
        final crashed = launch();
        final shown = await loopOf(crashed);
        final shownId = shown.presented!.decision.attemptId;
        crashed.dispose();

        final relaunched = await loopOf(launch());

        expect(relaunched.pending, isNotNull);
        expect(relaunched.pending!.attemptId, shownId);
        expect(
          relaunched.presented,
          isNull,
          reason: 'nothing new is decided while an unanswered attempt stands',
        );
        expect(relaunched.attemptsRecorded, 0);
      },
    );

    test(
      'can be answered, and lands in history under its original id',
      () async {
        final crashed = launch();
        final shownId = (await loopOf(crashed)).presented!.decision.attemptId;
        crashed.dispose();

        final container = launch();
        await loopOf(container);
        await container
            .read(practiceLoopProvider.notifier)
            .report(ReportedResult.brokeDown);
        final resumed = container.read(practiceLoopProvider).value!;

        expect(resumed.attemptsRecorded, 1);
        expect(resumed.lastCommitted!.identity.attemptId, shownId);
        expect(resumed.pending, isNull);
        expect(resumed.presented, isNotNull);
      },
    );

    test('can be abandoned, recording nothing', () async {
      final crashed = launch();
      await loopOf(crashed);
      crashed.dispose();

      final container = launch();
      await loopOf(container);
      await container.read(practiceLoopProvider.notifier).abandonPending();
      final resolved = container.read(practiceLoopProvider).value!;

      expect(resolved.pending, isNull);
      expect(
        resolved.attemptsRecorded,
        0,
        reason: 'nothing observed an outcome, so history claims none',
      );
      expect(resolved.presented, isNotNull);
    });

    test('is never answered twice, whatever the relaunch finds', () async {
      // A commit is followed immediately by the next decision, so a relaunch
      // here finds that new decision pending. What must not happen is the
      // committed attempt being folded in a second time: the attempt id is the
      // journal's idempotency key precisely so this is safe.
      final container = launch();
      await loopOf(container);
      await container
          .read(practiceLoopProvider.notifier)
          .report(ReportedResult.clean);
      final committed = container
          .read(practiceLoopProvider)
          .value!
          .lastCommitted!
          .identity
          .attemptId;
      container.dispose();

      final relaunched = await loopOf(launch());

      expect(relaunched.attemptsRecorded, 1);
      expect(relaunched.pending, isNotNull);
      expect(
        relaunched.pending!.attemptId,
        isNot(committed),
        reason: 'the pending slot holds the next attempt, not the answered one',
      );
      expect(
        relaunched.session.journal.records.single.identity.attemptId,
        committed,
      );
    });
  });

  test('a fully cued exercise never records a retrieval observation', () {
    // Not a UI concern but a correctness one: the buttons must not be able to
    // manufacture evidence the guidance level rules out.
    final cued = ReportedResult.clean;
    for (final result in ReportedResult.values) {
      expect(
        result.toOutcome(_cuedExercise()).retrieval.isTested,
        isFalse,
        reason: '${result.name} claimed a retrieval test that never happened',
      );
    }
    expect(cued.toOutcome(_unguidedExercise()).retrieval.isTested, isTrue);
  });
}

Exercise _exerciseGuidedBy(GuidanceContext guidance) => Exercise.linear(
  material: TechnicalMaterial('C', ScaleForm.major),
  hands: HandConfiguration.together,
  guidance: guidance,
);

Exercise _cuedExercise() => _exerciseGuidedBy(GuidanceContext.continuouslyCued);

Exercise _unguidedExercise() => _exerciseGuidedBy(GuidanceContext.unguided);
