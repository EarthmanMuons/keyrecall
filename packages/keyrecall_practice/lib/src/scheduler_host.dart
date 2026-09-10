import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

/// The candidates [dueRequirementIds] name, against [scope].
///
/// The requirement ids travel instead of the exercises: a slot's envelope is
/// ten thousand of them, and a host that already holds the scope can rebuild
/// the subset from a list of strings.
List<Exercise> candidatesDueIn(
  ResolvedPracticeScope scope,
  List<String> dueRequirementIds,
) {
  final due = dueRequirementIds.toSet();
  return distinctCandidatesOf([
    for (final requirement in scope.requirements)
      if (due.contains(requirement.requirement.id)) requirement,
  ]);
}

/// The emphasis [scope] puts on each of its materials.
///
/// Requirements are what a focus weights and candidates are generated per
/// material, so two requirements over one material contribute the stronger of
/// their weights rather than each other's.
GoalEmphasis goalEmphasisOf(ResolvedPracticeScope scope) {
  final weights = <String, double>{};
  for (final requirement in scope.requirements) {
    if (requirement.emphasis == GoalEmphasis.unemphasized) continue;
    final materialId = requirement.material.materialId;
    final held = weights[materialId];
    if (held == null || requirement.emphasis > held) {
      weights[materialId] = requirement.emphasis;
    }
  }
  return weights.isEmpty ? GoalEmphasis.none : GoalEmphasis(weights);
}

/// The scheduler's final-result effect carried by a practice host.
typedef SittingDecisionEffect = SelectionEffect;

/// One slot's decision, reduced to what a session acts on.
///
/// A [SelectionResult] holds a trace per candidate and a slot evaluates ten
/// thousand, so the whole of it cannot cross an isolate boundary at a price
/// worth paying. What a session does with it is narrower: the winning
/// candidate or a reason there was none, a compact competition report, and the
/// selection bookkeeping the sitting records.
@immutable
class SchedulerVerdict {
  final String diagnostics;

  /// Which version of the session's scheduler inputs this answers.
  ///
  /// Echoed rather than interpreted: what makes a verdict stale is a question
  /// only the session that asked can answer.
  final int epoch;

  /// The candidate to present, or null where the slot chose no ordinary work.
  final CandidateTrace? chosen;

  /// Why no ordinary work was chosen, present exactly when the slot was
  /// blocked.
  final BlockedReason? blockedReason;

  /// The supported task to present instead of ordinary work, or null.
  ///
  /// A slot answers with exactly one of these three. An acquisition task is
  /// not a candidate and never becomes one, so it travels beside [chosen]
  /// rather than through it, and a host that does not understand it cannot
  /// mistake it for ordinary work.
  final AcquisitionTask? acquisitionTask;

  /// The ordinary work an offered task was chosen instead of, if any.
  final Exercise? displacedByAcquisition;

  /// What to apply to the sitting if this verdict is still current.
  final SittingDecisionEffect effect;

  /// Every trace, where the decision was made in this isolate.
  ///
  /// Diagnostics read it and nothing in the product does, so a host that
  /// decides elsewhere leaves it null rather than sending it back.
  final SelectionResult? result;

  const SchedulerVerdict.selected(
    CandidateTrace this.chosen, {
    this.diagnostics = '',
    required this.epoch,
    required this.effect,
    this.result,
  }) : blockedReason = null,
       acquisitionTask = null,
       displacedByAcquisition = null;

  const SchedulerVerdict.blocked(
    BlockedReason this.blockedReason, {
    this.diagnostics = '',
    required this.epoch,
    required this.effect,
    this.result,
  }) : chosen = null,
       acquisitionTask = null,
       displacedByAcquisition = null;

  const SchedulerVerdict.acquisition(
    AcquisitionTask this.acquisitionTask, {
    this.diagnostics = '',
    required this.epoch,
    required this.effect,
    this.result,
    this.displacedByAcquisition,
  }) : chosen = null,
       blockedReason = null;
}

