import 'dart:convert';
import 'dart:io';

import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'profile_repository.dart';

/// A [ProfileRepository] backed by self-describing profile directories.
///
/// ```text
/// <root>/profiles.json          which profile is active
/// <root>/<profile-id>/
///   profile.json                who this is: the replay genesis
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
/// A directory is named by profile id permanently, so renaming rewrites one
/// small file and moves nothing. Every write goes to a temporary name and is
/// renamed over its target, so a reader sees one version or the other and
/// never a half-written one.
class FileProfileRepository implements ProfileRepository {
  /// Directory holding the index and the per-profile directories.
  final Directory root;

  final DateTime Function() _now;

  FileProfileRepository(this.root, {DateTime Function()? now})
    : _now = now ?? (() => DateTime.now().toUtc());

  /// A repository rooted at [path].
  factory FileProfileRepository.at(String path, {DateTime Function()? now}) =>
      FileProfileRepository(Directory(path), now: now);

  /// The file recording which profile is active.
  File get indexFile => File('${root.path}/profiles.json');

  /// Where [profileId] records itself.
  File profileFileFor(String profileId) =>
      File('${root.path}/${requireProfileId(profileId)}/profile.json');

  @override
  Future<List<Profile>> list() async => (await _read()).profiles;

  @override
  Future<Profile?> selected() async => (await _read()).selected;

  @override
  Future<Profile?> find(String profileId) async =>
      (await _read()).find(profileId);

  @override
  Future<Profile> create({
    required String displayName,
    required PlacementTier placement,
    DateTime? createdAt,
    String? presentationHint,
  }) async {
    final index = await _read();
    final profile = Profile.create(
      displayName: displayName,
      placement: placement,
      createdAt: createdAt ?? _now(),
      presentationHint: presentationHint,
    );
    await _write(
      ProfileIndex(
        profiles: [...index.profiles, profile],
        selectedProfileId: index.isEmpty ? profile.id : index.selectedProfileId,
      ),
    );
    return profile;
  }

  @override
  Future<Profile> rename(String profileId, String displayName) =>
      _replace(profileId, (profile) => profile.renamed(displayName));

  @override
  Future<Profile> restyle(String profileId, String? presentationHint) =>
      _replace(profileId, (profile) => profile.shownAs(presentationHint));

  /// Rewrites one profile's record of itself, leaving the selection alone.
  Future<Profile> _replace(
    String profileId,
    Profile Function(Profile) change,
  ) async {
    final index = await _read();
    final changed = change(_require(index, profileId));
    await _write(
      ProfileIndex(
        profiles: [
          for (final profile in index.profiles)
            profile.id == profileId ? changed : profile,
        ],
        selectedProfileId: index.selectedProfileId,
      ),
    );
    return changed;
  }

  @override
  Future<Profile> select(String profileId) async {
    final index = await _read();
    final profile = _require(index, profileId);
    await _write(
      ProfileIndex(profiles: index.profiles, selectedProfileId: profileId),
    );
    return profile;
  }

  @override
  Future<Profile> delete(String profileId) async {
    final index = await _read();
    final removed = _require(index, profileId);
    await _write(index.without(profileId));
    return removed;
  }

  Profile _require(ProfileIndex index, String profileId) {
    final profile = index.find(profileId);
    if (profile == null) {
      throw ArgumentError.value(profileId, 'profileId', 'no such profile');
    }
    return profile;
  }

  /// Assembles the roster from the profiles on disk, and the selection from
  /// the index.
  ///
  /// A missing directory or index is an install nobody has used yet. A file
  /// that exists and cannot be read is a different matter and fails: a profile
  /// is the genesis of a history, and a reader that skipped an unreadable one
  /// would present somebody with an install their practice had vanished from.
  ///
  /// A selection naming a profile that is no longer here is dropped rather
  /// than raised. It is the one piece of state here that is rewritable
  /// convenience, and a crash between removing a profile and rewriting the
  /// selection is exactly how it arises.
  Future<ProfileIndex> _read() async {
    if (!root.existsSync()) return ProfileIndex.empty();

    final profiles = <Profile>[];
    for (final entry in root.listSync().whereType<Directory>()) {
      final file = File('${entry.path}/profile.json');
      if (!file.existsSync()) continue;
      final profile = Profile.fromJson(
        asMap(_decode(file, 'profile'), 'profile', location: file.path),
      );
      // The directory name is where this profile's history is looked up, so a
      // record naming a different id would list a learner whose journal is
      // read from somewhere else.
      final directoryName = entry.path.split(Platform.pathSeparator).last;
      if (profile.id != directoryName) {
        throw JournalFormatException(
          'profile "${profile.id}" is stored in directory "$directoryName"',
          location: file.path,
        );
      }
      profiles.add(profile);
    }

    final selected = indexFile.existsSync()
        ? ProfileIndex.selectionFromJson(
            asMap(
              _decode(indexFile, 'profile index'),
              'profile index',
              location: indexFile.path,
            ),
          )
        : null;

    return ProfileIndex(
      profiles: profiles,
      selectedProfileId: profiles.any((profile) => profile.id == selected)
          ? selected
          : null,
    );
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

  /// Writes every profile beside its own history, then the selection.
  ///
  /// Profiles first, and the selection last, because the selection is the part
  /// that can be repaired by reading: a crash before it lands leaves everybody
  /// present with nobody active, which resolves itself.
  Future<void> _write(ProfileIndex index) async {
    await root.create(recursive: true);
    for (final profile in index.profiles) {
      final file = profileFileFor(profile.id);
      await file.parent.create(recursive: true);
      await _writeAtomically(file, canonicalJson(profile.toJson()));
    }
    for (final entry in root.listSync().whereType<Directory>()) {
      final id = entry.path.split(Platform.pathSeparator).last;
      if (index.find(id) != null) continue;
      final file = File('${entry.path}/profile.json');
      // Forgetting who somebody is takes their record of themselves with it.
      // Leaving it would make the roster resurrect them on the next scan, and
      // the history beside it becomes orphaned storage, which is what a
      // deleted profile's leftover practice already was.
      if (file.existsSync()) await file.delete();
    }
    await _writeAtomically(indexFile, canonicalJson(index.toJson()));
  }

  Future<void> _writeAtomically(File file, String contents) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(file.path);
  }
}
