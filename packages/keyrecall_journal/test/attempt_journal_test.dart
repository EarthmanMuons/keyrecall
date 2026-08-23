import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/fixtures.dart';

AttemptRecord recordAt({
  required String attemptId,
  required int indexInSession,
  String sessionId = 'session-1',
  int? journalSequence,
  String tonic = 'C',
}) {
  final exercise = exerciseFor(TechnicalMaterial(tonic, ScaleForm.major));
  final outcome = outcomeOf();
  final sequence = journalSequence ?? indexInSession;
  return AttemptRecord(
    journalSequence: sequence,
    identity: AttemptIdentity(
      profileId: testProfile.id,
      attemptId: attemptId,
      sessionId: sessionId,
      indexInSession: indexInSession,
      // History order, not sitting order: the model timeline follows the
      // journal.
      occurredAt: t0.plusDays(sequence.toDouble()),
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
        ..append(
          recordAt(attemptId: 'a', indexInSession: 5, journalSequence: 0),
        );

      expect(
        () => journal.append(
          recordAt(attemptId: 'b', indexInSession: 5, journalSequence: 1),
        ),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => journal.append(
          recordAt(attemptId: 'c', indexInSession: 4, journalSequence: 1),
        ),
        throwsA(isA<JournalFormatException>()),
      );
      expect(journal.length, 1);
    });

    test('tracks each session independently', () {
      final journal = AttemptJournal(header())
        ..append(
          recordAt(attemptId: 'a', indexInSession: 3, journalSequence: 0),
        )
        ..append(
          recordAt(
            attemptId: 'b',
            indexInSession: 0,
            sessionId: 'session-2',
            journalSequence: 1,
          ),
        );

      expect(journal.length, 2);
      expect(journal.session('session-1').length, 1);
      expect(journal.session('session-2').length, 1);
    });

    test('refuses a timestamp that runs backward', () {
      // The model timeline cannot go back, because propagating backward is
      // illegal and every memory transition is driven by elapsed time. A
      // device clock corrected mid-session is resolved at the observation
      // boundary; it never reaches the journal as an impossible timeline.
      final journal = AttemptJournal(header());
      final exercise = exerciseFor(v1ScaleCatalogFirst);
      final outcome = outcomeOf();

      AttemptRecord at(String id, int index, DateTime when) => AttemptRecord(
        journalSequence: index,
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

      expect(
        () => journal.append(at('b', 1, t0.plusDays(9))),
        throwsA(isA<JournalFormatException>()),
      );
      // Standing still is fine; only going back is not.
      expect(journal.append(at('c', 1, t0.plusDays(10))), isTrue);
    });

    test('keeps the raw device reading when it had to be clamped', () {
      final exercise = exerciseFor(v1ScaleCatalogFirst);
      final outcome = outcomeOf();
      final record = AttemptRecord(
        journalSequence: 0,
        identity: AttemptIdentity(
          profileId: testProfile.id,
          attemptId: 'a',
          sessionId: 'session-1',
          indexInSession: 0,
          occurredAt: t0.plusDays(10),
        ),
        observedWallTime: t0.plusDays(9),
        provenance: provenance,
        exercise: exercise,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        memoryUpdate: const MemoryUpdateDiagnostics(),
      );

      final journal = AttemptJournal(header())..append(record);
      final reread = AttemptJournal.fromJsonLines(journal.toJsonLines());

      expect(reread.records.single.observedWallTime, t0.plusDays(9));
      expect(
        reread.records.single.identity.occurredAt,
        t0.plusDays(10),
        reason: 'decay uses the model timeline, never the raw reading',
      );
    });

    test('refuses a journal sequence that is not the next one', () {
      // A gap means a record was lost; a repeat means one was duplicated.
      // Either way the history in hand is not the history that was written.
      final journal = AttemptJournal(header())
        ..append(recordAt(attemptId: 'a', indexInSession: 0));

      expect(journal.nextSequence, 1);
      expect(
        () => journal.append(
          recordAt(attemptId: 'b', indexInSession: 1, journalSequence: 5),
        ),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => journal.append(
          recordAt(attemptId: 'c', indexInSession: 1, journalSequence: 0),
        ),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('an id that returns with different content is a collision', () {
      // Idempotency must not mean first-write-wins. Two different records
      // claiming one id is corruption, and keeping either silently would make
      // the log unreliable exactly where it claims to be authoritative.
      final journal = AttemptJournal(header())
        ..append(recordAt(attemptId: 'a', indexInSession: 0));

      expect(
        journal.append(recordAt(attemptId: 'a', indexInSession: 0)),
        isFalse,
        reason: 'an identical retry is a no-op',
      );
      expect(
        () => journal.append(
          recordAt(attemptId: 'a', indexInSession: 0, tonic: 'G'),
        ),
        throwsA(isA<JournalFormatException>()),
      );
      expect(journal.length, 1);
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
