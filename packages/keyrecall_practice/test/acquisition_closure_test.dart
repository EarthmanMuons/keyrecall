import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  final parent = Exercise.linear(
    material: material,
    hands: HandConfiguration.right,
    octaves: 1,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
    guidance: GuidanceContext.continuouslyCued,
  );
  final task = AcquisitionTask.unmeteredTraversal(parent);
  final expected = [
    for (final moment in realizeAcquisition(task).moments)
      moment.noteFor(Hand.right)!.midiNote,
  ];
  final t0 = DateTime.utc(2026, 9, 9, 10);

  PerformanceTranscript played(List<int> midiNotes, List<int> gaps) {
    var transcript = PerformanceTranscript.empty;
    var at = 0;
    for (final (index, midiNote) in midiNotes.indexed) {
      at += index == 0 ? 0 : gaps[index - 1];
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: material),
        timestampMs: at,
      );
    }
    return transcript;
  }

  AcquisitionObservation observedWith({int? stallBefore}) => observeAcquisition(
    task: task,
    transcript: played(expected, [
      for (var i = 1; i < expected.length; i++)
        if (i == stallBefore) 4000 else 900,
    ]),
  );

  AttemptIdentity identityAt(int index) => AttemptIdentity(
    profileId: 'abc12345',
    attemptId: 'acq-$index',
    sessionId: 'sitting-1',
    indexInSession: index,
    occurredAt: t0.add(Duration(minutes: index)),
  );

  test('ordinary exposure survives replay without borrowing another task', () {
    final other = parent.atTempo(120);
    final log = AttemptJournal(
      JournalHeader(profileId: 'abc12345', createdAt: t0),
    );
    final measurement = measure(
      realization: realize(parent),
      transcript: played(expected.take(3).toList(), [900, 900]),
    );
    final outcome = outcomeFor(measurement: measurement, exercise: parent);
    final closures = [
      AttemptClosure.measured(
        termination: AttemptTermination.learnerStopped,
        outcome: outcome,
        weights: evidenceWeightsFor(parent, outcome),
        memoryUpdate: const MemoryUpdateDiagnostics(),
      ),
      AttemptClosure.unmeasured(
        termination: AttemptTermination.inputInterrupted,
      ),
    ];
    for (final (index, closure) in closures.indexed) {
      log.append(
        AttemptRecord(
          journalSequence: index,
          identity: identityAt(index),
          provenance: ModelProvenance.of(
            learnerParams: v1LearnerParams,
            schedulerModelVersion: v1SchedulerConfig.modelVersion,
          ),
          exercise: index == 0 ? parent : other,
          closure: closure,
        ),
      );
    }
    final restored = AttemptJournal.fromJsonLines(log.toJsonLines());
    expect(attemptedExercises(restored.records), {parent});
    expect(attemptedExercises(restored.records), isNot(contains(other)));
  });

  group('serving a probe by presenting the parent', () {
    final other = Exercise.linear(
      material: TechnicalMaterial('G', ScaleForm.major),
      hands: HandConfiguration.right,
      octaves: 1,
      direction: ExerciseDirection.up,
      tempoBpm: 60,
      guidance: GuidanceContext.continuouslyCued,
    );

    AcquisitionProgress owing() => const AcquisitionProgress.empty().recording(
      parent: parent,
      completed: true,
      earnedProbe: true,
      at: t0,
    );

    AcquisitionProbeServedRecord? serviceFor(
      Exercise presented,
      AcquisitionProgress progress,
    ) => acquisitionServiceOf(
      presented: presented,
      progress: progress,
      identity: identityAt(0),
      journalSequence: 0,
    );

    test('writes one record naming the attempt that asked the question', () {
      final record = serviceFor(parent, owing())!;

      expect(record.parent, parent);
      expect(record.identity.attemptId, 'acq-0');
    });

    test('writes nothing when there is no acquisition history', () {
      expect(serviceFor(parent, const AcquisitionProgress.empty()), isNull);
    });

    test('writes nothing when history has earned no probe', () {
      final practised = const AcquisitionProgress.empty().recording(
        parent: parent,
        completed: true,
        earnedProbe: false,
        at: t0,
      );

      expect(serviceFor(parent, practised), isNull);
    });

    test('writes nothing when the obligation is already discharged', () {
      final served = owing().serving(
        parent: parent,
        at: t0.add(const Duration(minutes: 1)),
      );

      expect(serviceFor(parent, served), isNull);
    });

    test('writes nothing for a different parent', () {
      expect(serviceFor(other, owing()), isNull);
    });

    test('discharges the obligation whatever selected the parent', () {
      // The point of hanging this off presentation. Ordinary ranking asking the
      // question counts exactly as the service phase asking it, so the next
      // slot does not ask it again.
      final log =
          AcquisitionJournal(
            AcquisitionJournalHeader(profileId: 'abc12345', createdAt: t0),
          )..append(
            acquisitionRecordOf(
              observation: observedWith(),
              identity: identityAt(0),
              journalSequence: 0,
            ),
          );
      expect(log.replay().probeOwed(parent), isTrue);

      log.append(
        acquisitionServiceOf(
          presented: parent,
          progress: log.replay(),
          identity: identityAt(1),
          journalSequence: 1,
        )!,
      );

      expect(log.replay().probeOwed(parent), isFalse);
      expect(log.replay().recordFor(parent)!.probesServed, 1);
    });
  });

  group('closing an acquisition attempt', () {
    test('carries the facts across without deriving an outcome', () {
      final observation = observedWith(stallBefore: 4);
      final record = acquisitionRecordOf(
        observation: observation,
        identity: identityAt(0),
        journalSequence: 0,
      );

      expect(record.task, task);
      expect(record.completion, observation.completion);
      expect(record.repairs, observation.repairs);
      expect(record.intrusions, observation.intrusions);
      expect(record.earnedProbe, observation.earnsParentProbe);
      expect(record.gaps, hasLength(observation.gaps.length));
      expect(
        record.gaps.map((gap) => gap.toPosition),
        observation.gaps.map((gap) => gap.toPosition),
      );
    });

    test('reaches progress the scheduler can read, through the log', () {
      // The whole loop, end to end: observe, record, append, replay. A clean
      // traversal earns the parent a probe and a stalled one does not.
      final log = AcquisitionJournal(
        AcquisitionJournalHeader(profileId: 'abc12345', createdAt: t0),
      );
      final attempts = [observedWith(stallBefore: 4), observedWith()];
      for (final (index, observation) in attempts.indexed) {
        log.append(
          acquisitionRecordOf(
            observation: observation,
            identity: identityAt(index),
            journalSequence: index,
          ),
        );
      }

      final progress = log.replay();
      final record = progress.recordFor(parent)!;

      expect(record.attempts, 2);
      expect(record.criterionSuccesses, 1);
      expect(progress.earnsParentProbe(parent), isTrue);
    });

    test('survives being written out and read back', () {
      final log =
          AcquisitionJournal(
            AcquisitionJournalHeader(profileId: 'abc12345', createdAt: t0),
          )..append(
            acquisitionRecordOf(
              observation: observedWith(stallBefore: 4),
              identity: identityAt(0),
              journalSequence: 0,
            ),
          );

      expect(
        AcquisitionJournal.fromJsonLines(log.toJsonLines()).replay().byParent,
        log.replay().byParent,
      );
    });
  });
}
