import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

import 'attempt_closure.dart';
import 'attempt_journal.dart';
import 'attempt_record.dart';
import 'checkpoint.dart';
import 'schema.dart';

/// How faithfully a replay must reproduce what was recorded.
enum ReplayMode {
  /// Reproduce the original history exactly.
  ///
  /// The model version must match what each attempt recorded, and every
  /// recomputed prediction, weight, and state hash must agree with the journal
  /// within [ReplayOptions.tolerance]. Any disagreement is reported: this mode
  /// exists to prove the past is still reachable.
  exact,

  /// Re-run the same observed attempts under a different estimator.
  ///
  /// Used to compare model versions or parameter sets. Recorded predictions
  /// and weights are recomputed and deliberately not compared, because they are
  /// expected to differ.
  ///
  /// The counterfactual boundary matters: an alternative estimator may be
  /// applied only to the exercise that was actually presented. The journal
  /// holds no outcome for an action that was never taken, so this says nothing
  /// about what a different scheduler would have achieved.
  counterfactual,
}

/// One place a replay disagreed with the journal.
@immutable
class ReplayDivergence {
  /// Which attempt disagreed.
  final String attemptId;

  /// What disagreed, such as `execution_p` or `state_after_hash`.
  final String field;

  /// What the journal recorded.
  final Object? recorded;

  /// What the replay produced.
  final Object? replayed;

  const ReplayDivergence({
    required this.attemptId,
    required this.field,
    required this.recorded,
    required this.replayed,
  });

  @override
  String toString() =>
      'attempt $attemptId: $field recorded $recorded, replayed $replayed';
}

/// How a replay should run.
@immutable
class ReplayOptions {
  /// Whether to reproduce history or re-estimate it.
  final ReplayMode mode;

  /// How far a recomputed number may drift before it counts as divergence.
  ///
  /// Not zero, because the model is floating-point and a rebuild may sum in a
  /// different order. Tight enough that a real behavioral change cannot hide
  /// under it.
  final double tolerance;

  /// Whether the first divergence should throw rather than be collected.
  ///
  /// Collecting is the better default for diagnosis: one root cause usually
  /// shows up as many divergences, and the shape of them is the evidence.
  final bool stopOnDivergence;

  const ReplayOptions({
    this.mode = ReplayMode.exact,
    this.tolerance = 1e-9,
    this.stopOnDivergence = false,
  });
}

/// What a replay produced.
@immutable
class ReplayResult {
  /// The state the replayed attempts add up to.
  final LearnerState state;

  /// Everywhere the replay disagreed with the journal, in order.
  final List<ReplayDivergence> divergences;

  /// How many attempts were applied.
  final int attemptsApplied;

  /// How many attempts carried no measurement and so moved nothing.
  ///
  /// Counted rather than skipped silently: an attempt that measured nothing
  /// still happened, and a replay that saw one should be able to say so.
  final int attemptsUnmeasured;

  const ReplayResult({
    required this.state,
    required this.divergences,
    required this.attemptsApplied,
    this.attemptsUnmeasured = 0,
  });

  /// Whether the replay reproduced the journal exactly.
  bool get isFaithful => divergences.isEmpty;

  /// The hash of the state this replay produced.
  String get stateHash => learnerStateHash(state);

  @override
  String toString() =>
      'ReplayResult($attemptsApplied attempts, '
      '$attemptsUnmeasured unmeasured, '
      '${divergences.length} divergences)';
}

