import 'package:collection/collection.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'outcome.dart';

const _weightMapEquality = MapEquality<Competency, double>();

/// How informative one attempt actually was, per state layer.
///
/// Distinct from the structural `Q`, which only says an exercise *could* teach
/// us something. A weight can be zero even where `Q` is one: failure to begin
/// because the notes could not be recalled says very little about motor
/// execution.
///
/// These are three separate quantities, not one confidence score. An attempt
/// can be strong execution evidence and no retrieval evidence at all.
@immutable
class EvidenceWeights {
  /// `w[a,k]`: per-competency informativeness, in `[0, 1]`.
  ///
  /// Competencies the attempt says nothing about are absent rather than
  /// mapped to zero; read with a `?? 0.0` fallback.
  final Map<Competency, double> competencies;

  /// `w_r`: informativeness about the execution residual, in `[0, 1]`.
  final double materialExecution;

  /// `w_M`: informativeness about material memory, in `[0, 1]`.
  final double materialMemory;

  EvidenceWeights({
    required Map<Competency, double> competencies,
    required this.materialExecution,
    required this.materialMemory,
  }) : competencies = Map.unmodifiable(competencies);

  /// The weight this attempt carries for [competency].
  double operator [](Competency competency) => competencies[competency] ?? 0.0;

  @override
  bool operator ==(Object other) =>
      other is EvidenceWeights &&
      other.materialExecution == materialExecution &&
      other.materialMemory == materialMemory &&
      _weightMapEquality.equals(other.competencies, competencies);

  @override
  int get hashCode => Object.hash(
    materialExecution,
    materialMemory,
    _weightMapEquality.hash(competencies),
  );

  @override
  String toString() =>
      'EvidenceWeights(execution: ${materialExecution.toStringAsFixed(2)}, '
      'memory: ${materialMemory.toStringAsFixed(2)}, '
      '${competencies.length} competencies)';
}

/// How much [outcome] on [exercise] tells us about each state layer.
///
/// Parameter-free by design: the weights follow from what the attempt could
/// observe, not from tunable constants.
EvidenceWeights evidenceWeightsFor(Exercise exercise, Outcome outcome) {
  if (!outcome.started) {
    // Informative about memory, almost nothing about execution, unless
    // retrieval was not being tested at all, in which case there is no memory
    // evidence either.
    //
    // The memory weight here is deliberately flat rather than scaled by
    // retrievalDemand, which is why an unstarted previewed attempt (0.8)
    // outweighs a completed one (0.6). Under a preview the material was put in
    // front of the learner and still produced nothing, so the failure to begin
    // is about as decisive as an unguided one; the demand discount exists to
    // discount what support made easy, and nothing was made easy here.
    return EvidenceWeights(
      competencies: const {},
      materialExecution: 0.0,
      materialMemory: outcome.retrieval.isTested ? 0.8 : 0.0,
    );
  }

  final executionWeight = outcome.completed ? 1.0 : 0.4;
  final retrievalDemand = exercise.guidance.retrievalDemand;

  // Topology is a pitch-knowledge question like memory, so a cued attempt is
  // barely informative about it. Motor competencies are unaffected: cueing
  // does not move the learner's hands for them.
  final competencyWeights = {
    for (final competency in exercise.structuralQ)
      competency: competency.isTopology
          ? executionWeight * retrievalDemand
          : executionWeight,
  };

  return EvidenceWeights(
    competencies: competencyWeights,
    materialExecution: executionWeight,
    materialMemory: outcome.retrieval.isTested
        ? retrievalDemand * (outcome.completed ? 1.0 : 0.6)
        : 0.0,
  );
}
