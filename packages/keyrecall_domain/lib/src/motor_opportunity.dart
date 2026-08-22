import 'competency.dart';
import 'execution_conditions.dart';

/// An observable motor site an exercise's event structure creates.
///
/// Opportunities are what makes localized diagnosis possible: an attempt can
/// fail at a thumb crossing without the aggregate score saying where.
enum MotorOpportunity {
  /// A thumb-under or finger-over crossing site.
  scalarCrossing('SCALAR_CROSSING', Competency.scalarCrossing),

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

  /// The opportunities a linear traversal under [conditions] creates.
  ///
  /// A provisional structural rule standing in for real motor-realization
  /// data: no fingering catalog or event generator exists yet, so octave span
  /// and direction are all this can read. Replace it with derivation from
  /// generated events once the catalog lands, not with a wider heuristic.
  static Set<MotorOpportunity> forLinearTraversal(
    ExecutionConditions conditions,
  ) => {
    scalarCrossing,
    if (conditions.octaves >= 2) multiOctaveContinuation,
    if (conditions.direction == ScaleDirection.upDown) directionReversal,
  };
}
