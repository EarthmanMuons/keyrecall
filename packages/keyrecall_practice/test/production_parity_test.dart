import 'dart:io';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  _testProductionParity(fixtureMaterials);
  _testProductionParity([proofArpeggios.first]);
}

void _testProductionParity(List<TechnicalMaterial> catalog) {
  test(
    '${catalog.first.familyId} production decisions and effects survive replay and host transport',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'production-parity-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final pipeline = pipelineCappedAt(30);
      final direct = _ParityPath(
        'direct',
        InMemoryPracticeStore(createdAt: t0),
        pipeline,
        InProcessScheduler(pipeline),
        materials: catalog,
      );
      final replayed = _ParityPath(
        'replayed',
        FilePracticeStore(Directory('${directory.path}/replayed')),
        pipeline,
        InProcessScheduler(pipeline),
        materials: catalog,
      );
      final worker = _ParityPath(
        'worker',
        FilePracticeStore(Directory('${directory.path}/worker')),
        pipeline,
        IsolateScheduler(),
        materials: catalog,
      );
      final paths = [direct, replayed, worker];
      for (final path in paths) {
        addTearDown(path.dispose);
        await path.open();
      }

      void expectAgreement(String stage) {
        for (final path in paths.skip(1)) {
          expect(
            persistentFacts(path.session),
            persistentFacts(direct.session),
            reason: '${path.name} history at $stage',
          );
          expect(
            sittingFacts(path.sitting),
            sittingFacts(direct.sitting),
            reason: '${path.name} sitting at $stage',
          );
        }
      }

      final kinds = <String>{};
      final earnedParents = <Exercise>{};
      var acquisitions = 0;
      var probes = 0;
      var reopenedFailures = 0;
      var reopenedSuccesses = 0;

      for (var slot = 0; slot < 32; slot++) {
        await replayed.replay();
        expectAgreement('the start of slot $slot');

        final at = t0.add(Duration(minutes: slot + 1));
        for (final path in paths) {
          await path.decide(at);
        }
        for (final path in paths.skip(1)) {
          expect(
            decisionFacts(path.decision),
            decisionFacts(direct.decision),
            reason: '${path.name} decision at slot $slot',
          );
          expect(
            effectFacts(path.verdict),
            effectFacts(direct.verdict),
            reason: '${path.name} effect at slot $slot',
          );
        }

        switch (direct.decision) {
          case PresentedAcquisition(:final task):
            kinds.add('acquisition');
            if (catalog.first is ArpeggioMaterial) {
              expect(task.portion, TraversalRepetitions(2));
            }
            acquisitions++;
            final succeeds = acquisitions.isEven;
            final transcript = succeeds
                ? cleanTraversal(task)
                : PerformanceTranscript.empty;
            for (final path in paths) {
              final closed = await path.session.closeAcquisition(
                transcript,
                at: at,
              );
              expect(
                closed.earnedProbe,
                succeeds,
                reason: '${path.name} at slot $slot',
              );
            }
            // Recurrence has to survive reconstruction from the journals alone.
            final reopened = await replayed.reopen();
            expect(persistentFacts(reopened), persistentFacts(direct.session));
            expect(reopened.acquisitionJournal.attempts.last.task, task);
            if (succeeds) {
              earnedParents.add(task.parent);
              if (catalog.first is ArpeggioMaterial) {
                expect(
                  reopened.acquisitionJournal.attempts.last.gaps,
                  hasLength(6),
                );
              }
              reopenedSuccesses++;
              expect(
                reopened.acquisitionProgress.probeOwed(task.parent),
                isTrue,
              );
            } else {
              reopenedFailures++;
              expect(
                pipeline.acquisitionSetAside(
                  executionEvidenceRevisions(reopened.journal.records),
                  reopened.acquisitionProgress,
                  task.parent,
                ),
                isTrue,
              );
            }
          case PresentedAttempt(decision: final chosen):
            kinds.add('ordinary');
            if (chosen.decision.challengeBypass ==
                ChallengeBypass.acquisitionProbe) {
              expect(earnedParents.remove(chosen.exercise), isTrue);
              probes++;
            }
            for (final path in paths) {
              final presented = path.decision as PresentedAttempt;
              await path.session.acknowledgePresentation(
                presented.decision.attemptId,
              );
              await path.session.closeWithOutcome(
                outcomeOf(
                  retrieval: presented.exercise.guidance.isRetrievalObserved
                      ? FactualRetrieval.failed
                      : FactualRetrieval.notTested,
                  quality: 0.1,
                  tempoRatio: 0.3,
                ),
                observedWallTime: at,
              );
            }
          case PracticeBlocked():
            kinds.add('blocked');
          case PracticeCaughtUp():
            kinds.add('caughtUp');
          default:
            fail('unexpected production decision: ${direct.decision}');
        }
        expectAgreement('the end of slot $slot');
      }
      expect(kinds, containsAll(['ordinary', 'acquisition', 'blocked']));
      expect(reopenedFailures, greaterThan(0));
      expect(reopenedSuccesses, greaterThan(0));
      expect(probes, greaterThan(0));

      // A genuinely new sitting clears transient service state the same way on
      // every path, rather than inheriting it from the sitting that just ended.
      for (final path in paths) {
        await path.open(sessionId: 'next-sitting');
        expect(path.sitting.attemptsThisSession, 0);
        expect(path.sitting.lastAcquisitionParent, isNull);
      }
      expectAgreement('a new sitting');
      for (final path in paths) {
        await path.decide(t0.plusDays(1));
      }
      for (final path in paths.skip(1)) {
        expect(
          decisionFacts(path.decision),
          decisionFacts(direct.decision),
          reason: '${path.name} decision in a new sitting',
        );
      }
    },
  );
}

