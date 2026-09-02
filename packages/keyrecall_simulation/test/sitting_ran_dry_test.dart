import 'package:keyrecall_domain/keyrecall_domain.dart';
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
  }) {
    var dry = 0;
    for (var seed = 0; seed < seeds; seed++) {
      final trajectory = runTrajectory(
        player: PlayerArchetypes.trueBeginner,
        seed: seed,
        materials: catalog,
        slots: slots,
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
