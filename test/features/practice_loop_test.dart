import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

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

  /// Answers the placement question, which is what creates the learner.
  ///
  /// The loop refuses to run on an install nobody has been placed on, so
  /// every test here starts where the first-run screen leaves the app.
  Future<void> place(
    ProviderContainer container, [
    PlacementTier tier = PlacementTier.someExperience,
  ]) => container.read(profileRosterProvider.notifier).place(tier);

  Future<PracticeLoopState> loopOf(ProviderContainer container) =>
      container.read(practiceLoopProvider.future);

  test('an install nobody has been placed on presents nothing', () async {
    // The loop will not conjure a learner to have somebody to run as: the
    // placement that learner would start from is one nobody chose and nobody
    // could change. The first-run screen is what resolves it.
    await expectLater(loopOf(launch()), throwsA(isA<StateError>()));
  });

  test(
    'placing the install reaches an exercise, asking nothing else',
    () async {
      final container = launch();
      await place(container, PlacementTier.beginner);

      final loop = await loopOf(container);

      expect(loop.profile.displayName, isNotEmpty);
      expect(
        loop.profile.placement,
        PlacementTier.beginner,
        reason:
            'the prior the whole history will be read against is the one '
            'that was answered for, not a house default',
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
      await place(container);
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
    await place(container);
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
    await place(first);
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
        await place(crashed);
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
        await place(crashed);
        final shownId = (await loopOf(crashed)).presented!.decision.attemptId;
        crashed.dispose();

        final container = launch();
        await place(container);
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
      await place(crashed);
      await loopOf(crashed);
      crashed.dispose();

      final container = launch();
      await place(container);
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
      await place(container);
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

  test('erasing recovers a journal this build cannot replay', () async {
    final before = launch();
    await place(before);
    final started = await loopOf(before);
    await before
        .read(practiceLoopProvider.notifier)
        .report(ReportedResult.clean);

    // The same history, recorded under the model that was live before the
    // tempo attribution change.
    final journal = File('${root.path}/${started.profile.id}/journal.jsonl');
    // Whatever this build calls its model, rewritten to one it does not run.
    journal.writeAsStringSync(
      journal.readAsStringSync().replaceAll(
        '"${v1LearnerParams.modelVersion}"',
        '"a-model-this-build-does-not-have"',
      ),
    );

    final after = launch();
    Object? refused;
    try {
      await loopOf(after);
    } on Object catch (error) {
      refused = error;
    }
    expect(
      refused,
      isA<JournalFormatException>(),
      reason: 'replay must refuse a model it did not run',
    );

    await after
        .read(practiceLoopProvider.notifier)
        .eraseHistory()
        .timeout(const Duration(seconds: 5));

    final recovered = await loopOf(after);
    expect(recovered.exercise, isNotNull);
    expect(recovered.attemptsRecorded, 0);
  });
}

Exercise _exerciseGuidedBy(GuidanceContext guidance) => Exercise.linear(
  material: TechnicalMaterial('C', ScaleForm.major),
  hands: HandConfiguration.together,
  guidance: guidance,
);

Exercise _cuedExercise() => _exerciseGuidedBy(GuidanceContext.continuouslyCued);

Exercise _unguidedExercise() => _exerciseGuidedBy(GuidanceContext.unguided);
