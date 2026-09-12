import 'dart:convert';
import 'dart:io';

import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'coordination_log.dart';
import 'feedback_exposure.dart';
import 'json_lines.dart';
import 'pending_decision.dart';
import 'practice_plan.dart';
import 'practice_store.dart';
import 'profile_write_queue.dart';

/// A [PracticeStore] backed by ordinary files, one directory per profile.
///
/// ```text
/// <root>/<profileId>/journal.jsonl     append-only, authoritative
/// <root>/<profileId>/feedback.jsonl    append-only exposure record
/// <root>/<profileId>/pending.json      one slot, replaced or removed
/// <root>/<profileId>/checkpoint.json   one slot, replaced
/// <root>/<profileId>/plan.json         one slot, replaced
/// <root>/<profileId>/coordination.jsonl append-only diagnostic log
/// <root>/<profileId>/selections.jsonl  append-only selection diagnostics
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

  FilePracticeStore(this.root, {this.params = v1LearnerParams});

  /// A store rooted at [path].
  factory FilePracticeStore.at(
    String path, {
    LearnerParams params = v1LearnerParams,
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
    final journal = AttemptJournal.fromJsonLines(
      await _readCommittedLines(file, profileId),
    );
    _requireOwnership(journal.header.profileId, profileId, file);
    return journal;
  }

  @override
  Future<void> appendAttempt(AttemptRecord record) =>
      _queue.run(record.profileId, () => _appendAttempt(record));

  Future<void> _appendAttempt(AttemptRecord record) async {
    await _recoverErase(record.profileId);
    final file = _journalFile(record.profileId);
    await file.parent.create(recursive: true);
    await truncateTornTail(file);

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
  Future<AcquisitionJournal> loadAcquisitionJournal(
    String profileId, {
    DateTime? createdAt,
  }) => _queue.run(profileId, () => _loadAcquisition(profileId, createdAt));

  Future<AcquisitionJournal> _loadAcquisition(
    String profileId,
    DateTime? createdAt,
  ) async {
    await _recoverErase(profileId);
    final file = _acquisitionFile(profileId);
    if (!file.existsSync()) {
      return AcquisitionJournal(
        AcquisitionJournalHeader(
          profileId: profileId,
          createdAt: createdAt ?? DateTime.now().toUtc(),
        ),
      );
    }
    final log = AcquisitionJournal.fromJsonLines(
      await _readCommittedLines(file, profileId),
    );
    _requireOwnership(log.header.profileId, profileId, file);
    return log;
  }

  @override
  Future<void> appendAcquisitionEntry(AcquisitionEntry entry) => _queue.run(
    entry.identity.profileId,
    () => _appendAcquisitionEntry(entry),
  );

  Future<void> _appendAcquisitionEntry(AcquisitionEntry entry) async {
    final profileId = entry.identity.profileId;
    await _recoverErase(profileId);
    final file = _acquisitionFile(profileId);
    await file.parent.create(recursive: true);
    await truncateTornTail(file);

    if (!file.existsSync()) {
      final header = AcquisitionJournalHeader(
        profileId: profileId,
        createdAt: entry.identity.occurredAt,
      );
      await _appendLine(file, canonicalJson(header.toJson()));
    }

    // Read-modify-validate against what is on disk, the way an attempt is
    // appended: the log enforces contiguous sequence, forward time, and
    // conflicting-id detection, and those checks mean nothing against a copy.
    final log = await _loadAcquisition(profileId, null);
    if (!log.append(entry)) return;

    await _appendLine(file, canonicalJson(entry.toJson()));
  }

  @override
  Future<List<FeedbackExposure>> loadFeedbackExposures(String profileId) =>
      _queue.run(profileId, () => _loadFeedbackExposures(profileId));

  Future<List<FeedbackExposure>> _loadFeedbackExposures(
    String profileId,
  ) async {
    await _recoverErase(profileId);
    final file = _feedbackFile(profileId);
    if (!file.existsSync()) return const [];
    final contents = await _readCompleteContents(file);
    if (contents.isEmpty) return const [];
    try {
      final exposures = [
        for (final line in const LineSplitter().convert(contents))
          located(
            () => FeedbackExposure.fromJson(
              asMap(jsonDecode(line), 'feedback exposure', location: file.path),
            ),
            'feedback exposure',
            location: file.path,
          ),
      ];
      if (exposures.any((exposure) => exposure.profileId != profileId)) {
        throw JournalFormatException(
          'feedback exposure belongs to another profile',
          location: file.path,
        );
      }
      return exposures;
    } on FormatException catch (error) {
      throw JournalFormatException(
        'feedback exposure is not valid JSON: ${error.message}',
        location: file.path,
      );
    }
  }

  @override
  Future<void> appendFeedbackExposure(FeedbackExposure exposure) =>
      _queue.run(exposure.profileId, () => _appendFeedbackExposure(exposure));

  Future<void> _appendFeedbackExposure(FeedbackExposure exposure) async {
    await _recoverErase(exposure.profileId);
    final file = _feedbackFile(exposure.profileId);
    await file.parent.create(recursive: true);
    await truncateTornTail(file);
    final journal = await _loadJournal(exposure.profileId, null);
    if (!journal.records.any(
      (record) => record.identity.attemptId == exposure.attemptId,
    )) {
      throw StateError('feedback refers to an attempt that is not recorded');
    }
    final existing = await _loadFeedbackExposures(exposure.profileId);
    if (existing.any(
      (item) =>
          item.attemptId == exposure.attemptId &&
          item.postAttemptFeedback == exposure.postAttemptFeedback,
    )) {
      return;
    }
    await _appendLine(file, canonicalJson(exposure.toJson()));
  }

  @override
  Future<PendingDecision?> loadPendingDecision(String profileId) =>
      _queue.run(profileId, () => _loadPendingDecision(profileId));

  Future<PendingDecision?> _loadPendingDecision(String profileId) async {
    await _recoverErase(profileId);
    final file = _pendingFile(profileId);
    if (!file.existsSync()) return null;
    // Wrapped whole rather than field by field: the decode reaches domain
    // validation that throws on its own terms, and a reader of an untrusted
    // file should not have to learn which terms those are.
    final json = asMap(
      await _decode(file, 'pending decision'),
      'pending decision',
      location: file.path,
    );
    return located(
      () => PendingDecision.fromJson(json),
      'pending decision',
      location: file.path,
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
  Future<List<CoordinationSample>> loadCoordinationSamples(String profileId) =>
      _queue.run(profileId, () => _loadCoordinationSamples(profileId));

  @override
  Future<Map<String, String>> loadSelectionDiagnostics(String profileId) =>
      _queue.run(profileId, () => _loadSelectionDiagnostics(profileId));

  Future<Map<String, String>> _loadSelectionDiagnostics(
    String profileId,
  ) async {
    await _recoverErase(profileId);
    final file = _selectionFile(profileId);
    if (!file.existsSync()) return {};
    final contents = await _readCompleteContents(file);
    final samples = <String, String>{};
    try {
      for (final line in const LineSplitter().convert(contents)) {
        final json = asMap(
          jsonDecode(line),
          'selection diagnostic',
          location: file.path,
        );
        samples.putIfAbsent(
          requireString(json, 'attempt_id'),
          () => requireString(json, 'diagnostics'),
        );
      }
    } on FormatException catch (error) {
      throw JournalFormatException(
        'selection diagnostic is not valid JSON: ${error.message}',
        location: file.path,
      );
    }
    return samples;
  }

  @override
  Future<void> appendSelectionDiagnostics(
    String profileId,
    String attemptId,
    String diagnostics,
  ) => _queue.run(profileId, () async {
    final existing = await _loadSelectionDiagnostics(profileId);
    if (existing.containsKey(attemptId)) return;
    final file = _selectionFile(profileId);
    await file.parent.create(recursive: true);
    await truncateTornTail(file);
    await _appendLine(
      file,
      canonicalJson({'attempt_id': attemptId, 'diagnostics': diagnostics}),
    );
  });

  Future<List<CoordinationSample>> _loadCoordinationSamples(
    String profileId,
  ) async {
    await _recoverErase(profileId);
    final file = _coordinationFile(profileId);
    if (!file.existsSync()) return const [];
    final contents = await _readCompleteContents(file);
    if (contents.isEmpty) return const [];
    try {
      return [
        for (final line in const LineSplitter().convert(contents))
          located(
            () => CoordinationSample.fromJson(
              asMap(
                jsonDecode(line),
                'coordination sample',
                location: file.path,
              ),
            ),
            'coordination sample',
            location: file.path,
          ),
      ];
    } on FormatException catch (error) {
      throw JournalFormatException(
        'coordination sample is not valid JSON: ${error.message}',
        location: file.path,
      );
    }
  }

  @override
  Future<void> appendCoordinationSample(CoordinationSample sample) =>
      _queue.run(sample.profileId, () => _appendCoordinationSample(sample));

  Future<void> _appendCoordinationSample(CoordinationSample sample) async {
    await _recoverErase(sample.profileId);
    final file = _coordinationFile(sample.profileId);
    await file.parent.create(recursive: true);
    await truncateTornTail(file);
    final existing = await _loadCoordinationSamples(sample.profileId);
    if (existing.any((held) => held.attemptId == sample.attemptId)) return;
    await _appendLine(file, canonicalJson(sample.toJson()));
  }

  @override
  Future<PracticePlan?> loadPracticePlan(String profileId) =>
      _queue.run(profileId, () => _loadPracticePlan(profileId));

  Future<PracticePlan?> _loadPracticePlan(String profileId) async {
    await _recoverErase(profileId);
    final file = _planFile(profileId);
    if (!file.existsSync()) return null;
    final json = asMap(
      await _decode(file, 'practice plan'),
      'practice plan',
      location: file.path,
    );
    return located(
      () => PracticePlan.fromJson(json),
      'practice plan',
      location: file.path,
    );
  }

  @override
  Future<void> savePracticePlan(String profileId, PracticePlan plan) =>
      _queue.run(profileId, () => _savePracticePlan(profileId, plan));

  Future<void> _savePracticePlan(String profileId, PracticePlan plan) async {
    await _recoverErase(profileId);
    await _writeAtomically(_planFile(profileId), canonicalJson(plan.toJson()));
  }

  @override
  Future<LearnerStateCheckpoint?> loadCheckpoint(String profileId) =>
      _queue.run(profileId, () => _loadCheckpoint(profileId));

  Future<LearnerStateCheckpoint?> _loadCheckpoint(String profileId) async {
    await _recoverErase(profileId);
    final file = _checkpointFile(profileId);
    if (!file.existsSync()) return null;
    final json = asMap(
      await _decode(file, 'learner checkpoint'),
      'learner checkpoint',
      location: file.path,
    );
    return located(
      () => LearnerStateCheckpoint.fromJson(json, params: params),
      'learner checkpoint',
      location: file.path,
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

  /// Reads the records that were fully committed.
  ///
  /// A crash mid-append can leave a final record without its terminating
  /// newline. That attempt was never committed, so the torn tail is dropped.
  /// A malformed record anywhere *else* is real corruption of history and is
  /// left to fail loudly when parsed.
  /// Refuses a file whose header names a profile other than the one asked for.
  ///
  /// Ownership is identity, not history: a whole file copied into another
  /// profile's directory is internally consistent, every record agrees with
  /// its own header, and replay cannot tell that the person it describes is
  /// not the person who asked. Only the placement can say so, so the placement
  /// is checked.
  void _requireOwnership(String owner, String profileId, File file) {
    if (owner == profileId) return;
    throw JournalFormatException(
      'this history belongs to profile $owner, but it was found under '
      '$profileId',
      location: file.path,
    );
  }

  Future<String> _readCommittedLines(File file, String profileId) async {
    final committed = await readCommittedLines(file);
    if (committed.isEmpty) {
      throw JournalFormatException(
        'journal file for $profileId is empty',
        location: file.path,
      );
    }
    if (!committed.hasCompleteRecord) {
      throw JournalFormatException(
        'journal file for $profileId holds no complete record',
        location: file.path,
      );
    }
    return committed.text;
  }

  Future<String> _readCompleteContents(File file) async =>
      (await readCommittedLines(file)).text;

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
      _acquisitionFile(profileId),
      _pendingFile(profileId),
      _checkpointFile(profileId),
      _feedbackFile(profileId),
      _planFile(profileId),
      _coordinationFile(profileId),
      _selectionFile(profileId),
      File('${_pendingFile(profileId).path}.tmp'),
      File('${_checkpointFile(profileId).path}.tmp'),
      File('${_planFile(profileId).path}.tmp'),
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

  File _acquisitionFile(String profileId) =>
      File('${_profileDirectory(profileId).path}/acquisition.jsonl');

  File _pendingFile(String profileId) =>
      File('${_profileDirectory(profileId).path}/pending.json');

  File _checkpointFile(String profileId) =>
      File('${_profileDirectory(profileId).path}/checkpoint.json');

  File _coordinationFile(String profileId) =>
      File('${_profileDirectory(profileId).path}/coordination.jsonl');

  File _selectionFile(String profileId) =>
      File('${_profileDirectory(profileId).path}/selections.jsonl');

  File _planFile(String profileId) =>
      File('${_profileDirectory(profileId).path}/plan.json');

  File _feedbackFile(String profileId) =>
      File('${_profileDirectory(profileId).path}/feedback.jsonl');

  File _eraseMarker(String profileId) =>
      File('${_profileDirectory(profileId).path}/practice-erasing');
}
