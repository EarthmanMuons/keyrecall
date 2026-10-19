import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

/// A history of [attempts] ordinary attempts, with an acquisition attempt
/// after every [acquisitionEvery], each carrying General Fluency evidence of
/// the size practice writes.
///
/// For timing the fold, whose cost is the records and the evidence on them
/// rather than anything a learner did, so nothing here is played or replayed.
({AttemptJournal attempts, AcquisitionJournal acquisition})
syntheticAllocationHistory({
  required int attempts,
  int acquisitionEvery = 400,
  int seed = 0,
}) {
  final random = math.Random(seed);
  final start = DateTime.utc(2026);
  const profileId = 'benchmark';
  final materials = allPracticeMaterials;
  final requirements = [
    for (final material in materials)
      catalogRequirementId(PracticeGoal.generalFluency.id, material.materialId),
  ];
  final policy = AllocationPolicyIdentity(
    assigned: SchedulingAssignment.allocation.id,
    effective: SchedulingAssignment.allocation.id,
  );
  AllocationObserved evidence(int attemptsBefore, int acquired, int? served) {
    final missed = [
      for (final (index, id) in requirements.indexed)
        if (index != served && random.nextBool()) id,
    ];
    return AllocationObserved(
      policy: policy,
      basis: AllocationBasis(
        attempts: attemptsBefore,
        acquisitionAttempts: acquired,
      ),
      evidence: AllocationEvidence(
        served: [?served == null ? null : requirements[served]],
        missed: missed,
      ),
    );
  }

  Exercise exerciseAt(int index) => Exercise.linear(
    material: materials[index % materials.length],
    hands: HandConfiguration.right,
    octaves: 1,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
    guidance: GuidanceContext.continuouslyCued,
  );

  final journal = AttemptJournal(
    JournalHeader(profileId: profileId, createdAt: start),
  );
  final acquisition = AcquisitionJournal(
    AcquisitionJournalHeader(profileId: profileId, createdAt: start),
  );
  for (var index = 0; index < attempts; index++) {
    final at = start.add(Duration(minutes: 2 * index));
    if (index > 0 && index % acquisitionEvery == 0) {
      acquisition.append(
        AcquisitionAttemptRecord(
          journalSequence: acquisition.nextSequence,
          identity: AttemptIdentity(
            profileId: profileId,
            attemptId: 'acquisition-$index',
            sessionId: 'benchmark',
            indexInSession: index,
            occurredAt: at,
          ),
          attemptsBefore: index,
          allocation: evidence(index, acquisition.attempts.length, null),
          task: AcquisitionTask.unmeteredTraversal(exerciseAt(index)),
          started: true,
          completion: AcquisitionCompletion.completedCleanly,
          repairs: 0,
          repeats: 0,
          intrusions: 0,
          earnedProbe: false,
          sequence: CriterionVerdict.notMet,
          continuity: CriterionVerdict.unavailable,
          gaps: const [],
        ),
      );
    }
    journal.append(
      AttemptRecord(
        journalSequence: index,
        identity: AttemptIdentity(
          profileId: profileId,
          attemptId: 'attempt-$index',
          sessionId: 'benchmark',
          indexInSession: index,
          occurredAt: at,
        ),
        provenance: ModelProvenance(
          learnerModelVersion: 'benchmark',
          schedulerModelVersion: SchedulingAssignment.v1_14.id,
        ),
        exercise: exerciseAt(index),
        closure: AttemptClosure.unmeasured(
          termination: AttemptTermination.learnerStopped,
          reason: MeasurementUnavailableReason.notAvailable,
        ),
        allocation: evidence(
          index,
          acquisition.attempts.length,
          index % requirements.length,
        ),
      ),
    );
  }
  return (attempts: journal, acquisition: acquisition);
}

/// How long folding [history] into waiting counters takes, [runs] times,
/// sorted.
List<Duration> timeSyntheticFold(
  ({AttemptJournal attempts, AcquisitionJournal acquisition}) history, {
  int runs = 31,
}) => [
  for (var run = 0; run < runs; run++)
    () {
      final watch = Stopwatch()..start();
      AllocationHistory.of(history.attempts, history.acquisition);
      return watch.elapsed;
    }(),
]..sort();

/// How long carrying [history] on by its last ordinary attempt takes, [runs]
/// times, sorted: what a decision pays once a session has folded the rest.
List<Duration> timeSyntheticContinuation(
  ({AttemptJournal attempts, AcquisitionJournal acquisition}) history, {
  int runs = 31,
}) {
  final shorter = AttemptJournal(history.attempts.header);
  final records = history.attempts.records;
  for (final record in records.take(records.length - 1)) {
    shorter.append(record);
  }
  final held = AllocationHistory.of(shorter, history.acquisition);
  return [
    for (var run = 0; run < runs; run++)
      () {
        final watch = Stopwatch()..start();
        held.continuedWith(history.attempts, history.acquisition);
        return watch.elapsed;
      }(),
  ]..sort();
}
