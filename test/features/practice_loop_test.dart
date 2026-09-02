import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/attempt_transcript.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryProfileRepository profiles;
  late InMemoryPracticeStore practice;

  setUp(() {
    profiles = InMemoryProfileRepository();
    practice = InMemoryPracticeStore();
  });

  /// A container over the same storage, as a fresh launch would see it.
  ProviderContainer launch() {
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) async => profiles),
        practiceStoreProvider.overrideWith((ref) async => practice),
      ],
    );
    addTearDown(container.dispose);
    // The synthetic instrument, rather than the MIDI stack a test has no
    // radio for. Nothing here plays it: what closing an attempt records is
    // what arrived, and nothing arriving is a performance like any other.
    container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
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
    'finishing an attempt commits it and presents the next exercise',
    () async {
      final container = launch();
      await place(container);
      final first = await loopOf(container);
      final firstId = first.presented!.decision.attemptId;

      await container.read(practiceLoopProvider.notifier).finish();
      final next = container.read(practiceLoopProvider).value!;

      expect(next.lastCommitted, isNotNull);
      expect(next.lastCommitted!.identity.attemptId, firstId);
      expect(next.attemptsRecorded, 1);
      expect(next.presented, isNotNull);
      expect(next.presented!.decision.attemptId, isNot(firstId));
      expect(next.pending, isNull);
    },
  );

  test('a second finish while one is in flight does nothing at all', () async {
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
    await Future.wait([notifier.finish(), notifier.finish()]);
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

  test('a timeout with nothing played commits no evidence', () async {
    // Silence is only a performance if somebody says it was, and a timeout is
    // nobody saying anything: measuring it would manufacture the retrieval
    // failure the three-valued encoding exists to prevent.
    final container = launch();
    await place(container);
    await loopOf(container);

    await container
        .read(practiceLoopProvider.notifier)
        .finish(termination: AttemptTermination.inactivityTimeout);
    final closed = container.read(practiceLoopProvider).value!.lastCommitted!;

    expect(closed.closure.termination, AttemptTermination.inactivityTimeout);
    expect(
      closed.closure.measurement,
      isA<MeasurementUnavailable>().having(
        (unavailable) => unavailable.reason,
        'reason',
        MeasurementUnavailableReason.nothingPlayed,
      ),
    );
  });

  test('an input reset interrupts the attempt without evidence', () async {
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) async => profiles),
        practiceStoreProvider.overrideWith((ref) async => practice),
        attemptTranscriptProvider.overrideWith(_InterruptedCapture.new),
      ],
    );
    addTearDown(container.dispose);
    await place(container);
    final before = await loopOf(container);
    final learnerBefore = learnerStateHash(before.session.state);
    expect(container.read(attemptTranscriptProvider).length, 3);
    await container.read(practiceLoopProvider.notifier).finish();
    final after = container.read(practiceLoopProvider).value!;
    final closed = after.lastCommitted!;

    expect(closed.closure.termination, AttemptTermination.inputInterrupted);
    expect(
      closed.closure.measurement,
      isA<MeasurementUnavailable>().having(
        (unavailable) => unavailable.reason,
        'reason',
        MeasurementUnavailableReason.inputInterrupted,
      ),
    );
    expect(learnerStateHash(after.session.state), learnerBefore);
  });

  test('history survives a relaunch', () async {
    final first = launch();
    await place(first);
    await loopOf(first);
    await first.read(practiceLoopProvider.notifier).finish();
    first.dispose();

    final second = await loopOf(launch());

    expect(
      second.attemptsRecorded,
      1,
      reason: 'the journal is the source of truth, not the process',
    );
  });

  test('erasing a loaded loop targets the profile on screen', () async {
    final repository = InMemoryProfileRepository();
    final store = _RecordingEraseStore();
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) async => repository),
        practiceStoreProvider.overrideWith((ref) async => store),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(profileRosterProvider.notifier)
        .place(PlacementTier.someExperience);
    final loop = await loopOf(container);
    final other = await repository.create(
      displayName: 'Bob',
      placement: PlacementTier.beginner,
    );
    await repository.select(other.id);

    await container.read(practiceLoopProvider.notifier).eraseHistory();

    expect(store.erased, [loop.profile.id]);
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
        await container.read(practiceLoopProvider.notifier).finish();
        final resumed = container.read(practiceLoopProvider).value!;

        expect(resumed.attemptsRecorded, 1);
        expect(resumed.lastCommitted!.identity.attemptId, shownId);
        expect(resumed.pending, isNull);
        expect(resumed.presented, isNotNull);
      },
    );

    test('is never answered twice, whatever the relaunch finds', () async {
      // A commit is followed immediately by the next decision, so a relaunch
      // here finds that new decision pending. What must not happen is the
      // committed attempt being folded in a second time: the attempt id is the
      // journal's idempotency key precisely so this is safe.
      final container = launch();
      await place(container);
      await loopOf(container);
      await container.read(practiceLoopProvider.notifier).finish();
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
}

class _InterruptedCapture extends AttemptTranscriptNotifier {
  @override
  AttemptCapture build() {
    final material = TechnicalMaterial('C', ScaleForm.major);
    var transcript = PerformanceTranscript.empty;
    for (final (index, midiNote) in [60, 62, 64].indexed) {
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: material),
        timestampMs: 1000 + index * 100,
      );
    }
    return AttemptCapture(transcript: transcript, isInterrupted: true);
  }
}

class _RecordingEraseStore extends InMemoryPracticeStore {
  final List<String> erased = [];

  @override
  Future<void> erase(String profileId) async {
    erased.add(profileId);
    await super.erase(profileId);
  }
}
