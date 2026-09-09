import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);

  Exercise cued({HandConfiguration hands = HandConfiguration.right}) =>
      Exercise.linear(
        material: material,
        hands: hands,
        octaves: 1,
        direction: ExerciseDirection.up,
        tempoBpm: 60,
        guidance: GuidanceContext.continuouslyCued,
      );

  final parent = cued();
  final other = cued(hands: HandConfiguration.left);
  final t0 = DateTime.utc(2026, 9, 9, 10);
  final later = t0.add(const Duration(days: 2));

  AcquisitionProgress progressWith() => const AcquisitionProgress.empty()
      .recording(parent: parent, completed: true, earnedProbe: false, at: t0)
      .recording(parent: parent, completed: true, earnedProbe: true, at: later)
      .recording(parent: other, completed: false, earnedProbe: false, at: t0);

  group('a round trip', () {
    test('preserves every count and both clocks', () {
      final decoded = decodeAcquisitionProgress(
        encodeAcquisitionProgress(progressWith()),
      );

      expect(decoded.byParent.keys.toSet(), {parent, other});
      final record = decoded.recordFor(parent)!;
      expect(record.attempts, 2);
      expect(record.completions, 2);
      expect(record.criterionSuccesses, 1);
      expect(record.lastAttemptAt, later);
      expect(record.lastCriterionSuccessAt, later);
      expect(decoded.recordFor(other)!.lastCriterionSuccessAt, isNull);
    });

    test('encodes the same progress identically twice', () {
      // Ordered by content rather than by insertion, so the same history
      // recorded in a different sequence hashes the same.
      final forwards = const AcquisitionProgress.empty()
          .recording(
            parent: parent,
            completed: true,
            earnedProbe: false,
            at: t0,
          )
          .recording(
            parent: other,
            completed: true,
            earnedProbe: false,
            at: t0,
          );
      final backwards = const AcquisitionProgress.empty()
          .recording(parent: other, completed: true, earnedProbe: false, at: t0)
          .recording(
            parent: parent,
            completed: true,
            earnedProbe: false,
            at: t0,
          );

      expect(
        canonicalJson(encodeAcquisitionProgress(forwards)),
        canonicalJson(encodeAcquisitionProgress(backwards)),
      );
    });
  });

  group('a record that cannot be true', () {
    test('is refused rather than read', () {
      final encoded = encodeAcquisitionProgress(progressWith());
      final tampered = [
        {...encoded.first, 'criterion_successes': 99},
        ...encoded.skip(1),
      ];

      expect(
        () => decodeAcquisitionProgress(tampered),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('is refused when the counts and the clock disagree', () {
      final encoded = encodeAcquisitionProgress(progressWith());
      final tampered = [
        for (final record in encoded)
          {...record, 'last_criterion_success_at': null},
      ];

      expect(
        () => decodeAcquisitionProgress(tampered),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });
}
