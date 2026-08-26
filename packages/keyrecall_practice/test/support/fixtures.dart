import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

final DateTime t0 = DateTime.utc(2026);

const LearnerModel learner = LearnerModel();
const LearnerParams params = v1PrototypeLearnerParams;

final Profile alice = Profile(
  id: '3f2a6c18-0000-4000-8000-00000000a11c',
  displayName: 'Alice',
  createdAt: t0,
);

final List<TechnicalMaterial> materials = v1ScaleCatalog.take(3).toList();

/// Ids that count up, so a test can name the attempt it expects.
IdGenerator countingIds([String prefix = 'attempt']) {
  var next = 0;
  return () => '$prefix-${next++}';
}

Outcome outcomeOf({
  FactualRetrieval retrieval = FactualRetrieval.succeeded,
  bool started = true,
  bool completed = true,
  double quality = 0.9,
  // Its own axis, not a quality score: how fast it was played is what the
  // execution evidence is attributed at, and these tests mean "at the tempo it
  // was asked for" unless they say otherwise.
  double tempoRatio = 1.0,
}) => Outcome(
  started: started,
  retrieval: retrieval,
  completed: completed,
  materialRetrieval: quality,
  pitchIntegrity: quality,
  continuity: quality,
  temporalStability: quality,
  achievedTempoRatio: tempoRatio,
  topologyAccuracy: quality,
);

/// An outcome that matches what the presented exercise could observe.
///
/// A continuously cued exercise never tests retrieval, so claiming a success on
/// one would be a lie the model is entitled to reject.
Outcome outcomeFor(Exercise exercise, {bool succeeded = true}) => outcomeOf(
  retrieval: exercise.guidance.isRetrievalObserved
      ? (succeeded ? FactualRetrieval.succeeded : FactualRetrieval.failed)
      : FactualRetrieval.notTested,
);

/// Opens a sitting against [store], with reproducible ids.
Future<PracticeSession> openSession(
  PracticeStore store, {
  Profile? profile,
  String sessionId = 'session-1',
  IdGenerator? ids,
  bool presentOnlyMeasurable = true,
}) => PracticeSession.open(
  store: store,
  profile: profile ?? alice,
  materials: materials,
  learner: learner,
  sessionId: sessionId,
  nextId: ids ?? countingIds(),
  presentOnlyMeasurable: presentOnlyMeasurable,
);

/// Runs [attempts] complete attempts against [session], starting at [startDay].
///
/// Returns the records committed. Slots that admit nothing are skipped, since
/// they present nothing and record nothing.
Future<List<AttemptRecord>> practise(
  PracticeSession session, {
  int attempts = 4,
  double startDay = 0.5,
  bool succeed = true,
}) async {
  final committed = <AttemptRecord>[];
  var slot = 0;
  while (committed.length < attempts) {
    if (slot > 500) {
      throw StateError('gave up waiting for $attempts admitted attempts');
    }
    final at = t0.plusDays(startDay + 0.5 * slot);
    slot++;
    final presented = await session.decide(at: at);
    if (presented == null) continue;
    committed.add(
      await session.commit(outcomeFor(presented.exercise, succeeded: succeed)),
    );
  }
  return committed;
}
