import 'dart:convert';
import 'dart:io';

import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'pending_decision.dart';
import 'practice_store.dart';
import 'profile_write_queue.dart';

/// A [PracticeStore] backed by ordinary files, one directory per profile.
///
/// ```text
/// <root>/<profileId>/journal.jsonl     append-only, authoritative
/// <root>/<profileId>/pending.json      one slot, replaced or removed
/// <root>/<profileId>/checkpoint.json   one slot, replaced
/// ```
///
/// The directory is shared with the profile's own record of itself, which the
/// profile repository writes and this store never touches. That is what lets a
/// history be reopened without the install's index; see
/// [FileProfileRepository].
///
/// The port exists so a database can be swapped in. Files are the natural first
/// fit: the journal is already append-only JSON lines, appending never rewrites
/// history, and a person can read a journal with ordinary tools.
///
/// Attempts are appended and flushed, so a committed attempt survives the
/// process. Single-slot files are written to a temporary name and renamed over
/// the target, so a reader never sees a half-written file.
///
/// Operations on one profile run one at a time. Each of them reads, decides,
/// and writes, and letting two interleave at their suspension points would let
/// the second decide from what the first has already replaced.
class FilePracticeStore implements PracticeStore {
  /// Directory holding one subdirectory per profile.
  final Directory root;

  /// The registry a stored checkpoint is validated against when read.
  final LearnerParams params;

  final ProfileWriteQueue _queue = ProfileWriteQueue();

  FilePracticeStore(this.root, {this.params = v1PrototypeLearnerParams});

  /// A store rooted at [path].
  factory FilePracticeStore.at(
    String path, {
    LearnerParams params = v1PrototypeLearnerParams,
  }) => FilePracticeStore(Directory(path), params: params);

  @override
  Future<AttemptJournal> loadJournal(String profileId, {DateTime? createdAt}) =>
      _queue.run(profileId, () => _loadJournal(profileId, createdAt));

  Future<AttemptJournal> _loadJournal(
    String profileId,
    DateTime? createdAt,
  ) async {
    await _recoverErase(profileId);
    final file = _journalFile(profileId);
    if (!file.existsSync()) {
      return AttemptJournal(
        JournalHeader(
          profileId: profileId,
          createdAt: createdAt ?? DateTime.now().toUtc(),
        ),
      );
    }
    return AttemptJournal.fromJsonLines(
      await _readCommittedLines(file, profileId),
    );
  }

  @override
  Future<void> appendAttempt(AttemptRecord record) =>
      _queue.run(record.profileId, () => _appendAttempt(record));

  Future<void> _appendAttempt(AttemptRecord record) async {
    await _recoverErase(record.profileId);
    final file = _journalFile(record.profileId);
    await file.parent.create(recursive: true);
    await _repairTornTail(file);

    if (!file.existsSync()) {
      // A journal created by its first append is stamped with the attempt it
      // is created for, rather than with whatever the clock reads now.
      final header = JournalHeader(
        profileId: record.profileId,
        createdAt: record.identity.occurredAt,
      );
      await _appendLine(file, canonicalJson(header.toJson()));
    }

    // Read-modify-validate before writing: the journal enforces contiguous
    // sequence, forward time, and conflicting-id detection, and those checks
    // have to run against what is actually on disk.
    final journal = await _loadJournal(record.profileId, null);
    if (!journal.append(record)) return;

    await _appendLine(file, canonicalJson(record.toJson()));
  }

  @override
  Future<PendingDecision?> loadPendingDecision(String profileId) =>
      _queue.run(profileId, () => _loadPendingDecision(profileId));

  Future<PendingDecision?> _loadPendingDecision(String profileId) async {
    await _recoverErase(profileId);
    final file = _pendingFile(profileId);
    if (!file.existsSync()) return null;
    return PendingDecision.fromJson(
      asMap(
        await _decode(file, 'pending decision'),
        'pending decision',
        location: file.path,
      ),
    );
  }

  @override
  Future<void> savePendingDecision(PendingDecision decision) =>
      _queue.run(decision.profileId, () => _savePendingDecision(decision));

  Future<void> _savePendingDecision(PendingDecision decision) async {
    await _recoverErase(decision.profileId);
    await _writeAtomically(
      _pendingFile(decision.profileId),
      canonicalJson(decision.toJson()),
    );
  }

  @override
  Future<void> clearPendingDecision(String profileId) =>
      _queue.run(profileId, () => _clearPendingDecision(profileId));

