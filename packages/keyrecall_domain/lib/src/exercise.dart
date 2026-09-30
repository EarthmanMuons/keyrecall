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
/// V1 ships [linear] only. The separate axis keeps a future pattern from
/// reinterpreting stored exercises.
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

  final _MotorStructure _structure;

  /// The observable motor sites this exercise creates.
  Set<MotorOpportunity> get opportunities => _structure.opportunities;

  /// The exact hand and moment for each derived motor opportunity.
  Set<MotorOpportunitySite> get opportunitySites => _structure.sites;

  /// Rehydrates the motor structure persisted with a presented exercise.
  Exercise.recorded({
    required this.material,
    required this.conditions,
    this.pattern = ExercisePattern.linear,
    this.guidance = GuidanceContext.unguided,
    required Set<MotorOpportunity> opportunities,
    Set<MotorOpportunitySite> opportunitySites = const {},
  }) : _structure = _MotorStructure(opportunities, opportunitySites) {
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

  /// A variant of [source] that shares its already validated motor structure,
  /// which neither tempo nor guidance can change.
  Exercise._variant(
    Exercise source, {
    required this.conditions,
    required this.guidance,
  }) : material = source.material,
       pattern = source.pattern,
       _structure = source._structure;

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
  Exercise withGuidance(GuidanceContext guidance) =>
      Exercise._variant(this, conditions: conditions, guidance: guidance);

  /// This exercise at [tempoBpm], with everything else held fixed.
  ///
  /// The next tempo rung is learner-dependent, so no static candidate sits at
  /// it and the scheduler builds one from the shape beside it.
  Exercise atTempo(double tempoBpm) => Exercise._variant(
    this,
    conditions: ExecutionConditions(
      hands: conditions.hands,
      octaves: conditions.octaves,
      direction: conditions.direction,
      handMotion: conditions.handMotion,
      tempoBpm: tempoBpm,
    ),
    guidance: guidance,
  );

  /// Whether [other] is the same motor task under different guidance.
  bool hasSameRealizationAs(Exercise other) =>
      material == other.material &&
      pattern == other.pattern &&
      conditions == other.conditions &&
      _structure.sameAs(other._structure);

  /// `Q[e,k]`: the competencies this exercise creates an opportunity to
  /// observe, generated from its composition.
  ///
  /// A statement about the exercise's structure, not a belief about the
  /// learner, and not affected by guidance: a cued harmonic-minor exercise
  /// still contains harmonic-minor topology.
  ///
  /// Derived once, since a scheduling slot asks this of every candidate at
  /// several stages and the answer cannot change.
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

  /// Computed once: scheduling hashes every candidate repeatedly.
  @override
  late final int hashCode = Object.hash(
    material,
    pattern,
    conditions,
    guidance,
    _structure.opportunitiesHash,
    _structure.sitesHash,
  );

  @override
  String toString() =>
      'Exercise(${material.materialId}, ${pattern.id}, $conditions, $guidance)';
}

/// The motor opportunities of an exercise, shared by its tempo and guidance
/// variants so that comparing and hashing them happens once per shape.
class _MotorStructure {
  final Set<MotorOpportunity> opportunities;
  final Set<MotorOpportunitySite> sites;

  _MotorStructure(
    Set<MotorOpportunity> opportunities,
    Set<MotorOpportunitySite> sites,
  ) : opportunities = Set.unmodifiable(opportunities),
      sites = Set.unmodifiable(sites);

  late final int opportunitiesHash = _opportunitySetEquality.hash(
    opportunities,
  );
  late final int sitesHash = _opportunitySiteSetEquality.hash(sites);

  bool sameAs(_MotorStructure other) =>
      identical(this, other) ||
      opportunitiesHash == other.opportunitiesHash &&
          sitesHash == other.sitesHash &&
          _opportunitySetEquality.equals(opportunities, other.opportunities) &&
          _opportunitySiteSetEquality.equals(sites, other.sites);
}
