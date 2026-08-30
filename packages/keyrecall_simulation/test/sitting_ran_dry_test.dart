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
  const slots = 120;
  const seeds = 20;

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
    // Reached by slot eleven, and by three quarters of seeds within a hundred
    // and twenty slots. Recovery walks each material toward support, cued
    // attempts never observe retrieval so nothing re-anchors, and with few
    // materials there is nothing left to introduce instead.
    expect(dryRuns(v1ScaleCatalog), greaterThan(seeds ~/ 2));
  });

  test('the shipped catalog does not', () {
    // Fewer seeds than the others because forty-eight materials is slow and
    // this runs on every commit. Measured further by hand at twenty seeds and
    // a hundred and twenty slots, three times a sweep: still zero, so the
    // breadth is an escape rather than a delay.
    expect(dryRuns(allScales, seeds: 6, slots: 60), isZero);
  });

  test('so a goal that narrows the catalog can reach it', () {
    // Not a stress fixture, then, but a live path: PracticeGoal.scopeOf cuts
    // the catalog to targetMaterialIds, and a goal aimed at a handful of
    // scales reproduces the condition the narrow catalog reaches. Breadth is
    // what is currently keeping the error state off the screen.
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
