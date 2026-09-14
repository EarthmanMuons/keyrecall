import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

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
    final recovered = container.read(practiceLoopProvider);
    expect(recovered, isA<AsyncData<PracticeLoopState>>());
    final after = recovered.requireValue;

    expect(
      after.lastCommitted!.identity.attemptId,
      issued.attemptId,
      reason: 'the frozen close is what is retried, not a fresh sitting',
    );
    expect(after.identity, first.identity);
    expect(after.attemptsRecorded, 1);
    expect(store.appends, 2);
  });

  test('a build superseded while opening never decides', () async {
    // An old build that runs on decides a slot and persists it, so the attempt
    // on screen and the attempt a relaunch would recover stop being the same
    // one. Finishing the open is harmless; going on to decide is not.
    final store = _HoldsOnePendingRead();
    practice = store;
    final container = launch();
    await place(container);
    final first = await loopOf(container);
    // Nothing to resume, so a reopened sitting decides rather than presenting
    // the slot it recovered.
    await first.session.abandonPending();

    // Listened to, so reopening rebuilds when it is invalidated rather than
    // when somebody next reads.
    final subscription = container.listen(practiceLoopProvider, (_, _) {});
    addTearDown(subscription.close);

    final notifier = container.read(practiceLoopProvider.notifier);
    final paused = Completer<void>();
    store.gate = paused;
    notifier.reopen();
    await pumpEventQueue();
    // A replacement that runs to completion behind the paused one.
    notifier.reopen();
    final replacement = await loopOf(container);

    paused.complete();
    await pumpEventQueue();

    final profileId = (await profiles.selectedOrOldest())!.id;
    final pending = await store.loadPendingDecision(profileId);
    expect(
      pending!.attemptId,
      replacement.attempt!.attemptId,
      reason: 'what is recorded as pending is what is on screen',
    );
    expect(
      container.read(practiceLoopProvider).requireValue.identity,
      replacement.identity,
    );
  });

  test('a build abandoned while opening never decides', () async {
    // Torn down rather than replaced. Nothing comes after it, so nothing else
    // will have moved the generation on: a build that only asks whether it was
    // superseded answers no, and goes on to decide for a sitting that no
    // longer exists.
    final store = _HoldsOnePendingRead();
    practice = store;
    final container = launch();
    await place(container);
    final first = await loopOf(container);
    await first.session.abandonPending();
    final profileId = (await profiles.selectedOrOldest())!.id;

    final subscription = container.listen(practiceLoopProvider, (_, _) {});
    final paused = Completer<void>();
    store.gate = paused;
    container.read(practiceLoopProvider.notifier).reopen();
    await pumpEventQueue();

    subscription.close();
    container.dispose();
    paused.complete();
    await pumpEventQueue();

    expect(
      await store.loadPendingDecision(profileId),
      isNull,
      reason: 'a sitting nobody is holding decides nothing and writes nothing',
    );
  });

  test(
    'retrying while a frozen commit is being written does nothing',
    () async {
      final store = _FailsThenHoldsAppend();
      practice = store;
      final container = launch();
      await place(container);
      final first = await loopOf(container);
      final notifier = container.read(practiceLoopProvider.notifier);

      await notifier.finish(
        AttemptCompletion.unplayed(AttemptTermination.learnerStopped),
        attempt: first.attempt!,
      );
      expect(container.read(practiceLoopProvider), isA<AsyncError<dynamic>>());

      final retrying = notifier.retry();
      await pumpEventQueue();
      // The recovery this would restart is the one still writing. Reopening now
      // is how the sitting on screen ends up behind durable history.
      await notifier.retry();
      store.gate.complete();
      await retrying;

      final recovered = container.read(practiceLoopProvider);
      expect(recovered, isA<AsyncData<PracticeLoopState>>());
      final after = recovered.requireValue;
      expect(after.identity, first.identity);
      expect(after.attemptsRecorded, 1);
      expect(after.lastCommitted!.identity.attemptId, first.attempt!.attemptId);
      expect(store.appends, 2, reason: 'one failure and one retry, not three');
    },
  );

  test(
    'a decision that lost its worker is asked again on a fresh one',
    () async {
      final host = _LosesTheWorkerOnce();
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWith((ref) async => profiles),
          practiceStoreProvider.overrideWith((ref) async => practice),
          schedulerHostFactoryProvider.overrideWith(
            (ref) =>
                () => host,
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
      await place(container);
      final first = await loopOf(container);

      await container
          .read(practiceLoopProvider.notifier)
          .finish(
            AttemptCompletion.unplayed(AttemptTermination.learnerStopped),
            attempt: first.attempt!,
          );

      final failed = container.read(practiceLoopProvider);
      expect(
        (failed as AsyncError).error,
        isA<PracticeLoopFailure>().having(
          (failure) => failure.kind,
          'kind',
          PracticeFailure.scheduling,
        ),
      );

      await container.read(practiceLoopProvider.notifier).retry();
      final recovered = container.read(practiceLoopProvider);

      // Read as an AsyncValue, not through it: a failure carries the last
      // value forward, so a state that still holds an exercise is not on its
      // own evidence that anything recovered.
      expect(
        recovered,
        isA<AsyncData<PracticeLoopState>>(),
        reason: 'the sitting rebinds where it decides rather than reopening',
      );
      final after = recovered.requireValue;
      expect(after.presented, isNotNull);
      expect(after.identity, first.identity);
      expect(after.attemptsRecorded, 1);
    },
  );

  test('a decision that failed to persist retries without rebinding', () async {
    // Deciding can fail for reasons that say nothing about where deciding
    // happens. Rebinding then would diagnose a host failure nobody observed.
    final host = _CountsItsBindings();
    final store = _RefusesOnePendingWrite();
    practice = store;
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) async => profiles),
        practiceStoreProvider.overrideWith((ref) async => practice),
        schedulerHostFactoryProvider.overrideWith(
          (ref) =>
              () => host,
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
    await place(container);
    final first = await loopOf(container);
    final bindings = host.bindings;

    store.refuses = true;
    await container
        .read(practiceLoopProvider.notifier)
        .finish(
          AttemptCompletion.unplayed(AttemptTermination.learnerStopped),
          attempt: first.attempt!,
        );
    expect(
      (container.read(practiceLoopProvider) as AsyncError).error,
      isA<PracticeLoopFailure>().having(
        (failure) => failure.kind,
        'kind',
        PracticeFailure.scheduling,
      ),
    );

    await container.read(practiceLoopProvider.notifier).retry();

    expect(
      container.read(practiceLoopProvider),
      isA<AsyncData<PracticeLoopState>>(),
    );
    expect(host.bindings, bindings, reason: 'the host never failed');
  });

  test(
    'a plan load waits for a write already accepted for that profile',
    () async {
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
      await switchProfile(container);
      await container.read(profileRosterProvider.notifier).select(profileId);

      // Back on the profile whose save is still in flight. Reading storage now
      // would read the state that save was asked to replace.
      final reopening = loopOf(container);
      await pumpEventQueue();
      gate.complete();
      await saving;
      await reopening;

      expect(
        container.read(practicePlanProvider).requireValue.isFocused,
        isTrue,
      );
    },
  );

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

