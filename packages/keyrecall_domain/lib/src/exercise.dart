import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'competency.dart';
import 'execution_conditions.dart';
import 'guidance_context.dart';
import 'motor_opportunity.dart';
import 'technical_material.dart';

/// How an exercise orders and transforms its material.
///
/// V1 ships [linear] only. The seam exists so patterns such as thirds or
/// contrary motion can be added without reinterpreting stored exercises.
enum ExercisePattern {
  /// Straight ascending or ascending-descending traversal.
  linear('LINEAR');

  const ExercisePattern(this.id);

  /// Stable identifier used in persisted state and traces.
  final String id;

  /// The pattern with the given [id].
  ///
  /// Throws [ArgumentError] when no pattern matches.
  static ExercisePattern fromId(String id) => values.firstWhere(
    (pattern) => pattern.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown pattern'),
  );
}

const _opportunitySetEquality = SetEquality<MotorOpportunity>();

/// One presentable practice task: material, pattern, conditions, guidance, and
/// the motor sites the resulting event structure exposes.
///
/// An exercise is a bundle of independent choices rather than a catalog row.
/// The canonical fingering and derived motor structure that would normally
/// supply [opportunities] are not modeled yet, so callers pass them in;
/// [Exercise.linear] applies the provisional structural rule.
@immutable
class Exercise {
  /// What is being played.
  final TechnicalMaterial material;

  /// How the material is ordered.
  final ExercisePattern pattern;

  /// How the exercise is to be performed.
  final ExecutionConditions conditions;

  /// The cues shown before or during the attempt.
  final GuidanceContext guidance;

  /// The observable motor sites this exercise creates.
  final Set<MotorOpportunity> opportunities;

  Exercise({
    required this.material,
    required this.conditions,
    this.pattern = ExercisePattern.linear,
    this.guidance = GuidanceContext.unguided,
    Set<MotorOpportunity> opportunities = const {},
  }) : opportunities = Set.unmodifiable(opportunities);

  /// A linear exercise whose opportunities follow from its conditions.
  ///
  /// The shorthand production code and scenarios use; see
  /// [MotorOpportunity.forLinearTraversal] for what the derivation can and
  /// cannot currently see.
  factory Exercise.linear({
    required TechnicalMaterial material,
    required HandConfiguration hands,
    int octaves = 1,
    ScaleDirection direction = ScaleDirection.upDown,
    HandMotion handMotion = HandMotion.parallel,
    double tempoBpm = 80,
    GuidanceContext guidance = GuidanceContext.unguided,
  }) {
    final conditions = ExecutionConditions(
      hands: hands,
      octaves: octaves,
      direction: direction,
      handMotion: handMotion,
      tempoBpm: tempoBpm,
    );
    return Exercise(
      material: material,
      conditions: conditions,
      guidance: guidance,
      opportunities: MotorOpportunity.forLinearTraversal(conditions),
    );
  }

  /// This exercise with [guidance] replaced and everything else held fixed.
  ///
  /// The only variation recovery and the probes are allowed to make.
  Exercise withGuidance(GuidanceContext guidance) => Exercise(
    material: material,
    conditions: conditions,
    pattern: pattern,
    guidance: guidance,
    opportunities: opportunities,
  );

  /// This exercise at [tempoBpm], with everything else held fixed.
  ///
  /// For asking what a task would have been at a different speed, and for the
  /// one place a candidate is built this way: the next tempo rung is a
  /// learner-dependent value, so the static generator has no candidate at it
  /// and the scheduler makes one from the shape beside it.
  Exercise atTempo(double tempoBpm) => Exercise(
    material: material,
    conditions: ExecutionConditions(
      hands: conditions.hands,
      octaves: conditions.octaves,
      direction: conditions.direction,
      handMotion: conditions.handMotion,
      tempoBpm: tempoBpm,
    ),
    pattern: pattern,
    guidance: guidance,
    opportunities: opportunities,
  );

  /// Whether [other] is the same motor task under different guidance.
  bool hasSameRealizationAs(Exercise other) =>
      material == other.material &&
      pattern == other.pattern &&
      conditions == other.conditions &&
      _opportunitySetEquality.equals(opportunities, other.opportunities);

  /// `Q[e,k]`: the competencies this exercise creates an opportunity to
  /// observe, generated from its composition.
  ///
  /// A statement about the exercise's structure, not a belief about the
  /// learner, and not affected by guidance: a cued harmonic-minor exercise
  /// still contains harmonic-minor topology.
  Set<Competency> get structuralQ => {
    material.form.topologyCompetency,
    ...conditions.hands.executionCompetencies,
    for (final opportunity in opportunities) opportunity.competency,
  };

  @override
  bool operator ==(Object other) =>
      other is Exercise &&
      other.guidance == guidance &&
      hasSameRealizationAs(other);

  @override
  int get hashCode => Object.hash(
    material,
    pattern,
    conditions,
    guidance,
    _opportunitySetEquality.hash(opportunities),
  );

  @override
  String toString() =>
      'Exercise(${material.materialId}, ${pattern.id}, $conditions, $guidance)';
}
