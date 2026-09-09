import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

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
/// The probe verdict is read here, once, and stored. Replay uses what was
/// stored rather than asking again, so a threshold that moves later changes
/// what the next attempt earns and never what a past one did.
AcquisitionAttemptRecord acquisitionRecordOf({
  required AcquisitionObservation observation,
  required AttemptIdentity identity,
  required int journalSequence,
  AttemptTermination termination = AttemptTermination.learnerStopped,
}) => AcquisitionAttemptRecord(
  journalSequence: journalSequence,
  identity: identity,
  termination: termination,
  task: observation.task,
  started: observation.started,
  completion: observation.completion,
  repairs: observation.repairs,
  repeats: observation.repeats,
  intrusions: observation.intrusions,
  firstAbsentPosition: observation.firstAbsentPosition,
  earnedProbe: observation.earnsParentProbe,
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

/// The service record an ordinary presentation of [presented] owes, or null
/// when it owes none.
///
/// Tied to presentation rather than to why the scheduler chose it. A parent can
/// reach the learner because the service phase served an owed probe or because
/// ordinary ranking happened to pick it, and either way the question has been
/// asked. Discharging only the first would leave the obligation open after the
/// learner had already answered it, and the next slot would ask it again.
///
/// Nothing is written when no probe is owed. A parent with acquisition history
/// that has earned nothing, or whose obligation a previous presentation already
/// discharged, is ordinary work like any other, and a record of service that
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
}) => progress.probeOwed(presented)
    ? AcquisitionProbeServedRecord(
        journalSequence: journalSequence,
        identity: identity,
        parent: presented,
      )
    : null;

/// Exact ordinary tasks that produced informative execution evidence.
///
/// Rebuilt from ordinary history; acquisition history cannot establish that an
/// ordinary realization was ever asked for.
///
/// Exact, and read by two rules that both need it to be. Acquisition asks
/// whether the declared floor itself was attempted, and introduction order asks
/// whether a material and hand has been asked for ascending before it is asked
/// for up and down. A near-enough exercise answers neither.
Set<Exercise> attemptedExercises(Iterable<AttemptRecord> records) => {
  for (final record in records)
    if (record.closure.measurement case Measured(
      :final outcome,
      :final weights,
    ))
      if (outcome.started && weights.materialExecution > 0) record.exercise,
};
