import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

import 'attempt_record.dart';
import 'canonical_json.dart';
import 'codecs/domain_codec.dart';
import 'profile.dart';
import 'schema.dart';

/// The wait between two moments that arrived, as it was recorded.
///
/// [ratio] is measured rather than judged: the gap against the upper quartile
/// of the same performance's own gaps. What counts as a stall is a threshold
/// applied to it, so keeping the ratio lets a later threshold be asked of an
/// old attempt without the old attempt having anticipated it.
typedef RecordedGap = ({
  int fromPosition,
  int toPosition,
  int gapMs,
  double ratio,
});

/// Identifies an acquisition log and the profile whose work it holds.
@immutable
class AcquisitionJournalHeader {
  /// Which profile this history belongs to.
  final String profileId;

  /// When this log was created, in UTC.
  final DateTime createdAt;

  AcquisitionJournalHeader({
    required String profileId,
    required DateTime createdAt,
  }) : profileId = requireProfileId(profileId),
       createdAt = createdAt.toUtc();

  /// Writes the header.
  Map<String, Object?> toJson() => {
    'record_type': JournalRecordType.acquisitionHeader.id,
    'schema_version': acquisitionSchemaVersion,
    'profile_id': profileId,
    'created_at': encodeTime(createdAt),
  };

  /// Reads a header back.
  ///
  /// Throws [JournalFormatException] for a version this build does not write.
  /// There is one version, so there is nothing to upgrade from and guessing at
  /// a shape this build has never seen would be worse than refusing it.
  factory AcquisitionJournalHeader.fromJson(Map<String, Object?> json) {
    final version = requireInt(json, 'schema_version', location: 'header');
    if (version != acquisitionSchemaVersion) {
      throw JournalFormatException(
        'acquisition schema version $version is not readable by this build, '
        'which writes version $acquisitionSchemaVersion',
        location: 'header',
      );
    }
    return AcquisitionJournalHeader(
      profileId: requireString(json, 'profile_id', location: 'header'),
      createdAt: requireTime(json, 'created_at', location: 'header'),
    );
  }

  @override
  String toString() => 'AcquisitionJournalHeader($profileId)';
}

/// One event in a profile's acquisition history.
///
/// Two kinds, because two different things happen: work at an acquisition task,
/// and the ordinary question that work earned finally being asked. Replaying
/// both is what makes an earned probe something that can be discharged rather
/// than a fact that stays true forever.
@immutable
sealed class AcquisitionEntry {
  /// Position in this log, counting from zero in append order.
  int get journalSequence;

  /// Which event, and when.
  AttemptIdentity get identity;

  /// The ordinary exercise this event is about.
  Exercise get parent;

  /// Writes the entry.
  Map<String, Object?> toJson();
}

/// One attempt at an acquisition task, as it happened.
///
/// What happened, not what a policy made of it. The completion class, the
/// extra notes split three ways, where an unfinished traversal ran out, and
/// the located gap series are all observation-level facts, so a later rule
/// about what earns a probe can be asked of an old attempt.
///
/// [earnedProbe] is the verdict as it stood, recorded beside those facts for
/// the same reason a decision records the admission band in force: replay must
/// reproduce the history that actually happened, and a threshold that moves
/// afterwards must not make a past attempt read differently than it did.
///
/// It carries no outcome, no measurement, and no scores. Nothing here can be
/// folded into learner state, which is why this log exists apart from the one
/// that can.
@immutable
final class AcquisitionAttemptRecord extends AcquisitionEntry {
  /// The wire format this record was written in.
  final int schemaVersion;

  @override
  final int journalSequence;

  @override
  final AttemptIdentity identity;

  /// The task that was presented.
  final AcquisitionTask task;

  /// Whether anything was played at all.
  final bool started;

  /// Whether the sequence came out, and at what cost.
  final AcquisitionCompletion completion;

  /// Extra notes immediately followed by the expected one.
  final int repairs;

  /// Extra notes that were the note the performance was already on.
  final int repeats;

  /// Extra notes that were something else.
  final int intrusions;

  /// The first moment nothing arrived for, or null when everything did.
  final int? firstAbsentPosition;

  /// The wait before each moment that arrived.
  final List<RecordedGap> gaps;

  /// Whether this attempt earned a probe of the unchanged parent, as the rule
  /// in force at the time read it.
  final bool earnedProbe;

