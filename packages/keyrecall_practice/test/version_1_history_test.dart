import 'dart:convert';
import 'dart:io';

import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// A launch that finds history written by an older build.
///
/// The record upgrade was tested on records alone, which is not what a launch
/// reads: it reads files, and a journal file starts with a header, and a slot
/// that was open when the app closed is a separate file too. All three carry
/// the attempt schema version, so all three have to accept an older one.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('keyrecall_v1_history');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  /// Rewrites everything a version 2 build wrote as version 1 would have.
  void downgradeStoredHistory(String profileId) {
    final directory = Directory('${root.path}/$profileId');

    final journal = File('${directory.path}/journal.jsonl');
    final lines = journal
        .readAsLinesSync()
        .where((line) => line.isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, Object?>)
        .map((record) {
          record['schema_version'] = 1;
          final exercise = record['exercise'];
          if (exercise is Map<String, Object?>) {
            exercise.remove('opportunity_sites');
          }
          final closure = record.remove('closure') as Map<String, Object?>?;
          if (closure == null) return record;
          final measurement = closure['measurement']! as Map<String, Object?>;
          return record
            ..['outcome'] = measurement['outcome']
            ..['evidence_weights'] = measurement['evidence_weights']
            ..['memory_update'] = measurement['memory_update'];
        })
        .map(jsonEncode);
    journal.writeAsStringSync('${lines.join('\n')}\n');

    final pending = File('${directory.path}/pending.json');
    if (pending.existsSync()) {
      final decision =
          jsonDecode(pending.readAsStringSync()) as Map<String, Object?>;
      decision['schema_version'] = 1;
      final exercise = decision['exercise'];
      if (exercise is Map<String, Object?>) {
        exercise.remove('opportunity_sites');
      }
      pending.writeAsStringSync(jsonEncode(decision));
    }
  }

  test('a version 1 journal opens and replays', () async {
    final store = FilePracticeStore(root);
    final first = await openSession(store);
    await practise(first, attempts: 3);
    final expected = learnerStateHash(first.state);
    downgradeStoredHistory(alice.id);

    final reopened = await openSession(FilePracticeStore(root));

    expect(reopened.journal.length, 3);
    expect(
      learnerStateHash(reopened.state),
      expected,
      reason: 'an upgraded history reaches the state the old build was in',
    );
    expect(
      reopened.journal.records.first.closure.termination,
      AttemptTermination.learnerStopped,
    );
  });

  test('a version 1 pending decision still has to be answered', () async {
    final store = FilePracticeStore(root);
    final first = await openSession(store);
    await practise(first, attempts: 1);
    final presented = await first.decide(at: t0.plusDays(5));
    expect(presented, isNotNull);
    downgradeStoredHistory(alice.id);

    final reopened = await openSession(FilePracticeStore(root));

    expect(
      reopened.pending?.attemptId,
      presented!.decision.attemptId,
      reason:
          'an attempt shown by an older build is still unanswered, and '
          'only a person can say what happened',
    );
  });

  test('a version this build cannot upgrade is refused', () async {
    final store = FilePracticeStore(root);
    final session = await openSession(store);
    await practise(session, attempts: 1);

    final journal = File('${root.path}/${alice.id}/journal.jsonl');
    journal.writeAsStringSync(
      journal
          .readAsLinesSync()
          .where((line) => line.isNotEmpty)
          .map((line) {
            final record = jsonDecode(line) as Map<String, Object?>;
            record['schema_version'] = 99;
            return jsonEncode(record);
          })
          .join('\n'),
    );

    expect(
      () => openSession(FilePracticeStore(root)),
      throwsA(isA<JournalFormatException>()),
    );
  });
}
