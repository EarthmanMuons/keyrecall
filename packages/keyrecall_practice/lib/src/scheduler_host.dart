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

/// What deciding a slot owes the sitting.
///
/// The scheduler records two things against a sitting as part of deciding, and
/// a host that decides elsewhere has to bring them back, because the sitting it
/// decided against was a copy. Applying this to the sitting a session owns
/// leaves it exactly as an in-process decision would have.
@immutable
class SittingDecisionEffect {
  final bool guidanceProbeAvailable;
  final bool guidanceProbeSelected;

  const SittingDecisionEffect({
    required this.guidanceProbeAvailable,
    required this.guidanceProbeSelected,
  });

  void applyTo(SessionState session) {
    session.recordSelectionOpportunity(
      guidanceProbeAvailable: guidanceProbeAvailable,
      guidanceProbeSelected: guidanceProbeSelected,
    );
    session.attemptsThisSession++;
  }
}

/// One slot's decision, reduced to what a session acts on.
///
/// A [SelectionResult] holds a trace per candidate and a slot evaluates ten
/// thousand, so the whole of it cannot cross an isolate boundary at a price
/// worth paying. What a session does with it is narrower: the winning
/// candidate or a reason there was none, plus the one set-level fact the
/// sitting records.
@immutable
class SchedulerVerdict {
  /// Which version of the session's scheduler inputs this answers.
  ///
  /// Echoed rather than interpreted: what makes a verdict stale is a question
  /// only the session that asked can answer.
  final int epoch;

  /// The candidate to present, or null where the slot is blocked.
  final CandidateTrace? chosen;

  /// Why nothing was chosen, present exactly when [chosen] is null.
  final BlockedReason? blockedReason;

  /// What to apply to the sitting if this verdict is still current.
  final SittingDecisionEffect effect;

  /// Every trace, where the decision was made in this isolate.
  ///
  /// Diagnostics read it and nothing in the product does, so a host that
  /// decides elsewhere leaves it null rather than sending it back.
  final SelectionResult? result;

  const SchedulerVerdict.selected(
    CandidateTrace this.chosen, {
    required this.epoch,
    required this.effect,
    this.result,
  }) : blockedReason = null;

  const SchedulerVerdict.blocked(
    BlockedReason this.blockedReason, {
    required this.epoch,
    required this.effect,
    this.result,
  }) : chosen = null;
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
  Future<SchedulerVerdict> decide({
    required int epoch,
    required LearnerState state,
    required SessionState session,
    required List<String> dueRequirementIds,
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
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
  }) async {
    final slot = pipeline.evaluateSlot(
      state: state,
      session: session,
      candidates: candidatesDueIn(_scope!, dueRequirementIds),
      at: at,
      acquisitionFloor: acquisitionFloor,
      practiceEntryPolicy: _entry,
    );
    final effect = SittingDecisionEffect(
      guidanceProbeAvailable: slot.guidanceProbeAvailable,
      guidanceProbeSelected: slot.guidanceProbeSelected,
    );
    return switch (slot.result) {
      CandidateSelected(:final candidate) => SchedulerVerdict.selected(
        candidate,
        epoch: epoch,
        effect: effect,
        result: slot.result,
      ),
      SelectionBlocked(:final reason) => SchedulerVerdict.blocked(
        reason,
        epoch: epoch,
        effect: effect,
        result: slot.result,
      ),
    };
  }
}
