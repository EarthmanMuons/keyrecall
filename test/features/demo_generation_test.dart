import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall/features/practice/demo_profile.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

void main() {
  final created = Profile(
    id: 'demo',
    displayName: 'Demo',
    createdAt: DateTime.utc(2026, 6),
    placement: PlacementTier.beginner,
  );

  ({ProviderContainer container, Completer<Profile> finishing, List<int> runs})
  owning() {
    final finishing = Completer<Profile>();
    final runs = <int>[];
    final container = ProviderContainer(
      overrides: [
        demoProfileGeneratorProvider.overrideWithValue((ref, {onSession}) {
          runs.add(runs.length);
          onSession?.call(1, 3);
          return finishing.future;
        }),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, finishing: finishing, runs: runs);
  }

  test('a run reports progress and its result with nobody watching', () async {
    final (:container, :finishing, :runs) = owning();
    final generation = container.read(demoGenerationProvider.notifier);

    final run = generation.start();
    expect(
      container.read(demoGenerationProvider),
      isA<DemoRunning>()
          .having((state) => state.completed, 'completed', 1)
          .having((state) => state.total, 'total', 3),
    );

    await generation.start();
    expect(runs, hasLength(1));

    // Long enough for anything that disposes unwatched state to have done so.
    await pumpEventQueue();
    finishing.complete(created);
    await run;
    expect(
      container.read(demoGenerationProvider),
      isA<DemoCreated>().having((state) => state.profile, 'profile', created),
    );
  });

  test('a run that fails says why, and another may start', () async {
    final (:container, :finishing, :runs) = owning();
    final generation = container.read(demoGenerationProvider.notifier);

    final run = generation.start();
    finishing.completeError(StateError('interrupted'));
    await run;

    expect(container.read(demoGenerationProvider), isA<DemoFailed>());
    unawaited(generation.start());
    expect(runs, hasLength(2));
  });
}
