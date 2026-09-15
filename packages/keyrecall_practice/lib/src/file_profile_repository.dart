import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

import 'profile_repository.dart';

/// Which durable profile artifact could not be read.
enum ProfileArtifact {
  /// The file recording which profile is active.
  ///
  /// Rewritable convenience: losing it costs a selection rather than an
  /// identity, so repairing it destroys nothing anybody practiced.
  selection,

  /// A profile's own record of itself, which is the genesis of a history.
  ///
  /// Nothing here can be rebuilt. The creation instant anchors placement, and
  /// placement is the prior every later posterior descends from.
  genesis,

  /// A deletion this install began and has not finished.
  ///
  /// A durable command rather than a flag, which is why it is read like one.
  /// Its presence is what authorizes destroying a history, so one that cannot
  /// be read is refused rather than obeyed or ignored.
  deletionIntent,
}

/// Version of the deletion intent wire format.
const int profileDeletionSchemaVersion = 1;

/// A deletion this install recorded and has not finished.
///
/// Read and validated before it means anything. A file named `deleting.json`
/// is not a decision somebody made about this profile until it says so: it can
/// be a copy of another profile's, or written by a build that meant something
/// else by it, and either would authorize destroying the wrong history.
@immutable
class ProfileDeletionIntent {
  /// Whose deletion this is.
  final String profileId;

  const ProfileDeletionIntent(this.profileId);

  Map<String, Object?> toJson() => {
    'schema_version': profileDeletionSchemaVersion,
    'profile_id': profileId,
  };

  /// The intent recorded in [json], for the profile stored at [directoryName].
  ///
  /// Throws [JournalFormatException] on anything unreadable, and on an intent
  /// naming somebody other than the profile it was found under: that is a
  /// command addressed to a history somewhere else.
  static ProfileDeletionIntent fromJson(
    Map<String, Object?> json, {
    required String directoryName,
  }) {
    final version = requireInt(json, 'schema_version');
    if (version != profileDeletionSchemaVersion) {
      throw JournalFormatException(
        'deletion intent schema version $version is not readable by this '
        'build, which writes version $profileDeletionSchemaVersion',
      );
    }
    final profileId = requireString(json, 'profile_id');
    if (profileId != directoryName) {
      throw JournalFormatException(
        'a deletion recorded for profile "$profileId" is stored in directory '
        '"$directoryName"',
      );
    }
    return ProfileDeletionIntent(profileId);
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileDeletionIntent && other.profileId == profileId;

  @override
  int get hashCode => profileId.hashCode;

  @override
  String toString() => 'ProfileDeletionIntent($profileId)';
}

/// A profile artifact that could not be read, and which one it was.
///
/// Raised instead of a bare format error so a recovery has something to act
/// on. An unreadable selection and an unreadable genesis both stop an install
/// from opening, and the ways out of them have nothing in common.
class ProfileStorageException implements Exception {
  /// Which artifact failed.
  final ProfileArtifact artifact;

  /// Whose artifact it was, where the failure identifies somebody.
  final String? profileId;

  /// What actually went wrong.
  final Object cause;

  const ProfileStorageException(this.artifact, this.cause, {this.profileId});

  @override
  String toString() => '$cause';
}

/// A [ProfileRepository] backed by self-describing profile directories.
///
/// ```text
/// <root>/profiles.json          which profile is active
/// <root>/<profile-id>/
///   profile.json                who this is: the replay genesis
///   deleting.json               a deletion begun and not finished
///   journal.jsonl               what they played
///   checkpoint.json
/// ```
///
/// Each profile records itself beside its own history, and that is the
/// authority on who exists. The invariant worth stating:
///
/// > a directory holding a valid `profile.json` and journal is enough to
/// > reopen that learner, with no file outside it.
///
/// Which matters because the genesis is tiny and the history it governs is
/// not: a profile's creation instant anchors placement, and placement is the
/// prior every posterior descends from, so one shared file holding the only
/// copy of both could strand every profile's intact evidence.
///
/// The roster is therefore scanned rather than stored, and `profiles.json`
/// holds only the selection. Scanning reads each profile's own record of itself
/// rather than guessing from directory names, so a directory with no
/// `profile.json` is orphaned storage rather than a person.
///
/// Every operation writes only what it owns: selecting writes the selection,
/// renaming rewrites one profile, and deleting removes its explicit target. A
/// directory is named by profile id permanently, so renaming moves nothing.
/// Mutations are serialized against each other, and each write goes to a
/// temporary name of its own and is renamed over its target, so a reader sees
/// one version or the other and never a half-written one.
class FileProfileRepository implements ProfileRepository {
  /// Directory holding the index and the per-profile directories.
  final Directory root;

  final DateTime Function() _now;

  /// What every mutation queues behind.
  ///
  /// One lock for the whole repository rather than one per profile: the
  /// selection is shared state, and a create that establishes it races a
  /// repair that rewrites it.
  Future<void> _mutations = Future<void>.value();

