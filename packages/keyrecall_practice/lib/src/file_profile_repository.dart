import 'dart:convert';
import 'dart:io';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'profile_repository.dart';

/// A [ProfileRepository] backed by a single index file.
///
/// ```text
/// <root>/profiles.json     who exists, and who is active
/// <root>/<profile-id>/     that person's practice storage
/// ```
///
/// The index is the authority on who exists. This never scans for directories:
/// a leftover practice directory is not a person, and rebuilding names from
/// directory ids would attach somebody to a history that is not theirs. A
/// directory is named by profile id permanently, so renaming touches only the
/// index and never moves anything, and deleting an entry leaves whatever
/// practice storage that id had: erasing that is the practice store's call and
/// not this one's.
///
/// Writes go to a temporary name and are renamed over the target, so a reader
/// sees the old index or the new one and never a half-written one.
class FileProfileRepository implements ProfileRepository {
  /// Directory holding the index and the per-profile directories.
  final Directory root;

  final DateTime Function() _now;

  FileProfileRepository(this.root, {DateTime Function()? now})
    : _now = now ?? (() => DateTime.now().toUtc());

  /// A repository rooted at [path].
  factory FileProfileRepository.at(String path, {DateTime Function()? now}) =>
      FileProfileRepository(Directory(path), now: now);

  /// The index file this repository reads and writes.
  File get indexFile => File('${root.path}/profiles.json');

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
    DateTime? createdAt,
    String? presentationHint,
  }) async {
    final index = await _read();
    final profile = Profile.create(
      displayName: displayName,
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
  Future<Profile> rename(String profileId, String displayName) async {
    final index = await _read();
    final existing = _require(index, profileId);
    final renamed = existing.renamed(displayName);
    await _write(
      ProfileIndex(
        profiles: [
          for (final profile in index.profiles)
            profile.id == profileId ? renamed : profile,
        ],
        selectedProfileId: index.selectedProfileId,
      ),
    );
    return renamed;
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

  /// Reads the index, treating a missing file as an install nobody has used.
  ///
  /// A file that exists but cannot be read is a different matter, and fails.
  Future<ProfileIndex> _read() async {
    final file = indexFile;
    if (!file.existsSync()) return ProfileIndex.empty();

    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException catch (error) {
      throw JournalFormatException(
        'profile index is not valid JSON: ${error.message}',
        location: file.path,
      );
    }
    return ProfileIndex.fromJson(
      asMap(decoded, 'profile index', location: file.path),
    );
  }

  Future<void> _write(ProfileIndex index) async {
    await root.create(recursive: true);
    final temporary = File('${indexFile.path}.tmp');
    await temporary.writeAsString(canonicalJson(index.toJson()), flush: true);
    await temporary.rename(indexFile.path);
  }
}