/// Holds the first pending-decision read taken while it is armed, in flight.
///
/// What comes back is what storage held when the read was made, which is what
/// a build that started before the one replacing it is working from.
class _HoldsOnePendingRead extends InMemoryPracticeStore {
  Completer<void>? gate;

  @override
  Future<PendingDecision?> loadPendingDecision(String profileId) async {
    final held = gate;
    gate = null;
    final answer = await super.loadPendingDecision(profileId);
    if (held != null) await held.future;
    return answer;
  }
}

/// Refuses the first append and holds the second until it is let go.
class _FailsThenHoldsAppend extends InMemoryPracticeStore {
  final Completer<void> gate = Completer<void>();
  int appends = 0;

  @override
  Future<void> appendAttempt(AttemptRecord record) async {
    appends++;
    if (appends == 1) throw StateError('storage is unavailable');
    await gate.future;
    await super.appendAttempt(record);
  }
}

/// Loses its worker once, the way a host whose isolate died does: the request
/// fails, and nothing decides again until something binds.
class _LosesTheWorkerOnce extends InProcessScheduler {
  _LosesTheWorkerOnce()
    : super(const SchedulerPipeline(learner: LearnerModel()));

  bool _bound = false;
  int _decisions = 0;

  @override
  Future<void> bind({
    required ResolvedPracticeScope scope,
    required PracticeEntryPolicy entry,
    required LearnerModel learner,
    required SchedulerConfig config,
  }) async {
    _bound = true;
    await super.bind(
      scope: scope,
      entry: entry,
      learner: learner,
      config: config,
    );
  }

  @override
  Future<SchedulerVerdict> decide({
    required int epoch,
    required LearnerState state,
    required SessionState session,
    required List<String> dueRequirementIds,
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    Set<Exercise>? attemptedExercises,
    Map<ExecutionContext, int> executionEvidenceRevisions = const {},
  }) {
    if (!_bound) {
      throw StateError('no scope is bound; bind one before deciding');
    }
    if (++_decisions == 2) {
      _bound = false;
      throw const SchedulerWorkerLost();
    }
    return super.decide(
      epoch: epoch,
      state: state,
      session: session,
      dueRequirementIds: dueRequirementIds,
      at: at,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: acquisitionFamilyFloor,
      acquisition: acquisition,
      attemptedExercises: attemptedExercises,
      executionEvidenceRevisions: executionEvidenceRevisions,
    );
  }
}

/// Counts what has been bound to it, and decides in this isolate.
class _CountsItsBindings extends InProcessScheduler {
  _CountsItsBindings()
    : super(const SchedulerPipeline(learner: LearnerModel()));

  int bindings = 0;

  @override
  Future<void> bind({
    required ResolvedPracticeScope scope,
    required PracticeEntryPolicy entry,
    required LearnerModel learner,
    required SchedulerConfig config,
  }) async {
    bindings++;
    await super.bind(
      scope: scope,
      entry: entry,
      learner: learner,
      config: config,
    );
  }
}

/// Refuses the next pending-decision write, once.
class _RefusesOnePendingWrite extends InMemoryPracticeStore {
  bool refuses = false;

  @override
  Future<void> savePendingDecision(PendingDecision decision) async {
    if (refuses) {
      refuses = false;
      throw StateError('storage is unavailable');
    }
    await super.savePendingDecision(decision);
  }
}
