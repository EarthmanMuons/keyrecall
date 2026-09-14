import 'package:flutter/foundation.dart';

/// What a practice failure leaves standing, which is what says how to recover.
enum PracticeFailure {
  /// The sitting could not be opened or replayed.
  ///
  /// The usual cause is a journal recorded under a learner model this build no
  /// longer runs, which no retry can change. This is the only failure erasing
  /// answers.
  history,

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

  const PracticeLoopFailure(this.kind, this.cause);

  @override
  String toString() => '$cause';
}
