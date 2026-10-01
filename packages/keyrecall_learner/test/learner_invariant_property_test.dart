import 'dart:math' as math;

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
    // The envelope the state documents: 0 < current <= consolidated <= max.
    expect(
      memory.logCurrentHalfLife,
      lessThanOrEqualTo(memory.logConsolidatedHalfLife),
      reason: 'current durability above what is held in reserve',
    );
    expect(
      memory.logConsolidatedHalfLife,
      lessThanOrEqualTo(
        math.log(model.params.materialMemory.maxMemoryHalfLifeDays) + 1e-12,
      ),
    );
    for (final (name, spread) in [
      ('current uncertainty', memory.currentHalfLifeUncertainty),
      ('cold-start uncertainty', memory.coldStartUncertainty),
      ('consolidation variance', memory.consolidatedLogHalfLifeVariance),
    ]) {
      expect(spread, greaterThan(0), reason: name);
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
  EvidenceWeights weights,
  DateTime at,
  Reached<String> reached,
) {
  final context = executionContextOf(exercise);
  final octaves = exercise.conditions.octaves;
  final materialId = exercise.material.materialId;

  // Evidence lands where the attempt was and nowhere else.
  final was = factsOf(before);
  final now = factsOf(after);
  for (final key in {...was.keys, ...now.keys}) {
    if (key == 'memory $materialId' || key == 'execution $context') continue;
    if (key.startsWith('competency')) continue;
    expect(now[key], was[key], reason: '$key moved for $exercise');
  }
  if (!outcome.retrieval.isTested) {
    final memoryBefore = before.materialMemory[materialId];
    final memoryAfter = after.materialMemory[materialId];
    expect(
      memoryAfter?.factualLastRetrievalAt,
      memoryBefore?.factualLastRetrievalAt,
      reason: 'no retrieval was tested',
    );
    expect(
      memoryAfter?.lastRetrievalAttemptAt,
      memoryBefore?.lastRetrievalAttemptAt,
      reason: 'no retrieval was attempted',
    );
  }
  for (final MapEntry(key: competency, value: was)
      in before.competencies.entries) {
    final now = after.competencies[competency]!;
    expect(notBefore(now.lastEvidenceAt, was.lastEvidenceAt), isTrue);
    expect(notBefore(now.updatedAt, was.updatedAt), isTrue);
    final moved =
        now.mean != was.mean ||
        now.variance != was.variance ||
        now.lastEvidenceAt != was.lastEvidenceAt;
    if (!moved) continue;
    expect(outcome.started, isTrue, reason: 'nothing began, ${competency.id}');
    expect(
      weights[competency],
      greaterThan(0),
      reason: '${competency.id} moved without the attempt crediting it',
    );
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
      if (now.residualMean != was.residualMean ||
          now.lastEvidenceAt != was.lastEvidenceAt) {
        expect(
          outcome.motorScore,
          isNotNull,
          reason: 'residual from no timing',
        );
        expect(weights.materialExecution, greaterThan(0));
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
///
/// Every step is valid practice, so every one has to be applied.
LearnerState practise(
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
    final weights = evidenceWeightsFor(exercise, outcome);

    final unpropagated = state.copy();
    model.propagate(state, at);
    expectPropagationHeld(unpropagated, state);
    expectSane(state, at);

    final before = state.copy();
    model.applyOutcome(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: weights,
      prediction: model.predict(state, exercise, at: at),
      at: at,
    );
    reached.add('applied');
    expectSane(state, at);
    expectUpdateHeld(before, state, exercise, outcome, weights, at, reached);
  }
  return state;
}

/// One rule of a valid update, broken.
enum Breach {
  misaligned,
  retrievalAgainstRung,
  neverBeganYetFinished,
  memoryWithoutRetrieval,
  executionWithoutTiming,
  unboundedTempo,
}

/// [outcome] with some of its fields replaced.
Outcome reshaped(
  Outcome outcome, {
  bool? started,
  FactualRetrieval? retrieval,
  bool untimed = false,
  double? achievedTempoRatio,
}) => Outcome(
  started: started ?? outcome.started,
  retrieval: retrieval ?? outcome.retrieval,
  completed: outcome.completed,
  materialRetrieval: outcome.materialRetrieval,
  pitchIntegrity: outcome.pitchIntegrity,
  continuity: untimed ? null : outcome.continuity,
  temporalStability: untimed ? null : outcome.temporalStability,
  achievedTempoRatio: achievedTempoRatio ?? outcome.achievedTempoRatio,
  topologyAccuracy: outcome.topologyAccuracy,
  coordination: outcome.coordination,
  pulseMaintenance: outcome.pulseMaintenance,
);

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
        final facts = factsOf(practise(tier, exercises, steps, reached));
        expect(
          factsOf(practise(tier, exercises, steps, reached)),
          facts,
          reason: 'the same history reaches the same state',
        );
      }),
    );
  });

  property('an update that breaks a rule is refused and writes nothing', () {
    final ignored = Reached<String>({});
    forAll(
      combine4(
        list(anyExercise, minLength: 1, maxLength: 3),
        list(anyStep, maxLength: 6),
        combine2(anyExercise, anyPlayed),
        choiceOf(Breach.values),
      ),
      seed: propertySeed,
      maxExamples: propertyBudget(200),
      failingOnErrors<
        (List<Exercise>, List<Step>, (Exercise, Played), Breach)
      >((value) {
        final (exercises, steps, (planned, played), breach) = value;
        final state = practise(null, exercises, steps, ignored);
        final at = state.lastPropagatedAt.add(const Duration(hours: 1));
        model.propagate(state, at);

        // The rung each breach needs, so it breaks its own rule and no
        // other.
        final exercise = switch (breach) {
          Breach.memoryWithoutRetrieval => planned.withGuidance(
            GuidanceContext.continuouslyCued,
          ),
          Breach.neverBeganYetFinished => planned.withGuidance(
            GuidanceContext.unguided,
          ),
          _ => planned,
        };
        final ((_, _, retrieval), scores, (continuity, stability, _), _, _) =
            played;
        // Begun, finished, timed, and at a pace: an attempt every rule
        // admits until one is broken.
        final valid = outcomeOf(exercise, (
          (true, true, retrieval),
          scores,
          (continuity ?? 0.5, stability ?? 0.5, null),
          1.0,
          false,
        ));
        final weights = evidenceWeightsFor(exercise, valid);
        void apply(Outcome outcome, EvidenceWeights credited, DateTime when) =>
            model.applyOutcome(
              state: state,
              exercise: exercise,
              outcome: outcome,
              weights: credited,
              prediction: model.predict(state, exercise, at: at),
              at: when,
            );

        final unbounded = reshaped(valid, achievedTempoRatio: double.maxFinite);
        final (outcome, credited, attemptAt) = switch (breach) {
          Breach.misaligned => (
            valid,
            weights,
            at.subtract(const Duration(minutes: 1)),
          ),
          Breach.retrievalAgainstRung => (
            reshaped(
              valid,
              retrieval: valid.retrieval.isTested
                  ? FactualRetrieval.notTested
                  : FactualRetrieval.succeeded,
            ),
            weights,
            at,
          ),
          Breach.neverBeganYetFinished => (
            reshaped(valid, started: false, retrieval: FactualRetrieval.failed),
            EvidenceWeights(
              competencies: const {},
              materialExecution: 0,
              materialMemory: weights.materialMemory,
            ),
            at,
          ),
          Breach.memoryWithoutRetrieval => (
            valid,
            EvidenceWeights(
              competencies: weights.competencies,
              materialExecution: weights.materialExecution,
              materialMemory: 0.5,
            ),
            at,
          ),
          Breach.executionWithoutTiming => (
            reshaped(valid, untimed: true),
            EvidenceWeights(
              competencies: {
                for (final MapEntry(:key, :value)
                    in weights.competencies.entries)
                  if (key.isTopology) key: value,
              },
              materialExecution: 0.5,
              materialMemory: weights.materialMemory,
            ),
            at,
          ),
          Breach.unboundedTempo => (
            unbounded,
            evidenceWeightsFor(exercise, unbounded),
            at,
          ),
        };

        final facts = factsOf(state);
        expect(
          () => apply(outcome, credited, attemptAt),
          throwsArgumentError,
          reason: breach.name,
        );
        expect(factsOf(state), facts, reason: 'refused, unchanged');

        // The same attempt with the rule kept is accepted.
        apply(valid, weights, at);
      }),
    );
  });
}
