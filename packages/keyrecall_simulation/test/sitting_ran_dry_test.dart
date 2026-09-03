import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// When a sitting runs out of things to offer.
///
/// A slot that admits nothing is severe: sittings are unbounded and eight
/// mechanisms can admit outside the ordinary band, so reaching it means every
/// one of them declined. The app shows an error state for it.
///
/// The sweep never produced one over the full catalog, and the invariant run
/// over the seven-material catalog produced them readily. This says which of
/// those is the accident.
void main() {
  const slots = 60;
  const seeds = 8;

  int dryRuns(
    List<TechnicalMaterial> catalog, {
    int seeds = seeds,
    int slots = slots,
    bool withAcquisitionFloor = false,
  }) {
    var dry = 0;
    final candidates = generateCandidates(InstrumentProfile(), catalog);
    for (var seed = 0; seed < seeds; seed++) {
      final trajectory = runTrajectory(
        player: PlayerArchetypes.trueBeginner,
        seed: seed,
        materials: catalog,
        slots: slots,
        generated: candidates,
        acquisitionFloor: withAcquisitionFloor
            ? scaleAcquisitionFloor(candidates)
            : null,
      );
      if (trajectory.slots.length < slots) dry++;
    }
    return dry;
  }

  test('a narrow catalog runs dry for a learner who fails most things', () {
    // A narrow catalog reliably exposes the dry-sitting condition.
    expect(dryRuns(v1ScaleCatalog), greaterThan(0));
  });

  test('the shipped catalog does not', () {
    // Three deterministic samples keep this regression guard inexpensive.
    expect(dryRuns(allScales, seeds: 3, slots: 40), isZero);
  });

  test('the scale acquisition floor keeps a narrow scope actionable', () {
    final candidates = generateCandidates(InstrumentProfile(), v1ScaleCatalog);
    var recoveredRuns = 0;
    for (var seed = 0; seed < seeds; seed++) {
      final withoutFloor = runTrajectory(
        player: PlayerArchetypes.trueBeginner,
        seed: seed,
        materials: v1ScaleCatalog,
        slots: slots,
        generated: candidates,
      );
      if (withoutFloor.terminal == null) continue;

      final withFloor = runTrajectory(
        player: PlayerArchetypes.trueBeginner,
        seed: seed,
        materials: v1ScaleCatalog,
        slots: slots,
        generated: candidates,
        acquisitionFloor: scaleAcquisitionFloor(candidates),
      );
      expect(withFloor.slots, hasLength(slots));
      expect(
        withFloor.slots.where(
          (slot) =>
              slot.winner.challengeBypass == ChallengeBypass.acquisitionFloor,
        ),
        isNotEmpty,
      );
      recoveredRuns++;
    }

    expect(recoveredRuns, greaterThan(0));
    expect(dryRuns(v1ScaleCatalog, withAcquisitionFloor: true), isZero);
  });

  test('so a goal that narrows the catalog can reach it', () {
    // Why PracticeSession.open refuses a scoped goal: PracticeGoal.scopeOf
    // cuts the catalog to targetMaterialIds, and a goal aimed at a handful of
    // scales reproduces the condition the narrow catalog reaches.
    final goal = PracticeGoal(
      id: 'FIVE_SCALES',
      targetMaterialIds: {
        for (final material in allScales.take(5)) material.materialId,
      },
    );

    expect(goal.scopeOf(allScales), hasLength(5));
    expect(
      dryRuns(goal.scopeOf(allScales)),
      greaterThan(0),
      reason: 'a scoped goal is a narrow catalog by another name',
    );
  });
}