  /// Throws [ArgumentError] when a probe was earned by an attempt that did not
  /// complete, which no observation produces.
  AcquisitionAttemptRecord({
    required this.journalSequence,
    required this.identity,
    required this.task,
    required this.started,
    required this.completion,
    required this.repairs,
    required this.repeats,
    required this.intrusions,
    required this.earnedProbe,
    required List<RecordedGap> gaps,
    this.firstAbsentPosition,
    this.schemaVersion = acquisitionSchemaVersion,
  }) : gaps = List.unmodifiable(gaps) {
    if (earnedProbe && !completion.isComplete) {
      throw ArgumentError.value(
        earnedProbe,
        'earnedProbe',
        'a criterion success is a completion',
      );
    }
  }

  /// Which profile this attempt belongs to.
  String get profileId => identity.profileId;

  /// The exercise a criterion success here would earn a probe of.
  @override
  Exercise get parent => task.parent;

  /// Writes the record.
  @override
  Map<String, Object?> toJson() => {
    'record_type': JournalRecordType.acquisitionAttempt.id,
    'schema_version': schemaVersion,
    'journal_sequence': journalSequence,
    'profile_id': identity.profileId,
    'attempt_id': identity.attemptId,
    'session_id': identity.sessionId,
    'index_in_session': identity.indexInSession,
    'occurred_at': encodeTime(identity.occurredAt),
    'parent': encodeExercise(task.parent),
    'portion': task.portion is FullTraversal ? 'FULL_TRAVERSAL' : null,
    'timing': task.timing.id,
    'advancement': task.advancement.id,
    'started': started,
    'completion': completion.id,
    'repairs': repairs,
    'repeats': repeats,
    'intrusions': intrusions,
    'first_absent_position': firstAbsentPosition,
    'earned_probe': earnedProbe,
    'gaps': [
      for (final gap in gaps)
        {
          'from': gap.fromPosition,
          'to': gap.toPosition,
          'gap_ms': gap.gapMs,
          'ratio': gap.ratio,
        },
    ],
  };

  /// Reads a record back.
  ///
  /// Throws [JournalFormatException] for anything it cannot read.
  factory AcquisitionAttemptRecord.fromJson(Map<String, Object?> json) {
    final location = 'acquisition record';
    final version = requireInt(json, 'schema_version', location: location);
    if (version != acquisitionSchemaVersion) {
      throw JournalFormatException(
        'acquisition schema version $version is not readable by this build, '
        'which writes version $acquisitionSchemaVersion',
        location: location,
      );
    }
    final portion = requireString(json, 'portion', location: location);
    if (portion != 'FULL_TRAVERSAL') {
      throw JournalFormatException(
        'unknown acquisition portion $portion',
        location: location,
      );
    }
    final completionId = requireString(json, 'completion', location: location);
    final completion = AcquisitionCompletion.values.firstWhere(
      (value) => value.id == completionId,
      orElse: () => throw JournalFormatException(
        'unknown acquisition completion $completionId',
        location: location,
      ),
    );
    return AcquisitionAttemptRecord(
      schemaVersion: version,
      journalSequence: requireInt(json, 'journal_sequence', location: location),
      identity: AttemptIdentity(
        profileId: requireString(json, 'profile_id', location: location),
        attemptId: requireString(json, 'attempt_id', location: location),
        sessionId: requireString(json, 'session_id', location: location),
        indexInSession: requireInt(
          json,
          'index_in_session',
          location: location,
        ),
        occurredAt: requireTime(json, 'occurred_at', location: location),
      ),
      task: AcquisitionTask(
        parent: decodeExercise(
          requireMap(json, 'parent', location: location),
          location: location,
        ),
        timing: TimingDemand.fromId(
          requireString(json, 'timing', location: location),
        ),
        advancement: TaskAdvancement.fromId(
          requireString(json, 'advancement', location: location),
        ),
      ),
      started: requireBool(json, 'started', location: location),
      completion: completion,
      repairs: requireInt(json, 'repairs', location: location),
      repeats: requireInt(json, 'repeats', location: location),
      intrusions: requireInt(json, 'intrusions', location: location),
      firstAbsentPosition: asOptionalInt(
        json['first_absent_position'],
        'first_absent_position',
        location: location,
      ),
      earnedProbe: requireBool(json, 'earned_probe', location: location),
      gaps: [
        for (final entry in _requireGaps(json, location))
          _decodeGap(asMap(entry, 'gap', location: location), location),
      ],
    );
  }

  static List<Object?> _requireGaps(
    Map<String, Object?> json,
    String location,
  ) {
    final value = json['gaps'];
    if (value is List<Object?>) return value;
    throw JournalFormatException(
      'expected a list at "gaps", got ${value.runtimeType}',
      location: location,
    );
  }

