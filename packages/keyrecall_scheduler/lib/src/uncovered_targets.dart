import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

/// A goal target not yet covered, as ranking asks about it.
@immutable
class UncoveredTarget {
  final TechnicalMaterial material;
  final ExerciseConstraints constraints;
  final CoverageRetrieval retrieval;

  const UncoveredTarget({
    required this.material,
    required this.constraints,
    required this.retrieval,
  });

  /// Whether [exercise] could cover this target: the target's material and
  /// shape, at a tempo it accepts, under guidance its coverage counts.
  ///
  /// A question about the requirement, not about any particular generated
  /// exercise, so a candidate at a tempo learned from this learner's history
  /// is as much a target as one at a tempo generation happened to offer.
  bool admits(Exercise exercise) =>
      exercise.material == material &&
      constraints.matches(exercise) &&
      retrieval.admits(exercise.guidance);
}

/// The targets still open, read by material.
@immutable
class UncoveredTargets {
  final Map<TechnicalMaterial, List<UncoveredTarget>> _byMaterial;

  const UncoveredTargets._(this._byMaterial);

  static const UncoveredTargets none = UncoveredTargets._({});

  factory UncoveredTargets(Iterable<UncoveredTarget> targets) {
    final byMaterial = <TechnicalMaterial, List<UncoveredTarget>>{};
    for (final target in targets) {
      byMaterial.putIfAbsent(target.material, () => []).add(target);
    }
    return UncoveredTargets._(Map.unmodifiable(byMaterial));
  }

  bool get isEmpty => _byMaterial.isEmpty;

  /// Whether [exercise] could cover any of these targets.
  bool admits(Exercise exercise) =>
      _byMaterial[exercise.material]?.any(
        (target) => target.admits(exercise),
      ) ??
      false;
}
