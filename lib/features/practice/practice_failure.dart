import 'package:flutter/foundation.dart';

/// What a practice failure leaves standing, which is what says how to recover.
enum PracticeFailure {
  /// The sitting could not be opened or replayed.
  ///
  /// The usual cause is a journal recorded under a learner model this build no
  /// longer runs, which no retry can change. This is the only failure erasing
  /// answers, and it names the profile whose history it read.
  history,

  /// Which profile is active could not be read.
  ///
  /// Rewritable convenience rather than identity: everybody is still here, and
  /// the repair rewrites the selection and destroys nothing.
  selection,

  /// A profile's own record of itself could not be read.
  ///
  /// Nothing here can be rebuilt, and nothing here is safe to throw away: the
  /// creation instant anchors placement, so a rewritten genesis reinterprets
  /// the history rather than repairing it.
  roster,

  /// A deletion this install began could not be read.
  ///
  /// The marker is what authorizes destroying a history, so one that does not
  /// validate is refused rather than obeyed. Nothing automatic can repair it:
  /// finishing the deletion and cancelling it are both decisions, and the file
  /// that would say which is the one nobody can read.
  ///
  /// What this guarantees is that nothing further is removed. How far the
  /// deletion had already got before the marker became unreadable is exactly
  /// what cannot be established from here, so nothing says it got nowhere.
  deletion,

  /// A sitting failed to open for a reason nothing classified.
  ///
  /// Deliberately not [history]. An unclassified failure says nothing about
  /// what is on disk, and offering to erase a history nobody established was
  /// unreadable answers a question nobody asked.
  opening,

  /// A closed attempt did not reach authoritative history.
  ///
  /// The transaction is frozen on the session that prepared it, so retrying
  /// writes that same attempt. Reopening would recover the pending decision
  /// and abandon the performance the learner already supplied.
  commit,

  /// The next exercise could not be decided.
  ///
  /// Everything recorded is durable and the session never gave up the state it
  /// decides from, so asking again is the whole of the recovery.
  scheduling,
}

/// A practice failure, classified by what is still valid behind it.
@immutable
class PracticeLoopFailure implements Exception {
  /// Which kind of failure this is.
  final PracticeFailure kind;

  /// What actually went wrong.
  final Object cause;

  /// Whose artifact failed, where the failure identified somebody.
  ///
  /// What a destructive recovery targets. A recovery that inferred its target
  /// from whatever the app happened to be holding would erase an intact
  /// history to repair a file somewhere else.
  final String? profileId;

  const PracticeLoopFailure(this.kind, this.cause, {this.profileId});

  @override
  String toString() => '$cause';
}
