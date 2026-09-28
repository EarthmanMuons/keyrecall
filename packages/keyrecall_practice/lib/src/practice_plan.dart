import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

import 'goal_curricula.dart';
import 'scope_resolution.dart';

/// Version of the stored goal's wire format.
const int practiceGoalSchemaVersion = 1;

/// The stored form of what a profile is working toward.
///
/// The goal and nothing else. A focus is what someone wants from this session,
/// so it lives as long as the running app and a relaunch starts unfocused;
/// storing only the goal makes that a property of the format rather than
/// something a reader has to remember to discard.
Map<String, Object?> practiceGoalToJson(String goalId) => {
  'schema_version': practiceGoalSchemaVersion,
  'goal_id': goalId,
};

/// Reads a stored goal back.
///
/// A version this build does not know is refused rather than guessed at.
String practiceGoalFromJson(Map<String, Object?> json) {
  final version = requireInt(json, 'schema_version');
  if (version != practiceGoalSchemaVersion) {
    throw JournalFormatException(
      'practice goal schema version $version is not readable by this build, '
      'which writes version $practiceGoalSchemaVersion',
    );
  }
  return requireString(json, 'goal_id', location: 'practice goal');
}

/// The weight an emphasis focus carries into goal relevance.
///
/// Only its order against [GoalEmphasis.unemphasized] is read, so the number
/// says "asked for" rather than "asked for this much".
const double focusEmphasisWeight = 2;

/// Whether a focus narrows what may be practiced or only what is preferred.
enum FocusStrength {
  /// Everything in the goal stays eligible; matching material is preferred.
  emphasis,

  /// Nothing outside the focus is generated.
  exclusive,
}

/// The material characteristics a focus matches.
///
/// A subset of the goal, expressed as the things a learner would say rather
/// than as a list of material ids: a family, a form or chord quality, a set of
/// keys. Each named facet narrows, an unnamed one says nothing, and family
/// facets combine by union so "minor material" can reach both minor scales and
/// minor arpeggios.
@immutable
class MaterialFocus {
  final Set<String> familyIds;
  final Set<String> scaleFormIds;
  final Set<String> arpeggioQualityIds;
  final Set<String> tonics;

  factory MaterialFocus({
    Set<String> familyIds = const {},
    Set<String> scaleFormIds = const {},
    Set<String> arpeggioQualityIds = const {},
    Set<String> tonics = const {},
  }) => MaterialFocus._(
    familyIds: Set.unmodifiable(familyIds),
    scaleFormIds: Set.unmodifiable(scaleFormIds),
    arpeggioQualityIds: Set.unmodifiable(arpeggioQualityIds),
    tonics: Set.unmodifiable(tonics),
  );

  const MaterialFocus._({
    required this.familyIds,
    required this.scaleFormIds,
    required this.arpeggioQualityIds,
    required this.tonics,
  });

  /// Whether any family facet is named at all.
  bool get namesFamilyFacet =>
      familyIds.isNotEmpty ||
      scaleFormIds.isNotEmpty ||
      arpeggioQualityIds.isNotEmpty;

  /// Whether this focus narrows anything.
  bool get isEmpty => !namesFamilyFacet && tonics.isEmpty;

  /// The identifiers this build has no meaning for.
  ///
  /// Vocabulary rather than catalog presence: a form this build knows and this
  /// install happens to stock no material for is a selection that reaches
  /// nothing, which is not the same as a request nobody can read.
  List<String> get unreadableIdentifiers => [
    for (final familyId in familyIds)
      if (!TechnicalMaterial.familyIds.contains(familyId)) familyId,
    for (final formId in scaleFormIds)
      if (!ScaleForm.values.any((form) => form.id == formId)) formId,
    for (final qualityId in arpeggioQualityIds)
      if (!ArpeggioQuality.values.any((quality) => quality.id == qualityId))
        qualityId,
    for (final tonic in tonics)
      if (!TechnicalMaterial.isCanonicalTonic(tonic)) tonic,
  ];

