import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

/// What an attempt was resolved to present, and what of it reached the learner.
///
/// Recorded rather than derived. What a rung and an exercise imply depends on
/// app policy, on whether the catalog could finger the material, and on what
/// the renderers draw, so deriving it later would let a policy change rewrite
/// what a historical attempt is taken to have exposed.
///
/// [conditions] and [delivery] are kept apart on purpose: an audio engine that
/// never opened did not change what the attempt intended to supply, and folding
/// the failure into the intent would lose the difference between scaffolding
/// that was withheld and scaffolding that was promised and missing.
@immutable
class PresentationRecord {
  /// Which presentation policy resolved these conditions.
  ///
  /// Provenance beside the conditions rather than instead of them: a version
  /// says which rules applied, and reading history must not depend on those
  /// rules still being executable.
  final String policyVersion;

  /// The conditions the attempt was resolved to run under.
  final PresentationConditions conditions;

  /// What the fallible channels actually supplied.
  final PresentationDelivery delivery;

  const PresentationRecord({
    required this.policyVersion,
    required this.conditions,
    required this.delivery,
  });

  @override
  bool operator ==(Object other) =>
      other is PresentationRecord &&
      other.policyVersion == policyVersion &&
      other.conditions == conditions &&
      other.delivery == delivery;

  @override
  int get hashCode => Object.hash(policyVersion, conditions, delivery);

  @override
  String toString() =>
      'PresentationRecord($policyVersion, $conditions, '
      '$delivery)';
}