/// Rebuilds learner state by replaying [journal] onto [initial].
///
/// This is what makes the journal authoritative: state is not something the app
/// keeps and hopes is right, it is a function of recorded history. A checkpoint
/// is only a place to start from, and passing one is an optimization rather
/// than a source of truth.
///
/// In [ReplayMode.exact] the replay recomputes each attempt's prediction and
/// evidence weights from the state it rebuilt, then compares them to what was
/// recorded. Recomputing and comparing is the point: simply reapplying the
/// stored numbers would reproduce any past mistake perfectly and prove nothing.
///
/// Throws [JournalFormatException] when an attempt was recorded under a
/// different learner model version than [model] carries and the mode is
/// [ReplayMode.exact]. A missing or mismatched model version fails loudly
/// rather than being reinterpreted under today's constants.
///
/// ## Canonical state advances only on a committed attempt
///
/// Replay propagates from one recorded attempt to the next, so the writer must
/// do the same. Time propagation is mathematically path-independent, but it is
/// not path-independent in floating point: advancing through three intervals
/// and advancing through their sum land on different bits, and a state hash is
/// exact.
///
/// So a decision that admits nothing, a candidate preview, or any other
/// look-ahead must run against a copy. Propagating canonical state at a moment
/// the journal does not record makes that state unreachable by replay, which
/// costs the journal its authority. The rule is narrow and mechanical: exactly
/// one canonical propagation per recorded attempt, at that attempt's time.
ReplayResult replayJournal(
  AttemptJournal journal, {
  required LearnerModel model,
  required LearnerState initial,
  ReplayOptions options = const ReplayOptions(),
  LearnerStateCheckpoint? from,
}) {
  final state = _seedState(
    initial: initial,
    from: from,
    model: model,
    mode: options.mode,
    profileId: journal.header.profileId,
  );
  final divergences = <ReplayDivergence>[];
  var applied = 0;
  var unmeasured = 0;

  for (final record in journal.records) {
    // Skip by position in the history, not by position within a sitting. A
    // journal spans many sessions, and a checkpoint already contains all of
    // them up to its sequence.
    if (from != null && record.journalSequence <= from.throughJournalSequence) {
      if (record.journalSequence == from.throughJournalSequence &&
          record.identity.attemptId != from.throughAttemptId) {
        throw JournalFormatException(
          'checkpoint claims to cover attempt ${from.throughAttemptId} at '
          'sequence ${from.throughJournalSequence}, but this journal has '
          '${record.identity.attemptId} there',
        );
      }
      continue;
    }

    if (options.mode == ReplayMode.exact &&
        record.provenance.learnerModelVersion != model.params.modelVersion) {
      throw JournalFormatException(
        'attempt was recorded under learner model '
        '"${record.provenance.learnerModelVersion}" but replay is running '
        '"${model.params.modelVersion}"; use ReplayMode.counterfactual to '
        're-estimate deliberately',
        location: 'attempt ${record.identity.attemptId}',
      );
    }

    // An attempt that measured nothing moves no learner state. Not even time:
    // propagation is driven by the next record that needs it, so a closure
    // carrying no evidence leaves competencies exactly as they were.
    if (record.closure.measurement case MeasurementUnavailable()) {
      unmeasured++;
      continue;
    }
    final measured = record.closure.measurement as Measured;

    final at = record.identity.occurredAt;
    model.propagate(state, at);

    if (options.mode == ReplayMode.exact && record.stateBeforeHash != null) {
      _compareHash(
        record.identity.attemptId,
        'state_before_hash',
        record.stateBeforeHash!,
        learnerStateHash(state),
        divergences,
        options,
      );
    }

    final prediction = model.predict(state, record.exercise, at: at);
    final weights = evidenceWeightsFor(record.exercise, measured.outcome);

    if (options.mode == ReplayMode.exact) {
      _comparePrediction(record, prediction, divergences, options);
      _compareWeights(
        measured,
        record.identity.attemptId,
        weights,
        divergences,
        options,
      );
    }

    final diagnostics = model.applyOutcome(
      state: state,
      exercise: record.exercise,
      outcome: measured.outcome,
      weights: weights,
      prediction: prediction,
      at: at,
    );
    applied++;

    if (options.mode == ReplayMode.exact) {
      _compareNumber(
        record.identity.attemptId,
        'consolidation_delta_from_retrieval_inference',
        measured.memoryUpdate.consolidationDeltaFromRetrievalInference,
        diagnostics.consolidationDeltaFromRetrievalInference,
        divergences,
        options,
      );
      _compareNumber(
        record.identity.attemptId,
        'consolidation_delta_from_causal_formation',
        measured.memoryUpdate.consolidationDeltaFromCausalFormation,
        diagnostics.consolidationDeltaFromCausalFormation,
        divergences,
        options,
      );
      if (record.stateAfterHash != null) {
        _compareHash(
          record.identity.attemptId,
          'state_after_hash',
          record.stateAfterHash!,
          learnerStateHash(state),
          divergences,
          options,
        );
      }
    }
  }

  return ReplayResult(
    state: state,
    divergences: divergences,
    attemptsApplied: applied,
    attemptsUnmeasured: unmeasured,
  );
}

