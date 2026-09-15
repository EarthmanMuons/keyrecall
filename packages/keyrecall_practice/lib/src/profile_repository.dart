import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
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

  /// This index without [profileId], and with the selection resolved.
  ///
  /// Removing somebody who was not selected leaves the selection alone.
  /// Removing the selected profile hands the selection to the oldest of those
  /// left, because the app has to run as somebody. Removing the last profile
  /// leaves nothing selected: an index does not invent a person to keep the
  /// slot filled.
  ///
  /// Removing a profile that is not here returns the same index, so the two
  /// repositories can raise that as an error the same way, in their own words.
  ProfileIndex without(String profileId) {
    final remaining = [
      for (final profile in profiles)
        if (profile.id != profileId) profile,
    ];
    return ProfileIndex(
      profiles: remaining,
      selectedProfileId: selectedProfileId != profileId
          ? selectedProfileId
          : (remaining.isEmpty ? null : remaining.first.id),
    );
  }

  /// Writes the part of an index that is not derivable from the profiles
  /// themselves.
  ///
  /// Which profiles exist is not written here. A profile records itself beside
  /// its own history, so this file answers only the question nothing else can:
  /// which of them is active. That makes it convenience state, and losing it
  /// costs a selection rather than an identity.
  Map<String, Object?> toJson() => {
    'schema_version': profileIndexSchemaVersion,
    'selected_profile_id': selectedProfileId,
  };

  /// The selection recorded in [json], or null when there is none.
  ///
  /// Throws [JournalFormatException] on anything unreadable. A selection is
  /// small and rewritable, but a version this build does not know is still a
  /// file it must not guess at.
  static String? selectionFromJson(Map<String, Object?> json) {
    final version = requireInt(json, 'schema_version');
    if (version != profileIndexSchemaVersion) {
      throw JournalFormatException(
        'profile index schema version $version is not readable by this build, '
        'which writes version $profileIndexSchemaVersion',
      );
    }
    return asOptionalString(
      json['selected_profile_id'],
      'selected_profile_id',
      location: 'profile index',
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
/// Deleting removes the profile record and nothing else. The practice storage
/// keyed on that id lives behind the other port.
abstract interface class ProfileRepository {
  /// Every profile, oldest first.
  Future<List<Profile>> list();

  /// The active profile, or null when none has been chosen.
  Future<Profile?> selected();

  /// The profile with [profileId], or null.
  Future<Profile?> find(String profileId);

  /// Creates a profile's record of itself, and nothing else.
  ///
  /// One durable fact, so a caller that is told it happened knows exactly what
  /// is on disk. Selecting the new profile is [select], and sequencing the two
  /// is [ProfileLifecycle.create]: creating even the first profile does not
  /// establish a selection here, because a create that wrote the genesis and
  /// then failed to write the selection would have to report itself as having
  /// done nothing.
  ///
  /// The id and creation instant are chosen once, here, and never change
  /// again. [placement] is where this learner's competency estimates start,
  /// and it is fixed here for the life of the profile: it is the initial
  /// condition every later posterior is computed from, so changing it would
  /// reinterpret the history rather than update it.
  Future<Profile> create({
    required String displayName,
    required PlacementTier placement,
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

  /// Changes a profile's presentation hint, and nothing else.
  ///
  /// Throws [ArgumentError] when no such profile exists.
  Future<Profile> restyle(String profileId, String? presentationHint);

  /// Makes [profileId] the active profile.
  ///
  /// Throws [ArgumentError] when no such profile exists, since a selection
  /// pointing at nobody would leave the app with no defined learner.
  Future<Profile> select(String profileId);

  /// The active profile, the oldest one when profiles exist but none is
  /// selected, or null when this install has nobody on it.
  ///
  /// Deliberately does not create anybody. A profile carries an immutable
  /// placement, so one conjured to keep the slot filled is a learner started
  /// from a prior nobody chose and nobody can change afterwards.
  ///
  /// Profiles existing with none selected is the one case repaired here, by
  /// choosing among the people who already exist. The repair writes the
  /// selection and nothing else, and it is serialized with every other
  /// mutation: two startup readers repairing at once must not both decide.
  Future<Profile?> selectedOrOldest();

  /// Forgets which profile is active, leaving everybody in place.
  ///
  /// The repair for selection metadata this build cannot read. It destroys
  /// nothing anybody practiced: [selectedOrOldest] chooses among the people
  /// who already exist, and the answer is written back.
  Future<void> clearSelection();

  /// Records the intent to delete [profileId], durably, before anything of
  /// theirs is destroyed.
  ///
  /// The first step of a deletion and the one that makes the rest resumable. A
  /// profile under a recorded intent is no longer on the roster, and a crash
  /// after this leaves an install that can finish the job rather than history
  /// nothing identifies.
  ///
  /// Idempotent: an intent that already stands and validates is left alone.
  /// This returns successfully only having written a valid intent or having
  /// read one belonging to this profile, because what waits on it returning is
  /// the destruction of that profile's history.
  ///
  /// Throws [ArgumentError] when no such profile exists and none is being
  /// deleted.
  Future<void> beginDelete(String profileId);

  /// Every profile this install began deleting and has not finished.
  Future<List<String>> pendingDeletions();

  /// Removes [profileId]'s record of itself, and the intent that named it.
  ///
  /// The last step of a deletion, run once the practice store has erased what
  /// the profile recorded. Idempotent, so a resumed deletion can start from
  /// wherever the interrupted one stopped.
  ///
  /// Deleting the active profile moves the selection to the oldest remaining
  /// one, since the app has to run as somebody. Deleting the last profile is
  /// the one case that leaves nothing selected, and [selectedOrOldest] reports
  /// that rather than inventing a person.
  Future<void> finishDelete(String profileId);

  /// Forgets [profileId], and returns the profile that was removed.
  ///
  /// Only the profile's own record goes. Erasing the practice history is a
  /// separate call to the practice store, because forgetting who somebody is
  /// and destroying what they played are different decisions; [ProfileLifecycle]
  /// is what orders the two.
  ///
  /// Throws [ArgumentError] when no such profile exists.
  Future<Profile> delete(String profileId);
}

/// The name a profile gets when the app creates one without asking for one.
///
/// Reads naturally beside real names in a switcher, and a caller with a
/// localized string should pass its own.
const String defaultProfileName = 'Me';

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
  Future<List<Profile>> list() async => [
    for (final profile in _index.profiles)
      if (!_deleting.contains(profile.id)) profile,
  ];

  @override
  Future<Profile?> selected() async {
    final active = _index.selected;
    return active == null || _deleting.contains(active.id) ? null : active;
  }

  @override
  Future<Profile?> find(String profileId) async =>
      _deleting.contains(profileId) ? null : _index.find(profileId);

  @override
  Future<Profile> create({
    required String displayName,
    required PlacementTier placement,
    DateTime? createdAt,
    String? presentationHint,
  }) async {
    final profile = Profile.create(
      displayName: displayName,
      placement: placement,
      createdAt: createdAt ?? _now(),
      presentationHint: presentationHint,
    );
    _index = ProfileIndex(
      profiles: [..._index.profiles, profile],
      selectedProfileId: _index.selectedProfileId,
    );
    return profile;
  }

  @override
  Future<Profile> rename(String profileId, String displayName) async =>
      _replace(profileId, (profile) => profile.renamed(displayName));

  @override
  Future<Profile> restyle(String profileId, String? presentationHint) async =>
      _replace(profileId, (profile) => profile.shownAs(presentationHint));

  Profile _replace(String profileId, Profile Function(Profile) change) {
    final changed = change(_requireProfile(profileId));
    _index = ProfileIndex(
      profiles: [
        for (final profile in _index.profiles)
          profile.id == profileId ? changed : profile,
      ],
      selectedProfileId: _index.selectedProfileId,
    );
    return changed;
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

  @override
  Future<Profile?> selectedOrOldest() async {
    final active = await selected();
    if (active != null) return active;
    final existing = await list();
    if (existing.isEmpty) return null;
    return select(existing.first.id);
  }

  @override
  Future<void> clearSelection() async {
    _index = ProfileIndex(profiles: _index.profiles);
  }

  @override
  Future<void> beginDelete(String profileId) async {
    if (_deleting.contains(profileId)) return;
    _requireProfile(profileId);
    _deleting.add(profileId);
  }

  @override
  Future<List<String>> pendingDeletions() async => List.unmodifiable(_deleting);

  @override
  Future<void> finishDelete(String profileId) async {
    _index = _index.without(profileId);
    _deleting.remove(profileId);
  }

  @override
  Future<Profile> delete(String profileId) async {
    final removed = _requireProfile(profileId);
    await beginDelete(profileId);
    await finishDelete(profileId);
    return removed;
  }

  /// Profiles whose deletion has been recorded and not finished.
  final Set<String> _deleting = {};

  Profile _requireProfile(String profileId) {
    final profile = _deleting.contains(profileId)
        ? null
        : _index.find(profileId);
    if (profile == null) {
      throw ArgumentError.value(profileId, 'profileId', 'no such profile');
    }
    return profile;
  }
}
