import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/fixtures.dart';

/// A version 1 record: the outcome and its derived evidence sat directly on the
/// record, because the learner ending the attempt and saying what happened was
/// the only way one could be written.
Map<String, Object?> version1(Map<String, Object?> current) {
  final measurement = measurementJsonOf(current);
  return Map<String, Object?>.of(current)
    ..['schema_version'] = 1
    ..remove('closure')
    ..['outcome'] = measurement['outcome']
    ..['evidence_weights'] = measurement['evidence_weights']
    ..['memory_update'] = measurement['memory_update'];
}

void main() {
  final recorded = recordSession();
  final journal = recorded.journal;

  group('version 1 to 2', () {
    test('reads every historical outcome as a learner-stopped measurement', () {
      for (final original in journal.records) {
        final upgraded = AttemptRecord.fromJson(version1(original.toJson()));

        expect(upgraded.closure.termination, AttemptTermination.learnerStopped);
        expect(measuredOf(upgraded).outcome, measuredOf(original).outcome);
        expect(measuredOf(upgraded).weights, measuredOf(original).weights);
        // Diagnostics have no value equality, so compare what they say.
        expect(
          '${measuredOf(upgraded).memoryUpdate}',
          '${measuredOf(original).memoryUpdate}',
        );
      }
    });

    test('carries every retrieval value through, including untested', () {
      final original = journal.records.first;

      for (final retrieval in FactualRetrieval.values) {
        final json = version1(original.toJson());
        (json['outcome']! as Map<String, Object?>)['retrieval_succeeded'] =
            switch (retrieval) {
              FactualRetrieval.succeeded => true,
              FactualRetrieval.failed => false,
              FactualRetrieval.notTested => null,
            };

        expect(
          measuredOf(AttemptRecord.fromJson(json)).outcome.retrieval,
          retrieval,
          reason:
              'untested serializes as null, which is the value most '
              'likely to be lost in a migration',
        );
      }
    });

    test('does not reinterpret a broken-down outcome as a termination', () {
      // What ReportedResult.brokeDown produced: an attempt that started, did
      // not complete, and failed retrieval. That is a characterization of the
      // performance, and the upgrade must leave it there rather than reading a
      // lifecycle event out of it.
      final brokeDown = outcomeOf(
        started: true,
        completed: false,
        retrieval: FactualRetrieval.failed,
      );
      final record = journal.records.first;
      final json = version1(record.toJson());
      json['outcome'] =
          {
            for (final entry
                in (json['outcome']! as Map<String, Object?>).entries)
              entry.key: entry.value,
          }..addAll({
            'started': brokeDown.started,
            'completed': brokeDown.completed,
            'retrieval_succeeded': false,
          });

      final upgraded = AttemptRecord.fromJson(json);

      expect(upgraded.closure.termination, AttemptTermination.learnerStopped);
      expect(measuredOf(upgraded).outcome, brokeDown);
      expect(measuredOf(upgraded).outcome.completed, isFalse);
    });

    test('an upgraded journal replays to the same learner state', () {
      final upgraded = AttemptJournal(journal.header);
      for (final record in journal.records) {
        upgraded.append(AttemptRecord.fromJson(version1(record.toJson())));
      }

      final before = replayJournal(
        journal,
        model: model,
        initial: recorded.initial.copy(),
      );
      final after = replayJournal(
        upgraded,
        model: model,
        initial: recorded.initial.copy(),
      );

      expect(after.stateHash, before.stateHash);
      expect(after.attemptsApplied, before.attemptsApplied);
      expect(after.divergences, isEmpty);
    });
  });

  test('a version this build cannot read fails loudly', () {
    final json = journal.records.first.toJson()..['schema_version'] = 99;

    expect(
      () => AttemptRecord.fromJson(json),
      throwsA(isA<JournalFormatException>()),
    );
  });
}