  static RecordedGap _decodeGap(Map<String, Object?> json, String location) => (
    fromPosition: requireInt(json, 'from', location: location),
    toPosition: requireInt(json, 'to', location: location),
    gapMs: requireInt(json, 'gap_ms', location: location),
    ratio: requireDouble(json, 'ratio', location: location),
  );

  @override
  String toString() =>
      'AcquisitionAttemptRecord(${identity.attemptId}, ${completion.id})';
}

/// One probe of a parent exercise, presented and thereby served.
///
/// Service is presentation, not success. What acquisition earned is that the
/// ordinary question be asked; what the answer means is the ordinary path's to
/// decide, and it decides it through the attempt journal like any other
/// attempt.
///
/// The identity is the ordinary attempt that asked the question, because
/// service is that presentation rather than a separate event beside it. That
/// makes it a reference into the attempt journal and not an ordering
/// invariant: the two logs still derive nothing from each other. It also means
/// one ordinary attempt can discharge an obligation at most once, since the log
/// is idempotent by attempt id.
@immutable
final class AcquisitionProbeServedRecord extends AcquisitionEntry {
  /// The wire format this record was written in.
  final int schemaVersion;

  @override
  final int journalSequence;

  @override
  final AttemptIdentity identity;

  @override
  final Exercise parent;

  AcquisitionProbeServedRecord({
    required this.journalSequence,
    required this.identity,
    required this.parent,
    this.schemaVersion = acquisitionSchemaVersion,
  });

  @override
  Map<String, Object?> toJson() => {
    'record_type': JournalRecordType.acquisitionProbeServed.id,
    'schema_version': schemaVersion,
    'journal_sequence': journalSequence,
    'profile_id': identity.profileId,
    'attempt_id': identity.attemptId,
    'session_id': identity.sessionId,
    'index_in_session': identity.indexInSession,
    'occurred_at': encodeTime(identity.occurredAt),
    'parent': encodeExercise(parent),
  };

  /// Reads a record back.
  ///
  /// Throws [JournalFormatException] for anything it cannot read.
  factory AcquisitionProbeServedRecord.fromJson(Map<String, Object?> json) {
    const location = 'acquisition probe service';
    final version = requireInt(json, 'schema_version', location: location);
    if (version != acquisitionSchemaVersion) {
      throw JournalFormatException(
        'acquisition schema version $version is not readable by this build, '
        'which writes version $acquisitionSchemaVersion',
        location: location,
      );
    }
    return AcquisitionProbeServedRecord(
      schemaVersion: version,
      journalSequence: requireInt(json, 'journal_sequence', location: location),
      identity: AttemptIdentity(
        profileId: requireString(json, 'profile_id', location: location),
        attemptId: requireString(json, 'attempt_id', location: location),
        sessionId: requireString(json, 'session_id', location: location),
        indexInSession: requireInt(
          json,
          'index_in_session',
          location: location,
        ),
        occurredAt: requireTime(json, 'occurred_at', location: location),
      ),
      parent: decodeExercise(
        requireMap(json, 'parent', location: location),
        location: location,
      ),
    );
  }

  @override
  String toString() => 'AcquisitionProbeServedRecord(${identity.attemptId})';
}

/// An append-only history of one profile's acquisition work.
///
/// Deliberately separate from [AttemptJournal]. That log is the source of
/// truth for learner state, and an acquisition attempt is not evidence for it,
/// so a reader that folds every record it finds must not be able to find one
/// of these. Replaying this produces [AcquisitionProgress] and nothing else.
///
/// The two logs share no ordering invariant, because neither derives from the
/// other. Each carries its own timestamps.
class AcquisitionJournal {
  /// Which profile this history belongs to.
  final AcquisitionJournalHeader header;

  final List<AcquisitionEntry> _records = [];
  final Map<String, String> _hashByAttemptId = {};

  AcquisitionJournal(this.header);

  /// Every acquisition event, oldest first.
  List<AcquisitionEntry> get records => List.unmodifiable(_records);

  /// Every attempt at an acquisition task, oldest first.
  List<AcquisitionAttemptRecord> get attempts => [
    for (final entry in _records)
      if (entry is AcquisitionAttemptRecord) entry,
  ];

  /// How many events this log holds.
  int get length => _records.length;

  /// The sequence the next appended record must carry.
  int get nextSequence => _records.length;

