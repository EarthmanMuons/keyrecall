import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  /// Practises [slots] decisions, recording supported attempts and failing
  /// every third ordinary one, and returns both logs as written.
  Future<(List<Map<String, Object?>>, List<Map<String, Object?>>)> practise(
    SchedulerHost host, {
    int slots = 80,
  }) async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(
      store,
      scheduler: host,
      materials: allPracticeMaterials,
    );
    for (var slot = 0; slot < slots; slot++) {
      final at = t0.plusDays(0.4 * (slot + 1));
      switch (await session.decideOutcome(at: at)) {
        case PresentedAttempt(:final exercise):
          await session.closeWithOutcome(
            outcomeFor(exercise, succeeded: slot % 3 != 0),
          );
        case PresentedAcquisition():
          await session.closeAcquisition(PerformanceTranscript.empty, at: at);
        case _:
      }
    }
    await host.dispose();
    return (
      [for (final record in session.journal.records) record.toJson()],
      [
        for (final record in session.acquisitionJournal.records)
          record.toJson(),
      ],
    );
  }

  List<Map<String, Object?>> withoutAllocation(
    List<Map<String, Object?>> records,
  ) => [for (final record in records) Map.of(record)..remove('allocation')];

  for (final (name, make) in [
    (
      'in process',
      () => InProcessScheduler(SchedulerPipeline(learner: learner)),
    ),
    ('on a worker', IsolateScheduler.new),
  ]) {
    test(
      'shadow accounting changes nothing it records beside, $name',
      () async {
        final (attempts, acquisition) = await practise(make());
        final (unobserved, unobservedAcquisition) = await practise(
          _Unaccounted(make()),
        );

        expect(attempts, hasLength(greaterThan(60)));
        expect(withoutAllocation(attempts), withoutAllocation(unobserved));
        expect(
          withoutAllocation(acquisition),
          withoutAllocation(unobservedAcquisition),
        );
        for (final record in attempts) {
          expect(
            AllocationRecord.fromJson(
              record['allocation']! as Map<String, Object?>,
            ),
            isA<AllocationObserved>().having(
              (observed) => observed.owedRequirementId,
              'owed requirement',
              isNull,
            ),
          );
        }
        for (final record in unobserved) {
          expect(
            AllocationRecord.fromJson(
              record['allocation']! as Map<String, Object?>,
            ),
            isA<AllocationUnobserved>(),
          );
        }
      },
    );
  }

  test('a worker records the evidence deciding in process would', () async {
    final (onWorker, onWorkerAcquisition) = await practise(IsolateScheduler());
    final (inProcess, inProcessAcquisition) = await practise(
      InProcessScheduler(SchedulerPipeline(learner: learner)),
    );

    expect(onWorker, inProcess);
    expect(onWorkerAcquisition, inProcessAcquisition);
  });
}

/// A host asked nothing about allocation.
class _Unaccounted implements SchedulerHost {
  final SchedulerHost inner;

  _Unaccounted(this.inner);

  @override
  Future<void> bind({
    required ResolvedPracticeScope scope,
    required PracticeEntryPolicy entry,
    required LearnerModel learner,
    required SchedulerConfig config,
  }) =>
      inner.bind(scope: scope, entry: entry, learner: learner, config: config);

  @override
  Future<void> dispose() => inner.dispose();

  @override
  Future<SchedulerVerdict> decide({
    required int epoch,
    required LearnerState state,
    required SessionState session,
    required List<String> dueRequirementIds,
    Map<String, Set<HandConfiguration>> liveSupportHands = const {},
    List<String> uncoveredTargetIds = const [],
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    AttemptHistory? history,
    AllocationRequest? allocation,
  }) => inner.decide(
    epoch: epoch,
    state: state,
    session: session,
    dueRequirementIds: dueRequirementIds,
    liveSupportHands: liveSupportHands,
    uncoveredTargetIds: uncoveredTargetIds,
    at: at,
    acquisitionFloor: acquisitionFloor,
    acquisitionFamilyFloor: acquisitionFamilyFloor,
    acquisition: acquisition,
    history: history,
  );
}
