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
  /// A managed attempt: the rung it was asked for, and the speed it was played
  /// at, which production records together and which differ only for somebody
  /// going faster than they were asked to.
  void demonstrate(
    LearnerState state,
    HandConfiguration hands, {
    String materialId = 'C_MAJOR',
    int octaves = 1,
    double tempoBpm = 60,
    double? pacedBpm,
  }) =>
      state.materialExecutionFor(
          (materialId, hands),
          t0,
          v1PrototypeLearnerParams,
        )
        ..demonstrate(octaves: octaves, tempoBpm: tempoBpm)
        ..readyForHandsTogether(octaves: octaves, tempoBpm: tempoBpm)
        ..paced(pacedBpm ?? tempoBpm);

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

  test('hands together enters a rung below the slower hand', () {
    // Slower than either hand managed alone, deliberately. Playing them
    // together is a new motor task rather than the two old ones at once.
    final state = learner();
    demonstrate(state, HandConfiguration.right, tempoBpm: 84);
    demonstrate(state, HandConfiguration.left, tempoBpm: 72);

    expect(
      executionAdvanceFor(
        state,
        scale(hands: HandConfiguration.together, tempoBpm: tempoBefore(72)),
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

  group('the tempo an unseen scale is met at', () {
    const pipeline = SchedulerPipeline(learner: LearnerModel());

    // B flat major: early transfer, so the later-band cap is not what these
    // are measuring. B major would have been, which is worth a comment.
    Exercise unseen({
      String tonic = 'Bb',
      HandConfiguration hands = HandConfiguration.right,
      double tempoBpm = 60,
    }) => Exercise.linear(
      material: TechnicalMaterial(tonic, ScaleForm.major),
      hands: hands,
      octaves: 1,
      tempoBpm: tempoBpm,
    );

    test('a learner who has shown nothing meets it unhurried', () {
      expect(
        pipeline.entryTempoFor(learner(), unseen()),
        v1SchedulerConfig.eligibility.gentleTempoBpm,
      );
    });

    test('it is the middle of what that hand does, not the best of it', () {
      // One quick success should not make every scale a learner has never
      // played arrive at a hundred and twenty-six.
      final state = learner();
      for (final (tonic, tempoBpm) in [
        ('C', 60.0),
        ('D', 63.0),
        ('E', 72.0),
        ('F', 104.0),
        ('G', 126.0),
      ]) {
        demonstrate(
          state,
          HandConfiguration.right,
          materialId: '${tonic}_MAJOR',
          tempoBpm: tempoBpm,
        );
      }

      expect(pipeline.entryTempoFor(state, unseen()), 72);
    });

    test('one hand does not speak for the other', () {
      final state = learner();
      demonstrate(state, HandConfiguration.right, tempoBpm: 96);

      expect(
        pipeline.entryTempoFor(state, unseen(hands: HandConfiguration.left)),
        v1SchedulerConfig.eligibility.gentleTempoBpm,
      );
    });

    test('a new geography costs a rung, not the whole ladder', () {
      // A new shape and a new speed at once is the compounding avoided
      // everywhere else, so an unfamiliar geography is worth being careful
      // about. It is worth one rung: the pace is behavioral evidence, and
      // sending a learner who plays at ninety-six back to sixty because the
      // key is harder treats that evidence as though it barely existed.
      final state = learner();
      for (final tonic in ['C', 'D', 'E']) {
        demonstrate(
          state,
          HandConfiguration.right,
          materialId: '${tonic}_MAJOR',
          tempoBpm: 96,
        );
      }

      expect(pipeline.entryTempoFor(state, unseen(tonic: 'D')), 96);
      expect(
        pipeline.entryTempoFor(state, unseen(tonic: 'Db')),
        tempoBefore(96),
        reason: 'D flat major is a keyboard away, not a whole ladder away',
      );
    });

    test('an introduction is offered at that tempo and no other', () {
      // The behaviour this replaced: every generated tempo was admitted and
      // nothing in the ranking key reads tempo, so which one a learner met
      // was decided by the order of a constant.
      final state = learner();
      for (final tonic in ['C', 'D', 'E']) {
        demonstrate(
          state,
          HandConfiguration.right,
          materialId: '${tonic}_MAJOR',
          tempoBpm: 76,
        );
        state.materialMemoryFor('${tonic}_MAJOR', v1PrototypeLearnerParams);
      }

      final offered = pipeline
          .evaluate(
            state: state,
            session: SessionState(),
            candidates: generateCandidates(InstrumentProfile(), [
              TechnicalMaterial('Bb', ScaleForm.major),
            ]),
            at: t0.plusDays(1),
          )
          .where(
            (trace) =>
                trace.challengeBypass == ChallengeBypass.newMaterial &&
                trace.exercise.conditions.hands == HandConfiguration.right &&
                // At one octave, which is the span the evidence is at: two
                // octaves has none, so it is met unhurried like anything else
                // nobody has shown.
                trace.exercise.conditions.octaves == 1,
          );

      expect(offered, isNotEmpty);
      expect(
        offered.map((trace) => trace.exercise.conditions.tempoBpm).toSet(),
        {76.0},
      );
    });
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
            e.conditions.tempoBpm == tempoBefore(63) &&
            e.conditions.octaves == 1,
      );
      expect(together, isNotEmpty);
      expect(
        executionAdvanceFor(state, together.first),
        ExecutionAdvance.handsTogether,
        reason: 'a rung below the slower of what each hand managed alone',
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

    test('the rung a learner is on stays offerable', () {
      // Found by the simulation suite rather than by reasoning. Offering only
      // the next rung made the current one vanish the moment the frontier
      // reached it, and a recovery context targets an exact exercise: with
      // its target gone, recovery is exclusive and admits nothing, so whole
      // slots went empty.
      final state = learner();
      demonstrate(state, HandConfiguration.right, tempoBpm: 63);
      final generated = generatedForC();

      final offered = withExecutionNeighbours(state, generated);
      expect(
        offered.any(
          (e) =>
              e.conditions.tempoBpm == 63 &&
              e.conditions.hands == HandConfiguration.right &&
              e.conditions.octaves == 1,
        ),
        isTrue,
        reason:
            'holding is ordinary work, and recovering needs somewhere to '
            'recover to',
      );
      expect(
        offered.any((e) => e.conditions.tempoBpm == 66),
        isTrue,
        reason: 'and the next rung is there beside it',
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
