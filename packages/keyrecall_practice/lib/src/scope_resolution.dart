import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
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

/// The requirement id a goal with no curriculum of its own gives [materialId].
///
/// A goal that names materials rather than a curriculum still has to produce
/// requirements a focus can name, so the scheme is public: nothing else can
/// address them.
String catalogRequirementId(String goalId, String materialId) =>
    '$goalId:$materialId';

/// Why a requested goal and focus could not become a practice scope.
enum ScopeResolutionFailureCode {
  /// A stored goal identifier no goal in this build answers to.
  unknownGoal,

  /// A stored focus naming material vocabulary this build has no meaning for.
  unreadableFocus,

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

/// Resolves curriculum identities and realizations without reading learner
/// state.
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

    // What completing this scope means. A requirement outside an exclusive
    // focus is never one of these, however the curriculum declared it: it can
    // still be retained as preparation, and preparation is not a completion
    // target.
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

    final catalogById = {
      for (final material in catalog) material.materialId: material,
    };
    final declaredSupportIds = _supportersOf(
      activeTargetIds,
      curriculum.requirements,
    );
    final retained = [
      for (final requirement in curriculum.requirements)
        if (exclusiveIds == null ||
            activeTargetIds.contains(requirement.id) ||
            declaredSupportIds.contains(requirement.id))
          requirement,
    ];
    final prerequisites = _prerequisiteSupportFor(
      retained,
      curriculum,
      catalogById,
    );
    final supportIds = {
      ...declaredSupportIds,
      for (final requirement in prerequisites) requirement.id,
    };
    final activeRequirements = [
      ...retained,
      for (final requirement in prerequisites)
        if (!retained.contains(requirement)) requirement,
    ];
    // What each material is offered as: the way to whatever the scope asks of
    // it. A support is offered on the way to what it prepares rather than to a
    // shape of its own, so a finite goal holds nothing its targets do not lead
    // to, and a goal naming no shape offers everything.
    final activeById = {
      for (final requirement in activeRequirements) requirement.id: requirement,
    };
    final envelopeByMaterial = <String, List<ExerciseConstraints>>{};
    for (final requirement in activeRequirements) {
      final dependents = activeTargetIds.contains(requirement.id)
          ? const <CurriculumRequirement>[]
          : [
              for (final id in requirement.supportsRequirementIds)
                ?activeById[id],
            ];
      envelopeByMaterial
          .putIfAbsent(requirement.materialId, () => [])
          .addAll(
            dependents.isEmpty
                ? [requirement.constraints]
                : [for (final dependent in dependents) dependent.constraints],
          );
    }

    // Generation reads the material and the instrument and nothing else, so
    // requirements over one material share a pool rather than each building an
    // identical one.
    final realizationsByMaterial = <String, List<Exercise>>{};
    final candidatesByMaterial = <String, List<Exercise>>{};
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
      final realizations = realizationsByMaterial.putIfAbsent(
        material.materialId,
        () => family.generate(instrument, material),
      );
      final candidates = candidatesByMaterial.putIfAbsent(
        material.materialId,
        () => [
          for (final exercise in realizations)
            if (envelopeByMaterial[material.materialId]!.any(
              (constraints) => constraints.admitsOnTheWay(
                exercise.conditions,
                material.progression,
              ),
            ))
              exercise,
        ],
      );
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
          realizations: realizations,
          roles: {
            if (activeTargetIds.contains(requirement.id))
              ResolvedRequirementRole.target,
            if (supportIds.contains(requirement.id) ||
                requirement.role == CurriculumRequirementRole.support)
              ResolvedRequirementRole.support,
          },
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
            id: catalogRequirementId(goal.id, materialId),
            familyId: catalogById[materialId]?.familyId ?? '',
            materialId: materialId,
          ),
      ],
    );
  }
}

/// Every requirement preparing one of [targetIds], through any chain of them.
Set<String> _supportersOf(
  Set<String> targetIds,
  List<CurriculumRequirement> requirements,
) {
  final supporters = <String>{};
  var frontier = targetIds;
  while (frontier.isNotEmpty) {
    final reached = {
      for (final requirement in requirements)
        if (!supporters.contains(requirement.id) &&
            requirement.supportsRequirementIds.any(frontier.contains))
          requirement.id,
    };
    supporters.addAll(reached);
    frontier = reached;
  }
  return supporters;
}

