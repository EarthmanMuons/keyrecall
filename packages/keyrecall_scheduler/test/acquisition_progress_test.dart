import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

void main() {
  final material = materials.first;

  Exercise cued({HandConfiguration hands = HandConfiguration.right}) =>
      Exercise.linear(
        material: material,
        hands: hands,
        octaves: 1,
        tempoBpm: 60,
        guidance: GuidanceContext.continuouslyCued,
      );

  final parent = cued();
  final later = t0.add(const Duration(days: 3));

  group('recording', () {
    test('keeps practice apart from criterion success', () {
      final progress = const AcquisitionProgress.empty()
          .recording(
            parent: parent,
            completed: false,
            earnedProbe: false,
            at: t0,
          )
          .recording(
            parent: parent,
            completed: true,
            earnedProbe: false,
            at: t0,
          );

      final record = progress.recordFor(parent)!;
      expect(record.attempts, 2);
      expect(record.completions, 1);
      expect(record.criterionSuccesses, 0);
      expect(record.earnsParentProbe, isFalse);
    });

    test('counts criterion successes so a later rule could want two', () {
      var progress = const AcquisitionProgress.empty();
      for (final at in [t0, later]) {
        progress = progress.recording(
          parent: parent,
          completed: true,
          earnedProbe: true,
          at: at,
        );
      }

      final record = progress.recordFor(parent)!;
      expect(record.criterionSuccesses, 2);
      expect(record.lastCriterionSuccessAt, later);

      // The policy that reads it is binary today. What is recorded is not.
      expect(progress.earnsParentProbe(parent), isTrue);
    });

    test('keeps a criterion success across the break that follows it', () {
      // The reason none of this lives in SessionState. A sitting boundary must
      // not decide whether work already done still counts.
      final progress = const AcquisitionProgress.empty().recording(
        parent: parent,
        completed: true,
        earnedProbe: true,
        at: t0,
      );

      expect(progress.recordFor(parent)!.lastCriterionSuccessAt, t0);
      expect(progress.earnsParentProbe(parent), isTrue);
    });

    test('separates parents that share an execution context', () {
      final other = cued(hands: HandConfiguration.left);
      final progress = const AcquisitionProgress.empty().recording(
        parent: parent,
        completed: true,
        earnedProbe: true,
        at: t0,
      );

      expect(progress.earnsParentProbe(parent), isTrue);
      expect(progress.earnsParentProbe(other), isFalse);
      expect(progress.recordFor(other), isNull);
    });

    test('separates having earned a probe from being owed one', () {
      var progress = const AcquisitionProgress.empty().recording(
        parent: parent,
        completed: true,
        earnedProbe: true,
        at: t0,
      );
      expect(progress.probeOwed(parent), isTrue);

      progress = progress.serving(parent: parent, at: later);

      // The success stays in the history; the obligation does not. Reading the
      // first as the scheduler condition would latch acquisition off forever.
      expect(progress.earnsParentProbe(parent), isTrue);
      expect(progress.probeOwed(parent), isFalse);
    });

    test('opens the obligation again for a parent that is still stuck', () {
      final progress = const AcquisitionProgress.empty()
          .recording(parent: parent, completed: true, earnedProbe: true, at: t0)
          .serving(parent: parent, at: t0.add(const Duration(minutes: 1)))
          .recording(
            parent: parent,
            completed: true,
            earnedProbe: true,
            at: later,
          );

      expect(progress.probeOwed(parent), isTrue);
      expect(progress.recordFor(parent)!.probesServed, 1);
      expect(progress.recordFor(parent)!.criterionSuccesses, 2);
    });

    test('event order reopens an obligation at an equal timestamp', () {
      final progress = const AcquisitionProgress.empty()
          .recording(parent: parent, completed: true, earnedProbe: true, at: t0)
          .recording(parent: parent, completed: true, earnedProbe: true, at: t0)
          .serving(parent: parent, at: t0)
          .recording(
            parent: parent,
            completed: true,
            earnedProbe: true,
            at: t0,
          );
      expect(progress.recordFor(parent)!.criterionSuccessesServed, 2);
      expect(progress.probeOwed(parent), isTrue);
      expect(
        progress.serving(parent: parent, at: t0).probeOwed(parent),
        isFalse,
      );
    });

    test('refuses service for a parent with no acquisition history', () {
      expect(
        () => const AcquisitionProgress.empty().serving(parent: parent, at: t0),
        throwsArgumentError,
      );
    });

    test('refuses a criterion success that did not complete', () {
      expect(
        () => const AcquisitionProgress.empty().recording(
          parent: parent,
          completed: false,
          earnedProbe: true,
          at: t0,
        ),
        throwsArgumentError,
      );
    });
  });
}
