import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

import 'scope_resolution.dart';

/// Version of the practice plan wire format.
const int practicePlanSchemaVersion = 1;

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

  Map<String, Object?> toJson() => {
    'family_ids': familyIds.toList()..sort(),
    'scale_form_ids': scaleFormIds.toList()..sort(),
    'arpeggio_quality_ids': arpeggioQualityIds.toList()..sort(),
    'tonics': tonics.toList()..sort(),
  };

  factory MaterialFocus.fromJson(Map<String, Object?> json) => MaterialFocus(
    familyIds: _stringSet(json, 'family_ids'),
    scaleFormIds: _stringSet(json, 'scale_form_ids'),
    arpeggioQualityIds: _stringSet(json, 'arpeggio_quality_ids'),
    tonics: _stringSet(json, 'tonics'),
  );

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

  Map<String, Object?> toJson() => {
    'material': material.toJson(),
    'strength': strength.name,
    'label': label,
  };

  factory ActiveFocus.fromJson(Map<String, Object?> json) => ActiveFocus(
    material: MaterialFocus.fromJson(
      asMap(json['material'], 'material', location: 'practice plan'),
    ),
    strength: FocusStrength.values.firstWhere(
      (strength) =>
          strength.name == requireString(json, 'strength', location: 'focus'),
      orElse: () =>
          throw const JournalFormatException('unknown focus strength'),
    ),
    label: requireString(json, 'label', location: 'focus'),
  );

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
const Map<String, PracticeGoal> supportedGoals = {
  'GENERAL_FLUENCY': PracticeGoal.generalFluency,
};

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

    final requirementIds = {
      for (final material in active.material.selectionOf(catalog))
        catalogRequirementId(goal.id, material.materialId),
    };
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

  Map<String, Object?> toJson() => {
    'schema_version': practicePlanSchemaVersion,
    'goal_id': goalId,
    'focus': focus?.toJson(),
  };

  /// Reads a plan back.
  ///
  /// A version this build does not know is refused rather than guessed at: a
  /// plan is what a learner asked for, and a partial reading of it would put
  /// them in a scope they never chose.
  factory PracticePlan.fromJson(Map<String, Object?> json) {
    final version = requireInt(json, 'schema_version');
    if (version != practicePlanSchemaVersion) {
      throw JournalFormatException(
        'practice plan schema version $version is not readable by this build, '
        'which writes version $practicePlanSchemaVersion',
      );
    }
    final focus = json['focus'];
    final plan = PracticePlan(
      goalId: requireString(json, 'goal_id', location: 'practice plan'),
      focus: focus == null
          ? null
          : ActiveFocus.fromJson(
              asMap(focus, 'focus', location: 'practice plan'),
            ),
    );
    // A facet that is present and empty narrows nothing, which a build whose
    // chooser offered that could write. It is read as the unfocused plan it
    // describes rather than refused, because what it asked for is legible. A
    // facet that is not there at all is a different thing and threw above:
    // nothing establishes what it said, and reading it as empty would widen
    // whatever was asked for.
    final stored = plan.focus;
    return stored == null ? plan : plan.focusedOn(stored);
  }

  @override
  bool operator ==(Object other) =>
      other is PracticePlan && other.goalId == goalId && other.focus == focus;

  @override
  int get hashCode => Object.hash(goalId, focus);
}

/// The strings at [field], which must be there.
///
/// A missing facet is not an empty one. Reading it as empty turns "C major
/// only" whose payload did not survive into a focus that narrows nothing, and
/// an exclusive one at that.
Set<String> _stringSet(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! List) {
    throw JournalFormatException('$field must be a list', location: 'focus');
  }
  return {
    for (final entry in value)
      if (entry is String)
        entry
      else
        throw JournalFormatException(
          '$field must hold strings',
          location: 'focus',
        ),
  };
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