/// The requirements that prepare [retained] because a material declares the
/// other as its prerequisite, through any chain of them.
///
/// A prerequisite the scope left out would otherwise make its dependent
/// unreachable, so an exclusive focus on an inversion, or on an altered minor
/// form, would be blocked by the very material it needs first. The
/// curriculum's own requirements over a prerequisite material are retained
/// where it has any; otherwise one is made, preparing whatever named it. A
/// prerequisite the catalog does not hold cannot be offered, and is left to
/// the scheduler to report as blocked.
List<CurriculumRequirement> _prerequisiteSupportFor(
  List<CurriculumRequirement> retained,
  Curriculum curriculum,
  Map<String, TechnicalMaterial> catalogById,
) {
  final requirementsByMaterial = <String, List<CurriculumRequirement>>{};
  for (final requirement in curriculum.requirements) {
    requirementsByMaterial
        .putIfAbsent(requirement.materialId, () => [])
        .add(requirement);
  }
  Iterable<String> requirementIdsOf(String materialId) =>
      requirementsByMaterial[materialId]?.map(
        (requirement) => requirement.id,
      ) ??
      [catalogRequirementId(curriculum.id, materialId)];

  final dependentsByMaterial = <String, Set<String>>{};
  var frontier = [
    for (final requirement in retained)
      (requirement.materialId, requirement.id),
  ];
  while (frontier.isNotEmpty) {
    final next = <(String, String)>[];
    for (final (materialId, requirementId) in frontier) {
      final material = catalogById[materialId];
      if (material == null) continue;
      for (final prerequisiteId
          in material.progression.prerequisiteMaterialIds) {
        if (!catalogById.containsKey(prerequisiteId)) continue;
        final firstVisit = !dependentsByMaterial.containsKey(prerequisiteId);
        dependentsByMaterial
            .putIfAbsent(prerequisiteId, () => {})
            .add(requirementId);
        if (firstVisit) {
          for (final id in requirementIdsOf(prerequisiteId)) {
            next.add((prerequisiteId, id));
          }
        }
      }
    }
    frontier = next;
  }

  return [
    for (final MapEntry(key: materialId, value: dependents)
        in dependentsByMaterial.entries)
      ...requirementsByMaterial[materialId] ??
          [
            CurriculumRequirement(
              id: catalogRequirementId(curriculum.id, materialId),
              familyId: catalogById[materialId]!.familyId,
              materialId: materialId,
              role: CurriculumRequirementRole.support,
              supportsRequirementIds: dependents,
            ),
          ],
  ];
}

List<Exercise> _generateArpeggioCandidates(
  InstrumentProfile instrument,
  ArpeggioMaterial material,
  ArpeggioPracticePolicy policy,
) => [
  for (final hands in HandConfiguration.values)
    if (_hasCanonicalFingering(material, hands))
      for (final octaves in material.progression.octaveSpans)
        for (final direction in ExerciseDirection.values)
          ..._guidanceRungsOf(
            instrument,
            Exercise.linear(
              material: material,
              hands: hands,
              octaves: octaves,
              direction: direction,
              tempoBpm: policy.initialTempoBpm,
            ),
          ),
];

/// Every guidance rung of [shape], or none when the instrument cannot play it.
///
/// Playability is a property of the shape: guidance reaches no note, so the
/// instrument is asked once rather than of every rung.
List<Exercise> _guidanceRungsOf(InstrumentProfile instrument, Exercise shape) =>
    playableOn(instrument, shape)
    ? [
        for (final guidance in GuidanceContext.ladder)
          shape.withGuidance(guidance),
      ]
    : const [];

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
          scaffold: _arpeggioScaffoldFor(exercise),
        ),
]);

/// The supported task offered below an arpeggio floor, or null for none.
///
/// The tempo comes off, as it does for a scale, and then the family asks its
/// own question: one octave of a triad is four notes and three intervals,
/// which is fewer than continuity can be read from, so a single traversal of
/// it can never say whether the motion was fluent. The task is that same
/// traversal played through as many times as the reading needs, from the
/// beginning each time. Running on into a second octave would supply the
/// intervals too, and would add the thumb crossing that makes a wider span its
/// own motor task rather than a supported version of this one.
///
/// Root position only. An inversion starts the same chord tones from a
/// different finger and is its own motor problem, so the root-position
/// traversal is not a simpler version of it; supporting one with the other
/// would claim a relationship the family has not established.
AcquisitionScaffold? _arpeggioScaffoldFor(Exercise exercise) =>
    (exercise.material as ArpeggioMaterial).inversion == ArpeggioInversion.root
    ? AcquisitionScaffold.unmeteredRepetitions(
        traversalsForContinuity(realize(exercise)),
      )
    : null;

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
