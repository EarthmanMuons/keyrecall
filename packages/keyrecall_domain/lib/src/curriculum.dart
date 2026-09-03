import 'package:meta/meta.dart';

import 'exercise.dart';
import 'execution_conditions.dart';
import 'technical_material.dart';

/// Whether a curriculum requirement is an outcome or preparation for one.
enum CurriculumRequirementRole { target, support }

/// The realization conditions a curriculum requirement names.
@immutable
class ExerciseConstraints {
  final HandConfiguration? hands;
  final int? octaves;
  final ScaleDirection? direction;
  final HandMotion? handMotion;
  final double? minimumTempoBpm;

  const ExerciseConstraints({
    this.hands,
    this.octaves,
    this.direction,
    this.handMotion,
    this.minimumTempoBpm,
  });

  bool matches(Exercise exercise) {
    final conditions = exercise.conditions;
    return (hands == null || conditions.hands == hands) &&
        (octaves == null || conditions.octaves == octaves) &&
        (direction == null || conditions.direction == direction) &&
        (handMotion == null || conditions.handMotion == handMotion) &&
        (minimumTempoBpm == null || conditions.tempoBpm >= minimumTempoBpm!);
  }
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

/// One requirement after its material and realizations have resolved.
@immutable
class ResolvedRequirement {
  final CurriculumRequirement requirement;
  final TechnicalMaterial material;
  final List<Exercise> targetCandidates;
  final List<Exercise> candidates;
  final double emphasis;

  ResolvedRequirement({
    required this.requirement,
    required this.material,
    Iterable<Exercise>? targetCandidates,
    required Iterable<Exercise> candidates,
    this.emphasis = 1,
  }) : targetCandidates = List.unmodifiable(targetCandidates ?? candidates),
       candidates = List.unmodifiable(candidates);
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

  Iterable<ResolvedRequirement> get targets => requirements.where(
    (resolved) => resolved.requirement.role == CurriculumRequirementRole.target,
  );
}
