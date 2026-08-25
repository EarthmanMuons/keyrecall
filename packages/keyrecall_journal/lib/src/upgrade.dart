import 'attempt_closure.dart';
import 'schema.dart';

/// Brings a persisted attempt forward to [attemptSchemaVersion].
///
/// Pure and total: it reads one record's JSON and returns the current shape, or
/// throws. A journal is the historical source of truth, so an upgrade may add
/// what the old format implied and must never guess at what it did not say.
///
/// Throws [JournalFormatException] for a version this build cannot upgrade.
Map<String, Object?> upgradeAttemptJson(Map<String, Object?> json) {
  final version = json['schema_version'];
  return switch (version) {
    attemptSchemaVersion => json,
    1 => _version1To2(json),
    _ => throw JournalFormatException(
      'attempt schema version $version is not upgradable by this build, which '
      'writes version $attemptSchemaVersion',
    ),
  };
}

/// Version 1 recorded an outcome and its derived evidence directly, because an
/// attempt could only end one way: the learner ended the presented attempt and
/// then said what happened, and nothing else could append a record. So the
/// termination is not a default chosen for convenience, it is the only thing
/// those records could have meant, and the measurement they carry is exactly
/// what they always carried.
Map<String, Object?> _version1To2(Map<String, Object?> json) {
  final upgraded = Map<String, Object?>.of(json)
    ..remove('outcome')
    ..remove('evidence_weights')
    ..remove('memory_update');

  upgraded['schema_version'] = attemptSchemaVersion;
  upgraded['closure'] = {
    'termination': AttemptTermination.learnerStopped.id,
    'measurement': {
      'status': 'MEASURED',
      'outcome': json['outcome'],
      'evidence_weights': json['evidence_weights'],
      'memory_update': json['memory_update'],
    },
  };
  return upgraded;
}
