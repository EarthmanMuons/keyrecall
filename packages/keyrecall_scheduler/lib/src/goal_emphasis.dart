import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

/// The weight a soft focus puts on each material it asks for.
///
/// Selection opportunity is not affected: every candidate in scope stays
/// eligible, and an emphasized one wins a slot only once the terms above goal
/// relevance have tied. A material nobody emphasized weighs [unemphasized].
@immutable
class GoalEmphasis {
  /// The weight of a material no focus named.
  static const double unemphasized = 1;

  /// Nothing is emphasized, which is what practicing normally means.
  static const GoalEmphasis none = GoalEmphasis._({});

  final Map<String, double> weightByMaterialId;

  factory GoalEmphasis(Map<String, double> weightByMaterialId) {
    for (final weight in weightByMaterialId.values) {
      if (!weight.isFinite || weight <= 0) {
        throw ArgumentError.value(
          weight,
          'weightByMaterialId',
          'weights must be finite and greater than zero',
        );
      }
    }
    return GoalEmphasis._(Map.unmodifiable(weightByMaterialId));
  }

  const GoalEmphasis._(this.weightByMaterialId);

  bool get isEmpty => weightByMaterialId.isEmpty;

  /// What [exercise] weighs.
  double of(Exercise exercise) =>
      weightByMaterialId[exercise.material.materialId] ?? unemphasized;
}
