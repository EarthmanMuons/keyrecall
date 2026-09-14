import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:meta/meta.dart';

/// Version of the profile lifetime wire format.
const int profileLifetimeSchemaVersion = 1;

/// Which incarnation of a profile may write.
///
/// A profile id says whose history a write belongs to. It does not say that
/// the history is still wanted: erasing and deleting both end a profile's
/// recorded practice while work started before them is still in flight, and an
/// id alone would let that work put back what was just destroyed.
///
/// So a lifetime is durable and it is replaced rather than cleared. Work
/// carries the lifetime it began under, and storage refuses anything naming an
/// incarnation that has been retired. Surviving the process is the point: an
/// interrupted deletion resumes against the incarnation it retired, not
/// against whatever a restart would have opened.
@immutable
class ProfileLifetime {
  /// Whose incarnation this is.
  final String profileId;

  /// Names this incarnation, and only this one.
  final String lifetimeId;

  const ProfileLifetime({required this.profileId, required this.lifetimeId});

  /// An incarnation nothing has held before.
  factory ProfileLifetime.next(String profileId) => ProfileLifetime(
    profileId: requireProfileId(profileId),
    lifetimeId: newProfileId(),
  );

  Map<String, Object?> toJson() => {
    'schema_version': profileLifetimeSchemaVersion,
    'profile_id': profileId,
    'lifetime_id': lifetimeId,
  };

  /// The lifetime recorded in [json].
  ///
  /// Throws [JournalFormatException] on anything unreadable. A lifetime is
  /// small and replaceable, but a caller that guessed at one would authorize
  /// writes it cannot account for.
  static ProfileLifetime fromJson(Map<String, Object?> json) {
    final version = requireInt(json, 'schema_version');
    if (version != profileLifetimeSchemaVersion) {
      throw JournalFormatException(
        'profile lifetime schema version $version is not readable by this '
        'build, which writes version $profileLifetimeSchemaVersion',
      );
    }
    return ProfileLifetime(
      profileId: requireString(json, 'profile_id'),
      lifetimeId: requireString(json, 'lifetime_id'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileLifetime &&
      other.profileId == profileId &&
      other.lifetimeId == lifetimeId;

  @override
  int get hashCode => Object.hash(profileId, lifetimeId);

  @override
  String toString() => 'ProfileLifetime($profileId, $lifetimeId)';
}

/// Raised when work holding a retired incarnation tries to persist.
///
/// Not a storage failure. The write is well formed and the profile may still
/// exist; what it no longer has is the standing to record anything, because
/// the history it was computed against has been erased.
@immutable
class RetiredProfileLifetime implements Exception {
  /// The incarnation the refused work was holding.
  final ProfileLifetime held;

  /// The incarnation that may write now, or null once the profile is gone.
  final ProfileLifetime? current;

  const RetiredProfileLifetime(this.held, this.current);

  @override
  String toString() =>
      'work for profile ${held.profileId} was accepted under an incarnation '
      'that has since been retired';
}
