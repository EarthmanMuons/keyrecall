import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

void main() {
  final scale = allScales.first;
  final arpeggio = allRootPositionArpeggios.first;

  Exercise shape(
    TechnicalMaterial material, {
    HandConfiguration hands = HandConfiguration.right,
    int octaves = 1,
    ExerciseDirection direction = ExerciseDirection.up,
  }) => Exercise.linear(
    material: material,
    hands: hands,
    octaves: octaves,
    direction: direction,
  );

  Set<RealizationShape> shown(Iterable<Exercise> exercises) => {
    for (final exercise in exercises) shapeOf(exercise),
  };

  test('nothing demonstrated is no frontier', () {
    expect(advancesShapeFrontier(shape(scale), const {}), isFalse);
  });

  test('a demonstrated shape is not a step past itself', () {
    expect(advancesShapeFrontier(shape(scale), shown([shape(scale)])), isFalse);
  });

  test('each dimension steps once from a demonstrated shape', () {
    final base = shown([shape(scale)]);

    expect(advancesShapeFrontier(shape(scale, octaves: 2), base), isTrue);
    expect(
      advancesShapeFrontier(
        shape(scale, direction: ExerciseDirection.upDown),
        base,
      ),
      isTrue,
    );
    expect(
      advancesShapeFrontier(
        shape(scale, octaves: 2, direction: ExerciseDirection.upDown),
        base,
      ),
      isFalse,
      reason: 'two steps at once',
    );
    expect(
      advancesShapeFrontier(shape(scale, hands: HandConfiguration.left), base),
      isFalse,
      reason: 'the other hand is a first encounter, not a step',
    );
  });

  test('says which way it steps', () {
    final base = shown([
      shape(scale),
      shape(scale, hands: HandConfiguration.left),
    ]);

    expect(shapeStepOf(shape(scale, octaves: 2), base), ShapeStep.span);
    expect(
      shapeStepOf(shape(scale, direction: ExerciseDirection.upDown), base),
      ShapeStep.direction,
    );
    expect(
      shapeStepOf(shape(scale, hands: HandConfiguration.together), base),
      ShapeStep.hands,
    );
  });

  test('hands together waits on both hands where the material asks', () {
    final together = shape(scale, hands: HandConfiguration.together);

    expect(advancesShapeFrontier(together, shown([shape(scale)])), isFalse);
    expect(
      advancesShapeFrontier(
        together,
        shown([shape(scale), shape(scale, hands: HandConfiguration.left)]),
      ),
      isTrue,
    );
  });

  test('span steps follow the declared spans, past two', () {
    final twoOctaves = shown([shape(arpeggio, octaves: 2)]);

    expect(arpeggio.progression.octaveSpans, [1, 2, 4]);
    expect(
      advancesShapeFrontier(shape(arpeggio, octaves: 4), twoOctaves),
      isTrue,
    );
    expect(
      advancesShapeFrontier(
        shape(arpeggio, octaves: 4),
        shown([shape(arpeggio)]),
      ),
      isFalse,
      reason: 'four octaves is two declared steps past one',
    );
  });

  test('every production span steps only from the one declared before it', () {
    for (final material in <TechnicalMaterial>[
      ...allScales,
      ...allRootPositionArpeggios,
    ]) {
      final spans = material.progression.octaveSpans;
      expect(spans.first, 1, reason: '${material.materialId} enters at one');
      for (final (index, span) in spans.indexed.skip(1)) {
        for (final from in spans) {
          expect(
            advancesShapeFrontier(
              shape(material, octaves: span),
              shown([shape(material, octaves: from)]),
            ),
            from == spans[index - 1],
            reason: '${material.materialId} from $from to $span',
          );
        }
      }
    }
  });
}
