/// Version of the attempt-record wire format.
///
/// Every persisted record carries this. A reader that meets a version it does
/// not understand must fail rather than guess, because a journal is the
/// historical source of truth and a misread record silently rewrites history.
///
/// Bumping it requires a pure, versioned upgrade function and upgrade tests
/// covering existing persisted state, historical golden journals, and
/// genuinely new material separately.
const int attemptSchemaVersion = 1;

/// Version of the checkpoint wire format.
///
/// Independent of [attemptSchemaVersion]: checkpoints are disposable
/// acceleration, so this one may move without the journal moving.
const int checkpointSchemaVersion = 1;

/// Discriminator for the record kinds a journal file can hold.
enum JournalRecordType {
  /// Identifies the journal and the learner it belongs to. First line.
  header('journal_header'),

  /// One practice attempt.
  attempt('attempt');

  const JournalRecordType(this.id);

  /// Stable identifier written to the `record_type` field.
  final String id;

  /// The record type with the given [id].
  ///
  /// Throws [ArgumentError] when no type matches, since an unrecognized record
  /// in an authoritative log is a reason to stop, not to skip a line.
  static JournalRecordType fromId(String id) => values.firstWhere(
    (type) => type.id == id,
    orElse: () =>
        throw ArgumentError.value(id, 'record_type', 'unknown record type'),
  );
}

/// Thrown when persisted data cannot be trusted.
///
/// State corruption, an unknown schema version, a missing model version, or a
/// broken invariant all fail loudly here rather than being repaired into
/// something plausible.
class JournalFormatException implements Exception {
  /// What is wrong, in human-readable form.
  final String message;

  /// Where it is wrong, when the reader can say.
  final String? location;

  const JournalFormatException(this.message, {this.location});

  @override
  String toString() => location == null
      ? 'JournalFormatException: $message'
      : 'JournalFormatException: $message (at $location)';
}
