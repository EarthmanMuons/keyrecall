import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// Whether [InformationKey] really names everything [information] reads.
///
/// The cache is only sound while it does, and the failure mode of getting it
/// wrong is silent: a candidate would be handed another candidate's answer and
/// the ranking would be subtly wrong rather than obviously broken. So this
/// asks the question over the whole generated candidate space rather than over
/// a few hand-built examples, and against states of different shapes, because
/// a key can be complete for one learner and incomplete for another.
void main() {
  final candidates = generateCandidates(InstrumentProfile(), allScales);

  /// A learner with memory, frontiers and residuals in place, so the terms
  /// [information] reads are populated rather than all at their priors.
  LearnerState populated() {
    final state = stateAt(PlacementTier.someExperience);
    for (final material in allScales.take(12)) {
      state.materialMemoryFor(material.materialId, learnerParams)
        ..memoryAnchorAt = t0
        ..factualLastRetrievalAt = t0;
      for (final hands in HandConfiguration.values) {
        state.materialExecutionFor(
            (material.materialId, hands, HandMotion.parallel),
            t0,
            learnerParams,
          )
          ..demonstrate(octaves: 1, tempoBpm: 80)
          ..residualVariance = 0.3 + material.materialId.length / 100
          ..lastEvidenceAt = t0;
      }
    }
    return state;
  }

  for (final (name, state) in [
    ('a learner at placement', stateAt(PlacementTier.someExperience)),
    ('a learner with a history', populated()),
  ]) {
    test('equal keys give equal information for $name', () {
      final answers = <InformationKey, double>{};
      final examples = <InformationKey, Exercise>{};

      for (final exercise in candidates) {
        final key = informationKeyFor(exercise);
        final value = information(state, exercise, learnerParams);
        final seen = answers[key];
        if (seen == null) {
          answers[key] = value;
          examples[key] = exercise;
          continue;
        }
        expect(
          value,
          seen,
          reason:
              'these share an information key and disagree, so the key is '
              'missing an input that information reads:\n'
              '  ${examples[key]!.material.materialId} '
              '${examples[key]!.conditions} '
              'guidance ${examples[key]!.guidance.independence}\n'
              '  ${exercise.material.materialId} ${exercise.conditions} '
              'guidance ${exercise.guidance.independence}',
        );
      }

      expect(
        answers.length,
        lessThan(candidates.length),
        reason: 'a key that never collides is not saving any work',
      );
    });
  }

  test('the key separates each input it names', () {
    final material = allScales.first;
    Exercise exercise({
      HandConfiguration hands = HandConfiguration.right,
      HandMotion handMotion = HandMotion.parallel,
      int octaves = 1,
      ExerciseDirection direction = ExerciseDirection.upDown,
      GuidanceContext guidance = GuidanceContext.unguided,
    }) => Exercise.linear(
      material: material,
      hands: hands,
      octaves: octaves,
      direction: direction,
      handMotion: handMotion,
      guidance: guidance,
    );

    final base = informationKeyFor(exercise());

    expect(
      informationKeyFor(exercise(hands: HandConfiguration.left)),
      isNot(base),
    );
    expect(
      informationKeyFor(
        exercise(
          hands: HandConfiguration.together,
          handMotion: HandMotion.contrary,
        ),
      ),
      isNot(informationKeyFor(exercise(hands: HandConfiguration.together))),
      reason: 'the two motions carry separate execution residuals',
    );
    expect(informationKeyFor(exercise(octaves: 2)), isNot(base));
    expect(
      informationKeyFor(exercise(direction: ExerciseDirection.up)),
      isNot(base),
    );
    expect(
      informationKeyFor(exercise(guidance: GuidanceContext.continuouslyCued)),
      isNot(base),
    );
  });

  test('and ignores what information does not read', () {
    final material = allScales.first;
    Exercise atTempo(double tempoBpm) => Exercise.linear(
      material: material,
      hands: HandConfiguration.right,
      octaves: 1,
      tempoBpm: tempoBpm,
    );

    expect(
      informationKeyFor(atTempo(60)),
      informationKeyFor(atTempo(120)),
      reason:
          'tempo reaches information only through the competencies it loads '
          'and the context it keys, and it changes neither',
    );
  });
}
