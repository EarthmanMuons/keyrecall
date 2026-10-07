import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'requirement_completion.dart';

/// The record [observation] belongs in the acquisition log.
///
/// The one place an observation becomes history. It carries the facts across
/// and nothing else: there is no outcome to derive, no evidence weights to
/// compute, and no learner state to update, which is the whole difference
/// between closing an acquisition attempt and closing an ordinary one.
///
/// [termination] travels beside the observation rather than inside it. An
/// attempt the learner stopped at six notes and one an input disconnection cut
/// off at six notes are the same performance and different evidence about the
/// learner.
///
/// It is also where capture integrity enters. Measurement reads a musical
/// observation and has no business knowing the ways a capture can fail; what
/// the two together say is an acquisition verdict, and this is the one place
/// both are in hand. A capture that may have lost events leaves every criterion
/// unavailable: the notes that arrived are still what was played, and the ones
/// that did not may have been played too, so the attempt establishes neither a
/// clean traversal nor a learner who fell short of one.
///
/// The verdicts are read here, once, and stored. Replay uses what was stored
/// rather than asking again, so a threshold that moves later changes what the
/// next attempt earns and never what a past one did.
AcquisitionAttemptRecord acquisitionRecordOf({
  required AcquisitionObservation observation,
  required AttemptIdentity identity,
  required int journalSequence,
  AttemptTermination termination = AttemptTermination.learnerStopped,
  PresentationRecord? presentation,
  int? executionEvidenceRevision,
  DateTime? observedWallTime,
}) {
  final integrity = termination.captureIntegrity;
  final sequence = observation.sequence.under(integrity);
  final continuity = observation.continuity.under(integrity);
  return AcquisitionAttemptRecord(
    journalSequence: journalSequence,
    identity: identity,
    executionEvidenceRevision: executionEvidenceRevision,
    observedWallTime: observedWallTime,
    termination: termination,
    task: observation.task,
    presentation: presentation,
    started: observation.started,
    completion: observation.completion,
    repairs: observation.repairs,
    repeats: observation.repeats,
    intrusions: observation.intrusions,
    firstAbsentPosition: observation.firstAbsentPosition,
    sequence: sequence,
    continuity: continuity,
    earnedProbe:
        sequence == CriterionVerdict.met && continuity == CriterionVerdict.met,
    gaps: [
      for (final gap in observation.gaps)
        (
          fromPosition: gap.fromPosition,
          toPosition: gap.toPosition,
          gapMs: gap.gapMs,
          ratio: gap.ratio,
        ),
    ],
  );
}

/// The service record an ordinary presentation of [presented] owes, or null
/// when it owes none.
///
/// Tied to presentation rather than to why the scheduler chose it. A parent can
/// reach the learner because the service phase served an owed probe or because
/// ordinary ranking happened to pick it, and either way the question has been
/// asked. Discharging only the first would leave the obligation open after the
/// learner had already answered it, and the next slot would ask it again.
///
/// Nothing is written when no probe is owed, since a record of service that
/// discharged nothing would say something did not happen.
///
/// The record's identity is the presenting attempt's, because service is that
/// presentation. One ordinary attempt therefore discharges at most one
/// obligation, which the log enforces by being idempotent on that id.
AcquisitionProbeServedRecord? acquisitionServiceOf({
  required Exercise presented,
  required AcquisitionProgress progress,
  required AttemptIdentity identity,
  required int journalSequence,
  DateTime? observedWallTime,
}) => progress.probeOwed(presented)
    ? AcquisitionProbeServedRecord(
        journalSequence: journalSequence,
        identity: identity,
        parent: presented,
        observedWallTime: observedWallTime,
      )
    : null;

/// One ordinary attempt as the scheduler's history reads it.
typedef OrdinaryAttempt = ({
  Exercise exercise,
  Outcome outcome,
  EvidenceWeights weights,
});

/// The ordinary attempts in [records] that were measured.
///
/// Acquisition history is not here: it cannot establish that an ordinary
/// realization was ever asked for.
Iterable<OrdinaryAttempt> ordinaryAttemptsOf(Iterable<AttemptRecord> records) =>
    [
      for (final record in records)
        if (record.closure.measurement case Measured(
          :final outcome,
          :final weights,
        ))
          (exercise: record.exercise, outcome: outcome, weights: weights),
    ];

/// What [attempts] tell the scheduler, in the order they happened.
///
/// The one reading of ordinary history, shared by the app and by anything
/// that simulates it, so the two cannot disagree about what a history
/// implies.
AttemptHistory attemptHistoryOf(
  Iterable<OrdinaryAttempt> attempts, {
  RequirementCompletionPolicy policy = RequirementCompletionPolicy.standard,
}) {
  final attempted = <Exercise>{};
  final retrieved = <(String, Hand)>{};
  final revisions = <ExecutionContext, int>{};
  final shapes = <String, Set<RealizationShape>>{};
  for (final (:exercise, :outcome, :weights) in attempts) {
    final informative = outcome.started && weights.materialExecution > 0;
    if (informative) {
      attempted.add(exercise);
      revisions.update(
        executionContextOf(exercise),
        (revision) => revision + 1,
        ifAbsent: () => 1,
      );
    }
    // The same condition that forms memory. Hands together is both hands
    // producing the scale, so it counts for each.
    if (outcome.retrieval == FactualRetrieval.succeeded) {
      for (final hand in exercise.conditions.hands.hands) {
        retrieved.add((exercise.material.materialId, hand));
      }
    }
    // Structure managed from memory: pitch accuracy is the covering one, and
    // timing is not asked.
    if (!exercise.guidance.isMaterialSupplied &&
        outcome.started &&
        outcome.completed &&
        outcome.pitchIntegrity >= policy.minimumPitchIntegrity) {
      shapes
          .putIfAbsent(exercise.material.materialId, () => {})
          .add(shapeOf(exercise));
    }
  }
  return AttemptHistory(
    attemptedExercises: attempted,
    retrievedMaterialHands: retrieved,
    executionEvidenceRevisions: revisions,
    demonstratedShapes: shapes,
  );
}

/// [attemptHistoryOf] the ordinary attempts in [records].
AttemptHistory attemptHistoryOfRecords(Iterable<AttemptRecord> records) =>
    attemptHistoryOf(ordinaryAttemptsOf(records));
