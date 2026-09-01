import 'dart:convert';

import 'package:meta/meta.dart';

import 'attempt_record.dart';
import 'canonical_json.dart';
import 'profile.dart';
import 'schema.dart';
import 'upgrade.dart';

/// Identifies a journal and the profile whose history it holds.
///
/// One journal per profile. A shared install has no single learner, so
/// ownership is stated here and repeated on every record: the header scopes
/// the file, and the record stays self-describing once it leaves the file.
@immutable
class JournalHeader {
  /// Which profile this history belongs to.
  final String profileId;

  /// When this journal was created, in UTC.
  ///
  /// Storage provenance, not learner timeline. Nothing derives a model
  /// timestamp from it: placement is anchored at the profile's creation
  /// instant, and every elapsed interval comes from the attempts themselves.
  /// Recording when the history began is still worth doing, but a reader must
  /// not mistake it for a point the model reasons from.
  final DateTime createdAt;

  JournalHeader({required String profileId, required DateTime createdAt})
    : profileId = requireProfileId(profileId),
      createdAt = createdAt.toUtc();

  /// Writes the header.
  Map<String, Object?> toJson() => {
    'record_type': JournalRecordType.header.id,
    'schema_version': attemptSchemaVersion,
    'profile_id': profileId,
    'created_at': encodeTime(createdAt),
  };

  /// Reads a header back.
  factory JournalHeader.fromJson(Map<String, Object?> json) {
    json = upgradeJournalHeaderJson(json);
    return JournalHeader(
      profileId: requireString(json, 'profile_id', location: 'header'),
      createdAt: requireTime(json, 'created_at', location: 'header'),
    );
  }

  @override
  String toString() => 'JournalHeader($profileId)';
}

/// An append-only history of one profile's practice attempts.
///
/// The source of truth. Learner state is whatever replaying this produces, so
/// nothing here is ever rewritten: [append] adds to the end, and appending the
/// same attempt twice is a no-op rather than a second event.
///
/// Records carry a contiguous [AttemptRecord.journalSequence] and a
/// nondecreasing timestamp. Both are enforced on append, so a lost line and a
/// timeline that runs backward are detectable rather than silently absorbed.
///
/// Scoped to a single profile. An install holds one of these per person, and
/// they never interleave: mixing two people's evidence into one state is the
/// failure this scoping exists to prevent.
///
/// Deliberately storage-free. It holds records in memory and encodes to
/// JSON lines; a database or file adapter wraps it. Keeping the contract here,
/// above any storage engine, is what stops the engine from deciding the
/// schema.
class AttemptJournal {
  /// Which profile this history belongs to.
  final JournalHeader header;

  final List<AttemptRecord> _records = [];
  final Map<String, String> _hashByAttemptId = {};
  final Map<String, int> _lastIndexBySession = {};

  AttemptJournal(this.header);

  /// Every attempt, oldest first.
  List<AttemptRecord> get records => List.unmodifiable(_records);

  /// How many attempts this journal holds.
  int get length => _records.length;

  /// Whether the journal holds no attempts yet.
  bool get isEmpty => _records.isEmpty;

  /// Whether [attemptId] has already been recorded.
  bool contains(String attemptId) => _hashByAttemptId.containsKey(attemptId);

  /// The sequence the next appended record must carry.
  int get nextSequence => _records.length;

  /// Appends [record], or does nothing if that exact attempt is already
  /// recorded.
  ///
  /// Returns whether it was newly appended. A retried commit after an
  /// interrupted write is a no-op, so the same evidence cannot be folded in
  /// twice. But idempotency is not first-write-wins: an attempt id that comes
  /// back carrying *different* content is a collision, not a retry, and it
  /// throws. In an authoritative log, silently keeping one of two conflicting
  /// records is worse than refusing both.
  ///
  /// Throws [JournalFormatException] when the record belongs to another
  /// profile, when its journal sequence is not the next one, when its
  /// timestamp precedes the previous attempt, or when its attempt index does
  /// not advance within its session.
  bool append(AttemptRecord record) {
    final location = 'attempt ${record.identity.attemptId}';

    if (record.identity.profileId != header.profileId) {
      throw JournalFormatException(
        'attempt belongs to profile ${record.identity.profileId}, but this '
        'journal holds ${header.profileId}',
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
          'previous attempt at ${encodeTime(previous)}; the model timeline '
          'cannot run backward, because propagating backward is illegal',
          location: location,
        );
      }
    }

    final sessionId = record.identity.sessionId;
    final index = record.identity.indexInSession;
    final lastIndex = _lastIndexBySession[sessionId];
    if (lastIndex != null && index <= lastIndex) {
      throw JournalFormatException(
        'attempt index $index does not advance past $lastIndex in session '
        '$sessionId',
        location: location,
      );
    }

    _records.add(record);
    _hashByAttemptId[record.identity.attemptId] = hash;
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
      final Object? decoded;
      try {
        decoded = jsonDecode(lines[i]);
      } on FormatException catch (error) {
        // Uniform failure type: a caller reading an untrusted journal should
        // catch one thing, not one thing plus whatever the JSON parser throws.
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
      'AttemptJournal(${header.profileId}, ${_records.length} attempts)';
}
