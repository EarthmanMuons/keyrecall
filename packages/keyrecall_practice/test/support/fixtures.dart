import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

final DateTime t0 = DateTime.utc(2026);

const LearnerModel learner = LearnerModel();
const LearnerParams params = v1PrototypeLearnerParams;

final Profile alice = alicePlacedAt(PlacementTier.someExperience);

/// Alice, started from [placement].
///
/// Same identity, so the same journal and the same store keys; only the prior
/// her history propagates from differs.
Profile alicePlacedAt(PlacementTier placement) => Profile(
  id: '3f2a6c18-0000-4000-8000-00000000a11c',
  displayName: 'Alice',
  createdAt: t0,
  placement: placement,
);

final List<TechnicalMaterial> fixtureMaterials = v1ScaleCatalog
    .take(3)
    .toList();

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
/// Placement now travels on the profile, so a session over a different tier
/// is a session over a different profile.
Future<PracticeSession> openSession(
  PracticeStore store, {
  Profile? profile,
  String sessionId = 'session-1',
  IdGenerator? ids,
  PlacementTier placement = PlacementTier.someExperience,
  List<TechnicalMaterial>? materials,
  SchedulerPipeline? pipeline,
}) => PracticeSession.open(
  store: store,
  profile: profile ?? alicePlacedAt(placement),
  materials: materials ?? fixtureMaterials,
  learner: learner,
  pipeline: pipeline,
  sessionId: sessionId,
  nextId: ids ?? countingIds(),
);

/// A pipeline whose sitting ends after [attempts] slots.
///
/// The one deterministic way to reach a slot that admits nothing. Running a
/// short catalog dry used to do it and no longer does: the scheduler can go on
/// deepening material it has, which is the point of execution progression and
/// makes running out a bad thing to depend on.
SchedulerPipeline pipelineCappedAt(int attempts) => SchedulerPipeline(
  learner: learner,
  config: SchedulerConfig(
    modelVersion: v1SchedulerConfig.modelVersion,
    eligibility: v1SchedulerConfig.eligibility,
    safety: SafetyConfig(maxSessionAttempts: attempts),
    challenge: v1SchedulerConfig.challenge,
    diversity: v1SchedulerConfig.diversity,
    probe: v1SchedulerConfig.probe,
    pacing: v1SchedulerConfig.pacing,
  ),
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
      await session.closeWithOutcome(
        outcomeFor(presented.exercise, succeeded: succeed),
      ),
    );
  }
  return committed;
}
