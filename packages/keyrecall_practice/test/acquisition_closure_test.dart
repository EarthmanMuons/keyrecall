import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
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
