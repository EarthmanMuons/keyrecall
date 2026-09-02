import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/practice/attempt_feedback.dart';

void main() {
  final exercise = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    tempoBpm: 60,
  );

  Outcome outcome({
    double notes = 1,
    double flow = 1,
    double pulse = 1,
    double tempo = 1,
    bool started = true,
    bool completed = true,
    FactualRetrieval retrieval = FactualRetrieval.succeeded,
  }) => Outcome(
    started: started,
    retrieval: retrieval,
    completed: completed,
    materialRetrieval: completed ? 1 : 0.5,
    pitchIntegrity: notes,
    continuity: flow,
    temporalStability: pulse,
    achievedTempoRatio: tempo,
    topologyAccuracy: notes,
  );

  AttemptRecord record(int index, Outcome result, {Exercise? task}) {
    final played = task ?? exercise;
    return AttemptRecord(
      journalSequence: index,
      identity: AttemptIdentity(
        profileId: 'profile',
        attemptId: 'attempt-$index',
        sessionId: 'session',
        indexInSession: index,
        occurredAt: DateTime.utc(2026, 1, 1, 12, index),
      ),
      provenance: const ModelProvenance(
        learnerModelVersion: 'learner',
        schedulerModelVersion: 'scheduler',
      ),
      exercise: played,
      closure: AttemptClosure.measured(
        termination: AttemptTermination.learnerStopped,
        outcome: result,
        weights: evidenceWeightsFor(played, result),
        memoryUpdate: const MemoryUpdateDiagnostics(),
      ),
    );
  }

  test('summary reports performance measurements at the requested task', () {
    final summary = summarizeAttempt(
      record(0, outcome(notes: 0.8, flow: 0.9, pulse: 0.7, tempo: 0.95)),
    )!;

    expect(summary.notes, 0.8);
    expect(summary.flow, 0.9);
    expect(summary.pulse, 0.7);
    expect(summary.achievedTempoBpm, 57);
    expect(summary.targetTempoBpm, 60);
  });

  test('an attempt with no performance gets no summary', () {
    expect(summarizeAttempt(record(0, outcome(started: false))), isNull);
  });

  test('first clean completion is a factual progress event', () {
    final rough = record(0, outcome(pulse: 0.8));
    final clean = record(1, outcome());

    final event = progressEventFor(clean, history: [rough, clean])!;

    expect(event.type, ProgressEventKind.firstCleanCompletion);
    expect(event.sentence, 'First clean right-hand pass at 60 BPM.');
  });

  test('three clean attempts establish reliability once', () {
    final attempts = [
      record(0, outcome(pulse: 0.8)),
      record(1, outcome()),
      record(2, outcome()),
      record(3, outcome()),
      record(4, outcome()),
    ];

    expect(
      progressEventFor(attempts[3], history: attempts)!.type,
      ProgressEventKind.repeatedReliability,
    );
    expect(progressEventFor(attempts[4], history: attempts), isNull);
  });

  test('first completed retrieval is distinct from clean execution', () {
    final recalled = record(0, outcome(notes: 0.9));

    final event = progressEventFor(recalled, history: [recalled])!;

    expect(event.type, ProgressEventKind.firstIndependentCompletion);
    expect(event.sentence, 'First time through from memory at 60 BPM.');
  });

  test('a cued completion does not claim independent retrieval', () {
    final cued = record(
      0,
      outcome(notes: 0.9, retrieval: FactualRetrieval.notTested),
    );

    expect(progressEventFor(cued, history: [cued]), isNull);
  });
}
