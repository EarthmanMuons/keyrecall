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
/// a record that no frontier was reached within that budget.
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

  test('a bounded chance reaches a first frontier it otherwise would not', () {
    var withoutFrontier = 0;
    var withFrontier = 0;
    var exhaustedWithNothing = 0;

    for (final weak in weakIn.keys) {
      for (final seed in seeds) {
        final without = runWith(weak: weak, bound: 0, seed: seed);
        final bounded = runWith(weak: weak, bound: 8, seed: seed);

        if (without.frontierAt >= 0) withoutFrontier++;
        if (bounded.frontierAt >= 0) withFrontier++;
        if (bounded.frontierAt < 0 && bounded.consumed >= 8) {
          exhaustedWithNothing++;
        }
        expect(
          bounded.consumed,
          lessThanOrEqualTo(8),
          reason: 'the bound holds for $weak at seed $seed',
        );
      }
    }

    expect(
      withFrontier,
      greaterThan(withoutFrontier),
      reason: 'families reach a frontier that ordinary work never gave them',
    );
    expect(
      exhaustedWithNothing,
      greaterThan(0),
      reason: 'some runs exhaust this budget without demonstrating a frontier',
    );
  });

  test('the bounded preference does not improve measured managed success', () {
    for (final weak in weakIn.keys) {
      for (final seed in seeds) {
        final without = runWith(weak: weak, bound: 0, seed: seed);
        final bounded = runWith(weak: weak, bound: 8, seed: seed);

        expect(
          bounded.weakGain,
          without.weakGain,
          reason:
              'the held-out reading of $weak at seed $seed is the same number '
              'either way; continuous outcomes may still change below that threshold',
        );
        expect(bounded.weakGain, lessThanOrEqualTo(0));
      }
    }
  });
}
