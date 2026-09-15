import 'package:meta/meta.dart';

import 'execution_conditions.dart';
import 'exercise.dart';
import 'technical_material.dart';

/// Whether a curriculum requirement is an outcome or preparation for one.
enum CurriculumRequirementRole { target, support }

/// The realization conditions a curriculum requirement names.
@immutable
class ExerciseConstraints {
  final HandConfiguration? hands;
  final int? octaves;
  final ExerciseDirection? direction;
  final HandMotion? handMotion;
  final double? minimumTempoBpm;

  const ExerciseConstraints({
    this.hands,
    this.octaves,
    this.direction,
    this.handMotion,
    this.minimumTempoBpm,
  });

  /// Whether [exercise] realizes the shape this requirement names.
  ///
  /// Tempo is excluded. [minimumTempoBpm] is a pace to be demonstrated, and
  /// what an attempt demonstrated is measured rather than requested, so an
  /// assessment matches structure here and reads the pace off the outcome.
  bool matchesStructure(Exercise exercise) {
    final conditions = exercise.conditions;
    return (hands == null || conditions.hands == hands) &&
        (octaves == null || conditions.octaves == octaves) &&
        (direction == null || conditions.direction == direction) &&
        (handMotion == null || conditions.handMotion == handMotion);
  }

  /// Whether [exercise] is a realization this requirement asks for, including
  /// the tempo it is presented at.
  bool matches(Exercise exercise) =>
      matchesStructure(exercise) &&
      (minimumTempoBpm == null ||
          exercise.conditions.tempoBpm >= minimumTempoBpm!);
}

/// One stable, independently assessable capability in a curriculum.
@immutable
class CurriculumRequirement {
  final String id;
  final String familyId;
  final String materialId;
  final ExerciseConstraints constraints;
  final CurriculumRequirementRole role;
  final Set<String> supportsRequirementIds;

  factory CurriculumRequirement({
    required String id,
    required String familyId,
    required String materialId,
    ExerciseConstraints constraints = const ExerciseConstraints(),
    CurriculumRequirementRole role = CurriculumRequirementRole.target,
    Set<String> supportsRequirementIds = const {},
  }) => CurriculumRequirement._(
    id: id,
    familyId: familyId,
    materialId: materialId,
    constraints: constraints,
    role: role,
    supportsRequirementIds: Set.unmodifiable(supportsRequirementIds),
  );

  const CurriculumRequirement._({
    required this.id,
    required this.familyId,
    required this.materialId,
    required this.constraints,
    required this.role,
    required this.supportsRequirementIds,
  });
}

/// A versioned body of technical capabilities, independent of learner state.
@immutable
class Curriculum {
  final String id;
  final String version;
  final List<CurriculumRequirement> requirements;

  Curriculum({
    required this.id,
    required this.version,
    required Iterable<CurriculumRequirement> requirements,
  }) : requirements = List.unmodifiable(requirements);
}

/// A temporary restriction or preference applied to a goal.
@immutable
class PracticeFocus {
  final Set<String>? exclusiveRequirementIds;
  final Map<String, double> emphasisByRequirementId;

  factory PracticeFocus({
    Set<String>? exclusiveRequirementIds,
    Map<String, double> emphasisByRequirementId = const {},
  }) {
    for (final emphasis in emphasisByRequirementId.values) {
      if (!emphasis.isFinite || emphasis <= 0) {
        throw ArgumentError.value(
          emphasis,
          'emphasisByRequirementId',
          'weights must be finite and greater than zero',
        );
      }
    }
    return PracticeFocus._(
      exclusiveRequirementIds: exclusiveRequirementIds == null
          ? null
          : Set.unmodifiable(exclusiveRequirementIds),
      emphasisByRequirementId: Map.unmodifiable(emphasisByRequirementId),
    );
  }

  const PracticeFocus._({
    this.exclusiveRequirementIds,
    this.emphasisByRequirementId = const {},
  });

  static const unrestricted = PracticeFocus._();
}

/// How a requirement takes part in one resolved scope.
///
/// Separate from [CurriculumRequirementRole], which is what the curriculum
/// declares. Both can hold at once: a selected target that also prepares
/// another selected target is required for completion and retained as
/// preparation, and an unselected one that prepares a selected target is
/// retained without being required.
enum ResolvedRequirementRole { target, support }

/// One requirement after its material and realizations have resolved.
@immutable
class ResolvedRequirement {
  final CurriculumRequirement requirement;
  final TechnicalMaterial material;
  final List<Exercise> targetCandidates;
  final List<Exercise> candidates;
  final Set<ResolvedRequirementRole> roles;
  final double emphasis;

  ResolvedRequirement({
    required this.requirement,
    required this.material,
    Iterable<Exercise>? targetCandidates,
    required Iterable<Exercise> candidates,
    Set<ResolvedRequirementRole> roles = const {ResolvedRequirementRole.target},
    this.emphasis = 1,
  }) : targetCandidates = List.unmodifiable(targetCandidates ?? candidates),
       candidates = List.unmodifiable(candidates),
       roles = Set.unmodifiable(roles);

  /// Whether completing this requirement is part of completing the goal.
  bool get isTarget => roles.contains(ResolvedRequirementRole.target);

  /// Whether this requirement is retained as preparation for a target.
  bool get isSupport => roles.contains(ResolvedRequirementRole.support);
}

/// The distinct candidates [requirements] resolve to, in requirement order.
///
/// Requirements over one material resolve to equal candidate sets, because
/// generation reads the material and the instrument and nothing else, so the
/// material is the identity that dedupes them.
List<Exercise> distinctCandidatesOf(
  Iterable<ResolvedRequirement> requirements,
) {
  final seen = <String>{};
  return [
    for (final requirement in requirements)
      if (seen.add(requirement.material.materialId)) ...requirement.candidates,
  ];
}

/// A valid structural practice scope, before learner-relative evaluation.
@immutable
class ResolvedPracticeScope {
  final String goalId;
  final String curriculumId;
  final String curriculumVersion;
  final bool isNarrow;
  final List<ResolvedRequirement> requirements;

  ResolvedPracticeScope({
    required this.goalId,
    required this.curriculumId,
    required this.curriculumVersion,
    required this.isNarrow,
    required Iterable<ResolvedRequirement> requirements,
  }) : requirements = List.unmodifiable(requirements);

  /// The requirements completing this scope means completing.
  Iterable<ResolvedRequirement> get targets =>
      requirements.where((resolved) => resolved.isTarget);

  /// The requirements retained as preparation for those targets.
  Iterable<ResolvedRequirement> get supports =>
      requirements.where((resolved) => resolved.isSupport);

  Set<String> get targetRequirementIds => {
    for (final resolved in targets) resolved.requirement.id,
  };

  Set<String> get supportRequirementIds => {
    for (final resolved in supports) resolved.requirement.id,
  };
}
