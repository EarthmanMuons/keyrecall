import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/journal_arbitraries.dart';

const LearnerModel model = LearnerModel();

/// Where a history starts: a cold learner with no material yet, or one of the
/// placements a new profile begins from.
final Arbitrary<(String, LearnerState Function(DateTime))> anyGenesis =
    choiceOf<(String, LearnerState Function(DateTime))>([
      ('cold', (at) => LearnerState.cold(model.params, at: at)),
      for (final tier in PlacementTier.values)
        (tier.id, (at) => model.placementState(tier, at: at)),
    ]);

/// Minutes, days, or a season between attempts.
final Arbitrary<int> anyPause = weighted<int>([
  (4, integer(min: 0, max: 3600000000)),
  (3, integer(min: 3600000000, max: 7 * 86400000000)),
  (1, integer(min: 30 * 86400000000, max: 180 * 86400000000)),
]);

/// One attempt before it is written: which of the history's exercises, how
/// long after the last, what was measured if anything, and how it ended.
typedef Step = (int, int, Outcome?, AttemptTermination);

final Arbitrary<Step> anyStep = combine4(
  integer(min: 0, max: 3),
  anyPause,
  weighted<Outcome?>([
    (5, anyOutcome.map<Outcome?>((outcome) => outcome)),
    (1, constant<Outcome?>(null)),
  ]),
  choiceOf(AttemptTermination.values),
);

/// A performance that measured everything, for building a populated state.
final Outcome anyOutcomeExample = Outcome(
  started: true,
  retrieval: FactualRetrieval.succeeded,
  completed: true,
  materialRetrieval: 0.9,
  pitchIntegrity: 0.9,
  continuity: 0.9,
  temporalStability: 0.9,
  achievedTempoRatio: 1,
  topologyAccuracy: 0.9,
  coordination: 0.9,
);

/// [outcome] as [exercise] could have produced it: retrieval is tested exactly
/// when the rung observes it, and an attempt that never began completed and
/// retrieved nothing.
Outcome plausibleFor(Exercise exercise, Outcome outcome) {
  final tested = exercise.guidance.isRetrievalObserved;
  final retrieval = !tested
      ? FactualRetrieval.notTested
      : !outcome.started || outcome.retrieval == FactualRetrieval.notTested
      ? FactualRetrieval.failed
      : outcome.retrieval;
  return Outcome(
    started: outcome.started,
    retrieval: retrieval,
    completed: outcome.started && outcome.completed,
    materialRetrieval: outcome.materialRetrieval,
    pitchIntegrity: outcome.pitchIntegrity,
    continuity: outcome.continuity,
    temporalStability: outcome.temporalStability,
    achievedTempoRatio: outcome.achievedTempoRatio,
    topologyAccuracy: outcome.topologyAccuracy,
    coordination: outcome.coordination,
    pulseMaintenance: outcome.pulseMaintenance,
  );
}

/// A history written the way the practice loop writes one, and the learner
/// state it held after each attempt.
///
/// The states are the writer's own, taken as it went, so they are evidence
/// independent of replay.
({AttemptJournal journal, LearnerState initial, List<LearnerState> after})
historyOf(
  LearnerState Function(DateTime) genesis,
  DateTime start,
  List<Exercise> exercises,
  List<Step> steps,
) {
  final initial = genesis(start);
  final state = initial.copy();
  final journal = AttemptJournal(
    JournalHeader(profileId: 'learner', createdAt: start),
  );
  final provenance = ModelProvenance(
    learnerModelVersion: model.params.modelVersion,
    schedulerModelVersion: 'scheduler',
  );
  final after = <LearnerState>[];
  var at = start;
  for (final (sequence, (which, pause, measured, termination))
      in steps.indexed) {
    final later = at.add(Duration(microseconds: pause));
    at = later.year > 9999 ? at : later;
    final exercise = exercises[which % exercises.length];
    final String before;
    final AttemptClosure closure;
    if (measured == null) {
      // Decided against a propagated copy; nothing was applied.
      before = learnerStateHash(propagatedCopy(state, at));
      closure = AttemptClosure.unmeasured(termination: termination);
    } else {
      model.propagate(state, at);
      before = learnerStateHash(state);
      final outcome = plausibleFor(exercise, measured);
      final weights = evidenceWeightsFor(exercise, outcome);
      final update = model.applyOutcome(
        state: state,
        exercise: exercise,
        outcome: outcome,
        weights: weights,
        prediction: model.predict(state, exercise, at: at),
        at: at,
      );
      closure = AttemptClosure.measured(
        termination: termination,
        outcome: outcome,
        weights: weights,
        memoryUpdate: update,
      );
    }
    journal.append(
      AttemptRecord(
        journalSequence: sequence,
        identity: AttemptIdentity(
          profileId: 'learner',
          attemptId: 'attempt-$sequence',
          sessionId: 'session',
          indexInSession: sequence,
          occurredAt: at,
        ),
        provenance: provenance,
        exercise: exercise,
        closure: closure,
        stateBeforeHash: before,
        stateAfterHash: learnerStateHash(state),
      ),
    );
    after.add(state.copy());
  }
  return (journal: journal, initial: initial, after: after);
}

