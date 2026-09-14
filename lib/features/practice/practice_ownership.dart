import 'package:flutter/foundation.dart';

/// One live instantiation of a profile's practice session.
///
/// A selected profile does not identify the owner of asynchronous work.
/// Reopening the same profile produces a new generation, so a continuation
/// that resolved the owner again after an await would act on whatever session
/// is current by then rather than on the one it began under.
@immutable
class PracticeSessionIdentity {
  /// Whose sitting this is.
  final String profileId;

  /// Which instantiation of it, unique for the life of the process.
  ///
  /// Counted globally rather than per notifier, because a notifier that is
  /// replaced starts its own count at the same place the last one did, and two
  /// sessions sharing a generation is the confusion this exists to prevent.
  final int generation;

  const PracticeSessionIdentity({
    required this.profileId,
    required this.generation,
  });

  /// The identity of a session opening now for [profileId].
  factory PracticeSessionIdentity.next(String profileId) =>
      PracticeSessionIdentity(profileId: profileId, generation: ++_opened);

  static int _opened = 0;

  @override
  bool operator ==(Object other) =>
      other is PracticeSessionIdentity &&
      other.profileId == profileId &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(profileId, generation);

  @override
  String toString() => '$profileId#$generation';
}

/// One attempt, and the session that issued it.
///
/// Carried from the presentation to whatever closes it, so completion names
/// its target instead of finding one.
@immutable
class PracticeAttemptOwner {
  /// The session that decided this attempt.
  final PracticeSessionIdentity session;

  /// The attempt, as history will record it.
  final String attemptId;

  const PracticeAttemptOwner({required this.session, required this.attemptId});

  @override
  bool operator ==(Object other) =>
      other is PracticeAttemptOwner &&
      other.session == session &&
      other.attemptId == attemptId;

  @override
  int get hashCode => Object.hash(session, attemptId);

  @override
  String toString() => '$session/$attemptId';
}
