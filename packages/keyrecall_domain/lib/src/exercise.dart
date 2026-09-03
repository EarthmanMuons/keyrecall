import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'competency.dart';
import 'execution_conditions.dart';
import 'guidance_context.dart';
import 'hand_path.dart';
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
const _opportunitySiteSetEquality = SetEquality<MotorOpportunitySite>();

/// One presentable practice task: material, pattern, conditions, guidance, and
/// the motor sites the resulting event structure exposes.
///
/// An exercise is a bundle of independent choices rather than a catalog row.
/// [Exercise.linear] derives [opportunities] from its hand paths and canonical
/// fingering.
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

  /// The exact hand and moment for each derived motor opportunity.
  final Set<MotorOpportunitySite> opportunitySites;

  /// Rehydrates the motor structure persisted with a presented exercise.
  Exercise.recorded({
    required this.material,
    required this.conditions,
    this.pattern = ExercisePattern.linear,
    this.guidance = GuidanceContext.unguided,
    required Set<MotorOpportunity> opportunities,
    Set<MotorOpportunitySite> opportunitySites = const {},
  }) : opportunities = Set.unmodifiable(opportunities),
       opportunitySites = Set.unmodifiable(opportunitySites) {
    final paths = handPathsFor(
      conditions,
      degreesPerOctave: material.topology.degreesPerOctave,
    );
    if (opportunitySites.any(
      (site) => !opportunities.contains(site.opportunity),
    )) {
      throw ArgumentError('every opportunity site must name an opportunity');
    }
    if (opportunitySites.any((site) {
      final path = paths[site.hand];
      return path == null ||
          site.momentIndex <= 0 ||
          site.momentIndex >= path.length;
    })) {
      throw ArgumentError('every opportunity site must name a played moment');
    }
  }

  /// A linear exercise with motor opportunities derived from its realization.
  factory Exercise.linear({
    required TechnicalMaterial material,
    required HandConfiguration hands,
    int octaves = 1,
    ExerciseDirection direction = ExerciseDirection.upDown,
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
    final opportunitySites = MotorOpportunity.sitesForLinearTraversal(
      material,
      conditions,
    );
    return Exercise.recorded(
      material: material,
      conditions: conditions,
      guidance: guidance,
      opportunities: {for (final site in opportunitySites) site.opportunity},
      opportunitySites: opportunitySites,
    );
  }

  /// This exercise with [guidance] replaced and everything else held fixed.
  ///
  /// The only variation recovery and the probes are allowed to make.
  Exercise withGuidance(GuidanceContext guidance) => Exercise.recorded(
    material: material,
    conditions: conditions,
    pattern: pattern,
    guidance: guidance,
    opportunities: opportunities,
    opportunitySites: opportunitySites,
  );

  /// This exercise at [tempoBpm], with everything else held fixed.
  ///
  /// For asking what a task would have been at a different speed, and for the
  /// one place a candidate is built this way: the next tempo rung is a
  /// learner-dependent value, so the static generator has no candidate at it
  /// and the scheduler makes one from the shape beside it.
  Exercise atTempo(double tempoBpm) => Exercise.recorded(
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
    opportunitySites: opportunitySites,
  );

  /// Whether [other] is the same motor task under different guidance.
  bool hasSameRealizationAs(Exercise other) =>
      material == other.material &&
      pattern == other.pattern &&
      conditions == other.conditions &&
      _opportunitySetEquality.equals(opportunities, other.opportunities) &&
      _opportunitySiteSetEquality.equals(
        opportunitySites,
        other.opportunitySites,
      );

  /// `Q[e,k]`: the competencies this exercise creates an opportunity to
  /// observe, generated from its composition.
  ///
  /// A statement about the exercise's structure, not a belief about the
  /// learner, and not affected by guidance: a cued harmonic-minor exercise
  /// still contains harmonic-minor topology.
  ///
  /// Derived once per exercise rather than on each read. A scheduling slot asks
  /// this of ten thousand candidates and several stages ask it of each, so
  /// rebuilding the set every time was a measurable share of a decision for a
  /// value that cannot change.
  late final Set<Competency> structuralQ = Set.unmodifiable({
    material.topologyCompetency,
    ...material.executionCompetenciesFor(conditions.hands),
    for (final opportunity in opportunities) opportunity.competency,
  });

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
    _opportunitySiteSetEquality.hash(opportunitySites),
  );

  @override
  String toString() =>
      'Exercise(${material.materialId}, ${pattern.id}, $conditions, $guidance)';
}