/// [state] as it would stand at [at], leaving [state] itself alone.
LearnerState propagatedCopy(LearnerState state, DateTime at) {
  final copy = state.copy();
  model.propagate(copy, at);
  return copy;
}

/// What a learner state predicts for [exercises] at [at], which is what the
/// scheduler reads from it and so what a recovered state must reproduce.
List<Prediction> predictionsOf(
  LearnerState state,
  List<Exercise> exercises,
  DateTime at,
) => [
  for (final exercise in exercises)
    model.predict(propagatedCopy(state, at), exercise, at: at),
];

List<(int, double)> _spans(Map<int, double> bySpan) =>
    [for (final MapEntry(:key, :value) in bySpan.entries) (key, value)]
      ..sort((a, b) => a.$1.compareTo(b.$1));

/// Every field of a competency, by name.
Map<String, Object?> competencyFacts(CompetencyState c) => {
  'competency': c.competency,
  'mean': c.mean,
  'variance': c.variance,
  'updatedAt': c.updatedAt,
  'lastEvidenceAt': c.lastEvidenceAt,
};

/// Every field of a material's memory, by name.
Map<String, Object?> memoryFacts(MaterialMemoryState m) => {
  'materialId': m.materialId,
  'logCurrentHalfLife': m.logCurrentHalfLife,
  'currentHalfLifeUncertainty': m.currentHalfLifeUncertainty,
  'logConsolidatedHalfLife': m.logConsolidatedHalfLife,
  'consolidatedLogHalfLifeVariance': m.consolidatedLogHalfLifeVariance,
  'logitColdStart': m.logitColdStart,
  'coldStartUncertainty': m.coldStartUncertainty,
  'memoryAnchorAt': m.memoryAnchorAt,
  'factualLastRetrievalAt': m.factualLastRetrievalAt,
  'establishedIndependence': m.establishedIndependence,
  'establishedIndependenceAt': m.establishedIndependenceAt,
  'lastRetrievalAttemptAt': m.lastRetrievalAttemptAt,
};

/// Every field of an execution context's state, by name.
Map<String, Object?> executionFacts(MaterialExecutionState e) => {
  'materialId': e.materialId,
  'familyId': e.familyId,
  'hands': e.hands,
  'handMotion': e.handMotion,
  'residualMean': e.residualMean,
  'residualVariance': e.residualVariance,
  'updatedAt': e.updatedAt,
  'lastEvidenceAt': e.lastEvidenceAt,
  'demonstratedTempoByOctaves': _spans(e.demonstratedTempoByOctaves),
  'pacedTempoBpm': e.pacedTempoBpm,
  'coordinationReadyTempoByOctaves': _spans(e.coordinationReadyTempoByOctaves),
};