  /// Whether [material] is what this focus asked for.
  bool matches(TechnicalMaterial material) {
    if (tonics.isNotEmpty && !tonics.contains(material.tonic)) return false;
    if (!namesFamilyFacet) return true;
    if (familyIds.contains(material.familyId)) return true;
    return switch (material) {
      ScaleMaterial(:final form) => scaleFormIds.contains(form.id),
      ArpeggioMaterial(:final quality) => arpeggioQualityIds.contains(
        quality.id,
      ),
    };
  }

  /// The materials of [catalog] this focus asked for.
  List<TechnicalMaterial> selectionOf(List<TechnicalMaterial> catalog) => [
    for (final material in catalog)
      if (matches(material)) material,
  ];

  @override
  bool operator ==(Object other) =>
      other is MaterialFocus &&
      _sameSet(other.familyIds, familyIds) &&
      _sameSet(other.scaleFormIds, scaleFormIds) &&
      _sameSet(other.arpeggioQualityIds, arpeggioQualityIds) &&
      _sameSet(other.tonics, tonics);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(familyIds),
    Object.hashAllUnordered(scaleFormIds),
    Object.hashAllUnordered(arpeggioQualityIds),
    Object.hashAllUnordered(tonics),
  );
}

/// What a learner asked KeyRecall to draw from for now.
@immutable
class ActiveFocus {
  final MaterialFocus material;
  final FocusStrength strength;

  /// What this focus is called where it is shown.
  ///
  /// Carried rather than derived, because the learner picked a named thing:
  /// "minor material" and the six checkboxes it happens to resolve to are the
  /// same selection and not the same request.
  final String label;

  const ActiveFocus({
    required this.material,
    required this.strength,
    required this.label,
  });

  bool get isExclusive => strength == FocusStrength.exclusive;

  @override
  bool operator ==(Object other) =>
      other is ActiveFocus &&
      other.material == material &&
      other.strength == strength &&
      other.label == label;

  @override
  int get hashCode => Object.hash(material, strength, label);
}

/// The goals this build knows how to resolve, in the order they are offered.
///
/// A stored identifier outside this registry is refused rather than turned
/// into a goal of its own. A goal nothing describes carries no materials and
/// no curriculum, so honoring one would quietly practice the whole catalog
/// under a name the learner chose for something narrower.
final Map<String, PracticeGoal> supportedGoals = Map.unmodifiable({
  'GENERAL_FLUENCY': PracticeGoal.generalFluency,
  'FOUNDATIONS': PracticeGoal(
    id: 'FOUNDATIONS',
    curriculum: foundationsCurriculum,
  ),
  'KEY_FLUENCY_24': PracticeGoal(
    id: 'KEY_FLUENCY_24',
    curriculum: keyFluencyCurriculum,
  ),
});

/// The target requirements [goal] holds over [materialIds].
///
/// What a focus resolves to. A focus names material rather than requirements,
/// since requirements belong to one goal and a focus outlives a change of goal:
/// Foundations holds C major as two one-hand requirements and 24-key fluency as
/// one hands-together requirement, and a focus on C major means both.
Set<String> targetRequirementIdsOver(
  PracticeGoal goal,
  Set<String> materialIds,
) {
  final curriculum = goal.curriculum;
  if (curriculum != null) {
    return {
      for (final requirement in curriculum.requirements)
        if (requirement.role == CurriculumRequirementRole.target &&
            materialIds.contains(requirement.materialId))
          requirement.id,
    };
  }
  return {
    for (final materialId in materialIds)
      if (goal.targetMaterialIds?.contains(materialId) ?? true)
        catalogRequirementId(goal.id, materialId),
  };
}

/// The result of reading a plan against this build and one catalog.
sealed class PlanResolution {
  const PlanResolution();
}

/// A plan this build can practice under.
@immutable
final class ResolvedPlan extends PlanResolution {
  final PracticeGoal goal;
  final PracticeFocus focus;

  const ResolvedPlan({required this.goal, required this.focus});
}

/// A plan naming something this build cannot interpret.
@immutable
final class UnresolvablePlan extends PlanResolution {
  final List<ScopeResolutionFailure> failures;

  UnresolvablePlan(Iterable<ScopeResolutionFailure> failures)
    : failures = List.unmodifiable(failures);
}

