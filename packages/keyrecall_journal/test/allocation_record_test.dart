import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

void main() {
  final policy = AllocationPolicyIdentity(
    assigned: 'allocation-k2-p60',
    effective: 'allocation-k2-p60',
  );
  AllocationObserved observed({int attempts = 3}) => AllocationObserved(
    policy: policy,
    basis: AllocationBasis(attempts: attempts, acquisitionAttempts: 1),
    evidence: AllocationEvidence(served: const ['a'], missed: const ['b', 'c']),
  );

  test('evidence is fixed when made, and names each requirement once', () {
    final served = ['r'];
    final evidence = AllocationEvidence(served: served, missed: const ['s']);
    served.add('t');

    expect(evidence.served, ['r']);
    expect(() => evidence.missed.add('t'), throwsUnsupportedError);
    expect(
      () => AllocationEvidence(served: const ['r'], missed: const ['r']),
      throwsArgumentError,
    );
    expect(
      () => AllocationEvidence(served: const [], missed: const ['s', 's']),
      throwsArgumentError,
    );
  });

  group('an allocation record', () {
    test('survives the round trip, observed or not', () {
      for (final record in [
        observed(),
        AllocationObserved(
          policy: policy,
          basis: AllocationBasis(attempts: 0, acquisitionAttempts: 0),
          evidence: AllocationEvidence(served: const [], missed: const []),
        ),
        AllocationUnobserved(AllocationGap.staleAcquisition, policy: policy),
        const AllocationUnobserved(AllocationGap.notInstrumented),
        AllocationUnobserved.legacy,
      ]) {
        expect(AllocationRecord.fromJson(record.toJson()), record);
      }
    });

    test('keeps observing nothing apart from recording nothing', () {
      final empty = AllocationObserved(
        policy: policy,
        basis: AllocationBasis(attempts: 0, acquisitionAttempts: 0),
        evidence: AllocationEvidence(served: const [], missed: const []),
      );

      expect(
        AllocationRecord.fromJson(empty.toJson()),
        isNot(isA<AllocationUnobserved>()),
      );
      expect(
        AllocationRecord.fromJson(AllocationUnobserved.legacy.toJson()),
        isNot(isA<AllocationObserved>()),
      );
    });

    test('refuses one that is both, neither, or unattributed', () {
      final both = {
        ...observed().toJson(),
        'gap': AllocationGap.notInstrumented.id,
      };
      final neither = observed().toJson()..remove('evidence');
      final unattributed = observed().toJson()
        ..['assigned_policy'] = null
        ..['effective_policy'] = null;
      final halfAttributed = observed().toJson()..['effective_policy'] = null;
      final unknownGap = AllocationUnobserved.legacy.toJson()..['gap'] = 'lost';
      final repeated = observed().toJson()
        ..['evidence'] = {
          'served': ['a'],
          'missed': ['a'],
        };

      for (final json in [
        both,
        neither,
        unattributed,
        halfAttributed,
        unknownGap,
        repeated,
      ]) {
        expect(
          () => AllocationRecord.fromJson(json),
          throwsA(isA<JournalFormatException>()),
          reason: '$json',
        );
      }
    });
  });

  group('an acquisition attempt', () {
    final parent = Exercise.linear(
      material: TechnicalMaterial('C', ScaleForm.major),
      hands: HandConfiguration.right,
      octaves: 1,
      direction: ExerciseDirection.up,
      tempoBpm: 60,
      guidance: GuidanceContext.continuouslyCued,
    );
    final t0 = DateTime.utc(2026, 9, 9, 10);
    AcquisitionAttemptRecord recordAt(
      int sequence, {
      int? attemptsBefore,
      AllocationRecord allocation = const AllocationUnobserved(
        AllocationGap.notInstrumented,
      ),
      int schemaVersion = acquisitionSchemaVersion,
    }) => AcquisitionAttemptRecord(
      journalSequence: sequence,
      identity: AttemptIdentity(
        profileId: 'abc12345',
        attemptId: 'acq-$sequence',
        sessionId: 'session-1',
        indexInSession: 0,
        occurredAt: t0,
      ),
      attemptsBefore: attemptsBefore,
      allocation: allocation,
      scope: DecisionScope(
        goalId: 'GENERAL_FLUENCY',
        curriculumId: 'general',
        curriculumVersion: '1',
      ),
      task: AcquisitionTask.unmeteredTraversal(parent),
      started: true,
      completion: AcquisitionCompletion.completedCleanly,
      repairs: 0,
      repeats: 0,
      intrusions: 0,
      earnedProbe: false,
      sequence: CriterionVerdict.notMet,
      continuity: CriterionVerdict.unavailable,
      gaps: const [],
      schemaVersion: schemaVersion,
    );
    AcquisitionJournal emptyLog() => AcquisitionJournal(
      AcquisitionJournalHeader(profileId: 'abc12345', createdAt: t0),
    );

    test('carries its place, scope, and allocation through the round trip', () {
      final record = recordAt(0, attemptsBefore: 3, allocation: observed());
      final read = AcquisitionAttemptRecord.fromJson(record.toJson());

      expect(read.attemptsBefore, 3);
      expect(read.scope, record.scope);
      expect(read.allocation, observed());
    });

    test('written before version 11, has no place and reads as legacy', () {
      final json = recordAt(
        0,
        attemptsBefore: 3,
        allocation: observed(),
      ).toJson()..['schema_version'] = 10;
      final read = AcquisitionAttemptRecord.fromJson(json);

      expect(read.attemptsBefore, isNull);
      expect(read.scope, isNull);
      expect(read.allocation, AllocationUnobserved.legacy);
    });

    test('places evidence after the attempts its counters read', () {
      expect(
        () => recordAt(0, attemptsBefore: 2, allocation: observed()),
        throwsArgumentError,
      );
      expect(() => recordAt(0, allocation: observed()), throwsArgumentError);
    });

    test('the log counts its attempts and reads them from any position', () {
      final log = emptyLog()
        ..append(recordAt(0, attemptsBefore: 1))
        ..append(recordAt(1, attemptsBefore: 2))
        ..append(recordAt(2, attemptsBefore: 2));

      expect(log.attemptCount, 3);
      expect(log.attemptsFrom(1), [log.attempts[1], log.attempts[2]]);
      expect(log.attemptsFrom(3), isEmpty);
      expect(() => log.attempts.add(recordAt(3)), throwsUnsupportedError);
    });

    test('is never placed before an earlier acquisition attempt', () {
      final log = emptyLog()..append(recordAt(0, attemptsBefore: 3));

      expect(log.append(recordAt(1)), isTrue);
      expect(log.append(recordAt(2, attemptsBefore: 3)), isTrue);
      expect(
        () => log.append(recordAt(3, attemptsBefore: 2)),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });
}
