/// Turns an aligned performance into what was observed, and into the outcome
/// the learner model consumes.
///
/// Two layers. [PerformanceMeasurement] is factual: how much of the material
/// appeared, how much of it sounded right, and how the playing sat in time.
/// [outcomeFor] is the interpretation, and the only place those facts meet the
/// learner model's vocabulary.
///
/// Correspondence comes first, and timing is read off notes whose
/// correspondence is already settled. [TimingEvidence] is the one reading of it,
/// so ordinary measurement, acquisition, and the transition census cannot
/// disagree about which waits happened or which of them could be judged.
library;

export 'src/acquisition_observation.dart';
export 'src/measurement_policy.dart';
export 'src/performance_measurement.dart';
export 'src/timing_evidence.dart';
export 'src/to_outcome.dart';
export 'src/transition_census.dart';
