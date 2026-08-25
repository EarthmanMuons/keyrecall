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
/// rather than evaluation: it says the learner has reached the end of what was
/// asked for, not whether they were right, because a substituted note covers
/// its position exactly as a correct one does.
///
/// Counting arrivals instead would end a corrected attempt one note early,
/// cutting off the end of the traversal to pay for an extra note in the
/// middle.
bool hasCoveredTraversal({
  required Exercise exercise,
  required PerformanceTranscript transcript,
}) {
  if (!isMeasurable(exercise) || transcript.isEmpty) return false;
  return AlignmentReading(
    align(realization: realize(exercise), transcript: transcript),
  ).reachedFinalPosition;
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
