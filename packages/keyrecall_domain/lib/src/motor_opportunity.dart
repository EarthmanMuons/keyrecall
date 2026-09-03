import 'competency.dart';
import 'execution_conditions.dart';
import 'fingering.dart';
import 'hand_path.dart';
import 'technical_material.dart';

/// An observable motor site an exercise's event structure creates.
///
/// Opportunities are what makes localized diagnosis possible: an attempt can
/// fail at a thumb crossing without the aggregate score saying where.
enum MotorOpportunity {
  /// A thumb-under or finger-over crossing site.
  scalarCrossing('SCALAR_CROSSING', Competency.scalarCrossing),

  /// A thumb transition between chord tones in an arpeggio.
  arpeggioTransition('ARPEGGIO_TRANSITION', Competency.arpeggioTransition),

  /// A join between octaves in a multi-octave traversal.
  multiOctaveContinuation(
    'MULTI_OCTAVE_CONTINUATION',
    Competency.multiOctaveContinuation,
  ),

  /// A turn from ascending to descending.
  directionReversal('DIRECTION_REVERSAL', Competency.directionReversal);

  const MotorOpportunity(this.id, this.competency);

  /// Stable identifier used in persisted state and traces.
  final String id;

  /// The localized competency this opportunity loads on.
  final Competency competency;

  /// The opportunity with the given [id].
  ///
  /// Throws [ArgumentError] when no opportunity matches.
  static MotorOpportunity fromId(String id) => values.firstWhere(
    (opportunity) => opportunity.id == id,
    orElse: () =>
        throw ArgumentError.value(id, 'id', 'unknown motor opportunity'),
  );

  /// The opportunities created by the material's realized hand paths.
  static Set<MotorOpportunity> forLinearTraversal(
    TechnicalMaterial material,
    ExecutionConditions conditions,
  ) {
    final degreesPerOctave = material.topology.degreesPerOctave;
    final paths = handPathsFor(conditions, degreesPerOctave: degreesPerOctave);
    var hasCrossing = false;
    var hasContinuation = false;
    var hasReversal = false;

    for (final MapEntry(key: hand, value: path) in paths.entries) {
      final fingers = fingeringForConditions(
        material: material,
        conditions: conditions,
        hand: hand,
      );
      if (fingers != null) {
        for (var index = 1; index < path.length; index++) {
          final degreeMotion = path[index] - path[index - 1];
          final fingerMotion = fingers[index] - fingers[index - 1];
          if (degreeMotion == 0 || fingerMotion == 0) continue;
          final directionsAgree = degreeMotion * fingerMotion > 0;
          if (directionsAgree == (hand == Hand.left)) hasCrossing = true;
        }
      }

      for (var index = 1; index < path.length - 1; index++) {
        final before = path[index] - path[index - 1];
        final after = path[index + 1] - path[index];
        if (before * after < 0) hasReversal = true;
        if (path[index] != 0 &&
            path[index].abs() % degreesPerOctave == 0 &&
            before * after > 0) {
          hasContinuation = true;
        }
      }
    }

    return {
      if (material is ArpeggioMaterial) arpeggioTransition,
      if (hasCrossing && material is! ArpeggioMaterial) scalarCrossing,
      if (hasContinuation) multiOctaveContinuation,
      if (hasReversal) directionReversal,
    };
  }
}
