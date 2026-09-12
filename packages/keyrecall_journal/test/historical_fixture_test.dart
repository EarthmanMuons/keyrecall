import 'dart:convert';
import 'dart:io';

import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/fixtures.dart';

/// History as it was actually written, byte for byte.
///
/// Every other fixture here is produced by today's codecs, so a change to
/// those changes the fixture with them and the test goes on passing. These
/// files are literal and are never regenerated: a reader that stops being able
/// to read them has broken persisted history, whatever the encoder now agrees
/// with itself about.
///
/// Replacing one is a decision, not maintenance. A record that can no longer
/// be read needs a versioned upgrade, and the file stays as it is so the
/// upgrade has something real to be proved against.
///
/// Both learner model versions are kept. The `v1-8` pair is the file as it was
/// actually written, and what this build does with it is part of the storage
/// contract: that version named a transition whose summation order followed
/// the order an exercise's opportunities happened to iterate in, so a record
/// of it read back off disk did not reliably replay to the state it produced,
/// and no replay claims otherwise. The `v1-9` pair is the same history
/// re-recorded, and it is the one that must still replay exactly.
void main() {
  /// What the state hash is under the current model.
  const recordedStateHash =
      'f2e8c4c3178050a76fa0cc00ee36c8255cbb521f67e5ed2486ec82a0e21d6d19';

  File fixture(String name) => File('test/fixtures/$name');

  AttemptJournal journalOf(String name) => AttemptJournal.fromJsonLines(
    fixture(name).readAsStringSync().trimRight(),
  );

  LearnerStateCheckpoint checkpointOf(String name) =>
      LearnerStateCheckpoint.fromJson(
        jsonDecode(fixture(name).readAsStringSync()) as Map<String, Object?>,
        params: params,
      );

  LearnerState genesis() => model.placementState(testProfile.placement, at: t0);

  test('a stored journal still replays to the state it produced', () {
    final journal = journalOf('attempt-journal-v4-v1-9.jsonl');

    expect(journal.header.profileId, testProfile.id);
    expect(journal.length, 4);
    expect(journal.records.map((record) => record.journalSequence), [
      0,
      1,
      2,
      3,
    ]);

    final replayed = replayJournal(journal, model: model, initial: genesis());

    expect(replayed.divergences, isEmpty, reason: replayed.divergences.join());
    expect(replayed.stateHash, recordedStateHash);
  });

  test('a stored checkpoint still covers that journal', () {
    final journal = journalOf('attempt-journal-v4-v1-9.jsonl');
    final checkpoint = checkpointOf('checkpoint-v3-v1-9.json');

    expect(checkpoint.contentHash, recordedStateHash);
    expect(
      validateCheckpointAgainstJournal(
        checkpoint,
        journal: journal,
        learnerModelVersion: params.modelVersion,
        genesisStateHash: learnerStateHash(genesis()),
      ),
      isNull,
    );
  });

  group('a journal from a superseded learner model', () {
    test('still reads, because the wire format did not change', () {
      final journal = journalOf('attempt-journal-v4-v1-8.jsonl');

      expect(journal.length, 4);
      expect(
        journal.records.map((record) => record.provenance.learnerModelVersion),
        everyElement('v1-8'),
      );
    });

    test('is refused by exact replay rather than reinterpreted', () {
      expect(
        () => replayJournal(
          journalOf('attempt-journal-v4-v1-8.jsonl'),
          model: model,
          initial: genesis(),
        ),
        throwsA(
          isA<JournalFormatException>().having(
            (error) => error.toString(),
            'message',
            allOf(contains('v1-8'), contains(params.modelVersion)),
          ),
        ),
      );
    });

    test('re-estimates only where a caller asked for it deliberately', () {
      final replayed = replayJournal(
        journalOf('attempt-journal-v4-v1-8.jsonl'),
        model: model,
        initial: genesis(),
        options: const ReplayOptions(mode: ReplayMode.counterfactual),
      );

      expect(replayed.attemptsApplied, 4);
    });

    test('its checkpoint is a cache miss, not a shortcut', () {
      final checkpoint = checkpointOf('checkpoint-v3-v1-8.json');

      expect(checkpoint.isUsableUnder(params.modelVersion), isFalse);
      expect(
        validateCheckpointAgainstJournal(
          checkpoint,
          journal: journalOf('attempt-journal-v4-v1-8.jsonl'),
          learnerModelVersion: params.modelVersion,
          genesisStateHash: learnerStateHash(genesis()),
        ),
        isNotNull,
      );
    });
  });

  test('a checkpoint from a format this build cannot read is a cache miss', () {
    // The version 2 file is kept exactly as it was written. It carries no
    // digest of the history it stands in for, and nothing computes one for it:
    // deriving the digest from whatever journal is on disk would assert the
    // thing it exists to check. Failing to read it costs a full replay, which
    // is the whole price of not having a checkpoint.
    expect(
      () => LearnerStateCheckpoint.fromJson(
        jsonDecode(fixture('checkpoint-v2.json').readAsStringSync())
            as Map<String, Object?>,
        params: params,
      ),
      throwsA(isA<JournalFormatException>()),
    );
  });
}
