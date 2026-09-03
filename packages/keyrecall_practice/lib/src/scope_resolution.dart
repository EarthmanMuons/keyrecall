import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

/// Why a requested goal and focus could not become a practice scope.
enum ScopeResolutionFailureCode {
  duplicateRequirementId,
  unknownMaterial,
  unknownFamily,
  unrealizableRequirement,
  unsupportedCurriculumVersion,
  unresolvedSupport,
  focusOutsideGoal,
  emptyExclusiveFocus,
}

/// One deterministic configuration failure found during scope resolution.
@immutable
class ScopeResolutionFailure {
  final ScopeResolutionFailureCode code;
  final String? requirementId;
  final String reference;

  const ScopeResolutionFailure({
    required this.code,
    required this.reference,
    this.requirementId,
  });
}

/// The result of resolving a goal and focus against the installed catalog.
sealed class ScopeResolution {
  const ScopeResolution();
}

/// A complete structural scope ready for learner-relative evaluation.
final class ValidPracticeScope extends ScopeResolution {
  final ResolvedPracticeScope scope;

  const ValidPracticeScope(this.scope);
}

/// A scope whose requested identities or constraints do not all resolve.
final class InvalidPracticeScope extends ScopeResolution {
  final List<ScopeResolutionFailure> failures;

  InvalidPracticeScope(Iterable<ScopeResolutionFailure> failures)
    : failures = List.unmodifiable(failures);
}

/// Resolves curriculum identities and realizations without reading learner state.
class PracticeScopeResolver {
  final Map<String, Set<String>> supportedVersionsByCurriculumId;

  PracticeScopeResolver({
    Map<String, Set<String>> supportedVersionsByCurriculumId = const {},
  }) : supportedVersionsByCurriculumId = Map.unmodifiable({
         for (final entry in supportedVersionsByCurriculumId.entries)
           entry.key: Set.unmodifiable(entry.value),
       });

  ScopeResolution resolve({
    required PracticeGoal goal,
    required PracticeFocus focus,
    required List<TechnicalMaterial> catalog,
    required InstrumentProfile instrument,
  }) {
    final failures = <ScopeResolutionFailure>[];
    final curriculum = _curriculumFor(goal, catalog);
    final supportedVersions = supportedVersionsByCurriculumId[curriculum.id];
    if (supportedVersions != null &&
        !supportedVersions.contains(curriculum.version)) {
      failures.add(
        ScopeResolutionFailure(
          code: ScopeResolutionFailureCode.unsupportedCurriculumVersion,
          reference: '${curriculum.id}@${curriculum.version}',
        ),
      );
    }

    final requirementsById = <String, CurriculumRequirement>{};
    for (final requirement in curriculum.requirements) {
      if (requirementsById.containsKey(requirement.id)) {
        failures.add(
          ScopeResolutionFailure(
            code: ScopeResolutionFailureCode.duplicateRequirementId,
            requirementId: requirement.id,
            reference: requirement.id,
          ),
        );
      } else {
        requirementsById[requirement.id] = requirement;
      }
    }

    for (final requirement in curriculum.requirements) {
      for (final targetId in requirement.supportsRequirementIds) {
        if (!requirementsById.containsKey(targetId)) {
          failures.add(
            ScopeResolutionFailure(
              code: ScopeResolutionFailureCode.unresolvedSupport,
              requirementId: requirement.id,
              reference: targetId,
            ),
          );
        }
      }
    }

    final focusIds = {
      ...?focus.exclusiveRequirementIds,
      ...focus.emphasisByRequirementId.keys,
    };
    for (final requirementId in focusIds) {
      if (!requirementsById.containsKey(requirementId)) {
        failures.add(
          ScopeResolutionFailure(
            code: ScopeResolutionFailureCode.focusOutsideGoal,
            requirementId: requirementId,
            reference: requirementId,
          ),
        );
      }
    }

    final exclusiveIds = focus.exclusiveRequirementIds;
    if (exclusiveIds != null && exclusiveIds.isEmpty) {
      failures.add(
        const ScopeResolutionFailure(
          code: ScopeResolutionFailureCode.emptyExclusiveFocus,
          reference: 'exclusive focus',
        ),
      );
    }

    final activeTargetIds = {
      for (final requirement in curriculum.requirements)
        if (requirement.role == CurriculumRequirementRole.target &&
            (exclusiveIds == null || exclusiveIds.contains(requirement.id)))
          requirement.id,
    };
    if (exclusiveIds != null && activeTargetIds.isEmpty) {
      failures.add(
        const ScopeResolutionFailure(
          code: ScopeResolutionFailureCode.emptyExclusiveFocus,
          reference: 'exclusive focus targets',
        ),
      );
    }

    final activeRequirements = [
      for (final requirement in curriculum.requirements)
        if (exclusiveIds == null ||
            activeTargetIds.contains(requirement.id) ||
            requirement.supportsRequirementIds.any(activeTargetIds.contains))
          requirement,
    ];

    final catalogById = {
      for (final material in catalog) material.materialId: material,
    };
    final resolved = <ResolvedRequirement>[];
    for (final requirement in activeRequirements) {
      final material = catalogById[requirement.materialId];
      if (material == null) {
        failures.add(
          ScopeResolutionFailure(
            code: ScopeResolutionFailureCode.unknownMaterial,
            requirementId: requirement.id,
            reference: requirement.materialId,
          ),
        );
        continue;
      }
      if (material.familyId != requirement.familyId) {
        failures.add(
          ScopeResolutionFailure(
            code: ScopeResolutionFailureCode.unknownFamily,
            requirementId: requirement.id,
            reference: requirement.familyId,
          ),
        );
        continue;
      }
      final candidates = generateCandidates(instrument, [
        material,
      ]).where(requirement.constraints.matches).toList();
      if (candidates.isEmpty) {
        failures.add(
          ScopeResolutionFailure(
            code: ScopeResolutionFailureCode.unrealizableRequirement,
            requirementId: requirement.id,
            reference: requirement.materialId,
          ),
        );
        continue;
      }
      resolved.add(
        ResolvedRequirement(
          requirement: requirement,
          material: material,
          candidates: candidates,
          emphasis: focus.emphasisByRequirementId[requirement.id] ?? 1,
        ),
      );
    }

    if (failures.isNotEmpty) return InvalidPracticeScope(failures);
    return ValidPracticeScope(
      ResolvedPracticeScope(
        goalId: goal.id,
        curriculumId: curriculum.id,
        curriculumVersion: curriculum.version,
        requirements: resolved,
      ),
    );
  }

  Curriculum _curriculumFor(
    PracticeGoal goal,
    List<TechnicalMaterial> catalog,
  ) {
    final explicit = goal.curriculum;
    if (explicit != null) return explicit;
    final materialIds = goal.targetMaterialIds;
    final selected =
        materialIds ?? {for (final material in catalog) material.materialId};
    return Curriculum(
      id: goal.id,
      version: '1',
      requirements: [
        for (final materialId in selected)
          CurriculumRequirement(
            id: '${goal.id}:$materialId',
            familyId: TechnicalMaterial.scaleFamilyId,
            materialId: materialId,
          ),
      ],
    );
  }
}
