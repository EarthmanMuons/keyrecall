import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'candidate_trace.dart';
import 'config/scheduler_config.dart';

/// Where one hand configuration stands in a sitting's timing remediation.
enum PulseRemediationStage {
  /// Reading clean attempts for unsteady timing.
  observing,

  /// Unsteady, and owed one attempt with a pulse.
  supportDue,

  /// Supported, and owed one attempt with the pulse taken away.
  withdrawalDue,

  /// Done for the sitting, whatever the withdrawal showed.
  ///
  /// One cycle a hand a sitting, so remediation is an intervention inside
  /// practice rather than a drill that takes the sitting over.
  closed,
}

/// One hand configuration's timing remediation for the sitting.
///
/// Scheduling state rather than learner state: it says what this sitting has
/// seen and owes, and nothing about how steady the learner is.
class PulseRemediation {
  PulseRemediationStage stage = PulseRemediationStage.observing;

  /// Temporal stability of the most recent clean attempts, oldest first.
  final List<double> steadiness = [];

  /// The exercise the cycle supplies a pulse for and then withdraws it from.
  Exercise? target;

  /// Whether a supported or withdrawn attempt is owed.
  bool get isDue =>
      stage == PulseRemediationStage.supportDue ||
      stage == PulseRemediationStage.withdrawalDue;

  /// The bypass an owed attempt is admitted under, or null when none is owed.
  ChallengeBypass? get bypass => switch (stage) {
    PulseRemediationStage.supportDue => ChallengeBypass.pulseSupport,
    PulseRemediationStage.withdrawalDue => ChallengeBypass.pulseWithdrawal,
    _ => null,
  };
}

/// Every hand configuration's remediation for one sitting.
class PulseRemediations {
  final Map<HandConfiguration, PulseRemediation> _byHands = {};

  /// Where [hands] stands.
  PulseRemediation of(HandConfiguration hands) =>
      _byHands.putIfAbsent(hands, PulseRemediation.new);

  /// The cycle owed an attempt, or null.
  ///
  /// At most one: a hand qualifies only while none is owed, and an owed cycle
  /// claims the slots until it moves on.
  PulseRemediation? get due {
    for (final remediation in _byHands.values) {
      if (remediation.isDue) return remediation;
    }
    return null;
  }

  /// Records that [exercise] was presented and ended in [outcome].
  ///
  /// [recovering] says the slot was a recovery, whose attempt followed a
  /// failure and says nothing clean about timing. An owed cycle waits out a
  /// recovery, since recovery comes first, and any other slot that passed it
  /// by closes it: the question lapses rather than lingering.
  ///
  /// An owed attempt with nothing measured moves on as well. Retrying it
  /// would make a sitting whose attempts cannot be measured nothing but
  /// retries.
  void record(
    Exercise exercise,
    Outcome? outcome, {
    required bool recovering,
    required PulseRemediationConfig config,
  }) {
    final owed = due;
    if (owed != null) {
      if (exercise == owed.target) {
        owed.stage = owed.stage == PulseRemediationStage.supportDue
            ? PulseRemediationStage.withdrawalDue
            : PulseRemediationStage.closed;
      } else if (!recovering) {
        owed.stage = PulseRemediationStage.closed;
      }
      return;
    }

    final remediation = of(exercise.conditions.hands);
    if (recovering ||
        remediation.stage != PulseRemediationStage.observing ||
        outcome == null ||
        !_isClean(outcome, config)) {
      return;
    }
    remediation.steadiness.add(outcome.temporalStability!);
    while (remediation.steadiness.length > config.observations) {
      remediation.steadiness.removeAt(0);
    }
    if (remediation.steadiness.length == config.observations &&
        remediation.steadiness.every(
          (steadiness) => steadiness < config.unsteadyStability,
        )) {
      remediation
        ..stage = PulseRemediationStage.supportDue
        ..target = exercise;
    }
  }

  /// Whether [outcome] is timing evidence about the pulse alone.
  ///
  /// Held and played through, the notes right, and the playing unbroken, so
  /// that unsteadiness left over is drift rather than not knowing the scale or
  /// not being able to play it.
  static bool _isClean(Outcome outcome, PulseRemediationConfig config) =>
      outcome.pulseMaintenance.isTested &&
      outcome.started &&
      outcome.completed &&
      outcome.retrieval != FactualRetrieval.failed &&
      outcome.pitchIntegrity >= config.minimumPitchIntegrity &&
      (outcome.continuity ?? -1) >= config.minimumContinuity &&
      outcome.temporalStability != null;
}
