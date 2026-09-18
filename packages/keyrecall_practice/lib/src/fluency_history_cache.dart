import 'dart:io';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'fluency_history.dart';
import 'practice_store.dart';

/// The fluency history of [profileId], brought up to date with its journal and
/// saved.
///
/// The saved projection is extended when it still covers a prefix of the
/// journal, and rebuilt when it cannot be read, was built under another
/// partition, or covers history the journal no longer holds. The journal is the
/// authority; the saved projection only saves time.
///
/// Saves the result when it covers attempts the saved one did not, or replaces
/// one that was unusable. A profile with no attempts saves nothing. A failure to
/// save propagates; see [readFluencyHistory] for a caller that only needs the
/// history.
Future<FluencyHistory> openFluencyHistory(
  PracticeStore store,
  String profileId, {
  required DayPartition partition,
}) async {
  final (history, :stale) = await _refreshed(store, profileId, partition);
  if (stale) await store.saveFluencyHistory(history);
  return history;
}

/// The fluency history of [profileId], for a caller that only needs to read it.
///
/// As [openFluencyHistory], except that failing to save the refreshed
/// projection is reported to [onSaveFailure] rather than thrown: the history is
/// already correct, and a cache that could not be written costs the next
/// opening time. Failing to read the journal still throws, and so does an
/// [Error], which is a defect rather than a storage condition.
Future<FluencyHistory> readFluencyHistory(
  PracticeStore store,
  String profileId, {
  required DayPartition partition,
  required void Function(Object error, StackTrace stackTrace) onSaveFailure,
}) async {
  final (history, :stale) = await _refreshed(store, profileId, partition);
  if (stale) {
    try {
      await store.saveFluencyHistory(history);
    } on Exception catch (error, stackTrace) {
      onSaveFailure(error, stackTrace);
    }
  }
  return history;
}

Future<(FluencyHistory, {bool stale})> _refreshed(
  PracticeStore store,
  String profileId,
  DayPartition partition,
) async {
  final journal = await store.loadJournal(profileId);
  final saved = await _readable(store, profileId, partition);
  final reusable = saved != null && saved.coversPrefixOf(journal)
      ? saved
      : null;

  final history =
      reusable ?? FluencyHistory.empty(profileId, partition: partition);
  final savedCoverage = reusable?.coveredRecords;
  journal.records.skip(history.coveredRecords).forEach(history.apply);

  return (
    history,
    stale:
        history.coveredRecords > 0 && history.coveredRecords != savedCoverage,
  );
}

Future<FluencyHistory?> _readable(
  PracticeStore store,
  String profileId,
  DayPartition partition,
) async {
  try {
    return await store.loadFluencyHistory(profileId, partition: partition);
  } on JournalFormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}
