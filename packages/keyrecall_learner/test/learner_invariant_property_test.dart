import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_testing/keyrecall_testing.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

const LearnerModel model = LearnerModel();
final DateTime start = DateTime.utc(2026);

final Arbitrary<Exercise> anyExercise =
    combine6(
      choiceOf([
        TechnicalMaterial('C', ScaleForm.major),
        TechnicalMaterial('D', ScaleForm.harmonicMinor),
        ArpeggioMaterial('G', ArpeggioQuality.major),
      ]),
      choiceOf(HandConfiguration.values),
      choiceOf([1, 2]),
      choiceOf(ExerciseDirection.values),
      choiceOf([40.0, 60.0, 90.0, 120.0]),
      choiceOf([
        GuidanceContext.unguided,
        GuidanceContext.notesPreviewedOnly,
        GuidanceContext.continuouslyCued,
      ]),
    ).map((parts) {
      final (material, hands, octaves, direction, tempo, guidance) = parts;
      return Exercise.linear(
        material: material,
        hands: hands,
        octaves: octaves,
        direction: direction,
        tempoBpm: tempo,
        guidance: guidance,
      );
    });

/// How an attempt went, before it is fitted to what its exercise could
/// observe: whether it began and finished, the retrieval it claims, its
/// scores, which timing and coordination it measured, its pace, and whether a
/// pulse was supplied.
typedef Played = (
  (bool, bool, FactualRetrieval),
  (double, double, double),
  (double?, double?, double?),
  double,
  bool,
);

final Arbitrary<double> anyScore = weighted<double>([
  (3, float(min: 0, max: 1)),
  (1, choiceOf([0.0, 1.0])),
]);

final Arbitrary<Played> anyPlayed = combine5(
  combine3(
    weighted<bool>([(9, constant(true)), (1, constant(false))]),
    boolean(),
    choiceOf(FactualRetrieval.values),
  ),
  combine3(anyScore, anyScore, anyScore),
  combine3(optional(anyScore), optional(anyScore), optional(anyScore)),
  weighted<double>([(1, constant(0.0)), (4, float(min: 0, max: 2))]),
  boolean(),
);

/// [played] as [exercise] could have produced it.
Outcome outcomeOf(Exercise exercise, Played played) {
  final ((started, completed, retrieval), scores, timing, tempo, pulsed) =
      played;
  final (material, pitch, topology) = scores;
  final (continuity, stability, coordination) = timing;
  final observed = exercise.guidance.isRetrievalObserved;
  if (!started) {
    return Outcome(
      started: false,
      retrieval: observed
          ? FactualRetrieval.failed
          : FactualRetrieval.notTested,
      completed: false,
      materialRetrieval: 0,
      pitchIntegrity: 0,
      continuity: null,
      temporalStability: null,
      achievedTempoRatio: 0,
      topologyAccuracy: 0,
    );
  }
  return Outcome(
    started: true,
    retrieval: !observed
        ? FactualRetrieval.notTested
        : retrieval == FactualRetrieval.notTested
        ? FactualRetrieval.failed
        : retrieval,
    completed: completed,
    materialRetrieval: material,
    pitchIntegrity: pitch,
    continuity: continuity,
    temporalStability: stability,
    achievedTempoRatio: tempo,
    topologyAccuracy: topology,
    coordination: exercise.conditions.hands == HandConfiguration.together
        ? coordination
        : null,
    pulseMaintenance: pulsed
        ? PulseMaintenance.notTested
        : PulseMaintenance.tested,
  );
}

/// One attempt: which exercise, how long after the last, and how it went.
typedef Step = (int, int, Played);

final Arbitrary<Step> anyStep = combine3(
  integer(min: 0, max: 2),
  weighted<int>([
    (3, integer(min: 0, max: 600)),
    (1, integer(min: 600, max: 60 * 24 * 60)),
  ]),
  anyPlayed,
);

