import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final materials = <TechnicalMaterial>[
    v1ScaleCatalog.first,
    ...proofArpeggios,
  ];

  test('mixed-family trajectories preserve structural invariants', () {
    final selectedFamilies = <String>{};
    final found = <Anomaly>[];

    for (final player in PlayerArchetypes.all) {
      for (var seed = 0; seed < 3; seed++) {
        final trajectory = runTrajectory(
          player: player,
          seed: seed,
          materials: materials,
          slots: 40,
        );
        selectedFamilies.addAll(
          trajectory.slots.map((slot) => slot.chosen.material.familyId),
        );
        found.addAll(
          detectAnomalies(trajectory, requestedSlots: 40).where(
            (anomaly) =>
                anomaly.severity == AnomalySeverity.invariant &&
                anomaly.detector != 'sitting_ran_dry',
          ),
        );
        final terminal = trajectory.terminal;
        if (terminal != null) {
          expect(terminal.selectable, isEmpty);
          expect(terminal.candidates.admitted, 0);
        }
      }
    }

    expect(
      found,
      isEmpty,
      reason: found.map((a) => '${a.summary}\n${a.census}').join('\n\n'),
    );
    expect(selectedFamilies, {
      TechnicalMaterial.scaleFamilyId,
      TechnicalMaterial.arpeggioFamilyId,
    });
  });
}
