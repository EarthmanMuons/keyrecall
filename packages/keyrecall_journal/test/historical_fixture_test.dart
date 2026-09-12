import 'dart:convert';
import 'dart:io';

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
/// These were re-stamped once, from `v1-8` to `v1-9`. That version could not
/// be preserved: it named a transition whose summation order followed the
/// order an exercise's opportunities happened to iterate in, so a record of it
/// read back off disk did not reliably replay to the state it produced. Only
/// the version string moved; every prediction, weight, and hash in the file is
/// what `v1-8` wrote, which is what says the arithmetic these particular
/// attempts ran was already canonical.
void main() {
  /// What the state hash was when these files were written.
  const recordedStateHash =
      'f2e8c4c3178050a76fa0cc00ee36c8255cbb521f67e5ed2486ec82a0e21d6d19';

  File fixture(String name) => File('test/fixtures/$name');

  test('a stored journal still replays to the state it produced', () {
    final journal = AttemptJournal.fromJsonLines(
      fixture('attempt-journal-v4.jsonl').readAsStringSync().trimRight(),
    );

    expect(journal.header.profileId, testProfile.id);
    expect(journal.length, 4);
    expect(journal.records.map((record) => record.journalSequence), [
      0,
      1,
      2,
      3,
    ]);

    final replayed = replayJournal(
      journal,
      model: model,
      initial: model.placementState(testProfile.placement, at: t0),
    );

    expect(replayed.divergences, isEmpty, reason: replayed.divergences.join());
    expect(replayed.stateHash, recordedStateHash);
  });

  test('a stored checkpoint still covers that journal', () {
    final journal = AttemptJournal.fromJsonLines(
      fixture('attempt-journal-v4.jsonl').readAsStringSync().trimRight(),
    );
    final checkpoint = LearnerStateCheckpoint.fromJson(
      jsonDecode(fixture('checkpoint-v3.json').readAsStringSync())
          as Map<String, Object?>,
      params: params,
    );

    expect(checkpoint.contentHash, recordedStateHash);
    expect(
      validateCheckpointAgainstJournal(
        checkpoint,
        journal: journal,
        learnerModelVersion: params.modelVersion,
        genesisStateHash: learnerStateHash(
          model.placementState(testProfile.placement, at: t0),
        ),
      ),
      isNull,
    );
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
