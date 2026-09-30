import 'package:meta/meta.dart';

import 'canonical_json.dart';
import 'schema.dart';

/// The goal and focus a decision was made under.
///
/// Recorded because nothing else keeps it: a profile stores only its current
/// goal, and a focus lives only as long as the session that set it. What a
/// goal asks of ranking differs by goal, so reading a decision later needs the
/// scope it was made in, not the one in force when somebody looks.
@immutable
class DecisionScope {
  final String goalId;
  final String curriculumId;
  final String curriculumVersion;

  /// The requirements a focus restricted practice to, or null for none.
  final Set<String>? exclusiveRequirementIds;

  /// The weight a focus put on each requirement it emphasized.
  final Map<String, double> emphasisByRequirementId;

  /// Throws [ArgumentError] for an emphasis weight the focus could not have
  /// carried: one that is not finite and greater than zero.
  DecisionScope({
    required this.goalId,
    required this.curriculumId,
    required this.curriculumVersion,
    Set<String>? exclusiveRequirementIds,
    Map<String, double> emphasisByRequirementId = const {},
  }) : exclusiveRequirementIds = exclusiveRequirementIds == null
           ? null
           : Set.unmodifiable(exclusiveRequirementIds),
       emphasisByRequirementId = Map.unmodifiable(emphasisByRequirementId) {
    for (final weight in emphasisByRequirementId.values) {
      if (!weight.isFinite || weight <= 0) {
        throw ArgumentError.value(
          weight,
          'emphasisByRequirementId',
          'weights must be finite and greater than zero',
        );
      }
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is! DecisionScope ||
        other.goalId != goalId ||
        other.curriculumId != curriculumId ||
        other.curriculumVersion != curriculumVersion) {
      return false;
    }
    final exclusive = exclusiveRequirementIds;
    final otherExclusive = other.exclusiveRequirementIds;
    if ((exclusive == null) != (otherExclusive == null)) return false;
    if (exclusive != null &&
        (exclusive.length != otherExclusive!.length ||
            !exclusive.containsAll(otherExclusive))) {
      return false;
    }
    return emphasisByRequirementId.length ==
            other.emphasisByRequirementId.length &&
        emphasisByRequirementId.entries.every(
          (entry) => other.emphasisByRequirementId[entry.key] == entry.value,
        );
  }

  @override
  int get hashCode => Object.hash(
    goalId,
    curriculumId,
    curriculumVersion,
    exclusiveRequirementIds == null
        ? null
        : Object.hashAllUnordered(exclusiveRequirementIds!),
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in emphasisByRequirementId.entries)
        Object.hash(key, value),
    ]),
  );
}

Map<String, Object?> encodeDecisionScope(DecisionScope scope) => {
  'goal_id': scope.goalId,
  'curriculum_id': scope.curriculumId,
  'curriculum_version': scope.curriculumVersion,
  'exclusive_requirement_ids': scope.exclusiveRequirementIds == null
      ? null
      : (scope.exclusiveRequirementIds!.toList()..sort()),
  'emphasis': {
    for (final id in scope.emphasisByRequirementId.keys.toList()..sort())
      id: scope.emphasisByRequirementId[id],
  },
};

DecisionScope decodeDecisionScope(
  Map<String, Object?> json, {
  String? location,
}) {
  final exclusive = json['exclusive_requirement_ids'];
  if (exclusive != null && exclusive is! List) {
    throw JournalFormatException(
      'expected a list at "exclusive_requirement_ids"',
      location: location,
    );
  }
  final emphasis = requireMap(json, 'emphasis', location: location);
  return DecisionScope(
    goalId: requireString(json, 'goal_id', location: location),
    curriculumId: requireString(json, 'curriculum_id', location: location),
    curriculumVersion: requireString(
      json,
      'curriculum_version',
      location: location,
    ),
    exclusiveRequirementIds: exclusive == null
        ? null
        : {
            for (final id in exclusive as List)
              asString(id, 'exclusive requirement id', location: location),
          },
    emphasisByRequirementId: {
      for (final MapEntry(:key, :value) in emphasis.entries)
        key: asDouble(value, 'emphasis', location: location),
    },
  );
}
