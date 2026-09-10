import 'dart:io';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'failure_atomicity_test.dart' show FlakyPracticeStore;
import 'support/fixtures.dart';

void main() {
  test(
    'a normalized failure is frozen across retry and file-backed reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'acquisition-order-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final disk = FilePracticeStore(directory);
      final store = FlakyPracticeStore(disk);
      final session = await openSession(
        store,
        pipeline: const AlwaysOffersAcquisition(),
      );
      await session.decideOutcome(at: t0.plusDays(2));
      await session.closeAcquisition(
        PerformanceTranscript.empty,
        at: t0.plusDays(2),
      );
      final offered =
          await session.decideOutcome(at: t0.plusDays(1))
              as PresentedAcquisition;
      store.failAcquisitionAppends = true;
      await expectLater(
        session.closeAcquisition(
          PerformanceTranscript.empty,
          at: t0.plusDays(1),
        ),
        throwsA(isA<Exception>()),
      );
      store.failAcquisitionAppends = false;
      final closed = await session.closeAcquisition(
        PerformanceTranscript.empty,
        at: t0.plusDays(3),
      );
      expect(closed.identity.occurredAt, t0.plusDays(2));
      expect(closed.observedWallTime, t0.plusDays(1));
      expect(closed.executionEvidenceRevision, 0);
      final reopened = await openSession(disk, sessionId: 'reopened');
      expect(reopened.acquisitionJournal.length, 2);
      expect(
        reopened.acquisitionJournal.attempts.last.toJson(),
        closed.toJson(),
      );
      expect(
        reopened.acquisitionProgress
            .recordFor(offered.task.parent)!
            .evidenceRevisionAtFailure,
        0,
      );
    },
  );

  test(
    'probe service remains appendable after a backward clock adjustment',
    () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final supported = await openSession(
        store,
        pipeline: const AlwaysOffersAcquisition(),
      );
      final offer =
          await supported.decideOutcome(at: t0.plusDays(2))
              as PresentedAcquisition;
      var transcript = PerformanceTranscript.empty;
      for (final (index, moment) in realizeAcquisition(
        offer.task,
      ).moments.indexed) {
        transcript = transcript.appending(
          pitch: spellObservedPitch(
            moment.notes.single.midiNote,
            material: offer.task.parent.material,
          ),
          timestampMs: index * 600,
        );
      }
      await supported.closeAcquisition(transcript, at: t0.plusDays(2));
      final ordinary = await openSession(
        store,
        ids: countingIds('probe'),
        sessionId: 'probe',
      );
      final probe =
          await ordinary.decideOutcome(at: t0.plusDays(1)) as PresentedAttempt;
      expect(probe.exercise, offer.task.parent);
      await ordinary.acknowledgePresentation(probe.decision.attemptId);
      final service =
          ordinary.acquisitionJournal.records.last
              as AcquisitionProbeServedRecord;
      expect(service.identity.occurredAt, t0.plusDays(2));
      expect(service.observedWallTime, t0.plusDays(1));
      expect(ordinary.acquisitionProgress.probeOwed(probe.exercise), isFalse);
    },
  );

  test('only informative ordinary evidence advances its own context', () async {
    final session = await openSession(InMemoryPracticeStore(createdAt: t0));
    final presented =
        await session.decideOutcome(at: t0.plusDays(1)) as PresentedAttempt;
    final record = await session.closeWithOutcome(
      outcomeFor(presented.exercise),
    );
    final parent = record.exercise;
    final context = executionContextOf(parent);
    final failure = const AcquisitionProgress.empty().recording(
      parent: parent,
      completed: false,
      earnedProbe: false,
      at: record.identity.occurredAt,
      executionEvidenceRevision: 1,
    );
    const pipeline = SchedulerPipeline(learner: learner);
    expect(
      pipeline.acquisitionSetAside(
        executionEvidenceRevisions([record]),
        failure,
        parent,
      ),
      isTrue,
    );
    final next = AttemptRecord(
      journalSequence: 1,
      identity: AttemptIdentity(
        profileId: record.profileId,
        attemptId: 'next',
        sessionId: record.identity.sessionId,
        indexInSession: 1,
        occurredAt: record.identity.occurredAt,
      ),
      observedWallTime: t0,
      provenance: record.provenance,
      exercise: parent,
      closure: record.closure,
    );
    final journal = AttemptJournal(session.journal.header)
      ..append(record)
      ..append(next);
    final restored = AttemptJournal.fromJsonLines(journal.toJsonLines());
    expect(
      pipeline.acquisitionSetAside(
        executionEvidenceRevisions(restored.records),
        failure,
        parent,
      ),
      isFalse,
    );
    final silent = AttemptRecord(
      journalSequence: 1,
      identity: record.identity,
      provenance: record.provenance,
      exercise: parent,
      closure: AttemptClosure.unmeasured(
        termination: AttemptTermination.learnerStopped,
      ),
    );
    expect(executionEvidenceRevisions([record, silent])[context], 1);
  });
}
