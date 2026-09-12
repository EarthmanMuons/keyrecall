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
/// A narrow catalog reaches it and a full one does not, and what separates them
/// is the pre-frontier acquisition floor: without it, the gentlest work in the
/// only family on offer is held to the ordinary challenge floor after a first
/// exposure and refused for being too hard. A learner with a second family
/// never notices, because that family keeps admission alive.
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

  test('a narrow catalog no longer runs dry', () {
    expect(
      dryRuns(v1ScaleCatalog),
      isZero,
      reason:
          'the gentlest work in a family with no frontier is admitted at the '
          'introduction floor rather than the ordinary one, so a sitting that '
          'used to run out of things to offer has this to offer',
    );
  });

  test('the shipped catalog does not either', () {
    // Three deterministic samples keep this regression guard inexpensive.
    expect(dryRuns(allScales, seeds: 3, slots: 40), isZero);
  });

  test('and the fallback is no longer what keeps it actionable', () {
    final candidates = generateCandidates(InstrumentProfile(), v1ScaleCatalog);
    for (var seed = 0; seed < seeds; seed++) {
      final trajectory = runTrajectory(
        player: PlayerArchetypes.trueBeginner,
        seed: seed,
        materials: v1ScaleCatalog,
        slots: slots,
        generated: candidates,
        acquisitionFloor: scaleAcquisitionFloor(candidates),
      );

      expect(trajectory.slots, hasLength(slots));
      expect(
        trajectory.slots.where(
          (slot) =>
              slot.winner.challengeBypass == ChallengeBypass.acquisitionFloor,
        ),
        isEmpty,
        reason:
            'ordinary admission has work for this learner now, so the '
            'fallback is not reached at seed $seed. It stays for the cases '
            'where admission genuinely produces nothing.',
      );
    }
  });

  test('so a goal that narrows the catalog can be offered one', () {
    // PracticeGoal.scopeOf cuts the catalog to targetMaterialIds, so a goal
    // aimed at a handful of scales was a narrow catalog by another name, and
    // this reproduced the dry sitting that argument against shipping goals
    // rested on. The seam itself is covered by scoped_goal_test.dart.
    final goal = PracticeGoal(
      id: 'FIVE_SCALES',
      targetMaterialIds: {
        for (final material in allScales.take(5)) material.materialId,
      },
    );

    expect(goal.scopeOf(allScales), hasLength(5));
    expect(
      dryRuns(goal.scopeOf(allScales)),
      isZero,
      reason: 'which no longer reproduces the condition that refuses it',
    );
  });
}
