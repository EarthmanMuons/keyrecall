/// Version of the attempt-record wire format.
///
/// Every persisted record carries this. A reader that meets a version it does
/// not understand must fail rather than guess, because a journal is the
/// historical source of truth and a misread record silently rewrites history.
///
/// Bumping it requires a pure, versioned upgrade function and upgrade tests
/// covering existing persisted state, historical golden journals, and
/// genuinely new material separately.
///
/// A retained version does not mean that version was ever released. Version 1
/// existed only during development, and is kept because upgrading it exercises
/// a real structural change: an outcome and its derived evidence became the
/// measured branch of a lifecycle sum, and the upgrade proves that historical
/// records keep their interpretation and replay to the same learner state.
/// Provenance and a regression fixture, not a claim about what shipped.
///
/// It is also not a precedent that every pre-release rearrangement bumps this.
/// Ordinary churn before release should rewrite fixtures instead; a bump is for
/// a change worth being able to prove survived.
const int attemptSchemaVersion = 4;

/// Version of the checkpoint wire format.
///
/// Independent of [attemptSchemaVersion]: checkpoints are disposable
/// acceleration, so this one may move without the journal moving.
///
/// Version 2 records the family each execution residual was earned in.
/// Nothing infers it for a version 1 checkpoint: the id of a scale does not
/// name its family, and manufacturing provenance that was never stored is
/// worse than rebuilding from the attempts, which is what an unreadable
/// checkpoint already asks for.
const int checkpointSchemaVersion = 2;

/// Version of the acquisition-log wire format.
///
/// Independent of [attemptSchemaVersion], because the two logs answer to
/// different readers: replaying attempts produces learner state, and replaying
/// acquisition produces acquisition progress and nothing else.
///
/// Version 2 records how an attempt ended. Version 1 did not, and nothing
/// infers it: an attempt the learner stopped and one an input disconnection
/// cut off looked identical in that format, and choosing between them
/// afterwards would put a cause on a record that never carried one.
///
/// Version 3 separates the app ending an attempt because the traversal was
/// covered from the learner ending it. Version 2 wrote both as the learner
/// stopping, so those records read back with no termination at all, for the
/// same reason version 1's do.
///
/// Version 4 carries an ordinary execution-evidence revision and preserves the
/// wall clock when the acquisition log needs a later logical timestamp.
///
/// Version 5 names the portion a task asked for and how many traversals of it.
/// Version 4 could write only one, so its records read back as a single full
/// traversal, which is what they were.
const int acquisitionSchemaVersion = 5;

/// Discriminator for the record kinds a journal file can hold.
enum JournalRecordType {
  /// Identifies the journal and the learner it belongs to. First line.
  header('journal_header'),

  /// One practice attempt.
  attempt('attempt'),

  /// Identifies an acquisition log and the learner it belongs to. First line.
  acquisitionHeader('acquisition_header'),

  /// One attempt at an acquisition task.
  ///
  /// Kept out of the attempt log rather than mixed into it. Replaying attempts
  /// produces learner state, and an acquisition attempt is deliberately not
  /// evidence for that state, so putting the two in one log would make the
  /// source of truth for learner state contain records it must ignore.
  acquisitionAttempt('acquisition_attempt'),

  /// One probe of a parent exercise, presented and thereby served.
  ///
  /// Not an acquisition attempt, and not derived from one: it is an ordinary
  /// presentation caused by acquisition history. It lives in the acquisition
  /// log because it is a transition of the acquisition state machine, and
  /// nothing else would be able to say the obligation was discharged.
  acquisitionProbeServed('acquisition_probe_served');

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
