import 'package:collection/collection.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'outcome.dart';

const _weightMapEquality = MapEquality<Competency, double>();

/// How informative one attempt actually was, per state layer.
///
/// Distinct from the structural `Q`, which only says an exercise *could* teach
/// something: a weight can be zero where `Q` is one. Three separate quantities
/// rather than one confidence score, so an attempt can be strong execution
/// evidence and no retrieval evidence at all.
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

  /// Throws [ArgumentError] for a weight that is not a finite `[0, 1]`
  /// informativeness.
  ///
  /// Weights reach the update path as multipliers on means, variances, and
  /// log-space durabilities, where an unchecked NaN would pass every guard and
  /// land in state.
  EvidenceWeights({
    required Map<Competency, double> competencies,
    required this.materialExecution,
    required this.materialMemory,
  }) : competencies = Map.unmodifiable({
         for (final competency in Competency.values)
           if (competencies[competency] case final weight?)
             competency: _checked(weight, competency.id),
       }) {
    _checked(materialExecution, 'materialExecution');
    _checked(materialMemory, 'materialMemory');
  }

  static double _checked(double weight, String name) {
    if (!weight.isFinite || weight < 0 || weight > 1) {
      throw ArgumentError.value(weight, name, 'must be in the range 0 to 1');
    }
    return weight;
  }

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
/// Parameter-free: the weights follow from what the attempt could observe.
EvidenceWeights evidenceWeightsFor(Exercise exercise, Outcome outcome) {
  if (!outcome.started) {
    // Informative about memory, almost nothing about execution, and nothing at
    // all when retrieval was not being tested.
    //
    // The memory weight is flat rather than scaled by retrievalDemand, so an
    // unstarted previewed attempt (0.8) outweighs a completed one (0.6): the
    // material was put in front of the learner and still produced nothing, and
    // the demand discount exists to discount what support made easy.
    return EvidenceWeights(
      competencies: const {},
      materialExecution: 0.0,
      materialMemory: outcome.retrieval.isTested ? 0.8 : 0.0,
    );
  }

  final executionWeight = outcome.completed ? 1.0 : 0.4;
  final retrievalDemand = exercise.guidance.retrievalDemand;

  // Topology is a pitch-knowledge question like memory, so a cued attempt says
  // little about it. Motor competencies are unaffected, since cueing does not
  // move the learner's hands.
  //
  // Coordination is omitted unless the attempt measured it: two hands create
  // the opportunity, and the performance decides whether it was observed.
  final competencyWeights = {
    for (final competency in Competency.values)
      if (exercise.structuralQ.contains(competency) &&
          (!coordinationCompetencies.contains(competency) ||
              outcome.coordination != null))
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
