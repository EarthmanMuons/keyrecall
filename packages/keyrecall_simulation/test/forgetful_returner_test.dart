import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
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

  test('what a returner is asked for on the way back is answerable', () {
    for (final player in [stable, ...decaying.values]) {
      for (final seed in [8, 9, 10]) {
        final back = runSittings(
          player: player,
          seed: seed,
          materials: catalog,
          sittings: schedule,
          assessment: set,
        ).slots.where((slot) => slot.sitting == returned).toList();
        final where = '${player.id} at seed $seed';

        expect(
          back.take(5).where((slot) => slot.outcome.started),
          hasLength(greaterThanOrEqualTo(2)),
          reason: 'more than one of the first five back answers, for $where',
        );
        for (final (i, slot) in back.indexed) {
          if (slot.outcome.started || i + 1 >= back.length) continue;
          expect(
            back[i + 1].chosen.guidance.independence,
            lessThan(slot.chosen.guidance.independence),
            reason:
                'an attempt that never started is answered with more support '
                'at slot ${slot.index}, for $where',
          );
        }
      }
    }
  });

  test('a returner is offered work the model expects nothing of', () {
    final back = runSittings(
      player: decaying['matched']!,
      seed: 8,
      materials: catalog,
      sittings: schedule,
      assessment: set,
    ).slots.where((slot) => slot.sitting == returned).first;

    expect(back.chosen.guidance, GuidanceContext.unguided);
    expect(back.winner.prediction.overallP, lessThan(0.01));
    expect(back.winner.isWithinChallengeBand, isFalse);
    expect(back.winner.challengeBypass, ChallengeBypass.executionProgression);
    expect(
      back.outcome.started,
      isFalse,
      reason:
          'the first thing back is unguided work admitted by a bypass rather '
          'than by the band, and the recovery it opens is what supplies the '
          'notes the model no longer believes are there',
    );
  });

  test('the model forgets faster than any of these people do', () {
    const gaps = [2, 14, 60];
    AssessmentReading arrivalAfter(SyntheticPlayer player, int gap) =>
        arrivalAt(
          runSittings(
            player: player,
            seed: 8,
            materials: catalog,
            sittings: sittingsOnDays([0, 1, 2, 3, 3 + gap], slots: 20),
            assessment: set,
          ),
          returned,
        );

    final believed = [for (final gap in gaps) arrivalAfter(stable, gap)];
    final forgetting = [
      for (final gap in gaps) arrivalAfter(decaying['faster']!, gap),
    ];

    expect(
      believed.map((r) => r.predictedRetrieval!),
      orderedEquals(
        [for (final r in believed) r.predictedRetrieval!]
          ..sort((a, b) => b.compareTo(a)),
      ),
      reason: 'the longer the gap the less the model expects',
    );
    expect(believed.last.predictedRetrieval, lessThan(0.001));
    expect(
      believed.last.retrieval,
      1.0,
      reason:
          'two months on, the model expects nothing of somebody who has '
          'forgotten nothing',
    );
    for (final (i, reading) in forgetting.indexed) {
      expect(
        reading.predictedRetrieval,
        lessThan(reading.retrieval),
        reason:
            'the model has decayed past even the fast forgetter at '
            '${gaps[i]} days',
      );
    }
    expect(
      forgetting.last.retrieval,
      greaterThan(0.5),
      reason:
          'decay toward the starting player floors what can be lost, so '
          'this bounds the model from one side only',
    );
  });

  test('overlapping sittings are refused rather than run backwards', () {
    expect(
      () => runSittings(
        player: stable,
        seed: 8,
        materials: catalog,
        sittings: [
          Sitting(at: _epoch, slots: 20),
          Sitting(at: _epoch.add(const Duration(minutes: 5)), slots: 20),
        ],
      ),
      throwsArgumentError,
    );
  });
}

final _epoch = DateTime.utc(2026);
