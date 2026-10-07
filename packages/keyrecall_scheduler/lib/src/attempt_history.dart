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
  /// Exact ordinary exercises the learner began.
  ///
  /// What introduction order reads: whether a material and hand has been asked
  /// for ascending before it is asked for up and down. Whether that attempt
  /// could be timed is a different question, so a traversal too short to time
  /// still counts as having been asked for.
  final Set<Exercise> startedExercises;

  /// Exact ordinary exercises that produced informative execution evidence.
  ///
  /// What acquisition reads: whether the declared floor itself was tried and
  /// demonstrated nothing.
  final Set<Exercise> executionEvidenceExercises;

  /// Each material a hand has produced from memory, as material and hand.
  final Set<(String, Hand)> retrievedMaterialHands;

  /// How many informative execution observations each context has had.
  final Map<ExecutionContext, int> executionEvidenceRevisions;

  /// The shapes each material has been played through cleanly in, from
  /// memory.
  final Map<String, Set<RealizationShape>> demonstratedShapes;

  /// Where each family last met a material for the first time, as that
  /// attempt's position in the history.
  ///
  /// A family that has introduced nothing is absent.
  final Map<String, int> lastIntroductionByFamily;

  const AttemptHistory({
    this.startedExercises = const {},
    this.executionEvidenceExercises = const {},
    this.retrievedMaterialHands = const {},
    this.executionEvidenceRevisions = const {},
    this.demonstratedShapes = const {},
    this.lastIntroductionByFamily = const {},
  });

  /// A history in which nothing has happened yet.
  static const AttemptHistory empty = AttemptHistory();
}
