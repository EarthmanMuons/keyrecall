import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

/// Resolves candidates and safe entries for one technical-material family.
abstract interface class PracticeMaterialFamily {
  String get familyId;

  double get entryTempoBpm;

  List<Exercise> generate(
    InstrumentProfile instrument,
    TechnicalMaterial material,
  );

  AcquisitionFloor acquisitionFloorFor(
    Iterable<AcquisitionFloorRequest> requests,
  );
}

/// The scale family's curriculum-resolution contract.
class ScalePracticeMaterialFamily implements PracticeMaterialFamily {
  const ScalePracticeMaterialFamily();

  @override
  String get familyId => TechnicalMaterial.scaleFamilyId;

  @override
  double get entryTempoBpm => generatedTempi.first;

  @override
  List<Exercise> generate(
    InstrumentProfile instrument,
    TechnicalMaterial material,
  ) => generateCandidates(instrument, [material]);

  @override
  AcquisitionFloor acquisitionFloorFor(
    Iterable<AcquisitionFloorRequest> requests,
  ) => scaleAcquisitionFloorFor(requests);
}

enum ArpeggioAcquisitionFloorShape {
  rightHandAscending,
  separateHandsAscending,
  rightHandAscendingAndDescending,
}

@immutable
class ArpeggioPracticePolicy {
  final double initialTempoBpm;
  final ArpeggioAcquisitionFloorShape acquisitionFloorShape;

  const ArpeggioPracticePolicy({
    this.initialTempoBpm = 60,
    this.acquisitionFloorShape =
        ArpeggioAcquisitionFloorShape.rightHandAscending,
  }) : assert(initialTempoBpm > 0);
}

/// The minimal arpeggio family's curriculum-resolution contract.
class ArpeggioPracticeMaterialFamily implements PracticeMaterialFamily {
  final ArpeggioPracticePolicy policy;

  const ArpeggioPracticeMaterialFamily({
    this.policy = const ArpeggioPracticePolicy(),
  });

  @override
  String get familyId => TechnicalMaterial.arpeggioFamilyId;

  @override
  double get entryTempoBpm => policy.initialTempoBpm;

  @override
  List<Exercise> generate(
    InstrumentProfile instrument,
    TechnicalMaterial material,
  ) => _generateArpeggioCandidates(
    instrument,
    material as ArpeggioMaterial,
    policy,
  );