/// Everything the state records, as plain values to compare.
Map<String, Object?> factsOf(LearnerState state) => {
  for (final MapEntry(key: competency, value: belief)
      in state.competencies.entries)
    'competency ${competency.id}': (
      belief.mean,
      belief.variance,
      belief.updatedAt,
      belief.lastEvidenceAt,
    ),
  for (final MapEntry(key: id, value: memory) in state.materialMemory.entries)
    'memory $id': (
      memory.logCurrentHalfLife,
      memory.currentHalfLifeUncertainty,
      memory.logConsolidatedHalfLife,
      memory.consolidatedLogHalfLifeVariance,
      memory.logitColdStart,
      memory.coldStartUncertainty,
      memory.memoryAnchorAt,
      memory.factualLastRetrievalAt,
      memory.establishedIndependence,
      memory.establishedIndependenceAt,
      memory.lastRetrievalAttemptAt,
    ),
  for (final MapEntry(key: context, value: execution)
      in state.materialExecution.entries)
    'execution $context': (
      execution.residualMean,
      execution.residualVariance,
      execution.updatedAt,
      execution.lastEvidenceAt,
      _written(execution.demonstratedTempoByOctaves),
      execution.pacedTempoBpm,
      _written(execution.coordinationReadyTempoByOctaves),
    ),
};

/// [tempos] as text in span order, which a record compares by value.
String _written(Map<int, double> tempos) =>
    '${[for (final span in tempos.keys.toList()..sort()) (span, tempos[span])]}';

void expectFinite(double value, String what) =>
    expect(value.isFinite, isTrue, reason: '$what is $value');

/// Every number in [state] finite, every variance positive, and nothing
/// stamped after [at].
void expectSane(LearnerState state, DateTime at) {
  void notAfter(DateTime? time, String what) {
    if (time != null) expect(time.isAfter(at), isFalse, reason: what);
  }

  for (final MapEntry(key: competency, value: belief)
      in state.competencies.entries) {
    expectFinite(belief.mean, '${competency.id} mean');
    expect(belief.variance > 0 && belief.variance.isFinite, isTrue);
    notAfter(belief.updatedAt, '${competency.id} update');
    notAfter(belief.lastEvidenceAt, '${competency.id} evidence');
  }
  for (final memory in state.materialMemory.values) {
    for (final value in [
      memory.logCurrentHalfLife,
      memory.currentHalfLifeUncertainty,
      memory.logConsolidatedHalfLife,
      memory.consolidatedLogHalfLifeVariance,
      memory.logitColdStart,
      memory.coldStartUncertainty,
    ]) {
      expectFinite(value, 'memory ${memory.materialId}');
    }
    for (final time in [
      memory.memoryAnchorAt,
      memory.factualLastRetrievalAt,
      memory.establishedIndependenceAt,
      memory.lastRetrievalAttemptAt,
    ]) {
      notAfter(time, 'memory ${memory.materialId}');
    }
  }
  for (final execution in state.materialExecution.values) {
    expectFinite(execution.residualMean, 'residual');
    expect(
      execution.residualVariance > 0 && execution.residualVariance.isFinite,
      isTrue,
    );
    for (final tempo in [
      ...execution.demonstratedTempoByOctaves.values,
      ...execution.coordinationReadyTempoByOctaves.values,
      execution.pacedTempoBpm,
    ]) {
      expect(tempo.isFinite && tempo >= 0, isTrue, reason: 'tempo $tempo');
    }
    notAfter(execution.updatedAt, 'execution update');
    notAfter(execution.lastEvidenceAt, 'execution evidence');
  }
}

/// Played through, and played rather than endured: what the frontier is
/// earned by, read off the outcome itself.
bool managed(Outcome outcome) =>
    outcome.completed &&
    outcome.motorScore != null &&
    outcome.motorScore! >=
        model.params.materialExecution.demonstratedMotorScore;

bool notBefore(DateTime? after, DateTime? before) =>
    before == null || (after != null && !after.isBefore(before));

