import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

/// Every consumer of timing evidence agrees with [TimingCapacity] about what
/// each shape in the catalog can establish.
///
/// Measurement decides what a performance did establish; everything else
/// decides in advance what one could. Where those disagree, the scheduler
/// values or waits on evidence that never arrives, so this holds each of them
/// to the contract over the whole catalog, including any family added to it.
void main() {
  const pipeline = SchedulerPipeline(learner: LearnerModel());
  final candidates = generateCandidates(
    InstrumentProfile(),
    allPracticeMaterials,
  );
  final shapes = {
    for (final exercise in candidates)
      (exercise.material.materialId, exercise.conditions.withoutTempo):
          exercise,
  }.values.toList();

  test('the catalog has shapes on both sides of the contract', () {
    final timed = shapes.where(
      (exercise) => TimingCapacity.of(exercise).supportsMotorScore,
    );
    expect(timed, isNotEmpty);
    expect(timed.length, lessThan(shapes.length));
  });

  test('a clean traversal establishes exactly what capacity promises', () {
    for (final exercise in shapes) {
      final realization = realize(exercise);
      var transcript = PerformanceTranscript.empty;
      for (final moment in realization.moments) {
        final atUs = 1000000 + 400000 * moment.position;
        for (final note in moment.notes) {
          transcript = transcript.appending(
            pitch: spellObservedPitch(
              note.midiNote,
              material: exercise.material,
            ),
            timestampMs: atUs ~/ 1000,
            performanceTimeUs: atUs,
          );
        }
      }
      final measurement = measure(
        realization: realization,
        transcript: transcript,
      );
      final capacity = TimingCapacity.of(exercise);
      final where = '${exercise.material.materialId} ${exercise.conditions}';

      expect(measurement.timing.hasPace, capacity.supportsPace, reason: where);
      expect(
        measurement.continuity != null,
        capacity.supportsContinuity,
        reason: where,
      );
      expect(
        measurement.temporalStability != null,
        capacity.supportsSpread,
        reason: where,
      );
      expect(
        outcomeFor(measurement: measurement, exercise: exercise).motorScore !=
            null,
        capacity.supportsMotorScore,
        reason: where,
      );
    }
  });

  test('information credits only motor uncertainty a shape can reduce', () {
    final baseline = learnerAt();
    final uncertain = learnerAt();
    for (final competency in motorCompetencies) {
      uncertain.competency(competency).variance *= 10;
    }
    for (final exercise in shapes) {
      uncertain
              .materialExecutionFor(
                executionContextOf(exercise),
                _t0,
                v1LearnerParams,
                familyId: exercise.material.familyId,
              )
              .residualVariance =
          5.0;
    }

    for (final exercise in candidates) {
      final before = information(baseline, exercise, v1LearnerParams);
      final after = information(uncertain, exercise, v1LearnerParams);
      final where = '${exercise.material.materialId} ${exercise.conditions}';
      if (TimingCapacity.of(exercise).supportsMotorScore) {
        expect(after, greaterThan(before), reason: where);
      } else {
        expect(after, before, reason: where);
      }
    }
  });

  test('no bootstrap shape is one that cannot be timed', () {
    for (final exercise in candidates) {
      if (!pipeline.isBootstrapShape(exercise)) continue;
      expect(
        TimingCapacity.of(exercise).supportsMotorScore,
        isTrue,
        reason: '${exercise.material.materialId} ${exercise.conditions}',
      );
    }
  });

  test('history counts every start and only timed evidence', () {
    for (final exercise in shapes) {
      final capacity = TimingCapacity.of(exercise);
      final outcome = Outcome(
        started: true,
        retrieval: FactualRetrieval.succeeded,
        completed: true,
        materialRetrieval: 1.0,
        pitchIntegrity: 1.0,
        continuity: capacity.supportsContinuity ? 1.0 : null,
        temporalStability: capacity.supportsSpread ? 1.0 : null,
        achievedTempoRatio: 1.0,
        topologyAccuracy: 1.0,
      );
      final history = attemptHistoryOf([
        (
          exercise: exercise,
          outcome: outcome,
          weights: evidenceWeightsFor(exercise, outcome),
        ),
      ]);
      final where = '${exercise.material.materialId} ${exercise.conditions}';

      expect(history.startedExercises, {exercise}, reason: where);
      expect(
        history.executionEvidenceExercises.contains(exercise),
        capacity.supportsMotorScore,
        reason: where,
      );
    }
  });
}

final DateTime _t0 = DateTime.utc(2026);

LearnerState learnerAt() => const LearnerModel().newState(at: _t0);

extension on ExecutionConditions {
  (HandConfiguration, int, ExerciseDirection, HandMotion) get withoutTempo =>
      (hands, octaves, direction, handMotion);
}
