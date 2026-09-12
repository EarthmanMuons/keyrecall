import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

final DateTime t0 = DateTime.utc(2026);

const LearnerModel learner = LearnerModel();
const LearnerParams params = v1LearnerParams;

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
Outcome outcomeFor(
  Exercise exercise, {
  bool succeeded = true,
  bool started = true,
  bool completed = true,
  double quality = 0.9,
  double tempoRatio = 1.0,
}) => outcomeOf(
  retrieval: exercise.guidance.isRetrievalObserved
      ? (succeeded ? FactualRetrieval.succeeded : FactualRetrieval.failed)
      : FactualRetrieval.notTested,
  started: started,
  completed: completed,
  quality: quality,
  tempoRatio: tempoRatio,
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
  SchedulerHost? scheduler,
}) => PracticeSession.open(
  store: store,
  profile: profile ?? alicePlacedAt(placement),
  materials: materials ?? fixtureMaterials,
  learner: learner,
  pipeline: pipeline,
  scheduler: scheduler,
  sessionId: sessionId,
  nextId: ids ?? countingIds(),
);

/// A pipeline whose sitting ends after [attempts] slots.
///
/// The one deterministic way to reach a slot that admits nothing. A short
/// catalog cannot be run dry, because the scheduler goes on deepening material
/// it already has.
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

/// A pipeline that offers supported work for the floor of the first material.
///
/// When the scheduler offers acquisition is the scheduler's own question, and
/// its tests ask it. These are about what a sitting does with an offer once it
/// has one, so the offer is supplied rather than provoked.
class AlwaysOffersAcquisition extends SchedulerPipeline {
  const AlwaysOffersAcquisition() : super(learner: learner);

  @override
  ({
    SelectionResult result,
    bool guidanceProbeAvailable,
    bool guidanceProbeSelected,
  })
  evaluateSlot({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    Map<Exercise, ChallengeBypass> overrides = const {},
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    Set<Exercise>? attemptedExercises,
    Map<ExecutionContext, int> executionEvidenceRevisions = const {},
    PracticeEntryPolicy? practiceEntryPolicy,
    GoalEmphasis emphasis = GoalEmphasis.none,
  }) {
    final slot = super.evaluateSlot(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: acquisitionFamilyFloor,
      acquisition: acquisition,
      attemptedExercises: attemptedExercises,
      executionEvidenceRevisions: executionEvidenceRevisions,
      practiceEntryPolicy: practiceEntryPolicy,
      emphasis: emphasis,
    );
    final floor = (acquisitionFamilyFloor ?? acquisitionFloor)?.entries.first;
    if (floor == null) return slot;
    return (
      result: AcquisitionOffered(
        traces: slot.result.traces,
        selectable: slot.result.selectable,
        pacing: slot.result.pacing,
        introductions: slot.result.introductions,
        task: AcquisitionTask.unmeteredTraversal(floor.exercise),
        stuck: null,
      ),
      guidanceProbeAvailable: slot.guidanceProbeAvailable,
      guidanceProbeSelected: slot.guidanceProbeSelected,
    );
  }
}

/// The state a profile's history propagates from, which a checkpoint's digest
/// covers along with the records it skips.
String genesisHashOf(Profile profile) => learnerStateHash(
  learner.placementState(profile.placement, at: profile.createdAt),
);

/// A checkpoint over [session]'s history, as that sitting would save one.
LearnerStateCheckpoint checkpointOf(
  PracticeSession session, {
  Profile? profile,
  LearnerState? state,
  String? learnerModelVersion,
}) => LearnerStateCheckpoint.after(
  session.journal,
  throughSequence: session.journal.length - 1,
  state: state ?? session.state,
  learnerModelVersion: learnerModelVersion ?? learner.params.modelVersion,
  genesisStateHash: genesisHashOf(profile ?? alice),
);

/// [exercise] played exactly as it was asked for.
///
/// A moment's notes arrive [spreadMs] apart and the moments [gapMs] apart, so
/// a two-hand exercise is played together and on the beat.
PerformanceTranscript playedFor(
  Exercise exercise, {
  int gapMs = 500,
  int spreadMs = 10,
}) {
  final realization = realize(exercise);
  final perMoment = realization.moments.first.notes.length;
  var transcript = PerformanceTranscript.empty;
  var index = 0;
  for (final moment in realization.moments) {
    for (final note in moment.notes) {
      transcript = transcript.appending(
        pitch: spellObservedPitch(note.midiNote, material: exercise.material),
        timestampMs:
            (index ~/ perMoment) * gapMs + (index % perMoment) * spreadMs,
      );
      index++;
    }
  }
  return transcript;
}

/// The measurement a record carries, for tests that know it has one.
Measured measuredOf(AttemptRecord record) =>
    record.closure.measurement as Measured;
