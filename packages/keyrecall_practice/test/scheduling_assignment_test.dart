import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  final following = alice.scheduledBy(null);
  final ordinary = alice.scheduledBy(SchedulingAssignment.v1_14);
  final allocating = alice.scheduledBy(SchedulingAssignment.allocation);
  AllocationPolicyIdentity decided(
    SchedulingAssignment assigned,
    SchedulingAssignment effective,
  ) => AllocationPolicyIdentity(assigned: assigned.id, effective: effective.id);
  final byAllocation = decided(
    SchedulingAssignment.allocation,
    SchedulingAssignment.allocation,
  );
  final byOrdinaryRanking = decided(
    SchedulingAssignment.v1_14,
    SchedulingAssignment.v1_14,
  );
  final focus = PracticeFocus(
    exclusiveRequirementIds: {
      catalogRequirementId(
        PracticeGoal.generalFluency.id,
        fixtureMaterials.first.materialId,
      ),
    },
  );

  Future<AllocationPolicyIdentity?> policyOf(
    PracticeSession session, {
    double day = 1,
  }) async =>
      ((await session.decideOutcome(at: t0.plusDays(day))) as PresentedAttempt)
          .decision
          .allocation
          .policy;

  test('production decides unrestricted General Fluency by allocation', () {
    expect(SchedulingAssignment.production, SchedulingAssignment.allocation);
    expect(following.scheduling, SchedulingAssignment.allocation);
  });

  test(
    'a profile nobody chose for is decided as one chosen for allocation',
    () async {
      expect(
        await policyOf(
          await openSession(
            InMemoryPracticeStore(createdAt: t0),
            profile: following,
          ),
        ),
        byAllocation,
      );
      expect(
        await policyOf(
          await openSession(
            InMemoryPracticeStore(createdAt: t0),
            profile: ordinary,
          ),
        ),
        byOrdinaryRanking,
      );
    },
  );

  test('a history ordinary ranking decided, once it follows production, '
      'is kept as written and decided as one chosen for allocation', () async {
    Future<List<Map<String, Object?>>> continued(Profile after) async {
      final store = InMemoryPracticeStore(createdAt: t0);
      await practise(
        await openSession(
          store,
          profile: ordinary,
          materials: allPracticeMaterials,
        ),
        attempts: 30,
      );
      final before = [
        for (final record in (await store.loadJournal(alice.id)).records)
          record.toJson(),
      ];
      final session = await openSession(
        store,
        profile: after,
        sessionId: 'after',
        ids: countingIds('after'),
        materials: allPracticeMaterials,
      );
      await practise(session, attempts: 30, startDay: 20);
      final all = [
        for (final record in session.journal.records) record.toJson(),
      ];
      expect(all.take(before.length), before);
      return all;
    }

    final adopted = await continued(following);
    expect(adopted, await continued(allocating));
    expect(
      AllocationRecord.fromJson(
        adopted.last['allocation']! as Map<String, Object?>,
      ).policy,
      byAllocation,
    );
  });

  test('a focus or another goal is decided by v1-14', () async {
    final focused =
        await openSession(
            InMemoryPracticeStore(createdAt: t0),
            profile: following,
          )
          ..updateScope(goal: PracticeGoal.generalFluency, focus: focus);
    final elsewhere =
        await openSession(
            InMemoryPracticeStore(createdAt: t0),
            profile: following,
            materials: allPracticeMaterials,
          )
          ..updateScope(goal: supportedGoals['FOUNDATIONS']!);
    final notAllocating = decided(
      SchedulingAssignment.allocation,
      SchedulingAssignment.v1_14,
    );

    expect(await policyOf(focused), notAllocating);
    expect(await policyOf(elsewhere), notAllocating);
  });

  test('a decision pending across a change of policy commits as it was made, '
      'and the next is decided by the new one', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final before = await openSession(store, profile: following);
    final presented =
        await before.decideOutcome(at: t0.plusDays(1)) as PresentedAttempt;

    final after = await openSession(
      store,
      profile: ordinary,
      sessionId: 'reassigned',
    );
    final record = await after.closeWithOutcome(
      outcomeFor(after.pending!.exercise),
    );

    expect(record.allocation, presented.decision.allocation);
    expect(record.allocation.policy, byAllocation);
    expect(await policyOf(after, day: 2), byOrdinaryRanking);
  });

  test(
    'a focus suspends what it leaves out, and keeps it for return',
    () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(
        store,
        profile: following,
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

  test('either choice survives the profile round trip, and following '
      'production writes nothing', () {
    for (final chosen in [ordinary, allocating]) {
      expect(
        Profile.fromJson(chosen.toJson()).schedulingOverride,
        chosen.schedulingOverride,
      );
    }
    expect(following.toJson().containsKey('scheduling'), isFalse);
    expect(Profile.fromJson(following.toJson()).schedulingOverride, isNull);
    expect(
      () => Profile.fromJson(allocating.toJson()..['scheduling'] = 'v2'),
      throwsA(isA<JournalFormatException>()),
    );
  });
}
