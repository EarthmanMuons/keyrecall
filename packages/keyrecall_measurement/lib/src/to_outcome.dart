import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'performance_measurement.dart';

/// The outcome [measurement] supports for [exercise].
///
/// The interpretation layer, and the only place measurement meets the learner
/// model's vocabulary. Everything above it is what was observed; everything
/// below it is what the observation is taken to mean.
///
/// Retrieval is forced to [FactualRetrieval.notTested] when the exercise
/// supplied the material throughout, whatever the playing looked like, since
/// succeeding while reading the answer is not evidence of remembering.
///
/// Pulse maintenance is forced to [PulseMaintenance.notTested] the same way
/// when [delivery] supplied any beat once the attempt began; see
/// [PulseMaintenance.under].
Outcome outcomeFor({
  required PerformanceMeasurement measurement,
  required Exercise exercise,
  PresentationDelivery? delivery,
}) {
  final tested = exercise.guidance.isRetrievalObserved;
  return Outcome(
    pulseMaintenance: PulseMaintenance.under(delivery),
    started: measurement.started,
    completed: measurement.completed,
    retrieval: !tested
        ? FactualRetrieval.notTested
        : measurement.retrievedIndependently
        ? FactualRetrieval.succeeded
        : FactualRetrieval.failed,
    materialRetrieval: measurement.materialAppeared,
    pitchIntegrity: measurement.pitchIntegrity,
    topologyAccuracy: measurement.topologyAccuracy,
    continuity: measurement.continuity,
    temporalStability: measurement.temporalStability,
    achievedTempoRatio: measurement.achievedTempoRatioFor(exercise.conditions),
    coordination: measurement.coordination,
  );
}
