import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  final policy = AllocationPolicyIdentity(
    assigned: SchedulingAssignment.allocationPilot.id,
    effective: SchedulingAssignment.allocationPilot.id,
  );
  final exercise = Exercise.linear(
    material: fixtureMaterials.first,
    hands: HandConfiguration.right,
    octaves: 1,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
    guidance: GuidanceContext.continuouslyCued,
  );
  const ids = ['a', 'b', 'c', 'd', 'e', 'f'];

  AllocationRecord allocationFrom(math.Random random, int attempts, int acq) {
    if (random.nextInt(8) == 0) {
      return AllocationUnobserved(
        AllocationGap.values[random.nextInt(AllocationGap.values.length)],
        policy: policy,
      );
    }
    final served = random.nextInt(ids.length + 1);
    return AllocationObserved(
      policy: policy,
      // Now and then a decision that read less than came before it.
      basis: AllocationBasis(
        attempts: attempts,
        acquisitionAttempts: random.nextInt(6) == 0 ? 0 : acq,
      ),
      evidence: AllocationEvidence(
        served: [if (served < ids.length) ids[served]],
        missed: [
          for (final (index, id) in ids.indexed)
            if (index != served && random.nextBool()) id,
        ],
      ),
    );
  }

  AttemptRecord attemptAt(int index, AllocationRecord allocation) =>
      AttemptRecord(
        journalSequence: index,
        identity: AttemptIdentity(
          profileId: alice.id,
          attemptId: 'attempt-$index',
          sessionId: 'session',
          indexInSession: index,
          occurredAt: t0,
        ),
        provenance: const ModelProvenance(
          learnerModelVersion: 'test',
          schedulerModelVersion: 'v1-14',
        ),
        exercise: exercise,
        closure: AttemptClosure.unmeasured(
          termination: AttemptTermination.learnerStopped,
          reason: MeasurementUnavailableReason.notAvailable,
        ),
        allocation: allocation,
      );

  AcquisitionAttemptRecord acquisitionAt(
    int sequence,
    int? attemptsBefore,
    AllocationRecord allocation,
  ) => AcquisitionAttemptRecord(
    journalSequence: sequence,
    identity: AttemptIdentity(
      profileId: alice.id,
      attemptId: 'acquisition-$sequence',
      sessionId: 'session',
      indexInSession: 0,
      occurredAt: t0,
    ),
    attemptsBefore: attemptsBefore,
    allocation: allocation,
    task: AcquisitionTask.unmeteredTraversal(exercise),
    started: true,
    completion: AcquisitionCompletion.completedCleanly,
    repairs: 0,
    repeats: 0,
    intrusions: 0,
    earnedProbe: false,
    sequence: CriterionVerdict.notMet,
    continuity: CriterionVerdict.unavailable,
    gaps: const [],
  );

  void expectSame(AllocationHistory carried, AllocationHistory whole) {
    expect(carried.counters.asMap.entries.map((e) => (e.key, e.value)), [
      for (final MapEntry(:key, :value) in whole.counters.asMap.entries)
        (key, value),
    ]);
    expect(carried.basis, whole.basis);
    expect(carried.observed, whole.observed);
    expect(carried.gaps, whole.gaps);
    expect(carried.staleDecisions, whole.staleDecisions);
    expect(carried.instrumentedFrom, whole.instrumentedFrom);
  }

  for (final seed in [0, 1, 2, 3]) {
    test('carried on event by event, it is the whole fold at every step, '
        'seed $seed', () {
      final random = math.Random(seed);
      final attempts = AttemptJournal(
        JournalHeader(profileId: alice.id, createdAt: t0),
      );
      final acquisition = AcquisitionJournal(
        AcquisitionJournalHeader(profileId: alice.id, createdAt: t0),
      );
      var carried = AllocationHistory.of(attempts, acquisition);
      for (var step = 0; step < 300; step++) {
        if (random.nextInt(5) == 0) {
          final unplaced = random.nextInt(10) == 0;
          final allocation = allocationFrom(
            random,
            attempts.length,
            acquisition.attempts.length,
          );
          acquisition.append(
            acquisitionAt(
              acquisition.nextSequence,
              unplaced && allocation is! AllocationObserved
                  ? null
                  : attempts.length,
              allocation is AllocationObserved &&
                      allocation.evidence.served.isNotEmpty
                  ? AllocationObserved(
                      policy: policy,
                      basis: allocation.basis,
                      evidence: AllocationEvidence(
                        served: const [],
                        missed: allocation.evidence.missed,
                      ),
                    )
                  : allocation,
            ),
          );
        } else {
          attempts.append(
            attemptAt(
              attempts.length,
              allocationFrom(
                random,
                attempts.length,
                acquisition.attempts.length,
              ),
            ),
          );
        }
        if (random.nextInt(3) != 0) {
          carried = carried.continuedWith(attempts, acquisition);
          expectSame(carried, AllocationHistory.of(attempts, acquisition));
        }
      }
      expect(carried.observed, greaterThan(150));
      expect(carried.staleDecisions, greaterThan(0));
    });
  }

  test('an acquisition attempt placed behind what was folded is folded whole '
      'again, in its place', () {
    final random = math.Random(9);
    final attempts = AttemptJournal(
      JournalHeader(profileId: alice.id, createdAt: t0),
    );
    final acquisition = AcquisitionJournal(
      AcquisitionJournalHeader(profileId: alice.id, createdAt: t0),
    );
    for (var index = 0; index < 4; index++) {
      attempts.append(attemptAt(index, allocationFrom(random, index, 0)));
    }
    final carried = AllocationHistory.of(attempts, acquisition);
    acquisition.append(
      acquisitionAt(
        0,
        1,
        AllocationObserved(
          policy: policy,
          basis: AllocationBasis(attempts: 1, acquisitionAttempts: 0),
          evidence: AllocationEvidence(served: const [], missed: ids),
        ),
      ),
    );

    expectSame(
      carried.continuedWith(attempts, acquisition),
      AllocationHistory.of(attempts, acquisition),
    );
  });
}
