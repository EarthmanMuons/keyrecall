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
    final ahead = encodeSittingExport(
      export,
    ).replaceFirst('"schema_version": 1', '"schema_version": 2');

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
}
