import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// A bounded chance for a family with nothing to show for itself.
///
/// Not a rank bonus and not a preference for weak families: while the target
/// family has no execution frontier, and only until it has one, a slot may be
/// spent on the single-hand, one-octave, continuously cued work that is the
/// only shape those families ever demonstrate anything from. The bound is what
/// stops it running forever, and exhausting the bound without a frontier is
/// the signal that the learner is under the floor rather than short of slots.
void main() {
  final catalog = <TechnicalMaterial>[
    ...v1ScaleCatalog.take(3),
    ...proofArpeggios.take(3),
  ];
  final set = standardAssessment(catalog, repetitions: 2);
  const seeds = [2, 3];

  final weakIn = {
    TechnicalMaterial.scaleFamilyId: PlayerArchetypes.arpeggioStrongScaleWeak,
    TechnicalMaterial.arpeggioFamilyId:
        PlayerArchetypes.scaleStrongArpeggioWeak,
  };

  ({int frontierAt, int consumed, double weakGain, double strongGain}) runWith({
    required String weak,
    required int bound,
    required int seed,
  }) {
    final strong = weak == TechnicalMaterial.scaleFamilyId
        ? TechnicalMaterial.arpeggioFamilyId
        : TechnicalMaterial.scaleFamilyId;
    var spent = 0;
    var frontierAt = -1;
    var slot = 0;

    final trajectory = runSittings(
      player: weakIn[weak]!,
      seed: seed,
      materials: catalog,
      sittings: sittingsOnDays([0, 1, 2, 3], slots: 20),
      assessment: set,
      chooseInstead: (selection, state) {
        slot++;
        final established = state.materialExecution.values.any(
          (residual) =>
              residual.familyId == weak &&
              residual.demonstratedTempoByOctaves.isNotEmpty,
        );
        if (established) {
          if (frontierAt < 0) frontierAt = slot;
          return null;
        }
        if (spent >= bound) return null;
        for (final trace in selection.selectable) {
          final exercise = trace.exercise;
          if (exercise.material.familyId == weak &&
              exercise.conditions.hands != HandConfiguration.together &&
              exercise.conditions.octaves == 1 &&
              exercise.guidance == GuidanceContext.continuouslyCued) {
            spent++;
            return trace;
          }
        }
        return null;
      },
    );

    final before = trajectory.assessments.first.families;
    final after = trajectory.assessments.last.families;
    return (
      frontierAt: frontierAt,
      consumed: spent,
      weakGain: after[weak]!.managed - before[weak]!.managed,
      strongGain: after[strong]!.managed - before[strong]!.managed,
    );
  }

  test('a bounded chance reaches the first frontier, and cheaply', () {
    for (final weak in weakIn.keys) {
      for (final seed in seeds) {
        final without = runWith(weak: weak, bound: 0, seed: seed);
        final with8 = runWith(weak: weak, bound: 8, seed: seed);
        final where = '$weak at seed $seed';

        expect(
          with8.frontierAt,
          greaterThanOrEqualTo(0),
          reason: 'the family ends up with something to progress from, $where',
        );
        expect(
          with8.consumed,
          lessThanOrEqualTo(8),
          reason: 'inside the bound, $where',
        );
        if (without.frontierAt < 0) {
          expect(
            with8.frontierAt,
            greaterThanOrEqualTo(0),
            reason: 'where eighty slots of ordinary work reached none, $where',
          );
        }
      }
    }
  });

  test('and it is not what makes the learner better', () {
    var reached = 0;
    var improved = 0;

    for (final weak in weakIn.keys) {
      for (final seed in seeds) {
        final result = runWith(weak: weak, bound: 8, seed: seed);
        if (result.frontierAt >= 0) reached++;
        if (result.weakGain > 0.01) improved++;
      }
    }

    expect(reached, seeds.length * weakIn.length);
    expect(
      improved,
      isZero,
      reason:
          'every family reaches a frontier and none of them reads better on '
          'the held-out set, so the first frontier is not the thing that was '
          'missing either',
    );
  });
}
