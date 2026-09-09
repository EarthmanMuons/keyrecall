import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// The record [observation] belongs in the acquisition log.
///
/// The one place an observation becomes history. It carries the facts across
/// and nothing else: there is no outcome to derive, no evidence weights to
/// compute, and no learner state to update, which is the whole difference
/// between closing an acquisition attempt and closing an ordinary one.
///
/// The probe verdict is read here, once, and stored. Replay uses what was
/// stored rather than asking again, so a threshold that moves later changes
/// what the next attempt earns and never what a past one did.
AcquisitionAttemptRecord acquisitionRecordOf({
  required AcquisitionObservation observation,
  required AttemptIdentity identity,
  required int journalSequence,
}) => AcquisitionAttemptRecord(
  journalSequence: journalSequence,
  identity: identity,
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
