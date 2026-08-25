/// The durable boundary under KeyRecall: what history is, and how state is
/// recovered from it.
///
/// An [AttemptJournal] is an append-only record of what was presented and what
/// happened, and it is the source of truth. Learner state is whatever
/// [replayJournal] produces from it, and a [LearnerStateCheckpoint] is
/// disposable acceleration: deleting every checkpoint must cost time and
/// nothing else.
///
/// Serialization lives here rather than on the model types, so the wire format
/// can change without touching the model, and so there is exactly one place
/// that owns schema versioning. Nothing here knows about a storage engine; an
/// adapter wraps it, which is what stops the engine from deciding the schema.
library;

export 'src/attempt_closure.dart';
export 'src/attempt_journal.dart';
export 'src/attempt_record.dart';
// The decode toolkit is exported alongside the codecs: an adapter that
// writes journal-adjacent records needs the same conventions and the same
// uniform failure type.
export 'src/canonical_json.dart';
export 'src/checkpoint.dart';
export 'src/codecs/domain_codec.dart';
export 'src/codecs/learner_codec.dart';
export 'src/codecs/scheduler_codec.dart';
export 'src/profile.dart';
export 'src/replay.dart';
export 'src/schema.dart';
export 'src/upgrade.dart';