/// What [state] was before an update, and what one attempt may change of it.
void expectUpdateHeld(
  LearnerState before,
  LearnerState after,
  Exercise exercise,
  Outcome outcome,
  DateTime at,
  Reached<String> reached,
) {
  final context = executionContextOf(exercise);
  final octaves = exercise.conditions.octaves;
  for (final MapEntry(key: competency, value: was)
      in before.competencies.entries) {
    final now = after.competencies[competency]!;
    expect(notBefore(now.lastEvidenceAt, was.lastEvidenceAt), isTrue);
    expect(notBefore(now.updatedAt, was.updatedAt), isTrue);
    final moved = now.mean != was.mean || now.variance != was.variance;
    if (!moved) continue;
    expect(outcome.started, isTrue, reason: 'nothing began, ${competency.id}');
    if (coordinationCompetencies.contains(competency)) {
      expect(outcome.coordination, isNotNull, reason: competency.id);
    } else if (!competency.isTopology) {
      expect(outcome.motorScore, isNotNull, reason: competency.id);
    }
  }

  for (final MapEntry(key: id, value: was) in before.materialMemory.entries) {
    final now = after.materialMemory[id]!;
    expect(
      notBefore(now.factualLastRetrievalAt, was.factualLastRetrievalAt),
      isTrue,
    );
    expect(
      notBefore(now.lastRetrievalAttemptAt, was.lastRetrievalAttemptAt),
      isTrue,
    );
  }

  for (final MapEntry(key: where, value: now)
      in after.materialExecution.entries) {
    final was = before.materialExecution[where];
    final ours = where == context;
    for (final (name, maxima, earlier) in [
      (
        'frontier',
        now.demonstratedTempoByOctaves,
        was?.demonstratedTempoByOctaves ?? const <int, double>{},
      ),
      (
        'hands-together readiness',
        now.coordinationReadyTempoByOctaves,
        was?.coordinationReadyTempoByOctaves ?? const <int, double>{},
      ),
    ]) {
      for (final MapEntry(key: span, value: tempo) in maxima.entries) {
        final prior = earlier[span];
        if (prior == tempo) continue;
        expect(prior == null || tempo > prior, isTrue, reason: '$name fell');
        expect(
          ours && span == octaves,
          isTrue,
          reason: '$name moved elsewhere',
        );
        if (name == 'frontier') {
          reached.add('frontier moved');
          expect(managed(outcome), isTrue);
          expect(tempo, exercise.conditions.tempoBpm);
        } else {
          reached.add('readiness moved');
          expect(outcome.completed, isTrue);
          expect(
            outcome.pitchIntegrity,
            greaterThanOrEqualTo(
              model.params.materialExecution.handsTogetherPitchIntegrity,
            ),
          );
          expect(
            tempo,
            exercise.conditions.tempoBpm * outcome.measuredTempoRatio!,
          );
        }
      }
      expect(earlier.keys.toSet().difference(maxima.keys.toSet()), isEmpty);
    }
    if (now.pacedTempoBpm != (was?.pacedTempoBpm ?? 0)) {
      reached.add('pace moved');
      expect(now.pacedTempoBpm, greaterThan(was?.pacedTempoBpm ?? 0));
      expect(ours && managed(outcome), isTrue);
      expect(outcome.chosenTempoRatio, isNotNull);
    }
    if (was != null) {
      expect(notBefore(now.lastEvidenceAt, was.lastEvidenceAt), isTrue);
      if (now.residualMean != was.residualMean) {
        expect(
          outcome.motorScore,
          isNotNull,
          reason: 'residual from no timing',
        );
      }
    }
  }

  final prediction = model.predict(after, exercise, at: at);
  for (final p in [
    prediction.independentRetrievalP,
    prediction.materialAvailableP,
    prediction.executionP,
    prediction.coordinationP,
    prediction.topologyP,
    prediction.overallP,
  ]) {
    expect(p.isFinite && p >= 0 && p <= 1, isTrue, reason: 'probability $p');
  }
}

