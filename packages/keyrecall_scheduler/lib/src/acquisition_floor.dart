import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

/// An unranked family realization that can begin work on one requirement.
@immutable
class AcquisitionFloorEntry {
  final String requirementId;
  final Exercise exercise;

  /// The supported task offered when this floor cannot be executed, or null
  /// when the family declares no supported path below it.
  ///
  /// The family's answer, held beside the realization it belongs to rather than
  /// beside the family, because a floor and the scaffold under it are the same
  /// declaration: a family may support one of its entry realizations and leave
  /// another to the ordinary path.
  final AcquisitionScaffold? scaffold;

  const AcquisitionFloorEntry({
    required this.requirementId,
    required this.exercise,
    this.scaffold,
  });
}

/// The safe entry realizations supplied for unresolved requirements.
@immutable
class AcquisitionFloor {
  final List<AcquisitionFloorEntry> entries;

  AcquisitionFloor(Iterable<AcquisitionFloorEntry> entries)
    : entries = List.unmodifiable(entries);

  /// What supported work [exercise] offers, or null when it offers none.
  ///
  /// Null for anything that is not a declared floor at all, which is the same
  /// answer for the same reason: nothing has said what a supported version of
  /// this work would be.
  AcquisitionScaffold? scaffoldFor(Exercise exercise) {
    for (final entry in entries) {
      if (entry.exercise == exercise && entry.scaffold != null) {
        return entry.scaffold;
      }
    }
    return null;
  }
}

/// One actionable requirement asking its family for safe entry realizations.
@immutable
class AcquisitionFloorRequest {
  final String requirementId;
  final Iterable<Exercise> candidates;

  const AcquisitionFloorRequest({
    required this.requirementId,
    required this.candidates,
  });
}