  /// Names this instance's temporary files apart from anybody else's.
  int _temporaries = 0;

  FileProfileRepository(this.root, {DateTime Function()? now})
    : _now = now ?? (() => DateTime.now().toUtc());

  /// A repository rooted at [path].
  factory FileProfileRepository.at(String path, {DateTime Function()? now}) =>
      FileProfileRepository(Directory(path), now: now);

  /// The file recording which profile is active.
  File get indexFile => File('${root.path}/profiles.json');

  /// Where [profileId] records itself.
  File profileFileFor(String profileId) =>
      File('${_directoryFor(profileId).path}/profile.json');

  @override
  Future<List<Profile>> list() async => _readProfiles();

  @override
  Future<Profile?> selected() async {
    final id = await _readSelection();
    if (id == null) return null;
    for (final profile in await _readProfiles()) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  @override
  Future<Profile?> find(String profileId) async {
    for (final profile in await _readProfiles()) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  @override
  Future<Profile> create({
    required String displayName,
    required PlacementTier placement,
    DateTime? createdAt,
    String? presentationHint,
  }) => _serialize(() async {
    final profile = Profile.create(
      displayName: displayName,
      placement: placement,
      createdAt: createdAt ?? _now(),
      presentationHint: presentationHint,
    );
    await _writeProfile(profile);
    return profile;
  });

  @override
  Future<Profile> rename(String profileId, String displayName) => _serialize(
    () => _replace(profileId, (profile) => profile.renamed(displayName)),
  );

  @override
  Future<Profile> restyle(String profileId, String? presentationHint) =>
      _serialize(
        () =>
            _replace(profileId, (profile) => profile.shownAs(presentationHint)),
      );

  /// Rewrites one profile's record of itself, and no other file.
  Future<Profile> _replace(
    String profileId,
    Profile Function(Profile) change,
  ) async {
    final changed = change(await _require(profileId));
    await _writeProfile(changed);
    return changed;
  }

  @override
  Future<Profile> select(String profileId) => _serialize(() async {
    final profile = await _require(profileId);
    await _writeSelection(profileId);
    return profile;
  });

  @override
  Future<Profile?> selectedOrOldest() => _serialize(() async {
    final profiles = await _readProfiles();
    final id = await _readSelection();
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    if (profiles.isEmpty) return null;
    await _writeSelection(profiles.first.id);
    return profiles.first;
  });

  @override
  Future<void> clearSelection() => _serialize(() async {
    if (indexFile.existsSync()) await indexFile.delete();
  });

  @override
  Future<void> beginDelete(String profileId) => _serialize(() async {
    // Through the same reader as everything else, and before the roster is
    // consulted: a deletion already recorded has taken this profile off it.
    // Returning on the file merely being there would make this the one way
    // past validation, and what waits on this returning is the destruction.
    if (_readDeletion(_directoryFor(profileId)) != null) return;
    await _require(profileId);
    await _writeAtomically(
      _deletionFileFor(profileId),
      canonicalJson(ProfileDeletionIntent(profileId).toJson()),
    );
  });

  @override
  Future<List<String>> pendingDeletions() async {
    if (!root.existsSync()) return const [];
    return [
      for (final entry in root.listSync().whereType<Directory>())
        if (_readDeletion(entry) case final intent?) intent.profileId,
    ]..sort();
  }

  /// The deletion recorded in [directory], or null where it records none.
  ///
  /// The single reading of that file, so what takes a profile off the roster
  /// and what authorizes destroying its history are the same judgement. A
  /// marker that does not validate is neither: it fails, rather than hiding a
  /// profile nothing will ever finish removing.
  ProfileDeletionIntent? _readDeletion(Directory directory) {
    final file = File('${directory.path}/deleting.json');
    if (!file.existsSync()) return null;
    final directoryName = directory.path.split(Platform.pathSeparator).last;
    return _located(
      ProfileArtifact.deletionIntent,
      profileId: directoryName,
      () => ProfileDeletionIntent.fromJson(
        asMap(
          _decode(file, 'deletion intent'),
          'deletion intent',
          location: file.path,
        ),
        directoryName: directoryName,
      ),
    );
  }

  @override
  Future<void> finishDelete(String profileId) => _serialize(() async {
    await _finishDelete(profileId);
  });

  @override
  Future<Profile> delete(String profileId) => _serialize(() async {
    final profile = await _require(profileId);
    await _writeAtomically(
      _deletionFileFor(profileId),
      canonicalJson(ProfileDeletionIntent(profileId).toJson()),
    );
    await _finishDelete(profileId);
    return profile;
  });

  /// Removes the genesis, repairs the selection, and drops the intent.
  ///
  /// In that order, and each step idempotent, so an interruption anywhere
  /// leaves a deletion the next call finishes rather than one that has to be
  /// started again.
  Future<void> _finishDelete(String profileId) async {
    final genesis = profileFileFor(profileId);
    if (genesis.existsSync()) await genesis.delete();

    if (await _readSelection() == profileId) {
      final remaining = await _readProfiles();
      if (remaining.isEmpty) {
        if (indexFile.existsSync()) await indexFile.delete();
      } else {
        await _writeSelection(remaining.first.id);
      }
    }

    final marker = _deletionFileFor(profileId);
    if (marker.existsSync()) await marker.delete();

    // The directory goes only once nothing is left in it. Anything still
    // there was not this repository's to remove, and a leftover file is
    // somebody's evidence until whoever wrote it says otherwise.
    final directory = _directoryFor(profileId);
    if (directory.existsSync() && directory.listSync().isEmpty) {
      await directory.delete();
    }
  }

  Future<Profile> _require(String profileId) async {
    final profile = await find(profileId);
    if (profile == null) {
      throw ArgumentError.value(profileId, 'profileId', 'no such profile');
    }
    return profile;
  }

  /// Runs [operation] once every mutation already accepted has finished.
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final done = Completer<void>();
    final waitFor = _mutations;
    _mutations = done.future;
    return waitFor.then((_) => operation()).whenComplete(() => done.complete());
  }

  /// The roster, oldest first, read from each profile's record of itself.
  ///
  /// A missing directory is an install nobody has used yet. A genesis that
  /// exists and cannot be read is a different matter and fails: a reader that
  /// skipped an unreadable one would present somebody with an install their
  /// practice had vanished from.
  ///
  /// A profile under a recorded deletion is not on the roster. The decision to
  /// forget them is already durable, and listing them would offer somebody a
  /// person the next startup finishes removing.
  Future<List<Profile>> _readProfiles() async {
    if (!root.existsSync()) return const [];

    final profiles = <Profile>[];
    for (final entry in root.listSync().whereType<Directory>()) {
      final directoryName = entry.path.split(Platform.pathSeparator).last;
      if (_readDeletion(entry) != null) continue;
      final file = File('${entry.path}/profile.json');
      if (!file.existsSync()) continue;
      final profile = _located(
        ProfileArtifact.genesis,
        profileId: directoryName,
        () => Profile.fromJson(
          asMap(_decode(file, 'profile'), 'profile', location: file.path),
        ),
      );
      // The directory name is where this profile's history is looked up, so a
      // record naming a different id would list a learner whose journal is
      // read from somewhere else.
      if (profile.id != directoryName) {
        throw ProfileStorageException(
          ProfileArtifact.genesis,
          JournalFormatException(
            'profile "${profile.id}" is stored in directory "$directoryName"',
            location: file.path,
          ),
          profileId: directoryName,
        );
      }
      profiles.add(profile);
    }

    return ProfileIndex(profiles: profiles).profiles;
  }

  /// The recorded selection, whether or not it names anybody who exists.
  Future<String?> _readSelection() async {
    if (!indexFile.existsSync()) return null;
    return _located(
      ProfileArtifact.selection,
      () => ProfileIndex.selectionFromJson(
        asMap(
          _decode(indexFile, 'profile index'),
          'profile index',
          location: indexFile.path,
        ),
      ),
    );
  }

  T _located<T>(
    ProfileArtifact artifact,
    T Function() read, {
    String? profileId,
  }) {
    try {
      return read();
    } on ProfileStorageException {
      rethrow;
    } catch (error) {
      throw ProfileStorageException(artifact, error, profileId: profileId);
    }
  }

  Object? _decode(File file, String what) {
    try {
      return jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      throw JournalFormatException(
        '$what is not valid JSON: ${error.message}',
        location: file.path,
      );
    }
  }

  Future<void> _writeProfile(Profile profile) async {
    final file = profileFileFor(profile.id);
    await file.parent.create(recursive: true);
    await _writeAtomically(file, canonicalJson(profile.toJson()));
  }

  Future<void> _writeSelection(String? profileId) async {
    await root.create(recursive: true);
    await _writeAtomically(
      indexFile,
      canonicalJson({
        'schema_version': profileIndexSchemaVersion,
        'selected_profile_id': profileId,
      }),
    );
  }

  Future<void> _writeAtomically(File file, String contents) async {
    await file.parent.create(recursive: true);
    // A name of its own per write. A shared one lets two writers rename the
    // same temporary over different targets, and the loser's rename fails
    // against a file that is no longer there.
    final temporary = File(
      '${file.path}.${identityHashCode(this)}-${_temporaries++}.tmp',
    );
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(file.path);
  }

  Directory _directoryFor(String profileId) =>
      Directory('${root.path}/${requireProfileId(profileId)}');

  File _deletionFileFor(String profileId) =>
      File('${_directoryFor(profileId).path}/deleting.json');
}
