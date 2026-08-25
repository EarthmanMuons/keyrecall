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
  final realization = realize(exercise);
  if (realization.hands.length > 1) {
    return const PerformanceUnmeasurable(
      MeasurementUnavailableReason.handsTogetherCorrespondence,
    );
  }

  final measurement = measure(
    realization: realization,
    transcript: transcript,
    policy: policy,
  );
  return PerformanceMeasured(
    measurement: measurement,
    outcome: outcomeFor(measurement: measurement, exercise: exercise),
  );
}
