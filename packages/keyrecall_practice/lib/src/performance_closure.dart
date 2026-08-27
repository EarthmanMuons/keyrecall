import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:meta/meta.dart';

/// What can be read from a performance of an exercise.
///
/// The orchestration boundary. `measure` is not broadly fallible, so deciding
/// that an attempt cannot be measured happens here, once, with a reason naming
/// the missing capability rather than a generic failure.
@immutable
sealed class PerformanceReading {
  const PerformanceReading();
}

/// The performance was measured.
@immutable
final class PerformanceMeasured extends PerformanceReading {
  /// What was observed.
  final PerformanceMeasurement measurement;

  /// What the observation means in the model's vocabulary.
  final Outcome outcome;

  const PerformanceMeasured({required this.measurement, required this.outcome});
}

/// The observation model cannot read this attempt.
@immutable
final class PerformanceUnmeasurable extends PerformanceReading {
  /// Which capability is missing.
  final MeasurementUnavailableReason reason;

  const PerformanceUnmeasurable(this.reason);
}

/// Whether the observation model can read a performance of [exercise].
///
/// What production may present. An exercise that cannot be measured produces
/// no evidence, so scheduling one spends a practice slot and teaches the model
/// nothing; the honest response is not to offer it until the capability
/// exists. [PerformanceUnmeasurable] stays as the defensive answer for an
/// attempt that reaches closure anyway, such as a pending decision recovered
/// from a build whose supported set was wider.
bool isMeasurable(Exercise exercise) => realize(exercise).hands.length == 1;

/// Whether a performance of [exercise] has covered the whole traversal.
///
/// What a screen asks to know whether the attempt is over. Interaction state
/// rather than evaluation: it says the learner has been through what was asked
/// for, not whether they were right, because a substituted note covers its
/// position exactly as a correct one does.
///
/// The criterion is [AlignmentReading.isComplete]: every expected position was
/// accounted for by something that arrived. Reaching the final position is not
/// enough on its own, and asking the aligner alone to answer a lifecycle
/// question was the mistake. It looks for the cheapest explanation of what
/// arrived, and for a scale ending on a note it does not start on, the
/// cheapest explanation of one played note can be "this was the last one, and
/// everything before it was missed" -- true, cheaper than any alternative, and
/// not somebody finishing.
///
/// A traversal's worth of wrong notes does end the attempt, and that is a
/// decision rather than an oversight. Under the alignment policy a
/// substitution costs less than dropping one note and adding another, so any
/// transcript that long accounts for every position whatever it contains: at
/// that point "played it badly" and "played something else" differ only in
/// whether the notes were right, which is correctness, which no rung permits
/// reading, and which would turn the app's silence into a verdict.
///
/// So this separates progress from correctness exactly as far as it can, and
/// the guarantee it makes is the one that matters: an attempt that has not
/// been through the exercise does not end on its own, however cheaply the
/// aligner can explain what arrived as having arrived at the end.
///
/// A learner who genuinely leaves notes out finishes with Done, which is
/// always there.
bool hasCoveredTraversal({
  required Exercise exercise,
  required PerformanceTranscript transcript,
}) {
  if (!isMeasurable(exercise)) return false;
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
/// Never unmeasurable because a performance was poor. A learner who played
/// nothing recognizable produces a measured attempt with bad numbers, which is
/// evidence; refusing to measure it would drop exactly the observations the
/// model most needs. Only a missing capability makes it unreadable, and when
/// observation grouping exists the hands-together case disappears from here
/// without anything else changing.
PerformanceReading readPerformance({
  required Exercise exercise,
  required PerformanceTranscript transcript,
  MeasurementPolicy policy = MeasurementPolicy.standard,
}) {
  if (!isMeasurable(exercise)) {
    return const PerformanceUnmeasurable(
      MeasurementUnavailableReason.handsTogetherCorrespondence,
    );
  }

  final measurement = measure(
    realization: realize(exercise),
    transcript: transcript,
    policy: policy,
  );
  return PerformanceMeasured(
    measurement: measurement,
    outcome: outcomeFor(measurement: measurement, exercise: exercise),
  );
}