/// Every field of [state], read from the objects rather than through the codec.
///
/// The state hashes are computed through the codec, so a field it failed to
/// write would be invisible to every one of them.
Map<String, Object?> factsOf(LearnerState state) => {
  'competencies': [
    for (final competency in Competency.values)
      if (state.competencies[competency] case final c?) competencyFacts(c),
  ],
  'materialMemory': [
    for (final m
        in state.materialMemory.values.toList()
          ..sort((a, b) => a.materialId.compareTo(b.materialId)))
      memoryFacts(m),
  ],
  'materialExecution': [
    for (final MapEntry(:key, :value)
        in state.materialExecution.entries.toList()
          ..sort((a, b) => '${a.key}'.compareTo('${b.key}')))
      [key, executionFacts(value)],
  ],
};

final RegExp _fieldDeclaration = RegExp(
  r'^  (?:final |late final |late )?[A-Za-z][\w<>?, ]*[\w>?] (\w+)'
  r'(?: = [^;]*)?;$',
  multiLine: true,
);

/// The fields class [type] declares in [file] of the learner's state, which
/// the facts above must name exactly.
///
/// Read from the source, one declaration per line, since nothing at runtime
/// lists a class's fields.
Future<Set<String>> declaredFields(String file, String type) async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:keyrecall_learner/src/state/$file'),
  );
  final source = File.fromUri(uri!).readAsStringSync();
  final start = source.indexOf(RegExp('^class $type\\b', multiLine: true));
  final body = source.substring(start, source.indexOf('\n}\n', start));
  return {
    for (final match in _fieldDeclaration.allMatches(body)) match.group(1)!,
  };
}

/// [checkpoint] as storage hands it back.
LearnerStateCheckpoint reread(LearnerStateCheckpoint checkpoint) =>
    LearnerStateCheckpoint.fromJson(
      jsonDecode(stored(canonicalJson(checkpoint.toJson())))
          as Map<String, Object?>,
      params: model.params,
    );

/// Every kind of state, boundary, and pause the generated histories reached.
final Set<String> reached = {};

void noteReached(LearnerState state) {
  for (final memory in state.materialMemory.values) {
    reached.addAll([
      if (memory.memoryAnchorAt != null) 'memory anchor',
      if (memory.factualLastRetrievalAt != null) 'factual retrieval',
      if (memory.establishedIndependence != null) 'established independence',
      if (memory.establishedIndependenceAt != null) 'independence time',
      if (memory.lastRetrievalAttemptAt != null) 'retrieval attempt',
    ]);
  }
  for (final execution in state.materialExecution.values) {
    reached.addAll([
      if (execution.demonstratedTempoByOctaves.isNotEmpty) 'demonstrated tempo',
      if (execution.coordinationReadyTempoByOctaves.isNotEmpty)
        'coordination-ready tempo',
      if (execution.lastEvidenceAt != null) 'execution evidence',
    ]);
  }
  if (state.competencies.values.any((c) => c.lastEvidenceAt != null)) {
    reached.add('competency evidence');
  }
  if (state.materialMemory.isEmpty && state.materialExecution.isEmpty) {
    reached.add('no material yet');
  }
}

