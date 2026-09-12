import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);

  Exercise parentFor(HandConfiguration hands) => Exercise.linear(
    material: material,
    hands: hands,
    octaves: 1,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
    guidance: GuidanceContext.continuouslyCued,
  );

  final parent = parentFor(HandConfiguration.right);
  final task = AcquisitionTask.unmeteredTraversal(parent);

  /// The moments a crossing happens at, which the exercise already knows.
  final crossings = {
    for (final site in parent.opportunitySites)
      if (site.hand == Hand.right) site.momentIndex,
  };

  AcquisitionObservation attemptBy(SyntheticPlayer player, int seed) =>
      observeAcquisition(
        task: task,
        transcript: performAcquisition(
          state: player.begin(),
          task: task,
          rng: PythonCompatibleRandom(seed),
        ),
      );

  TransitionCensus censusOf(SyntheticPlayer player, {required int attempts}) {
    var census = TransitionCensus.of(task);
    for (var seed = 0; seed < attempts; seed++) {
      census = census.recording(attemptBy(player, seed));
    }
    return census;
  }

  group('the exercise', () {
    test('puts a crossing somewhere for a penalty to land on', () {
      // Everything below reads localization back out of observations. If the
      // domain stopped creating a site here, those tests would be measuring
      // noise and passing for the wrong reason.
      expect(crossings, isNotEmpty);
    });
  });

  group('what the player produces', () {
    test('is a transcript, so every reading takes the device path', () {
      final transcript = performAcquisition(
        state: PlayerArchetypes.advanced.begin(),
        task: task,
        rng: PythonCompatibleRandom(7),
      );

      expect(transcript, isA<PerformanceTranscript>());
      expect(transcript.isNotEmpty, isTrue);
    });

    test('repeats exactly for one seed', () {
      final first = performAcquisition(
        state: PlayerArchetypes.developing.begin(),
        task: task,
        rng: PythonCompatibleRandom(3),
      );
      final again = performAcquisition(
        state: PlayerArchetypes.developing.begin(),
        task: task,
        rng: PythonCompatibleRandom(3),
      );

      expect(again, first);
    });

    test('ignores what the player would have done about a tempo', () {
      // Nothing was asked for, so compliance has nothing to comply with and
      // sprinting has no request to abandon.
      final indifferent = PlayerArchetypes.developing.copyWith(
        id: 'indifferent',
        tempoCompliance: 0,
        sprintProbability: 1,
      );

      expect(
        performAcquisition(
          state: indifferent.begin(),
          task: task,
          rng: PythonCompatibleRandom(11),
        ),
        performAcquisition(
          state: PlayerArchetypes.developing.begin(),
          task: task,
          rng: PythonCompatibleRandom(11),
        ),
      );
    });

    test('refuses a two-hand parent', () {
      expect(
        () => performAcquisition(
          state: PlayerArchetypes.advanced.begin(),
          task: AcquisitionTask.unmeteredTraversal(
            parentFor(HandConfiguration.together),
          ),
          rng: PythonCompatibleRandom(1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('shared execution difficulty', () {
    test('the crossing cost also lowers the ordinary parent performance', () {
      final limited = PlayerArchetypes.crossingLimited
          .copyWith(noise: 0, familiarity: 1)
          .begin();
      final free = PlayerArchetypes.crossingLimited
          .copyWith(noise: 0, familiarity: 1, opportunityPenalty: 0)
          .begin();
      final difficult = limited.play(
        parent,
        PythonCompatibleRandom(3),
        practising: false,
      );
      final easy = free.play(
        parent,
        PythonCompatibleRandom(3),
        practising: false,
      );
      expect(difficult.motorScore, lessThan(easy.motorScore!));
      expect(
        limited.executionEffortFor(parent, momentIndex: crossings.first),
        lessThan(limited.executionEffortFor(parent, momentIndex: 0)),
      );
    });

    test('acquisition practice improves a held-out ordinary parent', () {
      final player = PlayerArchetypes.crossingLimited.copyWith(
        noise: 0,
        familiarity: 1,
        learningRate: 0.05,
      );
      final trained = player.begin();
      final control = player.begin();
      final otherHandBefore = trained.abilityOf(
        HandConfiguration.left,
        material.familyId,
      );
      final otherFamilyBefore = trained.abilityOf(
        HandConfiguration.right,
        TechnicalMaterial.arpeggioFamilyId,
      );
      for (var seed = 0; seed < 100; seed++) {
        performAcquisition(
          state: trained,
          task: task,
          rng: PythonCompatibleRandom(seed),
          practising: true,
        );
        performAcquisition(
          state: control,
          task: task,
          rng: PythonCompatibleRandom(seed),
        );
      }
      final trainedAbility = trained.abilityOf(
        HandConfiguration.right,
        material.familyId,
      );
      final after = trained.play(
        parent,
        PythonCompatibleRandom(9),
        practising: false,
      );
      final withoutPractice = control.play(
        parent,
        PythonCompatibleRandom(9),
        practising: false,
      );
      expect(after.motorScore, greaterThan(withoutPractice.motorScore!));
      expect(
        trained.abilityOf(HandConfiguration.right, material.familyId),
        trainedAbility,
      );
      expect(
        control.abilityOf(HandConfiguration.right, material.familyId),
        player.begin().abilityOf(HandConfiguration.right, material.familyId),
      );
      expect(
        trained.abilityOf(HandConfiguration.left, material.familyId),
        otherHandBefore,
      );
      expect(
        trained.abilityOf(
          HandConfiguration.right,
          TechnicalMaterial.arpeggioFamilyId,
        ),
        otherFamilyBefore,
      );
    });
  });

  group('a capable player', () {
    test('mostly earns the parent probe', () {
      final earned = [
        for (var seed = 0; seed < 40; seed++)
          if (attemptBy(PlayerArchetypes.advanced, seed).earnsParentProbe) seed,
      ];

      expect(earned.length, greaterThan(30));
    });
  });

  group('a player whose thumb will not go under', () {
    test('stalls where the crossing is, not everywhere', () {
      final census = censusOf(PlayerArchetypes.crossingLimited, attempts: 40);
      final repeated = census.stalledAtLeast(5);

      expect(repeated, isNotEmpty);
      for (final transition in repeated) {
        expect(crossings, contains(transition.toPosition));
      }
    });

    test('is not a player who simply plays worse', () {
      // The same person without the localized cost. Their playing is uneven,
      // and the unevenness has no address, so nothing accumulates anywhere.
      final census = censusOf(PlayerArchetypes.developing, attempts: 40);

      expect(census.stalledAtLeast(5), isEmpty);
    });

    test('still gets through it often enough to be practising', () {
      final completions = [
        for (var seed = 0; seed < 40; seed++)
          attemptBy(PlayerArchetypes.crossingLimited, seed).completion,
      ];

      // The point of the task. A learner who cannot hold 60 BPM through a
      // crossing can still produce the sequence when time is not the
      // constraint, and the observation says both things at once.
      expect(
        completions.where((completion) => completion.isComplete),
        isNotEmpty,
      );
      expect(
        completions.where(
          (completion) => completion == AcquisitionCompletion.notCompleted,
        ),
        isNotEmpty,
      );
    });
  });
}
