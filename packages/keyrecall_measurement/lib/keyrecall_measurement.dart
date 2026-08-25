/// Turns an aligned performance into what was observed, and into the outcome
/// the learner model consumes.
///
/// Two layers, deliberately apart. [PerformanceMeasurement] is factual: how
/// much of the material appeared, how much of it sounded right, how much of it
/// was the right scale degree, and how the playing sat in time. [outcomeFor] is
/// the interpretation, and the only place those facts meet the learner model's
/// vocabulary.
///
/// Correspondence comes first and uses pitch alone. Timing is read off notes
/// whose correspondence is already settled, so the same notes played at a
/// different speed align identically and measure differently.
library;

export 'src/measurement_policy.dart';
export 'src/performance_measurement.dart';
export 'src/to_outcome.dart';
