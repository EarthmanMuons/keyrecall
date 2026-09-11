import 'dart:convert';

import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/fixtures.dart';

/// What the storage boundary promises about data it did not write.
///
/// Persisted state is untrusted input. Either it produces one unambiguous
/// domain object, or it produces a located [JournalFormatException]. Anything
/// in between is a decoder deciding what history probably meant.
void main() {
  /// A checkpoint written out, ready to be tampered with before reading.
  Map<String, Object?> checkpointJson() {
    final recorded = recordSession(attempts: 3);
    final replayed = replayJournal(
      recorded.journal,
      model: model,
      initial: recorded.initial,
    );
    final last = recorded.journal.records.last;
    final captured = LearnerStateCheckpoint.after(
      last,
      state: replayed.state,
      learnerModelVersion: params.modelVersion,
    );
    return jsonDecode(jsonEncode(captured.toJson())) as Map<String, Object?>;
  }

  /// [json] with its state replaced by [rewrite], rehashed so the content hash
  /// is not what fails.
  Map<String, Object?> withState(
    Map<String, Object?> json,
    void Function(Map<String, Object?> state) rewrite,
  ) {
    final state = json['state']! as Map<String, Object?>;
    rewrite(state);
    return {...json, 'state': state, 'content_hash': contentHash(state)};
  }

  LearnerStateCheckpoint read(Map<String, Object?> json) =>
      LearnerStateCheckpoint.fromJson(json, params: params);

  group('timestamps', () {
    test('reject a date the calendar does not have', () {
      // The platform parser accepts 2026-02-31 and hands back March 3. An
      // impossible date repaired into a plausible one is a fact nobody will
      // ever notice is invented.
      expect(parseTime('2026-02-31T00:00:00.000Z'), isNull);
      expect(parseTime('2026-13-01T00:00:00.000Z'), isNull);
      expect(parseTime('2026-01-01T25:00:00.000Z'), isNull);
    });

    test('reject a timestamp with no offset', () {
      // Its meaning would depend on which machine read it back.
      expect(parseTime('2026-01-01T00:00:00.000'), isNull);
      expect(parseTime('2026-01-01 00:00:00'), isNull);
    });

    test('accept what the encoder writes, and read it as UTC', () {
      final at = DateTime.utc(2026, 3, 14, 15, 9, 26, 535);
      expect(parseTime(encodeTime(at)), at);
      expect(parseTime('2026-03-14T16:09:26.535+01:00'), at);
    });

    test('a record carrying an impossible date does not load', () {
      final recorded = recordSession(attempts: 2);
      final lines = recorded.journal.toJsonLines().split('\n');
      final record = jsonDecode(lines[2]) as Map<String, Object?>;
      record['occurred_at'] = '2026-02-31T00:00:00.000Z';
      lines[2] = jsonEncode(record);

      expect(
        () => AttemptJournal.fromJsonLines(lines.join('\n')),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });

  group('learner state', () {
    test('rejects a memory entry filed under another material', () {
      final json = checkpointJson();
      expect(
        () => read(
          withState(json, (state) {
            final memory = state['material_memory']! as Map<String, Object?>;
            final first = memory.keys.first;
            memory['borrowed'] = memory.remove(first)!;
          }),
        ),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('rejects an execution entry whose key describes another context', () {
      final json = checkpointJson();
      expect(
        () => read(
          withState(json, (state) {
            final execution =
                state['material_execution']! as Map<String, Object?>;
            final first = execution.keys.first;
            execution['made/up/key'] = execution.remove(first)!;
          }),
        ),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('rejects two entries describing the same context', () {
      // The collision exists only after decoding: two stored keys, one
      // context. A decoder that rebuilds keys from values collapses them
      // silently, and whichever decoded second becomes the whole history of
      // that context.
      final json = checkpointJson();
      expect(
        () => read(
          withState(json, (state) {
            final execution =
                state['material_execution']! as Map<String, Object?>;
            final first = execution.keys.first;
            execution['$first/duplicate'] = execution[first];
          }),
        ),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('rejects evidence dated after the update it caused', () {
      final json = checkpointJson();
      expect(
        () => read(
          withState(json, (state) {
            final competencies = state['competencies']! as Map<String, Object?>;
            final entry = competencies.values.first! as Map<String, Object?>;
            entry['last_evidence_at'] = '2099-01-01T00:00:00.000Z';
          }),
        ),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('a decodable state still round-trips unchanged', () {
      final json = checkpointJson();
      final restored = read(json);
      expect(restored.contentHash, json['content_hash']);
      expect(learnerStateHash(restored.state), restored.contentHash);
    });
  });

  group('the uniform failure type', () {
    test('covers an unreadable enum value in an exercise', () {
      final recorded = recordSession(attempts: 2);
      final lines = recorded.journal.toJsonLines().split('\n');
      final record = jsonDecode(lines[2]) as Map<String, Object?>;
      (record['exercise']! as Map<String, Object?>)['hands'] = 'three';
      lines[2] = jsonEncode(record);

      expect(
        () => AttemptJournal.fromJsonLines(lines.join('\n')),
        throwsA(
          isA<JournalFormatException>().having(
            (error) => error.location,
            'location',
            'line 3',
          ),
        ),
      );
    });

    test('covers an unreadable numeric key inside a checkpoint', () {
      final json = checkpointJson();
      expect(
        () => read(
          withState(json, (state) {
            final execution =
                state['material_execution']! as Map<String, Object?>;
            final entry = execution.values.first! as Map<String, Object?>;
            entry['demonstrated_tempo_by_octaves'] = {'every': 80.0};
          }),
        ),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });
}
