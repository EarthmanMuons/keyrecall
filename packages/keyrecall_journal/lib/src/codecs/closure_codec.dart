import '../attempt_closure.dart';
import '../canonical_json.dart';
import '../schema.dart';
import 'learner_codec.dart';

/// Writes a closure.
Map<String, Object?> encodeClosure(AttemptClosure closure) => {
  'termination': closure.termination.id,
  'measurement': switch (closure.measurement) {
    Measured(:final outcome, :final weights, :final memoryUpdate) => {
      'status': 'MEASURED',
      'outcome': encodeOutcome(outcome),
      'evidence_weights': encodeEvidenceWeights(weights),
      'memory_update': encodeMemoryDiagnostics(memoryUpdate),
    },
    MeasurementUnavailable(:final reason) => {
      'status': 'UNAVAILABLE',
      'reason': reason.id,
    },
  },
};

/// Reads a closure back.
///
/// Throws [JournalFormatException] for an unknown termination, status, or
/// reason: an unreadable lifecycle fact is a reason to stop, not to assume the
/// ordinary case.
AttemptClosure decodeClosure(
  Map<String, Object?> json, {
  required String location,
}) {
  final measurement = requireMap(json, 'measurement', location: location);
  final status = requireString(measurement, 'status', location: location);

  return AttemptClosure(
    termination: _terminationOf(
      requireString(json, 'termination', location: location),
      location,
    ),
    measurement: switch (status) {
      // Validation inside an outcome stays the domain's to raise: only the
      // lifecycle vocabulary is this codec's to recognize.
      'MEASURED' => Measured(
        outcome: decodeOutcome(
          requireMap(measurement, 'outcome', location: location),
          location: location,
        ),
        weights: decodeEvidenceWeights(
          requireMap(measurement, 'evidence_weights', location: location),
          location: location,
        ),
        memoryUpdate: decodeMemoryDiagnostics(
          requireMap(measurement, 'memory_update', location: location),
          location: location,
        ),
      ),
      'UNAVAILABLE' => MeasurementUnavailable(
        _reasonOf(
          requireString(measurement, 'reason', location: location),
          location,
        ),
      ),
      _ => throw JournalFormatException(
        'unknown measurement status "$status"',
        location: location,
      ),
    },
  );
}

AttemptTermination _terminationOf(String id, String location) {
  try {
    return AttemptTermination.fromId(id);
  } on ArgumentError {
    throw JournalFormatException(
      'unknown termination "$id"',
      location: location,
    );
  }
}

MeasurementUnavailableReason _reasonOf(String id, String location) {
  try {
    return MeasurementUnavailableReason.fromId(id);
  } on ArgumentError {
    throw JournalFormatException(
      'unknown measurement reason "$id"',
      location: location,
    );
  }
}
