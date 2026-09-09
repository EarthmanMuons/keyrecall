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
    direction: ExerciseDirection.up,
    tempoBpm: tempoBpm,
    guidance: guidance,
  );

  final floor = cued();
  AcquisitionFloor entriesFor(Exercise parent) =>
      scaleAcquisitionFloor([parent]);
  final entries = scaleAcquisitionFloor([
    floor,
    cued(hands: HandConfiguration.left),
  ]);
  final attemptedParents = {floor, cued(hands: HandConfiguration.left)};

  bool needsAcquisition(LearnerState state, Exercise exercise) =>
      pipeline.needsAcquisition(
        state,
        exercise,
        floor: entries,
        attemptedParents: state.materialExecution.isEmpty
            ? {}
            : attemptedParents,
      );

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
      expect(needsAcquisition(metButUnproven(), floor), isTrue);
    });

    test('does not hold for a first exposure nobody has tried', () {
      // Evidence has never arrived, so there is nothing to have learned
      // nothing from. This is the case the forgiving floor exists for, and
      // acquisition would be answering a question the ordinary path has not
      // yet asked.
      expect(needsAcquisition(untouched(), floor), isFalse);
    });

    test('stops the moment a frontier exists', () {
      expect(needsAcquisition(proven(), floor), isFalse);
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

      expect(needsAcquisition(state, floor), isFalse);
      expect(
        needsAcquisition(state, cued(hands: HandConfiguration.left)),
        isTrue,
      );
    });

    test('asks only of the floor itself', () {
      // Two octaves and an unguided rung are not the gentlest ordinary
      // question, so failing to demonstrate them is not a reason to relax the
      // task. The ordinary path still has somewhere to go.
      final state = metButUnproven();

      expect(needsAcquisition(state, cued(octaves: 2)), isFalse);
      expect(
        needsAcquisition(state, cued(guidance: GuidanceContext.unguided)),
        isFalse,
      );
    });
  });

  group('entry boundaries', () {
    test('context evidence does not establish an exact floor exposure', () {
      expect(
        pipeline.needsAcquisition(
          metButUnproven(),
          floor,
          floor: entries,
          attemptedParents: {
            cued(octaves: 2),
            cued(guidance: GuidanceContext.notesPreviewedOnly),
          },
        ),
        isFalse,
      );
    });

    test('only the declared direction and tempo can enter acquisition', () {
      final upDown = Exercise.linear(
        material: material,
        hands: HandConfiguration.right,
        tempoBpm: 60,
        guidance: GuidanceContext.continuouslyCued,
      );
      for (final other in [upDown, floor.atTempo(120)]) {
        expect(
          pipeline.needsAcquisition(
            metButUnproven(),
            other,
            floor: entries,
            attemptedParents: {other},
          ),
          isFalse,
        );
      }
    });

    test('short arpeggios stay outside the automatic acquisition loop', () {
      final parent = Exercise.linear(
        material: ArpeggioMaterial('C', ArpeggioQuality.major),
        hands: HandConfiguration.right,
        direction: ExerciseDirection.up,
        tempoBpm: 60,
        guidance: GuidanceContext.continuouslyCued,
      );
      final declared = AcquisitionFloor([
        AcquisitionFloorEntry(
          requirementId: parent.material.materialId,
          exercise: parent,
        ),
      ]);
      expect(
        pipeline.needsAcquisition(
          metButUnproven(),
          parent,
          floor: declared,
          attemptedParents: {parent},
        ),
        isFalse,
      );
    });

    test('a blocked safety gate cannot offer acquisition', () {
      final bounded = SchedulerPipeline(learner: learner, config: boundedTo(1));
      final result = bounded.decide(
        state: metButUnproven(),
        session: SessionState(attemptsThisSession: 1),
        candidates: [floor],
        at: t0,
        acquisition: const AcquisitionProgress.empty(),
        acquisitionFloor: entriesFor(floor),
        attemptedAcquisitionParents: {floor},
      );
      expect(result, isA<SelectionBlocked>());
      expect(result.traces.single.safety.isAllowed, isFalse);
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
      acquisitionFloor: entriesFor(floor),
      attemptedAcquisitionParents: attemptedParents,
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

    test('stops while the parent is owed a probe', () {
      final progress = const AcquisitionProgress.empty().recording(
        parent: floor,
        completed: true,
        earnedProbe: true,
        at: t0,
      );

      // What it is owed now is the ordinary question, not more supported work.
      expect(
        decideWith(metButUnproven(), acquisition: progress),
        isNot(isA<AcquisitionOffered>()),
      );
      expect(progress.probeOwed(floor), isTrue);
    });

    test('resumes for a parent still stuck after its probe was asked', () {
      // The cycle, not a latch. The probe was asked and the context still has
      // no frontier, so the gentlest ordinary question is still going
      // unanswered and supported work is again the thing to offer.
      final progress = const AcquisitionProgress.empty()
          .recording(parent: floor, completed: true, earnedProbe: true, at: t0)
          .serving(parent: floor, at: t0.add(const Duration(minutes: 5)));

      expect(progress.earnsParentProbe(floor), isTrue);
      expect(
        decideWith(metButUnproven(), acquisition: progress),
        isA<AcquisitionOffered>(),
      );
    });

    test('does not need the floor to have won the slot', () {
      // The rule is about the family's gentlest ordinary realization. Ordinary
      // ranking may prefer a more independent rung of the same material
      // forever, and a question about the floor answerable only when nothing
      // else was worth doing is a question that never gets asked.
      final state = metButUnproven();
      final traces = pipeline.evaluate(
        state: state,
        session: SessionState(),
        candidates: [
          floor,
          cued(guidance: GuidanceContext.notesPreviewedOnly),
        ],
        at: t0,
      );

      final offered = pipeline.acquisitionFor(
        state: state,
        progress: const AcquisitionProgress.empty(),
        floor: entries,
        attemptedParents: attemptedParents,
        traces: traces,
      );

      expect(offered?.task.parent, floor);
    });
  });

  group('serving an owed probe', () {
    /// Acquisition history that has earned a probe of the floor and not been
    /// asked one.
    AcquisitionProgress owing() => const AcquisitionProgress.empty().recording(
      parent: floor,
      completed: true,
      earnedProbe: true,
      at: t0,
    );

    SelectionResult decideWith(
      LearnerState state,
      AcquisitionProgress progress, {
      List<Exercise>? candidates,
    }) => pipeline.decide(
      state: state,
      session: SessionState(),
      candidates: candidates ?? [floor],
      at: t0,
      acquisition: progress,
      acquisitionFloor: entriesFor(floor),
      attemptedAcquisitionParents: attemptedParents,
    );

    test('presents the unchanged parent through its own bypass', () {
      final result = decideWith(metButUnproven(), owing());

      expect(result, isA<CandidateSelected>());
      final chosen = (result as CandidateSelected).candidate;
      expect(chosen.exercise, floor);
      expect(chosen.challengeBypass, ChallengeBypass.acquisitionProbe);
      expect(result.diagnostics, contains('probe_served=true'));
    });

    test('is not offered acquisition instead', () {
      // The obligation outranks the thing that created it.
      expect(
        decideWith(metButUnproven(), owing()),
        isNot(isA<AcquisitionOffered>()),
      );
    });

    test('leaves the obligation alone when the parent is out of scope', () {
      // Dormant: nothing found, nothing consumed, nothing written.
      final progress = owing();
      final other = Exercise.linear(
        material: materials.last,
        hands: HandConfiguration.right,
        octaves: 1,
        tempoBpm: 60,
        guidance: GuidanceContext.continuouslyCued,
      );

      final result = decideWith(
        metButUnproven(),
        progress,
        candidates: [other],
      );

      expect(result, isNot(isA<AcquisitionOffered>()));
      expect(
        result is CandidateSelected ? result.candidate.exercise : null,
        isNot(floor),
      );
      expect(progress.probeOwed(floor), isTrue);
    });

    test('lapses once ordinary evidence has answered the question', () {
      // A frontier at the parent's own span and tempo answers what the probe
      // would have asked, so presenting it would offer work already exceeded.
      final state = metButUnproven();
      state
              .materialExecutionFor(
                executionContextOf(floor),
                t0,
                learnerParams,
                familyId: material.familyId,
              )
              .demonstratedTempoByOctaves[1] =
          floor.conditions.tempoBpm;

      expect(pipeline.probeWorthServing(state, owing(), floor), isFalse);
      expect(owing().probeOwed(floor), isTrue);
    });

    test('does not lapse on a frontier below the parent tempo', () {
      // A slower frontier is not an answer to this parent's question.
      final state = metButUnproven();
      state
              .materialExecutionFor(
                executionContextOf(floor),
                t0,
                learnerParams,
                familyId: material.familyId,
              )
              .demonstratedTempoByOctaves[1] =
          floor.conditions.tempoBpm - 20;

      expect(pipeline.probeWorthServing(state, owing(), floor), isTrue);
    });

    test('stops being owed once it has been served', () {
      final served = owing().serving(
        parent: floor,
        at: t0.add(const Duration(minutes: 1)),
      );

      expect(
        pipeline.probeWorthServing(metButUnproven(), served, floor),
        isFalse,
      );
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
