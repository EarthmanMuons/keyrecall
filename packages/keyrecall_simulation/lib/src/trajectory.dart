import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

/// Candidate counts at the scheduler stages relevant to selection.
class CandidateStageCounts {
  final int generated;
  final int evaluated;
  final int eligible;
  final int admitted;
  final int selectable;

  const CandidateStageCounts({
    required this.generated,
    required this.evaluated,
    required this.eligible,
    required this.admitted,
    required this.selectable,
  });
}

/// Hands-together material ids observed at each scheduler stage.
class HandsTogetherStages {
  final Set<String> prerequisiteSatisfied;
  final Set<String> eligible;
  final Set<String> admitted;
  final Set<String> selectable;
  final Map<String, HandsTogetherDiagnostic> diagnostics;

  const HandsTogetherStages({
    required this.prerequisiteSatisfied,
    required this.eligible,
    required this.admitted,
    required this.selectable,
    this.diagnostics = const {},
  });

  Set<String> get fullyEligibleSelectable => eligible.intersection(selectable);
}

class HandsTogetherDiagnostic {
  final int evaluated;
  final int fullyEligible;
  final int withinChallengeBand;
  final int admitted;
  final int selectable;
  final int coordinationTransitions;
  final int advancing;
  final int fullyEligibleAdvancing;
  final bool hasFactualRetrieval;
  final double minimumOverallP;
  final double maximumOverallP;
  final Set<String> eligibilityCodes;
  final Set<String> bypasses;

  const HandsTogetherDiagnostic({
    required this.evaluated,
    required this.fullyEligible,
    required this.withinChallengeBand,
    required this.admitted,
    required this.selectable,
    required this.coordinationTransitions,
    required this.advancing,
    required this.fullyEligibleAdvancing,
    required this.hasFactualRetrieval,
    required this.minimumOverallP,
    required this.maximumOverallP,
    required this.eligibilityCodes,
    required this.bypasses,
  });
}

/// A decision slot that produced no selection.
class TerminalTrajectorySlot {
  final int index;
  final DateTime at;
  final List<CandidateTrace> traces;
  final List<CandidateTrace> selectable;
  final CandidateStageCounts candidates;

  const TerminalTrajectorySlot({
    required this.index,
    required this.at,
    required this.traces,
    required this.selectable,
    required this.candidates,
  });
}

/// One slot of a simulated sitting, with the state detectors need.
class TrajectorySlot {
  /// Which slot of the sitting this is, from zero.
  final int index;

  /// When it was decided.
  final DateTime at;

  /// What the learner was asked for.
  final Exercise chosen;

  /// The trace for [chosen].
  final CandidateTrace winner;

  /// Everything else the slot could have offered, best first.
  final List<CandidateTrace> alternatives;

  /// The tempo the player actually played at.
  final double performedTempoBpm;

  /// What the learner did.
  final Outcome outcome;

  /// The frontier for the chosen material and hand, before the attempt.
  final Map<int, double> frontierBefore;

  /// The frontier for the chosen material and hand, after the attempt.
  final Map<int, double> frontierAfter;

  /// The paced tempo for the chosen material and hand, before the attempt.
  final double pacedBefore;

  /// The tempo this hand had shown at this span on material it already owns,
  /// before the attempt, or zero when it had shown none.
  ///
  /// What an unseen scale can legitimately be met at, recorded at decision
  /// time because it is the input a later detector has to compare the chosen
  /// tempo against.
  final double transferableBefore;

  final CandidateStageCounts candidates;
  final HandsTogetherStages handsTogether;

  const TrajectorySlot({
    required this.index,
    required this.at,
    required this.chosen,
    required this.winner,
    required this.alternatives,
    required this.performedTempoBpm,
    required this.outcome,
    required this.frontierBefore,
    required this.frontierAfter,
    required this.pacedBefore,
    required this.transferableBefore,
    required this.candidates,
    required this.handsTogether,
  });

  /// Where the chosen realization sat against the frontier.
  RealizationRank get realization => winner.rankKey!.realization;

  /// The demonstrated tempo at the span that was played, or zero.
  double get frontierAtSpan => frontierBefore[chosen.conditions.octaves] ?? 0;

  bool get frontierAdvanced => frontierAfter.entries.any(
    (entry) => entry.value > (frontierBefore[entry.key] ?? 0),
  );
}

/// How severely a detector's finding should be read.
enum AnomalySeverity {
  /// A property that should hold for any healthy scheduler, stated without
  /// reference to a tuned number.
  ///
  /// A trip here is a defect. These are the only findings safe to assert on,
  /// because a threshold nobody has calibrated becomes a second specification
  /// as arbitrary as the thing it is checking.
  invariant('INVARIANT'),

  /// A count or proportion that looks wrong against a threshold picked by
  /// judgment rather than evidence.
  ///
  /// Reported and counted, never asserted. Twelve below-frontier slots in
  /// fifty is suspicious; nobody yet knows whether the right bound is two or
  /// fifteen, and encoding a guess would freeze today's behavior as the
  /// definition of healthy practice.
  observation('OBSERVATION');

  const AnomalySeverity(this.id);

  /// Stable identifier used in reports.
  final String id;
}

/// Something a detector found in a trajectory.
class Anomaly {
  /// Which detector found it.
  final String detector;

  /// How to read it.
  final AnomalySeverity severity;

  /// The slot it is anchored to, or null for a whole-run finding.
  final int? slot;

  /// One line saying what happened.
  final String summary;

  /// Detector-specific magnitude used to order worked cases.
  final double magnitude;

  /// Material or hand the finding follows, when it has one.
  final String? subject;

  /// The census, when a slot anchors it.
  final String? census;

  const Anomaly({
    required this.detector,
    required this.severity,
    required this.summary,
    this.magnitude = 0,
    this.subject,
    this.slot,
    this.census,
  });

  @override
  String toString() =>
      '[${severity.id}] $detector${slot == null ? '' : ' at slot $slot'}: '
      '$summary';
}

/// A whole simulated sitting.
class Trajectory {
  /// Which archetype played it.
  final String playerId;

  /// Which seed produced it.
  final int seed;

  /// The slots, in order.
  final List<TrajectorySlot> slots;
  final TerminalTrajectorySlot? terminal;

  const Trajectory({
    required this.playerId,
    required this.seed,
    required this.slots,
    this.terminal,
  });
}
