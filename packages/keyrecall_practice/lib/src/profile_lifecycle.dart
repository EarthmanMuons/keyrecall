import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

import 'practice_store.dart';
import 'profile_repository.dart';

/// What came of asking for a profile.
///
/// Creating one is two durable facts, not one: the profile exists, and it is
/// the active profile. A caller told only that the whole thing failed would
/// retry it, and retrying a create makes a second person.
@immutable
sealed class ProfileCreation {
  const ProfileCreation();
}

/// Both steps landed.
@immutable
class ProfileCreated extends ProfileCreation {
  /// Who was created.
  final Profile profile;

  const ProfileCreated(this.profile);
}

/// The profile exists, and selecting it did not land.
///
/// Carries the identity, so finishing is [ProfileLifecycle.finishCreating] on
/// that same person rather than another run at creating one.
@immutable
class ProfileSelectionPending extends ProfileCreation {
  /// Who was created, and is waiting to be practiced as.
  final Profile profile;

  /// What stopped the selection.
  final Object cause;

  const ProfileSelectionPending(this.profile, this.cause);
}

/// Nothing was created, so nothing is owed.
@immutable
class ProfileNotCreated extends ProfileCreation {
  /// What stopped it.
  final Object cause;

  const ProfileNotCreated(this.cause);
}

/// Who exists on this install, and what each of them may still write.
///
/// The one place a profile's identity and its history are changed together.
/// The repository owns genesis and selection, the store owns practice, and
/// nothing below this knows that creating, erasing, and deleting are each a
/// sequence over both. Held apart they were: a deletion that removed the
/// genesis first left history nobody could name, and a create that failed
/// halfway left an identity the retry could not find.
class ProfileLifecycle {
  /// Who exists, and who is active.
  final ProfileRepository repository;

  /// What they have practiced.
  final PracticeStore store;

  const ProfileLifecycle({required this.repository, required this.store});

  /// Creates a profile, and practices as it when [selecting].
  ///
  /// [placement] is fixed for the life of the profile, because it is the prior
  /// the whole history is computed from: changing it would reinterpret every
  /// attempt rather than update a skill level.
  Future<ProfileCreation> create({
    required String displayName,
    required PlacementTier placement,
    String? presentationHint,
    DateTime? createdAt,
    bool selecting = true,
  }) async {
    final Profile created;
    try {
      created = await repository.create(
        displayName: displayName,
        placement: placement,
        createdAt: createdAt,
        presentationHint: presentationHint,
      );
    } catch (error) {
      return ProfileNotCreated(error);
    }
    return selecting ? finishCreating(created) : ProfileCreated(created);
  }

  /// Practices as [profile], which already exists.
  ///
  /// The unfinished half of a create whose selection did not land.
  Future<ProfileCreation> finishCreating(Profile profile) async {
    try {
      await repository.select(profile.id);
    } catch (error) {
      return ProfileSelectionPending(profile, error);
    }
    return ProfileCreated(profile);
  }

  /// Places the learner this install has not asked about yet.
  ///
  /// Placing an install that already has somebody on it returns them
  /// unchanged, because the question was already answered and a second answer
  /// would be one the history cannot honor.
  Future<ProfileCreation> place(
    PlacementTier placement, {
    String displayName = defaultProfileName,
    String? presentationHint,
  }) async {
    final Profile? existing;
    try {
      existing = await repository.selectedOrOldest();
    } catch (error) {
      return ProfileNotCreated(error);
    }
    if (existing != null) return ProfileCreated(existing);
    return create(
      displayName: displayName,
      placement: placement,
      presentationHint: presentationHint,
    );
  }

  /// Erases one profile's recorded practice, keeping the profile itself.
  ///
  /// The placement survives, because it is who this profile was when it was
  /// created rather than something the history taught. Starting from a
  /// different tier means a different profile.
  ///
  /// Retires the incarnation as part of the same operation, so work accepted
  /// before this cannot record the erased history again.
  Future<void> eraseHistory(String profileId) => store.erase(profileId);

  /// Deletes a profile and everything it recorded.
  ///
  /// Intent first, so an interruption anywhere after it leaves a deletion the
  /// next startup finishes rather than history nothing identifies. Every step
  /// after it is idempotent, and the profile is off the roster from the moment
  /// the intent is durable.
  Future<void> delete(String profileId) async {
    await repository.beginDelete(profileId);
    await _finishDeleting(profileId);
  }

  /// Finishes every deletion this install began and did not complete.
  ///
  /// Called at startup, before anything decides who is active. Returns the
  /// profiles that were finished, which is empty on the ordinary launch.
  Future<List<String>> resumeDeletions() async {
    final pending = await repository.pendingDeletions();
    for (final profileId in pending) {
      await _finishDeleting(profileId);
    }
    return pending;
  }

  /// Destroys the history, then the genesis, then the intent.
  ///
  /// History first because the genesis is what names it: removing the record
  /// of who somebody is before their practice is gone leaves storage no later
  /// pass can attribute.
  Future<void> _finishDeleting(String profileId) async {
    await store.forget(profileId);
    await repository.finishDelete(profileId);
  }
}
