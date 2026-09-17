import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'fluency_history.dart';
import 'practice_store.dart';

/// The fluency history of [profileId], brought up to date with its journal.
///
/// The saved projection is extended when it still covers a prefix of the
/// journal, and rebuilt when it cannot be read, was built under another
/// partition, or covers history the journal no longer holds. The journal is the
/// authority; the saved projection only saves time.
///
/// Saves the result when it covers attempts the saved one did not, or replaces
/// one that was unusable. A profile with no attempts saves nothing.
Future<FluencyHistory> openFluencyHistory(
  PracticeStore store,
  String profileId, {
  required DayPartition partition,
}) async {
  final journal = await store.loadJournal(profileId);
  final saved = await _readable(store, profileId, partition);
  final reusable = saved != null && saved.coversPrefixOf(journal)
      ? saved
      : null;

  final history =
      reusable ?? FluencyHistory.empty(profileId, partition: partition);
  final savedCoverage = reusable?.coveredRecords;
  journal.records.skip(history.coveredRecords).forEach(history.apply);

  if (history.coveredRecords > 0 && history.coveredRecords != savedCoverage) {
    await store.saveFluencyHistory(history);
  }
  return history;
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
  }
}