/// Where a scheduling decision is computed.
///
/// The seam exists because the decision is the expensive part of a slot and
/// nothing else about a slot is: on a mid-range phone a mature full-catalog
/// decision blocks its isolate for a fifth of a second, and computing it
/// elsewhere costs nothing but the state that has to travel.
///
/// A host never touches the sitting it is given. What deciding owes the
/// sitting comes back as a [SittingDecisionEffect], which the session applies
/// once it has established that the answer is still current.
/// A host holds the resolved scope it decides against for as long as that
/// scope is the sitting's, so the candidate envelope is established once
/// rather than travelling with every request. Binding again replaces it.
abstract interface class SchedulerHost {
  /// Adopts [scope], discarding whatever was bound before.
  ///
  /// The learner and the policy constants travel with it rather than being a
  /// host's own default, because a host deciding with different ones would
  /// decide differently for reasons nothing in a trace would show.
  Future<void> bind({
    required ResolvedPracticeScope scope,
    required PracticeEntryPolicy entry,
    required LearnerModel learner,
    required SchedulerConfig config,
  });

  /// The decision for the slot at [at], answering [epoch].
  ///
  /// [dueRequirementIds] names the requirements whose candidates the slot may
  /// choose between, against the bound scope.
  ///
  /// [acquisition] and [attemptedExercises] are rebuilt from persisted
  /// history by the caller, because a host holds no history of its own. Omit
  /// them and the slot decides exactly as it did before acquisition existed.
  Future<SchedulerVerdict> decide({
    required int epoch,
    required LearnerState state,
    required SessionState session,
    required List<String> dueRequirementIds,
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    Set<Exercise>? attemptedExercises,
    Map<ExecutionContext, int> executionEvidenceRevisions = const {},
  });

  /// Releases whatever computes decisions. A host is disposable: a session
  /// that loses one binds another and asks again from the state it owns.
  Future<void> dispose();
}

/// Decides in the calling isolate.
///
/// What a test, a simulation, and any caller that has not opted into a worker
/// use. It leaves the sitting alone like any other host, so both paths reach a
/// post-decision sitting the same way.
class InProcessScheduler implements SchedulerHost {
  final SchedulerPipeline pipeline;

  ResolvedPracticeScope? _scope;
  PracticeEntryPolicy? _entry;
  GoalEmphasis _emphasis = GoalEmphasis.none;

  InProcessScheduler(this.pipeline);

  /// The learner and config are the pipeline's already: a session builds this
  /// host from the pipeline it uses, so the two cannot differ.
  @override
  Future<void> bind({
    required ResolvedPracticeScope scope,
    required PracticeEntryPolicy entry,
    required LearnerModel learner,
    required SchedulerConfig config,
  }) async {
    _scope = scope;
    _entry = entry;
    _emphasis = goalEmphasisOf(scope);
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<SchedulerVerdict> decide({
    required int epoch,
    required LearnerState state,
    required SessionState session,
    required List<String> dueRequirementIds,
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    Set<Exercise>? attemptedExercises,
    Map<ExecutionContext, int> executionEvidenceRevisions = const {},
  }) async {
    final slot = pipeline.evaluateSlot(
      state: state,
      session: session,
      candidates: candidatesDueIn(_scope!, dueRequirementIds),
      at: at,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: acquisitionFamilyFloor,
      acquisition: acquisition,
      attemptedExercises: attemptedExercises,
      executionEvidenceRevisions: executionEvidenceRevisions,
      practiceEntryPolicy: _entry,
      emphasis: _emphasis,
    );
    final effect = SelectionEffect.of(slot.result);
    return switch (slot.result) {
      CandidateSelected(:final candidate) => SchedulerVerdict.selected(
        candidate,
        epoch: epoch,
        effect: effect,
        result: slot.result,
        diagnostics: slot.result.diagnostics,
      ),
      SelectionBlocked(:final reason) => SchedulerVerdict.blocked(
        reason,
        epoch: epoch,
        effect: effect,
        result: slot.result,
        diagnostics: slot.result.diagnostics,
      ),
      AcquisitionOffered(:final task, :final displaced) =>
        SchedulerVerdict.acquisition(
          task,
          epoch: epoch,
          effect: effect,
          result: slot.result,
          diagnostics: slot.result.diagnostics,
          displacedByAcquisition: displaced,
        ),
    };
  }
}