  @override
  AcquisitionFloor acquisitionFloorFor(
    Iterable<AcquisitionFloorRequest> requests,
  ) => _arpeggioAcquisitionFloorFor(requests, policy);
}

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
  noTargetRequirements,
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
  final PracticeEntryPolicy entryPolicy;

  const ValidPracticeScope(this.scope, {required this.entryPolicy});
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
  final Map<String, PracticeMaterialFamily> _families;

  PracticeScopeResolver({
    Map<String, Set<String>> supportedVersionsByCurriculumId = const {},
    Iterable<PracticeMaterialFamily> families = const [
      ScalePracticeMaterialFamily(),
      ArpeggioPracticeMaterialFamily(),
    ],
  }) : supportedVersionsByCurriculumId = Map.unmodifiable({
         for (final entry in supportedVersionsByCurriculumId.entries)
           entry.key: Set.unmodifiable(entry.value),
       }),
       _families = Map.unmodifiable({
         for (final family in families) family.familyId: family,
       });

  AcquisitionFloor acquisitionFloorFor(
    Iterable<ResolvedRequirement> requirements,
  ) {
    final resolved = requirements.toList();
    return AcquisitionFloor([
      for (final family in _families.values)
        ...family.acquisitionFloorFor([
          for (final requirement in resolved)
            if (requirement.requirement.familyId == family.familyId)
              AcquisitionFloorRequest(
                requirementId: requirement.requirement.id,
                candidates: requirement.candidates,
              ),
        ]).entries,
    ]);
  }

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
    if (activeTargetIds.isEmpty) {
      failures.add(
        ScopeResolutionFailure(
          code: exclusiveIds == null
              ? ScopeResolutionFailureCode.noTargetRequirements
              : ScopeResolutionFailureCode.emptyExclusiveFocus,
          reference: exclusiveIds == null
              ? 'curriculum targets'
              : 'exclusive focus targets',
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
      final family = _families[requirement.familyId];
      if (family == null || material.familyId != family.familyId) {
        failures.add(
          ScopeResolutionFailure(
            code: ScopeResolutionFailureCode.unknownFamily,
            requirementId: requirement.id,
            reference: requirement.familyId,
          ),
        );
        continue;
      }
      final candidates = family.generate(instrument, material);
      final targetCandidates = candidates
          .where(requirement.constraints.matches)
          .toList();
      if (targetCandidates.isEmpty) {
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
          targetCandidates: targetCandidates,
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
        isNarrow: goal.isScoped || focus.exclusiveRequirementIds != null,
        requirements: resolved,
      ),
      entryPolicy: PracticeEntryPolicy.byFamily({
        for (final familyId in {
          for (final requirement in activeRequirements) requirement.familyId,
        })
          if (_families[familyId] case final family?)
            familyId: family.entryTempoBpm,
      }, defaultTempoBpm: generatedTempi.first),
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
    final catalogById = {
      for (final material in catalog) material.materialId: material,
    };
    return Curriculum(
      id: goal.id,
      version: '1',
      requirements: [
        for (final materialId in selected)
          CurriculumRequirement(
            id: '${goal.id}:$materialId',
            familyId: catalogById[materialId]?.familyId ?? '',
            materialId: materialId,
          ),
      ],
    );
  }
}

List<Exercise> _generateArpeggioCandidates(
  InstrumentProfile instrument,
  ArpeggioMaterial material,
  ArpeggioPracticePolicy policy,
) => [
  for (final hands in HandConfiguration.values)
    if (_hasCanonicalFingering(material, hands))
      for (final octaves in material.progression.octaveSpans)
        if (instrument.supportsOctaveSpan(octaves))
          for (final direction in _arpeggioDirections(policy))
            for (final guidance in GuidanceContext.ladder)
              Exercise.linear(
                material: material,
                hands: hands,
                octaves: octaves,
                direction: direction,
                tempoBpm: policy.initialTempoBpm,
                guidance: guidance,
              ),
];

List<ExerciseDirection> _arpeggioDirections(ArpeggioPracticePolicy policy) =>
    policy.acquisitionFloorShape ==
        ArpeggioAcquisitionFloorShape.rightHandAscendingAndDescending
    ? const [ExerciseDirection.up, ExerciseDirection.upDown]
    : const [ExerciseDirection.up];

bool _hasCanonicalFingering(
  ArpeggioMaterial material,
  HandConfiguration hands,
) =>
    (!hands.usesRightHand ||
        canonicalFingering(material, Hand.right) != null) &&
    (!hands.usesLeftHand || canonicalFingering(material, Hand.left) != null);

AcquisitionFloor _arpeggioAcquisitionFloorFor(
  Iterable<AcquisitionFloorRequest> requests,
  ArpeggioPracticePolicy policy,
) => AcquisitionFloor([
  for (final request in requests)
    for (final exercise in request.candidates)
      if (_isFloorHand(exercise.conditions.hands, policy) &&
          exercise.conditions.octaves == 1 &&
          exercise.conditions.direction == _floorDirection(policy) &&
          exercise.conditions.tempoBpm == policy.initialTempoBpm &&
          exercise.guidance == GuidanceContext.continuouslyCued)
        AcquisitionFloorEntry(
          requirementId: request.requirementId,
          exercise: exercise,
        ),
]);

bool _isFloorHand(HandConfiguration hands, ArpeggioPracticePolicy policy) =>
    switch (policy.acquisitionFloorShape) {
      ArpeggioAcquisitionFloorShape.rightHandAscending ||
      ArpeggioAcquisitionFloorShape.rightHandAscendingAndDescending =>
        hands == HandConfiguration.right,
      ArpeggioAcquisitionFloorShape.separateHandsAscending =>
        hands != HandConfiguration.together,
    };

ExerciseDirection _floorDirection(ArpeggioPracticePolicy policy) =>
    policy.acquisitionFloorShape ==
        ArpeggioAcquisitionFloorShape.rightHandAscendingAndDescending
    ? ExerciseDirection.upDown
    : ExerciseDirection.up;
