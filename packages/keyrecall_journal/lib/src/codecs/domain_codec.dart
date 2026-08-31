import 'package:keyrecall_domain/keyrecall_domain.dart';

import '../canonical_json.dart';
import '../schema.dart';

/// Serializes the exercise that was actually presented.
///
/// The journal records the presented exercise rather than relying on a later
/// recomputation, so a changed catalog or candidate generator cannot silently
/// reinterpret a historical decision.
///
/// Guidance is written as the rung name rather than as the underlying flags:
/// there are exactly three guidance states, and naming them keeps a future
/// fourth flag combination from looking like historical data.
Map<String, Object?> encodeExercise(Exercise exercise) {
  final conditions = exercise.conditions;
  return {
    'material_id': exercise.material.materialId,
    'tonic': exercise.material.tonic,
    'form': exercise.material.form.id,
    'pattern': exercise.pattern.id,
    'hands': conditions.hands.id,
    'octaves': conditions.octaves,
    'direction': conditions.direction.id,
    'hand_motion': conditions.handMotion.id,
    'requested_tempo_bpm': conditions.tempoBpm,
    'guidance': encodeGuidance(exercise.guidance),
    'opportunities':
        exercise.opportunities.map((opportunity) => opportunity.id).toList()
          ..sort(),
  };
}

/// Reads an exercise back, rejecting anything the domain would not construct.
Exercise decodeExercise(Map<String, Object?> json, {String? location}) {
  final material = TechnicalMaterial(
    requireString(json, 'tonic', location: location),
    ScaleForm.fromId(requireString(json, 'form', location: location)),
  );

  // The stored id is redundant with tonic and form, and that redundancy is the
  // point: if they disagree, one of them was rewritten.
  final materialId = requireString(json, 'material_id', location: location);
  if (material.materialId != materialId) {
    throw JournalFormatException(
      'material_id "$materialId" does not match tonic and form, which give '
      '"${material.materialId}"',
      location: location,
    );
  }

  final conditions = ExecutionConditions(
    hands: HandConfiguration.fromId(
      requireString(json, 'hands', location: location),
    ),
    octaves: requireInt(json, 'octaves', location: location),
    direction: ScaleDirection.fromId(
      requireString(json, 'direction', location: location),
    ),
    handMotion: HandMotion.fromId(
      requireString(json, 'hand_motion', location: location),
    ),
    tempoBpm: requireDouble(json, 'requested_tempo_bpm', location: location),
  );

  final opportunities = json['opportunities'];
  if (opportunities is! List) {
    throw JournalFormatException(
      'expected a list at "opportunities"',
      location: location,
    );
  }

  return Exercise(
    material: material,
    conditions: conditions,
    pattern: ExercisePattern.fromId(
      requireString(json, 'pattern', location: location),
    ),
    guidance: decodeGuidance(
      requireString(json, 'guidance', location: location),
      location: location,
    ),
    opportunities: {
      for (final id in opportunities)
        MotorOpportunity.fromId(
          asString(id, 'motor opportunity', location: location),
        ),
    },
  );
}

/// Names of the three guidance rungs, most independent first.
const Map<int, String> _guidanceNames = {
  2: 'unguided',
  1: 'notes_previewed',
  0: 'continuously_cued',
};

/// Writes guidance as its rung name.
String encodeGuidance(GuidanceContext guidance) =>
    _guidanceNames[guidance.independence]!;

/// Reads a guidance rung back by name.
GuidanceContext decodeGuidance(String name, {String? location}) {
  for (final entry in _guidanceNames.entries) {
    if (entry.value == name) return GuidanceContext.ofIndependence(entry.key);
  }
  throw JournalFormatException(
    'unknown guidance level "$name"',
    location: location,
  );
}

/// Writes an instrument profile, which bounds what could have been offered.
Map<String, Object?> encodeInstrument(InstrumentProfile instrument) => {
  'key_count': instrument.keyCount,
};

/// Reads an instrument profile back.
InstrumentProfile decodeInstrument(
  Map<String, Object?> json, {
  String? location,
}) => InstrumentProfile(
  keyCount: requireInt(json, 'key_count', location: location),
);
