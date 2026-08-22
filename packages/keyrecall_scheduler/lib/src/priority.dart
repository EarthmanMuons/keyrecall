import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'session_state.dart';

/// How capable this candidate is of generating genuine retrieval evidence.
///
/// The retrieval demand when retrieval is observed at all, and exactly zero
/// under continuous cueing, matching the memory evidence weight the learner
/// model really applies. Shared by [retention] and [information] so both read
/// one guidance-derived notion of evidence capacity.
double retrievalOpportunity(Exercise exercise) =>
    exercise.guidance.isRetrievalObserved
    ? exercise.guidance.retrievalDemand
    : 0.0;

/// `1 - M`: how urgent it is to test this material before it is forgotten.
///
/// A property of the material's memory state alone, independent of which
/// candidate is asking.
double retentionNeed(Prediction prediction) =>
    1.0 - prediction.independentRetrievalP;

/// `R(e)`: retention need scaled by whether this candidate can act on it.
///
/// Without the scaling, a continuously cued candidate inherits the deficit but
/// can never resolve it: retrieval is correctly never tested, the memory clock
/// never re-anchors, and the need rises without bound, entrenching the one
/// candidate guaranteed to leave it exactly as unresolved as before. Weighting
/// by [retrievalOpportunity] denies that candidate the win without resetting
/// the clock, which would manufacture evidence the model never observed.
double retention(Prediction prediction, Exercise exercise) =>
    retentionNeed(prediction) * retrievalOpportunity(exercise);

/// `I(e)`: how much uncertainty this candidate's evidence opportunities
/// expose.
///
/// Candidate-specific expected uncertainty reduction, not a bare lookup of
/// current uncertainty: the weights reuse the same guidance-derived quantities
/// the real evidence weights use. Read-only, so computing it never creates a
/// memory or execution entry and is never itself evidence.
///
/// Deliberately blind to competency *means*. Weighting each term by predicted
/// capability was tried and reverted: it re-derived the difficulty structure
/// challenge admission already consumes, breaking the boundary that priority
/// ranking must not re-consume challenge difficulty.
double information(
  LearnerState state,
  Exercise exercise,
  LearnerParams params,
) {
  final q = exercise.structuralQ;
  final motorQ = motorLoadings(q);
  final topologyQ = topologyLoadings(q);
  final retrievalDemand = exercise.guidance.retrievalDemand;

  var competencyTerm = 0.0;
  for (final competency in Competency.values) {
    final variance = state.competency(competency).variance;
    final loading =
        (competency.isTopology ? topologyQ[competency] : motorQ[competency]) ??
        0.0;
    final weight = competency.isTopology ? retrievalDemand : 1.0;
    competencyTerm += variance * loading * weight;
  }

  final materialId = exercise.material.materialId;
  final memoryTerm =
      _memoryUncertainty(state, materialId, params) *
      retrievalOpportunity(exercise);

  final residual =
      state.materialExecution[(materialId, exercise.conditions.hands)];
  final executionTerm =
      residual?.residualVariance ?? params.materialExecution.priorVariance;

  return competencyTerm + memoryTerm + executionTerm;
}

/// Whichever memory uncertainty is currently the operative one.
double _memoryUncertainty(
  LearnerState state,
  String materialId,
  LearnerParams params,
) {
  final memory = state.materialMemory[materialId];
  if (memory == null) return params.materialMemory.priorUncertainty;
  return memory.isAnchored
      ? memory.currentHalfLifeUncertainty
      : memory.coldStartUncertainty;
}

/// `V(e)`: a simple recency count over the diversity window, negated so
/// higher is better like the other terms.
double diversity(Exercise exercise, SessionState session) =>
    -session.recentAttemptsOf(exercise.material.materialId).toDouble();

/// `G(e)`: learner-goal relevance.
///
/// Explicitly stubbed at zero rather than faked: no goal data model exists
/// yet, and a guessed value would silently reorder candidates.
double goals(Exercise exercise) => 0.0;