void main() {
  property('recovering from any checkpoint reaches the state genesis does', () {
    forAll(
      combine4(
        anyGenesis,
        integer(
          min: DateTime.utc(2020).microsecondsSinceEpoch,
          max: DateTime.utc(2030).microsecondsSinceEpoch,
        ),
        list(anyExercise, minLength: 1, maxLength: 4),
        list(anyStep, minLength: 1, maxLength: 12),
      ),
      seed: seed,
      maxExamples: examples(60),
      failingOnErrors<
        (
          (String, LearnerState Function(DateTime)),
          int,
          List<Exercise>,
          List<Step>,
        )
      >((parts) {
        final ((genesisName, genesis), startMicros, exercises, steps) = parts;
        final start = DateTime.fromMicrosecondsSinceEpoch(
          startMicros,
          isUtc: true,
        );
        final history = historyOf(genesis, start, exercises, steps);
        final journal = history.journal;
        final whole = replayJournal(
          journal,
          model: model,
          initial: history.initial,
        );
        reached.add('genesis ${genesisName.toLowerCase()}');
        noteReached(history.initial);

        expect(
          whole.divergences,
          isEmpty,
          reason: 'history replays as written',
        );
        expect(whole.stateHash, learnerStateHash(history.after.last));
        expect(factsOf(whole.state), factsOf(history.after.last));

        final later = journal.records.last.identity.occurredAt.add(
          const Duration(days: 3),
        );
        final expected = predictionsOf(whole.state, exercises, later);
        final genesisHash = learnerStateHash(history.initial);

        for (var through = 0; through < journal.length; through++) {
          final where = 'checkpoint through sequence $through of $steps';
          final written = LearnerStateCheckpoint.after(
            journal,
            throughSequence: through,
            state: history.after[through],
            learnerModelVersion: model.params.modelVersion,
            genesisStateHash: genesisHash,
          );
          final checkpoint = reread(written);
          noteReached(checkpoint.state);
          reached.addAll([
            if (through == 0) 'first boundary',
            if (through == journal.length - 1) 'last boundary',
            if (through > 0 && through < journal.length - 1) 'middle boundary',
            if (journal.records[through].closure.measurement
                is MeasurementUnavailable)
              'unmeasured boundary',
          ]);

          expect(
            canonicalJson(checkpoint.toJson()),
            canonicalJson(written.toJson()),
            reason: 'reading back and writing again changes nothing: $where',
          );
          expect(checkpoint.contentHash, written.contentHash, reason: where);
          expect(
            learnerStateHash(checkpoint.state),
            journal.records[through].stateAfterHash,
            reason: where,
          );
          expect(
            factsOf(checkpoint.state),
            factsOf(history.after[through]),
            reason: 'the state read back is the state written: $where',
          );
          expect(
            predictionsOf(checkpoint.state, exercises, later),
            predictionsOf(history.after[through], exercises, later),
            reason: 'the state read back predicts what was written: $where',
          );

          final resumed = replayJournal(
            journal,
            model: model,
            initial: history.initial,
            from: checkpoint,
          );
          expect(resumed.divergences, isEmpty, reason: where);
          expect(resumed.stateHash, whole.stateHash, reason: where);
          expect(
            factsOf(resumed.state),
            factsOf(history.after.last),
            reason: where,
          );
          expect(
            predictionsOf(resumed.state, exercises, later),
            expected,
            reason: where,
          );
        }
        for (final (index, record) in journal.records.indexed.skip(1)) {
          final previous = journal.records[index - 1].identity.occurredAt;
          if (record.identity.occurredAt.difference(previous).inDays >= 30) {
            reached.add('season away');
          }
        }
      }),
    );
  });

  test('the facts name every field the learner state declares', () async {
    // A tripwire. A field added to the state that these facts do not read is
    // one the recovery property cannot see the codec lose; update the facts
    // and the learner codec together.
    final state = historyOf(
      (at) => model.placementState(PlacementTier.advanced, at: at),
      DateTime.utc(2026),
      [shapes.first],
      [(0, 0, anyOutcomeExample, AttemptTermination.learnerStopped)],
    ).after.last;

    expect(
      factsOf(state).keys.toSet(),
      await declaredFields('learner_state.dart', 'LearnerState'),
    );
    expect(
      competencyFacts(state.competencies.values.first).keys.toSet(),
      await declaredFields('competency_state.dart', 'CompetencyState'),
    );
    expect(
      memoryFacts(state.materialMemory.values.first).keys.toSet(),
      await declaredFields('material_memory_state.dart', 'MaterialMemoryState'),
    );
    expect(
      executionFacts(state.materialExecution.values.first).keys.toSet(),
      await declaredFields(
        'material_execution_state.dart',
        'MaterialExecutionState',
      ),
    );
  });

  test('the generated histories reach every kind of state and boundary', () {
    expect(
      reached,
      containsAll([
        'genesis cold',
        for (final tier in PlacementTier.values)
          'genesis ${tier.id.toLowerCase()}',
        'no material yet',
        'memory anchor',
        'factual retrieval',
        'established independence',
        'independence time',
        'retrieval attempt',
        'demonstrated tempo',
        'coordination-ready tempo',
        'execution evidence',
        'competency evidence',
        'first boundary',
        'middle boundary',
        'last boundary',
        'unmeasured boundary',
        'season away',
      ]),
    );
  });
}