LearnerState _seedState({
  required LearnerState initial,
  required LearnerStateCheckpoint? from,
  required LearnerModel model,
  required ReplayMode mode,
  required String profileId,
}) {
  if (from == null) return initial.copy();
  if (from.profileId != profileId) {
    throw JournalFormatException(
      'checkpoint belongs to profile ${from.profileId}, but this journal '
      'holds $profileId',
    );
  }
  if (mode == ReplayMode.exact &&
      !from.isUsableUnder(model.params.modelVersion)) {
    throw JournalFormatException(
      'checkpoint was taken under learner model '
      '"${from.learnerModelVersion}" but replay is running '
      '"${model.params.modelVersion}"; replay from the journal instead',
    );
  }
  return from.state.copy();
}

void _comparePrediction(
  AttemptRecord record,
  Prediction replayed,
  List<ReplayDivergence> divergences,
  ReplayOptions options,
) {
  final recorded = record.decision?.prediction;
  if (recorded == null) return;

  final id = record.identity.attemptId;
  _compareNumber(
    id,
    'independent_retrieval_p',
    recorded.independentRetrievalP,
    replayed.independentRetrievalP,
    divergences,
    options,
  );
  _compareNumber(
    id,
    'material_available_p',
    recorded.materialAvailableP,
    replayed.materialAvailableP,
    divergences,
    options,
  );
  _compareNumber(
    id,
    'execution_p',
    recorded.executionP,
    replayed.executionP,
    divergences,
    options,
  );
  _compareNumber(
    id,
    'topology_p',
    recorded.topologyP,
    replayed.topologyP,
    divergences,
    options,
  );
}

void _compareWeights(
  Measured measured,
  String id,
  EvidenceWeights replayed,
  List<ReplayDivergence> divergences,
  ReplayOptions options,
) {
  final record = measured;
  _compareNumber(
    id,
    'weight.material_execution',
    record.weights.materialExecution,
    replayed.materialExecution,
    divergences,
    options,
  );
  _compareNumber(
    id,
    'weight.material_memory',
    record.weights.materialMemory,
    replayed.materialMemory,
    divergences,
    options,
  );

  final competencies = {
    ...record.weights.competencies.keys,
    ...replayed.competencies.keys,
  };
  for (final competency in competencies) {
    _compareNumber(
      id,
      'weight.${competency.id}',
      record.weights[competency],
      replayed[competency],
      divergences,
      options,
    );
  }
}

void _compareNumber(
  String attemptId,
  String field,
  double recorded,
  double replayed,
  List<ReplayDivergence> divergences,
  ReplayOptions options,
) {
  if ((recorded - replayed).abs() <= options.tolerance) return;
  _record(
    ReplayDivergence(
      attemptId: attemptId,
      field: field,
      recorded: recorded,
      replayed: replayed,
    ),
    divergences,
    options,
  );
}

void _compareHash(
  String attemptId,
  String field,
  String recorded,
  String replayed,
  List<ReplayDivergence> divergences,
  ReplayOptions options,
) {
  if (recorded == replayed) return;
  _record(
    ReplayDivergence(
      attemptId: attemptId,
      field: field,
      recorded: recorded,
      replayed: replayed,
    ),
    divergences,
    options,
  );
}

void _record(
  ReplayDivergence divergence,
  List<ReplayDivergence> divergences,
  ReplayOptions options,
) {
  divergences.add(divergence);
  if (options.stopOnDivergence) {
    throw JournalFormatException(
      'replay diverged from the journal: $divergence',
      location: 'attempt ${divergence.attemptId}',
    );
  }
}
