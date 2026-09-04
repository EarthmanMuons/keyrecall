import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  test('a narrow arpeggio scope traverses the declared progression', () async {
    final run = await runArpeggioPolicyTrajectory(
      arm: ArpeggioPolicyArm.baseline,
      scope: ArpeggioPolicyScope.singleArpeggio,
      player: PlayerArchetypes.advanced,
      seed: 0,
      slots: 20,
    );

    expect(run.terminal, isNot(ArpeggioPolicyTerminal.invalid));
    expect(run.firstRightHandArpeggioSlot, isNotNull);
    expect(run.firstLeftHandArpeggioSlot, isNotNull);
    expect(run.firstHandsTogetherArpeggioSlot, isNotNull);
    expect(run.firstTwoOctaveArpeggioSlot, isNotNull);
    expect(run.firstFourOctaveArpeggioSlot, isNotNull);
  });

  test('mixed scope selects both families through one practice loop', () async {
    final run = await runArpeggioPolicyTrajectory(
      arm: ArpeggioPolicyArm.baseline,
      scope: ArpeggioPolicyScope.mixed,
      player: PlayerArchetypes.intermediate,
      seed: 0,
      slots: 20,
    );

    expect(
      run.familySelections[TechnicalMaterial.scaleFamilyId],
      greaterThan(0),
    );
    expect(
      run.familySelections[TechnicalMaterial.arpeggioFamilyId],
      greaterThan(0),
    );
    expect(run.arpeggioCandidatesEvaluated, greaterThan(0));
    expect(run.admittedArpeggioPredictions, isNotEmpty);
  });

  test('entry-tempo counterfactuals escape the acquisition floor', () async {
    for (final id in ['tempo_50', 'tempo_70']) {
      final arm = ArpeggioPolicyArm.sensitivityArms.firstWhere(
        (arm) => arm.id == id,
      );
      final run = await runArpeggioPolicyTrajectory(
        arm: arm,
        scope: ArpeggioPolicyScope.singleArpeggio,
        player: PlayerArchetypes.trueBeginner,
        seed: 0,
        slots: 20,
      );

      expect(run.firstLeftHandArpeggioSlot, isNotNull, reason: id);
      expect(run.longestFloorRun, lessThan(20), reason: id);
    }
  });

  test(
    'scale-only control is run once rather than once per policy arm',
    () async {
      final runs = await runArpeggioPolicyMatrix(
        arms: const [
          ArpeggioPolicyArm.baseline,
          ArpeggioPolicyArm(id: 'transfer_0', rhoFamily: 0),
        ],
        scopes: const [ArpeggioPolicyScope.scaleOnly],
        players: [PlayerArchetypes.advanced],
        seeds: 2,
        slots: 2,
      );

      expect(runs, hasLength(2));
      expect(runs.map((run) => run.armId).toSet(), {'baseline'});
    },
  );
}
