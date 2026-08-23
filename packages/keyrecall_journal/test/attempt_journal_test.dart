import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/fixtures.dart';

AttemptRecord recordAt({
  required String attemptId,
  required int indexInSession,
  String sessionId = 'session-1',
}) {
  final exercise = exerciseFor(v1ScaleCatalogFirst);
  final outcome = outcomeOf();
  return AttemptRecord(
    identity: AttemptIdentity(
      profileId: testProfile.id,
      attemptId: attemptId,
      sessionId: sessionId,
      indexInSession: indexInSession,
      occurredAt: t0.plusDays(indexInSession.toDouble()),
    ),
    provenance: provenance,
    exercise: exercise,
    outcome: outcome,
    weights: evidenceWeightsFor(exercise, outcome),
    memoryUpdate: const MemoryUpdateDiagnostics(),
  );
}

void main() {
  JournalHeader header() =>
      JournalHeader(profileId: testProfile.id, createdAt: t0);

  group('append-only', () {
    test('keeps records in the order they arrived', () {
      final journal = AttemptJournal(header())
        ..append(recordAt(attemptId: 'a', indexInSession: 0))
        ..append(recordAt(attemptId: 'b', indexInSession: 1))
        ..append(recordAt(attemptId: 'c', indexInSession: 2));

      expect(journal.records.map((record) => record.identity.attemptId), [
        'a',
        'b',
        'c',
      ]);
    });

    test('re-appending the same attempt is a no-op', () {
      // An interrupted commit that gets retried must not fold the same
      // evidence in twice, which is why the attempt id is the idempotency key.
      final journal = AttemptJournal(header());
      final record = recordAt(attemptId: 'a', indexInSession: 0);

      expect(journal.append(record), isTrue);
      expect(journal.append(record), isFalse);
      expect(
        journal.append(recordAt(attemptId: 'a', indexInSession: 0)),
        isFalse,
      );
      expect(journal.length, 1);
    });

    test('rejects an index that does not advance within its session', () {
      final journal = AttemptJournal(header())
        ..append(recordAt(attemptId: 'a', indexInSession: 5));

      expect(
        () => journal.append(recordAt(attemptId: 'b', indexInSession: 5)),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => journal.append(recordAt(attemptId: 'c', indexInSession: 4)),
        throwsA(isA<JournalFormatException>()),
      );
      expect(journal.length, 1);
    });

    test('tracks each session independently', () {
      final journal = AttemptJournal(header())
        ..append(recordAt(attemptId: 'a', indexInSession: 3))
        ..append(
          recordAt(attemptId: 'b', indexInSession: 0, sessionId: 'session-2'),
        );

      expect(journal.length, 2);
      expect(journal.session('session-1').length, 1);
      expect(journal.session('session-2').length, 1);
    });

    test('orders by recorded index, not by wall clock', () {
      // A clock correction between attempts must not reorder history, which is
      // why the index is what advances and the timestamp is only data.
      final journal = AttemptJournal(header());
      final exercise = exerciseFor(v1ScaleCatalogFirst);
      final outcome = outcomeOf();

      AttemptRecord at(String id, int index, DateTime when) => AttemptRecord(
        identity: AttemptIdentity(
          profileId: testProfile.id,
          attemptId: id,
          sessionId: 'session-1',
          indexInSession: index,
          occurredAt: when,
        ),
        provenance: provenance,
        exercise: exercise,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        memoryUpdate: const MemoryUpdateDiagnostics(),
      );

      journal.append(at('a', 0, t0.plusDays(10)));
      journal.append(at('b', 1, t0.plusDays(9)));

      expect(journal.records.map((record) => record.identity.attemptId), [
        'a',
        'b',
      ]);
    });
  });

  group('json lines', () {
    test('round-trip a complete journal', () {
      final recorded = recordSession(attempts: 6);
      final reread = AttemptJournal.fromJsonLines(
        recorded.journal.toJsonLines(),
      );

      expect(reread.header.profileId, testProfile.id);
      expect(reread.length, recorded.journal.length);
      expect(reread.toJsonLines(), recorded.journal.toJsonLines());
    });

    test('write one line per record, header first', () {
      final recorded = recordSession(attempts: 4);
      final lines = recorded.journal.toJsonLines().split('\n');

      expect(lines, hasLength(5));
      expect(lines.first, contains('"record_type":"journal_header"'));
      for (final line in lines.skip(1)) {
        expect(line, contains('"record_type":"attempt"'));
      }
    });

    test('reject a journal with no header', () {
      final recorded = recordSession(attempts: 3);
      final withoutHeader = recorded.journal
          .toJsonLines()
          .split('\n')
          .skip(1)
          .join('\n');

      expect(
        () => AttemptJournal.fromJsonLines(withoutHeader),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => AttemptJournal.fromJsonLines(''),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('reject an unreadable line rather than skipping it', () {
      // Skipping would silently drop history from the source of truth.
      final recorded = recordSession(attempts: 3);
      final lines = recorded.journal.toJsonLines().split('\n')
        ..insert(2, '{"record_type":"attempt","schema_version":999}');

      expect(
        () => AttemptJournal.fromJsonLines(lines.join('\n')),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('reject an unknown record type', () {
      final recorded = recordSession(attempts: 2);
      final lines = recorded.journal.toJsonLines().split('\n')
        ..add('{"record_type":"telemetry_blob"}');

      expect(
        () => AttemptJournal.fromJsonLines(lines.join('\n')),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  test('a no-admission slot leaves no attempt behind', () {
    // The scheduler is allowed to admit nothing. When it does, the slot is
    // still consumed but no attempt was presented, so the journal records
    // nothing: it holds presented attempts, not decision opportunities.
    final recorded = recordSession(attempts: 8);

    expect(recorded.journal.length, 8);
    expect(recorded.journal.records.map((r) => r.identity.indexInSession), [
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
    ], reason: 'journal indices count attempts, contiguously');
  });
}
