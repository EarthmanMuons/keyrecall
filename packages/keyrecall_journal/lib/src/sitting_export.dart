import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'acquisition_journal.dart';
import 'canonical_json.dart';
import 'codecs/domain_codec.dart';
import 'codecs/learner_codec.dart';
import 'schema.dart';

/// The wire format one exported sitting is written in.
///
/// Separate from the journal's own schema version, because this is a file
/// somebody carries off a device to analyse rather than state the app reads
/// back. Anything that cannot read this version refuses rather than guessing.
const int sittingExportSchemaVersion = 2;

/// What was known, before the attempt, about the learner having met the
/// material.
///
/// A tri-state rather than a flag, because "nothing recorded this" is a real
/// answer and the common one. The journal begins when the profile does, so an
/// attempt on material with no earlier record says nothing about whether the
/// person had played it for years beforehand, and calling that unfamiliar
/// would invent evidence.
enum MaterialFamiliarity {
  familiar('familiar'),
  unfamiliar('unfamiliar'),
  unknown('unknown');

  const MaterialFamiliarity(this.id);

  final String id;

  static MaterialFamiliarity fromId(String id, {String? location}) =>
      values.firstWhere(
        (familiarity) => familiarity.id == id,
        orElse: () => throw JournalFormatException(
          'unknown familiarity $id',
          location: location,
        ),
      );
}

/// One attempt of an exported sitting: what was asked, what happened, and what
/// was known beforehand.
class ExportedAttempt {
  /// Position in the sitting, from zero.
  final int index;

  /// The exercise as it was presented, not a later reconstruction.
  final Exercise exercise;

  final Outcome outcome;
  final MaterialFamiliarity familiarity;

  const ExportedAttempt({
    required this.index,
    required this.exercise,
    required this.outcome,
    required this.familiarity,
  });
}

/// One sitting, as a file.
///
/// [profileId] and the timestamps are operational metadata for finding and
/// ordering exports. Nothing that fits a learner is entitled to read them: a
/// fit sees the exercise, the outcome and the familiarity, which is what makes
/// it a statement about playing rather than about who was playing.
class SittingExport {
  final int schemaVersion;
  final String profileId;
  final String sittingId;
  final DateTime startedAt;
  final List<ExportedAttempt> attempts;

  /// Supported attempts from the same sitting, beside the ordinary ones and
  /// never among them.
  ///
  /// A fit reads [attempts]. These are not ordinary evidence and must not
  /// become part of one, which is why they are a separate list rather than
  /// rows with a flag on them. They are here because the question a device
  /// sitting most often has to answer about supported work is what a
  /// particular attempt actually recorded, and an export that omitted them
  /// could not answer it.
  final List<AcquisitionAttemptRecord> acquisition;

  const SittingExport({
    required this.profileId,
    required this.sittingId,
    required this.startedAt,
    required this.attempts,
    this.acquisition = const [],
    this.schemaVersion = sittingExportSchemaVersion,
  });
}

/// Writes [export] as JSON.
String encodeSittingExport(SittingExport export) =>
    const JsonEncoder.withIndent('  ').convert({
      'schema_version': export.schemaVersion,
      'profile_id': export.profileId,
      'sitting_id': export.sittingId,
      'started_at': encodeTime(export.startedAt),
      'attempts': [
        for (final attempt in export.attempts)
          {
            'index': attempt.index,
            'exercise': encodeExercise(attempt.exercise),
            'outcome': encodeOutcome(attempt.outcome),
            'familiarity': attempt.familiarity.id,
          },
      ],
      'acquisition': [for (final record in export.acquisition) record.toJson()],
    });

/// Reads a sitting back, rejecting a version it does not know.
///
/// Throws [JournalFormatException] for a version it cannot read or a field it
/// cannot make sense of, rather than returning a half-built sitting that an
/// estimator would quietly fit.
SittingExport decodeSittingExport(String source) {
  final json = jsonDecode(source);
  if (json is! Map<String, Object?>) {
    throw const JournalFormatException('an export is a JSON object');
  }
  final version = requireInt(json, 'schema_version', location: 'export');
  if (version != sittingExportSchemaVersion && version != 1) {
    throw JournalFormatException(
      'cannot read export schema $version, this reads '
      '$sittingExportSchemaVersion',
      location: 'export',
    );
  }
  final attempts = json['attempts'];
  if (attempts is! List) {
    throw const JournalFormatException(
      'attempts is a list',
      location: 'export',
    );
  }

  return SittingExport(
    schemaVersion: version,
    profileId: requireString(json, 'profile_id', location: 'export'),
    sittingId: requireString(json, 'sitting_id', location: 'export'),
    startedAt: requireTime(json, 'started_at', location: 'export'),
    attempts: [
      for (final (position, attempt) in attempts.indexed)
        _attemptOf(attempt, position),
    ],
    // Absent in version 1, which had no supported work to carry.
    acquisition: [
      for (final record in (json['acquisition'] as List? ?? const []))
        AcquisitionAttemptRecord.fromJson(
          asMap(record, 'acquisition attempt', location: 'export'),
        ),
    ],
  );
}

ExportedAttempt _attemptOf(Object? attempt, int position) {
  final location = 'attempt $position';
  if (attempt is! Map<String, Object?>) {
    throw JournalFormatException('an attempt is an object', location: location);
  }
  return ExportedAttempt(
    index: requireInt(attempt, 'index', location: location),
    exercise: decodeExercise(
      requireMap(attempt, 'exercise', location: location),
      location: location,
    ),
    outcome: decodeOutcome(
      requireMap(attempt, 'outcome', location: location),
      location: location,
    ),
    familiarity: MaterialFamiliarity.fromId(
      requireString(attempt, 'familiarity', location: location),
      location: location,
    ),
  );
}