  /// Appends [record], or does nothing if that exact attempt is already
  /// recorded.
  ///
  /// Idempotent by attempt id, and not first-write-wins: an id that returns
  /// with different content is a collision rather than a retry.
  ///
  /// Throws [JournalFormatException] when the record belongs to another
  /// profile, when its sequence is not the next one, or when its timestamp
  /// precedes the previous attempt.
  bool append(AcquisitionEntry record) {
    final location = 'acquisition entry ${record.identity.attemptId}';

    if (record.identity.profileId != header.profileId) {
      throw JournalFormatException(
        'attempt belongs to profile ${record.identity.profileId}, but this '
        'log holds ${header.profileId}',
        location: location,
      );
    }

    final hash = contentHash(record.toJson());
    final existing = _hashByAttemptId[record.identity.attemptId];
    if (existing != null) {
      if (existing == hash) return false;
      throw JournalFormatException(
        'attempt id ${record.identity.attemptId} is already recorded with '
        'different content; an id that returns with new content is a '
        'collision, not a retry',
        location: location,
      );
    }

    if (record.journalSequence != nextSequence) {
      throw JournalFormatException(
        'journal sequence ${record.journalSequence} is not the expected '
        '$nextSequence; a gap means a record was lost, and a repeat means one '
        'was duplicated',
        location: location,
      );
    }

    if (_records.isNotEmpty) {
      final previous = _records.last.identity.occurredAt;
      if (record.identity.occurredAt.isBefore(previous)) {
        throw JournalFormatException(
          'attempt time ${encodeTime(record.identity.occurredAt)} precedes the '
          'previous attempt at ${encodeTime(previous)}',
          location: location,
        );
      }
    }

    _records.add(record);
    _hashByAttemptId[record.identity.attemptId] = hash;
    return true;
  }

  /// The progress this history produces.
  ///
  /// The whole of what replaying acquisition means. Each record contributes the
  /// verdict it was written with, so a threshold that moves afterwards changes
  /// what the next attempt earns and never what a past one did.
  AcquisitionProgress replay() {
    var progress = const AcquisitionProgress.empty();
    for (final record in _records) {
      progress = switch (record) {
        AcquisitionAttemptRecord() => progress.recording(
          parent: record.parent,
          completed: record.completion.isComplete,
          earnedProbe: record.earnedProbe,
          at: record.identity.occurredAt,
        ),
        AcquisitionProbeServedRecord() => progress.serving(
          parent: record.parent,
          at: record.identity.occurredAt,
        ),
      };
    }
    return progress;
  }

  /// Encodes the log as JSON lines, header first.
  String toJsonLines() => [
    canonicalJson(header.toJson()),
    for (final record in _records) canonicalJson(record.toJson()),
  ].join('\n');

  /// Reads a log back from JSON lines.
  ///
  /// Throws [JournalFormatException] for a missing header, an unknown record
  /// type, or any record the reader cannot interpret.
  factory AcquisitionJournal.fromJsonLines(String source) {
    final lines = source
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      throw const JournalFormatException(
        'acquisition log is empty, expected a header',
      );
    }

    AcquisitionJournal? journal;
    for (var i = 0; i < lines.length; i++) {
      final Object? decoded;
      try {
        decoded = jsonDecode(lines[i]);
      } on FormatException catch (error) {
        throw JournalFormatException(
          'line is not valid JSON: ${error.message}',
          location: 'line ${i + 1}',
        );
      }
      if (decoded is! Map<String, Object?>) {
        throw JournalFormatException(
          'expected an object',
          location: 'line ${i + 1}',
        );
      }
      final type = JournalRecordType.fromId(
        requireString(decoded, 'record_type', location: 'line ${i + 1}'),
      );

      switch (type) {
        case JournalRecordType.acquisitionHeader:
          if (i != 0) {
            throw JournalFormatException(
              'a log header may only be the first line',
              location: 'line ${i + 1}',
            );
          }
          journal = AcquisitionJournal(
            AcquisitionJournalHeader.fromJson(decoded),
          );
        case JournalRecordType.acquisitionAttempt:
          if (journal == null) {
            throw JournalFormatException(
              'an acquisition attempt appeared before the log header',
              location: 'line ${i + 1}',
            );
          }
          journal.append(AcquisitionAttemptRecord.fromJson(decoded));
        case JournalRecordType.acquisitionProbeServed:
          if (journal == null) {
            throw JournalFormatException(
              'a probe service appeared before the log header',
              location: 'line ${i + 1}',
            );
          }
          journal.append(AcquisitionProbeServedRecord.fromJson(decoded));
        case JournalRecordType.header:
        case JournalRecordType.attempt:
          throw JournalFormatException(
            'an attempt record appeared in an acquisition log',
            location: 'line ${i + 1}',
          );
      }
    }

    if (journal == null) {
      throw const JournalFormatException('acquisition log has no header');
    }
    return journal;
  }

  @override
  String toString() =>
      'AcquisitionJournal(${header.profileId}, ${_records.length} events)';
}
