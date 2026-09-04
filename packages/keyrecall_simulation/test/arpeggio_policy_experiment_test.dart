import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  test('the small fixture traverses the declared progression', () async {
    final run = await runArpeggioPolicyTrajectory(
      arm: ArpeggioPolicyArm.baseline,
      scope: ArpeggioPolicyScope.smallFixture,
      player: PlayerArchetypes.advanced,
      seed: 0,
      slots: 40,
    );

    expect(run.terminal, isNot(ArpeggioPolicyTerminal.invalid));
    expect(run.firstRightHandArpeggioSlot, isNotNull);
    expect(run.firstLeftHandArpeggioSlot, isNotNull);
    expect(run.firstHandsTogetherArpeggioSlot, isNotNull);
    expect(run.firstTwoOctaveArpeggioSlot, isNotNull);
    expect(run.firstFourOctaveArpeggioSlot, isNotNull);
  });

  test(
    'full mixed scope selects both families through one practice loop',
    () async {
      final run = await runArpeggioPolicyTrajectory(
        arm: ArpeggioPolicyArm.baseline,
        scope: ArpeggioPolicyScope.fullMixed,
        player: PlayerArchetypes.intermediate,
        seed: 0,
        slots: 40,
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
    },
  );

  test('entry-tempo counterfactuals escape the acquisition floor', () async {
    for (final id in ['tempo_50', 'tempo_70']) {
      final arm = ArpeggioPolicyArm.sensitivityArms.firstWhere(
        (arm) => arm.id == id,
      );
      final run = await runArpeggioPolicyTrajectory(
        arm: arm,
        scope: ArpeggioPolicyScope.smallFixture,
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

  test('full corpus records fingering-family selection', () async {
    final run = await runArpeggioPolicyTrajectory(
      arm: ArpeggioPolicyArm.baseline,
      scope: ArpeggioPolicyScope.fullArpeggioCorpus,
      player: PlayerArchetypes.advanced,
      seed: 0,
      slots: 4,
    );

    expect(run.arpeggioMaterialSelections, isNotEmpty);
    expect(run.arpeggioFingeringFamilySelections, isNotEmpty);
    expect(
      run.arpeggioFingeringFamilySelections.keys,
      everyElement(matches(RegExp(r'^(RH|LH) [1-5]{4}$'))),
    );
    expect(run.arpeggioHandSelections.values.reduce((a, b) => a + b), 4);
  });

  test('the policy matrix can use bounded isolate workers', () async {
    final progress = <int>[];
    final serial = await runArpeggioPolicyMatrix(
      scopes: const [ArpeggioPolicyScope.smallFixture],
      players: [PlayerArchetypes.advanced],
      seeds: 2,
      slots: 4,
    );
    final parallel = await runArpeggioPolicyMatrix(
      scopes: const [ArpeggioPolicyScope.smallFixture],
      players: [PlayerArchetypes.advanced],
      seeds: 2,
      slots: 4,
      parallelism: 2,
      onProgress: (completed, _) => progress.add(completed),
    );

    expect(parallel.map((run) => run.seed), [0, 1]);
    expect(progress.toSet(), {1, 2});
    for (var index = 0; index < serial.length; index++) {
      expect(
        parallel[index].arpeggioMaterialSelections,
        serial[index].arpeggioMaterialSelections,
      );
      expect(
        parallel[index].admittedArpeggioPredictions,
        serial[index].admittedArpeggioPredictions,
      );
      expect(parallel[index].terminal, serial[index].terminal);
    }
  });
}
