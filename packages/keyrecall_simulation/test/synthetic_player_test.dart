import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// The player model, checked on the things the archetypes depend on.
void main() {
  final material = v1ScaleCatalog.first;

  Exercise at(double tempoBpm, {HandConfiguration? hands}) => Exercise.linear(
    material: material,
    hands: hands ?? HandConfiguration.right,
    octaves: 1,
    tempoBpm: tempoBpm,
  );

  group('performed tempo', () {
    test('a follower plays what was asked for', () {
      final playing = PlayerArchetypes.trueBeginner
          .copyWith(tempoCompliance: 1.0)
          .begin();

      expect(playing.performedTempoFor(at(96)), closeTo(96, 0.001));
    });

    test('somebody who ignores it plays their own pace', () {
      final playing = PlayerArchetypes.tempoNoncompliant.begin();

      expect(
        playing.performedTempoFor(at(60)),
        closeTo(PlayerArchetypes.tempoNoncompliant.naturalTempoRightBpm, 0.001),
      );
      expect(
        playing.performedTempoFor(at(200)),
        closeTo(PlayerArchetypes.tempoNoncompliant.naturalTempoRightBpm, 0.001),
      );
    });

    test('and the ratio is what the app would see', () {
      // The device session, in one number: asked for sixty, played at a
      // hundred and twenty-six, reported as a ratio just over two.
      final playing = PlayerArchetypes.fastButPlacedLow
          .copyWith(tempoCompliance: 0)
          .begin();
      final outcome = playing.play(at(60), PythonCompatibleRandom(0));

      expect(outcome.achievedTempoRatio, closeTo(126 / 60, 0.001));
    });

    test('the existing profile generator cannot express that at all', () {
      // Why this model exists. Sampled achieved tempo is a quality score, so
      // no learner it can build ever plays faster than they were asked to,
      // and every tempo defect the device found lived in that gap.
      final rng = PythonCompatibleRandom(0);
      final profile = SyntheticProfile.advanced.build(
        start: DateTime.utc(2026),
      );
      for (var i = 0; i < 50; i++) {
        final outcome = sampleOutcome(
          profile: profile,
          exercise: at(60),
          at: DateTime.utc(2026),
          rng: rng,
        );
        expect(outcome.achievedTempoRatio, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('hands', () {
    test('each has its own pace, and together takes the slower', () {
      final playing = PlayerArchetypes.unevenHands.begin();

      expect(
        playing.naturalTempoFor(HandConfiguration.together),
        playing.naturalTempoFor(HandConfiguration.left),
      );
    });

    test('coordination is reported only when both hands played', () {
      final rng = PythonCompatibleRandom(1);
      final playing = PlayerArchetypes.intermediate.begin();

      expect(playing.play(at(96), rng).coordination, isNull);
      expect(
        playing
            .play(at(96, hands: HandConfiguration.together), rng)
            .coordination,
        isNotNull,
      );
    });

    test('a coordination-limited player is worse together than apart', () {
      final rng = PythonCompatibleRandom(2);
      final playing = PlayerArchetypes.coordinationLimited.begin();
      double mean(HandConfiguration hands) {
        var total = 0.0;
        for (var i = 0; i < 40; i++) {
          total += playing.play(at(96, hands: hands), rng).motorScore!;
        }
        return total / 40;
      }

      expect(
        mean(HandConfiguration.together),
        lessThan(mean(HandConfiguration.right)),
      );
    });
  });

  test('a run is reproducible from its archetype and seed', () {
    List<String> shapeOf(int seed) => [
      for (final slot in runTrajectory(
        player: PlayerArchetypes.developing,
        seed: seed,
        materials: v1ScaleCatalog,
        slots: 25,
      ).slots)
        '${slot.chosen.material.materialId}/${slot.chosen.conditions.hands.id}/'
            '${slot.chosen.conditions.tempoBpm}/${slot.outcome.completed}',
    ];

    expect(shapeOf(7), shapeOf(7));
    expect(shapeOf(7), isNot(shapeOf(8)));
  });

  test('no attempt carries timing measurement could not read', () {
    // Measurement reads continuity and steadiness from waits, and a traversal
    // with too few of them establishes neither however well it was played.
    final candidates = generateCandidates(InstrumentProfile(), [
      ...v1ScaleCatalog,
      ...allRootPositionArpeggios,
    ]);
    final shapes = {
      for (final exercise in candidates)
        (exercise.material.familyId, exercise.conditions): exercise,
    }.values;
    final player = PlayerArchetypes.advanced.begin();
    final profile = SyntheticProfile.advanced.build(start: DateTime.utc(2026));
    final rng = PythonCompatibleRandom(0);
    var untimed = 0;
    for (final exercise in shapes) {
      final capacity = TimingCapacity.of(exercise);
      if (!capacity.supportsMotorScore) untimed++;
      for (final outcome in [
        player.play(exercise, rng, practising: false),
        sampleOutcome(
          profile: profile,
          exercise: exercise,
          at: DateTime.utc(2026),
          rng: rng,
          applyMemoryTransition: false,
        ),
      ]) {
        if (!outcome.started) continue;
        expect(outcome.continuity != null, capacity.supportsContinuity);
        expect(outcome.temporalStability != null, capacity.supportsSpread);
      }
    }
    expect(untimed, greaterThan(0), reason: 'some shape is too short to time');
  });
}
