import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

import 'shape_frontier.dart';

/// What ordinary attempt history tells a decision that learner state cannot.
///
/// One value rather than separate facts, so a caller that keeps a history
/// hands over all of it: a fact left out does not fail, it silently switches
/// off every rule that reads it.
@immutable
class AttemptHistory {
  /// Exact ordinary exercises that produced informative execution evidence.
  ///
  /// Exact, because acquisition asks whether the declared floor itself was
  /// attempted, and introduction order asks whether a material and hand has
  /// been asked for ascending before it is asked for up and down. A
  /// near-enough exercise answers neither.
  final Set<Exercise> attemptedExercises;

  /// Each material a hand has produced from memory, as material and hand.
  final Set<(String, Hand)> retrievedMaterialHands;

  /// How many informative execution observations each context has had.
  final Map<ExecutionContext, int> executionEvidenceRevisions;

  /// The shapes each material has been played through cleanly in, from
  /// memory.
  final Map<String, Set<RealizationShape>> demonstratedShapes;

  const AttemptHistory({
    this.attemptedExercises = const {},
    this.retrievedMaterialHands = const {},
    this.executionEvidenceRevisions = const {},
    this.demonstratedShapes = const {},
  });

  /// A history in which nothing has happened yet.
  static const AttemptHistory empty = AttemptHistory();
}
