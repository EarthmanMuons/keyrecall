import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import '../canonical_json.dart';
import '../schema.dart';
import 'domain_codec.dart';

/// Writes one parent's acquisition history.
Map<String, Object?> encodeAcquisitionRecord(
  Exercise parent,
  AcquisitionRecord record,
) => {
  'parent': encodeExercise(parent),
  'attempts': record.attempts,
  'completions': record.completions,
  'criterion_successes': record.criterionSuccesses,
  'probes_served': record.probesServed,
  'criterion_successes_served': record.criterionSuccessesServed,
  'last_attempt_at': encodeTime(record.lastAttemptAt),
  'last_criterion_success_at': encodeOptionalTime(
    record.lastCriterionSuccessAt,
  ),
  'last_probe_served_at': encodeOptionalTime(record.lastProbeServedAt),
};

/// Writes acquisition progress, ordered so the same progress encodes
/// identically twice.
///
/// Ordered by the encoded parent rather than by insertion, because a content
/// hash over insertion order would change when the same work arrived in a
/// different sequence.
List<Map<String, Object?>> encodeAcquisitionProgress(
  AcquisitionProgress progress,
) {
  final records = [
    for (final entry in progress.byParent.entries)
      encodeAcquisitionRecord(entry.key, entry.value),
  ];
  records.sort(
    (left, right) => canonicalJson(left).compareTo(canonicalJson(right)),
  );
  return records;
}

/// Reads acquisition progress.
///
/// Throws [JournalFormatException] for anything it cannot read, since
/// acquisition history decides whether a learner is offered supported work or
/// the ordinary question, and a silently dropped record answers that wrongly.
AcquisitionProgress decodeAcquisitionProgress(
  List<Object?> json, {
  String? location,
}) {
  final byParent = <Exercise, AcquisitionRecord>{};
  for (final entry in json) {
    final record = asMap(entry, 'acquisition record', location: location);
    final parent = decodeExercise(
      requireMap(record, 'parent', location: location),
      location: location,
    );
    final criterionSuccesses = requireInt(
      record,
      'criterion_successes',
      location: location,
    );
    final completions = requireInt(record, 'completions', location: location);
    final lastCriterionSuccessAt = readOptionalTime(
      record,
      'last_criterion_success_at',
      location: location,
    );
    if (criterionSuccesses > completions) {
      throw JournalFormatException(
        'acquisition record claims more criterion successes than completions',
        location: location,
      );
    }
    if ((criterionSuccesses > 0) != (lastCriterionSuccessAt != null)) {
      throw JournalFormatException(
        'acquisition record disagrees about whether a criterion success '
        'happened',
        location: location,
      );
    }
    final probesServed = requireInt(
      record,
      'probes_served',
      location: location,
    );
    final lastProbeServedAt = readOptionalTime(
      record,
      'last_probe_served_at',
      location: location,
    );
    if ((probesServed > 0) != (lastProbeServedAt != null)) {
      throw JournalFormatException(
        'acquisition record disagrees about whether a probe was served',
        location: location,
      );
    }
    if (!record.containsKey('criterion_successes_served')) {
      throw JournalFormatException(
        'acquisition progress has no service watermark; replay its acquisition log',
        location: location,
      );
    }
    final successesServed = requireInt(
      record,
      'criterion_successes_served',
      location: location,
    );
    final attempts = requireInt(record, 'attempts', location: location);
    if (attempts < completions ||
        completions < 0 ||
        criterionSuccesses < 0 ||
        successesServed < 0 ||
        successesServed > criterionSuccesses ||
        probesServed < 0 ||
        (successesServed > 0 && probesServed == 0)) {
      throw JournalFormatException(
        'acquisition counts are inconsistent',
        location: location,
      );
    }
    byParent[parent] = AcquisitionRecord(
      attempts: attempts,
      completions: completions,
      criterionSuccesses: criterionSuccesses,
      probesServed: probesServed,
      criterionSuccessesServed: successesServed,
      lastAttemptAt: requireTime(record, 'last_attempt_at', location: location),
      lastCriterionSuccessAt: lastCriterionSuccessAt,
      lastProbeServedAt: lastProbeServedAt,
    );
  }
  return AcquisitionProgress(byParent);
}
