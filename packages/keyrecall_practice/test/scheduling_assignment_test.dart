import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  final pilot = alice.scheduledBy(SchedulingAssignment.allocationPilot);
  final assignedPilot = AllocationPolicyIdentity(
    assigned: SchedulingAssignment.allocationPilot.id,
    effective: SchedulingAssignment.allocationPilot.id,
  );
  final assignedButOrdinary = AllocationPolicyIdentity(
    assigned: SchedulingAssignment.allocationPilot.id,
    effective: SchedulingAssignment.v1_14.id,
  );
  final focus = PracticeFocus(
    exclusiveRequirementIds: {
      catalogRequirementId(
        PracticeGoal.generalFluency.id,
        fixtureMaterials.first.materialId,
      ),
    },
  );

  Future<AllocationPolicyIdentity?> policyOf(PracticeSession session) async =>
      ((await session.decideOutcome(at: t0.plusDays(1))) as PresentedAttempt)
          .decision
          .allocation
          .policy;

  test('a profile nobody assigned is decided by v1-14', () async {
    final session = await openSession(InMemoryPracticeStore(createdAt: t0));

    expect(
      await policyOf(session),
      AllocationPolicyIdentity(
        assigned: SchedulingAssignment.v1_14.id,
        effective: SchedulingAssignment.v1_14.id,
      ),
    );
  });

  test(
    'an assigned profile allocates in unrestricted General Fluency',
    () async {
      final session = await openSession(
        InMemoryPracticeStore(createdAt: t0),
        profile: pilot,
      );

      expect(await policyOf(session), assignedPilot);
    },
  );

  test('a focus or another goal leaves an assigned profile to v1-14', () async {
    final focused =
        await openSession(InMemoryPracticeStore(createdAt: t0), profile: pilot)
          ..updateScope(goal: PracticeGoal.generalFluency, focus: focus);
    final elsewhere =
        await openSession(
            InMemoryPracticeStore(createdAt: t0),
            profile: pilot,
            materials: allPracticeMaterials,
          )
          ..updateScope(goal: supportedGoals['FOUNDATIONS']!);

    expect(await policyOf(focused), assignedButOrdinary);
    expect(await policyOf(elsewhere), assignedButOrdinary);
  });

  test(
    'a decision pending across a reassignment commits as it was made',
    () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final before = await openSession(store, profile: pilot);
      final presented =
          await before.decideOutcome(at: t0.plusDays(1)) as PresentedAttempt;

      final after = await openSession(store, sessionId: 'reassigned');
      final record = await after.closeWithOutcome(
        outcomeFor(after.pending!.exercise),
      );

      expect(record.allocation, presented.decision.allocation);
      expect(record.allocation.policy, assignedPilot);
      expect(
        await policyOf(after),
        AllocationPolicyIdentity(
          assigned: SchedulingAssignment.v1_14.id,
          effective: SchedulingAssignment.v1_14.id,
        ),
      );
    },
  );

  test(
    'a focus suspends what it leaves out, and keeps it for return',
    () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(
        store,
        profile: pilot,
        materials: allPracticeMaterials,
      );
      await practise(session, attempts: 16);
      final waiting = AllocationHistory.of(
        session.journal,
        session.acquisitionJournal,
      ).counters.asMap;
      final outside = {
        for (final MapEntry(:key, :value) in waiting.entries)
          if (!focus.exclusiveRequirementIds!.contains(key)) key: value,
      };
      expect(outside, isNotEmpty);

      session.updateScope(goal: PracticeGoal.generalFluency, focus: focus);
      await practise(session, attempts: 4, startDay: 16);
      final kept = AllocationHistory.of(
        session.journal,
        session.acquisitionJournal,
      ).counters;

      for (final MapEntry(:key, :value) in outside.entries) {
        expect(kept[key], value, reason: key);
      }
    },
  );

  test('an assignment survives the profile round trip, and is written only '
      'when made', () {
    expect(Profile.fromJson(pilot.toJson()).scheduling, pilot.scheduling);
    expect(alice.toJson().containsKey('scheduling'), isFalse);
    expect(
      Profile.fromJson(alice.toJson()).scheduling,
      SchedulingAssignment.v1_14,
    );
    expect(
      () => Profile.fromJson(pilot.toJson()..['scheduling'] = 'v2'),
      throwsA(isA<JournalFormatException>()),
    );
  });
}
