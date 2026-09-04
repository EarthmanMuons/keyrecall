import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

/// One slot's decision, reduced to what a session acts on.
///
/// A [SelectionResult] holds a trace per candidate and a slot evaluates ten
/// thousand, so the whole of it cannot cross an isolate boundary at a price
/// worth paying. What a session does with it is narrower: the winning
/// candidate or a reason there was none, plus the one set-level fact the
/// sitting records.
@immutable
class SchedulerVerdict {
  /// The candidate to present, or null where the slot is blocked.
  final CandidateTrace? chosen;

  /// Why nothing was chosen, present exactly when [chosen] is null.
  final BlockedReason? blockedReason;

  /// Whether a guidance probe was among the candidates the slot could pick.
  final bool guidanceProbeAvailable;

  /// Every trace, where the decision was made in this isolate.
  ///
  /// Diagnostics read it and nothing in the product does, so a host that
  /// decides elsewhere leaves it null rather than sending it back.
  final SelectionResult? result;

  const SchedulerVerdict.selected(
    CandidateTrace this.chosen, {
    required this.guidanceProbeAvailable,
    this.result,
  }) : blockedReason = null;

  const SchedulerVerdict.blocked(
    BlockedReason this.blockedReason, {
    required this.guidanceProbeAvailable,
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
/// A host is responsible for leaving [session] as though the decision had been
/// taken in it, whichever isolate did the work.
abstract interface class SchedulerHost {
  Future<SchedulerVerdict> decide({
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
/// use. The pipeline records the slot against [session] itself here, so there
/// is nothing left to apply.
class InProcessScheduler implements SchedulerHost {
  final SchedulerPipeline pipeline;

  const InProcessScheduler(this.pipeline);

  @override
  Future<SchedulerVerdict> decide({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
    PracticeEntryPolicy? practiceEntryPolicy,
  }) async {
    final result = pipeline.decide(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      acquisitionFloor: acquisitionFloor,
      practiceEntryPolicy: practiceEntryPolicy,
    );
    final guidanceProbeAvailable = result.selectable.any(
      (trace) => trace.challengeBypass == ChallengeBypass.guidanceProbe,
    );
    return switch (result) {
      CandidateSelected(:final candidate) => SchedulerVerdict.selected(
        candidate,
        guidanceProbeAvailable: guidanceProbeAvailable,
        result: result,
      ),
      SelectionBlocked(:final reason) => SchedulerVerdict.blocked(
        reason,
        guidanceProbeAvailable: guidanceProbeAvailable,
        result: result,
      ),
    };
  }
}
