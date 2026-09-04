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

  PracticePlan focusedOn(ActiveFocus focus) =>
      PracticePlan(goalId: goalId, focus: focus);

  PracticePlan practicingNormally() => PracticePlan(goalId: goalId);

  /// The goal and focus this plan resolves to over [catalog].
  ///
  /// The requirement ids a focus names are the ones the goal's curriculum
  /// generates for the catalog it was resolved against, so a focus can only
  /// ever name material the goal already contains.
  ({PracticeGoal goal, PracticeFocus focus}) resolve(
    List<TechnicalMaterial> catalog,
  ) {
    final goal = goalId == PracticePlan.normal.goalId
        ? PracticeGoal.generalFluency
        : PracticeGoal(id: goalId);
    final active = focus;
    if (active == null) {
      return (goal: goal, focus: PracticeFocus.unrestricted);
    }

    final requirementIds = {
      for (final material in active.material.selectionOf(catalog))
        catalogRequirementId(goal.id, material.materialId),
    };
    return (
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
    return PracticePlan(
      goalId: requireString(json, 'goal_id', location: 'practice plan'),
      focus: focus == null
          ? null
          : ActiveFocus.fromJson(
              asMap(focus, 'focus', location: 'practice plan'),
            ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PracticePlan && other.goalId == goalId && other.focus == focus;

  @override
  int get hashCode => Object.hash(goalId, focus);
}

Set<String> _stringSet(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) return const {};
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
