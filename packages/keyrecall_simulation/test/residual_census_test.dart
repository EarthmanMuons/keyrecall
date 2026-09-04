import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  group('split-half reliability', () {
    test('reads zero on residuals that are only noise', () {
      final noise = _wobble();
      final observations = [
        for (var cell = 0; cell < 20; cell++)
          for (var attempt = 0; attempt < 8; attempt++)
            _observation(cell: cell, execution: noise()),
      ];

      final reliability = SplitHalfReliability.of(
        observations,
        (observation) => observation.materialId,
      );

      expect(reliability.cells, 20);
      expect(reliability.correlation.abs(), lessThan(0.4));
    });

    test('reads high on a stable offset per cell', () {
      final noise = _wobble();
      final observations = [
        for (var cell = 0; cell < 20; cell++)
          for (var attempt = 0; attempt < 8; attempt++)
            _observation(cell: cell, execution: cell * 0.05 + noise()),
      ];

      final reliability = SplitHalfReliability.of(
        observations,
        (observation) => observation.materialId,
      );

      expect(reliability.correlation, greaterThan(0.9));
    });

    test('ignores cells with too little to split', () {
      final observations = [
        for (var attempt = 0; attempt < 8; attempt++)
          _observation(cell: 0, execution: 0.1),
        _observation(cell: 1, execution: 0.9),
      ];

      final reliability = SplitHalfReliability.of(
        observations,
        (observation) => observation.materialId,
      );

      expect(reliability.cells, 1);
    });
  });

  group('controlling for a confound', () {
    test('removes an effect the control explains entirely', () {
      final observations = [
        for (var cell = 0; cell < 12; cell++)
          for (var attempt = 0; attempt < 8; attempt++)
            _observation(
              cell: cell,
              // The whole of the residual is the hand, and cells never mix
              // hands, so a cell mean is the hand mean and nothing else.
              hands: cell.isEven
                  ? HandConfiguration.right
                  : HandConfiguration.left,
              execution: cell.isEven ? 0.2 : -0.2,
            ),
      ];

      final raw = SplitHalfReliability.of(
        observations,
        (observation) => observation.materialHand,
      );
      final controlled = SplitHalfReliability.of(
        centeredBy(observations, (observation) => observation.hands.id),
        (observation) => observation.materialHand,
      );

      expect(raw.correlation, greaterThan(0.9));
      expect(controlled.correlation.abs(), lessThan(0.001));
    });
  });
}

/// A deterministic wobble, so a reliability test is not a coin flip.
double Function() _wobble() {
  var step = 0;
  return () => [0.3, -0.2, 0.1, -0.4, 0.25, -0.15, 0.35, -0.3][step++ % 8];
}

ResidualObservation _observation({
  required int cell,
  required double execution,
  HandConfiguration hands = HandConfiguration.right,
}) => ResidualObservation(
  playerId: 'test',
  seed: 0,
  index: cell,
  exercise: Exercise.linear(
    material: allScales[cell % allScales.length],
    hands: hands,
    octaves: 1,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
  ),
  execution: execution,
  topology: 0,
);
