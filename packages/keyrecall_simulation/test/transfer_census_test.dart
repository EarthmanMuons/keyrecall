import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final run = runTransfer(
    player: transferPlayers.first,
    tier: PlacementTier.beginner,
    firstFamilyId: TechnicalMaterial.arpeggioFamilyId,
    firstPhaseAttempts: 30,
    secondPhaseAttempts: 10,
    truthSamples: 4,
  );

  test('the logit sources add up to the prediction', () {
    for (final point in run.checkpoints) {
      for (final probe in point.probes) {
        final logit = probe.logit.values.reduce((a, b) => a + b);
        expect(
          1 / (1 + math.exp(-logit)),
          closeTo(probe.predicted, 1e-12),
          reason: '${point.phase} ${point.attempts} ${probe.shape.name}',
        );
      }
    }
  });

  test('one family\'s evidence leaves the other\'s own competencies', () {
    final start = run.checkpoints.first;
    final end = run.checkpoints.lastWhere((point) => point.phase == 'first');

    for (final competency in [
      Competency.rhScaleExecution,
      Competency.lhScaleExecution,
      Competency.scalarCrossing,
    ]) {
      expect(
        end.competencies[competency.id],
        closeTo(start.competencies[competency.id]!, 0.05),
        reason: competency.id,
      );
    }
  });

  test('the control sees the second phase the run does', () {
    final second = [
      for (final point in run.checkpoints)
        if (point.phase == 'second') point.attempts,
    ];
    final control = [
      for (final point in run.checkpoints)
        if (point.phase == 'control') point.attempts,
    ];

    expect(control, second);
    expect(
      run.checkpoints
          .firstWhere((point) => point.phase == 'control')
          .probe(TechnicalMaterial.scaleFamilyId, TransferShape.rightOneUp)
          .managed,
      run.checkpoints
          .firstWhere((point) => point.phase == 'second')
          .probe(TechnicalMaterial.scaleFamilyId, TransferShape.rightOneUp)
          .managed,
      reason: 'the player\'s scales are the same in both',
    );
  });
}
