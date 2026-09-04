import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

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
abstract interface class SchedulerHost {
  Future<SchedulerVerdict> decide({
    required int epoch,
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
    PracticeEntryPolicy? practiceEntryPolicy,
  });
}

/// Decides in the calling isolate.
///
/// What a test, a simulation, and any caller that has not opted into a worker
/// use. It leaves the sitting alone like any other host, so both paths reach a
/// post-decision sitting the same way.
class InProcessScheduler implements SchedulerHost {
  final SchedulerPipeline pipeline;

  const InProcessScheduler(this.pipeline);

  @override
  Future<SchedulerVerdict> decide({
    required int epoch,
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
    PracticeEntryPolicy? practiceEntryPolicy,
  }) async {
    final slot = pipeline.evaluateSlot(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      acquisitionFloor: acquisitionFloor,
      practiceEntryPolicy: practiceEntryPolicy,
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
