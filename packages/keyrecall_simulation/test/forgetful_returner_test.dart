import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final catalog = v1ScaleCatalog.take(4).toList();
  final set = standardAssessment(catalog, repetitions: 2);

  /// Four sittings to build something, then a season away, then a return.
  final schedule = sittingsOnDays([0, 1, 2, 3, 120], slots: 20);
  const returned = 4;

  final base = PlayerArchetypes.forgetfulReturner;
  final decaying = {
    'matched': base.copyWith(id: 'matched'),
    'faster': base.copyWith(
      id: 'faster',
      retentionHalfLifeDays: 12,
      familiarityHalfLifeDays: 6,
    ),
  };
  // The stable case is the same person with forgetting switched off, which
  // copyWith cannot express because it cannot pass null.
  final stable = SyntheticPlayer(
    id: 'stable',
    placement: base.placement,
    naturalTempoRightBpm: base.naturalTempoRightBpm,
    naturalTempoLeftBpm: base.naturalTempoLeftBpm,
    tempoCompliance: base.tempoCompliance,
    rightHandAbility: base.rightHandAbility,
    leftHandAbility: base.leftHandAbility,
    handsTogetherAbility: base.handsTogetherAbility,
    familiarity: base.familiarity,
    spanPenalty: base.spanPenalty,
    learningRate: base.learningRate,
  );

  Trajectory runOf(SyntheticPlayer player) => runSittings(
    player: player,
    seed: 8,
    materials: catalog,
    sittings: schedule,
    assessment: set,
  );

  /// The reading taken on arrival at sitting [index], before its practice.
  AssessmentReading arrivalAt(Trajectory trajectory, int index) =>
      trajectory.assessments[index * 2];

  /// The reading taken as sitting [index] ended.
  AssessmentReading departureAt(Trajectory trajectory, int index) =>
      trajectory.assessments[index * 2 + 1];

  test('a break costs the forgetful player what it costs nobody else', () {
    final unchanging = runOf(stable);
    final forgetting = runOf(decaying['matched']!);

    for (final trajectory in [unchanging, forgetting]) {
      expect(
        departureAt(trajectory, 3).managed,
        greaterThan(arrivalAt(trajectory, 0).managed),
        reason: 'both learn the same way before the break',
      );
    }
    expect(
      arrivalAt(unchanging, returned).managed,
      departureAt(unchanging, 3).managed,
      reason: 'a player who forgets nothing returns as they left',
    );
    expect(
      arrivalAt(forgetting, returned).managed,
      lessThan(departureAt(forgetting, 3).managed),
      reason: 'a hundred and seventeen days cost the returner something real',
    );
  });

  test('forgetting is elapsed time, not sittings missed', () {
    double lostOver(List<int> days) {
      final trajectory = runSittings(
        player: decaying['matched']!,
        seed: 8,
        materials: catalog,
        sittings: sittingsOnDays([0, ...days], slots: 20),
        assessment: set,
      );
      final away = trajectory.assessments;
      return away[1].managed - away[2].managed;
    }

    final short = lostOver([2]);
    final long = lostOver([90]);

    expect(short, lessThan(long));
    expect(short, greaterThanOrEqualTo(0));
  });

  test('one belief, three people, and the gap is what tells them apart', () {
    final readings = {
      for (final entry in {'stable': stable, ...decaying}.entries)
        entry.key: arrivalAt(runOf(entry.value), returned),
    };

    // Belief decays across the same calendar for all three, so the model is
    // equally stale everywhere and only the person differs.
    expect(
      readings.values.map((r) => r.predicted!.toStringAsFixed(6)).toSet(),
      hasLength(1),
    );
    expect(
      readings['faster']!.managed,
      lessThanOrEqualTo(readings['matched']!.managed),
    );
    expect(readings['matched']!.managed, lessThan(readings['stable']!.managed));
    expect(
      readings['stable']!.beliefGap!,
      lessThan(readings['matched']!.beliefGap!),
      reason:
          'the same expectation understates the player who kept what they '
          'had by more than it understates the one who lost it',
    );
  });

  test('a long gap leaves the model expecting nothing of anybody', () {
    final readings = {
      for (final entry in {'stable': stable, ...decaying}.entries)
        entry.key: arrivalAt(runOf(entry.value), returned),
    };

    for (final reading in readings.values) {
      expect(
        reading.predicted,
        lessThan(0.01),
        reason:
            'a hundred and seventeen days is long enough for the model to '
            'forget the whole learner',
      );
      expect(
        reading.beliefGap,
        lessThan(0),
        reason:
            'so a returner is met with a model that understates them, not '
            'one that keeps asking for what they could do in April',
      );
    }
    expect(
      readings['stable']!.managed,
      greaterThan(0.5),
      reason: 'the person the model expects nothing of can still play',
    );
  });

  test('what the scheduler asks for on return is answerable', () {
    for (final player in [stable, ...decaying.values]) {
      final trajectory = runOf(player);
      final firstBack = trajectory.slots
          .where((slot) => slot.sitting == returned)
          .take(5)
          .toList();

      expect(firstBack, hasLength(5));
      expect(
        firstBack.where((slot) => slot.outcome.started),
        isNotEmpty,
        reason:
            'a returner met with work they cannot begin is the failure this '
            'archetype exists to catch, for ${player.id}',
      );
    }
  });
}
