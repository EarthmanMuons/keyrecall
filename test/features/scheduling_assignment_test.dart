import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';

import '../support/scheduler_override.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('assigning the pilot reopens practice, resuming what was on screen '
      'under the policy it was decided by', () async {
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith(
          (ref) async => InMemoryProfileRepository(),
        ),
        inProcessScheduling,
        practiceStoreProvider.overrideWith(
          (ref) async => InMemoryPracticeStore(),
        ),
        practiceCatalogProvider.overrideWithValue([
          ScaleMaterial('C', ScaleForm.major),
          ScaleMaterial('G', ScaleForm.major),
        ]),
      ],
    );
    addTearDown(container.dispose);
    container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
    await container
        .read(profileRosterProvider.notifier)
        .place(PlacementTier.someExperience);
    final before = await container.read(practiceLoopProvider.future);
    final presented = before.presented!;
    final ordinary = AllocationPolicyIdentity(
      assigned: SchedulingAssignment.v1_14.id,
      effective: SchedulingAssignment.v1_14.id,
    );
    expect(presented.decision.allocation.policy, ordinary);

    await container
        .read(profileRosterProvider.notifier)
        .assign(before.profile.id, SchedulingAssignment.allocationPilot);
    final after = await container.read(practiceLoopProvider.future);

    expect(after.profile.scheduling, SchedulingAssignment.allocationPilot);
    expect(after.pending!.attemptId, presented.decision.attemptId);
    expect(after.pending!.allocation, presented.decision.allocation);

    final record = await after.session.closeUnmeasured(
      termination: AttemptTermination.learnerStopped,
    );
    expect(record.allocation.policy, ordinary);
    final next = await after.session.decideOutcome(
      at: record.identity.occurredAt.add(const Duration(minutes: 2)),
    );
    expect(
      (next as PresentedAttempt).decision.allocation.policy,
      AllocationPolicyIdentity(
        assigned: SchedulingAssignment.allocationPilot.id,
        effective: SchedulingAssignment.allocationPilot.id,
      ),
    );
  });
}
