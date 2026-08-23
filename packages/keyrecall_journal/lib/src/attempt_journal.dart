import 'dart:convert';

import 'package:meta/meta.dart';

import 'attempt_record.dart';
import 'canonical_json.dart';
import 'schema.dart';

/// Identifies a journal and the learner whose history it holds.
///
/// The learner id lives here rather than on every attempt because the storage
/// architecture is one journal per learner. If that ever changes, this is the
/// seam: move the field onto the record and bump the attempt schema, rather
/// than inferring ownership from a file path.
@immutable
class JournalHeader {
  /// Which learner this history belongs to.
  final String learnerId;

  /// When the journal was opened, in UTC.
  final DateTime createdAt;

  JournalHeader({required this.learnerId, required DateTime createdAt})
    : createdAt = createdAt.toUtc() {
    if (learnerId.isEmpty) {
      throw ArgumentError.value(learnerId, 'learnerId', 'must not be empty');
    }
  }

  /// Writes the header.
  Map<String, Object?> toJson() => {
    'record_type': JournalRecordType.header.id,
    'schema_version': attemptSchemaVersion,
    'learner_id': learnerId,
    'created_at': encodeTime(createdAt),
  };

  /// Reads a header back.
  factory JournalHeader.fromJson(Map<String, Object?> json) {
    final version = requireInt(json, 'schema_version');
    if (version != attemptSchemaVersion) {
      throw JournalFormatException(
        'journal schema version $version is not readable by this build, which '
        'writes version $attemptSchemaVersion',
      );
    }
    return JournalHeader(
      learnerId: requireString(json, 'learner_id', location: 'header'),
      createdAt: requireTime(json, 'created_at', location: 'header'),
    );
  }

  @override
  String toString() => 'JournalHeader($learnerId)';
}

/// An append-only history of practice attempts.
///
/// The source of truth. Learner state is whatever replaying this produces, so
/// nothing here is ever rewritten: [append] adds to the end, and appending the
/// same attempt twice is a no-op rather than a second event.
///
/// Deliberately storage-free. It holds records in memory and encodes to
/// JSON lines; a database or file adapter wraps it. Keeping the contract here,
/// above any storage engine, is what stops the engine from deciding the
/// schema.
class AttemptJournal {
  /// Which learner this history belongs to.
  final JournalHeader header;

  final List<AttemptRecord> _records = [];
  final Set<String> _attemptIds = {};
  final Map<String, int> _lastIndexBySession = {};

  AttemptJournal(this.header);

  /// Every attempt, oldest first.
  List<AttemptRecord> get records => List.unmodifiable(_records);

  /// How many attempts this journal holds.
  int get length => _records.length;

  /// Whether the journal holds no attempts yet.
  bool get isEmpty => _records.isEmpty;

  /// Whether [attemptId] has already been recorded.
  bool contains(String attemptId) => _attemptIds.contains(attemptId);

  /// Appends [record], or does nothing if that attempt is already recorded.
  ///
  /// Returns whether it was newly appended. Idempotent on the attempt id, so a
  /// retried commit after an interrupted write cannot fold the same evidence in
  /// twice.
  ///
  /// Throws [JournalFormatException] when the attempt index does not advance
  /// within its session, since that would mean history arriving out of order.
  bool append(AttemptRecord record) {
    if (_attemptIds.contains(record.identity.attemptId)) return false;

    final sessionId = record.identity.sessionId;
    final index = record.identity.indexInSession;
    final lastIndex = _lastIndexBySession[sessionId];
    if (lastIndex != null && index <= lastIndex) {
      throw JournalFormatException(
        'attempt index $index does not advance past $lastIndex in session '
        '$sessionId',
        location: 'attempt ${record.identity.attemptId}',
      );
    }

    _records.add(record);
    _attemptIds.add(record.identity.attemptId);
    _lastIndexBySession[sessionId] = index;
    return true;
  }

  /// Appends every record in order, returning how many were new.
  int appendAll(Iterable<AttemptRecord> records) {
    var appended = 0;
    for (final record in records) {
      if (append(record)) appended++;
    }
    return appended;
  }

  /// The attempts belonging to [sessionId], in order.
  Iterable<AttemptRecord> session(String sessionId) =>
      _records.where((record) => record.identity.sessionId == sessionId);

  /// Encodes the journal as JSON lines, header first.
  ///
  /// One record per line, so an adapter can append without rewriting what came
  /// before, and so a person can read a journal with ordinary tools.
  String toJsonLines() => [
    canonicalJson(header.toJson()),
    for (final record in _records) canonicalJson(record.toJson()),
  ].join('\n');

  /// Reads a journal back from JSON lines.
  ///
  /// Throws [JournalFormatException] for a missing header, an unknown record
  /// type, or any record the reader cannot interpret. Skipping an unreadable
  /// line would silently drop history.
  factory AttemptJournal.fromJsonLines(String source) {
    final lines = source
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      throw const JournalFormatException('journal is empty, expected a header');
    }

    AttemptJournal? journal;
    for (var i = 0; i < lines.length; i++) {
      final decoded = jsonDecode(lines[i]);
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
        case JournalRecordType.header:
          if (i != 0) {
            throw JournalFormatException(
              'a journal header may only be the first line',
              location: 'line ${i + 1}',
            );
          }
          journal = AttemptJournal(JournalHeader.fromJson(decoded));
        case JournalRecordType.attempt:
          if (journal == null) {
            throw JournalFormatException(
              'an attempt appeared before the journal header',
              location: 'line ${i + 1}',
            );
          }
          journal.append(AttemptRecord.fromJson(decoded));
      }
    }

    if (journal == null) {
      throw const JournalFormatException('journal has no header');
    }
    return journal;
  }

  @override
  String toString() =>
      'AttemptJournal(${header.learnerId}, ${_records.length} attempts)';
}
