import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:meta/meta.dart';

/// Version of the profile index wire format.
///
/// Independent of the attempt and checkpoint schemas: who the people are and
/// what they practiced change for different reasons.
const int profileIndexSchemaVersion = 1;

/// The durable list of profiles, and which one is active.
///
/// The authority on who exists. Directories on disk are not: a leftover
/// practice directory is not a person, and a name is not an identity.
@immutable
class ProfileIndex {
  /// Every profile, in a deterministic order.
  final List<Profile> profiles;

  /// The active profile, or null when none has been chosen.
  final String? selectedProfileId;

  ProfileIndex({required List<Profile> profiles, this.selectedProfileId})
    : profiles = List.unmodifiable(_ordered(profiles)) {
    final ids = profiles.map((profile) => profile.id).toSet();
    if (ids.length != profiles.length) {
      throw const JournalFormatException(
        'profile index holds duplicate profile ids',
      );
    }
    final selected = selectedProfileId;
    if (selected != null && !ids.contains(selected)) {
      throw JournalFormatException(
        'selected profile $selected is not in the index',
      );
    }
  }

  /// An index with nobody in it.
  factory ProfileIndex.empty() => ProfileIndex(profiles: const []);

  /// Oldest first, ties broken by id, so the order never depends on how the
  /// file happened to be written.
  static List<Profile> _ordered(List<Profile> profiles) =>
      [...profiles]..sort((a, b) {
        final byAge = a.createdAt.compareTo(b.createdAt);
        return byAge != 0 ? byAge : a.id.compareTo(b.id);
      });

  /// The profile with [profileId], or null.
  Profile? find(String profileId) {
    for (final profile in profiles) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  /// The active profile, or null.
  Profile? get selected {
    final id = selectedProfileId;
    return id == null ? null : find(id);
  }

  /// Whether anybody exists yet.
  bool get isEmpty => profiles.isEmpty;

  /// Writes the index.
  Map<String, Object?> toJson() => {
    'schema_version': profileIndexSchemaVersion,
    'selected_profile_id': selectedProfileId,
    'profiles': [for (final profile in profiles) profile.toJson()],
  };

  /// Reads an index back.
  ///
  /// Throws [JournalFormatException] on anything unreadable. A profile index
  /// that cannot be understood is not something to rebuild from directory
  /// names: an id is an identity, and guessing one would attach a person to
  /// somebody else's practice history.
  factory ProfileIndex.fromJson(Map<String, Object?> json) {
    final version = requireInt(json, 'schema_version');
    if (version != profileIndexSchemaVersion) {
      throw JournalFormatException(
        'profile index schema version $version is not readable by this build, '
        'which writes version $profileIndexSchemaVersion',
      );
    }

    const location = 'profile index';
    final entries = json['profiles'];
    if (entries is! List) {
      throw const JournalFormatException(
        'expected a list at "profiles"',
        location: location,
      );
    }

    return ProfileIndex(
      profiles: [
        for (final entry in entries)
          Profile.fromJson(asMap(entry, 'profile', location: location)),
      ],
      selectedProfileId: asOptionalString(
        json['selected_profile_id'],
        'selected_profile_id',
        location: location,
      ),
    );
  }

  @override
  String toString() =>
      'ProfileIndex(${profiles.length} profiles, '
      'selected: ${selectedProfileId ?? 'none'})';
}

/// Who uses this install, and who is using it now.
///
/// Deliberately separate from practice storage. A profile exists before it has
/// any history, and renaming or selecting one has no business touching the
/// attempt transaction. What connects them is only the profile id, which is
/// also what the per-profile practice storage is keyed on.
///
/// Deleting a profile is out of scope. It raises retention and recovery
/// questions that the first practice screen does not need answered, and adding
/// it later is easier than taking it back.
abstract interface class ProfileRepository {
  /// Every profile, oldest first.
  Future<List<Profile>> list();

  /// The active profile, or null when none has been chosen.
  Future<Profile?> selected();

  /// The profile with [profileId], or null.
  Future<Profile?> find(String profileId);