  Future<void> _clearPendingDecision(String profileId) async {
    await _recoverErase(profileId);
    final file = _pendingFile(profileId);
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<LearnerStateCheckpoint?> loadCheckpoint(String profileId) =>
      _queue.run(profileId, () => _loadCheckpoint(profileId));

  Future<LearnerStateCheckpoint?> _loadCheckpoint(String profileId) async {
    await _recoverErase(profileId);
    final file = _checkpointFile(profileId);
    if (!file.existsSync()) return null;
    return LearnerStateCheckpoint.fromJson(
      asMap(
        await _decode(file, 'learner checkpoint'),
        'learner checkpoint',
        location: file.path,
      ),
      params: params,
    );
  }

  @override
  Future<void> saveCheckpoint(LearnerStateCheckpoint checkpoint) =>
      _queue.run(checkpoint.profileId, () => _saveCheckpoint(checkpoint));

  Future<void> _saveCheckpoint(LearnerStateCheckpoint checkpoint) async {
    await _recoverErase(checkpoint.profileId);
    await _writeAtomically(
      _checkpointFile(checkpoint.profileId),
      canonicalJson(checkpoint.toJson()),
    );
  }

  /// Reads the lines that were fully committed.
  ///
  /// A crash mid-append can leave a final line without its terminating
  /// newline. That attempt was never committed, so the torn tail is dropped.
  /// A malformed line anywhere *else* is real corruption of history and is left
  /// to fail loudly when parsed.
  Future<String> _readCommittedLines(File file, String profileId) async {
    final contents = await file.readAsString();
    if (contents.isEmpty) {
      throw JournalFormatException(
        'journal file for $profileId is empty',
        location: file.path,
      );
    }
    if (contents.endsWith('\n')) {
      return contents.substring(0, contents.length - 1);
    }

    final lastBreak = contents.lastIndexOf('\n');
    if (lastBreak < 0) {
      throw JournalFormatException(
        'journal file for $profileId holds no complete record',
        location: file.path,
      );
    }
    return contents.substring(0, lastBreak);
  }

  /// Truncates an incomplete final line before appending after it.
  ///
  /// A crash mid-append leaves a record with no terminating newline. That
  /// attempt was never committed, so the next append must remove it rather than
  /// write onto the end of it.
  Future<void> _repairTornTail(File file) async {
    if (!file.existsSync()) return;
    final contents = await file.readAsString();
    if (contents.isEmpty || contents.endsWith('\n')) return;

    final lastBreak = contents.lastIndexOf('\n');
    await file.writeAsString(
      lastBreak < 0 ? '' : contents.substring(0, lastBreak + 1),
      flush: true,
    );
  }

  Future<void> _appendLine(File file, String line) async {
    final handle = file.openSync(mode: FileMode.append);
    try {
      handle.writeStringSync('$line\n');
      handle.flushSync();
    } finally {
      handle.closeSync();
    }
  }

  Future<void> _writeAtomically(File file, String contents) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(file.path);
  }

  /// Deletes the files this store wrote, and nothing else in the directory.
  ///
  /// Not the directory itself, because it is shared: a profile records itself
  /// beside its history so that the history can be reopened without the
  /// install's index, and erasing practice is not the same decision as
  /// forgetting who somebody is. Removing the directory wholesale would make
  /// the smaller decision impossible to ask for, which is the seam the profile
  /// repository and this store are kept apart to preserve.
  @override
  Future<void> erase(String profileId) =>
      _queue.run(profileId, () => _erase(profileId));

  Future<void> _erase(String profileId) async {
    final directory = _profileDirectory(profileId);
    if (!directory.existsSync()) return;
    await _writeAtomically(_eraseMarker(profileId), '');
    await _finishErase(profileId);
  }

  Future<void> _recoverErase(String profileId) async {
    if (_eraseMarker(profileId).existsSync()) await _finishErase(profileId);
  }

  Future<void> _finishErase(String profileId) async {
    for (final file in [
      _journalFile(profileId),
      _pendingFile(profileId),
      _checkpointFile(profileId),
      File('${_pendingFile(profileId).path}.tmp'),
      File('${_checkpointFile(profileId).path}.tmp'),
    ]) {
      if (file.existsSync()) await file.delete();
    }
    final marker = _eraseMarker(profileId);
    if (marker.existsSync()) await marker.delete();
  }

  Future<Object?> _decode(File file, String what) async {
    try {
      return jsonDecode(await file.readAsString());
    } on FormatException catch (error) {
      throw JournalFormatException(
        '$what is not valid JSON: ${error.message}',
        location: file.path,
      );
    }
  }

  Directory _profileDirectory(String profileId) =>
      Directory('${root.path}/${requireProfileId(profileId)}');

  File _journalFile(String profileId) =>
      File('${_profileDirectory(profileId).path}/journal.jsonl');

  File _pendingFile(String profileId) =>
      File('${_profileDirectory(profileId).path}/pending.json');

  File _checkpointFile(String profileId) =>
      File('${_profileDirectory(profileId).path}/checkpoint.json');

  File _eraseMarker(String profileId) =>
      File('${_profileDirectory(profileId).path}/practice-erasing');
}
