import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

void main() {
  final material = materials.first;

  Exercise cued({
    HandConfiguration hands = HandConfiguration.right,
    int octaves = 1,
    GuidanceContext guidance = GuidanceContext.continuouslyCued,
    double tempoBpm = 60,
  }) => Exercise.linear(
    material: material,
    hands: hands,
    octaves: octaves,
    tempoBpm: tempoBpm,
    guidance: guidance,
  );

  final floor = cued();

  /// A learner who has never been asked for this material at all.
  LearnerState untouched() => stateAt(PlacementTier.beginner);

  /// A learner who has met this material and demonstrated nothing in it.
  LearnerState metButUnproven() {
    final state = untouched();
    state.materialMemoryFor(material.materialId, learnerParams)
      ..factualLastRetrievalAt = t0
      ..lastRetrievalAttemptAt = t0;
    state
            .materialExecutionFor(
              executionContextOf(floor),
              t0,
              learnerParams,
              familyId: material.familyId,
            )
            .lastEvidenceAt =
        t0;
    return state;
  }

  /// The same learner, with a frontier at one octave.
  LearnerState proven() {
    final state = metButUnproven();
    state
            .materialExecutionFor(
              executionContextOf(floor),
              t0,
              learnerParams,
              familyId: material.familyId,
            )
            .demonstratedTempoByOctaves[1] =
        60;
    return state;
  }

  group('the entry rule', () {
    test('holds when the floor has taught the model nothing', () {
      expect(pipeline.needsAcquisition(metButUnproven(), floor), isTrue);
    });

    test('does not hold for a first exposure nobody has tried', () {
      // Evidence has never arrived, so there is nothing to have learned
      // nothing from. This is the case the forgiving floor exists for, and
      // acquisition would be answering a question the ordinary path has not
      // yet asked.
      expect(pipeline.needsAcquisition(untouched(), floor), isFalse);
    });

    test('stops the moment a frontier exists', () {
      expect(pipeline.needsAcquisition(proven(), floor), isFalse);
    });

    test('reads the same scope execution progression reads', () {
      // A frontier in the right hand says nothing about the left, so the left
      // is still acquiring. Widening the scope here would say a success
      // somewhere is evidence that somewhere else is ready.
      final state = proven();
      state
              .materialExecutionFor(
                executionContextOf(cued(hands: HandConfiguration.left)),
                t0,
                learnerParams,
                familyId: material.familyId,
              )
              .lastEvidenceAt =
          t0;

      expect(pipeline.needsAcquisition(state, floor), isFalse);
      expect(
        pipeline.needsAcquisition(state, cued(hands: HandConfiguration.left)),
        isTrue,
      );
    });

    test('asks only of the floor itself', () {
      // Two octaves and an unguided rung are not the gentlest ordinary
      // question, so failing to demonstrate them is not a reason to relax the
      // task. The ordinary path still has somewhere to go.
      final state = metButUnproven();

      expect(pipeline.needsAcquisition(state, cued(octaves: 2)), isFalse);
      expect(
        pipeline.needsAcquisition(
          state,
          cued(guidance: GuidanceContext.unguided),
        ),
        isFalse,
      );
    });
  });

  group('the offer', () {
    SelectionResult decideWith(
      LearnerState state, {
      AcquisitionProgress? acquisition,
      List<Exercise>? candidates,
    }) => pipeline.decide(
      state: state,
      session: SessionState(),
      candidates: candidates ?? [floor],
      at: t0,
      acquisition: acquisition,
    );

    test('is absent unless the caller asks for it', () {
      // Every existing decision passes no progress and is unchanged by this.
      expect(decideWith(metButUnproven()), isNot(isA<AcquisitionOffered>()));
    });

    test('replaces a stuck floor with the unmetered traversal', () {
      final result = decideWith(
        metButUnproven(),
        acquisition: const AcquisitionProgress.empty(),
      );

      expect(result, isA<AcquisitionOffered>());
      final offered = result as AcquisitionOffered;
      expect(offered.task.parent, floor);
      expect(offered.task.timing, TimingDemand.unmetered);
      expect(offered.stuck?.exercise, floor);
      expect(offered.diagnostics, contains('acquisition_offered=true'));
    });

    test('leaves ordinary work alone', () {
      final result = decideWith(
        proven(),
        acquisition: const AcquisitionProgress.empty(),
      );

      expect(result, isA<CandidateSelected>());
    });

    test('stops once the parent has earned its probe', () {
      final progress = const AcquisitionProgress.empty().recording(
        parent: floor,
        completed: true,
        earnedProbe: true,
        at: t0,
      );

      // What it is owed now is the probe, not more supported work.
      expect(
        decideWith(metButUnproven(), acquisition: progress),
        isNot(isA<AcquisitionOffered>()),
      );
      expect(progress.earnsParentProbe(floor), isTrue);
    });

    test('answers a blocked slot the same way it answers a stuck one', () {
      // A slot that produced no winner at all still reaches the same rule over
      // the same traces, so the blocked case does not acquire an escape hatch
      // with evidence rules of its own.
      final state = metButUnproven();
      final traces = pipeline.evaluate(
        state: state,
        session: SessionState(),
        candidates: [floor],
        at: t0,
      );

      final blocked = pipeline.acquisitionFor(
        state: state,
        progress: const AcquisitionProgress.empty(),
        selected: null,
        traces: traces,
      );
      final stuck = pipeline.acquisitionFor(
        state: state,
        progress: const AcquisitionProgress.empty(),
        selected: traces.single,
        traces: traces,
      );

      expect(blocked?.task, stuck?.task);
      expect(blocked?.task.parent, floor);
    });
  });

  group('what an offer does not do', () {
    test('leaves learner state exactly as it found it', () {
      final state = metButUnproven();
      final context = executionContextOf(floor);
      final before = state.materialExecution[context]!;
      final frontier = {...before.demonstratedTempoByOctaves};
      final residual = before.residualMean;
      final variance = before.residualVariance;

      pipeline.decide(
        state: state,
        session: SessionState(),
        candidates: [floor],
        at: t0,
        acquisition: const AcquisitionProgress.empty(),
      );

      final after = state.materialExecution[context]!;
      expect(after.demonstratedTempoByOctaves, frontier);
      expect(after.residualMean, residual);
      expect(after.residualVariance, variance);
    });
  });
}
