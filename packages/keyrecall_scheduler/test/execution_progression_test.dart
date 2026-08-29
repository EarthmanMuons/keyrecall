import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// Going on from where a learner already is, one axis at a time.
void main() {
  LearnerState learner() => LearnerState(
    competencies: {
      for (final competency in Competency.values)
        competency: CompetencyState(
          competency: competency,
          mean: 0.0,
          variance: 1.0,
          updatedAt: t0,
        ),
    },
  );

  /// Records that [hands] managed [materialId] at [octaves] and [tempoBpm].
  void demonstrate(
    LearnerState state,
    HandConfiguration hands, {
    String materialId = 'C_MAJOR',
    int octaves = 1,
    double tempoBpm = 60,
  }) => state
      .materialExecutionFor((materialId, hands), t0, v1PrototypeLearnerParams)
      .demonstrate(octaves: octaves, tempoBpm: tempoBpm);

  Exercise scale({
    HandConfiguration hands = HandConfiguration.right,
    int octaves = 1,
    double tempoBpm = 60,
  }) => Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: hands,
    octaves: octaves,
    tempoBpm: tempoBpm,
  );

  test('the next rung up at a span already managed is a tempo step', () {
    final state = learner();
    demonstrate(state, HandConfiguration.right, tempoBpm: 60);

    expect(
      executionAdvanceFor(state, scale(tempoBpm: 63)),
      ExecutionAdvance.tempo,
    );
  });

  test('a rung further off than the next is not a step', () {
    final state = learner();
    demonstrate(state, HandConfiguration.right, tempoBpm: 60);

    for (final tempoBpm in [66.0, 80.0, 120.0]) {
      expect(
        executionAdvanceFor(state, scale(tempoBpm: tempoBpm)),
        ExecutionAdvance.none,
        reason: '$tempoBpm',
      );
    }
  });

  test('what has already been managed is not a step either', () {
    final state = learner();
    demonstrate(state, HandConfiguration.right, tempoBpm: 60);

    expect(
      executionAdvanceFor(state, scale(tempoBpm: 60)),
      ExecutionAdvance.none,
    );
  });

  test('one span wider at a tempo the narrower one managed is a span step', () {
    final state = learner();
    demonstrate(state, HandConfiguration.right, octaves: 1, tempoBpm: 72);

    expect(
      executionAdvanceFor(state, scale(octaves: 2, tempoBpm: 72)),
      ExecutionAdvance.span,
    );
  });

  test('wider and faster at once is two steps taken as one', () {
    // The case information gain likes most and the learner is least ready
    // for. Whichever way it went, nobody would know which axis was the
    // problem.
    final state = learner();
    demonstrate(state, HandConfiguration.right, octaves: 1, tempoBpm: 60);

    expect(
      executionAdvanceFor(state, scale(octaves: 2, tempoBpm: 63)),
      ExecutionAdvance.multiple,
    );
    expect(ExecutionAdvance.multiple.isAdjacentStep, isFalse);
  });

  test('hands together enters at the slower of what each hand managed', () {
    final state = learner();
    demonstrate(state, HandConfiguration.right, tempoBpm: 84);
    demonstrate(state, HandConfiguration.left, tempoBpm: 72);

    expect(
      executionAdvanceFor(
        state,
        scale(hands: HandConfiguration.together, tempoBpm: 72),
      ),
      ExecutionAdvance.handsTogether,
      reason:
          'the weaker hand is what starts to matter when they go '
          'together',
    );
    expect(
      executionAdvanceFor(
        state,
        scale(hands: HandConfiguration.together, tempoBpm: 84),
      ),
      ExecutionAdvance.none,
      reason:
          'a strong right hand cannot drag a left hand that has never '
          'been that fast',
    );
  });

  test('hands together needs both hands, not one', () {
    final state = learner();
    demonstrate(state, HandConfiguration.right, tempoBpm: 72);

    expect(
      executionAdvanceFor(
        state,
        scale(hands: HandConfiguration.together, tempoBpm: 72),
      ),
      ExecutionAdvance.none,
    );
  });

  test('a span neither hand has reached is not where they go together', () {
    final state = learner();
    demonstrate(state, HandConfiguration.right, octaves: 1, tempoBpm: 72);
    demonstrate(state, HandConfiguration.left, octaves: 1, tempoBpm: 72);

    expect(
      executionAdvanceFor(
        state,
        scale(hands: HandConfiguration.together, octaves: 2, tempoBpm: 72),
      ),
      ExecutionAdvance.none,
    );
  });

  test('once hands together has a frontier it goes on like any other', () {
    final state = learner();
    demonstrate(state, HandConfiguration.right, tempoBpm: 84);
    demonstrate(state, HandConfiguration.left, tempoBpm: 84);
    demonstrate(state, HandConfiguration.together, tempoBpm: 60);

    expect(
      executionAdvanceFor(
        state,
        scale(hands: HandConfiguration.together, tempoBpm: 63),
      ),
      ExecutionAdvance.tempo,
      reason: 'through its own record, not through the two hands again',
    );
  });

  test('material nobody has played has nowhere to go on from', () {
    expect(
      executionAdvanceFor(learner(), scale()),
      ExecutionAdvance.none,
      reason: 'meeting material is introduction\'s business',
    );
  });

  group('the neighbours the generator does not contain', () {
    List<Exercise> generatedForC() => generateCandidates(InstrumentProfile(), [
      TechnicalMaterial('C', ScaleForm.major),
    ]);

    test('widening carries a tempo the generator has no candidate at', () {
      // The hole the tempo case alone left open. Sixty-three is reachable at
      // one octave because somebody managed sixty there; going on to two
      // octaves carries sixty-three with it, and the two-octave frontier is
      // empty by definition, so nothing else would make that candidate.
      final state = learner();
      demonstrate(state, HandConfiguration.right, octaves: 1, tempoBpm: 63);
      final generated = generatedForC();

      expect(
        generated.any(
          (e) => e.conditions.octaves == 2 && e.conditions.tempoBpm == 63,
        ),
        isFalse,
      );

      final wider = withExecutionNeighbours(state, generated).where(
        (e) =>
            e.conditions.octaves == 2 &&
            e.conditions.tempoBpm == 63 &&
            e.conditions.hands == HandConfiguration.right,
      );
      expect(wider, isNotEmpty);
      expect(executionAdvanceFor(state, wider.first), ExecutionAdvance.span);
    });

    test('going together carries one too', () {
      final state = learner();
      demonstrate(state, HandConfiguration.right, tempoBpm: 72);
      demonstrate(state, HandConfiguration.left, tempoBpm: 63);
      final generated = generatedForC();

      expect(
        generated.any(
          (e) =>
              e.conditions.hands == HandConfiguration.together &&
              e.conditions.tempoBpm == 63,
        ),
        isFalse,
      );

      final together = withExecutionNeighbours(state, generated).where(
        (e) =>
            e.conditions.hands == HandConfiguration.together &&
            e.conditions.tempoBpm == 63 &&
            e.conditions.octaves == 1,
      );
      expect(together, isNotEmpty);
      expect(
        executionAdvanceFor(state, together.first),
        ExecutionAdvance.handsTogether,
        reason: 'the slower of what each hand managed alone',
      );
    });

    test('a neighbour is added for a span that has been managed', () {
      final state = learner();
      demonstrate(state, HandConfiguration.right, tempoBpm: 60);
      final generated = generateCandidates(InstrumentProfile(), [
        TechnicalMaterial('C', ScaleForm.major),
      ]);

      expect(
        generated.any((e) => e.conditions.tempoBpm == 63),
        isFalse,
        reason: 'sixty-three exists only because somebody managed sixty',
      );
      expect(
        withExecutionNeighbours(state, generated).any(
          (e) =>
              e.conditions.tempoBpm == 63 &&
              e.conditions.hands == HandConfiguration.right &&
              e.conditions.octaves == 1,
        ),
        isTrue,
      );
    });

    test('nothing is added for a learner with no frontier', () {
      final generated = generateCandidates(InstrumentProfile(), [
        TechnicalMaterial('C', ScaleForm.major),
      ]);

      expect(
        withExecutionNeighbours(learner(), generated),
        hasLength(generated.length),
      );
    });

    test('a variant differs from its shape in tempo and nothing else', () {
      final state = learner();
      // Sixty steps to sixty-three, which the generator has no candidate for.
      // Ninety-six would step to a hundred, which it already contains.
      demonstrate(state, HandConfiguration.left, octaves: 2, tempoBpm: 60);
      final generated = generateCandidates(InstrumentProfile(), [
        TechnicalMaterial('C', ScaleForm.major),
      ]);

      final added = withExecutionNeighbours(
        state,
        generated,
      ).where((e) => !generated.contains(e));

      expect(added, isNotEmpty);
      for (final variant in added) {
        expect(variant.conditions.tempoBpm, 63);
        expect(variant.conditions.hands, HandConfiguration.left);
        expect(variant.conditions.octaves, 2);
      }
    });
  });
}
