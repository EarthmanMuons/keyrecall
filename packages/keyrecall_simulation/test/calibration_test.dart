import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Whether a fit recovers a player it was not told about.
///
/// Ground truth is synthetic on purpose. A fit against a device sitting cannot
/// be checked, because nobody knows the answer; a fit against a known player
/// can, and an estimator that cannot recover a player it generated has no
/// business being pointed at a person.
void main() {
  // The exercises a real sitting asked for, taken from a scheduler run so the
  // fit answers the same questions a person answered.
  final presented = [
    for (final slot in runTrajectory(
      player: PlayerArchetypes.intermediate,
      seed: 5,
      materials: v1ScaleCatalog,
      slots: 60,
    ).slots)
      ReplayPresentation(slot.chosen, seenBefore: true),
  ];

  SittingProfile sittingOf(SyntheticPlayer player) =>
      profileOf(replay(player, presented, seed: 11));

  List<PlayerFit> fitOf(
    SyntheticPlayer truth, {
    Set<PlayerParameter> vary = firstSitting,
  }) => fitPlayers(
    target: sittingOf(truth),
    presented: presented,
    vary: vary,
    samples: 600,
    keep: 20,
    seed: 3,
  );

  test('replay carries observed familiarity without reconstructing it', () {
    final exercise = presented.first.exercise;
    final trials = [
      ReplayPresentation(exercise, seenBefore: true),
      ReplayPresentation(exercise, seenBefore: false),
      ReplayPresentation(exercise),
    ];
    final observed = replay(PlayerArchetypes.advanced, trials);
    expect(observed.map((a) => a.seenBefore), [true, false, null]);
    expect(observed.map(ReplayPresentation.observed).map((a) => a.seenBefore), [
      true,
      false,
      null,
    ]);
  });

  test('a profile reads what a sitting did, not what it was asked', () {
    final profile = sittingOf(PlayerArchetypes.tempoNoncompliant);

    // Plays at its own pace whatever the count-in says, so the achieved tempo
    // is its own and the ratio is nothing like one.
    expect(profile.tempoRatio, greaterThan(1.2));
    expect(profile.achievedTempo[HandConfiguration.right], greaterThan(100));
    expect(profile.attempts, presented.length);
  });

  test('an ensemble recovers a natural tempo it was not given', () {
    final truth = PlayerArchetypes.developing;
    final ensemble = fitOf(truth);
    final tempo = rangeOf(ensemble, (player) => player.naturalTempoRightBpm);

    expect(
      tempo.median,
      closeTo(truth.naturalTempoRightBpm, truth.naturalTempoRightBpm * 0.3),
      reason: 'fitted ${tempo.low} to ${tempo.high}',
    );
  });

  test('an ensemble recovers a learner who ignores the count-in', () {
    final ensemble = fitOf(PlayerArchetypes.tempoNoncompliant);
    final compliance = rangeOf(ensemble, (player) => player.tempoCompliance);

    expect(compliance.median, lessThan(0.5));
  });

  test('holding compliance reports a natural tempo it cannot see', () {
    // The played tempo is a blend of the requested one and the natural one, so
    // fixing one of them makes the fit answer about the fixture rather than
    // the player. Pinned because it is the reason compliance is fitted with
    // the initial conditions rather than after them.
    final truth = PlayerArchetypes.developing;
    final held = rangeOf(
      fitOf(truth, vary: initialConditions),
      (player) => player.naturalTempoRightBpm,
    );
    final joint = rangeOf(
      fitOf(truth),
      (player) => player.naturalTempoRightBpm,
    );

    expect(
      (joint.median - truth.naturalTempoRightBpm).abs(),
      lessThan((held.median - truth.naturalTempoRightBpm).abs()),
    );
  });

  test('the ensemble is wide enough to say it is an ensemble', () {
    // Several parameter sets reproduce one sitting, and a point estimate would
    // claim a precision this cannot carry.
    final tempo = rangeOf(
      fitOf(PlayerArchetypes.developing),
      (player) => player.naturalTempoRightBpm,
    );

    expect(tempo.high - tempo.low, greaterThan(tempo.median * 0.4));
  });

  test('an ensemble recovers which hand is the weaker one', () {
    final ensemble = fitOf(PlayerArchetypes.unevenHands);
    final right = rangeOf(ensemble, (player) => player.rightHandAbility);
    final left = rangeOf(ensemble, (player) => player.leftHandAbility);

    expect(right.median, greaterThan(left.median));
  });

  test('a fit only moves the parameters it was asked to', () {
    final ensemble = fitOf(PlayerArchetypes.developing, vary: behavioralNoise);

    for (final fit in ensemble) {
      expect(fit.player.naturalTempoRightBpm, 100);
      expect(fit.player.rightHandAbility, 0.5);
    }
  });

  test('the closest candidate is closer than a wrong one', () {
    final target = sittingOf(PlayerArchetypes.advanced);
    final ensemble = fitOf(PlayerArchetypes.advanced);

    expect(
      ensemble.first.distance,
      lessThan(
        profileDistance(target, sittingOf(PlayerArchetypes.trueBeginner)),
      ),
    );
  });

  test('a distance skips what one sitting cannot answer', () {
    final singleHanded = [
      for (final exercise in presented)
        if (exercise.exercise.conditions.hands != HandConfiguration.together)
          exercise,
    ];
    final profile = profileOf(
      replay(PlayerArchetypes.developing, singleHanded, seed: 2),
    );

    expect(profile.handsTogetherPenalty, isNull);
    expect(profileDistance(profile, profile), 0);
  });

  group('what the report is willing to claim', () {
    final singleHanded = [
      for (final exercise in presented)
        if (exercise.exercise.conditions.hands != HandConfiguration.together)
          exercise,
    ];

    test('a sitting with no coordination work says so', () {
      final observed = profileOf(
        replay(PlayerArchetypes.unevenHands, singleHanded, seed: 11),
      );
      final answers = identifiabilityOf(
        ensemble: fitPlayers(
          target: observed,
          presented: singleHanded,
          vary: firstSitting,
          samples: 200,
          seed: 3,
        ),
        observed: observed,
        vary: firstSitting,
      );

      expect(
        answers[PlayerParameter.handsTogetherAbility],
        Identifiability.unobserved,
      );
    });

    test('one sitting never claims a learning rate', () {
      const vary = {...firstSitting, PlayerParameter.learningRate};
      final observed = profileOf(
        replay(PlayerArchetypes.developing, presented, seed: 11),
      );
      final answers = identifiabilityOf(
        ensemble: fitPlayers(
          target: observed,
          presented: presented,
          vary: vary,
          samples: 200,
          seed: 3,
        ),
        observed: observed,
        vary: vary,
      );

      expect(
        answers[PlayerParameter.learningRate],
        Identifiability.needsMoreSittings,
      );
    });

    test('familiarity needs provenance, not position in the sitting', () {
      final withoutProvenance = [
        for (final attempt in replay(
          PlayerArchetypes.developing,
          presented,
          seed: 11,
        ))
          AttemptObservation(attempt.exercise, attempt.outcome),
      ];
      final observed = profileOf(withoutProvenance);

      expect(observed.familiarMotor, isNull);
      expect(observed.unfamiliarMotor, isNull);
      expect(
        identifiabilityOf(
          ensemble: fitPlayers(
            target: observed,
            presented: presented,
            vary: firstSitting,
            samples: 200,
            seed: 3,
          ),
          observed: observed,
          vary: firstSitting,
        )[PlayerParameter.familiarity],
        Identifiability.unobserved,
      );
    });

    test('a hand asked one tempo cannot answer about compliance', () {
      final single = [
        for (var i = 0; i < 12; i++)
          ReplayPresentation(
            Exercise.linear(
              material: TechnicalMaterial('C', ScaleForm.major),
              hands: HandConfiguration.right,
              tempoBpm: 60,
            ),
          ),
      ];
      final observed = profileOf(
        replay(PlayerArchetypes.developing, single, seed: 4),
      );

      expect(observed.tempoSlope, isEmpty);
    });

    test('a report prints no interval for what it could not see', () {
      final observed = profileOf(
        replay(PlayerArchetypes.unevenHands, singleHanded, seed: 11),
      );
      final report = calibrationReport(
        ensemble: fitPlayers(
          target: observed,
          presented: singleHanded,
          vary: firstSitting,
          samples: 200,
          seed: 3,
        ),
        observed: observed,
        vary: firstSitting,
      );

      expect(report, contains('handsTogetherAbility'));
      expect(
        report
            .split('\n')
            .firstWhere((line) => line.contains('handsTogetherAbility')),
        contains('not observed'),
      );
    });
  });

  test('an exported sitting profiles the same as the run it came from', () {
    // One implementation of the profile semantics: a device sitting and a
    // synthetic one go through the same code, so a difference between them is
    // a difference in the playing.
    final played = replay(PlayerArchetypes.developing, presented, seed: 11);
    final export = SittingExport(
      profileId: 'profile-1',
      sittingId: 'session-1',
      startedAt: DateTime.utc(2026),
      attempts: [
        for (final (index, attempt) in played.indexed)
          ExportedAttempt(
            index: index,
            exercise: attempt.exercise,
            outcome: attempt.outcome,
            familiarity: attempt.seenBefore!
                ? MaterialFamiliarity.familiar
                : MaterialFamiliarity.unfamiliar,
          ),
      ],
    );
    final imported = observationsOf(
      decodeSittingExport(encodeSittingExport(export)),
    );

    expect(profileDistance(profileOf(imported), profileOf(played)), 0);
  });

  test('an export that knows nothing about familiarity says so', () {
    final played = replay(PlayerArchetypes.developing, presented, seed: 11);
    final export = SittingExport(
      profileId: 'profile-1',
      sittingId: 'session-1',
      startedAt: DateTime.utc(2026),
      attempts: [
        for (final (index, attempt) in played.indexed)
          ExportedAttempt(
            index: index,
            exercise: attempt.exercise,
            outcome: attempt.outcome,
            familiarity: MaterialFamiliarity.unknown,
          ),
      ],
    );

    expect(profileOf(observationsOf(export)).familiarMotor, isNull);
  });

  group('a reliable, self-paced player', () {
    final truth = PlayerArchetypes.reliableSelfPaced;

    test('completes nearly everything and plays its own pace', () {
      final profile = sittingOf(truth);

      expect(profile.completionRate, greaterThan(0.9));
      expect(profile.motor[HandConfiguration.right], greaterThan(0.85));
      expect(profile.tempoSlope[HandConfiguration.right], lessThan(0.6));
    });

    test('the weaker archetypes stay unreliable beside it', () {
      // The point is expressiveness, not making everybody clean: a family that
      // can describe this learner and no longer describe a struggling one has
      // traded one blind spot for another.
      for (final other in [
        PlayerArchetypes.trueBeginner,
        PlayerArchetypes.developing,
      ]) {
        expect(
          sittingOf(other).completionRate,
          lessThan(sittingOf(truth).completionRate - 0.2),
          reason: other.id,
        );
      }
    });

    test('a fit recovers that it does not follow the count-in', () {
      final compliance = rangeOf(
        fitOf(truth),
        (player) => player.tempoCompliance,
      );

      expect(compliance.median, lessThan(0.7));
    });

    test('a fit puts its ability above a struggling learner\'s', () {
      final reliable = rangeOf(fitOf(truth), (p) => p.rightHandAbility);
      final struggling = rangeOf(
        fitOf(PlayerArchetypes.developing),
        (p) => p.rightHandAbility,
      );

      expect(reliable.median, greaterThan(struggling.median));
    });
  });
}
