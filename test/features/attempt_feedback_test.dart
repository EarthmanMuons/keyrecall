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

    final events = progressEventsFor(clean, history: [rough, clean]);

    expect(events.map((event) => event.type), [
      ProgressEventKind.firstCleanCompletion,
    ]);
    expect(
      progressStatementFor(clean, events),
      'First clean right-hand run at 60 BPM.',
    );
  });

  test('simultaneous clean and independent milestones are both preserved', () {
    final clean = record(0, outcome());

    final events = progressEventsFor(clean, history: [clean]);

    expect(events.map((event) => event.type), [
      ProgressEventKind.firstCleanCompletion,
      ProgressEventKind.firstIndependentCompletion,
    ]);
    expect(
      progressStatementFor(clean, events),
      'First clean right-hand run from memory at 60 BPM.',
    );
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
      progressEventsFor(
        attempts[3],
        history: attempts,
      ).map((event) => event.type),
      [ProgressEventKind.repeatedReliability],
    );
    expect(progressEventsFor(attempts[4], history: attempts), isEmpty);
  });

  test('reliability and first independent completion can coincide', () {
    final attempts = [
      record(0, outcome(retrieval: FactualRetrieval.notTested)),
      record(1, outcome(retrieval: FactualRetrieval.notTested)),
      record(2, outcome()),
    ];

    final events = progressEventsFor(attempts.last, history: attempts);

    expect(events.map((event) => event.type), [
      ProgressEventKind.repeatedReliability,
      ProgressEventKind.firstIndependentCompletion,
    ]);
    expect(
      progressStatementFor(attempts.last, events),
      'First time through from memory, and clean on your last three attempts '
      'here.',
    );
  });

  test('first completed retrieval is distinct from clean execution', () {
    final recalled = record(0, outcome(notes: 0.9));

    final events = progressEventsFor(recalled, history: [recalled]);

    expect(events.map((event) => event.type), [
      ProgressEventKind.firstIndependentCompletion,
    ]);
    expect(
      progressStatementFor(recalled, events),
      'First time through from memory at 60 BPM.',
    );
  });

  test('a cued completion does not claim independent retrieval', () {
    final cued = record(
      0,
      outcome(notes: 0.9, retrieval: FactualRetrieval.notTested),
    );

    expect(progressEventsFor(cued, history: [cued]), isEmpty);
  });

  test('a previewed completion does not claim independent retrieval', () {
    final previewed = record(
      0,
      outcome(notes: 0.9),
      task: exercise.withGuidance(GuidanceContext.notesPreviewedOnly),
    );
    final unguided = record(1, outcome(notes: 0.9));

    expect(progressEventsFor(previewed, history: [previewed]), isEmpty);
    expect(
      progressEventsFor(
        unguided,
        history: [previewed, unguided],
      ).map((event) => event.type),
      [ProgressEventKind.firstIndependentCompletion],
    );
  });

  test('progress statements present tempo in whole BPM', () {
    final clean = record(0, outcome(tempo: 2.033));
    final events = progressEventsFor(clean, history: [clean]);

    expect(
      progressStatementFor(clean, events),
      'First clean right-hand run from memory at 122 BPM.',
    );
  });

  test('reliability compares the same execution across guidance levels', () {
    final attempts = [
      record(
        0,
        outcome(retrieval: FactualRetrieval.notTested),
        task: exercise.withGuidance(GuidanceContext.continuouslyCued),
      ),
      record(
        1,
        outcome(),
        task: exercise.withGuidance(GuidanceContext.notesPreviewedOnly),
      ),
      record(2, outcome()),
    ];

    expect(
      progressEventsFor(
        attempts.last,
        history: attempts,
      ).map((event) => event.type),
      [
        ProgressEventKind.repeatedReliability,
        ProgressEventKind.firstIndependentCompletion,
      ],
    );
  });

  test('reliability does not combine attempts at different tempos', () {
    final attempts = [
      record(0, outcome(), task: exercise.atTempo(48)),
      record(1, outcome(), task: exercise.atTempo(60)),
      record(2, outcome(), task: exercise.atTempo(72)),
    ];

    final kinds = progressEventsFor(
      attempts.last,
      history: attempts,
    ).map((event) => event.type);

    expect(kinds, isNot(contains(ProgressEventKind.repeatedReliability)));
  });
}
