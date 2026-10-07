import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

void main() {
  final cMajorScale = allScales.firstWhere(
    (material) => material.materialId == 'C_MAJOR',
  );
  final cMajorArpeggio = allRootPositionArpeggios.firstWhere(
    (material) => material.materialId == 'C_MAJOR_ROOT_ARPEGGIO',
  );

  TimingCapacity capacityOf(
    TechnicalMaterial material, {
    HandConfiguration hands = HandConfiguration.right,
    int octaves = 1,
    ExerciseDirection direction = ExerciseDirection.up,
  }) => TimingCapacity.of(
    Exercise.linear(
      material: material,
      hands: hands,
      octaves: octaves,
      direction: direction,
    ),
  );

  test('a one-octave ascending arpeggio reads a pace and nothing more', () {
    final capacity = capacityOf(cMajorArpeggio);
    expect(capacity.waits, 3);
    expect(capacity.supportsPace, isTrue);
    expect(capacity.supportsSpread, isFalse);
    expect(capacity.supportsContinuity, isFalse);
    expect(capacity.supportsMotorScore, isFalse);
  });

  test('a longer arpeggio traversal can carry a motor score', () {
    expect(
      capacityOf(
        cMajorArpeggio,
        direction: ExerciseDirection.upDown,
      ).supportsMotorScore,
      isTrue,
    );
    expect(capacityOf(cMajorArpeggio, octaves: 2).supportsMotorScore, isTrue);
  });

  test('a one-octave ascending scale can carry a motor score', () {
    final capacity = capacityOf(cMajorScale);
    expect(capacity.waits, 7);
    expect(capacity.supportsMotorScore, isTrue);
  });

  test('hands together play the moments one hand does', () {
    expect(
      capacityOf(cMajorArpeggio, hands: HandConfiguration.together),
      capacityOf(cMajorArpeggio),
    );
  });
}