  /// Creates a profile and returns it.
  ///
  /// The id and creation instant are chosen once, here, and never change
  /// again. The first profile created becomes the active one, since an install
  /// with exactly one person should not need a separate selection step. Later
  /// ones do not: adding somebody must not quietly switch who is practicing.
  Future<Profile> create({
    required String displayName,
    DateTime? createdAt,
    String? presentationHint,
  });

  /// Changes a profile's display name, and nothing else.
  ///
  /// Identity, creation instant, and history are untouched, which is the point
  /// of an opaque id.
  ///
  /// Throws [ArgumentError] when no such profile exists.
  Future<Profile> rename(String profileId, String displayName);

  /// Makes [profileId] the active profile.
  ///
  /// Throws [ArgumentError] when no such profile exists, since a selection
  /// pointing at nobody would leave the app with no defined learner.
  Future<Profile> select(String profileId);
}

/// The name a profile gets when the app creates one without asking.
///
/// Reads naturally beside real names in a switcher, and a caller with a
/// localized string should pass its own.
const String defaultProfileName = 'Me';

/// Conveniences every [ProfileRepository] gets for free.
extension ProfileRepositoryDefaults on ProfileRepository {
  /// The active profile, creating a default one if this install has none.
  ///
  /// A first launch should not open with a decision. One person on one
  /// instrument is the ordinary case, and profiles only become a choice worth
  /// making when somebody wants a second. So the app calls this and gets a
  /// learner either way; adding a profile stays an action, never a prerequisite.
  ///
  /// If profiles exist but none is selected, the oldest is selected rather than
  /// a new one being made. That state should not arise, but inventing another
  /// person to resolve it would be the worse repair.
  Future<Profile> selectedOrDefault({
    String displayName = defaultProfileName,
  }) async {
    final active = await selected();
    if (active != null) return active;

    final existing = await list();
    if (existing.isNotEmpty) return select(existing.first.id);

    return create(displayName: displayName);
  }
}

/// A [ProfileRepository] holding everything in memory.
class InMemoryProfileRepository implements ProfileRepository {
  ProfileIndex _index;

  /// The clock used when a caller does not supply a creation instant.
  final DateTime Function() _now;

  InMemoryProfileRepository({ProfileIndex? index, DateTime Function()? now})
    : _index = index ?? ProfileIndex.empty(),
      _now = now ?? (() => DateTime.now().toUtc());

  /// The current index, for tests and for saving elsewhere.
  ProfileIndex get index => _index;

  @override
  Future<List<Profile>> list() async => _index.profiles;

  @override
  Future<Profile?> selected() async => _index.selected;

  @override
  Future<Profile?> find(String profileId) async => _index.find(profileId);

  @override
  Future<Profile> create({
    required String displayName,
    DateTime? createdAt,
    String? presentationHint,
  }) async {
    final profile = Profile.create(
      displayName: displayName,
      createdAt: createdAt ?? _now(),
      presentationHint: presentationHint,
    );
    _index = ProfileIndex(
      profiles: [..._index.profiles, profile],
      selectedProfileId: _index.isEmpty ? profile.id : _index.selectedProfileId,
    );
    return profile;
  }

  @override
  Future<Profile> rename(String profileId, String displayName) async {
    final existing = _requireProfile(profileId);
    final renamed = existing.renamed(displayName);
    _index = ProfileIndex(
      profiles: [
        for (final profile in _index.profiles)
          profile.id == profileId ? renamed : profile,
      ],
      selectedProfileId: _index.selectedProfileId,
    );
    return renamed;
  }

  @override
  Future<Profile> select(String profileId) async {
    final profile = _requireProfile(profileId);
    _index = ProfileIndex(
      profiles: _index.profiles,
      selectedProfileId: profileId,
    );
    return profile;
  }

  Profile _requireProfile(String profileId) {
    final profile = _index.find(profileId);
    if (profile == null) {
      throw ArgumentError.value(profileId, 'profileId', 'no such profile');
    }
    return profile;
  }
}
