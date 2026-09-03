import 'competency.dart';
import 'execution_conditions.dart';
import 'fingering.dart';
import 'hand_path.dart';
import 'technical_material.dart';

/// One motor opportunity at the moment reached by its transition.
class MotorOpportunitySite {
  final MotorOpportunity opportunity;
  final Hand hand;

  /// The moment reached by the transition from the preceding moment.
  final int momentIndex;

  const MotorOpportunitySite({
    required this.opportunity,
    required this.hand,
    required this.momentIndex,
  }) : assert(momentIndex > 0);

  @override
  bool operator ==(Object other) =>
      other is MotorOpportunitySite &&
      other.opportunity == opportunity &&
      other.hand == hand &&
      other.momentIndex == momentIndex;

  @override
  int get hashCode => Object.hash(opportunity, hand, momentIndex);
}

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

  /// The opportunity sites created by the material's realized hand paths.
  static Set<MotorOpportunitySite> sitesForLinearTraversal(
    TechnicalMaterial material,
    ExecutionConditions conditions,
  ) {
    final degreesPerOctave = material.topology.degreesPerOctave;
    final paths = handPathsFor(conditions, degreesPerOctave: degreesPerOctave);
    final sites = <MotorOpportunitySite>{};

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
          if (directionsAgree == (hand == Hand.left)) {
            sites.add(
              MotorOpportunitySite(
                opportunity: switch (material.fingeringTransitionKind) {
                  FingeringTransitionKind.scalarCrossing => scalarCrossing,
                  FingeringTransitionKind.arpeggioTransition =>
                    arpeggioTransition,
                },
                hand: hand,
                momentIndex: index,
              ),
            );
          }
        }
      }

      for (var index = 1; index < path.length - 1; index++) {
        final before = path[index] - path[index - 1];
        final after = path[index + 1] - path[index];
        if (before * after < 0) {
          sites.add(
            MotorOpportunitySite(
              opportunity: directionReversal,
              hand: hand,
              momentIndex: index,
            ),
          );
        }
        if (path[index] != 0 &&
            path[index].abs() % degreesPerOctave == 0 &&
            before * after > 0) {
          sites.add(
            MotorOpportunitySite(
              opportunity: multiOctaveContinuation,
              hand: hand,
              momentIndex: index,
            ),
          );
        }
      }
    }

    return Set.unmodifiable(sites);
  }

  /// The opportunity kinds created by the material's realized hand paths.
  static Set<MotorOpportunity> forLinearTraversal(
    TechnicalMaterial material,
    ExecutionConditions conditions,
  ) => {
    for (final site in sitesForLinearTraversal(material, conditions))
      site.opportunity,
  };
}
