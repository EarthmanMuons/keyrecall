import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:meta/meta.dart';

/// What was read from a performance of an exercise.
///
/// The orchestration boundary: what the observation model saw, and what that
/// means in the learner model's vocabulary.
@immutable
class PerformanceReading {
  /// What was observed.
  final PerformanceMeasurement measurement;

  /// What the observation means in the model's vocabulary.
  final Outcome outcome;

  const PerformanceReading({required this.measurement, required this.outcome});
}

/// A committed attempt, and the reading it was committed from.
///
/// Two lifetimes in one place. The record is history and outlives the sitting;
/// the reading is the correspondence behind it, which nothing persists, so
/// this is the only moment anything can ask it where a fault happened.
@immutable
class ClosedAttempt {
  /// What history now says about the attempt.
  final AttemptRecord record;

  /// What that was read from.
  final PerformanceReading reading;

  const ClosedAttempt({required this.record, required this.reading});
}

/// Whether a performance of [exercise] has covered the whole traversal.
///
/// What a screen asks to know whether the attempt is over. Interaction state
/// rather than evaluation: it says the learner has been through what was asked
/// for, not whether they were right, because a substituted note covers its
/// position exactly as a correct one does.
///
/// The criterion is [AlignmentReading.isComplete]: every expected position was
/// accounted for by something that arrived. Reaching the final position is not
/// enough on its own, because the aligner looks for the cheapest explanation of
/// what arrived, and for a scale ending on a note it does not start on, one
/// played note can be explained as "the last one, everything before it missed".
///
/// A traversal's worth of wrong notes does end the attempt, deliberately. A
/// substitution costs less than a deletion plus an insertion, so a transcript
/// that long accounts for every position whatever it contains, and separating
/// it from a good performance would mean reading correctness, which no rung
/// permits.
///
/// A learner who genuinely leaves notes out finishes with Done, which is always
/// there.
bool hasCoveredTraversal({
  required Exercise exercise,
  required PerformanceTranscript transcript,
}) {
  final realization = realize(exercise);
  // Every position needs its own observation, so anything shorter cannot be
  // complete. Checked first because this runs on every note that arrives and
  // alignment is quadratic.
  if (transcript.length < realization.noteCount) return false;
  return AlignmentReading(
    align(realization: realization, transcript: transcript),
  ).isComplete;
}

/// Reads [transcript] as a performance of [exercise].
///
/// Never fails on a poor performance. A learner who played nothing
/// recognizable produces a measured attempt with bad numbers, which is
/// evidence; refusing to measure it would drop exactly the observations the
/// model most needs.
PerformanceReading readPerformance({
  required Exercise exercise,
  required PerformanceTranscript transcript,
  MeasurementPolicy policy = MeasurementPolicy.standard,
}) {
  final measurement = measure(
    realization: realize(exercise),
    transcript: transcript,
    policy: policy,
  );
  return PerformanceReading(
    measurement: measurement,
    outcome: outcomeFor(measurement: measurement, exercise: exercise),
  );
}
