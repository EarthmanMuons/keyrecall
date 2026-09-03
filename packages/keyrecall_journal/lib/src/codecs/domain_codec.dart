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
  final opportunitySites = exercise.opportunitySites.toList()
    ..sort((left, right) {
      final byMoment = left.momentIndex.compareTo(right.momentIndex);
      if (byMoment != 0) return byMoment;
      final byHand = left.hand.id.compareTo(right.hand.id);
      if (byHand != 0) return byHand;
      return left.opportunity.id.compareTo(right.opportunity.id);
    });
  return {
    'material_id': exercise.material.materialId,
    'tonic': exercise.material.tonic,
    ...switch (exercise.material) {
      ScaleMaterial(:final form) => {'form': form.id},
      ArpeggioMaterial(:final quality, :final inversion) => {
        'material_family': TechnicalMaterial.arpeggioFamilyId,
        'quality': quality.id,
        'inversion': inversion.id,
      },
    },
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
    'opportunity_sites': [
      for (final site in opportunitySites)
        {
          'opportunity': site.opportunity.id,
          'hand': site.hand.id,
          'moment_index': site.momentIndex,
        },
    ],
  };
}

/// Reads an exercise back, rejecting anything the domain would not construct.
Exercise decodeExercise(Map<String, Object?> json, {String? location}) {
  final tonic = requireString(json, 'tonic', location: location);
  final family = json['material_family'];
  final TechnicalMaterial material;
  if (family == null || family == TechnicalMaterial.scaleFamilyId) {
    material = TechnicalMaterial(
      tonic,
      ScaleForm.fromId(requireString(json, 'form', location: location)),
    );
  } else if (family == TechnicalMaterial.arpeggioFamilyId) {
    material = ArpeggioMaterial(
      tonic,
      ArpeggioQuality.fromId(
        requireString(json, 'quality', location: location),
      ),
      inversion: ArpeggioInversion.fromId(
        requireString(json, 'inversion', location: location),
      ),
    );
  } else {
    throw JournalFormatException(
      'unknown material family "$family"',
      location: location,
    );
  }

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
    direction: ExerciseDirection.fromId(
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
  final opportunitySites = json['opportunity_sites'];
  if (opportunitySites is! List) {
    throw JournalFormatException(
      'expected a list at "opportunity_sites"',
      location: location,
    );
  }

  return Exercise.recorded(
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
    opportunitySites: {
      for (final value in opportunitySites)
        _decodeOpportunitySite(
          asMap(value, 'motor opportunity site', location: location),
          location: location,
        ),
    },
  );
}

MotorOpportunitySite _decodeOpportunitySite(
  Map<String, Object?> json, {
  String? location,
}) => MotorOpportunitySite(
  opportunity: MotorOpportunity.fromId(
    requireString(json, 'opportunity', location: location),
  ),
  hand: Hand.fromId(requireString(json, 'hand', location: location)),
  momentIndex: requireInt(json, 'moment_index', location: location),
);

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