/// Propagation ages what is known and creates none of it: uncertainty only
/// grows, a residual only fades toward nothing, and memory is left alone.
void expectPropagationHeld(LearnerState before, LearnerState after) {
  for (final MapEntry(key: competency, value: was)
      in before.competencies.entries) {
    final now = after.competencies[competency]!;
    expect(now.lastEvidenceAt, was.lastEvidenceAt);
    expect(now.mean, was.mean);
    expect(now.variance, greaterThanOrEqualTo(was.variance));
  }
  final memory = factsOf(
    after,
  ).entries.where((e) => e.key.startsWith('memory'));
  expect(
    Map.fromEntries(memory),
    Map.fromEntries(
      factsOf(before).entries.where((e) => e.key.startsWith('memory')),
    ),
  );
  for (final MapEntry(key: where, value: was)
      in before.materialExecution.entries) {
    final now = after.materialExecution[where]!;
    expect(now.lastEvidenceAt, was.lastEvidenceAt);
    expect(now.demonstratedTempoByOctaves, was.demonstratedTempoByOctaves);
    expect(
      now.coordinationReadyTempoByOctaves,
      was.coordinationReadyTempoByOctaves,
    );
    expect(now.pacedTempoBpm, was.pacedTempoBpm);
    expect(now.residualMean.abs(), lessThanOrEqualTo(was.residualMean.abs()));
    expect(now.residualMean * was.residualMean, greaterThanOrEqualTo(0));
    expect(now.residualVariance, greaterThanOrEqualTo(was.residualVariance));
  }
  expect(
    after.materialMemory.keys.toSet(),
    before.materialMemory.keys.toSet(),
    reason: 'propagation meets no new material',
  );
}

/// [steps] applied to a learner placed at [tier], or a cold one, checking
/// every propagation and every update on the way.
Map<String, Object?> practise(
  PlacementTier? tier,
  List<Exercise> exercises,
  List<Step> steps,
  Reached<String> reached,
) {
  final state = tier == null
      ? model.newState(at: start)
      : model.placementState(tier, at: start);
  var at = start;
  for (final (which, minutes, played) in steps) {
    at = at.add(Duration(minutes: minutes));
    final exercise = exercises[which % exercises.length];
    final outcome = outcomeOf(exercise, played);

    final unpropagated = state.copy();
    model.propagate(state, at);
    expectPropagationHeld(unpropagated, state);
    expectSane(state, at);

    final before = state.copy();
    try {
      model.applyOutcome(
        state: state,
        exercise: exercise,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        prediction: model.predict(state, exercise, at: at),
        at: at,
      );
    } on ArgumentError {
      reached.add('refused');
      expect(factsOf(state), factsOf(before), reason: 'refused, unchanged');
      continue;
    }
    reached.add('applied');
    expectSane(state, at);
    expectUpdateHeld(before, state, exercise, outcome, at, reached);
  }
  return factsOf(state);
}

void main() {
  property('every update moves only what its attempt established', () {
    final reached = Reached({
      'applied',
      'frontier moved',
      'readiness moved',
      'pace moved',
    });
    forAll(
      combine3(
        optional(choiceOf(PlacementTier.values)),
        list(anyExercise, minLength: 1, maxLength: 3),
        list(anyStep, minLength: 1, maxLength: 12),
      ),
      seed: propertySeed,
      maxExamples: propertyBudget(200),
      onFalsify: reached.falsified,
      tearDownAll: reached.check,
      failingOnErrors<(PlacementTier?, List<Exercise>, List<Step>)>((value) {
        final (tier, exercises, steps) = value;
        final facts = practise(tier, exercises, steps, reached);
        expect(
          practise(tier, exercises, steps, reached),
          facts,
          reason: 'the same history reaches the same state',
        );
      }),
    );
  });
}
