import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'attempt_trace.dart';
import 'practice_simulation.dart';

/// Thrown when a decision opportunity admitted no candidate at all.
///
/// Never papered over with a fallback exercise: training the learner model on
/// something the scheduler explicitly did not choose would contaminate every
/// later attempt. A run that is not specifically testing this condition should
/// let it surface.
class NoAdmittedCandidate implements Exception {
  /// What the scheduler was asked, in human-readable form.
  final String message;

  const NoAdmittedCandidate(this.message);

  @override
  String toString() => 'NoAdmittedCandidate: $message';
}

/// What one decision opportunity produced.
///
/// An attempt slot always yields a record; a selection exists only when the
/// decision produced something to present. Keeping the two distinct is what
/// makes no-admission visible in diagnostics instead of silently absent.
class AttemptRecord {
  /// Position of this decision in the run, counting from zero.
  final int attemptIndex;

  /// When the decision was made.
  final DateTime at;

  /// What was chosen, or null when nothing was admitted.
  final CandidateTrace? selected;

  /// The next best candidates, so a "why that one?" question stays answerable
  /// without retaining every trace from every attempt.
  final List<CandidateTrace> runnersUp;

  /// Material ids of everything admitted, when the run asked for it.
  final Set<String>? admittedMaterialIds;

  /// What happened when the selection was played, once it is known.
  ///
  /// Recorded separately from the selection because recovery turns on whether
  /// retrieval was tested and failed, which a serialized summary would blur.
  Outcome? outcome;

  AttemptRecord({
    required this.attemptIndex,
    required this.at,
    required this.selected,
    this.runnersUp = const [],
    this.admittedMaterialIds,
  });
}

/// Drives the real scheduler pipeline inside a practice simulation.
///
/// Owns session state across a run and logs what was selected against what
/// nearly was. Plugging this in as the simulation's chooser is what turns a
/// learner-model run into a scheduler run: no second update loop is involved.
class SchedulerAgent {
  /// The pipeline making the decisions.
  final SchedulerPipeline pipeline;

  /// The candidate set, generated once for the run.
  final List<Exercise> candidates;

  /// How many runners-up to keep per decision.
  final int runnersUpCount;

  /// Whether to record the full admitted material set per decision.
  final bool captureAdmittedMaterialIds;

  /// Every decision this agent has made.
  final List<AttemptRecord> records = [];

  SessionState _session = SessionState();

  SchedulerAgent({
    required this.pipeline,
    required InstrumentProfile instrument,
    required List<TechnicalMaterial> materials,
    this.runnersUpCount = 5,
    this.captureAdmittedMaterialIds = false,
  }) : candidates = generateCandidates(instrument, materials);

  /// The current practice sitting.
  SessionState get session => _session;

  /// Every selection this agent has made, in order.
  Iterable<CandidateTrace> get selections =>
      records.map((record) => record.selected).nonNulls;

  /// Starts a fresh practice sitting.
  ///
  /// Session state resets while the learner, the hidden truth, and simulated
  /// time carry on. A long behavioral horizon is several bounded sessions, not
  /// one run past the safety cap.
  void startNewSession() => _session = SessionState();

  /// Chooses what to present next. Plug this into a simulation as its chooser.
  ///
  /// Throws [NoAdmittedCandidate] when the decision admits nothing.
  Exercise choose(AttemptContext context) {
    final selection = pipeline.decide(
      state: context.state,
      session: _session,
      candidates: candidates,
      at: context.at,
    );
    final winner = switch (selection) {
      CandidateSelected(:final candidate) => candidate,
      SelectionBlocked() => null,
    };

    final contenders =
        selection.selectable
            .where((trace) => trace.isRanked && !identical(trace, winner))
            .toList()
          ..sort((a, b) => b.rankKey!.compareTo(a.rankKey!));

    records.add(
      AttemptRecord(
        attemptIndex: context.attemptIndex,
        at: context.at,
        selected: winner,
        runnersUp: contenders.take(runnersUpCount).toList(),
        admittedMaterialIds: captureAdmittedMaterialIds
            ? {
                for (final trace in selection.selectable)
                  if (trace.isRanked) trace.exercise.material.materialId,
              }
            : null,
      ),
    );
    if (winner == null) {
      throw NoAdmittedCandidate(
        'no candidate reached priority ranking at attempt '
        '${context.attemptIndex} (at ${context.at.toIso8601String()}, '
        'session attempts ${_session.attemptsThisSession})',
      );
    }
    return winner.exercise;
  }

  /// Records what happened. Plug this into a simulation as its outcome
  /// observer.
  void observe(Exercise exercise, Outcome outcome, DateTime at) {
    records.last.outcome = outcome;
    pipeline.recordOutcome(_session, exercise, outcome);
  }
}

/// Runs several scheduler-driven sessions back to back over one simulation.
///
/// Session state resets at each boundary while the learner, the hidden truth,
/// and simulated time carry over unbroken. Returns every attempt trace in
/// order.
List<AttemptTrace> runSessions(
  PracticeSimulation simulation,
  SchedulerAgent agent, {
  required int sessionCount,
  required int attemptsPerSession,
}) {
  final traces = <AttemptTrace>[];
  for (var session = 0; session < sessionCount; session++) {
    if (session > 0) agent.startNewSession();
    traces.addAll(
      simulation.run(
        attemptsPerSession,
        chooser: agent.choose,
        onOutcome: agent.observe,
      ),
    );
  }
  return traces;
}
