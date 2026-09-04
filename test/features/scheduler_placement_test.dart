import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';

import '../support/scheduler_override.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A launch over its own storage, scheduling where the app does unless
  /// [inProcess].
  Future<ProviderContainer> launch({bool inProcess = false}) async {
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith(
          (ref) async => InMemoryProfileRepository(),
        ),
        practiceStoreProvider.overrideWith(
          (ref) async => InMemoryPracticeStore(),
        ),
        if (inProcess) inProcessScheduling,
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
    final onWorker = await launch();
    addTearDown(onWorker.dispose);
    final inProcess = await launch(inProcess: true);
    addTearDown(inProcess.dispose);

    for (var slot = 0; slot < 3; slot++) {
      final decided = onWorker.read(practiceLoopProvider).requireValue;
      final directly = inProcess.read(practiceLoopProvider).requireValue;

      expect(decided.presented, isNotNull);
      expect(
        decided.presented!.exercise,
        directly.presented!.exercise,
        reason: 'slot $slot',
      );
      expect(
        decided.session.session.attemptsThisSession,
        directly.session.session.attemptsThisSession,
      );

      await onWorker.read(practiceLoopProvider.notifier).decline();
      await inProcess.read(practiceLoopProvider.notifier).decline();
    }
  });
}
