import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final catalog = <TechnicalMaterial>[
    ...v1ScaleCatalog.take(3),
    ...proofArpeggios.take(3),
  ];
  final set = standardAssessment(catalog, repetitions: 2);
  const scales = TechnicalMaterial.scaleFamilyId;
  const arpeggios = TechnicalMaterial.arpeggioFamilyId;

  /// Each skew, keyed by the family the player is weak in.
  final weakIn = {
    scales: PlayerArchetypes.arpeggioStrongScaleWeak,
    arpeggios: PlayerArchetypes.scaleStrongArpeggioWeak,
  };
  const seeds = [2, 4];

  // Run once and ask several questions of the same trajectories, because each
  // is eighty slots against the real pipeline.
  final runs = {
    for (final weak in weakIn.keys)
      for (final seed in seeds)
        (weak, seed): runSittings(
          player: weakIn[weak]!,
          seed: seed,
          materials: catalog,
          sittings: sittingsOnDays([0, 1, 2, 3], slots: 20),
          assessment: set,
        ),
  };

  String otherThan(String family) => family == scales ? arpeggios : scales;

  Iterable<TrajectorySlot> slotsIn(Trajectory trajectory, String family) =>
      trajectory.slots.where((slot) => slot.chosen.material.familyId == family);

  test('a reading reports each family that was asked about', () {
    final reading = runs[(arpeggios, 2)]!.assessments.first;

    expect(reading.families.keys, unorderedEquals([scales, arpeggios]));
    expect(
      reading.families.values.map((r) => r.attempts).reduce((a, b) => a + b),
      reading.attempts,
    );
    expect(
      reading.families[scales]!.managed,
      greaterThan(reading.families[arpeggios]!.managed),
      reason: 'the skew is there before any practice happens',
    );
    expect(
      reading.families[scales]!.families,
      isEmpty,
      reason: 'a family reading does not divide itself again',
    );
  });

  test('a family is met at its own pace, never at the other one\'s', () {
    for (final entry in runs.entries) {
      final (weak, seed) = entry.key;
      final where = 'weak in $weak at seed $seed';
      final strongest = slotsIn(entry.value, otherThan(weak))
          .map((slot) => slot.chosen.conditions.tempoBpm)
          .fold<double>(0, (best, tempo) => tempo > best ? tempo : best);

      // What this family has actually shown, in the order the run showed it.
      var ownPace = 60.0;
      for (final slot in entry.value.slots) {
        if (slot.chosen.material.familyId != weak) continue;
        if (slot.frontierAtSpan == 0) {
          expect(
            slot.chosen.conditions.tempoBpm,
            // The rung at or just above what this family has played: a pace
            // is a measured number and the ladder only offers its rungs.
            lessThanOrEqualTo(tempoAfter(ownPace)),
            reason:
                'with nothing demonstrated at this span, $weak is met at what '
                '$weak itself has played, never at the $strongest the other '
                'family reached, $where',
          );
        }
        final performed = slot.performedTempoBpm;
        if (performed > ownPace) ownPace = performed;
      }
    }
  });

  test('the supported foothold survives narrowing, loses, and yields none', () {
    var admitted = 0;
    var selectable = 0;
    final chosen = <TrajectorySlot>[];
    final otherWeak = <TrajectorySlot>[];

    for (final weak in weakIn.keys) {
      bool foothold(CandidateTrace trace) =>
          trace.exercise.material.familyId == weak &&
          trace.executionAdvance == ExecutionAdvance.handsTogether &&
          trace.challengeBypass == ChallengeBypass.executionProgression;

      for (final seed in [2, 3, 4]) {
        final trajectory = runSittings(
          player: weakIn[weak]!,
          seed: seed,
          materials: catalog,
          sittings: sittingsOnDays([0, 1, 2, 3], slots: 20),
          observeTraces: (_, traces) =>
              admitted += traces.where(foothold).length,
        );
        for (final slot in trajectory.slots) {
          // Every slot, because a foothold competes in slots the strong family
          // goes on to win as well.
          selectable += [
            slot.winner,
            ...slot.alternatives,
          ].where(foothold).length;
          if (slot.chosen.material.familyId != weak) continue;
          (foothold(slot.winner) ? chosen : otherWeak).add(slot);
        }
      }
    }

    expect(
      selectable / admitted,
      greaterThan(0.8),
      reason:
          'almost nothing removes it between admission and ranking, so what '
          'happens to it is a ranking outcome rather than a narrowing one',
    );
    expect(
      chosen.length / admitted,
      lessThan(0.05),
      reason: 'and ranking passes over it nearly every time',
    );
    expect(chosen, isNotEmpty);
    expect(
      chosen.where((slot) => slot.managedExecution),
      isEmpty,
      reason:
          'when it does win it demonstrates nothing, so restoring its share '
          'would restore activity rather than learning',
    );
    expect(
      otherWeak.where((slot) => slot.managedExecution),
      isNotEmpty,
      reason: 'while the rest of the weak family sometimes does',
    );
  });

  test('the weaker family still gains far less than the stronger one', () {
    for (final entry in runs.entries) {
      final (weak, seed) = entry.key;
      final before = entry.value.assessments.first.families;
      final after = entry.value.assessments.last.families;
      final where = 'weak in $weak at seed $seed';

      final strongGain =
          after[otherThan(weak)]!.managed - before[otherThan(weak)]!.managed;
      final weakGain = after[weak]!.managed - before[weak]!.managed;

      expect(
        strongGain,
        greaterThan(0),
        reason: 'the strong family improves in every run, $where',
      );
      expect(
        weakGain,
        lessThan(strongGain),
        reason:
            'scoping the pace stopped the weak family being asked past itself '
            'and did not on its own make it catch up, $where',
      );
    }
  });
}
