import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

/// An unranked family realization that can begin work on one requirement.
@immutable
class AcquisitionFloorEntry {
  final String requirementId;
  final Exercise exercise;

  const AcquisitionFloorEntry({
    required this.requirementId,
    required this.exercise,
  });
}

/// The safe entry realizations supplied for unresolved requirements.
@immutable
class AcquisitionFloor {
  final List<AcquisitionFloorEntry> entries;

  AcquisitionFloor(Iterable<AcquisitionFloorEntry> entries)
    : entries = List.unmodifiable(entries);
}