/// What one profile is working toward, and what it is drawing from now.
///
/// The durable half of the curriculum surface: a goal that is rarely touched,
/// and a focus that is exceptional learner intent. Practicing normally is a
/// plan with no focus, not a focus named "everything".
@immutable
class PracticePlan {
  final String goalId;
  final ActiveFocus? focus;

  const PracticePlan({required this.goalId, this.focus});

  /// The plan an install that has never been asked practices under.
  static const PracticePlan normal = PracticePlan(goalId: 'GENERAL_FLUENCY');

  bool get isFocused => focus != null;

  /// This plan focused on [focus], or practicing normally where it narrows
  /// nothing.
  ///
  /// A focus over the whole catalog is what practicing normally already is,
  /// and it is collapsed here rather than stored, so nothing durable holds a
  /// focus that means everything. Whoever asked did choose something: the
  /// chooser's empty state says "stop drawing from less than all of it",
  /// which this plan expresses by having no focus.
  PracticePlan focusedOn(ActiveFocus focus) => focus.material.isEmpty
      ? practicingNormally()
      : PracticePlan(goalId: goalId, focus: focus);

  PracticePlan practicingNormally() => PracticePlan(goalId: goalId);

  /// This plan working toward [goalId] instead, keeping the focus only where
  /// the new goal holds some of its material in [catalog].
  ///
  /// A focus the new goal shares nothing with would be shown while nothing it
  /// names is practiced, so it is dropped when the goal is chosen rather than
  /// kept for a goal it might apply under later.
  PracticePlan withGoal(String goalId, List<TechnicalMaterial> catalog) {
    final active = focus;
    final goal = supportedGoals[goalId];
    if (active == null || goal == null) return PracticePlan(goalId: goalId);
    final applies = targetRequirementIdsOver(goal, {
      for (final material in active.material.selectionOf(catalog))
        material.materialId,
    }).isNotEmpty;
    return PracticePlan(goalId: goalId, focus: applies ? active : null);
  }

  /// The goal and focus this plan resolves to over [catalog].
  ///
  /// The requirement ids a focus names are the ones the goal's curriculum
  /// generates for the catalog it was resolved against, so a focus can only
  /// ever name material the goal already contains.
  ///
  /// Everything the plan names is checked before anything is selected, and a
  /// name this build cannot read fails the plan. The one thing resolution must
  /// never do is widen: a typo, a retired identifier, or a goal from a later
  /// build has to be distinguishable from a learner asking for everything.
  PlanResolution resolve(List<TechnicalMaterial> catalog) {
    final active = focus;
    final goal = supportedGoals[goalId];
    final failures = <ScopeResolutionFailure>[
      if (goal == null)
        ScopeResolutionFailure(
          code: ScopeResolutionFailureCode.unknownGoal,
          reference: goalId,
        ),
      if (active != null)
        for (final identifier in active.material.unreadableIdentifiers)
          ScopeResolutionFailure(
            code: ScopeResolutionFailureCode.unreadableFocus,
            reference: identifier,
          ),
    ];
    if (failures.isNotEmpty || goal == null) {
      return UnresolvablePlan(failures);
    }

    if (active == null) {
      return ResolvedPlan(goal: goal, focus: PracticeFocus.unrestricted);
    }

    final selected = {
      for (final material in active.material.selectionOf(catalog))
        material.materialId,
    };
    final requirementIds = targetRequirementIdsOver(goal, selected);
    // Material the goal does not hold is dropped rather than failing the plan:
    // a focus is carried across goals, and one the new goal shares nothing
    // with is no focus there. Material the catalog does not hold is another
    // matter, and still fails, since widening it would read a focus nothing
    // can satisfy as a request for everything.
    if (selected.isNotEmpty && requirementIds.isEmpty) {
      return ResolvedPlan(goal: goal, focus: PracticeFocus.unrestricted);
    }
    return ResolvedPlan(
      goal: goal,
      focus: active.isExclusive
          ? PracticeFocus(exclusiveRequirementIds: requirementIds)
          : PracticeFocus(
              emphasisByRequirementId: {
                for (final id in requirementIds) id: focusEmphasisWeight,
              },
            ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PracticePlan && other.goalId == goalId && other.focus == focus;

  @override
  int get hashCode => Object.hash(goalId, focus);
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
