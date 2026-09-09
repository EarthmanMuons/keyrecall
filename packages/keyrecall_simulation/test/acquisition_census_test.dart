import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final t0 = DateTime.utc(2026);
  final materials = v1ScaleCatalog.take(3).toList();

  Future<AcquisitionCensus> census(
    SyntheticPlayer player, {
    int seed = 1,
    int slots = 40,
  }) async {
    final profile = Profile(
      id: 'census-${player.id}',
      displayName: player.id,
      createdAt: t0,
      placement: player.placement,
    );
    final session = await PracticeSession.open(
      store: InMemoryPracticeStore(createdAt: t0),
      profile: profile,
      materials: materials,
      sessionId: 'sitting-${player.id}',
      nextId: _countingIds(player.id),
    );
    return censusOfSitting(
      session: session,
      player: player,
      seed: seed,
      slots: slots,
    );
  }

  group('what supported work does to a sitting', () {
    test('a beginner reaches it and is not trapped in it', () async {
      final beginner = await census(PlayerArchetypes.trueBeginner);

      // Descriptive, not a target. What it has to show is that the path is
      // reachable at all and that the sitting is still mostly ordinary work.
      expect(beginner.everCheckedFloor, isTrue);
      expect(beginner.everAcquired, isTrue);
      expect(beginner.ordinaryAttempts, greaterThan(0));
      print(
        'trueBeginner share=${beginner.acquisitionShare} '
        'run=${beginner.longestAcquisitionRun} '
        'probes=${beginner.probesServed} '
        'completions=${beginner.completions} '
        'toFloor=${beginner.slotsToFloorCheck} '
        'toAcq=${beginner.slotsToAcquisition} '
        'toProbe=${beginner.slotsToProbe} '
        'diverted=${beginner.divertedFrom}',
      );
    });

    test('never takes two opportunities running', () async {
      // Supported work is an intervention inside ordinary practice, not an
      // alternative to it, so the thing after one is ordinary work.
      final beginner = await census(PlayerArchetypes.trueBeginner);

      expect(beginner.longestAcquisitionRun, lessThanOrEqualTo(1));
      expect(beginner.sameParentGaps, everyElement(greaterThan(1)));
      print('sameParentGaps=${beginner.sameParentGaps}');
    });

    test(
      'a failed parent waits for new evidence rather than its turn',
      () async {
        // Rotation among simultaneously stuck floors used to fill a sitting
        // while never repeating a parent twice running. What ends a set-aside is
        // ordinary evidence, so recurrences are spaced by that rather than by
        // how much other work happened.
        final beginner = await census(PlayerArchetypes.trueBeginner);

        expect(beginner.sameParentGaps.any((gap) => gap > 5), isTrue);
        print(
          'run=${beginner.longestAcquisitionRun} '
          'share=${beginner.acquisitionShare.toStringAsFixed(3)}',
        );
      },
    );

    test('an advanced learner is left alone', () async {
      // Supported work is for a learner who cannot manage the floor. Somebody
      // who arrived able to play should meet it rarely or never.
      final advanced = await census(PlayerArchetypes.advanced);

      expect(advanced.acquisitionAttempts, lessThanOrEqualTo(1));
      print('advanced $advanced');
    });

    test('every archetype produces a readable census', () async {
      // Breadth rather than assertion: the point is that none of them crashes,
      // deadlocks the loop, or spends a whole sitting on scaffolds.
      for (final player in PlayerArchetypes.all) {
        final result = await census(player, slots: 24);
        expect(result.opportunities, 24, reason: player.id);
        print(
          '${player.id} share=${result.acquisitionShare.toStringAsFixed(2)} '
          'run=${result.longestAcquisitionRun} floor=${result.floorAttempts} '
          'probes=${result.probesServed}',
        );
      }
    });

    test('what it displaces is recorded, or nothing was available', () async {
      final beginner = await census(PlayerArchetypes.trueBeginner);

      final diverted = beginner.divertedFrom.values.fold(0, (a, b) => a + b);
      expect(diverted, lessThanOrEqualTo(beginner.acquisitionAttempts));
    });
  });

  group('the distinction the floor check exists for', () {
    /// A learner who cannot retrieve but can execute: the previewed rung fails
    /// on memory, and the cued floor is managed straight away.
    final cuedIsFine = PlayerArchetypes.developing.copyWith(
      id: 'cued_is_fine',
      familiarity: 0,
      rightHandAbility: 4,
      leftHandAbility: 4,
      noise: 0,
    );

    /// The same learner who cannot execute either.
    final nothingWorks = cuedIsFine.copyWith(
      id: 'nothing_works',
      rightHandAbility: -6,
      leftHandAbility: -6,
    );

    test('managing the floor keeps a learner out of supported work', () async {
      final easy = await census(cuedIsFine);

      // The floor was asked for, which is the check doing its job, and the
      // answer was yes, which is the whole reason acquisition is not offered.
      expect(easy.everCheckedFloor, isTrue);
      expect(easy.acquisitionAttempts, 0);
      printOnFailure(easy.toString());
    });

    test('failing the floor as well is what reaches it', () async {
      final stuck = await census(nothingWorks);

      expect(stuck.everCheckedFloor, isTrue);
      expect(stuck.everAcquired, isTrue);
      printOnFailure(stuck.toString());
    });
  });
}

/// Reproducible ids, so a census is a fixture rather than an anecdote.
IdGenerator _countingIds(String prefix) {
  var next = 0;
  return () => '$prefix-${next++}';
}
