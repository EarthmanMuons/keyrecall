import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

/// The export a device carries off, and what reading it back may assume.
void main() {
  final exercise = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    tempoBpm: 72,
  );
  final outcome = Outcome(
    started: true,
    retrieval: FactualRetrieval.succeeded,
    completed: true,
    materialRetrieval: 0.9,
    pitchIntegrity: 0.95,
    continuity: 0.8,
    temporalStability: 0.7,
    achievedTempoRatio: 1.1,
    topologyAccuracy: 0.9,
  );
  final export = SittingExport(
    profileId: 'profile-1',
    sittingId: 'session-1',
    startedAt: DateTime.utc(2026, 9, 7, 10),
    attempts: [
      ExportedAttempt(
        index: 0,
        exercise: exercise,
        outcome: outcome,
        familiarity: MaterialFamiliarity.unknown,
      ),
      ExportedAttempt(
        index: 1,
        exercise: exercise,
        outcome: outcome,
        familiarity: MaterialFamiliarity.familiar,
      ),
    ],
  );

  test('a sitting survives the round trip', () {
    final read = decodeSittingExport(encodeSittingExport(export));

    expect(read.profileId, 'profile-1');
    expect(read.sittingId, 'session-1');
    expect(read.startedAt, export.startedAt);
    expect(read.attempts.length, 2);
    expect(read.attempts.first.exercise, exercise);
    expect(read.attempts.first.outcome.achievedTempoRatio, 1.1);
  });

  test('familiarity keeps its three answers apart', () {
    final read = decodeSittingExport(encodeSittingExport(export));

    expect(read.attempts.first.familiarity, MaterialFamiliarity.unknown);
    expect(read.attempts.last.familiarity, MaterialFamiliarity.familiar);
  });

  test('a version it cannot read is refused, not guessed at', () {
    final ahead = encodeSittingExport(export).replaceFirst(
      '"schema_version": $sittingExportSchemaVersion',
      '"schema_version": 99',
    );

    expect(
      () => decodeSittingExport(ahead),
      throwsA(isA<JournalFormatException>()),
    );
  });

  test('an unknown familiarity is refused', () {
    final wrong = encodeSittingExport(
      export,
    ).replaceFirst('"familiarity": "unknown"', '"familiarity": "vaguely"');

    expect(
      () => decodeSittingExport(wrong),
      throwsA(isA<JournalFormatException>()),
    );
  });

  group('supported work in an export', () {
    final parent = Exercise.linear(
      material: TechnicalMaterial('C', ScaleForm.major),
      hands: HandConfiguration.right,
      octaves: 1,
      direction: ExerciseDirection.up,
      tempoBpm: 60,
      guidance: GuidanceContext.continuouslyCued,
    );
    final record = AcquisitionAttemptRecord(
      journalSequence: 0,
      identity: AttemptIdentity(
        profileId: 'abc12345',
        attemptId: 'acq-0',
        sessionId: 'sitting-1',
        indexInSession: 0,
        occurredAt: DateTime.utc(2026, 9, 9),
      ),
      task: AcquisitionTask.unmeteredTraversal(parent),
      started: true,
      completion: AcquisitionCompletion.completedWithCorrections,
      repairs: 2,
      repeats: 0,
      intrusions: 2,
      earnedProbe: false,
      termination: AttemptTermination.learnerStopped,
      gaps: const [(fromPosition: 2, toPosition: 3, gapMs: 3200, ratio: 3.4)],
    );

    test('travels beside the ordinary attempts, not among them', () {
      final read = decodeSittingExport(
        encodeSittingExport(
          SittingExport(
            profileId: 'abc12345',
            sittingId: 'sitting-1',
            startedAt: DateTime.utc(2026, 9, 9),
            attempts: const [],
            acquisition: [record],
          ),
        ),
      );

      // A fit reads the ordinary attempts. Supported work is here so a device
      // sitting can be asked what an attempt actually recorded, and it must
      // never become part of what a learner is fitted from.
      expect(read.attempts, isEmpty);
      expect(read.acquisition, hasLength(1));
      final held = read.acquisition.single;
      expect(held.earnedProbe, isFalse);
      expect(held.completion, AcquisitionCompletion.completedWithCorrections);
      expect(held.repairs, 2);
      expect(held.gaps.single.gapMs, 3200);
    });

    test('an export written before it existed still reads', () {
      final current = encodeSittingExport(
        SittingExport(
          profileId: 'abc12345',
          sittingId: 'sitting-1',
          startedAt: DateTime.utc(2026, 9, 9),
          attempts: const [],
        ),
      );
      final legacy = (jsonDecode(current) as Map<String, Object?>)
        ..['schema_version'] = 1
        ..remove('acquisition');

      expect(decodeSittingExport(jsonEncode(legacy)).acquisition, isEmpty);
    });
  });
}
