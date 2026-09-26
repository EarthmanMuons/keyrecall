import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  var slot = 0;
  GoalTrajectorySelection pick({
    String materialId = 'c-major',
    int sitting = 0,
    HandConfiguration hands = HandConfiguration.right,
    int octaves = 1,
    ExerciseDirection direction = ExerciseDirection.up,
    GuidanceContext guidance = GuidanceContext.unguided,
    bool clean = true,
    ShapeStepObservation? shapeStep,
  }) => GoalTrajectorySelection(
    slot: slot++,
    sitting: sitting,
    materialId: materialId,
    familyId: TechnicalMaterial.scaleFamilyId,
    form: null,
    hands: hands,
    octaves: octaves,
    direction: direction,
    guidance: guidance,
    isTarget: false,
    isTargetShaped: false,
    isLiveSupport: false,
    coveredBefore: 0,
    clean: clean,
    predicted: 0.8,
    shapeStep: shapeStep,
  );

  test(
    'a demonstrated harder shape subsumes an easier one of its material',
    () {
      final hard = pick(
        hands: HandConfiguration.together,
        octaves: 2,
        direction: ExerciseDirection.upDown,
      );
      expect(subsumes(hard, pick()), isTrue);
      expect(subsumes(hard, pick(materialId: 'g-major')), isFalse);
      expect(subsumes(pick(), pick()), isFalse, reason: 'the same shape');
      expect(
        subsumes(pick(octaves: 4), pick(octaves: 2)),
        isTrue,
        reason: 'wider within the same depth',
      );
      expect(
        subsumes(pick(octaves: 2), pick(hands: HandConfiguration.left)),
        isFalse,
        reason: 'the other hand is not played',
      );
    },
  );

  test('subsumed counts only what was demonstrated before the pick', () {
    final [first, second] = realizationDepthOf(
      [
        pick(),
        pick(octaves: 2, clean: false),
        pick(),
        pick(sitting: 1, octaves: 2),
        pick(sitting: 1),
      ],
      sittings: 2,
      every: 1,
    );
    expect(first.subsumed, 0, reason: 'the two-octave attempt failed');
    expect(first.depth, [2 / 3, 1 / 3, 0, 0]);
    expect(first.spans, {1: 2 / 3, 2: 1 / 3});
    expect(first.failed, 1 / 3);
    expect(second.subsumed, 0.5);
    expect(second.establishedRetrieved, 1);
  });

  test('supplied material neither demonstrates nor retrieves', () {
    final [first, second] = realizationDepthOf(
      [
        pick(guidance: GuidanceContext.notesPreviewedOnly),
        pick(sitting: 1, materialId: 'g-major'),
      ],
      sittings: 2,
      every: 1,
    );
    expect(first.previewed, 1);
    expect(second.establishedRetrieved, 0);
  });

  test('counts what the shape frontier could do, and did', () {
    const recovering = ShapeStepObservation(
      route: 'recovery',
      replaceable: false,
      opportunity: false,
    );
    const passedOver = ShapeStepObservation(
      route: 'execution_progression',
      replaceable: true,
      opportunity: true,
    );
    const taken = ShapeStepObservation(
      route: 'band',
      replaceable: true,
      opportunity: true,
      step: ShapeStep.hands,
      stepRoute: 'execution_progression',
    );
    final [interval] = realizationDepthOf(
      [
        pick(shapeStep: recovering),
        pick(shapeStep: passedOver),
        pick(shapeStep: taken),
        pick(),
      ],
      sittings: 1,
      every: 1,
    );

    expect(interval.routes, {
      'recovery': 0.25,
      'execution_progression': 0.25,
      'band': 0.25,
    });
    expect(interval.replaceable, 0.5);
    expect(interval.opportunity, 0.5);
    expect(interval.replaced, 0.25);
    expect(interval.steps, {'hands': 1});
    expect(interval.stepRoutes, {'execution_progression': 1});
  });
}
