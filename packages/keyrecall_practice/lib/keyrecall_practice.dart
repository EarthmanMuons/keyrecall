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
library;

export 'src/file_practice_store.dart';
export 'src/pending_decision.dart';
export 'src/practice_session.dart';
export 'src/practice_store.dart';
