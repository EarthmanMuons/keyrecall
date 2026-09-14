import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/attempt_transcript.dart';
import 'package:keyrecall/features/practice/practice_failure.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';

import '../support/scheduler_override.dart';

/// One property, instantiated at every boundary a result crosses:
///
/// > No result produced under one session generation may publish state, close
/// > an attempt, or schedule work for another.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryProfileRepository profiles;
  late PracticeStore practice;

  setUp(() {
    profiles = InMemoryProfileRepository();
    practice = InMemoryPracticeStore();
  });

  ProviderContainer launch() {
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) async => profiles),
        inProcessScheduling,
        practiceStoreProvider.overrideWith((ref) async => practice),
      ],
    );
    addTearDown(container.dispose);
    container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
    return container;
  }

  Future<PracticeLoopState> loopOf(ProviderContainer container) =>
      container.read(practiceLoopProvider.future);

  Future<void> place(ProviderContainer container) => container
      .read(profileRosterProvider.notifier)
      .place(PlacementTier.beginner);

  /// Practices as somebody else, which is what replaces the open sitting.
  Future<void> switchProfile(ProviderContainer container) async {
    await container
        .read(profileRosterProvider.notifier)
        .add('Bo', PlacementTier.someExperience);
    await loopOf(container);
  }

  test('a completion answers the sitting that issued it, or nothing', () async {
    final container = launch();
    await place(container);
    final first = await loopOf(container);
    final issued = first.attempt!;

    await switchProfile(container);
    final replacement = container.read(practiceLoopProvider).requireValue;

    await container
        .read(practiceLoopProvider.notifier)
        .finish(
          AttemptCompletion.unplayed(AttemptTermination.learnerStopped),
          attempt: issued,
        );
    final after = container.read(practiceLoopProvider).requireValue;

    expect(after.identity, replacement.identity);
    expect(
      after.lastCommitted,
      isNull,
      reason: 'evidence from a replaced sitting is not this one\'s to record',
    );
    expect(after.attemptsRecorded, 0);
    expect(after.presented, replacement.presented);
  });

  test('a plan saved for one profile is not shown under another', () async {
    final gate = Completer<void>();
    practice = _GatedPlanStore(gate.future);
    final container = launch();
    await place(container);
    await loopOf(container);

    final saving = container
        .read(practicePlanProvider.notifier)
        .apply(PracticePlan.normal.focusedOn(_minorMaterial));
    await switchProfile(container);
    gate.complete();
    await saving;

    expect(
      container.read(practicePlanProvider).requireValue.isFocused,
      isFalse,
      reason: 'the focus belongs to the profile that asked for it',
    );
  });

  test(
    'overlapping plan saves land in the order they were asked for',
    () async {
      final gate = Completer<void>();
      final store = _GatedPlanStore(gate.future);
      practice = store;
      final container = launch();
      await place(container);
      await loopOf(container);

      final notifier = container.read(practicePlanProvider.notifier);
      final focused = notifier.apply(
        PracticePlan.normal.focusedOn(_minorMaterial),
      );
      final normal = notifier.apply(PracticePlan.normal);
      gate.complete();
      await Future.wait([focused, normal]);

      expect(store.saved.map((plan) => plan.isFocused), [true, false]);
      expect(
        container.read(practicePlanProvider).requireValue.isFocused,
        isFalse,
      );
    },
  );

  test('nothing can change a plan before its storage has resolved', () async {
    // What the durability of an accepted plan change rests on. The write
    // captures the store when the mutation is accepted, so the contract holds
    // as long as nowhere the learner can ask for one is reachable before the
    // store is there, which is what opening the loop establishes.
    final container = launch();
    await place(container);
    await loopOf(container);

    expect(container.read(practiceStoreProvider).hasValue, isTrue);
  });

  test('a plan change already accepted still lands', () async {
    // Accepting an apply takes it on. Publishing it is the part that belongs
    // to whoever is still reading; the write is owed to the profile it names,
    // whether or not anything is left to show it.
    final gate = Completer<void>();
    final store = _GatedPlanStore(gate.future);
    practice = store;
    final container = launch();
    await place(container);
    await loopOf(container);
    final profileId = (await profiles.selectedOrOldest())!.id;

    final saving = container
        .read(practicePlanProvider.notifier)
        .apply(PracticePlan.normal.focusedOn(_minorMaterial));
    container.dispose();
    gate.complete();
    await saving;

    expect((await store.loadPracticePlan(profileId))!.isFocused, isTrue);
  });

  test('a commit that failed is written again, not reopened', () async {
    final store = _FailsFirstAppend();
    practice = store;
    final container = launch();
    await place(container);
    final first = await loopOf(container);
    final issued = first.attempt!;

    await container
        .read(practiceLoopProvider.notifier)
        .finish(
          AttemptCompletion.unplayed(AttemptTermination.learnerStopped),
          attempt: issued,
        );

    final failed = container.read(practiceLoopProvider);
    expect(failed, isA<AsyncError<PracticeLoopState>>());
    expect(
      (failed as AsyncError).error,
      isA<PracticeLoopFailure>().having(
        (failure) => failure.kind,
        'kind',
        PracticeFailure.commit,
      ),
    );

    await container.read(practiceLoopProvider.notifier).retry();
    final after = container.read(practiceLoopProvider).requireValue;

    expect(
      after.lastCommitted!.identity.attemptId,
      issued.attemptId,
      reason: 'the frozen close is what is retried, not a fresh sitting',
    );
    expect(after.identity, first.identity);
    expect(after.attemptsRecorded, 1);
    expect(store.appends, 2);
  });

  test('releasing a recording closes only the one it names', () async {
    // Whether a window is still open is read the way the input boundary would
    // close it: an interruption reaches a recording and passes over a released
    // one.
    final container = launch();
    final notifier = container.read(attemptTranscriptProvider.notifier);
    final material = TechnicalMaterial('C', ScaleForm.major);

    final alone = notifier.start(material);
    notifier.release(alone);
    notifier.interruptForTest(InputIntegrityFault.observationGap);
    expect(
      container.read(attemptTranscriptProvider).isInterrupted,
      isFalse,
      reason: 'the attempt that left the screen takes its window with it',
    );

    final leaving = notifier.start(material);
    final arriving = notifier.start(material);
    // The attempt that left releases what it opened, which by now is not the
    // recording anybody is playing into.
    notifier.release(leaving);
    notifier.interruptForTest(InputIntegrityFault.observationGap);

    final capture = container.read(attemptTranscriptProvider);
    expect(capture.recording, arriving);
    expect(
      capture.isInterrupted,
      isTrue,
      reason: 'an older attempt cannot close a newer attempt\'s recording',
    );
  });
}

final _minorMaterial = ActiveFocus(
  label: 'Minor material',
  strength: FocusStrength.emphasis,
  material: MaterialFocus(scaleFormIds: {ScaleForm.naturalMinor.id}),
);

/// Holds every plan save open until it is let go.
class _GatedPlanStore extends InMemoryPracticeStore {
  final Future<void> gate;
  final List<PracticePlan> saved = [];

  _GatedPlanStore(this.gate);

  @override
  Future<void> savePracticePlan(String profileId, PracticePlan plan) async {
    await gate;
    saved.add(plan);
    await super.savePracticePlan(profileId, plan);
  }
}

/// Refuses the first append, the way storage that is momentarily gone does.
class _FailsFirstAppend extends InMemoryPracticeStore {
  int appends = 0;

  @override
  Future<void> appendAttempt(AttemptRecord record) async {
    appends++;
    if (appends == 1) throw StateError('storage is unavailable');
    await super.appendAttempt(record);
  }
}