/// One execution path a production decision can travel.
///
/// The paths differ only in where history is persisted and where the pipeline
/// runs, so equivalent inputs owe equivalent decisions and effects.
class _ParityPath {
  final String name;
  final PracticeStore store;
  final List<TechnicalMaterial> materials;
  final SchedulerPipeline pipeline;
  final _RecordingHost host;
  final IdGenerator ids = countingIds();
  late PracticeSession session;
  late PracticeDecision decision;

  _ParityPath(
    this.name,
    this.store,
    this.pipeline,
    SchedulerHost host, {
    required this.materials,
  }) : host = _RecordingHost(host);

  SessionState get sitting => session.session;

  SchedulerVerdict get verdict => host.last!;

  Future<void> open({String sessionId = 'sitting'}) async =>
      session = await reopen(sessionId: sessionId);

  /// Opens a second view of the same store, leaving [session] untouched.
  Future<PracticeSession> reopen({String sessionId = 'sitting'}) => openSession(
    store,
    materials: materials,
    pipeline: pipeline,
    scheduler: host,
    ids: ids,
    sessionId: sessionId,
    placement: PlacementTier.beginner,
  );

  /// Rebuilds the session from persisted history, restoring the sitting state
  /// a live session would still be holding in memory.
  Future<void> replay() async {
    final previous = sitting;
    await open();
    copySitting(previous, sitting);
  }

  Future<PracticeDecision> decide(DateTime at) async =>
      decision = await session.decideOutcome(at: at);

  Future<void> dispose() => host.dispose();
}

Object decisionFacts(PracticeDecision decision) => switch (decision) {
  PresentedAttempt(:final exercise, :final decision) => (
    'ordinary',
    exercise,
    decision.decision.challengeBypass,
  ),
  PresentedAcquisition(:final task) => ('acquisition', task),
  PracticeBlocked(:final reason) => ('blocked', reason),
  PracticeCaughtUp() => 'caughtUp',
  PracticeInvalidScope() => 'invalid',
  PracticeSuperseded() => 'superseded',
};

Object effectFacts(SchedulerVerdict verdict) => (
  verdict.effect.guidanceProbeAvailable,
  verdict.effect.guidanceProbeSelected,
  verdict.effect.offeredAcquisitionParent,
);

Map<String, Object?> persistentFacts(PracticeSession session) => {
  'learner': encodeLearnerState(session.state),
  'acquisition': encodeAcquisitionProgress(session.acquisitionProgress),
  'attempted': attemptedExercises(session.journal.records),
  'revisions': executionEvidenceRevisions(session.journal.records),
  'ordinary': [for (final record in session.journal.records) record.toJson()],
  'supported': [
    for (final record in session.acquisitionJournal.records) record.toJson(),
  ],
};

Map<String, Object?> sittingFacts(SessionState session) => {
  'slots': session.attemptsThisSession,
  'recent': List.of(session.recentMaterialIds),
  'recovery': session.lastFailedExercise,
  'tempo': session.tempoProbe,
  'fresh': session.tempoProbeIsFresh,
  'supported': session.supportedAttemptsSinceObservation,
  'unserved': session.unservedGuidanceProbeSelections,
  'acquisition': session.lastAcquisitionParent,
  'families': [
    for (final observation in session.recentFamilies)
      {
        'families': observation.families,
        'productive': observation.productive,
        'at': observation.at,
      },
  ],
};

void copySitting(SessionState from, SessionState to) {
  to.attemptsThisSession = from.attemptsThisSession;
  to.recentMaterialIds
    ..clear()
    ..addAll(from.recentMaterialIds);
  to.lastFailedExercise = from.lastFailedExercise;
  to.tempoProbe = from.tempoProbe;
  to.tempoProbeIsFresh = from.tempoProbeIsFresh;
  to.supportedAttemptsSinceObservation = from.supportedAttemptsSinceObservation;
  to.unservedGuidanceProbeSelections = from.unservedGuidanceProbeSelections;
  to.lastAcquisitionParent = from.lastAcquisitionParent;
  to.recentFamilies
    ..clear()
    ..addAll(from.recentFamilies);
}

PerformanceTranscript cleanTraversal(AcquisitionTask task) {
  var transcript = PerformanceTranscript.empty;
  for (final (index, moment) in realizeAcquisition(task).moments.indexed) {
    transcript = transcript.appending(
      pitch: spellObservedPitch(
        moment.notes.single.midiNote,
        material: task.parent.material,
      ),
      timestampMs: index * 600,
    );
  }
  return transcript;
}

/// Keeps the effect of the last decision, which a host applies and discards.
class _RecordingHost implements SchedulerHost {
  final SchedulerHost inner;
  SchedulerVerdict? last;

  _RecordingHost(this.inner);

  @override
  Future<void> bind({
    required ResolvedPracticeScope scope,
    required PracticeEntryPolicy entry,
    required LearnerModel learner,
    required SchedulerConfig config,
  }) =>
      inner.bind(scope: scope, entry: entry, learner: learner, config: config);

  @override
  Future<void> dispose() => inner.dispose();

  @override
  Future<SchedulerVerdict> decide({
    required int epoch,
    required LearnerState state,
    required SessionState session,
    required List<String> dueRequirementIds,
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    Set<Exercise>? attemptedExercises,
    Map<ExecutionContext, int> executionEvidenceRevisions = const {},
  }) async => last = await inner.decide(
    epoch: epoch,
    state: state,
    session: session,
    dueRequirementIds: dueRequirementIds,
    at: at,
    acquisitionFloor: acquisitionFloor,
    acquisitionFamilyFloor: acquisitionFamilyFloor,
    acquisition: acquisition,
    attemptedExercises: attemptedExercises,
    executionEvidenceRevisions: executionEvidenceRevisions,
  );
}
