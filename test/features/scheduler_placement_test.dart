import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> launch({SchedulerHost? scheduler}) async {
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith(
          (ref) async => InMemoryProfileRepository(),
        ),
        practiceStoreProvider.overrideWith(
          (ref) async => InMemoryPracticeStore(),
        ),
        if (scheduler != null)
          schedulerHostProvider.overrideWith((ref) => scheduler),
      ],
    );
    container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
    await container
        .read(profileRosterProvider.notifier)
        .place(PlacementTier.someExperience);
    await container.read(practiceLoopProvider.future);
    return container;
  }

  test('the app schedules on a worker isolate', () async {
    final container = await launch();
    addTearDown(container.dispose);

    expect(container.read(schedulerHostProvider), isA<IsolateScheduler>());
  });

  test('disposing the container tears the worker down', () async {
    final container = await launch();
    final scheduler = container.read(schedulerHostProvider) as IsolateScheduler;

    container.dispose();

    // The host is disposed with the provider, so the request it would have
    // taken has nowhere to run rather than a worker still holding a scope.
    await expectLater(
      scheduler.decide(
        epoch: 0,
        state: const LearnerModel().placementState(
          PlacementTier.someExperience,
          at: DateTime.utc(2026),
        ),
        session: SessionState(),
        dueRequirementIds: const [],
        at: DateTime.utc(2026),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('placement does not change what the loop presents', () async {
    final scheduler = _ParityScheduler();
    final onWorker = await launch(scheduler: scheduler);
    addTearDown(onWorker.dispose);

    for (var slot = 0; slot < 3; slot++) {
      final decided = onWorker.read(practiceLoopProvider).requireValue;
      expect(decided.presented, isNotNull);
      expect(decided.session.session.attemptsThisSession, scheduler.decisions);

      await onWorker.read(practiceLoopProvider.notifier).decline();
    }
    expect(scheduler.decisions, greaterThanOrEqualTo(2));
  });
}

/// Compares hosts on identical inputs, including decision time and learner age.
class _ParityScheduler extends IsolateScheduler {
  late InProcessScheduler _direct;
  int decisions = 0;

  @override
  Future<void> bind({
    required ResolvedPracticeScope scope,
    required PracticeEntryPolicy entry,
    required LearnerModel learner,
    required SchedulerConfig config,
  }) async {
    await super.bind(
      scope: scope,
      entry: entry,
      learner: learner,
      config: config,
    );
    _direct = InProcessScheduler(
      SchedulerPipeline(learner: learner, config: config),
    );
    await _direct.bind(
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
  }) async {
    final verdict = await super.decide(
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
    final directly = await _direct.decide(
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
    expect(verdict.chosen?.exercise, directly.chosen?.exercise);
    expect(verdict.blockedReason, directly.blockedReason);
    expect(verdict.acquisitionTask, directly.acquisitionTask);
    expect(verdict.diagnostics, directly.diagnostics);
    expect(
      verdict.effect.guidanceProbeAvailable,
      directly.effect.guidanceProbeAvailable,
    );
    expect(
      verdict.effect.guidanceProbeSelected,
      directly.effect.guidanceProbeSelected,
    );
    decisions++;
    return verdict;
  }
}
