/// The KeyRecall attempt transaction and its durable store.
///
/// [PracticeSession] runs one sitting: it decides what to present, makes that
/// decision durable before the learner sees it, and commits the outcome as an
/// attempt. It survives being interrupted anywhere in that sequence, because
/// the decision is persisted before presentation and the attempt id chosen
/// there is the journal's idempotency key.
///
/// [PracticeStore] is the port storage implements. [FilePracticeStore] is the
/// reference implementation, appending to ordinary files; a database can
/// replace it without the transaction noticing.
///
/// [ProfileRepository] answers a separate question: who uses this install, and
/// who is using it now. It is kept apart from practice storage because a
/// profile exists before it has any history, and renaming or selecting one has
/// no business touching the attempt transaction.
library;

export 'src/file_practice_store.dart';
export 'src/file_profile_repository.dart';
export 'src/pending_decision.dart';
export 'src/performance_closure.dart';
export 'src/practice_session.dart';
export 'src/practice_store.dart';
export 'src/profile_repository.dart';
