import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// Competing introductions take turns between families, and nothing else
/// does.
void main() {
  final scale = allScales.firstWhere(
    (material) => material.materialId == 'C_MAJOR',
  );
  final arpeggio = allRootPositionArpeggios.firstWhere(
    (material) => material.materialId == 'C_MAJOR_ROOT_ARPEGGIO',
  );
  final candidates = generateCandidates(instrument, [scale, arpeggio]);

  List<CandidateTrace> selectableFor(LearnerState state) => pipeline.selectable(
    pipeline.evaluate(
      state: state,
      session: SessionState(),
      candidates: candidates,
      at: t0,
    ),
    SessionState(),
    state: state,
    at: t0,
  );

  String familyOf(CandidateTrace? trace) => trace!.exercise.material.familyId;

  test('new material from the family introduced longest ago goes first', () {
    final state = stateAt(PlacementTier.beginner);
    final selectable = selectableFor(state);
    final ranked = pipeline.selectBest(selectable);

    expect(
      familyOf(ranked),
      scale.familyId,
      reason: 'its first shape can be timed, so it claims more information',
    );
    expect(ranked!.challengeBypass, ChallengeBypass.newMaterial);

    final chosen = pipeline.introductionWithin(
      selectable,
      ranked,
      state: state,
      history: AttemptHistory(lastIntroductionByFamily: {scale.familyId: 0}),
    );
    expect(familyOf(chosen), arpeggio.familyId);
    expect(chosen!.challengeBypass, ChallengeBypass.newMaterial);
    expect(
      identical(
        chosen,
        pipeline.selectBest([
          for (final trace in selectable)
            if (trace.exercise.material == arpeggio &&
                trace.challengeBypass == ChallengeBypass.newMaterial)
              trace,
        ]),
      ),
      isTrue,
      reason: 'ranking still decides within the family',
    );

    expect(
      pipeline.introductionWithin(
        selectable,
        ranked,
        state: state,
        history: AttemptHistory(
          lastIntroductionByFamily: {scale.familyId: 0, arpeggio.familyId: 1},
        ),
      ),
      same(ranked),
      reason: 'the family ranking chose is already the one waiting longest',
    );
  });

  test('anything ranking chose over new material is left alone', () {
    final state = stateAt(PlacementTier.beginner);
    seedAllMaterials(state);
    final selectable = selectableFor(state);
    final established = pipeline.selectBest([
      for (final trace in selectable)
        if (trace.exercise.material == scale) trace,
    ]);

    expect(
      widensCatalog(established!, state),
      isFalse,
      reason: 'the scale is already met, so this is not an introduction',
    );
    expect(
      selectable.any(
        (trace) =>
            trace.exercise.material == arpeggio && widensCatalog(trace, state),
      ),
      isTrue,
      reason: 'while the arpeggio is still waiting to be introduced',
    );
    expect(
      pipeline.introductionWithin(
        selectable,
        established,
        state: state,
        history: AttemptHistory(lastIntroductionByFamily: {scale.familyId: 0}),
      ),
      same(established),
    );
  });

  group('a first meeting too short to time', () {
    Exercise arpeggioIn(ExerciseDirection direction, {int octaves = 1}) =>
        Exercise.linear(
          material: arpeggio,
          hands: HandConfiguration.right,
          octaves: octaves,
          direction: direction,
          tempoBpm: 60,
          guidance: GuidanceContext.notesPreviewedOnly,
        );

    DecisionFacts offering(
      LearnerState state,
      Iterable<Exercise> envelope, {
      Set<Exercise>? started,
    }) => DecisionFacts(
      state,
      startedExercises: started,
      offeredUpAndDown: {
        for (final exercise in envelope)
          if (exercise.conditions.direction == ExerciseDirection.upDown)
            upAndDownShapeOf(exercise),
      },
    );

    test('is ranked as the up and down it opens', () {
      final state = stateAt(PlacementTier.beginner);
      final short = arpeggioIn(ExerciseDirection.up);
      final ranked = pipeline.rankedAs(
        state,
        short,
        facts: offering(state, [short, arpeggioIn(ExerciseDirection.upDown)]),
      );

      expect(
        ranked.hasSameRealizationAs(arpeggioIn(ExerciseDirection.upDown)),
        isTrue,
      );
      expect(ranked.guidance, GuidanceContext.notesPreviewedOnly);
      expect(
        information(state, ranked, learnerParams),
        greaterThan(information(state, short, learnerParams)),
        reason: 'what it opens can be timed, so it carries motor uncertainty',
      );
    });

    test('borrows nothing from a follow-up the slot does not offer', () {
      final state = stateAt(PlacementTier.beginner);
      final short = arpeggioIn(ExerciseDirection.up);

      expect(
        pipeline.rankedAs(
          state,
          short,
          facts: offering(state, [
            short,
            arpeggioIn(ExerciseDirection.upDown, octaves: 2),
          ]),
        ),
        same(short),
        reason: 'up and down at another span is not what this meeting opens',
      );
      expect(pipeline.rankedAs(state, short), same(short));
    });

    test('is ranked as itself once the hand has met the material', () {
      final state = stateAt(PlacementTier.beginner);
      final short = arpeggioIn(ExerciseDirection.up);

      expect(
        pipeline.rankedAs(
          state,
          short,
          facts: offering(
            state,
            [short, arpeggioIn(ExerciseDirection.upDown)],
            started: {short},
          ),
        ),
        same(short),
        reason: 'the claim is spent by the meeting, so it cannot recur',
      );
    });

    test('and anything that can be timed is ranked as itself', () {
      final state = stateAt(PlacementTier.beginner);
      final envelope = [
        arpeggioIn(ExerciseDirection.upDown),
        arpeggioIn(ExerciseDirection.up, octaves: 2),
      ];
      for (final exercise in envelope) {
        expect(
          pipeline.rankedAs(state, exercise, facts: offering(state, envelope)),
          same(exercise),
        );
      }
    });
  });
}
