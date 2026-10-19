import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  for (final (name, make) in [
    (
      'in process',
      () => InProcessScheduler(SchedulerPipeline(learner: learner)),
    ),
    ('on a worker', IsolateScheduler.new),
  ]) {
    test('with every requirement but the winner\'s overdue, v1-14 keeps the '
        'winner and the pilot takes the slot, $name', () async {
      final host = _Overdue(make());
      final session = await openSession(
        InMemoryPracticeStore(createdAt: t0),
        profile: alice.scheduledBy(SchedulingAssignment.v1_14),
        scheduler: host,
        materials: allPracticeMaterials,
      );
      for (var slot = 0; slot < 24; slot++) {
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

      expect(host.overdue, greaterThan(20));
      expect(host.observedChanged, 0);
      expect(host.observedOwed, 0);
      expect(host.substituted, greaterThan(0));
      expect(host.substituted, host.allocatedOwed);
      expect(host.diagnosticsDiffered, 0);
      expect(host.accountsMissing, 0);
    });
  }
}

/// Decides every slot three ways: as asked, then with every requirement the
/// ordinary winner does not serve far overdue, observed and under the pilot.
/// Counts how each overdue answer departed from ordinary ranking, and answers
/// with the observed one.
class _Overdue implements SchedulerHost {
  final SchedulerHost inner;
  var overdue = 0;
  var observedChanged = 0;
  var observedOwed = 0;
  var substituted = 0;
  var allocatedOwed = 0;
  var diagnosticsDiffered = 0;
  var accountsMissing = 0;

  _Overdue(this.inner);

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
  }) async {
    Future<SchedulerVerdict> ask(AllocationRequest request) => inner.decide(
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
      allocation: request,
    );

    final ordinary = await ask(allocation!);
    final served = ordinary.allocation!.evidence.served.toSet();
    var counters = const WaitCounters.empty();
    final missed = [
      for (final state in allocation.requirements)
        if (!served.contains(state.resolved.requirement.id))
          state.resolved.requirement.id,
    ];
    for (var i = 0; i < 1000; i++) {
      counters = counters.advance(
        AllocationEvidence(served: const [], missed: missed),
      );
    }
    AllocationRequest overdueUnder(AllocationPolicy? policy) =>
        AllocationRequest(
          requirements: allocation.requirements,
          counters: counters,
          basis: allocation.basis,
          policy: policy,
        );

    final observed = await ask(overdueUnder(null));
    final allocated = await ask(overdueUnder(AllocationPolicy.production));
    if (ordinary.chosen == null) return observed;
    overdue++;
    if (observed.chosen?.exercise != ordinary.chosen!.exercise) {
      observedChanged++;
    }
    if (observed.allocation!.owedRequirementId != null) observedOwed++;
    if (allocated.chosen?.exercise != ordinary.chosen!.exercise) substituted++;
    if (allocated.allocation!.owedRequirementId != null) allocatedOwed++;
    if (observed.diagnostics != ordinary.diagnostics) diagnosticsDiffered++;
    final account = allocated.diagnostics;
    final owed = allocated.allocation!.owedRequirementId;
    final presented = allocated.chosen!.exercise;
    if (!account.startsWith('section=ordinary_ranking') ||
        !account.contains(ordinary.diagnostics) ||
        !account.contains('substituted=${owed != null}') ||
        !account.contains('owed_requirement=${owed ?? '-'}') ||
        !account.contains(
          'final candidate=${allocated.result?.traces.indexOf(allocated.chosen!) ?? ''}',
        ) ||
        !account
            .split('\n')
            .any(
              (line) =>
                  line.startsWith('final ') &&
                  line.contains(presented.material.materialId) &&
                  line.contains(presented.conditions.hands.id),
            )) {
      accountsMissing++;
    }
    return observed;
  }
}
