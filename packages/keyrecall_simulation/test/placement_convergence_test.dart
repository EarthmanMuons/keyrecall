import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  test('placements given one history are compared at each checkpoint', () {
    final run = runPlacementConvergence(
      player: PlayerArchetypes.intermediate,
      seed: 0,
      checkpoints: const [10, 20],
      slotsPerSitting: 10,
    );

    expect(
      {for (final point in run.checkpoints) (point.attempts, point.evidence)},
      {
        for (final attempts in [10, 20])
          for (final evidence in EligibilityEvidence.values)
            (attempts, evidence),
      },
      reason: 'both readings of the floors, on the same replayed states',
    );
    for (final point in run.checkpoints) {
      expect(point.meanPrediction, inInclusiveRange(0, 1));
      expect(point.bandDisagreement, inInclusiveRange(0, 1));
    }
  });

  test('a result reads back as it was written, for a resumed run', () {
    final run = runPlacementConvergence(
      player: PlayerArchetypes.intermediate,
      seed: 0,
      checkpoints: const [10],
      slotsPerSitting: 10,
    );
    final read = PlacementConvergenceRun.fromJson(run.toJson());

    expect(read.identity, run.identity);
    expect(read.toJson(), run.toJson());
  });

  test('a history kept selected-only still replays', () {
    final full = runSittings(
      player: PlayerArchetypes.intermediate,
      seed: 3,
      materials: allScales,
      sittings: [Sitting(at: DateTime.utc(2026), slots: 8)],
    );
    final lean = runSittings(
      player: PlayerArchetypes.intermediate,
      seed: 3,
      materials: allScales,
      sittings: [Sitting(at: DateTime.utc(2026), slots: 8)],
      traceRetention: TraceRetention.selectedOnly,
    );

    expect(
      [for (final slot in lean.slots) slot.chosen],
      [for (final slot in full.slots) slot.chosen],
      reason: 'what is kept is not what is decided',
    );
    expect(lean.slots.every((slot) => slot.alternatives.isEmpty), isTrue);
  });
}
