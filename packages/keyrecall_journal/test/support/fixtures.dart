import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

final DateTime t0 = DateTime.utc(2026);

/// A stable profile for these tests, standing in for one person on a shared
/// install.
final Profile testProfile = Profile(
  id: '3f2a6c18-0000-4000-8000-000000000001',
  displayName: 'Alice',
  createdAt: t0,
);

/// The material these tests reach for when the choice does not matter.
final TechnicalMaterial v1ScaleCatalogFirst = v1ScaleCatalog.first;

const LearnerModel model = LearnerModel();
const LearnerParams params = v1LearnerParams;
const SchedulerConfig schedulerConfig = v1PrototypeSchedulerConfig;
const SchedulerPipeline pipeline = SchedulerPipeline(learner: model);

const ModelProvenance provenance = ModelProvenance(
  learnerModelVersion: 'v1-2',
  schedulerModelVersion: 'v1-prototype-0',
  appBuildVersion: 'test',
);

Exercise exerciseFor(
  TechnicalMaterial material, {
  HandConfiguration hands = HandConfiguration.right,
  GuidanceContext guidance = GuidanceContext.unguided,
  double tempoBpm = 80,
}) => Exercise.linear(
  material: material,
  hands: hands,
  tempoBpm: tempoBpm,
  guidance: guidance,
);

Outcome outcomeOf({
  FactualRetrieval retrieval = FactualRetrieval.succeeded,
  bool started = true,
  bool completed = true,
  double quality = 0.9,
}) => Outcome(
  started: started,
  retrieval: retrieval,
  completed: completed,
  materialRetrieval: quality,
  pitchIntegrity: quality,
  continuity: quality,
  temporalStability: quality,
  achievedTempoRatio: quality,
  topologyAccuracy: quality,
);

/// A journal built by actually running the model, so its records are the ones
/// the production loop would have written rather than hand-assembled fiction.
///
/// Returns the journal alongside the state it started from, which is what
/// replay has to reproduce.
///
/// Slots where the scheduler admits nothing produce no record, which is the
/// point: an attempt slot is a decision opportunity, and a selection exists
/// only when that decision produces something to present. The journal holds
/// presented attempts, so its indices count attempts rather than slots.
({AttemptJournal journal, LearnerState initial}) recordSession({
  int attempts = 6,
  String sessionId = 'session-1',
  List<TechnicalMaterial>? materials,
  bool withDecisions = true,
  bool withStateHashes = true,
  AttemptJournal? continuing,
  LearnerState? fromState,
  double startDay = 0,
}) {
  final catalog = materials ?? v1ScaleCatalog.take(3).toList();
  final initial =
      fromState ?? model.placementState(PlacementTier.someExperience, at: t0);
  final state = initial.copy();
  final journal =
      continuing ??
      AttemptJournal(JournalHeader(profileId: testProfile.id, createdAt: t0));
  final session = SessionState();
  final candidates = generateCandidates(InstrumentProfile(), catalog);

  var recorded = 0;
  for (var slot = 0; recorded < attempts; slot++) {
    if (slot > 500) {
      throw StateError('gave up waiting for $attempts admitted attempts');
    }
    final at = t0.plusDays(startDay + 0.5 * (slot + 1));

    SchedulerDecision? decision;
    Exercise exercise;
    if (withDecisions) {
      // Evaluated against a scratch copy propagated to the decision time.
      // Canonical state advances only when an attempt is actually committed;
      // see the note on that rule in replayJournal.
      final scratch = state.copy();
      model.propagate(scratch, at);
      final traces = pipeline.evaluate(
        state: scratch,
        session: session,
        candidates: candidates,
        at: at,
      );
      final chosen = pipeline.selectChoice(traces, session);
      session.attemptsThisSession++;
      if (chosen == null) continue;
      decision = SchedulerDecision.fromTrace(chosen, schedulerConfig);
      exercise = chosen.exercise;
    } else {
      exercise = exerciseFor(catalog[recorded % catalog.length]);
      session.attemptsThisSession++;
    }

    // Committing the attempt is what advances canonical state.
    model.propagate(state, at);
    final before = learnerStateHash(state);

    final prediction = model.predict(state, exercise, at: at);
    // Alternate the retrieval outcome so the journal exercises every branch,
    // including the untested case that must survive serialization as null.
    final outcome = outcomeOf(
      retrieval: exercise.guidance.isRetrievalObserved
          ? (recorded.isEven
                ? FactualRetrieval.succeeded
                : FactualRetrieval.failed)
          : FactualRetrieval.notTested,
    );
    final weights = evidenceWeightsFor(exercise, outcome);
    final diagnostics = model.applyOutcome(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: weights,
      prediction: prediction,
      at: at,
    );

    session.recordSelection(
      exercise,
      retrievalFailed: outcome.retrieval == FactualRetrieval.failed,
      config: schedulerConfig.diversity,
    );

    var record = AttemptRecord(
      journalSequence: journal.nextSequence,
      identity: AttemptIdentity(
        profileId: testProfile.id,
        attemptId: '$sessionId-attempt-$recorded',
        sessionId: sessionId,
        indexInSession: recorded,
        occurredAt: at,
      ),
      provenance: provenance,
      exercise: exercise,
      decision: decision,
      closure: AttemptClosure.measured(
        termination: AttemptTermination.learnerStopped,

        outcome: outcome,

        weights: weights,

        memoryUpdate: diagnostics,
      ),
    );
    if (withStateHashes) {
      record = record.withStateHashes(
        before: before,
        after: learnerStateHash(state),
      );
    }
    journal.append(record);
    recorded++;
  }

  return (journal: journal, initial: initial);
}

/// The measurement a record carries, for tests that know it has one.
///
/// Deliberately test-only: production code branches on the sum rather than
/// reaching past it, which is what keeps an unmeasured attempt from flowing
/// into anything built on an outcome always existing.
Measured measuredOf(AttemptRecord record) =>
    record.closure.measurement as Measured;

/// The measurement inside a written record, for tests that poke at the wire
/// format.
Map<String, Object?> measurementJsonOf(Map<String, Object?> record) =>
    (record['closure']! as Map<String, Object?>)['measurement']!
        as Map<String, Object?>;
