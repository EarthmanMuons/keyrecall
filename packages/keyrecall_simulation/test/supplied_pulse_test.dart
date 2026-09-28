import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// A simulated attempt reads a supplied pulse the way a measured one does, and
/// the player's response to it is the player's, not the evidence rule's.
void main() {
  final exercise = Exercise.linear(
    material: v1ScaleCatalog.first,
    hands: HandConfiguration.right,
    tempoBpm: 80,
  );
  final countIn = PresentationDelivery(tempo: TempoDelivery.complete(4));
  final metronome = PresentationDelivery(
    tempo: TempoDelivery.complete(4, continuingBeats: 12),
  );

  Outcome played(
    SyntheticPlayer player, {
    PresentationDelivery? delivery,
    int seed = 0,
  }) => player.begin().play(
    exercise,
    PythonCompatibleRandom(seed),
    delivery: delivery,
  );

  group('what a simulated outcome claims', () {
    final player = PlayerArchetypes.intermediate;

    test('follows the measured rule for every delivery', () {
      for (final tempo in [
        TempoDelivery.complete(4),
        TempoDelivery.complete(4, continuingBeats: 12),
        TempoDelivery.silent(4, continuingBeats: 12),
        TempoDelivery(
          countInBeats: 4,
          continuingBeats: 12,
          deliveredCountInBeats: 0,
          deliveredContinuingBeats: 1,
        ),
        TempoDelivery(
          countInBeats: 4,
          continuingBeats: 12,
          deliveredCountInBeats: 4,
          deliveredContinuingBeats: 0,
        ),
      ]) {
        final delivery = PresentationDelivery(tempo: tempo);

        expect(
          played(player, delivery: delivery).pulseMaintenance,
          PulseMaintenance.under(delivery),
          reason: '$tempo',
        );
      }
    });

    test('is untested under a metronome, even for an attempt never begun', () {
      final stalled = PlayerArchetypes.trueBeginner.copyWith(familiarity: 0);
      final outcomes = [
        for (var seed = 0; seed < 20; seed++)
          played(stalled, delivery: metronome, seed: seed),
      ];

      expect(outcomes.any((outcome) => !outcome.started), isTrue);
      expect(
        outcomes.map((outcome) => outcome.pulseMaintenance),
        everyElement(PulseMaintenance.notTested),
      );
    });

    test('a count-in changes nothing about an attempt without one', () {
      for (var seed = 0; seed < 10; seed++) {
        expect(
          played(player, delivery: countIn, seed: seed),
          played(player, seed: seed),
        );
      }
    });
  });

  group('a player with no pulse weakness', () {
    test('follows a metronome\'s tempo instead of its own', () {
      for (final player in [
        PlayerArchetypes.advanced,
        PlayerArchetypes.reliableSelfPaced,
      ]) {
        final held = played(player, delivery: countIn);
        final given = played(player, delivery: metronome);
        expect(
          (given.achievedTempoRatio - 1).abs(),
          lessThan((held.achievedTempoRatio - 1).abs()),
          reason: player.id,
        );
        expect(given.pulseMaintenance, PulseMaintenance.notTested);
      }
    });
  });

  test('following a click\'s tempo and being steadied by it are separate', () {
    final unresponsive = PlayerArchetypes.unsteadyPulseUnresponsive;
    final held = played(unresponsive, delivery: countIn);
    final given = played(unresponsive, delivery: metronome);

    expect(
      (given.achievedTempoRatio - 1).abs(),
      lessThan((held.achievedTempoRatio - 1).abs()),
    );
    expect(unresponsive.pulseSteadinessResponsiveness, 0);
  });

  group('a player with a weak pulse', () {
    test('is steadier with a click only when it responds to one', () {
      final responsive = PlayerArchetypes.unsteadyPulseTransfers;
      final unresponsive = PlayerArchetypes.unsteadyPulseUnresponsive;

      expect(
        played(responsive, delivery: metronome).temporalStability,
        greaterThan(played(responsive, delivery: countIn).temporalStability!),
      );
      expect(
        played(unresponsive, delivery: metronome).temporalStability,
        played(unresponsive, delivery: countIn).temporalStability,
      );
    });

    test('is never steadier with a click than its hands allow', () {
      final responsive = PlayerArchetypes.unsteadyPulseTransfers.copyWith(
        pulseSteadinessResponsiveness: 1,
      );
      final steady = PlayerArchetypes.intermediate;

      expect(
        played(responsive, delivery: metronome).temporalStability,
        played(steady, delivery: countIn).temporalStability,
      );
    });

    test('keeps what a click lent it only when it transfers', () {
      double weaknessAfterPractice(SyntheticPlayer player) {
        final playing = player.begin();
        final rng = PythonCompatibleRandom(0);
        for (var attempt = 0; attempt < 6; attempt++) {
          playing.play(exercise, rng, delivery: metronome);
        }
        return playing.pulseWeakness;
      }

      final start = PlayerArchetypes.unsteadyPulseTransfers.pulseWeakness;

      expect(
        weaknessAfterPractice(PlayerArchetypes.unsteadyPulseTransfers),
        lessThan(start),
      );
      expect(
        weaknessAfterPractice(PlayerArchetypes.unsteadyPulseRelapses),
        start,
      );
      expect(
        weaknessAfterPractice(PlayerArchetypes.unsteadyPulseUnresponsive),
        start,
      );
    });

    test('keeps nothing from a click it only heard in an assessment', () {
      final playing = PlayerArchetypes.unsteadyPulseTransfers.begin();
      playing.play(
        exercise,
        PythonCompatibleRandom(0),
        delivery: metronome,
        practising: false,
      );

      expect(
        playing.pulseWeakness,
        PlayerArchetypes.unsteadyPulseTransfers.pulseWeakness,
      );
    });

    test('slips back toward where it started across a break', () {
      final playing = PlayerArchetypes.unsteadyPulseTransfers
          .copyWith(retentionHalfLifeDays: 10)
          .begin();
      final at = DateTime.utc(2026);
      playing.restUntil(at);
      final rng = PythonCompatibleRandom(0);
      for (var attempt = 0; attempt < 6; attempt++) {
        playing.play(exercise, rng, delivery: metronome);
      }
      final practised = playing.pulseWeakness;
      playing.restUntil(at.add(const Duration(days: 10)));

      expect(playing.pulseWeakness, greaterThan(practised));
      expect(
        playing.pulseWeakness,
        lessThan(PlayerArchetypes.unsteadyPulseTransfers.pulseWeakness),
      );
    });
  });

  test('the pulse archetypes stay out of the sweep', () {
    final swept = {for (final player in PlayerArchetypes.all) player.id};

    expect(swept, isNot(contains('unsteady_pulse_transfers')));
    expect(swept, isNot(contains('unsteady_pulse_relapses')));
    expect(swept, isNot(contains('unsteady_pulse_unresponsive')));
  });

  group('the response census', () {
    final responses = {
      for (final player in PlayerArchetypes.pulseCharacterization)
        player.id: pulseResponseOf(player, exercise: exercise, seeds: 8),
    };
    double steadiness(String id, PulsePhase phase) =>
        responses[id]![phase].temporalStability;

    test('reads every supplied attempt as untested, and no other', () {
      for (final response in responses.values) {
        expect(response[PulsePhase.before].pulseTested, 1);
        expect(response[PulsePhase.supplied].pulseTested, 0);
        expect(response[PulsePhase.withdrawn].pulseTested, 1);
      }
    });

    test('separates transfer from relapse only once the click is gone', () {
      const transfers = 'unsteady_pulse_transfers';
      const relapses = 'unsteady_pulse_relapses';

      expect(
        steadiness(transfers, PulsePhase.supplied),
        closeTo(steadiness(relapses, PulsePhase.supplied), 0.05),
      );
      expect(
        steadiness(transfers, PulsePhase.withdrawn),
        greaterThan(steadiness(relapses, PulsePhase.withdrawn) + 0.05),
      );
    });
  });

  group('timing recurrence', () {
    final trajectory = runSittings(
      player: PlayerArchetypes.intermediate,
      seed: 0,
      materials: v1ScaleCatalog,
      sittings: sittingsOnDays([0, 1], slots: 6),
    );

    test('counts every unaided timing observation once', () {
      final bySitting = TimingRecurrence.of([trajectory], keyOf: (_) => null);
      final timed = trajectory.slots.where(
        (slot) =>
            slot.outcome.started && slot.outcome.pulseMaintenance.isTested,
      );

      expect(bySitting.sittings, 2);
      expect(bySitting.observations, timed.length);
      expect(bySitting.keys, 2);
    });

    test('a finer key never recurs more than a coarser one', () {
      final coarse = TimingRecurrence.of([
        trajectory,
      ], keyOf: (exercise) => exercise.conditions.hands);
      final fine = TimingRecurrence.of([trajectory], keyOf: executionContextOf);

      expect(fine.keys, greaterThanOrEqualTo(coarse.keys));
      expect(
        fine.sittingsWithAKeyAtLeast[2]!,
        lessThanOrEqualTo(coarse.sittingsWithAKeyAtLeast[2]!),
      );
    });
  });
}
